"""
CaddieAI Remote Logging Lambda (v2)

Receives batched diagnostic log entries from iOS/Android clients and writes
them to CloudWatch Logs. Each device gets its own log stream within a shared
log group. Authenticates clients via x-api-key header.

v2 changes:
- Validate platform is "ios" or "android" (reject "unknown")
- Reject entries with empty message
- Include deviceModel, buildNumber, received_at in CloudWatch entries
- Return per-entry validation errors so clients can fix payloads
"""

import json
import os
import time

import boto3

# Cached values (persist across warm invocations)
_logs_client = None
_proxy_api_key: str | None = None

LOG_GROUP = os.environ.get("LOG_GROUP", "/caddieai/client-logs")
PROXY_API_KEY_ENV = os.environ.get("PROXY_API_KEY", "")

VALID_PLATFORMS = {"ios", "android"}
VALID_LEVELS = {"info", "warning", "error"}


def get_logs_client():
    """Get or create a cached CloudWatch Logs client."""
    global _logs_client
    if _logs_client is None:
        _logs_client = boto3.client("logs", region_name=os.environ.get("AWS_REGION", "us-east-2"))
    return _logs_client


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


def ensure_log_stream(client, log_group: str, stream_name: str):
    """Create the log stream if it doesn't exist."""
    try:
        client.create_log_stream(logGroupName=log_group, logStreamName=stream_name)
    except client.exceptions.ResourceAlreadyExistsException:
        pass


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
    headers = event.get("headers") or {}
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

    # Validate required top-level fields
    device_id = body.get("deviceId")
    platform = body.get("platform", "")
    entries = body.get("entries")
    session_id = body.get("sessionId", "")
    app_version = body.get("appVersion", "")
    os_version = body.get("osVersion", "")
    device_model = body.get("deviceModel", "")
    build_number = body.get("buildNumber", "")

    if not device_id:
        return error_response(400, "Missing 'deviceId' field.")
    if platform not in VALID_PLATFORMS:
        return error_response(
            400,
            f"Invalid 'platform': '{platform}'. Must be one of: {', '.join(sorted(VALID_PLATFORMS))}.",
        )
    if not entries or not isinstance(entries, list):
        return error_response(400, "Missing or invalid 'entries' field.")

    # Limit batch size to prevent abuse
    if len(entries) > 200:
        entries = entries[:200]

    # Build log stream name: platform/deviceId (e.g., ios/ABC123)
    stream_name = f"{platform}/{device_id}"

    client = get_logs_client()
    ensure_log_stream(client, LOG_GROUP, stream_name)

    # Server-side receive timestamp for clock-skew detection
    received_at = int(time.time() * 1000)

    # Convert entries to CloudWatch log events, skipping invalid ones
    log_events = []
    skipped = 0
    for entry in entries:
        message = entry.get("message", "")
        if not message or not message.strip():
            skipped += 1
            continue

        level = entry.get("level", "info")
        if level not in VALID_LEVELS:
            level = "info"

        timestamp_ms = entry.get("timestampMs")
        if not timestamp_ms:
            timestamp_ms = received_at

        log_message = json.dumps({
            "level": level,
            "category": entry.get("category", "general"),
            "message": message,
            "sessionId": session_id,
            "appVersion": app_version,
            "osVersion": os_version,
            "deviceModel": device_model,
            "buildNumber": build_number,
            "receivedAt": received_at,
            "metadata": entry.get("metadata", {}),
        })

        log_events.append({
            "timestamp": int(timestamp_ms),
            "message": log_message,
        })

    if not log_events:
        detail = ""
        if skipped > 0:
            detail = f" {skipped} entries skipped due to empty 'message' field."
        return error_response(400, f"No valid log entries to write.{detail}")

    # CloudWatch requires events sorted by timestamp
    log_events.sort(key=lambda e: e["timestamp"])

    # Write to CloudWatch Logs
    try:
        client.put_log_events(
            logGroupName=LOG_GROUP,
            logStreamName=stream_name,
            logEvents=log_events,
        )
    except Exception as e:
        return error_response(500, f"Failed to write logs: {str(e)}")

    response_body = {"accepted": len(log_events)}
    if skipped > 0:
        response_body["skipped"] = skipped
        response_body["skippedReason"] = "empty message field"

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(response_body),
    }
