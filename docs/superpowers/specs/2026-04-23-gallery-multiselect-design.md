# Gallery Multi-Select, Drag, Delete, Favorite

**Date:** 2026-04-23
**Status:** Design approved, spec in review

## Overview

Add multi-select to the gallery (grid and list modes) with Finder-style interactions, plus four batch operations driven from the selection: delete, move (drag-drop between folders), embed into editor, and toggle favorite. Files and folders are both selectable; links are not included in this pass.

## Goals

- Select multiple files and folders in a project's gallery (grid or list).
- Delete the selection to Trash with a single confirm dialog (⌘⌫).
- Drag the selection into any other folder in the project to move it.
- Drag the selection into the editor to create N `![[…]]` embeds at the cursor.
- Toggle favorite on selected files with a keyboard shortcut (L). Folders in the selection are ignored.

## Non-Goals

- Multi-select in the links pane. Same state type; click always replaces to a single item.
- Drag multiple items *out* of the app to Finder / other apps (only the primary drag item ships externally — acceptable limitation).
- Rubber-band / marquee selection on empty space.
- Drop onto breadcrumb path segments to move up levels.
- A dedicated "select mode" toolbar button. Interactions are implicit (⌘/⇧ modifiers).

## State Model

Replace the single-selection state in `GalleryView`:

```swift
@State private var selection: GallerySelection?
```

with:

```swift
@State private var selectedItems: Set<GallerySelection>
@State private var cursor: GallerySelection?
```

- `selectedItems` is the set acted on by delete, move, drag, favorite.
- `cursor` is the arrow-key anchor and the pivot for ⇧-click / ⇧-arrow range operations. Usually equals the most-recently-clicked item. Can be outside `selectedItems` (e.g. after ⌘-click toggles the item off, cursor stays).
- `GallerySelection` gains `Hashable` conformance (auto-synthesized; its associated values are already `Hashable`).
- `clearSelection()` sets both `selectedItems = []` and `cursor = nil`.

Helpers to keep call-sites readable:

```swift
func isSelected(_ item: GallerySelection) -> Bool
var selectedFileURLs: [URL]      // files only
var selectedFolderURLs: [URL]    // folders only
```

Existing call-sites that check `selection == .file(url)` for highlighting become `isSelected(.file(url))`.

## Interactions

### Mouse (grid + list modes)

| Action | Effect |
|---|---|
| Plain click on item | `selectedItems = {item}`, `cursor = item` |
| ⌘-click on item | Toggle item in `selectedItems`; `cursor = item` regardless of toggle direction |
| ⇧-click on item (cursor non-nil) | `selectedItems = rangeBetween(cursor, item, in: navigableSequence)`; cursor unchanged |
| ⇧-click on item (cursor nil) | Falls back to plain click |
| Click empty space | Clear selection |
| Double-click folder | Navigate into folder; clear selection (new context) |
| Double-click file | Open in default app (unchanged) |
| Drag an item in `selectedItems` (size ≥ 2) | Multi-drag (all selected) |
| Drag an item not in `selectedItems` | Replace to `{item}`, then single-drag |

### Keyboard

| Key | Effect |
|---|---|
| ↑ / ↓ / ← / → | Move cursor; `selectedItems = {cursor}` |
| ⇧ + arrow | Move cursor; extend `selectedItems` to include new cursor |
| ⌘ + ↑ / ↓ | First / last in navigable sequence; single-select result (existing behavior) |
| ⌘A | `selectedItems = Set(navigableSequence)`; `cursor = navigableSequence.last` |
| ⌘⌫ | Open batch delete confirm (if selection non-empty) |
| L | Toggle favorite on selected files (folders ignored) |
| Space | QuickLook the `cursor` item (unchanged) |
| Return | Existing open / navigate on cursor item |
| ESC | If selection non-empty → clear + return `.handled`. Else `.ignored` (propagates to `ProjectDetailView` back-to-list handler — matches the prior fix) |

### Links mode

Uses the same state. Every click replaces to `{item}` (equivalent to single-select). ⌘/⇧/⌘A are no-ops in links mode. ⌘⌫ is deferred (separate future work); L is a no-op (links aren't favorited).

## Drag & Drop

### Drag source

When the user starts a drag on item X in grid or list:

- If `X ∈ selectedItems && selectedItems.count ≥ 2`: emit a multi-item drag carrying the file/folder URLs of all selected items.
- Otherwise: replace `selectedItems = {X}` first, then single-drag.

### Payload

An array of `public.file-url` entries, one per selected file or folder URL, on the drag pasteboard.

SwiftUI's `.onDrag` closure emits one `NSItemProvider`. Two viable approaches — decide during implementation, whichever is less gnarly in practice:

1. **Single provider with multiple data representations** carrying an encoded URL list under a custom UTI plus a primary `public.file-url` (the URL of the item the user initiated the drag on). Drop destinations that know our UTI unpack all N; external destinations get the primary one.
2. **`NSViewRepresentable` wrapping the cell with direct `NSDraggingSession` / `NSPasteboardWriting`** to write N `public.file-url` entries. Standard AppKit pattern; plays nicely with internal targets; external drag still gets only the first (a documented limitation of either approach).

Ship the one that's simpler; both achieve the same UX for internal targets.

### Drop targets

| Target | Behavior |
|---|---|
| Folder tile in grid or list | Move all dragged items into the folder (see conflict rules below) |
| Editor (MarkdownTextView) | Insert N `![[filename]]` lines at the cursor. Existing `insertFileEmbeds` already handles URL arrays — no editor changes required |
| External apps (Finder etc.) | Receive only the primary item. Documented limitation; not in scope to fix |

### Conflict rules (move-into-folder)

- **Name collision** at destination → skip that single file, continue with the rest. Collect skipped count.
- **Move folder into itself or a descendant** → reject the whole drop. Toast: `"Can't move a folder into its own subtree."`
- **Selection contains the target folder** → reject the whole drop. Toast: `"Can't move a folder into itself."`
- After a move: one toast.
  - Full success: `"Moved N items to /mockups"`.
  - Partial: `"Moved K items to /mockups, M skipped (name already exists)"`.

### Delete

- Trigger: ⌘⌫ with non-empty selection.
- Confirm sheet (reuse `ConfirmationSheet`): `"Move N items to Trash?"` with primary "Move to Trash" and "Cancel".
- Use `FileManager.default.trashItem(at:resultingItemURL:)` (which the existing single-delete already uses) for each selected file and folder.
- On success: clear selection, toast `"N items moved to Trash"`. The reconciler picks up FSEvents and updates the cache.
- Partial failure: toast `"Moved K of N items; X failed."` and keep the failures selected so the user can retry or inspect.
- **Related cleanup (in the same PR):** `ProjectSettingsPopover.swift:282` uses `FileManager.removeItem` when replacing a teaser image. It's not a user-facing "delete", but aligning it to `trashItem` prevents accidental loss when a teaser is overwritten.

### Bulk favorite (L)

- Applies to selected *files* only. Folders and links in the selection are ignored silently.
- **Majority rule**: if every selected file is already favorited → unfavorite all. Otherwise → favorite all.
- One write to the project's frontmatter, not N.
- Toast: `"Favorited N items"` or `"Unfavorited N items"`.
- If zero files are in the selection → no-op. (A system beep is acceptable; a toast is not necessary.)

## Visual Feedback

- **Selected state**: existing accent-tinted background + 1pt accent stroke on each selected tile / row. Extends unchanged; just applied per-item from `isSelected(…)`.
- **Cursor vs. selection**: cursor gets a slightly heavier focus ring (`isFocused && isSelected` in the existing code). If cursor is *not* in `selectedItems`, still show the focus ring so the anchor is visible.
- **During drag**:
  - SwiftUI's default stacks the first ~3 thumbnails automatically.
  - Overlay a small count badge (e.g. `"5"` in a pill) when `selectedItems.count ≥ 2`. Position: top-right of the stack.
- **Drop target hover**: folder tile / list row gets the accent outline (existing pattern for external drops, extended to internal multi-drags).
- **Invalid drop target**: no highlight; system default "not allowed" cursor.

## Lifecycle / Edge Cases

| Event | Effect on selection |
|---|---|
| Navigate into a subfolder | Clear |
| Navigate up via breadcrumb | Clear |
| Grid ↔ list mode switch | **Keep** (same items, different view) |
| Switch to links mode | Clear |
| FSEvent deletes an item we had selected | Prune it from `selectedItems` on next render |
| Focus leaves gallery (click editor in split view) | Keep; ESC explicitly clears |
| Cursor item deleted | `cursor = nil` |
| All items in the folder disappear | Empty state renders; selection already pruned to empty |

## Testing

### Unit (XCTest)

- `rangeBetween(cursor, target, in: sequence)` — empty, same-index, forward, reverse, missing cursor.
- Move conflict detection — move-into-self, move-into-descendant, collision list.
- Favorite majority rule — all favorited, none favorited, mixed, empty.
- Selection pruning — items removed from filesystem are removed from `selectedItems`.
- Payload encoding/decoding (whichever drag approach is chosen) — N file URLs round-trip.

### Integration (use `ProjectReconciler` tests as template)

- Batch move with mixed name collisions → correct moved / skipped counts, reconciler observes moves.
- Batch delete of files + folders → all end up in Trash, cache updated.
- Bulk favorite → frontmatter written once with the correct set.

### Manual

- ⌘-click, ⇧-click, ⌘A, arrow nav (plain and ⇧-extended).
- Drag preview stacking and count badge appearance at size ≥ 2.
- Drop target highlight during drag.
- ESC behavior: clears when selection non-empty; propagates to "back to project list" when empty.

## Implementation Notes

- Keep pure logic (range computation, conflict detection, favorite majority) out of view files so they're unit-testable without SwiftUI.
- `navigableSequence` already exists. Reuse it as the ordered index for range and ⌘A.
- Heavy file ops on the main thread are fine up to tens of items; if a user moves hundreds, a future enhancement can push to the reconciler queue with a progress toast — not in scope for MVP.
- Favorites storage is in the project's frontmatter (`favorites` array). A single `FrontmatterParser` write covers the batch.

## Out of Scope (Follow-Ups)

- Rubber-band / marquee selection.
- Multi-file drag *out* to Finder and other apps (would require `NSFilePromiseProvider`).
- Drop onto breadcrumb segments to move up one level.
- Multi-select in the links pane (delete, copy URL, favorite, etc.).
- Progress UI for large batch moves / deletes.
