import XCTest
@testable import PortyMcFolio

final class FilenameDisplayTests: XCTestCase {
    func testStripsMatchingPrefix() {
        XCTAssertEqual(
            FilenameDisplay.display(name: "2026_foo_bar_baz.mp4", prefix: "2026_foo_"),
            "bar_baz.mp4"
        )
    }

    func testLeavesNonMatchingPrefixUntouched() {
        XCTAssertEqual(
            FilenameDisplay.display(name: "2026_foo_bar.mp4", prefix: "2025_foo_"),
            "2026_foo_bar.mp4"
        )
    }

    func testEmptyPrefixIsNoOp() {
        XCTAssertEqual(
            FilenameDisplay.display(name: "foo.mp4", prefix: ""),
            "foo.mp4"
        )
    }

    func testNameExactlyEqualsPrefixReturnsEmpty() {
        XCTAssertEqual(
            FilenameDisplay.display(name: "2026_foo_", prefix: "2026_foo_"),
            ""
        )
    }

    func testUnicodePrefix() {
        XCTAssertEqual(
            FilenameDisplay.display(name: "2026_café_x.jpg", prefix: "2026_café_"),
            "x.jpg"
        )
    }

    func testPrefixComputedFromTitleAndYear() {
        let prefix = "2026_\(Slug.underscoreFrom("Acme Rebrand"))_"
        XCTAssertEqual(prefix, "2026_acme_rebrand_")
        XCTAssertEqual(
            FilenameDisplay.display(name: "2026_acme_rebrand_logo.png", prefix: prefix),
            "logo.png"
        )
    }
}
