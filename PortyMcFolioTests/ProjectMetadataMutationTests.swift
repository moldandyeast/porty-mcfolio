import XCTest
@testable import PortyMcFolio

final class ProjectMetadataMutationTests: XCTestCase {

    private func makeDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func test_yearOnly_usesPickedYearOnlyYear() {
        let when = WhenValue.yearOnly(year: 2025, anchor: makeDate(2025, 1, 1))
        let derived = ProjectMetadataMutation.resolveFolderYear(when: when, currentYear: 2024)
        XCTAssertEqual(derived, 2025)
    }

    func test_yearOnly_fallsBackToCurrentYearWhenYearOnlyYearMissing() {
        let when = WhenValue(date: makeDate(2025, 1, 1), dateEnd: nil, yearOnlyYear: nil)
        let derived = ProjectMetadataMutation.resolveFolderYear(when: when, currentYear: 2030)
        XCTAssertEqual(derived, 2030)
    }

    func test_range_usesYearOfDateEnd() {
        let when = WhenValue(
            date: makeDate(2024, 9, 1),
            dateEnd: makeDate(2025, 2, 28),
            yearOnlyYear: nil
        )
        let derived = ProjectMetadataMutation.resolveFolderYear(when: when, currentYear: 2024)
        XCTAssertEqual(derived, 2025)
    }

    func test_range_dateEndOverridesYearOnlyYearIfBothSet() {
        let when = WhenValue(
            date: makeDate(2024, 9, 1),
            dateEnd: makeDate(2025, 2, 28),
            yearOnlyYear: 9999
        )
        let derived = ProjectMetadataMutation.resolveFolderYear(when: when, currentYear: 2024)
        XCTAssertEqual(derived, 2025)
    }
}
