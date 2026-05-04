import XCTest
@testable import PortyMcFolio

final class LinkURLNormalizationTests: XCTestCase {
    func testBareDomainGetsHttpsPrefix() {
        let url = LinkItem.normalizeURL("example.com")
        XCTAssertEqual(url?.absoluteString, "https://example.com")
    }

    func testHttpsURLPassesThrough() {
        let url = LinkItem.normalizeURL("https://example.com/path?q=1")
        XCTAssertEqual(url?.absoluteString, "https://example.com/path?q=1")
    }

    func testHttpURLPassesThrough() {
        let url = LinkItem.normalizeURL("http://example.com")
        XCTAssertEqual(url?.absoluteString, "http://example.com")
    }

    func testFtpURLPassesThrough() {
        // normalizeURL returns the URL as-is; scheme filtering is the caller's job.
        let url = LinkItem.normalizeURL("ftp://example.com")
        XCTAssertEqual(url?.absoluteString, "ftp://example.com")
    }

    func testLeadingAndTrailingWhitespaceTrimmed() {
        let url = LinkItem.normalizeURL("   https://example.com  ")
        XCTAssertEqual(url?.absoluteString, "https://example.com")
    }

    func testEmptyStringReturnsNil() {
        XCTAssertNil(LinkItem.normalizeURL(""))
        XCTAssertNil(LinkItem.normalizeURL("   "))
    }
}
