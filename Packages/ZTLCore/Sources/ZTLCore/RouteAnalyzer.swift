import Foundation

/// Zona attraversata da un percorso.
public struct RouteHit: Equatable, Sendable {
    public let zoneID: String
    /// Per Area B e C è il varco più vicino al punto di ingresso.
    public let name: String
    public let zone: Zone
    public let entry: Coordinate
    /// Metri dalla partenza al punto di ingresso.
    public let distanceAlong: Double
    /// Orario stimato di passaggio.
    public let passTime: Date
}

public enum RouteAnalyzer {
    /// Distanza massima tra due punti controllati lungo il percorso.
    static let sampleSpacing = 15.0

    /// Zone attive attraversate dal percorso, in ordine di passaggio. L'orario di passaggio
    /// è stimato distribuendo `travelTime` in proporzione alla distanza percorsa.
    public static func hits(
        route: [Coordinate],
        travelTime: TimeInterval,
        departure: Date,
        zones: [LocalZone],
        gates: [Gate] = [],
        rules: ZoneRules
    ) -> [RouteHit] {
        guard route.count >= 2 else { return [] }
        let samples = densify(route)
        let total = samples.last?.distance ?? 0
        let routeBounds = BoundingBox(route).expanded(by: 50)
        let candidates = zones.filter { routeBounds.intersects($0.bounds) }

        var found: [RouteHit] = []
        var seen = Set<String>()
        for sample in samples {
            let time = departure.addingTimeInterval(total > 0 ? travelTime * sample.distance / total : 0)
            for zone in candidates where !seen.contains(zone.id) {
                guard rules.applies(to: zone, at: time), zone.contains(sample.point) else { continue }
                seen.insert(zone.id)
                found.append(RouteHit(
                    zoneID: zone.id,
                    name: displayName(of: zone, entry: sample.point, gates: gates),
                    zone: zone.zone,
                    entry: sample.point,
                    distanceAlong: sample.distance,
                    passTime: time
                ))
            }
        }
        return found
    }

    /// Fino a `limit` punti del percorso alternativo, scelti dove passa accanto alle zone evitate.
    /// Passati a Google Maps come tappe, lo costringono a seguire l'alternativa.
    public static func detourWaypoints(alternative: [Coordinate], avoiding hits: [RouteHit], limit: Int = 3) -> [Coordinate] {
        guard alternative.count >= 2, limit > 0 else { return [] }
        let samples = densify(alternative)
        let total = samples.last?.distance ?? 0
        // Partenza e arrivo Google li conosce già.
        let inner = samples.filter { $0.distance > total * 0.05 && $0.distance < total * 0.95 }
        guard !inner.isEmpty else { return [] }

        func nearest(to point: Coordinate) -> Sample? {
            inner.min { Geo.distance($0.point, point) < Geo.distance($1.point, point) }
        }
        var chosen = hits.compactMap { nearest(to: $0.entry) }
        if chosen.isEmpty {
            chosen = [0.25, 0.5, 0.75].compactMap { fraction in
                inner.min { abs($0.distance - total * fraction) < abs($1.distance - total * fraction) }
            }
        }

        // In ordine lungo il percorso, scartando i punti a meno di 100 m dal precedente.
        var ordered: [Sample] = []
        for sample in chosen.sorted(by: { $0.distance < $1.distance }) {
            if let last = ordered.last, sample.distance - last.distance < 100 { continue }
            ordered.append(sample)
        }
        if ordered.count > limit {
            // Distribuiti uniformemente, includendo il primo e l'ultimo.
            if limit == 1 {
                ordered = [ordered[ordered.count / 2]]
            } else {
                let step = Double(ordered.count - 1) / Double(limit - 1)
                ordered = (0..<limit).map { ordered[Int((Double($0) * step).rounded())] }
            }
        }
        return ordered.map(\.point)
    }

    static func displayName(of zone: LocalZone, entry: Coordinate, gates: [Gate]) -> String {
        guard zone.zone.hasGates else { return zone.name }
        let nearest = gates
            .filter { $0.zone == zone.zone }
            .min { Geo.distance($0.coordinate, entry) < Geo.distance($1.coordinate, entry) }
        return nearest.map { "varco \($0.name)" } ?? zone.name
    }

    struct Sample {
        let point: Coordinate
        let distance: Double
    }

    /// Punti del percorso a non più di `sampleSpacing` metri l'uno dall'altro.
    static func densify(_ route: [Coordinate]) -> [Sample] {
        guard let first = route.first else { return [] }
        var samples = [Sample(point: first, distance: 0)]
        var travelled = 0.0
        for (a, b) in zip(route, route.dropFirst()) {
            let length = Geo.distance(a, b)
            let steps = max(1, Int((length / sampleSpacing).rounded(.up)))
            for step in 1...steps {
                let t = Double(step) / Double(steps)
                let point = Coordinate(
                    latitude: a.latitude + (b.latitude - a.latitude) * t,
                    longitude: a.longitude + (b.longitude - a.longitude) * t
                )
                samples.append(Sample(point: point, distance: travelled + length * t))
            }
            travelled += length
        }
        return samples
    }
}
