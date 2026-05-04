import XCTest
@testable import PortyMcFolio

final class ProjectTemplateTests: XCTestCase {

    func testTitleSubstitution() {
        let out = ProjectTemplate.render(
            "# {{title}}",
            title: "Hello",
            year: 2026,
            client: "",
            tags: [],
            date: Date()
        )
        XCTAssertEqual(out, "# Hello")
    }

    func testYearSubstitution() {
        let out = ProjectTemplate.render(
            "({{year}})",
            title: "",
            year: 2026,
            client: "",
            tags: [],
            date: Date()
        )
        XCTAssertEqual(out, "(2026)")
    }

    func testClientSubstitution() {
        let out = ProjectTemplate.render(
            "Client: {{client}}",
            title: "",
            year: 2026,
            client: "Acme",
            tags: [],
            date: Date()
        )
        XCTAssertEqual(out, "Client: Acme")
    }

    func testClientEmptyInsertsEmpty() {
        let out = ProjectTemplate.render(
            "Client: {{client}}",
            title: "",
            year: 2026,
            client: "",
            tags: [],
            date: Date()
        )
        XCTAssertEqual(out, "Client: ")
    }

    func testTagsMultipleJoinWithCommaSpace() {
        let out = ProjectTemplate.render(
            "{{tags}}",
            title: "",
            year: 2026,
            client: "",
            tags: ["design", "branding"],
            date: Date()
        )
        XCTAssertEqual(out, "design, branding")
    }

    func testTagsSingleNoTrailingComma() {
        let out = ProjectTemplate.render(
            "{{tags}}",
            title: "",
            year: 2026,
            client: "",
            tags: ["design"],
            date: Date()
        )
        XCTAssertEqual(out, "design")
    }

    func testTagsEmptyInsertsEmpty() {
        let out = ProjectTemplate.render(
            "Tags: {{tags}}",
            title: "",
            year: 2026,
            client: "",
            tags: [],
            date: Date()
        )
        XCTAssertEqual(out, "Tags: ")
    }

    func testDateISO8601() {
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 22
        components.hour = 12
        let date = Calendar.current.date(from: components)!

        let out = ProjectTemplate.render(
            "{{date}}",
            title: "",
            year: 2026,
            client: "",
            tags: [],
            date: date
        )
        XCTAssertEqual(out, "2026-04-22")
    }

    func testUnknownPlaceholderPreservedLiterally() {
        let out = ProjectTemplate.render(
            "{{titel}}",
            title: "Hello",
            year: 2026,
            client: "",
            tags: [],
            date: Date()
        )
        XCTAssertEqual(out, "{{titel}}")
    }

    func testNoPlaceholdersReturnedVerbatim() {
        let input = "Just prose.\nTwo lines."
        let out = ProjectTemplate.render(
            input,
            title: "Hello",
            year: 2026,
            client: "Acme",
            tags: ["x"],
            date: Date()
        )
        XCTAssertEqual(out, input)
    }

    func testAllVariablesTogether() {
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 22
        components.hour = 12
        let date = Calendar.current.date(from: components)!

        let template = "# {{title}} ({{year}})\nClient: {{client}}\nTags: {{tags}}\nCreated: {{date}}"
        let out = ProjectTemplate.render(
            template,
            title: "Hello",
            year: 2026,
            client: "Acme",
            tags: ["design", "branding"],
            date: date
        )
        XCTAssertEqual(
            out,
            "# Hello (2026)\nClient: Acme\nTags: design, branding\nCreated: 2026-04-22"
        )
    }
}
