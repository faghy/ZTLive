import Foundation

public enum RoutePoint: Equatable, Sendable {
    case coordinate(Coordinate)
    /// Indirizzo o nome di un luogo, da cercare.
    case query(String)
    case currentLocation
}

/// Percorso ricavato da un link condiviso da Google Maps.
public struct SharedRoute: Equatable, Sendable {
    /// Partenza, eventuali tappe, arrivo.
    public var points: [RoutePoint]
    public var isDriving: Bool

    public init(points: [RoutePoint], isDriving: Bool) {
        self.points = points
        self.isDriving = isDriving
    }
}

public enum GoogleMapsLink {
    /// Primo link presente nel testo condiviso (es. "Indicazioni per ...: https://maps.app.goo.gl/...").
    public static func firstURL(in text: String) -> URL? {
        guard let range = text.range(of: #"https?://[^\s<>"]+"#, options: .regularExpression) else { return nil }
        return URL(string: String(text[range]))
    }

    /// Link brevi da aprire per ottenere quello completo.
    public static func isShortLink(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "maps.app.goo.gl" || host == "goo.gl" || host == "g.co"
    }

    /// Nell'UE Google può rimandare alla pagina dei cookie: il link vero è nel parametro `continue`.
    public static func unwrapConsent(_ url: URL) -> URL {
        guard url.host?.lowercased().hasPrefix("consent.") == true,
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "continue" })?.value,
              let inner = URL(string: value) else { return url }
        return inner
    }

    /// Link a Google Maps contenuto in una pagina HTML (quando il link breve non fa un redirect diretto).
    public static func embeddedMapsURL(in html: String) -> URL? {
        let pattern = #"https://(?:www\.)?google\.[a-z.]+/maps/[^"'\s<>\\]+"#
        guard let range = html.range(of: pattern, options: .regularExpression) else { return nil }
        let link = String(html[range]).replacingOccurrences(of: "&amp;", with: "&")
        return URL(string: link)
    }

    public static func parse(_ url: URL) -> SharedRoute? {
        let url = unwrapConsent(url)
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] where query[item.name] == nil {
            query[item.name] = item.value.map { $0.replacingOccurrences(of: "+", with: " ") }
        }
        let isDriving = drivingMode(query: query, link: url.absoluteString)

        // https://www.google.com/maps/dir/?api=1&origin=...&destination=...&waypoints=a|b
        if let destination = query["destination"] {
            var points = [query["origin"].map(point(from:)) ?? .currentLocation]
            points += (query["waypoints"] ?? "").split(separator: "|").map { point(from: String($0)) }
            points.append(point(from: destination))
            return SharedRoute(points: points, isDriving: isDriving)
        }

        // Vecchio formato: ?saddr=...&daddr=A to:B
        if let destination = query["daddr"] {
            var points = [query["saddr"].map(point(from:)) ?? .currentLocation]
            points += destination.components(separatedBy: " to:").map(point(from:))
            return SharedRoute(points: points, isDriving: isDriving)
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)

        // /maps/dir/<partenza>/<tappe>/<arrivo>/@lat,lng,zoom/data=...
        if let dirIndex = parts.firstIndex(of: "dir") {
            var segments: [String] = []
            for part in parts[(dirIndex + 1)...] {
                if part.hasPrefix("@") || part.hasPrefix("data=") { break }
                segments.append(part.replacingOccurrences(of: "+", with: " "))
            }
            if segments.count > 2, segments.last?.isEmpty == true {
                segments.removeLast()
            }
            guard segments.count >= 2 else { return nil }
            var points = segments.map(point(from:))

            // I luoghi con nome hanno le coordinate nel parametro data, nello stesso ordine.
            let coordinates = dataCoordinates(in: url.absoluteString, pattern: #"!1d(-?\d+(?:\.\d+)?)!2d(-?\d+(?:\.\d+)?)"#, latitudeFirst: false)
            let queryIndices = points.indices.filter { if case .query = points[$0] { return true }; return false }
            if coordinates.count == queryIndices.count {
                for (index, coordinate) in zip(queryIndices, coordinates) {
                    points[index] = .coordinate(coordinate)
                }
            }
            return SharedRoute(points: points, isDriving: isDriving)
        }

        // /maps/place/<nome>/@.../data=...!3d<lat>!4d<lng>: solo destinazione.
        if let placeIndex = parts.firstIndex(of: "place"), placeIndex + 1 < parts.count {
            let name = parts[placeIndex + 1].replacingOccurrences(of: "+", with: " ")
            let coordinate = dataCoordinates(in: url.absoluteString, pattern: #"!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)"#, latitudeFirst: true).last
            return SharedRoute(points: [.currentLocation, coordinate.map(RoutePoint.coordinate) ?? point(from: name)], isDriving: true)
        }

        // ?q=... oppure /maps/search/<testo>
        if let destination = query["q"] ?? query["query"] {
            return SharedRoute(points: [.currentLocation, point(from: destination)], isDriving: true)
        }
        if let searchIndex = parts.firstIndex(of: "search"), searchIndex + 1 < parts.count {
            let text = parts[searchIndex + 1].replacingOccurrences(of: "+", with: " ")
            return SharedRoute(points: [.currentLocation, point(from: text)], isDriving: true)
        }
        return nil
    }

    /// Link di Google Maps con percorso in auto e tappe intermedie. Senza `origin` parte dalla posizione attuale.
    public static func directionsURL(origin: Coordinate?, destination: Coordinate, waypoints: [Coordinate]) -> URL {
        var components = URLComponents(string: "https://www.google.com/maps/dir/")!
        var items = [URLQueryItem(name: "api", value: "1")]
        if let origin {
            items.append(URLQueryItem(name: "origin", value: format(origin)))
        }
        items.append(URLQueryItem(name: "destination", value: format(destination)))
        if !waypoints.isEmpty {
            items.append(URLQueryItem(name: "waypoints", value: waypoints.map(format).joined(separator: "|")))
        }
        items.append(URLQueryItem(name: "travelmode", value: "driving"))
        components.queryItems = items
        return components.url!
    }

    /// Lo stesso link, da aprire direttamente nell'app Google Maps.
    public static func appURL(for url: URL) -> URL? {
        guard url.scheme == "https" else { return nil }
        return URL(string: "comgooglemapsurl" + url.absoluteString.dropFirst("https".count))
    }

    static func format(_ coordinate: Coordinate) -> String {
        String(format: "%.6f,%.6f", coordinate.latitude, coordinate.longitude)
    }

    static func point(from text: String) -> RoutePoint {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || currentLocationNames.contains(trimmed.lowercased()) {
            return .currentLocation
        }
        let pattern = #"^(-?\d{1,2}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)$"#
        if trimmed.range(of: pattern, options: .regularExpression) != nil {
            let values = trimmed.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if values.count == 2 {
                return .coordinate(Coordinate(latitude: values[0], longitude: values[1]))
            }
        }
        return .query(trimmed)
    }

    private static let currentLocationNames: Set<String> = [
        "my location", "current location", "la mia posizione", "posizione attuale", "la tua posizione", "your location",
    ]

    static func dataCoordinates(in link: String, pattern: String, latitudeFirst: Bool) -> [Coordinate] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(link.startIndex..., in: link)
        return regex.matches(in: link, range: range).compactMap { match in
            guard let first = Range(match.range(at: 1), in: link).flatMap({ Double(link[$0]) }),
                  let second = Range(match.range(at: 2), in: link).flatMap({ Double(link[$0]) }) else { return nil }
            return latitudeFirst
                ? Coordinate(latitude: first, longitude: second)
                : Coordinate(latitude: second, longitude: first)
        }
    }

    /// `travelmode`, `dirflg` o `!3e<n>` nel parametro data (0 = auto).
    static func drivingMode(query: [String: String], link: String) -> Bool {
        if let mode = query["travelmode"] {
            return mode == "driving"
        }
        if let flag = query["dirflg"] {
            return !["w", "r", "b"].contains(flag)
        }
        if let range = link.range(of: #"!3e\d"#, options: .regularExpression) {
            return link[range].last == "0"
        }
        return true
    }
}
