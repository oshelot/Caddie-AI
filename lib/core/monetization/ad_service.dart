// AdService — KAN-285 (S15) abstraction over the
// `google_mobile_ads` plugin. Production impl wraps the
// platform Mobile Ads SDK; tests inject `StubAdService` to drive
// the visibility logic without standing up a real AdMob session.
//
// **Why an interface, not a direct plugin call:** the same
// pattern as `SubscriptionService` and the rest of the
// platform-touching abstractions. The `bannerAd()` widget
// returns a `Widget` so screens that want a banner slot get one
// via `adService.bannerAd()` regardless of whether the
// underlying plugin is available. The stub returns
// `SizedBox.shrink()` for everyone — no banner ever shows in
// dev runs without a configured ad-unit ID, AND no banner shows
// in unit tests.
//
// **Subscription gating:** the `AdService` exposes
// `setSubscribed(bool)` so the production impl can hide the
// banner when the user is on the paid tier. The page wrapper
// for any screen that uses `bannerAd()` listens to
// `SubscriptionService.subscriptionStream` and forwards the
// state to `adService.setSubscribed`. This keeps the
// subscription concept inside the monetization namespace
// instead of leaking it into the ad widget tree.
//
// **App Tracking Transparency (iOS):** the production impl
// triggers the ATT prompt on `initialize()` if the user hasn't
// answered yet AND the app version is not the first launch
// (Apple's HIG says "ask after the user has had a chance to
// understand the value"). The stub never prompts.
//
// **In-app review trigger** (`requestReview()`): wraps the
// platform `in_app_review` plugin under the same abstraction so
// the caddie screen can trigger a review request after the
// Nth successful interaction (per the KAN-S15 scope). Stub is
// a no-op.

import 'package:flutter/material.dart';

abstract class AdService {
  /// Initializes the underlying ads SDK + the in-app-review
  /// plugin. Call once at app start. Idempotent. On iOS, may
  /// prompt for App Tracking Transparency.
  Future<void> initialize();

  /// Updates the cached subscription state. When `true`, every
  /// `bannerAd()` call returns an empty widget. When `false`,
  /// banners are shown.
  void setSubscribed(bool subscribed);

  /// True if banner ads should currently be visible. Mirrors
  /// the inverse of `setSubscribed`.
  bool get bannerVisible;

  /// Returns a banner ad widget for the current platform. Caller
  /// embeds it in their layout. The stub (and the production
  /// impl when `bannerVisible` is false) returns
  /// `SizedBox.shrink()`.
  Widget bannerAd();

  /// Preloads an interstitial ad. Call early (e.g. when search
  /// results appear) so it's ready when the user taps a course.
  void loadInterstitial() {}

  /// Shows the preloaded interstitial if conditions are met:
  /// not subscribed, ad loaded, not already shown this session.
  /// Returns true if the ad was shown.
  bool showInterstitialIfReady() => false;

  /// Triggers an in-app review prompt if the platform is willing
  /// to show one. The store throttles these per-app per-year so
  /// the request may be a no-op even when called.
  Future<void> requestReview();

  /// Releases plugin resources. Idempotent.
  Future<void> dispose();
}

/// Stub impl used in dev builds without a configured ad-unit ID
/// AND in unit tests. Banner widgets are always
/// `SizedBox.shrink()`. The visibility flag is still tracked so
/// the screen tests can assert that the subscription state
/// flowed through correctly.
class StubAdService implements AdService {
  bool _subscribed = false;

  @override
  Future<void> initialize() async {}

  @override
  void setSubscribed(bool subscribed) {
    _subscribed = subscribed;
  }

  @override
  bool get bannerVisible => !_subscribed;

  @override
  Widget bannerAd() {
    // The stub never renders a real banner, but it returns a
    // visible Container when `bannerVisible` is true so widget
    // tests can assert on the slot's presence in the tree
    // without a real ad SDK.
    if (!bannerVisible) return const SizedBox.shrink();
    return const _StubBannerSlot();
  }

  @override
  void loadInterstitial() {}

  @override
  bool showInterstitialIfReady() => false;

  @override
  Future<void> requestReview() async {}

  @override
  Future<void> dispose() async {}
}

/// Visible-but-empty placeholder for the banner slot. The real
/// `google_mobile_ads` `BannerAd` widget will replace this in
/// the production impl.
class _StubBannerSlot extends StatelessWidget {
  const _StubBannerSlot();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('ads-banner-slot'),
      height: 50,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Text(
        'Ad slot (stub)',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
