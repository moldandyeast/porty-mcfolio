import XCTest
@testable import PortyMcFolio

final class FrontmatterFolderRenameTests: XCTestCase {

    // MARK: - Disk fixture support (used by atomic-rename safety tests only)

    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrontmatterFolderRenameTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Restore permissions in case a test chmod'd the parent directory.
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempRoot.path)
        try? FileManager.default.removeItem(at: tempRoot)
        try super.tearDownWithError()
    }

    /// Materialise a minimal project on disk and return (appState, project).
    /// The AppState has its portfolioRootURL set to tempRoot but no reconciler,
    /// which is fine — projectFolderRenamed / notifyProjectFileChanged are nil-safe.
    @MainActor
    private func makeProjectOnDisk(
        title: String,
        year: Int,
        uid: String
    ) throws -> (AppState, Project) {
        let folderName = Project.folderName(title: title, year: year, uid: uid)
        let folderURL = tempRoot.appendingPathComponent(folderName)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let parsed = ParsedFrontmatter(
            title: title,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            tags: [],
            client: "",
            status: .empty,
            body: "",
            teaser: "",
            favorites: [],
            hidden: false
        )
        let content = FrontmatterParser.serialize(frontmatter: parsed)
        let mdURL = folderURL.appendingPathComponent("\(folderName).md")
        try content.write(to: mdURL, atomically: true, encoding: .utf8)

        let project = Project(
            uid: uid,
            year: year,
            folderName: folderName,
            folderURL: folderURL,
            title: title,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            tags: [],
            client: "",
            status: .empty,
            body: "",
            teaser: ""
        )

        let appState = AppState()
        appState.portfolioRootURL = tempRoot
        return (appState, project)
    }

    private func makeFrontmatter(
        body: String = "",
        teaser: String = "",
        favorites: [String] = []
    ) -> ParsedFrontmatter {
        ParsedFrontmatter(
            title: "T",
            date: Date(),
            tags: [],
            client: "",
            status: .empty,
            body: body,
            teaser: teaser,
            favorites: favorites,
            hidden: false
        )
    }

    func testNoReferencesReturnsUnchanged() {
        let fm = makeFrontmatter(body: "Hello world", teaser: "other/cover.png", favorites: ["other/a.png"])
        let (out, changed) = FrontmatterParser.rewritingFolderRename(
            in: fm,
            from: "photos",
            to: "images"
        )
        XCTAssertFalse(changed)
        XCTAssertEqual(out.body, "Hello world")
        XCTAssertEqual(out.teaser, "other/cover.png")
        XCTAssertEqual(out.favorites, ["other/a.png"])
    }

    func testBodyEmbedReferencesAreRewritten() {
        let fm = makeFrontmatter(body: "Before\n![[photos/a.png]]\nAfter\n![[photos/nested/b.jpg]]")
        let (out, changed) = FrontmatterParser.rewritingFolderRename(
            in: fm,
            from: "photos",
            to: "images"
        )
        XCTAssertTrue(changed)
        XCTAssertEqual(out.body, "Before\n![[images/a.png]]\nAfter\n![[images/nested/b.jpg]]")
    }

    func testTeaserPrefixIsRewritten() {
        let fm = makeFrontmatter(teaser: "photos/cover.png")
        let (out, changed) = FrontmatterParser.rewritingFolderRename(
            in: fm,
            from: "photos",
            to: "images"
        )
        XCTAssertTrue(changed)
        XCTAssertEqual(out.teaser, "images/cover.png")
    }

    func testTeaserThatMergesSubstringButIsNotPrefixStaysUnchanged() {
        // "other-photos/cover.png" should NOT match prefix "photos"
        let fm = makeFrontmatter(teaser: "other-photos/cover.png")
        let (out, changed) = FrontmatterParser.rewritingFolderRename(
            in: fm,
            from: "photos",
            to: "images"
        )
        XCTAssertFalse(changed)
        XCTAssertEqual(out.teaser, "other-photos/cover.png")
    }

    func testFavoritesWithPrefixAreRewritten() {
        let fm = makeFrontmatter(favorites: ["photos/a.png", "other/b.png", "photos/nested/c.jpg"])
        let (out, changed) = FrontmatterParser.rewritingFolderRename(
            in: fm,
            from: "photos",
            to: "images"
        )
        XCTAssertTrue(changed)
        XCTAssertEqual(out.favorites, ["images/a.png", "other/b.png", "images/nested/c.jpg"])
    }

    func testMultipleSimultaneousChangesAllApplied() {
        let fm = makeFrontmatter(
            body: "![[photos/a.png]]",
            teaser: "photos/cover.png",
            favorites: ["photos/d.png"]
        )
        let (out, changed) = FrontmatterParser.rewritingFolderRename(
            in: fm,
            from: "photos",
            to: "images"
        )
        XCTAssertTrue(changed)
        XCTAssertEqual(out.body, "![[images/a.png]]")
        XCTAssertEqual(out.teaser, "images/cover.png")
        XCTAssertEqual(out.favorites, ["images/d.png"])
    }

    func testSimilarNameNotMisreplaced() {
        // Body contains "photos2/" — should not match "photos" prefix after "![[".
        let fm = makeFrontmatter(body: "![[photos2/a.png]]")
        let (out, changed) = FrontmatterParser.rewritingFolderRename(
            in: fm,
            from: "photos",
            to: "images"
        )
        XCTAssertFalse(changed)
        XCTAssertEqual(out.body, "![[photos2/a.png]]")
    }

    // MARK: - Atomic rename safety

    @MainActor
    func testWhenEndYearChange_renamesFolderToDerivedYear() throws {
        // Project starts at year 2025, year-only.
        // User sets a Range with End in 2024 → derivedYear = 2024.
        // The folder must rename from 2025_..._uid to 2024_..._uid.
        let (appState, project) = try makeProjectOnDisk(
            title: "Atlas",
            year: 2025,
            uid: "dddddddd"
        )

        let cal = Calendar(identifier: .gregorian)
        var utc = cal
        utc.timeZone = TimeZone(identifier: "UTC")!
        let start = utc.date(from: DateComponents(year: 2024, month: 9, day: 1))!
        let end = utc.date(from: DateComponents(year: 2024, month: 12, day: 31))!
        let when = WhenValue(date: start, dateEnd: end, yearOnlyYear: nil)

        try appState.updateProjectMetadata(
            project: project,
            title: project.title,
            client: project.client,
            status: project.status,
            tags: project.tags,
            teaser: project.teaser,
            hidden: project.hidden,
            when: when
        )

        // Folder on disk should now start with 2024_.
        let parent = project.folderURL.deletingLastPathComponent()
        let contents = try FileManager.default.contentsOfDirectory(atPath: parent.path)
        let renamed = contents.first { $0.hasSuffix(project.uid) }
        XCTAssertNotNil(renamed)
        XCTAssertTrue(renamed?.hasPrefix("2024_") ?? false,
                      "Folder should be renamed to 2024_..., got \(renamed ?? "<nil>")")

        // README YAML should now have date: 2024-09-01 and dateEnd: 2024-12-31.
        if let renamed {
            let renamedURL = parent.appendingPathComponent(renamed)
            let readmeURL = renamedURL.appendingPathComponent("\(renamed).md")
            let content = try String(contentsOf: readmeURL, encoding: .utf8)
            XCTAssertTrue(content.contains("date: 2024-09-01"),
                          "README should have date: 2024-09-01, got: \(content)")
            XCTAssertTrue(content.contains("dateEnd: 2024-12-31"),
                          "README should have dateEnd: 2024-12-31, got: \(content)")
        }
    }

    @MainActor
    func testRenameFailsIfDestinationFolderExists() throws {
        let (appState, project) = try makeProjectOnDisk(
            title: "Original",
            year: 2025,
            uid: "aaaaaaaa"
        )
        // Create a sibling folder with the exact name we'll try to rename into.
        let collisionURL = tempRoot.appendingPathComponent("2025_colliding_aaaaaaaa")
        try FileManager.default.createDirectory(at: collisionURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try appState.updateProjectMetadata(
                project: project,
                title: "Colliding",
                client: project.client,
                status: project.status,
                tags: project.tags,
                teaser: project.teaser,
                hidden: project.hidden,
                when: WhenValue.yearOnly(year: project.year, anchor: project.date)
            )
        )

        // Original folder still exists with its original contents.
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.folderURL.path))
        let preservedContent = try String(contentsOf: project.readmeURL, encoding: .utf8)
        let preserved = try FrontmatterParser.parse(preservedContent)
        XCTAssertEqual(preserved.title, "Original")
    }

    @MainActor
    func testCaseOnlyTitleRename_doesNotThrowCollision() throws {
        // Create a project, then rename it with only a case change to the title.
        // On case-insensitive filesystems (default APFS), the destination path
        // reports "exists" — we should detect this is our own folder and let
        // the rename proceed (or no-op if the slug is identical).
        let (appState, project) = try makeProjectOnDisk(
            title: "Hello",
            year: 2025,
            uid: "cccccccc"
        )

        // Title with only a case difference produces the same slug under
        // Slug.underscoreFrom (which lowercases). The folder name is therefore
        // unchanged; willRenameFolder should be false and the call must not throw.
        XCTAssertNoThrow(
            try appState.updateProjectMetadata(
                project: project,
                title: "hello",
                client: project.client,
                status: project.status,
                tags: project.tags,
                teaser: project.teaser,
                hidden: project.hidden,
                when: WhenValue.yearOnly(year: project.year, anchor: project.date)
            )
        )
    }

    @MainActor
    func testRenameRollsBackInternalFileMoveIfFolderRenameFails() throws {
        let (appState, project) = try makeProjectOnDisk(
            title: "Original",
            year: 2025,
            uid: "bbbbbbbb"
        )

        // Make the parent directory read-only so the folder rename fails,
        // but operations INSIDE the project folder still succeed.
        let parent = project.folderURL.deletingLastPathComponent()
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: parent.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: parent.path
            )
        }

        XCTAssertThrowsError(
            try appState.updateProjectMetadata(
                project: project,
                title: "Renamed",
                client: project.client,
                status: project.status,
                tags: project.tags,
                teaser: project.teaser,
                hidden: project.hidden,
                when: WhenValue.yearOnly(year: project.year, anchor: project.date)
            )
        )

        // Restore parent perms so we can read.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: parent.path
        )

        // The internal file should still have its ORIGINAL name
        // (the rollback must have reversed the mid-rename).
        let originalInternalFile = project.folderURL.appendingPathComponent("\(project.folderName).md")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: originalInternalFile.path),
            "Expected original internal file to exist after rollback"
        )
        // The "new-name" internal file should NOT exist.
        let newFolderName = "2025_renamed_bbbbbbbb"
        let newInternalFile = project.folderURL.appendingPathComponent("\(newFolderName).md")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: newInternalFile.path),
            "Rollback should have removed the renamed internal file"
        )
    }
}
