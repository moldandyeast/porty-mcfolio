// PortyMcFolioTests/DragPayloadTests.swift
import XCTest
@testable import PortyMcFolio

final class DragPayloadTests: XCTestCase {
    func testEncodeDecodeSingleURL() throws {
        let urls = [URL(fileURLWithPath: "/a.png")]
        let data = try DragPayload.encode(urls: urls)
        let decoded = try DragPayload.decode(data: data)
        XCTAssertEqual(decoded, urls)
    }

    func testEncodeDecodeMultipleURLs() throws {
        let urls = [
            URL(fileURLWithPath: "/a.png"),
            URL(fileURLWithPath: "/sub/b.png"),
            URL(fileURLWithPath: "/c"),
        ]
        let data = try DragPayload.encode(urls: urls)
        let decoded = try DragPayload.decode(data: data)
        XCTAssertEqual(decoded, urls)
    }

    func testDecodeRejectsMalformed() {
        let junk = Data([0xff, 0xfe, 0xfd])
        XCTAssertThrowsError(try DragPayload.decode(data: junk))
    }
}
