import Foundation
import ZTLCore

enum Vehicle: String, CaseIterable, Identifiable {
    case auto
    case moto

    var id: String { rawValue }
    var label: String { self == .auto ? "Auto" : "Moto" }
}

/// Varchi e zone in uso: quelli scaricati da ZoneDataUpdater se ci sono, altrimenti quelli inclusi nell'app.
@MainActor
enum ZoneData {
    private(set) static var gates: [Gate] = loadGates()
    /// ZTL, aree pedonali e perimetri di Area B e C.
    private(set) static var zones: [LocalZone] = loadZones()

    /// Rilegge i file dopo un aggiornamento.
    static func reload() {
        gates = loadGates()
        zones = loadZones()
    }

    static let gateFiles: [(name: String, zone: Zone)] = [("areac_varchi.geojson", .areaC), ("areab_varchi.geojson", .areaB)]
    static let zonesFile = "zone_locali.json"

    private static func loadGates() -> [Gate] {
        gateFiles.flatMap { file -> [Gate] in
            data(file.name, parse: { try GateLoader.load(geoJSON: $0, zone: file.zone) }) ?? []
        }
    }

    private static func loadZones() -> [LocalZone] {
        data(zonesFile, parse: LocalZoneLoader.load(json:)) ?? []
    }

    /// Prova prima il file scaricato e, se manca o non si legge, quello incluso nell'app.
    private static func data<T>(_ file: String, parse: (Data) throws -> [T]) -> [T]? {
        let bundled = Bundle.main.url(forResource: file, withExtension: nil)
        for url in [ZoneDataUpdater.cachedURL(for: file), bundled].compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url), let items = try? parse(data), !items.isEmpty {
                return items
            }
        }
        print("Dati \(file) mancanti")
        return nil
    }
}
