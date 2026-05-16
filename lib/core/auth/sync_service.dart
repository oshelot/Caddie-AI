// KAN-416: Sync service — pushes local Hive data to cloud, pulls cloud
// data to local. Offline-first: writes always go to Hive first, then
// async push. Failed pushes are queued and retried on app resume.

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/player_profile.dart';
import '../../models/scorecard_entry.dart';
import '../storage/app_storage.dart';
import '../storage/profile_repository.dart';
import '../storage/scorecard_repository.dart';
import 'auth_service.dart';
import 'sync_client.dart';

class SyncService {
  SyncService({
    required this.authService,
    required this.syncClient,
    required this.profileRepo,
    required this.scorecardRepo,
  });

  final AuthService authService;
  final SyncClient syncClient;
  final ProfileRepository profileRepo;
  final ScorecardRepository scorecardRepo;

  bool _syncing = false;

  /// Push the current profile to cloud.
  Future<bool> pushProfile(PlayerProfile profile) async {
    if (!authService.isAuthenticated) return false;
    final resp = await syncClient.put(
      dataType: 'profile',
      dataId: 'self',
      data: profile.toJson(),
      updatedAtMs: profile.updatedAtMs,
      version: 1,
    );
    if (!resp.ok) {
      debugPrint('SyncService: pushProfile failed: ${resp.error}');
      _enqueue('profile', 'self');
    }
    return resp.ok;
  }

  /// Push a single scorecard to cloud.
  Future<bool> pushScorecard(ScorecardEntry scorecard) async {
    if (!authService.isAuthenticated) return false;
    final resp = await syncClient.put(
      dataType: 'scorecard',
      dataId: scorecard.id,
      data: scorecard.toJson(),
      updatedAtMs: scorecard.dateMs,
      version: 1,
    );
    if (!resp.ok) {
      debugPrint('SyncService: pushScorecard failed: ${resp.error}');
      _enqueue('scorecard', scorecard.id);
    }
    return resp.ok;
  }

  /// Push all local data to cloud — called on first sign-in (guest → account).
  Future<SyncReport> pushAllLocal() async {
    if (!authService.isAuthenticated) return SyncReport.empty();

    int pushed = 0;
    int failed = 0;

    // Profile
    try {
      final profile = profileRepo.loadOrDefault();
      final ok = await pushProfile(profile);
      ok ? pushed++ : failed++;
    } catch (e) {
      debugPrint('SyncService: pushAllLocal profile error: $e');
      failed++;
    }

    // Scorecards
    try {
      final scorecards = scorecardRepo.loadAll();
      for (final sc in scorecards) {
        final ok = await pushScorecard(sc);
        ok ? pushed++ : failed++;
      }
    } catch (e) {
      debugPrint('SyncService: pushAllLocal scorecards error: $e');
      failed++;
    }

    return SyncReport(pushed: pushed, failed: failed);
  }

  /// Pull all cloud data to local — called on sign-in on a new device.
  /// Uses last-write-wins by updatedAtMs.
  Future<SyncReport> pullAll() async {
    if (!authService.isAuthenticated) return SyncReport.empty();
    if (_syncing) return SyncReport.empty();
    _syncing = true;

    int pulled = 0;
    int skipped = 0;

    try {
      // Pull profile
      final profileResp = await syncClient.get('profile', 'self');
      if (profileResp.ok) {
        final cloudData = profileResp.body['data'] as Map<String, dynamic>?;
        if (cloudData != null) {
          final cloudProfile = PlayerProfile.fromJson(cloudData);
          final localProfile = profileRepo.loadOrDefault();
          // Last-write-wins
          if (cloudProfile.updatedAtMs > localProfile.updatedAtMs) {
            await profileRepo.save(cloudProfile);
            pulled++;
          } else {
            skipped++;
          }
        }
      }

      // Pull scorecards
      final scResp = await syncClient.list('scorecard');
      if (scResp.ok) {
        final items = scResp.body['items'] as List<dynamic>? ?? [];
        final localScorecards = scorecardRepo.loadAll();
        final localById = {for (final sc in localScorecards) sc.id: sc};

        for (final item in items) {
          final data = item['data'] as Map<String, dynamic>?;
          if (data == null) continue;
          final cloudSc = ScorecardEntry.fromJson(data);
          final localSc = localById[cloudSc.id];

          if (localSc == null || cloudSc.dateMs > localSc.dateMs) {
            await scorecardRepo.save(cloudSc);
            pulled++;
          } else {
            skipped++;
          }
        }
      }
    } catch (e) {
      debugPrint('SyncService: pullAll error: $e');
    } finally {
      _syncing = false;
    }

    return SyncReport(pushed: 0, failed: 0, pulled: pulled, skipped: skipped);
  }

  /// Drain the pending sync queue — call on app resume or connectivity restore.
  Future<void> drainQueue() async {
    if (!authService.isAuthenticated) return;

    final box = AppStorage.syncQueueBox;
    if (box == null) return;

    final keys = box.keys.toList();
    for (final key in keys) {
      final raw = box.get(key);
      if (raw == null) continue;

      try {
        final entry = jsonDecode(raw) as Map<String, dynamic>;
        final dataType = entry['dataType'] as String;
        final dataId = entry['dataId'] as String;

        bool ok = false;
        if (dataType == 'profile') {
          ok = await pushProfile(profileRepo.loadOrDefault());
        } else if (dataType == 'scorecard') {
          final sc = scorecardRepo.loadById(dataId);
          if (sc != null) ok = await pushScorecard(sc);
        }

        if (ok) await box.delete(key);
      } catch (e) {
        debugPrint('SyncService: drainQueue error for $key: $e');
      }
    }
  }

  void _enqueue(String dataType, String dataId) {
    final box = AppStorage.syncQueueBox;
    if (box == null) return;
    final key = '$dataType#$dataId';
    box.put(key, jsonEncode({
      'dataType': dataType,
      'dataId': dataId,
      'enqueuedAtMs': DateTime.now().millisecondsSinceEpoch,
    }));
  }
}

class SyncReport {
  const SyncReport({
    this.pushed = 0,
    this.failed = 0,
    this.pulled = 0,
    this.skipped = 0,
  });

  factory SyncReport.empty() => const SyncReport();

  final int pushed;
  final int failed;
  final int pulled;
  final int skipped;

  @override
  String toString() =>
      'SyncReport(pushed=$pushed, failed=$failed, pulled=$pulled, skipped=$skipped)';
}
