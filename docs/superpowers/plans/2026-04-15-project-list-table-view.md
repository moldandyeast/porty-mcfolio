# Project List: Table View & DT Migration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a sortable table view to the project list page alongside the card grid, and migrate both to the DT design system.

**Architecture:** A new `ProjectListMode` enum toggles between grid and table in `ProjectListView`. The table uses SwiftUI's native `Table` with sortable columns. All visual styling migrates from hardcoded values to the existing `DT` design token namespace.

**Tech Stack:** SwiftUI `Table`, `KeyPathComparator`, `UserDefaults`, existing `DT` design tokens

**Spec:** `docs/superpowers/specs/2026-04-15-project-list-table-view.md`

---

### Task 1: Add `Comparable` to `ProjectStatus`

**Files:**
- Modify: `PortyMcFolio/Models/ProjectStatus.swift`
- Test: `PortyMcFolioTests/ProjectTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `PortyMcFolioTests/ProjectTests.swift`:

```swift
func testProjectStatusComparable() {
    let statuses: [ProjectStatus] = [.archived, .draft, .complete, .active]
    let sorted = statuses.sorted()
    XCTAssertEqual(sorted, [.draft, .active, .complete, .archived])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' 2>&1 | grep -E '(Test Case|FAIL|error:)'`

Expected: Compile error — `ProjectStatus` does not conform to `Comparable`.

- [ ] **Step 3: Add `Comparable` conformance**

In `PortyMcFolio/Models/ProjectStatus.swift`, change the declaration and add conformance:

```swift
enum ProjectStatus: String, Codable, CaseIterable, Identifiable, Comparable {
    case draft
    case active
    case complete
    case archived

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }

    // Comparable based on declaration order
    private var sortIndex: Int {
        switch self {
        case .draft: 0
        case .active: 1
        case .complete: 2
        case .archived: 3
        }
    }

    static func < (lhs: ProjectStatus, rhs: ProjectStatus) -> Bool {
        lhs.sortIndex < rhs.sortIndex
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' 2>&1 | grep -E '(Test Case|PASS|FAIL)'`

Expected: `testProjectStatusComparable` PASSES, all existing tests PASS.

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Models/ProjectStatus.swift PortyMcFolioTests/ProjectTests.swift
git commit -m "feat: add Comparable conformance to ProjectStatus"
```

---

### Task 2: Add `ProjectListMode` enum and AppState properties

**Files:**
- Modify: `PortyMcFolio/App/AppState.swift`

- [ ] **Step 1: Add the `ProjectListMode` enum above `ViewMode`**

At the top of `AppState.swift`, before the `ViewMode` enum:

```swift
enum ProjectListMode: String, CaseIterable {
    case grid
    case table
}
```

- [ ] **Step 2: Add published properties to `AppState`**

After the `splitRatio` property (line 21), add:

```swift
@Published var projectListMode: ProjectListMode = .grid {
    didSet { UserDefaults.standard.set(projectListMode.rawValue, forKey: "projectListMode") }
}

@Published var projectSortOrder: [KeyPathComparator<Project>] = [
    KeyPathComparator(\.year, order: .reverse)
] {
    didSet { persistSortOrder() }
}
```

- [ ] **Step 3: Add sort persistence helpers to `AppState`**

After the `loadLayoutPreferences()` method, add:

```swift
private func persistSortOrder() {
    guard let first = projectSortOrder.first else { return }
    let key: String
    switch first.keyPath {
    case \Project.year: key = "year"
    case \Project.title: key = "title"
    case \Project.client: key = "client"
    case \Project.status: key = "status"
    default: return
    }
    let dir = first.order == .forward ? "asc" : "desc"
    UserDefaults.standard.set("\(key)-\(dir)", forKey: "projectSortKey")
}

private func restoreSortOrder() {
    guard let raw = UserDefaults.standard.string(forKey: "projectSortKey") else { return }
    let parts = raw.split(separator: "-")
    guard parts.count == 2 else { return }
    let order: SortOrder = parts[1] == "asc" ? .forward : .reverse
    switch parts[0] {
    case "year": projectSortOrder = [KeyPathComparator(\Project.year, order: order)]
    case "title": projectSortOrder = [KeyPathComparator(\Project.title, order: order)]
    case "client": projectSortOrder = [KeyPathComparator(\Project.client, order: order)]
    case "status": projectSortOrder = [KeyPathComparator(\Project.status, order: order)]
    default: break
    }
}
```

- [ ] **Step 4: Restore preferences in `loadLayoutPreferences()`**

Add to the end of the existing `loadLayoutPreferences()` method:

```swift
if let listRaw = UserDefaults.standard.string(forKey: "projectListMode"),
   let mode = ProjectListMode(rawValue: listRaw) {
    projectListMode = mode
}
restoreSortOrder()
```

- [ ] **Step 5: Build to verify**

Run: `xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' build 2>&1 | tail -3`

Expected: `BUILD SUCCEEDED`

- [ ] **Step 6: Commit**

```bash
git add PortyMcFolio/App/AppState.swift
git commit -m "feat: add ProjectListMode enum and sort state to AppState"
```

---

### Task 3: Migrate `ProjectCardView` to DT tokens

**Files:**
- Modify: `PortyMcFolio/Views/ProjectCardView.swift`

- [ ] **Step 1: Update `ProjectCardView` body styling**

Replace the body of `ProjectCardView` (lines 53-101):

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 0) {
        if let image = teaserImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 120)
                .clipped()
        }

        VStack(alignment: .leading, spacing: DT.Spacing.sm) {
            HStack {
                Text(String(project.year))
                    .font(DT.Typography.caption)
                    .foregroundStyle(DT.Colors.textSecondary)
                Spacer()
                StatusBadgeView(status: project.status)
            }

            Text(project.title.isEmpty ? "Untitled" : project.title)
                .font(DT.Typography.headline)
                .foregroundStyle(DT.Colors.textPrimary)
                .lineLimit(2)

            if !project.client.isEmpty {
                Text(project.client)
                    .font(DT.Typography.body)
                    .foregroundStyle(DT.Colors.textSecondary)
                    .lineLimit(1)
            }

            if !project.tags.isEmpty {
                FlowLayout(spacing: DT.Spacing.xs) {
                    ForEach(project.tags, id: \.self) { tag in
                        TagPillView(tag: tag) {
                            onTagTap?(tag)
                        }
                    }
                }
            }
        }
        .padding(DT.Spacing.md)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(DT.Colors.surface)
    .clipShape(RoundedRectangle(cornerRadius: DT.Radius.medium))
    .dtShadow(DT.Shadow.card)
    .task {
        await loadTeaser()
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' build 2>&1 | tail -3`

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add PortyMcFolio/Views/ProjectCardView.swift
git commit -m "fix: migrate ProjectCardView to DT design tokens"
```

---

### Task 4: Migrate `ProjectListView` grid to DT tokens and add toolbar toggle

**Files:**
- Modify: `PortyMcFolio/Views/ProjectListView.swift`

- [ ] **Step 1: Update the grid constants and add a toolbar helper**

Replace the `columns` constant and update the body to switch on `projectListMode`. Replace the full file:

```swift
import SwiftUI
import AppKit

struct ProjectListView: View {
    @EnvironmentObject var appState: AppState
    @State private var isShowingStyleGuide = false

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 400), spacing: DT.Spacing.lg)
    ]

    var body: some View {
        Group {
            if appState.projects.isEmpty {
                emptyState
            } else {
                switch appState.projectListMode {
                case .grid:
                    gridView
                case .table:
                    tableView
                }
            }
        }
        .sheet(isPresented: $isShowingStyleGuide) {
            StyleGuideView()
                .frame(minWidth: 700, minHeight: 500)
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                listModeIcon("square.grid.2x2", help: "Grid", active: appState.projectListMode == .grid) {
                    appState.projectListMode = .grid
                }
                listModeIcon("list.bullet", help: "Table", active: appState.projectListMode == .table) {
                    appState.projectListMode = .table
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    isShowingStyleGuide = true
                } label: {
                    Image(systemName: "paintbrush")
                }
                .help("Style Guide")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.prompt = "Choose"
                    panel.message = "Select a folder to use as your portfolio root."
                    if panel.runModal() == .OK, let url = panel.url {
                        appState.setRoot(url)
                    }
                } label: {
                    Image(systemName: "folder")
                }
                .help("Change portfolio folder")
            }
            ToolbarItem(placement: .automatic) {
                Button("New Project") {
                    appState.isShowingNewProject = true
                }
            }
        }
        .sheet(isPresented: $appState.isShowingNewProject) {
            NewProjectSheet()
                .environmentObject(appState)
        }
    }

    // MARK: - Grid View

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: DT.Spacing.lg) {
                ForEach(appState.filteredProjects) { project in
                    ProjectCardView(project: project) { tag in
                        appState.searchQuery = tag
                    }
                    .onTapGesture {
                        appState.selectedProject = project
                    }
                }
            }
            .padding(DT.Spacing.lg)
        }
    }

    // MARK: - Table View (placeholder — implemented in Task 5)

    private var tableView: some View {
        Text("Table view")
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Projects Yet")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Click \"New Project\" to create your first project.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Helpers

    private func listModeIcon(_ icon: String, help: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(active ? DT.Colors.textPrimary : DT.Colors.textTertiary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
```

Note: The `gridView` now uses `appState.filteredProjects` instead of `appState.projects` to respect the search query — matching the existing behavior. The `tableView` is a placeholder that will be completed in Task 5.

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' build 2>&1 | tail -3`

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add PortyMcFolio/Views/ProjectListView.swift
git commit -m "feat: add grid/table toolbar toggle and migrate grid to DT tokens"
```

---

### Task 5: Implement the sortable table view

**Files:**
- Modify: `PortyMcFolio/Views/ProjectListView.swift`

- [ ] **Step 1: Add selection state to `ProjectListView`**

Add a `@State` property to `ProjectListView` at the top, after `isShowingStyleGuide`:

```swift
@State private var selectedProjectID: Project.ID?
```

- [ ] **Step 2: Replace the `tableView` placeholder**

Replace the `tableView` computed property in `ProjectListView`:

```swift
// MARK: - Table View

private var sortedProjects: [Project] {
    appState.filteredProjects.sorted(using: appState.projectSortOrder)
}

private var tableView: some View {
    Table(sortedProjects, selection: $selectedProjectID, sortOrder: $appState.projectSortOrder) {
        TableColumn("Year", value: \.year) { project in
            Text(String(project.year))
                .font(DT.Typography.body)
                .foregroundStyle(DT.Colors.textSecondary)
        }
        .width(min: 50, ideal: 60, max: 80)

        TableColumn("Title", value: \.title) { project in
            Text(project.title.isEmpty ? "Untitled" : project.title)
                .font(DT.Typography.body)
                .foregroundStyle(DT.Colors.textPrimary)
        }

        TableColumn("Client", value: \.client) { project in
            Text(project.client)
                .font(DT.Typography.body)
                .foregroundStyle(DT.Colors.textSecondary)
        }
        .width(min: 80, ideal: 120, max: 200)

        TableColumn("Status", value: \.status) { project in
            StatusBadgeView(status: project.status)
        }
        .width(min: 60, ideal: 80, max: 100)

        TableColumn("Tags") { project in
            HStack(spacing: DT.Spacing.xs) {
                ForEach(project.tags, id: \.self) { tag in
                    TagPillView(tag: tag) {
                        appState.searchQuery = tag
                    }
                }
            }
        }
    }
    .onChange(of: selectedProjectID) { _, newID in
        if let id = newID {
            appState.selectedProject = appState.projects.first { $0.id == id }
        }
    }
}
```

Sorting is computed inline via `sortedProjects` — no mutation of the source array. The `Table`'s `sortOrder` binding updates `appState.projectSortOrder` when the user clicks column headers, which triggers a re-render with the new sort.

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' build 2>&1 | tail -3`

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Run the app and test**

Run: `xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' build 2>&1 | tail -3`

Then open the app. Verify:
1. Grid/table toggle icons appear in toolbar
2. Clicking table icon shows sortable table with Year, Title, Client, Status, Tags columns
3. Clicking a column header sorts by that column
4. Clicking a row navigates into the project
5. Switching back to grid shows the card view
6. Quitting and relaunching restores the last-used list mode

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Views/ProjectListView.swift
git commit -m "feat: implement sortable project table view with SwiftUI Table"
```

---

### Task 6: Run all tests and final build verification

**Files:** None (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' 2>&1 | grep -E '(Test Case|passed|failed)'`

Expected: All tests pass, including the new `testProjectStatusComparable`.

- [ ] **Step 2: Clean build**

Run: `xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' clean build 2>&1 | tail -3`

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit any remaining changes**

If xcodegen was needed or any small fixes arose during verification, commit them now.
