# Data integrity batch A — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix four data-integrity bugs from the 2026-04-17 code review: reconciler double-publish wiping `filePaths`, leaking lifetime on portfolio switch (likely root of `database is locked` error flood), non-atomic portfolio wipe leaving stale metadata rows, and `UID.generate()` silently returning `"00000000"` when `SecRandomCopyBytes` fails.

**Architecture:** All four live in the data/concurrency core: `ProjectReconciler.swift`, `AppState.swift` (setRoot lifecycle), `SearchIndex.swift`, and `UID.swift`. Each fix is small and isolated. Order matters: Task 1 unblocks the publish-ordering bug and can ship alone; Task 2 and 3 combine to make portfolio switch safe; Task 4 stands alone.

**Tech Stack:** Swift 5.9, SwiftUI (macOS 14+), GRDB (DatabaseQueue), XCTest.

**Related findings** from code review `audit-data-core`:
- Critical #1 — double-publish (`ProjectReconciler.swift:390-395`)
- Critical #2 — `database is locked` (caused by un-shutdown old SearchIndex on portfolio switch, per this plan's re-analysis — reviewer's diagnosis of nested-write on same queue does not hold since the queue serializes)
- Critical #3 — portfolio-switch non-atomic wipe (`AppState.swift:233-239`)
- Critical — `UID.generate` silent failure (`UID.swift:8`)

---

## Task 1: Reconciler — single publish per syncProject, preserve `filePaths`

**Files:**
- Modify: `PortyMcFolio/Services/ProjectReconciler.swift`
- Modify: `PortyMcFolioTests/ProjectReconcilerTests.swift` (add one test)

### Design

`repopulateFilesForUID` currently does two things: (1) re-indexes FTS file/link rows; (2) publishes `.update(project)`. After it returns, `syncProject` *also* publishes — with `filePaths: []`, overwriting (1).

Fix: make `repopulateFilesForUID` return the file relative paths without publishing. Callers (`syncProject`, `populateFiles`, `reindexEverything`) build the `Project` value with correct `filePaths` and publish exactly once.

- [ ] **Step 1: Write the failing test**

Open `PortyMcFolioTests/ProjectReconcilerTests.swift`. Follow the existing test harness (it already builds on-disk projects and records publishes — reuse those helpers). Add:

```swift
func testSyncProjectPublishesOnceWithFilePathsForPopulatedProject() throws {
    // Setup: one project on disk with two files + one link.
    let (recon, publishes, portfolioRoot) = try makeReconcilerWithPublishRecorder()
    let uid = "aaaaaaaa"
    let folderName = "2025_test_\(uid)"
    try createDiskProject(in: portfolioRoot, folderName: folderName, title: "Test", client: "C")
    let folderURL = portfolioRoot.appendingPathComponent(folderName)
    try "image bytes".write(
        to: folderURL.appendingPathComponent("hero.jpg"),
        atomically: true,
        encoding: .utf8
    )
    try "notes".write(
        to: folderURL.appendingPathComponent("notes.md"),
        atomically: true,
        encoding: .utf8
    )

    // Initial reconciliation lands a .insert.
    let initial = expectation(description: "initial")
    recon.startInitialReconciliation { initial.fulfill() }
    wait(for: [initial], timeout: 5)

    // Trigger lazy file population.
    let populated = expectation(description: "populated")
    recon.populateFiles(uid: uid) { populated.fulfill() }
    wait(for: [populated], timeout: 5)

    // Reset publish recorder — we care about what a subsequent syncProject does.
    publishes.reset()

    // Act: trigger a direct-poke sync (simulates editor save on the project).
    // Touch the project's frontmatter file so mtime advances and syncProject
    // actually runs the upsert branch.
    let readmeURL = folderURL.appendingPathComponent("\(folderName).md")
    try FileManager.default.setAttributes(
        [.modificationDate: Date()],
        ofItemAtPath: readmeURL.path
    )
    let synced = expectation(description: "synced")
    recon.notifyProjectFileChanged(uid: uid) { synced.fulfill() }
    wait(for: [synced], timeout: 5)

    // Assert: exactly one publish, and it carries the populated filePaths.
    let mutations = publishes.snapshot()
    XCTAssertEqual(mutations.count, 1, "expected exactly one publish; got \(mutations)")
    guard case .update(let project) = mutations.first else {
        XCTFail("expected .update; got \(String(describing: mutations.first))")
        return
    }
    XCTAssertFalse(project.filePaths.isEmpty, "filePaths should be preserved through the sync cycle")
    XCTAssertTrue(project.filePaths.contains("hero.jpg"))
    XCTAssertTrue(project.filePaths.contains("notes.md"))
}
```

If the test helpers `makeReconcilerWithPublishRecorder` / `createDiskProject` don't exist under those exact names, reuse whatever equivalents the file already has — just match the pattern of the neighboring tests.

- [ ] **Step 2: Run test — expect it to FAIL**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/ProjectReconcilerTests/testSyncProjectPublishesOnceWithFilePathsForPopulatedProject 2>&1 | tail -30
```
Expected: FAIL with either `mutations.count == 2` or `project.filePaths.isEmpty`.

- [ ] **Step 3: Refactor `repopulateFilesForUID` to return `[String]?`**

In `PortyMcFolio/Services/ProjectReconciler.swift`, replace `repopulateFilesForUID` (around lines 133-152):

```swift
/// Re-index file/link FTS rows for a project and return the file relative paths.
/// Does NOT publish — callers are responsible for publishing a `Project` that
/// carries the returned paths. Returns `nil` on missing folder or indexing error.
@discardableResult
private func repopulateFilesForUID(_ uid: String) -> [String]? {
    guard let folder = scanRootForProjectFolders().first(where: { $0.uid == uid }) else {
        return nil
    }
    let entries = enumerateFilesAndLinks(folderURL: folder.folderURL, folderName: folder.folderName)
    do {
        try searchIndex.appendFilesAndLinks(
            forProjectUID: uid,
            fileEntries: entries.files,
            linkEntries: entries.links
        )
    } catch {
        print("[Reconciler] appendFilesAndLinks failed for uid=\(uid): \(error)")
        return nil
    }
    return entries.files.map { $0.relativePath }
}
```

- [ ] **Step 4: Update `syncProject` to publish once with merged `filePaths`**

In the same file, `syncProject` (around lines 388-396). Replace the tail:

```swift
        // If files for this project were already populated in memory, refresh them too.
        if populatedFileUIDs.contains(uid) {
            repopulateFilesForUID(uid)
        }

        let project = Self.project(from: meta, root: portfolioRoot)
        publish(isInsert ? .insert(project) : .update(project))
```

with:

```swift
        // If files were lazily populated, re-index and carry the fresh paths into
        // the single publish below. (Previously this path published twice and the
        // second publish silently wiped filePaths.)
        let filePaths: [String]
        if populatedFileUIDs.contains(uid) {
            filePaths = repopulateFilesForUID(uid) ?? []
        } else {
            filePaths = []
        }

        var project = Self.project(from: meta, root: portfolioRoot)
        project.filePaths = filePaths
        publish(isInsert ? .insert(project) : .update(project))
```

- [ ] **Step 5: Update `populateFiles` to publish using the returned paths**

Replace `populateFiles` (lines 101-111) body with:

```swift
func populateFiles(uid: String, completion: (() -> Void)? = nil) {
    queue.async { [weak self] in
        guard let self else { return }
        let alreadyPopulated = self.populatedFileUIDs.contains(uid)
        self.populatedFileUIDs.insert(uid)
        if !alreadyPopulated,
           let filePaths = self.repopulateFilesForUID(uid),
           let cached = self.cache.load(uid: uid) {
            var project = Self.project(from: cached, root: self.portfolioRoot)
            project.filePaths = filePaths
            self.publish(.update(project))
        }
        completion?()
    }
}
```

- [ ] **Step 6: Update `reindexEverything` to publish with returned paths**

Replace `reindexEverything` (lines 116-131) body with:

```swift
func reindexEverything(completion: (() -> Void)? = nil) {
    queue.async { [weak self] in
        guard let self else { return }
        let folders = self.scanRootForProjectFolders()
        for folder in folders {
            self.populatedFileUIDs.insert(folder.uid)
            if let filePaths = self.repopulateFilesForUID(folder.uid),
               let cached = self.cache.load(uid: folder.uid) {
                var project = Self.project(from: cached, root: self.portfolioRoot)
                project.filePaths = filePaths
                self.publish(.update(project))
            }
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

- [ ] **Step 7: Run the failing test — expect PASS**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/ProjectReconcilerTests/testSyncProjectPublishesOnceWithFilePathsForPopulatedProject 2>&1 | tail -30
```
Expected: PASS.

- [ ] **Step 8: Full test suite — expect no regressions**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: all tests pass.

- [ ] **Step 9: Commit**

```bash
git add PortyMcFolio/Services/ProjectReconciler.swift PortyMcFolioTests/ProjectReconcilerTests.swift
git commit -m "fix: reconciler publishes filePaths exactly once per syncProject"
```

---

## Task 2: AppState.setRoot — shut down old reconciler, file watcher, and search index before constructing new ones

**Files:**
- Modify: `PortyMcFolio/App/AppState.swift` (inside `setRoot`)

### Design

On portfolio switch, the old `ProjectReconciler`, `FileWatcher`, and `SearchIndex` are silently replaced by new instances without tearing down. The old reconciler's dispatch queue may still have pending writes; the old `SearchIndex`'s `DatabaseQueue` remains alive until Swift deallocates it, which may overlap with the new one writing. Two `DatabaseQueue` instances on the same file coordinate via file locks and can produce `SQLITE_BUSY` (`error 5 — database is locked`) during overlap.

Fix: explicitly stop the old `FileWatcher`, `shutdown()` the old reconciler, and null out `searchIndex`/`cache`/`reconciler`/`fileWatcher` before constructing new ones. Swift's ARC will deinit them deterministically.

No unit test — this is lifecycle cleanup observable only in integration. We verify by (1) audit of the final code and (2) absence of `database is locked` errors in runtime logs after the fix.

- [ ] **Step 1: Locate `setRoot` in `AppState.swift`**

Around line 215 (start of function). Find the block that currently looks like:

```swift
selectedProject = nil
projects = []
searchQuery = ""

portfolioRootURL = url
portfolioStore = PortfolioStore(rootURL: url)

// Construct (or reuse) the SQLite-backed search index + cache.
do {
    let newIndex = try SearchIndex()
    …
```

- [ ] **Step 2: Insert the teardown block before the `portfolioRootURL = url` line**

Insert between the existing `searchQuery = ""` line and the `portfolioRootURL = url` line:

```swift
// Tear down services from any previous portfolio so their DatabaseQueue
// (and file watcher / reconciler queue) deallocate before we build new ones.
// Without this teardown, two DatabaseQueue instances coexist on the same
// search.sqlite file during portfolio switch and produce SQLITE_BUSY errors
// (observed as "database is locked" floods in the reconciler log).
fileWatcher?.stop()
fileWatcher = nil
reconciler?.shutdown()
reconciler = nil
searchIndex = nil
cache = nil
```

- [ ] **Step 3: Adjust the re-use branch downstream**

The existing code around line 237-239 has:
```swift
} else if self.cache == nil {
    self.cache = try ProjectMetadataCache(db: newIndex.databaseQueueForReconciler())
}
```

After Task 2 Step 2, `self.cache` is always `nil` on entry, so the `else if` condition is always true. Simplify by removing the `else if` guard — always construct the cache:

```swift
// If the user switched portfolios, wipe the cache + FTS to avoid mixing.
if let prevPath = newIndex.lastPortfolioRoot(), prevPath != url.path {
    try? newIndex.clearAll()
    self.cache = try ProjectMetadataCache(db: newIndex.databaseQueueForReconciler())
    try? self.cache?.clear()
} else {
    self.cache = try ProjectMetadataCache(db: newIndex.databaseQueueForReconciler())
}
try? newIndex.setLastPortfolioRoot(url.path)
```

(Task 3 will replace the wipe-then-clear pair with a single atomic call.)

- [ ] **Step 4: Build**

```bash
xcodebuild build -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Full test suite — confirm no regression**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add PortyMcFolio/App/AppState.swift
git commit -m "fix: shut down old reconciler/index/watcher before portfolio switch"
```

---

## Task 3: `SearchIndex.wipeAllForPortfolioSwitch()` — single atomic wipe of FTS + cache

**Files:**
- Modify: `PortyMcFolio/Services/SearchIndex.swift` (add method)
- Modify: `PortyMcFolio/App/AppState.swift` (use new method)
- Modify: `PortyMcFolioTests/SearchIndexTests.swift` (add test)

### Design

The current wipe sequence in `setRoot` runs `newIndex.clearAll()` (deletes FTS rows) and then `self.cache?.clear()` (deletes project_meta rows) as two separate `db.write` blocks. If one fails, the other may still commit, leaving the database in a half-wiped state. Both errors are suppressed via `try?`.

Add `SearchIndex.wipeAllForPortfolioSwitch()` that deletes from both tables in a single transaction. Remove the swallowed errors.

- [ ] **Step 1: Write the failing test**

Add to `PortyMcFolioTests/SearchIndexTests.swift` (follow existing patterns for setup):

```swift
func testWipeAllForPortfolioSwitchClearsBothFTSAndCache() throws {
    // Setup: seed FTS with a project row and cache with the same project.
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
        body: "body",
        hidden: false,
        date: Date(),
        frontmatterMTime: Date()
    )
    try db.write { conn in
        try cache.upsertWithin(conn, meta)
        try index.upsertProjectWithin(conn, meta: meta, fileEntries: [], linkEntries: [])
    }

    // Act.
    try index.wipeAllForPortfolioSwitch()

    // Assert: both tables empty.
    try db.read { conn in
        let ftsCount = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM search_fts") ?? -1
        let metaCount = try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM project_meta") ?? -1
        XCTAssertEqual(ftsCount, 0)
        XCTAssertEqual(metaCount, 0)
    }
}
```

- [ ] **Step 2: Run test — expect it to FAIL**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/SearchIndexTests/testWipeAllForPortfolioSwitchClearsBothFTSAndCache 2>&1 | tail -30
```
Expected: FAIL (compile error: `wipeAllForPortfolioSwitch` not found).

- [ ] **Step 3: Add the method on `SearchIndex`**

In `PortyMcFolio/Services/SearchIndex.swift`, near the existing `clearAll()` method (around line 195-198), add:

```swift
/// Atomically wipe both `search_fts` and `project_meta` in a single transaction.
/// Used by `AppState.setRoot` when the user switches portfolios.
func wipeAllForPortfolioSwitch() throws {
    try db.write { conn in
        try conn.execute(sql: "DELETE FROM search_fts")
        try conn.execute(sql: "DELETE FROM project_meta")
    }
}
```

Note: this SQL assumes `project_meta` exists. It will when `ProjectMetadataCache.init` has run, which it will have by the time `setRoot` calls this. The wipe method is safe to call before any cache instance exists because `project_meta`'s `CREATE TABLE IF NOT EXISTS` is idempotent and is guaranteed to have run at least once per `search.sqlite` after the cache is ever opened.

- [ ] **Step 4: Use the new method in `AppState.setRoot`**

Replace the portfolio-switch branch in `setRoot` (the `if let prevPath = newIndex.lastPortfolioRoot(), prevPath != url.path { … } else { … }` block from Task 2) with:

```swift
// Build cache first so project_meta exists before wiping it.
let cache = try ProjectMetadataCache(db: newIndex.databaseQueueForReconciler())
// If the user switched portfolios, wipe FTS + project_meta atomically.
if let prevPath = newIndex.lastPortfolioRoot(), prevPath != url.path {
    try newIndex.wipeAllForPortfolioSwitch()
}
self.cache = cache
try? newIndex.setLastPortfolioRoot(url.path)
```

Remove the `try?` around `wipeAllForPortfolioSwitch` — an unsuccessful wipe is a real problem. If the outer `do { … } catch` already surrounds this block (it does — see line 228-245 in the current file), the error will be caught there and logged. Leave the existing `catch` block alone.

- [ ] **Step 5: Run the failing test — expect PASS**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/SearchIndexTests/testWipeAllForPortfolioSwitchClearsBothFTSAndCache 2>&1 | tail -30
```
Expected: PASS.

- [ ] **Step 6: Full test suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add PortyMcFolio/Services/SearchIndex.swift PortyMcFolio/App/AppState.swift PortyMcFolioTests/SearchIndexTests.swift
git commit -m "fix: atomic FTS+cache wipe on portfolio switch"
```

---

## Task 4: `UID.generate()` — crash loudly on RNG failure, add test

**Files:**
- Modify: `PortyMcFolio/Services/UID.swift`
- Create: `PortyMcFolioTests/UIDTests.swift`

### Design

`SecRandomCopyBytes` returns `OSStatus`. The current call discards it (`_ = SecRandomCopyBytes(...)`). On failure, `bytes` stays zeroed and the UID becomes `"00000000"`. A silent failure here corrupts the folder namespace.

Fix: check the status; `preconditionFailure` on failure. RNG failure on macOS is so rare that hitting it indicates a deeper problem — crashing is correct behavior. Also add a minimal test suite.

- [ ] **Step 1: Write the failing test**

Create `PortyMcFolioTests/UIDTests.swift`:

```swift
import XCTest
@testable import PortyMcFolio

final class UIDTests: XCTestCase {
    func testGenerateReturnsEightHexCharacters() {
        for _ in 0..<100 {
            let uid = UID.generate()
            XCTAssertEqual(uid.count, 8, "uid should be 8 chars, got '\(uid)'")
            XCTAssertTrue(
                uid.allSatisfy { $0.isHexDigit },
                "uid should be hex, got '\(uid)'"
            )
        }
    }

    func testGenerateIsReasonablyUnique() {
        // 100 calls should not all be the same string. This catches the
        // degenerate-zeroed case: if SecRandomCopyBytes ever fails silently,
        // the old code returned "00000000" for every call.
        var seen = Set<String>()
        for _ in 0..<100 { seen.insert(UID.generate()) }
        XCTAssertGreaterThan(seen.count, 90, "should be very high entropy; got \(seen.count) unique out of 100")
    }
}
```

(The test does NOT exercise the failure path — that's environment-dependent. It does guard against the observable symptom of the bug: all-zeros output.)

- [ ] **Step 2: Regenerate the Xcode project (new test file)**

```bash
xcodegen
```

- [ ] **Step 3: Run test — expect PASS (the current code happens to work)**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/UIDTests 2>&1 | tail -20
```
Expected: PASS. (This test is a regression guard, not a failing-first-then-passing TDD test. Document that in the commit message.)

- [ ] **Step 4: Apply the fix**

In `PortyMcFolio/Services/UID.swift`, replace the `_ = SecRandomCopyBytes(...)` line with:

```swift
let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
precondition(status == errSecSuccess, "SecRandomCopyBytes failed with status \(status); aborting rather than generate a degenerate uid")
```

(The exact surrounding lines depend on the current shape of the file; preserve the existing signature and byte-length. The precondition goes immediately after the RNG call and before the bytes are consumed.)

- [ ] **Step 5: Run test again — still expect PASS**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/UIDTests 2>&1 | tail -20
```
Expected: PASS.

- [ ] **Step 6: Full test suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add PortyMcFolio/Services/UID.swift PortyMcFolioTests/UIDTests.swift PortyMcFolio.xcodeproj
git commit -m "fix: crash on SecRandomCopyBytes failure instead of yielding 00000000 uid"
```

---

## Spec coverage check

| Requirement | Task |
|---|---|
| Reconciler publishes `filePaths` exactly once per sync | Task 1 |
| Old reconciler/index/watcher are torn down on portfolio switch | Task 2 |
| FTS + cache wipe is atomic | Task 3 |
| `UID.generate()` never silently returns "00000000" | Task 4 |
| No regressions in existing 102 tests | Tasks 1-4 Step 5/6 |
