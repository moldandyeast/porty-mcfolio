import XCTest
@testable import PortyMcFolio

final class GallerySelectionTests: XCTestCase {
    func testIsHashableInSet() {
        let a = GallerySelection.file(URL(fileURLWithPath: "/a.png"))
        let b = GallerySelection.file(URL(fileURLWithPath: "/b.png"))
        let aDup = GallerySelection.file(URL(fileURLWithPath: "/a.png"))

        var set: Set<GallerySelection> = []
        set.insert(a)
        set.insert(b)
        set.insert(aDup)

        XCTAssertEqual(set.count, 2)
        XCTAssertTrue(set.contains(a))
    }

    func testDistinctCasesAreDistinct() {
        let file = GallerySelection.file(URL(fileURLWithPath: "/x"))
        let folder = GallerySelection.folder(URL(fileURLWithPath: "/x"))
        XCTAssertNotEqual(file, folder)
    }
}
