import XCTest
@testable import PortyMcFolio

@MainActor
final class ProjectFileOpsTests: XCTestCase {
    var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectFileOpsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Restore permissions in case a test chmod'd the folder.
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempRoot.path)
        try? FileManager.default.removeItem(at: tempRoot)
    }

    // Helper: materialize a minimal project on disk with a given teaser/body.
    private func makeProject(
        uid: String = "abcd1234",
        year: Int = 2025,
        teaser: String = "",
        body: String = "# Title\n\nBody"
    ) throws -> Project {
        let folderName = "\(year)_test_\(uid)"
        let folderURL = tempRoot.appendingPathComponent(folderName)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let parsed = ParsedFrontmatter(
            title: "Test",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            tags: [],
            client: "",
            status: .empty,
            body: body,
            teaser: teaser
        )
        let content = FrontmatterParser.serialize(frontmatter: parsed)
        let mdURL = folderURL.appendingPathComponent("\(folderName).md")
        try content.write(to: mdURL, atomically: true, encoding: .utf8)
        return Project(
            uid: uid,
            year: year,
            folderName: folderName,
            folderURL: folderURL,
            title: "Test",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            tags: [],
            client: "",
            status: .empty,
            body: body,
            teaser: teaser
        )
    }

    func testReturnsFalseWhenNoReferencesMatch() throws {
        let project = try makeProject(teaser: "other.jpg", body: "# X\n\n![[unrelated.png]]")
        let changed = try ProjectFileOps.updateReferences(in: project, from: "hero.jpg", to: "cover.jpg")
        XCTAssertFalse(changed)
    }

    func testRewritesTeaserAndReturnsTrue() throws {
        let project = try makeProject(teaser: "hero.jpg")
        let changed = try ProjectFileOps.updateReferences(in: project, from: "hero.jpg", to: "cover.jpg")
        XCTAssertTrue(changed)
        let updated = try String(contentsOf: project.readmeURL, encoding: .utf8)
        let parsed = try FrontmatterParser.parse(updated)
        XCTAssertEqual(parsed.teaser, "cover.jpg")
    }

    func testRewritesBodyEmbedAndReturnsTrue() throws {
        let project = try makeProject(body: "# X\n\n![[hero.jpg]]\n")
        let changed = try ProjectFileOps.updateReferences(in: project, from: "hero.jpg", to: "cover.jpg")
        XCTAssertTrue(changed)
        let updated = try String(contentsOf: project.readmeURL, encoding: .utf8)
        XCTAssertTrue(updated.contains("![[cover.jpg]]"))
        XCTAssertFalse(updated.contains("![[hero.jpg]]"))
    }

    func testThrowsWhenReadmeUnreadable() throws {
        let project = try makeProject(teaser: "hero.jpg")
        // Remove the folder on disk; the read will throw.
        try FileManager.default.removeItem(at: project.folderURL)
        XCTAssertThrowsError(
            try ProjectFileOps.updateReferences(in: project, from: "hero.jpg", to: "cover.jpg")
        )
    }
}
