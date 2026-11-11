import CoreLocation
import Observation

/// The device's position and the direction it is pointing.
@MainActor @Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    private(set) var location: CLLocation?
    /// Degrees clockwise from true north, or `nil` when the device cannot tell.
    private(set) var heading: CLLocationDirection?
    private(set) var isDenied = false

    func start() {
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            isDenied = status == .denied || status == .restricted
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            location = locations.last
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let direction = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        MainActor.assumeIsolated {
            heading = direction
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}
}
