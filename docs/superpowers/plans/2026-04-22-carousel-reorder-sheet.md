# Carousel Reorder Sheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the broken in-tray drag-to-reorder with a dedicated "Reorder Carousel" sheet that uses SwiftUI's native `List.onMove`. Tray keeps its click-to-jump + × behavior unchanged.

**Architecture:** Delete the `.onDrag`/`.onDrop` glue and its helper from `CarouselView`; add a small `arrow.up.arrow.down` button overlaid on the trailing edge of the tray; create `CarouselReorderSheet.swift` containing a `List { ForEach(...) }.onMove(...)` with thumbnail + filename rows; wire the sheet with `.sheet(isPresented:)`. Also update `CarouselView`'s `.onChange(of: project.favorites)` to preserve the currently-viewed slide across reorders (follow the same file to its new index; fall back to `clampIndex` on removal).

**Tech Stack:** SwiftUI macOS 14+ (deployment 14.0), XCTest (no new tests needed), XcodeGen for project regeneration.

**Spec:** `docs/superpowers/specs/2026-04-21-carousel-reorder-sheet-design.md`
**Branch:** `feature/media-favorites-carousel`
**Worktree:** `<repo>/.worktrees/media-favorites/`

---

## File map

| File | Change |
|---|---|
| `PortyMcFolio/Views/CarouselView.swift` | Delete broken drag (.onDrag, .onDrop, reorderFavorite(sourcePath:destIndex:)). Add `@State var isShowingReorder`. Add reorder button overlay on the tray's trailing edge. Add `.sheet(isPresented: ...)`. Replace `.onChange(of: project.favorites)` with path-preserving version. |
| `PortyMcFolio/Views/CarouselReorderSheet.swift` | **Create.** SwiftUI sheet view with header ("Reorder Carousel" + Done button), `List { ForEach(favorites, id: \.self) }.onMove`. Each row: small thumbnail (32×24) + filename. Private helper `reorderFavorites(from: IndexSet, to: Int)` that writes the rearranged favorites array to the markdown via the standard flush → read → rewrite → write → notify pattern. |
| `project.yml` | **Not modified.** XcodeGen picks up the new file via recursive source glob. |
| `PortyMcFolio.xcodeproj/project.pbxproj` | Regenerated via `xcodegen generate` in Task 3. |

## Shared commands

All commands run from the worktree: `cd <repo>/.worktrees/media-favorites`.

**Build:**
```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' -quiet build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

**Test:**
```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test 2>&1 \
  | grep -E "(Test Suite 'All tests'|failed|error:)" | tail -5
```
Expected: `Test Suite 'All tests' passed`.

**Regenerate xcodeproj:**
```bash
xcodegen generate
```
Expected: `Created project at PortyMcFolio.xcodeproj`.

**Launch built app:**
```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' -derivedDataPath build -quiet build \
  && open <repo>/.worktrees/media-favorites/build/Build/Products/Debug/PortyMcFolio.app
```

---

### Task 1: Delete the broken in-tray drag

Remove the `.onDrag`/`.onDrop` attached to thumbs and the `reorderFavorite(sourcePath:destIndex:)` helper. Leaves the app in a usable "no reorder yet" state until Task 3 adds the sheet.

**Files:**
- Modify: `PortyMcFolio/Views/CarouselView.swift`

- [ ] **Step 1: Remove `.onDrag` and `.onDrop` from the thumb view**

In `PortyMcFolio/Views/CarouselView.swift`, find the `thumb(at: index, relativePath: rel)` function (around line 247). It currently looks like:

```swift
    @ViewBuilder
    private func thumb(at index: Int, relativePath rel: String) -> some View {
        let url = project.folderURL.appendingPathComponent(rel)
        CarouselThumb(
            url: url,
            isCurrent: index == currentIndex
        )
        .onTapGesture { currentIndex = index }
        .onDrag {
            NSItemProvider(object: rel as NSString)
        }
        .onDrop(of: [.plainText], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { obj, _ in
                guard let sourcePath = obj as? String else { return }
                Task { @MainActor in
                    reorderFavorite(sourcePath: sourcePath, destIndex: index)
                }
            }
            return true
        }
        .overlay(alignment: .topTrailing) {
            ThumbRemoveButton {
                removeFavorite(at: index)
            }
            .padding(4)
        }
    }
```

Replace it with:

```swift
    @ViewBuilder
    private func thumb(at index: Int, relativePath rel: String) -> some View {
        let url = project.folderURL.appendingPathComponent(rel)
        CarouselThumb(
            url: url,
            isCurrent: index == currentIndex
        )
        .onTapGesture { currentIndex = index }
        .overlay(alignment: .topTrailing) {
            ThumbRemoveButton {
                removeFavorite(at: index)
            }
            .padding(4)
        }
    }
```

- [ ] **Step 2: Delete `reorderFavorite(sourcePath:destIndex:)`**

Still in `CarouselView.swift`, find the function (around line 295, right after `removeFavorite(at:)`). It currently looks like:

```swift
    /// Moves the favorite at `sourcePath` to `destIndex` in the ordered list.
    /// Used by the drag-to-reorder interaction on the thumbnail tray.
    private func reorderFavorite(sourcePath: String, destIndex: Int) {
        NotificationCenter.default.post(name: .markdownSaveNow, object: nil)
        guard let content = try? String(contentsOf: project.readmeURL, encoding: .utf8),
              var parsed = try? FrontmatterParser.parse(content),
              let sourceIdx = parsed.favorites.firstIndex(of: sourcePath),
              sourceIdx != destIndex
        else { return }

        var newFavs = parsed.favorites
        let item = newFavs.remove(at: sourceIdx)
        let adjustedDest = sourceIdx < destIndex ? destIndex - 1 : destIndex
        let insertAt = max(0, min(adjustedDest, newFavs.count))
        newFavs.insert(item, at: insertAt)

        parsed.favorites = newFavs
        let updated = FrontmatterParser.serialize(frontmatter: parsed)
        try? updated.write(to: project.readmeURL, atomically: true, encoding: .utf8)
        NotificationCenter.default.post(name: .markdownFileDidChange, object: project.readmeURL)
        appState.notifyProjectFileChanged(uid: project.uid)

        if currentIndex == sourceIdx {
            currentIndex = insertAt
        } else if sourceIdx < currentIndex && destIndex >= currentIndex {
            currentIndex -= 1
        } else if sourceIdx > currentIndex && destIndex <= currentIndex {
            currentIndex += 1
        }
    }
```

Delete the entire function (the comment block + the function body).

- [ ] **Step 3: Build**

Run the build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Views/CarouselView.swift
git commit -m "refactor(carousel): remove broken in-tray drag-to-reorder"
```

---

### Task 2: Path-preserving `onChange(of: favorites)`

Make the main slideshow follow the currently-viewed file to its new index after a reorder (instead of staying at the same numeric index and thus effectively jumping to a different file).

**Files:**
- Modify: `PortyMcFolio/Views/CarouselView.swift`

- [ ] **Step 1: Replace the `onChange` body**

In `CarouselView.swift`, find the `onChange(of: project.favorites)` modifier in the `body` (around line 22). It currently looks like:

```swift
        .onChange(of: project.favorites) { _, newFavorites in
            clampIndex(for: newFavorites)
        }
```

Replace with:

```swift
        .onChange(of: project.favorites) { oldFavorites, newFavorites in
            // Preserve the currently-viewed slide across reorders: if the old
            // slide's path still exists in the new list, follow it to its new
            // index. Otherwise fall through to clampIndex (mid-session removal,
            // reconciler drop, etc.).
            let currentPath: String? = oldFavorites.indices.contains(currentIndex)
                ? oldFavorites[currentIndex]
                : nil
            if let path = currentPath, let newIdx = newFavorites.firstIndex(of: path) {
                currentIndex = newIdx
            } else {
                clampIndex(for: newFavorites)
            }
        }
```

- [ ] **Step 2: Build**

Run the build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Run tests**

Run the test command.
Expected: `Test Suite 'All tests' passed`.

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Views/CarouselView.swift
git commit -m "feat(carousel): follow current slide across favorites reorder"
```

---

### Task 3: Create `CarouselReorderSheet` + wire into `CarouselView`

Create the sheet view with `List.onMove`, add the reorder button overlay on the tray, and present the sheet.

**Files:**
- Create: `PortyMcFolio/Views/CarouselReorderSheet.swift`
- Modify: `PortyMcFolio/Views/CarouselView.swift`

- [ ] **Step 1: Create `CarouselReorderSheet.swift`**

Create `PortyMcFolio/Views/CarouselReorderSheet.swift` with exactly this content:

```swift
import SwiftUI
import AppKit
import QuickLookThumbnailing

/// Sheet that lets the user reorder the project's favorites using SwiftUI's
/// native `List.onMove`. Opens from the carousel tray's reorder button.
///
/// Each drop commits live via the established flush → read → rewrite → write →
/// notify pattern, mirroring `GalleryView.toggleFavorite` / `setTeaser`.
struct CarouselReorderSheet: View {
    let project: Project
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
        }
        .frame(width: 480, height: 480)
        .background(theme.colors.background)
    }

    private var header: some View {
        HStack {
            Text("Reorder Carousel")
                .font(DT.Typography.headline)
                .foregroundStyle(theme.colors.textPrimary)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, DT.Spacing.lg)
        .padding(.vertical, DT.Spacing.md)
    }

    private var list: some View {
        List {
            ForEach(project.favorites, id: \.self) { rel in
                row(for: rel)
            }
            .onMove { from, to in
                reorderFavorites(from: from, to: to)
            }
        }
        .listStyle(.plain)
    }

    private func row(for rel: String) -> some View {
        let url = project.folderURL.appendingPathComponent(rel)
        return HStack(spacing: DT.Spacing.sm) {
            ReorderRowThumb(url: url)
            Text(rel)
                .font(DT.Typography.caption)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .frame(height: 32)
    }

    /// Applies `Array.move(fromOffsets:toOffset:)` to the favorites on disk.
    /// Matches the save pattern used by `GalleryView.toggleFavorite`.
    private func reorderFavorites(from source: IndexSet, to destination: Int) {
        NotificationCenter.default.post(name: .markdownSaveNow, object: nil)
        guard let content = try? String(contentsOf: project.readmeURL, encoding: .utf8),
              var parsed = try? FrontmatterParser.parse(content) else { return }
        parsed.favorites.move(fromOffsets: source, toOffset: destination)
        let updated = FrontmatterParser.serialize(frontmatter: parsed)
        try? updated.write(to: project.readmeURL, atomically: true, encoding: .utf8)
        NotificationCenter.default.post(name: .markdownFileDidChange, object: project.readmeURL)
        appState.notifyProjectFileChanged(uid: project.uid)
    }
}

/// Small thumbnail used in the reorder sheet's rows.
private struct ReorderRowThumb: View {
    let url: URL
    @Environment(\.theme) var theme
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .frame(width: 32, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.small))
        .task { await loadThumbnail() }
    }

    @ViewBuilder
    private var placeholder: some View {
        let kind = MediaKind.from(url: url)
        ZStack {
            Rectangle().fill(theme.colors.surfaceHover)
            Image(systemName: kind == .audio ? "waveform" : (kind == .video ? "play.rectangle" : "questionmark"))
                .font(.system(size: 10))
                .foregroundStyle(theme.colors.textTertiary)
        }
    }

    private func loadThumbnail() async {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 64, height: 48),
            scale: 2.0,
            representationTypes: .thumbnail
        )
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return }
        await MainActor.run { self.image = rep.nsImage }
    }
}
```

- [ ] **Step 2: Add `@State var isShowingReorder` and the sheet in `CarouselView`**

In `PortyMcFolio/Views/CarouselView.swift`, near the other `@State` declarations (around line 11):

```swift
    @State private var currentIndex: Int = 0
    @State private var slideImage: NSImage?
    @State private var showTray: Bool = false
    @State private var isShowingReorder: Bool = false
```

Then in `body`, attach a `.sheet` modifier after the existing modifiers. Find the `body` — it currently ends with the `.background { … }` modifier (which holds the hidden arrow-key buttons, around line 45). Append the sheet AFTER the closing `}` of `.background { }`:

```swift
        .background {
            // ←/→ navigation — bare arrows; no ScrollView to conflict.
            Button("") { step(-1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .opacity(0)
                .allowsHitTesting(false)
            Button("") { step(1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .opacity(0)
                .allowsHitTesting(false)
        }
        .sheet(isPresented: $isShowingReorder) {
            CarouselReorderSheet(project: project)
                .environmentObject(appState)
        }
```

- [ ] **Step 3: Add the reorder button overlay on the tray**

Still in `CarouselView.swift`, find the `tray` computed property (around line 223). It currently looks like:

```swift
    private var tray: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: DT.Spacing.xs) {
                    ForEach(Array(project.favorites.enumerated()), id: \.element) { index, rel in
                        thumb(at: index, relativePath: rel)
                            .id(index)
                    }
                }
                .padding(.horizontal, DT.Spacing.lg)
            }
            .frame(height: 72)
            .onChange(of: currentIndex) { _, newIndex in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
            .onAppear {
                proxy.scrollTo(currentIndex, anchor: .center)
            }
        }
        .background(theme.colors.surface.opacity(0.5))
    }
```

Wrap the whole thing in a ZStack-style overlay so the reorder button sits on the trailing edge, vertically centered, always visible when the tray is revealed:

```swift
    private var tray: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: DT.Spacing.xs) {
                    ForEach(Array(project.favorites.enumerated()), id: \.element) { index, rel in
                        thumb(at: index, relativePath: rel)
                            .id(index)
                    }
                }
                .padding(.horizontal, DT.Spacing.lg)
                // Reserve trailing space so the fixed reorder button doesn't
                // overlap the last thumb when the scroll is at the right end.
                .padding(.trailing, 40)
            }
            .frame(height: 72)
            .onChange(of: currentIndex) { _, newIndex in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
            .onAppear {
                proxy.scrollTo(currentIndex, anchor: .center)
            }
        }
        .background(theme.colors.surface.opacity(0.5))
        .overlay(alignment: .trailing) {
            reorderButton
                .padding(.trailing, DT.Spacing.sm)
        }
    }

    private var reorderButton: some View {
        Button {
            isShowingReorder = true
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Reorder Carousel")
    }
```

- [ ] **Step 4: Regenerate xcodeproj (new file added)**

Run `xcodegen generate`.
Expected: `Created project at PortyMcFolio.xcodeproj`.

- [ ] **Step 5: Build**

Run the build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Run tests**

Run the test command.
Expected: `Test Suite 'All tests' passed`.

- [ ] **Step 7: Commit**

```bash
git add PortyMcFolio/Views/CarouselReorderSheet.swift \
        PortyMcFolio/Views/CarouselView.swift \
        PortyMcFolio.xcodeproj
git commit -m "feat(carousel): reorder sheet with List.onMove"
```

---

### Task 4: End-to-end verification

Manual walkthrough to confirm the new reorder UX feels right and nothing regressed.

- [ ] **Step 1: Full build + test**

Run build and test commands. Both pass.

- [ ] **Step 2: Reorder flow**

Launch the app with the newly built binary:
```bash
open <repo>/.worktrees/media-favorites/build/Build/Products/Debug/PortyMcFolio.app
```

Open a project with 5+ favorites. Press ⌘5.

- Hover near the bottom of the carousel → tray reveals with thumbnails + a new trailing "arrow.up.arrow.down" button.
- Click the button → sheet opens titled "Reorder Carousel" with a vertical list showing a small thumbnail + filename per row.
- Drag a row to a new position via its native trailing handle (macOS shows the handle automatically). Release. The list reorders with native animation.
- Click "Done" or press Return → sheet dismisses.

- [ ] **Step 3: Persistence**

Close the sheet. Observe the main carousel tray: thumbnails now appear in the new order. The main slide should STILL show the file you were on before opening the sheet.

Quit the app. Open the project's markdown file in a text editor. Verify `favorites: [...]` reflects the new order.

- [ ] **Step 4: Click-to-jump still works**

Relaunch. ⌘5 on the same project. Hover a non-current thumbnail → click it → main slide jumps to it. (This was the behavior before — verify nothing regressed.)

- [ ] **Step 5: × still works**

Hover a thumb → × icon appears top-right → click → favorite removed, tray shrinks, current-slide-preservation kicks in (if the removed one was current, slideshow advances).

- [ ] **Step 6: Single-favorite edge case**

Unfavorite all but one file. Open ⌘5. Click the reorder button → sheet opens with exactly one row. No drag possible (native `.onMove` ignores single-row lists). Click Done — no crash.

- [ ] **Step 7: Empty carousel edge case**

Unfavorite the last file. Carousel shows empty state. Tray is not visible. Reorder button is not visible (it lives inside the tray which is hidden in the empty state). ⌘5 → empty-state hint.

- [ ] **Step 8: No commit needed**

Verification only. If any step fails, return to the relevant task and fix before declaring done.

---

## Completion checklist

- [ ] All three implementation tasks complete with green build + tests after each
- [ ] Three commits on `feature/media-favorites-carousel` (one per Task 1–3)
- [ ] Task 4 end-to-end verification passes
- [ ] Broken `.onDrag`/`.onDrop` and `reorderFavorite(sourcePath:destIndex:)` fully removed
- [ ] `CarouselReorderSheet.swift` present and rendering the native `List.onMove`
- [ ] Reorder button visible on the trailing edge of the tray when tray is revealed
- [ ] `currentIndex` correctly follows the viewed slide across reorders
