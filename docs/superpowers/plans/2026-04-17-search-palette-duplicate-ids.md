# Fix duplicate `SearchResult.id` for FTS file/link results

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop ⌘K Search Palette from landing on the wrong item when two projects share a filename (or link uid). Fix the root cause — non-unique `SearchResult.id` — in `SearchIndex.search`.

**Architecture:** `SearchResult.id` is currently built as `"\(type)-\(entityID)"`. For type `file`, `entity_id = relativePath`, which is unique per project but NOT globally unique — a `notes.md` in project A and project B produce identical `SearchResult.id`. The SwiftUI `ForEach(... id: \.element.id)` in `SearchPalette` then misbehaves (rows reused, gestures fire on wrong item). Fix: for types that have a parent (`file`, `link`), include `parent_uid` in the id. Types without a parent (`project`, `tag`, `command`) already have globally-unique entity ids, unchanged.

**Tech Stack:** Swift 5.9, SwiftUI, GRDB (FTS5), XCTest.

**Root cause evidence:** `PortyMcFolio/Services/SearchIndex.swift:442` (id construction); `PortyMcFolio/Services/SearchIndex.swift:158-161, 380-383` (file FTS insert, where `entity_id = relativePath`).

---

## Task 1: Regression test — duplicate filenames across projects produce distinct `SearchResult.id`s

**Files:**
- Modify: `PortyMcFolioTests/SearchIndexTests.swift`

**Step 1: Inspect existing tests**

- [ ] Read `PortyMcFolioTests/SearchIndexTests.swift` to understand the existing test harness (how it constructs a `SearchIndex`, how it inserts projects/files, how it calls `search`). Follow the style of the nearest existing test.

**Step 2: Write the failing test**

- [ ] Add a test named `testFileResultIDsAreUniqueAcrossProjectsWithSameFilename` that:
    1. Creates two projects (any two unique uids, e.g. `"aaaaaaaa"` and `"bbbbbbbb"`).
    2. For each, inserts a file named exactly `"notes.md"` (same `relativePath`).
    3. Calls `index.search(query: "notes")`.
    4. Filters results to `.file` type.
    5. Asserts `results.count == 2`.
    6. Asserts `Set(results.map(\.id)).count == 2` — the ids are distinct.

    Follow existing test-setup conventions in the file. If the file already has helpers (e.g. `makeIndex()`, `insertProject()`, `insertFile()`), reuse them. If not, write the minimum setup inline.

- [ ] Regenerate Xcode project in case the test file was already modified in a way xcodegen needs to pick up (only necessary if you added a new test file, not if you appended to an existing one). If you're only appending to an existing file, skip this step.

    ```bash
    xcodegen
    ```

**Step 3: Run test to verify it fails**

- [ ] Run:
    ```bash
    xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/SearchIndexTests/testFileResultIDsAreUniqueAcrossProjectsWithSameFilename 2>&1 | tail -40
    ```
    Expected: test FAILS because `Set(results.map(\.id)).count == 1` (both rows produce `"file-notes.md"`).

**Step 4: Commit failing test**

- [ ] (Optional) If you prefer, commit the failing test now, or bundle it with the fix in Task 2. Either is fine — it's a single logical change. If bundling, skip this step.

---

## Task 2: Fix id construction in `SearchIndex.search`

**Files:**
- Modify: `PortyMcFolio/Services/SearchIndex.swift` (around line 442)

**Step 1: Change the id construction**

- [ ] Find this block in `PortyMcFolio/Services/SearchIndex.swift` (around line 441-448):

    ```swift
    return SearchResult(
        id: "\(typeString)-\(entityID)",
        type: type,
        entityID: entityID,
        parentUID: parentUID,
        primaryText: primaryText,
        secondaryText: secondaryText
    )
    ```

- [ ] Replace the `id:` argument so file/link rows include `parentUID`, while project/tag rows keep their current format (their `entityID` is already globally unique):

    ```swift
    let resultID: String = {
        switch type {
        case .file, .link:
            return "\(typeString)-\(parentUID)-\(entityID)"
        case .project, .tag, .command:
            return "\(typeString)-\(entityID)"
        }
    }()
    return SearchResult(
        id: resultID,
        type: type,
        entityID: entityID,
        parentUID: parentUID,
        primaryText: primaryText,
        secondaryText: secondaryText
    )
    ```

**Step 2: Run the failing test — should now pass**

- [ ] Run:
    ```bash
    xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/SearchIndexTests/testFileResultIDsAreUniqueAcrossProjectsWithSameFilename 2>&1 | tail -40
    ```
    Expected: PASS.

**Step 3: Full test suite to confirm no regressions**

- [ ] Run:
    ```bash
    xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -20
    ```
    Expected: all tests pass.

**Step 4: Commit**

- [ ] Commit:
    ```bash
    git add PortyMcFolio/Services/SearchIndex.swift PortyMcFolioTests/SearchIndexTests.swift
    git commit -m "fix: globally-unique SearchResult.id for file/link results"
    ```

---

## Task 3: Manual verification (controller-driven)

**Files:** none

The controller launches the app and verifies the UX fix. Subagents do NOT run this task.

Acceptance: search for a term that matches files across multiple projects (e.g. a word that appears in `README.md`, `teaser.jpg`, or similar file present in more than one project). Click the second result in the FILES section. Land on the second result's project, not the first.

---

## Spec coverage check

| Requirement | Task |
|---|---|
| Duplicate filenames across projects produce distinct `SearchResult.id`s | Task 1 (test), Task 2 (fix) |
| Project/tag result ids stay unchanged (backward compat) | Task 2 (switch preserves old format) |
| Links also disambiguated | Task 2 (`.file, .link` share the same case) |
| No regressions | Task 2 Step 3 |
| User-visible fix confirmed | Task 3 (manual) |
