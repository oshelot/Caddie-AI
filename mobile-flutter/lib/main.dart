// CaddieAI Flutter app entry point — KAN-251 migration.
//
// Two things must complete before `runApp()`:
//
//   1. `await initMapbox()` — see `core/mapbox/mapbox_init.dart`
//      for the historical context (KAN-252 SPIKE_REPORT §4 Bug 1).
//      Per CONVENTIONS C-1, every process that constructs a
//      `MapWidget` must await this first.
//   2. `await AppStorage.init()` — opens the Hive boxes used by
//      the KAN-272 (S2) storage layer. The MainShell tabs read
//      the profile box on first frame, so the boxes have to be
//      open by the time the first widget renders. The migration
//      importer (KAN-272 AC #2) is run lazily by the screens that
//      need profile data — not here, to keep cold-start latency
//      bounded.
//
// CaddieApp is non-const because it owns a `GoRouter` instance built
// in its constructor (see lib/app.dart) — that's why `runApp` doesn't
// take a `const` here.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/build_mode.dart';
import 'core/logging/log_event.dart';
import 'core/monetization/ad_service.dart';
import 'core/monetization/google_mobile_ads_service.dart';
import 'core/monetization/subscription_service.dart';
import 'core/logging/log_sender.dart';
import 'core/logging/logging_service.dart';
import 'core/mapbox/mapbox_init.dart';
import 'core/storage/app_storage.dart';

/// Process-global LoggingService. Initialized in `main()` and read
/// by feature code via this getter — there's no DI container in
/// the scaffold yet, so a top-level singleton is the simplest way
/// to share the instance. When Riverpod lands (KAN-S7 or earlier),
/// this should become a `Provider<LoggingService>` and feature code
/// should switch to consuming it via the provider.
///
/// **Test fallback:** when accessed before `main()` runs (e.g. in
/// unit tests that pump a route widget directly), the getter
/// lazy-creates a no-op fallback that's disabled by default. This
/// keeps the test runtime functional without polluting the
/// production code path — production builds always assign
/// `_logger` from `main()` first, so the fallback is never used in
/// release builds.
LoggingService get logger {
  return _logger ??= _buildFallbackLogger();
}

LoggingService? _logger;

LoggingService _buildFallbackLogger() {
  return LoggingService(
    sender: _NoopLogSender(),
    deviceId: 'unknown',
    sessionId: 'unknown',
    enabled: false,
  );
}

class _NoopLogSender implements LogSender {
  @override
  Future<bool> send({
    required List<dynamic> entries,
    required String deviceId,
    required String sessionId,
  }) async =>
      true;
}

/// Global ad service — accessible from screens that need to show
/// banner ads. Initialized in main() before runApp. Falls back to
/// StubAdService in test runtime where main() hasn't run.
AdService adService = StubAdService();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initMapbox();
  await AppStorage.init();
  _logger = _buildLogger();
  // Initialize ads. In debug builds with Pro override, banners are
  // hidden automatically via setSubscribed(true).
  final ads = GoogleMobileAdsService();
  await ads.initialize();
  if (isDevMode) ads.setSubscribed(true);
  adService = ads;
  runApp(CaddieApp());
}

/// Builds the production LoggingService from `--dart-define`
/// values. The endpoint and API key are deliberately empty in
/// dev runs that don't pass the defines — the service degrades
/// gracefully (the underlying `HttpLogSender.send` short-circuits
/// when either is empty), so calling `logger.info(...)` in feature
/// code is always safe.
LoggingService _buildLogger() {
  const endpoint = String.fromEnvironment('LOGGING_ENDPOINT');
  const apiKey = String.fromEnvironment('LOGGING_API_KEY');

  final sender = HttpLogSender(
    endpoint: endpoint,
    apiKey: apiKey,
    platform: Platform.isIOS ? 'ios' : 'android',
    appVersion: const String.fromEnvironment('APP_VERSION', defaultValue: 'dev'),
    buildNumber: const String.fromEnvironment('BUILD_NUMBER', defaultValue: '0'),
    osVersion: Platform.operatingSystemVersion,
    deviceModel: Platform.localHostname,
  );

  final svc = LoggingService(
    sender: sender,
    // Device + session id placeholders. KAN-S2 ships the storage
    // layer that owns the persisted device id; a follow-up should
    // wire that here. For now both values are per-process — fine
    // for the foundation story.
    deviceId: 'flutter-${DateTime.now().millisecondsSinceEpoch}',
    sessionId: '${DateTime.now().millisecondsSinceEpoch}',
    // Enable logging in ALL builds so debug runs still write to
    // CloudWatch. The HttpLogSender.send short-circuits gracefully
    // when endpoint or apiKey is empty, so dev runs without
    // dart-defines are safe — they just no-op.
    enabled: true,
  );

  // Startup diagnostic — visible in CloudWatch so you can confirm
  // the dart-define wiring landed. Logs whether each secret is set
  // (not the values themselves).
  svc.info(
    LogCategory.lifecycle,
    'app_startup',
    metadata: {
      'loggingEndpoint': endpoint.isEmpty ? 'MISSING' : 'set',
      'loggingApiKey': apiKey.isEmpty ? 'MISSING' : 'set',
      'courseCacheEndpoint': const String.fromEnvironment('COURSE_CACHE_ENDPOINT').isEmpty
          ? 'MISSING'
          : 'set',
      'mapboxToken': const String.fromEnvironment('MAPBOX_TOKEN').isEmpty
          ? 'MISSING'
          : 'set',
      'buildMode': kDebugMode ? 'debug' : 'release',
      'platform': Platform.isIOS ? 'ios' : 'android',
    },
  );

  return svc;
}
