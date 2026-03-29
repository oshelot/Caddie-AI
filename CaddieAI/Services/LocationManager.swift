//
//  LocationManager.swift
//  CaddieAI
//
//  Manages CoreLocation permission requests for showing
//  the user's position on the course map.
//

import CoreLocation

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var currentLocation: CLLocationCoordinate2D?

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    override init() {
        authorizationStatus = CLLocationManager().authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if isAuthorized {
            manager.requestLocation()
        }
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// Request a single location update (e.g. for proximity check on startup).
    func requestCurrentLocation() {
        guard isAuthorized else { return }
        manager.requestLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized && currentLocation == nil {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last?.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location is best-effort for the proximity feature; silently ignore errors
    }
}
