# Arrow-Key Navigation for Project Overview

**Date:** 2026-04-20
**Scope:** `PortyMcFolio/Views/ProjectListView.swift`
**Stacks on:** `2026-04-20-overview-settings-shortcuts-design.md` (same branch `feature/overview-shortcuts`)

## Post-implementation revisions (2026-04-21)

After a code-review pass, four departures from the original spec below landed. The rest of the spec is historical context — trust this section for the current contract.

1. **Arrow keys use `⌘+arrow`, not bare arrows.** Bare ↑/↓/←/→ pass through to the ScrollView's native viewport scrolling, which matches macOS scroll behavior users already expect; `⌘+arrow` moves the selection. No `.disabled(filterFocused)` is needed on these since the ⌘ modifier already disambiguates from text cursor movement in the filter field.
2. **Selection is split into two independent state vars**:
   - `hoveredProjectID` (ephemeral) — set on hover-enter, cleared on hover-leave.
   - `keyboardSelectedProjectID` (sticky) — set by `⌘+arrow`, cleared by ESC / mode switch / filter invalidates it.
   - `highlightedProjectID` is now a computed `keyboardSelectedProjectID ?? hoveredProjectID` used for the visible accent border and `⌘4`'s target (keyboard wins when both are set).
   - **Hover does NOT clear keyboard selection.** Otherwise auto-scroll after `⌘+arrow` would re-fire `onHover` on cards sliding under the stationary cursor and clobber the keyboard target. Users exit keyboard mode explicitly via ESC.
3. **Return opens only the keyboard selection.** A stale mouse-hover selection must not cause accidental opens when the user presses Return for any other reason. Click to open hover-selected cards.
4. **Auto-scroll is gated to `keyboardSelectedProjectID` changes.** Hover-driven selection does not scroll, preventing thrash when the user sweeps the mouse across the grid.
5. **Seed behavior:** when nothing is highlighted, any arrow press (including `⌘↑`/`⌘←`) seeds to the first visible card. The pure helper still returns nil for up/left from nil, but `moveSelection` in the view layer short-circuits and seeds before calling the helper.

## Summary

Keyboard navigation for the project overview in both grid and table modes:
- **Grid:** ↑/↓/←/→ moves a single highlight across cards, flat-ordered across year groups.
- **Table:** ↑/↓ moves the highlight down the sorted rows. ←/→ no-op.
- **Enter:** opens the highlighted project (same as a click).
- **⌘4:** reuses the highlight (extends the existing hovered-project ⌘4 handler).
- **ESC:** single press clears both the highlight AND the filter; no-op if both are empty.
- **Auto-scroll:** keeps the highlighted card/row visible via `ScrollViewReader.scrollTo(…, anchor: .center)`.

All changes live in `ProjectListView.swift`. No `AppState` additions.

## Motivation

The previous feature added a hover-tinted border on grid cards to telegraph ⌘4's target. With that visual cue in place, keyboard navigation becomes a natural extension: users can move the highlight without the mouse and act on it via Enter or ⌘4. This closes the gap for keyboard-only users and makes triaging a long project list faster.

## Design

### One new state

```swift
@State private var highlightedProjectID: String?
@FocusState private var filterFocused: Bool
```

Mouse hover state (`hoveredGridProjectID`, `hoveredProjectID`) is unchanged. Both contribute to the visual cue:

```swift
.stroke(
    (highlightedProjectID == project.id || hoveredGridProjectID == project.id)
        ? theme.colors.accent.opacity(0.3)
        : Color.clear,
    lineWidth: 1
)
```

Same idea in the table row's hover-background condition, extended to include `highlightedProjectID`.

"Last interaction wins" falls out naturally: keyboard sets `highlightedProjectID`; mouse sets `hoveredGridProjectID` which clears on mouse-leave. If both are set, both render the same border (the `||` collapses them).

### Filter focus gate

Bind `.focused($filterFocused)` to the filter `TextField` in the toolbar. Arrow-key buttons use `.disabled(filterFocused)` so their `.keyboardShortcut` doesn't fire while the TextField is focused — arrow keys pass through to the text cursor, matching macOS convention.

### Key bindings (hidden buttons in `.background`)

The existing `.background { … }` block (ESC + ⌘4) gains six more sibling buttons: ↑, ↓, ←, →, Return, (ESC reuses existing). Pattern stays `Button("") { … }.keyboardShortcut(…).opacity(0).allowsHitTesting(false)`, plus `.disabled(filterFocused)` on the arrow/Return set.

```swift
Button("") { moveHighlight(.up) }
    .keyboardShortcut(.upArrow, modifiers: [])
    .disabled(filterFocused)
    .opacity(0).allowsHitTesting(false)

// repeat for .downArrow, .leftArrow, .rightArrow

Button("") { openHighlighted() }
    .keyboardShortcut(.return, modifiers: [])
    .disabled(filterFocused)
    .opacity(0).allowsHitTesting(false)
```

### Navigation math

#### Grid

Projects are grouped by year in the UI but keyboard nav traverses them as a flat list in display order (year desc, creation order within year — matches what the user sees scanning top-left to bottom-right):

```swift
private var navProjects: [Project] {
    projectsByYear.flatMap { $0.projects }  // already year-desc
}
```

Column count is derived from the visible grid width. Measured via a `.background(GeometryReader { proxy in Color.clear.preference(key: GridWidthKey.self, value: proxy.size.width) })` sitting on the grid container (NOT inside the ScrollView content — see memory on GeometryReader/ScrollView hit-testing). Stashed into `@State private var gridWidth: CGFloat = 0`. Column count:

```swift
private var gridColumnCount: Int {
    let minItem: CGFloat = 280       // matches .adaptive(minimum: 280, …)
    let spacing: CGFloat = DT.Spacing.sm
    let usable = gridWidth - DT.Spacing.lg * 2  // matches .padding(DT.Spacing.lg)
    return max(1, Int(floor((usable + spacing) / (minItem + spacing))))
}
```

Movement:

```swift
private func moveHighlight(_ direction: ArrowDirection) {
    let list: [Project]
    let stride: Int
    switch appState.projectListMode {
    case .grid:
        list = navProjects
        stride = (direction == .up || direction == .down) ? gridColumnCount : 1
    case .table:
        list = sortedProjects
        guard direction == .up || direction == .down else { return }  // ←/→ ignored
        stride = 1
    }
    guard !list.isEmpty else { return }

    if let id = highlightedProjectID,
       let idx = list.firstIndex(where: { $0.id == id }) {
        let delta = (direction == .down || direction == .right) ? stride : -stride
        let raw = idx + delta
        let clamped = max(0, min(list.count - 1, raw))
        // Stop at edges: if the full stride overshoots, clamp to the last item
        // in that direction (Finder-style). No wrap around. No-op if already there.
        if clamped != idx {
            highlightedProjectID = list[clamped].id
        }
    } else {
        // Nothing highlighted yet: ↓/→ picks first; ↑/← no-op
        if direction == .down || direction == .right {
            highlightedProjectID = list.first?.id
        }
    }
}
```

Year boundaries are transparent in grid because column count is container-width-driven, not per-year. Arrowing ↓ from the last row of 2026 lands on the item one column to the right in 2025 (or the last item of 2025 if the target column doesn't exist — handled by the edge clamp).

#### Table

Same function, `stride = 1`, ←/→ return early. `sortedProjects` is the same list the table renders.

### Auto-scroll

Wrap both `gridView`'s `ScrollView` and `tableView`'s `ScrollView` in `ScrollViewReader`. On `highlightedProjectID` change, call `proxy.scrollTo(id, anchor: .center)` inside a short `withAnimation(.easeInOut(duration: 0.15))`. Requires `.id(project.id)` on each card and each table row.

### Enter

```swift
private func openHighlighted() {
    guard let id = highlightedProjectID,
          let project = appState.filteredProjects.first(where: { $0.id == id })
    else { return }
    appState.setSelectedProject(project)
}
```

### ⌘4 adjustment

The existing handler resolves hover per mode. Extend to prefer keyboard highlight:

```swift
let targetID = highlightedProjectID ?? {
    switch appState.projectListMode {
    case .grid:  return hoveredGridProjectID
    case .table: return hoveredProjectID
    }
}()
```

### ESC extension

The existing ESC handler clears the filter. Extend to also clear `highlightedProjectID` in the same press:

```swift
Button("") {
    if highlightedProjectID != nil {
        highlightedProjectID = nil
    }
    if !appState.searchQuery.isEmpty {
        appState.searchQuery = ""
    }
}
.keyboardShortcut(.escape, modifiers: [])
```

Both no-ops when both are empty. No two-step behavior.

### Cleanup

- `.onChange(of: appState.projectListMode)` — clear `highlightedProjectID` (alongside the existing `hoveredGridProjectID` clear).
- `.onChange(of: appState.filteredProjects)` — if `highlightedProjectID` no longer exists in the new list, clear it.

### State summary

| State | Owner | Purpose |
|---|---|---|
| `highlightedProjectID` | `ProjectListView` (new) | Keyboard-driven highlight, unified across modes |
| `filterFocused` | `ProjectListView` (new, `@FocusState`) | Gates arrow/Return so they don't steal from TextField cursor |
| `gridWidth` | `ProjectListView` (new) | Measured width for column-count derivation |
| `hoveredGridProjectID` | `ProjectListView` (existing) | Mouse hover in grid; unchanged |
| `hoveredProjectID` | `ProjectListView` (existing) | Mouse hover in table; unchanged |
| `projectForSettings` | `ProjectListView` (existing) | Settings sheet; unchanged |

## Non-goals

- No wrap at edges.
- No PageUp/PageDown/Home/End.
- No Tab focus cycle, no multi-select.
- No ring-style focus decoration distinct from hover border — one shared visual.
- No arrow-key nav inside the settings sheet or detail view (those have their own input loops).
- No changes to existing mouse/context-menu/⌘-shortcut behavior beyond the ⌘4 and ESC extensions listed above.

## Testing

Matches the existing project convention (no SwiftUI view tests). Manual verification:

- **Grid ↓:** filter empty, nothing highlighted → ↓ highlights top-left card. Continued ↓ traverses by `gridColumnCount` rows. Stops at last item.
- **Grid ↑/←/→:** symmetric, stops at first item / row edges.
- **Grid resize:** change window width → column count recomputes → next ↑/↓ uses new stride. (Existing highlight does not jump.)
- **Year boundary:** highlight on last card of 2026, ↓ → lands on the next card in the flat list (typically first of 2025 in the same column, or the last item of 2025 if fewer items).
- **Table ↑/↓:** moves row-by-row. ←/→ no-op.
- **Filter focus:** click into the filter field → type → arrow keys move text cursor, do NOT move highlight. Click out of filter → arrow keys resume navigation.
- **Enter:** arrow to a card → press Enter → detail view opens for that project.
- **⌘4:** arrow to a card → press ⌘4 → settings sheet opens (not hover-dependent anymore when keyboard is in play).
- **ESC:** filter has text, highlight is set → one ESC clears both. Both empty → ESC is no-op.
- **Auto-scroll:** arrow ↓ past the viewport → the scroll view animates so the highlighted card is centered.
- **Mode switch:** highlight set in grid, ⌘2 → table → highlight cleared. ⌘1 back → grid starts fresh.
- **Filter change:** highlight a project, type in filter until it's filtered out → highlight clears.

## Risks

- **GeometryReader-in-background:** the documented pattern (per memory) is safe when the GeometryReader is in `.background(…)` with a `Color.clear` base, not wrapping the content. Spec uses this pattern; risk is low.
- **`@FocusState` on `.textFieldStyle(.plain)`:** plain-styled TextFields in SwiftUI still honor `@FocusState` on macOS 14+. If it doesn't fire reliably, fallback is an `NSEvent` local monitor that checks `NSApp.keyWindow?.firstResponder`. Plan flags this as the fallback path, not applied preemptively.
- **Arrow keys inside settings sheet:** the sheet has its own focus context; SwiftUI routes keys to the sheet's first responder when it's the key window. Hidden shortcuts on the list view under the sheet should not fire. Verify during manual test; if they do fire, gate the arrow buttons on `projectForSettings == nil` too.

## Files touched

- `PortyMcFolio/Views/ProjectListView.swift` — all changes.

No other files modified.
