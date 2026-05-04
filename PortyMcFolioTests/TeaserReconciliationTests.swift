import XCTest
@testable import PortyMcFolio

final class TeaserReconciliationTests: XCTestCase {
    func testEmptyTeaserIsUnchanged() {
        XCTAssertEqual(
            TeaserReconciliation.reconcile(teaser: "", onDiskPaths: ["a.jpg"]),
            .unchanged
        )
    }

    func testTeaserStillOnDiskIsUnchanged() {
        XCTAssertEqual(
            TeaserReconciliation.reconcile(
                teaser: "hero.jpg",
                onDiskPaths: ["hero.jpg", "other.jpg"]
            ),
            .unchanged
        )
    }

    func testStaleTeaserWithOneBasenameMatchIsRepaired() {
        XCTAssertEqual(
            TeaserReconciliation.reconcile(
                teaser: "hero.jpg",
                onDiskPaths: ["subfolder/hero.jpg", "other.jpg"]
            ),
            .repaired(newPath: "subfolder/hero.jpg")
        )
    }

    func testStaleTeaserWithMultipleBasenameMatchesIsOrphaned() {
        XCTAssertEqual(
            TeaserReconciliation.reconcile(
                teaser: "hero.jpg",
                onDiskPaths: ["a/hero.jpg", "b/hero.jpg"]
            ),
            .orphaned
        )
    }

    func testStaleTeaserWithZeroMatchesIsOrphaned() {
        XCTAssertEqual(
            TeaserReconciliation.reconcile(
                teaser: "hero.jpg",
                onDiskPaths: ["other.jpg"]
            ),
            .orphaned
        )
    }

    func testAbsolutePathIsUnchanged() {
        XCTAssertEqual(
            TeaserReconciliation.reconcile(
                teaser: "/etc/hero.jpg",
                onDiskPaths: ["hero.jpg"]
            ),
            .unchanged
        )
    }

    func testDotDotPathIsUnchanged() {
        XCTAssertEqual(
            TeaserReconciliation.reconcile(
                teaser: "../hero.jpg",
                onDiskPaths: ["hero.jpg"]
            ),
            .unchanged
        )
    }

    func testBasenameMatchIsCaseInsensitive() {
        XCTAssertEqual(
            TeaserReconciliation.reconcile(
                teaser: "Hero.JPG",
                onDiskPaths: ["subfolder/hero.jpg"]
            ),
            .repaired(newPath: "subfolder/hero.jpg")
        )
    }
}
