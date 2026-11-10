import CoreLocation
import Observation

/// The phone's current position, for centring the map and for dropping a dot where the helper
/// is standing. Asks for permission the first time `start()` is called.
@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    /// The latest fix, or nil before the first one arrives.
    private(set) var location: CLLocation?

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorization = manager.authorizationStatus
    }

    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    private var isAllowed: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    func start() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if isAllowed {
            manager.startUpdatingLocation()
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if isAllowed { manager.startUpdatingLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A failed fix leaves the last good one in place; the map can still be tapped.
    }
}
