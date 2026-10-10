import Foundation

/// Fascia oraria settimanale. Inizia nei `days` (1 = lunedì ... 7 = domenica) ai minuti `from`;
/// se `to` <= `from` prosegue fino ai minuti `to` del giorno dopo.
public struct WeeklyWindow: Codable, Equatable, Sendable {
    public let days: [Int]
    public let from: Int
    public let to: Int

    public init(days: [Int], from: Int, to: Int) {
        self.days = days
        self.from = from
        self.to = to
    }
}

/// Zona delimitata da un poligono (dataset ds51 del Comune di Milano): ZTL, area pedonale,
/// o il perimetro di Area B / Area C usato per controllare i percorsi.
public struct LocalZone: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let zone: Zone
    /// Le deroghe consentono l'accesso alle moto.
    public let motoAllowed: Bool
    /// `nil` = sempre attiva.
    public let schedule: [WeeklyWindow]?
    let rings: [[Coordinate]]
    let bounds: BoundingBox

    public init(id: String, name: String, zone: Zone, motoAllowed: Bool, schedule: [WeeklyWindow]?, rings: [[Coordinate]]) {
        self.id = id
        self.name = name
        self.zone = zone
        self.motoAllowed = motoAllowed
        self.schedule = schedule
        self.rings = rings
        bounds = BoundingBox(rings.flatMap { $0 })
    }

    public func isActive(at date: Date) -> Bool {
        guard let schedule else { return true }
        return ZoneSchedule.isWithin(schedule, at: date)
    }

    /// Regola pari-dispari su tutti gli anelli: gestisce poligoni multipli e buchi.
    public func contains(_ point: Coordinate) -> Bool {
        guard bounds.contains(point) else { return false }
        var inside = false
        for ring in rings where Self.ring(ring, contains: point) {
            inside.toggle()
        }
        return inside
    }

    func isNear(_ point: Coordinate, within meters: Double) -> Bool {
        bounds.expanded(by: meters).contains(point)
    }

    static func ring(_ ring: [Coordinate], contains point: Coordinate) -> Bool {
        guard ring.count >= 3 else { return false }
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let a = ring[i]
            let b = ring[j]
            if (a.latitude > point.latitude) != (b.latitude > point.latitude) {
                let crossing = (b.longitude - a.longitude) * (point.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude
                if point.longitude < crossing {
                    inside.toggle()
                }
            }
            j = i
        }
        return inside
    }
}

struct BoundingBox: Sendable {
    var minLatitude: Double
    var maxLatitude: Double
    var minLongitude: Double
    var maxLongitude: Double

    init(_ points: [Coordinate]) {
        minLatitude = points.map(\.latitude).min() ?? 0
        maxLatitude = points.map(\.latitude).max() ?? 0
        minLongitude = points.map(\.longitude).min() ?? 0
        maxLongitude = points.map(\.longitude).max() ?? 0
    }

    func contains(_ point: Coordinate) -> Bool {
        (minLatitude...maxLatitude).contains(point.latitude) && (minLongitude...maxLongitude).contains(point.longitude)
    }

    func intersects(_ other: BoundingBox) -> Bool {
        minLatitude <= other.maxLatitude && maxLatitude >= other.minLatitude
            && minLongitude <= other.maxLongitude && maxLongitude >= other.minLongitude
    }

    func expanded(by meters: Double) -> BoundingBox {
        let dLat = meters / 111_195
        let dLon = meters / (111_195 * cos(minLatitude * .pi / 180))
        var box = self
        box.minLatitude -= dLat
        box.maxLatitude += dLat
        box.minLongitude -= dLon
        box.maxLongitude += dLon
        return box
    }
}

/// Legge Resources/zone_locali.json, generato da tools/build_zone_data.py.
public enum LocalZoneLoader {
    public static func load(json data: Data) throws -> [LocalZone] {
        let raw: [RawZone]
        do {
            raw = try JSONDecoder().decode([RawZone].self, from: data)
        } catch {
            throw GateLoaderError.invalidFormat
        }
        return raw.compactMap { zone in
            let kind: Zone
            switch zone.kind {
            case "ztl": kind = .ztl
            case "pedestrian": kind = .pedestrian
            case "areaC": kind = .areaC
            case "areaB": kind = .areaB
            default: return nil
            }
            let rings = zone.rings.map { ring in
                ring.compactMap { pair in
                    pair.count >= 2 ? Coordinate(latitude: pair[0], longitude: pair[1]) : nil
                }
            }
            return LocalZone(
                id: "\(zone.kind)-\(zone.id)",
                name: zone.name,
                zone: kind,
                motoAllowed: zone.motoAllowed,
                schedule: zone.schedule,
                rings: rings
            )
        }
    }
}

private struct RawZone: Decodable {
    let id: Int
    let name: String
    let kind: String
    let motoAllowed: Bool
    let schedule: [WeeklyWindow]?
    let rings: [[[Double]]]
}

/// Avvisa quando la direzione di marcia porta dentro una zona.
public struct ZoneMonitor: Sendable {
    public var zones: [LocalZone]
    /// Distanza massima controllata lungo la direzione di marcia.
    public var lookahead: Double
    /// Passo dei punti controllati lungo la direzione di marcia.
    public var step: Double

    public init(zones: [LocalZone], lookahead: Double = 300, step: Double = 20) {
        self.zones = zones
        self.lookahead = lookahead
        self.step = step
    }

    /// Senza direzione di marcia non avvisa: da fermi non si sa dove si andrà.
    /// Le zone in cui ci si trova già vengono ignorate.
    public func approach(from position: Coordinate, course: Double?) -> Approach? {
        guard let course else { return nil }
        let candidates = zones.filter { $0.isNear(position, within: lookahead) && !$0.contains(position) }
        guard !candidates.isEmpty else { return nil }

        var distance = step
        while distance <= lookahead {
            let point = Geo.destination(from: position, bearing: course, distance: distance)
            if let zone = candidates.first(where: { $0.contains(point) }) {
                return Approach(id: zone.id, name: zone.name, zone: zone.zone, distance: distance, isAhead: true)
            }
            distance += step
        }
        return nil
    }
}
