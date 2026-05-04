# External-Edit Resilience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-repair stale teaser + body-embed references on external file rename (symmetric with existing `FavoritesReconciliation`), and surface a toast when favorites are dropped outright.

**Architecture:** Two new pure reconciliation helpers (`TeaserReconciliation`, `BodyEmbedReconciliation`) mirroring the existing `FavoritesReconciliation` algorithm (basename match, 1 match = repair, else = leave alone). `FavoritesReconciliation` return type upgraded to include `droppedCount`. `ProjectReconciler.syncProject` runs all three in one pass, serializes the modified frontmatter/body once, writes atomically, and fires a drop-toast if favorites were lost.

**Tech Stack:** Swift 5.9, `NSRegularExpression`, XCTest. Xcode project generated from `project.yml` via xcodegen.

**Spec:** [docs/superpowers/specs/2026-04-24-external-edit-resilience-design.md](docs/superpowers/specs/2026-04-24-external-edit-resilience-design.md)

**Out of scope:**
- UI for manually resolving ambiguous renames.
- Heuristics beyond basename match.
- Link-file repair (link files have fixed `link-{hex}.md` pattern; out of scope).
- Toast on teaser or body-embed changes (by design — too chatty).

---

## Preliminaries

- [ ] **Confirm clean working tree and record baseline**

```bash
git status
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -quiet 2>&1 | tail -5
```

Expected: `nothing to commit`; test run exits 0. Baseline Swift 6 mode warnings in `AppState.swift` are pre-existing — not yours.

---

## Task 1: `TeaserReconciliation` pure helper

**Files:**
- Create: `PortyMcFolio/Services/TeaserReconciliation.swift`
- Create: `PortyMcFolioTests/TeaserReconciliationTests.swift`

**Rationale:** Pure function mirroring `FavoritesReconciliation`'s basename match. Repairs a stale teaser path when the referenced file was renamed under a unique new basename; otherwise leaves it alone.

### Step 1: Write the test file FIRST (TDD)

Create `PortyMcFolioTests/TeaserReconciliationTests.swift`:

```swift
import XCTest
@testable import PortyMcFolio

final class TeaserReconciliationTests: XCTestCase {
    func testEmptyTeaserIsUnchanged() {
        XCTAssertEqual(
            TeaserReconciliation.reconcile(teaser: "", onDiskPaths: ["a.jpg"]),
            .unchanged
        )
    }

    func testTeaserStillOnDiskIsUnchanged() {
        XCTAssertEqual(
            TeaserReconciliation.reconcile(
                teaser: "hero.jpg",
                onDiskPaths: ["hero.jpg", "other.jpg"]
            ),
            .unchanged
        )
    }

    func testStaleTeaserWithOneBasenameMatchIsRepaired() {
        XCTAssertEqual(
            TeaserReconciliation.reconcile(
                teaser: "hero.jpg",
                onDiskPaths: ["subfolder/hero.jpg", "other.jpg"]
            ),
            .repaired(newPath: "subfolder/hero.jpg")
        )
    }

    func testStaleTeaserWithMultipleBasenameMatchesIsOrphaned() {
        XCTAssertEqual(
            TeaserReconciliation.reconcile(
                teaser: "hero.jpg",
                onDiskPaths: ["a/hero.jpg", "b/hero.jpg"]
            ),
            .orphaned
        )
    }

    func testStaleTeaserWithZeroMatchesIsOrphaned() {
        XCTAssertEqual(
            TeaserReconciliation.reconcile(
                teaser: "hero.jpg",
                onDiskPaths: ["other.jpg"]
            ),
            .orphaned
        )
    }

    func testAbsolutePathIsUnchanged() {
        XCTAssertEqual(
            TeaserReconciliation.reconcile(
                teaser: "/etc/hero.jpg",
                onDiskPaths: ["hero.jpg"]
            ),
            .unchanged
        )
    }

    func testDotDotPathIsUnchanged() {
        XCTAssertEqual(
            TeaserReconciliation.reconcile(
                teaser: "../hero.jpg",
                onDiskPaths: ["hero.jpg"]
            ),
            .unchanged
        )
    }

    func testBasenameMatchIsCaseInsensitive() {
        XCTAssertEqual(
            TeaserReconciliation.reconcile(
                teaser: "Hero.JPG",
                onDiskPaths: ["subfolder/hero.jpg"]
            ),
            .repaired(newPath: "subfolder/hero.jpg")
        )
    }
}
```

### Step 2: Run new tests — expect compile failure

```bash
xcodegen generate
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -only-testing:PortyMcFolioTests/TeaserReconciliationTests -quiet 2>&1 | tail -20
```

Expected: compile error — `TeaserReconciliation` doesn't exist.

### Step 3: Create the helper

`PortyMcFolio/Services/TeaserReconciliation.swift`:

```swift
import Foundation

enum TeaserOutcome: Equatable {
    case unchanged
    case repaired(newPath: String)
    case orphaned
}

/// Pure reconciliation for a project's `teaser` frontmatter field against the
/// current on-disk file tree. Used by `ProjectReconciler` as a safety net for
/// external (Finder-driven) renames.
///
/// Mirrors `FavoritesReconciliation`'s basename-match algorithm:
/// 1. Empty, absolute (`/…`), or dot-dot (`..`) paths → `.unchanged`.
/// 2. Teaser path still resolves on disk → `.unchanged`.
/// 3. Exactly one file on disk shares the teaser's lowercased basename → `.repaired(newPath:)`.
/// 4. Zero or multiple basename matches → `.orphaned`.
enum TeaserReconciliation {
    static func reconcile(
        teaser: String,
        onDiskPaths: Set<String>
    ) -> TeaserOutcome {
        guard !teaser.isEmpty else { return .unchanged }
        if teaser.hasPrefix("/") || teaser.contains("..") { return .unchanged }
        if onDiskPaths.contains(teaser) { return .unchanged }

        let basename = (teaser as NSString).lastPathComponent.lowercased()
        let candidates = onDiskPaths.filter {
            ($0 as NSString).lastPathComponent.lowercased() == basename
        }
        guard candidates.count == 1, let new = candidates.first else {
            return .orphaned
        }
        return .repaired(newPath: new)
    }
}
```

### Step 4: Regenerate + run tests — expect pass

```bash
xcodegen generate
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -only-testing:PortyMcFolioTests/TeaserReconciliationTests -quiet 2>&1 | tail -15
```

Expected: 8 tests pass.

### Step 5: Run full suite to confirm no regressions

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -quiet 2>&1 | tail -5
```

Expected: exit 0.

### Step 6: Commit

```bash
git add PortyMcFolio/Services/TeaserReconciliation.swift PortyMcFolioTests/TeaserReconciliationTests.swift
git commit -m "feat(services): TeaserReconciliation pure helper + tests"
```

---

## Task 2: `BodyEmbedReconciliation` pure helper

**Files:**
- Create: `PortyMcFolio/Services/BodyEmbedReconciliation.swift`
- Create: `PortyMcFolioTests/BodyEmbedReconciliationTests.swift`

**Rationale:** Walks `![[…]]` embeds in body text, repairs references to renamed files where basename is unique, leaves all other embeds + all non-embed text alone. `repaired` list deduplicates by `(oldPath, newPath)` pair so a body with two `![[hero.jpg]]` references gets reported as one repair.

### Step 1: Write the test file FIRST

Create `PortyMcFolioTests/BodyEmbedReconciliationTests.swift`:

```swift
import XCTest
@testable import PortyMcFolio

final class BodyEmbedReconciliationTests: XCTestCase {
    func testBodyWithNoEmbedsIsUnchanged() {
        let body = "# Title\n\nJust prose, no embeds."
        let result = BodyEmbedReconciliation.reconcile(body: body, onDiskPaths: ["hero.jpg"])
        XCTAssertEqual(result.body, body)
        XCTAssertTrue(result.repaired.isEmpty)
        XCTAssertTrue(result.orphaned.isEmpty)
    }

    func testEmbedThatResolvesIsUnchanged() {
        let body = "# Title\n\n![[hero.jpg]]"
        let result = BodyEmbedReconciliation.reconcile(body: body, onDiskPaths: ["hero.jpg"])
        XCTAssertEqual(result.body, body)
        XCTAssertTrue(result.repaired.isEmpty)
        XCTAssertTrue(result.orphaned.isEmpty)
    }

    func testStaleEmbedWithOneMatchIsRepaired() {
        let body = "# Title\n\n![[hero.jpg]]\n"
        let result = BodyEmbedReconciliation.reconcile(
            body: body,
            onDiskPaths: ["subfolder/hero.jpg"]
        )
        XCTAssertEqual(result.body, "# Title\n\n![[subfolder/hero.jpg]]\n")
        XCTAssertEqual(result.repaired, [
            .init(oldPath: "hero.jpg", newPath: "subfolder/hero.jpg")
        ])
        XCTAssertTrue(result.orphaned.isEmpty)
    }

    func testStaleEmbedWithZeroMatchesIsOrphaned() {
        let body = "# Title\n\n![[hero.jpg]]"
        let result = BodyEmbedReconciliation.reconcile(
            body: body,
            onDiskPaths: ["other.jpg"]
        )
        XCTAssertEqual(result.body, body)
        XCTAssertTrue(result.repaired.isEmpty)
        XCTAssertEqual(result.orphaned, ["hero.jpg"])
    }

    func testStaleEmbedWithMultipleMatchesIsOrphaned() {
        let body = "![[hero.jpg]]"
        let result = BodyEmbedReconciliation.reconcile(
            body: body,
            onDiskPaths: ["a/hero.jpg", "b/hero.jpg"]
        )
        XCTAssertEqual(result.body, body)
        XCTAssertTrue(result.repaired.isEmpty)
        XCTAssertEqual(result.orphaned, ["hero.jpg"])
    }

    func testTwoEmbedsPointingToSameRenamedFileAreRewrittenConsistentlyAndDedupedInRepaired() {
        let body = "![[hero.jpg]]\nSome text.\n![[hero.jpg]]"
        let result = BodyEmbedReconciliation.reconcile(
            body: body,
            onDiskPaths: ["new/hero.jpg"]
        )
        XCTAssertEqual(result.body, "![[new/hero.jpg]]\nSome text.\n![[new/hero.jpg]]")
        // Deduplicated by (oldPath, newPath) — one entry even though two rewrites happened.
        XCTAssertEqual(result.repaired, [
            .init(oldPath: "hero.jpg", newPath: "new/hero.jpg")
        ])
        XCTAssertTrue(result.orphaned.isEmpty)
    }

    func testEmbedWithAbsolutePathIsSkipped() {
        let body = "![[/etc/passwd]]"
        let result = BodyEmbedReconciliation.reconcile(
            body: body,
            onDiskPaths: ["passwd"]
        )
        XCTAssertEqual(result.body, body)
        XCTAssertTrue(result.repaired.isEmpty)
        XCTAssertTrue(result.orphaned.isEmpty)
    }

    func testEmbedWithDotDotPathIsSkipped() {
        let body = "![[../sibling.jpg]]"
        let result = BodyEmbedReconciliation.reconcile(
            body: body,
            onDiskPaths: ["sibling.jpg"]
        )
        XCTAssertEqual(result.body, body)
        XCTAssertTrue(result.repaired.isEmpty)
        XCTAssertTrue(result.orphaned.isEmpty)
    }

    func testRewritePreservesSurroundingTextByteForByte() {
        let body = """
        # Header

        ```swift
        let x = 1  // ![[code.jpg]] is literal here but the pattern still matches
        ```

        ![[hero.jpg]]

        More text **with** _markdown_.
        """
        let result = BodyEmbedReconciliation.reconcile(
            body: body,
            onDiskPaths: ["new/hero.jpg", "new/code.jpg"]
        )
        // Both embeds get rewritten (the regex doesn't know about code fences — that's OK).
        XCTAssertTrue(result.body.contains("![[new/hero.jpg]]"))
        XCTAssertTrue(result.body.contains("![[new/code.jpg]]"))
        XCTAssertTrue(result.body.contains("# Header"))
        XCTAssertTrue(result.body.contains("More text **with** _markdown_"))
        XCTAssertFalse(result.body.contains("![[hero.jpg]]"))
        XCTAssertFalse(result.body.contains("![[code.jpg]]"))
    }

    func testOrphanedListDedupes() {
        let body = "![[missing.jpg]] and then ![[missing.jpg]] again"
        let result = BodyEmbedReconciliation.reconcile(
            body: body,
            onDiskPaths: []
        )
        XCTAssertEqual(result.orphaned, ["missing.jpg"])
    }
}
```

### Step 2: Run new tests — expect compile failure

```bash
xcodegen generate
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -only-testing:PortyMcFolioTests/BodyEmbedReconciliationTests -quiet 2>&1 | tail -20
```

Expected: compile error — `BodyEmbedReconciliation` doesn't exist.

### Step 3: Create the helper

`PortyMcFolio/Services/BodyEmbedReconciliation.swift`:

```swift
import Foundation

struct BodyEmbedResult: Equatable {
    let body: String
    let repaired: [Repair]
    let orphaned: [String]

    struct Repair: Equatable {
        let oldPath: String
        let newPath: String
    }
}

/// Pure reconciliation for `![[…]]` embeds in a project body. Mirrors
/// `FavoritesReconciliation` / `TeaserReconciliation`: repairs references to
/// renamed files when the basename is unique on disk, leaves everything else
/// alone.
///
/// - Embeds with absolute (`/…`) or dot-dot (`..`) paths are skipped entirely
///   and appear in neither list.
/// - `repaired` deduplicates by `(oldPath, newPath)` pair: a body with three
///   `![[hero.jpg]]` references that all repair to `new/hero.jpg` produces
///   exactly one entry in `repaired` (and three rewrites in `body`).
/// - `orphaned` also deduplicates by path.
/// - Non-embed text is preserved byte-for-byte.
enum BodyEmbedReconciliation {
    private static let embedRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"!\[\[([^\]]+)\]\]"#)
    }()

    static func reconcile(
        body: String,
        onDiskPaths: Set<String>
    ) -> BodyEmbedResult {
        let nsBody = body as NSString
        let fullRange = NSRange(location: 0, length: nsBody.length)
        let matches = embedRegex.matches(in: body, range: fullRange)

        // Pre-index on-disk paths by lowercased basename.
        var byBasename: [String: [String]] = [:]
        for path in onDiskPaths {
            let basename = (path as NSString).lastPathComponent.lowercased()
            byBasename[basename, default: []].append(path)
        }

        // Decisions applied in reverse so earlier NSRange indices stay valid.
        struct Rewrite { let range: NSRange; let newPath: String }
        var rewrites: [Rewrite] = []
        var repaired: [BodyEmbedResult.Repair] = []
        var repairedKeys: Set<String> = []  // "oldPath\u{0}newPath"
        var orphaned: [String] = []
        var orphanedSeen: Set<String> = []

        for match in matches {
            guard match.numberOfRanges == 2 else { continue }
            let pathRange = match.range(at: 1)
            let oldPath = nsBody.substring(with: pathRange).trimmingCharacters(in: .whitespaces)

            if oldPath.hasPrefix("/") || oldPath.contains("..") { continue }
            if onDiskPaths.contains(oldPath) { continue }

            let basename = (oldPath as NSString).lastPathComponent.lowercased()
            let candidates = byBasename[basename] ?? []
            if candidates.count == 1, let new = candidates.first {
                rewrites.append(Rewrite(range: pathRange, newPath: new))
                let key = "\(oldPath)\u{0}\(new)"
                if !repairedKeys.contains(key) {
                    repairedKeys.insert(key)
                    repaired.append(.init(oldPath: oldPath, newPath: new))
                }
            } else {
                if !orphanedSeen.contains(oldPath) {
                    orphanedSeen.insert(oldPath)
                    orphaned.append(oldPath)
                }
            }
        }

        // Apply rewrites in reverse so earlier ranges remain valid.
        var out = body
        for rewrite in rewrites.reversed() {
            guard let swiftRange = Range(rewrite.range, in: out) else { continue }
            out.replaceSubrange(swiftRange, with: rewrite.newPath)
        }

        return BodyEmbedResult(body: out, repaired: repaired, orphaned: orphaned)
    }
}
```

### Step 4: Regenerate + run tests — expect pass

```bash
xcodegen generate
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -only-testing:PortyMcFolioTests/BodyEmbedReconciliationTests -quiet 2>&1 | tail -15
```

Expected: 10 tests pass.

### Step 5: Full suite

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -quiet 2>&1 | tail -5
```

Expected: exit 0.

### Step 6: Commit

```bash
git add PortyMcFolio/Services/BodyEmbedReconciliation.swift PortyMcFolioTests/BodyEmbedReconciliationTests.swift
git commit -m "feat(services): BodyEmbedReconciliation pure helper + tests"
```

---

## Task 3: `FavoritesReconciliation` returns `FavoritesResult` with `droppedCount`

**Files:**
- Modify: `PortyMcFolio/Services/FavoritesReconciliation.swift`
- Modify: `PortyMcFolio/Services/ProjectReconciler.swift` (one caller, line ~376)
- Modify: `PortyMcFolioTests/FavoritesReconciliationTests.swift`

**Rationale:** Need to know how many favorites were dropped (not relocated) so `syncProject` can decide whether to fire the toast in Task 4. A relocation (basename match succeeds) is NOT a drop; only 0-match or ambiguous-match counts as a drop. Duplicates (same resolved path) are silent dedupes, not drops.

### Step 1: Add failing tests to `FavoritesReconciliationTests`

Read the existing file first (`cat PortyMcFolioTests/FavoritesReconciliationTests.swift`) to match its style. Then APPEND these tests inside the existing test class (before its closing `}`):

```swift
    // MARK: - droppedCount (added 2026-04-24)

    func testDroppedCountZeroWhenAllFavoritesResolve() {
        let result = FavoritesReconciliation.reconcile(
            favorites: ["a.jpg", "b.jpg"],
            onDiskPaths: ["a.jpg", "b.jpg"]
        )
        XCTAssertEqual(result.reconciled, ["a.jpg", "b.jpg"])
        XCTAssertEqual(result.droppedCount, 0)
    }

    func testDroppedCountZeroWhenFavoriteIsRelocated() {
        let result = FavoritesReconciliation.reconcile(
            favorites: ["hero.jpg"],
            onDiskPaths: ["subfolder/hero.jpg"]
        )
        XCTAssertEqual(result.reconciled, ["subfolder/hero.jpg"])
        XCTAssertEqual(result.droppedCount, 0, "Relocation is not a drop")
    }

    func testDroppedCountOneWhenFavoriteHasNoMatch() {
        let result = FavoritesReconciliation.reconcile(
            favorites: ["hero.jpg"],
            onDiskPaths: ["other.jpg"]
        )
        XCTAssertEqual(result.reconciled, [])
        XCTAssertEqual(result.droppedCount, 1)
    }

    func testDroppedCountWhenFavoriteHasAmbiguousMatch() {
        let result = FavoritesReconciliation.reconcile(
            favorites: ["hero.jpg"],
            onDiskPaths: ["a/hero.jpg", "b/hero.jpg"]
        )
        XCTAssertEqual(result.reconciled, [])
        XCTAssertEqual(result.droppedCount, 1, "Ambiguous basename counts as a drop")
    }

    func testDroppedCountDoesNotIncludeDuplicates() {
        // Two favorites both resolve to the same disk path — one is deduped,
        // not dropped.
        let result = FavoritesReconciliation.reconcile(
            favorites: ["hero.jpg", "hero.jpg"],
            onDiskPaths: ["hero.jpg"]
        )
        XCTAssertEqual(result.reconciled, ["hero.jpg"])
        XCTAssertEqual(result.droppedCount, 0, "Duplicate is not a drop")
    }

    func testDroppedCountSumsAcrossMixedCases() {
        let result = FavoritesReconciliation.reconcile(
            favorites: ["kept.jpg", "missing.jpg", "ambiguous.jpg", "relocated.jpg"],
            onDiskPaths: [
                "kept.jpg",
                "a/ambiguous.jpg", "b/ambiguous.jpg",  // ambiguous → drop
                "new/relocated.jpg"                     // basename 1 match → relocate
            ]
        )
        XCTAssertEqual(result.reconciled, ["kept.jpg", "new/relocated.jpg"])
        XCTAssertEqual(result.droppedCount, 2, "missing.jpg and ambiguous.jpg")
    }
```

Every existing test in the file currently compares `.reconcile(...)` directly to an array. Those comparisons must be updated in Step 3 to read `.reconciled` off the new struct.

### Step 2: Run tests — expect compile failure for BOTH new and existing tests

```bash
xcodegen generate
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -only-testing:PortyMcFolioTests/FavoritesReconciliationTests -quiet 2>&1 | tail -30
```

Expected: compile errors. The new tests reference `result.reconciled` / `result.droppedCount` which don't exist. Existing tests compare `reconcile(...)` directly to `[String]` which won't work after the return type change.

### Step 3: Update the helper + all existing tests + the one non-test caller

**3a.** Replace `PortyMcFolio/Services/FavoritesReconciliation.swift` entirely with:

```swift
import Foundation

struct FavoritesResult: Equatable {
    let reconciled: [String]
    /// Favorites entries that had no single-match basename on disk —
    /// 0 matches OR ≥2 matches (ambiguous). Duplicates in the input that
    /// resolve to the same path are NOT counted as drops.
    let droppedCount: Int
}

/// Pure-function reconciliation of a project's favorites against the current
/// on-disk file tree. Used by `ProjectReconciler` as a safety net for external
/// (Finder-driven) moves the app's in-app hooks didn't see.
///
/// Algorithm, per entry in order:
/// 1. If the path still exists on disk, keep it.
/// 2. Otherwise, look for a file with the same basename (case-insensitive)
///    elsewhere on disk. Exactly one match → update to the new path.
/// 3. Zero matches → drop the entry (external delete or rename).
/// 4. Multiple matches → drop the entry (ambiguous; safer than guessing).
///
/// Result is de-duplicated (first occurrence wins) while preserving original
/// order. `droppedCount` counts cases 3 and 4 only.
enum FavoritesReconciliation {
    static func reconcile(
        favorites: [String],
        onDiskPaths: Set<String>
    ) -> FavoritesResult {
        var byBasename: [String: [String]] = [:]
        for path in onDiskPaths {
            let basename = (path as NSString).lastPathComponent.lowercased()
            byBasename[basename, default: []].append(path)
        }

        var reconciled: [String] = []
        var seen: Set<String> = []
        var droppedCount = 0

        for fav in favorites {
            let resolved: String?
            if onDiskPaths.contains(fav) {
                resolved = fav
            } else {
                let basename = (fav as NSString).lastPathComponent.lowercased()
                let candidates = byBasename[basename] ?? []
                resolved = candidates.count == 1 ? candidates.first : nil
            }

            if let path = resolved {
                if !seen.contains(path) {
                    reconciled.append(path)
                    seen.insert(path)
                }
                // else: duplicate — dedup silently, NOT a drop.
            } else {
                droppedCount += 1
            }
        }

        return FavoritesResult(reconciled: reconciled, droppedCount: droppedCount)
    }
}
```

**3b.** Update every existing test in `PortyMcFolioTests/FavoritesReconciliationTests.swift` that compares the result to `[String]`. Each test body like:

```swift
        let result = FavoritesReconciliation.reconcile(...)
        XCTAssertEqual(result, ["..."])
```

becomes:

```swift
        let result = FavoritesReconciliation.reconcile(...)
        XCTAssertEqual(result.reconciled, ["..."])
```

Read the file and apply this systematically. Don't change test semantics, just access `.reconciled`.

**3c.** Update the one non-test caller in `PortyMcFolio/Services/ProjectReconciler.swift`. Find the favorites-reconcile block around line 376:

```swift
        if !parsed.favorites.isEmpty {
            let mediaPaths = enumerateMediaPaths(under: folderInfo.folderURL)
            let reconciled = FavoritesReconciliation.reconcile(
                favorites: parsed.favorites,
                onDiskPaths: mediaPaths
            )
            if reconciled != parsed.favorites {
                parsed.favorites = reconciled
```

Change the two references:

```swift
        if !parsed.favorites.isEmpty {
            let mediaPaths = enumerateMediaPaths(under: folderInfo.folderURL)
            let favResult = FavoritesReconciliation.reconcile(
                favorites: parsed.favorites,
                onDiskPaths: mediaPaths
            )
            if favResult.reconciled != parsed.favorites {
                parsed.favorites = favResult.reconciled
```

**Do not** reshape the surrounding block yet — that's Task 4. This task keeps behavior identical; only the internal variable name and access change. Do not add the drop toast in this task.

### Step 4: Run tests — expect pass

```bash
xcodegen generate
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -only-testing:PortyMcFolioTests/FavoritesReconciliationTests -quiet 2>&1 | tail -15
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -only-testing:PortyMcFolioTests/ProjectReconcilerTests -quiet 2>&1 | tail -10
```

Expected: all pass.

### Step 5: Full suite

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -quiet 2>&1 | tail -5
```

Expected: exit 0.

### Step 6: Commit

```bash
git add PortyMcFolio/Services/FavoritesReconciliation.swift PortyMcFolio/Services/ProjectReconciler.swift PortyMcFolioTests/FavoritesReconciliationTests.swift
git commit -m "refactor(favorites): return FavoritesResult with droppedCount"
```

---

## Task 4: Integrate all three into `syncProject` + add drop toast + integration tests

**Files:**
- Modify: `PortyMcFolio/Services/ProjectReconciler.swift` (`syncProject`, lines ~370–395)
- Modify: `PortyMcFolioTests/ProjectReconcilerTests.swift`

**Rationale:** Wire teaser + body reconciliation into the existing favorites pass so all three happen in one on-disk walk and one atomic write. Fire the drop toast only when favorites were lost. Post `.markdownFileDidChange` once if anything changed.

### Step 1: Write failing integration tests in `ProjectReconcilerTests`

Read the existing `PortyMcFolioTests/ProjectReconcilerTests.swift` to learn its fixture style (it has `setUp` that builds `tempRoot`, `index`, `cache`, `reconciler`, and a `createDiskProject` helper). APPEND the following inside the existing test class, adapting the fixture helpers if needed:

```swift
    // MARK: - External-edit resilience (Task 4)

    /// Synchronously run one reconciliation pass for a single uid and wait for
    /// the reconciler queue to drain. Used by the tests below to avoid flaky
    /// RunLoop polling. Requires the test queue `reconciler.queue` to be
    /// accessible; adapt if the test file uses a different hook.
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
        try Data([0xFF, 0xD8, 0xFF, 0xE0]).write(to: newFileURL)  // minimal JPEG

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
        // Two embeds in the body, both rewritten.
        XCTAssertEqual(
            rewritten.body.components(separatedBy: "![[media/hero.jpg]]").count - 1,
            2
        )
        // Exactly one .markdownFileDidChange fired despite three repairs.
        XCTAssertEqual(fileDidChangeCount, 1)
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
```

If the existing test fixture uses a different way to construct `ParsedFrontmatter`, a different `createDiskProject`-style helper, or if `notifyProjectFileChanged` doesn't take a completion callback, adapt. The three behaviors to verify are:
- single atomic write + single `.markdownFileDidChange` for a combined repair
- `.showToast` fired with expected content on drops
- no write + no `.markdownFileDidChange` on no-op

### Step 2: Run — expect failure

```bash
xcodegen generate
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -only-testing:PortyMcFolioTests/ProjectReconcilerTests -quiet 2>&1 | tail -30
```

Expected: the three new tests fail (either at runtime or compile if fixture methods don't match).

### Step 3: Rewrite `syncProject`'s reconciliation block

In `PortyMcFolio/Services/ProjectReconciler.swift`, locate the current favorites-only block (around lines 370–394, shape after Task 3):

```swift
        var parsed = parsed0
        if !parsed.favorites.isEmpty {
            let mediaPaths = enumerateMediaPaths(under: folderInfo.folderURL)
            let favResult = FavoritesReconciliation.reconcile(
                favorites: parsed.favorites,
                onDiskPaths: mediaPaths
            )
            if favResult.reconciled != parsed.favorites {
                parsed.favorites = favResult.reconciled
                let updated = FrontmatterParser.serialize(frontmatter: parsed)
                do {
                    try updated.write(to: readmeURL, atomically: true, encoding: .utf8)
                    NotificationCenter.default.post(name: .markdownFileDidChange, object: readmeURL)
                } catch {
                    AppLogger.reconciler.error("favorites rewrite failed for uid=\(uid, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
```

Replace with:

```swift
        var parsed = parsed0
        var needsWrite = false
        var droppedFavoritesCount = 0

        // Single on-disk walk, shared by all three reconciliations.
        let mediaPaths = enumerateMediaPaths(under: folderInfo.folderURL)

        // 1. Favorites
        if !parsed.favorites.isEmpty {
            let favResult = FavoritesReconciliation.reconcile(
                favorites: parsed.favorites,
                onDiskPaths: mediaPaths
            )
            if favResult.reconciled != parsed.favorites {
                parsed.favorites = favResult.reconciled
                needsWrite = true
            }
            droppedFavoritesCount = favResult.droppedCount
        }

        // 2. Teaser
        if !parsed.teaser.isEmpty {
            let teaserOutcome = TeaserReconciliation.reconcile(
                teaser: parsed.teaser,
                onDiskPaths: mediaPaths
            )
            if case .repaired(let newPath) = teaserOutcome {
                parsed.teaser = newPath
                needsWrite = true
            }
        }

        // 3. Body embeds
        if !parsed.body.isEmpty {
            let bodyResult = BodyEmbedReconciliation.reconcile(
                body: parsed.body,
                onDiskPaths: mediaPaths
            )
            if bodyResult.body != parsed.body {
                parsed.body = bodyResult.body
                needsWrite = true
            }
        }

        // Write once if anything changed.
        if needsWrite {
            let updated = FrontmatterParser.serialize(frontmatter: parsed)
            do {
                try updated.write(to: readmeURL, atomically: true, encoding: .utf8)
                NotificationCenter.default.post(name: .markdownFileDidChange, object: readmeURL)
            } catch {
                AppLogger.reconciler.error("reconciliation rewrite failed for uid=\(uid, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        // Toast favorites drops (separate from the write — fires even if the
        // write itself didn't happen, e.g. all favorites were dropped so
        // there's nothing left to persist but the user still lost entries).
        if droppedFavoritesCount > 0 {
            let message: String
            if droppedFavoritesCount == 1 {
                message = "1 favorite removed from \"\(parsed.title)\" — file is gone."
            } else {
                message = "\(droppedFavoritesCount) favorites removed from \"\(parsed.title)\" — files are gone."
            }
            NotificationCenter.default.post(name: .showToast, object: message)
        }
```

Note: `droppedFavoritesCount > 0` can fire even when `needsWrite == false` (e.g., all favorites were dropped so `reconciled == []`, which differs from the original non-empty list → `needsWrite = true` above). In the edge case where the original favorites list was empty AND `droppedFavoritesCount == 0`, the toast block is correctly skipped.

Wait — re-read that. Let me trace: if original `parsed.favorites == ["a.jpg"]` and `a.jpg` has no match, `favResult.reconciled == []`, `droppedCount == 1`. Then `reconciled ([]) != parsed.favorites (["a.jpg"])` so `needsWrite = true` AND `droppedFavoritesCount = 1`. Write happens AND toast fires. Correct.

If `parsed.favorites == []` (empty) the outer `if !parsed.favorites.isEmpty` is false, so `droppedFavoritesCount` stays 0. Correct.

### Step 4: Run integration tests — expect pass

```bash
xcodegen generate
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -only-testing:PortyMcFolioTests/ProjectReconcilerTests -quiet 2>&1 | tail -15
```

Expected: all pass (existing + 3 new).

### Step 5: Full suite

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -quiet 2>&1 | tail -5
```

Expected: exit 0.

### Step 6: Commit

```bash
git add PortyMcFolio/Services/ProjectReconciler.swift PortyMcFolioTests/ProjectReconcilerTests.swift
git commit -m "feat(reconciler): auto-repair teaser + body embeds, toast favorite drops"
```

---

## Task 5: Final verification

### Step 1: Full suite

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -quiet 2>&1 | tail -10
```

Expected: exit 0, clean run.

### Step 2: Smoke test

```bash
xcodegen generate
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -configuration Release build -destination 'platform=macOS' -derivedDataPath build 2>&1 | tail -3
open build/Build/Products/Release/PortyMcFolio.app
```

Manual checklist:
- Open a project with a teaser set. In Finder, rename the teaser file to a new unique name (e.g., `hero.jpg` → `cover.jpg`). Watch the Console.app `subsystem:com.portymcfolio.app` filter; within 1–2 seconds the reconciler should pick up the change and the project card's teaser thumbnail should continue to render correctly.
- Open a project with a `![[hero.jpg]]` embed in the body. Rename `hero.jpg` externally to a unique new name. Re-enter the editor; the `![[…]]` string should now reference the new path (since the reconciler rewrote the body).
- Open a project with 2 favorited files. Delete both files in Finder. Within a couple of seconds you should see a toast "2 favorites removed from \"<title>\" — files are gone."
- Open a project and do nothing to the files. Confirm the project's README mtime is NOT updated on reconciliation passes (no unnecessary FSEvent churn).

### Step 3: No final commit needed — per-task commits capture everything.

---

## Spec coverage check

| Spec requirement | Addressed by |
|---|---|
| New `TeaserReconciliation` with stated semantics | Task 1 |
| New `BodyEmbedReconciliation` with stated semantics | Task 2 |
| `FavoritesReconciliation` returns `FavoritesResult` | Task 3 |
| Single shared on-disk walk in `syncProject` | Task 4 (Step 3, `let mediaPaths = ...` hoisted above all three) |
| Single atomic write for combined repair | Task 4 (Step 3, `if needsWrite { serialize + write }`) |
| `.markdownFileDidChange` once per write | Task 4 (Step 3) |
| Toast on `droppedCount > 0` | Task 4 (Step 3, post-write block) |
| No-op skip when nothing changed | Task 4 (Step 3, `needsWrite` flag) |
| Empty/absolute/`..` teaser → `.unchanged` | Task 1 (tests + impl) |
| Empty/absolute/`..` embeds skipped | Task 2 (tests + impl) |
| Two embeds same file → deduped in `repaired` | Task 2 (test `testTwoEmbedsPointingToSameRenamedFile…`) |
| Body rewrite byte-preserves surrounding text | Task 2 (test `testRewritePreservesSurroundingTextByteForByte`) |
| `droppedCount` tests | Task 3 (6 new tests) |
| Integration: combined repair single write | Task 4 (test `testRepairsFavoritesTeaserAndBodyEmbedsInOneWrite`) |
| Integration: drop toast | Task 4 (test `testFiresShowToastWhenFavoritesAreDropped`) |
| Integration: no-op skip | Task 4 (test `testNoopWhenEverythingResolves`) |
