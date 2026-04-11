# 0005. Monetization plugin

**Status:** Proposed — needs sign-off before KAN-285 (S15 monetization) starts.
**Date proposed:** 2026-04-11
**Affected stories:** KAN-285 (S15 monetization)

## Context

The KAN-251 Flutter migration needs to wrap **two store integrations**:

- **iOS StoreKit 2** for App Store subscriptions
- **Android Play Billing v6** for Play Store subscriptions

The native iOS app uses StoreKit 2 directly. The native Android app uses Play Billing directly. Single product: `com.caddieai.pro.monthly`. Free tier shows ads (`google_mobile_ads`); paid tier hides them and unlocks the proxy LLM path (KAN-277 / S7).

The migrated Flutter app needs to do the same things, plus:

- Restore purchases on reinstall
- App Tracking Transparency prompt on iOS for ad personalization
- Play Review API / iOS in-app review trigger on Nth successful caddie interaction
- Receipt validation (server-side preferred; native code state TBD — see KAN-285 description)

The Flutter ecosystem has two credible options:

1. **`in_app_purchase`** — official Flutter team package, free, wraps StoreKit + Play Billing directly
2. **`purchases_flutter`** (RevenueCat) — third-party SaaS that abstracts both stores behind a single API, charges based on net revenue

## Decision (proposed)

**Use `in_app_purchase` (official, free).**

## Rationale

- **One product, no entitlement complexity.** The app sells exactly one thing: `com.caddieai.pro.monthly`. The user is either subscribed or not. RevenueCat's main value is managing complex entitlement matrices (multiple products, tiers, promotions, A/B-tested pricing). For a single-product app, that machinery is unused weight.
- **No recurring SaaS cost.** RevenueCat charges 1% of revenue once you exceed their free tier ($2.5k/month MTR). For a small app this is fine, for a growing one it becomes a real line item that's hard to remove later. `in_app_purchase` is free forever.
- **Closer to the metal.** Receipt validation, purchase state changes, and edge cases (deferred purchases, family sharing) are all directly visible at the `in_app_purchase` API level. With RevenueCat you trust their abstraction. For a small surface area, direct is cleaner.
- **Matches the native architecture.** Both native apps already talk to StoreKit 2 and Play Billing directly. The Flutter version uses the same primitives. Easier to port the existing receipt-validation logic (wherever it lives — KAN-285 description flags this as a TBD to investigate).
- **App Tracking Transparency, App Review, and ads** all come from separate packages anyway (`app_tracking_transparency`, `in_app_review`, `google_mobile_ads`). Bundling those under a SaaS doesn't simplify anything.

## Alternatives considered

### `purchases_flutter` (RevenueCat)

**Pros:** Single API across iOS + Android. Server-side receipt validation handled for you. Built-in entitlement management. Webhook-based event delivery to your backend. Built-in support for promotional offers, intro pricing, paywalls.

**Cons:** SaaS dependency with cost that scales with revenue. The abstraction is genuinely useful for apps with complex pricing matrices but **adds nothing for a single-product app**. Lock-in: once your subscription state lives in RevenueCat's database, migrating away is real work.

**Verdict:** The right choice for an app with multiple products and tiers, or when the team doesn't have iOS/Android purchase-flow expertise. **Not the right choice here** — single product, native team already has the expertise (the native apps work).

### Custom platform channel wrappers

**Pros:** Maximum flexibility. No third-party dependency at all.

**Cons:** Reimplements `in_app_purchase` from scratch. Almost never the right call when an official package exists.

**Verdict:** Don't.

## Consequences

### What this enables

- KAN-285 ships using `in_app_purchase` ^3.x with platform-specific subscription detail handling
- Receipt validation logic (whatever the native apps do) ports directly without an extra abstraction layer in the way
- No SaaS bills, no third-party state to keep in sync with the local cache

### What this commits us to

- More upfront work in KAN-285 to handle each platform's edge cases (deferred purchases, family sharing, restore-from-other-device) — `in_app_purchase` exposes them but doesn't paper over them
- Future stories that want promotional offers / paywalls / A-B tests have to build that machinery on top of `in_app_purchase`. **If product asks for a paywall builder later, this ADR may need to be revisited** (it's the most realistic reason to switch to RevenueCat).
- Subscription state lives in `flutter_secure_storage` (or similar) plus the OS receipt — no remote state to query. Means restore-purchases must hit the platform receipt API, not a SaaS.

### Migration concerns

- KAN-285 must check whether the native apps do **server-side** receipt validation. If yes: port the call to the existing endpoint. If no: ship local validation with a `TODO` to move server-side later.
- Existing subscribers must transition seamlessly. Same bundle ID + same product ID = the OS automatically credits them after install. **Test this on a real device with a real test subscription.**

## References

- `in_app_purchase` docs: https://pub.dev/packages/in_app_purchase
- RevenueCat (`purchases_flutter`) docs: https://pub.dev/packages/purchases_flutter
- KAN-285 (S15 monetization)
- KAN-251 epic ("Same bundle IDs … existing users and subscribers transition seamlessly")
