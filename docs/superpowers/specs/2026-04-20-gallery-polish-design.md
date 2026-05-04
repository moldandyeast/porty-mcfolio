# Gallery Polish — Design Spec

**Date:** 2026-04-20
**Status:** design approved pending user review
**Scope:** Visual + interaction overhaul of the Gallery view (grid + list), two Cleanup bug fixes, better keyboard navigation.

## Goal

The Gallery is the user's primary surface for browsing project files, dragging them into the markdown editor, and curating content into subfolders. Today it feels dated (Finder-ish cells), long filenames truncate badly, there is no sort control, the list view has no thumbnails, selection is visually weak, and arrow-key navigation treats a 2-D grid as a 1-D list. Cleanup also occasionally renders the wrong file because of a stale-thumbnail callback race.

This spec addresses every one of those issues in a single scoped change. Direction **A** from brainstorming — modernize in place, keep grid and list as distinct views.

## Non-goals

- No responsive thumbnail sizing. Thumbnails stay at fixed dimensions for this change; responsive sizing can come later if desired.
- No new view modes (no unified icon-slider view, no persistent preview pane).
- No multi-select.
- No changes to the links subview beyond keyboard navigation.
- No rewrite of the Cleanup flow's layout — only the two targeted bug fixes.
- No fix for folder-delete leaving dangling `![[folder/file]]` embeds in the readme (flagged as follow-up).

## Affected files

- [PortyMcFolio/Views/GalleryView.swift](../../../PortyMcFolio/Views/GalleryView.swift) — grid cell builder, list row usage, toolbar, sort state, keyboard handlers, Cleanup sparkles-button index.
- [PortyMcFolio/Views/GalleryItemView.swift](../../../PortyMcFolio/Views/GalleryItemView.swift) — new card chrome, filename treatment, extension badge.
- [PortyMcFolio/Views/GalleryListView.swift](../../../PortyMcFolio/Views/GalleryListView.swift) — leading thumbnail, selection bar, filename treatment.
- [PortyMcFolio/Views/CleanupPopup.swift](../../../PortyMcFolio/Views/CleanupPopup.swift) — stale-callback guard.
- New: `PortyMcFolio/Services/FilenameDisplay.swift` — pure helper for prefix stripping. Small and testable.
- New: `PortyMcFolio/Services/GallerySort.swift` — pure helper for sort comparator + folders-first rule. Small and testable.
- `PortyMcFolioTests/FilenameDisplayTests.swift`
- `PortyMcFolioTests/GallerySortTests.swift`

No `project.yml` changes.

## 1. Grid cell redesign

Each grid cell becomes a surface card rather than a floating thumbnail + centered caption.

**Structure**
- Outer container: `RoundedRectangle(cornerRadius: DT.Radius.medium)` filled with `DT.Colors.surface`, stroked with 0.5pt `DT.Colors.border`.
- Top region: thumbnail area, fixed at 140×100 (unchanged dimensions). Corner-clipped at the top; `aspectRatio(.fit)` with the surface color letterboxing.
- Bottom region: filename strip, ~28pt tall, left-aligned (not centered), `DT.Typography.caption`, single line, `.truncationMode(.middle)`.

**Filename treatment (prefix stripping)**
- Compute `displayPrefix = "\(project.year)_\(Slug.underscoreFrom(project.title))_"` once per project (matches the prefix the Cleanup flow already uses when renaming).
- `FilenameDisplay.display(name:prefix:)` returns `String(name.dropFirst(prefix.count))` iff `name.hasPrefix(prefix)`, otherwise returns `name` unchanged.
- Apply in grid cell label and list row filename. Full on-disk name is always used for tooltips, context menu labels, and drag payloads.

**Extension badge**
- Small uppercase pill in the bottom-right of the thumbnail area, floating over the image.
- Text: `fileURL.pathExtension.uppercased()` truncated to max 4 chars (e.g. `JPG`, `MP4`, `USDZ`).
- Style: `DT.Typography.micro`, `DT.Colors.textSecondary`, `DT.Colors.surface.opacity(0.85)` bg, `DT.Radius.small` corner, 4pt horizontal padding, 1pt vertical padding.
- Suppressed when extension is empty.

**Teaser star** — unchanged (existing top-right overlay).

**States**
- Idle: `surface` fill, 0.5pt `border`.
- Hover: `surfaceHover` fill, 0.5pt `border`.
- Selected: `accent.opacity(0.12)` fill, 1pt `accent` border, `DT.Shadow.card` applied to the card.
- Cut: `.opacity(0.4)` on the entire cell (unchanged behavior).

## 2. List row redesign

The SF-symbol icon column is replaced by a real thumbnail; filename uses the same prefix-stripping rule as the grid.

**Structure (file rows)**
- Leading thumbnail: 32×32, `RoundedRectangle(cornerRadius: DT.Radius.small)` clip, `surfaceHover` letterbox background. Generate via the same `QLThumbnailGenerator.Request` helper used by the grid; request size 64×64 @2x.
- Fallback: existing SF-symbol icon logic (`doc.richtext`, `film`, `waveform`, `photo`, `doc`) centered in the 32×32 slot while the thumbnail loads or if generation fails.
- Filename column: single line, middle-truncation, prefix-stripped (see §1). Tooltip shows full name.
- Size (70pt trailing) and date (90pt trailing) unchanged.
- Divider inset updated so the hairline starts at the leading edge of the filename column (today's `46` was tuned for a 20pt icon; with a 32pt thumb and a 2pt leading accent bar it becomes `DT.Spacing.lg + 2 + DT.Spacing.md + 32 + DT.Spacing.md = 74`).

**Folder rows**
- Keep the folder SF-symbol at the same 32×32 slot for visual parity with file rows.
- No size column (unchanged).

**States**
- Idle: transparent bg.
- Hover: `surfaceHover`.
- Selected: `accent.opacity(0.12)` background + a 2pt `DT.Colors.accent` bar flush to the leading edge of the row.
- Cut: `.opacity(0.4)` (unchanged).

## 3. Sort controls

**Keys** — exactly two:
- **Name** — case-insensitive localized comparison, identical to today's sort.
- **Kind** — group by extension category, tie-breaking on name.

Kind categories (derived from `pathExtension.lowercased()`):
- `image` → `jpg jpeg png gif svg webp avif heic`
- `video` → `mp4 mov avi mkv m4v`
- `audio` → `mp3 wav aac m4a flac aiff`
- `doc`   → `pdf md txt rtf doc docx`
- `3d`    → `usdz obj stl dae scn`
- `other` → anything else

Category ordering (when sorting by Kind, ascending): `image, video, audio, doc, 3d, other`. Descending reverses.

**Folders-first rule** — always. Folders are sorted among themselves by the same key (folders have no extension, so sorting by Kind falls back to name order). Files sort among themselves. Folders always render before files.

**Placement** — new `galleryAction` icon `arrow.up.arrow.down` in the bottom toolbar, inserted between the action cluster (add/new folder/sparkles) and the view-mode separator. Tapping it presents an SwiftUI `Menu` with two sections:
- Sort by: Name (✓), Kind
- Order: Ascending (✓), Descending

The active selection in each section shows a checkmark.

**Persistence**
- UserDefaults key `gallerySortKey`, encoded as `"<key>-<dir>"` (e.g. `"name-asc"`, `"kind-desc"`).
- Loaded on `GalleryView.onAppear` into a `@State private var sortKey: GallerySortKey = .nameAsc`.
- Saved via `didSet` on the state.
- Default: `name-asc` (matches current behavior so nothing moves on first launch).
- Global across projects and across views (grid and list read the same key).

**Applies to** — files and folders in grid + list. **Not** applied to the links list (links retain oldest→newest by creation date, which is their intended model).

## 4. Selection and hover states

Centralized rules — see §1 and §2 for per-view application.

| State    | Grid cell                                                              | List row                                                                    |
| -------- | ---------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| Idle     | `surface` + 0.5pt border                                               | transparent                                                                 |
| Hover    | `surfaceHover` + 0.5pt border                                          | `surfaceHover`                                                              |
| Selected | `accent.opacity(0.12)` + 1pt accent border + `DT.Shadow.card`          | `accent.opacity(0.12)` + 2pt leading accent bar                             |
| Cut      | `.opacity(0.4)` (over any of the above)                                | `.opacity(0.4)` (over any of the above)                                     |

**Folder selection** — folders become single-click-selectable in both grid and list (today they are not). Single-click selects the folder (shows selection state); double-click still enters the folder. This aligns with file behavior and unblocks keyboard navigation through folders.

**Focus ring** — when `GalleryView` has keyboard focus (the `.focusable()` modifier already present), draw a 1pt `accent` ring around the currently selected item only. Implementation: a view modifier that overlays a stroke when `isFocused && isSelected`. The ring vanishes when focus leaves the gallery (e.g. user clicks into the editor).

**Hover timing** — instant, no animation.

## 5. Cleanup popup bug fixes

### 5a. Stale thumbnail callback race

**Problem** — [CleanupPopup.swift:274-288](../../../PortyMcFolio/Views/CleanupPopup.swift#L274) `loadCurrentFile` fires `QLThumbnailGenerator.generateBestRepresentation` and assigns the result to `@State private var thumbnail` in the completion handler without checking whether the user has advanced to a different file. Hitting `⌘→` faster than thumbnails generate causes the previous file's image to paint on top of the new file's filename input.

**Fix** — capture the target URL at request time; compare to the current file in the callback before assigning:

```swift
let targetURL = file
QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
    DispatchQueue.main.async {
        guard self.currentFile == targetURL else { return }
        thumbnail = rep?.nsImage
    }
}
```

### 5b. Sparkles toolbar button ignores selection

**Problem** — [GalleryView.swift:148-150](../../../PortyMcFolio/Views/GalleryView.swift#L148) `startCleanup()` is always called with the default `from: 0`, so clicking the sparkles button when a specific file is selected still opens Cleanup on the first file in the folder.

**Fix** — compute the start index from the current selection:

```swift
galleryAction(icon: "sparkles", help: "Clean Up") {
    let idx = selectedFileURL.flatMap { files.firstIndex(of: $0) } ?? 0
    startCleanup(from: idx)
}
```

## 6. Keyboard navigation

Rewrite `navigateSelection` and the `.onKeyPress` handlers in `GalleryView`.

**Grid mode**
- Navigable sequence = folders (in render order) followed by files (in render order).
- ←/→ move by 1 within the sequence. No wrap: at the left edge of the top row, ← is ignored.
- ↑/↓ move by `columns` where `columns = max(1, Int(floor(scrollViewWidth / 150)))`. The divisor is the grid's `minimum` (`.adaptive(minimum: 150, maximum: 180)` — SwiftUI resolves the column count as the largest N such that each column is at least 150pt wide). `scrollViewWidth` is read from a `GeometryReader` wrapping the grid container. If the row above/below is short (last row), clamp to the last valid index.
- ⌘↑ jumps to the first item; ⌘↓ jumps to the last.
- At edges, no wrap and no beep — just ignore.

**List mode**
- Navigable sequence = folders then files (same as grid).
- ↑/↓ move by 1.
- ←/→ return `.ignored`.
- Enter: if selection is a folder, enter the folder (same as double-click); if selection is a file, start Cleanup from that file (existing behavior); if selection is a link in Links mode, open in browser (existing behavior).

**Links mode**
- ↑/↓ navigate through links. `selectedLinkID` follows.
- ←/→ ignored.

**Space (QuickLook)**
- Existing behavior for files and links preserved.

**Focus ring** — as §4; follows selection regardless of type.

**Selection type** — `navigateSelection` needs to know whether the target is a folder, file, or link. Consolidate the three existing `@State` vars (`selectedFileURL`, `selectedLinkID`, and the new folder selection) behind a single enum:

```swift
enum GallerySelection: Equatable {
    case file(URL)
    case folder(URL)
    case link(String)  // link id
}
```

This is a meaningful refactor — `selectedFileURL` is read in ~12 call sites in `GalleryView.swift` (keyboard handlers, cut, delete, Cleanup start index, pending-selection consumption, QuickLook preview sync). The plan treats it as its own step so the diff is reviewable in isolation before the visual changes land on top.

The existing `@Published var pendingFileSelection` and `@Published var pendingLinkID` on `AppState` stay as the cross-view handoff surface; `consumePendingSelection` maps them into a local `GallerySelection`.

## 7. Testing

### Unit tests (pure functions)

**`FilenameDisplayTests`**
- `display(name: "2026_foo_bar_baz.mp4", prefix: "2026_foo_")` → `"bar_baz.mp4"`
- `display(name: "2026_foo_bar.mp4", prefix: "2025_foo_")` → `"2026_foo_bar.mp4"` (no strip)
- `display(name: "foo.mp4", prefix: "")` → `"foo.mp4"`
- `display(name: "2026_foo_", prefix: "2026_foo_")` → `""` (edge: name equals prefix)
- Unicode prefix: `display(name: "2026_café_x.jpg", prefix: "2026_café_")` → `"x.jpg"`

**`GallerySortTests`**
- Folders always first regardless of key/direction.
- Name asc/desc matches `localizedCaseInsensitiveCompare`.
- Kind asc orders `image` before `video` before `audio` before `doc` before `3d` before `other`.
- Kind within same category tie-breaks on name.
- Unknown extensions fall into `other`.
- Empty inputs return `([], [])`.

### Manual verification

Documented in the plan document — covers:
- Prefix stripping: create a project with one prefix-matching file and one not; confirm only the former strips.
- Grid selection visual: accent border + shadow visible on the card.
- List selection visual: 2pt leading accent bar visible.
- Focus ring: arrow-key into gallery, confirm ring follows selection; click into editor, ring disappears.
- Sort: switch name ↔ kind, asc ↔ desc; folders always first; persists across app relaunch.
- Arrow keys in grid: ↓ moves to the cell visually below (not one cell left); ↑ at top row is a no-op; ←/→ wrap across rows.
- Arrow keys in list: ↑/↓ move by 1 through folders then files; ←/→ ignored.
- Enter on a folder (list or grid) enters that folder.
- Cleanup: rapid-fire ⌘→ on a video-heavy folder; confirm no thumbnail/filename mismatch.
- Cleanup: select a file in the grid, click sparkles; confirm popup opens on that file.

### Not automated

- Thumbnail stale-callback guard. QuickLook is out-of-process; swapping the generator behind a protocol is out of proportion to the one-site use. Manual verification only.
- Hover / focus states — SwiftUI rendering; manual verification.

## 8. Rollout

Single branch off `dev/large-portfolio-perf` (or off main if that branch ships first). No feature flag — this is a UX refinement, not a behavior change the user can opt out of. Default `gallerySortKey` matches today's behavior so first launch after upgrade is visually stable.

## Follow-ups (explicitly deferred)

- Responsive grid thumbnails / size slider (direction B from brainstorming).
- Unified browse + preview pane (direction C).
- Folder-delete leaves dangling `![[folder/file]]` embeds in the readme. `trashFile` should detect a folder delete and rewrite embeds for every file below it, or at least strip them.
- Multi-select + batch operations (move many, trash many, set teaser from grid).
- Per-project sort override.
