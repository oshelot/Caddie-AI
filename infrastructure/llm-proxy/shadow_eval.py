"""
CaddieAI LLM Shadow Evaluation Module

Runs the same prompt against configurable shadow models alongside the primary
model, logs results with comparison metrics to DynamoDB for quality dashboards.

Configuration via environment variables:
  SHADOW_MODELS       JSON string of model registry (see README)
  SHADOW_SAMPLE_RATE  float 0.0-1.0, probability of running shadows (default 1.0)
  EVAL_TABLE_NAME     DynamoDB table name (default "caddieai-llm-eval")
  EVAL_TTL_DAYS       days before auto-expiry (default 30)
"""

import asyncio
import hashlib
import json
import logging
import os
import random
import time
import uuid
from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Optional

import boto3

logger = logging.getLogger("shadow_eval")

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SHADOW_SAMPLE_RATE = float(os.environ.get("SHADOW_SAMPLE_RATE", "1.0"))
EVAL_TABLE_NAME = os.environ.get("EVAL_TABLE_NAME", "caddieai-llm-eval")
EVAL_TTL_DAYS = int(os.environ.get("EVAL_TTL_DAYS", "30"))
BEDROCK_REGION = os.environ.get(
    "BEDROCK_REGION", os.environ.get("AWS_REGION", "us-east-2")
)

# ---------------------------------------------------------------------------
# Model Registry
# ---------------------------------------------------------------------------

_DEFAULT_SHADOW_MODELS: dict[str, dict] = {
    "nova-lite": {
        "model_id": "us.amazon.nova-lite-v1:0",
        "provider": "bedrock",
    },
}


def _load_shadow_models() -> dict[str, dict]:
    """Load shadow model registry from env var or use defaults."""
    raw = os.environ.get("SHADOW_MODELS", "")
    if raw:
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            logger.error("Failed to parse SHADOW_MODELS env var, using defaults")
    return _DEFAULT_SHADOW_MODELS


SHADOW_MODELS: dict[str, dict] = _load_shadow_models()

# ---------------------------------------------------------------------------
# Pricing (USD per 1M tokens)
# ---------------------------------------------------------------------------

PRICING: dict[str, dict[str, float]] = {
    "us.amazon.nova-micro-v1:0": {"input": 0.035, "output": 0.14},
    "us.amazon.nova-lite-v1:0": {"input": 0.06, "output": 0.24},
    "us.anthropic.claude-3-5-haiku-20241022-v1:0": {"input": 0.80, "output": 4.00},
    "us.anthropic.claude-haiku-4-5-20251001-v1:0": {"input": 0.80, "output": 4.00},
    "gpt-4o-mini": {"input": 0.15, "output": 0.60},
}


def _estimate_cost(model_id: str, prompt_tokens: int, completion_tokens: int) -> float:
    p = PRICING.get(model_id, {"input": 0.0, "output": 0.0})
    return (prompt_tokens * p["input"] + completion_tokens * p["output"]) / 1_000_000


# ---------------------------------------------------------------------------
# Cached clients
# ---------------------------------------------------------------------------

_bedrock_client = None
_dynamodb_resource = None
_cloudwatch_client = None

CW_NAMESPACE = "CaddieAI/LLMEval"


def _get_bedrock_client():
    global _bedrock_client
    if _bedrock_client is None:
        _bedrock_client = boto3.client("bedrock-runtime", region_name=BEDROCK_REGION)
    return _bedrock_client


def _get_dynamodb_table():
    global _dynamodb_resource
    if _dynamodb_resource is None:
        _dynamodb_resource = boto3.resource("dynamodb", region_name=BEDROCK_REGION)
    return _dynamodb_resource.Table(EVAL_TABLE_NAME)


def _get_cloudwatch_client():
    global _cloudwatch_client
    if _cloudwatch_client is None:
        _cloudwatch_client = boto3.client("cloudwatch", region_name=BEDROCK_REGION)
    return _cloudwatch_client


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def should_run_shadows() -> bool:
    """Check sampling rate to decide whether to run shadow models."""
    if not SHADOW_MODELS:
        return False
    if SHADOW_SAMPLE_RATE <= 0.0:
        return False
    if SHADOW_SAMPLE_RATE >= 1.0:
        return True
    return random.random() < SHADOW_SAMPLE_RATE


def _messages_hash(messages: list[dict]) -> str:
    """SHA-256 hash of input messages for grouping/dedup."""
    return hashlib.sha256(
        json.dumps(messages, sort_keys=True).encode()
    ).hexdigest()[:16]


def _extract_fields(text: str) -> dict[str, Any]:
    """Parse LLM response as JSON and extract golf-specific fields."""
    result: dict[str, Any] = {
        "json_valid": False,
        "club_recommended": None,
        "distance_yards": None,
    }

    cleaned = text.strip()
    # Strip markdown code fences if present
    if cleaned.startswith("```"):
        lines = cleaned.split("\n")
        lines = [l for l in lines if not l.strip().startswith("```")]
        cleaned = "\n".join(lines).strip()

    try:
        parsed = json.loads(cleaned)
        result["json_valid"] = True
        result["club_recommended"] = parsed.get("club")
        dist = parsed.get("effectiveDistanceYards")
        if isinstance(dist, (int, float)):
            result["distance_yards"] = int(dist)
    except (json.JSONDecodeError, TypeError):
        pass

    return result


# ---------------------------------------------------------------------------
# Shadow model execution
# ---------------------------------------------------------------------------


async def _call_bedrock_shadow(
    model_name: str,
    model_config: dict,
    system_msgs: list[dict],
    converse_msgs: list[dict],
    inference_config: dict,
) -> dict[str, Any]:
    """Call a Bedrock shadow model via Converse API (in executor)."""
    loop = asyncio.get_event_loop()
    start = time.perf_counter()

    try:
        client = _get_bedrock_client()
        kwargs: dict[str, Any] = {
            "modelId": model_config["model_id"],
            "messages": converse_msgs,
            "inferenceConfig": inference_config,
        }
        if system_msgs:
            kwargs["system"] = system_msgs

        response = await loop.run_in_executor(
            None, lambda: client.converse(**kwargs)
        )
        latency_ms = int((time.perf_counter() - start) * 1000)

        output = response.get("output", {})
        content_blocks = output.get("message", {}).get("content", [])
        content = "".join(b.get("text", "") for b in content_blocks if "text" in b)

        usage = response.get("usage", {})
        prompt_tokens = usage.get("inputTokens", 0)
        completion_tokens = usage.get("outputTokens", 0)

        return {
            "model_name": model_name,
            "model_id": model_config["model_id"],
            "response_text": content,
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
            "total_tokens": prompt_tokens + completion_tokens,
            "latency_ms": latency_ms,
            "error": None,
        }
    except Exception as e:
        return {
            "model_name": model_name,
            "model_id": model_config["model_id"],
            "response_text": "",
            "prompt_tokens": 0,
            "completion_tokens": 0,
            "total_tokens": 0,
            "latency_ms": int((time.perf_counter() - start) * 1000),
            "error": str(e)[:500],
        }


async def _call_openai_shadow(
    model_name: str,
    model_config: dict,
    messages: list[dict],
    inference_config: dict,
) -> dict[str, Any]:
    """Placeholder for OpenAI shadow calls (v2)."""
    return {
        "model_name": model_name,
        "model_id": model_config["model_id"],
        "response_text": "",
        "prompt_tokens": 0,
        "completion_tokens": 0,
        "total_tokens": 0,
        "latency_ms": 0,
        "error": "OpenAI provider not yet implemented",
    }


# ---------------------------------------------------------------------------
# DynamoDB logging
# ---------------------------------------------------------------------------


def _build_eval_item(
    request_id: str,
    model_id: str,
    role: str,
    messages_hash: str,
    response_text: str,
    latency_ms: int,
    prompt_tokens: int,
    completion_tokens: int,
    total_tokens: int,
    error: Optional[str],
    primary_fields: Optional[dict] = None,
) -> dict:
    """Build a DynamoDB item for one model's result."""
    now = datetime.now(timezone.utc)
    ttl = int(now.timestamp()) + (EVAL_TTL_DAYS * 86400)

    extracted = _extract_fields(response_text)

    item: dict[str, Any] = {
        "request_id": request_id,
        "model_id": model_id,
        "role": role,
        "timestamp": now.isoformat(),
        "messages_hash": messages_hash,
        "response_text": response_text[:10000],
        "json_valid": extracted["json_valid"],
        "latency_ms": latency_ms,
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "total_tokens": total_tokens,
        "estimated_cost_usd": Decimal(
            str(round(_estimate_cost(model_id, prompt_tokens, completion_tokens), 8))
        ),
        "ttl": ttl,
    }

    if extracted["club_recommended"] is not None:
        item["club_recommended"] = extracted["club_recommended"]
    if extracted["distance_yards"] is not None:
        item["distance_yards"] = extracted["distance_yards"]
    if error:
        item["error"] = error[:500]

    # Comparison metrics for shadow items
    if role == "shadow" and primary_fields is not None:
        p_club = primary_fields.get("club_recommended")
        s_club = extracted["club_recommended"]
        if p_club and s_club:
            item["club_match"] = s_club.lower() == p_club.lower()

        p_dist = primary_fields.get("distance_yards")
        s_dist = extracted["distance_yards"]
        if p_dist is not None and s_dist is not None:
            item["distance_delta"] = s_dist - p_dist

    return item


def _write_eval_items(items: list[dict]) -> None:
    """Batch-write evaluation items to DynamoDB."""
    try:
        table = _get_dynamodb_table()
        with table.batch_writer() as batch:
            for item in items:
                batch.put_item(Item=item)
    except Exception as e:
        logger.error(f"Failed to write eval items to DynamoDB: {e}")


# ---------------------------------------------------------------------------
# CloudWatch Metrics
# ---------------------------------------------------------------------------


def _publish_cloudwatch_metrics(items: list[dict]) -> None:
    """Publish eval metrics to CloudWatch for Grafana dashboards."""
    try:
        cw = _get_cloudwatch_client()
        metric_data = []
        now = datetime.now(timezone.utc)

        for item in items:
            model_id = item["model_id"]
            role = item["role"]
            dims = [
                {"Name": "ModelId", "Value": model_id},
                {"Name": "Role", "Value": role},
            ]

            # Latency
            metric_data.append({
                "MetricName": "Latency",
                "Dimensions": dims,
                "Timestamp": now,
                "Value": float(item["latency_ms"]),
                "Unit": "Milliseconds",
            })

            # Token counts
            metric_data.append({
                "MetricName": "PromptTokens",
                "Dimensions": dims,
                "Timestamp": now,
                "Value": float(item["prompt_tokens"]),
                "Unit": "Count",
            })
            metric_data.append({
                "MetricName": "CompletionTokens",
                "Dimensions": dims,
                "Timestamp": now,
                "Value": float(item["completion_tokens"]),
                "Unit": "Count",
            })
            metric_data.append({
                "MetricName": "TotalTokens",
                "Dimensions": dims,
                "Timestamp": now,
                "Value": float(item["total_tokens"]),
                "Unit": "Count",
            })

            # Cost
            cost = float(item.get("estimated_cost_usd", 0))
            metric_data.append({
                "MetricName": "EstimatedCostUSD",
                "Dimensions": dims,
                "Timestamp": now,
                "Value": cost,
                "Unit": "None",
            })

            # JSON validity (1 = valid, 0 = invalid)
            metric_data.append({
                "MetricName": "JSONValid",
                "Dimensions": dims,
                "Timestamp": now,
                "Value": 1.0 if item.get("json_valid") else 0.0,
                "Unit": "Count",
            })

            # Error count
            metric_data.append({
                "MetricName": "Errors",
                "Dimensions": dims,
                "Timestamp": now,
                "Value": 1.0 if item.get("error") else 0.0,
                "Unit": "Count",
            })

            # Shadow-specific comparison metrics
            if role == "shadow":
                if "club_match" in item:
                    metric_data.append({
                        "MetricName": "ClubMatch",
                        "Dimensions": dims,
                        "Timestamp": now,
                        "Value": 1.0 if item["club_match"] else 0.0,
                        "Unit": "Count",
                    })
                if "distance_delta" in item:
                    metric_data.append({
                        "MetricName": "DistanceDelta",
                        "Dimensions": dims,
                        "Timestamp": now,
                        "Value": float(abs(item["distance_delta"])),
                        "Unit": "Count",
                    })

        # Invocation count (one per request, no model dimension)
        metric_data.append({
            "MetricName": "EvalRequests",
            "Dimensions": [],
            "Timestamp": now,
            "Value": 1.0,
            "Unit": "Count",
        })

        # CloudWatch accepts max 1000 metric data points per call
        for i in range(0, len(metric_data), 1000):
            cw.put_metric_data(
                Namespace=CW_NAMESPACE,
                MetricData=metric_data[i:i + 1000],
            )
    except Exception as e:
        logger.error(f"Failed to publish CloudWatch metrics: {e}")


# ---------------------------------------------------------------------------
# Orchestrators (called from app.py)
# ---------------------------------------------------------------------------


async def run_shadow_evaluation_buffered(
    body: dict,
    primary_response_text: str,
    primary_usage: dict,
    primary_latency_ms: int,
    primary_model_id: str,
) -> None:
    """
    Async orchestrator for buffered mode.
    Runs shadow models concurrently and writes all results to DynamoDB.
    Catches all exceptions internally — never affects the primary response.
    """
    try:
        if not should_run_shadows():
            return

        request_id = str(uuid.uuid4())
        msg_hash = _messages_hash(body.get("messages", []))

        # Reuse message conversion from app.py (lazy import to avoid circular)
        from app import _convert_messages_to_bedrock

        system_msgs, converse_msgs = _convert_messages_to_bedrock(body)
        inference_config = {
            "maxTokens": body.get("max_tokens", 1500),
            "temperature": body.get("temperature", 0.7),
        }

        # Fire all shadow calls concurrently
        tasks = []
        for name, config in SHADOW_MODELS.items():
            provider = config.get("provider", "bedrock")
            if provider == "bedrock":
                tasks.append(
                    _call_bedrock_shadow(
                        name, config, system_msgs, converse_msgs, inference_config
                    )
                )
            elif provider == "openai":
                tasks.append(
                    _call_openai_shadow(
                        name, config, body.get("messages", []), inference_config
                    )
                )

        shadow_results = await asyncio.gather(*tasks, return_exceptions=True)

        # Build primary item
        primary_fields = _extract_fields(primary_response_text)
        items = [
            _build_eval_item(
                request_id=request_id,
                model_id=primary_model_id,
                role="primary",
                messages_hash=msg_hash,
                response_text=primary_response_text,
                latency_ms=primary_latency_ms,
                prompt_tokens=primary_usage.get("prompt_tokens", 0),
                completion_tokens=primary_usage.get("completion_tokens", 0),
                total_tokens=primary_usage.get("total_tokens", 0),
                error=None,
            )
        ]

        # Build shadow items
        for result in shadow_results:
            if isinstance(result, Exception):
                logger.error(f"Shadow task exception: {result}")
                continue
            items.append(
                _build_eval_item(
                    request_id=request_id,
                    model_id=result["model_id"],
                    role="shadow",
                    messages_hash=msg_hash,
                    response_text=result["response_text"],
                    latency_ms=result["latency_ms"],
                    prompt_tokens=result["prompt_tokens"],
                    completion_tokens=result["completion_tokens"],
                    total_tokens=result["total_tokens"],
                    error=result["error"],
                    primary_fields=primary_fields,
                )
            )

        # Write to DynamoDB and publish CloudWatch metrics in executor
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, lambda: _write_eval_items(items))
        await loop.run_in_executor(None, lambda: _publish_cloudwatch_metrics(items))

        logger.info(
            f"Shadow eval complete: request_id={request_id}, "
            f"models={len(shadow_results)}, items={len(items)}"
        )

    except Exception as e:
        logger.error(f"Shadow evaluation failed (non-fatal): {e}")


def run_shadow_evaluation_streaming_sync(
    body: dict,
    primary_response_text: str,
    primary_usage: dict,
    primary_latency_ms: int,
    primary_model_id: str,
) -> None:
    """
    Sync orchestrator for streaming mode.
    Called after [DONE] has been yielded (inside the generator, no more yields).
    Runs shadow models sequentially via boto3 and writes to DynamoDB.
    """
    try:
        if not should_run_shadows():
            return

        request_id = str(uuid.uuid4())
        msg_hash = _messages_hash(body.get("messages", []))

        from app import _convert_messages_to_bedrock

        system_msgs, converse_msgs = _convert_messages_to_bedrock(body)
        inference_config = {
            "maxTokens": body.get("max_tokens", 500),
            "temperature": body.get("temperature", 0.7),
        }

        primary_fields = _extract_fields(primary_response_text)

        items = [
            _build_eval_item(
                request_id=request_id,
                model_id=primary_model_id,
                role="primary",
                messages_hash=msg_hash,
                response_text=primary_response_text,
                latency_ms=primary_latency_ms,
                prompt_tokens=primary_usage.get("prompt_tokens", 0),
                completion_tokens=primary_usage.get("completion_tokens", 0),
                total_tokens=primary_usage.get("total_tokens", 0),
                error=None,
            )
        ]

        client = _get_bedrock_client()
        for name, config in SHADOW_MODELS.items():
            if config.get("provider") != "bedrock":
                continue

            start = time.perf_counter()
            try:
                kwargs: dict[str, Any] = {
                    "modelId": config["model_id"],
                    "messages": converse_msgs,
                    "inferenceConfig": inference_config,
                }
                if system_msgs:
                    kwargs["system"] = system_msgs

                response = client.converse(**kwargs)
                latency_ms = int((time.perf_counter() - start) * 1000)

                output = response.get("output", {})
                content_blocks = output.get("message", {}).get("content", [])
                content = "".join(
                    b.get("text", "") for b in content_blocks if "text" in b
                )

                usage = response.get("usage", {})
                prompt_tokens = usage.get("inputTokens", 0)
                completion_tokens = usage.get("outputTokens", 0)

                items.append(
                    _build_eval_item(
                        request_id=request_id,
                        model_id=config["model_id"],
                        role="shadow",
                        messages_hash=msg_hash,
                        response_text=content,
                        latency_ms=latency_ms,
                        prompt_tokens=prompt_tokens,
                        completion_tokens=completion_tokens,
                        total_tokens=prompt_tokens + completion_tokens,
                        error=None,
                        primary_fields=primary_fields,
                    )
                )
            except Exception as e:
                latency_ms = int((time.perf_counter() - start) * 1000)
                items.append(
                    _build_eval_item(
                        request_id=request_id,
                        model_id=config["model_id"],
                        role="shadow",
                        messages_hash=msg_hash,
                        response_text="",
                        latency_ms=latency_ms,
                        prompt_tokens=0,
                        completion_tokens=0,
                        total_tokens=0,
                        error=str(e)[:500],
                        primary_fields=primary_fields,
                    )
                )

        _write_eval_items(items)
        _publish_cloudwatch_metrics(items)
        logger.info(
            f"Shadow eval (streaming) complete: request_id={request_id}, "
            f"items={len(items)}"
        )

    except Exception as e:
        logger.error(f"Shadow evaluation (streaming) failed (non-fatal): {e}")
