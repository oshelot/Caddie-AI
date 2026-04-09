#!/usr/bin/env python3
"""
CaddieAI LLM Benchmark — compares OpenAI gpt-4o-mini vs Bedrock models.

Sends the same realistic golf caddie prompt (system + user with JSON schema)
to each provider and measures:
  - Time to first token (TTFT) — streaming only
  - Total latency (end-to-end)
  - Output token count (approximate)
  - Whether the response is valid JSON matching the ShotRecommendation schema
  - Cost estimate per call

Usage:
  pip install boto3 httpx
  export OPENAI_API_KEY="sk-..."   (or use --openai-key)
  python benchmark.py --profile caddieai --region us-east-2 --runs 3
"""

import argparse
import json
import os
import sys
import time
from typing import Any

import boto3
import httpx

# ---------------------------------------------------------------------------
# The actual CaddieAI system prompt (from PromptService.Defaults)
# ---------------------------------------------------------------------------

SYSTEM_PROMPT = """You are an expert golf caddie AI assistant. You have deep knowledge of course \
management, club selection, shot shaping, and risk/reward decision-making comparable \
to a PGA Tour caddie with 20+ years of experience.

Your role is to analyze the shot situation and the deterministic analysis provided, \
then give a confident, clear recommendation covering BOTH shot strategy and shot \
execution guidance. You speak with the calm authority of a trusted caddie — concise, \
specific, and reassuring.

STRATEGY guidelines:
- Trust the deterministic distance calculations provided. Do not recalculate effective distance.
- Focus on: target selection nuance, risk assessment, and mental approach.
- Consider the player's handicap, miss tendency, and stock shape when choosing targets.
- For higher handicaps (15+), favor safer plays and larger targets.
- For lower handicaps (<8), you can suggest more aggressive lines when appropriate.
- Always provide a conservative option for difficult or risky shots.
- Rationale should be 2-4 concise bullet points explaining your recommendation.
- If hazard notes mention specific dangers (water, OB, bunkers), factor them prominently.

EXECUTION guidelines:
- You will receive a structured execution plan from the deterministic engine. Use it as \
  the foundation. You may refine the phrasing to be more natural and caddie-like, but \
  do NOT contradict the structured template values.
- Execution guidance must be simple, practical, and usable on the course.
- Do NOT become a swing coach. No biomechanics. No deep mechanical overhauls.
- Use plain golfer language: "ball a touch back", "favor your lead side", "shorter finish".
- Keep it to 1-3 actionable setup/swing cues.
- The setupSummary should be a single calm sentence summarizing how to set up.
- The swingThought should be ONE specific, actionable thought.
- The mistakeToAvoid should be ONE common mistake for this shot type.

GUARDRAILS:
- You are a golf caddie. Only respond to golf-related questions.

You MUST respond with valid JSON matching this exact schema:
{
  "club": "string (e.g., '7 Iron', 'Pitching Wedge')",
  "effectiveDistanceYards": number,
  "target": "string describing where to aim",
  "preferredMiss": "string describing the safe miss area",
  "riskLevel": "low" | "medium" | "high",
  "confidence": "high" | "medium" | "low",
  "rationale": ["string bullet 1", "string bullet 2", ...],
  "conservativeOption": "string or null",
  "swingThought": "string - one specific, actionable thought",
  "executionPlan": {
    "archetype": "string (shot archetype name)",
    "setupSummary": "string - one calm sentence",
    "ballPosition": "string",
    "weightDistribution": "string",
    "stanceWidth": "string",
    "alignment": "string",
    "clubface": "string",
    "shaftLean": "string",
    "backswingLength": "string",
    "followThrough": "string",
    "tempo": "string",
    "strikeIntention": "string",
    "swingThought": "string",
    "mistakeToAvoid": "string"
  }
}

Respond ONLY with the JSON object. No markdown, no explanation outside the JSON."""

# ---------------------------------------------------------------------------
# Realistic user message (approximates a real CaddieAI request)
# ---------------------------------------------------------------------------

USER_MESSAGE = """Shot situation:
{
  "distanceYards": 156,
  "elevationFeet": -8,
  "hazardNotes": "Water left, bunker front-right",
  "lieType": "fairway",
  "shotType": "approach",
  "slope": "flat",
  "windDirection": "into",
  "windStrength": "moderate"
}

Player profile:
Handicap: 14
Stock shape (woods): Slight Fade
Stock shape (irons): Straight
Stock shape (hybrids): Straight
Miss tendency: Right
Default aggressiveness: Moderate
Bunker confidence: Low
Wedge confidence: Medium
Preferred chip style: Bump and Run
Swing tendency: Smooth
Club distances: D: 230 yards, 3W: 215 yards, 5W: 200 yards, 4H: 190 yards, 5I: 175 yards, 6I: 165 yards, 7I: 155 yards, 8I: 145 yards, 9I: 135 yards, PW: 125 yards, GW: 110 yards, SW: 95 yards, LW: 75 yards

Deterministic analysis (trust these calculations):
{
  "adjustments": [
    "Wind (into, moderate): +8 yards",
    "Elevation (-8 ft): -3 yards"
  ],
  "effectiveDistanceYards": 161,
  "recommendedClub": "6 Iron",
  "targetStrategy": {
    "preferredMiss": "Right of pin, short side",
    "reasoning": "Water left is the primary danger. With a right miss tendency, aiming center-left gives margin away from water while the natural fade works toward center.",
    "target": "Center-left of green"
  }
}

Execution template from engine (use as foundation, refine the phrasing):
{
  "alignment": "Feet and shoulders aimed center-left of green",
  "archetype": "standardIronApproach",
  "backswingLength": "full",
  "ballPosition": "Center of stance",
  "clubface": "Square to target line",
  "followThrough": "full finish",
  "mistakeToAvoid": "Trying to steer it away from water — trust your line and commit",
  "setupSummary": "Standard 6-iron setup. Ball center, weight balanced, aim center-left and trust the swing.",
  "shaftLean": "Slight forward press",
  "stanceWidth": "Shoulder width",
  "strikeIntention": "Solid, ball-first contact with a shallow divot",
  "swingThought": "Smooth tempo, trust the club",
  "tempo": "Smooth, controlled rhythm — no rushing",
  "weightDistribution": "55% lead side"
}

Based on this analysis, provide your caddie recommendation with execution plan as JSON."""

# ---------------------------------------------------------------------------
# Required JSON fields for validation
# ---------------------------------------------------------------------------

REQUIRED_TOP_KEYS = {
    "club", "effectiveDistanceYards", "target", "preferredMiss",
    "riskLevel", "confidence", "rationale", "swingThought", "executionPlan",
}
REQUIRED_EXEC_KEYS = {
    "archetype", "setupSummary", "ballPosition", "weightDistribution",
    "stanceWidth", "alignment", "clubface", "shaftLean", "backswingLength",
    "followThrough", "tempo", "strikeIntention", "swingThought", "mistakeToAvoid",
}

# ---------------------------------------------------------------------------
# Pricing (USD per 1M tokens)
# ---------------------------------------------------------------------------

PRICING = {
    "gpt-4o-mini":       {"input": 0.15,  "output": 0.60},
    "nova-micro":        {"input": 0.035, "output": 0.14},
    "nova-lite":         {"input": 0.06,  "output": 0.24},
    "claude-3.5-haiku":  {"input": 0.80,  "output": 4.00},
    "claude-haiku-4.5":  {"input": 0.80,  "output": 4.00},
}


def estimate_cost(model_key: str, prompt_tokens: int, completion_tokens: int) -> float:
    p = PRICING.get(model_key, {"input": 0, "output": 0})
    return (prompt_tokens * p["input"] + completion_tokens * p["output"]) / 1_000_000


def validate_json(text: str) -> dict[str, Any]:
    """Parse JSON, return dict with 'valid', 'missing_keys', 'parsed'."""
    # Strip markdown fences if present
    cleaned = text.strip()
    if cleaned.startswith("```"):
        lines = cleaned.split("\n")
        lines = [l for l in lines if not l.strip().startswith("```")]
        cleaned = "\n".join(lines)

    try:
        parsed = json.loads(cleaned)
    except json.JSONDecodeError as e:
        return {"valid": False, "error": str(e), "parsed": None, "missing_keys": []}

    missing_top = REQUIRED_TOP_KEYS - set(parsed.keys())
    missing_exec = set()
    if "executionPlan" in parsed and isinstance(parsed["executionPlan"], dict):
        missing_exec = REQUIRED_EXEC_KEYS - set(parsed["executionPlan"].keys())
    elif "executionPlan" not in parsed:
        missing_exec = REQUIRED_EXEC_KEYS

    all_missing = list(missing_top) + [f"executionPlan.{k}" for k in missing_exec]
    return {
        "valid": len(all_missing) == 0,
        "missing_keys": all_missing,
        "parsed": parsed,
        "club": parsed.get("club", "N/A"),
    }


# ---------------------------------------------------------------------------
# OpenAI (via proxy Lambda — same path the app uses)
# ---------------------------------------------------------------------------

def benchmark_openai_proxy(proxy_url: str, proxy_key: str) -> dict:
    """Call the CaddieAI proxy (gpt-4o-mini) in buffered mode."""
    payload = {
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": USER_MESSAGE},
        ],
        "max_tokens": 1500,
        "temperature": 0.7,
        "response_format": {"type": "json_object"},
    }

    start = time.perf_counter()
    resp = httpx.post(
        proxy_url,
        json=payload,
        headers={"Content-Type": "application/json", "x-api-key": proxy_key},
        timeout=60,
    )
    total_ms = (time.perf_counter() - start) * 1000

    if resp.status_code != 200:
        return {"model": "gpt-4o-mini (proxy)", "error": f"HTTP {resp.status_code}: {resp.text[:200]}", "total_ms": total_ms}

    body = resp.json()
    content = body.get("choices", [{}])[0].get("message", {}).get("content", "")
    usage = body.get("usage", {})
    prompt_tokens = usage.get("prompt_tokens", 0)
    completion_tokens = usage.get("completion_tokens", 0)

    validation = validate_json(content)

    return {
        "model": "gpt-4o-mini (proxy)",
        "total_ms": round(total_ms),
        "ttft_ms": "N/A (buffered)",
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "valid_json": validation["valid"],
        "missing_keys": validation["missing_keys"],
        "club": validation.get("club", "N/A"),
        "cost_usd": estimate_cost("gpt-4o-mini", prompt_tokens, completion_tokens),
    }


# ---------------------------------------------------------------------------
# OpenAI direct (for comparison without Lambda hop)
# ---------------------------------------------------------------------------

def benchmark_openai_direct(api_key: str) -> dict:
    """Call OpenAI directly (no Lambda proxy) to isolate model latency."""
    payload = {
        "model": "gpt-4o-mini",
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": USER_MESSAGE},
        ],
        "max_tokens": 1500,
        "temperature": 0.7,
        "response_format": {"type": "json_object"},
    }

    start = time.perf_counter()
    resp = httpx.post(
        "https://api.openai.com/v1/chat/completions",
        json=payload,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
        timeout=60,
    )
    total_ms = (time.perf_counter() - start) * 1000

    if resp.status_code != 200:
        return {"model": "gpt-4o-mini (direct)", "error": f"HTTP {resp.status_code}: {resp.text[:200]}", "total_ms": total_ms}

    body = resp.json()
    content = body.get("choices", [{}])[0].get("message", {}).get("content", "")
    usage = body.get("usage", {})
    prompt_tokens = usage.get("prompt_tokens", 0)
    completion_tokens = usage.get("completion_tokens", 0)

    validation = validate_json(content)

    return {
        "model": "gpt-4o-mini (direct)",
        "total_ms": round(total_ms),
        "ttft_ms": "N/A (buffered)",
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "valid_json": validation["valid"],
        "missing_keys": validation["missing_keys"],
        "club": validation.get("club", "N/A"),
        "cost_usd": estimate_cost("gpt-4o-mini", prompt_tokens, completion_tokens),
    }


# ---------------------------------------------------------------------------
# Bedrock (Converse API — works for Claude + Nova + Llama)
# ---------------------------------------------------------------------------

BEDROCK_MODELS = {
    "nova-micro":       "us.amazon.nova-micro-v1:0",
    "nova-lite":        "us.amazon.nova-lite-v1:0",
    "claude-3.5-haiku": "us.anthropic.claude-3-5-haiku-20241022-v1:0",
    "claude-haiku-4.5": "us.anthropic.claude-haiku-4-5-20251001-v1:0",
}


def benchmark_bedrock(client, model_key: str) -> dict:
    """Call Bedrock Converse API with the standard golf prompt."""
    model_id = BEDROCK_MODELS[model_key]

    messages = [
        {
            "role": "user",
            "content": [{"text": USER_MESSAGE}],
        }
    ]

    system_msg = [{"text": SYSTEM_PROMPT}]

    start = time.perf_counter()
    try:
        resp = client.converse(
            modelId=model_id,
            messages=messages,
            system=system_msg,
            inferenceConfig={
                "maxTokens": 1500,
                "temperature": 0.7,
            },
        )
    except Exception as e:
        total_ms = (time.perf_counter() - start) * 1000
        return {"model": model_key, "error": str(e)[:200], "total_ms": round(total_ms)}

    total_ms = (time.perf_counter() - start) * 1000

    # Extract content
    output = resp.get("output", {})
    content_blocks = output.get("message", {}).get("content", [])
    content = ""
    for block in content_blocks:
        if "text" in block:
            content += block["text"]

    # Token usage
    usage = resp.get("usage", {})
    prompt_tokens = usage.get("inputTokens", 0)
    completion_tokens = usage.get("outputTokens", 0)

    validation = validate_json(content)

    return {
        "model": model_key,
        "total_ms": round(total_ms),
        "ttft_ms": "N/A (buffered)",
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "valid_json": validation["valid"],
        "missing_keys": validation["missing_keys"],
        "club": validation.get("club", "N/A"),
        "cost_usd": estimate_cost(model_key, prompt_tokens, completion_tokens),
    }


def benchmark_bedrock_streaming(client, model_key: str) -> dict:
    """Call Bedrock ConverseStream API to measure TTFT."""
    model_id = BEDROCK_MODELS[model_key]

    messages = [
        {
            "role": "user",
            "content": [{"text": USER_MESSAGE}],
        }
    ]

    system_msg = [{"text": SYSTEM_PROMPT}]

    start = time.perf_counter()
    ttft = None
    content = ""

    try:
        resp = client.converse_stream(
            modelId=model_id,
            messages=messages,
            system=system_msg,
            inferenceConfig={
                "maxTokens": 1500,
                "temperature": 0.7,
            },
        )

        stream = resp.get("stream", [])
        prompt_tokens = 0
        completion_tokens = 0

        for event in stream:
            if "contentBlockDelta" in event:
                delta = event["contentBlockDelta"].get("delta", {})
                text = delta.get("text", "")
                if text and ttft is None:
                    ttft = (time.perf_counter() - start) * 1000
                content += text
            elif "metadata" in event:
                usage = event["metadata"].get("usage", {})
                prompt_tokens = usage.get("inputTokens", 0)
                completion_tokens = usage.get("outputTokens", 0)

    except Exception as e:
        total_ms = (time.perf_counter() - start) * 1000
        return {"model": f"{model_key} (stream)", "error": str(e)[:200], "total_ms": round(total_ms)}

    total_ms = (time.perf_counter() - start) * 1000

    validation = validate_json(content)

    return {
        "model": f"{model_key} (stream)",
        "total_ms": round(total_ms),
        "ttft_ms": round(ttft) if ttft else "N/A",
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "valid_json": validation["valid"],
        "missing_keys": validation["missing_keys"],
        "club": validation.get("club", "N/A"),
        "cost_usd": estimate_cost(model_key, prompt_tokens, completion_tokens),
    }


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def print_result(r: dict, run_num: int | None = None):
    prefix = f"  Run {run_num}: " if run_num else "  "
    if "error" in r:
        print(f"{prefix}{r['model']:30s}  ERROR: {r['error']}")
        return

    valid_str = "VALID" if r["valid_json"] else f"INVALID ({len(r['missing_keys'])} missing)"
    cost_str = f"${r['cost_usd']:.6f}"

    print(
        f"{prefix}{r['model']:30s}  "
        f"total={r['total_ms']:>5d}ms  "
        f"ttft={str(r['ttft_ms']):>12s}  "
        f"tokens={r['prompt_tokens']}+{r['completion_tokens']}  "
        f"json={valid_str:20s}  "
        f"club={r['club']:15s}  "
        f"cost={cost_str}"
    )


def main():
    parser = argparse.ArgumentParser(description="CaddieAI LLM Benchmark")
    parser.add_argument("--profile", default="caddieai", help="AWS profile name")
    parser.add_argument("--region", default="us-east-2", help="AWS region")
    parser.add_argument("--runs", type=int, default=3, help="Number of runs per model")
    parser.add_argument("--openai-key", default=os.environ.get("OPENAI_API_KEY", ""), help="OpenAI API key for direct test")
    parser.add_argument("--proxy-url", default="https://4utb5leh3ybifep5fgzuz3hlsy0apmmb.lambda-url.us-east-2.on.aws/", help="Lambda proxy URL")
    parser.add_argument("--proxy-key", default=os.environ.get("PROXY_API_KEY", ""), help="Proxy API key (or set PROXY_API_KEY env var)")
    parser.add_argument("--models", default="all", help="Comma-separated model keys, or 'all'")
    parser.add_argument("--skip-openai", action="store_true", help="Skip OpenAI tests")
    args = parser.parse_args()

    # Setup Bedrock client
    session = boto3.Session(profile_name=args.profile, region_name=args.region)
    bedrock = session.client("bedrock-runtime")

    # Determine which models to test
    if args.models == "all":
        model_keys = list(BEDROCK_MODELS.keys())
    else:
        model_keys = [m.strip() for m in args.models.split(",")]

    print("=" * 130)
    print("CaddieAI LLM Benchmark")
    print(f"Prompt: ~{len(SYSTEM_PROMPT) + len(USER_MESSAGE)} chars  |  Runs per model: {args.runs}")
    print("=" * 130)

    all_results: dict[str, list[dict]] = {}

    # OpenAI via proxy
    if not args.skip_openai:
        print(f"\n--- gpt-4o-mini (via Lambda proxy) ---")
        results = []
        for i in range(args.runs):
            r = benchmark_openai_proxy(args.proxy_url, args.proxy_key)
            print_result(r, i + 1)
            results.append(r)
        all_results["gpt-4o-mini (proxy)"] = results

        # OpenAI direct (if key available)
        if args.openai_key:
            print(f"\n--- gpt-4o-mini (direct, no Lambda) ---")
            results = []
            for i in range(args.runs):
                r = benchmark_openai_direct(args.openai_key)
                print_result(r, i + 1)
                results.append(r)
            all_results["gpt-4o-mini (direct)"] = results

    # Bedrock models
    for model_key in model_keys:
        if model_key not in BEDROCK_MODELS:
            print(f"\n--- {model_key}: SKIPPED (unknown model) ---")
            continue

        # Buffered
        print(f"\n--- {model_key} (Bedrock buffered) ---")
        results = []
        for i in range(args.runs):
            r = benchmark_bedrock(bedrock, model_key)
            print_result(r, i + 1)
            results.append(r)
        all_results[model_key] = results

        # Streaming (for TTFT)
        print(f"\n--- {model_key} (Bedrock streaming) ---")
        results = []
        for i in range(args.runs):
            r = benchmark_bedrock_streaming(bedrock, model_key)
            print_result(r, i + 1)
            results.append(r)
        all_results[f"{model_key} (stream)"] = results

    # Summary
    print("\n" + "=" * 130)
    print("SUMMARY (averages)")
    print("=" * 130)
    print(f"{'Model':35s}  {'Avg Total':>10s}  {'Avg TTFT':>10s}  {'Valid JSON':>10s}  {'Avg Cost':>12s}")
    print("-" * 85)

    for name, runs in all_results.items():
        ok_runs = [r for r in runs if "error" not in r]
        if not ok_runs:
            print(f"{name:35s}  ALL ERRORS")
            continue

        avg_total = sum(r["total_ms"] for r in ok_runs) / len(ok_runs)
        ttft_vals = [r["ttft_ms"] for r in ok_runs if isinstance(r.get("ttft_ms"), (int, float))]
        avg_ttft = f"{sum(ttft_vals) / len(ttft_vals):.0f}ms" if ttft_vals else "N/A"
        valid_pct = sum(1 for r in ok_runs if r["valid_json"]) / len(ok_runs) * 100
        avg_cost = sum(r["cost_usd"] for r in ok_runs) / len(ok_runs)

        print(f"{name:35s}  {avg_total:>8.0f}ms  {avg_ttft:>10s}  {valid_pct:>8.0f}%  ${avg_cost:>10.6f}")


if __name__ == "__main__":
    main()
