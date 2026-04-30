# 0002. State management framework

**Status:** Accepted — pre-decided in the KAN-251 epic description.
**Date accepted:** 2026-04-10 (epic creation; ratified post-spike on 2026-04-11)
**Affected stories:** All UI-touching stories (KAN-271 through KAN-285)

## Context

The KAN-251 Flutter migration needs a state management / DI framework that will scale from a single-screen scaffold to ~16k LOC of UI code across 4 tabs, onboarding flows, modals, streaming LLM interactions, and a course map with frequent style mutations.

The native iOS app uses SwiftUI's `@Observable` macro (no external DI framework). The native Android app uses Hilt (DI) + Jetpack Compose ViewModel + Kotlin Coroutines.

The Flutter ecosystem has three credible options:

1. **Riverpod** — provider-based, compile-time-safe, scales from single-widget to app-wide
2. **`flutter_bloc` (Bloc / Cubit)** — event-driven, opinionated, popular in enterprise Flutter
3. **Vanilla `ChangeNotifier` + `Provider`** — minimal dependency, lightweight, more boilerplate at scale

## Decision

**Use Riverpod.**

This decision was **pre-committed in the KAN-251 epic description** at epic-creation time, before the spike. The post-spike planning pass (KAN-270) reviewed the choice against the surveyed scope and found no reason to revisit. This ADR is recording the decision, not deciding it.

## Rationale

- **Scales without rewrites.** Riverpod providers compose cleanly. A `Provider` for a single piece of derived state can be promoted to a `StateNotifierProvider` or `AsyncNotifierProvider` without changing call sites.
- **Compile-time safety.** Riverpod's code generation (via `riverpod_generator`) gives compile-time type checking on every provider lookup. Cuts a class of runtime errors common in `provider`/`get_it`-based stacks.
- **Built for async-heavy domains.** The KAN-251 app is dominated by streaming LLM responses (KAN-281), live location updates (KAN-274), and course cache fetches (KAN-275). `AsyncValue` and `AsyncNotifier` make these patterns first-class.
- **DI for free.** Riverpod doubles as a DI container — no separate `get_it` or `injectable` package needed.
- **Compatible with the routing choice (ADR 0001).** `go_router` instances live in providers, rebuild on auth/profile state changes, and integrate cleanly.

## Alternatives considered

### Bloc / Cubit (`flutter_bloc`)

**Pros:** Mature, popular in enterprise Flutter, strong testability, very explicit event/state separation.

**Cons:** Heavier boilerplate per feature. The event/state ceremony is overkill for the app's scale (~16k LOC across multiple tabs but with relatively shallow per-screen state). The team would write more files per story than with Riverpod.

**Verdict:** Reasonable choice for a larger team or a more event-sourcing-heavy domain. Not the right fit here.

### `ChangeNotifier` + `provider`

**Pros:** Smaller dependency footprint. Familiar to anyone who's read Flutter intro docs.

**Cons:** Boilerplate scales linearly with screen count. No first-class `AsyncValue` equivalent — async patterns require manual state machines on top of `ChangeNotifier`. Compile-time safety is weaker.

**Verdict:** Fine for a one-screen prototype (the spike used `setState` exactly because of this). Not the right fit for a 4-tab production app.

## Consequences

### What this enables

- All UI stories use `Riverpod` providers for state and DI from day 1
- `riverpod_generator` codegen step is wired into the dev loop early
- Async-heavy paths (LLM streams, location streams, cache fetches) get `AsyncValue` for free
- Tests use Riverpod's `ProviderContainer` for isolated unit tests of business logic

### What this commits us to

- A `build_runner` codegen step in the dev loop (similar tooling cost to `freezed` + `json_serializable`, which the epic also pre-commits to — these often share the same codegen invocation)
- A Riverpod major version bump becomes a recurring maintenance event
- The team needs to learn Riverpod conventions: how to scope providers, when to use `Notifier` vs `AsyncNotifier`, how to dispose, etc. The Riverpod docs are good but it's a real ramp.

### Migration concerns

- None. This is greenfield Flutter work; no existing state management to migrate from.

## References

- Riverpod docs: https://pub.dev/packages/flutter_riverpod
- `riverpod_generator` docs: https://pub.dev/packages/riverpod_generator
- KAN-251 epic description ("Scope IN" → "Riverpod for state management / DI")
- ADR 0001 (routing library) — `go_router` interop
