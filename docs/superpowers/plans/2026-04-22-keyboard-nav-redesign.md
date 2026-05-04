# Keyboard Navigation Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure in-project view modes into 9 cases (each with its own `⌘<digit>` / `⌘⇧<digit>` shortcut), move Project Settings to `⌘9` globally, normalize Esc to stack-pop, and free up `⌘⇧3` by moving the editor's heading shortcuts to `⌘⌥1-3`.

**Architecture:** Replace `AppState.ViewMode` (5 cases) with 9 cases; expand `DefaultViewMode` to match. Add a one-shot UserDefaults migration flag so legacy `viewMode = 4` (old carousel) maps to new `viewMode = 8` exactly once. Delete `GalleryView`'s internal `GalleryViewMode` enum and toggle buttons; `GalleryView` now takes a `mode: GalleryMode` parameter from its parent. Rebuild the app's View menu and `ProjectDetailView`'s toolbar. Esc behavior is already correct at each layer; we just verify and clean up one overloaded `⌘1` binding.

**Tech Stack:** Swift 5.9, SwiftUI (`Commands`, `.keyboardShortcut`), AppKit (`performKeyEquivalent` for editor), XCTest, XcodeGen.

---

## Spec Reference

Design doc: `docs/superpowers/specs/2026-04-22-keyboard-nav-redesign-design.md`

## File Structure

**New:**
- `PortyMcFolio/Services/ViewModeMigration.swift` — pure helper that migrates legacy UserDefaults `viewMode` Int (~25 LOC). Extracted into a service so we can unit-test with an injected `UserDefaults`.
- `PortyMcFolioTests/ViewModeMigrationTests.swift` — 3–4 unit tests for the migration (~60 LOC).

**Modified:**
- `PortyMcFolio/App/AppState.swift` — new `ViewMode` enum (9 cases); expanded `DefaultViewMode`; call `ViewModeMigration.migrate(_:)` once at init; handle new string rawValue `"split"→"splitGallery"` on the `defaultViewMode` load path.
- `PortyMcFolio/App/PortyMcFolioApp.swift` — rewrite the View `CommandGroup` with 10 entries in shortcut order.
- `PortyMcFolio/Views/ProjectDetailView.swift` — new toolbar (keep 5 icons, but each button targets a specific new case); remove the `⌘1` "toggle editor↔preview" overload (now `⌘1` = Editor only); remove the `⌘4` Project Settings binding (rebound to `⌘9`); expand the layout `switch` to branch on 9 cases; update `handlePendingSelection` to route to `.splitGallery` / `.splitLinks` as appropriate.
- `PortyMcFolio/Views/GalleryView.swift` — delete `GalleryViewMode` enum, delete `@State var viewMode`, delete grid/list/links toggle buttons; add `let mode: GalleryMode` init parameter; replace every `self.viewMode` with `self.mode`; escalate the `pendingLinkID → .links` switch to `appState.viewMode = .splitLinks` (handled one level up in Task 1's `ProjectDetailView` change).
- `PortyMcFolio/Views/ProjectListView.swift` — change `⌘4` to `⌘9` on the "open highlighted project settings" binding.
- `PortyMcFolio/Views/AppSettingsView.swift` — expand `defaultViewMode` pill row to 10 pills; rewrite `shortcutsSection` to the new shortcut map.
- `PortyMcFolio/Views/MarkdownEditorView.swift` — move editor heading shortcuts from `⌘⇧1/2/3` to `⌘⌥1/2/3` inside `performKeyEquivalent`.

**Regenerated:**
- `PortyMcFolio.xcodeproj/project.pbxproj` — via `xcodegen generate` after the two new Swift files are added.

## Convention Notes

- **Build command:**
  ```
  xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' build
  ```
- **Test command:**
  ```
  xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' test
  ```
- **Do NOT edit** `project.yml`, `PortyMcFolio/PortyMcFolio.entitlements`, or any file under `Services/` except the new `ViewModeMigration.swift`.
- **Ignore** `.claude/settings.local.json`'s unstaged change — never stage it.
- **The ViewMode/DefaultViewMode refactor is atomic.** Because Swift enums can't have two cases at the same raw value, every call site must update together. Task 1 therefore edits 7 files in one commit; intermediate states don't build. Do all edits in Task 1's steps in order, then build once at the end.

---

## Task 1: ViewMode migration helper + unit tests (TDD)

Build the testable migration function first; later tasks call it.

**Files:**
- Create: `PortyMcFolio/Services/ViewModeMigration.swift`
- Create: `PortyMcFolioTests/ViewModeMigrationTests.swift`
- Regenerated: `PortyMcFolio.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create the failing test file**

Create `PortyMcFolioTests/ViewModeMigrationTests.swift`:

```swift
import XCTest
@testable import PortyMcFolio

final class ViewModeMigrationTests: XCTestCase {

    private func scratchDefaults() -> UserDefaults {
        let name = "test-vm-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testMigratesLegacyCarouselFromFourToEight() {
        let d = scratchDefaults()
        d.set(4, forKey: "viewMode")

        ViewModeMigration.migrate(d)

        XCTAssertEqual(d.integer(forKey: "viewMode"), 8)
        XCTAssertTrue(d.bool(forKey: "viewModeMigratedToV2"))
    }

    func testMigratesEditorPreviewSplitGalleryUntouched() {
        for legacy in 0...3 {
            let d = scratchDefaults()
            d.set(legacy, forKey: "viewMode")

            ViewModeMigration.migrate(d)

            XCTAssertEqual(d.integer(forKey: "viewMode"), legacy, "legacy=\(legacy)")
            XCTAssertTrue(d.bool(forKey: "viewModeMigratedToV2"))
        }
    }

    func testSecondCallIsNoop() {
        let d = scratchDefaults()
        d.set(4, forKey: "viewMode")
        ViewModeMigration.migrate(d)
        XCTAssertEqual(d.integer(forKey: "viewMode"), 8)

        // User later picks .splitList which happens to be raw=4.
        d.set(4, forKey: "viewMode")

        ViewModeMigration.migrate(d)  // Should NOT re-migrate

        XCTAssertEqual(d.integer(forKey: "viewMode"), 4, "second call must not touch user's new value")
    }

    func testNoLegacyKeyStillSetsFlag() {
        let d = scratchDefaults()
        // No "viewMode" key written.

        ViewModeMigration.migrate(d)

        XCTAssertNil(d.object(forKey: "viewMode"))
        XCTAssertTrue(d.bool(forKey: "viewModeMigratedToV2"))
    }
}
```

- [ ] **Step 2: Regenerate xcodeproj**

Run: `xcodegen generate`

Expected: `project.pbxproj` is updated; output ends with `Created project at PortyMcFolio.xcodeproj`.

- [ ] **Step 3: Run the tests and verify they fail to compile**

Run: `xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/ViewModeMigrationTests test`

Expected: TEST BUILD FAILED — `error: cannot find 'ViewModeMigration' in scope`.

- [ ] **Step 4: Create the migration helper**

Create `PortyMcFolio/Services/ViewModeMigration.swift`:

```swift
import Foundation

/// One-shot migration of the stored `viewMode` UserDefaults Int from the
/// legacy 5-case enum to the new 9-case enum.
///
/// Legacy layout: editor=0, preview=1, split=2, gallery=3, carousel=4
/// New layout:    editor=0, preview=1, splitGallery=2, gallery=3,
///                splitList=4, list=5, splitLinks=6, links=7, carousel=8
///
/// The only raw-value shift is carousel (4 → 8). `split` renames to
/// `splitGallery` but keeps raw=2, so the stored Int is already correct
/// for everything except legacy carousel.
///
/// Because new raw=4 means `splitList` — colliding with legacy raw=4
/// (carousel) — the migration must run exactly once. A sticky flag
/// `viewModeMigratedToV2` gates it.
enum ViewModeMigration {
    static func migrate(_ defaults: UserDefaults) {
        guard !defaults.bool(forKey: "viewModeMigratedToV2") else { return }

        if let legacy = defaults.object(forKey: "viewMode") as? Int {
            let migrated: Int
            switch legacy {
            case 0: migrated = 0  // editor
            case 1: migrated = 1  // preview
            case 2: migrated = 2  // split → splitGallery
            case 3: migrated = 3  // gallery
            case 4: migrated = 8  // carousel (was 4, now 8)
            default: migrated = 0
            }
            defaults.set(migrated, forKey: "viewMode")
        }
        defaults.set(true, forKey: "viewModeMigratedToV2")
    }
}
```

- [ ] **Step 5: Regenerate xcodeproj for the new source file**

Run: `xcodegen generate`

- [ ] **Step 6: Run the tests and verify all pass**

Run: `xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/ViewModeMigrationTests test`

Expected: TEST SUCCEEDED — 4 passing.

- [ ] **Step 7: Commit**

```bash
git add PortyMcFolio/Services/ViewModeMigration.swift \
        PortyMcFolioTests/ViewModeMigrationTests.swift \
        PortyMcFolio.xcodeproj/project.pbxproj
git commit -m "feat(viewmode): migration helper for legacy carousel raw value"
```

---

## Task 2: ViewMode enum restructure + all call-site updates (atomic)

This is the big one. All enum references must update together because Swift enums can't hold two cases at the same raw value.

**Files:**
- Modify: `PortyMcFolio/App/AppState.swift`
- Modify: `PortyMcFolio/App/PortyMcFolioApp.swift`
- Modify: `PortyMcFolio/Views/ProjectDetailView.swift`
- Modify: `PortyMcFolio/Views/GalleryView.swift`
- Modify: `PortyMcFolio/Views/ProjectListView.swift`
- Modify: `PortyMcFolio/Views/AppSettingsView.swift`

- [ ] **Step 1: Replace the `ViewMode` enum in `AppState.swift`**

Find the existing enum near the top of `PortyMcFolio/App/AppState.swift` (around line 10–16):

```swift
enum ViewMode: Int, Codable {
    case editor = 0
    case preview = 1
    case split = 2
    case gallery = 3
    case carousel = 4
}
```

Replace with:

```swift
enum ViewMode: Int, Codable, CaseIterable {
    case editor       = 0  // ⌘1
    case preview      = 1  // ⌘2
    case splitGallery = 2  // ⌘3
    case gallery      = 3  // ⌘⇧3
    case splitList    = 4  // ⌘4
    case list         = 5  // ⌘⇧4
    case splitLinks   = 6  // ⌘5
    case links        = 7  // ⌘⇧5
    case carousel     = 8  // ⌘6
}
```

- [ ] **Step 2: Expand `DefaultViewMode` in `AppState.swift`**

Find the existing `DefaultViewMode` enum (near the top, or nested inside `AppState`):

```swift
enum DefaultViewMode: String, Codable, CaseIterable {
    case lastUsed
    case editor
    case preview
    case split
    case gallery
    case carousel
}
```

Replace with:

```swift
enum DefaultViewMode: String, Codable, CaseIterable {
    case lastUsed
    case editor
    case preview
    case splitGallery
    case gallery
    case splitList
    case list
    case splitLinks
    case links
    case carousel
}
```

- [ ] **Step 3: Wire the migration into `AppState.init` and adjust `loadLayoutPreferences`**

In `AppState.swift`, find `loadLayoutPreferences()`. At the TOP of the function (before any `UserDefaults` reads), add:

```swift
        ViewModeMigration.migrate(.standard)
```

Still in `loadLayoutPreferences`, find the `defaultViewMode` load block (current pattern: `if let raw = UserDefaults.standard.string(forKey: "defaultViewMode"), let mode = DefaultViewMode(rawValue: raw)`). Replace it with:

```swift
        if let raw = UserDefaults.standard.string(forKey: "defaultViewMode") {
            // Legacy rename: "split" → "splitGallery". Idempotent.
            let migrated = raw == "split" ? "splitGallery" : raw
            if let mode = DefaultViewMode(rawValue: migrated) {
                defaultViewMode = mode
            }
        }
```

The `viewMode` Int load block stays as-is — the migration already rewrote the stored value in Step 1's helper.

- [ ] **Step 4: Rewrite `PortyMcFolioApp.swift` command group**

Open `PortyMcFolio/App/PortyMcFolioApp.swift`. Find the `CommandGroup(replacing: .sidebar)` (around lines 28–48) that currently has 4 menu items (Editor ⌘1, Split ⌘2, Gallery ⌘3, Carousel ⌘5). Replace the whole block with:

```swift
            CommandGroup(replacing: .sidebar) {
                Button("Editor") { appState.viewMode = .editor }
                    .keyboardShortcut("1", modifiers: .command)

                Button("Preview") { appState.viewMode = .preview }
                    .keyboardShortcut("2", modifiers: .command)

                Button("Editor + Gallery") { appState.viewMode = .splitGallery }
                    .keyboardShortcut("3", modifiers: .command)

                Button("Gallery") { appState.viewMode = .gallery }
                    .keyboardShortcut("3", modifiers: [.command, .shift])

                Button("Editor + List") { appState.viewMode = .splitList }
                    .keyboardShortcut("4", modifiers: .command)

                Button("List") { appState.viewMode = .list }
                    .keyboardShortcut("4", modifiers: [.command, .shift])

                Button("Editor + Links") { appState.viewMode = .splitLinks }
                    .keyboardShortcut("5", modifiers: .command)

                Button("Links") { appState.viewMode = .links }
                    .keyboardShortcut("5", modifiers: [.command, .shift])

                Button("Carousel") { appState.viewMode = .carousel }
                    .keyboardShortcut("6", modifiers: .command)

                Divider()

                Button("Project Settings") { appState.isShowingProjectSettings = true }
                    .keyboardShortcut("9", modifiers: .command)
            }
```

**Note:** `appState.isShowingProjectSettings` is a new `@Published Bool` on `AppState` added in Step 5. Macos menu shortcuts preempt view-local key handlers, so this one menu entry is the sole ⌘9 trigger. Both `ProjectDetailView` and `ProjectListView` observe the flag and each decides how to present the popover for its own context.

- [ ] **Step 5: Add the shared Project Settings flag on `AppState`**

Still in `PortyMcFolio/App/AppState.swift`, add one `@Published` property near the other UI-state flags (around `isShowingSettings`):

```swift
    /// Set to true by the ⌘9 menu handler. Whichever view is visible —
    /// ProjectDetailView or ProjectListView — observes this flag, opens
    /// its Project Settings popover for the relevant project, and resets
    /// the flag to false.
    @Published var isShowingProjectSettings = false
```

No helper methods needed — the flag is the full API.

- [ ] **Step 6: Update `ProjectDetailView`'s shortcuts and layout switch**

Open `PortyMcFolio/Views/ProjectDetailView.swift`.

**6a.** Find the `.background { ... }` block at the bottom that currently has three keyboard-shortcut buttons (around lines 260–273):

```swift
        .background {
            Button("") { toggleEditorPreview() }
                .keyboardShortcut("1", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
            Button("") { isShowingSettings = true }
                .keyboardShortcut("4", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
            Button("") { appState.setSelectedProject(nil) }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
                .allowsHitTesting(false)
        }
```

Replace with:

```swift
        .background {
            Button("") { appState.setSelectedProject(nil) }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
                .allowsHitTesting(false)
        }
        .onChange(of: appState.isShowingProjectSettings) { _, newValue in
            guard newValue else { return }
            appState.isShowingProjectSettings = false
            // Only handle the flag when WE are the visible view (project is selected).
            guard appState.selectedProject != nil else { return }
            isShowingSettings = true
        }
```

Rationale: the global ⌘9 from the app menu sets `appState.isShowingProjectSettings = true`; this view reacts when it's the visible one (a project is selected) by presenting its existing settings sheet. `⌘1` is no longer overloaded — it's the app-menu "Editor" shortcut, which sets `viewMode = .editor` directly. `⌘4` is also removed here (now belongs to the View menu's "Editor + List").

**6b.** Find the layout switch (around lines 18–75) that today has five cases (`.editor, .preview, .split, .gallery, .carousel`). Replace the whole `switch appState.viewMode { ... }` block with:

```swift
                    switch appState.viewMode {
                    case .editor:
                        MarkdownEditorView(
                            markdown: $markdown,
                            projectFolderURL: project.folderURL,
                            autoSaveDelay: appState.autoSaveDelay,
                            scrollToLinesFlash: $scrollToLinesFlash
                        )
                    case .preview:
                        MarkdownPreviewView(
                            markdown: previewBody,
                            projectFolderURL: project.folderURL,
                            project: project
                        )
                    case .splitGallery, .splitList, .splitLinks:
                        GeometryReader { geo in
                            let totalWidth = geo.size.width
                            let minEditor: CGFloat = 320
                            let minGallery: CGFloat = 320
                            let editorWidth = max(minEditor, min(totalWidth - minGallery, totalWidth * appState.splitRatio))
                            HStack(spacing: 0) {
                                MarkdownEditorView(
                                    markdown: $markdown,
                                    projectFolderURL: project.folderURL,
                                    autoSaveDelay: appState.autoSaveDelay,
                                    scrollToLinesFlash: $scrollToLinesFlash
                                )
                                .frame(width: editorWidth)

                                SplitDivider(
                                    ratio: $appState.splitRatio,
                                    containerWidth: totalWidth,
                                    minLeft: minEditor,
                                    minRight: minGallery
                                )

                                GalleryView(project: project, mode: galleryMode(for: appState.viewMode))
                                    .environmentObject(appState)
                            }
                        }
                    case .gallery, .list, .links:
                        GalleryView(project: project, mode: galleryMode(for: appState.viewMode))
                            .environmentObject(appState)
                    case .carousel:
                        CarouselView(project: project)
                            .environmentObject(appState)
                    }
```

**6c.** Add a helper function inside `ProjectDetailView` (just above the closing `}` of the struct, near the other private helpers):

```swift
    private func galleryMode(for viewMode: ViewMode) -> GalleryMode {
        switch viewMode {
        case .splitList, .list:       return .list
        case .splitLinks, .links:     return .links
        default:                       return .grid
        }
    }
```

**6d.** Update the `handlePendingSelection()` function in the same file (around line 301):

```swift
    private func handlePendingSelection() {
        let showsGallery: Set<ViewMode> = [.splitGallery, .gallery, .splitList, .list]
        let showsLinks: Set<ViewMode> = [.splitLinks, .links]

        if appState.pendingFileSelection != nil, !showsGallery.contains(appState.viewMode) {
            appState.viewMode = .splitGallery
        }
        if appState.pendingLinkID != nil, !showsLinks.contains(appState.viewMode) {
            appState.viewMode = .splitLinks
        }
    }
```

**6e.** Update the toolbar (around lines 186–231). The 5 buttons keep their current shape and icons but target the new cases per the spec:

Find each button and update its `viewMode =` assignment + `==` comparison to match this map:

| Old code | New code |
|---|---|
| `appState.viewMode == .editor` / `appState.viewMode = .editor` | keep |
| `appState.viewMode == .preview` / `appState.viewMode = .preview` | keep |
| `appState.viewMode = .split` / `appState.viewMode == .split` | `.splitGallery` / `.splitGallery` |
| `appState.viewMode = .gallery` / `appState.viewMode == .gallery` | keep |
| `appState.viewMode = .carousel` / `appState.viewMode == .carousel` | keep |

Specifically replace the `Split` button (around lines 200–209):

```swift
                Button {
                    appState.viewMode = .splitGallery
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 12))
                        .foregroundStyle(appState.viewMode == .splitGallery ? theme.colors.textPrimary : theme.colors.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Split view")
```

**6f.** Update `toggleEditorPreview()` to NOT be called on ⌘1 anymore (we removed that binding). The function itself can stay (it's called by the Editor/Preview toggle button at lines 187–198). No change needed to the function body.

**6g.** Update the `String` label helper at lines 376–380:

```swift
        switch appState.viewMode {
        case .editor: "Editor"
        case .preview: "Preview"
        case .splitGallery: "Editor + Gallery"
        case .gallery: "Gallery"
        case .splitList: "Editor + List"
        case .list: "List"
        case .splitLinks: "Editor + Links"
        case .links: "Links"
        case .carousel: "Carousel"
        }
```

**6h.** Update the icon helper at lines 386–390 similarly:

```swift
        switch appState.viewMode {
        case .editor: "doc.text"
        case .preview: "eye"
        case .splitGallery: "rectangle.split.2x1"
        case .gallery: "square.grid.2x2"
        case .splitList: "rectangle.split.2x1"
        case .list: "list.bullet"
        case .splitLinks: "rectangle.split.2x1"
        case .links: "link"
        case .carousel: "rectangle.stack.badge.play"
        }
```

- [ ] **Step 7: Gut `GalleryView.swift` of its internal view-mode state**

Open `PortyMcFolio/Views/GalleryView.swift`.

**7a.** Near the top of the file (line 5), the existing local enum:

```swift
enum GalleryViewMode {
    case grid, list, links
}
```

Rename it to:

```swift
enum GalleryMode {
    case grid, list, links
}
```

This is the same type `ProjectDetailView` will import. Keep it file-scoped `enum GalleryMode` (no `public`) — it's in the same module.

**7b.** On the `GalleryView` struct, remove the `@State` view-mode property. Find (around line 98):

```swift
    @State private var viewMode: GalleryViewMode = .grid
```

Delete that line.

**7c.** Add a required init parameter:

Find the struct declaration (around line 78):

```swift
struct GalleryView: View {
    let project: Project
    @Environment(\.theme) var theme
    @EnvironmentObject var appState: AppState
```

Change to:

```swift
struct GalleryView: View {
    let project: Project
    let mode: GalleryMode
    @Environment(\.theme) var theme
    @EnvironmentObject var appState: AppState
```

**7d.** Replace every `self.viewMode` / `viewMode == .grid` / `viewMode = .links` throughout the file:

- Read references (`viewMode == .list`, `viewMode == .links`, etc.) → `mode == .list`, `mode == .links`
- Write references (`viewMode = .links` at line 601) → `appState.viewMode = .splitLinks`
- Write references in the grid/list/links toolbar (line 316–318) — **delete the entire toolbar button row**. In the gallery's top bar, find the `HStack` that holds the three `toolbarIcon(...)` calls for grid/list/links and remove the whole HStack. The sort menu (which sits next to it today) stays.

After this step, run a grep to ensure there are zero remaining `viewMode` (lowercase) references inside `GalleryView.swift` that refer to the local state — only the new `mode` parameter should be read.

**7e.** Ensure Xcode-level consumers know `GalleryMode` is top-level in the same file scope. The parent `ProjectDetailView` references `GalleryMode` via `galleryMode(for:)`; both files are in the same module so the enum is visible without imports.

- [ ] **Step 8: Replace `ProjectListView`'s local ⌘4 button with an `isShowingProjectSettings` observer**

Open `PortyMcFolio/Views/ProjectListView.swift`. Find the keyboard-shortcut block around lines 188–197:

```swift
            // ⌘4 opens settings for the currently-highlighted project (keyboard wins over hover).
            Button("") {
                guard let id = highlightedProjectID,
                      let project = appState.filteredProjects.first(where: { $0.id == id })
                else { return }
                projectForSettings = project
            }
            .keyboardShortcut("4", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
```

**Delete this entire button.** The menu-level `⌘9` now handles the shortcut.

Instead, add an `.onChange` observer on the same view's body (alongside the existing `.onChange` observers, or in the same `.background` block the other shortcuts live in):

```swift
        .onChange(of: appState.isShowingProjectSettings) { _, newValue in
            guard newValue else { return }
            appState.isShowingProjectSettings = false

            // Only handle the flag when WE are the visible view (no selected project).
            guard appState.selectedProject == nil else { return }
            guard let id = highlightedProjectID,
                  let project = appState.filteredProjects.first(where: { $0.id == id })
            else { return }
            projectForSettings = project
        }
```

`ProjectDetailView`'s observer (from Step 6a) only handles the flag when a project IS selected; this one only handles it when no project is selected. Together they cover both contexts without overlap.

- [ ] **Step 9: Expand `AppSettingsView`'s default-view-mode pill row**

Open `PortyMcFolio/Views/AppSettingsView.swift`. Find the `workspaceSection` block's `HStack(spacing: DT.Spacing.xs)` with the 6 `pillOption` calls (lines 184–191). Replace the HStack contents with:

```swift
                HStack(spacing: DT.Spacing.xs) {
                    pillOption("Last used", AppState.DefaultViewMode.lastUsed, selection: $appState.defaultViewMode)
                    pillOption("Editor", .editor, selection: $appState.defaultViewMode)
                    pillOption("Preview", .preview, selection: $appState.defaultViewMode)
                    pillOption("Editor + Gallery", .splitGallery, selection: $appState.defaultViewMode)
                    pillOption("Gallery", .gallery, selection: $appState.defaultViewMode)
                    pillOption("Editor + List", .splitList, selection: $appState.defaultViewMode)
                    pillOption("List", .list, selection: $appState.defaultViewMode)
                    pillOption("Editor + Links", .splitLinks, selection: $appState.defaultViewMode)
                    pillOption("Links", .links, selection: $appState.defaultViewMode)
                    pillOption("Carousel", .carousel, selection: $appState.defaultViewMode)
                }
```

Wrap the HStack in a `.frame(maxWidth: .infinity, alignment: .leading)` if the row would overflow the settings-pane width; otherwise leave as-is. The existing 640pt settings frame accommodates 6 pills today; 10 may or may not wrap naturally — if they don't fit, replace `HStack` with `FlowLayout` or a `ViewThatFits`, OR break into two HStacks on two lines. For this pass, keep it a single HStack and let SwiftUI's default behavior handle overflow; adjust in a follow-up if needed.

- [ ] **Step 10: Rewrite the Keyboard Shortcuts help section in `AppSettingsView.swift`**

Find `shortcutsSection` (around line 456). Replace the whole `section("Keyboard Shortcuts") { ... }` body with:

```swift
        section("Keyboard Shortcuts") {
            subsection("Global") {
                shortcutRow("Search & Commands", "\u{2318}K")
                shortcutRow("New Project", "\u{2318}N")
                shortcutRow("Back to Projects", "\u{238B}")
            }

            subsection("View Modes (in a project)") {
                shortcutRow("Editor", "\u{2318}1")
                shortcutRow("Preview", "\u{2318}2")
                shortcutRow("Editor + Gallery", "\u{2318}3")
                shortcutRow("Gallery", "\u{2318}\u{21E7}3")
                shortcutRow("Editor + List", "\u{2318}4")
                shortcutRow("List", "\u{2318}\u{21E7}4")
                shortcutRow("Editor + Links", "\u{2318}5")
                shortcutRow("Links", "\u{2318}\u{21E7}5")
                shortcutRow("Carousel", "\u{2318}6")
                shortcutRow("Project Settings", "\u{2318}9")
            }

            subsection("Editor") {
                shortcutRow("Bold", "\u{2318}B")
                shortcutRow("Italic", "\u{2318}I")
                shortcutRow("Strikethrough", "\u{2318}\u{21E7}S")
                shortcutRow("Inline Code", "\u{2318}E")
                shortcutRow("Heading 1 / 2 / 3", "\u{2318}\u{2325}1\u{2013}3")
                shortcutRow("Insert Link", "\u{2318}\u{21E7}K")
                shortcutRow("Find", "\u{2318}F")
            }

            subsection("Gallery") {
                shortcutRow("Quick Look", "\u{2423}")
                shortcutRow("Cut File", "\u{2318}X")
                shortcutRow("Paste File", "\u{2318}V")
                shortcutRow("Go Up a Folder", "\u{2318}[")
                shortcutRow("Navigate Files", "\u{2190}\u{2191}\u{2193}\u{2192}")
            }

            subsection("Carousel") {
                shortcutRow("Previous / Next Slide", "\u{2190} / \u{2192}")
            }
        }
```

- [ ] **Step 11: Build and verify**

Run: `xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' build`

Expected: BUILD SUCCEEDED. If the build fails with "cannot find 'splitGallery'" or similar, grep for remaining old-case references (`\.split\b`, `\.carousel`) in `PortyMcFolio/` — you likely missed one.

- [ ] **Step 12: Run the full test suite**

Run: `xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' test`

Expected: TEST SUCCEEDED. Pass count should be unchanged (+0) vs. Task 1's end — Task 2 only adds view-mode behavior, no new tests beyond Task 1's 4 migration tests.

If any existing tests fail because they referenced `.split`, `.carousel=4`, etc., update them to the new cases. The test files that may need updates: `AppStateFilteredProjectsTests.swift` — search for `.split`, `.gallery`, `.carousel` usage in tests and align to new enum.

- [ ] **Step 13: Commit**

```bash
git add PortyMcFolio/App/AppState.swift \
        PortyMcFolio/App/PortyMcFolioApp.swift \
        PortyMcFolio/Views/ProjectDetailView.swift \
        PortyMcFolio/Views/GalleryView.swift \
        PortyMcFolio/Views/ProjectListView.swift \
        PortyMcFolio/Views/AppSettingsView.swift
# Only add test files if you modified them in Step 12:
# git add PortyMcFolioTests/AppStateFilteredProjectsTests.swift
git commit -m "feat(viewmode): 9-case ViewMode with ⌘1-6/⌘⇧3-5 shortcuts and ⌘9 project settings"
```

---

## Task 3: Editor heading shortcut rebind (⌘⇧1-3 → ⌘⌥1-3)

Small, focused change isolated to the editor.

**Files:**
- Modify: `PortyMcFolio/Views/MarkdownEditorView.swift`

- [ ] **Step 1: Update `performKeyEquivalent` in `MarkdownTextView`**

Open `PortyMcFolio/Views/MarkdownEditorView.swift`. Find `performKeyEquivalent(with event: NSEvent)` (around line 150–180 after the clipboard-paste fix). You'll see a variable `let hasShift = event.modifierFlags.contains(.shift)` and a big switch.

**1a.** Add an Option-key flag alongside `hasShift`. Just after the `hasShift` line:

```swift
        let hasOption = event.modifierFlags.contains(.option)
```

**1b.** Find the three heading cases in the switch:

```swift
        case ("1", true): setHeading(level: 1); return true
        case ("2", true): setHeading(level: 2); return true
        case ("3", true): setHeading(level: 3); return true
```

Replace with:

```swift
        case ("1", false) where hasOption: setHeading(level: 1); return true
        case ("2", false) where hasOption: setHeading(level: 2); return true
        case ("3", false) where hasOption: setHeading(level: 3); return true
```

The `hasShift: false + hasOption: true` combination uniquely identifies `⌘⌥<digit>` without `Shift` modifier.

- [ ] **Step 2: Build**

Run: `xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' build`

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run full test suite**

Run: `xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' test`

Expected: TEST SUCCEEDED — same count as end of Task 2.

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Views/MarkdownEditorView.swift
git commit -m "feat(editor): move heading shortcuts to ⌘⌥1/2/3"
```

---

## Manual Verification (run once after all tasks)

Build and launch:

```
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/PortyMcFolio.app
```

Walk the checklist from the spec:

**View modes**
- Open a project. Press `⌘1` → Editor. `⌘2` → Preview. `⌘3` → split (editor+gallery). `⌘⇧3` → gallery full. `⌘4` → split+list. `⌘⇧4` → list full. `⌘5` → split+links. `⌘⇧5` → links full. `⌘6` → carousel.
- Gallery no longer shows the grid/list/links toggle buttons.
- Split variants render editor on the left, secondary on the right; drag divider still works.
- Toolbar icons (Editor, Preview, Split, Gallery, Carousel) each switch to the right mode.

**Project Settings**
- `⌘9` inside a project opens the Project Settings sheet for that project.
- `⌘9` in the projects overview opens the settings sheet for the highlighted project.

**Menu**
- App menu → View: all 10 entries present with correct shortcut hints.

**Editor shortcuts**
- In the editor, select text, press `⌘⌥1` → becomes H1. `⌘⌥2` → H2. `⌘⌥3` → H3.
- `⌘⇧3` no longer sets H3 — it switches to Gallery full view.
- `⌘B`, `⌘I`, `⌘E`, `⌘⇧S`, `⌘⇧K`, `⌘F` still work as today.

**Esc**
- In a sheet (e.g. New Folder) → Esc dismisses sheet.
- In search palette → Esc closes palette.
- In project detail → Esc goes back to list.
- In project list with filter text typed → Esc clears filter.
- In project list empty state → Esc is a no-op (no crash).

**Settings UI**
- Settings → Workspace → "Default view mode": all 10 pills visible. Pick each, relaunch the app, open a project — lands on that mode.
- Settings → Help → Keyboard Shortcuts: the new list is shown, no stale `⌘1–3 headings` claim.

**Migration**
- Close the app. In Terminal: `defaults delete com.portymcfolio.app viewModeMigratedToV2 2>/dev/null; defaults write com.portymcfolio.app viewMode -int 4`.
- Relaunch. The app opens on the **Carousel** mode (legacy 4 migrated to new 8).
- Close. Relaunch again. Still on Carousel (flag is set, migration doesn't re-run).
- Change view to Editor+List (`⌘4`). Close. Relaunch. App opens on List+split (new raw 4), NOT Carousel — confirms migration didn't re-run on the user's new value.

---

## Self-Review Checklist (before merge)

- [ ] Every spec section has a task. (Enums ✓, migration ✓, menu ✓, toolbar ✓, GalleryView gut ✓, ⌘9 rebinding ✓, Esc ✓ (verified no code change needed; normalized via normative priority), DefaultViewMode picker ✓, help section ✓, heading shortcut move ✓.)
- [ ] No placeholders, no "TBD", no "similar to Task N" — every task has full code.
- [ ] All enum references on the new scheme (`splitGallery`, `gallery`, `splitList`, `list`, `splitLinks`, `links`, `carousel`) match across AppState, App, ProjectDetailView, GalleryView, AppSettingsView.
- [ ] Migration test covers: legacy 4 → new 8, legacy 0-3 untouched, second-call no-op, no-legacy-key fills flag.
- [ ] Build green at end of every task.
- [ ] Three commits: `feat(viewmode): migration helper...`, `feat(viewmode): 9-case ViewMode...`, `feat(editor): move heading shortcuts...`.
