import XCTest
@testable import PortyMcFolio

final class SearchPaletteLogicTests: XCTestCase {

    func testEmptyResultsReturnsZero() {
        XCTAssertEqual(SearchPaletteLogic.clampedIndex(current: 3, resultCount: 0), 0)
    }

    func testIndexWithinBoundsIsUnchanged() {
        XCTAssertEqual(SearchPaletteLogic.clampedIndex(current: 2, resultCount: 5), 2)
        XCTAssertEqual(SearchPaletteLogic.clampedIndex(current: 0, resultCount: 5), 0)
        XCTAssertEqual(SearchPaletteLogic.clampedIndex(current: 4, resultCount: 5), 4)
    }

    func testIndexAboveBoundsClampsToLast() {
        XCTAssertEqual(SearchPaletteLogic.clampedIndex(current: 10, resultCount: 3), 2)
        XCTAssertEqual(SearchPaletteLogic.clampedIndex(current: 5, resultCount: 1), 0)
    }

    func testNegativeIndexClampsToZero() {
        XCTAssertEqual(SearchPaletteLogic.clampedIndex(current: -1, resultCount: 5), 0)
    }

    func testSelectionSurvivesRefineWhenStillInBounds() {
        // User arrowed to position 2 in a 5-result list, then typed to refine.
        // New result set still has 3+ results — selection should hold.
        XCTAssertEqual(SearchPaletteLogic.clampedIndex(current: 2, resultCount: 3), 2)
    }

    func testSelectionMovesUpWhenResultsShrink() {
        // User arrowed to position 4, then typed to refine; now only 2 results.
        // Selection should clamp to last valid index (1).
        XCTAssertEqual(SearchPaletteLogic.clampedIndex(current: 4, resultCount: 2), 1)
    }
}
