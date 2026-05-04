import XCTest
import AppKit
@testable import PortyMcFolio

final class ThemeCSSTests: XCTestCase {
    private let aqua = NSAppearance(named: .aqua)!
    private let darkAqua = NSAppearance(named: .darkAqua)!

    private let expectedVars = [
        "--color-background",
        "--color-background-alt",
        "--color-surface",
        "--color-surface-hover",
        "--color-text-primary",
        "--color-text-secondary",
        "--color-text-tertiary",
        "--color-border",
        "--color-accent",
        "--color-status-draft",
        "--color-status-active",
        "--color-status-complete",
        "--color-status-archived",
        "--color-error",
    ]

    func testPortyCSSContainsAllVariables() {
        let css = Theme.porty.cssVariables(appearance: aqua)
        for name in expectedVars {
            XCTAssertTrue(css.contains(name), "missing \(name) in Porty CSS")
        }
    }

    func testOSXCSSContainsAllVariables() {
        let css = Theme.osx.cssVariables(appearance: darkAqua)
        for name in expectedVars {
            XCTAssertTrue(css.contains(name), "missing \(name) in OSX CSS")
        }
    }

    func testBWCSSContainsAllVariables() {
        let css = Theme.bw.cssVariables(appearance: aqua)
        for name in expectedVars {
            XCTAssertTrue(css.contains(name), "missing \(name) in BW CSS")
        }
    }

    func testPortyLightBackgroundHexInCSS() {
        let css = Theme.porty.cssVariables(appearance: aqua)
        XCTAssertTrue(css.contains("--color-background: #F3F4F6"),
                      "expected Porty light background hex in CSS, got:\n\(css)")
    }

    func testPortyDarkBackgroundHexInCSS() {
        let css = Theme.porty.cssVariables(appearance: darkAqua)
        XCTAssertTrue(css.contains("--color-background: #14161B"),
                      "expected Porty dark background hex in CSS, got:\n\(css)")
    }

    func testCSSStartsWithRootSelector() {
        let css = Theme.porty.cssVariables(appearance: aqua)
        XCTAssertTrue(css.contains(":root"),
                      "expected `:root` selector in CSS, got:\n\(css)")
    }
}
