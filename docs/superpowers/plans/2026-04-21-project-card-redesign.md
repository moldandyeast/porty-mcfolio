# Project Card Redesign — Implementation Plan

> **Plan is historical.** This plan was executed but the final design diverged from the dark-gradient + white-text goal. The shipped card uses a `.regularMaterial` label bar at the bottom with `theme.colors.textPrimary`/`textSecondary` (client uppercase caps + title), a status dot top-right, and an `.ultraThinMaterial` hover overlay that reveals the tags. Post-review (2026-04-21) also added `.allowsHitTesting(false)` on the material rectangle and `.allowsHitTesting(isHovered)` on the hover overlay so clicks reach the card below. See the current `PortyMcFolio/Views/ProjectCardView.swift` for the actual implementation.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite `ProjectCardView` to a full-bleed 3:2 card with dark bottom gradient, status dot, tinted empty state, and hover-reveal clickable tags.

**Architecture:** Single-file rewrite. `ProjectCardView.body` becomes a `ZStack` with layered content: base (teaser image or empty-state tint + serif year numeral), bottom gradient, text block, status dot, hover-reveal overlay. Center-crop default. `FlowLayout` helper in the same file stays. `ProjectListView` integration stays unchanged — `onOpen` and `onTagTap` callbacks are already wired.

**Tech Stack:** SwiftUI macOS 14+ (deployment 15.0), AppKit (`QLThumbnailGenerator`). No new deps.

**Testing note:** View-only rewrite, no business logic. The project has no SwiftUI view tests by convention. Verification is `xcodebuild build` per task plus manual UI verification at the end. Each task leaves the app buildable; progressive visual verification lands with the overall rewrite.

**Spec:** `docs/superpowers/specs/2026-04-21-project-card-redesign-design.md`

---

## File map

| File | Change |
|---|---|
| `PortyMcFolio/Views/ProjectCardView.swift` | Full rewrite of `ProjectCardView` body. `FlowLayout` struct stays unchanged. Remove unused `cardHeight` constant. |

No other files touched.

## Shared commands

**Build** (run after each task):
```bash
cd <repo>/.worktrees/overview-shortcuts && \
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' -quiet build 2>&1 | tail -8
```
Expected: `** BUILD SUCCEEDED **`. Pre-existing warnings about `appearanceSignal` actor isolation and `FSEventStreamScheduleWithRunLoop` are fine. Any NEW warning or error blocks progression.

---

### Task 1: Scaffold 3:2 base layer (teaser OR empty-state tint + year numeral)

**Files:**
- Modify: `PortyMcFolio/Views/ProjectCardView.swift`

Replace the current `ProjectCardView.body` with a fresh ZStack at 3:2. Keep teaser loading unchanged. Empty-state tint with serif year numeral. No gradient/text/status/hover yet.

- [ ] **Step 1: Rewrite `ProjectCardView`**

Replace the entire `struct ProjectCardView: View { … }` block (leave `struct FlowLayout` above it untouched). The new struct:

```swift
struct ProjectCardView: View {
    let project: Project
    var onOpen: (() -> Void)?
    var onTagTap: ((String) -> Void)?

    @State private var teaserImage: NSImage?
    @State private var isHovered = false
    @Environment(\.theme) var theme

    private var yearSuffix: String {
        String(project.year % 100)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Base: teaser OR empty-state tint
            if let image = teaserImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                emptyStateBackground
            }
        }
        .aspectRatio(3.0/2.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(theme.colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.large))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.large)
                .stroke(theme.colors.border, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: DT.Radius.large))
        .onTapGesture { onOpen?() }
        .onHover { hovering in isHovered = hovering }
        .dtShadow(DT.Shadow.card)
        .task { await loadTeaser() }
    }

    @ViewBuilder
    private var emptyStateBackground: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    theme.colors.statusDraft.opacity(0.18),
                    theme.colors.background
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Text(yearSuffix)
                .font(.custom("Georgia", size: 44))
                .fontWeight(.bold)
                .foregroundStyle(theme.colors.textPrimary.opacity(0.08))
                .padding(.top, 12)
                .padding(.leading, 16)
        }
    }

    private func loadTeaser() async {
        guard !project.teaser.isEmpty else { return }
        let teaserURL = project.folderURL.appendingPathComponent(project.teaser)
        guard FileManager.default.fileExists(atPath: teaserURL.path) else { return }

        let size = CGSize(width: 600, height: 400)
        let request = QLThumbnailGenerator.Request(
            fileAt: teaserURL,
            size: size,
            scale: 2.0,
            representationTypes: .thumbnail
        )
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return }
        await MainActor.run {
            teaserImage = rep.nsImage
        }
    }
}
```

Key points:
- `cardHeight` constant is gone (replaced by `aspectRatio(3/2, contentMode: .fit)`).
- Teaser thumbnail request size changed from 600×240 to 600×400 to better match the new 3:2 aspect.
- `.clipped()` isn't needed explicitly — the `clipShape(RoundedRectangle)` already clips.
- `isHovered` is wired but unused for now (next tasks use it).

- [ ] **Step 2: Build**

Run build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd <repo>/.worktrees/overview-shortcuts && \
git add PortyMcFolio/Views/ProjectCardView.swift && \
git commit -m "refactor(card): scaffold 3:2 base layer with empty-state tint"
```

---

### Task 2: Bottom gradient + text block (year, title, client)

**Files:**
- Modify: `PortyMcFolio/Views/ProjectCardView.swift`

Add the dark-bottom gradient and the white text overlay.

- [ ] **Step 1: Add gradient + text to the ZStack**

In `var body: some View` — extend the `ZStack(alignment: .topLeading)` block. The gradient fills the whole card; the alpha ramp concentrates darkness at the bottom (four-stop: the first two stops are fully transparent, then ramp to 95% opaque at the bottom). The text block uses a VStack with a top Spacer to bottom-align itself inside the ZStack.

```swift
ZStack(alignment: .topLeading) {
    // Base: teaser OR empty-state tint
    if let image = teaserImage {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
    } else {
        emptyStateBackground
    }

    // Bottom gradient for text legibility — alpha ramp covers the card,
    // darkness concentrates in the bottom half.
    LinearGradient(
        colors: [
            Color.black.opacity(0.0),
            Color.black.opacity(0.0),
            Color.black.opacity(0.55),
            Color.black.opacity(0.95)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    .allowsHitTesting(false)

    // Text block (bottom-left)
    VStack(alignment: .leading, spacing: 0) {
        Spacer(minLength: 0)
        VStack(alignment: .leading, spacing: 3) {
            Text(String(project.year))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Color.white.opacity(0.8))

            Text(project.title.isEmpty ? "Untitled" : project.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(2)

            if !project.client.isEmpty {
                Text(project.client)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .lineLimit(1)
                    .padding(.top, 1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }
    .allowsHitTesting(false)
}
```

- [ ] **Step 2: Build**

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd <repo>/.worktrees/overview-shortcuts && \
git add PortyMcFolio/Views/ProjectCardView.swift && \
git commit -m "feat(card): bottom gradient + overlay text (year, title, client)"
```

---

### Task 3: Status dot top-right with color mapping

**Files:**
- Modify: `PortyMcFolio/Views/ProjectCardView.swift`

Add the 8pt colored status dot in the top-right corner with a subtle glow.

- [ ] **Step 1: Add `statusColor` helper**

Inside `struct ProjectCardView`, near `yearSuffix`:

```swift
private var statusColor: Color {
    switch project.status {
    case .empty:      return theme.colors.statusDraft
    case .inProgress: return theme.colors.statusActive
    case .archived:   return theme.colors.statusArchived
    }
}
```

This mirrors `StatusBadgeView`'s mapping (already using the updated color values from the earlier theme tweak commit).

- [ ] **Step 2: Add the dot to the ZStack**

Inside `var body: some View`, inside the ZStack, AFTER the text block (so it sits on top):

```swift
    // Status dot — top-right
    VStack {
        HStack {
            Spacer(minLength: 0)
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.6), radius: 5)
        }
        Spacer(minLength: 0)
    }
    .padding(12)
    .allowsHitTesting(false)
```

- [ ] **Step 3: Build**

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd <repo>/.worktrees/overview-shortcuts && \
git add PortyMcFolio/Views/ProjectCardView.swift && \
git commit -m "feat(card): colored status dot in top-right corner"
```

---

### Task 4: Hover-reveal overlay with clickable tags

**Files:**
- Modify: `PortyMcFolio/Views/ProjectCardView.swift`

Layer an `.ultraThinMaterial` on top of the card that fades in on hover. Shows the project's tags as clickable `TagPillView` pills. No tags → no overlay.

- [ ] **Step 1: Add the hover overlay to the ZStack**

Inside the body's ZStack, as the LAST element (so it sits above text, gradient, and status dot):

```swift
    // Hover reveal — shows tags as clickable pills
    if !project.tags.isEmpty {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)

            VStack(alignment: .leading, spacing: 10) {
                Text("Tags — click to filter")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.white.opacity(0.55))

                FlowLayout(spacing: 5) {
                    ForEach(project.tags, id: \.self) { tag in
                        TagPillView(tag: tag) {
                            onTagTap?(tag)
                        }
                        .environment(\.colorScheme, .dark)
                    }
                }
            }
            .padding(16)
        }
        .opacity(isHovered ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
```

Notes:
- `.environment(\.colorScheme, .dark)` on the material + the `TagPillView` forces the dark variant regardless of the app theme, so the material reads as dark-translucent and tag pills show their dark-appropriate colors. This matches the white-on-dark text the gradient already uses.
- `.ultraThinMaterial` + `.dark` scheme produces a blurred dark tint — mirrors the mockup.
- `if !project.tags.isEmpty` wraps the whole overlay — projects without tags get no hover reveal.

- [ ] **Step 2: Build**

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd <repo>/.worktrees/overview-shortcuts && \
git add PortyMcFolio/Views/ProjectCardView.swift && \
git commit -m "feat(card): hover-reveal overlay with clickable tag pills"
```

---

### Task 5: End-to-end manual verification

View-only change; manual pass across themes and states.

- [ ] **Step 1: ⌘R in Xcode (worktree project)**

If the worktree's Xcode project isn't already open:
```bash
open <repo>/.worktrees/overview-shortcuts/PortyMcFolio.xcodeproj
```
Quit any already-running PortyMcFolio first, then ⌘R.

- [ ] **Step 2: Grid with teasers — visual check**

Open a project folder with a mix of teasered and empty-state projects. Confirm:
- Cards are wider than tall (3:2 landscape).
- Teaser fills the card edge-to-edge. No visible card background around the image.
- Title + year + client readable on the dark bottom gradient.
- Status dot visible in top-right, colored per status (red/orange/grey).

- [ ] **Step 3: Empty state — visual check**

Find a project with no teaser:
- Background is a red-tinted gradient.
- Serif "26" (or whatever 2-digit year) sits top-left, very low contrast.
- Text block at bottom still readable.
- Status dot in top-right.

- [ ] **Step 4: Hover-reveal**

Hover a card that has tags:
- `.ultraThinMaterial` overlay fades in over ~150ms.
- "TAGS — CLICK TO FILTER" label visible.
- Tag pills below, clickable.
- Click a tag → the overlay should close (because the grid filters, the card may exit view). Filter field updates to that tag.
- Mouse away → overlay fades out.

Hover a card with no tags:
- Nothing happens — no overlay appears. Base card stays.

- [ ] **Step 5: Click behavior**

- Click the body of a card (anywhere not on a tag pill) → detail view opens.
- Right-click → context menu (Open / Project Settings… / Open in Finder / Delete).
- Click a tag in the hover overlay → does NOT open the card; only filters.

- [ ] **Step 6: Keyboard nav (sanity)**

- ⌘↓ / ⌘→ navigate the selection border across cards. Accent border should draw outside the card (not interfere with the 3:2 layout).
- ⌘4 on a hovered or selected card opens its settings sheet.

- [ ] **Step 7: Theme cycle**

In Settings, switch between `porty`, `osx`, `bw`:
- Empty-state tint (`statusDraft.opacity(0.18)`) readable in each theme.
- Status dot colors legible (red/orange/grey per theme's values).
- Light mode AND dark mode for each theme — gradient+white-text stays legible.

- [ ] **Step 8: Window resize**

Drag the window narrower and wider:
- Cards reflow correctly (`.adaptive(minimum: 280, maximum: 400)` unchanged).
- 3:2 aspect maintained at all widths.
- No clipping of text or gradient artifacts.

- [ ] **Step 9: Long titles / many tags**

- A project with a very long title → wraps to 2 lines, ellipsized beyond that.
- A project with many tags → hover overlay's `FlowLayout` wraps pills across multiple rows.

- [ ] **Step 10: Report**

Confirm all checks pass, or describe what's off. No code commit — this is a verification-only task.

---

## Completion checklist

- [ ] All four implementation tasks landed (Tasks 1–4)
- [ ] `xcodebuild build` green after each task
- [ ] Four new commits on `feature/overview-shortcuts`
- [ ] No changes to `ProjectListView.swift`, `AppState.swift`, `Theme.swift`, or any other file
- [ ] Manual verification (Task 5) passes across grid + table, themes, and states
