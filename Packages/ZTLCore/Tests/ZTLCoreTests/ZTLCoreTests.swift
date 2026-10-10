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
