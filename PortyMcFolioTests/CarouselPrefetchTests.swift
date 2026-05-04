import XCTest
@testable import PortyMcFolio

final class CarouselPrefetchTests: XCTestCase {

    func testEmptyListReturnsEmpty() {
        XCTAssertEqual(CarouselPrefetch.indicesToPrefetch(around: 0, count: 0, radius: 2), [])
    }

    func testRadiusZeroReturnsEmpty() {
        XCTAssertEqual(CarouselPrefetch.indicesToPrefetch(around: 2, count: 5, radius: 0), [])
    }

    func testMiddleOfListReturnsBothNeighbors() {
        XCTAssertEqual(
            Set(CarouselPrefetch.indicesToPrefetch(around: 2, count: 5, radius: 1)),
            Set([1, 3])
        )
    }

    func testAtFirstIndexReturnsOnlyForward() {
        XCTAssertEqual(CarouselPrefetch.indicesToPrefetch(around: 0, count: 5, radius: 2), [1, 2])
    }

    func testAtLastIndexReturnsOnlyBackward() {
        XCTAssertEqual(CarouselPrefetch.indicesToPrefetch(around: 4, count: 5, radius: 2), [3, 2])
    }

    func testRadiusLargerThanListClampsToAvailableNeighbors() {
        // 3 items, current=1, radius=5 → neighbors 0 and 2 only.
        XCTAssertEqual(
            Set(CarouselPrefetch.indicesToPrefetch(around: 1, count: 3, radius: 5)),
            Set([0, 2])
        )
    }

    func testDoesNotIncludeCurrentIndex() {
        let result = CarouselPrefetch.indicesToPrefetch(around: 2, count: 5, radius: 2)
        XCTAssertFalse(result.contains(2))
    }

    func testSingleItemListReturnsEmpty() {
        XCTAssertEqual(CarouselPrefetch.indicesToPrefetch(around: 0, count: 1, radius: 2), [])
    }
}
