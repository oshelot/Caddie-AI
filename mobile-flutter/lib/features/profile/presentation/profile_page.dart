// ProfilePage — KAN-283 (S13) route-level wiring for the Profile
// tab. Loads the player profile from `ProfileRepository` (S2) and
// the API keys from `SecureKeysStorage` (S2), passes them to
// `ProfileScreen`, and on save:
//
//   1. Writes the new profile to `ProfileRepository`
//   2. Writes the secret-keys map to `SecureKeysStorage`
//   3. Updates the `LoggingService` enabled state to match the
//      new `telemetryEnabled` flag (so the toggle takes effect
//      without an app restart)
//
// **Critical safety contract:** the `ProfileSaveRequest` object
// returned by the screen has TWO separate fields — `profile`
// (which never carries API keys) and `secrets` (which only
// carries API keys). The page wrapper hands them to the right
// stores. The KAN-272 canary test
// (`test/storage/secure_keys_isolation_test.dart`) verifies
// that the profile blob on disk never contains the secret values.

import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../../core/monetization/subscription_service.dart';
import '../../../main.dart' show adService;
import '../../../core/storage/profile_repository.dart';
import '../../../core/storage/secure_keys_storage.dart';
import '../../../main.dart' show logger;
import '../../../models/player_profile.dart';
import 'profile_screen.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.subscriptionService});

  /// Optional injection seam. Production builds the stub service
  /// inline; once `InAppPurchaseSubscriptionService` ships, the
  /// shell will own a single instance and pass it down here.
  final SubscriptionService? subscriptionService;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _profileRepo = ProfileRepository();
  final _secureKeys = SecureKeysStorage();
  late final SubscriptionService _subscriptionService =
      widget.subscriptionService ?? StubSubscriptionService()
        ..debugForcePro = kDebugMode;
  late final bool _ownsSubscriptionService = widget.subscriptionService == null;
  StreamSubscription<bool>? _adSyncSub;

  @override
  void initState() {
    super.initState();
    // Sync adService with the subscription state so toggling the
    // debug Pro switch immediately shows/hides ads.
    adService.setSubscribed(_subscriptionService.isSubscribed);
    _adSyncSub = _subscriptionService.subscriptionStream.listen((subscribed) {
      adService.setSubscribed(subscribed);
    });
    _loadSecrets();
  }

  @override
  void dispose() {
    _adSyncSub?.cancel();
    if (_ownsSubscriptionService) {
      _subscriptionService.dispose();
    }
    super.dispose();
  }

  // Defensive load: in unit tests Hive isn't initialized so the
  // repo throws. Fall back to a default profile so the screen
  // still mounts. Production always has the boxes open by the
  // time the route builds.
  late PlayerProfile _profile = _safeLoadProfile();
  Map<String, String> _secrets = const {};
  bool _loadingSecrets = true;

  PlayerProfile _safeLoadProfile() {
    try {
      return _profileRepo.loadOrDefault();
    } catch (_) {
      return const PlayerProfile();
    }
  }

  Future<void> _loadSecrets() async {
    try {
      final out = <String, String>{};
      for (final key in const [
        SecureKey.openAi,
        SecureKey.claude,
        SecureKey.gemini,
      ]) {
        final value = await _secureKeys.read(key);
        if (value != null) out[key] = value;
      }
      if (!mounted) return;
      setState(() {
        _secrets = out;
        _loadingSecrets = false;
      });
    } catch (_) {
      // SecureKeysStorage is unavailable in unit-test runtime.
      // Continue with an empty map.
      if (mounted) setState(() => _loadingSecrets = false);
    }
  }

  Future<void> _onSave(ProfileSaveRequest request) async {
    await _profileRepo.save(request.profile);
    await _secureKeys.writeAll(request.secrets);
    // Telemetry toggle takes effect immediately.
    logger.setEnabled(request.profile.telemetryEnabled);
    if (mounted) {
      setState(() => _profile = request.profile);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingSecrets) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return ProfileScreen(
      profile: _profile,
      initialSecrets: _secrets,
      onSave: _onSave,
      subscriptionService: _subscriptionService,
      adService: adService,
    );
  }
}
