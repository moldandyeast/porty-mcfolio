import XCTest
@testable import PortyMcFolio

/// Tests for the exported HTML document that users ship to browsers.
/// Because the export can contain user-authored markdown that embeds raw
/// HTML, the output MUST sanitize via DOMPurify — marked.parse() alone
/// would pass <script> tags straight through.
final class MarkdownExportHTMLTests: XCTestCase {
    private let dummyCSS = "<style>body{color:#000}</style>"
    private let dummyMarkedJS = "/* marked */"
    private let dummyPurifyJS = "/* purify */"

    func testOutputEmbedsPurifyScript() {
        let html = MarkdownPreviewView.buildExportHTML(
            title: "t",
            processedMd: "hello",
            css: dummyCSS,
            markedJS: dummyMarkedJS,
            purifyJS: dummyPurifyJS
        )
        XCTAssertTrue(html.contains(dummyPurifyJS), "Export must inline DOMPurify so sanitize runs in the browser.")
    }

    func testOutputSanitizesMarkedOutput() {
        let html = MarkdownPreviewView.buildExportHTML(
            title: "t",
            processedMd: "hello",
            css: dummyCSS,
            markedJS: dummyMarkedJS,
            purifyJS: dummyPurifyJS
        )
        // The exact call shape is `DOMPurify.sanitize(marked.parse(...))`.
        // A plain `marked.parse(...).innerHTML = ...` would ship XSS.
        XCTAssertTrue(
            html.contains("DOMPurify.sanitize(marked.parse("),
            "Export must wrap marked.parse output in DOMPurify.sanitize."
        )
    }

    func testTitleIsHTMLEscaped() {
        let html = MarkdownPreviewView.buildExportHTML(
            title: "<script>alert(1)</script>",
            processedMd: "hello",
            css: dummyCSS,
            markedJS: dummyMarkedJS,
            purifyJS: dummyPurifyJS
        )
        XCTAssertFalse(html.contains("<script>alert(1)</script>"), "Raw title must not land in <title>.")
        XCTAssertTrue(html.contains("&lt;script&gt;"), "Title must be HTML-escaped.")
    }

    func testMarkdownIsPassedAsJSONNotInlineInterpolation() {
        // The markdown is user-controlled; it must be JSON-encoded into the
        // JS string, not pasted into a template literal, or a `"` breaks out.
        let html = MarkdownPreviewView.buildExportHTML(
            title: "t",
            processedMd: "a \"quote\" and a \\backslash",
            css: dummyCSS,
            markedJS: dummyMarkedJS,
            purifyJS: dummyPurifyJS
        )
        // The raw markdown with unescaped quotes must NOT appear verbatim.
        XCTAssertFalse(html.contains("a \"quote\""), "Raw markdown quotes must be JSON-escaped before being placed in JS.")
    }
}
