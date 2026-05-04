# Project Card Redesign — Full-Bleed 3:2

**Date:** 2026-04-21
**Scope:** `PortyMcFolio/Views/ProjectCardView.swift`
**Follow-up:** Image positioner spec (separate)

## Post-implementation revisions (2026-04-21)

Several visual choices below were superseded during iteration. Shipped design:

- **Bottom label bar**, not a dark gradient with white text. The bar uses `.regularMaterial` (theme-adaptive) with `theme.colors.textPrimary` for title and `theme.colors.textSecondary` for an uppercase small-caps client label. The year numeral was dropped from the bar to avoid duplicating the year divider above each grid group.
- **Hover overlay** still uses `.ultraThinMaterial` forced to dark colorScheme and reveals clickable tag pills via `FlowLayout`. After the code-review pass, the material rectangle gained `.allowsHitTesting(false)` and the whole overlay wraps in `.allowsHitTesting(isHovered)` so clicks still reach the card body when the overlay is invisible, and the material doesn't intercept clicks between tag pills when visible.
- **Status dot** top-right and **empty-state** (serif year numeral + tinted gradient) shipped as specified.

The rest of this spec is historical context for motivation and layer ordering.

## Summary

Rewrite the grid card to a photo-frame feel: teaser fills the entire 3:2 card, title and metadata sit on a dark gradient at the bottom, status becomes a small glowing colored dot in the corner. No tags on the card at rest — hovering reveals a backdrop-blurred layer with clickable tag pills. Empty state uses a tinted gradient background with a large serif year numeral as typographic fill.

Center-crop default for teasers. Custom focal-point positioning is deferred to a separate follow-up spec.

## Motivation

The current card feels generic — fixed 120px teaser, stacked metadata with inline tag pills, all in roughly equal visual weight. For designers/artists using the app to review their portfolio, the teaser should dominate. Tags are a filter tool, not a primary card concern. Empty states ("No teaser" placeholder on ~half the user's projects) feel blank rather than intentional. The redesign addresses all three.

## Design

### Card structure — layers (ZStack, bottom to top)

```
┌─ Base ─────────────────────────────────────┐
│ Option 1: teaser image, object-fit cover   │
│ Option 2: tinted gradient empty state      │
│           + oversized serif year numeral   │
├─ Bottom gradient (52% height) ─────────────┤
│ linear gradient                            │
│   from: rgba(0,0,0,0) at top              │
│   to:   rgba(0,0,0,0.95) at bottom        │
├─ Text block (bottom-left) ─────────────────┤
│ YEAR (micro caps, 10pt, tracking 0.12em)  │
│ Title (semibold, 16pt, lineLimit 2)       │
│ Client (11pt, secondary)                   │
├─ Status dot (top-right) ───────────────────┤
│ 8pt circle with color glow                 │
├─ Hover overlay (full card, opacity 0 → 1) ─┤
│ material: .ultraThinMaterial               │
│ "TAGS — CLICK TO FILTER" label + pills     │
├─ Selection border (existing) ──────────────┤
│ RoundedRectangle.stroke, accent tint       │
└────────────────────────────────────────────┘
```

### Dimensions

- Aspect ratio: **3:2 landscape** (width × 2/3 height). No explicit `minHeight`.
- Card width remains controlled by the outer `LazyVGrid(columns: .adaptive(minimum: 280, maximum: 400))` — unchanged.
- At 320px width → 213px tall. At 400px width → 267px tall. Denser than the current 240px min-height cards.
- Corner radius: `DT.Radius.large` (unchanged).

### Base layer

**With teaser:**
```swift
Image(nsImage: teaserImage)
    .resizable()
    .aspectRatio(contentMode: .fill)
    .clipped()
```
`.fill` crops to cover the 3:2 frame, center-anchored (SwiftUI default).

**Without teaser (empty state):**
```swift
LinearGradient(
    colors: [
        theme.colors.statusDraft.opacity(0.18),  // red-tinted (matches status color mapping)
        theme.colors.background
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)
```
Overlaid with a large serif numeral for the 2-digit year, tucked top-left, low opacity:
```swift
Text(yearSuffix)  // "26" for 2026
    .font(.custom("Georgia", size: 44))
    .fontWeight(.bold)
    .foregroundStyle(theme.colors.textPrimary.opacity(0.08))
    .padding(.top, 12)
    .padding(.leading, 16)
```
`yearSuffix = String(project.year % 100)` — only the two least-significant digits.

The tint uses `statusDraft` (red in the new color mapping) regardless of actual status. We experimented with status-based tinting and it felt noisy. Red-tint-for-empty-state is a one-constant look that reads as "this card has no image yet."

### Bottom gradient

```swift
LinearGradient(
    colors: [
        Color.black.opacity(0.0),
        Color.black.opacity(0.55),
        Color.black.opacity(0.95)
    ],
    startPoint: .top,
    endPoint: .bottom
)
.frame(height: cardHeight * 0.52, alignment: .bottom)
```

Applied at the bottom 52% of the card. `.allowsHitTesting(false)`. Works for both teaser and empty-state bases — ensures white text is always legible.

### Text block

Bottom-left, 14pt inset from left, 14pt from bottom:

```swift
VStack(alignment: .leading, spacing: 3) {
    Text(String(project.year))
        .font(DT.Typography.micro)
        .fontWeight(.semibold)
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
    }
}
```

Text is always white (not theme-adaptive) — it sits on a dark gradient regardless of theme. Readability wins over theme consistency for the overlay.

### Status dot

Top-right, 12pt inset:

```swift
Circle()
    .fill(statusColor)
    .frame(width: 8, height: 8)
    .shadow(color: statusColor.opacity(0.6), radius: 5)
```

Where `statusColor` is:
- `.empty` → `theme.colors.statusDraft` (red)
- `.inProgress` → `theme.colors.statusActive` (orange)
- `.archived` → `theme.colors.statusArchived` (grey)

These colors were updated in commit `416b647`. The dot reads as a small status indicator without needing a pill/badge with text.

### Hover overlay — tags

Inset the whole card with a material layer that fades in on hover:

```swift
@State private var isHovered = false

// In the ZStack, above everything:
if !project.tags.isEmpty {
    ZStack(alignment: .bottomLeading) {
        Rectangle()
            .fill(.ultraThinMaterial)
            .colorScheme(.dark)  // force dark material regardless of app theme

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
                    .colorScheme(.dark)
                }
            }
        }
        .padding(16)
    }
    .opacity(isHovered ? 1 : 0)
    .animation(.easeInOut(duration: 0.15), value: isHovered)
}
.onHover { hovering in isHovered = hovering }
```

**Tag click behavior:** `onTagTap(tag)` is already wired by `ProjectListView.gridView` to `appState.searchQuery = tag`. That's unchanged.

**Event propagation:** `TagPillView` is a `Button` — tapping it does NOT propagate to the card's `onTapGesture`. Confirmed by the existing table view behavior. No extra work needed.

**No tags case:** if `project.tags.isEmpty`, the hover layer is skipped entirely. Nothing to reveal.

### Selection border

Existing keyboard-selection highlight stays:

```swift
.overlay(
    RoundedRectangle(cornerRadius: DT.Radius.large)
        .stroke(
            isSelected ? theme.colors.accent.opacity(0.3) : Color.clear,
            lineWidth: 1
        )
        .allowsHitTesting(false)
)
```

Applied OUTSIDE the card's ZStack so it sits on top of the hover overlay — visible whether or not the card is hovered.

The existing mutual-exclusion logic in `ProjectListView` (hover sets `selectedProjectID`, arrows move it) continues to drive `isSelected`.

### Click / context menu (unchanged)

- Single click → `onOpen?()` → opens detail view. (Existing.)
- Right-click → `projectContextMenu(for: project)` from the list view. (Existing.)
- `onTagTap?(tag)` → set filter. (Existing, now only fires from hover overlay.)

## Files touched

- `PortyMcFolio/Views/ProjectCardView.swift` — full rewrite of the `body` property and related helpers. `FlowLayout` helper (currently in the same file) stays — still used by the hover overlay's tag pills and by the table view. The `cardHeight: 240` constant is removed (aspect ratio replaces it).
- **No changes** to `ProjectListView.swift`. The grid's `ProjectCardView` call already passes `onOpen`, `onTagTap`. The outer `.overlay` for the selection border lives in `ProjectListView`'s grid ForEach — that stays.
- **No changes** to `AppState`, `Project`, `ThemeColors`, `StatusBadgeView` (still used in table view).

## State summary

| State | Owner | Purpose |
|---|---|---|
| `teaserImage: NSImage?` | `ProjectCardView` (existing) | Loaded async via QL thumbnail |
| `isHovered: Bool` | `ProjectCardView` (new) | Drives hover-reveal opacity |

No external state changes.

## Non-goals

- No image positioning / custom focal point. Center-crop (SwiftUI's `.fill` default) for all teasers. Follow-up spec.
- No new status values or color changes (colors were already updated in a prior commit).
- No changes to table view.
- No changes to tag click behavior — `onTagTap` continues to set the filter.
- No new frontmatter fields.
- No responsive card sizing beyond what `LazyVGrid(.adaptive)` already does.
- No change to the grid's year-group layout.

## Testing

View-only change; follows project convention of manual verification for SwiftUI. No new unit tests warranted.

**Manual checklist:**
- Grid view with mix of teaser / no-teaser projects — confirm 3:2 aspect, cards tile cleanly.
- Porty / osx / bw themes × light / dark — empty-state tint readable, text legible on gradient.
- Hover a card with tags → overlay fades in smoothly. Hover away → fades out.
- Click a tag in the hover overlay → filter updates, card doesn't open.
- Click card body (not a tag) → detail view opens.
- Right-click → context menu appears (unchanged behavior).
- Keyboard ⌘↓ to navigate → selection border moves, hover state unaffected.
- Projects with long titles wrap to 2 lines; ellipsized if longer.
- Empty-state year numeral shows only the last 2 digits (e.g., "26" for 2026) and stays low-contrast.
- Teaser image load: card shows empty state during `.task`, teaser fades in when ready.

## Risks

- **`.ultraThinMaterial` appearance:** on very dark themes, the material may still show through busier teasers. Forcing `.colorScheme(.dark)` on the material container should keep it dark-tinted. Verify during manual test.
- **Hover-triggered selection thrash during scroll:** the existing sticky-selection model handles this (last committed hover wins; no re-render cascade). The hover-reveal is layered on that — should inherit the same behavior.
- **Accessibility:** bottom gradient can reduce contrast on very light teasers. White text + 0.95 black gradient should be ≥4.5:1 for most real photos. If a specific teaser fails, user can reset or pick a different image. No automatic mitigation.
- **Performance with many hover-overlays:** each card instantiates its hover ZStack eagerly (opacity 0 when not hovered). For 50+ cards, SwiftUI should handle this fine with `LazyVGrid`, but if teaser + material + FlowLayout compounds cost, we can lazy-build the overlay (`if isHovered { … }`) as a fallback.
