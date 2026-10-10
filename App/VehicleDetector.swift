import AVFoundation

/// Riconosce il veicolo dal dispositivo audio collegato (CarPlay dell'auto o della moto, interfono).
/// La prima volta l'utente sceglie il veicolo a mano; l'associazione viene ricordata.
@MainActor
final class VehicleDetector {
    struct Device: Equatable {
        let uid: String
        let name: String
    }

    var onChange: ((Device?) -> Void)?
    private(set) var current: Device?

    private static let externalPorts: Set<AVAudioSession.Port> = [.carAudio, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE]
    private static let associationsKey = "vehicleAssociations"
    private let defaults = UserDefaults.standard
    private var associations: [String: String]

    init() {
        associations = defaults.dictionary(forKey: Self.associationsKey) as? [String: String] ?? [:]
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        refresh()
    }

    func refresh() {
        let output = AVAudioSession.sharedInstance().currentRoute.outputs.first {
            Self.externalPorts.contains($0.portType)
        }
        let device = output.map { Device(uid: $0.uid, name: $0.portName) }
        guard device != current else { return }
        current = device
        onChange?(device)
    }

    func vehicle(for device: Device) -> Vehicle? {
        associations[device.uid].flatMap(Vehicle.init(rawValue:))
    }

    func associate(_ device: Device, with vehicle: Vehicle) {
        associations[device.uid] = vehicle.rawValue
        defaults.set(associations, forKey: Self.associationsKey)
    }
}
