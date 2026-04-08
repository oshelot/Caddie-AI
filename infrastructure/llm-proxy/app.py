"""
CaddieAI LLM Proxy — FastAPI on AWS Lambda (via Lambda Web Adapter)

Stateless proxy that forwards OpenAI-compatible chat completion requests
to OpenAI's API using a server-side key stored in AWS Secrets Manager.
Forces gpt-4o-mini for all requests. Authenticates clients via x-api-key header.

Supports two modes:
  - Buffered (default): Returns the full JSON response after OpenAI completes.
  - Streaming (stream: true): Forwards SSE chunks from OpenAI as they arrive,
    using FastAPI StreamingResponse through Lambda Function URL RESPONSE_STREAM.
"""

import json
import os
from typing import AsyncGenerator

import boto3
import httpx
import uvicorn
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, StreamingResponse

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

OPENAI_API_URL = "https://api.openai.com/v1/chat/completions"
FORCED_MODEL = "gpt-4o-mini"
SECRET_ID = os.environ.get("SECRET_ID", "caddieai/openai-api-key")
PROXY_API_KEY_ENV = os.environ.get("PROXY_API_KEY", "")
REQUEST_TIMEOUT = 55  # seconds

# Cached values (persist across warm invocations)
_openai_key: str | None = None
_proxy_api_key: str | None = None

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["POST", "OPTIONS"],
    allow_headers=["Content-Type", "x-api-key"],
)

# ---------------------------------------------------------------------------
# Key retrieval
# ---------------------------------------------------------------------------

def get_openai_key() -> str:
    """Retrieve OpenAI API key from Secrets Manager, cached after first call."""
    global _openai_key
    if _openai_key:
        return _openai_key

    client = boto3.client(
        "secretsmanager",
        region_name=os.environ.get("AWS_REGION", "us-east-2"),
    )
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
# Helpers
# ---------------------------------------------------------------------------

def _authenticate(request: Request) -> str | None:
    """Returns an error message string if auth fails, None if OK."""
    client_key = request.headers.get("x-api-key", "")
    expected_key = get_proxy_api_key()
    if not expected_key or client_key != expected_key:
        return "Unauthorized: invalid or missing API key."
    return None


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
# Streaming handler
# ---------------------------------------------------------------------------

async def _stream_openai(body: dict) -> AsyncGenerator[str, None]:
    """
    Async generator that streams SSE events from OpenAI to the client.

    Yields `data: {"content": "..."}` for each text chunk,
    `data: {"usage": {...}}` for token counts, and `data: [DONE]` to finish.
    """
    openai_payload = _build_openai_payload(body, stream=True)

    try:
        openai_key = get_openai_key()
    except Exception as e:
        yield f"data: {json.dumps({'error': str(e)})}\n\n"
        yield "data: [DONE]\n\n"
        return

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {openai_key}",
    }

    usage_data = None

    async with httpx.AsyncClient() as client:
        try:
            async with client.stream(
                "POST",
                OPENAI_API_URL,
                headers=headers,
                json=openai_payload,
                timeout=REQUEST_TIMEOUT,
            ) as resp:
                if resp.status_code != 200:
                    error_body = await resp.aread()
                    try:
                        error_json = json.loads(error_body)
                        msg = error_json.get("error", {}).get(
                            "message", f"OpenAI error: HTTP {resp.status_code}"
                        )
                    except (json.JSONDecodeError, AttributeError):
                        msg = f"OpenAI error: HTTP {resp.status_code}"
                    yield f"data: {json.dumps({'error': msg})}\n\n"
                    yield "data: [DONE]\n\n"
                    return

                async for raw_line in resp.aiter_lines():
                    line = raw_line.strip()
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
                            yield f"data: {json.dumps({'content': content})}\n\n"

                    # Capture usage from the final chunk
                    if "usage" in chunk and chunk["usage"]:
                        usage_data = chunk["usage"]

        except httpx.HTTPStatusError as e:
            yield f"data: {json.dumps({'error': f'OpenAI error: HTTP {e.response.status_code}'})}\n\n"
            yield "data: [DONE]\n\n"
            return
        except (httpx.ConnectError, httpx.TimeoutException) as e:
            yield f"data: {json.dumps({'error': str(e)})}\n\n"
            yield "data: [DONE]\n\n"
            return

    # Emit usage as a separate event so clients can track token counts
    if usage_data:
        yield f"data: {json.dumps({'usage': usage_data})}\n\n"

    yield "data: [DONE]\n\n"


# ---------------------------------------------------------------------------
# Buffered handler
# ---------------------------------------------------------------------------

async def _handle_buffered(body: dict) -> JSONResponse:
    """Call OpenAI without streaming and return the full response."""
    openai_payload = _build_openai_payload(body, stream=False)

    try:
        openai_key = get_openai_key()
    except Exception as e:
        return JSONResponse(
            status_code=500,
            content={"error": f"Failed to retrieve API key: {str(e)}"},
        )

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {openai_key}",
    }

    async with httpx.AsyncClient() as client:
        try:
            resp = await client.post(
                OPENAI_API_URL,
                headers=headers,
                json=openai_payload,
                timeout=REQUEST_TIMEOUT,
            )
        except httpx.TimeoutException:
            return JSONResponse(
                status_code=504, content={"error": "OpenAI request timed out."}
            )
        except httpx.ConnectError as e:
            return JSONResponse(
                status_code=504,
                content={"error": f"Failed to reach OpenAI: {str(e)}"},
            )

    if resp.status_code == 429:
        return JSONResponse(
            status_code=429,
            content={
                "error": "Rate limit exceeded at OpenAI. Please try again shortly."
            },
        )

    if resp.status_code != 200:
        try:
            error_json = resp.json()
            msg = error_json.get("error", {}).get(
                "message", f"OpenAI error: HTTP {resp.status_code}"
            )
        except (json.JSONDecodeError, AttributeError):
            msg = f"OpenAI error: HTTP {resp.status_code}"
        return JSONResponse(status_code=502, content={"error": msg})

    try:
        openai_response = resp.json()
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
        return JSONResponse(
            status_code=502,
            content={"error": "Unexpected response format from OpenAI."},
        )

    return JSONResponse(status_code=200, content=result)


# ---------------------------------------------------------------------------
# Route
# ---------------------------------------------------------------------------

@app.post("/")
async def chat_completions(request: Request):
    # Authenticate
    auth_error = _authenticate(request)
    if auth_error:
        return JSONResponse(status_code=401, content={"error": auth_error})

    # Parse body
    try:
        body = await request.json()
    except Exception:
        return JSONResponse(
            status_code=400, content={"error": "Invalid JSON in request body."}
        )

    # Validate
    messages = body.get("messages")
    if not messages or not isinstance(messages, list):
        return JSONResponse(
            status_code=400,
            content={"error": "Missing or invalid 'messages' field."},
        )

    # Route to streaming or buffered handler
    if body.get("stream", False):
        return StreamingResponse(
            _stream_openai(body),
            media_type="text/event-stream",
            headers={
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
            },
        )
    else:
        return await _handle_buffered(body)


# ---------------------------------------------------------------------------
# Health check (Lambda Web Adapter readiness probe)
# ---------------------------------------------------------------------------

@app.get("/health")
async def health():
    return {"status": "ok"}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
