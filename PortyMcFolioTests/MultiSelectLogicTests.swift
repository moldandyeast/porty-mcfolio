// PortyMcFolioTests/MultiSelectLogicTests.swift
import XCTest
@testable import PortyMcFolio

final class MultiSelectLogicTests: XCTestCase {
    private func sel(_ i: Int) -> GallerySelection {
        .file(URL(fileURLWithPath: "/\(i).png"))
    }

    func testRangeForwardInclusive() {
        let seq = [sel(0), sel(1), sel(2), sel(3), sel(4)]
        let range = MultiSelectLogic.rangeBetween(sel(1), sel(3), in: seq)
        XCTAssertEqual(range, [sel(1), sel(2), sel(3)])
    }

    func testRangeReverseFlips() {
        let seq = [sel(0), sel(1), sel(2), sel(3), sel(4)]
        let range = MultiSelectLogic.rangeBetween(sel(3), sel(1), in: seq)
        XCTAssertEqual(range, [sel(1), sel(2), sel(3)])
    }

    func testRangeSameIndex() {
        let seq = [sel(0), sel(1), sel(2)]
        let range = MultiSelectLogic.rangeBetween(sel(1), sel(1), in: seq)
        XCTAssertEqual(range, [sel(1)])
    }

    func testRangeMissingAnchorReturnsEmpty() {
        let seq = [sel(0), sel(1), sel(2)]
        let range = MultiSelectLogic.rangeBetween(sel(99), sel(1), in: seq)
        XCTAssertEqual(range, [])
    }

    func testRangeMissingTargetReturnsEmpty() {
        let seq = [sel(0), sel(1), sel(2)]
        let range = MultiSelectLogic.rangeBetween(sel(1), sel(99), in: seq)
        XCTAssertEqual(range, [])
    }

    // MARK: - validateMove

    func testMoveIntoDifferentFolderAllowed() {
        let target = URL(fileURLWithPath: "/root/dest")
        let items = [URL(fileURLWithPath: "/root/a.png")]
        XCTAssertEqual(
            MultiSelectLogic.validateMove(items: items, into: target),
            .allowed
        )
    }

    func testMoveFolderIntoItselfRejected() {
        let target = URL(fileURLWithPath: "/root/dest")
        let items = [target]
        XCTAssertEqual(
            MultiSelectLogic.validateMove(items: items, into: target),
            .rejected(reason: .targetInSelection)
        )
    }

    func testMoveFolderIntoItsDescendantRejected() {
        let parent = URL(fileURLWithPath: "/root/parent")
        let child = URL(fileURLWithPath: "/root/parent/child")
        XCTAssertEqual(
            MultiSelectLogic.validateMove(items: [parent], into: child),
            .rejected(reason: .targetIsDescendantOfSelection)
        )
    }

    func testMoveWhenTargetIsOneOfTheItemsRejected() {
        let target = URL(fileURLWithPath: "/root/dest")
        let items = [URL(fileURLWithPath: "/root/a.png"), target]
        XCTAssertEqual(
            MultiSelectLogic.validateMove(items: items, into: target),
            .rejected(reason: .targetInSelection)
        )
    }

    // MARK: - favoriteToggleDirection

    func testFavoriteDirectionAllFavoritedUnfavorites() {
        let selected = [
            URL(fileURLWithPath: "/root/a.png"),
            URL(fileURLWithPath: "/root/b.png"),
        ]
        let favorites = ["a.png", "b.png", "c.png"]
        let projectRoot = URL(fileURLWithPath: "/root")
        XCTAssertEqual(
            MultiSelectLogic.favoriteToggleDirection(
                selected: selected, projectRoot: projectRoot, favorites: favorites
            ),
            .unfavoriteAll
        )
    }

    func testFavoriteDirectionNoneFavoritedFavorites() {
        let selected = [
            URL(fileURLWithPath: "/root/a.png"),
            URL(fileURLWithPath: "/root/b.png"),
        ]
        let favorites = ["c.png"]
        let projectRoot = URL(fileURLWithPath: "/root")
        XCTAssertEqual(
            MultiSelectLogic.favoriteToggleDirection(
                selected: selected, projectRoot: projectRoot, favorites: favorites
            ),
            .favoriteAll
        )
    }

    func testFavoriteDirectionMixedFavorites() {
        let selected = [
            URL(fileURLWithPath: "/root/a.png"),
            URL(fileURLWithPath: "/root/b.png"),
        ]
        let favorites = ["a.png"]
        let projectRoot = URL(fileURLWithPath: "/root")
        XCTAssertEqual(
            MultiSelectLogic.favoriteToggleDirection(
                selected: selected, projectRoot: projectRoot, favorites: favorites
            ),
            .favoriteAll
        )
    }

    func testFavoriteDirectionEmptyNoop() {
        let projectRoot = URL(fileURLWithPath: "/root")
        XCTAssertEqual(
            MultiSelectLogic.favoriteToggleDirection(
                selected: [], projectRoot: projectRoot, favorites: ["a.png"]
            ),
            .noop
        )
    }
}
