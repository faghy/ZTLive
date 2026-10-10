import Foundation

public struct Coordinate: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum Geo {
    static let earthRadius = 6_371_000.0

    /// Distanza in metri tra due coordinate (formula dell'emisenoverso).
    public static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = radians(a.latitude)
        let lat2 = radians(b.latitude)
        let dLat = lat2 - lat1
        let dLon = radians(b.longitude - a.longitude)
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// Direzione iniziale da `a` verso `b`, in gradi (0 = nord, senso orario).
    public static func bearing(from a: Coordinate, to b: Coordinate) -> Double {
        let lat1 = radians(a.latitude)
        let lat2 = radians(b.latitude)
        let dLon = radians(b.longitude - a.longitude)
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Punto raggiunto partendo da `start` e percorrendo `distance` metri in direzione `bearing`.
    public static func destination(from start: Coordinate, bearing: Double, distance: Double) -> Coordinate {
        let lat1 = radians(start.latitude)
        let lon1 = radians(start.longitude)
        let angle = radians(bearing)
        let delta = distance / earthRadius
        let lat2 = asin(sin(lat1) * cos(delta) + cos(lat1) * sin(delta) * cos(angle))
        let lon2 = lon1 + atan2(sin(angle) * sin(delta) * cos(lat1), cos(delta) - sin(lat1) * sin(lat2))
        return Coordinate(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    /// Differenza minima tra due direzioni, in gradi (0...180).
    public static func angleDifference(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }
}
