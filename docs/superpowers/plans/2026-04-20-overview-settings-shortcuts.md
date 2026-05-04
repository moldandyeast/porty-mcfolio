# Overview Filter + Per-Project Settings Shortcuts — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three ergonomics shortcuts to the project overview: ESC clears the filter, right-click exposes "Project Settings…", and ⌘4 opens settings for the hovered project in both grid and table modes.

**Architecture:** All changes in `PortyMcFolio/Views/ProjectListView.swift`. One shared `@ViewBuilder` for the context menu, one new `@State` for the settings-target project, one new `@State` for grid-hover tracking, two hidden buttons in `.background` for keyboard shortcuts. `ProjectSettingsPopover` is reused unchanged. No `AppState` additions.

**Tech Stack:** SwiftUI (macOS 14+, deployment 15.0), AppKit. No new deps.

**Testing note:** The project has no SwiftUI view tests by convention — `PortyMcFolioTests/` is all model/service tests. This plan uses build verification (`xcodebuild build`) after each task and manual interaction checks in the running app. Do **not** introduce a ViewInspector dependency or similar just to unit-test these UI hooks.

**Spec:** `docs/superpowers/specs/2026-04-20-overview-settings-shortcuts-design.md`

---

## File map

| File | Change |
|---|---|
| `PortyMcFolio/Views/ProjectListView.swift` | All edits below — add shared context menu, new state, new sheet, two hidden shortcut buttons, grid hover overlay |

Zero other files modified. `ProjectSettingsPopover.swift`, `AppState.swift`, `PortyMcFolioApp.swift`, `project.yml` all untouched.

## Shared commands

**Build check** (run after each task):
```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' -quiet build
```
Expected: `** BUILD SUCCEEDED **`. Any SwiftUI compile error blocks progression.

**Manual run** (run after each task where UI behavior is verified):
Build and launch via Xcode (⌘R), or:
```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' -derivedDataPath build -quiet build \
  && open build/Build/Products/Debug/PortyMcFolio.app
```

---

### Task 1: Extract shared context-menu builder (refactor, no behavior change)

The grid and table both define an identical `.contextMenu { Open / Delete }` block. Pull it out so the next task can add a third item in one place.

**Files:**
- Modify: `PortyMcFolio/Views/ProjectListView.swift`

- [ ] **Step 1: Add `projectContextMenu(for:)` helper**

Insert this helper inside `struct ProjectListView` — put it directly above the `// MARK: - Empty State` section (around current line 496):

```swift
// MARK: - Context Menu

@ViewBuilder
private func projectContextMenu(for project: Project) -> some View {
    Button { appState.setSelectedProject(project) } label: {
        Label("Open", systemImage: "doc.text")
    }
    Divider()
    Button(role: .destructive) { projectToDelete = project } label: {
        Label("Delete\u{2026}", systemImage: "trash")
    }
}
```

- [ ] **Step 2: Replace the grid card's context menu**

In `gridView` (around current lines 187-195), replace:

```swift
.contextMenu {
    Button { appState.setSelectedProject(project) } label: {
        Label("Open", systemImage: "doc.text")
    }
    Divider()
    Button(role: .destructive) { projectToDelete = project } label: {
        Label("Delete\u{2026}", systemImage: "trash")
    }
}
```

with:

```swift
.contextMenu { projectContextMenu(for: project) }
```

- [ ] **Step 3: Replace the table row's context menu**

In `tableDataRow` (around current lines 485-493), replace the identical block with:

```swift
.contextMenu { projectContextMenu(for: project) }
```

- [ ] **Step 4: Build**

Run the build check command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual verify — no regression**

Launch app, open a portfolio with projects. Right-click a grid card and a table row. Expected: menu shows `Open` and `Delete…` with a divider between — identical to before. Confirm `Open` navigates to detail view and `Delete…` opens the delete sheet.

- [ ] **Step 6: Commit**

```bash
git add PortyMcFolio/Views/ProjectListView.swift
git commit -m "refactor(overview): extract shared project context menu"
```

---

### Task 2: Add "Project Settings…" item + sheet

Hooks the context menu up to `ProjectSettingsPopover` so the user can edit metadata without entering the project.

**Files:**
- Modify: `PortyMcFolio/Views/ProjectListView.swift`

- [ ] **Step 1: Add `projectForSettings` state**

At the top of `struct ProjectListView`, next to the existing `@State private var projectToDelete: Project?` (around line 8), add:

```swift
@State private var projectForSettings: Project?
```

- [ ] **Step 2: Add the sheet presentation**

In the view body, find the existing `.sheet(item: $projectToDelete) { … }` block (around current lines 139-143). Add a sibling sheet below it:

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

- [ ] **Step 3: Add the menu item to the shared builder**

In `projectContextMenu(for:)` (from Task 1), insert the new button between `Open` and the `Divider`:

```swift
@ViewBuilder
private func projectContextMenu(for project: Project) -> some View {
    Button { appState.setSelectedProject(project) } label: {
        Label("Open", systemImage: "doc.text")
    }
    Button { projectForSettings = project } label: {
        Label("Project Settings\u{2026}", systemImage: "slider.horizontal.3")
    }
    Divider()
    Button(role: .destructive) { projectToDelete = project } label: {
        Label("Delete\u{2026}", systemImage: "trash")
    }
}
```

Note: intentionally NO `.keyboardShortcut("4", modifiers: .command)` on this button — the global ⌘4 handler added in Task 5 is the single source of truth. Binding it here too would double-fire.

- [ ] **Step 4: Build**

Run the build check command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual verify**

Launch the app.
- Right-click a grid card → menu shows `Open / Project Settings… / — / Delete…`. Click `Project Settings…`. Expected: the same sheet you see from detail view's ⌘4 opens, pre-populated with this project's fields.
- Edit the title, click Save. Expected: sheet closes, grid card reflects the new title (FileWatcher triggers refresh).
- Repeat the right-click test on a table row.

- [ ] **Step 6: Commit**

```bash
git add PortyMcFolio/Views/ProjectListView.swift
git commit -m "feat(overview): open project settings from right-click menu"
```

---

### Task 3: ESC clears filter

Hidden button in `.background` bound to ESC. Clears `appState.searchQuery` when non-empty; otherwise no-op.

**Files:**
- Modify: `PortyMcFolio/Views/ProjectListView.swift`

- [ ] **Step 1: Add the hidden ESC button**

At the very end of the view body — after the sheets, before the closing brace of `body` — add a `.background` modifier hosting a hidden button:

Find the end of the body (after the two `.sheet` modifiers added so far). Append:

```swift
.background {
    Button("") {
        if !appState.searchQuery.isEmpty {
            appState.searchQuery = ""
        }
    }
    .keyboardShortcut(.escape, modifiers: [])
    .opacity(0)
    .allowsHitTesting(false)
}
```

If a `.background { … }` block already exists from a later task, merge them — only one `.background` per view.

- [ ] **Step 2: Build**

Run the build check command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual verify**

Launch the app.
- Type "test" into the filter field (top toolbar). Press ESC. Expected: the field clears immediately.
- Press ESC again on the empty field. Expected: nothing visibly changes (no crash, no focus jump, no detail-view navigation — we're already in list view).
- Focus concern: if the TextField is focused when you press ESC, confirm it still clears. If the field editor intercepts ESC and the button doesn't fire, note this during manual test and see "Risk mitigation" below.

**Risk mitigation (only if step 3 shows ESC not firing when TextField is focused):** replace the hidden Button with a field-scoped handler. Wrap the TextField in a `ZStack` and attach:

```swift
.onExitCommand {
    if !appState.searchQuery.isEmpty { appState.searchQuery = "" }
}
```

`.onExitCommand` is a SwiftUI-native ESC hook that works on focused controls. Apply it to the TextField directly in the toolbar. If needed, the hidden background Button can stay for the unfocused case, and the `.onExitCommand` covers focused case.

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Views/ProjectListView.swift
git commit -m "feat(overview): ESC clears the filter field"
```

---

### Task 4: Grid hover state + visual cue

Adds `hoveredGridProjectID` tracking and a subtle accent-tinted border so the user can see which card ⌘4 would target. Table already has hover tracking (`hoveredProjectID`) — we don't touch it.

**Files:**
- Modify: `PortyMcFolio/Views/ProjectListView.swift`

- [ ] **Step 1: Add grid-hover state**

Near the other `@State` declarations at the top of `struct ProjectListView`, add:

```swift
@State private var hoveredGridProjectID: String?
```

- [ ] **Step 2: Wrap the grid card with hover tracking + overlay**

In `gridView`'s `ForEach` (around current lines 181-196), the card construction currently looks like:

```swift
ProjectCardView(project: project, onOpen: {
    appState.setSelectedProject(project)
}) { tag in
    appState.searchQuery = tag
}
.contextMenu { projectContextMenu(for: project) }
```

Replace with:

```swift
ProjectCardView(project: project, onOpen: {
    appState.setSelectedProject(project)
}) { tag in
    appState.searchQuery = tag
}
.overlay(
    RoundedRectangle(cornerRadius: DT.Radius.large)
        .stroke(
            hoveredGridProjectID == project.id
                ? theme.colors.accent.opacity(0.3)
                : Color.clear,
            lineWidth: 1
        )
        .allowsHitTesting(false)
)
.onHover { hovering in
    hoveredGridProjectID = hovering ? project.id : nil
}
.contextMenu { projectContextMenu(for: project) }
```

`.allowsHitTesting(false)` on the overlay is important — without it the stroke shape can swallow clicks and break `onTapGesture` inside the card.

- [ ] **Step 3: Build**

Run the build check command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual verify**

Launch the app with projects showing in grid mode.
- Move mouse over a card. Expected: a subtle 1px border in the accent color (~30% opacity) appears around the card.
- Mouse away. Expected: the border disappears.
- Click the card. Expected: navigates to detail view (the onTapGesture still fires — overlay is hit-disabled).
- Right-click the card. Expected: context menu works normally.

- [ ] **Step 5: Theme sanity**

In Settings, switch to each theme: `porty`, `osx`, `bw`. For each, verify the hover border is subtle but visible in both light and dark appearance. (macOS Settings → Appearance lets you toggle dark/light.) Expected: never invisible, never loud.

- [ ] **Step 6: Commit**

```bash
git add PortyMcFolio/Views/ProjectListView.swift
git commit -m "feat(overview): subtle hover border on grid cards"
```

---

### Task 5: ⌘4 opens settings for the hovered project

Global ⌘4 handler in `.background` that reads the hover state for the current mode and triggers the settings sheet.

**Files:**
- Modify: `PortyMcFolio/Views/ProjectListView.swift`

- [ ] **Step 1: Add the ⌘4 hidden button**

Merge into the same `.background { … }` block added in Task 3 (one `.background` per view). After Task 3 the block is:

```swift
.background {
    Button("") {
        if !appState.searchQuery.isEmpty {
            appState.searchQuery = ""
        }
    }
    .keyboardShortcut(.escape, modifiers: [])
    .opacity(0)
    .allowsHitTesting(false)
}
```

Replace with:

```swift
.background {
    Button("") {
        if !appState.searchQuery.isEmpty {
            appState.searchQuery = ""
        }
    }
    .keyboardShortcut(.escape, modifiers: [])
    .opacity(0)
    .allowsHitTesting(false)

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
}
```

- [ ] **Step 2: Build**

Run the build check command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual verify — grid**

Launch the app in grid mode.
- Hover a card (accent border from Task 4 confirms target). Press ⌘4. Expected: settings sheet opens for that project.
- Close sheet. Move mouse off all cards (onto empty area). Press ⌘4. Expected: nothing happens — no sheet, no flicker.

- [ ] **Step 4: Manual verify — table**

Switch to table mode (⌘2).
- Hover a row (existing hover background highlight confirms target). Press ⌘4. Expected: settings sheet opens for that project.
- Close sheet. Move mouse off all rows. Press ⌘4. Expected: no-op.

- [ ] **Step 5: Manual verify — conflict with detail view**

Select a project (⌘ click or Open). Press ⌘4 in detail view. Expected: detail view's own ⌘4 handler opens settings (preexisting behavior — not touched). Go back to list (ESC). Press ⌘4 without hovering. Expected: no-op. Hover → ⌘4 → sheet. Confirms the list and detail handlers don't interfere.

- [ ] **Step 6: Commit**

```bash
git add PortyMcFolio/Views/ProjectListView.swift
git commit -m "feat(overview): ⌘4 on hovered project opens settings"
```

---

### Task 6: End-to-end sanity pass

One final integrated walkthrough across both modes and all three themes to catch any regressions the per-task manual checks missed.

- [ ] **Step 1: Full interaction loop — grid**

In grid mode with `porty` theme, light appearance:
- Filter: type "a" → results filter. Press ESC → filter clears.
- Hover a card → border appears. ⌘4 → sheet opens. Save a trivial edit (e.g., reorder tags and restore). Close sheet → list reflects.
- Right-click a different card → `Project Settings…` → sheet opens for *that* card (not the hovered one, if different). Close.
- Click a card → detail view opens. ESC → back to list.

- [ ] **Step 2: Full interaction loop — table**

Switch to table mode (⌘2).
- Filter + ESC cycle — same as above.
- Hover a row → hover background. ⌘4 → sheet opens. Close.
- Right-click a row → `Project Settings…` → sheet. Close.
- Click a row → detail view. ESC → back to list.

- [ ] **Step 3: Theme cycle**

In App Settings, switch theme to `osx`, then `bw`. For each:
- Grid hover border is visible but subtle.
- Table hover background is unchanged from current behavior.
- Context menu readable.

- [ ] **Step 4: Dark mode spot check**

Toggle macOS appearance to Dark. Repeat quick grid-hover + ⌘4 check in each theme.

- [ ] **Step 5: No commit needed**

This task is verification only. If any step fails, return to the relevant task and fix before declaring done.

---

## Completion checklist

- [ ] All six tasks complete
- [ ] `xcodebuild build` is green
- [ ] All three features verified manually in grid mode
- [ ] All three features verified manually in table mode
- [ ] Hover border readable in porty/osx/bw × light/dark (6 combos)
- [ ] No new `AppState` fields, no changes outside `ProjectListView.swift`
- [ ] Five commits on the branch (one per Task 1–5)
