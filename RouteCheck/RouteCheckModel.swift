import CoreLocation
import Foundation
import ZTLCore

/// Esito del controllo: zone attraversate da ciascun percorso.
struct RouteAnalysis {
    let result: RouteCheckResult
    let hits: [[RouteHit]]
    /// Se il percorso principale passa dall'Area C quando non è attiva: quando riapre.
    var areaCReopens: Date?

    var mainHits: [RouteHit] { hits.first ?? [] }

    /// Prima alternativa che non attraversa zone, se il percorso principale ne attraversa.
    var cleanAlternative: RouteOption? {
        guard !mainHits.isEmpty else { return nil }
        return zip(result.options, hits).first { $0.1.isEmpty }?.0
    }

    /// Link per Google Maps che segue l'alternativa senza zone.
    var alternativeLink: URL? {
        guard let alternative = cleanAlternative else { return nil }
        let waypoints = RouteAnalyzer.detourWaypoints(alternative: alternative.coordinates, avoiding: mainHits)
        return GoogleMapsLink.directionsURL(origin: result.origin, destination: result.destination, waypoints: waypoints)
    }

    /// Dove lasciare l'auto: poco prima della prima zona del percorso principale.
    /// `nil` se il percorso parte già dentro la zona.
    private var switchSample: (point: Coordinate, distanceAlong: Double)? {
        guard let hit = mainHits.first, let main = result.options.first else { return nil }
        return RouteAnalyzer.switchPoint(route: main.coordinates, before: hit)
    }

    var switchPoint: Coordinate? { switchSample?.point }

    /// Metri del percorso in auto rimasti dopo il punto di cambio.
    var lastLegDistance: Double {
        guard let main = result.options.first else { return 0 }
        return max(0, main.distance - (switchSample?.distanceAlong ?? 0))
    }

    /// Primo tratto in auto, fino al punto di cambio.
    func drivingLegLink(to point: Coordinate) -> URL {
        GoogleMapsLink.directionsURL(origin: result.origin, destination: point)
    }

    /// Ultimo tratto con l'altro mezzo; senza punto di cambio parte dalla partenza.
    func lastLegLink(from point: Coordinate?, mode: TravelMode) -> URL {
        GoogleMapsLink.directionsURL(origin: point ?? result.origin, destination: result.destination, mode: mode)
    }

    /// Minuti in più dell'alternativa rispetto al percorso principale.
    var extraMinutes: Int {
        guard let alternative = cleanAlternative, let main = result.options.first else { return 0 }
        return max(0, Int(((alternative.travelTime - main.travelTime) / 60).rounded()))
    }
}

@MainActor
final class RouteCheckModel: ObservableObject {
    enum Phase {
        case idle
        case loading
        case failed(String)
        case done(RouteAnalysis)
    }

    @Published private(set) var phase: Phase = .idle
    /// Messaggio informativo mostrato sotto il risultato.
    @Published var notice: String?
    /// Passaggi del controllo, per capire cosa non va.
    @Published private(set) var details: [String] = []
    /// Mezzo per l'ultimo tratto, dopo aver lasciato l'auto fuori dalla zona.
    @Published var lastLegMode: TravelMode {
        didSet { defaults.set(lastLegMode.rawValue, forKey: "lastLegMode") }
    }
    /// Indirizzo del punto in cui lasciare l'auto.
    @Published private(set) var switchPointName: String?
    @Published var vehicle: Vehicle {
        didSet {
            defaults.set(vehicle.rawValue, forKey: "routeVehicle")
            reanalyze()
        }
    }

    private let defaults = UserDefaults.standard
    private var result: RouteCheckResult?
    private var task: Task<Void, Never>?
    private let geocoder = CLGeocoder()

    init() {
        vehicle = Vehicle(rawValue: UserDefaults.standard.string(forKey: "routeVehicle") ?? "") ?? .auto
        lastLegMode = TravelMode(rawValue: UserDefaults.standard.string(forKey: "lastLegMode") ?? "") ?? .walking
    }

    func check(_ text: String) {
        task?.cancel()
        result = nil
        details = []
        phase = .loading
        task = Task {
            do {
                let result = try await RouteChecker.check(text: text) { [weak self] line in
                    Task { @MainActor in self?.details.append(line) }
                }
                guard !Task.isCancelled else { return }
                self.result = result
                reanalyze()
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func reanalyze() {
        guard let result else { return }
        let rules = ZoneRules(isMotorcycle: vehicle == .moto, includeAreaB: defaults.bool(forKey: "includeAreaB"))
        let hits = result.options.map { option in
            RouteAnalyzer.hits(
                route: option.coordinates,
                travelTime: option.travelTime,
                departure: result.departure,
                zones: ZoneData.zones,
                gates: ZoneData.gates,
                rules: rules
            )
        }
        var analysis = RouteAnalysis(result: result, hits: hits)
        analysis.areaCReopens = inactiveAreaCReopening(result: result, hits: hits.first ?? [])
        phase = .done(analysis)
        nameSwitchPoint(analysis.switchPoint)
    }

    /// In auto, se il percorso entra nell'Area C ma non la conta perché spenta, quando riapre.
    private func inactiveAreaCReopening(result: RouteCheckResult, hits: [RouteHit]) -> Date? {
        guard vehicle == .auto, !hits.contains(where: { $0.zone == .areaC }), let main = result.options.first else { return nil }
        let crossing = RouteAnalyzer.hits(
            route: main.coordinates,
            travelTime: main.travelTime,
            departure: result.departure,
            zones: ZoneData.zones.filter { $0.zone == .areaC },
            rules: ZoneRules(ignoreSchedule: true)
        ).first
        guard let crossing else { return nil }
        return ZoneSchedule.nextAreaActivation(after: crossing.passTime)
    }

    private func nameSwitchPoint(_ point: Coordinate?) {
        geocoder.cancelGeocode()
        switchPointName = nil
        guard let point else { return }
        geocoder.reverseGeocodeLocation(CLLocation(latitude: point.latitude, longitude: point.longitude)) { [weak self] placemarks, _ in
            guard let placemark = placemarks?.first else { return }
            let name = [placemark.thoroughfare, placemark.subThoroughfare].compactMap { $0 }.joined(separator: " ")
            Task { @MainActor in
                self?.switchPointName = name.isEmpty ? placemark.name : name
            }
        }
    }
}
