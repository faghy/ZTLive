import Foundation

public enum Zone: String, Codable, Sendable, CaseIterable {
    case areaC
    case areaB
    case ztl

    public var label: String {
        switch self {
        case .areaC: return "Area C"
        case .areaB: return "Area B"
        case .ztl: return "ZTL"
        }
    }
}

public struct Gate: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let zone: Zone
    public let coordinate: Coordinate

    public init(id: String, name: String, zone: Zone, coordinate: Coordinate) {
        self.id = id
        self.name = name
        self.zone = zone
        self.coordinate = coordinate
    }
}

public enum GateLoaderError: Error {
    case invalidFormat
}

/// Legge i GeoJSON dei varchi pubblicati dal Comune di Milano (dataset ds82 Area C, ds959 Area B).
public enum GateLoader {
    public static func load(geoJSON data: Data, zone: Zone) throws -> [Gate] {
        let collection: FeatureCollection
        do {
            collection = try JSONDecoder().decode(FeatureCollection.self, from: data)
        } catch {
            throw GateLoaderError.invalidFormat
        }

        return collection.features.enumerated().compactMap { index, feature in
            guard feature.geometry?.type == "Point",
                  let point = feature.geometry?.coordinates, point.count >= 2 else { return nil }
            let properties = feature.properties
            // Area B: il dataset include varchi non ancora sanzionanti.
            if let state = properties?.stato, state != "ATTIVI E SANZIONANTI" { return nil }

            let rawName = properties?.label ?? properties?.nome ?? "Varco"
            let id = properties?.idAmat.map(String.init) ?? String(index)
            return Gate(
                id: "\(zone.rawValue)-\(id)",
                name: prettify(rawName),
                zone: zone,
                coordinate: Coordinate(latitude: point[1], longitude: point[0])
            )
        }
    }

    /// "PORTA TENAGLIA" → "Porta Tenaglia", "001 - CORELLI" → "Corelli".
    static func prettify(_ name: String) -> String {
        var trimmed = name.trimmingCharacters(in: .whitespaces)
        if let range = trimmed.range(of: #"^\d+\s*-\s*"#, options: .regularExpression) {
            trimmed.removeSubrange(range)
        }
        return trimmed.capitalized
    }
}

private struct FeatureCollection: Decodable {
    let features: [Feature]
}

private struct Feature: Decodable {
    let geometry: Geometry?
    let properties: Properties?
}

private struct Geometry: Decodable {
    let type: String
    let coordinates: [Double]?

    enum CodingKeys: String, CodingKey {
        case type, coordinates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        // Solo i punti hanno un array piatto; le altre geometrie vengono ignorate.
        coordinates = try? container.decode([Double].self, forKey: .coordinates)
    }
}

private struct Properties: Decodable {
    let idAmat: Int?
    let label: String?
    let nome: String?
    let stato: String?

    enum CodingKeys: String, CodingKey {
        case idAmat = "id_amat"
        case label, nome, stato
    }
}
