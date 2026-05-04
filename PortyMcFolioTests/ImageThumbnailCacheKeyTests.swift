import XCTest
@testable import PortyMcFolio

final class ImageThumbnailCacheKeyTests: XCTestCase {

    private let urlA = URL(fileURLWithPath: "/tmp/a.png")
    private let urlB = URL(fileURLWithPath: "/tmp/b.png")

    func testSameUrlAndSizeProducesEqualKey() {
        let k1 = ImageThumbnail.cacheKey(url: urlA, size: CGSize(width: 100, height: 100))
        let k2 = ImageThumbnail.cacheKey(url: urlA, size: CGSize(width: 100, height: 100))
        XCTAssertEqual(k1, k2)
    }

    func testDifferentUrlProducesDifferentKey() {
        let k1 = ImageThumbnail.cacheKey(url: urlA, size: CGSize(width: 100, height: 100))
        let k2 = ImageThumbnail.cacheKey(url: urlB, size: CGSize(width: 100, height: 100))
        XCTAssertNotEqual(k1, k2)
    }

    func testDifferentSizeProducesDifferentKey() {
        let k1 = ImageThumbnail.cacheKey(url: urlA, size: CGSize(width: 100, height: 100))
        let k2 = ImageThumbnail.cacheKey(url: urlA, size: CGSize(width: 1600, height: 1200))
        XCTAssertNotEqual(k1, k2)
    }

    func testFractionalSizesAreRoundedSoNearDuplicatesShareCache() {
        // Thumbnail targets are integer-pixel; fractional widths should be
        // bucketed to the same cache entry rather than producing near-duplicates.
        let k1 = ImageThumbnail.cacheKey(url: urlA, size: CGSize(width: 100.4, height: 100.4))
        let k2 = ImageThumbnail.cacheKey(url: urlA, size: CGSize(width: 100.0, height: 100.0))
        XCTAssertEqual(k1, k2)
    }
}
