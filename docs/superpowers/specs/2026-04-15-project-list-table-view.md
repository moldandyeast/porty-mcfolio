# Project List: Table View & DT Migration

**Date:** 2026-04-15
**Branch:** `dev/v1-implementation`
**Scope:** Add a sortable table view to the project list page alongside the existing card grid, and migrate both to the DT design system.

## Problem

The project list page only offers a card grid view. For portfolios with many projects, a dense table view with sortable columns would let users scan and find projects faster. Additionally, the card grid and list page still use hardcoded styles rather than DT design tokens, creating visual inconsistency with the editor and gallery views.

## Design Decisions

- **SwiftUI `Table`** for the table view — native macOS sortable columns, keyboard navigation, and column resizing for free. Minimal code vs. a custom `LazyVStack` reimplementation.
- **Persisted view mode** — user preference saved to UserDefaults, consistent with how `viewMode` and `splitRatio` are already persisted.
- **Sort state persisted** — default is year descending (newest first). Stored as a simple string key in UserDefaults.

## Data & State

### New Types

```swift
enum ProjectListMode: String, CaseIterable {
    case grid
    case table
}
```

### AppState Additions

```swift
@Published var projectListMode: ProjectListMode = .grid {
    didSet { UserDefaults.standard.set(projectListMode.rawValue, forKey: "projectListMode") }
}

@Published var projectSortOrder: [KeyPathComparator<Project>] = [
    KeyPathComparator(\.year, order: .reverse)
]
```

`projectListMode` is restored from UserDefaults in `init()`.

Sort order is persisted as a string key in UserDefaults (`"projectSortKey"`). Format: `"<field>-<direction>"` where field is one of `year`, `title`, `client`, `status` and direction is `asc` or `desc`. Default: `"year-desc"`. Decoded back to the appropriate `KeyPathComparator` on launch.

### Model Conformance

`ProjectStatus` needs `Comparable` conformance for the status column to be sortable. Case order defines sort order: `draft < active < complete < archived`.

## Table View

SwiftUI `Table` with these columns:

| Column | Key Path | Width | Sortable | Alignment |
|--------|----------|-------|----------|-----------|
| Year | `\.year` | ~60pt fixed | Yes | Trailing |
| Title | `\.title` | Flexible (primary) | Yes | Leading |
| Client | `\.client` | Medium (~120pt) | Yes | Leading |
| Status | `\.status` | ~80pt fixed | Yes | Center |
| Tags | `\.tags` | Flexible | No | Leading |

### Row Behavior

- Single click selects project (`appState.selectedProject = project`)
- Status column renders `StatusBadgeView` (existing component)
- Tags column renders inline tag pills using DT tokens

### Row Styling

- Text: `DT.Typography.body` for primary content, `DT.Typography.caption` for secondary
- Colors: `DT.Colors.textPrimary` for title, `DT.Colors.textSecondary` for year/client
- Selection/hover: `DT.Colors.surfaceHover`

## Card Grid DT Migration

`ProjectCardView` token updates (no behavioral changes):

| Element | Before | After |
|---------|--------|-------|
| Year text | `.font(.caption)` | `.font(DT.Typography.caption)` |
| Year color | `.foregroundStyle(.secondary)` | `.foregroundStyle(DT.Colors.textSecondary)` |
| Title text | `.font(.headline)` | `.font(DT.Typography.headline)` |
| Client text | `.font(.subheadline)` | `.font(DT.Typography.body)` |
| Client color | `.foregroundStyle(.secondary)` | `.foregroundStyle(DT.Colors.textSecondary)` |
| Card padding | `.padding(12)` | `.padding(DT.Spacing.md)` |
| Inner spacing | `spacing: 8` | `spacing: DT.Spacing.sm` |
| Tag flow spacing | `spacing: 4` | `spacing: DT.Spacing.xs` |
| Corner radius | `cornerRadius: 10` | `DT.Radius.medium` |
| Shadow | `.shadow(color:..., radius: 4)` | `.dtShadow(DT.Shadow.card)` |
| Background | `.background(.background)` | `.background(DT.Colors.surface)` |

`ProjectListView` grid updates:

| Element | Before | After |
|---------|--------|-------|
| Grid spacing | `spacing: 16` | `spacing: DT.Spacing.lg` |
| Grid padding | `.padding(16)` | `.padding(DT.Spacing.lg)` |

## Toolbar Toggle

Two icons added to `ProjectListView` toolbar, placed before the existing folder picker button:

- `square.grid.2x2` — grid mode
- `list.bullet` — table mode

Styling matches the gallery toolbar pattern:
- 12pt system font icon
- 26x26pt hit target
- Active: `DT.Colors.textPrimary`
- Inactive: `DT.Colors.textTertiary`
- `.buttonStyle(.plain)`

## Out of Scope

- Teaser image column in the table
- Empty state DT migration
- Keyboard shortcuts for switching list modes
- Search/filter changes
