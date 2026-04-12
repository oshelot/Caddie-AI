// Shared FakeLocationService for the location tests AND any
// downstream feature tests (KAN-280 / S10 onward) that need to
// drive a `LocationGate` without touching the real `geolocator`
// or `permission_handler` plugins.

import 'package:caddieai/core/location/location_service.dart';

class FakeLocationService implements LocationService {
  FakeLocationService({
    LocationPermission initialStatus = LocationPermission.notDetermined,
    LocationPermission? requestResult,
  })  : _status = initialStatus,
        _requestResult = requestResult;

  LocationPermission _status;
  final LocationPermission? _requestResult;

  int requestCallCount = 0;
  int openSettingsCallCount = 0;

  /// Test hook to flip the status (e.g. simulate the user
  /// returning from settings with permission newly granted).
  void setStatus(LocationPermission status) => _status = status;

  @override
  Future<LocationPermission> permissionStatus() async => _status;

  @override
  Future<LocationPermission> requestPermission() async {
    requestCallCount++;
    final result = _requestResult;
    if (result != null) {
      _status = result;
    }
    return _status;
  }

  @override
  Future<LocationReading> currentLocation() async {
    throw UnimplementedError();
  }

  @override
  Stream<HeadingReading> headingStream() {
    throw UnimplementedError();
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCallCount++;
    return true;
  }
}
