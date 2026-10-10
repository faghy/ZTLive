import CoreLocation

/// GPS continuo, anche con l'app in background (es. mentre si usa Google Maps).
final class LocationService: NSObject, CLLocationManagerDelegate {
    var onUpdate: (@MainActor (CLLocation) -> Void)?
    var onAuthorizationChange: (@MainActor (CLAuthorizationStatus) -> Void)?

    private let manager = CLLocationManager()
    private var backgroundSession: CLBackgroundActivitySession?

    var authorizationStatus: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        backgroundSession = CLBackgroundActivitySession()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        backgroundSession?.invalidate()
        backgroundSession = nil
    }

    // Il manager è creato sul main thread, quindi i callback arrivano sul main thread.

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        MainActor.assumeIsolated {
            onUpdate?(location)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            onAuthorizationChange?(status)
        }
    }
}
