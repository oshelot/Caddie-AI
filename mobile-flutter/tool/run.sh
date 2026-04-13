#!/usr/bin/env bash
# tool/run.sh — wrapper for `flutter run` that reads secrets from
# android/local.properties and passes them as --dart-define flags.
#
# Usage:
#   ./tool/run.sh                  # runs on the default device
#   ./tool/run.sh -d <device-id>   # runs on a specific device
#   ./tool/run.sh --release        # release build
#
# Why this exists: the gradle-based dart-defines injection
# (android/app/build.gradle) may not work for `flutter run` debug
# builds depending on how the IDE invokes the toolchain. This script
# is the guaranteed path — it constructs the --dart-define flags
# explicitly on the flutter CLI.
set -euo pipefail
cd "$(dirname "$0")/.."

# Resolve flutter binary — check PATH first, then local.properties
FLUTTER="flutter"
if ! command -v flutter &>/dev/null; then
  FLUTTER_SDK=$(grep '^flutter.sdk=' android/local.properties 2>/dev/null | cut -d= -f2-)
  if [ -n "$FLUTTER_SDK" ] && [ -x "$FLUTTER_SDK/bin/flutter" ]; then
    FLUTTER="$FLUTTER_SDK/bin/flutter"
  else
    echo "ERROR: flutter not found on PATH and flutter.sdk not set in android/local.properties"
    exit 1
  fi
fi

PROPS="android/local.properties"
if [ ! -f "$PROPS" ]; then
  echo "ERROR: $PROPS not found. Copy secrets from the native android/local.properties."
  exit 1
fi

DART_DEFINES=""
for KEY in COURSE_CACHE_ENDPOINT COURSE_CACHE_API_KEY MAPBOX_TOKEN \
           LLM_PROXY_ENDPOINT LLM_PROXY_API_KEY \
           LOGGING_ENDPOINT LOGGING_API_KEY GOLF_COURSE_API_KEY; do
  VAL=$(grep "^${KEY}=" "$PROPS" 2>/dev/null | head -1 | cut -d= -f2-)
  if [ -n "$VAL" ]; then
    DART_DEFINES="$DART_DEFINES --dart-define=$KEY=$VAL"
  fi
done

echo "Injecting dart-defines for: $(echo $DART_DEFINES | grep -oP '(?<=--dart-define=)[A-Z_]+(?==)' | tr '\n' ' ')"
echo ""

# Force --debug unless the user explicitly passes --release or --profile.
# Without this, flutter.buildMode=profile in local.properties causes
# kDebugMode=false, hiding the debug Pro toggle and disabling debug features.
MODE="--debug"
for arg in "$@"; do
  case "$arg" in --release|--profile) MODE="" ;; esac
done

# shellcheck disable=SC2086
exec $FLUTTER run $MODE $DART_DEFINES "$@"
