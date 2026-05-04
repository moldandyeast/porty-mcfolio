# URL page redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make URL entry first-class on the Links view (inline bottom composer + async title fetch), simplify the gallery toolbar (remove duplicate Add-URL icon, fix overflow), and delete the now-dead `AddLinkSheet`.

**Architecture:** Eight bite-sized tasks. Tasks 1-2 are pure utility code with tests. Tasks 3-7 are UI changes in `GalleryView` that build toward the composer + title-fetch flow and then remove the old modal path. Task 8 is a verification pass.

**Tech Stack:** Swift 5.9, SwiftUI (macOS 14+), LinkPresentation framework (macOS 10.15+ — already available), XCTest.

**Spec:** `docs/superpowers/specs/2026-04-18-url-page-redesign-design.md`

---

## File Structure

**Create:**
- `PortyMcFolio/Services/LinkTitleFetcher.swift` — async helper wrapping `LPMetadataProvider` with a timeout.
- `PortyMcFolioTests/LinkURLNormalizationTests.swift` — tests for `LinkItem.normalizeURL`.

**Modify:**
- `PortyMcFolio/Models/LinkItem.swift` — add `static func normalizeURL(_:) -> URL?`.
- `PortyMcFolio/Views/GalleryView.swift` — composer UI, wiring, toolbar changes.

**Delete:**
- `PortyMcFolio/Views/AddLinkSheet.swift` — no callers after the toolbar change.

---

## Task 1: Move URL normalization from AddLinkSheet to LinkItem + add tests

**Files:**
- Modify: `PortyMcFolio/Models/LinkItem.swift`
- Create: `PortyMcFolioTests/LinkURLNormalizationTests.swift`

**Rationale:** the existing `normalizeURL` lives as a private static on `AddLinkSheet` (which we'll delete). Move it to `LinkItem` so the new composer can reuse it, and add unit tests that lock the behavior (bare domain, explicit scheme, non-http schemes).

- [ ] **Step 1: Write the failing tests**

Create `PortyMcFolioTests/LinkURLNormalizationTests.swift`:

```swift
import XCTest
@testable import PortyMcFolio

final class LinkURLNormalizationTests: XCTestCase {
    func testBareDomainGetsHttpsPrefix() {
        let url = LinkItem.normalizeURL("example.com")
        XCTAssertEqual(url?.absoluteString, "https://example.com")
    }

    func testHttpsURLPassesThrough() {
        let url = LinkItem.normalizeURL("https://example.com/path?q=1")
        XCTAssertEqual(url?.absoluteString, "https://example.com/path?q=1")
    }

    func testHttpURLPassesThrough() {
        let url = LinkItem.normalizeURL("http://example.com")
        XCTAssertEqual(url?.absoluteString, "http://example.com")
    }

    func testFtpURLPassesThrough() {
        // normalizeURL returns the URL as-is; scheme filtering is the caller's job.
        let url = LinkItem.normalizeURL("ftp://example.com")
        XCTAssertEqual(url?.absoluteString, "ftp://example.com")
    }

    func testLeadingAndTrailingWhitespaceTrimmed() {
        let url = LinkItem.normalizeURL("   https://example.com  ")
        XCTAssertEqual(url?.absoluteString, "https://example.com")
    }

    func testEmptyStringReturnsNil() {
        XCTAssertNil(LinkItem.normalizeURL(""))
        XCTAssertNil(LinkItem.normalizeURL("   "))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodegen
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/LinkURLNormalizationTests 2>&1 | tail -30
```
Expected: FAIL with a compile error (`LinkItem.normalizeURL` not defined).

- [ ] **Step 3: Add `normalizeURL` to LinkItem**

In `PortyMcFolio/Models/LinkItem.swift`, append inside the `struct LinkItem` body (after the existing static helpers, before `parse`):

```swift
    /// Normalizes user-entered URL text. Returns nil for empty/invalid input.
    /// Bare domains (no scheme) get prepended with `https://`. URLs that
    /// already have a scheme (http, https, ftp, file, mailto, etc.) pass through.
    static func normalizeURL(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return URL(string: trimmed)
        }

        if trimmed.contains("://") {
            return URL(string: trimmed)
        }

        return URL(string: "https://\(trimmed)")
    }
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/LinkURLNormalizationTests 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`, 6/6 pass.

- [ ] **Step 5: Full suite — no regressions**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: all tests pass (114 = 108 + 6 new).

- [ ] **Step 6: Commit**

```bash
git add PortyMcFolio/Models/LinkItem.swift PortyMcFolioTests/LinkURLNormalizationTests.swift PortyMcFolio.xcodeproj
git commit -m "refactor: hoist normalizeURL from AddLinkSheet to LinkItem + add tests"
```

---

## Task 2: Create `LinkTitleFetcher`

**Files:**
- Create: `PortyMcFolio/Services/LinkTitleFetcher.swift`

**Rationale:** the composer kicks off a title fetch after saving. Isolate `LPMetadataProvider` + timeout behind a small async helper so `GalleryView` has no network code.

- [ ] **Step 1: Create the helper**

Create `PortyMcFolio/Services/LinkTitleFetcher.swift`:

```swift
import Foundation
import LinkPresentation

/// Fetches a web page's title for use as a link's display name.
/// Wraps `LPMetadataProvider` with a hard timeout so a hanging site doesn't
/// block the calling task indefinitely.
enum LinkTitleFetcher {
    /// Fetches the page title for `url`. Returns `nil` if the fetch fails,
    /// times out, or the fetched metadata has no usable title.
    static func fetch(url: URL, timeout: TimeInterval = 5) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                await fetchWithProvider(url: url)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }

            // Return the first result — fetch success, fetch failure, or timeout.
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func fetchWithProvider(url: URL) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let provider = LPMetadataProvider()
            provider.startFetchingMetadata(for: url) { metadata, _ in
                let title = metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let title, !title.isEmpty {
                    continuation.resume(returning: title)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Regenerate project + build**

```bash
xcodegen
xcodebuild build -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **`. (No unit tests for this — real network behavior isn't deterministic. It gets exercised end-to-end in the composer task.)

- [ ] **Step 3: Full suite — no regressions**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: all 114 tests pass.

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Services/LinkTitleFetcher.swift PortyMcFolio.xcodeproj
git commit -m "feat: LinkTitleFetcher wraps LPMetadataProvider with a timeout"
```

---

## Task 3: Flip link sort order + update empty-state copy

**Files:**
- Modify: `PortyMcFolio/Views/GalleryView.swift`

**Rationale:** new URLs should land at the bottom next to the composer, and the empty-state text should point at the composer.

- [ ] **Step 1: Flip the sort at line ~336**

In `PortyMcFolio/Views/GalleryView.swift`, find in `scanProjectFolder()`:

```swift
        links = scannedLinks.sorted { $0.date > $1.date }
```

Change to:

```swift
        links = scannedLinks.sorted { $0.date < $1.date }
```

- [ ] **Step 2: Update the empty-state message at line ~427**

In the same file, find `linksEmptyState`:

```swift
            Text("Add a URL from the + menu")
```

Change to:

```swift
            Text("Paste a URL below to save it.")
```

- [ ] **Step 3: Build + full suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Views/GalleryView.swift
git commit -m "fix: sort links oldest→newest and rewrite empty-state copy"
```

---

## Task 4: Composer UI + save URL on submit (no fetch yet)

**Files:**
- Modify: `PortyMcFolio/Views/GalleryView.swift`

**Rationale:** get the inline composer UI in place, wire Enter → validate + save. Title auto-fetch comes in Task 5.

- [ ] **Step 1: Add composer state to `GalleryView`**

Near the other `@State` properties at the top of the struct (around line 13-32), add:

```swift
    @State private var composerText = ""
    @State private var composerShake = false
    @FocusState private var composerFocused: Bool
```

- [ ] **Step 2: Extract a composer subview**

After the other `private var` view blocks (e.g. after `linksEmptyState`), add:

```swift
    private var urlComposer: some View {
        HStack(spacing: DT.Spacing.sm) {
            TextField("Paste a URL…", text: $composerText)
                .textFieldStyle(.plain)
                .font(DT.Typography.body)
                .foregroundStyle(DT.Colors.textPrimary)
                .focused($composerFocused)
                .onSubmit { submitComposer() }
                .padding(.horizontal, DT.Spacing.sm)
                .padding(.vertical, DT.Spacing.sm)
                .background(DT.Colors.backgroundAlt, in: RoundedRectangle(cornerRadius: DT.Radius.small))
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.small)
                        .stroke(composerShake ? DT.Colors.error : DT.Colors.border,
                                lineWidth: composerShake ? 1 : 0.5)
                )
                .animation(.easeInOut(duration: 0.15), value: composerShake)
        }
        .padding(.horizontal, DT.Spacing.md)
        .padding(.vertical, DT.Spacing.sm)
    }

    private func submitComposer() {
        let raw = composerText
        guard let url = LinkItem.normalizeURL(raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            flashComposerError()
            return
        }

        let uid = UID.generate()
        let link = LinkItem(
            uid: uid,
            url: url,
            title: "",
            annotation: "",
            date: Date()
        )
        let fileURL = project.folderURL.appendingPathComponent(LinkItem.fileName(uid: uid))
        do {
            try link.toMarkdown().write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("[GalleryView] failed to save link: \(error)")
            flashComposerError()
            return
        }

        composerText = ""
        // Ensure the list picks it up without waiting for FSEvent.
        scanProjectFolder()
    }

    private func flashComposerError() {
        composerShake = true
        NSSound.beep()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            composerShake = false
        }
    }
```

- [ ] **Step 3: Insert the composer into the Links-view layout**

Find the `body` in `GalleryView`, around line 50-59:

```swift
        VStack(spacing: 0) {
            // Content
            if viewMode == .links {
                if links.isEmpty {
                    linksEmptyState
                        .contextMenu { galleryBackgroundMenu }
                } else {
                    linksContent
                }
            } else if isEmpty {
```

Replace with:

```swift
        VStack(spacing: 0) {
            // Content
            if viewMode == .links {
                Group {
                    if links.isEmpty {
                        linksEmptyState
                            .contextMenu { galleryBackgroundMenu }
                    } else {
                        linksContent
                    }
                }
                urlComposer
            } else if isEmpty {
```

This puts `urlComposer` below the list (or the empty-state) in the same outer `VStack`, above the bottom toolbar.

- [ ] **Step 4: Autofocus composer when switching into Links view**

Find in `body` the bottom toolbar's view-mode toggles (around line 154-156):

```swift
                toolbarIcon("square.grid.2x2", help: "Grid", active: viewMode == .grid) { viewMode = .grid }
                toolbarIcon("list.bullet", help: "List", active: viewMode == .list) { viewMode = .list }
                toolbarIcon("link", help: "Links", active: viewMode == .links) { viewMode = .links }
```

Change the Links toggle to focus the composer:

```swift
                toolbarIcon("square.grid.2x2", help: "Grid", active: viewMode == .grid) { viewMode = .grid }
                toolbarIcon("list.bullet", help: "List", active: viewMode == .list) { viewMode = .list }
                toolbarIcon("link", help: "Links", active: viewMode == .links) {
                    viewMode = .links
                    // Defer focus to next runloop so the composer view exists.
                    DispatchQueue.main.async { composerFocused = true }
                }
```

- [ ] **Step 5: Build + full suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add PortyMcFolio/Views/GalleryView.swift
git commit -m "feat: inline URL composer on Links view with Enter-to-save"
```

---

## Task 5: Wire async title fetch after save

**Files:**
- Modify: `PortyMcFolio/Views/GalleryView.swift`

**Rationale:** after the link file is written, fetch the page title in the background. Update the file when the title arrives.

- [ ] **Step 1: Add a title-fetch helper method on `GalleryView`**

In `GalleryView`, alongside `submitComposer` (from Task 4), add:

```swift
    /// After a fresh link save, fetch the page title and write it back into the
    /// link file. The existing `FileWatcher → reconciler` path re-indexes the
    /// second write, and `scanProjectFolder()` on MainActor refreshes the UI.
    private func fetchAndApplyTitle(for uid: String, url: URL) {
        Task.detached { [project] in
            guard let title = await LinkTitleFetcher.fetch(url: url) else { return }

            let fileURL = project.folderURL.appendingPathComponent(LinkItem.fileName(uid: uid))
            guard let existing = try? String(contentsOf: fileURL, encoding: .utf8),
                  let parsed = try? LinkItem.parse(markdown: existing, overrideUID: uid) else {
                return
            }
            guard parsed.title.isEmpty else { return } // user may have set a title in the meantime; don't clobber

            let updated = LinkItem(
                uid: uid,
                url: parsed.url,
                title: title,
                annotation: parsed.annotation,
                date: parsed.date
            )
            do {
                try updated.toMarkdown().write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                print("[GalleryView] failed to write fetched title: \(error)")
                return
            }

            await MainActor.run { self.scanProjectFolder() }
        }
    }
```

- [ ] **Step 2: Call it from `submitComposer`**

Find `submitComposer` (from Task 4) and add one line after `scanProjectFolder()` at the end:

```swift
        composerText = ""
        scanProjectFolder()
        fetchAndApplyTitle(for: uid, url: url)
    }
```

- [ ] **Step 3: Build + full suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: all tests pass.

- [ ] **Step 4: Manual verification**

Launch the app (⌘R in Xcode or rebuild the DMG), open a project, switch to the Links view, paste `https://example.com`, press Enter. The URL appears immediately with the host as its title; within 1-5 seconds the title updates to "Example Domain".

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Views/GalleryView.swift
git commit -m "feat: auto-fetch page title after saving a URL"
```

---

## Task 6: Remove Add-URL toolbar button + fix toolbar overflow

**Files:**
- Modify: `PortyMcFolio/Views/GalleryView.swift`

**Rationale:** the composer replaces the Add-URL modal. Remove the button, the sheet modifier, the `@State var isShowingAddLink`, and the second call-site in the background menu. Add `layoutPriority` so the breadcrumb truncates instead of clipping the action icons.

- [ ] **Step 1: Remove `isShowingAddLink` state**

Delete line ~18:
```swift
    @State private var isShowingAddLink = false
```

- [ ] **Step 2: Remove the Add-URL toolbar action (line ~98-100)**

Delete:
```swift
                // Action buttons
                galleryAction(icon: "link", help: "Add URL") {
                    isShowingAddLink = true
                }
```

Keep the `// Action buttons` comment (move it to the next button if desired).

- [ ] **Step 3: Remove the sheet modifier (line ~197-199)**

Delete:
```swift
        .sheet(isPresented: $isShowingAddLink) {
            AddLinkSheet(projectFolderURL: project.folderURL)
        }
```

- [ ] **Step 4: Remove the background-menu call-site (line ~629)**

Find in the file:
```swift
        Button { isShowingAddLink = true } label: {
```

Locate the enclosing `Button { ... } label: { ... }` block in the gallery background context menu (search for `isShowingAddLink`; there is one remaining occurrence after Step 1). Delete the whole Button block (and any preceding/trailing Divider if appropriate — reviewer should preserve the surrounding menu structure but drop the now-dangling "Add URL" entry).

- [ ] **Step 5: Add layoutPriority to the toolbar**

Find the toolbar `HStack` (around line 77-157). Wrap the action-icons + separator + view-mode-toggles in a sibling `HStack` with `.layoutPriority(1)`, and apply `.layoutPriority(0)` to the `BreadcrumbBar`:

```swift
            // Bottom bar: breadcrumb + view toggle
            HStack(spacing: DT.Spacing.xs) {
                BreadcrumbBar(
                    projectName: project.title.isEmpty ? "Project" : project.title,
                    relativePath: currentSubpath,
                    currentFolderURL: currentFolderURL,
                    onNavigate: { index in
                        if index < 0 {
                            currentSubpath = []
                        } else {
                            currentSubpath = Array(currentSubpath.prefix(index + 1))
                        }
                        clearSelection()
                        scanProjectFolder()
                    },
                    onRenameCurrentFolder: currentSubpath.isEmpty ? nil : {
                        folderRenameText = currentSubpath.last ?? ""
                        folderToRename = currentFolderURL
                    }
                )
                .layoutPriority(0)

                HStack(spacing: DT.Spacing.xs) {
                    galleryAction(icon: "doc.badge.plus", help: "Add File") {
                        showFilePicker()
                    }
                    galleryAction(icon: "folder.badge.plus", help: "New Folder") {
                        isCreatingFolder = true
                    }
                    .popover(isPresented: $isCreatingFolder) {
                        VStack(spacing: DT.Spacing.sm) {
                            TextField("Folder name", text: $newFolderName)
                                .textFieldStyle(.plain)
                                .font(DT.Typography.body)
                                .padding(.horizontal, DT.Spacing.sm)
                                .padding(.vertical, DT.Spacing.sm)
                                .background(DT.Colors.backgroundAlt, in: RoundedRectangle(cornerRadius: DT.Radius.small))
                                .overlay(RoundedRectangle(cornerRadius: DT.Radius.small).stroke(DT.Colors.border, lineWidth: 0.5))
                                .frame(width: 180)
                                .onSubmit { createFolder() }
                            HStack {
                                Button("Cancel") {
                                    newFolderName = ""
                                    isCreatingFolder = false
                                }
                                .font(DT.Typography.caption)
                                .buttonStyle(.plain)
                                .foregroundStyle(DT.Colors.textSecondary)

                                Button {
                                    createFolder()
                                } label: {
                                    Text("Create")
                                        .font(DT.Typography.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, DT.Spacing.md)
                                        .padding(.vertical, DT.Spacing.xs)
                                        .background(DT.Colors.accent, in: RoundedRectangle(cornerRadius: DT.Radius.small))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(DT.Spacing.md)
                    }
                    galleryAction(icon: "sparkles", help: "Clean Up") {
                        startCleanup()
                    }

                    // Separator
                    Rectangle()
                        .fill(DT.Colors.border)
                        .frame(width: 1, height: 14)
                        .padding(.horizontal, DT.Spacing.xs)

                    // View mode
                    toolbarIcon("square.grid.2x2", help: "Grid", active: viewMode == .grid) { viewMode = .grid }
                    toolbarIcon("list.bullet", help: "List", active: viewMode == .list) { viewMode = .list }
                    toolbarIcon("link", help: "Links", active: viewMode == .links) {
                        viewMode = .links
                        DispatchQueue.main.async { composerFocused = true }
                    }
                }
                .layoutPriority(1)
            }
            .padding(.horizontal, DT.Spacing.sm)
```

- [ ] **Step 6: Build + full suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add PortyMcFolio/Views/GalleryView.swift
git commit -m "refactor: remove Add-URL toolbar button and fix icon overflow"
```

---

## Task 7: Delete `AddLinkSheet.swift`

**Files:**
- Delete: `PortyMcFolio/Views/AddLinkSheet.swift`

**Rationale:** no remaining callers after Task 6. Dead code — remove.

- [ ] **Step 1: Verify no references**

```bash
grep -rn "AddLinkSheet" PortyMcFolio PortyMcFolioTests 2>/dev/null || echo "no references found"
```
Expected: `no references found` (or only matches inside a commented-out/doc context — stop and flag if anything else).

- [ ] **Step 2: Delete the file**

```bash
git rm PortyMcFolio/Views/AddLinkSheet.swift
```

- [ ] **Step 3: Regenerate Xcode project**

```bash
xcodegen
```

- [ ] **Step 4: Build + full suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: all 114 tests pass, build succeeds.

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio.xcodeproj
git commit -m "chore: delete dead AddLinkSheet after URL composer migration"
```

(The file deletion was already staged by `git rm` in Step 2.)

---

## Task 8: Final verification

**Files:** none.

- [ ] **Step 1: Full suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: 114 tests passing.

- [ ] **Step 2: Rebuild Debug and relaunch**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -configuration Debug -destination 'platform=macOS' -derivedDataPath build build 2>&1 | tail -3
pkill -x PortyMcFolio 2>/dev/null; sleep 1
open build/Build/Products/Debug/PortyMcFolio.app
```

- [ ] **Step 3: Manual acceptance (controller does NOT perform — user does)**

Inside the running app:
1. Open a project with an existing long breadcrumb (like "Openrank & Karma3Labs") — toolbar icons are no longer clipped; breadcrumb truncates if necessary.
2. Switch to Links view. Composer is pinned at the bottom, above the toolbar. Cursor is in it.
3. With no existing URLs, empty-state says "Paste a URL below to save it."
4. Paste `https://example.com`. Press Enter. URL appears immediately at the bottom of the list with the host as its title. Title updates within a few seconds to the actual page title.
5. Paste `example.com` (no scheme). Press Enter. Saved as `https://example.com`, same auto-title behavior.
6. Paste `not a url`. Press Enter. Composer border flashes red, beep sounds, nothing saved, input preserved.
7. Paste `ftp://example.com`. Press Enter. Rejected (non-http/https scheme).
8. Add several URLs in succession. They append at the bottom, one by one. Composer clears after each.
9. Only one `link` icon visible in the toolbar (the view-mode toggle). No Add-URL button.

- [ ] **Step 4: If anything failed, STOP and debug. No final commit — each task committed.**

---

## Spec coverage check

| Spec requirement | Task |
|---|---|
| Inline URL composer on Links view | Task 4 |
| Composer pinned at bottom | Task 4 |
| Empty-state points at composer | Task 3 |
| New URLs appear at bottom (oldest→newest) | Task 3 |
| `http`/`https`-only validation | Task 4 |
| Invalid URL → subtle feedback, no modal | Task 4 (`flashComposerError`) |
| Auto-fetch page title via `LPMetadataProvider` | Task 2 + Task 5 |
| 5-second timeout on fetch | Task 2 |
| URL normalization (bare domain → https) | Task 1 |
| Remove Add-URL toolbar button | Task 6 |
| Fix toolbar overflow | Task 6 (layoutPriority) |
| Delete `AddLinkSheet.swift` | Task 7 |
| No regressions in existing 108 tests | All tasks step 3/4 |
