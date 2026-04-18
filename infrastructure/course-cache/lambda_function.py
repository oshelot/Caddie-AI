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
from collections import OrderedDict

import boto3
from botocore.exceptions import ClientError

# Cached across warm invocations
_s3_client = None
_proxy_api_key: str | None = None
_manifest_cache: list | None = None
_manifest_etag: str | None = None

# KAN-296: in-memory FIFO cache for Google Places proxy responses. Shared
# across warm invocations of the same Lambda container so we don't pay
# Google for every keystroke. Cleared on cold start, which is fine — the
# cache is purely a cost optimization.
_places_cache: "OrderedDict[str, list]" = OrderedDict()
_PLACES_CACHE_MAX = 256

BUCKET_NAME = os.environ.get("BUCKET_NAME", "caddieai-course-cache")
PROXY_API_KEY_ENV = os.environ.get("PROXY_API_KEY", "")
GOOGLE_PLACES_API_KEY = os.environ.get("GOOGLE_PLACES_API_KEY", "")
MAPBOX_TOKEN = os.environ.get("MAPBOX_TOKEN", "")
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
# Google Places proxy (KAN-296) — autocomplete + text search
# ---------------------------------------------------------------------------
#
# These two helpers expose the existing GOOGLE_PLACES_API_KEY env var as
# read-only proxy routes for the Flutter mobile client. iOS uses Apple
# MapKit's MKLocalSearchCompleter (cities) and MKLocalSearch (course names)
# but neither is available on Android/Flutter. The proxy routes give the
# Flutter port a cross-platform replacement without bundling a Google API
# key in the app.

def _places_cache_get(key: str):
    if key in _places_cache:
        _places_cache.move_to_end(key)
        return _places_cache[key]
    return None


def _places_cache_put(key: str, value: list):
    _places_cache[key] = value
    _places_cache.move_to_end(key)
    while len(_places_cache) > _PLACES_CACHE_MAX:
        _places_cache.popitem(last=False)


def google_places_autocomplete(query: str) -> list:
    """Call Google Places Autocomplete (New) for city/region suggestions.

    Restricted to localities + administrative areas so the autocomplete
    only returns places (not businesses, addresses, or POIs).
    Returns a list of {description, mainText, secondaryText} dicts.
    """
    if not GOOGLE_PLACES_API_KEY or not query:
        return []

    try:
        params = {
            "input": query,
            "includedPrimaryTypes": [
                "locality",
                "administrative_area_level_3",
                "administrative_area_level_2",
            ],
        }
        req_body = json.dumps(params).encode("utf-8")
        url = "https://places.googleapis.com/v1/places:autocomplete"

        req = urllib.request.Request(url, data=req_body, method="POST")
        req.add_header("Content-Type", "application/json")
        req.add_header("X-Goog-Api-Key", GOOGLE_PLACES_API_KEY)

        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode("utf-8"))

        out = []
        for s in data.get("suggestions", [])[:5]:
            pred = s.get("placePrediction") or {}
            text = (pred.get("text") or {}).get("text", "")
            structured = pred.get("structuredFormat") or {}
            main = (structured.get("mainText") or {}).get("text", "")
            secondary = (structured.get("secondaryText") or {}).get("text", "")
            if text:
                out.append({
                    "description": text,
                    "mainText": main,
                    "secondaryText": secondary,
                })
        return out
    except Exception as e:
        print(f"Places autocomplete failed for '{query}': {e}")
        return []


def google_places_text_search(query: str, lat: float | None = None,
                               lon: float | None = None) -> list:
    """Call Google Places Text Search (New) for golf courses.

    Returns a list of course-like dicts (id, name, city, state, lat, lon,
    formattedAddress). Capped to 10 results to keep payloads small —
    matches the iOS MapKit search size.
    """
    if not GOOGLE_PLACES_API_KEY or not query:
        return []

    try:
        params = {
            "textQuery": f"golf course {query}",
            "includedType": "golf_course",
            "maxResultCount": 10,
        }
        if lat is not None and lon is not None:
            params["locationBias"] = {
                "circle": {
                    "center": {"latitude": lat, "longitude": lon},
                    "radius": 50000.0,
                }
            }

        req_body = json.dumps(params).encode("utf-8")
        url = "https://places.googleapis.com/v1/places:searchText"

        req = urllib.request.Request(url, data=req_body, method="POST")
        req.add_header("Content-Type", "application/json")
        req.add_header("X-Goog-Api-Key", GOOGLE_PLACES_API_KEY)
        req.add_header(
            "X-Goog-FieldMask",
            "places.id,places.displayName,places.formattedAddress,"
            "places.addressComponents,places.location",
        )

        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode("utf-8"))

        out = []
        for place in data.get("places", []):
            name = (place.get("displayName") or {}).get("text", "")
            location = place.get("location") or {}
            place_lat = location.get("latitude")
            place_lon = location.get("longitude")
            if not name or place_lat is None or place_lon is None:
                continue

            city = ""
            state = ""
            for comp in place.get("addressComponents", []):
                types = comp.get("types", [])
                if "locality" in types and not city:
                    city = comp.get("longText", "")
                elif "administrative_area_level_1" in types and not state:
                    state = comp.get("shortText", "")

            out.append({
                "id": place.get("id", ""),
                "name": name,
                "city": city,
                "state": state,
                "lat": place_lat,
                "lon": place_lon,
                "formattedAddress": place.get("formattedAddress", ""),
            })
        return out
    except Exception as e:
        print(f"Places text search failed for '{query}': {e}")
        return []


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
# Golf Course API helpers (for async multi-course ingestion)
# ---------------------------------------------------------------------------

GOLF_COURSE_API_KEY = os.environ.get("GOLF_COURSE_API_KEY", "")
GOLF_COURSE_API_BASE = "https://api.golfcourseapi.com/v1"

# Suffixes stripped during retry search — mirrors the Flutter client.
_GOLF_API_SUFFIXES = [
    "Golf & Country Club", "Municipal Golf Course", "Public Golf Course",
    "Country Club", "Golf Course", "Golf Links", "Golf Club",
]


def golf_api_search(name: str) -> list:
    """Search the Golf Course API by course name with suffix-retry."""
    results = _golf_api_search_once(name)
    if results:
        return results
    lower = name.lower()
    for suffix in _GOLF_API_SUFFIXES:
        if lower.endswith(suffix.lower()):
            stripped = name[:len(name) - len(suffix)].strip()
            if stripped:
                results = _golf_api_search_once(stripped)
                if results:
                    return results
    return []


def _golf_api_search_once(query: str) -> list:
    url = f"{GOLF_COURSE_API_BASE}/search?{urllib.parse.urlencode({'search_query': query})}"
    req = urllib.request.Request(url)
    req.add_header("Authorization", f"Key {GOLF_COURSE_API_KEY}")
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data.get("courses", [])
    except Exception as e:
        print(f"Golf API search failed for '{query}': {e}")
        return []


def golf_api_detail(course_id: int) -> dict | None:
    """Fetch full course detail by Golf Course API id."""
    url = f"{GOLF_COURSE_API_BASE}/courses/{course_id}"
    req = urllib.request.Request(url)
    req.add_header("Authorization", f"Key {GOLF_COURSE_API_KEY}")
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data.get("course", data)
    except Exception as e:
        print(f"Golf API detail failed for id={course_id}: {e}")
        return None


def _extract_par_sequence(api_course: dict) -> list[int]:
    """Extract par sequence from any tee of a Golf Course API result."""
    tees = api_course.get("tees", {})
    for gender in ("male", "female"):
        gender_tees = tees.get(gender, [])
        if isinstance(gender_tees, list) and gender_tees:
            holes = gender_tees[0].get("holes", [])
            return [h.get("par", 4) for h in holes]
    return []


# ---------------------------------------------------------------------------
# Multi-course algorithms (Python port of Dart CourseMatcher + Normalizer)
# ---------------------------------------------------------------------------

def extract_courses(api_details: list[dict]) -> list[dict]:
    """Extract individual named courses from Golf Course API results.

    Handles two patterns:
    - Standalone: "North", "South" → used directly
    - Combos: "West-Lind", "West-Creek", "Lind-Creek" → decomposed
      into individual 9s: West, Lind, Creek
    """
    if len(api_details) < 2:
        return api_details

    combo_parts: dict[str, list] = {}
    is_combos = True

    for detail in api_details:
        name = (detail.get("course_name") or detail.get("courseName", "")).strip()
        parts = [p.strip() for p in name.split("-")]
        if len(parts) != 2 or not parts[0] or not parts[1]:
            is_combos = False
            break
        combo_parts.setdefault(parts[0], []).append({"detail": detail, "is_front": True})
        combo_parts.setdefault(parts[1], []).append({"detail": detail, "is_front": False})

    if is_combos and len(combo_parts) >= 2:
        # Validate: each sub-name should appear in at least 2 combos
        valid = sum(1 for v in combo_parts.values() if len(v) >= 2)
        if valid >= 2:
            return _extract_from_combos(combo_parts)

    # Standard pattern: return as-is with par sequences
    return [
        {"name": (d.get("course_name") or d.get("courseName", "")),
         "pars": _extract_par_sequence(d), "detail": d}
        for d in api_details
    ]


def _extract_from_combos(combo_parts: dict) -> list[dict]:
    results = []
    for sub_name, appearances in combo_parts.items():
        pars = None
        source_detail = None
        front_or_back = None
        for combo in appearances:
            detail = combo["detail"]
            full_pars = _extract_par_sequence(detail)
            if len(full_pars) < 18:
                continue
            half = full_pars[:9] if combo["is_front"] else full_pars[9:18]
            if pars is None:
                pars = half
                source_detail = detail
                front_or_back = "front" if combo["is_front"] else "back"
        if pars is not None:
            results.append({
                "name": sub_name,
                "pars": pars,
                "detail": source_detail,
                "front_or_back": front_or_back,
            })
    return results


def split_by_par_sequence(course_json: dict, par_sequences: list[list[int]]) -> list[dict]:
    """Split a multi-course facility's holes into separate courses
    using par sequences from the Golf Course API.

    Each hole is assigned to the API course whose par at that hole
    number matches. Works for both interleaved courses (Terra Lago)
    and combo 9-hole courses (Kennedy).
    """
    holes = course_json.get("holes", [])
    course_count = len(par_sequences)
    buckets: list[list[dict]] = [[] for _ in range(course_count)]

    # Group holes by number
    by_number: dict[int, list[dict]] = {}
    for h in holes:
        num = h.get("number", 0)
        by_number.setdefault(num, []).append(h)

    for hole_num, candidates in by_number.items():
        if len(candidates) == 1:
            # Unique hole — assign to first matching par
            h = candidates[0]
            assigned = False
            for ci in range(course_count):
                seq = par_sequences[ci]
                if hole_num - 1 < len(seq) and seq[hole_num - 1] == h.get("par", 0):
                    buckets[ci].append(h)
                    assigned = True
                    break
            if not assigned:
                buckets[0].append(h)
        else:
            # Duplicate — match each to a different API course by par
            used_courses: set[int] = set()
            unmatched = []
            for h in candidates:
                matched = False
                for ci in range(course_count):
                    if ci in used_courses:
                        continue
                    seq = par_sequences[ci]
                    if hole_num - 1 < len(seq) and seq[hole_num - 1] == h.get("par", 0):
                        buckets[ci].append(h)
                        used_courses.add(ci)
                        matched = True
                        break
                if not matched:
                    unmatched.append(h)
            for h in unmatched:
                for ci in range(course_count):
                    if ci not in used_courses:
                        buckets[ci].append(h)
                        used_courses.add(ci)
                        break

    # Build sub-course JSON objects
    results = []
    for i, bucket in enumerate(buckets):
        if not bucket:
            continue
        bucket.sort(key=lambda h: h.get("number", 0))
        # Compute centroid from hole geometry
        lats, lons = [], []
        for h in bucket:
            pin = h.get("pin")
            if isinstance(pin, dict) and "latitude" in pin:
                lats.append(pin["latitude"])
                lons.append(pin["longitude"])
            lop = h.get("lineOfPlay")
            if isinstance(lop, dict):
                for coord in (lop.get("coordinates") or []):
                    if isinstance(coord, list) and len(coord) >= 2:
                        lons.append(coord[0])
                        lats.append(coord[1])

        centroid_lat = sum(lats) / len(lats) if lats else 0
        centroid_lon = sum(lons) / len(lons) if lons else 0

        results.append({
            "id": f"{course_json.get('id', '')}_{i}",
            "name": course_json.get("name", ""),
            "city": course_json.get("city", ""),
            "state": course_json.get("state", ""),
            "centroid": {"latitude": centroid_lat, "longitude": centroid_lon},
            "holes": bucket,
            "teeNames": [],
            "teeYardageTotals": {},
        })

    return results


def enrich_with_tee_data(course_json: dict, api_detail: dict,
                          front_or_back: str | None = None) -> dict:
    """Enrich a course with tee/yardage data from a Golf API detail."""
    tees_raw = api_detail.get("tees", {})
    tees: dict[str, dict] = {}
    for gender in ("male", "female"):
        for tee in (tees_raw.get(gender) or []):
            tee_name = re.sub(r"\s+\d{3,}\s*$", "", tee.get("tee_name", "")).strip()
            key = tee_name.lower()
            if key not in tees:
                tees[key] = {"name": tee_name, "tee": tee}

    tee_names = []
    tee_yardage_totals = {}
    for info in tees.values():
        tee = info["tee"]
        tee_names.append(info["name"])
        total = tee.get("total_yards", 0)
        if total:
            tee_yardage_totals[info["name"]] = total

    # Sort by yardage descending
    tee_names.sort(key=lambda n: tee_yardage_totals.get(n, 0), reverse=True)

    # Determine hole offset for combo 9s
    hole_offset = 9 if front_or_back == "back" else 0

    enriched_holes = []
    for hole in course_json.get("holes", []):
        h = dict(hole)  # shallow copy
        yardages = dict(h.get("yardages", {}))
        par = h.get("par", 0)
        stroke_index = h.get("strokeIndex")
        hole_num = h.get("number", 0)
        # Map to API hole index (for combo 9s, offset by 9)
        api_idx = (hole_num - 1) + hole_offset

        for info in tees.values():
            tee = info["tee"]
            api_holes = tee.get("holes", [])
            if api_idx < len(api_holes):
                api_hole = api_holes[api_idx]
                yardages[info["name"]] = api_hole.get("yardage", 0)
                if par == 0:
                    par = api_hole.get("par", 0)
                if stroke_index is None:
                    stroke_index = api_hole.get("handicap")

        h["yardages"] = yardages
        h["par"] = par
        h["strokeIndex"] = stroke_index
        enriched_holes.append(h)

    course_json["holes"] = enriched_holes
    course_json["teeNames"] = tee_names
    course_json["teeYardageTotals"] = tee_yardage_totals
    return course_json


# ---------------------------------------------------------------------------
# Satellite vision gap-filler (fills missing holes via Bedrock + Mapbox)
# ---------------------------------------------------------------------------

def _find_missing_holes(sub_courses: list[dict], extracted: list[dict]) -> list[dict]:
    """Identify holes that exist in the Golf API data but are missing
    from the split OSM courses. Returns a list of gap descriptors."""
    gaps = []
    for i, sub in enumerate(sub_courses):
        ext = extracted[i] if i < len(extracted) else None
        if not ext:
            continue
        assigned_numbers = {h.get("number", 0) for h in sub.get("holes", [])}
        expected_count = len(ext["pars"])
        for hole_num in range(1, expected_count + 1):
            if hole_num not in assigned_numbers:
                par = ext["pars"][hole_num - 1] if hole_num - 1 < len(ext["pars"]) else 0
                gaps.append({
                    "course_name": ext["name"],
                    "course_index": i,
                    "hole_number": hole_num,
                    "par": par,
                })
    return gaps


def _fetch_satellite_image(lat: float, lon: float) -> bytes | None:
    """Fetch a satellite image from Mapbox centered on the given coords."""
    if not MAPBOX_TOKEN:
        print("VISION: no MAPBOX_TOKEN configured")
        return None
    url = (f"https://api.mapbox.com/styles/v1/mapbox/satellite-v9/static/"
           f"{lon},{lat},15.5,0/1280x1280@2x?access_token={MAPBOX_TOKEN}")
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=15) as resp:
            return resp.read()
    except Exception as e:
        print(f"VISION: satellite fetch failed: {e}")
        return None


def _image_bounds(lat: float, lon: float) -> dict:
    """Approximate lat/lon bounds for a 1280x1280@2x Mapbox static
    image at zoom 15.5 centered on (lat, lon)."""
    # At zoom 15.5, the tile covers roughly 0.018 degrees lat/lon
    # for a 1280px image at 2x.
    span_lat = 0.0091
    span_lon = 0.012
    return {
        "top_left_lat": lat + span_lat,
        "top_left_lon": lon - span_lon,
        "bottom_right_lat": lat - span_lat,
        "bottom_right_lon": lon + span_lon,
    }


def fill_missing_holes_with_vision(
    sub_courses: list[dict],
    extracted: list[dict],
    facility_lat: float,
    facility_lon: float,
) -> list[dict]:
    """Use satellite imagery + Bedrock Nova Pro to locate missing
    holes and synthesize basic geometry (tee + green coordinates)."""
    gaps = _find_missing_holes(sub_courses, extracted)
    if not gaps:
        print("VISION: no missing holes to fill")
        return sub_courses

    print(f"VISION: {len(gaps)} missing holes to locate: "
          f"{[(g['course_name'], g['hole_number']) for g in gaps]}")

    # Fetch satellite image
    img_bytes = _fetch_satellite_image(facility_lat, facility_lon)
    if not img_bytes:
        return sub_courses

    bounds = _image_bounds(facility_lat, facility_lon)

    # Build the gap description for the prompt
    gap_descriptions = []
    for g in gaps:
        # Find nearby assigned holes for spatial context
        sub = sub_courses[g["course_index"]]
        nearby = []
        for h in sub.get("holes", []):
            pin = h.get("pin")
            lop = h.get("lineOfPlay")
            if pin and "latitude" in pin:
                nearby.append(f"hole {h['number']} at lat={pin['latitude']:.5f}, lon={pin['longitude']:.5f}")
            elif lop and lop.get("coordinates"):
                coords = lop["coordinates"]
                mid = coords[len(coords)//2]
                nearby.append(f"hole {h['number']} near lon={mid[0]:.5f}, lat={mid[1]:.5f}")

        context = f" Nearby mapped holes: {', '.join(nearby[:3])}." if nearby else ""
        gap_descriptions.append(
            f"- {g['course_name']} Hole {g['hole_number']}: par {g['par']}.{context}"
        )

    prompt = f"""This satellite image shows a golf course facility.
Image bounds:
- Top-left: lat={bounds['top_left_lat']:.4f}, lon={bounds['top_left_lon']:.4f}
- Bottom-right: lat={bounds['bottom_right_lat']:.4f}, lon={bounds['bottom_right_lon']:.4f}

I have mapped most holes from OSM data, but these specific holes are MISSING and I need you to find them in the satellite image:

{chr(10).join(gap_descriptions)}

Look for unmapped fairway corridors and greens visible in the satellite image. Use the image bounds to estimate coordinates. For each missing hole, return the approximate tee and green locations.

Return ONLY a JSON array:
[{{"course": "...", "hole": N, "par": N, "tee_lat": N, "tee_lon": N, "green_lat": N, "green_lon": N}}]

If you cannot confidently locate a hole, omit it from the array."""

    try:
        bedrock = boto3.client("bedrock-runtime",
                               region_name=os.environ.get("AWS_REGION", "us-east-2"))
        resp = bedrock.invoke_model(
            modelId="us.amazon.nova-pro-v1:0",
            contentType="application/json",
            accept="application/json",
            body=json.dumps({
                "messages": [{"role": "user", "content": [
                    {"image": {"format": "jpeg",
                               "source": {"bytes": base64.b64encode(img_bytes).decode()}}},
                    {"text": prompt},
                ]}],
                "inferenceConfig": {"maxTokens": 2000},
            }),
        )
        result = json.loads(resp["body"].read())
        text = result["output"]["message"]["content"][0]["text"]

        # Parse JSON from response (may be wrapped in ```json blocks)
        text = text.strip()
        if text.startswith("```"):
            text = text.split("\n", 1)[1].rsplit("```", 1)[0]
        found_holes = json.loads(text)
        print(f"VISION: LLM located {len(found_holes)} of {len(gaps)} missing holes")

    except Exception as e:
        print(f"VISION: Bedrock call failed: {e}")
        return sub_courses

    # Merge found holes into the sub-courses
    for fh in found_holes:
        course_name = fh.get("course", "")
        hole_num = fh.get("hole", 0)
        tee_lat = fh.get("tee_lat")
        tee_lon = fh.get("tee_lon")
        green_lat = fh.get("green_lat")
        green_lon = fh.get("green_lon")
        par = fh.get("par", 0)

        if not all([tee_lat, tee_lon, green_lat, green_lon]):
            continue

        # Find the matching sub-course
        target_idx = None
        for g in gaps:
            if g["course_name"] == course_name and g["hole_number"] == hole_num:
                target_idx = g["course_index"]
                break
        if target_idx is None:
            continue

        # Build a minimal hole with line-of-play from tee to green
        new_hole = {
            "number": hole_num,
            "par": par,
            "strokeIndex": None,
            "yardages": {},
            "lineOfPlay": {
                "coordinates": [[tee_lon, tee_lat], [green_lon, green_lat]]
            },
            "green": None,
            "pin": {"latitude": green_lat, "longitude": green_lon},
            "teeAreas": [],
            "bunkers": [],
            "water": [],
            "_synthesized": True,  # Flag so the app can style differently
        }

        sub_courses[target_idx].setdefault("holes", []).append(new_hole)
        sub_courses[target_idx]["holes"].sort(key=lambda h: h.get("number", 0))
        print(f"VISION: added {course_name} hole {hole_num} "
              f"(tee={tee_lat:.5f},{tee_lon:.5f} green={green_lat:.5f},{green_lon:.5f})")

    return sub_courses


def _llm_assign_holes(
    course_json: dict,
    extracted: list[dict],
    facility_lat: float,
    facility_lon: float,
) -> list[dict] | None:
    """Use Bedrock Nova Pro to assign all OSM holes to the correct
    courses AND locate any missing holes via satellite imagery.
    Returns a list of sub-course dicts, or None on failure."""

    holes = course_json.get("holes", [])

    # Build hole descriptions for the prompt
    hole_lines = []
    for h in holes:
        num = h.get("number", 0)
        par = h.get("par", 0)
        # Get a representative coordinate
        lat, lon = 0, 0
        lop = h.get("lineOfPlay")
        if isinstance(lop, dict) and lop.get("coordinates"):
            coords = lop["coordinates"]
            mid = coords[len(coords) // 2]
            lon, lat = mid[0], mid[1]
        elif h.get("pin"):
            lat = h["pin"].get("latitude", 0)
            lon = h["pin"].get("longitude", 0)
        # Include the raw ref if available
        raw_refs = h.get("rawRefs", "")
        ref_info = f", rawRef=\"{raw_refs}\"" if raw_refs else ""
        hole_lines.append(
            f"  hole_number={num}, par={par}, lat={lat:.5f}, lon={lon:.5f}{ref_info}"
        )

    # Build course descriptions from Golf API
    course_descs = []
    for ext in extracted:
        course_descs.append(
            f"- {ext['name']}: {len(ext['pars'])} holes, pars={ext['pars']}"
        )

    # Fetch satellite image
    img_content = []
    bounds_text = ""
    if facility_lat and facility_lon:
        img_bytes = _fetch_satellite_image(facility_lat, facility_lon)
        if img_bytes:
            bounds = _image_bounds(facility_lat, facility_lon)
            bounds_text = (
                f"\nI've included a satellite image of the facility.\n"
                f"Image bounds: top-left=({bounds['top_left_lat']:.4f}, "
                f"{bounds['top_left_lon']:.4f}), bottom-right="
                f"({bounds['bottom_right_lat']:.4f}, {bounds['bottom_right_lon']:.4f})\n"
                f"Use this to locate any holes that aren't in the OSM data.\n"
            )
            img_content = [{"image": {"format": "jpeg",
                                      "source": {"bytes": base64.b64encode(img_bytes).decode()}}}]

    prompt = f"""You are a golf course data expert. I have OSM data for "{course_json.get('name', '')}" that needs to be split into individual courses.

## Golf Course API Data (ground truth for course names and pars)
{chr(10).join(course_descs)}
Note: Exclude any par-3 course holes (if present) from the output.

## Rules
1. Each course has exactly the number of holes shown above.
2. Use the OSM ref tags, par values, AND coordinates to determine which course each hole belongs to.
3. Refs like "west9-1" mean hole 1 of a course with "west" in its name.
4. Refs like "Par3-*" are a par-3 course — exclude them entirely.
5. Standard numeric refs (1-18) may represent paired 18-hole combinations. Use par values and spatial clustering to disambiguate.
6. When there are DUPLICATE refs, each duplicate belongs to a DIFFERENT course.
7. If par is 4 (the default) and no other signal exists, use coordinates to cluster the hole with its course neighbors.
8. Deduplicate — if the same physical hole appears multiple times (same coordinates), include it only once.
{bounds_text}
## OSM Holes ({len(holes)} total)
{chr(10).join(hole_lines)}

## Output Format
Return ONLY a JSON object with this structure:
{{
  "courses": [
    {{
      "name": "CourseName",
      "holes": [
        {{"osm_index": 0, "hole_number": 1, "par": 5}},
        ...
      ]
    }},
    ...
  ],
  "missing_holes": [
    {{"course": "CourseName", "hole_number": N, "par": N, "tee_lat": N, "tee_lon": N, "green_lat": N, "green_lon": N}},
    ...
  ]
}}

osm_index is the 0-based index into the OSM holes list above.
missing_holes are holes that exist in the Golf API but have no matching OSM data — locate them from the satellite image if possible."""

    try:
        bedrock = boto3.client("bedrock-runtime",
                               region_name=os.environ.get("AWS_REGION", "us-east-2"))

        content = img_content + [{"text": prompt}]
        resp = bedrock.invoke_model(
            modelId="us.amazon.nova-pro-v1:0",
            contentType="application/json",
            accept="application/json",
            body=json.dumps({
                "messages": [{"role": "user", "content": content}],
                "inferenceConfig": {"maxTokens": 4000},
            }),
        )
        result = json.loads(resp["body"].read())
        text = result["output"]["message"]["content"][0]["text"]

        # Parse JSON from response
        text = text.strip()
        if text.startswith("```"):
            text = text.split("\n", 1)[1].rsplit("```", 1)[0]
        llm_output = json.loads(text)

    except Exception as e:
        print(f"LLM_ASSIGN: Bedrock call failed: {e}")
        return None

    # Build sub-courses from LLM output
    llm_courses = llm_output.get("courses", [])
    missing_holes = llm_output.get("missing_holes", [])
    print(f"LLM_ASSIGN: {len(llm_courses)} courses, {len(missing_holes)} missing holes located")

    sub_courses = []
    for lc in llm_courses:
        course_holes = []
        for lh in lc.get("holes", []):
            osm_idx = lh.get("osm_index", -1)
            hole_num = lh.get("hole_number", 0)
            par = lh.get("par", 0)
            if 0 <= osm_idx < len(holes):
                h = dict(holes[osm_idx])
                h["number"] = hole_num
                if par > 0:
                    h["par"] = par
                course_holes.append(h)

        # Add any missing holes located via satellite
        for mh in missing_holes:
            if mh.get("course") == lc.get("name"):
                tee_lat = mh.get("tee_lat")
                tee_lon = mh.get("tee_lon")
                green_lat = mh.get("green_lat")
                green_lon = mh.get("green_lon")
                if all([tee_lat, tee_lon, green_lat, green_lon]):
                    course_holes.append({
                        "number": mh.get("hole_number", 0),
                        "par": mh.get("par", 0),
                        "strokeIndex": None,
                        "yardages": {},
                        "lineOfPlay": {"coordinates": [[tee_lon, tee_lat], [green_lon, green_lat]]},
                        "green": None,
                        "pin": {"latitude": green_lat, "longitude": green_lon},
                        "teeAreas": [], "bunkers": [], "water": [],
                        "_synthesized": True,
                    })

        course_holes.sort(key=lambda h: h.get("number", 0))

        # Compute centroid
        lats, lons = [], []
        for h in course_holes:
            pin = h.get("pin")
            if isinstance(pin, dict) and "latitude" in pin:
                lats.append(pin["latitude"])
                lons.append(pin["longitude"])
            lop = h.get("lineOfPlay")
            if isinstance(lop, dict):
                for coord in (lop.get("coordinates") or []):
                    if isinstance(coord, list) and len(coord) >= 2:
                        lons.append(coord[0])
                        lats.append(coord[1])

        sub_courses.append({
            "id": f"{course_json.get('id', '')}_{len(sub_courses)}",
            "name": course_json.get("name", ""),
            "city": course_json.get("city", ""),
            "state": course_json.get("state", ""),
            "centroid": {
                "latitude": sum(lats) / len(lats) if lats else 0,
                "longitude": sum(lons) / len(lons) if lons else 0,
            },
            "holes": course_holes,
            "teeNames": [],
            "teeYardageTotals": {},
        })

        print(f"LLM_ASSIGN: {lc.get('name')} → {len(course_holes)} holes")

    return sub_courses if sub_courses else None


# ---------------------------------------------------------------------------
# Single-course vision refinement (fills missing holes in a cached course)
# ---------------------------------------------------------------------------

def refine_course_with_vision(course: dict, facility_name: str) -> dict:
    """Use satellite imagery + Bedrock Nova Pro to locate missing
    holes and synthesize basic geometry for a single course.

    Identifies holes without lineOfPlay or green geometry, fetches
    a satellite image of the course, and asks Nova Pro to find each
    missing hole's tee and green coordinates. Mutates and returns
    the course dict with synthesized geometry added.
    """
    holes = course.get("holes", [])
    missing = [h for h in holes if not h.get("lineOfPlay") and not h.get("green")]
    if not missing:
        print(f"REFINE: '{course.get('name')}' has no missing holes")
        return course

    print(f"REFINE: '{course.get('name')}' — {len(missing)} missing holes: "
          f"{[h.get('number') for h in missing]}")

    lat = course.get("centroid", {}).get("latitude", 0)
    lon = course.get("centroid", {}).get("longitude", 0)
    if not lat or not lon:
        # Fall back to an averaged centroid from assigned holes
        lats, lons = [], []
        for h in holes:
            pin = h.get("pin")
            if isinstance(pin, dict):
                lats.append(pin.get("latitude", 0))
                lons.append(pin.get("longitude", 0))
        if lats:
            lat = sum(lats) / len(lats)
            lon = sum(lons) / len(lons)

    if not lat or not lon:
        print("REFINE: no valid facility centroid, skipping")
        return course

    img_bytes = _fetch_satellite_image(lat, lon)
    if not img_bytes:
        return course

    bounds = _image_bounds(lat, lon)

    # Build context about assigned holes for spatial grounding
    assigned_context = []
    for h in holes:
        if h.get("lineOfPlay") or h.get("green"):
            pin = h.get("pin")
            lop = h.get("lineOfPlay")
            if pin and "latitude" in pin:
                assigned_context.append(
                    f"- Hole {h.get('number')}: par {h.get('par')}, "
                    f"green near lat={pin['latitude']:.5f}, "
                    f"lon={pin['longitude']:.5f}"
                )
            elif lop and lop.get("coordinates"):
                coords = lop["coordinates"]
                mid = coords[len(coords) // 2]
                assigned_context.append(
                    f"- Hole {h.get('number')}: par {h.get('par')}, "
                    f"midpoint near lat={mid[1]:.5f}, lon={mid[0]:.5f}"
                )

    missing_descriptions = [
        f"- Hole {h.get('number')}: par {h.get('par')}"
        for h in missing
    ]

    prompt = f"""This satellite image shows "{course.get('name')}" — a nine or eighteen hole golf course within the {facility_name} facility.

Image bounds (use for pixel→coordinate conversion):
- Top-left corner: lat={bounds['top_left_lat']:.5f}, lon={bounds['top_left_lon']:.5f}
- Bottom-right corner: lat={bounds['bottom_right_lat']:.5f}, lon={bounds['bottom_right_lon']:.5f}

## Reference coordinates (holes already mapped — use these as anchor points for precision)
{chr(10).join(assigned_context) if assigned_context else "- (none available — estimate from image bounds only)"}

## Missing holes to locate
{chr(10).join(missing_descriptions)}

## Instructions
1. The reference coordinates above are known-accurate. Interpolate the missing hole positions RELATIVE to these anchors — don't estimate from image bounds alone.
2. Course holes flow in sequence — hole N's tee is typically <200m from hole (N-1)'s green.
3. Only return a hole if you can clearly identify its fairway (linear corridor of lighter green) and green (circular manicured area) in the image.
4. Do NOT place holes in water, residential neighborhoods, parking lots, or outside the course boundary (visible as the grass/fairway region).
5. If a hole is ambiguous or you cannot confidently locate it, OMIT IT from the response. Partial data beats wrong data.

## Output Format
Return ONLY a JSON array:
[{{"hole": N, "par": N, "tee_lat": N, "tee_lon": N, "green_lat": N, "green_lon": N}}]

Coordinates: 5 decimal places (e.g., 39.65173)."""

    try:
        bedrock = boto3.client("bedrock-runtime",
                               region_name=os.environ.get("AWS_REGION", "us-east-2"))
        resp = bedrock.invoke_model(
            modelId="us.amazon.nova-pro-v1:0",
            contentType="application/json",
            accept="application/json",
            body=json.dumps({
                "messages": [{"role": "user", "content": [
                    {"image": {"format": "jpeg",
                               "source": {"bytes": base64.b64encode(img_bytes).decode()}}},
                    {"text": prompt},
                ]}],
                "inferenceConfig": {"maxTokens": 2000},
            }),
        )
        result = json.loads(resp["body"].read())
        text = result["output"]["message"]["content"][0]["text"].strip()
        if text.startswith("```"):
            text = text.split("\n", 1)[1].rsplit("```", 1)[0]
        found = json.loads(text)
        print(f"REFINE: Nova Pro located {len(found)} of {len(missing)} missing holes")
    except Exception as e:
        print(f"REFINE: Bedrock call failed: {e}")
        return course

    # Merge found coordinates into the course holes
    by_number = {h.get("number"): h for h in holes}
    for fh in found:
        hole_num = fh.get("hole")
        tee_lat = fh.get("tee_lat")
        tee_lon = fh.get("tee_lon")
        green_lat = fh.get("green_lat")
        green_lon = fh.get("green_lon")
        if not all([hole_num, tee_lat, tee_lon, green_lat, green_lon]):
            continue
        target = by_number.get(hole_num)
        if target is None:
            continue
        target["lineOfPlay"] = {
            "coordinates": [[tee_lon, tee_lat], [green_lon, green_lat]]
        }
        target["pin"] = {"latitude": green_lat, "longitude": green_lon}
        target["_synthesized"] = True
        print(f"REFINE: synthesized hole {hole_num} "
              f"tee=({tee_lat:.5f},{tee_lon:.5f}) green=({green_lat:.5f},{green_lon:.5f})")

    return course


def handle_refine(event: dict, context) -> dict:
    """POST /courses/refine — refine a single cached course using
    satellite vision to fill missing hole geometry. Fire-and-forget."""
    body_str = event.get("body", "")
    if event.get("isBase64Encoded"):
        body_str = base64.b64decode(body_str).decode("utf-8")
    if not body_str:
        return error_response(400, "Empty request body.")

    try:
        payload = json.loads(body_str)
    except json.JSONDecodeError:
        return error_response(400, "Invalid JSON.")

    cache_key = payload.get("cacheKey", "")
    facility_name = payload.get("facilityName", "")
    if not cache_key:
        return error_response(400, "Missing 'cacheKey'.")

    # Self-invoke asynchronously
    async_payload = {
        "_asyncRefine": True,
        "cacheKey": cache_key,
        "facilityName": facility_name,
        "schema": "1.0",
    }

    lambda_client = boto3.client("lambda",
                                  region_name=os.environ.get("AWS_REGION", "us-east-2"))
    lambda_client.invoke(
        FunctionName=context.function_name,
        InvocationType="Event",
        Payload=json.dumps(async_payload).encode(),
    )

    print(f"REFINE: accepted '{cache_key}'")
    return {
        "statusCode": 202,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps({"status": "refining", "cacheKey": cache_key}),
    }


def handle_async_refine(event: dict):
    """Fetch a cached course, fill missing holes via vision, save back."""
    cache_key = event.get("cacheKey", "")
    facility_name = event.get("facilityName", "")
    schema = event.get("schema", "1.0")

    print(f"ASYNC_REFINE: starting for '{cache_key}'")

    s3 = get_s3_client()
    s3_object_key = s3_key(schema, cache_key)

    try:
        obj = s3.get_object(Bucket=BUCKET_NAME, Key=s3_object_key)
        compressed_body = obj["Body"].read()
        course = json.loads(gzip.decompress(compressed_body).decode("utf-8"))
    except Exception as e:
        print(f"ASYNC_REFINE: failed to fetch course: {e}")
        return

    before_missing = sum(
        1 for h in course.get("holes", [])
        if not h.get("lineOfPlay") and not h.get("green")
    )
    if before_missing == 0:
        print(f"ASYNC_REFINE: '{cache_key}' already complete, skipping")
        return

    refined = refine_course_with_vision(course, facility_name)

    after_missing = sum(
        1 for h in refined.get("holes", [])
        if not h.get("lineOfPlay") and not h.get("green")
    )
    filled = before_missing - after_missing
    if filled == 0:
        print(f"ASYNC_REFINE: no holes filled for '{cache_key}'")
        return

    # Save refined version back to S3
    try:
        compressed = gzip.compress(
            json.dumps(refined, separators=(",", ":")).encode("utf-8")
        )
        s3.put_object(
            Bucket=BUCKET_NAME,
            Key=s3_object_key,
            Body=compressed,
            ContentType="application/json",
            ContentEncoding="gzip",
        )
        print(f"ASYNC_REFINE: saved '{cache_key}' — filled {filled}/{before_missing} holes")
    except Exception as e:
        print(f"ASYNC_REFINE: failed to save: {e}")


# ---------------------------------------------------------------------------
# Async ingestion handler
# ---------------------------------------------------------------------------

def handle_async_ingest(event: dict):
    """Process a multi-course facility asynchronously.

    Called via Lambda self-invocation (InvocationType=Event).
    Receives the normalized course JSON, splits by par sequence,
    enriches each sub-course, and saves to S3 + manifest.
    """
    name = event.get("name", "")
    cache_key_base = event.get("cacheKey", "")
    course_json = event.get("courseJson", {})
    schema = event.get("schema", "1.0")

    print(f"ASYNC_INGEST: starting for '{name}', {len(course_json.get('holes', []))} holes")

    s3 = get_s3_client()
    status_key = f"courses/status/{cache_key_base}.json"

    try:
        # 1. Search Golf Course API
        if not GOLF_COURSE_API_KEY:
            raise RuntimeError("GOLF_COURSE_API_KEY not configured")

        api_results = golf_api_search(name)
        print(f"ASYNC_INGEST: Golf API returned {len(api_results)} results")

        if len(api_results) < 2:
            raise RuntimeError(f"Golf API returned {len(api_results)} results, need ≥2")

        # 2. Fetch details for each API result
        api_details = []
        for r in api_results[:6]:
            detail = golf_api_detail(r.get("id", 0))
            if detail:
                api_details.append(detail)

        if len(api_details) < 2:
            raise RuntimeError(f"Golf API details: only {len(api_details)} valid, need ≥2")

        # 3. Extract individual courses (handles combos like West-Lind)
        extracted = extract_courses(api_details)
        print(f"ASYNC_INGEST: extracted {len(extracted)} individual courses: "
              f"{[e['name'] for e in extracted]}")

        if len(extracted) < 2:
            raise RuntimeError(f"Only {len(extracted)} courses extracted, need ≥2")

        # 4. Split holes by par sequence (fast algorithmic path)
        par_sequences = [e["pars"] for e in extracted]
        sub_courses = split_by_par_sequence(course_json, par_sequences)
        print(f"ASYNC_INGEST: algorithmic split → {len(sub_courses)} sub-courses: "
              f"{[len(s.get('holes',[])) for s in sub_courses]}")

        # 4a. Quality check — did the algorithmic split produce clean results?
        # Clean = each sub-course has the expected hole count (±1) from the API.
        clean_split = True
        for i, sub in enumerate(sub_courses):
            expected = len(extracted[i]["pars"]) if i < len(extracted) else 0
            actual = len(sub.get("holes", []))
            if expected > 0 and (actual < expected - 1 or actual > expected + 1):
                clean_split = False
                print(f"ASYNC_INGEST: split quality FAIL — course {i} "
                      f"expected {expected} holes, got {actual}")
                break

        facility_lat = course_json.get("centroid", {}).get("latitude", 0)
        facility_lon = course_json.get("centroid", {}).get("longitude", 0)

        if clean_split:
            print("ASYNC_INGEST: algorithmic split is clean, skipping LLM")
            # Still fill any single missing holes via satellite vision
            if facility_lat and facility_lon:
                sub_courses = fill_missing_holes_with_vision(
                    sub_courses, extracted, facility_lat, facility_lon,
                )
        else:
            # 4b. Algorithmic split failed — use LLM for full assignment
            print("ASYNC_INGEST: falling back to LLM for hole assignment")
            llm_result = _llm_assign_holes(
                course_json, extracted, facility_lat, facility_lon,
            )
            if llm_result:
                sub_courses = llm_result
            else:
                print("ASYNC_INGEST: LLM assignment also failed, using algorithmic result")

        # 5. Name, enrich, and save each sub-course
        for i, sub in enumerate(sub_courses):
            ext = extracted[i] if i < len(extracted) else None
            if ext:
                sub["name"] = f"{name} - {ext['name']}"
                sub = enrich_with_tee_data(
                    sub, ext["detail"],
                    front_or_back=ext.get("front_or_back"),
                )
            print(f"ASYNC_INGEST: sub-course '{sub['name']}' — "
                  f"{len(sub.get('holes', []))} holes, "
                  f"{len(sub.get('teeNames', []))} tees")

            # Save to S3 via the same path as handle_put
            sub_cache_key = normalize_name(sub["name"]).replace(" ", "-")
            sub_s3_key = s3_key(schema, sub_cache_key)
            compressed = gzip.compress(
                json.dumps(sub, separators=(",", ":")).encode("utf-8")
            )
            s3.put_object(
                Bucket=BUCKET_NAME,
                Key=sub_s3_key,
                Body=compressed,
                ContentType="application/json",
                ContentEncoding="gzip",
            )

            # Update manifest
            lat = sub.get("centroid", {}).get("latitude", 0)
            lon = sub.get("centroid", {}).get("longitude", 0)
            try:
                update_manifest(
                    s3, sub_cache_key, sub["name"], lat, lon, schema,
                    sub_s3_key,
                    city=sub.get("city", ""),
                    state=sub.get("state", ""),
                )
            except Exception as e:
                print(f"ASYNC_INGEST: manifest update failed for {sub_cache_key}: {e}")

        # 6. Done — delete status marker
        try:
            s3.delete_object(Bucket=BUCKET_NAME, Key=status_key)
        except Exception:
            pass

        print(f"ASYNC_INGEST: completed successfully — {len(sub_courses)} courses saved")

    except Exception as e:
        print(f"ASYNC_INGEST: failed — {e}")
        # Update status marker with error
        try:
            s3.put_object(
                Bucket=BUCKET_NAME,
                Key=status_key,
                Body=json.dumps({"status": "failed", "error": str(e)}).encode(),
                ContentType="application/json",
            )
        except Exception:
            pass


# ---------------------------------------------------------------------------
# RAG-based multi-course ingestion (GPT-4o + website images)
# ---------------------------------------------------------------------------

OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")
TRACES_PREFIX = "courses/traces/"


def _get_openai_key() -> str:
    """Get OpenAI API key from env or Secrets Manager."""
    if OPENAI_API_KEY:
        return OPENAI_API_KEY
    try:
        sm = boto3.client("secretsmanager",
                          region_name=os.environ.get("AWS_REGION", "us-east-2"))
        secret = sm.get_secret_value(SecretId="caddieai/openai-api-key")
        return secret["SecretString"]
    except Exception as e:
        print(f"RAG: failed to get OpenAI key: {e}")
        return ""


def _detect_img_format(data: bytes) -> str:
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    if data[:3] == b"\xff\xd8\xff":
        return "jpeg"
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    return "jpeg"


def _fetch_course_website_images(facility_name: str) -> list[dict]:
    """Search for scorecard/course map images on the facility website.
    Returns list of {name, bytes, format} dicts."""
    images = []

    # Step 1: Google search for the course website
    search_query = f"{facility_name} golf scorecard course map"
    try:
        # Use Google Places Text Search to find the website
        if GOOGLE_PLACES_API_KEY:
            params = {
                "textQuery": f"{facility_name} golf course",
                "includedType": "golf_course",
                "maxResultCount": 1,
            }
            req_body = json.dumps(params).encode("utf-8")
            url = "https://places.googleapis.com/v1/places:searchText"
            req = urllib.request.Request(url, data=req_body, method="POST")
            req.add_header("Content-Type", "application/json")
            req.add_header("X-Goog-Api-Key", GOOGLE_PLACES_API_KEY)
            req.add_header("X-Goog-FieldMask", "places.websiteUri")
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            places = data.get("places", [])
            if places:
                website = places[0].get("websiteUri", "")
                if website:
                    print(f"RAG: found website: {website}")
                    # Fetch the website and extract image URLs
                    req = urllib.request.Request(website)
                    req.add_header("User-Agent", "CaddieAI/1.0")
                    with urllib.request.urlopen(req, timeout=10) as resp:
                        html = resp.read().decode("utf-8", errors="ignore")

                    # Extract image URLs that look like scorecards/maps
                    import re as re_mod
                    img_urls = re_mod.findall(
                        r'(?:src|data-src)=["\']([^"\']+(?:scorecard|course|map|layout|CCF|hole)[^"\']*\.(?:jpg|jpeg|png|webp))["\']',
                        html, re_mod.IGNORECASE,
                    )
                    # Also grab squarespace-cdn images (common pattern)
                    img_urls += re_mod.findall(
                        r'(https://images\.squarespace-cdn\.com/[^"\']+)',
                        html,
                    )
                    # Dedupe
                    seen = set()
                    unique_urls = []
                    for u in img_urls:
                        if u not in seen:
                            seen.add(u)
                            unique_urls.append(u)

                    for i, img_url in enumerate(unique_urls[:5]):
                        try:
                            req = urllib.request.Request(img_url)
                            req.add_header("User-Agent", "CaddieAI/1.0")
                            with urllib.request.urlopen(req, timeout=10) as resp:
                                img_data = resp.read()
                            if len(img_data) > 5000:  # skip tiny images
                                fmt = _detect_img_format(img_data)
                                images.append({
                                    "name": f"web_image_{i}",
                                    "bytes": img_data,
                                    "format": fmt,
                                    "url": img_url,
                                })
                                print(f"RAG: fetched image {i}: {len(img_data)} bytes ({fmt})")
                        except Exception as e:
                            print(f"RAG: failed to fetch image {img_url}: {e}")
    except Exception as e:
        print(f"RAG: website search failed: {e}")

    return images


def _call_gpt4o_assignment(
    facility_name: str,
    osm_holes: list[dict],
    golf_api_data: list[dict],
    web_images: list[dict],
) -> tuple[dict | None, str]:
    """Call GPT-4o to assign OSM holes to courses. Returns (result, raw_text)."""
    api_key = _get_openai_key()
    if not api_key:
        return None, "No OpenAI API key"

    # Build OSM summary
    osm_lines = []
    for h in osm_holes:
        osm_lines.append(
            f"  osm_id={h.get('id', '?')} ref={h.get('ref', '?')} "
            f"par={h.get('par', '?')} lat={h.get('lat', 0):.5f} "
            f"lon={h.get('lon', 0):.5f}"
        )

    # Build Golf API summary
    api_lines = []
    for c in golf_api_data:
        name = c.get("course_name") or c.get("courseName", "")
        pars = _extract_par_sequence(c)
        api_lines.append(f"  {name}: pars={pars}")

    prompt = f"""You are a golf course data expert. Assign each OSM hole to the correct course at this multi-course facility.

## Facility
{facility_name}

## Golf Course API Data (authoritative names and pars)
{chr(10).join(api_lines)}

## OSM Data ({len(osm_holes)} holes — may have duplicate numbering)
{chr(10).join(osm_lines)}

## Attached Images
Scorecard and course map images from the facility website. Use these to understand hole layout, names, and spatial relationships.

## Task
Match each OSM hole (by osm_id) to a course. Use par values, coordinates, scorecard data, and map layout. For duplicate hole numbers, match each to the course whose par at that position agrees.

## Output
Return ONLY JSON:
{{
  "courses": {{
    "<course_name>": [
      {{"osm_id": 12345, "hole_number": 1, "par": 4, "confidence": "high|medium|low"}},
      ...
    ],
    ...
  }},
  "reasoning": "Brief explanation"
}}"""

    # Build multimodal content
    content = []
    for img in web_images:
        mime = f"image/{img['format']}"
        b64 = base64.b64encode(img["bytes"]).decode()
        content.append({
            "type": "image_url",
            "image_url": {"url": f"data:{mime};base64,{b64}", "detail": "high"},
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

    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            result = json.loads(resp.read())
        text = result["choices"][0]["message"]["content"]

        # Parse JSON from response
        clean = text.strip()
        if clean.startswith("```"):
            clean = clean.split("\n", 1)[1].rsplit("```", 1)[0]
        parsed = json.loads(clean)
        return parsed, text

    except Exception as e:
        print(f"RAG: GPT-4o call failed: {e}")
        return None, str(e)


def _build_courses_from_rag(
    rag_result: dict,
    course_json: dict,
    golf_api_data: list[dict],
    facility_name: str,
) -> list[dict]:
    """Build NormalizedCourse dicts from RAG assignment results."""
    courses_output = rag_result.get("courses", {})
    osm_holes_by_id = {}
    for h in course_json.get("holes", []):
        # Use a composite key since holes might not have unique IDs
        key = f"{h.get('number', 0)}_{h.get('par', 0)}"
        osm_holes_by_id[key] = h

    # Also index by the raw osm_id if present
    # The course_json holes come from the normalizer which doesn't keep osm_id.
    # We need to match by hole number + par instead.
    results = []
    for course_name, assignments in courses_output.items():
        holes = []
        used_keys = set()
        for a in assignments:
            hole_num = a.get("hole_number", 0)
            par = a.get("par", 0)
            # Find matching hole from course_json
            for h in course_json.get("holes", []):
                key = id(h)
                if key in used_keys:
                    continue
                if h.get("number") == hole_num and h.get("par") == par:
                    holes.append(h)
                    used_keys.add(key)
                    break

        if not holes:
            continue

        holes.sort(key=lambda h: h.get("number", 0))

        # Compute centroid
        lats, lons = [], []
        for h in holes:
            lop = h.get("lineOfPlay")
            if lop and lop.get("coordinates"):
                coords = lop["coordinates"]
                mid = coords[len(coords) // 2]
                lons.append(mid[0])
                lats.append(mid[1])

        sub_name = f"{facility_name} - {course_name}"

        # Find matching Golf API detail for enrichment
        api_detail = None
        for d in golf_api_data:
            api_name = (d.get("course_name") or d.get("courseName", "")).lower()
            if api_name == course_name.lower():
                api_detail = d
                break

        sub_course = {
            "id": normalize_name(sub_name).replace(" ", "-"),
            "name": sub_name,
            "city": course_json.get("city", ""),
            "state": course_json.get("state", ""),
            "centroid": {
                "latitude": sum(lats) / len(lats) if lats else 0,
                "longitude": sum(lons) / len(lons) if lons else 0,
            },
            "holes": holes,
            "teeNames": [],
            "teeYardageTotals": {},
        }

        # Enrich with Golf API tee data
        if api_detail:
            sub_course = enrich_with_tee_data(sub_course, api_detail)

        results.append(sub_course)

    return results


def handle_rag_ingest(event: dict, context) -> dict:
    """POST /courses/ingest-rag — RAG-based multi-course ingestion
    using GPT-4o with website images for hole assignment."""
    body_str = event.get("body", "")
    if event.get("isBase64Encoded"):
        body_str = base64.b64decode(body_str).decode("utf-8")
    if not body_str:
        return error_response(400, "Empty request body.")

    try:
        payload = json.loads(body_str)
    except json.JSONDecodeError:
        return error_response(400, "Invalid JSON.")

    name = payload.get("name", "")
    course_json = payload.get("courseJson")
    if not name or not course_json:
        return error_response(400, "Missing 'name' or 'courseJson'.")

    # Self-invoke asynchronously
    async_payload = {
        "_asyncRagIngest": True,
        "name": name,
        "courseJson": course_json,
        "schema": "1.0",
    }

    lambda_client = boto3.client("lambda",
                                  region_name=os.environ.get("AWS_REGION", "us-east-2"))
    lambda_client.invoke(
        FunctionName=context.function_name,
        InvocationType="Event",
        Payload=json.dumps(async_payload).encode(),
    )

    print(f"RAG_INGEST: accepted '{name}'")
    return {
        "statusCode": 202,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps({"status": "processing"}),
    }


def handle_async_rag_ingest(event: dict):
    """Async RAG ingestion: fetch website + Golf API + call GPT-4o."""
    import time as _time
    start_time = _time.perf_counter()

    name = event.get("name", "")
    course_json = event.get("courseJson", {})
    schema = event.get("schema", "1.0")

    print(f"RAG_INGEST: starting for '{name}', "
          f"{len(course_json.get('holes', []))} holes")

    s3 = get_s3_client()
    trace = {
        "facility": name,
        "timestamp": _time.strftime("%Y-%m-%dT%H:%M:%SZ", _time.gmtime()),
        "steps": [],
    }

    try:
        # 1. Golf Course API
        api_results = golf_api_search(name)
        api_details = []
        for r in api_results[:6]:
            d = golf_api_detail(r.get("id", 0))
            if d:
                api_details.append(d)

        trace["steps"].append({
            "step": "golf_api",
            "courses_found": [d.get("course_name", "") for d in api_details],
        })
        print(f"RAG_INGEST: Golf API → {len(api_details)} courses")

        if len(api_details) < 2:
            raise RuntimeError(f"Golf API returned {len(api_details)} courses, need ≥2")

        # 2. Fetch website images
        web_images = _fetch_course_website_images(name)
        trace["steps"].append({
            "step": "web_images",
            "images_found": len(web_images),
            "urls": [img.get("url", "") for img in web_images],
        })
        print(f"RAG_INGEST: fetched {len(web_images)} website images")

        # 3. Build OSM hole summary for the prompt
        osm_holes = []
        for h in course_json.get("holes", []):
            lop = h.get("lineOfPlay")
            lat, lon = 0, 0
            if lop and lop.get("coordinates"):
                coords = lop["coordinates"]
                mid = coords[len(coords) // 2]
                lon, lat = mid[0], mid[1]
            osm_holes.append({
                "id": h.get("id", f"h{h.get('number', 0)}"),
                "ref": str(h.get("number", 0)),
                "par": h.get("par", 0),
                "lat": lat,
                "lon": lon,
            })

        # 4. Call GPT-4o
        rag_result, raw_response = _call_gpt4o_assignment(
            name, osm_holes, api_details, web_images,
        )
        trace["steps"].append({
            "step": "gpt4o_assignment",
            "success": rag_result is not None,
            "raw_response": raw_response[:2000] if raw_response else "",
            "courses_assigned": list(rag_result.get("courses", {}).keys()) if rag_result else [],
            "reasoning": rag_result.get("reasoning", "") if rag_result else "",
        })

        if not rag_result:
            raise RuntimeError("GPT-4o assignment failed")

        print(f"RAG_INGEST: GPT-4o assigned courses: "
              f"{list(rag_result.get('courses', {}).keys())}")

        # 5. Build and save sub-courses
        sub_courses = _build_courses_from_rag(
            rag_result, course_json, api_details, name,
        )

        for sub in sub_courses:
            holes_with_geom = sum(
                1 for h in sub.get("holes", [])
                if h.get("lineOfPlay") or h.get("green")
            )
            print(f"RAG_INGEST: '{sub['name']}' — "
                  f"{len(sub.get('holes', []))} holes, "
                  f"{holes_with_geom} with geometry")

            # Only save if we have geometry
            if holes_with_geom == 0:
                print(f"RAG_INGEST: skipping '{sub['name']}' — no geometry")
                continue

            sub_cache_key = normalize_name(sub["name"]).replace(" ", "-")
            sub_s3_key = s3_key(schema, sub_cache_key)
            compressed = gzip.compress(
                json.dumps(sub, separators=(",", ":")).encode("utf-8")
            )
            s3.put_object(
                Bucket=BUCKET_NAME,
                Key=sub_s3_key,
                Body=compressed,
                ContentType="application/json",
                ContentEncoding="gzip",
            )
            try:
                lat = sub.get("centroid", {}).get("latitude", 0)
                lon = sub.get("centroid", {}).get("longitude", 0)
                update_manifest(
                    s3, sub_cache_key, sub["name"], lat, lon, schema,
                    sub_s3_key,
                    city=sub.get("city", ""),
                    state=sub.get("state", ""),
                )
            except Exception as e:
                print(f"RAG_INGEST: manifest update failed for {sub_cache_key}: {e}")

        elapsed = _time.perf_counter() - start_time
        trace["result"] = {
            "courses_saved": [s["name"] for s in sub_courses],
            "total_time_s": round(elapsed, 2),
        }
        print(f"RAG_INGEST: completed in {elapsed:.1f}s — "
              f"{len(sub_courses)} courses saved")

    except Exception as e:
        print(f"RAG_INGEST: failed — {e}")
        trace["error"] = str(e)

    # Save trace to S3
    trace_key = f"{TRACES_PREFIX}{normalize_name(name).replace(' ', '-')}.json"
    try:
        s3.put_object(
            Bucket=BUCKET_NAME,
            Key=trace_key,
            Body=json.dumps(trace, indent=2, default=str).encode("utf-8"),
            ContentType="application/json",
        )
        print(f"RAG_INGEST: trace saved to s3://{BUCKET_NAME}/{trace_key}")
    except Exception as e:
        print(f"RAG_INGEST: trace save failed: {e}")


def handle_ingest(event: dict, context) -> dict:
    """POST /courses/ingest — accept a multi-course facility for
    async backend processing. Writes a status marker and invokes
    this Lambda asynchronously to do the heavy work."""
    body_str = event.get("body", "")
    if event.get("isBase64Encoded"):
        body_str = base64.b64decode(body_str).decode("utf-8")

    if not body_str:
        return error_response(400, "Empty request body.")

    try:
        payload = json.loads(body_str)
    except json.JSONDecodeError:
        return error_response(400, "Invalid JSON.")

    name = payload.get("name", "")
    course_json = payload.get("courseJson")
    if not name or not course_json:
        return error_response(400, "Missing 'name' or 'courseJson'.")

    cache_key = normalize_name(name).replace(" ", "-")

    # Write status marker
    s3 = get_s3_client()
    status_key = f"courses/status/{cache_key}.json"
    s3.put_object(
        Bucket=BUCKET_NAME,
        Key=status_key,
        Body=json.dumps({"status": "processing",
                         "startedAt": str(int(__import__("time").time()))}).encode(),
        ContentType="application/json",
    )

    # Self-invoke asynchronously
    async_payload = {
        "_asyncIngest": True,
        "name": name,
        "cacheKey": cache_key,
        "courseJson": course_json,
        "schema": "1.0",
    }

    lambda_client = boto3.client("lambda",
                                  region_name=os.environ.get("AWS_REGION", "us-east-2"))
    lambda_client.invoke(
        FunctionName=context.function_name,
        InvocationType="Event",
        Payload=json.dumps(async_payload).encode(),
    )

    print(f"INGEST: accepted '{name}', dispatched async processing")

    return {
        "statusCode": 202,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps({
            "status": "processing",
            "cacheKey": cache_key,
        }),
    }


# ---------------------------------------------------------------------------
# Route handlers
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# OSM correction queue (human-in-the-loop geometry review)
# ---------------------------------------------------------------------------

CORRECTIONS_PREFIX = "corrections/"


def handle_submit_correction(event: dict) -> dict:
    """POST /corrections — queue a geometry correction for human review."""
    body_str = event.get("body", "")
    if event.get("isBase64Encoded"):
        body_str = base64.b64decode(body_str).decode("utf-8")
    if not body_str:
        return error_response(400, "Empty body.")

    try:
        correction = json.loads(body_str)
    except json.JSONDecodeError:
        return error_response(400, "Invalid JSON.")

    required = ["facilityName", "courseName", "holeNumber"]
    for field in required:
        if field not in correction:
            return error_response(400, f"Missing '{field}'.")

    # Generate a stable id from facility + course + hole.
    facility = correction["facilityName"]
    course = correction["courseName"]
    hole_num = correction["holeNumber"]
    correction_id = normalize_name(
        f"{facility}-{course}-h{hole_num}"
    ).replace(" ", "-")

    correction["id"] = correction_id
    correction["status"] = "pending"
    correction["submittedAt"] = __import__("time").strftime(
        "%Y-%m-%dT%H:%M:%SZ", __import__("time").gmtime()
    )

    s3 = get_s3_client()
    s3_object_key = f"{CORRECTIONS_PREFIX}{correction_id}.json"
    s3.put_object(
        Bucket=BUCKET_NAME,
        Key=s3_object_key,
        Body=json.dumps(correction, separators=(",", ":")).encode("utf-8"),
        ContentType="application/json",
    )

    print(f"CORRECTION: queued {correction_id}")
    return {
        "statusCode": 201,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps({"id": correction_id, "status": "pending"}),
    }


def handle_get_corrections(event: dict) -> dict:
    """GET /corrections — list pending corrections for review."""
    s3 = get_s3_client()
    query_params = event.get("queryStringParameters") or {}
    status_filter = query_params.get("status", "pending")

    try:
        response = s3.list_objects_v2(
            Bucket=BUCKET_NAME, Prefix=CORRECTIONS_PREFIX,
        )
        items = []
        for obj in response.get("Contents", []):
            key = obj["Key"]
            if not key.endswith(".json"):
                continue
            data = s3.get_object(Bucket=BUCKET_NAME, Key=key)
            correction = json.loads(data["Body"].read().decode("utf-8"))
            if correction.get("status") == status_filter:
                items.append(correction)
        items.sort(key=lambda c: c.get("submittedAt", ""), reverse=True)
    except Exception as e:
        print(f"CORRECTION: list failed: {e}")
        items = []

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "no-cache",
        },
        "body": json.dumps({"corrections": items}),
    }


def handle_review_correction(event: dict) -> dict:
    """POST /corrections/review — approve or deny a correction."""
    body_str = event.get("body", "")
    if event.get("isBase64Encoded"):
        body_str = base64.b64decode(body_str).decode("utf-8")
    if not body_str:
        return error_response(400, "Empty body.")

    try:
        payload = json.loads(body_str)
    except json.JSONDecodeError:
        return error_response(400, "Invalid JSON.")

    correction_id = payload.get("id", "")
    decision = payload.get("decision", "")  # "approved" or "denied"
    if not correction_id or decision not in ("approved", "denied"):
        return error_response(400, "Need 'id' and 'decision' (approved|denied).")

    s3 = get_s3_client()
    s3_key_path = f"{CORRECTIONS_PREFIX}{correction_id}.json"

    try:
        data = s3.get_object(Bucket=BUCKET_NAME, Key=s3_key_path)
        correction = json.loads(data["Body"].read().decode("utf-8"))
    except Exception:
        return error_response(404, f"Correction {correction_id} not found.")

    correction["status"] = decision
    correction["reviewedAt"] = __import__("time").strftime(
        "%Y-%m-%dT%H:%M:%SZ", __import__("time").gmtime()
    )

    s3.put_object(
        Bucket=BUCKET_NAME,
        Key=s3_key_path,
        Body=json.dumps(correction, separators=(",", ":")).encode("utf-8"),
        ContentType="application/json",
    )

    print(f"CORRECTION: {correction_id} → {decision}")
    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps({"id": correction_id, "status": decision}),
    }


def lambda_handler(event, context):
    # Async self-invocations
    if event.get("_asyncIngest"):
        handle_async_ingest(event)
        return {"statusCode": 200, "body": "ok"}
    if event.get("_asyncRefine"):
        handle_async_refine(event)
        return {"statusCode": 200, "body": "ok"}
    if event.get("_asyncRagIngest"):
        handle_async_rag_ingest(event)
        return {"statusCode": 200, "body": "ok"}

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
                "Access-Control-Allow-Methods": "GET, PUT, POST, DELETE, OPTIONS",
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

    # Dispatch by raw path for routes that don't use {courseId}
    raw_path = event.get("rawPath") or event.get("path") or ""

    # POST /courses/ingest-rag — RAG-based multi-course ingestion (GPT-4o)
    if http_method == "POST" and (raw_path == "/courses/ingest-rag"
                                  or raw_path.endswith("/courses/ingest-rag")):
        return handle_rag_ingest(event, context)

    # POST /courses/ingest — async multi-course ingestion (algorithmic fallback)
    if http_method == "POST" and (raw_path == "/courses/ingest"
                                  or raw_path.endswith("/courses/ingest")):
        return handle_ingest(event, context)

    # POST /courses/refine — single-course vision refinement
    if http_method == "POST" and (raw_path == "/courses/refine"
                                  or raw_path.endswith("/courses/refine")):
        return handle_refine(event, context)

    # Corrections queue — human-in-the-loop geometry review
    if raw_path == "/corrections" or raw_path.endswith("/corrections"):
        if http_method == "POST":
            return handle_submit_correction(event)
        if http_method == "GET":
            return handle_get_corrections(event)
    if http_method == "POST" and (raw_path == "/corrections/review"
                                  or raw_path.endswith("/corrections/review")):
        return handle_review_correction(event)

    # KAN-296: Google Places proxy routes
    if http_method == "GET":
        if raw_path == "/places/autocomplete" or raw_path.endswith("/places/autocomplete"):
            return handle_places_autocomplete(event)
        if raw_path == "/places/search" or raw_path.endswith("/places/search"):
            return handle_places_search(event)

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


def handle_places_autocomplete(event: dict) -> dict:
    """KAN-296: GET /places/autocomplete?q=<input> → city suggestions."""
    query_params = event.get("queryStringParameters") or {}
    query = (query_params.get("q") or "").strip()
    if not query:
        return error_response(400, "Missing 'q' query parameter.")

    cache_key = f"ac:{query.lower()}"
    cached = _places_cache_get(cache_key)
    if cached is not None:
        suggestions = cached
    else:
        suggestions = google_places_autocomplete(query)
        _places_cache_put(cache_key, suggestions)

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "public, max-age=3600",
        },
        "body": json.dumps({"suggestions": suggestions}, separators=(",", ":")),
    }


def handle_places_search(event: dict) -> dict:
    """KAN-296: GET /places/search?q=<query>&lat=&lon= → golf-course results."""
    query_params = event.get("queryStringParameters") or {}
    query = (query_params.get("q") or "").strip()
    if not query:
        return error_response(400, "Missing 'q' query parameter.")

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

    cache_key = f"ts:{query.lower()}:{lat}:{lon}"
    cached = _places_cache_get(cache_key)
    if cached is not None:
        results = cached
    else:
        results = google_places_text_search(query, lat, lon)
        _places_cache_put(cache_key, results)

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "public, max-age=3600",
        },
        "body": json.dumps({"results": results}, separators=(",", ":")),
    }


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

    # Merge with existing course data — preserve any holes that
    # already have real (non-synthesized) geometry if the incoming
    # upload is missing them. This prevents a "blind" upload with
    # 0 geometry from overwriting good cached data.
    try:
        existing_obj = s3.get_object(Bucket=BUCKET_NAME, Key=key)
        existing_data = json.loads(
            gzip.decompress(existing_obj["Body"].read()).decode("utf-8")
        )
        existing_holes = {h.get("number"): h for h in existing_data.get("holes", [])}
        merged_holes = []
        merges = 0
        for h in course_data.get("holes", []):
            num = h.get("number")
            incoming_has_geom = h.get("lineOfPlay") or h.get("green")
            existing = existing_holes.get(num)
            if not incoming_has_geom and existing and (
                existing.get("lineOfPlay") or existing.get("green")
            ):
                # Keep the existing geometry (may be real OSM or
                # previously synthesized — either way it's better
                # than nothing).
                h = {**h, **{
                    "lineOfPlay": existing.get("lineOfPlay"),
                    "green": existing.get("green"),
                    "pin": existing.get("pin"),
                    "teeAreas": existing.get("teeAreas", []),
                    "bunkers": existing.get("bunkers", []),
                    "water": existing.get("water", []),
                }}
                if existing.get("_synthesized"):
                    h["_synthesized"] = True
                merges += 1
            merged_holes.append(h)
        course_data["holes"] = merged_holes
        if merges > 0:
            print(f"MERGE: preserved geometry on {merges} holes from existing cache")
    except ClientError as e:
        if e.response["Error"]["Code"] != "NoSuchKey":
            print(f"MERGE: failed to fetch existing: {e}")
    except Exception as e:
        print(f"MERGE: error merging: {e}")

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
