import Foundation
import ZTLCore

/// Esito del controllo: zone attraversate da ciascun percorso.
struct RouteAnalysis {
    let result: RouteCheckResult
    let hits: [[RouteHit]]

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
    @Published var vehicle: Vehicle {
        didSet {
            defaults.set(vehicle.rawValue, forKey: "routeVehicle")
            reanalyze()
        }
    }

    private let defaults = UserDefaults.standard
    private var result: RouteCheckResult?
    private var task: Task<Void, Never>?

    init() {
        vehicle = Vehicle(rawValue: UserDefaults.standard.string(forKey: "routeVehicle") ?? "") ?? .auto
    }

    func check(_ text: String) {
        task?.cancel()
        result = nil
        phase = .loading
        task = Task {
            do {
                let result = try await RouteChecker.check(text: text)
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
        phase = .done(RouteAnalysis(result: result, hits: hits))
    }
}
