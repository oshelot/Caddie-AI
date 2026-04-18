"""
A/B test: Nova Pro vs GPT-4o for multi-course hole assignment.

Fetches Terra Lago's website (scorecard + course maps), OSM data,
and Golf Course API data, then sends the same multimodal prompt to
both models. Compares their hole-to-course assignments against the
scorecard ground truth.

Usage:
  python3 test_rag_assignment.py

Requires:
  - AWS credentials (for Bedrock)
  - OPENAI_API_KEY env var or caddieai/openai-api-key in Secrets Manager
  - GOLF_COURSE_API_KEY env var
"""

import base64
import json
import os
import sys
import time
import urllib.parse
import urllib.request

import boto3

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

FACILITY_NAME = "The Golf Club at Terra Lago"
FACILITY_LAT = 33.742
FACILITY_LON = -116.188

GOLF_API_KEY = os.environ.get("GOLF_COURSE_API_KEY", "2VND3GOBC6S3JQEI7P2YM3A5JY")
BEDROCK_REGION = "us-east-2"
NOVA_PRO_MODEL = "us.amazon.nova-pro-v1:0"

# Ground truth from scorecard
NORTH_PARS = [4, 4, 4, 3, 5, 5, 3, 4, 4, 5, 4, 4, 3, 4, 3, 4, 5, 4]
SOUTH_PARS = [4, 4, 5, 3, 4, 3, 4, 5, 4, 4, 4, 3, 4, 5, 4, 4, 3, 5]

NORTH_HOLE_NAMES = [
    "Uphill Battle", "Moonscape", "Postage Stamp", "Intimidation",
    "Eternity", "The Alley", "Peak-A-Boo", "Pinnacle", "The Brute",
    "Gauntlet", "Roller Coaster", "Options", "No Way Out", "Go For It",
    "Got Balls?", "Sand Box", "Wasteland", "Knockout"
]
SOUTH_HOLE_NAMES = [
    "Rocky Peak", "Box Car", "Mountain Pass", "Cliffhanger",
    "Panorama", "Badlands", "Caracas", "Vengeance", "The Sluice",
    "Table Top", "Brutal", "Star Wars", "Sidewinder", "Deception",
    "Temptation", "The Dunes", "Jaws", "Entrapment"
]

# ---------------------------------------------------------------------------
# Data fetching
# ---------------------------------------------------------------------------

def fetch_golf_api():
    """Fetch Golf Course API data for Terra Lago."""
    url = f"https://api.golfcourseapi.com/v1/search?{urllib.parse.urlencode({'search_query': 'Terra Lago'})}"
    req = urllib.request.Request(url)
    req.add_header("Authorization", f"Key {GOLF_API_KEY}")
    with urllib.request.urlopen(req, timeout=15) as resp:
        data = json.loads(resp.read())

    courses = data.get("courses", [])
    details = []
    for c in courses[:4]:
        detail_url = f"https://api.golfcourseapi.com/v1/courses/{c['id']}"
        req = urllib.request.Request(detail_url)
        req.add_header("Authorization", f"Key {GOLF_API_KEY}")
        with urllib.request.urlopen(req, timeout=15) as resp:
            d = json.loads(resp.read())
            details.append(d.get("course", d))

    return details


def fetch_overpass():
    """Fetch OSM hole data for Terra Lago."""
    query = f"""[out:json][timeout:30];
    way["golf"="hole"]({FACILITY_LAT-0.015},{FACILITY_LON-0.015},{FACILITY_LAT+0.015},{FACILITY_LON+0.015});
    out tags center;"""

    data = urllib.parse.urlencode({"data": query}).encode()
    req = urllib.request.Request("https://overpass-api.de/api/interpreter", data=data)
    with urllib.request.urlopen(req, timeout=45) as resp:
        return json.loads(resp.read())


def fetch_images():
    """Fetch scorecard and course map images from Terra Lago website."""
    images = {}
    urls = {
        "scorecard": "https://images.squarespace-cdn.com/content/v1/5b4f6ff9e17ba367c23c31cd/1539901295534-29OB8BFT804XLI1FB69B/course_scorecard.jpg",
        "north_map": "https://images.squarespace-cdn.com/content/v1/5b4f6ff9e17ba367c23c31cd/1584202021435-B9M2ELKCYDVBUGHJWGNM/CCF_000047.jpg",
        "south_back9_map": "https://images.squarespace-cdn.com/content/v1/5b4f6ff9e17ba367c23c31cd/1584202029302-OES5R7GRG4031K1K7SS2/CCF_000048.jpg",
    }
    for name, url in urls.items():
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=15) as resp:
            images[name] = resp.read()
        print(f"  Fetched {name}: {len(images[name])} bytes")
    return images


# ---------------------------------------------------------------------------
# Prompt construction
# ---------------------------------------------------------------------------

def build_prompt(osm_data, golf_api_data, images):
    """Build the multimodal prompt for hole assignment."""

    # Summarize OSM holes
    elements = osm_data.get("elements", [])
    holes = [e for e in elements if e.get("tags", {}).get("golf") == "hole"]

    osm_summary = []
    for h in sorted(holes, key=lambda x: int(x.get("tags", {}).get("ref", "0") or "0")):
        tags = h.get("tags", {})
        center = h.get("center", {})
        osm_summary.append(
            f"  ref={tags.get('ref','?'):>2} par={tags.get('par','?'):>2} "
            f"lat={center.get('lat',0):.5f} lon={center.get('lon',0):.5f} "
            f"osm_id={h['id']}"
        )

    # Summarize Golf API data
    api_summary = []
    for c in golf_api_data:
        name = c.get("course_name", "")
        tees = c.get("tees", {})
        pars = []
        for gender in ("male", "female"):
            for tee in tees.get(gender, [])[:1]:
                pars = [h.get("par", 0) for h in tee.get("holes", [])]
                break
            if pars:
                break
        api_summary.append(f"  {name}: pars={pars}")

    prompt = f"""You are a golf course data expert. I need you to assign OSM (OpenStreetMap) hole features to the correct course at a multi-course facility.

## Facility
{FACILITY_NAME} in Indio, CA. This facility has TWO 18-hole courses: North and South.

## Golf Course API Data (authoritative course names and pars)
{chr(10).join(api_summary)}

## Scorecard Data (from the attached scorecard image)
The scorecard image shows both North and South courses with:
- Hole names (e.g., North H1 = "Uphill Battle", South H1 = "Rocky Peak")
- Par for each hole
- Yardages from multiple tees

## Course Maps (from attached images)
- North course map showing holes 1-9 front and partial back nine
- South/back nine map showing holes 10-18 area with clubhouse

## OSM Data ({len(holes)} holes with duplicate numbering — two H1s, two H2s, etc.)
{chr(10).join(osm_summary)}

## Task
Each OSM hole belongs to either North or South. Use ALL available context:
1. The scorecard pars (ground truth)
2. The course map images (spatial layout)
3. The OSM coordinates (lat/lon positions)
4. The par values in OSM tags (when present)

For each OSM hole, determine which course it belongs to. When two holes share the same ref number (e.g., two "hole 7"s), match each to the course whose par at that position agrees.

## Output Format
Return ONLY a JSON object:
{{
  "north": [
    {{"osm_id": 12345, "hole_number": 1, "par": 4, "confidence": "high"}},
    ...
  ],
  "south": [
    {{"osm_id": 67890, "hole_number": 1, "par": 4, "confidence": "high"}},
    ...
  ],
  "reasoning": "Brief explanation of how you matched the holes"
}}

Use confidence: "high" when par matches perfectly, "medium" when inferred from position, "low" when guessing."""

    return prompt


# ---------------------------------------------------------------------------
# Model calls
# ---------------------------------------------------------------------------

def _detect_image_format(img_bytes):
    """Detect image format from magic bytes."""
    if img_bytes[:4] == b"RIFF" and img_bytes[8:12] == b"WEBP":
        return "webp"
    if img_bytes[:3] == b"\xff\xd8\xff":
        return "jpeg"
    if img_bytes[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    return "jpeg"  # fallback


def call_nova_pro(prompt, images):
    """Call Bedrock Nova Pro with multimodal input."""
    client = boto3.client("bedrock-runtime", region_name=BEDROCK_REGION)

    content = []
    for name, img_bytes in images.items():
        fmt = _detect_image_format(img_bytes)
        content.append({
            "image": {
                "format": fmt,
                "source": {"bytes": base64.b64encode(img_bytes).decode()}
            }
        })
    content.append({"text": prompt})

    start = time.perf_counter()
    resp = client.invoke_model(
        modelId=NOVA_PRO_MODEL,
        contentType="application/json",
        accept="application/json",
        body=json.dumps({
            "messages": [{"role": "user", "content": content}],
            "inferenceConfig": {"maxTokens": 4000, "temperature": 0.1},
        }),
    )
    elapsed = time.perf_counter() - start

    result = json.loads(resp["body"].read())
    text = result["output"]["message"]["content"][0]["text"]
    usage = result.get("usage", {})

    return text, elapsed, usage


def call_gpt4o(prompt, images):
    """Call OpenAI GPT-4o with multimodal input."""
    # Get API key
    api_key = os.environ.get("OPENAI_API_KEY", "")
    if not api_key:
        try:
            sm = boto3.client("secretsmanager", region_name=BEDROCK_REGION)
            secret = sm.get_secret_value(SecretId="caddieai/openai-api-key")
            api_key = secret["SecretString"]
        except Exception as e:
            print(f"  Failed to get OpenAI key from Secrets Manager: {e}")
            return None, 0, {}

    content = []
    for name, img_bytes in images.items():
        fmt = _detect_image_format(img_bytes)
        mime = f"image/{fmt}"
        b64 = base64.b64encode(img_bytes).decode()
        content.append({
            "type": "image_url",
            "image_url": {"url": f"data:{mime};base64,{b64}", "detail": "high"}
        })
    content.append({"type": "text", "text": prompt})

    body = json.dumps({
        "model": "gpt-4o",
        "messages": [{"role": "user", "content": content}],
        "max_tokens": 4000,
        "temperature": 0.1,
    }).encode()

    req = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=body,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )

    start = time.perf_counter()
    with urllib.request.urlopen(req, timeout=120) as resp:
        result = json.loads(resp.read())
    elapsed = time.perf_counter() - start

    text = result["choices"][0]["message"]["content"]
    usage = result.get("usage", {})

    return text, elapsed, usage


# ---------------------------------------------------------------------------
# Scoring
# ---------------------------------------------------------------------------

def parse_response(text):
    """Extract JSON from model response."""
    text = text.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[1].rsplit("```", 1)[0]
    return json.loads(text)


def score_assignments(assignments, label):
    """Score assignments against ground truth pars."""
    north = assignments.get("north", [])
    south = assignments.get("south", [])

    north_correct = 0
    south_correct = 0

    for h in north:
        num = h.get("hole_number", 0)
        par = h.get("par", 0)
        if 1 <= num <= 18 and num - 1 < len(NORTH_PARS):
            if NORTH_PARS[num - 1] == par:
                north_correct += 1

    for h in south:
        num = h.get("hole_number", 0)
        par = h.get("par", 0)
        if 1 <= num <= 18 and num - 1 < len(SOUTH_PARS):
            if SOUTH_PARS[num - 1] == par:
                south_correct += 1

    print(f"\n{'='*60}")
    print(f"  {label}")
    print(f"{'='*60}")
    print(f"  North: {len(north)} holes assigned, {north_correct}/18 pars correct")
    print(f"  South: {len(south)} holes assigned, {south_correct}/18 pars correct")
    print(f"  Total: {north_correct + south_correct}/36 correct")

    high = sum(1 for h in north + south if h.get("confidence") == "high")
    med = sum(1 for h in north + south if h.get("confidence") == "medium")
    low = sum(1 for h in north + south if h.get("confidence") == "low")
    print(f"  Confidence: {high} high, {med} medium, {low} low")

    reasoning = assignments.get("reasoning", "")
    if reasoning:
        print(f"  Reasoning: {reasoning[:200]}")

    return north_correct + south_correct


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 60)
    print("  RAG-based Multi-Course Assignment: A/B Test")
    print("  Facility: The Golf Club at Terra Lago")
    print("=" * 60)

    # 1. Fetch data
    print("\n[1/4] Fetching Golf Course API data...")
    golf_api = fetch_golf_api()
    print(f"  Found {len(golf_api)} courses")

    print("\n[2/4] Fetching Overpass OSM data...")
    osm = fetch_overpass()
    holes = [e for e in osm.get("elements", []) if e.get("tags", {}).get("golf") == "hole"]
    print(f"  Found {len(holes)} holes")

    print("\n[3/4] Fetching website images...")
    images = fetch_images()

    # 2. Build prompt
    print("\n[4/4] Building prompt...")
    prompt = build_prompt(osm, golf_api, images)
    print(f"  Prompt length: {len(prompt)} chars")

    # 3. Call models
    print("\n" + "=" * 60)
    print("  Calling Nova Pro (Bedrock)...")
    print("=" * 60)
    nova_text, nova_time, nova_usage = call_nova_pro(prompt, images)
    print(f"  Latency: {nova_time:.1f}s")
    print(f"  Usage: {nova_usage}")

    print("\n" + "=" * 60)
    print("  Calling GPT-4o (OpenAI)...")
    print("=" * 60)
    gpt_text, gpt_time, gpt_usage = call_gpt4o(prompt, images)
    if gpt_text is None:
        print("  SKIPPED — no API key")
    else:
        print(f"  Latency: {gpt_time:.1f}s")
        print(f"  Usage: {gpt_usage}")

    # 4. Score results
    print("\n" + "=" * 60)
    print("  RESULTS")
    print("=" * 60)

    try:
        nova_result = parse_response(nova_text)
        nova_score = score_assignments(nova_result, "Nova Pro")
    except Exception as e:
        print(f"\n  Nova Pro: FAILED TO PARSE — {e}")
        print(f"  Raw: {nova_text[:500]}")
        nova_score = 0
        nova_result = {}

    gpt_score = 0
    gpt_result = {}
    if gpt_text:
        try:
            gpt_result = parse_response(gpt_text)
            gpt_score = score_assignments(gpt_result, "GPT-4o")
        except Exception as e:
            print(f"\n  GPT-4o: FAILED TO PARSE — {e}")
            print(f"  Raw: {gpt_text[:500]}")

    # 5. Save traces to S3
    print("\n" + "=" * 60)
    print("  Saving traces to S3...")
    print("=" * 60)

    trace = {
        "facility": FACILITY_NAME,
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "osm_holes": len(holes),
        "golf_api_courses": len(golf_api),
        "images": list(images.keys()),
        "prompt_length": len(prompt),
        "models": {
            "nova_pro": {
                "latency_s": round(nova_time, 2),
                "usage": nova_usage,
                "score": nova_score,
                "assignments": nova_result,
                "raw_response": nova_text,
            },
            "gpt4o": {
                "latency_s": round(gpt_time, 2) if gpt_text else None,
                "usage": gpt_usage,
                "score": gpt_score,
                "assignments": gpt_result,
                "raw_response": gpt_text,
            },
        },
        "ground_truth": {
            "north_pars": NORTH_PARS,
            "south_pars": SOUTH_PARS,
            "north_hole_names": NORTH_HOLE_NAMES,
            "south_hole_names": SOUTH_HOLE_NAMES,
        },
    }

    s3 = boto3.client("s3", region_name=BEDROCK_REGION)
    s3.put_object(
        Bucket="caddieai-course-cache",
        Key="courses/traces/terra-lago-ab-test.json",
        Body=json.dumps(trace, indent=2).encode(),
        ContentType="application/json",
    )
    print("  Saved to s3://caddieai-course-cache/courses/traces/terra-lago-ab-test.json")

    # 6. Winner
    print("\n" + "=" * 60)
    if nova_score > gpt_score:
        print(f"  WINNER: Nova Pro ({nova_score} vs {gpt_score})")
    elif gpt_score > nova_score:
        print(f"  WINNER: GPT-4o ({gpt_score} vs {nova_score})")
    else:
        print(f"  TIE: Both scored {nova_score}/36")
    print("=" * 60)


if __name__ == "__main__":
    main()
