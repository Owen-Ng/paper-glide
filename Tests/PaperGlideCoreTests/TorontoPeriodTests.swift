import PaperGlideCore
import XCTest

final class TorontoPeriodTests: XCTestCase {
    func testSpringForwardKeepsTheCivilDay() {
        let beforeGap = TestTime.iso("2026-03-08T06:30:00Z")
        let afterGap = TestTime.iso("2026-03-08T07:30:00Z")
        XCTAssertEqual(TorontoPeriod.dayKey(for: beforeGap), "2026-03-08")
        XCTAssertEqual(TorontoPeriod.dayKey(for: afterGap), "2026-03-08")
        XCTAssertEqual(TorontoPeriod.weekKey(for: beforeGap), "2026-03-02")
        XCTAssertEqual(TorontoPeriod.weekKey(for: afterGap), "2026-03-02")
    }

    func testDailyBoundaryMovesWithDST() {
        let saturdayNight = TestTime.iso("2026-03-08T04:30:00Z")
        let sundayAfterMidnightEST = TestTime.iso("2026-03-08T05:30:00Z")
        XCTAssertEqual(TorontoPeriod.dayKey(for: saturdayNight), "2026-03-07")
        XCTAssertEqual(TorontoPeriod.dayKey(for: sundayAfterMidnightEST), "2026-03-08")

        let sundayNightEDT = TestTime.iso("2026-03-09T03:30:00Z")
        let mondayEDT = TestTime.iso("2026-03-09T04:00:00Z")
        XCTAssertEqual(TorontoPeriod.dayKey(for: sundayNightEDT), "2026-03-08")
        XCTAssertEqual(TorontoPeriod.dayKey(for: mondayEDT), "2026-03-09")
        XCTAssertEqual(TorontoPeriod.weekKey(for: sundayNightEDT), "2026-03-02")
        XCTAssertEqual(TorontoPeriod.weekKey(for: mondayEDT), "2026-03-09")
    }

    func testFallBackRepeatedHourStaysOnSunday() {
        let firstOneThirty = TestTime.iso("2026-11-01T05:30:00Z")
        let repeatedOneThirty = TestTime.iso("2026-11-01T06:30:00Z")
        XCTAssertEqual(TorontoPeriod.dayKey(for: firstOneThirty), "2026-11-01")
        XCTAssertEqual(TorontoPeriod.dayKey(for: repeatedOneThirty), "2026-11-01")
        XCTAssertEqual(TorontoPeriod.weekKey(for: firstOneThirty), "2026-10-26")
        XCTAssertEqual(TorontoPeriod.weekKey(for: repeatedOneThirty), "2026-10-26")

        let sundayNight = TestTime.iso("2026-11-02T04:30:00Z")
        let monday = TestTime.iso("2026-11-02T05:30:00Z")
        XCTAssertEqual(TorontoPeriod.dayKey(for: sundayNight), "2026-11-01")
        XCTAssertEqual(TorontoPeriod.dayKey(for: monday), "2026-11-02")
        XCTAssertEqual(TorontoPeriod.weekKey(for: sundayNight), "2026-10-26")
        XCTAssertEqual(TorontoPeriod.weekKey(for: monday), "2026-11-02")
    }
}
