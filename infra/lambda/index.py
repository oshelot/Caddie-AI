"""
CaddieAI Telemetry Ingestion Lambda

Accepts POST /events with a JSON body containing telemetry events,
validates the payload, and writes it to S3 partitioned by date.

Expected payload:
{
    "deviceId": "UUID",
    "events": [
        {
            "type": "llm_call" | "golf_api_call" | "weather_call" | "mapbox_call" | "course_played",
            "timestamp": "ISO-8601",
            "provider": "openAI" | "claude" | "gemini",  // for llm_call
            "model": "gpt-4o",                            // for llm_call
            "method": "getRecommendation",
            "promptTokens": 500,                           // for llm_call
            "completionTokens": 200,                       // for llm_call
            "totalTokens": 700,                            // for llm_call
            "courseName": "Pebble Beach Golf Links"        // for course_played
        }
    ]
}
"""

import json
import os
import uuid
from datetime import datetime, timezone

import boto3

s3 = boto3.client("s3")
BUCKET = os.environ["BUCKET_NAME"]

VALID_EVENT_TYPES = {
    "llm_call",
    "golf_api_call",
    "weather_call",
    "mapbox_call",
    "course_played",
}

MAX_EVENTS_PER_REQUEST = 100
MAX_BODY_BYTES = 64 * 1024  # 64 KB


def handler(event, context):
    # Parse body
    body_str = event.get("body", "")
    if not body_str:
        return _response(400, {"error": "Empty request body"})

    if len(body_str) > MAX_BODY_BYTES:
        return _response(400, {"error": "Request body too large"})

    try:
        body = json.loads(body_str)
    except json.JSONDecodeError:
        return _response(400, {"error": "Invalid JSON"})

    # Validate structure
    device_id = body.get("deviceId")
    if not device_id or not isinstance(device_id, str):
        return _response(400, {"error": "Missing or invalid deviceId"})

    events = body.get("events")
    if not events or not isinstance(events, list):
        return _response(400, {"error": "Missing or invalid events array"})

    if len(events) > MAX_EVENTS_PER_REQUEST:
        return _response(400, {"error": f"Too many events (max {MAX_EVENTS_PER_REQUEST})"})

    # Validate each event has a valid type
    for i, evt in enumerate(events):
        if not isinstance(evt, dict):
            return _response(400, {"error": f"Event {i} is not an object"})
        evt_type = evt.get("type")
        if evt_type not in VALID_EVENT_TYPES:
            return _response(400, {"error": f"Event {i} has invalid type: {evt_type}"})

    # Write to S3, partitioned by date
    now = datetime.now(timezone.utc)
    date_prefix = now.strftime("%Y/%m/%d")
    file_id = uuid.uuid4().hex[:12]
    key = f"events/{date_prefix}/{device_id}_{file_id}.json"

    record = {
        "deviceId": device_id,
        "receivedAt": now.isoformat(),
        "eventCount": len(events),
        "events": events,
    }

    s3.put_object(
        Bucket=BUCKET,
        Key=key,
        Body=json.dumps(record),
        ContentType="application/json",
    )

    return _response(200, {"accepted": len(events)})


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
        },
        "body": json.dumps(body),
    }
