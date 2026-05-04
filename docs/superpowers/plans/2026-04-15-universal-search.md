# Universal Cmd+K Search — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the broken Cmd+K search with a universal search palette that finds projects, files, links, and tags across the portfolio, plus "New Project" and "Settings" commands.

**Architecture:** Typed FTS5 index stores one row per searchable entity (project/file/link/tag) with a `type` discriminator. SearchPalette queries the index and groups results by type with section headers. File/link results navigate to the parent project and auto-select the item in the gallery via a `pendingFileSelection` on AppState.

**Tech Stack:** Swift, SwiftUI, GRDB (FTS5), existing DesignTokens (DT namespace)

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `PortyMcFolio/Models/SearchResult.swift` | Create | `SearchResultType` enum, `SearchResult` struct, `SearchCommand` struct |
| `PortyMcFolio/Services/SearchIndex.swift` | Rewrite | Typed FTS5 schema, versioned migration, typed indexing, typed search |
| `PortyMcFolioTests/SearchIndexTests.swift` | Rewrite | Tests for typed indexing, per-type search, tag dedup, migration |
| `PortyMcFolio/App/AppState.swift` | Modify | New `pendingFileSelection`/`pendingLinkSelection`, update `refreshProjects()` to do typed indexing, remove `searchIndexAccess` |
| `PortyMcFolio/Views/SearchPalette.swift` | Rewrite | Grouped results UI, section headers, richer rows, commands, empty-query state |
| `PortyMcFolio/Views/ProjectListView.swift` | Modify | Remove toolbar filter TextField |
| `PortyMcFolio/Views/ProjectDetailView.swift` | Modify | Observe `pendingFileSelection` → switch to gallery, pass selection down |
| `PortyMcFolio/Views/GalleryView.swift` | Modify | Accept and act on pending file/link selection from AppState |

---

### Task 1: SearchResult Model

**Files:**
- Create: `PortyMcFolio/Models/SearchResult.swift`

- [ ] **Step 1: Create the SearchResult model file**

```swift
import Foundation

enum SearchResultType: String, CaseIterable {
    case command
    case project
    case file
    case link
    case tag
}

struct SearchResult: Identifiable, Equatable {
    let id: String
    let type: SearchResultType
    let entityID: String
    let parentUID: String
    let primaryText: String
    let secondaryText: String

    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        lhs.id == rhs.id
    }
}

struct SearchCommand: Identifiable {
    let id: String
    let name: String
    let icon: String
    let shortcut: String?
    let action: (AppState) -> Void

    static let allCommands: [SearchCommand] = [
        SearchCommand(
            id: "cmd-new-project",
            name: "New Project",
            icon: "plus.rectangle",
            shortcut: "Cmd+N"
        ) { state in
            state.isShowingNewProject = true
        },
        SearchCommand(
            id: "cmd-settings",
            name: "Settings",
            icon: "gearshape",
            shortcut: nil
        ) { state in
            state.isShowingSettings = true
        }
    ]

    static func matching(_ query: String) -> [SearchCommand] {
        guard !query.isEmpty else { return allCommands }
        let q = query.lowercased()
        return allCommands.filter { $0.name.lowercased().contains(q) }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild build -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add PortyMcFolio/Models/SearchResult.swift
git commit -m "feat(search): add SearchResult and SearchCommand models"
```

---

### Task 2: Rewrite SearchIndex with Typed FTS5 Schema

**Files:**
- Modify: `PortyMcFolio/Services/SearchIndex.swift`
- Rewrite: `PortyMcFolioTests/SearchIndexTests.swift`

- [ ] **Step 1: Write the failing tests**

Replace the contents of `PortyMcFolioTests/SearchIndexTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/SearchIndexTests 2>&1 | grep -E "(Test Case|FAIL|PASS|error:)" | head -30`
Expected: Compilation errors — `indexFile`, `indexLink`, `indexTag` don't exist yet, `search()` returns old `SearchResult` type.

- [ ] **Step 3: Rewrite SearchIndex.swift**

Replace the contents of `PortyMcFolio/Services/SearchIndex.swift`:

```swift
import Foundation
import GRDB

final class SearchIndex {
    private let db: DatabaseQueue
    private static let schemaVersion = "2"

    init(inMemory: Bool = false) throws {
        if inMemory {
            db = try DatabaseQueue()
        } else {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dir = appSupport.appendingPathComponent("PortyMcFolio", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dbURL = dir.appendingPathComponent("search.sqlite")
            db = try DatabaseQueue(path: dbURL.path)
        }

        try migrate()
    }

    private func migrate() throws {
        try db.write { conn in
            // Create meta table if needed
            try conn.execute(sql: """
                CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)
                """)

            // Check schema version
            let row = try Row.fetchOne(conn, sql: "SELECT value FROM meta WHERE key = 'schema_version'")
            let currentVersion = row?["value"] as? String

            if currentVersion != Self.schemaVersion {
                try conn.execute(sql: "DROP TABLE IF EXISTS search_fts")
                try conn.execute(sql: """
                    CREATE VIRTUAL TABLE search_fts USING fts5(
                        type UNINDEXED,
                        entity_id UNINDEXED,
                        parent_uid UNINDEXED,
                        primary_text,
                        secondary_text,
                        body,
                        tokenize='unicode61 remove_diacritics 2'
                    )
                    """)
                try conn.execute(
                    sql: "INSERT OR REPLACE INTO meta (key, value) VALUES ('schema_version', ?)",
                    arguments: [Self.schemaVersion]
                )
            }
        }
    }

    // MARK: - Index

    func indexProject(
        uid: String,
        title: String,
        tags: [String],
        client: String,
        status: String,
        body: String,
        folderName: String
    ) throws {
        try db.write { conn in
            // Remove old project row
            try conn.execute(
                sql: "DELETE FROM search_fts WHERE type = 'project' AND entity_id = ?",
                arguments: [uid]
            )
            // Combine tags, status, body into the body column for broad matching
            let bodyContent = [tags.joined(separator: " "), status, body]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            try conn.execute(
                sql: """
                    INSERT INTO search_fts (type, entity_id, parent_uid, primary_text, secondary_text, body)
                    VALUES ('project', ?, '', ?, ?, ?)
                    """,
                arguments: [uid, title, client, bodyContent]
            )
        }
    }

    func indexFile(
        relativePath: String,
        fileName: String,
        fileNameNoExt: String,
        parentUID: String,
        parentTitle: String
    ) throws {
        try db.write { conn in
            try conn.execute(
                sql: """
                    INSERT INTO search_fts (type, entity_id, parent_uid, primary_text, secondary_text, body)
                    VALUES ('file', ?, ?, ?, ?, ?)
                    """,
                arguments: [relativePath, parentUID, fileName, parentTitle, fileNameNoExt]
            )
        }
    }

    func indexLink(
        uid: String,
        url: String,
        host: String,
        title: String,
        annotation: String,
        parentUID: String,
        parentTitle: String
    ) throws {
        try db.write { conn in
            let bodyContent = [url, annotation]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            // Secondary text combines host and parent project title
            let secondary = [host, parentTitle]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")

            try conn.execute(
                sql: """
                    INSERT INTO search_fts (type, entity_id, parent_uid, primary_text, secondary_text, body)
                    VALUES ('link', ?, ?, ?, ?, ?)
                    """,
                arguments: [uid, parentUID, title.isEmpty ? host : title, secondary, bodyContent]
            )
        }
    }

    func indexTag(name: String, projectCount: Int) throws {
        try db.write { conn in
            try conn.execute(
                sql: """
                    INSERT INTO search_fts (type, entity_id, parent_uid, primary_text, secondary_text, body)
                    VALUES ('tag', ?, '', ?, ?, '')
                    """,
                arguments: [name, name, "\(projectCount) project\(projectCount == 1 ? "" : "s")"]
            )
        }
    }

    // MARK: - Clear / Remove

    func clearAll() throws {
        try db.write { conn in
            try conn.execute(sql: "DELETE FROM search_fts")
        }
    }

    func removeProject(uid: String) throws {
        try db.write { conn in
            // Remove the project row
            try conn.execute(
                sql: "DELETE FROM search_fts WHERE type = 'project' AND entity_id = ?",
                arguments: [uid]
            )
            // Remove all files and links belonging to this project
            try conn.execute(
                sql: "DELETE FROM search_fts WHERE parent_uid = ?",
                arguments: [uid]
            )
        }
    }

    // MARK: - Search

    func search(query: String) throws -> [SearchResult] {
        let tokens = query.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { "\($0)*" }
        guard !tokens.isEmpty else { return [] }
        let ftsQuery = tokens.joined(separator: " ")

        return try db.read { conn in
            let rows = try Row.fetchAll(
                conn,
                sql: """
                    SELECT type, entity_id, parent_uid, primary_text, secondary_text
                    FROM search_fts
                    WHERE search_fts MATCH ?
                    ORDER BY rank
                    """,
                arguments: [ftsQuery]
            )
            return rows.compactMap { row -> SearchResult? in
                guard let typeString = row["type"] as? String,
                      let type = SearchResultType(rawValue: typeString) else { return nil }
                let entityID: String = row["entity_id"]
                let parentUID: String = row["parent_uid"]
                let primaryText: String = row["primary_text"]
                let secondaryText: String = row["secondary_text"]
                return SearchResult(
                    id: "\(typeString)-\(entityID)",
                    type: type,
                    entityID: entityID,
                    parentUID: parentUID,
                    primaryText: primaryText,
                    secondaryText: secondaryText
                )
            }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/SearchIndexTests 2>&1 | grep -E "(Test Case|FAIL|PASS)" | head -30`
Expected: All 14 tests PASS

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Services/SearchIndex.swift PortyMcFolioTests/SearchIndexTests.swift
git commit -m "feat(search): rewrite SearchIndex with typed FTS5 schema

Separate rows per entity type (project/file/link/tag), versioned
migration, unicode61 tokenizer with diacritic removal."
```

---

### Task 3: Update AppState for Typed Indexing and File Selection

**Files:**
- Modify: `PortyMcFolio/App/AppState.swift`

- [ ] **Step 1: Add pending selection properties**

At the top of `AppState`, after the existing `@Published` properties, add:

```swift
/// Set by search palette to auto-select a file in gallery after navigation
@Published var pendingFileSelection: URL?
/// Set by search palette to auto-select a link in gallery after navigation
@Published var pendingLinkID: String?
```

- [ ] **Step 2: Remove `searchIndexAccess` and simplify `filteredProjects`**

Delete this computed property from `AppState`:

```swift
/// Public access for SearchPalette
var searchIndexAccess: SearchIndex? { searchIndex }
```

`searchIndex` is already `private(set)` which allows external read access. The palette will use `appState.searchIndex` directly.

Also replace the `filteredProjects` computed property. Since `searchQuery` is now only set by tag clicks (not a freeform text field), simplify it to a tag-only filter:

```swift
var filteredProjects: [Project] {
    guard !searchQuery.isEmpty else {
        return projects
    }
    let q = searchQuery.lowercased()
    return projects.filter { project in
        project.tags.contains { $0.lowercased() == q }
    }
}
```

- [ ] **Step 3: Rewrite `refreshProjects()` to do typed indexing**

Replace the `refreshProjects()` method and `buildSearchableBody(for:)` with:

```swift
func refreshProjects() {
    guard let store = portfolioStore else { return }
    let scanned = (try? store.scanProjects()) ?? []
    projects = scanned

    guard let index = searchIndex else { return }
    try? index.clearAll()

    // Collect tag counts across all projects
    var tagCounts: [String: Int] = [:]

    for project in scanned {
        // Index the project itself
        try? index.indexProject(
            uid: project.uid,
            title: project.title,
            tags: project.tags,
            client: project.client,
            status: project.status.rawValue,
            body: project.body,
            folderName: project.folderName
        )

        // Count tags
        for tag in project.tags {
            tagCounts[tag, default: 0] += 1
        }

        // Scan files and links in the project folder
        indexProjectFiles(project: project, index: index)
    }

    // Index unique tags
    for (tag, count) in tagCounts {
        try? index.indexTag(name: tag, projectCount: count)
    }
}

private func indexProjectFiles(project: Project, index: SearchIndex) {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(
        at: project.folderURL,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    ) else { return }

    for case let url as URL in enumerator {
        let name = url.lastPathComponent
        if name == "README.md" { continue }

        let relativePath = url.path.replacingOccurrences(
            of: project.folderURL.path + "/",
            with: ""
        )

        if LinkItem.isLinkFile(name: name) {
            // Index as a link
            if let md = try? String(contentsOf: url, encoding: .utf8),
               let link = try? LinkItem.parse(markdown: md) {
                try? index.indexLink(
                    uid: link.uid,
                    url: link.url.absoluteString,
                    host: link.url.host ?? "",
                    title: link.title,
                    annotation: link.annotation,
                    parentUID: project.uid,
                    parentTitle: project.title
                )
            }
        } else {
            // Index as a file
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if !isDir {
                let nameNoExt = url.deletingPathExtension().lastPathComponent
                try? index.indexFile(
                    relativePath: relativePath,
                    fileName: name,
                    fileNameNoExt: nameNoExt,
                    parentUID: project.uid,
                    parentTitle: project.title
                )
            }
        }
    }
}
```

- [ ] **Step 4: Remove the old `buildSearchableBody` method**

Delete the entire `buildSearchableBody(for:)` method from AppState.

- [ ] **Step 5: Update `createProject` to use new indexing**

The existing `createProject` method indexes a new project inline. It calls `index.indexProject(...)` which still works with the same signature. No change needed.

- [ ] **Step 6: Verify it compiles**

Run: `xcodebuild build -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED (SearchPalette will have a compile error referencing `searchIndexAccess` — that's expected, we fix it in Task 5)

If there are compilation errors in SearchPalette referencing `searchIndexAccess`, that's fine — we rewrite it in Task 5. Verify no other errors.

- [ ] **Step 7: Run existing tests**

Run: `xcodebuild test -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | grep -E "(Test Suite|Tests|FAIL)" | tail -10`
Expected: All tests pass (SearchIndexTests already updated in Task 2)

- [ ] **Step 8: Commit**

```bash
git add PortyMcFolio/App/AppState.swift
git commit -m "feat(search): typed indexing in AppState with pending file selection

Index files, links, and tags as separate rows. Add pendingFileSelection
and pendingLinkID for search-to-gallery navigation."
```

---

### Task 4: Remove Toolbar Filter from ProjectListView

**Files:**
- Modify: `PortyMcFolio/Views/ProjectListView.swift`

- [ ] **Step 1: Remove the toolbar filter TextField**

In `ProjectListView.swift`, delete the entire `ToolbarItem(placement: .principal)` block (lines 54-71):

```swift
// Center: search
ToolbarItem(placement: .principal) {
    HStack(spacing: DT.Spacing.xs) {
        Image(systemName: "line.3.horizontal.decrease")
            .font(.system(size: 11))
            .foregroundStyle(DT.Colors.textTertiary)
        TextField("Filter…", text: $appState.searchQuery)
            .textFieldStyle(.plain)
            .font(DT.Typography.body)
            .frame(width: 200)
    }
    .padding(.horizontal, DT.Spacing.sm)
    .padding(.vertical, DT.Spacing.xs)
    .background(DT.Colors.surfaceHover, in: RoundedRectangle(cornerRadius: DT.Radius.small))
    .overlay(
        RoundedRectangle(cornerRadius: DT.Radius.small)
            .stroke(DT.Colors.border, lineWidth: 0.5)
    )
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild build -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED (or only SearchPalette errors from `searchIndexAccess`)

- [ ] **Step 3: Commit**

```bash
git add PortyMcFolio/Views/ProjectListView.swift
git commit -m "refactor(search): remove toolbar filter TextField

Cmd+K search palette is now the single search entry point.
Tag-click filtering still works via AppState.searchQuery."
```

---

### Task 5: Rewrite SearchPalette with Grouped Results

**Files:**
- Rewrite: `PortyMcFolio/Views/SearchPalette.swift`

- [ ] **Step 1: Rewrite SearchPalette.swift**

Replace the entire contents of `PortyMcFolio/Views/SearchPalette.swift`:

```swift
import SwiftUI

struct SearchPalette: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var selectedIndex = 0

    // MARK: - Grouped results

    private struct GroupedResults {
        var commands: [SearchCommand] = []
        var projects: [SearchResult] = []
        var files: [SearchResult] = []
        var links: [SearchResult] = []
        var tags: [SearchResult] = []

        /// All items in display order, flattened for keyboard navigation
        var flatItems: [FlatItem] {
            var items: [FlatItem] = []
            for cmd in commands {
                items.append(.command(cmd))
            }
            for r in projects { items.append(.result(r)) }
            for r in files { items.append(.result(r)) }
            for r in links { items.append(.result(r)) }
            for r in tags { items.append(.result(r)) }
            return items
        }

        var isEmpty: Bool {
            commands.isEmpty && projects.isEmpty && files.isEmpty && links.isEmpty && tags.isEmpty
        }
    }

    private enum FlatItem: Identifiable {
        case command(SearchCommand)
        case result(SearchResult)

        var id: String {
            switch self {
            case .command(let cmd): return cmd.id
            case .result(let r): return r.id
            }
        }
    }

    private var grouped: GroupedResults {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        // Commands — always filtered client-side
        let commands = SearchCommand.matching(trimmed)

        if trimmed.isEmpty {
            // Empty query: show commands + recent projects (top 5 by year)
            let recentProjects = Array(appState.projects.prefix(5)).map { project in
                SearchResult(
                    id: "project-\(project.uid)",
                    type: .project,
                    entityID: project.uid,
                    parentUID: "",
                    primaryText: project.title.isEmpty ? "Untitled" : project.title,
                    secondaryText: [String(project.year), project.client]
                        .filter { !$0.isEmpty }
                        .joined(separator: " · ")
                )
            }
            return GroupedResults(commands: commands, projects: recentProjects)
        }

        // Query the FTS index
        guard let index = appState.searchIndex,
              let searchResults = try? index.search(query: trimmed) else {
            // FTS failed — fall back to simple project filter
            let filtered = simpleFilter(trimmed)
            return GroupedResults(commands: commands, projects: filtered)
        }

        // Group by type with caps
        let projects = Array(searchResults.filter { $0.type == .project }.prefix(5))
        let files = Array(searchResults.filter { $0.type == .file }.prefix(5))
        let links = Array(searchResults.filter { $0.type == .link }.prefix(3))
        let tags = Array(searchResults.filter { $0.type == .tag }.prefix(3))

        // If FTS returned nothing for projects, fall back to simple filter
        let finalProjects = projects.isEmpty ? simpleFilter(trimmed) : projects

        return GroupedResults(
            commands: commands,
            projects: finalProjects,
            files: files,
            links: links,
            tags: tags
        )
    }

    private func simpleFilter(_ query: String) -> [SearchResult] {
        let q = query.lowercased()
        return appState.projects
            .filter { project in
                project.title.lowercased().contains(q) ||
                project.client.lowercased().contains(q) ||
                project.tags.contains { $0.lowercased().contains(q) } ||
                project.folderName.lowercased().contains(q)
            }
            .prefix(5)
            .map { project in
                SearchResult(
                    id: "project-\(project.uid)",
                    type: .project,
                    entityID: project.uid,
                    parentUID: "",
                    primaryText: project.title.isEmpty ? "Untitled" : project.title,
                    secondaryText: [String(project.year), project.client]
                        .filter { !$0.isEmpty }
                        .joined(separator: " · ")
                )
            }
    }

    // MARK: - Body

    var body: some View {
        let currentGrouped = grouped
        let flat = currentGrouped.flatItems

        VStack(spacing: 0) {
            // Search input
            SearchPaletteTextField(
                text: $query,
                selectedIndex: $selectedIndex,
                resultCount: flat.count,
                onSubmit: { selectItem(at: selectedIndex, from: flat) },
                onEscape: { isPresented = false }
            )
            .padding(.horizontal, DT.Spacing.lg)
            .padding(.vertical, DT.Spacing.md)

            Divider()

            // Results
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        var runningIndex = 0

                        // Commands
                        if !currentGrouped.commands.isEmpty {
                            sectionHeader("COMMANDS")
                            ForEach(currentGrouped.commands) { cmd in
                                let idx = runningIndex
                                CommandRow(command: cmd, isSelected: idx == selectedIndex)
                                    .id(idx)
                                    .onTapGesture { executeCommand(cmd) }
                                let _ = (runningIndex += 1)
                            }
                        }

                        // Projects
                        if !currentGrouped.projects.isEmpty {
                            sectionHeader("PROJECTS")
                            ForEach(currentGrouped.projects) { result in
                                let idx = runningIndex
                                ResultRow(result: result, isSelected: idx == selectedIndex)
                                    .id(idx)
                                    .onTapGesture { executeResult(result) }
                                let _ = (runningIndex += 1)
                            }
                        }

                        // Files
                        if !currentGrouped.files.isEmpty {
                            sectionHeader("FILES")
                            ForEach(currentGrouped.files) { result in
                                let idx = runningIndex
                                ResultRow(result: result, isSelected: idx == selectedIndex)
                                    .id(idx)
                                    .onTapGesture { executeResult(result) }
                                let _ = (runningIndex += 1)
                            }
                        }

                        // Links
                        if !currentGrouped.links.isEmpty {
                            sectionHeader("LINKS")
                            ForEach(currentGrouped.links) { result in
                                let idx = runningIndex
                                ResultRow(result: result, isSelected: idx == selectedIndex)
                                    .id(idx)
                                    .onTapGesture { executeResult(result) }
                                let _ = (runningIndex += 1)
                            }
                        }

                        // Tags
                        if !currentGrouped.tags.isEmpty {
                            sectionHeader("TAGS")
                            ForEach(currentGrouped.tags) { result in
                                let idx = runningIndex
                                ResultRow(result: result, isSelected: idx == selectedIndex)
                                    .id(idx)
                                    .onTapGesture { executeResult(result) }
                                let _ = (runningIndex += 1)
                            }
                        }

                        // No results
                        if currentGrouped.isEmpty && !query.isEmpty {
                            HStack {
                                Spacer()
                                Text("No results for \"\(query)\"")
                                    .font(DT.Typography.caption)
                                    .foregroundStyle(DT.Colors.textTertiary)
                                    .padding(.vertical, 20)
                                Spacer()
                            }
                        }
                    }
                }
                .frame(maxHeight: 400)
                .onChange(of: selectedIndex) { _, newValue in
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }

            // Hints
            HStack(spacing: DT.Spacing.lg) {
                shortcutHint("↑↓", label: "navigate")
                shortcutHint("↵", label: "open")
                shortcutHint("esc", label: "close")
            }
            .padding(.horizontal, DT.Spacing.lg)
            .padding(.vertical, DT.Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        }
        .frame(width: 560)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.large))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 10)
        .onChange(of: query) { _, _ in
            selectedIndex = 0
        }
    }

    // MARK: - Actions

    private func selectItem(at index: Int, from flat: [FlatItem]) {
        guard index < flat.count else { return }
        switch flat[index] {
        case .command(let cmd):
            executeCommand(cmd)
        case .result(let result):
            executeResult(result)
        }
    }

    private func executeCommand(_ command: SearchCommand) {
        command.action(appState)
        isPresented = false
    }

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

    // MARK: - Subviews

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(DT.Typography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(DT.Colors.textTertiary)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, DT.Spacing.lg)
        .padding(.top, DT.Spacing.sm)
        .padding(.bottom, DT.Spacing.xs)
    }

    private func shortcutHint(_ key: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, design: .rounded))
                .fontWeight(.medium)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color(nsColor: .quaternaryLabelColor), in: RoundedRectangle(cornerRadius: 3))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Command Row

private struct CommandRow: View {
    let command: SearchCommand
    let isSelected: Bool

    var body: some View {
        HStack(spacing: DT.Spacing.sm) {
            Image(systemName: command.icon)
                .font(.system(size: 14))
                .foregroundStyle(DT.Colors.textSecondary)
                .frame(width: 24, height: 24)

            Text(command.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DT.Colors.textPrimary)

            Spacer()

            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(DT.Colors.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(nsColor: .quaternaryLabelColor))
                    )
            }
        }
        .padding(.horizontal, DT.Spacing.lg)
        .padding(.vertical, DT.Spacing.sm)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Result Row

private struct ResultRow: View {
    let result: SearchResult
    let isSelected: Bool

    private var icon: String {
        switch result.type {
        case .project: "folder.fill"
        case .file: fileIcon(for: result.primaryText)
        case .link: "link"
        case .tag: "tag"
        case .command: "command"
        }
    }

    var body: some View {
        HStack(spacing: DT.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(DT.Colors.textSecondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(result.primaryText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DT.Colors.textPrimary)
                    .lineLimit(1)

                if !result.secondaryText.isEmpty {
                    Text(result.secondaryText)
                        .font(.system(size: 11))
                        .foregroundStyle(DT.Colors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, DT.Spacing.lg)
        .padding(.vertical, DT.Spacing.sm)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
    }

    private func fileIcon(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext"
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "tiff", "svg":
            return "photo"
        case "mp4", "mov", "avi", "mkv":
            return "film"
        case "mp3", "wav", "aac", "m4a":
            return "music.note"
        case "sketch", "fig":
            return "paintbrush"
        case "psd", "ai":
            return "paintpalette"
        case "zip", "tar", "gz":
            return "doc.zipper"
        default:
            return "doc"
        }
    }
}

// MARK: - Custom NSTextField wrapper for reliable focus + arrow key handling

struct SearchPaletteTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var selectedIndex: Int
    let resultCount: Int
    let onSubmit: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "Search projects, files, links, tags…"
        field.font = .systemFont(ofSize: 16)
        field.isBezeled = false
        field.focusRingType = .none
        field.backgroundColor = .clear
        field.delegate = context.coordinator
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        context.coordinator.resultCount = resultCount
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: SearchPaletteTextField
        var resultCount: Int = 0

        init(_ parent: SearchPaletteTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                if parent.selectedIndex > 0 {
                    parent.selectedIndex -= 1
                }
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                if parent.selectedIndex < resultCount - 1 {
                    parent.selectedIndex += 1
                }
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                return true
            }
            return false
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild build -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add PortyMcFolio/Views/SearchPalette.swift
git commit -m "feat(search): rewrite SearchPalette with grouped results

Grouped sections (commands/projects/files/links/tags), type-specific
icons, richer result rows, empty-query shows commands + recent projects."
```

---

### Task 6: Wire Up Pending File/Link Selection in ProjectDetailView and GalleryView

**Files:**
- Modify: `PortyMcFolio/Views/ProjectDetailView.swift`
- Modify: `PortyMcFolio/Views/GalleryView.swift`

- [ ] **Step 1: Update ProjectDetailView to handle pending selections**

In `ProjectDetailView.swift`, add an `.onAppear` / `.onChange` handler to switch to gallery mode and forward the pending selection. Add this modifier after the existing `.sheet(isPresented: $isShowingSettings)` block (before the closing `}` of the body):

```swift
.onAppear {
    handlePendingSelection()
}
.onChange(of: appState.pendingFileSelection) { _, newValue in
    if newValue != nil { handlePendingSelection() }
}
.onChange(of: appState.pendingLinkID) { _, newValue in
    if newValue != nil { handlePendingSelection() }
}
```

And add this method to `ProjectDetailView`:

```swift
private func handlePendingSelection() {
    if appState.pendingFileSelection != nil || appState.pendingLinkID != nil {
        // Switch to gallery-visible mode
        if appState.viewMode == .editor {
            appState.viewMode = .split
        }
    }
}
```

- [ ] **Step 2: Update GalleryView to consume pending selections**

In `GalleryView.swift`, in the `.onAppear` block (around line 165), add after `scanProjectFolder()`:

```swift
consumePendingSelection()
```

And add a new method to `GalleryView`:

```swift
private func consumePendingSelection() {
    if let fileURL = appState.pendingFileSelection {
        // Check if this file is in the current project
        let relativePath = fileURL.path.replacingOccurrences(
            of: project.folderURL.path + "/",
            with: ""
        )
        let components = relativePath.components(separatedBy: "/")

        if components.count > 1 {
            // File is in a subfolder — navigate there
            currentSubpath = Array(components.dropLast())
            scanProjectFolder()
        }

        selectedFileURL = fileURL
        selectedLinkID = nil
        appState.pendingFileSelection = nil
    }

    if let linkID = appState.pendingLinkID {
        viewMode = .links
        selectedLinkID = linkID
        selectedFileURL = nil
        appState.pendingLinkID = nil
    }
}
```

Also add an `@EnvironmentObject` to `GalleryView` if it doesn't already have one. Currently `GalleryView` takes `project` as a parameter but doesn't have `@EnvironmentObject var appState: AppState`. Add it at the top of the struct:

```swift
@EnvironmentObject var appState: AppState
```

- [ ] **Step 3: Verify it compiles**

Run: `xcodebuild build -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Run all tests**

Run: `xcodebuild test -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | grep -E "(Test Suite|Tests|FAIL)" | tail -10`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Views/ProjectDetailView.swift PortyMcFolio/Views/GalleryView.swift
git commit -m "feat(search): wire pending file/link selection into gallery

Search results navigate to the parent project and auto-select
the file or link in the gallery view."
```

---

### Task 7: Final Integration Verification

**Files:** None (verification only)

- [ ] **Step 1: Build the full project**

Run: `xcodebuild build -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Run all tests**

Run: `xcodebuild test -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | grep -E "(Test Suite|Tests|FAIL)" | tail -10`
Expected: All tests pass, 0 failures

- [ ] **Step 3: Verify no references to old search API remain**

Search for `searchIndexAccess`:

```bash
grep -r "searchIndexAccess" PortyMcFolio/ --include="*.swift"
```

Expected: No results

Search for `projects_fts` (old table name):

```bash
grep -r "projects_fts" PortyMcFolio/ --include="*.swift"
```

Expected: No results

Search for `buildSearchableBody` (old method):

```bash
grep -r "buildSearchableBody" PortyMcFolio/ --include="*.swift"
```

Expected: No results

- [ ] **Step 4: Commit any final fixes if needed, then tag completion**

```bash
git log --oneline -7
```

Verify you see commits for: SearchResult model, SearchIndex rewrite, AppState typed indexing, toolbar filter removal, SearchPalette rewrite, gallery wiring.
