"""
CaddieAI LLM Proxy Lambda

Stateless proxy that forwards OpenAI-compatible chat completion requests
to OpenAI's API using a server-side key stored in AWS Secrets Manager.
Forces gpt-4o-mini for all requests. Authenticates clients via x-api-key header.
"""

import json
import os
import urllib.request
import urllib.error

# Cached values (persist across warm invocations)
_openai_key: str | None = None
_proxy_api_key: str | None = None

OPENAI_API_URL = "https://api.openai.com/v1/chat/completions"
FORCED_MODEL = "gpt-4o-mini"
SECRET_ID = os.environ.get("SECRET_ID", "caddieai/openai-api-key")
PROXY_API_KEY_ENV = os.environ.get("PROXY_API_KEY", "")
REQUEST_TIMEOUT = 55  # seconds (under API Gateway's 60s limit)


def get_openai_key() -> str:
    """Retrieve OpenAI API key from Secrets Manager, cached after first call."""
    global _openai_key
    if _openai_key:
        return _openai_key

    import boto3
    client = boto3.client("secretsmanager", region_name=os.environ.get("AWS_REGION", "us-east-2"))
    resp = client.get_secret_value(SecretId=SECRET_ID)
    _openai_key = resp["SecretString"]
    return _openai_key


def get_proxy_api_key() -> str:
    """Get the proxy API key for client authentication."""
    global _proxy_api_key
    if _proxy_api_key:
        return _proxy_api_key
    _proxy_api_key = PROXY_API_KEY_ENV
    return _proxy_api_key


def error_response(status_code: int, message: str) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps({"error": message}),
    }


def lambda_handler(event, context):
    # Handle CORS preflight
    http_method = event.get("httpMethod") or event.get("requestContext", {}).get("http", {}).get("method", "")
    if http_method == "OPTIONS":
        return {
            "statusCode": 200,
            "headers": {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "POST, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type, x-api-key",
            },
            "body": "",
        }

    # Authenticate
    headers = event.get("headers") or {}
    # API Gateway lowercases header names
    client_key = headers.get("x-api-key") or headers.get("X-Api-Key") or ""
    expected_key = get_proxy_api_key()

    if not expected_key or client_key != expected_key:
        return error_response(401, "Unauthorized: invalid or missing API key.")

    # Parse request body
    body_str = event.get("body", "")
    if event.get("isBase64Encoded"):
        import base64
        body_str = base64.b64decode(body_str).decode("utf-8")

    try:
        body = json.loads(body_str) if body_str else {}
    except json.JSONDecodeError:
        return error_response(400, "Invalid JSON in request body.")

    # Validate required fields
    messages = body.get("messages")
    if not messages or not isinstance(messages, list):
        return error_response(400, "Missing or invalid 'messages' field.")

    # Build OpenAI request — force model, pass through allowed fields
    openai_payload = {
        "model": FORCED_MODEL,
        "messages": messages,
        "max_tokens": body.get("max_tokens", 500),
        "temperature": body.get("temperature", 0.7),
    }

    # Pass through response_format if present (for JSON mode)
    if "response_format" in body:
        openai_payload["response_format"] = body["response_format"]

    # Call OpenAI
    try:
        openai_key = get_openai_key()
    except Exception as e:
        return error_response(500, f"Failed to retrieve API key: {str(e)}")

    req_data = json.dumps(openai_payload).encode("utf-8")
    req = urllib.request.Request(
        OPENAI_API_URL,
        data=req_data,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {openai_key}",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as resp:
            resp_body = resp.read().decode("utf-8")
            openai_response = json.loads(resp_body)
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8") if e.fp else ""
        try:
            error_json = json.loads(error_body)
            msg = error_json.get("error", {}).get("message", f"OpenAI error: HTTP {e.code}")
        except (json.JSONDecodeError, AttributeError):
            msg = f"OpenAI error: HTTP {e.code}"

        if e.code == 429:
            return error_response(429, "Rate limit exceeded at OpenAI. Please try again shortly.")
        return error_response(502, msg)
    except urllib.error.URLError as e:
        return error_response(504, f"Failed to reach OpenAI: {str(e.reason)}")
    except TimeoutError:
        return error_response(504, "OpenAI request timed out.")

    # Extract and return the response
    try:
        choice = openai_response["choices"][0]["message"]["content"]
        usage = openai_response.get("usage", {})

        result = {
            "choices": [
                {
                    "message": {
                        "role": "assistant",
                        "content": choice,
                    }
                }
            ],
            "usage": {
                "prompt_tokens": usage.get("prompt_tokens", 0),
                "completion_tokens": usage.get("completion_tokens", 0),
                "total_tokens": usage.get("total_tokens", 0),
            },
        }
    except (KeyError, IndexError):
        return error_response(502, "Unexpected response format from OpenAI.")

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(result),
    }
