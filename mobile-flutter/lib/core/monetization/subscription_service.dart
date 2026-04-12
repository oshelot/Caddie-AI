// SubscriptionService — KAN-285 (S15) abstraction over the
// `in_app_purchase` plugin per ADR 0009. Production impl wraps
// the platform StoreKit / Play Billing APIs; tests inject
// `FakeSubscriptionService` to drive scripted state changes.
//
// **Why an interface, not a direct plugin call:** the LLM router
// (KAN-294) and the caddie / profile screens (KAN-281, KAN-283)
// all need to know whether the user is currently subscribed.
// Coupling them to `in_app_purchase` directly would force every
// test to mock platform method channels. The interface is the
// seam — the production impl in
// `in_app_purchase_subscription_service.dart` is the ONLY file
// that imports the plugin.
//
// **Subscription state shape:** the only thing the rest of the
// app cares about is "is this user paid". Active subscription,
// trial, grace period, billing retry — all of those collapse to
// `isSubscribed = true`. Cancelled / expired / never-purchased
// collapse to `false`. Tier-gating logic in the LLM router and
// the ads visibility logic both consume just the boolean.
//
// **Stream + getter pattern:** `isSubscribed` is the synchronous
// snapshot (cheap, fine to call from `build()`). `subscriptionStream`
// is the broadcast stream that fires whenever the state flips
// (after a successful purchase, after a restore, after a
// background entitlement refresh). UI code subscribes to the
// stream to rebuild when the user transitions between tiers
// without an app restart.

import 'dart:async';

/// Single product the app sells. The actual product ID lives in
/// `--dart-define=SUBSCRIPTION_PRODUCT_ID=com.caddieai.pro.monthly`
/// at build time so the public repo never carries the literal.
abstract class SubscriptionService {
  /// True if the user has an active "Pro" subscription right now.
  /// Synchronous snapshot — production reads from a cached value
  /// that the platform plugin keeps up-to-date.
  bool get isSubscribed;

  /// Broadcast stream that fires whenever `isSubscribed` flips.
  /// Caddie / profile / shell widgets listen so they rebuild on
  /// the transition without an app restart.
  Stream<bool> get subscriptionStream;

  /// Initializes the underlying plugin (StoreKit on iOS, Play
  /// Billing on Android) and refreshes the cached subscription
  /// state from the store. Call once at app start, before the
  /// first build of any screen that gates on `isSubscribed`.
  /// Idempotent — calling twice is a no-op.
  Future<void> initialize();

  /// Triggers the platform purchase flow for the configured
  /// product. Returns true if the purchase completed; false if
  /// the user cancelled or the store reported an error. The
  /// `subscriptionStream` will fire `true` on success.
  Future<bool> subscribe();

  /// Restores any previously-completed purchases. Required for
  /// reinstalls + cross-device support. Returns true if any
  /// active subscription was found and the cached state was
  /// updated.
  Future<bool> restorePurchases();

  /// Releases plugin resources. Idempotent.
  Future<void> dispose();
}

/// Stub `SubscriptionService` used in development builds without
/// a configured product ID, AND in unit tests that don't care
/// about the subscription path. Always reports `isSubscribed =
/// false`; `subscribe()` returns false; the stream never fires.
///
/// The production impl is `InAppPurchaseSubscriptionService` in
/// the same directory.
class StubSubscriptionService implements SubscriptionService {
  StubSubscriptionService({bool initialSubscribed = false})
      : _isSubscribed = initialSubscribed;

  bool _isSubscribed;
  final StreamController<bool> _controller =
      StreamController<bool>.broadcast();

  @override
  bool get isSubscribed => _isSubscribed;

  @override
  Stream<bool> get subscriptionStream => _controller.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> subscribe() async {
    // Stub: pretend the purchase succeeded so dev runs can step
    // through the paid-tier code path without a real store.
    _setSubscribed(true);
    return true;
  }

  @override
  Future<bool> restorePurchases() async {
    return _isSubscribed;
  }

  @override
  Future<void> dispose() async {
    if (!_controller.isClosed) await _controller.close();
  }

  /// Test/dev helper — flips the cached state and emits on the
  /// stream. Used by the screen tests AND by a future "Force tier"
  /// dev menu (KAN-S13's debug overrides field).
  void setSubscribedForTest(bool value) => _setSubscribed(value);

  void _setSubscribed(bool value) {
    if (_isSubscribed == value) return;
    _isSubscribed = value;
    _controller.add(value);
  }
}
