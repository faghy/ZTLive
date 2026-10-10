import ActivityKit
import CoreLocation
import Foundation
import ZTLCore

enum Vehicle: String, CaseIterable, Identifiable {
    case auto
    case moto

    var id: String { rawValue }
    var label: String { self == .auto ? "Auto" : "Moto" }
}

enum RunMode {
    case off
    case real
    case simulation
}

@MainActor
final class AppModel: ObservableObject {
    typealias State = GateActivityAttributes.ContentState

    @Published private(set) var mode: RunMode = .off
    @Published private(set) var state = State.clear(vehicle: Vehicle.auto.label)
    @Published private(set) var gpsUpdates = 0
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var gatesCount = 0

    @Published var vehicle: Vehicle {
        didSet { defaults.set(vehicle.rawValue, forKey: "vehicle") }
    }
    @Published var voiceEnabled: Bool {
        didSet { defaults.set(voiceEnabled, forKey: "voiceEnabled") }
    }
    @Published var includeAreaB: Bool {
        didSet { defaults.set(includeAreaB, forKey: "includeAreaB") }
    }
    /// Solo per le prove: avvisa anche fuori dagli orari di Area B/C.
    @Published var ignoreSchedule: Bool {
        didSet { defaults.set(ignoreSchedule, forKey: "ignoreSchedule") }
    }

    /// Sotto questa distanza l'avviso diventa "imminente".
    static let imminentDistance = 120.0

    private let defaults = UserDefaults.standard
    private let location = LocationService()
    private let liveActivity = LiveActivityManager()
    private let speaker = Speaker()
    private let gates: [Gate]
    private var announced: [String: State.Status] = [:]
    private var simulationTimer: Timer?
    private var simulatedDistance = 0.0

    var liveActivitiesEnabled: Bool {
        liveActivity.areActivitiesEnabled
    }

    init() {
        let defaults = UserDefaults.standard
        vehicle = Vehicle(rawValue: defaults.string(forKey: "vehicle") ?? "") ?? .auto
        voiceEnabled = defaults.object(forKey: "voiceEnabled") as? Bool ?? true
        includeAreaB = defaults.bool(forKey: "includeAreaB")
        ignoreSchedule = defaults.object(forKey: "ignoreSchedule") as? Bool ?? true
        gates = Self.loadGates()
        gatesCount = gates.count
        authorization = location.authorizationStatus

        location.onUpdate = { [weak self] location in
            self?.handle(location)
        }
        location.onAuthorizationChange = { [weak self] status in
            self?.authorization = status
        }
    }

    // MARK: - Comandi

    func startMonitoring() {
        stop()
        mode = .real
        location.start()
        liveActivity.start(state: .clear(vehicle: vehicle.label))
    }

    /// Simula l'avvicinamento a un varco ogni 2 secondi, per provare Live Activity e CarPlay da fermi.
    /// Il GPS resta acceso solo per tenere viva l'app in background.
    func startSimulation() {
        stop()
        mode = .simulation
        location.start()
        liveActivity.start(state: .clear(vehicle: vehicle.label))
        simulatedDistance = 600
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.simulationTick()
            }
        }
    }

    func stop() {
        simulationTimer?.invalidate()
        simulationTimer = nil
        location.stop()
        liveActivity.endAll()
        announced = [:]
        state = .clear(vehicle: vehicle.label)
        mode = .off
    }

    // MARK: - Logica

    private func handle(_ location: CLLocation) {
        gpsUpdates += 1
        guard mode == .real else { return }

        // Con l'auto ferma la direzione GPS non è affidabile.
        let course = location.course >= 0 && location.speed > 1.5 ? location.course : nil
        let position = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let now = Date()
        let monitor = GateMonitor(gates: gates.filter { isRelevant($0.zone, at: now) })
        present(monitor.nearestGate(from: position, course: course))
    }

    private func simulationTick() {
        simulatedDistance -= 25
        if simulatedDistance < -100 {
            simulatedDistance = 600
        }
        guard simulatedDistance >= 0, simulatedDistance <= 400, let gate = gates.first else {
            present(nil)
            return
        }
        present(Approach(gate: gate, distance: simulatedDistance, isAhead: true))
    }

    private func isRelevant(_ zone: Zone, at date: Date) -> Bool {
        let active = ignoreSchedule || ZoneSchedule.isAreaActive(at: date)
        switch zone {
        case .areaC: return vehicle == .auto && active
        case .areaB: return includeAreaB && active
        case .ztl: return true
        }
    }

    private func present(_ approach: Approach?) {
        guard let approach else {
            announced = [:]
            state = .clear(vehicle: vehicle.label)
            liveActivity.update(state)
            return
        }

        let status: State.Status = approach.distance <= Self.imminentDistance ? .imminent : .approaching
        state = State(
            status: status,
            gateName: approach.gate.name,
            zone: approach.gate.zone.label,
            distance: Int((approach.distance / 10).rounded()) * 10,
            vehicle: vehicle.label
        )

        // Avvisa solo quando il livello sale, una volta per varco.
        announced = announced.filter { $0.key == approach.gate.id }
        let previous = announced[approach.gate.id] ?? .clear
        guard status > previous else {
            liveActivity.update(state)
            return
        }
        announced[approach.gate.id] = status

        let message = spokenMessage(for: approach, status: status)
        liveActivity.update(state, alert: AlertConfiguration(
            title: "Varco \(state.zone)",
            body: "\(state.gateName) tra \(state.distance) m",
            sound: .default
        ))
        if voiceEnabled {
            speaker.say(message)
        }
    }

    private func spokenMessage(for approach: Approach, status: State.Status) -> String {
        let zone = approach.gate.zone.label
        if status == .imminent {
            return "Attenzione, varco \(zone) \(approach.gate.name) a \(state.distance) metri."
        }
        let rounded = Int((approach.distance / 50).rounded()) * 50
        return "Varco \(zone) \(approach.gate.name) tra \(rounded) metri."
    }

    private static func loadGates() -> [Gate] {
        let files: [(String, Zone)] = [("areac_varchi", .areaC), ("areab_varchi", .areaB)]
        return files.flatMap { name, zone -> [Gate] in
            guard let url = Bundle.main.url(forResource: name, withExtension: "geojson"),
                  let data = try? Data(contentsOf: url),
                  let gates = try? GateLoader.load(geoJSON: data, zone: zone) else {
                print("Dataset \(name) non caricato")
                return []
            }
            return gates
        }
    }
}
