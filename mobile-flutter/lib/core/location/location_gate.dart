// LocationGate — wraps a child widget that requires location
// permission, and ensures the system permission prompt is shown
// BEFORE the child renders. This is the structural enforcement of
// **KAN-274 AC #1**:
//
// > First-run permission prompt appears BEFORE the Course tab's
// > map screen renders, not after — avoid the native-app UX
// > regression where the map loads with no location.
//
// Usage (when KAN-S10 ships the real Course map screen):
//
//     LocationGate(
//       service: locationService,
//       child: CourseMapScreen(...),
//     )
//
// The gate's flow:
//
//   1. On mount, calls `service.permissionStatus()`.
//   2. If granted → renders `child`.
//   3. If notDetermined → shows a brief rationale screen with a
//      "Continue" button. Tapping it triggers the system prompt
//      via `service.requestPermission()`. The system dialog
//      appears BEFORE the child mounts.
//   4. If denied / permanentlyDenied / restricted → shows the
//      "enable location in settings" banner with a deep-link
//      button (the **AC #2** path: "Denied-permission path
//      renders a clear 'enable location in settings' banner,
//      doesn't crash").
//
// The rationale screen exists because both Apple and Google have
// rejected apps that show the system permission dialog without
// any context. A two-line "we use your location to show your
// position on the course map" rationale shipped before the
// system prompt is the cheapest way to comply.

import 'package:flutter/material.dart';

import 'location_service.dart';

class LocationGate extends StatefulWidget {
  const LocationGate({
    super.key,
    required this.service,
    required this.child,
    this.rationale =
        'CaddieAI uses your location to show your position on '
        'the course map and calculate shot distances.',
  });

  /// The service that owns the permission state. Injected so tests
  /// can pass a fake without touching the real plugins.
  final LocationService service;

  /// What to render once permission has been granted.
  final Widget child;

  /// Plain-language explanation shown above the "Continue" button
  /// before the system permission dialog appears. Both stores
  /// require this kind of rationale before the OS dialog.
  final String rationale;

  @override
  State<LocationGate> createState() => _LocationGateState();
}

class _LocationGateState extends State<LocationGate> {
  LocationPermission? _status;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final status = await widget.service.permissionStatus();
    if (!mounted) return;
    setState(() => _status = status);
  }

  Future<void> _request() async {
    setState(() => _requesting = true);
    final status = await widget.service.requestPermission();
    if (!mounted) return;
    setState(() {
      _status = status;
      _requesting = false;
    });
  }

  Future<void> _openSettings() async {
    await widget.service.openSettings();
    // After returning from settings, refresh — the user may have
    // toggled the permission on.
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null) {
      return const _LoadingScaffold();
    }
    switch (status) {
      case LocationPermission.granted:
        return widget.child;
      case LocationPermission.notDetermined:
        return _RationaleScaffold(
          rationale: widget.rationale,
          onContinue: _requesting ? null : _request,
        );
      case LocationPermission.denied:
      case LocationPermission.permanentlyDenied:
      case LocationPermission.restricted:
        return _DeniedScaffold(
          status: status,
          onOpenSettings: _openSettings,
          onRetry: _refresh,
        );
    }
  }
}

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _RationaleScaffold extends StatelessWidget {
  const _RationaleScaffold({
    required this.rationale,
    required this.onContinue,
  });

  final String rationale;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Location Access',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                rationale,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onContinue,
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeniedScaffold extends StatelessWidget {
  const _DeniedScaffold({
    required this.status,
    required this.onOpenSettings,
    required this.onRetry,
  });

  final LocationPermission status;
  final VoidCallback onOpenSettings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPermanent = status == LocationPermission.permanentlyDenied ||
        status == LocationPermission.restricted;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.location_off_outlined,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Location Access Required',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                isPermanent
                    ? 'Location is currently disabled. Open Settings '
                        'to enable it for CaddieAI.'
                    : 'CaddieAI needs location access to show the '
                        'course map. Tap Continue to grant permission.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              if (isPermanent)
                FilledButton.icon(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Open Settings'),
                )
              else
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Continue'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
