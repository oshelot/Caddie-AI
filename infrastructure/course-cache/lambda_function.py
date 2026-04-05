"""
CaddieAI Course Cache Lambda

Stores and retrieves NormalizedCourse JSON objects in S3, keyed by courseId
and schema version. Authenticates clients via x-api-key header.

Routes:
  GET  /courses/{courseId}?schema=1.0  → S3 lookup, return JSON (gzip) or 404
  PUT  /courses/{courseId}?schema=1.0  → gzip-compress and store in S3
"""

import gzip
import json
import os
import base64

import boto3
from botocore.exceptions import ClientError

# Cached across warm invocations
_s3_client = None
_proxy_api_key: str | None = None

BUCKET_NAME = os.environ.get("BUCKET_NAME", "caddieai-course-cache")
PROXY_API_KEY_ENV = os.environ.get("PROXY_API_KEY", "")
MAX_BODY_BYTES = 1_048_576  # 1 MB


def get_s3_client():
    global _s3_client
    if _s3_client is None:
        _s3_client = boto3.client("s3", region_name=os.environ.get("AWS_REGION", "us-east-2"))
    return _s3_client


def get_proxy_api_key() -> str:
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


def s3_key(schema: str, course_id: str) -> str:
    return f"courses/v{schema}/{course_id}.json.gz"


def lambda_handler(event, context):
    # Handle CORS preflight
    http_method = (
        event.get("requestContext", {}).get("http", {}).get("method", "")
        or event.get("httpMethod", "")
    )
    if http_method == "OPTIONS":
        return {
            "statusCode": 200,
            "headers": {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, PUT, OPTIONS",
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

    # Extract courseId from path
    path_params = event.get("pathParameters") or {}
    course_id = path_params.get("courseId", "")
    if not course_id:
        return error_response(400, "Missing courseId in path.")

    # Extract schema version from query params
    query_params = event.get("queryStringParameters") or {}
    schema = query_params.get("schema", "1.0")

    s3 = get_s3_client()
    key = s3_key(schema, course_id)

    if http_method == "GET":
        return handle_get(s3, key, course_id)
    elif http_method == "PUT":
        return handle_put(s3, key, course_id, event)
    else:
        return error_response(405, f"Method {http_method} not allowed.")


def handle_get(s3, key: str, course_id: str) -> dict:
    try:
        obj = s3.get_object(Bucket=BUCKET_NAME, Key=key)
        compressed_body = obj["Body"].read()

        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                "Content-Encoding": "gzip",
                "Access-Control-Allow-Origin": "*",
                "Cache-Control": "public, max-age=86400",
            },
            "body": base64.b64encode(compressed_body).decode("utf-8"),
            "isBase64Encoded": True,
        }
    except ClientError as e:
        if e.response["Error"]["Code"] == "NoSuchKey":
            return error_response(404, f"Course not found: {course_id}")
        raise


def handle_put(s3, key: str, course_id: str, event: dict) -> dict:
    # Parse body
    body_str = event.get("body", "")
    if event.get("isBase64Encoded"):
        body_str = base64.b64decode(body_str).decode("utf-8")

    if not body_str:
        return error_response(400, "Empty request body.")

    body_bytes = body_str.encode("utf-8")
    if len(body_bytes) > MAX_BODY_BYTES:
        return error_response(413, f"Payload too large. Max {MAX_BODY_BYTES} bytes.")

    # Validate JSON
    try:
        json.loads(body_str)
    except json.JSONDecodeError:
        return error_response(400, "Invalid JSON in request body.")

    # Gzip compress and store
    compressed = gzip.compress(body_bytes)
    s3.put_object(
        Bucket=BUCKET_NAME,
        Key=key,
        Body=compressed,
        ContentType="application/json",
        ContentEncoding="gzip",
    )

    return {
        "statusCode": 201,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps({
            "stored": True,
            "key": key,
            "originalSize": len(body_bytes),
            "compressedSize": len(compressed),
        }),
    }
