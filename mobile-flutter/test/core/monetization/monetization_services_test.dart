// Tests for KAN-285 (S15) monetization abstractions —
// `SubscriptionService` (via `StubSubscriptionService`) and
// `AdService` (via `StubAdService`).
//
// Coverage:
//   1. Subscription stub: starts unsubscribed, `subscribe()`
//      flips state and emits on the stream
//   2. Stream is broadcast (multiple listeners receive events)
//   3. `setSubscribedForTest` flips state without going through
//      the purchase flow
//   4. `restorePurchases` reflects the current cached state
//   5. AdService starts with `bannerVisible = true` (no
//      subscription)
//   6. `setSubscribed(true)` hides the banner
//   7. `bannerAd()` returns SizedBox.shrink when subscribed,
//      a visible slot when not
//   8. **End-to-end coupling test:** flipping the subscription
//      state on `SubscriptionService` and forwarding to
//      `AdService.setSubscribed` flips the banner visibility.
//      This is the contract every monetization-aware page
//      wrapper has to honor.

import 'package:caddieai/core/monetization/ad_service.dart';
import 'package:caddieai/core/monetization/subscription_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StubSubscriptionService', () {
    test('starts unsubscribed', () {
      final service = StubSubscriptionService();
      expect(service.isSubscribed, isFalse);
    });

    test('subscribe() flips the cached state to true', () async {
      final service = StubSubscriptionService();
      final result = await service.subscribe();
      expect(result, isTrue);
      expect(service.isSubscribed, isTrue);
    });

    test('subscribe() emits on subscriptionStream', () async {
      final service = StubSubscriptionService();
      final received = <bool>[];
      final sub = service.subscriptionStream.listen(received.add);
      await service.subscribe();
      // Drain the controller's pending events.
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(received, [true]);
      await service.dispose();
    });

    test(
        'subscriptionStream is a broadcast stream — multiple listeners '
        'receive events', () async {
      final service = StubSubscriptionService();
      final a = <bool>[];
      final b = <bool>[];
      final subA = service.subscriptionStream.listen(a.add);
      final subB = service.subscriptionStream.listen(b.add);
      service.setSubscribedForTest(true);
      service.setSubscribedForTest(false);
      await Future<void>.delayed(Duration.zero);
      await subA.cancel();
      await subB.cancel();
      expect(a, [true, false]);
      expect(b, [true, false]);
      await service.dispose();
    });

    test('setSubscribedForTest only emits on actual changes', () async {
      final service = StubSubscriptionService();
      final received = <bool>[];
      final sub = service.subscriptionStream.listen(received.add);
      service.setSubscribedForTest(false); // already false → no event
      service.setSubscribedForTest(true);
      service.setSubscribedForTest(true); // already true → no event
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(received, [true]);
      await service.dispose();
    });

    test('restorePurchases reflects the current cached state', () async {
      final service = StubSubscriptionService(initialSubscribed: true);
      expect(await service.restorePurchases(), isTrue);
      service.setSubscribedForTest(false);
      expect(await service.restorePurchases(), isFalse);
    });

    test('initialSubscribed=true seeds the cached state', () {
      final service = StubSubscriptionService(initialSubscribed: true);
      expect(service.isSubscribed, isTrue);
    });

    group('KAN-95: debugForcePro', () {
      test('starts false', () {
        final service = StubSubscriptionService();
        expect(service.debugForcePro, isFalse);
      });

      test('setting to true forces isSubscribed to true and emits on stream',
          () async {
        final service = StubSubscriptionService();
        final received = <bool>[];
        final sub = service.subscriptionStream.listen(received.add);
        service.debugForcePro = true;
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        expect(service.isSubscribed, isTrue);
        expect(received, [true]);
        await service.dispose();
      });

      test('setting back to false restores the underlying state', () async {
        final service = StubSubscriptionService();
        service.debugForcePro = true;
        expect(service.isSubscribed, isTrue);
        service.debugForcePro = false;
        expect(service.isSubscribed, isFalse);
        await service.dispose();
      });

      test(
          'when underlying state is already true, toggling debugForcePro '
          'on/off does not flip isSubscribed and does not emit', () async {
        final service = StubSubscriptionService(initialSubscribed: true);
        final received = <bool>[];
        final sub = service.subscriptionStream.listen(received.add);
        service.debugForcePro = true;
        service.debugForcePro = false;
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        expect(service.isSubscribed, isTrue);
        expect(received, isEmpty);
        await service.dispose();
      });

      test('repeated set to the same value is a no-op', () async {
        final service = StubSubscriptionService();
        final received = <bool>[];
        final sub = service.subscriptionStream.listen(received.add);
        service.debugForcePro = true;
        service.debugForcePro = true;
        service.debugForcePro = true;
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        expect(received, [true]);
        await service.dispose();
      });
    });
  });

  group('StubAdService', () {
    test('starts with bannerVisible = true', () {
      final service = StubAdService();
      expect(service.bannerVisible, isTrue);
    });

    test('setSubscribed(true) flips bannerVisible to false', () {
      final service = StubAdService();
      service.setSubscribed(true);
      expect(service.bannerVisible, isFalse);
    });

    test('setSubscribed(false) flips bannerVisible back to true', () {
      final service = StubAdService();
      service.setSubscribed(true);
      service.setSubscribed(false);
      expect(service.bannerVisible, isTrue);
    });

    testWidgets(
        'bannerAd() returns SizedBox.shrink when subscribed',
        (tester) async {
      final service = StubAdService();
      service.setSubscribed(true);
      await tester.pumpWidget(MaterialApp(home: service.bannerAd()));
      // Stub banner slot is gone.
      expect(find.byKey(const Key('ads-banner-slot')), findsNothing);
    });

    testWidgets(
        'bannerAd() returns the stub banner slot when not subscribed',
        (tester) async {
      final service = StubAdService();
      await tester.pumpWidget(MaterialApp(home: service.bannerAd()));
      expect(find.byKey(const Key('ads-banner-slot')), findsOneWidget);
    });

    test('initialize / requestReview / dispose are no-ops', () async {
      final service = StubAdService();
      await service.initialize();
      await service.requestReview();
      await service.dispose();
      // No exceptions = pass.
    });
  });

  group('end-to-end coupling: SubscriptionService ↔ AdService', () {
    test(
        'forwarding subscription state to AdService flips banner '
        'visibility — the contract every page wrapper honors', () async {
      final subs = StubSubscriptionService();
      final ads = StubAdService();

      // Wire the same forwarding the page wrapper would do.
      final sub = subs.subscriptionStream.listen(ads.setSubscribed);

      // Initial state: free → ads visible.
      expect(ads.bannerVisible, isTrue);

      // Subscribe → ads hide.
      await subs.subscribe();
      await Future<void>.delayed(Duration.zero);
      expect(ads.bannerVisible, isFalse);

      // Restore on a fresh launch flow: state is already true
      // (from the cached subscription).
      expect(await subs.restorePurchases(), isTrue);

      // Cancel subscription → ads come back.
      subs.setSubscribedForTest(false);
      await Future<void>.delayed(Duration.zero);
      expect(ads.bannerVisible, isTrue);

      await sub.cancel();
      await subs.dispose();
    });
  });
}
