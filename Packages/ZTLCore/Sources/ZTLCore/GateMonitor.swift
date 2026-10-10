import Foundation

/// Varco o zona verso cui ci si sta dirigendo.
public struct Approach: Equatable, Sendable {
    public let id: String
    public let name: String
    public let zone: Zone
    /// Distanza in metri.
    public let distance: Double
    /// `true` se è nella direzione di marcia.
    public let isAhead: Bool

    public init(id: String, name: String, zone: Zone, distance: Double, isAhead: Bool) {
        self.id = id
        self.name = name
        self.zone = zone
        self.distance = distance
        self.isAhead = isAhead
    }

    public init(gate: Gate, distance: Double, isAhead: Bool) {
        self.init(id: gate.id, name: gate.name, zone: gate.zone, distance: distance, isAhead: isAhead)
    }
}

/// Trova il varco verso cui ci si sta dirigendo.
public struct GateMonitor: Sendable {
    public var gates: [Gate]
    /// Oltre questa distanza i varchi vengono ignorati.
    public var radius: Double
    /// Scarto massimo tra direzione di marcia e direzione del varco.
    public var headingTolerance: Double

    /// Sotto questa distanza il varco è "sopra di noi" e la direzione non è più affidabile.
    static let closeRange = 30.0

    public init(gates: [Gate], radius: Double = 400, headingTolerance: Double = 50) {
        self.gates = gates
        self.radius = radius
        self.headingTolerance = headingTolerance
    }

    /// Varco più vicino entro `radius`. Con una direzione di marcia valida considera solo i varchi davanti.
    public func nearestGate(from position: Coordinate, course: Double?) -> Approach? {
        var best: Approach?
        for gate in gates {
            let distance = Geo.distance(position, gate.coordinate)
            guard distance <= radius else { continue }

            var isAhead = false
            if let course {
                let bearing = Geo.bearing(from: position, to: gate.coordinate)
                isAhead = distance < Self.closeRange || Geo.angleDifference(course, bearing) <= headingTolerance
                guard isAhead else { continue }
            }

            if best == nil || distance < best!.distance {
                best = Approach(gate: gate, distance: distance, isAhead: isAhead)
            }
        }
        return best
    }
}
