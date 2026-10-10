import XCTest
@testable import ZTLCore

final class GeoTests: XCTestCase {
    let duomo = Coordinate(latitude: 45.4642, longitude: 9.1900)

    func testDistanceOfOneThousandthDegreeLatitude() {
        let north = Coordinate(latitude: duomo.latitude + 0.001, longitude: duomo.longitude)
        XCTAssertEqual(Geo.distance(duomo, north), 111.2, accuracy: 0.5)
    }

    func testBearingCardinalDirections() {
        let north = Coordinate(latitude: duomo.latitude + 0.01, longitude: duomo.longitude)
        let east = Coordinate(latitude: duomo.latitude, longitude: duomo.longitude + 0.01)
        XCTAssertEqual(Geo.bearing(from: duomo, to: north), 0, accuracy: 0.1)
        XCTAssertEqual(Geo.bearing(from: duomo, to: east), 90, accuracy: 0.1)
    }

    func testAngleDifferenceWrapsAround() {
        XCTAssertEqual(Geo.angleDifference(350, 10), 20, accuracy: 0.001)
        XCTAssertEqual(Geo.angleDifference(90, 270), 180, accuracy: 0.001)
    }
}

final class GateMonitorTests: XCTestCase {
    let start = Coordinate(latitude: 45.4642, longitude: 9.1900)
    lazy var gateNorth = Gate(
        id: "areaC-1",
        name: "Nord",
        zone: .areaC,
        coordinate: Coordinate(latitude: start.latitude + 0.0018, longitude: start.longitude)
    )

    func testGateAheadIsReported() throws {
        let monitor = GateMonitor(gates: [gateNorth])
        let approach = try XCTUnwrap(monitor.nearestGate(from: start, course: 5))
        XCTAssertEqual(approach.id, gateNorth.id)
        XCTAssertEqual(approach.distance, 200, accuracy: 2)
        XCTAssertTrue(approach.isAhead)
    }

    func testGateBehindIsIgnored() {
        let monitor = GateMonitor(gates: [gateNorth])
        XCTAssertNil(monitor.nearestGate(from: start, course: 180))
    }

    func testWithoutCourseNearestGateIsReported() throws {
        let monitor = GateMonitor(gates: [gateNorth])
        let approach = try XCTUnwrap(monitor.nearestGate(from: start, course: nil))
        XCTAssertFalse(approach.isAhead)
    }

    func testGateOutsideRadiusIsIgnored() {
        let monitor = GateMonitor(gates: [gateNorth], radius: 150)
        XCTAssertNil(monitor.nearestGate(from: start, course: 0))
    }
}

final class GateLoaderTests: XCTestCase {
    func testLoadsOnlyActivePointGates() throws {
        let json = """
        {"type":"FeatureCollection","features":[
          {"type":"Feature","properties":{"id_amat":1,"nome":"001 - CORELLI","stato":"ATTIVI E SANZIONANTI"},
           "geometry":{"type":"Point","coordinates":[9.2614,45.4714]}},
          {"type":"Feature","properties":{"id_amat":2,"nome":"002 - ALTRO","stato":"IN PRE-ESERCIZIO"},
           "geometry":{"type":"Point","coordinates":[9.25,45.47]}},
          {"type":"Feature","properties":{"id_amat":3,"label":"PORTA TENAGLIA"},
           "geometry":{"type":"Polygon","coordinates":[[[9.1,45.4],[9.2,45.4],[9.2,45.5],[9.1,45.4]]]}}
        ]}
        """
        let gates = try GateLoader.load(geoJSON: Data(json.utf8), zone: .areaB)
        XCTAssertEqual(gates.count, 1)
        XCTAssertEqual(gates[0].id, "areaB-1")
        XCTAssertEqual(gates[0].name, "Corelli")
        XCTAssertEqual(gates[0].coordinate.latitude, 45.4714, accuracy: 0.0001)
    }

    func testPrettify() {
        XCTAssertEqual(GateLoader.prettify("PORTA TENAGLIA"), "Porta Tenaglia")
        XCTAssertEqual(GateLoader.prettify("012 - VIALE MONZA"), "Viale Monza")
    }
}

final class ZoneScheduleTests: XCTestCase {
    func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    func testWeekdayDaytimeIsActive() {
        XCTAssertTrue(ZoneSchedule.isAreaActive(at: date("2026-10-12T07:30:00+02:00")))
        XCTAssertTrue(ZoneSchedule.isAreaActive(at: date("2026-10-12T19:29:00+02:00")))
    }

    func testEveningAndWeekendAreInactive() {
        XCTAssertFalse(ZoneSchedule.isAreaActive(at: date("2026-10-12T19:30:00+02:00")))
        XCTAssertFalse(ZoneSchedule.isAreaActive(at: date("2026-10-12T07:29:00+02:00")))
        XCTAssertFalse(ZoneSchedule.isAreaActive(at: date("2026-10-10T10:00:00+02:00")))
    }
}

final class LocalZoneTests: XCTestCase {
    let start = Coordinate(latitude: 45.4642, longitude: 9.1900)

    /// Quadrato di circa 100 m il cui lato sud è 200 m a nord di `start`.
    func squareNorth(schedule: [WeeklyWindow]? = nil) -> LocalZone {
        let south = start.latitude + 0.0018
        let north = south + 0.0009
        let west = start.longitude - 0.0006
        let east = start.longitude + 0.0006
        let ring = [
            Coordinate(latitude: south, longitude: west),
            Coordinate(latitude: south, longitude: east),
            Coordinate(latitude: north, longitude: east),
            Coordinate(latitude: north, longitude: west),
            Coordinate(latitude: south, longitude: west),
        ]
        return LocalZone(id: "ztl-1", name: "Prova", zone: .ztl, motoAllowed: false, schedule: schedule, rings: [ring])
    }

    func testContains() {
        let zone = squareNorth()
        XCTAssertTrue(zone.contains(Coordinate(latitude: start.latitude + 0.0022, longitude: start.longitude)))
        XCTAssertFalse(zone.contains(start))
    }

    func testDestinationNorth() {
        let point = Geo.destination(from: start, bearing: 0, distance: 111.2)
        XCTAssertEqual(point.latitude, start.latitude + 0.001, accuracy: 0.00001)
        XCTAssertEqual(point.longitude, start.longitude, accuracy: 0.00001)
    }

    func testHeadingIntoZoneIsReported() throws {
        let monitor = ZoneMonitor(zones: [squareNorth()])
        let approach = try XCTUnwrap(monitor.approach(from: start, course: 0))
        XCTAssertEqual(approach.id, "ztl-1")
        XCTAssertEqual(approach.distance, 220, accuracy: 0.1)
    }

    func testHeadingAwayOrStoppedIsIgnored() {
        let monitor = ZoneMonitor(zones: [squareNorth()])
        XCTAssertNil(monitor.approach(from: start, course: 180))
        XCTAssertNil(monitor.approach(from: start, course: nil))
    }

    func testAlreadyInsideIsIgnored() {
        let monitor = ZoneMonitor(zones: [squareNorth()])
        let inside = Coordinate(latitude: start.latitude + 0.0020, longitude: start.longitude)
        XCTAssertNil(monitor.approach(from: inside, course: 0))
    }

    func testLoader() throws {
        let json = """
        [{"id":7,"name":"Ticinese","kind":"ztl","motoAllowed":true,"schedule":[{"days":[1,2,3,4,5,6,7],"from":1200,"to":420}],
          "rings":[[[45.0,9.0],[45.0,9.1],[45.1,9.1],[45.0,9.0]]]},
         {"id":8,"name":"Altro","kind":"sconosciuto","motoAllowed":false,"schedule":null,"rings":[]}]
        """
        let zones = try LocalZoneLoader.load(json: Data(json.utf8))
        XCTAssertEqual(zones.count, 1)
        XCTAssertEqual(zones[0].id, "ztl-7")
        XCTAssertTrue(zones[0].motoAllowed)
        XCTAssertEqual(zones[0].schedule?.first?.from, 1200)
    }
}

final class WeeklyScheduleTests: XCTestCase {
    func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    func testOvernightWindow() {
        // Navigli notturna: tutti i giorni 20:00-7:00.
        let navigli = [WeeklyWindow(days: [1, 2, 3, 4, 5, 6, 7], from: 1200, to: 420)]
        XCTAssertTrue(ZoneSchedule.isWithin(navigli, at: date("2026-10-10T23:00:00+02:00")))
        XCTAssertTrue(ZoneSchedule.isWithin(navigli, at: date("2026-10-11T06:59:00+02:00")))
        XCTAssertFalse(ZoneSchedule.isWithin(navigli, at: date("2026-10-11T12:00:00+02:00")))
    }

    func testAscanioSforzaWeekend() {
        let ascanio = [
            WeeklyWindow(days: [1, 2, 3, 4], from: 1140, to: 360),
            WeeklyWindow(days: [5], from: 1140, to: 1440),
            WeeklyWindow(days: [6, 7], from: 0, to: 1440),
            WeeklyWindow(days: [1], from: 0, to: 360),
        ]
        XCTAssertTrue(ZoneSchedule.isWithin(ascanio, at: date("2026-10-09T20:00:00+02:00")))  // venerdì sera
        XCTAssertTrue(ZoneSchedule.isWithin(ascanio, at: date("2026-10-10T12:00:00+02:00")))  // sabato
        XCTAssertTrue(ZoneSchedule.isWithin(ascanio, at: date("2026-10-12T05:00:00+02:00")))  // lunedì all'alba
        XCTAssertTrue(ZoneSchedule.isWithin(ascanio, at: date("2026-10-13T03:00:00+02:00")))  // notte lun-mar
        XCTAssertFalse(ZoneSchedule.isWithin(ascanio, at: date("2026-10-12T12:00:00+02:00"))) // lunedì giorno
        XCTAssertFalse(ZoneSchedule.isWithin(ascanio, at: date("2026-10-09T12:00:00+02:00"))) // venerdì giorno
    }

    func testHolidays() {
        XCTAssertTrue(ZoneSchedule.isHoliday(date("2026-12-07T10:00:00+01:00")))  // Sant'Ambrogio
        XCTAssertTrue(ZoneSchedule.isHoliday(date("2026-12-25T10:00:00+01:00")))
        XCTAssertTrue(ZoneSchedule.isHoliday(date("2027-03-29T10:00:00+02:00")))  // Pasquetta 2027
        XCTAssertFalse(ZoneSchedule.isHoliday(date("2026-10-12T10:00:00+02:00")))
    }

    func testAreaInactiveOnWeekdayHoliday() {
        // 8 dicembre 2026 è un martedì.
        XCTAssertFalse(ZoneSchedule.isAreaActive(at: date("2026-12-08T10:00:00+01:00")))
        XCTAssertTrue(ZoneSchedule.isAreaActive(at: date("2026-12-09T10:00:00+01:00")))
    }
}

final class ZoneRulesTests: XCTestCase {
    let mondayMorning = ISO8601DateFormatter().date(from: "2026-10-12T09:00:00+02:00")!
    let ring = [
        Coordinate(latitude: 45.0, longitude: 9.0), Coordinate(latitude: 45.0, longitude: 9.1),
        Coordinate(latitude: 45.1, longitude: 9.1), Coordinate(latitude: 45.0, longitude: 9.0),
    ]

    func testMotorcycleSkipsAreaCAndAllowedZones() {
        let moto = ZoneRules(isMotorcycle: true)
        let car = ZoneRules()
        XCTAssertFalse(moto.applies(to: .areaC, at: mondayMorning))
        XCTAssertTrue(car.applies(to: .areaC, at: mondayMorning))

        let ticinese = LocalZone(id: "ztl-194", name: "Ticinese", zone: .ztl, motoAllowed: true, schedule: nil, rings: [ring])
        XCTAssertFalse(moto.applies(to: ticinese, at: mondayMorning))
        XCTAssertTrue(car.applies(to: ticinese, at: mondayMorning))
    }

    func testAreaBOnlyWhenEnabled() {
        XCTAssertFalse(ZoneRules().applies(to: .areaB, at: mondayMorning))
        XCTAssertTrue(ZoneRules(includeAreaB: true).applies(to: .areaB, at: mondayMorning))
    }

    func testAreaCPolygonFollowsAreaSchedule() {
        let areaC = LocalZone(id: "areaC-276", name: "Area C", zone: .areaC, motoAllowed: false, schedule: nil, rings: [ring])
        let sunday = ISO8601DateFormatter().date(from: "2026-10-11T09:00:00+02:00")!
        XCTAssertTrue(ZoneRules().applies(to: areaC, at: mondayMorning))
        XCTAssertFalse(ZoneRules().applies(to: areaC, at: sunday))
    }
}

final class RouteAnalyzerTests: XCTestCase {
    let start = Coordinate(latitude: 45.4642, longitude: 9.1900)
    let departure = ISO8601DateFormatter().date(from: "2026-10-12T09:00:00+02:00")!

    /// Quadrato di circa 100 m centrato 500 m a nord di `start`.
    func zone(_ kind: Zone = .ztl, id: String = "ztl-1") -> LocalZone {
        let center = start.latitude + 0.0045
        let ring = [
            Coordinate(latitude: center - 0.00045, longitude: start.longitude - 0.0006),
            Coordinate(latitude: center - 0.00045, longitude: start.longitude + 0.0006),
            Coordinate(latitude: center + 0.00045, longitude: start.longitude + 0.0006),
            Coordinate(latitude: center + 0.00045, longitude: start.longitude - 0.0006),
            Coordinate(latitude: center - 0.00045, longitude: start.longitude - 0.0006),
        ]
        return LocalZone(id: id, name: "Prova", zone: kind, motoAllowed: false, schedule: nil, rings: [ring])
    }

    /// Percorso dritto verso nord per 1 km.
    var straightRoute: [Coordinate] {
        [start, Coordinate(latitude: start.latitude + 0.009, longitude: start.longitude)]
    }

    func testRouteThroughZoneIsReportedWithPassTime() throws {
        let hits = RouteAnalyzer.hits(route: straightRoute, travelTime: 200, departure: departure, zones: [zone()], rules: ZoneRules())
        let hit = try XCTUnwrap(hits.first)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hit.zoneID, "ztl-1")
        XCTAssertEqual(hit.distanceAlong, 450, accuracy: 20)
        // Circa metà del percorso: ~90 secondi dopo la partenza.
        XCTAssertEqual(hit.passTime.timeIntervalSince(departure), 90, accuracy: 5)
    }

    func testRouteAroundZoneIsClean() {
        let east = start.longitude + 0.003
        let route = [start, Coordinate(latitude: start.latitude, longitude: east), Coordinate(latitude: start.latitude + 0.009, longitude: east)]
        XCTAssertTrue(RouteAnalyzer.hits(route: route, travelTime: 200, departure: departure, zones: [zone()], rules: ZoneRules()).isEmpty)
    }

    func testAreaCHitIsNamedAfterNearestGate() throws {
        let gates = [
            Gate(id: "areaC-1", name: "Porta Lontana", zone: .areaC, coordinate: Coordinate(latitude: start.latitude + 0.02, longitude: start.longitude)),
            Gate(id: "areaC-2", name: "Porta Vicina", zone: .areaC, coordinate: Coordinate(latitude: start.latitude + 0.0041, longitude: start.longitude)),
        ]
        let hits = RouteAnalyzer.hits(route: straightRoute, travelTime: 200, departure: departure, zones: [zone(.areaC, id: "areaC-276")], gates: gates, rules: ZoneRules())
        XCTAssertEqual(try XCTUnwrap(hits.first).name, "varco Porta Vicina")
    }

    func testDetourWaypointsFollowAlternativeNearTheZone() throws {
        let hit = try XCTUnwrap(RouteAnalyzer.hits(route: straightRoute, travelTime: 200, departure: departure, zones: [zone()], rules: ZoneRules()).first)
        let east = start.longitude + 0.003
        let alternative = [start, Coordinate(latitude: start.latitude, longitude: east), Coordinate(latitude: start.latitude + 0.009, longitude: east), Coordinate(latitude: start.latitude + 0.009, longitude: start.longitude)]
        let waypoints = RouteAnalyzer.detourWaypoints(alternative: alternative, avoiding: [hit])
        XCTAssertEqual(waypoints.count, 1)
        // Il punto scelto sta sulla strada parallela, all'altezza della zona.
        XCTAssertEqual(waypoints[0].longitude, east, accuracy: 0.0001)
        XCTAssertEqual(waypoints[0].latitude, hit.entry.latitude, accuracy: 0.0003)
    }

    func testDetourWaypointsAreLimited() {
        let route = (0...40).map { Coordinate(latitude: start.latitude + Double($0) * 0.001, longitude: start.longitude) }
        let hits = (1...6).map { index in
            RouteHit(zoneID: "z\(index)", name: "", zone: .ztl, entry: route[index * 6], distanceAlong: 0, passTime: departure)
        }
        XCTAssertEqual(RouteAnalyzer.detourWaypoints(alternative: route, avoiding: hits, limit: 3).count, 3)
    }
}

final class GoogleMapsLinkTests: XCTestCase {
    func url(_ string: String) -> URL { URL(string: string)! }

    func testFirstURLInSharedText() {
        let text = "Indicazioni per Piazza Gae Aulenti: https://maps.app.goo.gl/AbC123xyz?g_st=ic"
        XCTAssertEqual(GoogleMapsLink.firstURL(in: text)?.absoluteString, "https://maps.app.goo.gl/AbC123xyz?g_st=ic")
        XCTAssertTrue(GoogleMapsLink.isShortLink(GoogleMapsLink.firstURL(in: text)!))
    }

    func testDirectionsPathWithPlaceCoordinatesInData() throws {
        let link = url("https://www.google.com/maps/dir/Duomo+di+Milano/Piazza+Gae+Aulenti,+Milano/@45.47,9.18,14z/data=!3m1!4b1!4m14!4m13!1m5!1m1!1s0x4786c6aec34636a1:0xab7f4e27101a2e13!2m2!1d9.1916!2d45.4641!1m5!1m1!1s0x4786c6c5e6c4c7d5:0x2!2m2!1d9.1895!2d45.4840!3e0")
        let route = try XCTUnwrap(GoogleMapsLink.parse(link))
        XCTAssertTrue(route.isDriving)
        XCTAssertEqual(route.points, [
            .coordinate(Coordinate(latitude: 45.4641, longitude: 9.1916)),
            .coordinate(Coordinate(latitude: 45.4840, longitude: 9.1895)),
        ])
    }

    func testDirectionsPathFromCurrentLocation() throws {
        let link = url("https://www.google.com/maps/dir//45.4840,9.1895/@45.47,9.18,14z/data=!4m2!4m1!3e0")
        let route = try XCTUnwrap(GoogleMapsLink.parse(link))
        XCTAssertEqual(route.points, [.currentLocation, .coordinate(Coordinate(latitude: 45.484, longitude: 9.1895))])
    }

    func testWalkingRouteIsDetected() throws {
        let link = url("https://www.google.com/maps/dir/45.46,9.19/45.48,9.18/data=!4m2!4m1!3e2")
        XCTAssertFalse(try XCTUnwrap(GoogleMapsLink.parse(link)).isDriving)
    }

    func testApiLinkWithWaypoints() throws {
        let link = url("https://www.google.com/maps/dir/?api=1&origin=Duomo+Milano&destination=45.48,9.18&waypoints=45.47,9.17%7CCorso+Como&travelmode=driving")
        let route = try XCTUnwrap(GoogleMapsLink.parse(link))
        XCTAssertEqual(route.points, [
            .query("Duomo Milano"),
            .coordinate(Coordinate(latitude: 45.47, longitude: 9.17)),
            .query("Corso Como"),
            .coordinate(Coordinate(latitude: 45.48, longitude: 9.18)),
        ])
    }

    func testLegacySaddrDaddr() throws {
        let route = try XCTUnwrap(GoogleMapsLink.parse(url("https://maps.google.com/maps?saddr=My+Location&daddr=Via+Torino,+Milano")))
        XCTAssertEqual(route.points, [.currentLocation, .query("Via Torino, Milano")])
    }

    func testPlaceLink() throws {
        let link = url("https://www.google.com/maps/place/Arco+della+Pace/@45.4757,9.1724,17z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d45.4757!4d9.1724")
        XCTAssertEqual(try XCTUnwrap(GoogleMapsLink.parse(link)).points, [.currentLocation, .coordinate(Coordinate(latitude: 45.4757, longitude: 9.1724))])
    }

    func testConsentPageIsUnwrapped() throws {
        let inner = "https://www.google.com/maps/dir//45.484,9.1895/"
        let consent = url("https://consent.google.com/m?continue=" + inner.addingPercentEncoding(withAllowedCharacters: .alphanumerics)! + "&gl=IT")
        XCTAssertEqual(GoogleMapsLink.unwrapConsent(consent).absoluteString, inner)
        XCTAssertEqual(try XCTUnwrap(GoogleMapsLink.parse(consent)).points.count, 2)
    }

    func testEmbeddedMapsURL() {
        let html = #"<a href="https://www.google.com/maps/dir/A/B/@45,9,12z?entry=ttu&amp;g_ep=x">"#
        XCTAssertEqual(GoogleMapsLink.embeddedMapsURL(in: html)?.absoluteString, "https://www.google.com/maps/dir/A/B/@45,9,12z?entry=ttu&g_ep=x")
    }

    func testDirectionsURLBuilder() throws {
        let link = GoogleMapsLink.directionsURL(
            origin: nil,
            destination: Coordinate(latitude: 45.484, longitude: 9.1895),
            waypoints: [Coordinate(latitude: 45.47, longitude: 9.17), Coordinate(latitude: 45.475, longitude: 9.175)]
        )
        let route = try XCTUnwrap(GoogleMapsLink.parse(link))
        XCTAssertEqual(route.points.count, 4)
        XCTAssertEqual(route.points.first, .currentLocation)
        XCTAssertTrue(route.isDriving)
        XCTAssertEqual(GoogleMapsLink.appURL(for: link)?.scheme, "comgooglemapsurl")
    }

    func testDirectionsURLWithOtherMode() throws {
        let link = GoogleMapsLink.directionsURL(
            origin: Coordinate(latitude: 45.47, longitude: 9.17),
            destination: Coordinate(latitude: 45.484, longitude: 9.1895),
            mode: .walking
        )
        XCTAssertTrue(link.absoluteString.contains("travelmode=walking"))
        let route = try XCTUnwrap(GoogleMapsLink.parse(link))
        XCTAssertEqual(route.points.count, 2)
        XCTAssertFalse(route.isDriving)
    }

    func testSwitchPointBeforeZoneEntry() throws {
        // Percorso verso nord di circa 1,1 km, ingresso nella zona a 800 m.
        let route = [Coordinate(latitude: 45.45, longitude: 9.19), Coordinate(latitude: 45.46, longitude: 9.19)]
        let hit = RouteHit(zoneID: "test", name: "Test", zone: .ztl, entry: route[1], distanceAlong: 800, passTime: Date())
        let result = try XCTUnwrap(RouteAnalyzer.switchPoint(route: route, before: hit))
        XCTAssertLessThanOrEqual(result.distanceAlong, 750)
        XCTAssertGreaterThan(result.distanceAlong, 730)
        XCTAssertLessThan(result.point.latitude, 45.46)

        let atStart = RouteHit(zoneID: "test", name: "Test", zone: .ztl, entry: route[0], distanceAlong: 0, passTime: Date())
        XCTAssertNil(RouteAnalyzer.switchPoint(route: route, before: atStart))
    }
}
