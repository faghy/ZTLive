import ActivityKit
import CoreLocation
import Foundation
import ZTLCore

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
    @Published private(set) var zonesCount = 0
    /// Ultimo aggiornamento dei dati del Comune; `nil` = quelli inclusi nell'app.
    @Published private(set) var dataUpdatedAt: Date?
    @Published private(set) var connectedDevice: VehicleDetector.Device?
    /// Il veicolo è stato scelto automaticamente dal dispositivo collegato.
    @Published private(set) var vehicleIsAutomatic = false

    @Published var vehicle: Vehicle {
        didSet {
            defaults.set(vehicle.rawValue, forKey: "vehicle")
            // Una scelta manuale con un dispositivo collegato viene ricordata per le prossime volte.
            if !isApplyingDetection, let connectedDevice {
                vehicleDetector.associate(connectedDevice, with: vehicle)
                vehicleIsAutomatic = true
            }
        }
    }
    @Published var voiceEnabled: Bool {
        didSet { defaults.set(voiceEnabled, forKey: "voiceEnabled") }
    }
    @Published var includeAreaB: Bool {
        didSet { defaults.set(includeAreaB, forKey: "includeAreaB") }
    }
    @Published var includeLocalZones: Bool {
        didSet { defaults.set(includeLocalZones, forKey: "includeLocalZones") }
    }
    /// Solo per le prove: avvisa anche fuori dagli orari.
    @Published var ignoreSchedule: Bool {
        didSet { defaults.set(ignoreSchedule, forKey: "ignoreSchedule") }
    }

    /// Sotto questa distanza l'avviso diventa "imminente".
    static let imminentDistance = 120.0

    private let defaults = UserDefaults.standard
    private let location = LocationService()
    private let liveActivity = LiveActivityManager()
    private let speaker = Speaker()
    private let vehicleDetector = VehicleDetector()
    private var gates: [Gate] { ZoneData.gates }
    /// Durante la guida Area B e C si controllano dai varchi, non dal perimetro.
    private var localZones: [LocalZone] { ZoneData.zones.filter { !$0.zone.hasGates } }
    private var announced: [String: State.Status] = [:]
    private var simulationTimer: Timer?
    private var simulatedDistance = 0.0
    private var isApplyingDetection = false

    var liveActivitiesEnabled: Bool {
        liveActivity.areActivitiesEnabled
    }

    init() {
        let defaults = UserDefaults.standard
        vehicle = Vehicle(rawValue: defaults.string(forKey: "vehicle") ?? "") ?? .auto
        voiceEnabled = defaults.object(forKey: "voiceEnabled") as? Bool ?? true
        includeAreaB = defaults.bool(forKey: "includeAreaB")
        includeLocalZones = defaults.object(forKey: "includeLocalZones") as? Bool ?? true
        ignoreSchedule = defaults.object(forKey: "ignoreSchedule") as? Bool ?? false
        refreshDataInfo()
        authorization = location.authorizationStatus

        location.onUpdate = { [weak self] location in
            self?.handle(location)
        }
        location.onAuthorizationChange = { [weak self] status in
            self?.authorization = status
        }
        vehicleDetector.onChange = { [weak self] device in
            self?.apply(device)
        }
        apply(vehicleDetector.current)
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

    // MARK: - Dati

    /// Scarica varchi e zone aggiornati, se ce ne sono.
    func updateData(force: Bool = false) async {
        await ZoneDataUpdater.updateIfNeeded(force: force)
        refreshDataInfo()
    }

    private func refreshDataInfo() {
        gatesCount = gates.count
        zonesCount = localZones.count
        dataUpdatedAt = ZoneDataUpdater.lastUpdate
    }

    // MARK: - Veicolo

    private func apply(_ device: VehicleDetector.Device?) {
        connectedDevice = device
        guard let device, let detected = vehicleDetector.vehicle(for: device) else {
            vehicleIsAutomatic = false
            return
        }
        isApplyingDetection = true
        vehicle = detected
        isApplyingDetection = false
        vehicleIsAutomatic = true
    }

    // MARK: - Logica

    private func handle(_ location: CLLocation) {
        gpsUpdates += 1
        guard mode == .real else { return }

        // Da fermi la direzione GPS non è affidabile.
        let course = location.course >= 0 && location.speed > 1.5 ? location.course : nil
        let position = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let now = Date()

        let rules = self.rules
        let gateMonitor = GateMonitor(gates: gates.filter { rules.applies(to: $0.zone, at: now) })
        let zoneMonitor = ZoneMonitor(zones: localZones.filter { rules.applies(to: $0, at: now) })
        let candidates = [
            gateMonitor.nearestGate(from: position, course: course),
            zoneMonitor.approach(from: position, course: course),
        ].compactMap { $0 }
        present(candidates.min { $0.distance < $1.distance })
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

    private var rules: ZoneRules {
        ZoneRules(
            isMotorcycle: vehicle == .moto,
            includeAreaB: includeAreaB,
            includeLocalZones: includeLocalZones,
            ignoreSchedule: ignoreSchedule
        )
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
            gateName: approach.name,
            zone: approach.zone.label,
            distance: Int((approach.distance / 10).rounded()) * 10,
            vehicle: vehicle.label
        )

        // Avvisa solo quando il livello sale, una volta per varco o zona.
        announced = announced.filter { $0.key == approach.id }
        let previous = announced[approach.id] ?? .clear
        guard status > previous else {
            liveActivity.update(state)
            return
        }
        announced[approach.id] = status

        let subject = approach.zone.hasGates ? "Varco \(approach.zone.label)" : approach.zone.label
        liveActivity.update(state, alert: AlertConfiguration(
            title: "\(subject)",
            body: "\(approach.name) tra \(state.distance) m",
            sound: .default
        ))
        if voiceEnabled {
            speaker.say(spokenMessage(subject: subject, approach: approach, status: status))
        }
    }

    private func spokenMessage(subject: String, approach: Approach, status: State.Status) -> String {
        if status == .imminent {
            return "Attenzione, \(subject) \(approach.name) a \(state.distance) metri."
        }
        let rounded = Int((approach.distance / 50).rounded()) * 50
        return "\(subject) \(approach.name) tra \(rounded) metri."
    }
}
