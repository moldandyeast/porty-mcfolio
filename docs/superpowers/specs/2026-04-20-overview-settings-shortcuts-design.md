# Overview Filter + Per-Project Settings Shortcuts

**Date:** 2026-04-20
**Scope:** `PortyMcFolio/Views/ProjectListView.swift`

## Summary

Three small ergonomics additions to the project-list overview (grid and table modes):

1. **ESC clears the filter** when the filter field has content.
2. **Right-click → "Project Settings…"** on any card or row opens the project's settings sheet directly from the list — no need to enter the project first.
3. **⌘4 on the hovered project** opens its settings sheet. Works in both grid and table modes; silent no-op when nothing is hovered.

All three changes live in `ProjectListView.swift`. No `AppState` additions. `ProjectSettingsPopover` is reused unchanged.

## Motivation

- The filter is in the toolbar and there's an `x` button to clear it, but no keyboard shortcut — ESC feels natural and is currently unused in list view.
- Editing a project's metadata (title, year, client, status, tags, teaser, hidden flag) currently requires opening the project (detail view) and then pressing ⌘4. For a light edit — e.g. correcting a tag, flipping a status — two navigations is more friction than necessary.
- ⌘4 matches the existing detail-view shortcut, so muscle memory carries across views.

## Design

### 1. ESC clears filter

Add a hidden button in the list view's `.background` with `.keyboardShortcut(.escape, modifiers: [])`:

```swift
Button("") {
    if !appState.searchQuery.isEmpty {
        appState.searchQuery = ""
    }
}
.keyboardShortcut(.escape, modifiers: [])
.opacity(0)
.allowsHitTesting(false)
```

Behavior:
- Filter has content → clear it.
- Filter empty → no-op (doesn't intercept ESC, leaving it free for future uses like arrow-key selection).

### 2. "Project Settings…" in context menu

Extract the duplicated context-menu block into a shared `@ViewBuilder`:

```swift
@ViewBuilder
private func projectContextMenu(for project: Project) -> some View {
    Button { appState.setSelectedProject(project) } label: {
        Label("Open", systemImage: "doc.text")
    }
    Button { projectForSettings = project } label: {
        Label("Project Settings…", systemImage: "slider.horizontal.3")
    }
    Divider()
    Button(role: .destructive) { projectToDelete = project } label: {
        Label("Delete…", systemImage: "trash")
    }
}
```

**Note on ⌘4 in the menu:** we do *not* attach `.keyboardShortcut("4", modifiers: .command)` to the menu item, because the ⌘4 global handler (Feature 3) already binds it. Two handlers = conflict. The shortcut is a hover-targeted action, not a right-click-targeted one, so showing it in the menu would also be misleading (the menu operates on the clicked project, the shortcut on the hovered project — usually the same, but not always).

The two existing `.contextMenu { … }` blocks (one on the grid card, one on the table row) are replaced with `.contextMenu { projectContextMenu(for: project) }`.

New state on `ProjectListView`:

```swift
@State private var projectForSettings: Project?
```

New sheet presentation (sibling to the existing `NewProjectSheet` and delete sheet):

```swift
.sheet(item: $projectForSettings) { project in
    ProjectSettingsPopover(
        project: project,
        isPresented: Binding(
            get: { projectForSettings != nil },
            set: { if !$0 { projectForSettings = nil } }
        )
    )
    .environmentObject(appState)
}
```

### 3. ⌘4 opens settings for hovered project

**New state:**
```swift
@State private var hoveredGridProjectID: String?
```
(Table view already has `hoveredProjectID`. We keep them separate so the two modes don't fight over the same state.)

**Grid hover tracking + visual cue:**

Each `ProjectCardView` in the grid wraps in a container that handles hover:

```swift
ProjectCardView(project: project, onOpen: { … }) { tag in … }
    .overlay(
        RoundedRectangle(cornerRadius: DT.Radius.large)
            .stroke(
                hoveredGridProjectID == project.id
                    ? theme.colors.accent.opacity(0.3)
                    : Color.clear,
                lineWidth: 1
            )
    )
    .onHover { hovering in
        hoveredGridProjectID = hovering ? project.id : nil
    }
    .contextMenu { projectContextMenu(for: project) }
```

The overlay is intentionally subtle — visible enough to confirm "⌘4 targets this card," not loud enough to compete with `dtShadow(DT.Shadow.card)` or the card content.

**⌘4 global handler** in the list view's `.background`:

```swift
Button("") {
    let hoveredID: String? = {
        switch appState.projectListMode {
        case .grid:  return hoveredGridProjectID
        case .table: return hoveredProjectID
        }
    }()
    guard let id = hoveredID,
          let project = appState.filteredProjects.first(where: { $0.id == id })
    else { return }
    projectForSettings = project
}
.keyboardShortcut("4", modifiers: .command)
.opacity(0)
.allowsHitTesting(false)
```

Behavior:
- Grid mode + card hovered → open its settings.
- Table mode + row hovered → open its settings.
- Neither → silent no-op.
- Uses `appState.filteredProjects` (same list the user is looking at).

### State summary

| State | Owner | Purpose |
|---|---|---|
| `hoveredGridProjectID` | `ProjectListView` (new) | Grid-mode ⌘4 target + hover visual |
| `hoveredProjectID` | `ProjectListView` (existing) | Table-mode ⌘4 target + row-hover background |
| `projectForSettings` | `ProjectListView` (new) | Drives the settings sheet |

Nothing leaks to `AppState`.

## Non-goals

- No arrow-key navigation / list selection model.
- No changes to the existing detail-view ⌘4 handler.
- No changes to `ProjectSettingsPopover` itself.
- No per-card "pinned" selection in grid; hover only.
- No new item in the App-level `CommandMenu("View")` — ⌘4 is a pointer-scoped shortcut, not a global one.

## Testing

XCTest doesn't cover SwiftUI interaction states well; these are all UI hooks, so manual verification is the main path:

- **ESC:** type in filter → press ESC → filter clears; press ESC again → no visible effect (no selection deselection, etc.).
- **Context menu (grid):** right-click a card → three items (Open / Project Settings… / Delete…); click Settings → sheet opens with that project's metadata.
- **Context menu (table):** same, from a table row.
- **⌘4 (grid):** hover a card → subtle accent border appears → ⌘4 → settings sheet for that card; mouse away → border fades → ⌘4 → no-op.
- **⌘4 (table):** hover a row → existing hover bg shows → ⌘4 → settings sheet for that row.
- **Sheet save flow:** edit a field → Save → sheet closes → list reflects change (same behavior as from detail view).
- **Theme sanity:** verify hover border is visible but subtle in all three themes (porty / osx / bw) in both light and dark.

## Files touched

- `PortyMcFolio/Views/ProjectListView.swift` — all changes.

Zero other files modified. `ProjectSettingsPopover.swift`, `AppState.swift`, `PortyMcFolioApp.swift` untouched.

## Risks

- **ESC interaction with focused text field:** when the filter `TextField` has focus, AppKit's field editor may consume ESC before the hidden SwiftUI button shortcut fires. If that happens, the fix is a small `NSViewRepresentable`-based key-monitor on the field OR binding `onSubmit`-style handling. Verify during implementation; fall back only if needed.
- **Hover state staleness:** if the user moves focus away from the window (⌘-tab) while hovering, the hover state may remain set. ⌘4 pressed via app-switcher before re-hovering could open settings for a stale target. Low severity — the user explicitly invoked the shortcut. No mitigation planned.
- **Sheet collision:** not possible — the list view and detail view are mutually exclusive in `ContentView`.
