import XCTest
@testable import PortyMcFolio

final class ProjectCreatorTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testCreateProject() throws {
        let project = try ProjectCreator.create(
            title: "Brand Identity — Acme",
            client: "Acme Corp",
            tags: ["branding", "identity"],
            rootURL: tempDir,
            body: "# Brand Identity — Acme\n\nProject description here."
        )

        // Folder exists
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: project.folderURL.path, isDirectory: &isDir
        ))
        XCTAssertTrue(isDir.boolValue)

        // README.md exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.readmeURL.path))

        // Folder name matches pattern
        let name = project.folderName
        let year = Calendar.current.component(.year, from: Date())
        XCTAssertTrue(name.hasPrefix("\(year)_brand_identity"))
        XCTAssertEqual(project.uid.count, 8)

        // README content is valid
        let content = try String(contentsOf: project.readmeURL, encoding: .utf8)
        let parsed = try FrontmatterParser.parse(content)
        XCTAssertEqual(parsed.title, "Brand Identity — Acme")
        XCTAssertEqual(parsed.client, "Acme Corp")
        XCTAssertEqual(parsed.tags, ["branding", "identity"])
        XCTAssertEqual(parsed.status, .empty)
    }

    func testCreateProjectSlugsName() throws {
        let project = try ProjectCreator.create(
            title: "My Cool Project!!!",
            client: "",
            tags: [],
            rootURL: tempDir,
            body: ""
        )
        XCTAssertTrue(project.folderName.contains("my_cool_project"))
    }

    func testCreateProjectWritesPassedBodyVerbatim() throws {
        let project = try ProjectCreator.create(
            title: "Templated",
            client: "",
            tags: [],
            rootURL: tempDir,
            body: "# Templated\n\nHello {{irrelevant}}"
        )

        let content = try String(contentsOf: project.readmeURL, encoding: .utf8)
        let parsed = try FrontmatterParser.parse(content)

        // ProjectCreator is a pass-through — no substitution happens inside it.
        XCTAssertEqual(parsed.body, "# Templated\n\nHello {{irrelevant}}")
    }

    func testCreateProjectUsesInjectedDate() throws {
        let fixedDate = Date(timeIntervalSince1970: 1_000_000_000) // 2001-09-09 01:46:40 UTC

        let project = try ProjectCreator.create(
            title: "Date Injection",
            client: "",
            tags: [],
            rootURL: tempDir,
            body: "",
            date: fixedDate
        )

        let content = try String(contentsOf: project.readmeURL, encoding: .utf8)
        let parsed = try FrontmatterParser.parse(content)

        // The frontmatter serializer truncates to full-date ISO-8601 (YYYY-MM-DD,
        // interpreted as UTC midnight on round-trip). Compare on that basis so we
        // verify the injected `date:` is what lands in frontmatter without
        // asserting sub-day precision the format can't carry.
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        XCTAssertEqual(iso.string(from: parsed.date), iso.string(from: fixedDate))
    }
}
