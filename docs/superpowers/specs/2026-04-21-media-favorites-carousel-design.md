# Media Favorites + Carousel View

**Date:** 2026-04-21
**Scope:** Per-project favoriting of individual media files (images/video/audio) with a dedicated slideshow-style carousel view (⌘5).

## Summary

Add a per-project, ordered list of "favorited" media files surfaced in a new `ViewMode.carousel` slideshow view.

- **Favoriting:** users click a heart icon on media tiles in the existing Gallery view to add/remove files from the project's carousel. Heart is always visible on every media file; outline when not favorited, filled when favorited.
- **Carousel view:** new `.carousel` view mode in the detail view, bound to ⌘5 via the existing `CommandMenu("View")`, with a new toolbar icon. Displays favorites as a slideshow — one item at a time, centered, with arrow-key navigation. A persistent (always-visible) thumbnail tray at the bottom lets users click to jump and × to remove. **Drag-to-reorder is a stretch goal, not MVP.**
- **Storage:** ordered list of project-relative paths in a new `favorites:` YAML field in the project's frontmatter. Purely additive — old projects parse unchanged.
- **File tracking:** in-app renames, moves, and deletes (via Gallery / CleanupPopup) already rewrite `teaser` and body embed references through `updateReadmeReferences` / `renameFolder` in `GalleryView.swift`; the new `favorites` array plugs into the same two hooks and gets rewritten in lockstep. External (Finder-driven) moves are caught by a basename heuristic in the reconciler; external renames and deletes drop the entry silently.

Everything is strictly additive. No existing code path, shortcut, or frontmatter field is modified.

## Motivation

The current Gallery view is a file browser — neutral, complete, unfocused. For a portfolio-viewing workflow ("just to look at my files") the user wants a curated, ordered subset of media and a viewing mode that treats those files as a slideshow rather than a file tree.

The `teaser` field already lets the overview pick one representative image per project. The carousel extends that idea from "one representative" to "an ordered curated set" without touching the overview or the teaser — both fields coexist independently, and each has its own purpose.

## Scope

**In scope:**
- Per-project favorites (each project owns its own list).
- Individual file favoriting (no folders, no bulk-add).
- Three media kinds — classified by delegating to the existing `GallerySort.category(for:)` ([GallerySort.swift:27-43](PortyMcFolio/Services/GallerySort.swift:27)). Whatever `GallerySort` recognizes as `.image / .video / .audio` is favoritable.
- Heart icon in Gallery grid and list modes.
- ⌘5 carousel view (slideshow + always-visible thumbnail tray with click-to-jump and ×-to-remove).
- Reconciliation: in-app rename/move/delete rewrite favorites in lockstep with teaser; external Finder moves caught by a basename heuristic in the reconciler (MainActor-hopped write).

**Out of scope (explicit non-goals):**
- Cross-project / global carousel.
- Multiple named carousels per project.
- Per-favorite captions or notes.
- Export (slideshow video, PDF deck, web gallery).
- Autoplay video/audio. Manual click to play per item.
- "Advance on audio finish" or other auto-advance logic.
- Dedicated fullscreen mode beyond the normal detail-view frame.
- Filter / search inside the carousel.
- "Jump to slide N" number shortcuts.
- Folder-level favoriting (bulk-add all media inside a folder).
- Feature flag / runtime off-switch — revert safety comes from the additive structure and git revert, not runtime toggles.
- FSEvents `kFSEventStreamEventFlagItemRenamed` wiring for Finder-driven renames that happen while the app is closed. In-app renames (Gallery / CleanupPopup) are fully tracked; external basename-changing renames drop the favorite. Addressable later if painful in practice.
- **Drag-to-reorder thumbnails** (MVP uses click-to-jump + ×-to-remove; user can re-favorite to append at end). Post-MVP stretch goal — deferred because `LazyHStack`-horizontal reorder has known SwiftUI rough edges.
- **Hover-reveal / pin thumbnail tray** (MVP tray is always visible at the bottom). Post-MVP stretch if the always-visible version turns out to feel cluttered.
- Consolidation of `MarkdownPreviewView`'s embed classifier with `GallerySort` — tracked as a follow-up, not done here.

## Data model

### Frontmatter field

Add one optional field to `ParsedFrontmatter` and `Project`:

```swift
var favorites: [String] = []   // ordered, project-relative paths
```

YAML serialization follows the `teaser` / `hidden` pattern: **omit the field when empty**, write when non-empty as a quoted flow-style array:

```yaml
favorites: ["photos/hero.jpg", "videos/reel.mp4", "audio/demo.mp3"]
```

Parse path (in `FrontmatterParser.parse`):

```swift
let favoritesRaw = dict["favorites"] as? [Any] ?? []
let favorites = favoritesRaw.compactMap { $0 as? String }
```

The `compactMap` matches the defensive pattern `tags` already uses — non-string entries are silently dropped rather than throwing.

### Path validation

A hand-edited or malicious YAML could include absolute paths (`/Users/…/secret.jpg`) or escape attempts (`../other-project/image.jpg`). All favorite paths must be project-relative and within the project folder. Validate either during parse or during the first reconciler pass after load (whichever is simpler — I'd lean on parse so the validated list is the only one that ever reaches the UI):

```swift
func isValidFavoritePath(_ path: String) -> Bool {
    guard !path.isEmpty,
          !path.hasPrefix("/"),                       // reject absolute
          !path.hasPrefix("~"),                       // reject home-relative
          !path.contains(".."),                       // reject parent-traversal
          !path.contains("\0")                        // defensive: null byte
    else { return false }
    return true
}
```

Invalid entries are dropped during parse. An `isValidFavoritePath`-aware reconciler pass also rejects anything introduced by external editing that slipped past parse (e.g., paths added while another tool edits the YAML). Result: `project.favorites` in memory is always safe to render against `project.folderURL.appendingPathComponent(_:)`.

### MediaKind service

New file `PortyMcFolio/Services/MediaKind.swift`. To avoid a parallel, drifting extension set, `MediaKind` delegates to `GallerySort.category(for:)` ([GallerySort.swift:27-43](PortyMcFolio/Services/GallerySort.swift:27)) — the existing single source of truth for "what kind of file is this":

```swift
enum MediaKind: String {
    case image, video, audio

    static func from(url: URL) -> MediaKind? {
        switch GallerySort.category(for: url) {
        case .image: return .image
        case .video: return .video
        case .audio: return .audio
        default:     return nil   // .document, .other, etc.
        }
    }

    static func isMedia(url: URL) -> Bool {
        from(url: url) != nil
    }
}
```

Consequence: any extension `GallerySort` treats as image/video/audio is favoritable (`.svg`, `.avif`, `.tiff`, `.aiff`, `.mkv`, etc. are all included via this route). If `GallerySort` gains a new extension, the carousel picks it up automatically. Used by both Gallery (to decide whether to show the heart) and Carousel (to pick the correct renderer per slide).

**Playback-codec caveat.** Being classifiable as `.video` or `.audio` doesn't guarantee AVKit can play it — `.webm` (VP8/VP9) and `.mkv` are classifiable but not natively decoded. The slide's player falls back to AVKit's own error overlay in that case, same as any other unsupported codec. Not a new failure mode; we just inherit it.

**Implication for `MarkdownPreviewView`.** Its embed classifier hard-codes its own (slightly different) extension list at [MarkdownPreviewView.swift:113-115, 230-232](PortyMcFolio/Views/MarkdownPreviewView.swift:113). Follow-up task should consolidate against `GallerySort` — flagged in non-goals, not fixed here.

### View mode

New case in `ViewMode` enum (whichever file defines it — typically `AppState.swift` or a siblings file):

```swift
enum ViewMode {
    case editor, preview, split, gallery, carousel
}
```

All existing cases remain unchanged.

## Favoriting in Gallery view

### Heart icon

- **Placement.** Top-right corner of each media file tile in Gallery grid, top-right trailing edge in Gallery list mode.
- **Button geometry.** ~22pt circular tap target with a semi-transparent backdrop so the icon remains legible over bright images.
- **States.**
  - Not favorited: outline heart, `theme.colors.textPrimary.opacity(0.5)` foreground.
  - Favorited: filled heart, `theme.colors.accent` foreground.
  - Hover on tile: outline heart bumps to full opacity.
- **Gating.**
  - Only files where `MediaKind.isMedia(url:)` returns true get a heart.
  - Folders and non-media files render the tile without a heart button (no changes to their layout).

### Click isolation

`GalleryItemView` currently chains two `.onTapGesture` modifiers (single-tap select, double-tap open) plus `.onDrag` and `.contextMenu` at [GalleryView.swift:864-877](PortyMcFolio/Views/GalleryView.swift:864). An `.overlay { Button … }` will not reliably beat those tap gestures on macOS — the parent can still intercept depending on view ordering and hit-test precedence.

**Approach:** add the heart button via a `ZStack` wrapping the `GalleryItemView`, with the button as the topmost layer and `.contentShape(Circle())` on the button. If that still produces double-firing (parent tap + button tap), fall back to hoisting the tile's tap gestures to the ZStack level and distinguishing heart vs. tile via hit-test in a custom `.onTapGesture` handler.

**Realistic effort note.** Expect ~half a day of interaction polish here, not a one-liner. This is flagged explicitly so the implementation plan allocates accordingly.

### Toggle save path

Click on the heart:

1. **Flush** any pending editor save via `NotificationCenter.default.post(name: .markdownSaveNow, object: nil)` (same pattern `updateReadmeReferences` uses at [GalleryView.swift:1119](PortyMcFolio/Views/GalleryView.swift:1119)). Without this, unsaved editor typing in split mode could be clobbered when the frontmatter is re-serialized.
2. **Read** the README, parse frontmatter.
3. **Mutate** `parsed.favorites`:
   - If toggling on: append `relativePath(for: url)` if not already present.
   - If toggling off: remove all occurrences (order-preserving).
4. **Serialize** via `FrontmatterParser.serialize`, **write** atomically to `project.readmeURL`.
5. **Notify** via `NotificationCenter.default.post(name: .markdownFileDidChange, object: project.readmeURL)` + `appState.notifyProjectFileChanged(uid: project.uid)`.

This is the pattern used by `GalleryView.setTeaser(_:)` at [GalleryView.swift:1067-1080](PortyMcFolio/Views/GalleryView.swift:1067), adjusted to flush the editor save first (step 1). No confirmation prompt either way — the action is cheap and reversible.

**Note:** this is NOT the same as `AppState.updateProjectMetadata` at [AppState.swift:492](PortyMcFolio/App/AppState.swift:492), which takes every metadata field and runs the folder-rename logic — wrong tool for a heart click.

### Gallery list mode

Same gating and toggle behavior; heart sits as the last trailing element in the row, before any existing context-menu affordance.

### Gallery links mode

Unaffected. Links are not media files.

## Carousel view (⌘5)

### Entry

- **Shortcut — App menu.** ⌘5 is added to the existing `CommandMenu("View")` in [PortyMcFolioApp.swift:28-43](PortyMcFolio/App/PortyMcFolioApp.swift:28), alongside ⌘1 (Editor), ⌘2 (Split), ⌘3 (Gallery). Action: `appState.viewMode = .carousel`. This is a deliberate choice to keep the "View" menu complete and discoverable; it's consistent with the ⌘1/⌘2/⌘3 pattern already in that menu.
- **No hidden Button in detail view.** Unlike ⌘4 (which is a detail-only shortcut for settings), ⌘5 comes exclusively from the App menu. Avoids a double-fire with the existing ⌘1 hidden Button at [ProjectDetailView.swift:246](PortyMcFolio/Views/ProjectDetailView.swift:246) (which already has asymmetric ⌘1 semantics — documented tension that predates this feature).
- **Toolbar icon.** New icon in the detail-view toolbar, same row as the existing `.editor / .split / .gallery` icons. Symbol: `rectangle.stack.badge.play` (tentative — iterate during implementation). Click = `appState.viewMode = .carousel`.
- **Icon availability.** Icon stays always tappable. When `project.favorites` is empty, tapping/⌘5 still opens the carousel but renders the empty state (below). Tooltip on hover: "Carousel — slideshow of favorited media."
- **Entry from split mode.** `viewMode = .carousel` replaces the **entire** detail content (including split mode's editor pane), because `ProjectDetailView.body` uses a top-level `switch` on `viewMode`. Same behavior as switching from split → gallery today. Users in split mode will see the editor disappear — acceptable given the existing pattern.

### Frame layout

```
┌──────────────────────────────────────────────┐
│              filename.jpg      3 / 12        │  ← thin top row (muted)
├──────────────────────────────────────────────┤
│                                              │
│                                              │
│               [ MEDIA ITEM ]                 │  ← centered, aspect-fit
│                                              │
│                                              │
├──────────────────────────────────────────────┤
│  [thumb] [thumb] [•thumb•] [thumb] [thumb]   │  ← always-visible tray
└──────────────────────────────────────────────┘
```

- **Top row.** Current filename (truncated, centered, muted) + counter "N / Total" on the trailing side.
- **Center.** Single media item, `aspectRatio(.fit)` within available area, ~24pt padding. Background is `theme.colors.background` — no hard frame around the media.
- **Bottom.** Thumbnail tray (see next section) — always visible. Hover-reveal + pin are post-MVP stretch.

### Rendering per media kind

- **Image** — `Image(nsImage:)` loaded async via `QLThumbnailGenerator` at display resolution; cached per path (small LRU, evicted on slide change). Same QuickLook generator the rest of the app uses.
- **Video** — SwiftUI's `VideoPlayer` (AVKit) bound to an `AVPlayer(url:)`. On slide arrival, shows the poster (first frame) with a centered play-button overlay. Manual click to start. Native AVKit controls appear on hover over the video area.
- **Audio** — SwiftUI's `VideoPlayer` renders an audio-only `AVPlayer` as a *black video pane* with controls underneath on macOS — not the clean strip the first spec draft implied. Use AppKit's `AVPlayerView` wrapped in `NSViewRepresentable` instead, with `controlsStyle = .inline`:

  ```swift
  struct AudioPlayerView: NSViewRepresentable {
      let url: URL
      func makeNSView(context: Context) -> AVPlayerView {
          let v = AVPlayerView()
          v.player = AVPlayer(url: url)
          v.controlsStyle = .inline
          v.showsFullScreenToggleButton = false
          return v
      }
      func updateNSView(_ v: AVPlayerView, context: Context) {
          if (v.player?.currentItem?.asset as? AVURLAsset)?.url != url {
              v.player = AVPlayer(url: url)
          }
      }
  }
  ```

  Wrap in a card: filename shown prominently (`DT.Typography.headline`) above the transport bar. Manual click to play.

**Shared lifecycle.** Each slide owns its own `AVPlayer` instance, created on appear and released on disappear. Simple and avoids stale-player bugs. Playback is explicitly paused before navigating away (see the Slide change bullet below).

### Navigation

- **`←` / `→`** — previous / next slide. **No wrap** — stop at edges (consistent with the grid-nav contract).
- **`Space`** — no-op on images; toggles play/pause on video/audio (standard media shortcut).
- **`ESC`** — exit carousel, return to overview (same behavior as the other detail-view modes).
- **Click center** — on video/audio, toggles play/pause. On images, no-op.
- **Slide change (← / → / thumb click / ESC)** — any currently-playing media pauses.

### State

- **Current slide index.** In-memory only; not persisted to frontmatter. Fresh entry starts at index 0.
- **Out-of-bounds protection.** If `project.favorites` changes while the carousel is open (external reconciler drop, user `×`-removes a thumb, etc.), `currentSlideIndex` clamps via `.onChange(of: project.favorites)` to `min(currentSlideIndex, favorites.count - 1)`. If `favorites.count == 0`, the carousel switches to the empty state. This prevents a reconciler pass that trims a favorite at index `k ≤ currentSlideIndex` from leaving the slideshow pointing at `favorites[old-count]`.
- **Playback position.** Resets on slide change. Any currently-playing `AVPlayer` is paused before the new slide mounts.

## Thumbnail tray (MVP)

The MVP tray is **always visible** at the bottom of the carousel. No hover-reveal, no pin, no drag-to-reorder — those are post-MVP stretch goals (see Non-goals). This cuts meaningful complexity (`onContinuousHover` / `NSTrackingArea` dances, `LazyHStack`-horizontal drag-and-drop fragility, pin state coordination) without losing the core value: see all favorites, jump between them, remove from the carousel.

### Layout

- Horizontal strip, ~72pt tall, always visible at the bottom of the carousel.
- Each thumbnail: 3:2 aspect ratio, ~96pt wide, `DT.Radius.small` corners.
- Thumbs separated by `DT.Spacing.xs`.
- Horizontal `ScrollView` with `LazyHStack` (handles 100+ favorites without rendering overhead).
- Auto-scroll to center the current-slide thumb when the user navigates via ←/→ or thumb click.

### Thumb content per kind

- **Image** — `QLThumbnailGenerator` preview.
- **Video** — `AVAssetImageGenerator` first-frame thumbnail + small play glyph in the top-right.
- **Audio** — flat tile tinted `theme.colors.surfaceHover` + SF Symbol `waveform` glyph + truncated filename. (Same `waveform` symbol `GallerySort.fallbackSymbol` already uses for audio.)

### Current-item indicator

- Current thumb: 2pt accent-color stroke.
- Non-current thumbs: 0.5pt `theme.colors.border` stroke at ~30% opacity.

### Interactions (MVP)

- **Click thumb** — jump to that slide (current-index update, pause any playing media).
- **× on thumb** (visible on hover over the thumb) — removes the favorite. Same save path as the Gallery heart (see the Toggle save path section above). If the removed thumb was the current slide, the slideshow advances to the next (or previous, if removed was the last); if it was the only favorite, the carousel switches to the empty state.
- **Re-ordering (MVP):** user unfavorites + re-favorites to put an item at the end. Not elegant; is tracked as a post-MVP item. `×`-then-heart round trip is one or two clicks depending on whether they're re-adding.
- **Keyboard while tray is present** — arrow keys still navigate the main slideshow.

### Post-MVP stretch

- **Drag-to-reorder** via SwiftUI `onDrag` / `onDrop` with a string pasteboard carrying the path. Deferred because `LazyHStack`-horizontal reorder has known SwiftUI rough edges (drop-target hit-testing near scroll edges, auto-scroll-while-dragging, flicker on reorder). When we add it: visible on the full branch as its own PR, with its own verification pass.
- **Hover-reveal + pin.** Deferred unless the always-visible tray turns out to feel cluttered in real use.

## File tracking & reconciliation

### Existing in-app machinery we reuse

`GalleryView.swift` already rewrites markdown references whenever a file is modified through the app:

- **`updateReadmeReferences(oldRelative:, newRelative:)`** (line ~1112) — flushes any pending editor save, re-reads the project markdown, rewrites `parsed.teaser` if it matched `oldRelative`, rewrites body embed references `![[oldRelative]]` → `![[newRelative]]`, serializes and writes back, notifies. Called by `moveFile`, `pasteFile`, `moveDroppedFiles`, `trashFile` (with `newRelative: ""`), and the `CleanupPopup.onFileMoved` callback (which is the rename-a-file path).
- **`renameFolder()`** (line ~1225) — for folder renames, runs a prefix-rewrite over `parsed.body` (`![[oldPrefix/` → `![[newPrefix/`) and `parsed.teaser` if it starts with the old folder prefix.

These two hooks already cover every in-app file/folder mutation.

### Favorites plug into the same hooks

Two narrow additions, no new reconciler pass needed for the in-app path:

1. **`updateReadmeReferences` extension.** After the teaser rewrite block, add a favorites rewrite:

   ```swift
   // 3. Frontmatter favorites array
   if parsed.favorites.contains(oldRelative) {
       if newRelative.isEmpty {
           parsed.favorites.removeAll { $0 == oldRelative }
       } else {
           parsed.favorites = parsed.favorites.map { $0 == oldRelative ? newRelative : $0 }
       }
       changed = true
   }
   ```

2. **`renameFolder` extension.** After the teaser prefix rewrite, add a favorites prefix rewrite:

   ```swift
   let folderPrefix = "\(oldPrefix)/"
   var newFavorites: [String] = []
   var favsChanged = false
   for fav in parsed.favorites {
       if fav.hasPrefix(folderPrefix) {
           newFavorites.append("\(newPrefix)/" + fav.dropFirst(folderPrefix.count))
           favsChanged = true
       } else {
           newFavorites.append(fav)
       }
   }
   if favsChanged {
       parsed.favorites = newFavorites
       changed = true
   }
   ```

Both extensions are ~5–10 lines and pattern-match the existing teaser logic.

### External Finder operations (lower-priority path)

When files are moved/renamed in Finder while the app is running (or while it was closed), the in-app hooks don't fire. For those cases, the `ProjectReconciler` gets a new favorites pass after frontmatter load.

**Thread safety.** `ProjectReconciler` runs on a private background queue ([ProjectReconciler.swift:19](PortyMcFolio/Services/ProjectReconciler.swift:19)). The existing reconciler is read-only against README files; adding a write path from the background queue would race with MainActor editor saves, the gallery's `updateReadmeReferences`, and `AppState.updateProjectMetadata`. To keep things safe, the reconciler's favorites pass:

1. Reads the frontmatter and computes the clamped list **on the background queue** (pure computation).
2. If the list changed, **hops to MainActor** to post `.markdownSaveNow` (flush pending editor save), re-serialize, and write the README atomically. The MainActor write reuses the same code path `setTeaser` / heart-toggle uses.
3. The write triggers an FSEvent, which re-enters the reconciler — but since the frontmatter now matches disk, the second pass is a no-op. No loop.

1. **Collect** the current file tree under the project folder (relative paths to files whose extension is in `MediaKind`).
2. **For each path** in `project.favorites`:
   - Exists at current path → keep.
   - Missing, but a file with the same basename (case-insensitive) exists exactly once elsewhere in the project → update the path (catches external moves that kept the filename).
   - Missing, zero matches → drop (external delete or rename).
   - Missing, multiple matches → drop (ambiguous).
3. **De-duplicate** the list (first occurrence wins, preserves order).
4. If the list changed, re-serialize frontmatter via the existing save pipeline.

The reconciler path is a safety net. The common workflow — users renaming/moving files *inside the app* — is handled cleanly by the two hooks above.

### Rename-in-Finder limitation

External renames that change the basename (e.g., user renames `hero.jpg` → `banner.jpg` in Finder while the app is closed) can't be distinguished from delete + new-file without FSEvents `kFSEventStreamEventFlagItemRenamed` wiring. That entry drops from favorites; the user re-hearts under the new name. Acceptable given the main authoring surface is the Gallery, where renames are tracked.

### UI visibility of reconciliation

No toasts, no warnings. The user sees the updated state (new path rendered, or slot disappeared) on the next render pass. Matches how teaser behaves today.

## Edge cases

- **Empty carousel.** Centered hint: "No favorites yet — heart items in Gallery (⌘3)". Tray hidden. ⌘5 and the toolbar icon still work — they just show the empty state.
- **Single favorite.** Arrows are no-ops (no wrap). Tray shows one thumb. × on the thumb returns to empty state.
- **Current item removed.** Slideshow advances to next slide; if removed was the last, show the new-last; if only one favorite existed, switch to empty state.
- **100+ favorites.** LazyHStack in the tray renders thumbs on demand. Full-resolution center rendering happens only for the current slide.
- **Missing file at load (reconciler hasn't caught up yet).** Slide shows a grey placeholder card with "Media unavailable" + the filename. Tray thumb uses the same placeholder. Reconciler drops on next sync.
- **Unsupported codec / corrupt file.** AVKit shows its own error overlay for video/audio; image load failure falls back to the missing-file placeholder.
- **Rename or move via Gallery / CleanupPopup** (the main in-app path). `updateReadmeReferences` rewrites the favorites array in lockstep with teaser/body embeds. Tray thumbs and slides keep pointing at the right file.
- **Folder rename via Gallery.** `renameFolder` rewrites favorites entries that start with the old folder prefix, same way it rewrites teaser and body embeds.
- **External move in Finder** (basename unchanged, different folder). Reconciler's basename heuristic updates the path on next sync.
- **External rename in Finder** (basename changed, no corresponding in-app hook). Entry drops from favorites. User re-hearts under the new name. Noted in the Rename-in-Finder limitation above.
- **Hand-edited YAML pointing to a non-media file.** Parse-time validation (or reconciler's MediaKind gate) drops the entry.
- **Hand-edited YAML with absolute paths or `../` escapes.** Parse-time validation drops the entry (see Path validation above).
- **Hand-edited YAML with duplicate entries.** Parse de-duplicates (first occurrence wins, preserves order).
- **Mid-session favorites mutation.** If `project.favorites` changes while the carousel is open (reconciler trim, hand-edit, etc.), `currentSlideIndex` clamps to `min(currentSlideIndex, favorites.count - 1)` via `.onChange(of: project.favorites)`. If the list becomes empty, the carousel switches to empty state.
- **Entry from split mode.** `viewMode = .carousel` replaces the entire detail content (including the split-mode editor pane). Same switch pattern the other view modes use today.
- **Portfolio-root change.** Favorites live in each project's frontmatter. They travel with the project folder through a portfolio-root change — no extra work needed. Frontmatter-resident state is portfolio-root agnostic by design.
- **Theme switch / dark mode / window resize.** All handled implicitly via `@Environment(\.theme)` and SwiftUI layout; no special code.

## Rollout & revert safety

### Strictly additive structure

Every change is one of:
1. A **net-new file** (`CarouselView.swift`, `MediaKind.swift`, this spec, the plan).
2. A **narrow addition** to an existing file (one new case, one new field, one new overlay, etc.).

No existing code path is modified or removed. Every existing view mode, shortcut, frontmatter field, and reconciliation pass remains exactly as-is.

### Feature flag

**None.** Revert safety comes from the additive structure and git, not a runtime toggle. If the feature turns out to be wrong, `git revert -m 1 <merge-sha>` drops it as a unit. Unused `favorites: [...]` entries in user markdown after revert are harmless — the parser ignores unknown YAML keys.

### Branch strategy

- Implementation branch: `feature/media-favorites-carousel`.
- Merge to `main` with `--no-ff` so the merge commit represents the whole feature.
- Revert strategy: `git revert -m 1 <merge-sha>` returns main to pre-feature state in one commit.

### Backward compatibility

- Absence of `favorites:` → empty list. Old projects open unchanged.
- Writing `favorites:` happens only when the user actually hearts something.
- Removing the last favorite → field returns to absent (matches `teaser` / `hidden` serialization).

## Files touched

**New files (removable as a unit):**
- `PortyMcFolio/Views/CarouselView.swift`
- `PortyMcFolio/Services/MediaKind.swift`
- `docs/superpowers/specs/2026-04-21-media-favorites-carousel-design.md` (this document)
- `docs/superpowers/plans/2026-04-21-media-favorites-carousel.md` (implementation plan, written next)

**Narrow edits to existing files:**
- `PortyMcFolio/Models/Project.swift` — `favorites: [String]` property.
- `PortyMcFolio/Services/FrontmatterParser.swift` — parse line, serialize block, `isValidFavoritePath` helper, path-validation drop on parse.
- `PortyMcFolio/App/AppState.swift` — new `ViewMode.carousel` case (ViewMode lives in AppState).
- `PortyMcFolio/App/PortyMcFolioApp.swift` — ⌘5 entry in `CommandMenu("View")`.
- `PortyMcFolio/Views/GalleryView.swift` — heart-button overlay on media tiles (grid + list); favorites rewrite blocks added inside `updateReadmeReferences` and `renameFolder`. The heart tap-isolation may hoist tap gestures up from `GalleryItemView` (see "Click isolation" above).
- `PortyMcFolio/Views/ProjectDetailView.swift` — one new case in the view-mode `switch`, one toolbar icon.
- `PortyMcFolio/Services/ProjectReconciler.swift` — new favorites pass (basename heuristic, MainActor-hopped write) and its call site in `syncProject`. Safety-net only; in-app operations are handled by the GalleryView hooks above.

Each existing-file edit is ~5–30 lines. Every addition is localized and can be surgically removed.

## Plan decomposition

The feature is split across **two implementation plans** so that each ships independently and each yields a reviewable, shippable slice.

### Plan A — Data + Gallery hearts + scaffolding

Goal: user can heart files in Gallery and see the heart-state persist in markdown. Carousel view exists in the toolbar/menu but shows an empty-state placeholder. Ships even without Plan B — the data model is correct and `updateReadmeReferences` keeps favorites in sync with file operations.

Tasks (~6):
1. `MediaKind` service + tests (delegates to `GallerySort`).
2. `Project.favorites` + `FrontmatterParser` parse/serialize + `isValidFavoritePath` + round-trip tests (absent, present, invalid paths dropped, dupes de-duped on parse).
3. `updateReadmeReferences` + `renameFolder` favorites rewrite extensions + tests.
4. Heart icon in Gallery grid (with the tap-isolation strategy from the Click Isolation section). Manual interaction test.
5. Heart icon in Gallery list.
6. `ViewMode.carousel` + `PortyMcFolioApp` `CommandMenu("View")` ⌘5 entry + `ProjectDetailView` toolbar icon + empty-state placeholder inside `ProjectDetailView`'s switch. No `CarouselView.swift` content yet.

### Plan B — CarouselView proper + reconciler safety net

Goal: favorites render as a slideshow with click-to-jump, ×-to-remove, arrow-key nav, ESC exit, filename header, counter, and always-visible thumbnail tray. External moves caught by the reconciler.

Tasks (~5):
1. `CarouselView.swift` skeleton — empty state, image rendering, ←/→ nav, ESC exit, counter, filename header. Clamp protection against mid-session `favorites` changes.
2. Video rendering via `VideoPlayer` (manual click to start, pause on slide change).
3. Audio rendering via `AudioPlayerView` (`NSViewRepresentable` wrapping `AVPlayerView` with `.inline` controls).
4. Thumbnail tray — always visible, click-to-jump, × to remove, `LazyHStack` for perf, auto-scroll to center current.
5. Reconciler favorites pass — basename heuristic, MainActor-hopped write, validation on parse, dedup. Tests for each reconciler outcome.

### Stretch (post-MVP, not part of either plan)

- Drag-to-reorder thumbnails.
- Hover-reveal tray with pin toggle.
- Full FSEvents `kFSEventStreamEventFlagItemRenamed` support for Finder-initiated renames while the app is closed.
- `MarkdownPreviewView` extension-classifier consolidation with `GallerySort`.

Each stretch item gets its own spec + plan if/when we decide to pick it up.

## Testing

XCTest covers the pure helpers well. Manual passes cover the SwiftUI layout and playback.

**Unit tests:**
- `MediaKind.from(url:)` — delegates correctly to `GallerySort.category(for:)` for each kind; returns nil for `.document` / `.other`; no parallel extension list maintained.
- `FrontmatterParser` — round-trips with favorites absent, present, mixed string/non-string (non-strings dropped), empty-after-parse omits the key on serialize.
- Path validation — absolute paths dropped, `../` escapes dropped, empty strings dropped, null-byte entries dropped.
- `updateReadmeReferences` favorites rewrite — matching entry rewritten, non-matching entries unchanged, trash (`newRelative == ""`) removes matching entries, multiple matches all rewritten/removed.
- `renameFolder` favorites prefix rewrite — entries under the old folder prefix get rewritten, entries outside stay as-is, folder with no favorite descendants is a no-op.
- Reconciler's basename heuristic (pure-function extract for testability) — external move (same basename) updates path, external delete drops entry, external rename drops entry (indistinguishable from delete), ambiguous case (multiple basename matches) drops entry, `MediaKind`-rejected entry dropped, de-duplication preserves first occurrence and original order.

**Manual (Plan A scope):**
- Heart toggle in Gallery grid + list, for each media kind. Favoriting a non-media file: heart doesn't appear. Heart on a folder: doesn't appear.
- ⌘5 from a project with no favorites → empty-state placeholder.
- Editor-open-with-unsaved-edits + heart click → unsaved edit preserved (pre-save flush works).
- Move/rename/trash a favorited file via Gallery drag / CleanupPopup / trash → `favorites` entry updated or removed in markdown; verify by inspecting the file and reopening the project.
- Rename a folder containing favorited files via Gallery → all affected entries rewritten.

**Manual (Plan B scope):**
- ⌘5 with one favorite → arrows no-op (no wrap), tray shows one thumb, × → empty state.
- ⌘5 with multiple favorites → ←/→ navigates, ESC exits.
- Video slide → click to play; slide change pauses it.
- Audio slide → `AVPlayerView` compact strip renders (no black video pane); click to play; slide change pauses it.
- Mid-session reconciler drop → carousel clamps `currentSlideIndex`, doesn't go out of bounds.
- Move a favorited file in Finder while app runs (same basename, different folder) → basename heuristic in reconciler updates the path on next sync.
- Rename a favorited file in Finder (basename change) → tray entry disappears (external-rename limitation; re-heart under new name).
- Delete a favorited file in Finder → tray entry disappears, slideshow advances if current.
- Enter carousel from split mode → editor pane is replaced by carousel (same switch pattern as gallery today).
- Theme switch (porty / osx / bw) × light/dark — carousel legible and consistent.
- 50+ favorites — tray scrolls smoothly, center renders only current.
