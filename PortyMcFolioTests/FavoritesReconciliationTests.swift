import XCTest
@testable import PortyMcFolio

final class FavoritesReconciliationTests: XCTestCase {
    func testAllEntriesExistOnDisk_unchanged() {
        let favs = ["a.jpg", "sub/b.mp4"]
        let disk: Set<String> = ["a.jpg", "sub/b.mp4", "unrelated/c.png"]
        let out = FavoritesReconciliation.reconcile(favorites: favs, onDiskPaths: disk)
        XCTAssertEqual(out.reconciled, favs)
    }

    func testBasenameMatchAfterMove() {
        // "hero.jpg" used to be at root; now it's in "photos/hero.jpg".
        let favs = ["hero.jpg"]
        let disk: Set<String> = ["photos/hero.jpg"]
        let out = FavoritesReconciliation.reconcile(favorites: favs, onDiskPaths: disk)
        XCTAssertEqual(out.reconciled, ["photos/hero.jpg"])
    }

    func testMissingWithNoBasenameMatch_dropped() {
        let favs = ["gone.jpg", "still.png"]
        let disk: Set<String> = ["still.png"]
        let out = FavoritesReconciliation.reconcile(favorites: favs, onDiskPaths: disk)
        XCTAssertEqual(out.reconciled, ["still.png"])
    }

    func testAmbiguousBasename_dropped() {
        // Two files with the same basename — can't safely pick; drop.
        let favs = ["hero.jpg"]
        let disk: Set<String> = ["a/hero.jpg", "b/hero.jpg"]
        let out = FavoritesReconciliation.reconcile(favorites: favs, onDiskPaths: disk)
        XCTAssertEqual(out.reconciled, [])
    }

    func testDedup_firstOccurrenceWins_orderPreserved() {
        let favs = ["a.jpg", "b.mp4", "a.jpg", "c.mp3"]
        let disk: Set<String> = ["a.jpg", "b.mp4", "c.mp3"]
        let out = FavoritesReconciliation.reconcile(favorites: favs, onDiskPaths: disk)
        XCTAssertEqual(out.reconciled, ["a.jpg", "b.mp4", "c.mp3"])
    }

    func testDedupAfterBasenameRewrite() {
        // Both favorites match the same on-disk file after basename rewrite
        // → keep only the first rewritten, drop the duplicate.
        let favs = ["hero.jpg", "hero.jpg"]
        let disk: Set<String> = ["photos/hero.jpg"]
        let out = FavoritesReconciliation.reconcile(favorites: favs, onDiskPaths: disk)
        XCTAssertEqual(out.reconciled, ["photos/hero.jpg"])
    }

    func testCaseInsensitiveBasenameMatch() {
        // macOS filesystem is usually case-insensitive; the basename heuristic
        // should be case-insensitive to match typical user filesystems.
        let favs = ["HERO.JPG"]
        let disk: Set<String> = ["photos/hero.jpg"]
        let out = FavoritesReconciliation.reconcile(favorites: favs, onDiskPaths: disk)
        XCTAssertEqual(out.reconciled, ["photos/hero.jpg"])
    }

    func testOrderPreservedAcrossMixedOutcomes() {
        let favs = ["a.jpg", "moved.png", "gone.mp3", "d.mp4"]
        // moved.png exists at new path; gone.mp3 has no match
        let disk: Set<String> = ["a.jpg", "sub/moved.png", "d.mp4"]
        let out = FavoritesReconciliation.reconcile(favorites: favs, onDiskPaths: disk)
        XCTAssertEqual(out.reconciled, ["a.jpg", "sub/moved.png", "d.mp4"])
    }

    // MARK: - droppedCount (added 2026-04-24)

    func testDroppedCountZeroWhenAllFavoritesResolve() {
        let result = FavoritesReconciliation.reconcile(
            favorites: ["a.jpg", "b.jpg"],
            onDiskPaths: ["a.jpg", "b.jpg"]
        )
        XCTAssertEqual(result.reconciled, ["a.jpg", "b.jpg"])
        XCTAssertEqual(result.droppedCount, 0)
    }

    func testDroppedCountZeroWhenFavoriteIsRelocated() {
        let result = FavoritesReconciliation.reconcile(
            favorites: ["hero.jpg"],
            onDiskPaths: ["subfolder/hero.jpg"]
        )
        XCTAssertEqual(result.reconciled, ["subfolder/hero.jpg"])
        XCTAssertEqual(result.droppedCount, 0, "Relocation is not a drop")
    }

    func testDroppedCountOneWhenFavoriteHasNoMatch() {
        let result = FavoritesReconciliation.reconcile(
            favorites: ["hero.jpg"],
            onDiskPaths: ["other.jpg"]
        )
        XCTAssertEqual(result.reconciled, [])
        XCTAssertEqual(result.droppedCount, 1)
    }

    func testDroppedCountWhenFavoriteHasAmbiguousMatch() {
        let result = FavoritesReconciliation.reconcile(
            favorites: ["hero.jpg"],
            onDiskPaths: ["a/hero.jpg", "b/hero.jpg"]
        )
        XCTAssertEqual(result.reconciled, [])
        XCTAssertEqual(result.droppedCount, 1, "Ambiguous basename counts as a drop")
    }

    func testDroppedCountDoesNotIncludeDuplicates() {
        // Two favorites both resolve to the same disk path — one is deduped,
        // not dropped.
        let result = FavoritesReconciliation.reconcile(
            favorites: ["hero.jpg", "hero.jpg"],
            onDiskPaths: ["hero.jpg"]
        )
        XCTAssertEqual(result.reconciled, ["hero.jpg"])
        XCTAssertEqual(result.droppedCount, 0, "Duplicate is not a drop")
    }

    func testDroppedCountSumsAcrossMixedCases() {
        let result = FavoritesReconciliation.reconcile(
            favorites: ["kept.jpg", "missing.jpg", "ambiguous.jpg", "relocated.jpg"],
            onDiskPaths: [
                "kept.jpg",
                "a/ambiguous.jpg", "b/ambiguous.jpg",  // ambiguous → drop
                "new/relocated.jpg"                     // basename 1 match → relocate
            ]
        )
        XCTAssertEqual(result.reconciled, ["kept.jpg", "new/relocated.jpg"])
        XCTAssertEqual(result.droppedCount, 2, "missing.jpg and ambiguous.jpg")
    }
}
