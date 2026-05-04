import XCTest
@testable import PortyMcFolio

final class UIDTests: XCTestCase {
    func testGenerateReturnsEightHexCharacters() {
        for _ in 0..<100 {
            let uid = UID.generate()
            XCTAssertEqual(uid.count, 8, "uid should be 8 chars, got '\(uid)'")
            XCTAssertTrue(
                uid.allSatisfy { $0.isHexDigit },
                "uid should be hex, got '\(uid)'"
            )
        }
    }

    func testGenerateIsReasonablyUnique() {
        // Guards against the degenerate-zeroed case: if SecRandomCopyBytes
        // ever fails silently, the old code returned "00000000" for every call.
        var seen = Set<String>()
        for _ in 0..<100 { seen.insert(UID.generate()) }
        XCTAssertGreaterThan(seen.count, 90, "expected high entropy, got \(seen.count) unique out of 100")
    }

    func testFallbackHexIsEightLowercaseHexCharacters() {
        let hex = UID.fallbackHex()
        XCTAssertEqual(hex.count, 8)
        let hexSet = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(hex.unicodeScalars.allSatisfy { hexSet.contains($0) })
    }

    func testFallbackHexIsUnique() {
        // UUID-derived fallback must not collide across rapid calls.
        var seen = Set<String>()
        for _ in 0..<50 {
            seen.insert(UID.fallbackHex())
        }
        XCTAssertGreaterThan(seen.count, 40, "fallbackHex should produce mostly-unique values")
    }

    func testSecureRandomHexReturnsEightHexOrNil() {
        if let hex = UID.secureRandomHex() {
            XCTAssertEqual(hex.count, 8)
            let hexSet = CharacterSet(charactersIn: "0123456789abcdef")
            XCTAssertTrue(hex.unicodeScalars.allSatisfy { hexSet.contains($0) })
        }
        // If SecRandomCopyBytes returns nil on this environment, the test still passes
        // — we're asserting a shape contract, not that it always succeeds.
    }
}
