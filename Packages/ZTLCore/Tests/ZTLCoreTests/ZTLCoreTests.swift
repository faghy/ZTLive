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
        XCTAssertEqual(approach.gate, gateNorth)
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
