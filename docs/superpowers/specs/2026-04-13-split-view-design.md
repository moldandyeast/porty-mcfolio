# Editor + Gallery Split View

**Date:** 2026-04-13
**Status:** Spec
**Scope:** Add a split view mode where editor and gallery appear side by side with a draggable divider

---

## Goal

Allow users to work in the editor and browse the gallery simultaneously. Three view modes: Editor, Split, Gallery. Split mode shows editor on the left and gallery on the right with a draggable divider. The user's view mode preference is persisted.

## View Modes

| Mode | Layout | When |
|------|--------|------|
| **Editor** | Full-width editor | Default for text-focused work |
| **Split** | Editor (left) + Gallery (right), draggable divider | Media-heavy projects |
| **Gallery** | Full-width gallery | Browsing/organizing files |

## UI Changes

### Toolbar Segmented Control

Replace the current 2-option `Picker` with a 3-option segmented control:

```
[ Editor | Split | Gallery ]
```

Width increases from 160pt to 240pt to accommodate the third option.

### Split View Layout

In split mode, the content area becomes an `HSplitView` (or custom equivalent):

```
┌─────────────────────────────────────────────┐
│  < Title        [ Editor | Split | Gallery ] │
├──────────────────────┬──────────────────────┤
│                      │                      │
│      EditorView      │     GalleryView      │
│                      │                      │
│                      │                      │
└──────────────────────┴──────────────────────┘
```

- **Default split**: 60% editor, 40% gallery
- **Divider**: draggable, thin (1pt line, standard macOS `HSplitView` handle)
- **Min width**: editor 300pt, gallery 200pt
- Divider position persisted alongside view mode

### Gallery Drag to Editor

In split mode, gallery file thumbnails become drag sources. Dragging a file from the gallery into the editor inserts `![[filename]]` at the drop position.

Implementation: add `.onDrag` to `GalleryItemView` providing the file URL as `NSItemProvider`. The existing `DropTargetWebView` in `EditorView.swift` already handles file drops — no editor changes needed.

## Data Model Changes

### ViewMode Enum

```swift
enum ViewMode: Int, Codable {
    case editor = 0
    case split = 1
    case gallery = 2
}
```

### Persistence

Add to `AppState`:
- `viewMode: ViewMode` — stored in `UserDefaults` under key `"viewMode"`
- `splitRatio: CGFloat` — stored in `UserDefaults` under key `"splitRatio"`, default `0.6`

These are global preferences (not per-project) to keep things simple.

## Files Changed

| File | Change |
|------|--------|
| `PortyMcFolio/Views/ProjectDetailView.swift` | Replace 2-tab picker with 3-mode segmented control; add HSplitView for split mode |
| `PortyMcFolio/App/AppState.swift` | Add `viewMode` and `splitRatio` with UserDefaults persistence |
| `PortyMcFolio/Views/GalleryView.swift` | Add `.onDrag` to `GalleryItemView` for file thumbnails |

## What Does NOT Change

- `EditorView.swift` — already handles file drops via `DropTargetWebView`
- Editor JS/CSS — no changes
- Gallery scanning, link cards, Quick Look — unchanged

## Edge Cases

- **Window too narrow for split**: if window width < 500pt, split mode falls back to editor-only with a badge indicating gallery is hidden
- **Resize preserves ratio**: dragging the divider updates `splitRatio` which persists
- **Mode switch preserves state**: switching Editor → Split → Gallery doesn't reload content; views stay alive in the background
