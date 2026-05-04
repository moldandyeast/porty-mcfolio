import XCTest
import GRDB
@testable import PortyMcFolio

final class ProjectReconcilerTests: XCTestCase {
    var tempRoot: URL!
    var db: DatabaseQueue!
    var cache: ProjectMetadataCache!
    var index: SearchIndex!
    var publishedMutations: [ProjectReconciler.Mutation] = []
    var reconciler: ProjectReconciler!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectReconcilerTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        index = try! SearchIndex(inMemory: true)
        db = index.databaseQueueForReconciler()
        cache = try! ProjectMetadataCache(db: db)
        publishedMutations = []
        reconciler = ProjectReconciler(
            portfolioRoot: tempRoot,
            db: db,
            cache: cache,
            searchIndex: index,
            publish: { [weak self] m in self?.publishedMutations.append(m) }
        )
    }

    override func tearDown() {
        reconciler.shutdown()
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    // MARK: - Test fixtures

    /// Create a project folder + frontmatter file on disk. Returns the uid.
    @discardableResult
    private func createDiskProject(
        uid: String = "abcd1234",
        year: Int = 2025,
        title: String = "Disk Project",
        client: String = "ACME",
        status: ProjectStatus = .empty,
        tags: [String] = ["UI"]
    ) -> String {
        let folderName = "\(year)_disk_\(uid)"
        let folderURL = tempRoot.appendingPathComponent(folderName)
        try! FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let parsed = ParsedFrontmatter(
            title: title, date: Date(timeIntervalSince1970: 1_700_000_000),
            tags: tags, client: client, status: status,
            body: "# \(title)\n\nbody", teaser: ""
        )
        let content = FrontmatterParser.serialize(frontmatter: parsed)
        let mdURL = folderURL.appendingPathComponent("\(folderName).md")
        try! content.write(to: mdURL, atomically: true, encoding: .utf8)
        return uid
    }

    private func mtime(of relativePath: String) -> Date {
        let url = tempRoot.appendingPathComponent(relativePath)
        let attrs = try! FileManager.default.attributesOfItem(atPath: url.path)
        return attrs[.modificationDate] as! Date
    }

    // MARK: - Tests

    func testInitialReconciliationOnEmptyPortfolio() throws {
        let exp = expectation(description: "done")
        reconciler.startInitialReconciliation { exp.fulfill() }
        wait(for: [exp], timeout: 2)

        XCTAssertEqual(try cache.loadAll(), [])
        XCTAssertEqual(publishedMutations.count, 0)
    }

    func testInitialReconciliationDiscoversProjectOnDisk() throws {
        let uid = createDiskProject(title: "Hello")
        let exp = expectation(description: "done")
        reconciler.startInitialReconciliation { exp.fulfill() }
        wait(for: [exp], timeout: 2)

        let cached = try cache.loadAll()
        XCTAssertEqual(cached.count, 1)
        XCTAssertEqual(cached[0].uid, uid)
        XCTAssertEqual(cached[0].title, "Hello")
        XCTAssertFalse(try index.search(query: "Hello").isEmpty)
    }

    func testReconciliationTrustsCacheWhenMTimeUnchanged() throws {
        let uid = createDiskProject(title: "Original")
        let folderName = "2025_disk_\(uid)"
        let mdMTime = mtime(of: "\(folderName)/\(folderName).md")

        // Pre-populate cache with the SAME mtime — reconciler should not re-read the file.
        try cache.upsert(CachedProjectMeta(
            uid: uid, folderName: folderName, year: 2025,
            title: "Cached title (different from disk)", client: "X",
            status: .empty, tags: [], teaser: "", favorites: [], body: "cached body",
            hidden: false, date: Date(timeIntervalSince1970: 0),
            dateEnd: nil,
            frontmatterMTime: mdMTime
        ))

        let exp = expectation(description: "done")
        reconciler.startInitialReconciliation { exp.fulfill() }
        wait(for: [exp], timeout: 2)

        let cached = try cache.loadAll()
        XCTAssertEqual(cached.count, 1)
        // Cache entry was trusted; title is still "Cached title", not "Original"
        XCTAssertEqual(cached[0].title, "Cached title (different from disk)")
    }

    func testReconciliationDetectsStaleEntryViaMTime() throws {
        let uid = createDiskProject(title: "Disk Title")
        let folderName = "2025_disk_\(uid)"

        // Cache says the project's mtime was 1 day ago — stale.
        try cache.upsert(CachedProjectMeta(
            uid: uid, folderName: folderName, year: 2025,
            title: "Cached title", client: "X", status: .empty,
            tags: [], teaser: "", favorites: [], body: "cached body", hidden: false,
            date: Date(timeIntervalSince1970: 0),
            dateEnd: nil,
            frontmatterMTime: Date(timeIntervalSince1970: 1)
        ))

        let exp = expectation(description: "done")
        reconciler.startInitialReconciliation { exp.fulfill() }
        wait(for: [exp], timeout: 2)

        let cached = try cache.loadAll()
        XCTAssertEqual(cached[0].title, "Disk Title")  // updated from disk
    }

    func testReconciliationRemovesDeletedProject() throws {
        // Cache has uid X, but no folder for X on disk
        try cache.upsert(CachedProjectMeta(
            uid: "ghost111", folderName: "2025_ghost_ghost111",
            year: 2025, title: "Ghost", client: "", status: .empty,
            tags: [], teaser: "", favorites: [], body: "", hidden: false,
            date: Date(timeIntervalSince1970: 0),
            dateEnd: nil,
            frontmatterMTime: Date(timeIntervalSince1970: 0)
        ))
        // Pre-seed FTS too
        try index.indexProject(uid: "ghost111", title: "Ghost", tags: [],
                                client: "", status: "empty", body: "", folderName: "2025_ghost_ghost111")
        XCTAssertFalse(try index.search(query: "Ghost").isEmpty)

        let exp = expectation(description: "done")
        reconciler.startInitialReconciliation { exp.fulfill() }
        wait(for: [exp], timeout: 2)

        XCTAssertEqual(try cache.loadAll(), [])
        XCTAssertTrue(try index.search(query: "Ghost").isEmpty)
    }

    func testReconciliationDiscoversNewProject() throws {
        let exp1 = expectation(description: "first")
        reconciler.startInitialReconciliation { exp1.fulfill() }
        wait(for: [exp1], timeout: 2)
        XCTAssertEqual(try cache.loadAll(), [])

        // Add a project after the first reconciliation
        createDiskProject(uid: "ae111111", title: "New One")

        let exp2 = expectation(description: "second")
        reconciler.reconcileTopLevel { exp2.fulfill() }
        wait(for: [exp2], timeout: 2)

        let cached = try cache.loadAll()
        XCTAssertEqual(cached.count, 1)
        XCTAssertEqual(cached[0].uid, "ae111111")
    }

    func testProjectFolderRenamedUpdatesFolderNameInPlace() throws {
        let uid = createDiskProject(uid: "ab111111", year: 2024, title: "Before")
        let exp = expectation(description: "init")
        reconciler.startInitialReconciliation { exp.fulfill() }
        wait(for: [exp], timeout: 2)

        let renameExp = expectation(description: "renamed")
        reconciler.projectFolderRenamed(uid: uid, newFolderName: "2025_after_ab111111") {
            renameExp.fulfill()
        }
        wait(for: [renameExp], timeout: 2)

        let cached = try cache.loadAll()
        XCTAssertEqual(cached.count, 1)
        XCTAssertEqual(cached[0].folderName, "2025_after_ab111111")
        XCTAssertEqual(cached[0].uid, "ab111111")
    }

    func testNotifyProjectFileChangedTriggersImmediateSync() throws {
        let uid = createDiskProject(title: "First")
        let folderName = "2025_disk_\(uid)"
        let exp1 = expectation(description: "init")
        reconciler.startInitialReconciliation { exp1.fulfill() }
        wait(for: [exp1], timeout: 2)
        XCTAssertEqual(try cache.loadAll().first?.title, "First")

        // Modify the frontmatter file directly — bump title
        let mdURL = tempRoot.appendingPathComponent(folderName).appendingPathComponent("\(folderName).md")
        let parsed = ParsedFrontmatter(
            title: "Second", date: Date(timeIntervalSince1970: 1_700_000_000),
            tags: [], client: "", status: .empty, body: "x", teaser: ""
        )
        try FrontmatterParser.serialize(frontmatter: parsed).write(to: mdURL, atomically: true, encoding: .utf8)
        // Touch mtime explicitly forward
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: mdURL.path)

        let exp2 = expectation(description: "notify")
        reconciler.notifyProjectFileChanged(uid: uid) { exp2.fulfill() }
        wait(for: [exp2], timeout: 2)

        XCTAssertEqual(try cache.loadAll().first?.title, "Second")
    }

    func testFSEventPathToUIDResolution() {
        let folderName = "2025_dango_a1b2c3d4"
        let path = tempRoot.appendingPathComponent(folderName).appendingPathComponent("photos/x.jpg").path
        XCTAssertEqual(reconciler.uidFromEventPath(path), "a1b2c3d4")

        // Path equals portfolio root → nil (caller falls back to top-level scan)
        XCTAssertNil(reconciler.uidFromEventPath(tempRoot.path))

        // Unparseable folder name → nil
        let bad = tempRoot.appendingPathComponent("not_a_project_folder/x.txt").path
        XCTAssertNil(reconciler.uidFromEventPath(bad))

        // Path outside portfolio root → nil
        XCTAssertNil(reconciler.uidFromEventPath("/somewhere/else/file.txt"))
    }

    func testParseFailureLeavesCachedEntryAlone() throws {
        let uid = createDiskProject(title: "Good Title")
        let folderName = "2025_disk_\(uid)"
        let exp1 = expectation(description: "init")
        reconciler.startInitialReconciliation { exp1.fulfill() }
        wait(for: [exp1], timeout: 2)

        // Corrupt the frontmatter file (write malformed YAML — unclosed bracket inside delimiters)
        let mdURL = tempRoot.appendingPathComponent(folderName).appendingPathComponent("\(folderName).md")
        try "---\nthis is not: [valid yaml\n---\n".write(to: mdURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: mdURL.path)

        let exp2 = expectation(description: "second")
        reconciler.notifyProjectFileChanged(uid: uid) { exp2.fulfill() }
        wait(for: [exp2], timeout: 2)

        // Cache entry should still be intact (not replaced by garbage)
        let cached = try cache.loadAll()
        XCTAssertEqual(cached.count, 1)
        XCTAssertEqual(cached[0].title, "Good Title")
    }

    // MARK: - Lazy file/link population

    /// Add a regular file and a link file to a project folder on disk.
    private func addFileAndLink(toUID uid: String, year: Int = 2025) {
        let folderName = "\(year)_disk_\(uid)"
        let folderURL = tempRoot.appendingPathComponent(folderName)
        // Regular file
        let pdfURL = folderURL.appendingPathComponent("hero.pdf")
        try! Data().write(to: pdfURL)
        // Link file
        let linkUID = "ff112233"
        let linkParsed = """
        ---
        url: https://example.com
        title: Example Site
        annotation: Note
        date: 2024-01-01T00:00:00Z
        ---
        """
        let linkURL = folderURL.appendingPathComponent("link-\(linkUID).md")
        try! linkParsed.write(to: linkURL, atomically: true, encoding: .utf8)
    }

    func testPopulateFilesAddsFTSFileAndLinkRows() throws {
        let uid = createDiskProject(uid: "1a2b1111")
        addFileAndLink(toUID: uid)

        let exp1 = expectation(description: "init")
        reconciler.startInitialReconciliation { exp1.fulfill() }
        wait(for: [exp1], timeout: 2)

        // Before populate: no file/link FTS rows for this project
        XCTAssertTrue(try index.search(query: "hero").isEmpty)
        XCTAssertTrue(try index.search(query: "Example").isEmpty)

        let exp2 = expectation(description: "populate")
        reconciler.populateFiles(uid: uid) { exp2.fulfill() }
        wait(for: [exp2], timeout: 2)

        XCTAssertFalse(try index.search(query: "hero").isEmpty)
        XCTAssertFalse(try index.search(query: "Example").isEmpty)
    }

    func testPopulateFilesIsIdempotent() throws {
        let uid = createDiskProject(uid: "1de21111")
        addFileAndLink(toUID: uid)
        let exp1 = expectation(description: "init")
        reconciler.startInitialReconciliation { exp1.fulfill() }
        wait(for: [exp1], timeout: 2)

        let exp2 = expectation(description: "first populate")
        reconciler.populateFiles(uid: uid) { exp2.fulfill() }
        wait(for: [exp2], timeout: 2)

        let exp3 = expectation(description: "second populate")
        reconciler.populateFiles(uid: uid) { exp3.fulfill() }
        wait(for: [exp3], timeout: 2)

        // No duplicate file rows
        let heroResults = try index.search(query: "hero")
        XCTAssertEqual(heroResults.filter { $0.type == .file }.count, 1)
    }

    func testPopulateFilesShortCircuitsOnceAlreadyPopulated() throws {
        let uid = createDiskProject(uid: "54711a1a")
        addFileAndLink(toUID: uid)
        let exp1 = expectation(description: "init")
        reconciler.startInitialReconciliation { exp1.fulfill() }
        wait(for: [exp1], timeout: 2)

        let exp2 = expectation(description: "first populate")
        reconciler.populateFiles(uid: uid) { exp2.fulfill() }
        wait(for: [exp2], timeout: 2)

        // Add a file on disk
        let folderName = "2025_disk_\(uid)"
        let newFileURL = tempRoot.appendingPathComponent(folderName).appendingPathComponent("added.pdf")
        try Data().write(to: newFileURL)

        // Second populate — should short-circuit, NOT pick up the new file
        let exp3 = expectation(description: "second populate")
        reconciler.populateFiles(uid: uid) { exp3.fulfill() }
        wait(for: [exp3], timeout: 2)
        XCTAssertTrue(try index.search(query: "added").isEmpty, "Second populateFiles should short-circuit; new file should NOT be indexed yet")

        // notifyProjectFileChanged forces re-walk via syncProject's guard
        // (bump mtime so syncProject doesn't fast-path-skip)
        let mdURL = tempRoot.appendingPathComponent(folderName).appendingPathComponent("\(folderName).md")
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: mdURL.path)
        let exp4 = expectation(description: "notify")
        reconciler.notifyProjectFileChanged(uid: uid) { exp4.fulfill() }
        wait(for: [exp4], timeout: 2)
        XCTAssertFalse(try index.search(query: "added").isEmpty, "After notify, the added file should be indexed")
    }

    func testRePopulatesAfterSyncWhenFilesAlreadyLoaded() throws {
        let uid = createDiskProject(uid: "1e501111")
        addFileAndLink(toUID: uid)
        let exp1 = expectation(description: "init")
        reconciler.startInitialReconciliation { exp1.fulfill() }
        wait(for: [exp1], timeout: 2)

        let exp2 = expectation(description: "populate")
        reconciler.populateFiles(uid: uid) { exp2.fulfill() }
        wait(for: [exp2], timeout: 2)

        // Add another file on disk
        let folderName = "2025_disk_\(uid)"
        let newFileURL = tempRoot.appendingPathComponent(folderName).appendingPathComponent("second.pdf")
        try Data().write(to: newFileURL)

        // Bump the frontmatter mtime so syncProject sees a change
        let mdURL = tempRoot.appendingPathComponent(folderName).appendingPathComponent("\(folderName).md")
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: mdURL.path)

        let exp3 = expectation(description: "notify")
        reconciler.notifyProjectFileChanged(uid: uid) { exp3.fulfill() }
        wait(for: [exp3], timeout: 2)

        // The new file should now be searchable (re-population triggered automatically)
        XCTAssertFalse(try index.search(query: "second").isEmpty)
    }

    // MARK: - External-edit resilience (Task 4, 2026-04-24)

    /// Synchronously run one reconciliation pass for a single uid and wait for
    /// the reconciler queue to drain. Uses the existing completion hook on
    /// `notifyProjectFileChanged`.
    private func syncProjectAndWait(uid: String, timeout: TimeInterval = 2) {
        let done = expectation(description: "sync complete")
        reconciler.notifyProjectFileChanged(uid: uid) {
            done.fulfill()
        }
        wait(for: [done], timeout: timeout)
    }

    func testRepairsFavoritesTeaserAndBodyEmbedsInOneWrite() throws {
        // Create a project with teaser + 2 body embeds + 1 favorite all
        // pointing at "hero.jpg" at the project root.
        let uid = "cafebabe"
        let folderName = "2025_heroes_\(uid)"
        let folderURL = tempRoot.appendingPathComponent(folderName)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let parsed = ParsedFrontmatter(
            title: "Heroes",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            tags: [],
            client: "",
            status: .empty,
            body: "# Heroes\n\n![[hero.jpg]]\n\nSome text.\n\n![[hero.jpg]]\n",
            teaser: "hero.jpg",
            favorites: ["hero.jpg"]
        )
        let md = FrontmatterParser.serialize(frontmatter: parsed)
        let mdURL = folderURL.appendingPathComponent("\(folderName).md")
        try md.write(to: mdURL, atomically: true, encoding: .utf8)

        // Put the actual file at a new relative path (simulates Finder rename).
        let subfolderURL = folderURL.appendingPathComponent("media")
        try FileManager.default.createDirectory(at: subfolderURL, withIntermediateDirectories: true)
        let newFileURL = subfolderURL.appendingPathComponent("hero.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xE0]).write(to: newFileURL)  // minimal JPEG-ish

        // Observe .markdownFileDidChange so we can assert it fires exactly once.
        var fileDidChangeCount = 0
        let obs = NotificationCenter.default.addObserver(
            forName: .markdownFileDidChange,
            object: nil,
            queue: nil
        ) { _ in fileDidChangeCount += 1 }
        defer { NotificationCenter.default.removeObserver(obs) }

        syncProjectAndWait(uid: uid)

        // Read the rewritten README.
        let rewrittenContent = try String(contentsOf: mdURL, encoding: .utf8)
        let rewritten = try FrontmatterParser.parse(rewrittenContent)

        XCTAssertEqual(rewritten.teaser, "media/hero.jpg", "Teaser should be repaired")
        XCTAssertEqual(rewritten.favorites, ["media/hero.jpg"], "Favorites should be repaired")
        XCTAssertTrue(rewritten.body.contains("![[media/hero.jpg]]"))
        XCTAssertFalse(rewritten.body.contains("![[hero.jpg]]"))
        XCTAssertEqual(
            rewritten.body.components(separatedBy: "![[media/hero.jpg]]").count - 1,
            2,
            "Both body embeds should be rewritten"
        )
        XCTAssertEqual(fileDidChangeCount, 1, "Exactly one .markdownFileDidChange despite three repairs")
    }

    func testFiresShowToastWhenFavoritesAreDropped() throws {
        let uid = "deadbeef"
        let folderName = "2025_drops_\(uid)"
        let folderURL = tempRoot.appendingPathComponent(folderName)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let parsed = ParsedFrontmatter(
            title: "Drops",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            tags: [],
            client: "",
            status: .empty,
            body: "# Drops",
            teaser: "",
            favorites: ["gone1.jpg", "gone2.jpg"]  // neither exists on disk
        )
        let md = FrontmatterParser.serialize(frontmatter: parsed)
        let mdURL = folderURL.appendingPathComponent("\(folderName).md")
        try md.write(to: mdURL, atomically: true, encoding: .utf8)

        var toastMessages: [String] = []
        let obs = NotificationCenter.default.addObserver(
            forName: .showToast,
            object: nil,
            queue: nil
        ) { note in
            if let message = note.object as? String {
                toastMessages.append(message)
            }
        }
        defer { NotificationCenter.default.removeObserver(obs) }

        syncProjectAndWait(uid: uid)

        XCTAssertTrue(
            toastMessages.contains { $0.contains("2") && $0.contains("favorites") && $0.contains("Drops") },
            "Expected a drop toast mentioning 2, favorites, and the project title; got: \(toastMessages)"
        )
    }

    func testNoopWhenEverythingResolves() throws {
        let uid = "00ff00ff"
        let folderName = "2025_noop_\(uid)"
        let folderURL = tempRoot.appendingPathComponent(folderName)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        try Data([0xFF]).write(to: folderURL.appendingPathComponent("hero.jpg"))

        let parsed = ParsedFrontmatter(
            title: "Noop",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            tags: [],
            client: "",
            status: .empty,
            body: "# Noop\n\n![[hero.jpg]]",
            teaser: "hero.jpg",
            favorites: ["hero.jpg"]
        )
        let md = FrontmatterParser.serialize(frontmatter: parsed)
        let mdURL = folderURL.appendingPathComponent("\(folderName).md")
        try md.write(to: mdURL, atomically: true, encoding: .utf8)

        let preMtime = try FileManager.default.attributesOfItem(atPath: mdURL.path)[.modificationDate] as! Date

        var fileDidChangeCount = 0
        let obs = NotificationCenter.default.addObserver(
            forName: .markdownFileDidChange,
            object: nil,
            queue: nil
        ) { _ in fileDidChangeCount += 1 }
        defer { NotificationCenter.default.removeObserver(obs) }

        syncProjectAndWait(uid: uid)

        let postMtime = try FileManager.default.attributesOfItem(atPath: mdURL.path)[.modificationDate] as! Date
        XCTAssertEqual(preMtime.timeIntervalSince1970, postMtime.timeIntervalSince1970,
                       "README must not have been rewritten when nothing needs repair")
        XCTAssertEqual(fileDidChangeCount, 0)
    }

    func testSyncProjectPublishesOnceWithFilePathsForPopulatedProject() throws {
        // One project on disk with two files.
        let uid = createDiskProject()
        let folderName = "2025_disk_\(uid)"
        let folderURL = tempRoot.appendingPathComponent(folderName)
        try "image".write(
            to: folderURL.appendingPathComponent("hero.jpg"),
            atomically: true, encoding: .utf8
        )
        try "notes".write(
            to: folderURL.appendingPathComponent("notes.md"),
            atomically: true, encoding: .utf8
        )

        // Initial reconciliation lands an .insert.
        let initial = expectation(description: "initial")
        reconciler.startInitialReconciliation { initial.fulfill() }
        wait(for: [initial], timeout: 5)

        // Trigger lazy file population.
        let populated = expectation(description: "populated")
        reconciler.populateFiles(uid: uid) { populated.fulfill() }
        wait(for: [populated], timeout: 5)

        // Reset recorder — we care what happens on a subsequent sync.
        publishedMutations.removeAll()

        // Touch frontmatter mtime so syncProject actually runs the upsert branch.
        let readmeURL = folderURL.appendingPathComponent("\(folderName).md")
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(1)],
            ofItemAtPath: readmeURL.path
        )
        let synced = expectation(description: "synced")
        reconciler.notifyProjectFileChanged(uid: uid) { synced.fulfill() }
        wait(for: [synced], timeout: 5)

        // Exactly one publish; it carries populated filePaths.
        XCTAssertEqual(publishedMutations.count, 1, "expected one publish, got \(publishedMutations)")
        guard case .update(let project) = publishedMutations.first else {
            XCTFail("expected .update; got \(String(describing: publishedMutations.first))")
            return
        }
        XCTAssertTrue(project.filePaths.contains("hero.jpg"))
        XCTAssertTrue(project.filePaths.contains("notes.md"))
    }
}
