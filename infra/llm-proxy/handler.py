"""
CaddieAI LLM Proxy Lambda

Proxies LLM requests for paid-tier users through OpenAI's API.
Injects the server-side API key and forces model = gpt-4o-mini.

Expected payload:
{
    "messages": [
        {"role": "system", "content": "..."},
        {"role": "user", "content": "..."}
    ],
    "response_format": {"type": "json_object"},  // optional
    "max_tokens": 1500,                           // optional, default 1500
    "temperature": 0.7                            // optional, default 0.7
}

Response: proxied OpenAI response body (JSON).
"""

import json
import os
import urllib.request
import urllib.error

OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")
MODEL = "gpt-4o-mini"
OPENAI_URL = "https://api.openai.com/v1/chat/completions"
MAX_BODY_BYTES = 256 * 1024  # 256 KB


def handler(event, context):
    # --- Parse body ---
    body_str = event.get("body", "")
    if not body_str:
        return _response(400, {"error": "Empty request body"})

    if len(body_str) > MAX_BODY_BYTES:
        return _response(400, {"error": "Request body too large"})

    try:
        body = json.loads(body_str)
    except json.JSONDecodeError:
        return _response(400, {"error": "Invalid JSON"})

    # --- Validate messages ---
    messages = body.get("messages")
    if not messages or not isinstance(messages, list):
        return _response(400, {"error": "Missing or invalid messages array"})

    for i, msg in enumerate(messages):
        if not isinstance(msg, dict) or "role" not in msg:
            return _response(400, {"error": f"Message {i} is missing required 'role' field"})

    # --- Build OpenAI request ---
    openai_body = {
        "model": MODEL,
        "messages": messages,
        "temperature": body.get("temperature", 0.7),
        "max_tokens": min(body.get("max_tokens", 1500), 4096),
    }

    # Pass through response_format if provided
    if "response_format" in body:
        openai_body["response_format"] = body["response_format"]

    # --- Call OpenAI ---
    req = urllib.request.Request(
        OPENAI_URL,
        data=json.dumps(openai_body).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {OPENAI_API_KEY}",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            resp_body = resp.read().decode("utf-8")
            return _response(200, json.loads(resp_body))
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8") if e.fp else "{}"
        return _response(e.code, {"error": f"OpenAI API error", "details": error_body})
    except urllib.error.URLError as e:
        return _response(502, {"error": f"Failed to reach OpenAI: {str(e.reason)}"})
    except Exception as e:
        return _response(500, {"error": f"Internal error: {str(e)}"})


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(body),
    }
