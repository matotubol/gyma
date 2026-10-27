import XCTest
@testable import GymaCore

final class CivilDateTests: XCTestCase {
    func testMonthCellsStartOnMonday() {
        let cells = CivilDate.cells(month: "2026-10")
        XCTAssertEqual(cells.first, "2026-09-28")
        XCTAssertEqual(cells.last, "2026-11-01")
        XCTAssertEqual(cells.count, 35)
    }

    func testShiftsAcrossBoundaries() {
        XCTAssertEqual(CivilDate.shift(day: "2026-12-31", by: 1), "2027-01-01")
        XCTAssertEqual(CivilDate.shift(month: "2026-01", by: -1), "2025-12")
        XCTAssertEqual(CivilDate.shift(month: "2026-10", by: 1), "2026-11")
    }

    func testValidatesKeys() {
        XCTAssertTrue(CivilDate.isValid("2026-02-28"))
        XCTAssertFalse(CivilDate.isValid("2026-02-30"))
        XCTAssertFalse(CivilDate.isValid("26-2-1"))
    }

    func testParsesWorkerTimestamps() {
        XCTAssertNotNil(parseTimestamp("2026-10-27T17:00:00.123Z"))
        XCTAssertNotNil(parseTimestamp("2026-10-27T17:00:00Z"))
    }
}
