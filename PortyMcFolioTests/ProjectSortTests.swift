import XCTest
@testable import PortyMcFolio

final class ProjectSortTests: XCTestCase {

    private func makeDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func makeProject(
        uid: String,
        title: String,
        year: Int,
        date: Date,
        dateEnd: Date? = nil
    ) -> Project {
        Project(
            uid: uid,
            year: year,
            folderName: "\(year)_\(title.lowercased())_\(uid)",
            folderURL: URL(fileURLWithPath: "/tmp/\(uid)"),
            title: title,
            date: date,
            dateEnd: dateEnd,
            tags: [],
            client: "",
            status: .empty,
            body: "",
            teaser: "",
            favorites: []
        )
    }

    func test_effectiveSortDate_yearPrecision_isJan1OfFolderYear() {
        // Folder year 2025; project's `date` happens to be in 2026 (legacy noise)
        let p = makeProject(
            uid: "00000001", title: "P", year: 2025,
            date: makeDate(2026, 6, 15)
        )
        XCTAssertEqual(ProjectSort.effectiveSortDate(for: p), makeDate(2025, 1, 1))
    }

    func test_effectiveSortDate_range_isDateEnd() {
        let p = makeProject(
            uid: "00000004", title: "P", year: 2025,
            date: makeDate(2025, 3, 1),
            dateEnd: makeDate(2025, 6, 30)
        )
        XCTAssertEqual(ProjectSort.effectiveSortDate(for: p), makeDate(2025, 6, 30))
    }

    func test_sortedWithinYear_explicitWhensDescend() {
        let mar = makeProject(uid: "a1111111", title: "March", year: 2025, date: makeDate(2025, 3, 1), dateEnd: makeDate(2025, 3, 31))
        let jun = makeProject(uid: "a2222222", title: "June", year: 2025, date: makeDate(2025, 6, 1), dateEnd: makeDate(2025, 6, 30))
        let sep = makeProject(uid: "a3333333", title: "Sept", year: 2025, date: makeDate(2025, 9, 1), dateEnd: makeDate(2025, 9, 30))
        let sorted = ProjectSort.sortedWithinYear([mar, jun, sep])
        XCTAssertEqual(sorted.map(\.title), ["Sept", "June", "March"])
    }

    func test_sortedWithinYear_yearOnlyProjectsFallToEnd() {
        let dated = makeProject(uid: "b1111111", title: "Dated", year: 2025, date: makeDate(2025, 3, 1), dateEnd: makeDate(2025, 3, 31))
        let yearOnlyA = makeProject(uid: "b2222222", title: "Alpha", year: 2025, date: makeDate(2025, 1, 1))
        let yearOnlyB = makeProject(uid: "b3333333", title: "Bravo", year: 2025, date: makeDate(2025, 1, 1))
        let sorted = ProjectSort.sortedWithinYear([yearOnlyA, dated, yearOnlyB])
        XCTAssertEqual(sorted.map(\.title), ["Dated", "Alpha", "Bravo"])
    }

    func test_sortedWithinYear_alphaTieBreakOnSameDate() {
        let zebra = makeProject(uid: "c1111111", title: "Zebra", year: 2025, date: makeDate(2025, 3, 1), dateEnd: makeDate(2025, 3, 31))
        let apple = makeProject(uid: "c2222222", title: "Apple", year: 2025, date: makeDate(2025, 3, 1), dateEnd: makeDate(2025, 3, 31))
        let sorted = ProjectSort.sortedWithinYear([zebra, apple])
        XCTAssertEqual(sorted.map(\.title), ["Apple", "Zebra"])
    }
}
