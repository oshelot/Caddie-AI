# KAN-S16 — Cutover plan

**Story:** [KAN-286](https://caddieai.atlassian.net/browse/KAN-286)
**Epic:** [KAN-251](https://caddieai.atlassian.net/browse/KAN-251) Flutter migration
**Status:** Code-side complete; platform-side checklist below
**Cutover branch:** the only KAN-251 story authorized to touch `main` directly

This document is the operational checklist the cutover team
runs at the moment of go-live. The Flutter codebase is feature-
complete (S0–S15 all merged); this doc covers the steps that
need humans, real devices, and store-side actions before the
native trees can be deleted from `main`.

---

## Pre-cutover state

After commit `<TBD-cutover-commit>` on
`kan-251-mobile-flutter-scaffold`:

- **16/16 stories shipped** (S0–S15, including KAN-292/293/294/295
  sub-tasks of S7)
- **Test count:** the full `flutter test` suite is green at
  cutover time. Run `flutter test` once before the deletion
  commit and record the count below.
- **`flutter analyze` clean** (verified at every commit during
  the migration)
- **`mobile-flutter/` is the canonical app source.** Both
  `ios/` and `android/` (the native Swift / Kotlin trees at the
  repo root) are scheduled for archival in this story.

## Platform-side actions checklist

These steps require humans at keyboards. **Run them in order.**
Do not skip the QA pass (step 2) — the AC explicitly requires
device validation on a mid-tier iPhone + a mid-tier Android.

### 1. Final code-side sweep (~15 min)

- [ ] On `kan-251-mobile-flutter-scaffold`, pull latest, run
      `cd mobile-flutter && flutter pub get`
- [ ] `flutter analyze` — must report `No issues found!`
- [ ] `flutter test` — must report `All tests passed!`
      Record the test count: `_______`
- [ ] Open the latest screenshots from any KAN-S10 manual run
      and confirm they match the spike's reference images
      (CONVENTIONS §5 defaults: solid hole-lines + Mapbox
      default font for hole labels)
- [ ] Verify every S0–S15 JIRA ticket is in **Done** status

### 2. QA pass (~2 hours, two devices)

Run the scripted interaction below on both:

- **mid-tier iPhone** (iPhone 12 / 13 / 14, iOS ≥ 17)
- **mid-tier Android** (Pixel 6 / 7 / Samsung A-series, Android ≥ 13)

For each device, build with:

```bash
cd mobile-flutter
flutter run -d <device-id> \
  --dart-define=MAPBOX_TOKEN=pk.eyJ1IjoicGF0... \
  --dart-define=COURSE_CACHE_ENDPOINT=https://cache.caddieai.app \
  --dart-define=COURSE_CACHE_API_KEY=... \
  --dart-define=LLM_PROXY_ENDPOINT=https://llm-proxy.caddieai.app \
  --dart-define=LLM_PROXY_API_KEY=... \
  --dart-define=LOGGING_ENDPOINT=https://logs.caddieai.app \
  --dart-define=LOGGING_API_KEY=... \
  --dart-define=SUBSCRIPTION_PRODUCT_ID=com.caddieai.pro.monthly
```

Then walk the **scripted interaction**:

| Step | Action | Expected | iOS ✓ | Android ✓ |
|---|---|---|---|---|
| 1 | Cold start, fresh install | Onboarding wizard appears (KAN-S14) | ⬜ | ⬜ |
| 2 | Skip onboarding | Lands on Course tab (search screen) | ⬜ | ⬜ |
| 3 | Search "Sharp Park", tap result | Course map renders all 7 layers | ⬜ | ⬜ |
| 4 | Tap holes 1, 9, 18 in the hole selector | flyTo with bearing-aware padding | ⬜ | ⬜ |
| 5 | Tap anywhere on the map | Yellow line + yardage HUD | ⬜ | ⬜ |
| 6 | Switch to Caddie tab | Shot input form renders | ⬜ | ⬜ |
| 7 | Tap "Get recommendation" | Deterministic card with club + target | ⬜ | ⬜ |
| 8 | Tap "Ask AI for commentary" | LLM tokens stream into the card | ⬜ | ⬜ |
| 9 | Listen to TTS playback | Voice persona matches Profile setting | ⬜ | ⬜ |
| 10 | Speak "150 yards into the wind, fairway" | Form fields update | ⬜ | ⬜ |
| 11 | Switch to History tab | Empty state (or list if any prior shots) | ⬜ | ⬜ |
| 12 | Switch to Profile tab, change handicap, save | Snackbar confirms save | ⬜ | ⬜ |
| 13 | Re-open Profile tab | Handicap edit persisted | ⬜ | ⬜ |
| 14 | Toggle Telemetry off, save | `LoggingService.isEnabled` flips | ⬜ | ⬜ |
| 15 | Tap "Subscribe" (S15 path) | StoreKit / Play Billing sheet appears | ⬜ | ⬜ |
| 16 | Complete sandbox purchase | Banner ad disappears (paid tier) | ⬜ | ⬜ |
| 17 | Force-quit, reopen | Subscription state restored | ⬜ | ⬜ |
| 18 | Force-quit Caddie screen mid-stream | No timer / stream leaks (logcat clean) | ⬜ | ⬜ |

### 3. Pre-cutover production smoke (~30 min)

- [ ] Submit a TestFlight build with the same `--dart-define`s
      as step 2
- [ ] Submit an Internal Testing track build to Play Console
- [ ] At least one team member walks the scripted interaction
      on a TestFlight install (different device than step 2)
- [ ] Confirm the `layer_render`, `llm_latency`, `tts_latency`,
      `stt_latency`, and `log_search_latency` events all appear
      in the production CloudWatch dashboard at the expected
      cardinality

### 4. Native tree archival (~15 min)

The KAN-S16 AC requires the native trees to be deleted in a
**separate commit on `main`** with a clean revert path. Do NOT
combine the deletion with any other change.

```bash
git checkout main
git pull
git rm -r ios/ android/
git commit -m "KAN-286: archive native iOS + Android trees

The Flutter migration (KAN-251) shipped 16/16 stories on
mobile-flutter/. The native Swift / Kotlin trees at the repo
root are no longer the production source. Delete them in a
single commit so any post-cutover regression has a clean
revert path:

  git revert <this-commit-sha>

restores the pre-cutover state.

Co-Authored-By: <cutover author>"
```

**Do NOT push yet.** Let the next step run first.

### 5. CI/CD pipeline updates (~1 hour)

The existing CI pipelines build the native iOS / Android apps.
After cutover they need to build the Flutter app. The exact
edits depend on the CI provider (GitHub Actions vs CircleCI vs
Bitrise) — the team should:

- [ ] Update the iOS workflow to run `cd mobile-flutter && flutter build ios`
      (instead of `xcodebuild` against the native project)
- [ ] Update the Android workflow to run `cd mobile-flutter && flutter build apk`
      (instead of `gradle assembleRelease`)
- [ ] Plumb the production `--dart-define`s through the CI
      secret store (Mapbox token, Course Cache endpoint + key,
      LLM proxy endpoint + key, Logging endpoint + key)
- [ ] Update any branch-protection rules that gate `main` on
      the old native CI checks
- [ ] Verify a fresh push to `main` produces a green CI run
      against the Flutter build

### 6. Push the cutover commit (~5 min)

After the CI pipeline is updated AND the QA pass + smoke tests
all passed:

```bash
git push origin main
```

Then immediately:

- [ ] Watch CI for the post-push run
- [ ] If anything goes red, `git revert <cutover-commit-sha>`
      and investigate offline. The native trees come back
      cleanly because step 4 was a single-commit deletion.

### 7. Store submission (~30 min + store review time)

- [ ] Bump `version` in `mobile-flutter/pubspec.yaml`
      (e.g. `2.0.0+1` to mark the Flutter cutover)
- [ ] Build release artifacts:
      ```bash
      cd mobile-flutter
      flutter build ipa --release --dart-define=...
      flutter build appbundle --release --dart-define=...
      ```
- [ ] Upload IPA to App Store Connect, mark for review
- [ ] Upload AAB to Play Console, promote from Internal Testing
      to Production rollout (start at 10% staged rollout)
- [ ] Monitor crash-free rate in the first 24h. If < 99.5%,
      pause the rollout and triage.

### 8. Post-cutover infra cleanup (~1 hour)

- [ ] Remove the `ios/` + `android/` build cache directories
      from the team's nightly storage cleanup scripts
- [ ] Update root `README.md` to point at `mobile-flutter/` as
      the canonical source
- [ ] Update infra docs that reference the native build
      pipelines (Confluence pages, Notion tickets, Slack
      bookmarks)
- [ ] Archive the `kan-251-mobile-flutter-scaffold` branch
      after `main` has caught up (don't delete — keeps the
      review history accessible)

---

## Feature parity matrix

Cross-platform parity check. Every row should be **green** on
both columns by step 4 above. If any row is red, hold the
deletion commit until the parity gap is closed.

| # | Feature | iOS native | Android native | Flutter port |
|---|---|---|---|---|
| 1 | App shell + 4-tab nav (Caddie / Course / History / Profile) | ✓ | ✓ | KAN-271 ✓ |
| 2 | Local storage + profile persistence | ✓ | ✓ | KAN-272 ✓ |
| 3 | Logging + telemetry to CloudWatch | ✓ | ✓ | KAN-273 ✓ |
| 4 | Location service + permission gate | ✓ | ✓ | KAN-274 ✓ |
| 5 | Course cache + Golf Course API client | ✓ | ✓ | KAN-275 ✓ |
| 6 | Weather (Open-Meteo + wind projection) | ✓ | ✓ | KAN-276 ✓ |
| 7 | ExecutionEngine — pre-LLM shot setup | ✓ | partial† | KAN-292 ✓ |
| 8 | GolfLogicEngine — distance + club selection | ✓ | divergent‡ | KAN-293 ✓ |
| 9 | HoleAnalysisEngine — geometry + hazards | ✓ | partial† | KAN-293 ✓ |
| 10 | LLMRouter + LLMProxyService + streaming | ✓ | ✓ | KAN-294 ✓ |
| 11 | VoiceInputParser — heuristic transcript extraction | ✓ | ✓ | KAN-295 ✓ |
| 12 | STT + TTS speech I/O | ✓ | ✓ | KAN-278 ✓ |
| 13 | Course search screen | ✓ | ✓ | KAN-279 ✓ |
| 14 | Course map screen (7 layers + flyTo + tap-to-distance) | ✓ | ✓ | KAN-280 ✓ |
| 15 | Caddie screen (form + voice + LLM + TTS) | ✓ | ✓ | KAN-281 ✓ |
| 16 | History + scoring screen | ✓ | partial† | KAN-282 ✓ |
| 17 | Profile + settings + API config | ✓ | ✓ | KAN-283 ✓ |
| 18 | Onboarding wizard | ✓ | ✓ | KAN-284 ✓ |
| 19 | Subscriptions + ads + ATT + review | ✓ | ✓ | KAN-285 (architecture)§ |
| 20 | Custom CaddieAI icon set | ✓ | ✓ | KAN-291 ✓ |
| 21 | Mapbox 7-layer overlay rendering | ✓ | ✓ | KAN-280 (CONVENTIONS §5 defaults)¶ |

**† partial:** the Android native shipped a leaner version of
this feature. Per ADR 0008, the Flutter port follows the iOS
shape (which is more complete). Android post-cutover alignment
is deferred indefinitely — the cutover deletes the Android
native source, so there's nothing left to align.

**‡ divergent:** GolfLogicEngine wind/lie/slope formulas
diverge between iOS (proportional / additive) and Android
(fixed-yardage / multiplicative). ADR 0008 picks iOS as
authoritative for the Flutter port. The user-visible
recommendations may differ slightly from what the Android
native would have produced for the same input — this is
expected and documented in the release notes.

**§ architectural:** the abstraction layer (`SubscriptionService`,
`AdService`) ships in KAN-285 with `StubSubscriptionService` /
`StubAdService` test impls. The production wiring against
`in_app_purchase` + `google_mobile_ads` is a follow-up KAN
ticket the cutover team picks up before the store submission
in step 7. Per ADR 0009.

**¶ CONVENTIONS §5 defaults:** the Flutter port renders
hole-lines as **solid white** (not dashed) and hole-labels in
the **Mapbox SATELLITE_STREETS default font** (not DIN Pro
Bold). Both decisions are forced by upstream Mapbox bugs
(mapbox/mapbox-maps-flutter#1121 and #1122) that silently drop
the dashed-line and custom-font properties on iOS. ADR 0008 +
KAN-270 retest results document the rationale. Visual diff
from the iOS native: dashes are gone, font is sans-serif. Flag
for product before submission.

---

## Known follow-ups (NOT blocking cutover)

These items are tracked outside this story and don't block the
deletion commit:

1. **Receipt validation server-side.** KAN-285 / ADR 0009 —
   today the subscription state is local-only. A future ticket
   adds a `validateReceipt(token)` Lambda call.
2. **In-app-purchase + google-mobile-ads production wiring.**
   KAN-285 architectural layer is in; the platform-plugin
   wiring against real ad-unit IDs and product IDs lands when
   the App Store Connect / AdMob setup is finalized.
3. **Mid-tier iPhone retest of the dashed-line bugs** (KAN-270
   AC #2). Hardware-gated; the retest ran on iPhone 17 only.
   When a 12/13/14-era device is available, re-verify Bug 2/3
   are still present so we know whether CONVENTIONS §5 defaults
   can be relaxed.
4. **Bag editor in the Profile screen** (KAN-S13 note). Per-club
   carry distance editing isn't in the current Profile form.
   Users with custom bags set them via the KAN-272 native
   migration importer or via a future "Edit bag" sub-screen.
5. **Stay-in-touch contact form** (KAN-S13 note). Endpoint
   wasn't confirmed during the migration. Adds a single HTTP
   POST when product confirms the destination.
6. **Tee-box selection at search-result entry** (KAN-S9 note).
   The map screen's hole picker handles tee selection per-hole;
   a search-level picker would need an extra fetch and is
   deferred until product asks for it.
7. **Dashed tap-to-distance overlay** (CONVENTIONS §5 option b).
   Solid yellow today; chunked-LineString workaround is a
   separate KAN ticket if product wants the dashed visual back.
8. **Mid-stream LLM fallback** (KAN-294 note). Today the router
   only falls back BEFORE the first chunk arrives. Mid-stream
   fallback would require buffering + replay logic.
9. **`CoursePlaceholder` filename rename.** S10 / S9 left the
   file named `course_placeholder.dart` even though it's no
   longer a placeholder. Rename + reference update is a
   mechanical follow-up.
10. **`HistoryPage` scorecard detail screen.** S12 ships the
    list; the per-scorecard detail view is a follow-up once
    product confirms the design.

---

## Revert procedure

If the cutover causes a regression after step 6:

```bash
# 1. Revert the deletion commit (brings the native trees back)
git revert <cutover-commit-sha>
git push origin main

# 2. Revert the CI pipeline update (separate commit, also single-commit)
git revert <ci-update-commit-sha>
git push origin main

# 3. The store submission in step 7 stays paused — the new
#    version isn't released yet. No customer impact.
```

Investigate the regression on `kan-251-mobile-flutter-scaffold`
(or a fresh branch off it), fix it, and re-run the cutover from
step 1 once the fix lands.
