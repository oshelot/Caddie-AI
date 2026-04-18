"""
CaddieAI LLM Proxy — FastAPI on AWS Lambda (via Lambda Web Adapter)

Stateless proxy that forwards OpenAI-compatible chat completion requests
to Amazon Bedrock (Nova Micro) using IAM authentication.
Authenticates clients via x-api-key header.

Supports two modes:
  - Buffered (default): Returns the full JSON response after Bedrock completes.
  - Streaming (stream: true): Forwards SSE chunks from Bedrock as they arrive,
    using FastAPI StreamingResponse through Lambda Function URL RESPONSE_STREAM.
"""

import json
import os
import time
from typing import AsyncGenerator

import boto3
import uvicorn
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, StreamingResponse

from shadow_eval import (
    run_shadow_evaluation_buffered,
    run_shadow_evaluation_streaming_sync,
)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

BEDROCK_MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "us.amazon.nova-micro-v1:0")
PROXY_API_KEY_ENV = os.environ.get("PROXY_API_KEY", "")
BEDROCK_REGION = os.environ.get("BEDROCK_REGION", os.environ.get("AWS_REGION", "us-east-2"))

# Cached Bedrock client (persists across warm invocations)
_bedrock_client = None
_proxy_api_key: str | None = None

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["POST", "OPTIONS"],
    allow_headers=["Content-Type", "x-api-key"],
)

# ---------------------------------------------------------------------------
# Bedrock client
# ---------------------------------------------------------------------------

def get_bedrock_client():
    """Get or create the Bedrock Runtime client, cached across warm invocations."""
    global _bedrock_client
    if _bedrock_client is None:
        _bedrock_client = boto3.client(
            "bedrock-runtime",
            region_name=BEDROCK_REGION,
        )
    return _bedrock_client


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


def _convert_messages_to_bedrock(body: dict) -> tuple[list[dict], list[dict]]:
    """
    Convert OpenAI-format messages to Bedrock Converse format.

    Returns (system_messages, conversation_messages).
    Bedrock separates system messages from the conversation.
    """
    system_msgs = []
    converse_msgs = []

    for msg in body["messages"]:
        role = msg.get("role", "user")
        content = msg.get("content", "")

        if role == "system":
            system_msgs.append({"text": content if isinstance(content, str) else str(content)})
        else:
            # Map OpenAI roles to Bedrock roles
            bedrock_role = "assistant" if role == "assistant" else "user"

            # Handle content that may be a list (multimodal) or string
            if isinstance(content, list):
                # OpenAI multimodal format: [{"type": "text", "text": "..."}, {"type": "image_url", ...}]
                bedrock_content = []
                for part in content:
                    if part.get("type") == "text":
                        bedrock_content.append({"text": part["text"]})
                    # Skip image_url parts — Nova Micro is text-only
                converse_msgs.append({"role": bedrock_role, "content": bedrock_content})
            else:
                converse_msgs.append({
                    "role": bedrock_role,
                    "content": [{"text": content if isinstance(content, str) else str(content)}],
                })

    return system_msgs, converse_msgs


# ---------------------------------------------------------------------------
# Streaming handler (Bedrock ConverseStream)
# ---------------------------------------------------------------------------

def _run_post_stream_shadows(
    body: dict,
    accumulated_text: str,
    usage_data: dict | None,
    stream_start: float,
) -> None:
    """Run shadow evaluation after streaming completes (sync, no more yields)."""
    primary_latency_ms = int((time.perf_counter() - stream_start) * 1000)
    run_shadow_evaluation_streaming_sync(
        body=body,
        primary_response_text=accumulated_text,
        primary_usage=usage_data or {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
        primary_latency_ms=primary_latency_ms,
        primary_model_id=BEDROCK_MODEL_ID,
    )


async def _stream_bedrock(body: dict) -> AsyncGenerator[str, None]:
    """
    Generator that streams SSE events from Bedrock to the client.

    Yields `data: {"content": "..."}` for each text chunk,
    `data: {"usage": {...}}` for token counts, and `data: [DONE]` to finish.
    After [DONE], runs shadow model evaluation if sampled.
    """
    accumulated_text = ""
    usage_data = None
    stream_start = time.perf_counter()

    try:
        system_msgs, converse_msgs = _convert_messages_to_bedrock(body)
    except Exception as e:
        yield f"data: {json.dumps({'error': f'Message conversion error: {str(e)}'})}\n\n"
        yield "data: [DONE]\n\n"
        return

    try:
        client = get_bedrock_client()
        kwargs = {
            "modelId": BEDROCK_MODEL_ID,
            "messages": converse_msgs,
            "inferenceConfig": {
                "maxTokens": body.get("max_tokens", 500),
                "temperature": body.get("temperature", 0.7),
            },
        }
        if system_msgs:
            kwargs["system"] = system_msgs

        response = client.converse_stream(**kwargs)
    except Exception as e:
        yield f"data: {json.dumps({'error': f'Bedrock error: {str(e)}'})}\n\n"
        yield "data: [DONE]\n\n"
        return

    try:
        for event in response.get("stream", []):
            if "contentBlockDelta" in event:
                delta = event["contentBlockDelta"].get("delta", {})
                text = delta.get("text", "")
                if text:
                    accumulated_text += text
                    yield f"data: {json.dumps({'content': text})}\n\n"

            elif "metadata" in event:
                usage = event["metadata"].get("usage", {})
                if usage:
                    usage_data = {
                        "prompt_tokens": usage.get("inputTokens", 0),
                        "completion_tokens": usage.get("outputTokens", 0),
                        "total_tokens": usage.get("inputTokens", 0) + usage.get("outputTokens", 0),
                    }
    except Exception as e:
        yield f"data: {json.dumps({'error': f'Stream error: {str(e)}'})}\n\n"
        yield "data: [DONE]\n\n"
        _run_post_stream_shadows(body, accumulated_text, usage_data, stream_start)
        return

    # Emit usage as a separate event so clients can track token counts
    if usage_data:
        yield f"data: {json.dumps({'usage': usage_data})}\n\n"

    yield "data: [DONE]\n\n"

    # Shadow evaluation runs here after [DONE] — generator keeps Lambda alive
    _run_post_stream_shadows(body, accumulated_text, usage_data, stream_start)


# ---------------------------------------------------------------------------
# Buffered handler (Bedrock Converse)
# ---------------------------------------------------------------------------

async def _handle_buffered(body: dict) -> JSONResponse:
    """Call Bedrock without streaming and return the full response.

    If shadow evaluation is enabled and this request is sampled,
    shadow models run after the primary call completes.
    """
    try:
        system_msgs, converse_msgs = _convert_messages_to_bedrock(body)
    except Exception as e:
        return JSONResponse(
            status_code=400,
            content={"error": f"Message conversion error: {str(e)}"},
        )

    start_ms = time.perf_counter()

    try:
        client = get_bedrock_client()
        kwargs = {
            "modelId": BEDROCK_MODEL_ID,
            "messages": converse_msgs,
            "inferenceConfig": {
                "maxTokens": body.get("max_tokens", 1500),
                "temperature": body.get("temperature", 0.7),
            },
        }
        if system_msgs:
            kwargs["system"] = system_msgs

        response = client.converse(**kwargs)
    except client.exceptions.ThrottlingException:
        return JSONResponse(
            status_code=429,
            content={"error": "Rate limit exceeded at Bedrock. Please try again shortly."},
        )
    except Exception as e:
        return JSONResponse(
            status_code=502,
            content={"error": f"Bedrock error: {str(e)}"},
        )

    primary_latency_ms = int((time.perf_counter() - start_ms) * 1000)

    try:
        # Extract content from Bedrock response
        output = response.get("output", {})
        content_blocks = output.get("message", {}).get("content", [])
        content = ""
        for block in content_blocks:
            if "text" in block:
                content += block["text"]

        # Extract usage
        usage = response.get("usage", {})
        prompt_tokens = usage.get("inputTokens", 0)
        completion_tokens = usage.get("outputTokens", 0)

        result = {
            "choices": [{"message": {"role": "assistant", "content": content}}],
            "usage": {
                "prompt_tokens": prompt_tokens,
                "completion_tokens": completion_tokens,
                "total_tokens": prompt_tokens + completion_tokens,
            },
        }
    except (KeyError, IndexError, TypeError) as e:
        return JSONResponse(
            status_code=502,
            content={"error": f"Unexpected response format from Bedrock: {str(e)}"},
        )

    # Shadow evaluation — runs concurrently, awaited before response returns
    await run_shadow_evaluation_buffered(
        body=body,
        primary_response_text=content,
        primary_usage=result["usage"],
        primary_latency_ms=primary_latency_ms,
        primary_model_id=BEDROCK_MODEL_ID,
    )

    return JSONResponse(status_code=200, content=result)


# ---------------------------------------------------------------------------
# Route
# ---------------------------------------------------------------------------

@app.post("/")
@app.post("/chat/completions")
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
            _stream_bedrock(body),
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

# ---------------------------------------------------------------------------
# Joke endpoint (KAN-195 / KAN-186)
# ---------------------------------------------------------------------------

_JOKE_SYSTEM_PROMPT = (
    "You are a golf comedy writer. Generate ONE short, funny golf joke or "
    "one-liner (1-3 sentences max). Make it context-aware when details are "
    "provided (course name, location, weather, player handicap). Keep it "
    "clean, witty, and relatable to golfers. Do NOT add quotation marks, "
    "attribution, or commentary — just the joke itself."
)


@app.post("/joke")
async def get_joke(request: Request):
    """Generate a context-aware golf joke for the loading screen."""
    auth_error = _authenticate(request)
    if auth_error:
        return JSONResponse(status_code=401, content={"error": auth_error})

    try:
        body = await request.json()
    except Exception:
        body = {}

    # Build a context-rich user prompt from optional fields.
    context_parts = []
    if body.get("courseName"):
        context_parts.append(f"Course: {body['courseName']}")
    if body.get("state"):
        context_parts.append(f"Location: {body['state']}")
    if body.get("weatherSummary"):
        context_parts.append(f"Weather: {body['weatherSummary']}")
    if body.get("handicap"):
        context_parts.append(f"Player handicap: {body['handicap']}")
    if body.get("elevation"):
        context_parts.append(f"Elevation: {body['elevation']} ft")

    user_msg = "Tell me a golf joke."
    if context_parts:
        user_msg += " Context: " + ", ".join(context_parts) + "."

    try:
        client = get_bedrock_client()
        response = client.converse(
            modelId=BEDROCK_MODEL_ID,
            messages=[{"role": "user", "content": [{"text": user_msg}]}],
            system=[{"text": _JOKE_SYSTEM_PROMPT}],
            inferenceConfig={
                "maxTokens": 150,
                "temperature": 0.9,  # higher temp for creativity
            },
        )

        content_blocks = response.get("output", {}).get("message", {}).get("content", [])
        joke = ""
        for block in content_blocks:
            if "text" in block:
                joke += block["text"]

        return JSONResponse(content={"joke": joke.strip()})

    except Exception as e:
        print(f"Joke generation failed: {e}")
        return JSONResponse(
            status_code=502,
            content={"error": "Joke generation failed", "joke": ""},
        )


@app.get("/health")
async def health():
    return {"status": "ok"}


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
