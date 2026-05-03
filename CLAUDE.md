# CaddieAI (Flutter App)

Mobile golf caddie app built with Flutter. Renders hole geometry on Mapbox satellite, provides AI caddie advice via voice, and integrates with backend lambdas for course data and LLM inference.

## Repo relationship

- **This repo** (`Caddie-AI` / `CaddieAI-Mono`): open-source Flutter app code. Public.
- **`CaddieAI-infra`** (`github.com/oshelot/CaddieAI-infra`): private repo with all backend lambdas, scraper fleet, course pipeline, and infrastructure. Has its own `CLAUDE.md` with AWS details, lambda internals, and deployment runbooks.
- **Never push infra content here.** The `infrastructure/` directory on disk is a nested git repo pointing at the private remote; it's gitignored from this repo.

### infrastructure/ is a nested git repo — handle with care
- **NEVER `rm -rf infrastructure`** — it has its own `.git` directory. Deleting and re-cloning overwrites the parent repo's `.git` history and working tree.
- To update: `cd infrastructure && git pull origin main`
- To get a missing subdirectory: `cd infrastructure && git checkout origin/main -- course-viewer/`
- To fetch the infra CLAUDE.md without cloning: `gh api repos/oshelot/CaddieAI-infra/contents/CLAUDE.md --jq '.content' | base64 -d`

## Build & run

### Prerequisites
- Flutter SDK at `~/development/flutter` (or on PATH)
- `android/local.properties` must exist with secrets (see Secrets section)

### Canonical run command
```bash
./tool/run.sh                  # default device, debug mode
./tool/run.sh -d <device-id>   # specific device
./tool/run.sh --release        # release build
```
`tool/run.sh` reads dart-defines from `android/local.properties` and passes them as `--dart-define` flags. This is the guaranteed injection path — IDE-based builds may not wire dart-defines correctly.

### Important: `flutter clean` when dart-define wiring changes
If you add, rename, or change how a dart-define is wired (in `run.sh`, `build.gradle`, or Dart code that reads it), always run `flutter clean` before rebuilding. Stale build artifacts will silently use old values.

## Secrets / dart-defines

All secrets live in `android/local.properties` (gitignored). Both Android and iOS get them via `--dart-define` from `tool/run.sh` — there is no iOS-specific secrets file.

### Required keys
| Key | What it connects to |
|-----|---------------------|
| `COURSE_CACHE_ENDPOINT` | `caddieai-course-cache` lambda URL |
| `COURSE_CACHE_API_KEY` | API key for course cache lambda |
| `MAPBOX_TOKEN` | Mapbox access token (map rendering + satellite tiles) |
| `LLM_PROXY_ENDPOINT` | `caddieai-llm-proxy` lambda URL |
| `LLM_PROXY_API_KEY` | API key for LLM proxy lambda |
| `LOGGING_ENDPOINT` | `caddieai-logging` lambda URL |
| `LOGGING_API_KEY` | API key for logging lambda |
| `GOLF_COURSE_API_KEY` | Golf Course API (runtime course lookup) |

`DEV_MODE=true` is injected automatically by `run.sh`.

## App architecture

```
lib/
  main.dart              # entry point
  app.dart               # MaterialApp setup
  features/              # feature screens
    caddie/              # AI caddie (voice interaction, advice)
    course/              # course view (map, hole rendering)
    onboarding/          # first-run flow
    history/             # round history
    profile/             # user profile
    dev/                 # dev/debug tools
    splash/              # splash screen
  core/                  # shared infrastructure
    llm/                 # LLM proxy client (Bedrock Nova via lambda)
    mapbox/              # Mapbox integration (map, satellite, layers)
    voice/               # voice input/output
    geo/                 # geolocation utilities
    golf/                # golf domain logic
    courses/             # course data models + loading
    location/            # device location
    logging/             # client-side logging (to logging lambda)
    monetization/        # subscription/paywall
    routing/             # navigation
    storage/             # local persistence
    theme/               # app theme
    weather/             # weather data
    icons/               # custom icons
    build_mode.dart      # debug/release mode detection
  models/                # data models
  services/              # cross-feature services
  shell/                 # app shell (bottom nav, scaffold)
```

## Key integrations

| Integration | Role | Notes |
|-------------|------|-------|
| **Mapbox** | Map rendering, satellite tiles, hole geometry overlay | Token via `MAPBOX_TOKEN` dart-define |
| **LLM proxy** | AI caddie advice (Bedrock Nova) | SSE streaming format; non-streaming fallback available |
| **Course cache** | Hole data, geometry, scorecards | S3-backed lambda |
| **Roboflow** | CV detection of greens/tees/fairways | Corroboration-only (post-CV-pivot); not primary snap source |
| **Voice** | Caddie voice interaction | TTS + STT |

## Cache architecture (KAN-331)

The cloud pipeline (`batch_publish.py`) is the **sole authoritative writer** to the server cache. The app is read-only — it fetches from the cache but never writes to it. The legacy `putCourse` path was removed in KAN-331.

### Canonical cache key format (KAN-328)
`{facility-slug}-{state}` for single courses, `{facility-slug}-{state}/{sub-course-slug}` for multi-course facilities. City slug appended as tiebreaker on same-name-same-state collision.

Examples: `wellshire-golf-course-co`, `kennedy-golf-course-co/west`, `coyote-creek-golf-course-ca`

Key is constructed by `NormalizedCourse.serverCacheKey(name, {state})` in Dart and `make_cache_key(name, state)` in Python. **Both must produce identical output.**

## Multi-course facility handling

Facilities with multiple courses (e.g., Kennedy 27-hole, Cimarron) require special handling:
- **Always re-prompt the course picker** when a multi-course facility is selected. Never cache the selected course combo.
- The algorithmic matcher (not GPT-4o) handles course assignment. Kennedy: 27/27 deterministic. Cimarron exposed limits of rule-based fixes.

## Telemetry / CloudWatch

All client telemetry flows through a single path: app → `caddieai-logging` lambda → CloudWatch `/caddieai/client-logs`.

### Infrastructure
- **Logging service:** `lib/core/logging/` (batched, 10-event threshold or 5s flush)
- **Data sharing toggle:** Profile > "Share Usage Data" (`PlayerProfile.telemetryEnabled`). Default: ON. Takes effect immediately, no restart.
- **Endpoint:** `LOGGING_ENDPOINT` dart-define → `caddieai-logging` lambda with `LOGGING_API_KEY`

### Canonical events (what's tracked)
| Event | Category | What it measures |
|-------|----------|-----------------|
| `log_search_latency` | network | Course search time, query, result count |
| `cache_check` | map | Local/server cache hit/miss + latency |
| `total_ingestion` | map | Full course load time end-to-end |
| `llm_latency` | llm | LLM proxy request time, provider, success/fail |
| `stt_complete` | llm | Speech-to-text latency + word count |
| `tts_start` | general | Text-to-speech latency + voice metadata |
| `map_style_load` | map | Mapbox style load time |
| `layer_add_failure` | map | Missing layer after add attempt |
| `layer_drop_post_audit` | map | Layer disappeared after initial audit |
| `app_startup` | lifecycle | Startup latency + config status |
| `tab_dwell` | general | Time spent on each tab |

### Known gaps (KAN-332)
- Overpass requests — completely dark
- Course-load failure path ("could not load") — no event emitted
- General error/crash handling — no centralized logging

### Rule
**Every new network call or user-facing failure must emit a telemetry event.** All events must respect the `telemetryEnabled` toggle.

## Active work

### JIRA epics
| Epic | What |
|------|------|
| [KAN-251](https://caddieai.atlassian.net/browse/KAN-251) | Flutter migration (Done) |
| [KAN-303](https://caddieai.atlassian.net/browse/KAN-303) | Validate & apply derived hole geometry (KAN-315→318) |
| [KAN-321](https://caddieai.atlassian.net/browse/KAN-321) | Layer 0: hole inventory validation & discovery |
| [KAN-319](https://caddieai.atlassian.net/browse/KAN-319) | Scraper text-relevance gate |
| [KAN-320](https://caddieai.atlassian.net/browse/KAN-320) | Scraper image-relevance gate |

### Active investigation: duplicate cache files (Layer 0 blocker)
- **The Ridge at Castle Pines** and **Coyote Creek Golf Course (Ft Lupton)** — both CO — have multiple cache files in S3 under different slugs. Should always be exactly 1 active file per course.
- Root causes: no canonical course key enforcement, no archive-on-replace, no QA gate before publish.
- Fixes span KAN-321 (canonical key + single-active-file invariant) and KAN-300 (cache inspector in census.ryppl.com management UI).
- Census management UI: `census.ryppl.com`

### Miro board
- **Hole Geometry Pipeline**: https://miro.com/app/board/uXjVHZVNUnM=/ — end-to-end diagram of KAN-315→321, dependency chain, architecture decisions, render-mode buckets. MCP-managed via `mcp__miro__*` tools.

### For geometry pipeline / backend details
See `CaddieAI-infra` CLAUDE.md at `infrastructure/CLAUDE.md` or fetch with:
```bash
gh api repos/oshelot/CaddieAI-infra/contents/CLAUDE.md --jq '.content' | base64 -d
```

## Known gotchas

- **`flutter clean` on dart-define changes** — stale build artifacts silently use old values.
- **LLM streaming** — SSE format is fixed, proxy is available. If streaming fails on-device, test the non-streaming path.
- **Multi-course selection** — never cache; always re-prompt the picker.
- **`tool/run.sh` is canonical** — don't bypass it for IDE run configs unless you've manually wired all dart-defines.
- **infrastructure/ is a nested git repo** — NEVER `rm -rf infrastructure`. See "Repo relationship" section above.
- **AWS profile** — use `default` (not `caddieai` as the infra CLAUDE.md says — that profile doesn't exist on this machine).

## Git workflow

- Default branch: `main`
- Direct commits to `main` for solo dev
- Commits should reference `KAN-###` where applicable
