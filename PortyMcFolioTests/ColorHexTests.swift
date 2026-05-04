import XCTest
import SwiftUI
import AppKit
@testable import PortyMcFolio

final class ColorHexTests: XCTestCase {
    private let aqua = NSAppearance(named: .aqua)!
    private let darkAqua = NSAppearance(named: .darkAqua)!

    func testStaticColorResolvesToHex() {
        let white = Color.white
        XCTAssertEqual(white.hex(for: aqua), "#FFFFFF")
    }

    func testBlackResolvesToHex() {
        XCTAssertEqual(Color.black.hex(for: aqua), "#000000")
    }

    func testDynamicColorPicksLightUnderAqua() {
        let c = Color(light: Color(hex: "112233"), dark: Color(hex: "AABBCC"))
        XCTAssertEqual(c.hex(for: aqua), "#112233")
    }

    func testDynamicColorPicksDarkUnderDarkAqua() {
        let c = Color(light: Color(hex: "112233"), dark: Color(hex: "AABBCC"))
        XCTAssertEqual(c.hex(for: darkAqua), "#AABBCC")
    }

    func testRoundsComponents() {
        // Component 0.501 must round to 128 (0x80), not 127.
        let c = Color(red: 0.501, green: 0.501, blue: 0.501)
        XCTAssertEqual(c.hex(for: aqua), "#808080")
    }
}
