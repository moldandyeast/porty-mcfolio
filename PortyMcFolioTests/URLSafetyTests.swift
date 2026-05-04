import XCTest
@testable import PortyMcFolio

final class URLSafetyTests: XCTestCase {
    func testHTTPIsSafe() {
        XCTAssertTrue(URL(string: "http://example.com")!.isSafeExternalScheme)
    }

    func testHTTPSIsSafe() {
        XCTAssertTrue(URL(string: "https://example.com/path?q=1")!.isSafeExternalScheme)
    }

    func testMailtoIsSafe() {
        XCTAssertTrue(URL(string: "mailto:foo@example.com")!.isSafeExternalScheme)
    }

    func testSchemeIsCaseInsensitive() {
        XCTAssertTrue(URL(string: "HTTPS://example.com")!.isSafeExternalScheme)
        XCTAssertTrue(URL(string: "Http://example.com")!.isSafeExternalScheme)
    }

    func testFileSchemeRejected() {
        XCTAssertFalse(URL(string: "file:///etc/passwd")!.isSafeExternalScheme)
    }

    func testJavascriptSchemeRejected() {
        XCTAssertFalse(URL(string: "javascript:alert(1)")!.isSafeExternalScheme)
    }

    func testDataSchemeRejected() {
        XCTAssertFalse(URL(string: "data:text/html,<script>alert(1)</script>")!.isSafeExternalScheme)
    }

    func testAboutSchemeRejected() {
        XCTAssertFalse(URL(string: "about:blank")!.isSafeExternalScheme)
    }

    func testFTPSchemeRejected() {
        // Conservative allowlist — FTP not included even though benign.
        XCTAssertFalse(URL(string: "ftp://example.com/file.txt")!.isSafeExternalScheme)
    }

    func testCustomSchemeRejected() {
        XCTAssertFalse(URL(string: "portymcfolio://file/foo.png")!.isSafeExternalScheme)
    }
}
