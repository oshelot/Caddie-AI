# 0009. Monetization plugin choice

**Status:** Accepted
**Date proposed:** 2026-04-11
**Date accepted:** 2026-04-11 (KAN-285 / S15)
**Affected stories:** KAN-285 (S15 monetization)
**Supersedes:** ADR 0005 (recorded the same decision in the planning pass; this ADR formalizes it at story-start time per the KAN-285 "ADR required before starting" gate)

## Context

KAN-285 ships subscriptions + ads. Two plugin choices:

1. **`in_app_purchase`** — Flutter team's official wrapper around StoreKit 2 (iOS) + Play Billing (Android). Free, no third-party dependency, well-maintained, but you write your own entitlement bookkeeping.

2. **`purchases_flutter` (RevenueCat)** — third-party SDK that handles entitlements, server-side receipt validation, dashboards, A/B testing of paywalls. Free tier for revenue under $10k/month, then 1% revenue share above that.

The native iOS / Android apps **already use the platform-native APIs directly** (StoreKit and Play Billing without RevenueCat). There's no entitlement infrastructure on the server side today — the apps cache the subscription state locally and re-query the store on launch.

## Decision

**Use `in_app_purchase` (official).**

Receipt validation is **local-only** for the first cut, with a `TODO(server-side)` marker the cutover team can pick up later.

## Rationale

- **Matches the existing native apps' approach.** Both iOS and Android already manage entitlements locally without RevenueCat. Migrating to the official Flutter wrapper preserves that architecture — the Flutter port doesn't introduce a new server-side dependency or a new third-party billing agreement at the same time it's also rewriting every screen.
- **Zero revenue share.** RevenueCat takes 1% of revenue above $10k/month. For an app at the CaddieAI scale that's not free; for an app projecting growth past that threshold it's a meaningful drag. The official plugin has none.
- **Avoids a second migration.** Adopting RevenueCat means committing to its dashboard, its webhook contracts, and its server-side infrastructure for entitlements. If product later wants to leave RevenueCat (vendor lock-in concerns, cost concerns, dashboard fragmentation), that's a second migration on top of the Flutter cutover. Sticking with the official plugin keeps the option open.
- **Simpler unit tests.** The `in_app_purchase` API is small enough that the `SubscriptionService` abstraction in this story can hide it entirely. Tests inject `FakeSubscriptionService`. With RevenueCat the surface is bigger and the stub gets larger.

## Alternatives considered

### `purchases_flutter` (RevenueCat)

**Pros:** Cross-platform entitlement management for free. Server-side receipt validation included. Built-in paywall A/B testing. Webhook delivery for subscription state changes (useful for the LLM proxy's tier check). Dashboard for revenue analytics.

**Cons:**
- 1% revenue share above $10k/month
- Vendor lock-in — switching out later is non-trivial
- Adds a second SDK with its own update cadence and breaking-change risk
- The native apps don't use it today, so adopting it during the migration mixes "we're rewriting in Flutter" with "we're also moving to a third-party billing service" — two unrelated migrations at once

**Verdict:** Reconsider only if (a) the local entitlement bookkeeping turns out to be more painful than expected after KAN-S15 ships, (b) product decides to invest in serious paywall A/B testing, OR (c) the LLM proxy needs reliable webhook-driven tier updates. Until then the official plugin is the smaller commit.

## Consequences

### What this enables

- KAN-S15 ships with the `in_app_purchase` plugin as the production impl behind a `SubscriptionService` abstraction
- The `LlmRouter` (KAN-294) already takes a `tier` parameter — the page wrappers wire `SubscriptionService.isSubscribed ? LlmTier.paid : LlmTier.free` so the routing flips automatically when a purchase completes
- `AdService` is a separate abstraction wrapping `google_mobile_ads`; subscription state hides the banner via `AdService.bannerAd()` returning `SizedBox.shrink()` when `isSubscribed`
- Test fakes (`FakeSubscriptionService`, `FakeAdService`) drive the screen tests without touching real platform plugins
- Local receipt validation is the first cut; server-side validation lands in a follow-up KAN ticket once the Lambda contract is defined

### What this commits us to

- **Local entitlement bookkeeping forever** (or until a future ADR supersedes this one). The `SubscriptionService` impl re-queries the store on app launch and trusts whatever StoreKit/Play Billing reports.
- **No paywall A/B testing infrastructure** on the Flutter side. Product changes to paywall copy/timing happen via app updates and feature flags — slower than RevenueCat's remote config but consistent with how the native apps operate today.
- **Manual receipt-validation upgrade path.** When the cutover team decides to move validation server-side, the work is: (1) add a `validateReceipt(token)` Lambda, (2) call it from `SubscriptionService.subscribe()` after the store reports success, (3) gate the `isSubscribed` getter on the Lambda's response. The interface stays the same; only the impl changes.

### Migration concerns

- **Cutover-time validation gap.** The KAN-S15 AC ("free tier → ads show → subscribe → ads hide → restore on reinstall works") fundamentally requires a real device on a real store. The architectural work (interfaces + fakes + tier-gating) is mergeable today; the device validation is a manual checklist item the cutover team (KAN-S16) handles.
- **Real product / ad-unit IDs are NOT in source.** They live in App Store Connect (`com.caddieai.pro.monthly`) and the AdMob console (banner ad unit ids per platform). The production impls read them from `--dart-define` constants, NOT from hard-coded literals. This avoids leaking credentials to the public repo and matches the same `LOGGING_API_KEY` / `MAPBOX_TOKEN` / `LLM_PROXY_API_KEY` pattern the rest of the scaffold uses.

## References

- KAN-285 (S15)
- KAN-S15 in `mobile-flutter/docs/KAN-251-STORIES.md`
- ADR 0005 (planning-pass version of this decision)
- `in_app_purchase`: https://pub.dev/packages/in_app_purchase
- `google_mobile_ads`: https://pub.dev/packages/google_mobile_ads
- `purchases_flutter` (rejected): https://pub.dev/packages/purchases_flutter
