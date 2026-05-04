import XCTest
@testable import PortyMcFolio

final class ImageThumbnailTests: XCTestCase {

    func testSVGLoadsViaNSImageBypass() async throws {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
          <rect width="100" height="100" fill="red"/>
        </svg>
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).svg")
        try svg.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let image = await ImageThumbnail.load(url: url, size: CGSize(width: 100, height: 100))
        XCTAssertNotNil(image, "SVG should load via NSImage(contentsOf:) bypass")
        XCTAssertGreaterThan(image?.size.width ?? 0, 0)
    }

    func testNonExistentFileReturnsNil() async {
        let url = URL(fileURLWithPath: "/tmp/definitely-does-not-exist-\(UUID().uuidString).png")
        let image = await ImageThumbnail.load(url: url, size: CGSize(width: 100, height: 100))
        XCTAssertNil(image)
    }
}
