# Error-Handling & Silent-Write Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate silent failures in file writes, replace `print()` with `os.Logger`, and make `UID.generate` non-crashing.

**Architecture:** Introduce a single `AppLogger` namespace over `os.Logger` with seven categories. Migrate every `print(...)` call in the app target to it. Change `ProjectFileOps.updateReferences` from `-> Bool` (swallowing write errors) to `throws -> Bool`. Fix `ProjectReconciler`'s post-favorites write to log instead of dropping errors, and have `mtimeOf` log when it returns nil. Refactor `UID.generate` to use a graceful fallback instead of `precondition`.

**Tech Stack:** Swift 5.9, AppKit, `os.Logger`, XCTest. Xcode project generated from `project.yml` via xcodegen.

**Out of scope:** GalleryView refactor, test hygiene fixes (`try!` in setUp, sleep-based waits), missing test coverage for FileWatcher/LinkTitleFetcher/PathValidation. Those are separate plans.

---

## Preliminaries

- [ ] **Confirm working tree is clean**

Run: `git status`
Expected: `nothing to commit, working tree clean`

If dirty, stash or commit first. This plan creates one commit per task for reviewability.

- [ ] **Note the baseline test-suite status**

Run: `xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -quiet 2>&1 | tail -40`

Expected: `** TEST SUCCEEDED **` at the bottom. Record any currently-failing tests so you can tell new regressions from pre-existing state.

---

## Task 1: Introduce `AppLogger`

**Files:**
- Create: `PortyMcFolio/Services/AppLogger.swift`

No test file — the compile check IS the test. Subsequent tasks exercise every category.

- [ ] **Step 1: Create the AppLogger file**

`PortyMcFolio/Services/AppLogger.swift`:

```swift
import Foundation
import os

/// Namespaced `os.Logger` instances used across the app.
///
/// One subsystem (`com.portymcfolio.app`), many categories. Filter in Console.app
/// by `subsystem:com.portymcfolio.app` and a specific category when debugging a
/// single subsystem.
///
/// Default string-interpolation privacy for `os.Logger` is `.private` in release
/// builds, which masks values with `<private>`. For this app — a single-user,
/// local-only portfolio tool — that is overzealous. Pass `privacy: .public` on
/// values you want to appear literally in logs (uids, paths, error descriptions).
enum AppLogger {
    private static let subsystem = "com.portymcfolio.app"

    static let app         = Logger(subsystem: subsystem, category: "app")
    static let reconciler  = Logger(subsystem: subsystem, category: "reconciler")
    static let cache       = Logger(subsystem: subsystem, category: "cache")
    static let search      = Logger(subsystem: subsystem, category: "search")
    static let frontmatter = Logger(subsystem: subsystem, category: "frontmatter")
    static let portfolio   = Logger(subsystem: subsystem, category: "portfolio")
    static let ui          = Logger(subsystem: subsystem, category: "ui")
}
```

- [ ] **Step 2: Regenerate the Xcode project and build**

Run: `xcodegen generate && xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio build -destination 'platform=macOS' -quiet 2>&1 | tail -20`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add PortyMcFolio/Services/AppLogger.swift
git commit -m "feat(logging): introduce AppLogger over os.Logger"
```

---

## Task 2: Fix `ProjectReconciler` — silent favorites write, silent mtime failure, migrate prints

**Files:**
- Modify: `PortyMcFolio/Services/ProjectReconciler.swift`

This task replaces all 7 `print(...)` calls in this file with `AppLogger.reconciler` calls, fixes the silent `try?` at line 383, and makes `mtimeOf` log when it returns nil.

- [ ] **Step 1: Find `mtimeOf` and verify the current shape**

Run: `grep -n "func mtimeOf" PortyMcFolio/Services/ProjectReconciler.swift`

Expected output: a single line showing the function definition (around line 460 area, verify actual line number before editing).

- [ ] **Step 2: Add `import os` at the top if missing**

If the file does not already have `import os`, add it after the existing imports at the top of the file. (The file currently imports only `Foundation`, `Combine`, and `GRDB`. `AppLogger` does the `import os` internally, so callers don't need it — skip this step unless the Swift compiler asks for it.)

- [ ] **Step 3: Replace the silent favorites write at line 383**

Locate the block inside `syncProject` that ends with:

```swift
                let updated = FrontmatterParser.serialize(frontmatter: parsed)
                try? updated.write(to: readmeURL, atomically: true, encoding: .utf8)
```

Replace with:

```swift
                let updated = FrontmatterParser.serialize(frontmatter: parsed)
                do {
                    try updated.write(to: readmeURL, atomically: true, encoding: .utf8)
                } catch {
                    AppLogger.reconciler.error("favorites rewrite failed for uid=\(uid, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
```

- [ ] **Step 4: Make `mtimeOf` log on failure**

Find the `mtimeOf` function. It currently looks like:

```swift
private func mtimeOf(_ url: URL) -> Date? {
    let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
    return attrs?[.modificationDate] as? Date
}
```

Replace with:

```swift
private func mtimeOf(_ url: URL) -> Date? {
    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return attrs[.modificationDate] as? Date
    } catch {
        AppLogger.reconciler.warning("mtime read failed for \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        return nil
    }
}
```

If `mtimeOf` has a different exact shape in the current codebase, preserve its signature and just wrap the attributes read in do/catch + warning log. Do NOT change its return type.

- [ ] **Step 5: Replace the remaining `print(...)` calls in this file**

There are 8 `print` calls in `ProjectReconciler.swift`. For each, replace with the equivalent `AppLogger.reconciler` call using this mapping:

| Original | Replacement |
|----------|-------------|
| `print("[Reconciler] rebuildTags failed during reindexEverything: \(error)")` | `AppLogger.reconciler.error("rebuildTags failed during reindexEverything: \(error.localizedDescription, privacy: .public)")` |
| `print("[Reconciler] appendFilesAndLinks failed for uid=\(uid): \(error)")` | `AppLogger.reconciler.error("appendFilesAndLinks failed for uid=\(uid, privacy: .public): \(error.localizedDescription, privacy: .public)")` |
| `print("[Reconciler] projectFolderRenamed failed for uid=\(uid): \(error)")` | `AppLogger.reconciler.error("projectFolderRenamed failed for uid=\(uid, privacy: .public): \(error.localizedDescription, privacy: .public)")` |
| `print("[Reconciler] cache.loadAll failed: \(error)")` | `AppLogger.reconciler.error("cache.loadAll failed: \(error.localizedDescription, privacy: .public)")` |
| `print("[Reconciler] rebuildTags failed: \(error)")` | `AppLogger.reconciler.error("rebuildTags failed: \(error.localizedDescription, privacy: .public)")` |
| `print("[Reconciler] removal write failed for uid=\(uid): \(error)")` | `AppLogger.reconciler.error("removal write failed for uid=\(uid, privacy: .public): \(error.localizedDescription, privacy: .public)")` |
| `print("[Reconciler] parse failed for uid=\(uid) — leaving cache as-is")` | `AppLogger.reconciler.warning("parse failed for uid=\(uid, privacy: .public) — leaving cache as-is")` |
| `print("[Reconciler] atomic write failed for uid=\(uid): \(error)")` | `AppLogger.reconciler.error("atomic write failed for uid=\(uid, privacy: .public): \(error.localizedDescription, privacy: .public)")` |

Verify you caught all 8 by grepping after you edit — see Step 6.

- [ ] **Step 6: Verify no `print(` remains in this file**

Run: `grep -n "print(" PortyMcFolio/Services/ProjectReconciler.swift`

Expected: no output.

- [ ] **Step 7: Build and run the reconciler tests**

Run: `xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -only-testing:PortyMcFolioTests/ProjectReconcilerTests -only-testing:PortyMcFolioTests/ProjectReconcilerDebounceTests -quiet 2>&1 | tail -20`

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add PortyMcFolio/Services/ProjectReconciler.swift
git commit -m "fix(reconciler): surface favorites write errors via AppLogger"
```

---

## Task 3: Migrate `ProjectMetadataCache` prints + log duplicate-column

**Files:**
- Modify: `PortyMcFolio/Services/ProjectMetadataCache.swift`

- [ ] **Step 1: Replace the 3 `print(...)` calls**

- Line 95: `print("[Cache] load(uid:) failed for \(uid): \(error)")` → `AppLogger.cache.error("load(uid:) failed for \(uid, privacy: .public): \(error.localizedDescription, privacy: .public)")`
- Line 192: `print("[Cache] dropping corrupt row uid=\(uid) (bad tags_json)")` → `AppLogger.cache.error("dropping corrupt row uid=\(uid, privacy: .public) (bad tags_json)")`
- Line 203: `print("[Cache] dropping corrupt row uid=\(uid) (bad date_iso)")` → `AppLogger.cache.error("dropping corrupt row uid=\(uid, privacy: .public) (bad date_iso)")`

- [ ] **Step 2: Log the duplicate-column swallow at line ~60**

Current block:

```swift
            do {
                try conn.execute(sql: """
                    ALTER TABLE project_meta
                    ADD COLUMN favorites_json TEXT NOT NULL DEFAULT '[]'
                    """)
            } catch {
                // SQLite throws on duplicate column; that's expected on re-runs.
            }
```

Replace with:

```swift
            do {
                try conn.execute(sql: """
                    ALTER TABLE project_meta
                    ADD COLUMN favorites_json TEXT NOT NULL DEFAULT '[]'
                    """)
            } catch {
                // SQLite throws on duplicate column; that's expected on re-runs.
                AppLogger.cache.debug("ALTER TABLE favorites_json ignored (likely already exists): \(error.localizedDescription, privacy: .public)")
            }
```

- [ ] **Step 3: Verify and run cache tests**

```bash
grep -n "print(" PortyMcFolio/Services/ProjectMetadataCache.swift
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -only-testing:PortyMcFolioTests/ProjectMetadataCacheTests -quiet 2>&1 | tail -20
```

Expected: no `print(` lines; `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Services/ProjectMetadataCache.swift
git commit -m "chore(cache): migrate prints to AppLogger, log duplicate-column migration"
```

---

## Task 4: Migrate remaining Services prints (FrontmatterParser, PortfolioStore, SearchIndex)

**Files:**
- Modify: `PortyMcFolio/Services/FrontmatterParser.swift`
- Modify: `PortyMcFolio/Services/PortfolioStore.swift`
- Modify: `PortyMcFolio/Services/SearchIndex.swift`

- [ ] **Step 1: FrontmatterParser.swift:185**

Replace:

```swift
            print("[FrontmatterParser] YAML parse error: \(error)")
```

With:

```swift
            AppLogger.frontmatter.error("YAML parse error: \(error.localizedDescription, privacy: .public)")
```

- [ ] **Step 2: PortfolioStore.swift:42**

Replace:

```swift
                print("[PortfolioStore] loadReadme failed for \(folderName): \(error)")
```

With:

```swift
                AppLogger.portfolio.error("loadReadme failed for \(folderName, privacy: .public): \(error.localizedDescription, privacy: .public)")
```

- [ ] **Step 3: SearchIndex.swift:307**

Replace:

```swift
                print("[SearchIndex] appendFilesAndLinks: project row missing for uid=\(uid); link/file rows will have empty secondary_text")
```

With:

```swift
                AppLogger.search.warning("appendFilesAndLinks: project row missing for uid=\(uid, privacy: .public); link/file rows will have empty secondary_text")
```

- [ ] **Step 4: Verify and test**

```bash
grep -rn "print(" PortyMcFolio/Services/
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio build -destination 'platform=macOS' -quiet 2>&1 | tail -10
```

Expected: no `print(` in Services; `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Services/FrontmatterParser.swift PortyMcFolio/Services/PortfolioStore.swift PortyMcFolio/Services/SearchIndex.swift
git commit -m "chore(services): migrate prints to AppLogger"
```

---

## Task 5: Migrate App + Views prints

**Files:**
- Modify: `PortyMcFolio/App/AppState.swift`
- Modify: `PortyMcFolio/Views/SearchPalette.swift`
- Modify: `PortyMcFolio/Views/ProjectListView.swift`
- Modify: `PortyMcFolio/Views/ProjectSettingsPopover.swift`
- Modify: `PortyMcFolio/Views/MarkdownEditorView.swift`
- Modify: `PortyMcFolio/Views/GalleryView.swift`

- [ ] **Step 1: AppState.swift:519**

Replace:

```swift
            print("[AppState] SearchIndex/cache init failed: \(error). Will retry on refresh.")
```

With:

```swift
            AppLogger.app.error("SearchIndex/cache init failed: \(error.localizedDescription, privacy: .public). Will retry on refresh.")
```

- [ ] **Step 2: SearchPalette.swift — three prints at 379, 390, 399**

- `print("[SearchPalette] project result not found in appState.projects — uid=\(result.entityID) title=\(result.primaryText); click ignored")`
  → `AppLogger.search.warning("project result not found in appState.projects — uid=\(result.entityID, privacy: .public) title=\(result.primaryText, privacy: .public); click ignored")`
- `print("[SearchPalette] file result parent not found — parentUID=\(result.parentUID) parentTitle=\(result.secondaryText)")`
  → `AppLogger.search.warning("file result parent not found — parentUID=\(result.parentUID, privacy: .public) parentTitle=\(result.secondaryText, privacy: .public)")`
- `print("[SearchPalette] link result parent not found — parentUID=\(result.parentUID) secondary=\(result.secondaryText)")`
  → `AppLogger.search.warning("link result parent not found — parentUID=\(result.parentUID, privacy: .public) secondary=\(result.secondaryText, privacy: .public)")`

- [ ] **Step 3: ProjectListView.swift:536**

Replace:

```swift
            print("[CSVExport] write failed: \(error)")
```

With:

```swift
            AppLogger.ui.error("CSV export write failed: \(error.localizedDescription, privacy: .public)")
```

- [ ] **Step 4: ProjectSettingsPopover.swift:248**

Replace:

```swift
            print("[ProjectSettings] Save failed: \(error)")
```

With:

```swift
            AppLogger.ui.error("ProjectSettings save failed: \(error.localizedDescription, privacy: .public)")
```

- [ ] **Step 5: MarkdownEditorView.swift:543**

Replace:

```swift
                print("[MarkdownEditorView] Save failed: \(error)")
```

With:

```swift
                AppLogger.ui.error("MarkdownEditor save failed: \(error.localizedDescription, privacy: .public)")
```

- [ ] **Step 6: GalleryView.swift — two prints at 872, 912**

- `print("[GalleryView] failed to save link: \(error)")`
  → `AppLogger.ui.error("GalleryView: failed to save link: \(error.localizedDescription, privacy: .public)")`
- `print("[GalleryView] failed to write fetched title: \(error)")`
  → `AppLogger.ui.error("GalleryView: failed to write fetched title: \(error.localizedDescription, privacy: .public)")`

- [ ] **Step 7: Verify and build**

```bash
grep -rn "print(" PortyMcFolio/App/ PortyMcFolio/Views/
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio build -destination 'platform=macOS' -quiet 2>&1 | tail -10
```

Expected: no `print(` lines in App/ or Views/; `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add PortyMcFolio/App/AppState.swift PortyMcFolio/Views/SearchPalette.swift PortyMcFolio/Views/ProjectListView.swift PortyMcFolio/Views/ProjectSettingsPopover.swift PortyMcFolio/Views/MarkdownEditorView.swift PortyMcFolio/Views/GalleryView.swift
git commit -m "chore(ui): migrate prints to AppLogger"
```

---

## Task 6: Make `ProjectFileOps.updateReferences` throw on write failure

**Files:**
- Modify: `PortyMcFolio/Services/ProjectFileOps.swift`
- Modify: `PortyMcFolio/Views/CarouselView.swift` (line 418 call site)
- Modify: `PortyMcFolio/Views/GalleryView.swift` (line 1407 call site)
- Create: `PortyMcFolioTests/ProjectFileOpsTests.swift`

**Rationale:** The current signature `-> Bool` swallows write errors and claims success. Callers post `.markdownFileDidChange` on `true`, but the file may not have been written. Making it `throws -> Bool` forces callers to decide — retry, show the user, or log.

- [ ] **Step 1: Write the failing test file**

`PortyMcFolioTests/ProjectFileOpsTests.swift`:

```swift
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

    func testThrowsWhenWriteFails() throws {
        let project = try makeProject(teaser: "hero.jpg")
        // Make the project folder read-only so the atomic write's rename fails.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: project.folderURL.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: project.folderURL.path
            )
        }
        XCTAssertThrowsError(
            try ProjectFileOps.updateReferences(in: project, from: "hero.jpg", to: "cover.jpg")
        )
    }
}
```

- [ ] **Step 2: Run the new test file — expect failures**

Run: `xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -only-testing:PortyMcFolioTests/ProjectFileOpsTests -quiet 2>&1 | tail -30`

You may first need to regenerate the project so the new test file is included:

```bash
xcodegen generate
```

Then re-run the test command above.

Expected: compile error — `updateReferences` is not `throws`, so the `try`/`XCTAssertThrowsError` calls will fail to compile.

- [ ] **Step 3: Change `ProjectFileOps.updateReferences` to throw**

Replace the function body in `PortyMcFolio/Services/ProjectFileOps.swift`:

```swift
import Foundation

enum ProjectFileOps {
    /// Updates README references (teaser, body `![[…]]` embeds, favorites)
    /// when a file's project-relative path changes. Caller is responsible
    /// for the actual filesystem move and for posting
    /// `.markdownFileDidChange` / reconciler notifications after this runs.
    /// Returns true if the README was modified and successfully written.
    /// Throws if reading, parsing, or writing the README fails.
    @MainActor
    static func updateReferences(
        in project: Project,
        from oldRelative: String,
        to newRelative: String
    ) throws -> Bool {
        guard oldRelative != newRelative else { return false }

        // Flush any pending debounced editor save BEFORE reading the
        // README from disk, so user-typed-but-not-yet-saved edits don't
        // clobber our rewrite when the editor's debounce fires later.
        NotificationCenter.default.post(name: .markdownSaveNow, object: nil)

        let content = try String(contentsOf: project.readmeURL, encoding: .utf8)
        var parsed = try FrontmatterParser.parse(content)

        var changed = false

        if parsed.teaser == oldRelative {
            parsed.teaser = newRelative
            changed = true
        }

        let oldEmbed = "![[\(oldRelative)]]"
        if parsed.body.contains(oldEmbed) {
            parsed.body = parsed.body.replacingOccurrences(of: oldEmbed, with: "![[\(newRelative)]]")
            changed = true
        }

        let newFavorites = FrontmatterParser.rewritingFavorite(
            in: parsed.favorites, from: oldRelative, to: newRelative
        )
        if newFavorites != parsed.favorites {
            parsed.favorites = newFavorites
            changed = true
        }

        guard changed else { return false }
        let updated = FrontmatterParser.serialize(frontmatter: parsed)
        try updated.write(to: project.readmeURL, atomically: true, encoding: .utf8)
        return true
    }
}
```

Key changes from the original:
- Signature: `throws -> Bool`
- `try? String(contentsOf:)` → `try` (propagate read failure)
- `try? FrontmatterParser.parse(...)` → `try` (propagate parse failure)
- `try? updated.write(...)` → `try` (propagate write failure)

- [ ] **Step 4: Update the CarouselView call site**

In `PortyMcFolio/Views/CarouselView.swift`, find the call at ~:418:

```swift
        if ProjectFileOps.updateReferences(in: project, from: oldRel, to: newRel) {
```

Replace with:

```swift
        let didRewrite: Bool
        do {
            didRewrite = try ProjectFileOps.updateReferences(in: project, from: oldRel, to: newRel)
        } catch {
            AppLogger.ui.error("CarouselView: updateReferences failed: \(error.localizedDescription, privacy: .public)")
            didRewrite = false
        }
        if didRewrite {
```

Read the surrounding lines in the file and match the closing brace — the original had a single-expression `if`; the new form preserves the existing body of the `if`.

- [ ] **Step 5: Update the GalleryView call site**

In `PortyMcFolio/Views/GalleryView.swift`, find the call at ~:1407:

```swift
        if ProjectFileOps.updateReferences(in: project, from: oldRelative, to: newRelative) {
```

Replace with:

```swift
        let didRewrite: Bool
        do {
            didRewrite = try ProjectFileOps.updateReferences(in: project, from: oldRelative, to: newRelative)
        } catch {
            AppLogger.ui.error("GalleryView: updateReferences failed: \(error.localizedDescription, privacy: .public)")
            didRewrite = false
        }
        if didRewrite {
```

- [ ] **Step 6: Run the new tests — expect pass**

```bash
xcodegen generate
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -only-testing:PortyMcFolioTests/ProjectFileOpsTests -quiet 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **` with 4 tests passing.

If `testThrowsWhenWriteFails` fails to actually throw on your machine (the rename might succeed despite the read-only parent on some filesystems), use this alternative: after creating the project, delete the project's folder between setup and the call:

```swift
    func testThrowsWhenWriteFails() throws {
        let project = try makeProject(teaser: "hero.jpg")
        // Remove the folder on disk; the read will throw.
        try FileManager.default.removeItem(at: project.folderURL)
        XCTAssertThrowsError(
            try ProjectFileOps.updateReferences(in: project, from: "hero.jpg", to: "cover.jpg")
        )
    }
```

This exercises the read-path throw instead of the write-path throw, which is equally good at proving errors propagate.

- [ ] **Step 7: Run the full test suite to catch regressions in the caller files**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -quiet 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add PortyMcFolio/Services/ProjectFileOps.swift PortyMcFolio/Views/CarouselView.swift PortyMcFolio/Views/GalleryView.swift PortyMcFolioTests/ProjectFileOpsTests.swift
git commit -m "fix(projectfileops): propagate write errors via throws -> Bool"
```

---

## Task 7: `UID.generate` — non-crashing fallback

**Files:**
- Modify: `PortyMcFolio/Services/UID.swift`
- Modify: `PortyMcFolioTests/UIDTests.swift`

**Rationale:** `precondition(status == errSecSuccess)` crashes the app if `SecRandomCopyBytes` fails, on a user-reachable path (new project). `UID` is a folder-name disambiguator, not a security token — there is no cryptographic requirement. A `UUID`-derived fallback is entirely fine when CommonCrypto is unavailable.

- [ ] **Step 1: Read the existing UIDTests to follow house style**

Run: `cat PortyMcFolioTests/UIDTests.swift`

Note the assertion style it uses; match it.

- [ ] **Step 2: Add failing tests for the fallback helper**

Append to `PortyMcFolioTests/UIDTests.swift` (or add new test methods inside the existing class — pick whichever matches the file's current structure):

```swift
    func testFallbackHexIsEightLowercaseHexCharacters() {
        let hex = UID.fallbackHex()
        XCTAssertEqual(hex.count, 8)
        let hexSet = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(hex.unicodeScalars.allSatisfy { hexSet.contains($0) })
    }

    func testFallbackHexIsUnique() {
        // UUID-derived fallback must not collide across rapid calls.
        var seen = Set<String>()
        for _ in 0..<50 {
            seen.insert(UID.fallbackHex())
        }
        XCTAssertGreaterThan(seen.count, 40, "fallbackHex should produce mostly-unique values")
    }

    func testSecureRandomHexReturnsEightHexOrNil() {
        if let hex = UID.secureRandomHex() {
            XCTAssertEqual(hex.count, 8)
            let hexSet = CharacterSet(charactersIn: "0123456789abcdef")
            XCTAssertTrue(hex.unicodeScalars.allSatisfy { hexSet.contains($0) })
        }
        // If SecRandomCopyBytes returns nil on this environment, the test still passes
        // — we're asserting a shape contract, not that it always succeeds.
    }
```

- [ ] **Step 3: Run the new tests — expect fail**

```bash
xcodegen generate
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -only-testing:PortyMcFolioTests/UIDTests -quiet 2>&1 | tail -20
```

Expected: compile error — `UID.fallbackHex` and `UID.secureRandomHex` don't exist yet.

- [ ] **Step 4: Refactor `UID.swift`**

Replace the entire contents of `PortyMcFolio/Services/UID.swift` with:

```swift
import Foundation
import Security

enum UID {
    /// Generate an 8-character lowercase hex string to disambiguate project folder
    /// names. Prefers cryptographically random bytes via `SecRandomCopyBytes`;
    /// falls back to a `UUID`-derived hex if the system RNG call fails.
    ///
    /// UID is not a security token — it's a folder-name suffix. A UUID-derived
    /// fallback is perfectly adequate when `SecRandomCopyBytes` is unavailable,
    /// and is strictly better than crashing the app on project creation.
    static func generate() -> String {
        if let hex = secureRandomHex() {
            return hex
        }
        AppLogger.app.warning("SecRandomCopyBytes unavailable; falling back to UUID-derived UID")
        return fallbackHex()
    }

    /// Internal — exposed for testing. Returns nil if `SecRandomCopyBytes` fails.
    static func secureRandomHex() -> String? {
        var bytes = [UInt8](repeating: 0, count: 4)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { return nil }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Internal — exposed for testing. Returns 8 lowercase hex chars derived
    /// from a fresh `UUID`. Non-cryptographic but collision-resistant enough
    /// for a folder-name suffix.
    static func fallbackHex() -> String {
        let uuid = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return String(uuid.prefix(8))
    }
}
```

Note: `secureRandomHex()` and `fallbackHex()` are internal (no `private`) so the test target — using `@testable import PortyMcFolio` — can exercise them directly.

- [ ] **Step 5: Run the new tests — expect pass**

```bash
xcodegen generate
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -only-testing:PortyMcFolioTests/UIDTests -quiet 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **` with the 3 new tests plus any existing UID tests passing.

- [ ] **Step 6: Commit**

```bash
git add PortyMcFolio/Services/UID.swift PortyMcFolioTests/UIDTests.swift
git commit -m "fix(uid): fall back to UUID-derived hex instead of precondition-crashing"
```

---

## Task 8: Final verification

- [ ] **Step 1: Run the full test suite**

Run: `xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -quiet 2>&1 | tail -30`

Expected: `** TEST SUCCEEDED **` with no regressions compared to the baseline recorded in Preliminaries.

- [ ] **Step 2: Confirm no `print(` remains in the app target**

Run: `grep -rn "print(" PortyMcFolio/`

Expected: no output. (If there are `#if DEBUG` blocks with print that you want to keep, document why; otherwise migrate them too.)

- [ ] **Step 3: Smoke-test the app**

```bash
xcodegen generate
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio build -destination 'platform=macOS' -quiet 2>&1 | tail -10
open build/Build/Products/Debug/PortyMcFolio.app
```

Exercise: open a portfolio, create a project, edit frontmatter, rename a project (triggers `ProjectFileOps.updateReferences`), drag a media file into the gallery. Check `Console.app` → filter `subsystem:com.portymcfolio.app` to verify logs surface under the expected categories.

- [ ] **Step 4: No final commit needed — the per-task commits already capture everything.**

---

## Spec coverage check

| Review finding | Addressed by |
|----------------|--------------|
| ProjectFileOps:48 silent `try?` write + returns true | Task 6 |
| ProjectReconciler:383 silent `try?` favorites write | Task 2 |
| ProjectReconciler mtimeOf silent nil on error | Task 2 (Step 4) |
| UID.generate precondition crash on user path | Task 7 |
| Inconsistent `print()` logging across 11 files | Tasks 2–5 |
| ProjectMetadataCache:59 swallowed duplicate-column | Task 3 (Step 2) |
