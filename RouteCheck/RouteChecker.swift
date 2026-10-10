import Foundation
import MapKit
import ZTLCore

struct RouteOption: Identifiable {
    let id: Int
    let coordinates: [Coordinate]
    let travelTime: TimeInterval
    let distance: CLLocationDistance
}

struct RouteCheckResult {
    let originLabel: String
    let destinationLabel: String
    /// `nil` = posizione attuale.
    let origin: Coordinate?
    let destination: Coordinate
    /// Il primo è il percorso consigliato da Apple Maps, gli altri le alternative.
    let options: [RouteOption]
    let departure: Date
}

enum RouteCheckError: LocalizedError {
    case noLink
    case unsupportedLink
    case notDriving
    case placeNotFound(String)
    case noRoute(String)
    case noLocation(String)

    var errorDescription: String? {
        switch self {
        case .noLink: return "Non ho trovato un link di Google Maps."
        case .unsupportedLink: return "Questo link di Google Maps non contiene un percorso che riesco a leggere."
        case .notDriving: return "Il percorso condiviso non è in auto: imposta il percorso in auto o in moto e condividilo di nuovo."
        case .placeNotFound(let name): return "Non trovo \"\(name)\" sulla mappa."
        case .noRoute(let detail): return "Apple Maps non ha trovato un percorso tra questi punti (\(detail))."
        case .noLocation(let detail): return "Non riesco a leggere la tua posizione (\(detail)). Controlla che ZTLive possa usare la posizione nelle Impostazioni."
        }
    }
}

/// Dal link condiviso da Google Maps ai percorsi in auto calcolati con Apple Maps.
enum RouteChecker {
    /// `log` riceve i passaggi intermedi, mostrati nei dettagli per capire cosa non va.
    static func check(text: String, log: @escaping (String) -> Void = { _ in }) async throws -> RouteCheckResult {
        guard let link = GoogleMapsLink.firstURL(in: text) else { throw RouteCheckError.noLink }
        log("Link: \(link.absoluteString)")
        let resolved = try await resolve(link)
        if resolved != link {
            log("Link completo: \(resolved.absoluteString)")
        }
        guard let route = GoogleMapsLink.parse(resolved) else { throw RouteCheckError.unsupportedLink }
        log("Punti: \(route.points.map(describe).joined(separator: " → "))")
        guard route.isDriving else { throw RouteCheckError.notDriving }

        var items: [MKMapItem] = []
        for point in route.points {
            let item = try await mapItem(for: point)
            let coordinate = String(format: "%.5f, %.5f", item.placemark.coordinate.latitude, item.placemark.coordinate.longitude)
            if point == .currentLocation {
                log("Posizione attuale: \(coordinate)")
            } else {
                log("Trovato: \(item.name ?? "?") (\(coordinate))")
            }
            items.append(item)
        }
        guard let first = items.first, let last = items.last, items.count >= 2 else { throw RouteCheckError.unsupportedLink }

        let options = try await directions(through: items)
        guard let main = options.first, let start = main.coordinates.first, let end = main.coordinates.last else {
            throw RouteCheckError.noRoute("nessun percorso restituito")
        }
        log("Percorsi calcolati: \(options.count)")
        let startsHere = route.points.first == .currentLocation
        return RouteCheckResult(
            originLabel: startsHere ? "Posizione attuale" : label(for: first, point: route.points[0]),
            destinationLabel: label(for: last, point: route.points[route.points.count - 1]),
            origin: startsHere ? nil : start,
            destination: end,
            options: options,
            departure: Date()
        )
    }

    /// Apre i link brevi (maps.app.goo.gl) per ottenere quello completo.
    static func resolve(_ url: URL) async throws -> URL {
        guard GoogleMapsLink.isShortLink(url) else { return url }
        let (data, response) = try await URLSession.shared.data(from: url)
        let final = GoogleMapsLink.unwrapConsent(response.url ?? url)
        if GoogleMapsLink.isShortLink(final),
           let html = String(data: data, encoding: .utf8),
           let embedded = GoogleMapsLink.embeddedMapsURL(in: html) {
            return embedded
        }
        return final
    }

    private static func mapItem(for point: RoutePoint) async throws -> MKMapItem {
        switch point {
        case .currentLocation:
            let location = try await CurrentLocation.fetch()
            return MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        case .coordinate(let coordinate):
            return MKMapItem(placemark: MKPlacemark(coordinate: coordinate.clLocation))
        case .query(let text):
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = text
            request.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 45.4642, longitude: 9.1900),
                latitudinalMeters: 40_000,
                longitudinalMeters: 40_000
            )
            guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else {
                throw RouteCheckError.placeNotFound(text)
            }
            return item
        }
    }

    /// Con solo partenza e arrivo chiede anche le alternative; con tappe intermedie unisce le tratte.
    private static func directions(through items: [MKMapItem]) async throws -> [RouteOption] {
        if items.count == 2 {
            let routes = try await calculate(from: items[0], to: items[1], alternatives: true)
            return routes.enumerated().map { index, route in
                RouteOption(id: index, coordinates: route.polyline.coordinates, travelTime: route.expectedTravelTime, distance: route.distance)
            }
        }

        var coordinates: [Coordinate] = []
        var travelTime: TimeInterval = 0
        var distance: CLLocationDistance = 0
        for (from, to) in zip(items, items.dropFirst()) {
            guard let leg = try await calculate(from: from, to: to, alternatives: false).first else {
                throw RouteCheckError.noRoute("tratta vuota")
            }
            coordinates += leg.polyline.coordinates
            travelTime += leg.expectedTravelTime
            distance += leg.distance
        }
        return [RouteOption(id: 0, coordinates: coordinates, travelTime: travelTime, distance: distance)]
    }

    private static func calculate(from source: MKMapItem, to destination: MKMapItem, alternatives: Bool) async throws -> [MKRoute] {
        let request = MKDirections.Request()
        request.source = source
        request.destination = destination
        request.transportType = .automobile
        request.requestsAlternateRoutes = alternatives
        do {
            return try await MKDirections(request: request).calculate().routes
        } catch {
            throw RouteCheckError.noRoute(error.localizedDescription)
        }
    }

    private static func describe(_ point: RoutePoint) -> String {
        switch point {
        case .currentLocation: return "posizione attuale"
        case .coordinate(let c): return String(format: "%.5f, %.5f", c.latitude, c.longitude)
        case .query(let text): return "\"\(text)\""
        }
    }

    private static func label(for item: MKMapItem, point: RoutePoint) -> String {
        if case .query(let text) = point {
            return item.name ?? text
        }
        if let name = item.name, name != "Unknown Location" {
            return name
        }
        if case .coordinate(let coordinate) = point {
            return String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
        }
        return "Posizione attuale"
    }
}

extension Coordinate {
    var clLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension MKPolyline {
    var coordinates: [Coordinate] {
        var points = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&points, range: NSRange(location: 0, length: pointCount))
        return points.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
    }
}
