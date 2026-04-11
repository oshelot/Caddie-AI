# 0001. Routing library

**Status:** Accepted
**Date proposed:** 2026-04-11
**Date accepted:** 2026-04-11 (KAN-270 planning pass)
**Affected stories:** KAN-271 (S1 app shell), all subsequent UI stories

## Context

The KAN-251 Flutter migration needs a routing solution for the 4-tab bottom navigation (Caddie / Course / History / Profile) plus modal flows for onboarding (KAN-284), settings (KAN-283), and the course map screen (KAN-280). The native iOS app uses SwiftUI's `TabView` + `NavigationStack`; the native Android app uses Jetpack Navigation Compose with sealed-class routes.

Flutter offers three credible routing approaches:

1. **`go_router`** (community-maintained but blessed by the Flutter team, on track to become the recommended default)
2. **`auto_route`** (codegen-based, type-safe, more opinionated)
3. **Vanilla `Navigator 2.0`** (no extra dependency, full control, more boilerplate)

## Decision (proposed)

**Use `go_router`.**

## Rationale

- **Idiomatic for 2026.** `go_router` is now the de facto standard for Flutter routing — most new Flutter projects ship with it, the Flutter team contributes to it directly, and the documentation is current.
- **Declarative URL-style routing** maps naturally to the 4-tab + modal structure of the migrated app. Each tab is a top-level route; onboarding is a separate route stack pushed over the tab bar; the course map screen is a route under the Course tab that takes a `courseId` path parameter.
- **Deep linking is free** — `go_router` handles iOS Universal Links and Android App Links out of the box. Even though the current native apps don't use deep links, the migrated app gets the capability for free, and product may want it later.
- **Codegen-free.** Unlike `auto_route`, there's no `build_runner` step in the dev loop. Faster iteration on routing changes.
- **Ecosystem fit.** `go_router` works cleanly with Riverpod (already pre-decided in the KAN-251 epic) — `GoRouter` instances live in providers and rebuild on auth/profile state changes.

## Alternatives considered

### `auto_route`

**Pros:** Type-safe routes via codegen — typos in route names fail at compile time. More opinionated structure, which can be helpful for a team learning Flutter.

**Cons:** Codegen step adds dev-loop friction (every route change needs `dart run build_runner build`). The type safety is genuinely nice but the cost of the codegen step is real and recurring. Smaller ecosystem.

**Verdict:** Reasonable second choice. If the team finds itself shipping route bugs that compile-time checks would have caught, revisit.

### Vanilla `Navigator 2.0`

**Pros:** No extra dependency. Full control over the imperative push/pop API.

**Cons:** Substantially more boilerplate for the 4-tab + modal structure. No deep-linking out of the box. Easy to get into "what does the back stack look like" debates.

**Verdict:** Not recommended. The boilerplate cost outweighs the dependency cost.

## Consequences

### What this enables

- KAN-271 (S1) can pick up `go_router` directly without further decision delay
- All subsequent UI stories use `context.go(...)` / `context.push(...)` for navigation
- Deep linking infrastructure is in place if product wants to enable it later

### What this commits us to

- A `go_router` major version bump becomes a recurring maintenance event (the API has changed meaningfully between major versions historically)
- Navigation tests have to use `go_router`'s test helpers, not vanilla `Navigator` mocks

### Migration concerns

- None. This is greenfield Flutter work; no existing routing to migrate from.

## References

- `go_router` docs: https://pub.dev/packages/go_router
- KAN-271 (S1 app shell)
- KAN-251 epic — Riverpod is pre-decided, which influences this choice (see "Ecosystem fit" above)
