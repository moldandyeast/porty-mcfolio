import XCTest
import SwiftUI
import AppKit
@testable import PortyMcFolio

final class ThemeTests: XCTestCase {
    private let aqua = NSAppearance(named: .aqua)!
    private let darkAqua = NSAppearance(named: .darkAqua)!

    // MARK: Identity

    func testNamedRoundTrip() {
        XCTAssertEqual(Theme.named(.porty).id, .porty)
        XCTAssertEqual(Theme.named(.osx).id, .osx)
        XCTAssertEqual(Theme.named(.bw).id, .bw)
    }

    func testAllEnumerates() {
        XCTAssertEqual(Theme.all.map(\.id), [.porty, .osx, .bw])
    }

    func testNamesAreHumanReadable() {
        XCTAssertEqual(Theme.porty.name, "Porty")
        XCTAssertEqual(Theme.osx.name, "OSX")
        XCTAssertEqual(Theme.bw.name, "BW")
    }

    // MARK: Porty — cool white · mauve accent

    func testPortyAccentIsMauve() {
        XCTAssertEqual(Theme.porty.colors.accent.hex(for: aqua), "#B34778")
        XCTAssertEqual(Theme.porty.colors.accent.hex(for: darkAqua), "#C8628F")
    }

    func testPortyLightBackground() {
        XCTAssertEqual(Theme.porty.colors.background.hex(for: aqua), "#F3F4F6")
    }

    func testPortyDarkBackground() {
        XCTAssertEqual(Theme.porty.colors.background.hex(for: darkAqua), "#14161B")
    }

    func testPortyGrainOpacity() {
        XCTAssertEqual(Theme.porty.grainOpacity, 0.03, accuracy: 0.0001)
    }

    // MARK: OSX — warm white · mauve accent (shared brand with Porty)

    func testOSXAccentMatchesPortyMauve() {
        // The brand accent is shared across Porty and OSX. BW suppresses it.
        XCTAssertEqual(Theme.osx.colors.accent.hex(for: aqua), "#B34778")
        XCTAssertEqual(Theme.osx.colors.accent.hex(for: darkAqua), "#C8628F")
    }

    func testOSXLightBackgroundIsWarmNearWhite() {
        XCTAssertEqual(Theme.osx.colors.background.hex(for: aqua), "#FBFAF7")
    }

    func testOSXDarkBackgroundIsWarmNearBlack() {
        XCTAssertEqual(Theme.osx.colors.background.hex(for: darkAqua), "#171613")
    }

    func testOSXGrainOpacity() {
        XCTAssertEqual(Theme.osx.grainOpacity, 0.0, accuracy: 0.0001)
    }

    // MARK: BW — neutral with whisper of cool · monochrome accent

    func testBWLightBackgroundIsOffWhiteNotPureWhite() {
        // New BW is intentionally NOT pure white — there's a 1-2 unit cool
        // bias (B ≥ G ≥ R) so the theme reads as neutral but breathes slightly
        // cool in context.
        XCTAssertEqual(Theme.bw.colors.background.hex(for: aqua), "#F5F6F7")
    }

    func testBWDarkBackgroundIsOffBlackNotPureBlack() {
        XCTAssertEqual(Theme.bw.colors.background.hex(for: darkAqua), "#16171A")
    }

    func testBWAccentIsMonochromeNotMauve() {
        // BW is the art-first mode — brand mauve is deliberately dropped so
        // content doesn't compete with chrome chroma.
        XCTAssertEqual(Theme.bw.colors.accent.hex(for: aqua), "#2A2B2D")
        XCTAssertEqual(Theme.bw.colors.accent.hex(for: darkAqua), "#D4D5D8")
    }

    func testBWSurfacesNeverWarmDrift() {
        // Each non-accent BW color should be cool-biased or neutral
        // (B ≥ R). Guards against future drift into warm territory —
        // warm is OSX's job, BW stays at-or-past neutral toward cool.
        let bw = Theme.bw.colors
        let neutrals: [Color] = [
            bw.background, bw.backgroundAlt, bw.surface, bw.surfaceHover,
            bw.textPrimary, bw.textSecondary, bw.textTertiary, bw.border,
        ]
        for color in neutrals {
            for app in [aqua, darkAqua] {
                let hex = color.hex(for: app)
                guard hex.count == 7 else {
                    XCTFail("unexpected hex shape: \(hex)")
                    continue
                }
                let r = Int(hex[hex.index(hex.startIndex, offsetBy: 1)..<hex.index(hex.startIndex, offsetBy: 3)], radix: 16) ?? 0
                let b = Int(hex[hex.index(hex.startIndex, offsetBy: 5)..<hex.index(hex.startIndex, offsetBy: 7)], radix: 16) ?? 0
                XCTAssertGreaterThanOrEqual(b, r, "BW surface \(hex) drifted warm (B < R)")
            }
        }
    }
}
