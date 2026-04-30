# 0008. iOS-as-authoritative for the AI caddie engine port

**Status:** Accepted
**Date proposed:** 2026-04-11
**Date accepted:** 2026-04-11 (KAN-292/293/294/295 split of KAN-277)
**Affected stories:** KAN-292 (S7.1 ExecutionEngine), KAN-293 (S7.2 GolfLogicEngine + HoleAnalysisEngine), KAN-294 (S7.3 LLMRouter), KAN-295 (S7.4 VoiceInputParser)

## Context

KAN-277 (S7) ports the AI caddie backend to Dart. The story-breakdown
called the byte-identical golden-tests requirement non-negotiable,
which raised an immediate problem during the survey: **the iOS and
Android natives disagree with each other on the math.** Some examples:

| Engine | Field | iOS approach | Android approach |
|---|---|---|---|
| GolfLogicEngine | Wind adjustment | Proportional factors (3% / 7% / 12% of base distance) | Fixed yardage values (5 / 10 / 17 / 25 yards) |
| GolfLogicEngine | Lie adjustment | Additive yardage (`+7` for rough) | Multiplicative penalty (`×0.92` for rough) |
| GolfLogicEngine | Slope adjustment | Computed from `Slope` enum (`uphill: base * 0.05`) | Pre-set on `ShotContext.elevationChangeYards` |
| GolfLogicEngine | GI/SGI iron | Adds penalty yardage in bad lies | Substitutes a different club entirely |
| ExecutionEngine | Archetype templates | 12 verbose templates with 13 descriptive string fields each | 6 abstract paths with compact functional attributes |
| HoleAnalysisEngine | Green dimension | Full 2D projection on approach/perpendicular axes | Centroid + degree-to-yardage approximation |

These produce **different outputs for the same input**. The Flutter
port can only honor "byte-identical" against ONE of the natives — and
once it ships, the *other* native is now wrong relative to the new
canonical math.

## Decision

**The iOS native is the authoritative source for every Flutter
engine port in KAN-292 / KAN-293 / KAN-295.** The KAN-294 LLM router
is configuration + orchestration (not byte-identical) and follows
iOS architecture for consistency.

Specific reconciliation calls:

| Engine | Reconciled to | Why iOS over Android |
|---|---|---|
| ExecutionEngine archetype templates | iOS verbose 12-archetype set | UI consumes the descriptive fields directly; Android's compact attributes are harder to render |
| ExecutionEngine archetype selection | iOS branching order | iOS handles edge cases (chip-style preference, partial wedge bands) Android collapses |
| GolfLogicEngine wind | iOS proportional factors | Scales naturally with the player's club distances; fixed yardages bias against shorter hitters |
| GolfLogicEngine lie | iOS additive yardage | Easier to explain to users ("rough adds 7 yards") than a multiplier |
| GolfLogicEngine slope | iOS computes from enum | Cleaner caller API — no need to pre-fill `elevationChangeYards` |
| GolfLogicEngine GI/SGI iron | iOS penalty yardage | Predictable; club substitution mid-recommendation surprises users |
| HoleAnalysisEngine green dimensions | iOS full projection | More accurate; the strategic-advice text leans on these numbers |
| HoleAnalysisEngine bearing math | Both already agree | Direct Haversine, no divergence |
| VoiceInputParser | Hybrid: iOS word lists + Android regex fallback | Lowest-stakes engine; both natives are explicitly tagged as `TODO(migration)` tech debt |
| LLMRouter / LLMProxyService | iOS architecture | Consistency with the engine ports |

## Rationale

- **iOS is more complete.** The native survey found iOS at ~2,528 LoC across the 5 engines vs Android's ~1,348. iOS has more archetype templates, more nuanced adjustment logic, and explicit handling for cases Android collapses.
- **iOS came first.** Both natives diverged from the same original spec; iOS held closer to it. Picking iOS is the smaller delta from the spec the engines were originally designed against.
- **The Caddie screen UI was originally designed against the iOS output shape.** Native UI components (e.g. the execution-plan card with separate `setupSummary`, `ballPosition`, `swingThought` rows) bind directly to iOS field names. Porting Android's compact attributes would break the UI binding.
- **Android needs to be updated post-Flutter regardless.** The migration replaces both native apps. Whatever the Flutter port picks becomes the new canonical math; the legacy Android code is going away with KAN-S16 cutover.

## Consequences

### What this enables

- **One source of truth.** Future developers reading the engine code refer to the iOS Swift originals when they have a question about intent. No "wait, what does Android do here" lookup.
- **Golden tests have a single oracle.** The S7.1 test fixtures are generated from the iOS implementation. If the test passes, the Dart port matches iOS. There is no second comparison to pass.
- **Cleaner divergence reports.** Anyone investigating a "the Flutter recommendation differs from what I got on Android last week" bug can immediately point at this ADR and explain the deliberate change.

### What this commits us to

- **Android natives are now technically outdated** the moment Flutter ships. They will keep producing recommendations until the Flutter app replaces them at cutover (KAN-S16). During that gap, an Android user might see one number and a Flutter beta tester might see a different one. Document this in release notes for any pre-cutover beta build.
- **Re-syncing the iOS tree post-port is allowed.** If the iOS app is patched after the port, the Flutter port may need a refresh — but only via a deliberate ADR amendment, not silently. The engine code should reference the iOS file path + line numbers in comments so future-you knows where to look.
- **Android-only bug fixes are out of scope.** If someone files an Android-only bug against the existing native, the fix lives on the Android side and has zero effect on the Flutter port (which doesn't share code).

### Migration concerns

- **Test fixtures must be derivable from iOS code, not from running iOS.** I don't have a Mac in this environment to compile and run the iOS engine, so the golden test expected values are computed by mentally executing the Swift code (which is in front of me as text). Any future amendment that changes the iOS engine MUST update the test fixtures in the same commit — the test won't catch a Swift-side change because there's no live oracle.

## References

- iOS sources:
  - `ios/CaddieAI/Services/ExecutionEngine.swift` (~502 lines)
  - `ios/CaddieAI/Services/GolfLogicEngine.swift` (~429 lines)
  - `ios/CaddieAI/Services/HoleAnalysisEngine.swift` (~557 lines)
  - `ios/CaddieAI/Services/LLMRouter.swift` (~505 lines)
  - `ios/CaddieAI/Services/LLMProxyService.swift` (~280 lines)
  - `ios/CaddieAI/Services/VoiceInputParser.swift` (~300 lines)
- Android sources (for reference, NOT authoritative):
  - `android/app/src/main/java/com/caddieai/android/data/caddie/ShotExecutionEngine.kt`
  - `android/app/src/main/java/com/caddieai/android/data/caddie/GolfLogicEngine.kt`
  - `android/app/src/main/java/com/caddieai/android/data/caddie/HoleAnalysisEngine.kt`
  - `android/app/src/main/java/com/caddieai/android/data/llm/LLMRouter.kt`
  - `android/app/src/main/java/com/caddieai/android/data/llm/LLMProxyService.kt`
  - `android/app/src/main/java/com/caddieai/android/data/voice/VoiceInputParser.kt`
- KAN-277 (parent story) and KAN-292/293/294/295 (sub-tasks)
- KAN-S7 in `mobile-flutter/docs/KAN-251-STORIES.md`
