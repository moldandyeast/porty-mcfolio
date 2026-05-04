# Media Favorites — Plan B (CarouselView + Reconciler Safety Net)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the real `CarouselView` slideshow (image, video, audio rendering + always-visible thumbnail tray + navigation) and add a reconciler safety-net pass that catches favorites whose files were moved in Finder while the app was closed. Replaces the Plan A `CarouselPlaceholderView`.

**Architecture:** New `PortyMcFolio/Views/CarouselView.swift` owns the slideshow UI — centered media-kind renderer + filename header + counter + thumbnail tray. Each slide owns its own `AVPlayer` (created on appear, released on disappear). `AudioPlayerView.swift` wraps AppKit's `AVPlayerView` via `NSViewRepresentable` because SwiftUI's `VideoPlayer` renders audio-only tracks as an ugly black pane. The reconciler gains a pure-function `FavoritesReconciliation.reconcile(favorites:onDiskPaths:)` helper + integration inside `syncProject`; the helper is fully unit-tested and the integration writes frontmatter from the reconciler queue (the narrow editor-save race is tolerated — see Task 5).

**Tech Stack:** SwiftUI macOS 14+ (deployment 14.0), AVKit (`VideoPlayer`, `AVPlayer`, `AVPlayerView`), AppKit (`NSViewRepresentable`), QuickLookThumbnailing (`QLThumbnailGenerator`), XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-04-21-media-favorites-carousel-design.md`
**Plan A:** `docs/superpowers/plans/2026-04-21-media-favorites-plan-a.md` (already shipped in this branch)
**Branch:** `feature/media-favorites-carousel`
**Worktree:** `<repo>/.worktrees/media-favorites/`

---

## File map

| File | Change |
|---|---|
| `PortyMcFolio/Views/CarouselView.swift` | **Create.** Full slideshow view — media renderer, filename header, counter, ←/→ nav, thumbnail tray, × to remove, click-to-jump. |
| `PortyMcFolio/Views/AudioPlayerView.swift` | **Create.** `NSViewRepresentable` wrapping `AVPlayerView` with `.inline` controls for audio-only playback. |
| `PortyMcFolio/Services/FavoritesReconciliation.swift` | **Create.** Pure-function helper: `reconcile(favorites:onDiskPaths:) -> [String]`. Fully unit-tested. |
| `PortyMcFolioTests/FavoritesReconciliationTests.swift` | **Create.** Covers exact match, basename move, delete, rename-as-delete, ambiguous drop, dedup, order preservation. |
| `PortyMcFolio/Services/ProjectReconciler.swift` | Modify. In `syncProject`, after frontmatter parse, reconcile favorites against on-disk media paths. If changed, write back. |
| `PortyMcFolio/Views/ProjectDetailView.swift` | Modify. Route `.carousel` to `CarouselView(project:)` instead of `CarouselPlaceholderView(project:)`. Delete the placeholder struct. |
| `PortyMcFolio/App/AppState.swift` | Modify. Add `case carousel` to `DefaultViewMode` enum. |
| `PortyMcFolio/Views/AppSettingsView.swift` | Modify. Add "Carousel" pill to the default-view-mode picker. |
| `project.yml` | **Not modified.** XcodeGen's recursive sources pattern picks up new files automatically. |
| `PortyMcFolio.xcodeproj/project.pbxproj` | Regenerated via `xcodegen generate` when new files are added (Tasks 1, 3, 5). |

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
Expected: `Created project at PortyMcFolio.xcodeproj`. Commit the resulting `project.pbxproj` delta.

**Launch built app:**
```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' -derivedDataPath build -quiet build \
  && open <repo>/.worktrees/media-favorites/build/Build/Products/Debug/PortyMcFolio.app
```

---

### Task 1: `CarouselView` skeleton — empty state, image rendering, nav, clamp

Scaffold the view with an empty state, image slide rendering, ←/→ navigation, counter, filename header, and clamp-on-favorites-mutation protection. Replaces `CarouselPlaceholderView`. Video and audio come in Tasks 2 and 3. Thumbnail tray comes in Task 4.

**Files:**
- Create: `PortyMcFolio/Views/CarouselView.swift`
- Modify: `PortyMcFolio/Views/ProjectDetailView.swift`

- [ ] **Step 1: Create `CarouselView.swift`**

Create `PortyMcFolio/Views/CarouselView.swift`:

```swift
import SwiftUI
import QuickLookThumbnailing

struct CarouselView: View {
    let project: Project
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme

    @State private var currentIndex: Int = 0
    @State private var slideImage: NSImage?

    var body: some View {
        ZStack {
            if project.favorites.isEmpty {
                emptyState
            } else {
                slideshowBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.background)
        .onChange(of: project.favorites) { _, newFavorites in
            clampIndex(for: newFavorites)
        }
        .onAppear {
            clampIndex(for: project.favorites)
            loadCurrentSlide()
        }
        .onChange(of: currentIndex) { _, _ in
            loadCurrentSlide()
        }
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
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: DT.Spacing.md) {
            Image(systemName: "rectangle.stack.badge.play")
                .font(.system(size: 48))
                .foregroundStyle(theme.colors.textTertiary)
            Text("No favorites yet")
                .font(DT.Typography.title)
                .foregroundStyle(theme.colors.textPrimary)
            Text("Click the heart on media files in Gallery (⌘3) to build your carousel.")
                .font(DT.Typography.body)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Slideshow

    private var slideshowBody: some View {
        VStack(spacing: 0) {
            header
            slide
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
        }
    }

    private var header: some View {
        HStack {
            Text(currentFilename)
                .font(DT.Typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .center)
            Text("\(currentIndex + 1) / \(project.favorites.count)")
                .font(DT.Typography.caption)
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.trailing, DT.Spacing.lg)
        }
        .padding(.vertical, DT.Spacing.sm)
        .padding(.horizontal, DT.Spacing.lg)
    }

    @ViewBuilder
    private var slide: some View {
        if let url = currentSlideURL {
            switch MediaKind.from(url: url) {
            case .image:
                imageSlide(for: url)
            case .video, .audio, .none:
                // Video/audio land in Tasks 2 and 3. `.none` (non-media from
                // hand-edited YAML) shows the missing-file placeholder.
                missingPlaceholder(for: url)
            }
        } else {
            missingPlaceholder(for: nil)
        }
    }

    private func imageSlide(for url: URL) -> some View {
        Group {
            if let image = slideImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // Loading placeholder
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func missingPlaceholder(for url: URL?) -> some View {
        VStack(spacing: DT.Spacing.sm) {
            Image(systemName: "questionmark.square.dashed")
                .font(.system(size: 48))
                .foregroundStyle(theme.colors.textTertiary)
            Text("Media unavailable")
                .font(DT.Typography.body)
                .foregroundStyle(theme.colors.textSecondary)
            if let url {
                Text(url.lastPathComponent)
                    .font(DT.Typography.caption)
                    .foregroundStyle(theme.colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Slide logic

    private var currentSlideURL: URL? {
        guard currentIndex >= 0, currentIndex < project.favorites.count else { return nil }
        let rel = project.favorites[currentIndex]
        let url = project.folderURL.appendingPathComponent(rel)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private var currentFilename: String {
        guard currentIndex >= 0, currentIndex < project.favorites.count else { return "" }
        return (project.favorites[currentIndex] as NSString).lastPathComponent
    }

    private func step(_ delta: Int) {
        let newIndex = currentIndex + delta
        guard newIndex >= 0, newIndex < project.favorites.count else { return }   // no wrap
        currentIndex = newIndex
    }

    private func clampIndex(for favorites: [String]) {
        if favorites.isEmpty {
            currentIndex = 0   // irrelevant when empty; empty state renders
            slideImage = nil
        } else if currentIndex >= favorites.count {
            currentIndex = favorites.count - 1
        } else if currentIndex < 0 {
            currentIndex = 0
        }
    }

    private func loadCurrentSlide() {
        slideImage = nil
        guard let url = currentSlideURL,
              MediaKind.from(url: url) == .image
        else { return }
        Task {
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: 1600, height: 1200),
                scale: 2.0,
                representationTypes: .thumbnail
            )
            guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return }
            await MainActor.run {
                // Guard against a stale async completion landing after the user advanced.
                if self.currentSlideURL == url {
                    self.slideImage = rep.nsImage
                }
            }
        }
    }
}
```

- [ ] **Step 2: Route `.carousel` to `CarouselView` in `ProjectDetailView`**

In `PortyMcFolio/Views/ProjectDetailView.swift`, find the `.carousel` case in the top-level switch (Plan A Task 8). Replace `CarouselPlaceholderView(project: project)` with `CarouselView(project: project)`:

```swift
case .carousel:
    CarouselView(project: project)
        .frame(maxWidth: .infinity)
        .transition(.opacity)
```

Also delete the `private struct CarouselPlaceholderView` declaration that was added in Plan A Task 8 — it's dead code now.

- [ ] **Step 3: Regenerate xcodeproj**

```bash
xcodegen generate
```

- [ ] **Step 4: Build**

Run build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual smoke test**

Launch the app, open a project with at least one favorited image. Press ⌘5.
- Image loads centered, aspect-fit, with ~24pt padding.
- Filename centered in the top row; counter "N / Total" on the right.
- ←/→ navigates between slides; arrow at edge is a no-op.
- Favoriting another file via Gallery updates the count (and the current slide renders correctly).
- Unfavoriting the current slide (via Gallery's heart toggle) clamps `currentIndex` — no crash, no out-of-bounds.
- Empty favorites → empty state with "Click the heart…" copy.

- [ ] **Step 6: Commit**

```bash
git add PortyMcFolio/Views/CarouselView.swift \
        PortyMcFolio/Views/ProjectDetailView.swift \
        PortyMcFolio.xcodeproj
git commit -m "feat(carousel): CarouselView skeleton with image slides + nav"
```

---

### Task 2: Video rendering

Replace the `.video` arm of the slide switch with AVKit's `VideoPlayer` bound to an `AVPlayer`. Each slide owns its own player; pauses on slide change.

**Files:**
- Modify: `PortyMcFolio/Views/CarouselView.swift`

- [ ] **Step 1: Add the video slide view**

In `CarouselView.swift`, add the video-specific view at the bottom of the file (inside the struct, after `loadCurrentSlide()`):

```swift
    // MARK: - Video

    @ViewBuilder
    private func videoSlide(for url: URL) -> some View {
        VideoPlayerSlide(url: url)
            .id(url)  // Force re-init when the slide changes so the player resets.
    }
```

Add this private helper struct OUTSIDE `CarouselView` (bottom of the file):

```swift
import AVKit

private struct VideoPlayerSlide: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                Color.clear
            }
        }
        .onAppear {
            player = AVPlayer(url: url)
            // Manual click to play — do not call player.play() here.
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
```

Add `import AVKit` to the top of `CarouselView.swift` (right under `import SwiftUI`).

- [ ] **Step 2: Wire the video case into the switch**

In `CarouselView.swift`'s `slide` computed view, replace the `.video, .audio, .none` catch-all with:

```swift
            switch MediaKind.from(url: url) {
            case .image:
                imageSlide(for: url)
            case .video:
                videoSlide(for: url)
            case .audio, .none:
                // Audio lands in Task 3. `.none` (non-media) shows placeholder.
                missingPlaceholder(for: url)
            }
```

- [ ] **Step 3: Build**

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual smoke test**

Relaunch the app. Favorite a `.mp4` or `.mov` file. ⌘5.
- Video poster (first frame) visible.
- Native AVKit controls appear on hover: play/pause, scrubber, volume.
- Clicking play starts playback.
- Navigating to the next slide pauses the video; returning renders the poster again (not stuck at the previously-paused frame — the `.id(url)` recreates the state).

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Views/CarouselView.swift
git commit -m "feat(carousel): video rendering via AVKit VideoPlayer"
```

---

### Task 3: Audio rendering (AudioPlayerView via NSViewRepresentable)

SwiftUI's `VideoPlayer` renders audio-only `AVPlayer` as a black video pane with controls — ugly. Wrap AppKit's `AVPlayerView` in `NSViewRepresentable` with `controlsStyle = .inline` to get a compact transport bar.

**Files:**
- Create: `PortyMcFolio/Views/AudioPlayerView.swift`
- Modify: `PortyMcFolio/Views/CarouselView.swift`

- [ ] **Step 1: Create `AudioPlayerView.swift`**

```swift
import SwiftUI
import AVKit

/// `NSViewRepresentable` wrapping `AVPlayerView` with `.inline` controls.
/// Used for audio slides in the carousel — SwiftUI's `VideoPlayer` renders
/// audio-only tracks as an ugly black pane, so we drop to AppKit for this
/// specific case.
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
        // Recreate the player only when the url changes — avoids resetting
        // the scrub position on every re-render.
        let currentURL = (v.player?.currentItem?.asset as? AVURLAsset)?.url
        if currentURL != url {
            v.player = AVPlayer(url: url)
        }
    }
}
```

- [ ] **Step 2: Add the audio slide view to `CarouselView`**

In `CarouselView.swift`, add this inside the struct (next to `videoSlide(for:)`):

```swift
    // MARK: - Audio

    @ViewBuilder
    private func audioSlide(for url: URL) -> some View {
        VStack(spacing: DT.Spacing.lg) {
            Text(url.lastPathComponent)
                .font(DT.Typography.headline)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DT.Spacing.lg)
            AudioPlayerView(url: url)
                .frame(height: 44)
                .id(url)   // rebuild on slide change so transport resets
        }
        .frame(maxWidth: 480)
        .padding(DT.Spacing.xl)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: DT.Radius.medium))
    }
```

- [ ] **Step 3: Wire the audio case into the switch**

In `slide`, replace the `.audio, .none` catch-all with separate cases:

```swift
            switch MediaKind.from(url: url) {
            case .image:
                imageSlide(for: url)
            case .video:
                videoSlide(for: url)
            case .audio:
                audioSlide(for: url)
            case .none:
                missingPlaceholder(for: url)
            }
```

- [ ] **Step 4: Regenerate xcodeproj (new file)**

```bash
xcodegen generate
```

- [ ] **Step 5: Build**

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Manual smoke test**

Launch app. Favorite a `.mp3` or `.wav` file. ⌘5 and navigate to it.
- Card shows filename at top, AVKit inline transport bar below (play button, scrubber, time). NO black video pane.
- Click play → audio plays with volume on (not muted).
- Navigate away → player pauses, gets recreated when returning.

- [ ] **Step 7: Commit**

```bash
git add PortyMcFolio/Views/AudioPlayerView.swift \
        PortyMcFolio/Views/CarouselView.swift \
        PortyMcFolio.xcodeproj
git commit -m "feat(carousel): audio rendering via AVPlayerView .inline controls"
```

---

### Task 4: Thumbnail tray (always-visible, click-to-jump, × to remove)

Add the persistent thumbnail strip at the bottom of the carousel. Each thumb is ~96pt wide, 3:2 aspect, LazyHStack for perf. Click a thumb to jump; hover reveals an × that removes the favorite via the same `.markdownSaveNow` + read-mutate-write pattern used by `toggleFavorite`.

**Files:**
- Modify: `PortyMcFolio/Views/CarouselView.swift`

- [ ] **Step 1: Add tray layout to `slideshowBody`**

In `CarouselView.swift`, replace the existing `slideshowBody`:

```swift
    private var slideshowBody: some View {
        VStack(spacing: 0) {
            header
            slide
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            tray
        }
    }
```

- [ ] **Step 2: Add the tray view, thumb view, and `removeFavorite(at:)` helper**

Append these inside `CarouselView`:

```swift
    // MARK: - Thumbnail tray

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

    @ViewBuilder
    private func thumb(at index: Int, relativePath rel: String) -> some View {
        let url = project.folderURL.appendingPathComponent(rel)
        CarouselThumb(
            url: url,
            isCurrent: index == currentIndex
        )
        .onTapGesture { currentIndex = index }
        .overlay(alignment: .topTrailing) {
            // × removes this favorite — visible on hover.
            ThumbRemoveButton {
                removeFavorite(at: index)
            }
            .padding(4)
        }
    }

    private func removeFavorite(at index: Int) {
        guard index >= 0, index < project.favorites.count else { return }
        let toRemove = project.favorites[index]
        NotificationCenter.default.post(name: .markdownSaveNow, object: nil)
        guard let content = try? String(contentsOf: project.readmeURL, encoding: .utf8),
              var parsed = try? FrontmatterParser.parse(content) else { return }
        parsed.favorites = FrontmatterParser.rewritingFavorite(
            in: parsed.favorites, from: toRemove, to: ""
        )
        let updated = FrontmatterParser.serialize(frontmatter: parsed)
        try? updated.write(to: project.readmeURL, atomically: true, encoding: .utf8)
        NotificationCenter.default.post(name: .markdownFileDidChange, object: project.readmeURL)
        appState.notifyProjectFileChanged(uid: project.uid)
        // clampIndex runs via onChange(project.favorites).
    }
```

Add a `CarouselThumb` private struct OUTSIDE `CarouselView`, below `VideoPlayerSlide`:

```swift
private struct CarouselThumb: View {
    let url: URL
    let isCurrent: Bool
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
        .frame(width: 96, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.small))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.small)
                .stroke(
                    isCurrent ? theme.colors.accent : theme.colors.border.opacity(0.3),
                    lineWidth: isCurrent ? 2 : 0.5
                )
        )
        .task { await loadThumbnail() }
    }

    @ViewBuilder
    private var placeholder: some View {
        let kind = MediaKind.from(url: url)
        ZStack {
            Rectangle().fill(theme.colors.surfaceHover)
            Image(systemName: kind == .audio ? "waveform" : (kind == .video ? "play.rectangle" : "questionmark"))
                .font(.system(size: 20))
                .foregroundStyle(theme.colors.textTertiary)
        }
    }

    private func loadThumbnail() async {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 192, height: 128),
            scale: 2.0,
            representationTypes: .thumbnail
        )
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return }
        await MainActor.run { self.image = rep.nsImage }
    }
}

private struct ThumbRemoveButton: View {
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .background(Circle().fill(.black.opacity(0.6)))
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .opacity(hovering ? 1 : 0)
        .onHover { hovering = $0 }
    }
}
```

**Note on hover scope:** `ThumbRemoveButton.hovering` is local to each button, so one × per thumb, each independent. Hovering one thumb only shows its own ×.

- [ ] **Step 3: Build**

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual smoke test**

Relaunch app. Open a project with 4+ favorites. ⌘5.
- Tray visible at bottom, always. LazyHStack renders thumbs on demand as you scroll horizontally.
- Current thumb has a 2pt accent border; others have a faint 0.5pt border.
- Click a thumb → main slide jumps to that item; tray auto-scrolls to center it.
- ←/→ also scrolls the tray to keep the current thumb centered.
- Hover a thumb → × appears top-right of the thumb.
- Click × → favorite is removed from frontmatter. Tray shrinks by one; if you × the current slide, `currentIndex` clamps to the new last (via `onChange(project.favorites)`). If you × the last favorite, empty state appears.
- 50+ favorites — tray scrolls smoothly with no lag.

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Views/CarouselView.swift
git commit -m "feat(carousel): thumbnail tray with click-to-jump and × remove"
```

---

### Task 5: Reconciler safety-net pass for external Finder moves

Add a pure-function `FavoritesReconciliation.reconcile(favorites:onDiskPaths:)` helper. Wire it into `ProjectReconciler.syncProject`: after frontmatter parse, reconcile favorites against the on-disk media file tree. If the list changed, re-serialize and write frontmatter.

**Files:**
- Create: `PortyMcFolio/Services/FavoritesReconciliation.swift`
- Create: `PortyMcFolioTests/FavoritesReconciliationTests.swift`
- Modify: `PortyMcFolio/Services/ProjectReconciler.swift`

- [ ] **Step 1: Write the failing tests**

Create `PortyMcFolioTests/FavoritesReconciliationTests.swift`:

```swift
import XCTest
@testable import PortyMcFolio

final class FavoritesReconciliationTests: XCTestCase {
    func testAllEntriesExistOnDisk_unchanged() {
        let favs = ["a.jpg", "sub/b.mp4"]
        let disk: Set<String> = ["a.jpg", "sub/b.mp4", "unrelated/c.png"]
        let out = FavoritesReconciliation.reconcile(favorites: favs, onDiskPaths: disk)
        XCTAssertEqual(out, favs)
    }

    func testBasenameMatchAfterMove() {
        // "hero.jpg" used to be at root; now it's in "photos/hero.jpg".
        let favs = ["hero.jpg"]
        let disk: Set<String> = ["photos/hero.jpg"]
        let out = FavoritesReconciliation.reconcile(favorites: favs, onDiskPaths: disk)
        XCTAssertEqual(out, ["photos/hero.jpg"])
    }

    func testMissingWithNoBasenameMatch_dropped() {
        let favs = ["gone.jpg", "still.png"]
        let disk: Set<String> = ["still.png"]
        let out = FavoritesReconciliation.reconcile(favorites: favs, onDiskPaths: disk)
        XCTAssertEqual(out, ["still.png"])
    }

    func testAmbiguousBasename_dropped() {
        // Two files with the same basename — can't safely pick; drop.
        let favs = ["hero.jpg"]
        let disk: Set<String> = ["a/hero.jpg", "b/hero.jpg"]
        let out = FavoritesReconciliation.reconcile(favorites: favs, onDiskPaths: disk)
        XCTAssertEqual(out, [])
    }

    func testDedup_firstOccurrenceWins_orderPreserved() {
        let favs = ["a.jpg", "b.mp4", "a.jpg", "c.mp3"]
        let disk: Set<String> = ["a.jpg", "b.mp4", "c.mp3"]
        let out = FavoritesReconciliation.reconcile(favorites: favs, onDiskPaths: disk)
        XCTAssertEqual(out, ["a.jpg", "b.mp4", "c.mp3"])
    }

    func testDedupAfterBasenameRewrite() {
        // Both favorites match the same on-disk file after basename rewrite
        // → keep only the first rewritten, drop the duplicate.
        let favs = ["hero.jpg", "hero.jpg"]
        let disk: Set<String> = ["photos/hero.jpg"]
        let out = FavoritesReconciliation.reconcile(favorites: favs, onDiskPaths: disk)
        XCTAssertEqual(out, ["photos/hero.jpg"])
    }

    func testCaseInsensitiveBasenameMatch() {
        // macOS filesystem is usually case-insensitive; the basename heuristic
        // should be case-insensitive to match typical user filesystems.
        let favs = ["HERO.JPG"]
        let disk: Set<String> = ["photos/hero.jpg"]
        let out = FavoritesReconciliation.reconcile(favorites: favs, onDiskPaths: disk)
        XCTAssertEqual(out, ["photos/hero.jpg"])
    }

    func testOrderPreservedAcrossMixedOutcomes() {
        let favs = ["a.jpg", "moved.png", "gone.mp3", "d.mp4"]
        // moved.png exists at new path; gone.mp3 has no match
        let disk: Set<String> = ["a.jpg", "sub/moved.png", "d.mp4"]
        let out = FavoritesReconciliation.reconcile(favorites: favs, onDiskPaths: disk)
        XCTAssertEqual(out, ["a.jpg", "sub/moved.png", "d.mp4"])
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test 2>&1 | tail -10
```
Expected: compile error — `FavoritesReconciliation` doesn't exist.

- [ ] **Step 3: Create the pure helper**

Create `PortyMcFolio/Services/FavoritesReconciliation.swift`:

```swift
import Foundation

/// Pure-function reconciliation of a project's favorites against the current
/// on-disk file tree. Used by `ProjectReconciler` as a safety net for external
/// (Finder-driven) moves the app's in-app hooks didn't see.
///
/// Algorithm, per entry in order:
/// 1. If the path still exists on disk, keep it.
/// 2. Otherwise, look for a file with the same basename (case-insensitive)
///    elsewhere on disk. Exactly one match → update to the new path.
/// 3. Zero matches → drop the entry (external delete or rename).
/// 4. Multiple matches → drop the entry (ambiguous; safer than guessing).
///
/// Result is de-duplicated (first occurrence wins) while preserving original
/// order.
enum FavoritesReconciliation {
    static func reconcile(
        favorites: [String],
        onDiskPaths: Set<String>
    ) -> [String] {
        // Pre-index disk paths by lowercased basename for the heuristic.
        var byBasename: [String: [String]] = [:]
        for path in onDiskPaths {
            let basename = (path as NSString).lastPathComponent.lowercased()
            byBasename[basename, default: []].append(path)
        }

        var result: [String] = []
        var seen: Set<String> = []

        for fav in favorites {
            let resolved: String?
            if onDiskPaths.contains(fav) {
                resolved = fav
            } else {
                let basename = (fav as NSString).lastPathComponent.lowercased()
                let candidates = byBasename[basename] ?? []
                resolved = candidates.count == 1 ? candidates.first : nil
            }

            if let path = resolved, !seen.contains(path) {
                result.append(path)
                seen.insert(path)
            }
        }

        return result
    }
}
```

- [ ] **Step 4: Regenerate xcodeproj**

```bash
xcodegen generate
```

- [ ] **Step 5: Run tests — expect pass**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test 2>&1 \
  | grep -E "(FavoritesReconciliationTests|All tests)" | tail -5
```
Expected: `Test Suite 'FavoritesReconciliationTests' passed` and `Test Suite 'All tests' passed`.

- [ ] **Step 6: Wire the pass into `syncProject`**

In `PortyMcFolio/Services/ProjectReconciler.swift`, find `syncProject(uid:)`. After the frontmatter parse block (where `parsed` is produced) and BEFORE the `let meta = CachedProjectMeta(...)` construction, add a block:

```swift
        // Re-parse frontmatter
        guard let content = try? String(contentsOf: readmeURL, encoding: .utf8),
              let parsed0 = try? FrontmatterParser.parse(content) else {
            print("[Reconciler] parse failed for uid=\(uid) — leaving cache as-is")
            return
        }

        // Favorites safety net: reconcile against the on-disk file tree so
        // external Finder moves (which don't flow through updateReadmeReferences)
        // get caught. See spec for rationale; in-app moves are already handled.
        var parsed = parsed0
        if !parsed.favorites.isEmpty {
            let mediaPaths = enumerateMediaPaths(under: folderInfo.folderURL)
            let reconciled = FavoritesReconciliation.reconcile(
                favorites: parsed.favorites,
                onDiskPaths: mediaPaths
            )
            if reconciled != parsed.favorites {
                parsed.favorites = reconciled
                // Re-serialize back to disk. Written from reconciler queue;
                // the narrow race with editor's debounced save is acceptable
                // (editor re-reads disk on save, preserving our change).
                let updated = FrontmatterParser.serialize(frontmatter: parsed)
                try? updated.write(to: readmeURL, atomically: true, encoding: .utf8)
            }
        }

        let meta = CachedProjectMeta(
            ...
        )
```

(Note: the `guard let parsed = try? ...` is renamed to `parsed0` to allow a mutable copy in the reconciliation step. The original variable name referenced downstream — the existing `CachedProjectMeta` args — just reads `parsed.title`, `parsed.client`, etc., and the new `var parsed = parsed0` makes those still valid.)

Also add the `enumerateMediaPaths(under:)` helper at the bottom of the `ProjectReconciler` class (near the other private helpers):

```swift
    /// Enumerate all media files under a project folder, returning their
    /// project-relative paths. Used by the favorites reconciliation pass.
    private func enumerateMediaPaths(under folderURL: URL) -> Set<String> {
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let prefix = folderURL.path + "/"
        var result: Set<String> = []
        for case let fileURL as URL in enumerator {
            let isRegularFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            guard isRegularFile else { continue }
            guard MediaKind.isMedia(url: fileURL) else { continue }
            let rel = fileURL.path.replacingOccurrences(of: prefix, with: "")
            result.insert(rel)
        }
        return result
    }
```

- [ ] **Step 7: Build + tests**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' -quiet build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test 2>&1 \
  | grep -E "(Test Suite 'All tests'|failed|error:)" | tail -5
```
Expected: `Test Suite 'All tests' passed`.

- [ ] **Step 8: Manual smoke test**

1. Favorite 2 media files (e.g., `photos/hero.jpg` and `audio/demo.mp3`).
2. Quit the app completely.
3. In Finder, MOVE `photos/hero.jpg` to `assets/hero.jpg` (basename unchanged).
4. In Finder, DELETE `audio/demo.mp3`.
5. Relaunch the app, open the project.
6. Inspect the markdown: `favorites` should now be `["assets/hero.jpg"]` — the moved file updated, the deleted file dropped.
7. ⌘5 — carousel shows one slide, the moved image renders correctly.

- [ ] **Step 9: Commit**

```bash
git add PortyMcFolio/Services/FavoritesReconciliation.swift \
        PortyMcFolioTests/FavoritesReconciliationTests.swift \
        PortyMcFolio/Services/ProjectReconciler.swift \
        PortyMcFolio.xcodeproj
git commit -m "feat(reconciler): favorites safety-net pass for external Finder moves"
```

---

### Task 6: Add `.carousel` to `DefaultViewMode` + AppSettingsView pill

Flagged by Plan A's final code review — `DefaultViewMode` lacked `.carousel`, so users couldn't set the carousel as their default view mode for opening projects. Adding it now that the real `CarouselView` is in place.

**Files:**
- Modify: `PortyMcFolio/App/AppState.swift`
- Modify: `PortyMcFolio/Views/AppSettingsView.swift`

- [ ] **Step 1: Add `.carousel` to `DefaultViewMode`**

In `PortyMcFolio/App/AppState.swift` (around line 54):

```swift
enum DefaultViewMode: String, CaseIterable, Codable {
    case lastUsed, editor, preview, split, gallery, carousel
}
```

- [ ] **Step 2: Add the Carousel pill to the default-view-mode picker**

In `PortyMcFolio/Views/AppSettingsView.swift`, find the `pillOption(...)` row around line 184-190 (hard-coded, not iterating `allCases`). After the Gallery line, append:

```swift
                    pillOption("Last used", AppState.DefaultViewMode.lastUsed, selection: $appState.defaultViewMode)
                    pillOption("Editor", .editor, selection: $appState.defaultViewMode)
                    pillOption("Preview", .preview, selection: $appState.defaultViewMode)
                    pillOption("Split", .split, selection: $appState.defaultViewMode)
                    pillOption("Gallery", .gallery, selection: $appState.defaultViewMode)
                    pillOption("Carousel", .carousel, selection: $appState.defaultViewMode)
```

- [ ] **Step 3: Build + tests**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' -quiet build 2>&1 | tail -5
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test 2>&1 | grep "All tests" | tail -1
```
Expected: `** BUILD SUCCEEDED **` and `Test Suite 'All tests' passed`.

- [ ] **Step 4: Manual smoke test**

Launch app → open Settings → locate the "Default view mode" row. The new "Carousel" pill appears alongside Editor/Preview/Split/Gallery. Set it. Open a project with favorites → view opens in carousel mode.

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/App/AppState.swift PortyMcFolio/Views/AppSettingsView.swift
git commit -m "feat(settings): carousel option in default-view-mode picker"
```

---

### Task 7: End-to-end verification pass

A final integrated walkthrough covering Plan A + Plan B together.

- [ ] **Step 1: Full build + test**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' -quiet build 2>&1 | tail -5
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test 2>&1 \
  | grep -E "(Test Suite 'All tests'|failed)" | tail -5
```

- [ ] **Step 2: Empty carousel**

Open a brand-new project (no favorites). ⌘5 → empty state renders, "Click the heart on media files in Gallery (⌘3)" copy visible.

- [ ] **Step 3: Image slide flow**

Favorite a `.jpg` and a `.png`. ⌘5. ←/→ moves between them. Counter correct. Arrow at edge is no-op. Filename header matches the shown image.

- [ ] **Step 4: Video slide flow**

Favorite a `.mp4`. Navigate to it. Poster visible. Hover shows AVKit controls. Click play → plays. ← to previous, → back → player re-created, showing poster again.

- [ ] **Step 5: Audio slide flow**

Favorite an `.mp3`. Navigate to it. Filename at top, inline transport bar (NO black pane). Click play → audio plays. Navigate away and back → player re-created (transport reset).

- [ ] **Step 6: Missing / hand-edited edge cases**

Quit app. In the project's markdown, add `favorites: ["nonexistent.jpg", "/abs/evil.jpg"]`. Launch app, ⌘5.
- `nonexistent.jpg` → missing placeholder (Media unavailable + filename).
- `/abs/evil.jpg` → dropped at parse time (isValidFavoritePath rejects absolute paths).

- [ ] **Step 7: Tray interactions**

With 5+ favorites, ⌘5.
- All 5 thumbs visible (scroll horizontally if needed).
- Current thumb has accent border.
- Click a non-current thumb → main slide jumps, tray auto-scrolls to center.
- ←/→ → tray auto-scrolls to center the newly current thumb.
- Hover a thumb → × appears top-right.
- Click × → that favorite is removed, frontmatter updated, tray shrinks by one.
- Remove all → empty state appears.

- [ ] **Step 8: Reconciler safety net (Finder move)**

Favorite `photo.jpg`. Quit app. In Finder, move `photo.jpg` into a subfolder (same basename). Relaunch the app. Open project. Inspect frontmatter: `favorites` should have the new path. ⌘5 → image renders.

- [ ] **Step 9: Reconciler safety net (Finder rename — dropped)**

Favorite `demo.mp3`. Quit app. In Finder, rename to `sample.mp3`. Relaunch. Frontmatter favorites no longer contains the old entry (dropped as indistinguishable from delete). ⌘5 → empty state (if it was the only favorite).

- [ ] **Step 10: DefaultViewMode setting**

App Settings → Default view mode → Carousel. Open a project that has favorites → opens directly in the carousel view. Verified.

- [ ] **Step 11: Theme sanity**

Cycle through `porty`, `osx`, `bw` × light/dark. All carousel UI elements legible (filename header, counter, thumbnail borders, missing-file placeholder, empty state, audio card).

- [ ] **Step 12: 50+ favorites perf**

Favorite 50 media files. ⌘5 → tray scrolls smoothly. Arrow-navigate through them — no lag. Center slide loads on demand (ProgressView briefly, then image). Memory usage in Xcode Debug Navigator stays under ~300MB.

- [ ] **Step 13: No commit needed**

Verification only. If any step fails, return to the relevant task and fix before declaring Plan B done.

---

## Completion checklist

- [ ] All six implementation tasks complete (Tasks 1–6) with green `xcodebuild build` and `test` after each
- [ ] Six commits on `feature/media-favorites-carousel` (one per implementation task)
- [ ] Task 7 end-to-end verification passes
- [ ] `CarouselView`, `AudioPlayerView`, `FavoritesReconciliation` in place
- [ ] `CarouselPlaceholderView` deleted from `ProjectDetailView`
- [ ] `DefaultViewMode.carousel` available in Settings
- [ ] No changes to Plan A features (Gallery hearts, frontmatter parse/serialize, `updateReadmeReferences` extensions) beyond the targeted Task 1 / Task 6 edits
- [ ] Unit tests on `FavoritesReconciliation` pass across all 8 cases
