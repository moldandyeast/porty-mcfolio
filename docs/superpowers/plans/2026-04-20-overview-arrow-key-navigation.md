# Arrow-Key Navigation for Project Overview — Implementation Plan

> **Plan is historical.** This plan was executed but several decisions were revised after code review (2026-04-21). For the current contract, see the "Post-implementation revisions" section in the spec: `docs/superpowers/specs/2026-04-20-overview-arrow-key-navigation-design.md`. Key deltas: `⌘+arrow` (not bare arrows), split `hoveredProjectID`/`keyboardSelectedProjectID` state, Return gated to keyboard selection, auto-scroll gated to keyboard changes.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add ↑/↓/←/→ navigation + Return-to-open for the project overview (grid and table), with auto-scroll, sticky keyboard highlight that coexists with mouse hover, filter-field passthrough, and one-press ESC that clears both highlight and filter.

**Architecture:** Introduce one new pure-logic service `ProjectNavigation` (in `PortyMcFolio/Services/`) that computes the next highlight ID from (current, list, direction, columnCount, mode). All view wiring — state, key bindings, visual border, auto-scroll — lives inside `PortyMcFolio/Views/ProjectListView.swift`. Column count is measured via a `.background(GeometryReader { … })` pattern (never inside the ScrollView content — see memory).

**Tech Stack:** SwiftUI macOS 14+ (deployment 15.0), AppKit, XCTest. No new Swift-Package deps. XcodeGen regeneration required once (adding two new files).

**Spec:** `docs/superpowers/specs/2026-04-20-overview-arrow-key-navigation-design.md`
**Stacks on:** `feature/overview-shortcuts` — the six commits from the previous feature are already in place.

---

## File map

| File | Change |
|---|---|
| `PortyMcFolio/Services/ProjectNavigation.swift` | **Create.** Pure `enum ProjectNavigation` with `Direction`, `Mode`, and `nextHighlightID(...)` static function. |
| `PortyMcFolioTests/ProjectNavigationTests.swift` | **Create.** XCTest unit tests for the helper covering nine edge cases. |
| `PortyMcFolio/Views/ProjectListView.swift` | Modify. New state, `@FocusState`, `.background(GeometryReader)` for width, hidden keyboard buttons, visual extensions, ⌘4/ESC tweaks, ScrollViewReader auto-scroll, cleanup hooks. |
| `project.yml` | **Not modified.** XcodeGen's recursive `sources: PortyMcFolio` and `sources: PortyMcFolioTests` picks up the new files automatically. |
| `PortyMcFolio.xcodeproj/project.pbxproj` | Regenerated via `xcodegen generate`. Committed as part of Task 2. |

## Shared commands

**Build** (run after each task unless noted):
```bash
cd <repo>/.worktrees/overview-shortcuts && \
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' -quiet build 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **` (or exit 0). Pre-existing warnings about `appearanceSignal` actor isolation and `FSEventStreamScheduleWithRunLoop` deprecation are fine; ANY NEW warning or error blocks progression.

**Test** (after Task 2 only — the only task that adds unit tests):
```bash
cd <repo>/.worktrees/overview-shortcuts && \
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' \
  -only-testing:PortyMcFolioTests/ProjectNavigationTests \
  test 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`, all cases green.

**XcodeGen regeneration** (once, Task 2):
```bash
cd <repo>/.worktrees/overview-shortcuts && xcodegen generate 2>&1 | tail -5
```
Expected: `Created project at ...`.

---

### Task 1: Add new state + `@FocusState` on the filter field

Pure scaffolding — no behavior change. Gives later tasks something to bind to.

**Files:**
- Modify: `PortyMcFolio/Views/ProjectListView.swift`

- [ ] **Step 1: Declare the three new state properties**

Near the existing `@State private var projectToDelete: Project?` and `@State private var projectForSettings: Project?` at the top of `struct ProjectListView`, add:

```swift
@State private var highlightedProjectID: String?
@State private var gridWidth: CGFloat = 0
@FocusState private var filterFocused: Bool
```

- [ ] **Step 2: Bind `@FocusState` to the filter `TextField`**

In the toolbar's principal `ToolbarItem` (around current line 65-91), the filter TextField reads:

```swift
TextField("Filter\u{2026}", text: $appState.searchQuery)
    .textFieldStyle(.plain)
    .font(DT.Typography.body)
```

Add `.focused($filterFocused)` after `.font(...)`:

```swift
TextField("Filter\u{2026}", text: $appState.searchQuery)
    .textFieldStyle(.plain)
    .font(DT.Typography.body)
    .focused($filterFocused)
```

- [ ] **Step 3: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd <repo>/.worktrees/overview-shortcuts && \
git add PortyMcFolio/Views/ProjectListView.swift && \
git commit -m "feat(overview): scaffold keyboard-nav state and filter focus gate"
```

---

### Task 2: Pure nav helper `ProjectNavigation` + unit tests (TDD)

Extract the navigation math into a pure service with exhaustive test coverage.

**Files:**
- Create: `PortyMcFolio/Services/ProjectNavigation.swift`
- Create: `PortyMcFolioTests/ProjectNavigationTests.swift`
- Regenerate: `PortyMcFolio.xcodeproj/project.pbxproj` (via `xcodegen generate`)

- [ ] **Step 1: Write failing tests first**

Create `PortyMcFolioTests/ProjectNavigationTests.swift` with:

```swift
import XCTest
@testable import PortyMcFolio

final class ProjectNavigationTests: XCTestCase {
    private let list = ["a", "b", "c", "d", "e", "f", "g"]
    // ^ 7 IDs — enough to test a 3-column grid (3 full + 1 partial row)

    // MARK: - Grid mode

    func testGridDownByColumnCount() {
        let next = ProjectNavigation.nextHighlightID(
            current: "a", in: list, direction: .down, columnCount: 3, mode: .grid
        )
        XCTAssertEqual(next, "d")
    }

    func testGridRightByOne() {
        let next = ProjectNavigation.nextHighlightID(
            current: "a", in: list, direction: .right, columnCount: 3, mode: .grid
        )
        XCTAssertEqual(next, "b")
    }

    func testGridUpFromSecondRow() {
        let next = ProjectNavigation.nextHighlightID(
            current: "d", in: list, direction: .up, columnCount: 3, mode: .grid
        )
        XCTAssertEqual(next, "a")
    }

    func testGridDownOvershootClampsToLast() {
        // From "f" (index 5) ↓ by 3 = index 8, clamps to last (index 6 = "g")
        let next = ProjectNavigation.nextHighlightID(
            current: "f", in: list, direction: .down, columnCount: 3, mode: .grid
        )
        XCTAssertEqual(next, "g")
    }

    func testGridUpFromFirstItemNoOp() {
        // At index 0, ↑ clamps to 0 — same as current, returns current unchanged
        let next = ProjectNavigation.nextHighlightID(
            current: "a", in: list, direction: .up, columnCount: 3, mode: .grid
        )
        XCTAssertEqual(next, "a")
    }

    func testGridLeftFromFirstItemNoOp() {
        let next = ProjectNavigation.nextHighlightID(
            current: "a", in: list, direction: .left, columnCount: 3, mode: .grid
        )
        XCTAssertEqual(next, "a")
    }

    func testGridRightFromLastItemNoOp() {
        let next = ProjectNavigation.nextHighlightID(
            current: "g", in: list, direction: .right, columnCount: 3, mode: .grid
        )
        XCTAssertEqual(next, "g")
    }

    // MARK: - Empty / nil / stale state

    func testEmptyListReturnsCurrent() {
        let next = ProjectNavigation.nextHighlightID(
            current: "x", in: [], direction: .down, columnCount: 3, mode: .grid
        )
        XCTAssertEqual(next, "x")
    }

    func testNilCurrentDownPicksFirst() {
        let next = ProjectNavigation.nextHighlightID(
            current: nil, in: list, direction: .down, columnCount: 3, mode: .grid
        )
        XCTAssertEqual(next, "a")
    }

    func testNilCurrentRightPicksFirst() {
        let next = ProjectNavigation.nextHighlightID(
            current: nil, in: list, direction: .right, columnCount: 3, mode: .grid
        )
        XCTAssertEqual(next, "a")
    }

    func testNilCurrentUpNoOp() {
        let next = ProjectNavigation.nextHighlightID(
            current: nil, in: list, direction: .up, columnCount: 3, mode: .grid
        )
        XCTAssertNil(next)
    }

    func testNilCurrentLeftNoOp() {
        let next = ProjectNavigation.nextHighlightID(
            current: nil, in: list, direction: .left, columnCount: 3, mode: .grid
        )
        XCTAssertNil(next)
    }

    func testStaleCurrentTreatedAsNil() {
        // "zzz" is not in the list — should behave like nil-current, ↓ picks first
        let next = ProjectNavigation.nextHighlightID(
            current: "zzz", in: list, direction: .down, columnCount: 3, mode: .grid
        )
        XCTAssertEqual(next, "a")
    }

    // MARK: - Table mode

    func testTableDownByOne() {
        let next = ProjectNavigation.nextHighlightID(
            current: "a", in: list, direction: .down, columnCount: 99, mode: .table
        )
        XCTAssertEqual(next, "b")
    }

    func testTableUpByOne() {
        let next = ProjectNavigation.nextHighlightID(
            current: "c", in: list, direction: .up, columnCount: 99, mode: .table
        )
        XCTAssertEqual(next, "b")
    }

    func testTableLeftNoOp() {
        // Table ignores horizontal arrows — returns current
        let next = ProjectNavigation.nextHighlightID(
            current: "c", in: list, direction: .left, columnCount: 99, mode: .table
        )
        XCTAssertEqual(next, "c")
    }

    func testTableRightNoOp() {
        let next = ProjectNavigation.nextHighlightID(
            current: "c", in: list, direction: .right, columnCount: 99, mode: .table
        )
        XCTAssertEqual(next, "c")
    }

    // MARK: - Column count edge

    func testGridColumnCountZeroTreatedAsOne() {
        // Defensive: columnCount=0 shouldn't crash; treat as 1.
        let next = ProjectNavigation.nextHighlightID(
            current: "a", in: list, direction: .down, columnCount: 0, mode: .grid
        )
        XCTAssertEqual(next, "b")
    }
}
```

- [ ] **Step 2: Create the implementation file**

Create `PortyMcFolio/Services/ProjectNavigation.swift`:

```swift
import Foundation

/// Pure, view-free navigation math for the project overview (grid and table).
///
/// Given a current highlighted ID and the visible, ordered list, compute the next ID
/// for an arrow-key move. Matches Finder semantics: stop at edges (no wrap), soft-clamp
/// when a stride overshoots so the last item is always reachable.
enum ProjectNavigation {
    enum Direction {
        case up, down, left, right
    }

    enum Mode {
        case grid, table
    }

    /// Returns the new highlight ID for an arrow press.
    ///
    /// - `current`: the currently-highlighted ID, or nil if nothing is highlighted.
    /// - `list`: the ordered IDs the user sees (year-desc for grid, sort-order for table).
    /// - `direction`: which arrow was pressed.
    /// - `columnCount`: grid columns (ignored in table mode; `0` is treated as `1`).
    /// - `mode`: grid or table. Table ignores horizontal arrows.
    ///
    /// Returns nil only when `current` was nil AND the direction is ↑/← (nothing to do).
    /// When `current` is non-nil and the move would overshoot, returns the clamped edge ID.
    /// If `current` is already at the clamped edge (or list is empty), returns `current` unchanged.
    static func nextHighlightID(
        current: String?,
        in list: [String],
        direction: Direction,
        columnCount: Int,
        mode: Mode
    ) -> String? {
        guard !list.isEmpty else { return current }

        let stride: Int
        switch mode {
        case .grid:
            stride = (direction == .up || direction == .down) ? max(1, columnCount) : 1
        case .table:
            if direction == .left || direction == .right { return current }
            stride = 1
        }

        // Resolve current index, treating missing/stale as "nothing highlighted".
        let idx: Int? = current.flatMap { list.firstIndex(of: $0) }

        if let idx {
            let delta = (direction == .down || direction == .right) ? stride : -stride
            let clamped = max(0, min(list.count - 1, idx + delta))
            return clamped == idx ? current : list[clamped]
        } else {
            // Nothing highlighted (or stale ID): ↓/→ picks first, ↑/← is no-op.
            switch direction {
            case .down, .right: return list.first
            case .up, .left:    return current  // nil stays nil
            }
        }
    }
}
```

- [ ] **Step 3: Regenerate xcodeproj so the new files are part of both targets**

```bash
cd <repo>/.worktrees/overview-shortcuts && xcodegen generate 2>&1 | tail -3
```
Expected: `Created project at ...`.

- [ ] **Step 4: Run the new tests**

```bash
cd <repo>/.worktrees/overview-shortcuts && \
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' \
  -only-testing:PortyMcFolioTests/ProjectNavigationTests \
  test 2>&1 | tail -20
```
Expected: all 17 test cases pass, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd <repo>/.worktrees/overview-shortcuts && \
git add PortyMcFolio/Services/ProjectNavigation.swift \
        PortyMcFolioTests/ProjectNavigationTests.swift \
        PortyMcFolio.xcodeproj/project.pbxproj && \
git commit -m "feat(nav): pure ProjectNavigation helper with TDD coverage"
```

---

### Task 3: Measure grid container width

Set up the `PreferenceKey` + `.background(GeometryReader { … })` pattern so `gridWidth` tracks the available grid width. No consumer yet.

**Files:**
- Modify: `PortyMcFolio/Views/ProjectListView.swift`

- [ ] **Step 1: Add a PreferenceKey at file scope**

At the very top of `ProjectListView.swift`, AFTER the existing `import` statements and BEFORE `struct ProjectListView`, add:

```swift
private struct GridWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
```

- [ ] **Step 2: Attach the measuring overlay to the grid's outer container**

In `gridView` (around current lines 164-206), the current structure is:

```swift
private var gridView: some View {
    ScrollView {
        LazyVStack(alignment: .leading, spacing: 48) {
            ForEach(projectsByYear, id: \.year) { group in
                ...
            }
        }
        .padding(DT.Spacing.lg)
    }
}
```

Wrap the `ScrollView { … }` with a GeometryReader-in-background for width measurement. Replace with:

```swift
private var gridView: some View {
    ScrollView {
        LazyVStack(alignment: .leading, spacing: 48) {
            ForEach(projectsByYear, id: \.year) { group in
                ...
            }
        }
        .padding(DT.Spacing.lg)
    }
    .background(
        GeometryReader { geo in
            Color.clear.preference(
                key: GridWidthPreferenceKey.self,
                value: geo.size.width
            )
        }
    )
    .onPreferenceChange(GridWidthPreferenceKey.self) { gridWidth = $0 }
}
```

`.background(GeometryReader { … })` measures the parent size without participating in layout or hit-testing — this is the documented-in-memory safe pattern for ScrollView-adjacent geometry. Naming the inner reader `geo` (not `proxy`) leaves `proxy` free for the `ScrollViewReader` added in Task 7.

- [ ] **Step 3: Add a derived `gridColumnCount` computed property**

Inside `struct ProjectListView`, near the existing private helpers (e.g., just above `private var gridView: some View`), add:

```swift
/// Number of columns the adaptive LazyVGrid will produce at the current width.
/// Mirrors the math SwiftUI does internally: floor((available + spacing) / (minItem + spacing)).
private var gridColumnCount: Int {
    let minItem: CGFloat = 280                    // GridItem(.adaptive(minimum: 280, …))
    let spacing: CGFloat = DT.Spacing.sm          // columns' internal spacing
    let usable = gridWidth - DT.Spacing.lg * 2    // matches .padding(DT.Spacing.lg)
    guard usable > 0 else { return 1 }
    return max(1, Int(floor((usable + spacing) / (minItem + spacing))))
}
```

- [ ] **Step 4: Build**

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd <repo>/.worktrees/overview-shortcuts && \
git add PortyMcFolio/Views/ProjectListView.swift && \
git commit -m "feat(overview): measure grid width for column-count derivation"
```

---

### Task 4: Extend hover border to react to `highlightedProjectID`

Wire the keyboard highlight into the existing visual cues. No key bindings yet — just make the view light up when `highlightedProjectID` changes.

**Files:**
- Modify: `PortyMcFolio/Views/ProjectListView.swift`

- [ ] **Step 1: Update the grid card overlay condition**

In `gridView`'s `ForEach` (from the previous feature), the card block is:

```swift
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
```

Replace the condition with an OR that includes the keyboard highlight:

```swift
.overlay(
    RoundedRectangle(cornerRadius: DT.Radius.large)
        .stroke(
            (hoveredGridProjectID == project.id || highlightedProjectID == project.id)
                ? theme.colors.accent.opacity(0.3)
                : Color.clear,
            lineWidth: 1
        )
        .allowsHitTesting(false)
)
```

- [ ] **Step 2: Update the table row's background condition**

In `tableDataRow` (around current lines 412-494), the `background` modifier currently reads:

```swift
.background(
    RoundedRectangle(cornerRadius: DT.Radius.small)
        .fill(
            isSelected ? theme.colors.accent.opacity(0.1) :
            isHovered ? theme.colors.surfaceHover.opacity(0.3) :
            Color.clear
        )
)
```

Before the `return HStack(...)` inside `tableDataRow`, add a local `isHighlighted`:

```swift
let isSelected = selectedProjectID == project.id
let isHovered = hoveredProjectID == project.id
let isHighlighted = highlightedProjectID == project.id
```

And update the `.fill(...)` ternary to treat highlight with the same weight as hover:

```swift
.fill(
    isSelected ? theme.colors.accent.opacity(0.1) :
    (isHovered || isHighlighted) ? theme.colors.surfaceHover.opacity(0.3) :
    Color.clear
)
```

- [ ] **Step 3: Build**

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd <repo>/.worktrees/overview-shortcuts && \
git add PortyMcFolio/Views/ProjectListView.swift && \
git commit -m "feat(overview): highlight border reacts to keyboard selection"
```

---

### Task 5: Wire arrow keys + Return

Add the hidden keyboard shortcut buttons and the view-level nav methods that call into `ProjectNavigation`.

**Files:**
- Modify: `PortyMcFolio/Views/ProjectListView.swift`

- [ ] **Step 1: Add `navProjects`, `moveHighlight`, `openHighlighted` to `ProjectListView`**

Inside `struct ProjectListView`, in a convenient spot (e.g., just above `// MARK: - Context Menu`), add:

```swift
// MARK: - Keyboard navigation

/// Flat list of projects in the same order the user sees them in the grid
/// (year-desc, creation order within year). Used for arrow-key nav in grid mode.
private var navProjects: [Project] {
    projectsByYear.flatMap { $0.projects }
}

private func moveHighlight(_ direction: ProjectNavigation.Direction) {
    let ids: [String]
    let mode: ProjectNavigation.Mode
    switch appState.projectListMode {
    case .grid:
        ids = navProjects.map { $0.id }
        mode = .grid
    case .table:
        ids = sortedProjects.map { $0.id }
        mode = .table
    }
    highlightedProjectID = ProjectNavigation.nextHighlightID(
        current: highlightedProjectID,
        in: ids,
        direction: direction,
        columnCount: gridColumnCount,
        mode: mode
    )
}

private func openHighlighted() {
    guard let id = highlightedProjectID,
          let project = appState.filteredProjects.first(where: { $0.id == id })
    else { return }
    appState.setSelectedProject(project)
}
```

- [ ] **Step 2: Add 5 hidden buttons to the existing `.background` block**

The existing `.background { … }` block (from the previous feature) has two buttons (ESC + ⌘4). Append five more siblings inside the same block. The full merged block becomes:

```swift
.background {
    // ESC clears filter; .escape (not .cancelAction) because sheets have their own cancel bindings.
    Button("") {
        if !appState.searchQuery.isEmpty {
            appState.searchQuery = ""
        }
    }
    .keyboardShortcut(.escape, modifiers: [])
    .opacity(0)
    .allowsHitTesting(false)

    // ⌘4 opens settings for the hovered project (grid or table mode).
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

    // Arrow keys + Return — disabled while the filter text field has focus
    // so the TextField's cursor handling wins.
    Button("") { moveHighlight(.up) }
        .keyboardShortcut(.upArrow, modifiers: [])
        .disabled(filterFocused)
        .opacity(0)
        .allowsHitTesting(false)

    Button("") { moveHighlight(.down) }
        .keyboardShortcut(.downArrow, modifiers: [])
        .disabled(filterFocused)
        .opacity(0)
        .allowsHitTesting(false)

    Button("") { moveHighlight(.left) }
        .keyboardShortcut(.leftArrow, modifiers: [])
        .disabled(filterFocused)
        .opacity(0)
        .allowsHitTesting(false)

    Button("") { moveHighlight(.right) }
        .keyboardShortcut(.rightArrow, modifiers: [])
        .disabled(filterFocused)
        .opacity(0)
        .allowsHitTesting(false)

    Button("") { openHighlighted() }
        .keyboardShortcut(.return, modifiers: [])
        .disabled(filterFocused)
        .opacity(0)
        .allowsHitTesting(false)
}
```

- [ ] **Step 3: Build**

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd <repo>/.worktrees/overview-shortcuts && \
git add PortyMcFolio/Views/ProjectListView.swift && \
git commit -m "feat(overview): arrow keys + Return navigate project overview"
```

---

### Task 6: Extend ⌘4 and ESC to prefer keyboard highlight

Small tweaks so both shortcuts target `highlightedProjectID` first.

**Files:**
- Modify: `PortyMcFolio/Views/ProjectListView.swift`

- [ ] **Step 1: Update the ⌘4 button action**

In the same `.background { … }` block, the ⌘4 button currently reads:

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
```

Change it to prefer `highlightedProjectID`:

```swift
Button("") {
    let targetID: String? = highlightedProjectID ?? {
        switch appState.projectListMode {
        case .grid:  return hoveredGridProjectID
        case .table: return hoveredProjectID
        }
    }()
    guard let id = targetID,
          let project = appState.filteredProjects.first(where: { $0.id == id })
    else { return }
    projectForSettings = project
}
```

- [ ] **Step 2: Update the ESC button action**

The existing ESC button reads:

```swift
Button("") {
    if !appState.searchQuery.isEmpty {
        appState.searchQuery = ""
    }
}
```

Extend to clear the keyboard highlight in the same press:

```swift
Button("") {
    if highlightedProjectID != nil {
        highlightedProjectID = nil
    }
    if !appState.searchQuery.isEmpty {
        appState.searchQuery = ""
    }
}
```

Both blocks no-op when both are empty.

- [ ] **Step 3: Build**

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd <repo>/.worktrees/overview-shortcuts && \
git add PortyMcFolio/Views/ProjectListView.swift && \
git commit -m "feat(overview): ⌘4 and ESC prefer keyboard highlight"
```

---

### Task 7: Auto-scroll the highlighted card/row into view

Wrap the existing `ScrollView` bodies in a `ScrollViewReader` and `.scrollTo(...)` on `highlightedProjectID` change. Requires `.id(project.id)` on each card and each table row.

**Files:**
- Modify: `PortyMcFolio/Views/ProjectListView.swift`

- [ ] **Step 1: Wrap `gridView`'s ScrollView in a ScrollViewReader**

Change `gridView` from:

```swift
private var gridView: some View {
    ScrollView {
        LazyVStack(alignment: .leading, spacing: 48) {
            ForEach(projectsByYear, id: \.year) { group in
                ...
            }
        }
        .padding(DT.Spacing.lg)
    }
    .background(...)
    .onPreferenceChange(...) { ... }
}
```

to:

```swift
private var gridView: some View {
    ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 48) {
                ForEach(projectsByYear, id: \.year) { group in
                    ...
                }
            }
            .padding(DT.Spacing.lg)
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: GridWidthPreferenceKey.self,
                    value: geo.size.width
                )
            }
        )
        .onPreferenceChange(GridWidthPreferenceKey.self) { gridWidth = $0 }
        .onChange(of: highlightedProjectID) { _, newValue in
            guard let id = newValue else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }
}
```

The inner `GeometryReader` binding is renamed to `geo` to avoid shadowing the outer `ScrollViewReader`'s `proxy` — `.onChange` needs the outer one for `scrollTo`.

- [ ] **Step 2: Add `.id(project.id)` to each grid card**

In the `ForEach(group.projects) { project in ... }` block, the card invocation ends with `.contextMenu { projectContextMenu(for: project) }`. Append `.id(project.id)`:

```swift
ProjectCardView(...)
    .overlay(...)
    .onHover { ... }
    .contextMenu { projectContextMenu(for: project) }
    .id(project.id)
```

- [ ] **Step 3: Wrap `tableView`'s ScrollView in a ScrollViewReader**

`tableView` currently reads:

```swift
private var tableView: some View {
    GeometryReader { geo in
        let c = Col.widths(for: geo.size.width - DT.Spacing.lg * 2)

        VStack(spacing: 0) {
            tableHeaderRow(c: c)
                .padding(.horizontal, DT.Spacing.lg)

            Rectangle()
                .fill(theme.colors.border)
                .frame(height: 0.5)
                .padding(.horizontal, DT.Spacing.lg)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sortedProjects) { project in
                        tableDataRow(project, c: c)
                            .padding(.horizontal, DT.Spacing.lg)
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}
```

Wrap the inner `ScrollView { … }` in a `ScrollViewReader`. Replace the ScrollView block with:

```swift
ScrollViewReader { proxy in
    ScrollView {
        LazyVStack(spacing: 0) {
            ForEach(sortedProjects) { project in
                tableDataRow(project, c: c)
                    .padding(.horizontal, DT.Spacing.lg)
                    .id(project.id)
            }
        }
        .padding(.top, 2)
    }
    .onChange(of: highlightedProjectID) { _, newValue in
        guard let id = newValue,
              appState.projectListMode == .table
        else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            proxy.scrollTo(id, anchor: .center)
        }
    }
}
```

The `appState.projectListMode == .table` guard prevents the table's onChange from firing when the user is in grid mode (both views receive the change signal even if only one is visible).

Symmetrically, add the same mode guard to the grid's `onChange` from Step 1. Update it to:

```swift
.onChange(of: highlightedProjectID) { _, newValue in
    guard let id = newValue,
          appState.projectListMode == .grid
    else { return }
    withAnimation(.easeInOut(duration: 0.15)) {
        proxy.scrollTo(id, anchor: .center)
    }
}
```

- [ ] **Step 4: Build**

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd <repo>/.worktrees/overview-shortcuts && \
git add PortyMcFolio/Views/ProjectListView.swift && \
git commit -m "feat(overview): auto-scroll highlighted card into view"
```

---

### Task 8: Cleanup hooks — clear highlight on mode/filter change

Prevents stale highlights.

**Files:**
- Modify: `PortyMcFolio/Views/ProjectListView.swift`

- [ ] **Step 1: Extend the existing `onChange(projectListMode)` handler**

The previous feature introduced (and then amended):

```swift
.onChange(of: appState.projectListMode) { _, _ in
    selectedProjectID = nil
    hoveredGridProjectID = nil
}
```

Extend to also clear the keyboard highlight:

```swift
.onChange(of: appState.projectListMode) { _, _ in
    selectedProjectID = nil
    hoveredGridProjectID = nil
    highlightedProjectID = nil
}
```

- [ ] **Step 2: Add a new `onChange(filteredProjects)` handler to drop a now-hidden highlight**

The existing `.onChange(of: appState.filteredProjects) { _, newValue in projectsByYear = Self.computeProjectsByYear(newValue) }` is the update for the year grouping. Do NOT modify it; add a SEPARATE `.onChange` sibling near it (order within the same modifier chain):

```swift
.onChange(of: appState.filteredProjects) { _, newValue in
    if let id = highlightedProjectID,
       !newValue.contains(where: { $0.id == id }) {
        highlightedProjectID = nil
    }
}
```

Important: keep the existing `.onChange(of: appState.filteredProjects) { _, newValue in projectsByYear = ... }` handler as-is. SwiftUI fires ALL matching `.onChange` handlers on the same source in order.

- [ ] **Step 3: Build**

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd <repo>/.worktrees/overview-shortcuts && \
git add PortyMcFolio/Views/ProjectListView.swift && \
git commit -m "feat(overview): clear keyboard highlight on mode and filter change"
```

---

### Task 9: End-to-end manual verification (user-driven)

No code changes — this is the manual walkthrough that the controller (or user) runs with the app launched from the worktree's Xcode project.

- [ ] **Step 1: Launch the worktree's Xcode project + ⌘R**

If Xcode already has the worktree project open: ⌘R. Otherwise:

```bash
open <repo>/.worktrees/overview-shortcuts/PortyMcFolio.xcodeproj
```

Important: quit any existing running `PortyMcFolio` first (same bundle id would otherwise be reactivated, hiding the new build).

- [ ] **Step 2: Grid happy path**

With projects showing in grid mode (⌘1):
- Click away from the filter field. Press ↓. Expected: the top-left card gets the accent border.
- Press → three times. Expected: highlight moves right one card per press, clamps at end of row (if row is shorter than column count).
- Press ↓. Expected: highlight moves down by `gridColumnCount` cards.
- Press ↑ from the first row. Expected: highlight stays (stop at edge).
- Press Enter on a highlighted card. Expected: project detail view opens for that project. Press ESC to return.

- [ ] **Step 3: Grid + ⌘4**

Arrow to a card. Press ⌘4. Expected: settings sheet opens for that card (not the hovered one, even if a different card is under the mouse). Cancel the sheet.

- [ ] **Step 4: Grid auto-scroll**

Arrow ↓ repeatedly until the highlight would go off-screen. Expected: the scroll view animates the highlighted card into view (centered).

- [ ] **Step 5: Grid column-count reflow**

Resize the window wider or narrower. Press ↓. Expected: the stride of ↓ reflects the new column count (i.e., moves by the new number of columns).

- [ ] **Step 6: Filter focus passthrough**

Click into the filter field and type. Press arrow keys. Expected: arrow keys move the text cursor inside the filter, NOT the grid highlight. Press ESC. Expected: filter clears AND the highlight (if any) clears, in one press.

- [ ] **Step 7: Table mode**

⌘2 to switch to table. Expected: the grid highlight is cleared (mode switch).
- Press ↓. Expected: first row gets the hover-like background.
- Press ↓ repeatedly. Expected: highlight moves row-by-row.
- Press ← or →. Expected: nothing happens.
- Press Enter. Expected: project detail view opens.
- Press ⌘4 from a keyboard-highlighted row. Expected: settings sheet opens.
- Auto-scroll: arrow ↓ past viewport → row scrolls into view.

- [ ] **Step 8: Filter-driven highlight clear**

In grid mode, arrow to any card. Type in the filter until the highlighted card is filtered out. Expected: the highlight clears.

- [ ] **Step 9: Mode switch clears highlight**

In grid, arrow to a card. ⌘2 to table. Expected: highlight cleared. ⌘1 back to grid. Expected: no highlight.

- [ ] **Step 10: Edge case — empty filter result**

Type gibberish in the filter. Press ↓. Expected: no-op (no crash, no ghost highlight). Clear filter.

- [ ] **Step 11: Edge case — arrows while sheet open**

Open project settings (right-click → Project Settings…). Press arrow keys. Expected: the sheet's own input handles them (e.g., the title field). If the grid highlight visibly moves behind the sheet, report this and the plan will gate arrow buttons on `projectForSettings == nil`.

- [ ] **Step 12: Theme cycle**

Switch theme to `osx`, then `bw`. Confirm highlight border is readable (subtle but visible) in each theme × light/dark.

- [ ] **Step 13: Report**

If any step failed or looked off, describe which step and what you saw. Otherwise, confirm all pass — this closes the feature and the next step is merging the branch.

---

## Completion checklist

- [ ] All nine tasks complete
- [ ] `xcodebuild build` green
- [ ] `ProjectNavigationTests` all pass
- [ ] Eight new commits on `feature/overview-shortcuts` (plus Task 9 is no-commit)
- [ ] No `AppState` changes
- [ ] Manual verification passes in grid and table, porty/osx/bw × light/dark
