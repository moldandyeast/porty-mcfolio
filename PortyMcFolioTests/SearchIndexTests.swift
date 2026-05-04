import XCTest
import GRDB
@testable import PortyMcFolio

final class SearchIndexTests: XCTestCase {
    var index: SearchIndex!

    override func setUp() {
        super.setUp()
        index = try! SearchIndex(inMemory: true)
    }

    override func tearDown() {
        index = nil
        super.tearDown()
    }

    // MARK: - Project indexing

    func testIndexAndSearchProjectByTitle() throws {
        try index.indexProject(
            uid: "aaa11111",
            title: "Brand Identity Acme",
            tags: ["branding"],
            client: "Acme",
            status: "inProgress",
            body: "A full rebrand.",
            folderName: "2025_brand_identity_acme_aaa11111"
        )
        let results = try index.search(query: "Brand")
        let projects = results.filter { $0.type == .project }
        XCTAssertEqual(projects.count, 1)
        XCTAssertEqual(projects.first?.entityID, "aaa11111")
        XCTAssertEqual(projects.first?.primaryText, "Brand Identity Acme")
        XCTAssertEqual(projects.first?.secondaryText, "Acme")
    }

    func testSearchProjectByClient() throws {
        try index.indexProject(
            uid: "aaa11111",
            title: "Brand Identity",
            tags: [],
            client: "Acme Corp",
            status: "inProgress",
            body: "",
            folderName: "2025_brand_identity_aaa11111"
        )
        let results = try index.search(query: "Acme")
        let projects = results.filter { $0.type == .project }
        XCTAssertEqual(projects.count, 1)
    }

    func testSearchProjectByBody() throws {
        try index.indexProject(
            uid: "ccc33333",
            title: "Logo",
            tags: [],
            client: "",
            status: "empty",
            body: "Designed a geometric wordmark with custom kerning.",
            folderName: "2025_logo_ccc33333"
        )
        let results = try index.search(query: "geometric")
        let projects = results.filter { $0.type == .project }
        XCTAssertEqual(projects.count, 1)
    }

    func testReindexUpdatesProject() throws {
        try index.indexProject(
            uid: "eee55555",
            title: "Old Title",
            tags: [],
            client: "",
            status: "empty",
            body: "",
            folderName: "2025_old_title_eee55555"
        )
        try index.indexProject(
            uid: "eee55555",
            title: "New Title",
            tags: ["updated"],
            client: "",
            status: "inProgress",
            body: "",
            folderName: "2025_old_title_eee55555"
        )
        let oldResults = try index.search(query: "Old")
        XCTAssertTrue(oldResults.filter { $0.type == .project }.isEmpty)
        let newResults = try index.search(query: "New Title")
        XCTAssertEqual(newResults.filter { $0.type == .project }.count, 1)
    }

    // MARK: - File indexing

    func testIndexAndSearchFile() throws {
        try index.indexFile(
            relativePath: "wireframes/hero-banner.png",
            fileName: "hero-banner.png",
            fileNameNoExt: "hero-banner",
            parentUID: "aaa11111",
            parentTitle: "Brand Identity"
        )
        let results = try index.search(query: "hero")
        let files = results.filter { $0.type == .file }
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.primaryText, "hero-banner.png")
        XCTAssertEqual(files.first?.secondaryText, "Brand Identity")
        XCTAssertEqual(files.first?.parentUID, "aaa11111")
    }

    func testSearchFileByExtensionlessName() throws {
        try index.indexFile(
            relativePath: "final-logo.svg",
            fileName: "final-logo.svg",
            fileNameNoExt: "final-logo",
            parentUID: "bbb22222",
            parentTitle: "Logo Project"
        )
        let results = try index.search(query: "final logo")
        let files = results.filter { $0.type == .file }
        XCTAssertEqual(files.count, 1)
    }

    // MARK: - Link indexing

    func testIndexAndSearchLink() throws {
        try index.indexLink(
            uid: "lnk11111",
            url: "https://dribbble.com/shots/123",
            host: "dribbble.com",
            title: "Dribbble Shot",
            annotation: "Great color palette inspiration",
            parentUID: "aaa11111",
            parentTitle: "Brand Identity"
        )
        let results = try index.search(query: "dribbble")
        let links = results.filter { $0.type == .link }
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.primaryText, "Dribbble Shot")
        XCTAssertEqual(links.first?.secondaryText, "dribbble.com · Brand Identity")
    }

    func testSearchLinkByAnnotation() throws {
        try index.indexLink(
            uid: "lnk22222",
            url: "https://example.com",
            host: "example.com",
            title: "Example",
            annotation: "Typography reference for headings",
            parentUID: "bbb22222",
            parentTitle: "Website"
        )
        let results = try index.search(query: "typography")
        let links = results.filter { $0.type == .link }
        XCTAssertEqual(links.count, 1)
    }

    // MARK: - Tag indexing

    func testIndexAndSearchTag() throws {
        try index.indexTag(name: "branding", projectCount: 5)
        let results = try index.search(query: "brand")
        let tags = results.filter { $0.type == .tag }
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags.first?.primaryText, "branding")
        XCTAssertEqual(tags.first?.secondaryText, "5 projects")
    }

    // MARK: - Mixed results

    func testSearchReturnsMixedTypes() throws {
        try index.indexProject(
            uid: "aaa11111",
            title: "Brand Identity",
            tags: ["branding"],
            client: "Acme",
            status: "inProgress",
            body: "",
            folderName: "2025_brand_identity_aaa11111"
        )
        try index.indexFile(
            relativePath: "brand-guidelines.pdf",
            fileName: "brand-guidelines.pdf",
            fileNameNoExt: "brand-guidelines",
            parentUID: "aaa11111",
            parentTitle: "Brand Identity"
        )
        try index.indexTag(name: "branding", projectCount: 3)

        let results = try index.search(query: "brand")
        let types = Set(results.map { $0.type })
        XCTAssertTrue(types.contains(.project))
        XCTAssertTrue(types.contains(.file))
        XCTAssertTrue(types.contains(.tag))
    }

    // MARK: - Clear and remove

    func testClearAll() throws {
        try index.indexProject(uid: "aaa11111", title: "Test", tags: [], client: "", status: "empty", body: "", folderName: "2025_test_aaa11111")
        try index.indexTag(name: "test", projectCount: 1)
        try index.clearAll()
        let results = try index.search(query: "test")
        XCTAssertTrue(results.isEmpty)
    }

    func testRemoveProject() throws {
        try index.indexProject(uid: "fff66666", title: "To Delete", tags: [], client: "", status: "empty", body: "", folderName: "2025_to_delete_fff66666")
        try index.indexFile(relativePath: "file.png", fileName: "file.png", fileNameNoExt: "file", parentUID: "fff66666", parentTitle: "To Delete")
        try index.removeProject(uid: "fff66666")
        let results = try index.search(query: "Delete")
        XCTAssertTrue(results.isEmpty)
        // Files belonging to removed project should also be gone
        let fileResults = try index.search(query: "file")
        XCTAssertTrue(fileResults.filter { $0.parentUID == "fff66666" }.isEmpty)
    }

    func testSearchReturnsEmptyForNoMatch() throws {
        try index.indexProject(uid: "ddd44444", title: "Something", tags: [], client: "", status: "empty", body: "", folderName: "2025_something_ddd44444")
        let results = try index.search(query: "nonexistent")
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Incremental update methods

    func testUpsertProjectWithinReplacesExistingRows() throws {
        let index = try SearchIndex(inMemory: true)

        // Pre-populate one project + one of its files via the existing rebuild path
        let project = makeProject(uid: "pa111111", title: "Original")
        let fileEntry = (project: project, fileName: "old.pdf", relativePath: "old.pdf", fileNameNoExt: "old")
        try index.rebuild(projects: [project], fileEntries: [fileEntry], linkEntries: [], tagCounts: [:])

        // Now upsert with a new title and a new file via the in-transaction path
        let updated = makeProject(uid: "pa111111", title: "Updated")
        try index.testHelper_upsertProjectInOwnTransaction(
            meta: cachedMeta(from: updated),
            fileEntries: [(fileName: "new.pdf", relativePath: "new.pdf", fileNameNoExt: "new")],
            linkEntries: []
        )

        let results = try index.search(query: "Updated")
        XCTAssertTrue(results.contains { $0.type == .project && $0.entityID == "pa111111" })
        XCTAssertTrue(try index.search(query: "Original").isEmpty)

        let fileResults = try index.search(query: "new")
        XCTAssertTrue(fileResults.contains { $0.type == .file })
        XCTAssertTrue(try index.search(query: "old").isEmpty)
    }

    func testAppendFilesAndLinksClearsExistingFileLinkRows() throws {
        let index = try SearchIndex(inMemory: true)
        let project = makeProject(uid: "pb222222", title: "P")

        // Seed with one file via rebuild
        try index.rebuild(
            projects: [project],
            fileEntries: [(project: project, fileName: "first.pdf", relativePath: "first.pdf", fileNameNoExt: "first")],
            linkEntries: [],
            tagCounts: [:]
        )
        XCTAssertFalse(try index.search(query: "first").isEmpty)

        // Now append with a different file — old file rows should be wiped for this project
        try index.appendFilesAndLinks(
            forProjectUID: "pb222222",
            fileEntries: [(fileName: "second.pdf", relativePath: "second.pdf", fileNameNoExt: "second")],
            linkEntries: []
        )
        XCTAssertTrue(try index.search(query: "first").isEmpty)
        XCTAssertFalse(try index.search(query: "second").isEmpty)
    }

    func testRebuildTagsRecomputesAllTagRows() throws {
        let index = try SearchIndex(inMemory: true)
        let db = try DatabaseQueue()
        let cache = try ProjectMetadataCache(db: db)
        try cache.upsert(cachedMeta(uid: "pc333333", tags: ["UI", "Brand"]))
        try cache.upsert(cachedMeta(uid: "pc444444", tags: ["UI", "Strategy"]))

        // Seed FTS with stale tag rows that don't match
        try index.indexTag(name: "Stale", projectCount: 99)
        XCTAssertFalse(try index.search(query: "Stale").isEmpty)

        try index.rebuildTags(from: cache)

        XCTAssertTrue(try index.search(query: "Stale").isEmpty)
        let uiResults = try index.search(query: "UI")
        XCTAssertTrue(uiResults.contains { $0.type == .tag && $0.entityID == "UI" })
    }

    // MARK: - ID uniqueness

    func testFileResultIDsAreUniqueAcrossProjectsWithSameFilename() throws {
        try index.indexFile(
            relativePath: "notes.md",
            fileName: "notes.md",
            fileNameNoExt: "notes",
            parentUID: "aaaaaaaa",
            parentTitle: "Project Alpha"
        )
        try index.indexFile(
            relativePath: "notes.md",
            fileName: "notes.md",
            fileNameNoExt: "notes",
            parentUID: "bbbbbbbb",
            parentTitle: "Project Beta"
        )
        let results = try index.search(query: "notes")
        let files = results.filter { $0.type == .file }
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(Set(files.map(\.id)).count, 2)
    }

    // MARK: - Atomic portfolio switch wipe

    func testWipeAllForPortfolioSwitchClearsBothFTSAndCache() throws {
        let index = try SearchIndex(inMemory: true)
        let db = index.databaseQueueForReconciler()
        let cache = try ProjectMetadataCache(db: db)

        let meta = CachedProjectMeta(
            uid: "aaaaaaaa",
            folderName: "2025_test_aaaaaaaa",
            year: 2025,
            title: "Test",
            client: "Client",
            status: .inProgress,
            tags: ["a"],
            teaser: "",
            favorites: [],
            body: "body",
            hidden: false,
            date: Date(),
            dateEnd: nil,
            frontmatterMTime: Date()
        )
        try db.write { conn in
            try cache.upsertWithin(conn, meta)
            try index.upsertProjectWithin(conn, meta: meta, fileEntries: [], linkEntries: [])
        }

        // Sanity check: pre-wipe both tables have rows.
        try db.read { conn in
            XCTAssertEqual(try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM search_fts"), 1)
            XCTAssertEqual(try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM project_meta"), 1)
        }

        try index.wipeAllForPortfolioSwitch()

        try db.read { conn in
            XCTAssertEqual(try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM search_fts"), 0)
            XCTAssertEqual(try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM project_meta"), 0)
        }
    }

    // MARK: - Helpers

    private func makeProject(uid: String = "abcd1234", title: String = "T") -> Project {
        Project(
            uid: uid, year: 2025,
            folderName: "2025_test_\(uid)",
            folderURL: URL(fileURLWithPath: "/tmp/2025_test_\(uid)"),
            title: title, date: Date(timeIntervalSince1970: 0),
            tags: [], client: "", status: .empty,
            body: "", teaser: ""
        )
    }

    private func cachedMeta(
        uid: String = "abcd1234",
        title: String = "T",
        tags: [String] = []
    ) -> CachedProjectMeta {
        CachedProjectMeta(
            uid: uid,
            folderName: "2025_test_\(uid)",
            year: 2025,
            title: title,
            client: "",
            status: .empty,
            tags: tags,
            teaser: "",
            favorites: [],
            body: "",
            hidden: false,
            date: Date(timeIntervalSince1970: 0),
            dateEnd: nil,
            frontmatterMTime: Date(timeIntervalSince1970: 0)
        )
    }

    private func cachedMeta(from project: Project) -> CachedProjectMeta {
        cachedMeta(uid: project.uid, title: project.title, tags: project.tags)
    }
}
