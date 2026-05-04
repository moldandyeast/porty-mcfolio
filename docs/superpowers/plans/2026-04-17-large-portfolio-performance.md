# Large-Portfolio Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make PortyMcFolio launch instantly and stay responsive as portfolios grow toward ~100GB / 100K files, by introducing a persistent project-metadata cache and a reconciler that owns FSEvent debouncing, per-project mtime-checked sync, lazy file enumeration, and incremental FTS updates.

**Architecture:** A new `ProjectMetadataCache` (SQLite-backed in `search.sqlite`) stores everything needed to render the project list. A new `ProjectReconciler` owns the serial queue, FSEvent debouncing, per-project sync via mtime checks, lazy file/link population, and batched MainActor publishing. Cache + FTS writes are wrapped in a single shared transaction for atomicity. `AppState` becomes a thin orchestrator delegating disk work to the reconciler.

**Tech Stack:** Swift, SwiftUI, GRDB (SQLite/FTS5, already a dep), Foundation FSEvents, XCTest. No new dependencies.

**Spec:** [docs/superpowers/specs/2026-04-17-large-portfolio-performance-design.md](../specs/2026-04-17-large-portfolio-performance-design.md)

---

## Prerequisites

This branch (`main`) currently has 9 uncommitted files from a prior session's bug fixes (status/tags click-area, table alignment, instant-open on create, ProjectDetailView .id, MarkdownEditorView save flush, teaser-rename fix). The plan modifies some of the same files (`AppState.swift`, `MarkdownEditorView.swift`, `GalleryView.swift`).

**Before starting Task 1**, commit or stash those in-flight changes so the plan applies cleanly. Recommended: bundle them into one or two "fix:" commits.

```bash
git status --short        # see the dirty files
git diff                  # review what's there
git add ...               # stage what you want
git commit -m "fix: ..."  # bundle related fixes
```

Any commands in this plan that conflict with the in-flight bug fixes will be obvious — stop and reconcile before proceeding.

---

## Conventions

**Test command** (project uses XcodeGen + xcodebuild; tests need code-signing disabled to avoid local-signing flakiness in headless runs):

```bash
xcodebuild test \
    -project PortyMcFolio.xcodeproj \
    -scheme PortyMcFolioTests \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
    2>&1 | grep -E '(Test Case|Executed|passed|failed|error:)' | tail -30
```

**Build command:**

```bash
xcodebuild build \
    -project PortyMcFolio.xcodeproj \
    -scheme PortyMcFolio \
    -destination 'platform=macOS' \
    2>&1 | grep -E '(error:|BUILD)' | tail -5
```

**After creating any new `.swift` file, regenerate the Xcode project**:

```bash
cd <repo> && xcodegen generate
```

`xcodegen` is at `/opt/homebrew/bin/xcodegen`.

---

## File Structure

| Path | Action | Responsibility |
|------|--------|----------------|
| `PortyMcFolio/Services/ProjectMetadataCache.swift` | **create** (Task 1) | Pure data layer: SQL CRUD over `project_meta` table. No business logic. |
| `PortyMcFolio/Services/ProjectReconciler.swift` | **create** (Task 3) | Serial queue, debouncing, per-project sync, lazy file/link population, batched publishing. |
| `PortyMcFolioTests/ProjectMetadataCacheTests.swift` | **create** (Task 1) | Unit tests for the cache. |
| `PortyMcFolioTests/ProjectReconcilerTests.swift` | **create** (Task 3) | Tests for sync logic, atomic writes, folder rename. |
| `PortyMcFolioTests/ProjectReconcilerDebounceTests.swift` | **create** (Task 5) | Debounce timing tests. |
| `PortyMcFolio/Models/Project.swift` | **modify** (Task 1) | Add `frontmatterMTime: Date?`. |
| `PortyMcFolio/Services/SearchIndex.swift` | **modify** (Task 1 + Task 2) | Bump `schemaVersion` to `"3"`, add `DROP TABLE` for `project_meta` on migration. Add `upsertProjectWithin`, `appendFilesAndLinks`, `rebuildTags`. |
| `PortyMcFolio/App/AppState.swift` | **modify** (Task 4 + Task 7) | Construct cache + reconciler. Replace `performScan`/`enumerateFiles`/`cachedLinks` with reconciler delegation. New methods: `notifyProjectFileChanged`, `projectFolderRenamed`, `setSelectedProject`, `populateFilesForLikelyMatches`. |
| `PortyMcFolio/Views/MarkdownEditorView.swift` | **modify** (Task 7) | `onSave` callback uses `notifyProjectFileChanged` instead of `refreshProjects`. |
| `PortyMcFolio/Views/GalleryView.swift` | **modify** (Task 7) | `setTeaser` and `updateReadmeReferences` call `notifyProjectFileChanged` after writes. |
| `PortyMcFolio/Views/SearchPalette.swift` | **modify** (Task 6) | On query change, call `populateFilesForLikelyMatches`. Add "Re-index portfolio" command. |
| `PortyMcFolio/Models/SearchResult.swift` | **modify** (Task 6) | Add a new `SearchCommand` for "Re-index portfolio". |

---

## Task 1: Project model field + SearchIndex schema bump + ProjectMetadataCache

Self-contained data layer. No behavior change to the running app — these new building blocks are unused until Task 4.

**Files:**
- Modify: `PortyMcFolio/Models/Project.swift`
- Modify: `PortyMcFolio/Services/SearchIndex.swift`
- Create: `PortyMcFolio/Services/ProjectMetadataCache.swift`
- Create: `PortyMcFolioTests/ProjectMetadataCacheTests.swift`

- [ ] **Step 1: Add `frontmatterMTime: Date?` to Project**

In `PortyMcFolio/Models/Project.swift`, find the `Project` struct's stored property list (around line 14-29). Add the new field right after `filePaths`:

```swift
struct Project: Identifiable, Equatable {
    let uid: String
    let year: Int
    let folderName: String
    let folderURL: URL
    var title: String
    var date: Date
    var tags: [String]
    var client: String
    var status: ProjectStatus
    var body: String
    var teaser: String
    var hidden: Bool = false
    /// Cached relative file paths (excluding README.md and link files) for fallback search,
    /// populated by refreshProjects().
    var filePaths: [String] = []
    /// mtime of the frontmatter file ({folderName}.md or README.md) at last sync.
    /// nil for projects loaded only from cache and not yet validated against disk.
    var frontmatterMTime: Date? = nil
```

- [ ] **Step 2: Bump `SearchIndex.schemaVersion` and add project_meta DROP**

In `PortyMcFolio/Services/SearchIndex.swift`, find:

```swift
private static let schemaVersion = "2"
```

Replace with:

```swift
private static let schemaVersion = "3"
```

Then in the `migrate()` method, find the version-mismatch block:

```swift
if currentVersion != Self.schemaVersion {
    try conn.execute(sql: "DROP TABLE IF EXISTS search_fts")
}
```

Replace with:

```swift
if currentVersion != Self.schemaVersion {
    try conn.execute(sql: "DROP TABLE IF EXISTS search_fts")
    try conn.execute(sql: "DROP TABLE IF EXISTS project_meta")
}
```

- [ ] **Step 3: Write failing tests for ProjectMetadataCache**

Create `PortyMcFolioTests/ProjectMetadataCacheTests.swift`:

```swift
import XCTest
import GRDB
@testable import PortyMcFolio

final class ProjectMetadataCacheTests: XCTestCase {
    var db: DatabaseQueue!
    var cache: ProjectMetadataCache!

    override func setUp() {
        super.setUp()
        db = try! DatabaseQueue()  // in-memory
        cache = try! ProjectMetadataCache(db: db)
    }

    override func tearDown() {
        cache = nil
        db = nil
        super.tearDown()
    }

    private func makeMeta(
        uid: String = "abcd1234",
        folderName: String? = nil,
        year: Int = 2025,
        title: String = "Test",
        client: String = "ACME",
        status: ProjectStatus = .empty,
        tags: [String] = ["a", "b"],
        teaser: String = "",
        body: String = "Body text",
        hidden: Bool = false,
        date: Date = Date(timeIntervalSince1970: 1_700_000_000),
        mtime: Date = Date(timeIntervalSince1970: 1_700_000_500)
    ) -> CachedProjectMeta {
        CachedProjectMeta(
            uid: uid,
            folderName: folderName ?? "\(year)_test_\(uid)",
            year: year,
            title: title,
            client: client,
            status: status,
            tags: tags,
            teaser: teaser,
            body: body,
            hidden: hidden,
            date: date,
            frontmatterMTime: mtime
        )
    }

    func testEmptyCacheReturnsEmptyArray() throws {
        XCTAssertEqual(try cache.loadAll(), [])
    }

    func testUpsertThenLoadRoundTrips() throws {
        let m = makeMeta(tags: ["UI", "Brand"])
        try cache.upsert(m)
        let loaded = try cache.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0], m)
    }

    func testUpsertReplacesExistingRow() throws {
        try cache.upsert(makeMeta(title: "Old"))
        try cache.upsert(makeMeta(title: "New"))
        let loaded = try cache.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].title, "New")
    }

    func testRemoveDropsRow() throws {
        try cache.upsert(makeMeta(uid: "aaaa1111"))
        try cache.upsert(makeMeta(uid: "bbbb2222"))
        try cache.remove(uid: "aaaa1111")
        let loaded = try cache.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].uid, "bbbb2222")
    }

    func testClearWipesEverything() throws {
        try cache.upsert(makeMeta(uid: "aaaa1111"))
        try cache.upsert(makeMeta(uid: "bbbb2222"))
        try cache.clear()
        XCTAssertEqual(try cache.loadAll(), [])
    }

    func testCorruptTagsJsonDropsRowGracefully() throws {
        try cache.upsert(makeMeta(uid: "good1111"))
        // Manually inject a row with malformed tags_json
        try db.write { conn in
            try conn.execute(sql: """
                INSERT INTO project_meta (uid, folder_name, year, title, client, status,
                    tags_json, teaser, body, hidden, date_iso, frontmatter_mtime, cached_at)
                VALUES ('bad22222', '2025_bad_bad22222', 2025, 'Bad', 'X', 'empty',
                    'NOT VALID JSON{{', '', '', 0, '2024-01-01', 1700000000, 1700000000)
                """)
        }
        // loadAll should skip the corrupt row and return the good one
        let loaded = try cache.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].uid, "good1111")
    }

    func testFrontmatterMTimeRoundTripsAtSecondPrecision() throws {
        let mtime = Date(timeIntervalSince1970: 1_700_000_555)
        try cache.upsert(makeMeta(mtime: mtime))
        let loaded = try cache.loadAll()
        XCTAssertEqual(loaded[0].frontmatterMTime.timeIntervalSince1970, mtime.timeIntervalSince1970, accuracy: 1.0)
    }

    func testHiddenBoolRoundTripsBothValues() throws {
        try cache.upsert(makeMeta(uid: "vis11111", hidden: false))
        try cache.upsert(makeMeta(uid: "hid22222", hidden: true))
        let loaded = try cache.loadAll().sorted { $0.uid < $1.uid }
        XCTAssertEqual(loaded[0].hidden, true)   // hid22222 < vis11111
        XCTAssertEqual(loaded[1].hidden, false)
    }

    func testAggregateTagCountsAcrossProjects() throws {
        try cache.upsert(makeMeta(uid: "p1aaaaaa", tags: ["UI", "Brand"]))
        try cache.upsert(makeMeta(uid: "p2bbbbbb", tags: ["UI", "Strategy"]))
        try cache.upsert(makeMeta(uid: "p3cccccc", tags: ["UI"]))
        let counts = try cache.aggregateTagCounts()
        XCTAssertEqual(counts["UI"], 3)
        XCTAssertEqual(counts["Brand"], 1)
        XCTAssertEqual(counts["Strategy"], 1)
    }

    func testReplaceFolderNameUpdatesInPlace() throws {
        try cache.upsert(makeMeta(uid: "rn111111", folderName: "2024_old_rn111111"))
        try cache.replaceFolderName(uid: "rn111111", newFolderName: "2025_new_rn111111")
        let loaded = try cache.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].folderName, "2025_new_rn111111")
        XCTAssertEqual(loaded[0].uid, "rn111111")
    }
}
```

- [ ] **Step 4: Regenerate Xcode project + run tests to verify they fail**

Run:
```bash
cd <repo> && xcodegen generate
```
Expected: `Created project at PortyMcFolio.xcodeproj`.

Then:
```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' -only-testing:PortyMcFolioTests/ProjectMetadataCacheTests CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E '(error:|Test Case.*failed|FAIL)' | head -10
```
Expected: compile errors (`Cannot find 'ProjectMetadataCache' in scope`, `Cannot find 'CachedProjectMeta' in scope`).

- [ ] **Step 5: Implement ProjectMetadataCache**

Create `PortyMcFolio/Services/ProjectMetadataCache.swift`:

```swift
import Foundation
import GRDB

struct CachedProjectMeta: Equatable {
    let uid: String
    let folderName: String
    let year: Int
    var title: String
    var client: String
    var status: ProjectStatus
    var tags: [String]
    var teaser: String
    var body: String
    var hidden: Bool
    var date: Date
    var frontmatterMTime: Date
}

final class ProjectMetadataCache {
    private let db: DatabaseQueue

    init(db: DatabaseQueue) throws {
        self.db = db
        try migrate()
    }

    private func migrate() throws {
        try db.write { conn in
            try conn.execute(sql: """
                CREATE TABLE IF NOT EXISTS project_meta (
                    uid               TEXT PRIMARY KEY,
                    folder_name       TEXT NOT NULL,
                    year              INTEGER NOT NULL,
                    title             TEXT NOT NULL,
                    client            TEXT NOT NULL,
                    status            TEXT NOT NULL,
                    tags_json         TEXT NOT NULL,
                    teaser            TEXT NOT NULL,
                    body              TEXT NOT NULL,
                    hidden            INTEGER NOT NULL,
                    date_iso          TEXT NOT NULL,
                    frontmatter_mtime REAL NOT NULL,
                    cached_at         REAL NOT NULL
                )
                """)
            try conn.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_project_meta_year ON project_meta(year)
                """)
        }
    }

    // MARK: - Public API (own-transaction)

    func loadAll() throws -> [CachedProjectMeta] {
        try db.read { conn in
            let rows = try Row.fetchAll(conn, sql: """
                SELECT uid, folder_name, year, title, client, status,
                       tags_json, teaser, body, hidden, date_iso, frontmatter_mtime
                FROM project_meta
                """)
            return rows.compactMap(Self.decode)
        }
    }

    func upsert(_ meta: CachedProjectMeta) throws {
        try db.write { conn in try Self.upsert(conn, meta) }
    }

    func remove(uid: String) throws {
        try db.write { conn in try Self.remove(conn, uid: uid) }
    }

    func clear() throws {
        try db.write { conn in
            try conn.execute(sql: "DELETE FROM project_meta")
        }
    }

    func replaceFolderName(uid: String, newFolderName: String) throws {
        try db.write { conn in
            try conn.execute(
                sql: "UPDATE project_meta SET folder_name = ?, cached_at = ? WHERE uid = ?",
                arguments: [newFolderName, Date().timeIntervalSince1970, uid]
            )
        }
    }

    func aggregateTagCounts() throws -> [String: Int] {
        let rows = try db.read { conn in
            try Row.fetchAll(conn, sql: "SELECT tags_json FROM project_meta")
        }
        var counts: [String: Int] = [:]
        for row in rows {
            let tagsJson: String = row["tags_json"]
            guard let data = tagsJson.data(using: .utf8),
                  let tags = try? JSONDecoder().decode([String].self, from: data) else { continue }
            for tag in tags { counts[tag, default: 0] += 1 }
        }
        return counts
    }

    // MARK: - In-transaction variants (for atomic cache + FTS writes)

    func upsertWithin(_ db: Database, _ meta: CachedProjectMeta) throws {
        try Self.upsert(db, meta)
    }

    func removeWithin(_ db: Database, uid: String) throws {
        try Self.remove(db, uid: uid)
    }

    // MARK: - Private helpers

    private static func upsert(_ conn: Database, _ meta: CachedProjectMeta) throws {
        let tagsData = try JSONEncoder().encode(meta.tags)
        let tagsJson = String(data: tagsData, encoding: .utf8) ?? "[]"
        let isoFormatter = ISO8601DateFormatter()
        try conn.execute(sql: """
            INSERT INTO project_meta
                (uid, folder_name, year, title, client, status,
                 tags_json, teaser, body, hidden, date_iso, frontmatter_mtime, cached_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(uid) DO UPDATE SET
                folder_name = excluded.folder_name,
                year = excluded.year,
                title = excluded.title,
                client = excluded.client,
                status = excluded.status,
                tags_json = excluded.tags_json,
                teaser = excluded.teaser,
                body = excluded.body,
                hidden = excluded.hidden,
                date_iso = excluded.date_iso,
                frontmatter_mtime = excluded.frontmatter_mtime,
                cached_at = excluded.cached_at
            """, arguments: [
                meta.uid, meta.folderName, meta.year, meta.title, meta.client, meta.status.rawValue,
                tagsJson, meta.teaser, meta.body, meta.hidden ? 1 : 0,
                isoFormatter.string(from: meta.date),
                meta.frontmatterMTime.timeIntervalSince1970,
                Date().timeIntervalSince1970
            ])
    }

    private static func remove(_ conn: Database, uid: String) throws {
        try conn.execute(sql: "DELETE FROM project_meta WHERE uid = ?", arguments: [uid])
    }

    private static func decode(_ row: Row) -> CachedProjectMeta? {
        let uid: String = row["uid"]
        let tagsJson: String = row["tags_json"]
        guard let data = tagsJson.data(using: .utf8),
              let tags = try? JSONDecoder().decode([String].self, from: data) else {
            print("[Cache] dropping corrupt row uid=\(uid) (bad tags_json)")
            return nil
        }
        let statusRaw: String = row["status"]
        let status = ProjectStatus(rawValue: statusRaw) ?? .empty
        let dateIso: String = row["date_iso"]
        let date = ISO8601DateFormatter().date(from: dateIso) ?? Date(timeIntervalSince1970: 0)
        let mtimeSec: Double = row["frontmatter_mtime"]
        let hiddenInt: Int = row["hidden"]
        return CachedProjectMeta(
            uid: uid,
            folderName: row["folder_name"],
            year: row["year"],
            title: row["title"],
            client: row["client"],
            status: status,
            tags: tags,
            teaser: row["teaser"],
            body: row["body"],
            hidden: hiddenInt != 0,
            date: date,
            frontmatterMTime: Date(timeIntervalSince1970: mtimeSec)
        )
    }
}
```

- [ ] **Step 6: Regenerate Xcode project + run tests to verify they pass**

Run:
```bash
cd <repo> && xcodegen generate
```
Then:
```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' -only-testing:PortyMcFolioTests/ProjectMetadataCacheTests CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E '(Test Case|passed|failed|error:|Executed)' | tail -15
```
Expected: 10 cases passed.

- [ ] **Step 7: Run the full suite to confirm no regressions**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E '(Executed|failed|error:)' | tail -3
```
Expected: `Executed N tests, with 0 failures` (N = previous + 10).

- [ ] **Step 8: Commit**

```bash
git add PortyMcFolio/Models/Project.swift \
        PortyMcFolio/Services/SearchIndex.swift \
        PortyMcFolio/Services/ProjectMetadataCache.swift \
        PortyMcFolioTests/ProjectMetadataCacheTests.swift \
        PortyMcFolio.xcodeproj
git commit -m "feat: ProjectMetadataCache + Project.frontmatterMTime + schema v3"
```

---

## Task 2: SearchIndex incremental methods

Add the in-transaction methods the reconciler will use. Existing `rebuild(...)` stays for the "Re-index everything" command and schema migration. No behavior change yet.

**Files:**
- Modify: `PortyMcFolio/Services/SearchIndex.swift`
- Modify: `PortyMcFolioTests/SearchIndexTests.swift`

- [ ] **Step 1: Write failing tests for the new methods**

Append to `PortyMcFolioTests/SearchIndexTests.swift`, inside the existing `final class SearchIndexTests: XCTestCase` body:

```swift
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
            body: "",
            hidden: false,
            date: Date(timeIntervalSince1970: 0),
            frontmatterMTime: Date(timeIntervalSince1970: 0)
        )
    }

    private func cachedMeta(from project: Project) -> CachedProjectMeta {
        cachedMeta(uid: project.uid, title: project.title, tags: project.tags)
    }
```

Note: `testHelper_upsertProjectInOwnTransaction` is a test-only wrapper (added in Step 3) that calls the in-transaction `upsertProjectWithin` from inside its own `db.write { ... }`. The reconciler will use it inside a shared transaction; tests need a way to call it standalone.

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' -only-testing:PortyMcFolioTests/SearchIndexTests CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E '(error:|Test Case.*failed|FAIL)' | head -10
```
Expected: compile errors (`type 'SearchIndex' has no member 'upsertProjectWithin'`, etc.).

- [ ] **Step 3: Implement the new SearchIndex methods**

In `PortyMcFolio/Services/SearchIndex.swift`, append these methods inside the `final class SearchIndex` body (after the existing `removeProject` method, before the `MARK: - Search` divider):

```swift
    // MARK: - Incremental updates (in-transaction)

    /// Replace all FTS rows for a single project (project + files + links).
    /// Tag rows are NOT updated here — call `rebuildTags(from:)` once per batch instead.
    /// Caller wraps this in `db.write { conn in ... }` together with cache.upsertWithin
    /// so cache + FTS commit atomically.
    func upsertProjectWithin(
        _ conn: Database,
        meta: CachedProjectMeta,
        fileEntries: [(fileName: String, relativePath: String, fileNameNoExt: String)],
        linkEntries: [LinkItem]
    ) throws {
        // Drop existing project + file + link rows for this uid
        try conn.execute(
            sql: "DELETE FROM search_fts WHERE type = 'project' AND entity_id = ?",
            arguments: [meta.uid]
        )
        try conn.execute(
            sql: "DELETE FROM search_fts WHERE parent_uid = ?",
            arguments: [meta.uid]
        )

        // Insert project row from cached meta (no need to re-read the .md file)
        let bodyContent = [meta.tags.joined(separator: " "), meta.status.rawValue, meta.body]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        try conn.execute(
            sql: """
                INSERT INTO search_fts (type, entity_id, parent_uid, primary_text, secondary_text, body)
                VALUES ('project', ?, '', ?, ?, ?)
                """,
            arguments: [meta.uid, meta.title, meta.client, bodyContent]
        )

        for f in fileEntries {
            try conn.execute(
                sql: """
                    INSERT INTO search_fts (type, entity_id, parent_uid, primary_text, secondary_text, body)
                    VALUES ('file', ?, ?, ?, ?, ?)
                    """,
                arguments: [f.relativePath, meta.uid, f.fileName, meta.title, f.fileNameNoExt]
            )
        }

        for link in linkEntries {
            let bodyContent = [link.url.absoluteString, link.annotation]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            let secondary = [link.url.host ?? "", meta.title]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            try conn.execute(
                sql: """
                    INSERT INTO search_fts (type, entity_id, parent_uid, primary_text, secondary_text, body)
                    VALUES ('link', ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    link.uid, meta.uid,
                    link.title.isEmpty ? (link.url.host ?? "") : link.title,
                    secondary, bodyContent
                ]
            )
        }
    }

    /// Append file + link FTS rows for a project that already has its project row in FTS.
    /// Used after lazy populateFiles so file/link search becomes available for that project.
    /// Existing file/link rows for the project are cleared first (idempotent).
    func appendFilesAndLinks(
        forProjectUID uid: String,
        fileEntries: [(fileName: String, relativePath: String, fileNameNoExt: String)],
        linkEntries: [LinkItem]
    ) throws {
        try db.write { conn in
            try conn.execute(
                sql: "DELETE FROM search_fts WHERE parent_uid = ? AND type IN ('file', 'link')",
                arguments: [uid]
            )

            // Resolve project title for link secondary_text
            let titleRow = try Row.fetchOne(
                conn,
                sql: "SELECT primary_text FROM search_fts WHERE type = 'project' AND entity_id = ?",
                arguments: [uid]
            )
            let projectTitle: String = (titleRow?["primary_text"] as? String) ?? ""

            for f in fileEntries {
                try conn.execute(
                    sql: """
                        INSERT INTO search_fts (type, entity_id, parent_uid, primary_text, secondary_text, body)
                        VALUES ('file', ?, ?, ?, ?, ?)
                        """,
                    arguments: [f.relativePath, uid, f.fileName, projectTitle, f.fileNameNoExt]
                )
            }
            for link in linkEntries {
                let bodyContent = [link.url.absoluteString, link.annotation]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                let secondary = [link.url.host ?? "", projectTitle]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                try conn.execute(
                    sql: """
                        INSERT INTO search_fts (type, entity_id, parent_uid, primary_text, secondary_text, body)
                        VALUES ('link', ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        link.uid, uid,
                        link.title.isEmpty ? (link.url.host ?? "") : link.title,
                        secondary, bodyContent
                    ]
                )
            }
        }
    }

    /// Recompute all 'tag' FTS rows from the cache. O(#tags). Call once per reconciliation batch.
    func rebuildTags(from cache: ProjectMetadataCache) throws {
        let counts = try cache.aggregateTagCounts()
        try db.write { conn in
            try conn.execute(sql: "DELETE FROM search_fts WHERE type = 'tag'")
            for (tag, count) in counts {
                try conn.execute(
                    sql: """
                        INSERT INTO search_fts (type, entity_id, parent_uid, primary_text, secondary_text, body)
                        VALUES ('tag', ?, '', ?, ?, '')
                        """,
                    arguments: [tag, tag, "\(count) project\(count == 1 ? "" : "s")"]
                )
            }
        }
    }

    // MARK: - Test-only helper

    #if DEBUG
    /// Test-only wrapper that calls upsertProjectWithin inside its own transaction.
    /// Production code should call upsertProjectWithin within a shared db.write block.
    func testHelper_upsertProjectInOwnTransaction(
        meta: CachedProjectMeta,
        fileEntries: [(fileName: String, relativePath: String, fileNameNoExt: String)],
        linkEntries: [LinkItem]
    ) throws {
        try db.write { conn in
            try upsertProjectWithin(conn, meta: meta, fileEntries: fileEntries, linkEntries: linkEntries)
        }
    }
    #endif
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' -only-testing:PortyMcFolioTests/SearchIndexTests CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E '(Test Case|passed|failed|error:|Executed)' | tail -20
```
Expected: all SearchIndexTests cases pass (existing 13 + new 3 = 16).

- [ ] **Step 5: Run the full suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E '(Executed|failed|error:)' | tail -3
```
Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add PortyMcFolio/Services/SearchIndex.swift \
        PortyMcFolioTests/SearchIndexTests.swift
git commit -m "feat: SearchIndex incremental upsert/append/tag methods"
```

---

## Task 3: ProjectReconciler skeleton (sync + initial reconciliation, no debounce yet)

Create the reconciler with its core sync logic. It's not yet wired into `AppState` — that's Task 4. Tests cover sync + atomic writes + folder rename. Debouncing is added in Task 5.

**Files:**
- Create: `PortyMcFolio/Services/ProjectReconciler.swift`
- Create: `PortyMcFolioTests/ProjectReconcilerTests.swift`

- [ ] **Step 1: Write failing tests for the reconciler**

Create `PortyMcFolioTests/ProjectReconcilerTests.swift`:

```swift
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
        db = try! DatabaseQueue()
        cache = try! ProjectMetadataCache(db: db)
        index = try! SearchIndex(inMemory: true)
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
            status: .empty, tags: [], teaser: "", body: "cached body",
            hidden: false, date: Date(timeIntervalSince1970: 0),
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
            tags: [], teaser: "", body: "cached body", hidden: false,
            date: Date(timeIntervalSince1970: 0),
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
            tags: [], teaser: "", body: "", hidden: false,
            date: Date(timeIntervalSince1970: 0),
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
        createDiskProject(uid: "newp1111", title: "New One")

        let exp2 = expectation(description: "second")
        reconciler.reconcileTopLevel { exp2.fulfill() }
        wait(for: [exp2], timeout: 2)

        let cached = try cache.loadAll()
        XCTAssertEqual(cached.count, 1)
        XCTAssertEqual(cached[0].uid, "newp1111")
    }

    func testProjectFolderRenamedUpdatesFolderNameInPlace() throws {
        let uid = createDiskProject(uid: "rn111111", year: 2024, title: "Before")
        let exp = expectation(description: "init")
        reconciler.startInitialReconciliation { exp.fulfill() }
        wait(for: [exp], timeout: 2)

        try reconciler.projectFolderRenamed(uid: uid, newFolderName: "2025_after_rn111111")

        let cached = try cache.loadAll()
        XCTAssertEqual(cached.count, 1)
        XCTAssertEqual(cached[0].folderName, "2025_after_rn111111")
        XCTAssertEqual(cached[0].uid, "rn111111")
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

        // Corrupt the frontmatter file (write malformed YAML)
        let mdURL = tempRoot.appendingPathComponent(folderName).appendingPathComponent("\(folderName).md")
        try "---\nthis is not: [valid yaml\n".write(to: mdURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: mdURL.path)

        let exp2 = expectation(description: "second")
        reconciler.notifyProjectFileChanged(uid: uid) { exp2.fulfill() }
        wait(for: [exp2], timeout: 2)

        // Cache entry should still be intact (not replaced by garbage)
        let cached = try cache.loadAll()
        XCTAssertEqual(cached.count, 1)
        XCTAssertEqual(cached[0].title, "Good Title")
    }
}
```

- [ ] **Step 2: Implement ProjectReconciler**

Create `PortyMcFolio/Services/ProjectReconciler.swift`:

```swift
import Foundation
import GRDB

final class ProjectReconciler {
    typealias PublishHandler = (Mutation) -> Void

    enum Mutation {
        case insert(Project)
        case update(Project)
        case remove(uid: String)
        case batch([Mutation])
    }

    private let portfolioRoot: URL
    private let db: DatabaseQueue
    private let cache: ProjectMetadataCache
    private let searchIndex: SearchIndex
    private let publish: PublishHandler
    private let queue = DispatchQueue(label: "com.portymcfolio.reconciler", qos: .userInitiated)

    /// Bookkeeping for projects whose files have been lazily populated.
    /// Used by syncProject to decide whether to re-walk file/link rows.
    private var populatedFileUIDs: Set<String> = []

    init(
        portfolioRoot: URL,
        db: DatabaseQueue,
        cache: ProjectMetadataCache,
        searchIndex: SearchIndex,
        publish: @escaping PublishHandler
    ) {
        self.portfolioRoot = portfolioRoot
        self.db = db
        self.cache = cache
        self.searchIndex = searchIndex
        self.publish = publish
    }

    func shutdown() {
        // Synchronous barrier: drain any in-flight work before returning.
        queue.sync { }
    }

    // MARK: - Public entry points

    /// Initial reconciliation pass — top-level scan + per-project sync for all uids
    /// (those on disk and those in cache). `completion` runs on the reconciler queue
    /// after the pass finishes.
    func startInitialReconciliation(completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            self?.runReconciliationPass()
            completion?()
        }
    }

    /// Top-level scan only — finds new/deleted project folders. Used between launches
    /// and from inside `enqueue` (Task 5).
    func reconcileTopLevel(completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            self?.runReconciliationPass()
            completion?()
        }
    }

    /// Sync a single project immediately (no debounce). Used by direct-poke callers
    /// (editor save, settings popover save, gallery teaser/rename writes).
    func notifyProjectFileChanged(uid: String, completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            self.syncProject(uid: uid)
            // Tags depend on cache aggregate — refresh after each direct-poke sync.
            try? self.searchIndex.rebuildTags(from: self.cache)
            completion?()
        }
    }

    /// Update the cached folder_name for a project after AppState renames the folder.
    /// Avoids the delete+add flicker that would happen if we waited for FSEvents.
    func projectFolderRenamed(uid: String, newFolderName: String) throws {
        try cache.replaceFolderName(uid: uid, newFolderName: newFolderName)
        // Republish so the UI sees the new folderName
        if let entry = try cache.loadAll().first(where: { $0.uid == uid }) {
            publish(.update(Self.project(from: entry, root: portfolioRoot)))
        }
    }

    // MARK: - Internal: reconciliation pass

    private func runReconciliationPass() {
        // 1. List on-disk uids
        let onDiskFolders = scanRootForProjectFolders()
        let onDiskUIDs = Set(onDiskFolders.map(\.uid))

        // 2. List cached uids
        let cachedUIDs: Set<String>
        do {
            cachedUIDs = Set(try cache.loadAll().map(\.uid))
        } catch {
            print("[Reconciler] cache.loadAll failed: \(error)")
            return
        }

        // 3. Sync union of (onDisk ∪ cached). Each call decides what to do.
        let allUIDs = onDiskUIDs.union(cachedUIDs)
        for uid in allUIDs {
            syncProject(uid: uid)
        }

        // 4. Recompute tag rows once per pass.
        do {
            try searchIndex.rebuildTags(from: cache)
        } catch {
            print("[Reconciler] rebuildTags failed: \(error)")
        }
    }

    /// Sync a single project. Caller is the reconciler queue.
    private func syncProject(uid: String) {
        // Locate the project folder on disk by scanning (uid may correspond to a
        // folder whose name we don't know yet, e.g., after a rename).
        let onDiskFolder = scanRootForProjectFolders().first { $0.uid == uid }

        // Project deleted?
        guard let folderInfo = onDiskFolder else {
            do {
                try db.write { conn in
                    try cache.removeWithin(conn, uid: uid)
                }
                try searchIndex.removeProject(uid: uid)
                publish(.remove(uid: uid))
                populatedFileUIDs.remove(uid)
            } catch {
                print("[Reconciler] removal write failed for uid=\(uid): \(error)")
            }
            return
        }

        let readmeURL = readmeURL(forFolder: folderInfo.folderURL, folderName: folderInfo.folderName)
        guard let mtime = mtimeOf(readmeURL) else { return }

        let cachedEntry: CachedProjectMeta? = (try? cache.loadAll())?
            .first { $0.uid == uid }

        // Up-to-date and no in-memory file population? Skip entirely.
        if let cached = cachedEntry,
           cached.frontmatterMTime.timeIntervalSince1970 == mtime.timeIntervalSince1970,
           !populatedFileUIDs.contains(uid) {
            return
        }

        // Re-parse frontmatter
        guard let content = try? String(contentsOf: readmeURL, encoding: .utf8),
              let parsed = try? FrontmatterParser.parse(content) else {
            print("[Reconciler] parse failed for uid=\(uid) — leaving cache as-is")
            return
        }

        let meta = CachedProjectMeta(
            uid: uid,
            folderName: folderInfo.folderName,
            year: folderInfo.year,
            title: parsed.title,
            client: parsed.client,
            status: parsed.status,
            tags: parsed.tags,
            teaser: parsed.teaser,
            body: parsed.body,
            hidden: parsed.hidden,
            date: parsed.date,
            frontmatterMTime: mtime
        )

        let isInsert = (cachedEntry == nil)

        // Atomic cache + FTS write in a single transaction.
        do {
            try db.write { conn in
                try cache.upsertWithin(conn, meta)
                try searchIndex.upsertProjectWithin(
                    conn, meta: meta,
                    fileEntries: [],   // file/link rows added via lazy populate (Task 6)
                    linkEntries: []
                )
            }
        } catch {
            print("[Reconciler] atomic write failed for uid=\(uid): \(error)")
            return
        }

        let project = Self.project(from: meta, root: portfolioRoot)
        publish(isInsert ? .insert(project) : .update(project))
    }

    // MARK: - Internal helpers (some exposed for tests)

    struct OnDiskFolder {
        let uid: String
        let year: Int
        let folderName: String
        let folderURL: URL
    }

    private func scanRootForProjectFolders() -> [OnDiskFolder] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: portfolioRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [OnDiskFolder] = []
        for url in contents {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }
            let folderName = url.lastPathComponent
            guard let project = try? Project.from(folderName: folderName, rootURL: portfolioRoot) else { continue }
            result.append(OnDiskFolder(uid: project.uid, year: project.year, folderName: folderName, folderURL: url))
        }
        return result
    }

    private func readmeURL(forFolder folderURL: URL, folderName: String) -> URL {
        let projectFile = folderURL.appendingPathComponent("\(folderName).md")
        if FileManager.default.fileExists(atPath: projectFile.path) { return projectFile }
        return folderURL.appendingPathComponent("README.md")
    }

    private func mtimeOf(_ url: URL) -> Date? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attrs[.modificationDate] as? Date
    }

    /// Resolve an FSEvent path to a project uid. Exposed for testing; debounce + dispatch
    /// added in Task 5.
    func uidFromEventPath(_ path: String) -> String? {
        let rootPrefix = portfolioRoot.path.hasSuffix("/") ? portfolioRoot.path : portfolioRoot.path + "/"
        guard path.hasPrefix(rootPrefix) else { return nil }
        let relative = String(path.dropFirst(rootPrefix.count))
        guard !relative.isEmpty else { return nil }
        let firstComponent = String(relative.split(separator: "/").first ?? "")
        guard !firstComponent.isEmpty else { return nil }
        return (try? Project.from(folderName: firstComponent, rootURL: portfolioRoot))?.uid
    }

    /// Build a `Project` value from a cached metadata entry.
    static func project(from meta: CachedProjectMeta, root: URL) -> Project {
        Project(
            uid: meta.uid,
            year: meta.year,
            folderName: meta.folderName,
            folderURL: root.appendingPathComponent(meta.folderName),
            title: meta.title,
            date: meta.date,
            tags: meta.tags,
            client: meta.client,
            status: meta.status,
            body: meta.body,
            teaser: meta.teaser,
            hidden: meta.hidden,
            filePaths: [],
            frontmatterMTime: meta.frontmatterMTime
        )
    }
}
```

- [ ] **Step 3: Regenerate Xcode project + run tests to verify they pass**

```bash
cd <repo> && xcodegen generate
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' -only-testing:PortyMcFolioTests/ProjectReconcilerTests CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E '(Test Case|passed|failed|error:|Executed)' | tail -25
```
Expected: 9 tests pass.

- [ ] **Step 4: Run the full suite to confirm no regressions**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E '(Executed|failed|error:)' | tail -3
```
Expected: 0 failures.

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Services/ProjectReconciler.swift \
        PortyMcFolioTests/ProjectReconcilerTests.swift \
        PortyMcFolio.xcodeproj
git commit -m "feat: ProjectReconciler skeleton with sync + initial reconciliation"
```

---

## Task 4: AppState cutover (the big one)

`AppState` stops doing direct disk I/O. It loads cached metadata synchronously, then asks the reconciler to validate against disk in the background. Old `performScan` / `enumerateFiles` / `cachedLinks` are deleted. FileWatcher routes through the reconciler (immediate, no debounce — debouncing comes in Task 5).

**Behavior change at this point:**
- Cold start visible UI in ~50-200ms even on large portfolios.
- File copy storms still trigger one full reconciliation per FSEvent batch (no debounce yet → Task 5).
- ⌘K file/link search returns empty for never-opened projects (lazy population not yet wired → Task 6). **This is acceptable for one task**; users can still find projects by title/tags/client.

**Files:**
- Modify: `PortyMcFolio/App/AppState.swift`
- Modify: `PortyMcFolio/Services/SearchIndex.swift` (expose `metaTable` reads/writes for last-portfolio-root persistence)

- [ ] **Step 1: Add `lastPortfolioRoot` accessors to SearchIndex**

In `PortyMcFolio/Services/SearchIndex.swift`, append these methods inside the `final class SearchIndex` body (after the existing `clearAll` method, before `removeProject`):

```swift
    // MARK: - Last-portfolio-root persistence (in the existing meta table)

    func lastPortfolioRoot() -> String? {
        try? db.read { conn in
            try Row.fetchOne(
                conn,
                sql: "SELECT value FROM meta WHERE key = 'portfolio_root_path'"
            )?["value"] as? String
        } ?? nil
    }

    func setLastPortfolioRoot(_ path: String) throws {
        try db.write { conn in
            try conn.execute(
                sql: "INSERT OR REPLACE INTO meta (key, value) VALUES ('portfolio_root_path', ?)",
                arguments: [path]
            )
        }
    }
```

- [ ] **Step 2: Refactor AppState — replace performScan with reconciler delegation**

In `PortyMcFolio/App/AppState.swift`, locate the `setRoot(_:)` method (around line 186). Read the existing implementation; you'll be rewriting it.

Replace the entire `setRoot(_:)` method with this version:

```swift
    func setRoot(_ url: URL) {
        // Stop accessing the previously held security-scoped resource before switching
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil

        guard url.startAccessingSecurityScopedResource() else { return }
        accessedURL = url

        saveBookmark(for: url)

        // Tear down old reconciler (if any) before constructing fresh state
        reconciler?.shutdown()
        reconciler = nil
        fileWatcher?.stop()
        fileWatcher = nil

        // Clear old state before loading new root
        selectedProject = nil
        projects = []
        searchQuery = ""

        portfolioRootURL = url
        portfolioStore = PortfolioStore(rootURL: url)

        // Construct (or reuse) the SQLite-backed search index + cache.
        do {
            let newIndex = try SearchIndex()
            self.searchIndex = newIndex

            // If the user switched portfolios, wipe the cache + FTS to avoid mixing.
            if let prevPath = newIndex.lastPortfolioRoot(), prevPath != url.path {
                try? newIndex.clearAll()
                self.cache = try ProjectMetadataCache(db: newIndex.databaseQueueForReconciler())
                try? self.cache?.clear()
            } else if self.cache == nil {
                self.cache = try ProjectMetadataCache(db: newIndex.databaseQueueForReconciler())
            }
            try? newIndex.setLastPortfolioRoot(url.path)
        } catch {
            print("[AppState] SearchIndex/cache init failed: \(error). Will retry on refresh.")
            self.searchIndex = nil
            self.cache = nil
        }

        // Synchronously load cached metadata into self.projects so the UI is immediately populated.
        if let cache = self.cache {
            let cached = (try? cache.loadAll()) ?? []
            self.projects = cached.map { ProjectReconciler.project(from: $0, root: url) }
        }
        // Mark ready as soon as we've loaded cached state — the reconciler runs in the background.
        if !isReady { isReady = true }

        // Construct + start the reconciler.
        if let cache = self.cache, let index = self.searchIndex {
            let recon = ProjectReconciler(
                portfolioRoot: url,
                db: index.databaseQueueForReconciler(),
                cache: cache,
                searchIndex: index,
                publish: { [weak self] mutation in
                    Task { @MainActor [weak self] in
                        self?.applyMutation(mutation)
                    }
                }
            )
            self.reconciler = recon

            // Initial background reconciliation against disk.
            recon.startInitialReconciliation()

            // Wire FileWatcher → reconciler (immediate sync; debounce arrives in Task 5).
            fileWatcher = FileWatcher(path: url.path) { [weak recon] paths in
                guard let recon else { return }
                // For now: any FSEvent triggers a top-level reconcile.
                // Task 5 replaces this with debouncing + per-uid sync.
                recon.reconcileTopLevel()
            }
            fileWatcher?.start()
        }
    }
```

- [ ] **Step 3: Add the new fields + helper to AppState**

Still in `AppState.swift`, locate the section with `private var portfolioStore: PortfolioStore?` etc. (around line 67). Add the new fields:

```swift
    private var portfolioStore: PortfolioStore?
    private(set) var searchIndex: SearchIndex?
    /// Cached project metadata, shared with the reconciler.
    private(set) var cache: ProjectMetadataCache?
    /// Background reconciler that owns disk sync.
    private(set) var reconciler: ProjectReconciler?

    private var refreshTask: Task<Void, Never>?  // DEPRECATED — kept for compile only; remove in this task
    private var scanTask: Task<ScanResult?, Never>?  // DEPRECATED — kept for compile only; remove in this task
```

Then add this MainActor helper near the bottom of the class (just before the closing `}`):

```swift
    /// Apply a mutation published by the reconciler. Runs on MainActor.
    private func applyMutation(_ mutation: ProjectReconciler.Mutation) {
        switch mutation {
        case .insert(let project):
            // De-duplicate in case both inserts and re-inserts arrive
            if !projects.contains(where: { $0.uid == project.uid }) {
                projects.append(project)
            } else {
                applyMutation(.update(project))
            }
        case .update(let project):
            if let idx = projects.firstIndex(where: { $0.uid == project.uid }) {
                projects[idx] = project
                if selectedProject?.uid == project.uid {
                    selectedProject = project
                }
            } else {
                projects.append(project)
            }
        case .remove(let uid):
            projects.removeAll { $0.uid == uid }
            if selectedProject?.uid == uid {
                selectedProject = nil
            }
        case .batch(let mutations):
            for m in mutations { applyMutation(m) }
        }
    }
```

- [ ] **Step 4: Replace `refreshProjects` with reconciler delegation**

Still in `AppState.swift`, find the existing `refreshProjects(thenSelect:)` method (around line 221). Replace its entire body with:

```swift
    func refreshProjects(thenSelect uid: String? = nil) {
        guard let recon = reconciler else { return }
        recon.reconcileTopLevel { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let uid else { return }
                self.selectedProject = self.projects.first { $0.uid == uid }
            }
        }
    }
```

- [ ] **Step 5: Delete the dead `performScan` / `enumerateFiles` / cachedLinks state**

Still in `AppState.swift`, **delete** the following entirely:

- The `cachedLinks: [CachedLink]` property and its `CachedLink` struct definition (around lines 58-65).
- The `private struct ScanResult: Sendable { ... }` definition.
- The `private nonisolated static func performScan(...)` method.
- The `private nonisolated static func enumerateFiles(...)` method.
- The `private var refreshTask: Task<Void, Never>?` and `private var scanTask: Task<ScanResult?, Never>?` properties added in Step 3 (they were transitional).

Also find and update `filteredProjects` — it currently references `project.filePaths.contains { $0.lowercased().contains(q) }` in the substring fallback. Remove that substring check (filePaths is now lazy and may be empty):

```swift
    var filteredProjects: [Project] {
        let base = hideHiddenProjects ? projects.filter { !$0.hidden } : projects

        guard !searchQuery.isEmpty else {
            return base
        }

        // Try FTS search first
        if let index = searchIndex,
           let results = try? index.search(query: searchQuery), !results.isEmpty {
            var matchingUIDs = Set<String>()
            for result in results {
                if result.type == .project {
                    matchingUIDs.insert(result.entityID)
                } else if !result.parentUID.isEmpty {
                    matchingUIDs.insert(result.parentUID)
                }
            }
            let matched = base.filter { matchingUIDs.contains($0.uid) }
            if !matched.isEmpty { return matched }
        }

        // Fallback: substring on metadata (no longer searches filePaths — lazy)
        let q = searchQuery.lowercased()
        return base.filter { project in
            project.title.lowercased().contains(q) ||
            project.client.lowercased().contains(q) ||
            project.tags.contains { $0.lowercased().contains(q) } ||
            project.folderName.lowercased().contains(q) ||
            project.status.displayName.lowercased().contains(q)
        }
    }
```

- [ ] **Step 6: Expose the DatabaseQueue from SearchIndex**

`AppState.setRoot` references `index.databaseQueueForReconciler()` — add it. In `PortyMcFolio/Services/SearchIndex.swift`, the `db` property is `private`. Add a package-internal accessor near the top of the class:

```swift
    /// Exposes the underlying DatabaseQueue so the reconciler can wrap cache + FTS
    /// writes in a single transaction. Do not use from views.
    func databaseQueueForReconciler() -> DatabaseQueue { db }
```

- [ ] **Step 7: Update the SearchPalette commands list (CachedLink references)**

Search for any remaining references to `appState.cachedLinks` in the codebase:

```bash
grep -rn "cachedLinks" PortyMcFolio/
```

Expected: hits in `SearchPalette.swift` (`matchLinks` reads from `appState.cachedLinks`).

In `PortyMcFolio/Views/SearchPalette.swift`, find the `matchLinks` method. Since `cachedLinks` is now empty (link population is lazy until Task 6), update `matchLinks` to return `[]` for now, with a comment:

```swift
    private func matchLinks(_ query: String, excluding hiddenUIDs: Set<String>) -> [SearchResult] {
        // Link substring fallback is disabled until Task 6 wires up lazy link population.
        // FTS link results still flow through the main path (executed in the body above).
        return []
    }
```

- [ ] **Step 8: Build to verify it compiles**

```bash
xcodebuild build -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | grep -E '(error:|warning:|BUILD)' | tail -15
```
Expected: `BUILD SUCCEEDED`. Some warnings are acceptable; no errors.

- [ ] **Step 9: Run the full test suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E '(Executed|failed|error:)' | tail -3
```
Expected: 0 failures.

- [ ] **Step 10: Manual smoke test**

This task is the cutover — the running app's behavior changes meaningfully. Launch the app from Xcode (⌘R) on a real portfolio and verify:

1. App launches; project list appears.
2. Click a project → detail view opens.
3. Edit a project's frontmatter via Finder (e.g., open `{folder}.md` in TextEdit, change title, save). Within ~1s, the project list reflects the new title.
4. Drop a file into a project folder via Finder. Switch to gallery mode. The new file appears.
5. Quit + relaunch. App opens to the project list within ~500ms (vs. multi-second before this change).

If any step fails, fix before committing.

- [ ] **Step 11: Commit**

```bash
git add PortyMcFolio/App/AppState.swift \
        PortyMcFolio/Services/SearchIndex.swift \
        PortyMcFolio/Views/SearchPalette.swift
git commit -m "feat: AppState cutover — reconciler + cached metadata launch"
```

---

## Task 5: FSEvent debouncing + per-uid sync

Replace the "any event → full top-level reconcile" wiring with a debouncer that coalesces bursts and dispatches per-uid syncs (with one cheap top-level scan per batch for new/deleted folders).

**Files:**
- Modify: `PortyMcFolio/Services/ProjectReconciler.swift`
- Modify: `PortyMcFolio/App/AppState.swift` (FileWatcher callback now calls `enqueue` instead of `reconcileTopLevel`)
- Create: `PortyMcFolioTests/ProjectReconcilerDebounceTests.swift`

- [ ] **Step 1: Write failing tests for the debouncer**

Create `PortyMcFolioTests/ProjectReconcilerDebounceTests.swift`:

```swift
import XCTest
import GRDB
@testable import PortyMcFolio

final class ProjectReconcilerDebounceTests: XCTestCase {
    var tempRoot: URL!
    var db: DatabaseQueue!
    var cache: ProjectMetadataCache!
    var index: SearchIndex!
    var reconciler: ProjectReconciler!
    var passCount = 0

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectReconcilerDebounceTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        db = try! DatabaseQueue()
        cache = try! ProjectMetadataCache(db: db)
        index = try! SearchIndex(inMemory: true)
        passCount = 0
        reconciler = ProjectReconciler(
            portfolioRoot: tempRoot,
            db: db, cache: cache, searchIndex: index,
            publish: { _ in }
        )
        reconciler.testHookOnReconciliationPass = { [weak self] in self?.passCount += 1 }
    }

    override func tearDown() {
        reconciler.shutdown()
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    /// Synchronously wait until passCount reaches `target` or `timeout` elapses.
    /// Polls every 25ms.
    private func waitForPasses(_ target: Int, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while passCount < target && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.025))
        }
    }

    func testEnqueueSingleEventTriggersOnePassAfterDebounce() {
        reconciler.enqueue([tempRoot.appendingPathComponent("anything").path])
        waitForPasses(1, timeout: 1.0)
        XCTAssertEqual(passCount, 1)
    }

    func testRapidEnqueueCoalescesIntoOnePass() {
        // Fire 50 events in rapid succession (well within the 250ms debounce window).
        for i in 0..<50 {
            reconciler.enqueue([tempRoot.appendingPathComponent("file\(i)").path])
        }
        waitForPasses(1, timeout: 1.0)
        // Allow a brief grace window to ensure no extra pass slipped in
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(passCount, 1)
    }

    func testSlidingWindowCapsAt1000ms() {
        // Continuously enqueue every 100ms for 1.5 seconds.
        // Without a cap, the sliding window would never fire.
        // With the 1000ms cap, the first pass should fire at ~1.0s.
        let start = Date()
        var deadline = start.addingTimeInterval(1.5)
        while Date() < deadline && passCount == 0 {
            reconciler.enqueue([tempRoot.appendingPathComponent("p").path])
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        // Stop bursting; let the timer drain
        Thread.sleep(forTimeInterval: 0.3)

        XCTAssertGreaterThanOrEqual(passCount, 1, "Expected at least one pass within 1000ms cap")
        // The first pass should have fired before the 1.5s deadline
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThanOrEqual(elapsed, 1.5, "Pass took longer than expected")
    }
}
```

- [ ] **Step 2: Add the debouncer to ProjectReconciler**

In `PortyMcFolio/Services/ProjectReconciler.swift`, add these properties inside the `final class ProjectReconciler` body (after the existing `populatedFileUIDs` property):

```swift
    // MARK: - Debouncer state

    private static let debounceWindow: TimeInterval = 0.25
    private static let debounceCap: TimeInterval = 1.0

    private var pendingPaths: Set<String> = []
    private var debounceTimer: DispatchSourceTimer?
    private var debounceFirstEnqueueAt: Date?

    /// Test hook: invoked at the start of every reconciliation pass.
    var testHookOnReconciliationPass: (() -> Void)?
```

Add the public `enqueue` method (after `notifyProjectFileChanged`, before `projectFolderRenamed`):

```swift
    /// Enqueue paths from an FSEvent batch. Coalesces with other events arriving
    /// within the debounce window. After the window expires, runs one reconciliation
    /// pass that syncs all affected uids and a top-level scan.
    func enqueue(_ paths: [String]) {
        queue.async { [weak self] in
            guard let self else { return }
            let now = Date()
            if self.debounceFirstEnqueueAt == nil {
                self.debounceFirstEnqueueAt = now
            }
            self.pendingPaths.formUnion(paths)
            self.scheduleDebouncedFire(now: now)
        }
    }

    private func scheduleDebouncedFire(now: Date) {
        // Determine fire time: min(now + window, firstEnqueue + cap)
        let earliestFire = now.addingTimeInterval(Self.debounceWindow)
        let cappedFire: Date
        if let first = debounceFirstEnqueueAt {
            cappedFire = first.addingTimeInterval(Self.debounceCap)
        } else {
            cappedFire = earliestFire
        }
        let fireAt = min(earliestFire, cappedFire)
        let delay = max(0, fireAt.timeIntervalSince(now))

        debounceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.fireDebouncedPass()
        }
        timer.resume()
        debounceTimer = timer
    }

    private func fireDebouncedPass() {
        let paths = pendingPaths
        pendingPaths.removeAll()
        debounceFirstEnqueueAt = nil
        debounceTimer?.cancel()
        debounceTimer = nil
        runReconciliationPass(forPaths: paths)
    }
```

Now modify the existing `runReconciliationPass` to accept paths and use them. Replace the existing private method with this overload + helper:

```swift
    private func runReconciliationPass() {
        runReconciliationPass(forPaths: nil)
    }

    private func runReconciliationPass(forPaths paths: Set<String>?) {
        testHookOnReconciliationPass?()

        // 1. Always run a top-level scan to find new/deleted project folders.
        let onDiskFolders = scanRootForProjectFolders()
        let onDiskUIDs = Set(onDiskFolders.map(\.uid))
        let cachedUIDs: Set<String>
        do {
            cachedUIDs = Set(try cache.loadAll().map(\.uid))
        } catch {
            print("[Reconciler] cache.loadAll failed: \(error)")
            return
        }

        // 2. Compute the union of "uids to consider":
        //    - All uids present on disk (handles new projects)
        //    - All cached uids (handles deletions)
        //    - For incremental events: all uids resolved from event paths
        var affectedUIDs = onDiskUIDs.union(cachedUIDs)
        if let paths {
            for path in paths {
                if let uid = uidFromEventPath(path) { affectedUIDs.insert(uid) }
            }
        }

        // 3. Sync each affected uid.
        for uid in affectedUIDs {
            syncProject(uid: uid)
        }

        // 4. Recompute tag rows once per pass.
        do {
            try searchIndex.rebuildTags(from: cache)
        } catch {
            print("[Reconciler] rebuildTags failed: \(error)")
        }
    }
```

Also update `shutdown()` to cancel any pending timer:

```swift
    func shutdown() {
        queue.sync {
            debounceTimer?.cancel()
            debounceTimer = nil
            pendingPaths.removeAll()
            debounceFirstEnqueueAt = nil
        }
    }
```

- [ ] **Step 3: Update AppState to call `enqueue` instead of `reconcileTopLevel`**

In `PortyMcFolio/App/AppState.swift`, find the FileWatcher setup inside `setRoot(_:)` (added in Task 4 Step 2):

```swift
            fileWatcher = FileWatcher(path: url.path) { [weak recon] paths in
                guard let recon else { return }
                // For now: any FSEvent triggers a top-level reconcile.
                // Task 5 replaces this with debouncing + per-uid sync.
                recon.reconcileTopLevel()
            }
```

Replace with:

```swift
            fileWatcher = FileWatcher(path: url.path) { [weak recon] paths in
                guard let recon else { return }
                recon.enqueue(paths)
            }
```

- [ ] **Step 4: Regenerate Xcode project + run debounce tests**

```bash
cd <repo> && xcodegen generate
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' -only-testing:PortyMcFolioTests/ProjectReconcilerDebounceTests CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E '(Test Case|passed|failed|error:|Executed)' | tail -10
```
Expected: 3 tests pass. (These tests use real time + small sleeps; they may take ~3s total. Acceptable.)

- [ ] **Step 5: Run the full suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E '(Executed|failed|error:)' | tail -3
```
Expected: 0 failures.

- [ ] **Step 6: Manual smoke test — file copy storm**

Launch the app on a real portfolio. Drop a folder containing many files (~50+) into a project folder via Finder. Verify:

1. App stays responsive throughout the copy.
2. After the copy finishes, project list updates within ~1s (single batched reconcile, not many).
3. No spinner storms.

- [ ] **Step 7: Commit**

```bash
git add PortyMcFolio/Services/ProjectReconciler.swift \
        PortyMcFolio/App/AppState.swift \
        PortyMcFolioTests/ProjectReconcilerDebounceTests.swift \
        PortyMcFolio.xcodeproj
git commit -m "feat: FSEvent debouncing + per-uid sync in reconciler"
```

---

## Task 6: Lazy file + link population

Implement on-demand file enumeration. Files and link FTS rows are populated when a project is opened OR when ⌘K query has likely matches. Once populated, syncProject re-walks if the project's files were already loaded.

**Files:**
- Modify: `PortyMcFolio/Services/ProjectReconciler.swift`
- Modify: `PortyMcFolio/App/AppState.swift`
- Modify: `PortyMcFolio/Views/SearchPalette.swift`
- Modify: `PortyMcFolioTests/ProjectReconcilerTests.swift` (add 3 lazy-population tests)

- [ ] **Step 1: Write failing tests for lazy population**

In `PortyMcFolioTests/ProjectReconcilerTests.swift`, append these tests inside the existing class body:

```swift
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
        let uid = createDiskProject(uid: "lazy1111")
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
        let uid = createDiskProject(uid: "idem1111")
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

    func testRePopulatesAfterSyncWhenFilesAlreadyLoaded() throws {
        let uid = createDiskProject(uid: "repop111")
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
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' -only-testing:PortyMcFolioTests/ProjectReconcilerTests CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E '(error:|Test Case.*failed|FAIL)' | head -10
```
Expected: compile error (`'ProjectReconciler' has no member 'populateFiles'`).

- [ ] **Step 3: Implement `populateFiles` and re-population**

In `PortyMcFolio/Services/ProjectReconciler.swift`, add these constants near the top of the class (just after `static let debounceCap`):

```swift
    static let lazyPopulateFanout = 10
    static let lazyPopulateMinQueryLength = 2
```

Then add the public `populateFiles` method (placed after `notifyProjectFileChanged`):

```swift
    /// Walk a project folder, populate its file + link FTS rows, and mark the uid
    /// as "files loaded" so future syncProject calls re-walk to keep the index current.
    /// Idempotent — safe to call repeatedly.
    func populateFiles(uid: String, completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            self.populatedFileUIDs.insert(uid)
            self.repopulateFilesForUID(uid)
            completion?()
        }
    }

    private func repopulateFilesForUID(_ uid: String) {
        guard let folder = scanRootForProjectFolders().first(where: { $0.uid == uid }) else { return }
        let entries = enumerateFilesAndLinks(folderURL: folder.folderURL, folderName: folder.folderName)
        do {
            try searchIndex.appendFilesAndLinks(
                forProjectUID: uid,
                fileEntries: entries.files,
                linkEntries: entries.links
            )
        } catch {
            print("[Reconciler] appendFilesAndLinks failed for uid=\(uid): \(error)")
            return
        }
        // Publish updated Project value with new filePaths
        if let cached = (try? cache.loadAll())?.first(where: { $0.uid == uid }) {
            var project = Self.project(from: cached, root: portfolioRoot)
            project.filePaths = entries.files.map { $0.relativePath }
            publish(.update(project))
        }
    }

    private struct EnumeratedEntries {
        let files: [(fileName: String, relativePath: String, fileNameNoExt: String)]
        let links: [LinkItem]
    }

    private func enumerateFilesAndLinks(folderURL: URL, folderName: String) -> EnumeratedEntries {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return EnumeratedEntries(files: [], links: []) }

        var files: [(fileName: String, relativePath: String, fileNameNoExt: String)] = []
        var links: [LinkItem] = []

        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name == "README.md" || name == "\(folderName).md" { continue }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir { continue }

            let relativePath = url.path.replacingOccurrences(
                of: folderURL.path + "/", with: ""
            )

            if LinkItem.isLinkFile(name: name) {
                let fileUID = String(name.dropFirst("link-".count).dropLast(".md".count))
                if let md = try? String(contentsOf: url, encoding: .utf8),
                   let link = try? LinkItem.parse(markdown: md, overrideUID: fileUID) {
                    links.append(link)
                }
            } else {
                files.append((
                    fileName: name,
                    relativePath: relativePath,
                    fileNameNoExt: url.deletingPathExtension().lastPathComponent
                ))
            }
        }
        return EnumeratedEntries(files: files, links: links)
    }
```

Now update `syncProject` to trigger re-population when files are already loaded. Find the existing `syncProject(uid:)` method. After the atomic-write block, just before the publish call (`publish(isInsert ? .insert(project) : .update(project))`), insert this:

```swift
        // If files for this project were already populated in memory, refresh them too.
        if populatedFileUIDs.contains(uid) {
            repopulateFilesForUID(uid)
        }
```

- [ ] **Step 4: Add `setSelectedProject` and `populateFilesForLikelyMatches` to AppState**

In `PortyMcFolio/App/AppState.swift`, add these methods near the end of the class (after `applyMutation`):

```swift
    /// Set the selected project. Triggers lazy file population for the new project
    /// so file/link search returns results for it.
    func setSelectedProject(_ project: Project?) {
        selectedProject = project
        if let project, let recon = reconciler {
            recon.populateFiles(uid: project.uid)
        }
    }

    /// Populate file/link FTS rows for the top metadata-matched projects.
    /// Called by SearchPalette as the user types so file/link results become available.
    func populateFilesForLikelyMatches(query: String) {
        guard let recon = reconciler, let index = searchIndex else { return }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= ProjectReconciler.lazyPopulateMinQueryLength else { return }
        guard let results = try? index.search(query: trimmed), !results.isEmpty else { return }

        // Take the top N project uids that appear in matches (either project hits or via parent_uid)
        var seen: [String] = []
        for r in results {
            let uid: String
            if r.type == .project { uid = r.entityID }
            else if !r.parentUID.isEmpty { uid = r.parentUID }
            else { continue }
            if !seen.contains(uid) { seen.append(uid) }
            if seen.count >= ProjectReconciler.lazyPopulateFanout { break }
        }
        for uid in seen {
            recon.populateFiles(uid: uid)
        }
    }
```

- [ ] **Step 5: Wire SearchPalette to call `populateFilesForLikelyMatches`**

In `PortyMcFolio/Views/SearchPalette.swift`, find the `.onChange(of: query)` handler in `var body` (around line 317):

```swift
        .onChange(of: query) { _, _ in
            grouped = computeGrouped()
            selectedIndex = 0
        }
```

Replace with:

```swift
        .onChange(of: query) { _, newValue in
            grouped = computeGrouped()
            selectedIndex = 0
            // Trigger lazy file/link population so file/link results surface.
            appState.populateFilesForLikelyMatches(query: newValue)
        }
```

- [ ] **Step 6: Update SearchPalette's executeResult to use `setSelectedProject`**

Still in `SearchPalette.swift`, find `executeResult(_ result:)`. The cases for `.project`, `.file`, and `.link` all set `appState.selectedProject = ...` directly. Change them to use `setSelectedProject`:

Replace:

```swift
    private func executeResult(_ result: SearchResult) {
        switch result.type {
        case .project:
            appState.selectedProject = appState.projects.first { $0.uid == result.entityID }
        case .file:
            if let project = appState.projects.first(where: { $0.uid == result.parentUID }) {
                let fileURL = project.folderURL.appendingPathComponent(result.entityID)
                appState.pendingFileSelection = fileURL
                appState.selectedProject = project
            }
        case .link:
            if let project = appState.projects.first(where: { $0.uid == result.parentUID }) {
                appState.pendingLinkID = result.entityID
                appState.selectedProject = project
            }
        case .tag:
            appState.searchQuery = result.entityID
            appState.selectedProject = nil
        case .command:
            break
        }
        isPresented = false
    }
```

With:

```swift
    private func executeResult(_ result: SearchResult) {
        switch result.type {
        case .project:
            appState.setSelectedProject(appState.projects.first { $0.uid == result.entityID })
        case .file:
            if let project = appState.projects.first(where: { $0.uid == result.parentUID }) {
                let fileURL = project.folderURL.appendingPathComponent(result.entityID)
                appState.pendingFileSelection = fileURL
                appState.setSelectedProject(project)
            }
        case .link:
            if let project = appState.projects.first(where: { $0.uid == result.parentUID }) {
                appState.pendingLinkID = result.entityID
                appState.setSelectedProject(project)
            }
        case .tag:
            appState.searchQuery = result.entityID
            appState.setSelectedProject(nil)
        case .command:
            break
        }
        isPresented = false
    }
```

- [ ] **Step 7: Update other call sites that set selectedProject directly**

```bash
grep -rn "appState\.selectedProject = " PortyMcFolio/Views/
```

Expected hits (from prior tasks):
- `ProjectListView.swift` (grid `onOpen`, contextMenu Open buttons, table row `onTapGesture`) — change each `appState.selectedProject = project` to `appState.setSelectedProject(project)`.
- `ProjectDetailView.swift` (back-to-projects button, ⎋ shortcut) — change `appState.selectedProject = nil` to `appState.setSelectedProject(nil)`.

Edit each occurrence to use the setter. The behavioral difference: opening a project now also kicks off lazy file population. Closing a project (`nil`) is a no-op for population.

- [ ] **Step 8: Run lazy-population tests**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' -only-testing:PortyMcFolioTests/ProjectReconcilerTests CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E '(Test Case|passed|failed|error:|Executed)' | tail -20
```
Expected: 12 tests pass (9 from Task 3 + 3 new).

- [ ] **Step 9: Run full suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E '(Executed|failed|error:)' | tail -3
```
Expected: 0 failures.

- [ ] **Step 10: Manual smoke test — search palette**

Launch the app. Open ⌘K palette.

1. Type a project title → project results appear.
2. Open a project, then ⌘K, then type a file name from inside that project → file result appears.
3. Type a query that wouldn't normally match a project, but matches a file in some project. Let it sit for ~1-2s. The file result should appear.

- [ ] **Step 11: Commit**

```bash
git add PortyMcFolio/Services/ProjectReconciler.swift \
        PortyMcFolio/App/AppState.swift \
        PortyMcFolio/Views/SearchPalette.swift \
        PortyMcFolio/Views/ProjectListView.swift \
        PortyMcFolio/Views/ProjectDetailView.swift \
        PortyMcFolioTests/ProjectReconcilerTests.swift
git commit -m "feat: lazy file/link population on project open + search palette"
```

---

## Task 7: Direct-poke wiring + Re-index command

Replace the remaining `appState.refreshProjects()` calls with targeted `notifyProjectFileChanged(uid:)` calls so writes from inside the app don't wait for FSEvent latency. Add the "Re-index portfolio" command to ⌘K.

**Files:**
- Modify: `PortyMcFolio/App/AppState.swift` (add `notifyProjectFileChanged`, `projectFolderRenamed`, `reindexEverything`; update `updateProjectMetadata`)
- Modify: `PortyMcFolio/Services/ProjectReconciler.swift` (add `reindexEverything`)
- Modify: `PortyMcFolio/Views/MarkdownEditorView.swift` (onSave callback)
- Modify: `PortyMcFolio/Views/GalleryView.swift` (setTeaser, updateReadmeReferences)
- Modify: `PortyMcFolio/Models/SearchResult.swift` (add Re-index command)

- [ ] **Step 1: Add `notifyProjectFileChanged`, `projectFolderRenamed`, `reindexEverything` on AppState**

In `PortyMcFolio/App/AppState.swift`, append these methods near the bottom of the class (after `populateFilesForLikelyMatches`):

```swift
    /// Tell the reconciler that a specific project's frontmatter or files were just
    /// modified by code inside the app. Bypasses FSEvent latency.
    func notifyProjectFileChanged(uid: String) {
        reconciler?.notifyProjectFileChanged(uid: uid)
    }

    /// Update the cached folder_name for a project after a folder rename, in place,
    /// avoiding the delete+add flicker that would happen if we waited for FSEvents.
    func projectFolderRenamed(uid: String, newFolderName: String) {
        try? reconciler?.projectFolderRenamed(uid: uid, newFolderName: newFolderName)
    }

    /// Re-walk every project's files and rebuild the file/link FTS rows from scratch.
    /// Triggered from the "Re-index portfolio" command in ⌘K.
    func reindexEverything() {
        reconciler?.reindexEverything()
    }
```

- [ ] **Step 2: Update `updateProjectMetadata` to use direct-poke**

In `AppState.swift`, find the existing `updateProjectMetadata(...)` method (around line 385). Locate the section that handles folder rename (around lines 418-430). Right after the folder rename succeeds, add:

```swift
            // Tell the reconciler about the rename in-place to avoid a UI flicker.
            projectFolderRenamed(uid: project.uid, newFolderName: newFolderName)
```

Then replace the existing `refreshProjects(thenSelect: project.uid)` line at the end of the method with:

```swift
        // Direct-poke the reconciler to sync this project immediately.
        notifyProjectFileChanged(uid: project.uid)
        // Re-select by uid in case the folder was renamed (selectedProject's value
        // may now reference the old folder URL); the publish handler will update.
        if let updated = projects.first(where: { $0.uid == project.uid }) {
            selectedProject = updated
        }
```

- [ ] **Step 3: Add `reindexEverything` to ProjectReconciler**

In `PortyMcFolio/Services/ProjectReconciler.swift`, append this method (after `populateFiles`):

```swift
    /// Re-walk every project on disk and rebuild file/link FTS rows for all of them.
    /// Used by the "Re-index portfolio" command. One-shot; runs on the reconciler queue.
    func reindexEverything(completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            let folders = self.scanRootForProjectFolders()
            for folder in folders {
                self.populatedFileUIDs.insert(folder.uid)
                self.repopulateFilesForUID(folder.uid)
            }
            do {
                try self.searchIndex.rebuildTags(from: self.cache)
            } catch {
                print("[Reconciler] rebuildTags failed during reindexEverything: \(error)")
            }
            completion?()
        }
    }
```

- [ ] **Step 4: Wire `MarkdownEditorView.saveContent` to direct-poke**

In `PortyMcFolio/Views/ProjectDetailView.swift`, find the place where `MarkdownEditorView(readmeURL: project.readmeURL)` is constructed (multiple occurrences in the view modes switch). The `onSave` callback currently calls `appState.refreshProjects()`. Replace each:

```swift
                    MarkdownEditorView(readmeURL: project.readmeURL) { _ in
                        appState.refreshProjects()
                    }
```

with:

```swift
                    MarkdownEditorView(readmeURL: project.readmeURL) { _ in
                        appState.notifyProjectFileChanged(uid: project.uid)
                    }
```

There are two occurrences (in `.editor` and `.split` modes). Update both.

- [ ] **Step 5: Wire `GalleryView` writes to direct-poke**

In `PortyMcFolio/Views/GalleryView.swift`:

a) Find `setTeaser(_ url: URL)` (around line 684). After the existing `try? updated.write(to: project.readmeURL, ...)` line, add:

```swift
        appState.notifyProjectFileChanged(uid: project.uid)
```

b) Find `updateReadmeReferences(...)` (around line 723, as modified earlier in the session). After the existing `try? updated.write(to: project.readmeURL, ...)` line and the `NotificationCenter.default.post(...)`, add:

```swift
        appState.notifyProjectFileChanged(uid: project.uid)
```

These calls are idempotent — even if FSEvents also fires later for the same write, the second sync sees mtime unchanged and no-ops.

- [ ] **Step 6: Add the Re-index portfolio command**

In `PortyMcFolio/Models/SearchResult.swift`, add a third entry to the `SearchCommand.allCommands` array (after the "Guide" command):

```swift
        SearchCommand(
            id: "cmd-reindex",
            name: "Re-index portfolio",
            icon: "arrow.clockwise",
            shortcut: nil
        ) { state in
            state.reindexEverything()
        }
```

- [ ] **Step 7: Build to verify**

```bash
xcodebuild build -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | grep -E '(error:|BUILD)' | tail -5
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 8: Run full suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" 2>&1 | grep -E '(Executed|failed|error:)' | tail -3
```
Expected: 0 failures.

- [ ] **Step 9: Manual smoke tests**

Launch the app on a real portfolio. Verify:

1. **Editor save** — open a project, edit the body, wait ~2s for the auto-save. The project list should reflect any title change immediately (within ~100ms after debounce).
2. **Settings popover save** — open settings popover, change title (triggers folder rename). Save. The project list updates with no flicker (in-place update via `projectFolderRenamed`).
3. **Gallery teaser** — click "Set teaser" on a gallery image. The settings popover (re-opened) should show the new teaser.
4. **Gallery file rename via cleanup** — rename a file that's the teaser. The settings popover (re-opened) shows the renamed file as teaser.
5. **Re-index portfolio command** — ⌘K, type "re-index", select. Brief activity, then file/link results from all projects appear in subsequent ⌘K queries.

- [ ] **Step 10: Commit**

```bash
git add PortyMcFolio/App/AppState.swift \
        PortyMcFolio/Services/ProjectReconciler.swift \
        PortyMcFolio/Views/ProjectDetailView.swift \
        PortyMcFolio/Views/GalleryView.swift \
        PortyMcFolio/Models/SearchResult.swift
git commit -m "feat: direct-poke from in-app writes + Re-index portfolio command"
```

---

## Self-Review

**Spec coverage** — every section/requirement of the spec maps to a task:

| Spec section | Implemented in |
|---|---|
| Project model `frontmatterMTime: Date?` field | Task 1 Step 1 |
| `project_meta` SQL schema, schema version bump to "3" | Task 1 Steps 2 + 5 |
| `ProjectMetadataCache` API + tests + corruption handling | Task 1 Steps 3-5 |
| `SearchIndex.upsertProjectWithin`, `appendFilesAndLinks`, `rebuildTags` | Task 2 Step 3 |
| `ProjectReconciler` skeleton + initial reconciliation + `syncProject` | Task 3 Step 2 |
| Atomic cache + FTS writes via shared transaction | Task 3 Step 2 (`db.write { ... cache.upsertWithin + searchIndex.upsertProjectWithin }`) |
| `projectFolderRenamed` no-flicker in-place rename | Task 3 Step 2 + Task 7 Step 2 |
| `notifyProjectFileChanged` direct-poke entry point | Task 3 Step 2 + Task 7 Step 4-5 |
| FSEvent path → uid resolution | Task 3 Step 2 (`uidFromEventPath`) |
| Cold-start flow: cache load → publish → reconciler in background | Task 4 Step 2 |
| Last portfolio root persistence + clear-on-switch | Task 4 Steps 1-2 |
| Delete dead `performScan`/`enumerateFiles`/`cachedLinks` | Task 4 Step 5 |
| FSEvent debouncing (250ms sliding, 1000ms cap) | Task 5 Step 2 |
| `reconcileTopLevel` runs once per debounced batch | Task 5 Step 2 (`runReconciliationPass(forPaths:)`) |
| Lazy `populateFiles(uid:)` | Task 6 Step 3 |
| Re-population on syncProject when files already loaded | Task 6 Step 3 (modification to syncProject) |
| `setSelectedProject` triggers populate | Task 6 Step 4 + Step 7 |
| `populateFilesForLikelyMatches` for ⌘K | Task 6 Steps 4-5 |
| Named constants `lazyPopulateFanout = 10`, `lazyPopulateMinQueryLength = 2` | Task 6 Step 3 |
| Re-index portfolio command | Task 7 Step 6 |
| `reindexEverything()` on reconciler | Task 7 Step 3 |
| 27 new tests across 3 test files | Tasks 1, 3, 5, 6 |

**Placeholder scan** — no `TBD`/`TODO`/"add appropriate error handling"/"implement later" anywhere. Every code block is concrete.

**Type / name consistency** — verified across tasks:
- `CachedProjectMeta` field list identical in cache schema (Task 1 Step 5), test fixtures (Tasks 1, 3, 6), and reconciler `Self.project(from:)` (Task 3).
- `ProjectReconciler.Mutation` enum cases (`.insert`, `.update`, `.remove`, `.batch`) used consistently in `applyMutation` (Task 4) and `publish` calls (Task 3, 6).
- `populatedFileUIDs: Set<String>` declared in Task 3, mutated in Task 6 (`populateFiles`, `repopulateFilesForUID`) and Task 7 (`reindexEverything`).
- `databaseQueueForReconciler()` declared in Task 4 Step 6, used in Task 4 Step 2 reconciler init.
- `lazyPopulateFanout` and `lazyPopulateMinQueryLength` declared in Task 6 Step 3, referenced in Task 6 Step 4.
- `notifyProjectFileChanged(uid:)` declared on reconciler (Task 3 Step 2), wrapped on AppState (Task 7 Step 1), called from editor/gallery (Task 7 Steps 4-5) and `updateProjectMetadata` (Task 7 Step 2).
- `projectFolderRenamed(uid:newFolderName:)` declared on reconciler (Task 3 Step 2), wrapped on AppState (Task 7 Step 1), called from `updateProjectMetadata` (Task 7 Step 2).
- `reindexEverything()` declared on reconciler (Task 7 Step 3), wrapped on AppState (Task 7 Step 1), invoked from SearchCommand (Task 7 Step 6).

**Scope check** — single cohesive subsystem (large-portfolio performance). The 7 tasks are sequential dependencies (each task ends with passing tests + a working app) but don't decompose into independent subsystems.

No fixes needed.







