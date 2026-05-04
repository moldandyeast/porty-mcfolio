# Carousel Reorder Sheet

**Date:** 2026-04-21
**Scope:** `PortyMcFolio/Views/CarouselView.swift`, plus a new `CarouselReorderSheet.swift`.

## Summary

Replace the broken in-tray drag-to-reorder with a dedicated "Reorder Carousel" sheet. The carousel's thumbnail tray keeps its current behavior (click-to-jump, × to remove, hover-reveal). A new small button in the tray opens a sheet containing a vertical SwiftUI `List` of favorites that uses the native `.onMove` modifier — battle-tested macOS reorder with built-in drag handles and drop indicators.

The current `.onDrag` / `.onDrop` glue on the tray thumbs is deleted entirely.

## Motivation

The in-tray drag implementation (commit `b54f098`) landed via SwiftUI's `.onDrag`/`.onDrop` APIs, which are the macOS *system-wide* cross-app drag machinery (same mechanism as dragging files out to Finder). They're heavy, slow to respond, give no in-app visual feedback (no sibling shift, no drop indicator), and conflict with the `.onTapGesture` on the same view. Result: unresponsive, clunky, hard to tell what's happening.

Building a custom in-place `DragGesture` would work but is brittle in a horizontal `LazyHStack` — every sibling needs offset animations, the scroll view's own drag behavior can interfere, and accidental drags on small thumbs make click-to-jump unreliable.

A reorder sheet sidesteps all of that. `List.onMove` is the one reorder API that Just Works on macOS SwiftUI.

## Scope

**In scope:**
- New `CarouselReorderSheet` view: a sheet presenting a `List` of the project's favorites with `.onMove` to reorder.
- New "Reorder" button in the carousel's thumbnail tray that opens the sheet.
- Commit reorders live (one write per move via the existing flush → read → rewrite → write → notify pattern).
- Delete `.onDrag`/`.onDrop` + the `reorderFavorite(sourcePath:destIndex:)` helper from `CarouselView.swift`.

**Out of scope:**
- In-place drag-to-reorder in the tray. Dropped.
- Multi-select / bulk-remove inside the sheet. Not needed.
- Keyboard reorder shortcuts (⌘↑ / ⌘↓). Not needed.
- Reorder from the Gallery view. Stays Gallery's current "heart toggle" model — order is decided in the carousel.

## Design

### Entry point

A small square button in the thumbnail tray, placed at the trailing edge (right side) of the tray's internal layout so it doesn't drift when thumbs are scrolled:

- Icon: `arrow.up.arrow.down`
- Style: `.buttonStyle(.plain)`, `theme.colors.textSecondary`, 22pt tap target.
- Tooltip: "Reorder Carousel".
- Action: sets `@State var isShowingReorder = true` in `CarouselView`.

The button sits OUTSIDE the horizontal `ScrollView` (as an `overlay(alignment: .trailing)` on the outer tray frame, trailing-aligned, vertically centered in the tray's 72pt height, with `.padding(.trailing, DT.Spacing.sm)` so it clears the right edge). It stays fixed as the ScrollView content scrolls underneath. Always visible when the tray is revealed; hidden with the tray when the hover-reveal is not triggered.

### Sheet contents

```
┌──────────────────────────────────────────┐
│ Reorder Carousel              [  Done ]  │  ← header
├──────────────────────────────────────────┤
│ ≡   [thumb] photos/hero.jpg              │  ← rows, drag by anywhere
│ ≡   [thumb] videos/reel.mp4              │
│ ≡   [thumb] audio/demo.mp3               │
│ ≡   [thumb] photos/sunset.jpg            │
└──────────────────────────────────────────┘
```

- Header: title "Reorder Carousel" + "Done" button that dismisses via `@Environment(\.dismiss)`.
- List rows:
  - Leading: the native reorder drag-handle (macOS `List.onMove` provides this automatically as part of the row's trailing edge — see "SwiftUI behavior" below).
  - Small thumbnail (32×24, same `QLThumbnailGenerator` + placeholder pattern as `CarouselThumb`).
  - Filename (`DT.Typography.caption`, `textPrimary`, truncated middle).
- Row height ~44pt. Total sheet size: 480pt wide × 480pt tall (`frame(width: 480, height: 480)` on the sheet content).

### SwiftUI behavior

macOS SwiftUI `List { ForEach(...).onMove { … } }` renders each row with a drag affordance on the row's trailing side. Rows can be picked up and dropped with native animations, drop indicators, and accessibility. `.onMove` fires once per drop with an `IndexSet` of source offsets and an `Int` destination offset.

The handler calls a small `reorderFavorites(from:to:)` helper that:
1. Posts `.markdownSaveNow` (flush any pending editor typing).
2. Reads README, parses frontmatter.
3. Applies `parsed.favorites.move(fromOffsets:toOffset:)`.
4. Serializes and writes atomically.
5. Posts `.markdownFileDidChange` + `appState.notifyProjectFileChanged(uid:)`.

No new parser helpers needed — `Array.move(fromOffsets:toOffset:)` is Foundation.

### Handling `currentIndex` during reorder

When `favorites` changes, `CarouselView`'s existing `.onChange(of: project.favorites) { … clampIndex }` fires. But clamping alone can make the main slideshow jump to a different slide (e.g., user moves the current slide to the end; index stays the same but now points at a different file).

Preserve "stay with the currently-viewed slide" semantics by tracking the **path** of the currently-visible favorite before the mutation and re-syncing `currentIndex` to its new position after. Implement as:

```swift
.onChange(of: project.favorites) { old, new in
    let currentPath: String? = old.indices.contains(currentIndex) ? old[currentIndex] : nil
    if let path = currentPath, let newIdx = new.firstIndex(of: path) {
        currentIndex = newIdx   // follow the same slide to its new position
    } else {
        clampIndex(for: new)    // existing fallback (mid-session removal etc.)
    }
}
```

### Delete the broken drag

Remove from `CarouselView.swift`:
- The `.onDrag { NSItemProvider(object: rel as NSString) }` block on each thumb.
- The `.onDrop(of: [.plainText], …)` block.
- The `reorderFavorite(sourcePath:destIndex:)` function (replaced by `reorderFavorites(from:to:)`).

### Empty / single-favorite edge cases

- Zero favorites: the "Reorder" button stays hidden (the tray itself is hidden in the empty state).
- One favorite: button visible, but opening the sheet shows the single row with `.onMove` inert (native — can't move a single row). No explicit special-casing needed.

## Files touched

**New files:**
- `PortyMcFolio/Views/CarouselReorderSheet.swift` — the sheet view.

**Modified files:**
- `PortyMcFolio/Views/CarouselView.swift`:
  - Add `@State private var isShowingReorder: Bool = false`.
  - Add the reorder button in the tray (overlay on the tray frame).
  - Add `.sheet(isPresented: $isShowingReorder) { CarouselReorderSheet(project: project) … }`.
  - Replace the `.onChange(of: project.favorites)` body with the path-preserving logic above.
  - Delete `.onDrag` / `.onDrop` / `reorderFavorite(sourcePath:destIndex:)`.
- `PortyMcFolio/Views/CarouselReorderSheet.swift` — owns the new `reorderFavorites(from:to:)` helper.
- `project.yml` — unchanged (XcodeGen picks up the new file via directory glob).
- `PortyMcFolio.xcodeproj/project.pbxproj` — regenerated.

No changes to `FrontmatterParser`, `ProjectReconciler`, `Project`, `MediaKind`, or any other module.

## Testing

- **Unit tests:** none added. The reorder write path shares the same read-mutate-write pattern as existing helpers; `Array.move(fromOffsets:toOffset:)` is Foundation. The value add of a view-level test is low.
- **Manual:**
  - Open carousel with 4+ favorites. Click the Reorder button — sheet opens with a list.
  - Drag a row by its handle to a new position. Release. Close the sheet. The thumbnail tray reflects the new order and the main slide stays on the same file the user was viewing.
  - Drag the currently-viewed slide to the end. `currentIndex` follows. Slide doesn't switch.
  - Open the project's markdown in a text editor. `favorites:` reflects the new order.
  - With one favorite, open the sheet — single row, no drag possible. Close. No crash.

## Rollout & revert

Strictly additive. `git revert -m 1 <merge-sha>` of the eventual merge undoes both the reorder-sheet addition and the deletion of the broken drag. Since the current drag doesn't work, reverting the whole merge to get the broken drag back isn't useful — but the revert story stays clean.

No frontmatter schema changes. No migration needed.
