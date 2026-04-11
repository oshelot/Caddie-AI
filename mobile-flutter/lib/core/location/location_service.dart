// LocationService — KAN-274 (S4) Flutter port of the iOS
// `LocationManager` and Android `LocationService` natives.
//
// **Why an abstraction over geolocator + permission_handler:**
// the AC says "LocationService is mockable for tests". A direct
// dependency on `Geolocator.getCurrentPosition()` and
// `Permission.location.request()` would force every consumer to
// pull a real platform channel into its tests. Instead, this file
// defines the abstract `LocationService` interface that feature
// code talks to, and `GeolocatorLocationService` is the production
// impl that delegates to the real plugins. Tests use a fake.
//
// **Permission model.** The Course tab map screen (KAN-S10) needs
// "while in use" permission to render the player's puck. We do NOT
// request "always" — that's reserved for any future
// background-tracking story (none planned). The first-launch
// prompt path is:
//
//   1. App cold-starts, MainShell builds the Course tab.
//   2. CoursePlaceholder (today) / CourseMapScreen (after S10)
//      wraps its content in `LocationGate` (see
//      `lib/core/location/location_gate.dart`).
//   3. `LocationGate` calls `LocationService.permissionStatus()`.
//   4. If `notDetermined`, it calls `requestPermission()` and
//      shows the system prompt BEFORE inflating the map widget —
//      this is the AC's "before, not after" requirement.
//   5. If `granted`, the map renders normally.
//   6. If `denied` or `permanentlyDenied`, the gate renders the
//      "enable location in settings" banner with a deep-link
//      button to the system settings page.
//
// **Heading stream:** the AC asks for a unified "current location,
// heading stream, permission state" API. Heading is exposed as a
// `Stream<HeadingReading>` instead of a one-shot getter because
// the Course map's player puck rotates in real time, and feeding
// it via a stream avoids per-frame polling.

import 'dart:async';

/// Permission state for the location feature. Maps onto the
/// platform-handler's `PermissionStatus` enum but with a tighter
/// vocabulary that fits the UI's branching needs (the
/// `permission_handler` enum has values like `provisional` and
/// `limited` that don't apply to location).
enum LocationPermission {
  /// The user hasn't been asked yet — show the system prompt.
  notDetermined,

  /// The user granted "while in use" or "always" — proceed.
  granted,

  /// The user denied this run, but the app can ask again next
  /// launch (Android) or after re-prompting (iOS, sometimes).
  denied,

  /// The user permanently denied permission. The system prompt
  /// will not appear; the user must enable the permission in
  /// the system settings UI. The UI shows a deep-link button.
  permanentlyDenied,

  /// Restricted by parental controls / MDM / device policy. Same
  /// UI treatment as permanentlyDenied (no point in re-asking).
  restricted,
}

/// One location reading. Yards-aware downstream code wants double
/// precision; latitude/longitude come straight from the platform
/// in degrees. `accuracyMeters` is exposed so consumers can decide
/// whether to trust the reading (e.g. ignore anything > 50 m for
/// shot distance calculations).
class LocationReading {
  const LocationReading({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestampMs,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final int timestampMs;
}

/// One heading reading. Degrees clockwise from true north,
/// 0..360. Source platform may report magnetic-north heading;
/// Geolocator's stream normalizes to true-north on iOS but not
/// on Android — consumers that need magnetic-vs-true precision
/// should consult the heading source and apply declination
/// themselves. For map-puck rotation the difference is below
/// the rendering threshold and can be ignored.
class HeadingReading {
  const HeadingReading({required this.degrees, required this.timestampMs});
  final double degrees;
  final int timestampMs;
}

/// Public location API. Feature code talks to this; tests inject
/// a fake. The production implementation is
/// `GeolocatorLocationService` in `geolocator_location_service.dart`.
abstract class LocationService {
  /// Returns the current permission state without prompting.
  Future<LocationPermission> permissionStatus();

  /// Triggers the system permission prompt and returns the
  /// resulting state. Calling this when the state is already
  /// `granted` is a no-op that returns `granted`. Calling it
  /// when the state is `permanentlyDenied` does NOT re-prompt
  /// (the OS won't show the dialog) — instead, it returns the
  /// same `permanentlyDenied`, and the UI is expected to surface
  /// the settings deep-link.
  Future<LocationPermission> requestPermission();

  /// Returns a single best-effort location reading. Throws
  /// `LocationException` if the permission isn't granted or the
  /// platform can't fix a position within a reasonable timeout
  /// (the production impl uses 15 s).
  Future<LocationReading> currentLocation();

  /// Stream of compass heading readings. Throws on subscribe if
  /// permission isn't granted. The stream remains hot for the
  /// service's lifetime; consumers should cancel their
  /// subscription when done to release the platform listener.
  Stream<HeadingReading> headingStream();

  /// Opens the platform's app-settings page so the user can
  /// re-grant a permanently-denied location permission. Returns
  /// true if the page actually opened. The UI's "enable location
  /// in settings" button calls this.
  Future<bool> openSettings();
}

/// Thrown by [LocationService.currentLocation] when the platform
/// can't honor the request. Subclassed by callers when they want
/// finer-grained handling.
class LocationException implements Exception {
  const LocationException(this.message);
  final String message;
  @override
  String toString() => 'LocationException: $message';
}
