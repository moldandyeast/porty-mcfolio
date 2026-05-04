import XCTest
@testable import PortyMcFolio

final class ViewModeMigrationTests: XCTestCase {

    private func scratchDefaults() -> UserDefaults {
        let name = "test-vm-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testMigratesLegacyCarouselFromFourToEight() {
        let d = scratchDefaults()
        d.set(4, forKey: "viewMode")

        ViewModeMigration.migrate(d)

        XCTAssertEqual(d.integer(forKey: "viewMode"), 8)
        XCTAssertTrue(d.bool(forKey: "viewModeMigratedToV2"))
    }

    func testMigratesEditorPreviewSplitGalleryUntouched() {
        for legacy in 0...3 {
            let d = scratchDefaults()
            d.set(legacy, forKey: "viewMode")

            ViewModeMigration.migrate(d)

            XCTAssertEqual(d.integer(forKey: "viewMode"), legacy, "legacy=\(legacy)")
            XCTAssertTrue(d.bool(forKey: "viewModeMigratedToV2"))
        }
    }

    func testSecondCallIsNoop() {
        let d = scratchDefaults()
        d.set(4, forKey: "viewMode")
        ViewModeMigration.migrate(d)
        XCTAssertEqual(d.integer(forKey: "viewMode"), 8)

        // User later picks .splitList which happens to be raw=4.
        d.set(4, forKey: "viewMode")

        ViewModeMigration.migrate(d)  // Should NOT re-migrate

        XCTAssertEqual(d.integer(forKey: "viewMode"), 4, "second call must not touch user's new value")
    }

    func testNoLegacyKeyStillSetsFlag() {
        let d = scratchDefaults()
        // No "viewMode" key written.

        ViewModeMigration.migrate(d)

        XCTAssertNil(d.object(forKey: "viewMode"))
        XCTAssertTrue(d.bool(forKey: "viewModeMigratedToV2"))
    }
}
