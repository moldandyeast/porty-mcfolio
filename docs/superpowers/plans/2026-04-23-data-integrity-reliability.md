# Data Integrity & Reliability Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the load-bearing data-integrity and reliability gaps surfaced in the 2026-04-23 review: make `updateProjectMetadata` atomic, close the editor↔reconciler favorites race, surface search-index failures and parse failures to the user, add a launch-time bookmark timeout, auto-recover on app-resume, and give the editor paste/load errors a user-visible warning.

**Architecture:** Five small surgical changes plus two new tests. No new services. All changes target existing files. The editor/reconciler race uses the user-approved "option (a)" — reconciler posts `.markdownFileDidChange` after its write — plus a minimal mtime-based retry in the editor's save path, because option (a) alone doesn't close the window (`handleExternalFileChange` already short-circuits when a save is pending).

**Tech Stack:** Swift 5.9, AppKit, GRDB, `os.Logger` via `AppLogger`, XCTest. Xcode project generated from `project.yml` via xcodegen.

**Out of scope:**
- GalleryView refactor (Plan 4).
- Performance memoizations (Plan 3).
- The editor ↔ reconciler race beyond the mtime-retry mitigation (if the retry approach proves insufficient later, we escalate to option (c): editor-only writer).
- Broader FileWatcher stream health monitoring. This plan does NOT add FSEvent-stream heartbeats or error-callback handling; it mitigates the "missed events" problem via a `didBecomeActive` full reconcile.

---

## Preliminaries

- [ ] **Confirm clean working tree and record baseline**

```bash
git status
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -quiet 2>&1 | tail -5
```

Expected: `nothing to commit`; test run exits 0. Baseline warnings in `AppState.swift` (Swift 6 mode) are pre-existing.

---

## Task 1: Atomic `updateProjectMetadata` with rollback

**Files:**
- Modify: `PortyMcFolio/App/AppState.swift` (method `updateProjectMetadata` starts at :640)
- Modify: `PortyMcFolioTests/FrontmatterFolderRenameTests.swift` (add new tests)

**Problem:** [AppState.swift:640](PortyMcFolio/App/AppState.swift:640) does three non-atomic steps: write README, rename internal `.md`, rename folder. If any later step fails (destination collision, permission, volume flaky), the project is left with divergent state (new title in frontmatter but old folder name, or new internal file inside un-renamed folder).

**Fix:** Pre-flight collision check + rollback on partial failure. Preserves the original on-disk layout if any step fails.

### Step 1: Write failing tests

Add these inside `PortyMcFolioTests/FrontmatterFolderRenameTests.swift` (inside the existing test class; match its house style):

```swift
    // MARK: - Atomic rename safety

    @MainActor
    func testRenameFailsIfDestinationFolderExists() throws {
        let appState = try makeAppState()
        let project = try createProject(
            title: "Original",
            year: 2025,
            uid: "aaaaaaaa",
            in: appState
        )
        // Create a sibling folder with the exact name we'll try to rename into.
        let collisionURL = tempRoot.appendingPathComponent("2025_colliding_aaaaaaaa")
        try FileManager.default.createDirectory(at: collisionURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try appState.updateProjectMetadata(
                project: project,
                title: "Colliding",
                year: 2025,
                client: project.client,
                status: project.status,
                tags: project.tags,
                teaser: project.teaser,
                hidden: project.hidden
            )
        )

        // Original folder still exists with its original contents.
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.folderURL.path))
        let preservedContent = try String(contentsOf: project.readmeURL, encoding: .utf8)
        let preserved = try FrontmatterParser.parse(preservedContent)
        XCTAssertEqual(preserved.title, "Original")
    }

    @MainActor
    func testRenameRollsBackInternalFileMoveIfFolderRenameFails() throws {
        let appState = try makeAppState()
        let project = try createProject(
            title: "Original",
            year: 2025,
            uid: "bbbbbbbb",
            in: appState
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
                year: 2025,
                client: project.client,
                status: project.status,
                tags: project.tags,
                teaser: project.teaser,
                hidden: project.hidden
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
```

If `FrontmatterFolderRenameTests` does not already have `makeAppState` / `createProject` helpers, inspect the existing test file and either:
(a) add minimal helpers mirroring the file's setup style, or
(b) adapt the test to build a `Project` + call `appState.updateProjectMetadata` using whatever fixture shape the existing tests use.

Read the file first (`cat PortyMcFolioTests/FrontmatterFolderRenameTests.swift`) and match its patterns before writing.

### Step 2: Regenerate project + run new tests — expect compile/runtime failure

```bash
xcodegen generate
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -only-testing:PortyMcFolioTests/FrontmatterFolderRenameTests -quiet 2>&1 | tail -30
```

Expected: the two new tests either fail to compile (if helpers aren't in scope) or fail at runtime because the current `updateProjectMetadata` doesn't pre-flight-check and doesn't rollback.

### Step 3: Rewrite `updateProjectMetadata` with pre-flight + rollback

Locate the method starting at `AppState.swift:640`. Replace its body with:

```swift
    func updateProjectMetadata(
        project: Project,
        title: String,
        year: Int,
        client: String,
        status: ProjectStatus,
        tags: [String],
        teaser: String,
        hidden: Bool
    ) throws {
        let newFolderName = Project.folderName(title: title, year: year, uid: project.uid)
        let willRenameFolder = newFolderName != project.folderName

        // Pre-flight: if the folder rename would collide, refuse the whole operation
        // before we mutate anything on disk.
        if willRenameFolder, let rootURL = portfolioRootURL {
            let newFolderURL = rootURL.appendingPathComponent(newFolderName)
            guard !FileManager.default.fileExists(atPath: newFolderURL.path) else {
                throw NSError(
                    domain: "com.portymcfolio.app",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "A project folder named \"\(newFolderName)\" already exists."]
                )
            }
        }

        // 1. Read and rewrite the README.
        let originalContent = try String(contentsOf: project.readmeURL, encoding: .utf8)
        var parsed = try FrontmatterParser.parse(originalContent)
        parsed.title = title
        parsed.client = client
        parsed.status = status
        parsed.tags = tags
        parsed.teaser = teaser
        parsed.hidden = hidden

        // Update year in date (keep month/day from existing date)
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var dateComponents = calendar.dateComponents([.month, .day], from: parsed.date)
        dateComponents.year = year
        if let newDate = calendar.date(from: dateComponents) {
            parsed.date = newDate
        }

        let updated = FrontmatterParser.serialize(frontmatter: parsed)
        try updated.write(to: project.readmeURL, atomically: true, encoding: .utf8)

        // Track what we've done so we can roll back on failure.
        var internalFileRenamed = false
        let oldInternalFile = project.folderURL.appendingPathComponent("\(project.folderName).md")
        let newInternalFile = project.folderURL.appendingPathComponent("\(newFolderName).md")

        do {
            // 2. Rename the internal project file (if any).
            if willRenameFolder, let rootURL = portfolioRootURL {
                if FileManager.default.fileExists(atPath: oldInternalFile.path) {
                    try FileManager.default.moveItem(at: oldInternalFile, to: newInternalFile)
                    internalFileRenamed = true
                }

                // 3. Rename the folder.
                let newFolderURL = rootURL.appendingPathComponent(newFolderName)
                try FileManager.default.moveItem(at: project.folderURL, to: newFolderURL)

                projectFolderRenamed(uid: project.uid, newFolderName: newFolderName)
            }
        } catch {
            // Rollback.
            if internalFileRenamed {
                try? FileManager.default.moveItem(at: newInternalFile, to: oldInternalFile)
            }
            try? originalContent.write(to: project.readmeURL, atomically: true, encoding: .utf8)
            throw error
        }

        // 4. Direct-poke the reconciler to sync this project immediately.
        notifyProjectFileChanged(uid: project.uid)
    }
```

Key differences from the current implementation:
- Pre-flight collision check BEFORE any disk mutation.
- Original README content captured before the write, so rollback can restore it.
- `internalFileRenamed` flag tracks completion; catch block rolls back in reverse order.
- Folder rename is the last destructive step; failure there triggers internal-file rename rollback.

### Step 4: Run the new tests — expect pass

```bash
xcodegen generate
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -only-testing:PortyMcFolioTests/FrontmatterFolderRenameTests -quiet 2>&1 | tail -20
```

Expected: all tests pass.

### Step 5: Run the full suite

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -quiet 2>&1 | tail -10
```

Expected: exit 0, no regressions.

### Step 6: Commit

```bash
git add PortyMcFolio/App/AppState.swift PortyMcFolioTests/FrontmatterFolderRenameTests.swift
git commit -m "fix(appstate): pre-flight + rollback updateProjectMetadata rename"
```

---

## Task 2: Close the editor ↔ reconciler favorites race

**Files:**
- Modify: `PortyMcFolio/Services/ProjectReconciler.swift`
- Modify: `PortyMcFolio/Views/MarkdownEditorView.swift`

**Problem (two parts):**

1. When `ProjectReconciler` rewrites favorites at [:386](PortyMcFolio/Services/ProjectReconciler.swift:386), nothing tells the editor to refresh. If the editor has the project open with no pending edit, it displays stale in-memory state until the user navigates away and back.
2. If the editor has a pending debounced save when the reconciler writes, the editor's `saveContent` at [MarkdownEditorView.swift:530](PortyMcFolio/Views/MarkdownEditorView.swift:530) does read-modify-write on disk. The read (line 535) may happen BEFORE the reconciler's write, then the editor serializes from its stale in-memory parsed frontmatter and writes, clobbering the reconciler's favorites change.

Option (a) as originally described — "reconciler posts `.markdownFileDidChange`, editor reloads before next save" — only solves part 1. `Coordinator.handleExternalFileChange` at [:471](PortyMcFolio/Views/MarkdownEditorView.swift:471) guards `debounceTimer == nil`, so it skips the reload precisely when the race matters. To fully close part 2 we also need `saveContent` to detect disk mutation between its read and write and retry.

**Fix:** Reconciler posts the notification (part 1) + editor's save uses an mtime check to retry on race (part 2).

### Step 1: Reconciler posts `.markdownFileDidChange` after the favorites write

In `PortyMcFolio/Services/ProjectReconciler.swift`, find the favorites-write block (around line 386):

```swift
                let updated = FrontmatterParser.serialize(frontmatter: parsed)
                do {
                    try updated.write(to: readmeURL, atomically: true, encoding: .utf8)
                } catch {
                    AppLogger.reconciler.error("favorites rewrite failed for uid=\(uid, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
```

Replace with:

```swift
                let updated = FrontmatterParser.serialize(frontmatter: parsed)
                do {
                    try updated.write(to: readmeURL, atomically: true, encoding: .utf8)
                    NotificationCenter.default.post(name: .markdownFileDidChange, object: readmeURL)
                } catch {
                    AppLogger.reconciler.error("favorites rewrite failed for uid=\(uid, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
```

Rationale: this is safe from the reconciler queue — `NotificationCenter.default.post` is thread-safe; observers will run on whatever thread the observer was registered on (AppKit/MainActor here).

### Step 2: Editor `saveContent` detects disk mutation via mtime and retries

In `PortyMcFolio/Views/MarkdownEditorView.swift`, the `Coordinator` class currently tracks no mtime. Add a stored property and update `loadContent` + `saveContent`.

Find the `Coordinator` class declaration block (starts around line 429). Add this stored property near the other stored `var`s (near `debounceTimer`, `autoSaveDelay`):

```swift
        /// mtime of `readmeURL` at last successful load or save. Used by
        /// `saveContent` to detect external writes between our read and write
        /// and retry — prevents clobbering reconciler-side favorites rewrites.
        private var lastKnownMTime: Date?
```

Then update `loadContent` (around line 479). Find the end of the successful-load path (after `highlighter.highlight(...)`). Add an mtime capture:

```swift
        func loadContent() {
            // ... existing body unchanged up through `highlighter.highlight(...)` ...
            lastKnownMTime = (try? FileManager.default.attributesOfItem(atPath: readmeURL.path)[.modificationDate]) as? Date
        }
```

(Preserve every line that's currently in `loadContent`; only APPEND the `lastKnownMTime` capture at the very end.)

Then rewrite `saveContent` (starts around line 530) to:

```swift
        private func saveContent() {
            guard let textView else { return }
            let body = textView.string

            // Retry on race: if the file's mtime changed between our read and the
            // moment we're about to write, another writer (e.g. ProjectReconciler's
            // favorites rewrite) modified it. Re-read and re-serialize, preserving
            // the user's typed body.
            for attempt in 0..<3 {
                do {
                    let preMTime = (try? FileManager.default.attributesOfItem(atPath: readmeURL.path)[.modificationDate]) as? Date
                    let currentContent = try String(contentsOf: readmeURL, encoding: .utf8)
                    var parsed = try FrontmatterParser.parse(currentContent)
                    parsed.body = body
                    let fullContent = FrontmatterParser.serialize(frontmatter: parsed)

                    // If the file changed since we read it, retry with fresh state.
                    let postMTime = (try? FileManager.default.attributesOfItem(atPath: readmeURL.path)[.modificationDate]) as? Date
                    if let preMTime, let postMTime, postMTime > preMTime {
                        continue
                    }

                    try fullContent.write(to: readmeURL, atomically: true, encoding: .utf8)
                    lastKnownMTime = (try? FileManager.default.attributesOfItem(atPath: readmeURL.path)[.modificationDate]) as? Date
                    onSave?(fullContent)
                    return
                } catch {
                    AppLogger.ui.error("MarkdownEditor save failed (attempt \(attempt + 1)): \(error.localizedDescription, privacy: .public)")
                    return
                }
            }
            AppLogger.ui.warning("MarkdownEditor save gave up after retries — file is being modified concurrently")
        }
```

### Step 3: Build and run editor-related tests

```bash
xcodegen generate
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio build -destination 'platform=macOS' -quiet 2>&1 | tail -5
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -quiet 2>&1 | tail -10
```

Expected: build + test exit 0. No regressions.

(No new unit test for this task: the race window is sub-millisecond and not reproducible in a unit test without heavy fixture plumbing. We verify the logic by code review and the full suite's absence of regressions.)

### Step 4: Commit

```bash
git add PortyMcFolio/Services/ProjectReconciler.swift PortyMcFolio/Views/MarkdownEditorView.swift
git commit -m "fix(editor): close reconciler-favorites race via mtime-retry + notification"
```

---

## Task 3: SearchIndex init failure → user-visible toast

**Files:**
- Modify: `PortyMcFolio/App/AppState.swift`

**Problem:** [AppState.swift:519](PortyMcFolio/App/AppState.swift:519) logs when `SearchIndex` init fails, sets `searchIndex = nil`, and continues. Search silently returns `[]`. The user has no idea.

**Fix:** When the init fails, fire `showToast` with a plain-language explanation. It's already the right mechanism — `showToast` exists and displays a floating pill.

### Step 1: Add toast on init failure

Find the catch block in `setRoot` around line 519:

```swift
        } catch {
            AppLogger.app.error("SearchIndex/cache init failed: \(error.localizedDescription, privacy: .public). Will retry on refresh.")
            self.searchIndex = nil
            self.cache = nil
        }
```

Replace with:

```swift
        } catch {
            AppLogger.app.error("SearchIndex/cache init failed: \(error.localizedDescription, privacy: .public). Will retry on refresh.")
            self.searchIndex = nil
            self.cache = nil
            showToast("Search unavailable — index failed to load. Try re-opening the portfolio.", duration: .seconds(4))
        }
```

### Step 2: Build

```bash
xcodegen generate
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio build -destination 'platform=macOS' -quiet 2>&1 | tail -5
```

Expected: build exits 0.

(No unit test: `showToast` side-effect is observable only in-app; covered by smoke test in Task 9.)

### Step 3: Commit

```bash
git add PortyMcFolio/App/AppState.swift
git commit -m "fix(appstate): toast when SearchIndex init fails"
```

---

## Task 4: Bookmark resolution timeout on launch

**Files:**
- Modify: `PortyMcFolio/App/AppState.swift`

**Problem:** [AppState.swift:323](PortyMcFolio/App/AppState.swift:323) in `loadSavedRoot` calls `URL(resolvingBookmarkData:…)` and then `setRoot`, which calls `startAccessingSecurityScopedResource`. If the backing volume is unmounted or slow (network), the launch splash freezes for 10+ seconds with no fallback.

**Fix:** Resolve the bookmark on a background task with a 2-second deadline. If it fails or times out, fall back to the folder picker (set `isReady = true` without a root).

### Step 1: Rewrite `loadSavedRoot`

Find `loadSavedRoot` at `AppState.swift:317`. Replace the entire method with this version, which uses a task-group race so a hanging `URL(resolvingBookmarkData:)` can't pin the splash past the deadline:

```swift
    func loadSavedRoot() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else {
            isReady = true
            return
        }

        Task { [weak self] in
            // Race bookmark resolution against a 2s deadline. Using a small
            // enum instead of a double-optional keeps the intent readable.
            enum ResolveOutcome {
                case success(URL, Bool)
                case failed
            }

            let outcome: ResolveOutcome = await withTaskGroup(of: ResolveOutcome.self) { group in
                group.addTask {
                    var isStale = false
                    guard let url = try? URL(
                        resolvingBookmarkData: bookmarkData,
                        options: .withSecurityScope,
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    ) else {
                        return .failed
                    }
                    return .success(url, isStale)
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(2))
                    return .failed
                }
                let first = await group.next() ?? .failed
                group.cancelAll()
                return first
            }

            guard let self else { return }
            await MainActor.run {
                switch outcome {
                case .failed:
                    AppLogger.app.warning("Bookmark resolution timed out or failed; falling back to folder picker")
                    UserDefaults.standard.removeObject(forKey: self.bookmarkKey)
                    self.isReady = true
                case .success(let url, let isStale):
                    if isStale {
                        self.saveBookmark(for: url)
                    }
                    self.setRoot(url)
                }
            }
        }
    }
```

### Step 2: Build and test

```bash
xcodegen generate
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -quiet 2>&1 | tail -10
```

Expected: exit 0.

### Step 3: Commit

```bash
git add PortyMcFolio/App/AppState.swift
git commit -m "fix(appstate): 2s timeout on bookmark resolution, fall back to picker"
```

---

## Task 5: Re-reconcile on `NSApplication.didBecomeActiveNotification`

**Files:**
- Modify: `PortyMcFolio/App/AppState.swift`

**Problem:** If the FSEvent stream silently dies (sleep/wake, volume eject, permission change), file changes stop arriving and the UI shows stale data. [FileWatcher.swift](PortyMcFolio/Services/FileWatcher.swift) has no health check or reconnection logic.

**Fix (pragmatic, not full):** When the app becomes active, trigger `reconciler.reconcileTopLevel()`. This full scan catches anything the watcher missed. Full FSEvent stream-health monitoring is deferred — this covers the common case (wake from sleep, app brought forward after being backgrounded).

### Step 1: Add the observer

Find `AppState.startAppearanceObservers` at line 389. After its existing observers, add:

```swift
        // Trigger a full reconcile when the app becomes active. FSEvents can
        // miss changes during sleep/wake or when the volume was unmounted —
        // this is a cheap reliability backstop.
        let activeObs = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshProjects()
        }
        appearanceObservers.append(activeObs)
```

Note: `refreshProjects()` (already public on `AppState`, defined at line 590) is a no-op if `reconciler` is nil, so it's safe on initial launch before the portfolio is set.

### Step 2: Fix the orphaned toast observer while you're here

`AppState.deinit` at line 746-749 removes observers from `DistributedNotificationCenter.default()`, but `startAppearanceObservers` registers the `.showToast` and now `.didBecomeActive` observers on `NotificationCenter.default`. Those never get removed.

Replace `deinit` with:

```swift
    deinit {
        let dnc = DistributedNotificationCenter.default()
        let nc = NotificationCenter.default
        for obs in appearanceObservers {
            dnc.removeObserver(obs)
            nc.removeObserver(obs)
        }
    }
```

Calling `removeObserver` on a center that doesn't have the observer is a no-op, so it's safe to try both.

### Step 3: Build and test

```bash
xcodegen generate
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -quiet 2>&1 | tail -10
```

Expected: exit 0.

### Step 4: Commit

```bash
git add PortyMcFolio/App/AppState.swift
git commit -m "fix(appstate): reconcile on didBecomeActive + remove observers from correct center"
```

---

## Task 6: Parse-failure toast

**Files:**
- Modify: `PortyMcFolio/Services/ProjectReconciler.swift`

**Problem:** When `FrontmatterParser.parse` fails inside `syncProject` at [:366](PortyMcFolio/Services/ProjectReconciler.swift:366), the reconciler logs a warning and returns early, leaving stale cached metadata. The user has no indication their file is broken; the UI shows old data forever.

**Fix:** In addition to the existing log, post `.showToast` (the existing Notification-based toast bridge) with the folder name. The AppState observer at [:414](PortyMcFolio/App/AppState.swift:414) will display it. User learns something's wrong and can investigate.

### Step 1: Add toast post

Find the parse-failure block in `ProjectReconciler.syncProject` (around :361-:365):

```swift
        guard let content = try? String(contentsOf: readmeURL, encoding: .utf8),
              let parsed0 = try? FrontmatterParser.parse(content) else {
            AppLogger.reconciler.warning("parse failed for uid=\(uid, privacy: .public) — leaving cache as-is")
            return
        }
```

Replace with:

```swift
        guard let content = try? String(contentsOf: readmeURL, encoding: .utf8),
              let parsed0 = try? FrontmatterParser.parse(content) else {
            AppLogger.reconciler.warning("parse failed for uid=\(uid, privacy: .public) — leaving cache as-is")
            let folderName = folderInfo.folderName
            NotificationCenter.default.post(
                name: .showToast,
                object: "Couldn't read \"\(folderName)\". Check the frontmatter for syntax errors."
            )
            return
        }
```

Rationale: reconciler queue is safe to post from (`NotificationCenter.default.post` is thread-safe). `.showToast` observer in `AppState` already marshals onto main via its `queue: .main` handler.

### Step 2: Build

```bash
xcodegen generate
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio build -destination 'platform=macOS' -quiet 2>&1 | tail -5
```

Expected: build exits 0.

### Step 3: Commit

```bash
git add PortyMcFolio/Services/ProjectReconciler.swift
git commit -m "fix(reconciler): toast user when frontmatter parse fails"
```

---

## Task 7: Silent copy on paste/drop → toast

**Files:**
- Modify: `PortyMcFolio/Views/MarkdownEditorView.swift`

**Problem:** [MarkdownEditorView.swift:132](PortyMcFolio/Views/MarkdownEditorView.swift:132) uses `try? FileManager.default.copyItem(at:to:)` when a user pastes or drops a file from outside the project folder. If the copy fails (disk full, permissions), the embed `![[\(filename)]]` is still inserted, producing a broken reference with no user feedback.

**Fix:** Do/catch + post `.showToast` on failure. Skip the embed insertion for that URL so a broken link isn't inserted.

### Step 1: Locate and rewrite

Find the block around `MarkdownEditorView.swift:122-138` (the current shape):

```swift
        for url in urls {
            let fileURL = url.standardizedFileURL
            let filename: String
            if let projectFolder = projectFolderURL?.standardizedFileURL,
               fileURL.path.hasPrefix(projectFolder.path + "/") {
                filename = String(fileURL.path.dropFirst(projectFolder.path.count + 1))
            } else if let projectFolder = projectFolderURL {
                let dest = projectFolder.appendingPathComponent(fileURL.lastPathComponent)
                if !FileManager.default.fileExists(atPath: dest.path) {
                    try? FileManager.default.copyItem(at: fileURL, to: dest)
                }
                filename = fileURL.lastPathComponent
            } else {
                filename = fileURL.lastPathComponent
            }
            embedParts.append("![[\(filename)]]")
        }
```

Replace with:

```swift
        for url in urls {
            let fileURL = url.standardizedFileURL
            let filename: String
            if let projectFolder = projectFolderURL?.standardizedFileURL,
               fileURL.path.hasPrefix(projectFolder.path + "/") {
                filename = String(fileURL.path.dropFirst(projectFolder.path.count + 1))
            } else if let projectFolder = projectFolderURL {
                let dest = projectFolder.appendingPathComponent(fileURL.lastPathComponent)
                if !FileManager.default.fileExists(atPath: dest.path) {
                    do {
                        try FileManager.default.copyItem(at: fileURL, to: dest)
                    } catch {
                        AppLogger.ui.error("MarkdownEditor paste/drop copy failed for \(fileURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        NotificationCenter.default.post(
                            name: .showToast,
                            object: "Couldn't copy \(fileURL.lastPathComponent) into project."
                        )
                        continue
                    }
                }
                filename = fileURL.lastPathComponent
            } else {
                filename = fileURL.lastPathComponent
            }
            embedParts.append("![[\(filename)]]")
        }
```

Key changes:
- `try?` → `do/catch` with log + toast.
- On failure, `continue` — don't append a broken `![[...]]` embed for a file that wasn't copied.

### Step 2: Build

```bash
xcodegen generate
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio build -destination 'platform=macOS' -quiet 2>&1 | tail -5
```

Expected: build exits 0.

### Step 3: Commit

```bash
git add PortyMcFolio/Views/MarkdownEditorView.swift
git commit -m "fix(editor): surface paste/drop copy errors via toast, skip broken embeds"
```

---

## Task 8: Editor load failure → toast

**Files:**
- Modify: `PortyMcFolio/Views/MarkdownEditorView.swift`

**Problem:** [MarkdownEditorView.swift:484-491](PortyMcFolio/Views/MarkdownEditorView.swift:484) catches read/parse errors in `loadContent` and silently sets the body to `""`. If the user starts typing, they overwrite whatever was on disk with an empty-body-plus-typed-text save on next debounce. User has no idea something went wrong.

**Fix:** On catch, log + post `.showToast` with a message mentioning the project name.

### Step 1: Locate `loadContent`'s catch path

Find the catch path in `loadContent` (around line 489-491):

```swift
            } catch {
                body = ""
            }
```

Replace with:

```swift
            } catch {
                body = ""
                AppLogger.ui.error("MarkdownEditor load failed for \(readmeURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                let name = readmeURL.deletingPathExtension().lastPathComponent
                NotificationCenter.default.post(
                    name: .showToast,
                    object: "Couldn't load \(name). Editor opened blank — don't type here until you reload the project."
                )
            }
```

### Step 2: Build

```bash
xcodegen generate
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio build -destination 'platform=macOS' -quiet 2>&1 | tail -5
```

Expected: build exits 0.

### Step 3: Commit

```bash
git add PortyMcFolio/Views/MarkdownEditorView.swift
git commit -m "fix(editor): toast user when README load fails, warn against typing"
```

---

## Task 9: Final verification

### Step 1: Full test suite

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio test -destination 'platform=macOS' -quiet 2>&1 | tail -15
```

Expected: exit 0, no regressions.

### Step 2: Build Release and smoke-test manually

```bash
xcodegen generate
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -configuration Release build -destination 'platform=macOS' -derivedDataPath build 2>&1 | tail -3
open build/Build/Products/Release/PortyMcFolio.app
```

Manual smoke-test checklist:
- Launch the app. Splash clears within ~2s even if you simulate a stale bookmark by renaming the portfolio root externally before launch.
- Open a project, type a few characters, wait for the debounce, verify the file saved correctly.
- Rename a project via the settings popover (title change that triggers folder rename). Verify folder + internal file both renamed. Try it again with the target folder already existing — verify you get an error and the original state is preserved.
- Externally edit the project's frontmatter YAML to be syntactically broken (delete a `:`). Save. Verify you see a "Couldn't read …" toast.
- Corrupt `search.sqlite` in `~/Library/Group Containers/...`/`~/Library/Containers/com.portymcfolio.app/...` (optional — skip if you can't find it safely). Re-open the portfolio. Verify you see a "Search unavailable" toast.
- Put the Mac to sleep for 30s, wake it. Verify the project list reconciles cleanly.

### Step 3: No final commit needed — the per-task commits already capture everything.

---

## Spec coverage check

| Review finding | Addressed by |
|----------------|--------------|
| Critical: `updateProjectMetadata` non-atomic rename | Task 1 |
| Critical: editor ↔ reconciler favorites race | Task 2 |
| High: SearchIndex init failure is invisible | Task 3 |
| High: stale bookmark hangs launch | Task 4 |
| High: FSEvent stream death undetected | Task 5 (mitigated via didBecomeActive full reconcile) |
| High: parse failure silently wedges project | Task 6 |
| Medium: silent copy on paste/drop | Task 7 |
| Low: editor load failure shows empty body | Task 8 |
| Medium: NotificationCenter observer leak on toast | Task 5 (Step 2 — bundled) |

Not addressed in this plan (intentionally deferred):
- Full FSEvent stream-health monitoring — ship Task 5's pragmatic mitigation, revisit if reports of stale-state bugs persist.
- Reconciler debouncer backpressure — belongs in a future reliability/perf plan.
- Selected-project briefly dangling after deletion — present but rare in practice; defer.
- Link date silently becoming today — cosmetic, low-priority.
