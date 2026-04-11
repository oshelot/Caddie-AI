# KAN-251 — Flutter migration story breakdown (draft)

**Status:** DRAFT for review. These stories have NOT been created in
JIRA yet. Approve or amend this doc first; creation is a batch
operation against the shared project.

**Source of truth for the inventory:** native Swift/SwiftUI app under
`ios/CaddieAI/` and Kotlin/Compose app under
`android/app/src/main/java/com/caddieai/android/`. Feature survey
conducted 2026-04-10 during KAN-270 planning pass. ~72 Swift files /
~17k LoC + ~88 Kotlin files / ~14k LoC.

**Cross-cutting acceptance criteria** (from `docs/CONVENTIONS.md`)
that apply to **every** story below unless explicitly marked N/A:

- **C-1.** `initMapbox()` is awaited before `runApp` — touched only
  by stories that construct a `MapWidget`.
- **C-2.** Style-layer mutations use `tryAddLayer` / `verifyLayersPresent`
  / `safeGetLayer` helpers from `lib/core/mapbox/layer_helpers.dart` —
  never `style.addLayer` directly.
- **C-3.** Any performance claim specifies measurement tool: DevTools
  timeline for Dart UI, Android GPU Profiler / Xcode Instruments for
  end-to-end. `FrameTiming` is NOT an end-to-end map metric.
- **C-4.** `mapbox_maps_flutter` version is pinned; no bumps without
  re-running the KAN-252 spike's scripted interaction on both
  platforms.
- **C-5.** Every PR updates `mobile-flutter/test/` with at least one
  new unit or integration test proving the new contract. Pure-Dart
  tests preferred; no server-cache or device-on dependency in unit
  tests.

## Story list (16 stories)

Grouped by layer. Order within each layer is not strict, but the
dependency arrows (`→`) encode hard blockers.

### Foundation (4 stories — parallel)

**KAN-S1. App shell: routing, theme, tab bar, and bootstrap**
- Size: Medium
- Blocks: everything else in the migration
- Scope:
  - Pick and install routing library (recommend `go_router`).
  - Port the 4-tab bottom navigation (Caddie / Course / History / Profile).
  - Dark-mode Material 3 theme matching existing iOS/Android visual language.
  - Shared widgets for cards, list rows, HUD badges.
  - Wire `initMapbox()` into `main.dart` — already scaffolded, needs
    to survive the routing integration.
- Custom ACs:
  - Tab bar + placeholder screens render on both platforms from a
    cold start in ≤ 2 s.
  - All four tabs accessible and switchable; state preserved on
    back-stack navigation.
  - Theme constants exposed as a `CaddieTheme` class; no hex literals
    inside feature screens.
- Cross-cutting: C-1, C-5.

**KAN-S2. Local storage and profile persistence**
- Size: Medium
- Blocks: S5, S7, S11, S12, S13, S14, S15 (anywhere profile/history is read)
- Scope:
  - Pick and install storage library (recommend `shared_preferences` +
    `hive_ce` for structured profile/history, or `drift` if we want a
    proper query layer — flag for decision).
  - Port `PlayerProfile` model from iOS + Android.
  - Port `ShotHistoryEntry` and `ScorecardEntry` models.
  - Write a one-time migration importer that reads existing native
    `UserDefaults` (iOS) / `DataStore` (Android) payloads and upserts
    into the Flutter store on first launch, so users don't lose their
    profile when the native app is replaced.
- Custom ACs:
  - Round-trip test: write profile → read profile → assert equal.
  - Migration importer produces correct profile for a captured set of
    native-format fixtures (commit a few sample payloads in
    `test/fixtures/migration/`).
  - No plaintext API keys in the store — use platform secure storage
    for LLM keys (iOS Keychain / Android EncryptedSharedPreferences,
    via `flutter_secure_storage`).
- Cross-cutting: C-5.
- ⚠️ Open question: **storage library choice**. Decide before
  starting — see KAN-270 for the decision pattern.

**KAN-S3. Logging and telemetry client**
- Size: Small
- Blocks: nothing (fire-and-forget), but everything else benefits
- Scope:
  - Port the native `LoggingService` / `DiagnosticLogger` contract.
  - Batched HTTP POST to the existing logging endpoint
    (`3wcw5juj2d.execute-api.us-east-2.amazonaws.com/prod/logs`) —
    reuse the same API key via `--dart-define`.
  - Log categories matching native: `llm`, `network`, `general`,
    `lifecycle`, `map`.
  - Respect `PlayerProfile.telemetryEnabled` opt-in flag.
- Custom ACs:
  - Batch flush every 10 events OR every 5 seconds, whichever first.
  - Offline queue: if the logging endpoint is unreachable, buffer up
    to 200 events in memory and drop-oldest on overflow.
  - `layer_render`, `llm_latency`, `stt_latency`, `tts_latency` event
    names match native exactly — so dashboards built against native
    data keep working after migration.
- Cross-cutting: C-5.

**KAN-S4. Location and permissions foundation**
- Size: Small
- Blocks: S5, S9, S10, S11 (anywhere location is needed)
- Scope:
  - Install `geolocator` + `permission_handler`.
  - `LocationService` abstraction with a unified API: current
    location, heading stream, permission state.
  - Permission prompts wired to iOS `Info.plist` and Android manifest
    (already pre-declared in the scaffold).
- Custom ACs:
  - First-run permission prompt appears before the Course tab's map
    screen renders, not after — avoid the native-app UX regression
    where the map loads with no location.
  - Denied-permission path renders a clear "enable location in
    settings" banner, doesn't crash.
  - `LocationService` is mockable for tests.
- Cross-cutting: C-5.

### Data / service layer (3 stories — parallel)

**KAN-S5. Course cache + Golf Course API clients**
- Size: Medium
- Blocks: S9, S10 (course search, course map)
- Depends on: S1 (shell), S2 (storage for offline cache), S4 (location)
- Scope:
  - Port `ServerCacheClient.kt` / iOS equivalent. Endpoints:
    `/courses/search?q=&lat=&lon=&platform=ios&schema=1.0`,
    `/courses/{cacheKey}?platform=ios&schema=1.0`.
  - Port the Golf Course API client (external provider used for
    initial discovery before the server cache takes over).
  - Wire into the existing `NormalizedCourse.fromJson` in
    `lib/models/normalized_course.dart` (already lifted from spike).
  - Disk cache for recently fetched courses with TTL matching native.
- Custom ACs:
  - `platform=ios&schema=1.0` must be passed on every call — the
    Android-platform serialization is a different shape and NOT
    compatible with our lifted models. Test proves this.
  - Cache miss → search → fetch → persist → return happy path covered
    by an integration test against a test-server double.
  - Unit test covers the "server returned gzip" path that tripped us
    during the spike (curl needs `--compressed`; Dart's `http` handles
    it automatically, but verify).
- Cross-cutting: C-5.

**KAN-S6. Weather client and wind-vector provider**
- Size: Small
- Blocks: S11 (caddie screen — wind is a shot input)
- Depends on: S4 (location)
- Scope:
  - Identify the existing weather provider in the native apps (the
    survey couldn't determine which — read the iOS/Android service
    class and port it).
  - Return wind speed, wind direction, temperature for a given
    lat/lon.
  - Project wind vector relative to a hole's tee-to-green bearing so
    the caddie screen can display "10 mph into wind" vs "10 mph
    tailwind".
- Custom ACs:
  - Stale-while-revalidate: cached reading returned instantly, fresh
    reading fetched in background if older than 5 min.
  - Unit test covers the projection math (unit circle rotation).
- Cross-cutting: C-5.

**KAN-S7. AI caddie backend: LLM router + execution engine + hole analysis**
- Size: **Large** (probably the biggest story in the migration)
- Blocks: S11 (caddie screen)
- Depends on: S1, S2, S5 (course geometry for hole analysis), S6 (weather)
- Scope:
  - Port `LLMRouter`: routes to OpenAI / Claude / Gemini direct for
    free tier, or `LLMProxyService` (Lambda) for paid tier. Match
    the native router's provider selection logic.
  - Port `ExecutionEngine`: deterministic pre-LLM shot recommendation
    (club, swing direction, execution notes) given distance, lie,
    handicap, wind, slope, weather.
  - Port `HoleAnalysisEngine`: given a hole's geometry + the player's
    location, compute hazard distances, optimal targeting line,
    slope/elevation impact.
  - Port `GolfLogicEngine`: wind push, slope compensation, confidence
    adjustments.
  - Port `VoiceInputParser`: hand-rolled regex/heuristics for
    extracting distance/club/lie from voice transcript. Surface as a
    `TODO(migration)` marker — this is tech debt per the native survey.
  - Streaming LLM responses via Dart async streams.
- Custom ACs:
  - Golden tests: given a fixed input (distance, wind, handicap),
    `ExecutionEngine` returns byte-identical output to the iOS and
    Android versions on a small corpus of known inputs. Non-negotiable
    — this is the one place where cross-platform divergence would
    mean a regression in user-facing recommendations.
  - Streaming: first token arrives within 1.5 s on the paid proxy
    path under normal network, measured via
    `LoggingService.llm_latency` (C-3 applies — specify measurement
    method).
  - Router correctly falls back to the next provider on failure and
    logs the fallback with tier + provider metadata.
- Cross-cutting: C-3, C-5.
- ⚠️ Break out a sub-story if any of these engines exceeds ~500 lines
  of Dart; they're each roughly 500-900 lines in the native code and
  may deserve their own story.

### Voice I/O (1 story)

**KAN-S8. Speech I/O: STT + TTS services**
- Size: Medium
- Blocks: S11 (caddie screen — voice input/output is a core feature)
- Depends on: S1, S3 (telemetry for latency logs)
- Scope:
  - STT via `speech_to_text` plugin — partial results, final
    transcription, latency tracking, iOS + Android permission
    handling.
  - TTS via `flutter_tts` plugin — configurable voice gender
    (male/female) and accent (American/British/Scottish/Irish/
    Australian), pitch adjustment per gender, speech rate ~0.5-0.95x.
  - Mockable interfaces for unit tests of the caddie screen's
    voice-interaction logic.
- Custom ACs:
  - All 10 voice combos (2 genders × 5 accents) render on iOS and
    Android.
  - STT partial results stream into the UI < 300 ms after each
    syllable (subjective — verify manually, not gated).
  - Microphone permission prompt triggered on first use with clear
    rationale text.
- Cross-cutting: C-5.

### Feature screens (5 stories — parallel after foundation + services)

**KAN-S9. Course search screen**
- Size: Medium
- Depends on: S1, S2, S4, S5
- Scope:
  - Port the native Course tab's search UX: text search, nearby-by-
    location, result list, course preview card, tee-box selection
    for result entry.
  - Server cache client integration (S5).
- Custom ACs:
  - Search result list renders within 1 s of typing stop
    (debounced), measured via `log_search_latency` telemetry event.
  - "No results" state + "location required" state handled.
  - Tapping a course navigates to the Course Map screen (S10) via
    go_router.
- Cross-cutting: C-3, C-5.

**KAN-S10. Course map screen (7-layer overlay + flyTo + tap-to-distance)**
- Size: **Large**
- Depends on: S1, S2, S4, S5
- Scope:
  - Port the course map from the spike's `map_screen.dart` BUT using
    the hardened `tryAddLayer` + `verifyLayersPresent` helpers from
    `lib/core/mapbox/layer_helpers.dart`. Do NOT copy the raw
    `addLayer` calls from the spike.
  - All 7 layers: boundary, water, bunkers, greens, tees, hole-lines,
    hole-labels — rendered with the **CONVENTIONS §5 defaults** (solid
    hole-lines, Mapbox default font for hole-labels). Do **NOT** set
    `LineLayer.lineDasharray` or `SymbolLayer.textFont` — both are
    silently dropped on iOS in the pinned `mapbox_maps_flutter` version
    (SPIKE_REPORT §4 Bugs 2 & 3, confirmed still broken on 2.21.1 in
    the KAN-270 retest).
  - Bearing-aware `flyTo` via `cameraForCoordinatesPadding` with
    HUD-aware insets (`EdgeInsets(top: 80, left: 40, bottom: 200, right: 40)`).
  - Hole selector + highlight-selected-hole logic.
  - Tap-to-distance overlay with a **solid** yellow line (Bug 2 means
    the dashed style on the existing iOS native app cannot be
    reproduced cross-platform; the spike screenshots show the solid-
    line equivalent).
  - Player location puck.
- Custom ACs:
  - `verifyLayersPresent` audit at style-loaded time logs presence
    of all 7 layers; if any are missing, the screen shows a
    dev-facing error banner (`kDebugMode` only) and logs a
    `layer_add_failure` telemetry event with the missing layer id.
  - Re-audits before the first hole-tap interaction to catch the
    Bug 2/3 mutated symptom (audit-passing-then-disappearing). If a
    layer was present at style-load and is missing on first
    interaction, log a distinct `layer_drop_post_audit` event.
  - Works on both iOS and Android with visual parity (per-layer
    paint matches the KAN-252 spike's screenshots, accepting the
    documented CONVENTIONS §5 defaults for dashes and typeface).
  - Tap-to-distance pre-warms the tap-line source at style-loaded
    time (addresses the 80.3 ms first-tap outlier from
    `flutter-spike/SPIKE_REPORT.md §5.4`).
  - Layer-render latency ≤ 800 ms on mid-tier devices (measured via
    `layer_render` telemetry event).
- Cross-cutting: **C-1, C-2, C-3, C-4, C-5** — all of them apply.
- ✅ **No longer blocked on KAN-270 AC #4 / AC #5.** The KAN-270 retest
  forced both decisions toward the simplest path (solid lines, Mapbox
  default font) — see CONVENTIONS §5. If a follow-up story decides to
  implement option (b) chunked-LineString dashes or option (b) bundled
  PBF glyph source, that work lands as a SEPARATE story; this story
  does not gate on those decisions.

**KAN-S11. Caddie (shot input + AI chat) screen**
- Size: **Large** — the flagship UX
- Depends on: S1, S2, S6, S7, S8, S10 (needs map for hole context)
- Scope:
  - Port the Caddie tab UX: shot-input form (distance, lie, club,
    wind, elevation, slope), optional voice input, optional hole
    image upload (paid tier only).
  - Streaming LLM response rendering with token-by-token animation.
  - Execution engine integration (pre-LLM deterministic baseline
    shown while LLM streams).
  - Hole context pulled from the selected course + hole (S10).
  - TTS playback of the final recommendation (S8).
- Custom ACs:
  - End-to-end test: voice input → `VoiceInputParser` → structured
    context → `ExecutionEngine` baseline → LLM stream → TTS speak.
  - Token-by-token streaming renders without jank on mid-tier
    devices (C-3 applies — specify measurement).
- Cross-cutting: C-3, C-5.

**KAN-S12. History and scoring screen**
- Size: Small-Medium
- Depends on: S1, S2
- Scope:
  - Port the History tab: shot log list, shot detail drawer showing
    AI reasoning + execution outcome.
  - Port the scorecard UI behind the existing `scoringEnabled`
    feature flag from the native profile.
- Custom ACs:
  - Respects `PlayerProfile.scoringEnabled` — if false, scorecard UI
    hidden. (Native note: scoring UI appears half-built in the iOS
    code — confirm the target design before porting, flag as an
    open question.)
  - Sort + filter by date, course, shot type.
- Cross-cutting: C-5.

**KAN-S13. Profile + settings + API configuration**
- Size: Medium
- Depends on: S1, S2, S7 (for the LLM provider/model/keys section)
- Scope:
  - Port the Profile tab: handicap editor, club distance editor
    ("bag"), caddie voice config (gender, accent, persona),
    aggressiveness level, tee-box preference, feature flags
    (telemetry, beta image analysis, scoring).
  - API settings screen: LLM provider picker (OpenAI/Claude/Gemini/
    Proxy), model picker, API key entry, free/paid tier switch.
  - Stay-in-touch contact form (simple HTTP POST to an existing
    endpoint — check native for which one).
- Custom ACs:
  - API keys stored in platform secure storage (Keychain / Encrypted
    SharedPreferences), NOT in the shared profile store. Test proves
    this — attempting to read the raw profile file does not leak keys.
  - All feature flags round-trip through the profile store.
- Cross-cutting: C-5.

### Onboarding + monetization (2 stories)

**KAN-S14. Onboarding flow**
- Size: Medium
- Depends on: S1, S2, S13 (sets fields that profile screen also edits)
- Scope:
  - Port the 6-step onboarding wizard: setup notice → contact info →
    handicap (swing capture) → short-game preferences → club bag →
    tee box preference.
  - Splash screen + first-run detection.
- Custom ACs:
  - First-run detection uses the profile store, not a separate
    "has-onboarded" flag — single source of truth.
  - Users can skip any step and complete onboarding later from the
    Profile tab.
- Cross-cutting: C-5.

**KAN-S15. Monetization: subscriptions + ads**
- Size: **Large** — cross-platform store work is always more than it looks
- Depends on: S1, S2, S13
- Scope:
  - Subscriptions via `in_app_purchase` (wraps StoreKit 2 on iOS and
    Play Billing on Android). Single product: `com.caddieai.pro.monthly`.
  - Ads via `google_mobile_ads` (banner on free tier, optional on
    paid).
  - Subscription state gates the LLM router's paid-proxy path (S7)
    and the ads visibility.
  - App Tracking Transparency prompt on iOS for ad personalization.
  - Play Review API / iOS in-app review trigger on Nth successful
    caddie interaction.
- Custom ACs:
  - Fresh install on each platform: free tier → ads show → subscribe
    → ads hide → restore purchases on reinstall works.
  - Receipt validation happens server-side if the native app already
    does it (check); otherwise local validation with a `TODO` to move
    server-side.
- Cross-cutting: C-3 (subscription flow latency), C-5.

### Cutover (1 story)

**KAN-S16. Native decommissioning and cutover**
- Size: Medium
- Depends on: **all other stories** (blocks on every one of S1-S15)
- Scope:
  - QA pass: scripted interaction on mid-tier iPhone + mid-tier
    Android, both pre- and post-cutover.
  - Archive or delete `ios/` and `android/` native trees.
  - Update CI/CD pipelines to build the Flutter app, not the native
    apps.
  - Update any infra docs / READMEs referencing the native codebases.
  - Bump app version and submit to both stores from the Flutter
    build.
  - Post-submission smoke test on production.
- Custom ACs:
  - All of S1-S15 are Done.
  - Feature parity checklist (one row per screen / flow) is ticked
    off for both platforms.
  - Native trees deleted in a **separate commit on main** with a
    clean revert path in case of post-cutover regression.
- Cross-cutting: C-5.

---

## Dependency graph

```
          S1 (shell) ←───────────────────────────────────────┐
            │                                                │
    ┌───────┼───────┬────────┐                               │
    ▼       ▼       ▼        ▼                               │
    S2    S3       S4        │                               │
  (store)(log) (loc/perm)    │                               │
    │       │      │         │                               │
    ├───────┼──────┤         │                               │
    ▼       ▼      ▼         │                               │
    S5  S6      S8           │                               │
  (courses)(weather)(voice)  │                               │
    │    │      │            │                               │
    └──┬─┴──┬───┴─────► S7 (AI backend — depends on S5+S6)  │
       │    │              │                                 │
       ▼    ▼              ▼                                 │
       S9  S10  ◄──────  S11 (caddie screen)                │
       (search) (map)       │                                │
                            │                                │
                            S12  S13  S14  S15 (history/profile/onboarding/monetization)
                            │    │    │    │                 │
                            └────┴────┴────┴────────► S16 (cutover) ◄──┘
```

Not strict — S3 (logging) and S6 (weather) can slot in wherever. Just
don't try to land S11 before S7 or S10, and don't try S16 before
everything else is green.

---

## Summary for KAN-270

- **Total stories:** 16
- **Large:** S7 (AI backend), S10 (course map), S11 (caddie screen),
  S15 (monetization) — each likely 3-5 days
- **Medium:** S1, S2, S5, S8, S9, S13, S14, S16 — each 1-3 days
- **Small:** S3, S4, S6, S12 — each < 1 day
- **Blocked on KAN-270 decisions:** S10 (two sub-ACs — dashes and
  typeface)
- **Rough engineer-days:** 30-50 for one engineer, 20-35 with two
  working in parallel on independent tracks

Cross-cutting ACs from `docs/CONVENTIONS.md` are referenced per story
above. The scaffold already ships the helpers (`initMapbox`,
`tryAddLayer`, `verifyLayersPresent`, `safeGetLayer`) — no story should
be writing those from scratch.

---

## Open questions for the planning pass

Capture decisions on these before the first PR:

1. **Storage library** (S2): `shared_preferences` + `hive_ce` vs
   `drift`. Trade-off: Hive is simpler; Drift gives us query power
   for shot history. Recommend Hive.
2. **Routing library** (S1): `go_router` vs `auto_route` vs vanilla
   `Navigator 2.0`. Recommend `go_router` — most idiomatic for 2026.
3. **State management** (all UI stories): `riverpod` vs `bloc` vs
   vanilla `ChangeNotifier`. Recommend `riverpod` — scales from
   single-screen to app-wide.
4. **Monetization plugin** (S15): `in_app_purchase` (official) vs
   `purchases_flutter` (RevenueCat). Trade-off: RC is easier for
   entitlement management; `in_app_purchase` is free. Recommend
   `in_app_purchase` for scaffolding, revisit if entitlement
   complexity grows.
5. **Shot history query strategy** (S12): do we need to index by
   course? By date? By club? Affects whether S2 picks Hive or Drift.

None of these are blockers for KAN-270 closure, but the first three
should be captured as ADRs in `docs/adr/` before the first story that
depends on them is picked up.
