import XCTest
@testable import PortyMcFolio

final class ProjectNavigationTests: XCTestCase {
    private let list = ["a", "b", "c", "d", "e", "f", "g"]

    // MARK: - Grid mode

    func testGridDownByColumnCount() {
        let next = ProjectNavigation.nextHighlightID(
            current: "a", in: list, direction: .down, columnCount: 3, mode: .grid
        )
        XCTAssertEqual(next, "d")
    }

    func testGridRightByOne() {
        let next = ProjectNavigation.nextHighlightID(
            current: "a", in: list, direction: .right, columnCount: 3, mode: .grid
        )
        XCTAssertEqual(next, "b")
    }

    func testGridUpFromSecondRow() {
        let next = ProjectNavigation.nextHighlightID(
            current: "d", in: list, direction: .up, columnCount: 3, mode: .grid
        )
        XCTAssertEqual(next, "a")
    }

    func testGridDownOvershootClampsToLast() {
        let next = ProjectNavigation.nextHighlightID(
            current: "f", in: list, direction: .down, columnCount: 3, mode: .grid
        )
        XCTAssertEqual(next, "g")
    }

    func testGridUpFromFirstItemNoOp() {
        let next = ProjectNavigation.nextHighlightID(
            current: "a", in: list, direction: .up, columnCount: 3, mode: .grid
        )
        XCTAssertEqual(next, "a")
    }

    func testGridLeftFromFirstItemNoOp() {
        let next = ProjectNavigation.nextHighlightID(
            current: "a", in: list, direction: .left, columnCount: 3, mode: .grid
        )
        XCTAssertEqual(next, "a")
    }

    func testGridRightFromLastItemNoOp() {
        let next = ProjectNavigation.nextHighlightID(
            current: "g", in: list, direction: .right, columnCount: 3, mode: .grid
        )
        XCTAssertEqual(next, "g")
    }

    // MARK: - Empty / nil / stale state

    func testEmptyListReturnsCurrent() {
        let next = ProjectNavigation.nextHighlightID(
            current: "x", in: [], direction: .down, columnCount: 3, mode: .grid
        )
        XCTAssertEqual(next, "x")
    }

    func testNilCurrentDownPicksFirst() {
        let next = ProjectNavigation.nextHighlightID(
            current: nil, in: list, direction: .down, columnCount: 3, mode: .grid
        )
        XCTAssertEqual(next, "a")
    }

    func testNilCurrentRightPicksFirst() {
        let next = ProjectNavigation.nextHighlightID(
            current: nil, in: list, direction: .right, columnCount: 3, mode: .grid
        )
        XCTAssertEqual(next, "a")
    }

    func testNilCurrentUpNoOp() {
        let next = ProjectNavigation.nextHighlightID(
            current: nil, in: list, direction: .up, columnCount: 3, mode: .grid
        )
        XCTAssertNil(next)
    }

    func testNilCurrentLeftNoOp() {
        let next = ProjectNavigation.nextHighlightID(
            current: nil, in: list, direction: .left, columnCount: 3, mode: .grid
        )
        XCTAssertNil(next)
    }

    func testStaleCurrentTreatedAsNil() {
        let next = ProjectNavigation.nextHighlightID(
            current: "zzz", in: list, direction: .down, columnCount: 3, mode: .grid
        )
        XCTAssertEqual(next, "a")
    }

    // MARK: - Table mode

    func testTableDownByOne() {
        let next = ProjectNavigation.nextHighlightID(
            current: "a", in: list, direction: .down, columnCount: 99, mode: .table
        )
        XCTAssertEqual(next, "b")
    }

    func testTableUpByOne() {
        let next = ProjectNavigation.nextHighlightID(
            current: "c", in: list, direction: .up, columnCount: 99, mode: .table
        )
        XCTAssertEqual(next, "b")
    }

    func testTableLeftNoOp() {
        let next = ProjectNavigation.nextHighlightID(
            current: "c", in: list, direction: .left, columnCount: 99, mode: .table
        )
        XCTAssertEqual(next, "c")
    }

    func testTableRightNoOp() {
        let next = ProjectNavigation.nextHighlightID(
            current: "c", in: list, direction: .right, columnCount: 99, mode: .table
        )
        XCTAssertEqual(next, "c")
    }

    // MARK: - Column count edge

    func testGridColumnCountZeroTreatedAsOne() {
        let next = ProjectNavigation.nextHighlightID(
            current: "a", in: list, direction: .down, columnCount: 0, mode: .grid
        )
        XCTAssertEqual(next, "b")
    }

    // MARK: - Boundary no-ops (stop-at-edges contract)

    func testGridDownFromLastItemNoOp() {
        // At last item, ↓ by stride clamps to same index → returns current unchanged.
        let next = ProjectNavigation.nextHighlightID(
            current: "g", in: list, direction: .down, columnCount: 3, mode: .grid
        )
        XCTAssertEqual(next, "g")
    }

    func testTableDownFromLastItemNoOp() {
        let next = ProjectNavigation.nextHighlightID(
            current: "g", in: list, direction: .down, columnCount: 1, mode: .table
        )
        XCTAssertEqual(next, "g")
    }

    func testTableUpFromFirstItemNoOp() {
        let next = ProjectNavigation.nextHighlightID(
            current: "a", in: list, direction: .up, columnCount: 1, mode: .table
        )
        XCTAssertEqual(next, "a")
    }

    // MARK: - Grouped grid (year-aware)

    private let groupA = ["a", "b", "c", "d", "e", "f", "g"]  // 7 items; with cols=3 → rows [a,b,c],[d,e,f],[g]
    private let groupB = ["h", "i", "j", "k"]                 // 4 items; with cols=3 → rows [h,i,j],[k]

    func testGroupedGridDownSameGroup() {
        let next = ProjectNavigation.nextHighlightIDInGroupedGrid(
            current: "a", groups: [groupA], direction: .down, columnCount: 3
        )
        XCTAssertEqual(next, "d")
    }

    func testGroupedGridDownCrossingEmptyRowToNextGroup() {
        // "g" is last of groupA (row 2, col 0). ↓ → groupB row 0 col 0 = "h".
        let next = ProjectNavigation.nextHighlightIDInGroupedGrid(
            current: "g", groups: [groupA, groupB], direction: .down, columnCount: 3
        )
        XCTAssertEqual(next, "h")
    }

    func testGroupedGridDownPreservesColWithSoftClamp() {
        // "e" (groupA row 1 col 1). ↓ targets row 2 col 1 — which doesn't exist (row 2 only has "g" at col 0).
        // Soft-clamp to last card of row 2 = "g".
        let next = ProjectNavigation.nextHighlightIDInGroupedGrid(
            current: "e", groups: [groupA, groupB], direction: .down, columnCount: 3
        )
        XCTAssertEqual(next, "g")
    }

    func testGroupedGridDownAcrossGroupPreservesCol() {
        // "j" (groupB row 0 col 2). ↓ targets row 1 col 2 — doesn't exist (row 1 only has "k" at col 0).
        // Soft-clamp to last card of row 1 = "k".
        let next = ProjectNavigation.nextHighlightIDInGroupedGrid(
            current: "j", groups: [groupA, groupB], direction: .down, columnCount: 3
        )
        XCTAssertEqual(next, "k")
    }

    func testGroupedGridDownAtBottomNoOp() {
        let next = ProjectNavigation.nextHighlightIDInGroupedGrid(
            current: "k", groups: [groupA, groupB], direction: .down, columnCount: 3
        )
        XCTAssertEqual(next, "k")
    }

    func testGroupedGridUpToPrevGroupPreservesCol() {
        // "h" (groupB row 0 col 0). ↑ → groupA last row col 0 = "g".
        let next = ProjectNavigation.nextHighlightIDInGroupedGrid(
            current: "h", groups: [groupA, groupB], direction: .up, columnCount: 3
        )
        XCTAssertEqual(next, "g")
    }

    func testGroupedGridUpAcrossGroupsWithSoftClamp() {
        // "i" (groupB row 0 col 1). ↑ → groupA last row col 1 — doesn't exist → clamp to "g".
        let next = ProjectNavigation.nextHighlightIDInGroupedGrid(
            current: "i", groups: [groupA, groupB], direction: .up, columnCount: 3
        )
        XCTAssertEqual(next, "g")
    }

    func testGroupedGridUpAtTopNoOp() {
        let next = ProjectNavigation.nextHighlightIDInGroupedGrid(
            current: "a", groups: [groupA, groupB], direction: .up, columnCount: 3
        )
        XCTAssertEqual(next, "a")
    }

    func testGroupedGridRightCrossesGroupBoundary() {
        // "g" is last of groupA; → should go to "h" (first of groupB).
        let next = ProjectNavigation.nextHighlightIDInGroupedGrid(
            current: "g", groups: [groupA, groupB], direction: .right, columnCount: 3
        )
        XCTAssertEqual(next, "h")
    }

    func testGroupedGridLeftCrossesGroupBoundaryBackwards() {
        let next = ProjectNavigation.nextHighlightIDInGroupedGrid(
            current: "h", groups: [groupA, groupB], direction: .left, columnCount: 3
        )
        XCTAssertEqual(next, "g")
    }

    func testGroupedGridEmptyGroupsReturnsCurrent() {
        let next = ProjectNavigation.nextHighlightIDInGroupedGrid(
            current: "x", groups: [], direction: .down, columnCount: 3
        )
        XCTAssertEqual(next, "x")
    }

    func testGroupedGridNilCurrentDownPicksFirst() {
        let next = ProjectNavigation.nextHighlightIDInGroupedGrid(
            current: nil, groups: [groupA, groupB], direction: .down, columnCount: 3
        )
        XCTAssertEqual(next, "a")
    }

    func testGroupedGridNilCurrentUpNoOp() {
        let next = ProjectNavigation.nextHighlightIDInGroupedGrid(
            current: nil, groups: [groupA, groupB], direction: .up, columnCount: 3
        )
        XCTAssertNil(next)
    }

    func testGroupedGridSkipsEmptyGroups() {
        // groupA, empty, groupB — ↓ from "g" should skip the empty group and land on "h".
        let next = ProjectNavigation.nextHighlightIDInGroupedGrid(
            current: "g", groups: [groupA, [], groupB], direction: .down, columnCount: 3
        )
        XCTAssertEqual(next, "h")
    }

    func testGroupedGridStaleCurrentDownPicksFirst() {
        let next = ProjectNavigation.nextHighlightIDInGroupedGrid(
            current: "zzz", groups: [groupA, groupB], direction: .down, columnCount: 3
        )
        XCTAssertEqual(next, "a")
    }

    func testGroupedGridColumnCountZeroTreatedAsOne() {
        let next = ProjectNavigation.nextHighlightIDInGroupedGrid(
            current: "a", groups: [groupA], direction: .down, columnCount: 0
        )
        XCTAssertEqual(next, "b")
    }
}
