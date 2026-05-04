# Design Tokens & Style Guide

## Goal

Establish a visual design language for PortyMcFolio — warm, editorial, refined macOS native — and provide a live style guide view to iterate on tokens before applying them across the app.

Reference: Family Wallet (family.co) — warm neutrals, generous whitespace, rounded corners, clean hierarchy.

## Phase 1: Design Tokens + Style Guide (this spec)

Build the token system and a preview view. Iterate with the user until approved.

## Phase 2: Full View Polish (separate spec)

Apply approved tokens across every view. Not covered here.

---

## DesignTokens.swift

Single file, static properties grouped by namespace. All colors adaptive (light/dark).

### Colors

Warm neutral palette — NOT cold system grays.

| Token | Light | Dark | Usage |
|-------|-------|------|-------|
| `background` | Warm off-white (#FAFAF8) | Deep charcoal (#1C1C1E) | Window/page background |
| `surface` | White (#FFFFFF) | Elevated dark (#2C2C2E) | Cards, panels, sheets |
| `surfaceHover` | Warm gray (#F5F5F3) | Lighter dark (#3A3A3C) | Hover/pressed states |
| `textPrimary` | Near-black (#1A1A1A) | Off-white (#F5F5F5) | Headings, primary text |
| `textSecondary` | Warm gray (#6B6B6B) | Muted (#A1A1A1) | Metadata, captions |
| `textTertiary` | Light gray (#999999) | Dim (#666666) | Hints, placeholders |
| `border` | Warm separator (#E8E8E5) | Dark separator (#3A3A3C) | Dividers, card borders |
| `accent` | Warm blue (#3478F6) | Brighter blue (#4A9AFF) | Links, selection, primary action |
| `statusDraft` | Gray (#8E8E93) | Gray (#8E8E93) | Draft badge |
| `statusActive` | Green (#34C759) | Green (#30D158) | Active badge |
| `statusArchived` | Orange (#FF9500) | Orange (#FFa733) | Archived badge |
| `statusHighlight` | Blue (#3478F6) | Blue (#4A9AFF) | Highlight badge |

Colors defined in code using a `Color` extension with `init(light:dark:)` that reads the current color scheme — no asset catalog needed. All in `DesignTokens.swift`.

### Typography

SF Pro throughout. Named roles, not arbitrary sizes.

| Token | Size | Weight | Usage |
|-------|------|--------|-------|
| `largeTitle` | 28pt | Semibold | Project detail header |
| `title` | 18pt | Semibold | Card titles, section headers |
| `headline` | 15pt | Medium | Subheadings, toolbar items |
| `body` | 14pt | Regular | Body text, descriptions |
| `caption` | 12pt | Regular | Metadata, dates, secondary info |
| `micro` | 10pt | Medium | Badges, keyboard hints, tags |

### Spacing

Consistent scale used everywhere.

| Token | Value | Usage |
|-------|-------|-------|
| `xs` | 4pt | Tight internal gaps (badge padding) |
| `sm` | 8pt | Small gaps (between icon and text) |
| `md` | 12pt | Medium gaps (card internal spacing) |
| `lg` | 16pt | Standard padding (card padding, grid gaps) |
| `xl` | 24pt | Section spacing |
| `xxl` | 32pt | Large section gaps, page margins |

### Corner Radius

| Token | Value | Usage |
|-------|-------|-------|
| `small` | 6pt | Badges, tags, small chips |
| `medium` | 10pt | Cards, panels, inputs |
| `large` | 14pt | Modals, popovers, search palette |

### Shadows

| Token | Color | Blur | Y-Offset | Usage |
|-------|-------|------|----------|-------|
| `card` | black 6% | 8pt | 2pt | Card elevation |
| `floating` | black 15% | 24pt | 8pt | Popovers, search palette, FABs |

---

## StyleGuideView.swift

A scrollable view accessible from a toolbar button. Shows all tokens rendered live so the user can evaluate and request changes.

### Sections

1. **Color Palette**
   - Grid of rounded rect swatches (60×60pt)
   - Each swatch shows the color with its token name below
   - Shows both light and dark appearance side by side (using `.colorScheme` environment override)

2. **Typography Scale**
   - Each named style rendered with sample text: "Portfolio — 2026"
   - Label below each: token name, size, weight

3. **Spacing Scale**
   - Horizontal bars at each spacing value, labeled
   - Visual comparison of the scale progression

4. **Corner Radius**
   - Sample rectangles (100×60pt) at each radius level, labeled

5. **Shadow Samples**
   - Cards showing each shadow level on the surface background

6. **Component Mockups**
   - A sample project card using all tokens (image placeholder, title, client, tags, status badge)
   - Status badge row showing all 4 states
   - A sample toolbar/header area

### Appearance Toggle

- Toggle button at the top of the style guide: Light / Dark / System
- Overrides the view's `colorScheme` environment so you see all tokens update live
- No need to go to System Preferences — flip between modes instantly within the guide

### Access

- Toolbar button (paintbrush icon) in ProjectListView, visible only during development
- Could also be a menu item under Window → Style Guide
- Straightforward to remove before shipping

---

## Files to Create

| File | Purpose |
|------|---------|
| `PortyMcFolio/Design/DesignTokens.swift` | All token definitions |
| `PortyMcFolio/Views/StyleGuideView.swift` | Live preview of all tokens |

## Files to Modify

| File | Change |
|------|--------|
| `PortyMcFolio/Views/ProjectListView.swift` | Add toolbar button to open StyleGuideView |

---

## Success Criteria

- Style guide renders all tokens correctly in both light and dark mode
- User can evaluate the full palette, type scale, spacing, and component mockups at a glance
- Tokens are easy to adjust (change one value, see it everywhere in the guide)
- No existing views are modified yet — tokens are defined but not applied until Phase 2
