// Production LocationService implementation. Delegates to
// `permission_handler` for the permission state and the system
// prompt, and to `geolocator` for the actual location + heading
// streams.
//
// Why split the two plugins instead of using just `geolocator`'s
// permission API: `permission_handler` has the better cross-
// platform model — one Permission enum, one settings deep-link.
// `geolocator`'s permission methods exist but they don't expose
// the "permanently denied" state cleanly across platforms, and
// the settings-deep-link is `permission_handler`-only. We treat
// `permission_handler` as the source of truth for state.

import 'dart:async';

import 'package:geolocator/geolocator.dart' as geo;
import 'package:permission_handler/permission_handler.dart';

import 'location_service.dart';

class GeolocatorLocationService implements LocationService {
  GeolocatorLocationService({
    Duration currentLocationTimeout = const Duration(seconds: 15),
    geo.LocationAccuracy accuracy = geo.LocationAccuracy.high,
  })  : _currentLocationTimeout = currentLocationTimeout,
        _accuracy = accuracy;

  final Duration _currentLocationTimeout;
  final geo.LocationAccuracy _accuracy;

  @override
  Future<LocationPermission> permissionStatus() async {
    final status = await Permission.locationWhenInUse.status;
    return _mapStatus(status);
  }

  @override
  Future<LocationPermission> requestPermission() async {
    // Check first — if already granted, the request call would
    // be a no-op anyway, but we want to short-circuit the
    // platform round-trip.
    final existing = await Permission.locationWhenInUse.status;
    if (existing.isGranted) return LocationPermission.granted;
    if (existing.isPermanentlyDenied) {
      return LocationPermission.permanentlyDenied;
    }
    if (existing.isRestricted) return LocationPermission.restricted;

    final result = await Permission.locationWhenInUse.request();
    return _mapStatus(result);
  }

  @override
  Future<LocationReading> currentLocation() async {
    final permission = await permissionStatus();
    if (permission != LocationPermission.granted) {
      throw const LocationException('Location permission not granted');
    }
    final servicesEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!servicesEnabled) {
      throw const LocationException('System location services disabled');
    }
    try {
      final position = await geo.Geolocator.getCurrentPosition(
        locationSettings: geo.LocationSettings(accuracy: _accuracy),
      ).timeout(_currentLocationTimeout);
      return LocationReading(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        timestampMs: position.timestamp.millisecondsSinceEpoch,
      );
    } on TimeoutException {
      throw const LocationException(
        'Timed out waiting for a location fix',
      );
    } catch (e) {
      throw LocationException(e.toString());
    }
  }

  @override
  Stream<HeadingReading> headingStream() async* {
    final permission = await permissionStatus();
    if (permission != LocationPermission.granted) {
      throw const LocationException('Location permission not granted');
    }
    // Geolocator's heading stream comes from `getPositionStream`'s
    // `heading` field. Filter out readings with `heading == -1`,
    // which Geolocator emits when the device can't determine a
    // direction (e.g. stationary, no compass).
    yield* geo.Geolocator.getPositionStream(
      locationSettings: geo.LocationSettings(
        accuracy: _accuracy,
        distanceFilter: 1,
      ),
    )
        .where((p) => p.heading >= 0)
        .map(
          (p) => HeadingReading(
            degrees: p.heading,
            timestampMs: p.timestamp.millisecondsSinceEpoch,
          ),
        );
  }

  @override
  Future<bool> openSettings() => openAppSettings();

  LocationPermission _mapStatus(PermissionStatus status) {
    if (status.isGranted || status.isLimited) {
      return LocationPermission.granted;
    }
    if (status.isPermanentlyDenied) {
      return LocationPermission.permanentlyDenied;
    }
    if (status.isRestricted) return LocationPermission.restricted;
    if (status.isDenied) return LocationPermission.denied;
    return LocationPermission.notDetermined;
  }
}
