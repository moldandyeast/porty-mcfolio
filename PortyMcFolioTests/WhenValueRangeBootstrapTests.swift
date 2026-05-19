import XCTest
@testable import PortyMcFolio

final class WhenValueRangeBootstrapTests: XCTestCase {

    private var utcCal: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func makeDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utcCal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func test_midYear_startIsFirstOfPrevMonth_endIsLastOfCurrentMonth() {
        let now = makeDate(2026, 5, 19)
        let v = WhenValue.rangeBootstrap(from: now)
        XCTAssertEqual(v.date, makeDate(2026, 4, 1))
        XCTAssertEqual(v.dateEnd, makeDate(2026, 5, 31))
        XCTAssertNil(v.yearOnlyYear)
    }

    func test_january_rollsBackToDecemberOfPriorYear() {
        let now = makeDate(2026, 1, 15)
        let v = WhenValue.rangeBootstrap(from: now)
        XCTAssertEqual(v.date, makeDate(2025, 12, 1))
        XCTAssertEqual(v.dateEnd, makeDate(2026, 1, 31))
    }

    func test_december_endIsDec31() {
        let now = makeDate(2026, 12, 7)
        let v = WhenValue.rangeBootstrap(from: now)
        XCTAssertEqual(v.date, makeDate(2026, 11, 1))
        XCTAssertEqual(v.dateEnd, makeDate(2026, 12, 31))
    }

    func test_february_endIsLastDayOfFebruary_nonLeap() {
        let now = makeDate(2026, 2, 10)
        let v = WhenValue.rangeBootstrap(from: now)
        XCTAssertEqual(v.date, makeDate(2026, 1, 1))
        XCTAssertEqual(v.dateEnd, makeDate(2026, 2, 28))
    }

    func test_february_endIsLastDayOfFebruary_leap() {
        let now = makeDate(2024, 2, 10)
        let v = WhenValue.rangeBootstrap(from: now)
        XCTAssertEqual(v.date, makeDate(2024, 1, 1))
        XCTAssertEqual(v.dateEnd, makeDate(2024, 2, 29))
    }
}
