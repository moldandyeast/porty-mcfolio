# Security & correctness batch C — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the small-to-medium correctness/security/test-quality items from the 2026-04-17 code review: three preview XSS tightenings, MarkdownEditorView's unsafe deinit save, silent project drops in PortfolioStore, recomputed projectsByYear dictionary, flaky reconciler debounce tests, and a dev-only preview HTML that's shipping in the app bundle.

**Architecture:** Seven independent local fixes. None change public APIs.

**Deferred to Batch D (bigger refactors):** GalleryView 938-line decomposition; ProjectListView 640-line decomposition; main-thread `scanProjectFolder` + `allProjectFolders`.

**Deferred to Batch E (tests):** Coverage gaps for PathValidation, FileWatcher, AppState paths, `try!` in test setUps.

**Still unresolved (needs user decision):** Editor/src CodeMirror JS bundle — unknown whether dead code or WIP. Left alone this batch.

---

## Task 1: MarkdownPreviewView — narrow `allowingReadAccessTo` and safely escape filenames in `src=`

**Files:**
- Modify: `PortyMcFolio/Views/MarkdownPreviewView.swift`

### Bug 1a: bundle-wide read access

`webView.loadFileURL(htmlURL, allowingReadAccessTo: Bundle.main.bundleURL)` (line 34) grants the preview WebView read access to the entire app bundle. Any DOMPurify bypass could `fetch('file://...')` arbitrary bundle files.

### Bug 1b: filename-to-src injection risk

`preprocessEmbeds` builds `<img src="portymcfolio://media/\(encoded)" ...>` from user filenames. Encoding uses `addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename` — the `?? filename` fallback passes the raw filename (with quotes and all) into the HTML attribute if encoding returns nil.

### Fix

- Change the `allowingReadAccessTo` argument to the HTML file's parent directory.
- Change `?? filename` fallbacks to `?? ""` and additionally HTML-escape the encoded value before it enters the `src` attribute.

### Steps

- [ ] **Step 1: Narrow the read-access grant**

Find line ~33-35:
```swift
        if let htmlURL = Bundle.main.url(forResource: "preview", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: Bundle.main.bundleURL)
        }
```

Replace with:
```swift
        if let htmlURL = Bundle.main.url(forResource: "preview", withExtension: "html") {
            // Grant read access ONLY to the directory containing preview.html,
            // not the whole app bundle. Prevents a DOMPurify-bypass from
            // fetching arbitrary bundle resources.
            let readScope = htmlURL.deletingLastPathComponent()
            webView.loadFileURL(htmlURL, allowingReadAccessTo: readScope)
        }
```

- [ ] **Step 2: Safely escape filenames in `src=`**

In `preprocessEmbeds` (around lines 64-78), replace the three `src=` branches:

Current:
```swift
            let replacement: String
            if imageExts.contains(ext) {
                let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
                replacement = "<img src=\"portymcfolio://media/\(encoded)\" alt=\"\(Self.escapeHTML(filename))\">"
            } else if videoExts.contains(ext) {
                let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
                replacement = "<video src=\"portymcfolio://media/\(encoded)\" controls preload=\"metadata\"></video>"
            } else if audioExts.contains(ext) {
                let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
                replacement = "<audio src=\"portymcfolio://media/\(encoded)\" controls preload=\"metadata\"></audio>"
            } else if LinkItem.isLinkFile(name: filename) {
```

Changed:
```swift
            let replacement: String
            // Defense-in-depth: even though .urlPathAllowed percent-encodes `"`,
            // the `??` fallback would previously pass the raw filename into the
            // attribute if encoding returned nil. Fall back to "" and HTML-escape
            // the encoded value before it enters the attribute.
            let safeEncodedSrc: String = {
                let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
                return Self.escapeHTML(encoded)
            }()

            if imageExts.contains(ext) {
                replacement = "<img src=\"portymcfolio://media/\(safeEncodedSrc)\" alt=\"\(Self.escapeHTML(filename))\">"
            } else if videoExts.contains(ext) {
                replacement = "<video src=\"portymcfolio://media/\(safeEncodedSrc)\" controls preload=\"metadata\"></video>"
            } else if audioExts.contains(ext) {
                replacement = "<audio src=\"portymcfolio://media/\(safeEncodedSrc)\" controls preload=\"metadata\"></audio>"
            } else if LinkItem.isLinkFile(name: filename) {
```

Note: `safeEncodedSrc` is computed once per match (inside the `for match in matches` loop) and reused across all three branches, so the closure is per-match, not hoisted. That's deliberate — it depends on `filename`.

- [ ] **Step 3: Build + full test suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: all tests pass (still 108).

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Views/MarkdownPreviewView.swift
git commit -m "security: narrow webview read scope and escape filenames in preview src"
```

---

## Task 2: Tighten DOMPurify `ALLOWED_URI_REGEXP` — drop `data:` and document the rest

**Files:**
- Modify: `PortyMcFolio/Editor/Resources/preview.html`

### Bug

The regex at line 325 allows `data:` URIs:
```
ALLOWED_URI_REGEXP: /^(?:(?:https?|ftp|mailto|tel|callto|cid|xmpp|data|portymcfolio):)/i
```

`preprocessEmbeds` only emits `portymcfolio://` URIs. The `data:` scheme is there by inheritance of a common DOMPurify setting, and allowing it means any `![alt](data:text/html;base64,…)` a user (or third party) includes in a markdown body gets rendered. That's a latent XSS risk for a content-editor app where the content might be partially imported.

Schemes that remain serve these purposes:
- `https`, `http` — generic external links
- `ftp` — legacy external links (keep — users may have them in historical notes)
- `mailto`, `tel`, `callto` — action schemes commonly produced by markdown
- `cid`, `xmpp` — niche, unused in this app but low-risk and DOMPurify-standard
- `portymcfolio` — our custom scheme for local-file media

### Fix

Remove `data|` from the allow-list, add a brief comment documenting scheme intent.

### Steps

- [ ] **Step 1: Edit the preview.html script block (around line 319-335)**

Current:
```html
<script>
function renderMarkdown(md) {
  var raw = marked.parse(md, { gfm: true, breaks: true });
  document.getElementById('content').innerHTML = DOMPurify.sanitize(raw, {
    ADD_TAGS: ['audio', 'video', 'source'],
    ADD_ATTR: ['controls', 'preload', 'src', 'alt', 'target', 'data-file'],
    ALLOWED_URI_REGEXP: /^(?:(?:https?|ftp|mailto|tel|callto|cid|xmpp|data|portymcfolio):)/i
  });
}
```

Changed:
```html
<script>
function renderMarkdown(md) {
  var raw = marked.parse(md, { gfm: true, breaks: true });
  // Allowed URI schemes:
  //   https, http, ftp — external links in markdown body
  //   mailto, tel, callto — user actions
  //   cid, xmpp — DOMPurify-standard, niche
  //   portymcfolio — custom scheme for local-file media via PreviewSchemeHandler
  // Intentionally NOT allowed: data: — prevents embedded data URI XSS.
  document.getElementById('content').innerHTML = DOMPurify.sanitize(raw, {
    ADD_TAGS: ['audio', 'video', 'source'],
    ADD_ATTR: ['controls', 'preload', 'src', 'alt', 'target', 'data-file'],
    ALLOWED_URI_REGEXP: /^(?:(?:https?|ftp|mailto|tel|callto|cid|xmpp|portymcfolio):)/i
  });
}
```

- [ ] **Step 2: Manual acceptance — verify a regular preview still renders**

No automated test covers the preview. This change is low-risk (we only dropped an allow-list entry). Build the app and open a project with an image embed to confirm the preview still renders. The controller does this manually after Task 7.

- [ ] **Step 3: Commit**

```bash
git add PortyMcFolio/Editor/Resources/preview.html
git commit -m "security: remove data: from preview DOMPurify allow-list"
```

---

## Task 3: Remove `preview-dev.html` from the app bundle

**Files:**
- Delete: `PortyMcFolio/Editor/Resources/preview-dev.html`

### Bug

`preview-dev.html` is a developer convenience file that uses `innerHTML` without DOMPurify (pre-review notes). It sits in `PortyMcFolio/Editor/Resources/` which is part of the build source path (`project.yml` has `sources: - path: PortyMcFolio`). Any code path that loads it via `Bundle.main.url(forResource:)` would bypass sanitization.

### Verification that nothing references it

A grep for `preview-dev` in `PortyMcFolio/` returns nothing (the name only appears in code-review notes and this plan file). Safe to delete — it's dead in production.

### Steps

- [ ] **Step 1: Delete the file**

```bash
git rm PortyMcFolio/Editor/Resources/preview-dev.html
```

- [ ] **Step 2: Verify nothing references it**

```bash
grep -rn "preview-dev" PortyMcFolio || echo "no references found"
```
Expected: "no references found".

- [ ] **Step 3: Regenerate Xcode project (resources list changed)**

```bash
xcodegen
```

- [ ] **Step 4: Build + full test suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio.xcodeproj
git commit -m "security: delete dev-only preview-dev.html from app bundle"
```

(The deletion was already staged by `git rm` in Step 1; xcodeproj change captured here.)

---

## Task 4: MarkdownEditorView — move save flush from `deinit` to `dismantleNSView`

**Files:**
- Modify: `PortyMcFolio/Views/MarkdownEditorView.swift`

### Bug

`Coordinator.deinit` (lines ~411-423) calls `saveContent()`, which reads `textView?.string` (an `NSTextView` property, main-thread-only) and writes to disk synchronously. `deinit` is not guaranteed to run on the main thread in Swift.

### Fix

`NSViewRepresentable` provides `static func dismantleNSView(_:coordinator:)`, which runs on MainActor before the coordinator is deallocated. Flush there and drop the deinit save.

### Steps

- [ ] **Step 1: Add `dismantleNSView` at the struct level**

In `PortyMcFolio/Views/MarkdownEditorView.swift`, right after `func updateNSView(_:context:)` (around line 296), add:

```swift
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        // Flush any pending debounced save BEFORE the coordinator deinits.
        // This runs on MainActor (guaranteed by NSViewRepresentable), so it
        // can safely touch NSTextView.string.
        coordinator.flushPendingSave()
    }
```

- [ ] **Step 2: Simplify `Coordinator.deinit`**

Replace the current deinit (around lines 411-423):
```swift
        deinit {
            // Flush any pending debounced save before being torn down.
            // This matters when ProjectDetailView is recreated via .id(project.uid)
            // on project navigation — the old coordinator is deallocated, and
            // without this any typed-but-not-yet-saved edits would be lost.
            if debounceTimer?.isValid == true {
                debounceTimer?.invalidate()
                saveContent()
            } else {
                debounceTimer?.invalidate()
            }
            highlightTimer?.invalidate()
        }
```

with:
```swift
        deinit {
            // Save flush happens in `MarkdownEditorView.dismantleNSView`
            // (MainActor), not here — deinit is not guaranteed main-thread.
            debounceTimer?.invalidate()
            highlightTimer?.invalidate()
        }
```

- [ ] **Step 3: Build + full test suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Views/MarkdownEditorView.swift
git commit -m "fix: move editor save flush from deinit to dismantleNSView (MainActor)"
```

---

## Task 5: PortfolioStore — log project load failures instead of silently dropping

**Files:**
- Modify: `PortyMcFolio/Services/PortfolioStore.swift`

### Bug

`scanProjects()` silently `continue`s past folders that fail to parse or load (lines 29-31, 33-37). A project with a temporarily locked `.md` file disappears from the UI with no diagnostic. The reconciler also has a similar pattern but at least logs some paths.

### Fix

Log the folder name and error before skipping. Match the `print("[X]")` pattern used elsewhere (reconciler, AppState).

### Steps

- [ ] **Step 1: Add logging to the two failure branches**

In `PortyMcFolio/Services/PortfolioStore.swift`, around lines 26-37:

```swift
            let folderName = url.lastPathComponent

            var project: Project
            do {
                project = try Project.from(folderName: folderName, rootURL: rootURL)
            } catch {
                continue
            }

            do {
                try project.loadReadme()
            } catch {
                continue
            }
```

Replace with:

```swift
            let folderName = url.lastPathComponent

            var project: Project
            do {
                project = try Project.from(folderName: folderName, rootURL: rootURL)
            } catch {
                // Folder name doesn't match the {year}_{slug}_{uid} pattern — not
                // necessarily a problem (it could be a user's own non-project folder),
                // so don't log noisily here.
                continue
            }

            do {
                try project.loadReadme()
            } catch {
                // This is a real signal: the folder names parses as a project but
                // its markdown file is missing/corrupt/locked. Log and skip so the
                // user at least has a trail to follow when a project "disappears."
                print("[PortfolioStore] loadReadme failed for \(folderName): \(error)")
                continue
            }
```

- [ ] **Step 2: Build + full test suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add PortyMcFolio/Services/PortfolioStore.swift
git commit -m "fix: log project load failures in PortfolioStore (stop dropping silently)"
```

---

## Task 6: ProjectListView — cache `projectsByYear`

**Files:**
- Modify: `PortyMcFolio/Views/ProjectListView.swift`

### Bug

`projectsByYear` (lines ~142-148) is a computed property that runs `Dictionary(grouping:)` on `appState.filteredProjects` every body evaluation. For large portfolios this is wasted work on every unrelated render.

### Fix

Cache in `@State`, load on appear, update on change of `appState.filteredProjects`.

### Steps

- [ ] **Step 1: Read the current shape**

Read `PortyMcFolio/Views/ProjectListView.swift` lines 140-160 to see the current computed property and its usage site.

- [ ] **Step 2: Replace the computed property with a `@State`-backed cache**

Find the property, currently:
```swift
    /// Projects grouped by year, sorted newest-first
    private var projectsByYear: [(year: Int, projects: [Project])] {
        let grouped = Dictionary(grouping: appState.filteredProjects) { $0.year }
        …
    }
```

Keep the function body intact, but rename it to a private helper `computeProjectsByYear()` that takes `[Project]` as input, and introduce a cache:

```swift
    @State private var projectsByYear: [(year: Int, projects: [Project])] = []

    private static func computeProjectsByYear(_ projects: [Project]) -> [(year: Int, projects: [Project])] {
        let grouped = Dictionary(grouping: projects) { $0.year }
        // … keep the rest of the original body here, returning the sorted tuple array …
    }
```

Preserve the exact grouping and sort logic; only refactor the input binding. Since the original was a computed property of `ProjectListView` that read `appState.filteredProjects`, we now explicitly pass `projects` in and return the same tuple type.

- [ ] **Step 3: Wire the cache to `onAppear` and `onChange`**

On the outermost view in `body`, add (or merge into existing):
```swift
        .onAppear {
            projectsByYear = Self.computeProjectsByYear(appState.filteredProjects)
        }
        .onChange(of: appState.filteredProjects) { _, newValue in
            projectsByYear = Self.computeProjectsByYear(newValue)
        }
```

The callsite in the body uses `projectsByYear` directly — no change needed there (same name, same tuple type).

- [ ] **Step 4: Build + full test suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Views/ProjectListView.swift
git commit -m "perf: cache projectsByYear in ProjectListView"
```

---

## Task 7: ProjectReconcilerDebounceTests — remove `Thread.sleep` in favor of condition waits

**Files:**
- Modify: `PortyMcFolioTests/ProjectReconcilerDebounceTests.swift`

### Bug

`testRapidEnqueueCoalescesIntoOnePass` (line 51) uses `Thread.sleep(forTimeInterval: 0.3)` after `waitForPasses(1, ...)` to ensure no extra pass slipped in. On a busy CI the 300ms grace is tight against the 250ms debounce window.

`testSlidingWindowCapsAt1000ms` (line 62) uses the same `Thread.sleep(forTimeInterval: 0.3)` as a drain and asserts `elapsed <= 2.5` — a 1.5-second slack band that won't catch regressions in the cap logic.

### Fix

Use the existing `waitForPasses` helper inverted — after confirming the expected pass, wait a bounded window for an unexpected second pass and assert it didn't arrive. For the sliding-window test, assert the elapsed time falls in a tight expected band (0.9s - 1.5s) instead of "under 2.5s."

### Steps

- [ ] **Step 1: Add a helper for "wait-and-expect-no-extra-pass"**

Immediately after `waitForPasses` in the test file (around line 43), add:

```swift
    /// Wait up to `window` seconds and verify `passCount` does NOT exceed `expected`.
    /// Used to prove coalescing worked — a runaway pass would arrive within one
    /// debounce-window after the first one fires.
    private func expectNoExtraPass(beyond expected: Int, window: TimeInterval) {
        let deadline = Date().addingTimeInterval(window)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.025))
            if passCount > expected {
                XCTFail("Extra pass arrived; passCount=\(passCount), expected=\(expected)")
                return
            }
        }
        XCTAssertEqual(passCount, expected)
    }
```

- [ ] **Step 2: Update `testRapidEnqueueCoalescesIntoOnePass`**

Replace:
```swift
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
```

With:
```swift
    func testRapidEnqueueCoalescesIntoOnePass() {
        // Fire 50 events in rapid succession (well within the 250ms debounce window).
        for i in 0..<50 {
            reconciler.enqueue([tempRoot.appendingPathComponent("file\(i)").path])
        }
        waitForPasses(1, timeout: 1.0)
        // Watch for 750ms (three debounce windows) to confirm no extra pass sneaks in.
        expectNoExtraPass(beyond: 1, window: 0.75)
    }
```

- [ ] **Step 3: Update `testSlidingWindowCapsAt1000ms`**

Replace:
```swift
    func testSlidingWindowCapsAt1000ms() {
        // Continuously enqueue every 100ms for 1.5 seconds.
        // Without a cap, the sliding window would never fire.
        // With the 1000ms cap, the first pass should fire at ~1.0s.
        let start = Date()
        let deadline = start.addingTimeInterval(2.5)
        while Date() < deadline && passCount == 0 {
            reconciler.enqueue([tempRoot.appendingPathComponent("p").path])
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        // Stop bursting; let the timer drain
        Thread.sleep(forTimeInterval: 0.3)

        XCTAssertGreaterThanOrEqual(passCount, 1, "Expected at least one pass within 1000ms cap")
        // The first pass should have fired before the 1.5s deadline
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThanOrEqual(elapsed, 2.5, "Pass took longer than expected")
    }
```

With:
```swift
    func testSlidingWindowCapsAt1000ms() {
        // Continuously enqueue every 100ms. Without a cap, the sliding window
        // would never fire. With a 1000ms cap, the first pass should fire at ~1.0s
        // after the first enqueue.
        let start = Date()
        let burstDeadline = start.addingTimeInterval(1.5)
        while Date() < burstDeadline && passCount == 0 {
            reconciler.enqueue([tempRoot.appendingPathComponent("p").path])
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        // passCount should already be 1 by now if the cap fired; give one runloop
        // tick in case the event handler is about to run.
        waitForPasses(1, timeout: 0.5)

        let elapsed = Date().timeIntervalSince(start)
        XCTAssertGreaterThanOrEqual(passCount, 1, "Expected the cap to fire at least one pass")
        // Tight band: cap is 1000ms; allow 200ms below (overdrive) and 500ms above
        // (CI jitter). A regression that removed the cap would blow past 1.5s.
        XCTAssertGreaterThan(elapsed, 0.8, "Pass fired far too early — cap logic may be broken")
        XCTAssertLessThan(elapsed, 1.5, "Pass took much longer than the 1000ms cap")
    }
```

- [ ] **Step 4: Full test suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolioTests/ProjectReconcilerDebounceTests.swift
git commit -m "test: replace Thread.sleep in debounce tests with condition-based waits"
```

---

## Task 8: Final verification

- [ ] **Step 1: Full test suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -10
```

- [ ] **Step 2: Rebuild and relaunch for manual checks**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -configuration Debug -destination 'platform=macOS' -derivedDataPath build build 2>&1 | tail -3
pkill -x PortyMcFolio 2>/dev/null; sleep 1
open build/Build/Products/Debug/PortyMcFolio.app
```

Manual acceptance (controller or user runs):
- Open a project with embedded images/videos — preview still renders.
- Click a file badge in preview — still opens the file.
- Navigate between projects quickly while typing — unsaved edits to the previous project are still persisted.
- Delete a project folder from disk while app is open — project disappears from list, no noisy errors.

No final commit (each task committed its own changes).

---

## Spec coverage check

| Requirement | Task |
|---|---|
| Narrow webview bundle read scope | Task 1 |
| Filename escape into src= attribute | Task 1 |
| DOMPurify data: removed | Task 2 |
| preview-dev.html removed from bundle | Task 3 |
| Editor deinit save off main-thread | Task 4 |
| PortfolioStore logs project load failures | Task 5 |
| ProjectListView caches projectsByYear | Task 6 |
| Debounce tests use condition waits | Task 7 |
| No regressions in existing 108 tests | All tasks Step 3/4 |
