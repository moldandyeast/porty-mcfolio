import XCTest
@testable import PortyMcFolio

final class LinkItemTests: XCTestCase {
    func testParseLinkMarkdown() throws {
        let md = """
        ---
        type: link
        url: "https://dribbble.com/shots/12345"
        title: "Dribbble — Final Concepts"
        annotation: "Client loved option B"
        date: 2025-03-15
        ---
        """
        let link = try LinkItem.parse(markdown: md)
        XCTAssertEqual(link.url.absoluteString, "https://dribbble.com/shots/12345")
        XCTAssertEqual(link.title, "Dribbble — Final Concepts")
        XCTAssertEqual(link.annotation, "Client loved option B")
    }

    func testLinkFileName() {
        let name = LinkItem.fileName(uid: "b2c4d6e8")
        XCTAssertEqual(name, "link-b2c4d6e8.md")
    }

    func testSerializeLinkMarkdown() throws {
        let link = LinkItem(
            uid: "b2c4d6e8",
            url: URL(string: "https://example.com")!,
            title: "Example",
            annotation: "A test link",
            date: ISO8601DateFormatter().date(from: "2025-03-15T00:00:00Z")!
        )
        let md = link.toMarkdown()
        XCTAssertTrue(md.contains("type: link"))
        XCTAssertTrue(md.contains("url: \"https://example.com\""))
        XCTAssertTrue(md.contains("title: \"Example\""))
        XCTAssertTrue(md.contains("annotation: \"A test link\""))
    }

    func testIsLinkFile() {
        XCTAssertTrue(LinkItem.isLinkFile(name: "link-a3f1b2c4.md"))
        XCTAssertFalse(LinkItem.isLinkFile(name: "README.md"))
        XCTAssertFalse(LinkItem.isLinkFile(name: "link-short.md"))
    }
}
