import XCTest
@testable import PortyMcFolio

final class WhenFormattingTests: XCTestCase {

    private func makeDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func test_yearOnly_returnsYearString() {
        let s = WhenFormatting.summaryString(
            date: makeDate(2025, 1, 1),
            dateEnd: nil,
            year: 2025
        )
        XCTAssertEqual(s, "2025")
    }

    func test_range_sameYear_differentMonths() {
        let s = WhenFormatting.summaryString(
            date: makeDate(2025, 3, 1),
            dateEnd: makeDate(2025, 6, 30),
            year: 2025
        )
        XCTAssertEqual(s, "MAR — JUN 2025")
    }

    func test_range_sameYear_sameMonth_collapsesToSingleMonth() {
        let s = WhenFormatting.summaryString(
            date: makeDate(2025, 3, 1),
            dateEnd: makeDate(2025, 3, 31),
            year: 2025
        )
        XCTAssertEqual(s, "MAR 2025")
    }

    func test_range_crossYear() {
        let s = WhenFormatting.summaryString(
            date: makeDate(2024, 9, 1),
            dateEnd: makeDate(2025, 2, 28),
            year: 2025
        )
        XCTAssertEqual(s, "SEP 2024 — FEB 2025")
    }

    func test_yearOnly_ignoresDateArgument() {
        // When year-only, the start date should not influence output.
        let s = WhenFormatting.summaryString(
            date: makeDate(2030, 11, 1),  // bogus
            dateEnd: nil,
            year: 2025
        )
        XCTAssertEqual(s, "2025")
    }
}
