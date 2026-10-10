import Foundation
import ZTLCore

enum Vehicle: String, CaseIterable, Identifiable {
    case auto
    case moto

    var id: String { rawValue }
    var label: String { self == .auto ? "Auto" : "Moto" }
}

/// Varchi e zone inclusi nell'app, caricati una sola volta.
enum ZoneData {
    static let gates: [Gate] = {
        let files: [(String, Zone)] = [("areac_varchi", .areaC), ("areab_varchi", .areaB)]
        return files.flatMap { name, zone -> [Gate] in
            guard let data = resource(name, "geojson"),
                  let gates = try? GateLoader.load(geoJSON: data, zone: zone) else { return [] }
            return gates
        }
    }()

    /// ZTL, aree pedonali e perimetri di Area B e C.
    static let zones: [LocalZone] = {
        guard let data = resource("zone_locali", "json"),
              let zones = try? LocalZoneLoader.load(json: data) else { return [] }
        return zones
    }()

    private static func resource(_ name: String, _ ext: String) -> Data? {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            print("Risorsa \(name).\(ext) mancante")
            return nil
        }
        return try? Data(contentsOf: url)
    }
}
