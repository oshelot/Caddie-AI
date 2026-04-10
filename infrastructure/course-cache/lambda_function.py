"""
CaddieAI Course Cache Lambda

Stores and retrieves NormalizedCourse JSON objects in S3, keyed by courseId
and schema version. Authenticates clients via x-api-key header.

On PUT, validates course metadata via Google Places Text Search (New) API
to correct city/state/name before storing. This ensures accurate location
data regardless of Nominatim/OSM data quality.

Routes:
  GET  /courses/search?q=sharp+park&lat=37.6&lon=-122.5  → fuzzy search manifest
  GET  /courses/search?q=sharp+park&mode=metadata       → manifest metadata only (name, city, state)
  GET  /courses/{courseId}?schema=1.0  → S3 lookup, return JSON (gzip) or 404
  PUT  /courses/{courseId}?schema=1.0  → validate via Google Places, gzip-compress
                                         and store in S3, update manifest

  Optional query param for GET/search:
    platform=android  → converts iOS-format JSON to Android-compatible format
                        (field renaming, geo type restructuring, etc.)
"""

import gzip
import json
import math
import os
import re
import base64
import urllib.request
import urllib.parse

import boto3
from botocore.exceptions import ClientError

# Cached across warm invocations
_s3_client = None
_proxy_api_key: str | None = None
_manifest_cache: list | None = None
_manifest_etag: str | None = None

BUCKET_NAME = os.environ.get("BUCKET_NAME", "caddieai-course-cache")
PROXY_API_KEY_ENV = os.environ.get("PROXY_API_KEY", "")
GOOGLE_PLACES_API_KEY = os.environ.get("GOOGLE_PLACES_API_KEY", "")
MAX_BODY_BYTES = 1_048_576  # 1 MB
MANIFEST_KEY = "courses/manifest.json"

# Words to strip when normalizing course names for fuzzy matching
STRIP_WORDS = {"golf", "course", "club", "country", "cc", "gc", "the", "and", "&", "at", "of"}


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


# ---------------------------------------------------------------------------
# Fuzzy matching helpers
# ---------------------------------------------------------------------------

def normalize_name(name: str) -> str:
    """Lowercase, strip common golf suffixes, collapse whitespace."""
    name = name.lower().strip()
    # Remove apostrophes, quotes, hyphens
    name = re.sub(r"['\"\-]", " ", name)
    tokens = name.split()
    tokens = [t for t in tokens if t not in STRIP_WORDS]
    return " ".join(tokens)


def levenshtein(s1: str, s2: str) -> int:
    """Simple Levenshtein edit distance."""
    if len(s1) < len(s2):
        return levenshtein(s2, s1)
    if len(s2) == 0:
        return len(s1)
    prev_row = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        curr_row = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = prev_row[j + 1] + 1
            deletions = curr_row[j] + 1
            substitutions = prev_row[j] + (c1 != c2)
            curr_row.append(min(insertions, deletions, substitutions))
        prev_row = curr_row
    return prev_row[-1]


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance in km between two points."""
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (math.sin(dlat / 2) ** 2 +
         math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) *
         math.sin(dlon / 2) ** 2)
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def load_manifest(s3) -> list:
    """Load the course manifest from S3, with ETag-based caching."""
    global _manifest_cache, _manifest_etag
    try:
        # Conditional get to avoid re-downloading if unchanged
        kwargs = {"Bucket": BUCKET_NAME, "Key": MANIFEST_KEY}
        if _manifest_etag:
            try:
                obj = s3.get_object(**kwargs, IfNoneMatch=_manifest_etag)
            except ClientError as e:
                if e.response["Error"]["Code"] == "304":
                    return _manifest_cache or []
                if e.response["Error"]["Code"] == "NoSuchKey":
                    return []
                raise
        else:
            try:
                obj = s3.get_object(**kwargs)
            except ClientError as e:
                if e.response["Error"]["Code"] == "NoSuchKey":
                    return []
                raise

        body = obj["Body"].read().decode("utf-8")
        _manifest_cache = json.loads(body)
        _manifest_etag = obj.get("ETag")
        return _manifest_cache
    except Exception:
        return _manifest_cache or []


def update_manifest(s3, course_id: str, name: str, lat: float, lon: float,
                    schema: str, s3_object_key: str,
                    city: str = "", state: str = "", country: str = ""):
    """Add or update a course entry in the manifest."""
    manifest = load_manifest(s3)

    # Remove existing entry for same course_id + schema
    manifest = [e for e in manifest if not (e.get("courseId") == course_id and e.get("schema") == schema)]

    entry = {
        "courseId": course_id,
        "name": name,
        "lat": lat,
        "lon": lon,
        "schema": schema,
        "s3Key": s3_object_key,
    }
    if city:
        entry["city"] = city
    if state:
        entry["state"] = state
    if country:
        entry["country"] = country

    manifest.append(entry)

    body = json.dumps(manifest, separators=(",", ":"))
    s3.put_object(
        Bucket=BUCKET_NAME,
        Key=MANIFEST_KEY,
        Body=body.encode("utf-8"),
        ContentType="application/json",
    )
    # Invalidate cache so next read picks up the new version
    global _manifest_cache, _manifest_etag
    _manifest_cache = manifest
    _manifest_etag = None


def search_manifest(manifest: list, query: str, lat: float | None,
                    lon: float | None, schema: str) -> list:
    """
    Fuzzy search the manifest. Returns up to 5 best matches.

    Scoring: lower is better.
    - Name score: edit distance between normalized query and normalized cached name,
      with a bonus (score of 0) for exact substring match.
    - Distance penalty: km / 100 (so 100km adds 1.0 to score).
    - Results with name score > 5 are filtered out (too different).
    """
    query_norm = normalize_name(query)
    if not query_norm:
        return []

    results = []
    for entry in manifest:
        if entry.get("schema", "1.0") != schema:
            continue

        entry_name_norm = normalize_name(entry.get("name", ""))
        if not entry_name_norm:
            continue

        # Substring match gets score 0
        if query_norm in entry_name_norm or entry_name_norm in query_norm:
            name_score = 0.0
        else:
            name_score = float(levenshtein(query_norm, entry_name_norm))

        # Skip if too different
        if name_score > 5:
            continue

        # Distance penalty
        dist_penalty = 0.0
        if lat is not None and lon is not None:
            entry_lat = entry.get("lat")
            entry_lon = entry.get("lon")
            if entry_lat is not None and entry_lon is not None:
                dist_km = haversine_km(lat, lon, entry_lat, entry_lon)
                dist_penalty = dist_km / 100.0

        total_score = name_score + dist_penalty
        results.append((total_score, entry))

    results.sort(key=lambda x: x[0])
    return [r[1] for r in results[:5]]


# ---------------------------------------------------------------------------
# Google Places validation
# ---------------------------------------------------------------------------

def validate_with_google_places(name: str, lat: float | None, lon: float | None) -> dict | None:
    """
    Call Google Places Text Search to validate/correct a course's name, city,
    state, and coordinates. Returns a dict with verified fields, or None if
    the lookup fails or no API key is configured.
    """
    if not GOOGLE_PLACES_API_KEY:
        return None

    try:
        query = f"{name} golf course"
        params = {
            "textQuery": query,
            "includedType": "golf_course",
            "maxResultCount": 1,
        }

        # If we have coordinates, bias the search toward that location
        if lat is not None and lon is not None:
            params["locationBias"] = {
                "circle": {
                    "center": {"latitude": lat, "longitude": lon},
                    "radius": 50000.0,  # 50km radius
                }
            }

        req_body = json.dumps(params).encode("utf-8")
        url = "https://places.googleapis.com/v1/places:searchText"

        req = urllib.request.Request(url, data=req_body, method="POST")
        req.add_header("Content-Type", "application/json")
        req.add_header("X-Goog-Api-Key", GOOGLE_PLACES_API_KEY)
        req.add_header("X-Goog-FieldMask",
                        "places.displayName,places.formattedAddress,"
                        "places.addressComponents,places.location")

        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode("utf-8"))

        places = data.get("places", [])
        if not places:
            return None

        place = places[0]
        result = {}

        # Extract display name
        display_name = place.get("displayName", {}).get("text")
        if display_name:
            result["name"] = display_name

        # Extract coordinates
        location = place.get("location")
        if location:
            result["lat"] = location.get("latitude")
            result["lon"] = location.get("longitude")

        # Extract city and state from address components
        for component in place.get("addressComponents", []):
            types = component.get("types", [])
            if "locality" in types:
                result["city"] = component.get("longText", "")
            elif "administrative_area_level_1" in types:
                result["state"] = component.get("shortText", "")
            elif "country" in types:
                result["country"] = component.get("shortText", "")

        result["formattedAddress"] = place.get("formattedAddress", "")
        return result

    except Exception as e:
        print(f"Google Places validation failed for '{name}': {e}")
        return None


# ---------------------------------------------------------------------------
# Cross-platform normalization (iOS JSON → Android JSON)
# ---------------------------------------------------------------------------

def _lonlat_to_geopoint(coord: list) -> dict:
    """Convert a [lon, lat] coordinate pair to {latitude, longitude}."""
    return {"latitude": coord[1], "longitude": coord[0]}


def _ring_to_geopoints(ring: list) -> list:
    """Convert a ring of [[lon, lat], ...] to [{latitude, longitude}, ...]."""
    return [_lonlat_to_geopoint(c) for c in ring]


def _polygon_to_android(poly: dict) -> dict | None:
    """Convert iOS GeoJSONPolygon {coordinates: [[[lon,lat]...]]} to
    Android GeoPolygon {outerRing: [{lat,lon}...], holes: [[{lat,lon}...]]}."""
    coords = poly.get("coordinates")
    if not coords or not isinstance(coords, list) or len(coords) == 0:
        return None
    outer_ring = _ring_to_geopoints(coords[0])
    holes = [_ring_to_geopoints(ring) for ring in coords[1:]]
    return {"outerRing": outer_ring, "holes": holes}


def _linestring_to_android(ls: dict) -> dict | None:
    """Convert iOS GeoJSONLineString {coordinates: [[lon,lat]...]} to
    Android GeoLineString {points: [{lat,lon}...]}."""
    coords = ls.get("coordinates")
    if not coords or not isinstance(coords, list):
        return None
    return {"points": [_lonlat_to_geopoint(c) for c in coords]}


def _tee_areas_to_tee_box(tee_areas: list) -> dict | None:
    """Convert iOS teeAreas (array of GeoJSONPolygon) to a single Android
    GeoPoint teeBox by computing the centroid of the first tee area's outer ring."""
    if not tee_areas:
        return None
    first = tee_areas[0]
    coords = first.get("coordinates")
    if not coords or not isinstance(coords, list) or len(coords) == 0:
        return None
    ring = coords[0]
    if not ring:
        return None
    avg_lon = sum(c[0] for c in ring) / len(ring)
    avg_lat = sum(c[1] for c in ring) / len(ring)
    return {"latitude": avg_lat, "longitude": avg_lon}


def _convert_hazards(bunkers: list, water: list) -> list:
    """Convert iOS bunkers/water arrays (GeoJSONPolygon[]) to Android
    hazards list [{type, boundary, location}]."""
    hazards = []
    for b in bunkers:
        poly = _polygon_to_android(b)
        if poly:
            hazards.append({"type": "BUNKER", "label": "", "boundary": poly})
    for w in water:
        poly = _polygon_to_android(w)
        if poly:
            hazards.append({"type": "WATER", "label": "", "boundary": poly})
    return hazards


def _convert_hole(ios_hole: dict, tee_names: list | None) -> dict:
    """Convert an iOS NormalizedHole to Android Hole format."""
    number = ios_hole.get("number", 0)
    par = ios_hole.get("par") or 0

    # Yardage: pick first tee from yardages map, or 0
    yardage = 0
    yardages = ios_hole.get("yardages")
    if isinstance(yardages, dict) and yardages:
        # Prefer first tee name from course if available, else first key
        if tee_names:
            for tn in tee_names:
                if tn in yardages:
                    yardage = yardages[tn]
                    break
            else:
                yardage = next(iter(yardages.values()))
        else:
            yardage = next(iter(yardages.values()))

    hole = {
        "number": number,
        "par": par,
        "yardage": yardage,
        "handicapIndex": ios_hole.get("strokeIndex") or number,
        "pin": ios_hole.get("pin"),  # Already {latitude, longitude}
        "notes": "",
    }

    # teeAreas → teeBox
    tee_areas = ios_hole.get("teeAreas", [])
    hole["teeBox"] = _tee_areas_to_tee_box(tee_areas)

    # lineOfPlay → fairwayCenterLine
    lop = ios_hole.get("lineOfPlay")
    hole["fairwayCenterLine"] = _linestring_to_android(lop) if lop else None

    # green polygon
    green = ios_hole.get("green")
    hole["green"] = _polygon_to_android(green) if green else None

    # bunkers + water → hazards
    bunkers = ios_hole.get("bunkers", [])
    water = ios_hole.get("water", [])
    hole["hazards"] = _convert_hazards(bunkers, water)

    return hole


def normalize_course_for_android(course: dict) -> dict:
    """
    Convert an iOS NormalizedCourse JSON dict to Android NormalizedCourse format.
    If the course is already in Android format (no 'lineOfPlay' in holes, source is
    a string), returns it as-is.
    """
    # Detect if this is iOS format (source is an object, not a string)
    source = course.get("source", "")
    if isinstance(source, str):
        # Already Android-compatible or simple format — return as-is
        return course

    tee_names = course.get("teeNames") or []

    # Build holeYardagesByTee from holes' yardages maps
    hole_yardages_by_tee: dict = {}
    ios_holes = course.get("holes", [])
    for h in ios_holes:
        yardages = h.get("yardages")
        if isinstance(yardages, dict):
            for tee_name, yd in yardages.items():
                if tee_name not in hole_yardages_by_tee:
                    hole_yardages_by_tee[tee_name] = {}
                hole_yardages_by_tee[tee_name][str(h.get("number", 0))] = yd

    # Source: object → string (just the provider)
    source_str = source.get("provider", "osm") if isinstance(source, dict) else str(source)

    # Schema version: string → int
    schema_str = course.get("schemaVersion", "1.0")
    try:
        schema_int = int(float(schema_str))
    except (ValueError, TypeError):
        schema_int = 1

    # Confidence: stats.overallConfidence → confidenceScore
    confidence = 1.0
    stats = course.get("stats")
    if isinstance(stats, dict):
        confidence = stats.get("overallConfidence", 1.0)

    android = {
        "id": course.get("id", ""),
        "name": course.get("name", ""),
        "city": course.get("city", ""),
        "state": course.get("state", ""),
        "country": course.get("country", "US"),
        "holes": [_convert_hole(h, tee_names) for h in ios_holes],
        "confidenceScore": confidence,
        "source": source_str,
        "cachedAtMs": 0,  # Android will set this on save
        "teeNames": tee_names,
        "holeYardagesByTee": hole_yardages_by_tee,
        "schemaVersion": schema_int,
    }

    return android


# ---------------------------------------------------------------------------
# Route handlers
# ---------------------------------------------------------------------------

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

    # Route: /courses/search → fuzzy search
    if course_id == "search" and http_method == "GET":
        return handle_search(event)

    if not course_id:
        return error_response(400, "Missing courseId in path.")

    # Extract schema version from query params
    query_params = event.get("queryStringParameters") or {}
    schema = query_params.get("schema", "1.0")

    s3 = get_s3_client()
    key = s3_key(schema, course_id)

    platform = query_params.get("platform", "")

    if http_method == "GET":
        return handle_get(s3, key, course_id, platform)
    elif http_method == "PUT":
        return handle_put(s3, key, course_id, event, schema)
    else:
        return error_response(405, f"Method {http_method} not allowed.")


def handle_search(event: dict) -> dict:
    """Fuzzy search for a cached course by name + optional coordinates."""
    query_params = event.get("queryStringParameters") or {}
    query = query_params.get("q", "").strip()
    if not query:
        return error_response(400, "Missing 'q' query parameter.")

    schema = query_params.get("schema", "1.0")
    platform = query_params.get("platform", "")

    lat = None
    lon = None
    try:
        lat_str = query_params.get("lat")
        lon_str = query_params.get("lon")
        if lat_str and lon_str:
            lat = float(lat_str)
            lon = float(lon_str)
    except (ValueError, TypeError):
        pass

    s3 = get_s3_client()
    manifest = load_manifest(s3)
    matches = search_manifest(manifest, query, lat, lon, schema)

    if not matches:
        return error_response(404, "No matching courses found.")

    # mode=metadata: return just manifest metadata (name, city, state) for all
    # matches — no S3 fetch. Used by clients to correct Nominatim city/state.
    mode = query_params.get("mode", "")
    if mode == "metadata":
        entries = [
            {
                "name": m.get("name", ""),
                "city": m.get("city", ""),
                "state": m.get("state", ""),
                "lat": m.get("lat"),
                "lon": m.get("lon"),
                "courseId": m.get("courseId", ""),
            }
            for m in matches
        ]
        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
                "Cache-Control": "public, max-age=3600",
            },
            "body": json.dumps(entries, separators=(",", ":")),
        }

    # Return the best match's full course data
    best = matches[0]
    best_s3_key = best.get("s3Key") or s3_key(schema, best["courseId"])

    try:
        obj = s3.get_object(Bucket=BUCKET_NAME, Key=best_s3_key)
        compressed_body = obj["Body"].read()

        # Platform-specific normalization
        if platform == "android":
            course_json = json.loads(gzip.decompress(compressed_body).decode("utf-8"))
            course_json = normalize_course_for_android(course_json)
            compressed_body = gzip.compress(json.dumps(course_json, separators=(",", ":")).encode("utf-8"))

        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json",
                "Content-Encoding": "gzip",
                "Access-Control-Allow-Origin": "*",
                "Cache-Control": "public, max-age=86400",
                "X-Cache-Course-Id": best.get("courseId", ""),
                "X-Cache-Course-Name": best.get("name", ""),
                "X-Cache-Course-City": best.get("city", ""),
                "X-Cache-Course-State": best.get("state", ""),
            },
            "body": base64.b64encode(compressed_body).decode("utf-8"),
            "isBase64Encoded": True,
        }
    except ClientError as e:
        if e.response["Error"]["Code"] == "NoSuchKey":
            return error_response(404, f"Course data not found for match: {best.get('name')}")
        raise


def handle_get(s3, key: str, course_id: str, platform: str = "") -> dict:
    try:
        obj = s3.get_object(Bucket=BUCKET_NAME, Key=key)
        compressed_body = obj["Body"].read()

        # Platform-specific normalization
        if platform == "android":
            course_json = json.loads(gzip.decompress(compressed_body).decode("utf-8"))
            course_json = normalize_course_for_android(course_json)
            compressed_body = gzip.compress(json.dumps(course_json, separators=(",", ":")).encode("utf-8"))

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


def handle_put(s3, key: str, course_id: str, event: dict, schema: str) -> dict:
    # Parse body
    body_str = event.get("body", "")
    if event.get("isBase64Encoded"):
        body_str = base64.b64decode(body_str).decode("utf-8")

    if not body_str:
        return error_response(400, "Empty request body.")

    body_bytes = body_str.encode("utf-8")
    if len(body_bytes) > MAX_BODY_BYTES:
        return error_response(413, f"Payload too large. Max {MAX_BODY_BYTES} bytes.")

    # Validate JSON and extract metadata for manifest
    try:
        course_data = json.loads(body_str)
    except json.JSONDecodeError:
        return error_response(400, "Invalid JSON in request body.")

    # Extract course metadata for manifest and Google validation
    name = course_data.get("name", course_id)
    lat = None
    lon = None

    # Try to extract centroid from the course data
    centroid = course_data.get("centroid")
    if isinstance(centroid, dict):
        lat = centroid.get("latitude")
        lon = centroid.get("longitude")

    # Fallback: compute centroid from bounding box
    if lat is None or lon is None:
        bbox = course_data.get("boundingBox")
        if isinstance(bbox, dict):
            s_val = bbox.get("south")
            n_val = bbox.get("north")
            w_val = bbox.get("west")
            e_val = bbox.get("east")
            if all(v is not None for v in [s_val, n_val, w_val, e_val]):
                lat = (s_val + n_val) / 2
                lon = (w_val + e_val) / 2

    # Fallback: try first hole's tee or pin
    if lat is None or lon is None:
        holes = course_data.get("holes", [])
        for hole in holes:
            pin = hole.get("pin")
            if isinstance(pin, dict) and "latitude" in pin:
                lat = pin["latitude"]
                lon = pin["longitude"]
                break
            tee = hole.get("teeBox")
            if isinstance(tee, dict) and "latitude" in tee:
                lat = tee["latitude"]
                lon = tee["longitude"]
                break

    # Validate and enrich with Google Places
    city = course_data.get("city", "")
    state = course_data.get("state", "")
    country = course_data.get("country", "")
    google_validated = False

    places_result = validate_with_google_places(name, lat, lon)
    if places_result:
        google_validated = True
        # Always use Google's city/state — it's more accurate than Nominatim/OSM
        if places_result.get("city"):
            city = places_result["city"]
            course_data["city"] = city
        if places_result.get("state"):
            state = places_result["state"]
            course_data["state"] = state
        if places_result.get("country"):
            country = places_result["country"]
            course_data["country"] = country
        # Use Google's verified name if it looks like a match
        google_name = places_result.get("name", "")
        if google_name and normalize_name(google_name) == normalize_name(name):
            course_data["name"] = google_name
            name = google_name
        print(f"Google Places validated '{name}': city={city}, state={state}")
    else:
        print(f"Google Places validation unavailable for '{name}', using client-provided metadata")

    # Gzip compress and store (with Google-corrected fields)
    corrected_body = json.dumps(course_data).encode("utf-8")
    compressed = gzip.compress(corrected_body)
    s3.put_object(
        Bucket=BUCKET_NAME,
        Key=key,
        Body=compressed,
        ContentType="application/json",
        ContentEncoding="gzip",
    )

    try:
        update_manifest(s3, course_id, name, lat, lon, schema, key,
                        city=city, state=state, country=country)
    except Exception as e:
        # Non-fatal — course is stored, manifest update failed
        print(f"Warning: manifest update failed for {course_id}: {e}")

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
            "manifestUpdated": True,
            "googleValidated": google_validated,
            "city": city,
            "state": state,
        }),
    }
