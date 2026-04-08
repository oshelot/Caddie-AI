"""
CaddieAI LLM Proxy Lambda

Stateless proxy that forwards OpenAI-compatible chat completion requests
to OpenAI's API using a server-side key stored in AWS Secrets Manager.
Forces gpt-4o-mini for all requests. Authenticates clients via x-api-key header.

Supports two modes:
  - Buffered (default): Returns the full JSON response after OpenAI completes.
  - Streaming (stream: true): Forwards SSE chunks from OpenAI as they arrive.
    Requires Lambda Function URL with InvokeMode: RESPONSE_STREAM.
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
REQUEST_TIMEOUT = 55  # seconds


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


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

def error_response(status_code: int, message: str) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps({"error": message}),
    }


def _authenticate(event: dict) -> str | None:
    """Returns an error message string if auth fails, None if OK."""
    headers = event.get("headers") or {}
    client_key = headers.get("x-api-key") or headers.get("X-Api-Key") or ""
    expected_key = get_proxy_api_key()
    if not expected_key or client_key != expected_key:
        return "Unauthorized: invalid or missing API key."
    return None


def _parse_body(event: dict) -> dict | str:
    """Returns parsed body dict, or error string."""
    body_str = event.get("body", "")
    if event.get("isBase64Encoded"):
        import base64
        body_str = base64.b64decode(body_str).decode("utf-8")
    try:
        return json.loads(body_str) if body_str else {}
    except json.JSONDecodeError:
        return "Invalid JSON in request body."


def _build_openai_payload(body: dict, stream: bool = False) -> dict:
    """Build the payload forwarded to OpenAI."""
    payload = {
        "model": FORCED_MODEL,
        "messages": body["messages"],
        "max_tokens": body.get("max_tokens", 500),
        "temperature": body.get("temperature", 0.7),
    }
    if stream:
        payload["stream"] = True
        payload["stream_options"] = {"include_usage": True}
    if "response_format" in body:
        payload["response_format"] = body["response_format"]
    return payload


# ---------------------------------------------------------------------------
# Buffered (non-streaming) handler — original behavior
# ---------------------------------------------------------------------------

def _handle_buffered(body: dict) -> dict:
    """Call OpenAI without streaming and return the full response."""
    openai_payload = _build_openai_payload(body, stream=False)

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

    try:
        choice = openai_response["choices"][0]["message"]["content"]
        usage = openai_response.get("usage", {})
        result = {
            "choices": [{"message": {"role": "assistant", "content": choice}}],
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


# ---------------------------------------------------------------------------
# Streaming handler — forwards SSE from OpenAI
# ---------------------------------------------------------------------------

def _stream_generator(body: dict):
    """
    Generator that yields SSE lines from OpenAI.

    Each yielded string is a complete SSE event (including "data: " prefix
    and trailing newlines) ready to be written to the response stream.

    The final event is a custom `data: {"usage": {...}}` so the client can
    record token counts, followed by `data: [DONE]`.
    """
    openai_payload = _build_openai_payload(body, stream=True)

    try:
        openai_key = get_openai_key()
    except Exception as e:
        yield f"data: {json.dumps({'error': str(e)})}\n\n"
        yield "data: [DONE]\n\n"
        return

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
        resp = urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT)
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8") if e.fp else ""
        try:
            error_json = json.loads(error_body)
            msg = error_json.get("error", {}).get("message", f"OpenAI error: HTTP {e.code}")
        except (json.JSONDecodeError, AttributeError):
            msg = f"OpenAI error: HTTP {e.code}"
        yield f"data: {json.dumps({'error': msg})}\n\n"
        yield "data: [DONE]\n\n"
        return
    except (urllib.error.URLError, TimeoutError) as e:
        yield f"data: {json.dumps({'error': str(e)})}\n\n"
        yield "data: [DONE]\n\n"
        return

    # Read the SSE stream line-by-line from OpenAI and forward to client
    usage_data = None
    try:
        for raw_line in resp:
            line = raw_line.decode("utf-8").strip()
            if not line:
                continue
            if not line.startswith("data: "):
                continue

            payload = line[6:]  # strip "data: " prefix

            if payload == "[DONE]":
                break

            try:
                chunk = json.loads(payload)
            except json.JSONDecodeError:
                continue

            # Extract content delta
            choices = chunk.get("choices", [])
            if choices:
                delta = choices[0].get("delta", {})
                content = delta.get("content")
                if content:
                    # Forward just the text content as an SSE event
                    yield f"data: {json.dumps({'content': content})}\n\n"

            # Capture usage from the final chunk (stream_options.include_usage)
            if "usage" in chunk and chunk["usage"]:
                usage_data = chunk["usage"]

    except Exception as e:
        yield f"data: {json.dumps({'error': f'Stream read error: {str(e)}'})}\n\n"
    finally:
        resp.close()

    # Emit usage as a separate event so clients can track token counts
    if usage_data:
        yield f"data: {json.dumps({'usage': usage_data})}\n\n"

    yield "data: [DONE]\n\n"


def _handle_streaming(body: dict) -> dict:
    """
    Build a response that streams SSE events.

    For Lambda Function URL with RESPONSE_STREAM invoke mode, returning
    a body that is a generator/iterator will cause the runtime to stream
    each chunk to the client.

    For environments that don't support streaming (e.g. testing via API
    Gateway), this collects all chunks and returns them as a single
    text/event-stream body.
    """
    # Collect the full SSE body — the Function URL streaming runtime
    # will handle actual chunked transfer. For non-streaming runtimes
    # (API Gateway fallback), this still works — just not incrementally.
    chunks = list(_stream_generator(body))
    full_body = "".join(chunks)

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "text/event-stream",
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "Access-Control-Allow-Origin": "*",
        },
        "body": full_body,
    }


# ---------------------------------------------------------------------------
# Main handler
# ---------------------------------------------------------------------------

def lambda_handler(event, context):
    # Handle CORS preflight
    http_method = (
        event.get("httpMethod")
        or event.get("requestContext", {}).get("http", {}).get("method", "")
    )
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
    auth_error = _authenticate(event)
    if auth_error:
        return error_response(401, auth_error)

    # Parse body
    body = _parse_body(event)
    if isinstance(body, str):
        return error_response(400, body)

    # Validate
    messages = body.get("messages")
    if not messages or not isinstance(messages, list):
        return error_response(400, "Missing or invalid 'messages' field.")

    # Route to streaming or buffered handler
    if body.get("stream", False):
        return _handle_streaming(body)
    else:
        return _handle_buffered(body)
