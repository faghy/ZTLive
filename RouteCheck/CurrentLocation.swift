import CoreLocation

/// Legge una volta la posizione attuale, per i percorsi che partono da dove ti trovi.
/// Apple Maps non calcola in modo affidabile i percorsi da `MKMapItem.forCurrentLocation()` nelle app di terze parti.
final class CurrentLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?
    /// Il delegate del manager è debole: l'oggetto si tiene in vita da solo finché non ha una risposta.
    private var keepAlive: CurrentLocation?

    /// Il manager va creato sul main thread, così i callback arrivano sul main thread.
    @MainActor
    static func fetch() async throws -> CLLocation {
        let locator = CurrentLocation()
        return try await withCheckedThrowingContinuation { continuation in
            locator.continuation = continuation
            locator.keepAlive = locator
            // Il delegate riceve subito lo stato dell'autorizzazione e da lì parte la richiesta.
            locator.manager.delegate = locator
        }
    }

    private override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        manager.delegate = nil
        keepAlive = nil
        continuation.resume(with: result)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finish(.failure(RouteCheckError.noLocation("accesso alla posizione non consentito")))
        default:
            if let recent = manager.location, recent.timestamp.timeIntervalSinceNow > -60 {
                finish(.success(recent))
            } else {
                manager.requestLocation()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        finish(.success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(RouteCheckError.noLocation(error.localizedDescription)))
    }
}
