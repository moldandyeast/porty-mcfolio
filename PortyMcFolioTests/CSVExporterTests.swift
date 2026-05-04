import XCTest
@testable import PortyMcFolio

final class CSVExporterTests: XCTestCase {

    // MARK: - escape(_:)

    func testEscape_plainStringIsUnchanged() {
        XCTAssertEqual(CSVExporter.escape("hello"), "hello")
    }

    func testEscape_commaIsQuoted() {
        XCTAssertEqual(CSVExporter.escape("Dango, Grug"), "\"Dango, Grug\"")
    }

    func testEscape_quoteIsDoubledAndWrapped() {
        // Input:  Concept "PostBox"
        // Output: "Concept ""PostBox"""
        XCTAssertEqual(
            CSVExporter.escape("Concept \"PostBox\""),
            "\"Concept \"\"PostBox\"\"\""
        )
    }

    func testEscape_newlineIsQuoted() {
        XCTAssertEqual(CSVExporter.escape("line1\nline2"), "\"line1\nline2\"")
    }

    func testEscape_carriageReturnIsQuoted() {
        XCTAssertEqual(CSVExporter.escape("a\rb"), "\"a\rb\"")
    }

    func testEscape_emptyStringStaysEmpty() {
        // Empty must stay empty — NOT the two-character `""`
        XCTAssertEqual(CSVExporter.escape(""), "")
    }

    // MARK: - csv(for:) helpers

    private func makeProject(
        uid: String = "abcd1234",
        year: Int = 2025,
        title: String = "Test",
        client: String = "ACME",
        status: ProjectStatus = .empty,
        tags: [String] = []
    ) -> Project {
        Project(
            uid: uid,
            year: year,
            folderName: "\(year)_test_\(uid)",
            folderURL: URL(fileURLWithPath: "/tmp/\(year)_test_\(uid)"),
            title: title,
            date: Date(timeIntervalSince1970: 0),
            tags: tags,
            client: client,
            status: status,
            body: "",
            teaser: ""
        )
    }

    // MARK: - csv(for:)

    func testCSV_startsWithBOM() {
        let csv = CSVExporter.csv(for: [])
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"), "CSV should start with UTF-8 BOM")
    }

    func testCSV_headerOrderIsFixed() {
        let csv = CSVExporter.csv(for: [])
        XCTAssertTrue(
            csv.hasPrefix("\u{FEFF}Year,Title,Client,Status,Tags\r\n"),
            "Expected BOM + fixed header followed by CRLF, got: \(csv.debugDescription)"
        )
    }

    func testCSV_emptyProjectsListReturnsHeaderOnly() {
        let csv = CSVExporter.csv(for: [])
        XCTAssertEqual(csv, "\u{FEFF}Year,Title,Client,Status,Tags\r\n")
    }

    func testCSV_usesCRLFBetweenRows() {
        let projects = [
            makeProject(year: 2025, title: "A", client: "X"),
            makeProject(uid: "ffff0000", year: 2024, title: "B", client: "Y"),
        ]
        let csv = CSVExporter.csv(for: projects)
        // Two data rows + header = 3 CRLFs (one after each)
        let crlfCount = csv.components(separatedBy: "\r\n").count - 1
        XCTAssertEqual(crlfCount, 3)
    }

    func testCSV_endsWithTrailingCRLF() {
        let projects = [makeProject(title: "Only")]
        let csv = CSVExporter.csv(for: projects)
        XCTAssertTrue(csv.hasSuffix("\r\n"))
    }

    func testCSV_tagsAreSemicolonJoined() {
        let projects = [makeProject(title: "T", tags: ["A", "B", "C"])]
        let csv = CSVExporter.csv(for: projects)
        XCTAssertTrue(csv.contains("A; B; C"), "Got: \(csv)")
    }

    func testCSV_emptyTagsProduceEmptyCell() {
        let projects = [makeProject(title: "T", tags: [])]
        let csv = CSVExporter.csv(for: projects)
        // Last column is tags — line should end with a comma then CRLF
        XCTAssertTrue(csv.contains(",\r\n"), "Got: \(csv)")
    }

    func testCSV_statusUsesDisplayName() {
        let projects = [makeProject(title: "T", status: .inProgress)]
        let csv = CSVExporter.csv(for: projects)
        XCTAssertTrue(csv.contains(",In Progress,"), "Got: \(csv)")
        XCTAssertFalse(csv.contains("inProgress"), "rawValue should not appear")
    }

    func testCSV_titleWithCommaAndQuoteIsEscaped() {
        // Title:  Hello, "world"
        // Cell:   "Hello, ""world"""
        let projects = [makeProject(title: "Hello, \"world\"")]
        let csv = CSVExporter.csv(for: projects)
        XCTAssertTrue(
            csv.contains("\"Hello, \"\"world\"\"\""),
            "Expected escaped title in output, got: \(csv)"
        )
    }

    func testCSV_yearIsNotQuoted() {
        let projects = [makeProject(year: 2026, title: "X", client: "Y")]
        let csv = CSVExporter.csv(for: projects)
        // Row should start with `2026,` (no quotes around the year)
        XCTAssertTrue(csv.contains("\r\n2026,X,Y,Empty,\r\n"), "Got: \(csv)")
    }

    func testCSV_emptyTitleEmitsEmptyCell_notUntitled() {
        let projects = [makeProject(title: "", client: "C")]
        let csv = CSVExporter.csv(for: projects)
        // Title cell is empty, so we should see `,,C,` in the row
        XCTAssertTrue(csv.contains(",,C,"), "Got: \(csv)")
        XCTAssertFalse(csv.contains("Untitled"), "CSV must export raw value, not display fallback")
    }
}
