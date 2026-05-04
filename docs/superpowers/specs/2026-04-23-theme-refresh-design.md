# Theme refresh — three palettes, one brand

**Status:** Approved in brainstorm (v6). Ready for implementation.
**Scope:** Replace the current three-theme palette values and remove the
`statusDraft`-based card gradient + Georgia-44 year ghost. Surface-level
visual change only — no architecture change, no new tokens, no new views.
A single discrete commit that's easy to revert if it doesn't land.

## Why

The current Porty light-mode palette mixes cool gray neutrals with a
warm red-derived card wash and a warm mauve accent — three competing
temperatures. All "no teaser" project cards render a uniform pink wash
via `statusDraft.opacity(0.18)`, which reads as flat/accidental. The
Georgia-44 year ghost is an ornamental inconsistency with the system-
font typography used everywhere else. The OSX theme is native-system
but undifferentiated (same temperature as Porty). The BW theme uses
`#FFFFFF` / `#000000` with no softness.

## The system

Three themes, three temperatures of white:

- **Porty** = cool white, mauve accent
- **OSX**   = warm (nearly pure) white, mauve accent
- **BW**    = neutral white with a whisper of cool, monochrome accent (art-first)

Mauve `#B34778` is the brand. Porty and OSX share it. BW suppresses it
on purpose — the art-first mode where content is the focus, not the
chrome.

Mauve is **never used for card gradient fills**. It's reserved for:
selected row/cell backgrounds (at `DT.Opacity.selection` = 0.12),
button tints, link text, active status dots, and accent strokes.

## Palettes

### Porty

|                  | Light     | Dark      |
|------------------|-----------|-----------|
| background       | `#F3F4F6` | `#14161B` |
| backgroundAlt    | `#E7E9ED` | `#1F232B` |
| surface          | `#FBFBFC` | `#1C1F25` |
| surfaceHover     | `#ECEDF0` | `#262A32` |
| textPrimary      | `#1A1B1F` | `#E8EAEF` |
| textSecondary    | `#5A5E68` | `#9298A3` |
| textTertiary     | `#9297A0` | `#6C717C` |
| border           | `#DEDFE3` | `#2E323B` |
| accent           | `#B34778` | `#C8628F` |

### OSX

|                  | Light     | Dark      |
|------------------|-----------|-----------|
| background       | `#FBFAF7` | `#171613` |
| backgroundAlt    | `#EDEAE2` | `#1F1D19` |
| surface          | `#FEFEFC` | `#1E1C18` |
| surfaceHover     | `#F2F0EB` | `#26241F` |
| textPrimary      | `#1E1B15` | `#EFEDE6` |
| textSecondary    | `#5A5448` | `#A09C90` |
| textTertiary     | `#8F887A` | `#777469` |
| border           | `#E4E1D8` | `#2E2C27` |
| accent           | `#B34778` | `#C8628F` |

OSX uses the mauve accent now (not `NSColor.controlAccentColor`). The
"native" framing carries through the warm-near-white neutrals; the
accent is intentionally the brand.

### BW

|                  | Light     | Dark      |
|------------------|-----------|-----------|
| background       | `#F5F6F7` | `#16171A` |
| backgroundAlt    | `#E5E6E8` | `#202125` |
| surface          | `#FCFCFD` | `#1D1E21` |
| surfaceHover     | `#ECEDEE` | `#27282B` |
| textPrimary      | `#1A1B1D` | `#EBECED` |
| textSecondary    | `#5A5B5E` | `#9FA0A3` |
| textTertiary     | `#8B8C8E` | `#72737A` |
| border           | `#D6D7D9` | `#303235` |
| accent           | `#2A2B2D` | `#D4D5D8` |

BW accent is a dark gray on light / light gray on dark — enough
contrast to read as a selection pill without injecting chroma.

**Neutral progression in all three themes:** light mode runs
`border < backgroundAlt < surfaceHover < background < surface` (darkest
to lightest). Dark mode inverts: `background < backgroundAlt <
surface < surfaceHover < border`. `surfaceHover` is the hover-on-card
tint; `backgroundAlt` is a secondary canvas tone for sidebars / inset
panels / dividers.

### Status colors (all themes)

Unchanged from the current palette. These convey project state
semantics and don't participate in the brand tonal system:

- `statusDraft` — existing red
- `statusActive` — existing orange
- `statusComplete` — existing blue
- `statusArchived` — existing gray
- `error` — existing red

## Card changes in `ProjectCardView`

Two changes:

1. **Drop the gradient wash.** Empty-state (no teaser) cards render
   plain `surface` with a hairline `border`. No `statusDraft.opacity`
   gradient. No colored wash at all. The card is a blank sheet waiting
   for content.

2. **Drop the Georgia-44 year ghost.** Remove `Text(yearSuffix)` from
   `emptyStateBackground`. Add the year to the existing client meta
   line in the card footer as `"<CLIENT> · <YEAR>"` (uppercase,
   tracking 1.2, `DT.Typography.micro`-ish — same voice as the current
   client line). If `client` is empty, show just the year.

`DT.Typography.displayYear` is removed from the token layer — nothing
else uses it.

## Out of scope

- Status color revisions (the red/orange/blue/gray status dots stay).
- Material fills on the card footer strip (`.regularMaterial`) — leave
  alone for now; revisit if the new palette makes it obviously wrong.
- Dark-mode manual toggle (still follows system appearance).
- Icon color tokenization (was already its own pass).
- Editor/preview CSS surface refresh beyond what already lives in
  `preview.html`'s CSS-var consumption (the new hexes flow through via
  `Theme.cssVariables`).

## Implementation as one commit

One file-by-file change:

- `PortyMcFolio/Design/Theme.swift` — replace the three theme color
  blocks with the hexes above. OSX accent swaps from
  `NSColor.controlAccentColor` to the mauve hex.
- `PortyMcFolio/Design/DesignTokens.swift` — remove
  `DT.Typography.displayYear`.
- `PortyMcFolio/Views/ProjectCardView.swift` — remove the gradient +
  year-ghost in `emptyStateBackground`; inline the year in the client
  meta line.

All three changes land together as one `refactor(design): ...` commit
so the revert is clean (`git revert <sha>` puts everything back).

## Risk

Visual regressions on surfaces that depend on the old palette
indirectly: status badges, the preview markdown rendering, the search
palette accent tint, the grain-overlay opacity per-theme. The grain
per-theme opacities stay — they were tuned separately and don't need
to change with the palette.

## Verification

After rebuild:
- Project overview: cards are clean surfaces, no uniform pink. Mauve
  shows only on selected/keyboard-active card strokes and the status
  pill in the footer strip.
- Theme switch (Porty → OSX → BW): cards visibly change temperature,
  accent stays mauve for Porty/OSX and drops to gray for BW.
- Dark mode (system flip): all three themes flip cleanly; mauve
  brightens to `#C8628F` on Porty/OSX.
- Preview.html heading hierarchy still works (CSS vars pick up the new
  hexes).

If the palette doesn't land: `git revert <sha>` restores the previous
theme state in a single step.
