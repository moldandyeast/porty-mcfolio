# Onboarding + Settings Manual Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a five-bullet "Welcome / How PortyMcFolio works" primer card to the empty `ProjectListView`, reorganize `AppSettingsView` into clearly-labeled **PREFERENCES** and **MANUAL** bands with three new manual sections, and bundle a small persistence fix so the "Show hidden projects" toggle survives app launches.

**Architecture:** All changes are local — one new SwiftUI view file (`WelcomePrimerView`), one new section in `AppSettingsView`, and edits to `AppState` for persistence. No new services, no schema changes, no new dependencies. Spec: `docs/superpowers/specs/2026-04-29-onboarding-and-settings-manual-design.md`.

**Tech Stack:** Swift 5.9, SwiftUI, XCTest. Build via `xcodebuild`. New `.swift` files under `PortyMcFolio/` or `PortyMcFolioTests/` are auto-discovered by `xcodegen`; run `xcodegen generate` after creating any new file. Project conventions: `type(scope): short summary` commit style with the `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` trailer; **no SwiftUI view tests** — only model/service/state tests.

---

## Task 1: Persist `hideHiddenProjects` across launches

The `hideHiddenProjects` toggle on the project overview today resets to `false` every launch because `AppState` doesn't write it to UserDefaults. Fix that, with a unit test for the round-trip.

**Files:**
- Create: `PortyMcFolioTests/AppStateHideHiddenPersistenceTests.swift`
- Modify: `PortyMcFolio/App/AppState.swift:52` (add `didSet`)
- Modify: `PortyMcFolio/App/AppState.swift:394–444` (extend `loadLayoutPreferences()`)

- [ ] **Step 1: Write the failing test**

Create `PortyMcFolioTests/AppStateHideHiddenPersistenceTests.swift` with:

```swift
import XCTest
@testable import PortyMcFolio

@MainActor
final class AppStateHideHiddenPersistenceTests: XCTestCase {

    private let key = "hideHiddenProjects"

    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: key)
    }

    func test_setting_writes_to_defaults() {
        let appState = AppState()
        appState.hideHiddenProjects = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))

        appState.hideHiddenProjects = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: key))
    }

    func test_loadLayoutPreferences_restoresStoredValue() {
        UserDefaults.standard.set(true, forKey: key)
        let appState = AppState()
        appState.loadLayoutPreferences()
        XCTAssertTrue(appState.hideHiddenProjects)
    }

    func test_loadLayoutPreferences_noStoredValue_keepsFalseDefault() {
        let appState = AppState()
        appState.loadLayoutPreferences()
        XCTAssertFalse(appState.hideHiddenProjects)
    }
}
```

- [ ] **Step 2: Regenerate Xcode project so the new test file is picked up**

```bash
cd <repo> && xcodegen generate
```

- [ ] **Step 3: Run the test to confirm it fails**

```bash
cd <repo> && xcodebuild test \
  -project PortyMcFolio.xcodeproj \
  -scheme PortyMcFolio \
  -destination 'platform=macOS' \
  -only-testing:PortyMcFolioTests/AppStateHideHiddenPersistenceTests \
  2>&1 | grep -E "Test Case|failed|passed" | tail -10
```

Expected: `test_setting_writes_to_defaults` and `test_loadLayoutPreferences_restoresStoredValue` fail. The `_noStoredValue_keepsFalseDefault` test will pass already because the property defaults to `false`.

- [ ] **Step 4: Add the `didSet` to `hideHiddenProjects`**

In `PortyMcFolio/App/AppState.swift`, replace line 52:

```swift
    @Published var hideHiddenProjects = false
```

with:

```swift
    @Published var hideHiddenProjects = false {
        didSet { UserDefaults.standard.set(hideHiddenProjects, forKey: "hideHiddenProjects") }
    }
```

- [ ] **Step 5: Restore the value in `loadLayoutPreferences()`**

In `PortyMcFolio/App/AppState.swift`, inside `loadLayoutPreferences()`, just after the `gridAspectRatio` block (around line 442) and before `restoreSortOrder()` (line 443), insert:

```swift
        if UserDefaults.standard.object(forKey: "hideHiddenProjects") != nil {
            hideHiddenProjects = UserDefaults.standard.bool(forKey: "hideHiddenProjects")
        }
```

- [ ] **Step 6: Run the test to confirm it passes**

```bash
cd <repo> && xcodebuild test \
  -project PortyMcFolio.xcodeproj \
  -scheme PortyMcFolio \
  -destination 'platform=macOS' \
  -only-testing:PortyMcFolioTests/AppStateHideHiddenPersistenceTests \
  2>&1 | grep -E "Test Case|failed|passed" | tail -10
```

Expected: all three tests pass.

- [ ] **Step 7: Run the full test suite to confirm no regressions**

```bash
cd <repo> && xcodebuild test \
  -project PortyMcFolio.xcodeproj \
  -scheme PortyMcFolio \
  -destination 'platform=macOS' \
  2>&1 | grep -E "Test Suite 'All tests'|Executed [0-9]+ tests|failed" | tail -5
```

Expected: `Test Suite 'All tests' passed`, no failures.

- [ ] **Step 8: Commit**

```bash
cd <repo> && git add PortyMcFolio/App/AppState.swift PortyMcFolioTests/AppStateHideHiddenPersistenceTests.swift PortyMcFolio.xcodeproj/project.pbxproj && git commit -m "$(cat <<'EOF'
fix(state): persist hideHiddenProjects across launches

The toggle on the project overview was session-only because the
property had no UserDefaults write in didSet. Add the write and
restore the value in loadLayoutPreferences. Pairs with the new
"Show hidden projects" preference row added in the settings revamp.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Create `WelcomePrimerView`

A new SwiftUI view used as the empty-state for `ProjectListView`. Pure presentation; takes one closure for the "Create your first project" tap. Uses the app's design tokens and theme colors.

**Files:**
- Create: `PortyMcFolio/Views/WelcomePrimerView.swift`

- [ ] **Step 1: Create the view file**

Write `PortyMcFolio/Views/WelcomePrimerView.swift`:

```swift
import SwiftUI

/// Empty-state primer shown on `ProjectListView` when the user has picked a
/// portfolio root but hasn't created any projects yet. The card disappears
/// for good once any project exists; re-access via Settings → Manual.
struct WelcomePrimerView: View {
    let onCreate: () -> Void
    @Environment(\.theme) var theme

    private struct Bullet: Identifiable {
        let id = UUID()
        let symbol: String
        let label: String
    }

    private static let bullets: [Bullet] = [
        Bullet(symbol: "folder",
               label: "Each project is a folder with a markdown file"),
        Bullet(symbol: "photo.on.rectangle",
               label: "Drop in files: images, video, PDFs"),
        Bullet(symbol: "link",
               label: "Add links with previews"),
        Bullet(symbol: "square.and.pencil",
               label: "Edit the markdown to describe the work"),
        Bullet(symbol: "star.fill",
               label: "Mark favorites for the carousel"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.lg) {
            VStack(alignment: .leading, spacing: DT.Spacing.xs) {
                Text("WELCOME")
                    .font(DT.Typography.micro)
                    .tracking(1.4)
                    .foregroundStyle(theme.colors.textTertiary)
                Text("How PortyMcFolio works")
                    .font(DT.Typography.title)
                    .foregroundStyle(theme.colors.textPrimary)
            }

            VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                ForEach(Self.bullets) { bullet in
                    HStack(alignment: .firstTextBaseline, spacing: DT.Spacing.sm) {
                        Image(systemName: bullet.symbol)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.colors.textSecondary)
                            .frame(width: 18, alignment: .center)
                        Text(bullet.label)
                            .font(DT.Typography.body)
                            .foregroundStyle(theme.colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Button(action: onCreate) {
                Text("Create your first project")
                    .font(DT.Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(theme.colors.accentForeground)
                    .padding(.horizontal, DT.Spacing.lg)
                    .padding(.vertical, DT.Spacing.sm)
                    .background(theme.colors.accent, in: RoundedRectangle(cornerRadius: DT.Radius.small))
            }
            .buttonStyle(.plain)
        }
        .padding(DT.Spacing.xl)
        .frame(maxWidth: 420)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: DT.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.medium)
                .stroke(theme.colors.border, lineWidth: 0.5)
        )
    }
}
```

- [ ] **Step 2: Regenerate the Xcode project**

```bash
cd <repo> && xcodegen generate
```

- [ ] **Step 3: Build to verify it compiles**

```bash
cd <repo> && xcodebuild \
  -project PortyMcFolio.xcodeproj \
  -scheme PortyMcFolio \
  -destination 'platform=macOS' \
  -configuration Debug build \
  2>&1 | grep -E "error:|BUILD" | tail -3
```

Expected: `** BUILD SUCCEEDED **`. If `DT.Typography.title` or `theme.colors.accentForeground` don't exist, swap to whichever similarly-named token does (you can grep `PortyMcFolio/Design/DesignTokens.swift` and `PortyMcFolio/Design/Theme.swift` to find the right name).

- [ ] **Step 4: Commit**

```bash
cd <repo> && git add PortyMcFolio/Views/WelcomePrimerView.swift PortyMcFolio.xcodeproj/project.pbxproj && git commit -m "$(cat <<'EOF'
feat(views): WelcomePrimerView for empty-state onboarding

Five-bullet card explaining how a project is a folder with a markdown,
plus the "Drop in files / Add links / Edit markdown / Mark favorites"
capabilities, with a "Create your first project" accent button. Pure
presentation; takes an onCreate closure. Wired into ProjectListView
in the next task.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Show `WelcomePrimerView` in `ProjectListView` empty state

Replace the existing folder-icon-and-text empty placeholder with the new primer card. Tapping the button sets `appState.isShowingNewProject = true` (the same trigger as ⌘N).

**Files:**
- Modify: `PortyMcFolio/Views/ProjectListView.swift:794–809` (the `emptyState` view)

- [ ] **Step 1: Replace the `emptyState` view body**

In `PortyMcFolio/Views/ProjectListView.swift`, locate the `emptyState` computed property starting at line 794 and replace its current body:

```swift
    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: DT.Spacing.md) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(theme.colors.textTertiary)
            Text("No Projects Yet")
                .font(DT.Typography.title)
                .foregroundStyle(theme.colors.textPrimary)
            Text("Click \"New Project\" to create your first project.")
                .font(DT.Typography.body)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
    }
```

with:

```swift
    @ViewBuilder
    private var emptyState: some View {
        VStack {
            Spacer()
            WelcomePrimerView {
                appState.isShowingNewProject = true
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DT.Spacing.xl)
    }
```

- [ ] **Step 2: Build to verify**

```bash
cd <repo> && xcodebuild \
  -project PortyMcFolio.xcodeproj \
  -scheme PortyMcFolio \
  -destination 'platform=macOS' \
  -configuration Debug build \
  2>&1 | grep -E "error:|BUILD" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd <repo> && git add PortyMcFolio/Views/ProjectListView.swift && git commit -m "$(cat <<'EOF'
feat(views): show WelcomePrimerView on empty project overview

Replace the old folder-icon-and-text placeholder with the centered
primer card. Disappears for good the moment any project exists; user
can re-read the same content from Settings → Manual after that.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Add "Show hidden projects" toggle to Portfolio preferences

Surface the now-persisted `hideHiddenProjects` as a real settings row beneath the portfolio folder picker.

**Files:**
- Modify: `PortyMcFolio/Views/AppSettingsView.swift:402–421`

- [ ] **Step 1: Extend `portfolioSection`**

In `PortyMcFolio/Views/AppSettingsView.swift`, replace the existing `portfolioSection` (lines 402–421):

```swift
    private var portfolioSection: some View {
        section("Portfolio") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Portfolio folder")
                        .font(DT.Typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(appState.portfolioRootURL?.path ?? "—")
                        .font(DT.Typography.monoSmall)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                pillButton("Change…") {
                    pickPortfolioFolder()
                }
            }
        }
    }
```

with:

```swift
    private var portfolioSection: some View {
        section("Portfolio") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Portfolio folder")
                        .font(DT.Typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(appState.portfolioRootURL?.path ?? "—")
                        .font(DT.Typography.monoSmall)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                pillButton("Change…") {
                    pickPortfolioFolder()
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hide projects marked hidden")
                        .font(DT.Typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text("Persists across launches. Same toggle as the eye icon on the overview.")
                        .font(DT.Typography.caption)
                        .foregroundStyle(theme.colors.textTertiary)
                }
                Spacer()
                Toggle("", isOn: $appState.hideHiddenProjects)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(theme.colors.accent)
            }
        }
    }
```

- [ ] **Step 2: Build**

```bash
cd <repo> && xcodebuild \
  -project PortyMcFolio.xcodeproj \
  -scheme PortyMcFolio \
  -destination 'platform=macOS' \
  -configuration Debug build \
  2>&1 | grep -E "error:|BUILD" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd <repo> && git add PortyMcFolio/Views/AppSettingsView.swift && git commit -m "$(cat <<'EOF'
feat(settings): expose Hide Hidden Projects as a persistent preference

A switch under Portfolio that mirrors the overview eye-icon toggle.
Backed by the now-persisted hideHiddenProjects state.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Rename zone headers to PREFERENCES / MANUAL

`AppSettingsView` already has zone headers (`SETTINGS` / `REFERENCE`). Rename to match the spec's vocabulary so the page legibly says "preferences here, manual there".

**Files:**
- Modify: `PortyMcFolio/Views/AppSettingsView.swift:14, :21`

- [ ] **Step 1: Edit the two zoneHeader calls in `body`**

In `PortyMcFolio/Views/AppSettingsView.swift`, find lines 14 and 21:

```swift
                zoneHeader("SETTINGS")
```

```swift
                zoneHeader("REFERENCE")
```

Change to:

```swift
                zoneHeader("PREFERENCES")
```

```swift
                zoneHeader("MANUAL")
```

- [ ] **Step 2: Build**

```bash
cd <repo> && xcodebuild \
  -project PortyMcFolio.xcodeproj \
  -scheme PortyMcFolio \
  -destination 'platform=macOS' \
  -configuration Debug build \
  2>&1 | grep -E "error:|BUILD" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd <repo> && git add PortyMcFolio/Views/AppSettingsView.swift && git commit -m "$(cat <<'EOF'
refactor(settings): rename zone headers to PREFERENCES / MANUAL

Make the page's intent legible: top half is tunable preferences,
bottom half is the in-app manual.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Add the new "Getting started" manual section

The first manual section. Recap of the primer plus the on-disk concept (folder name shape, markdown frontmatter).

**Files:**
- Modify: `PortyMcFolio/Views/AppSettingsView.swift` — add a new `gettingStartedSection` and insert it as the first section under the MANUAL zone header.

- [ ] **Step 1: Add the section function**

In `PortyMcFolio/Views/AppSettingsView.swift`, just above `// MARK: - View Modes (existing help content)` (right before `viewModesSection`, around line 435), insert:

```swift
    // MARK: - Getting started (manual)

    private var gettingStartedSection: some View {
        section("Getting started") {
            featureRow(
                icon: "folder",
                title: "Each project is a folder with a markdown file",
                description: "Folders are named year_slug_uid. The markdown file inside (same name as the folder, .md) holds your project body plus YAML frontmatter for title, year, client, status, tags, teaser, favorites, and hidden."
            )
            featureRow(
                icon: "photo.on.rectangle",
                title: "Drop in files",
                description: "Images, video, audio, PDFs — anything. They live next to the markdown inside the project folder."
            )
            featureRow(
                icon: "link",
                title: "Add links with previews",
                description: "Each link becomes a small markdown file in the project folder. Switch to the Links pane to browse them."
            )
            featureRow(
                icon: "square.and.pencil",
                title: "Edit the markdown",
                description: "Use the Editor to describe the work. Auto-saves after 1.5 seconds of inactivity by default."
            )
            featureRow(
                icon: "star.fill",
                title: "Mark favorites",
                description: "Press L on a media file to favorite it. Favorites populate the Carousel and the project teaser."
            )
            featureRow(
                icon: "doc.text.magnifyingglass",
                title: "Filesystem is canonical",
                description: "PortyMcFolio reads and writes plain folders and files; the database is just a search and metadata cache. Move or back up your portfolio with anything that handles folders."
            )
        }
    }
```

- [ ] **Step 2: Insert the section in `body`**

In `body` (around line 21), find:

```swift
                zoneHeader("MANUAL")
                viewModesSection
                divider
                editorSection
```

Replace with:

```swift
                zoneHeader("MANUAL")
                gettingStartedSection
                divider
                viewModesSection
                divider
                editorSection
```

- [ ] **Step 3: Build**

```bash
cd <repo> && xcodebuild \
  -project PortyMcFolio.xcodeproj \
  -scheme PortyMcFolio \
  -destination 'platform=macOS' \
  -configuration Debug build \
  2>&1 | grep -E "error:|BUILD" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd <repo> && git add PortyMcFolio/Views/AppSettingsView.swift && git commit -m "$(cat <<'EOF'
feat(settings): add Getting Started manual section

First section of the MANUAL band. Recaps the empty-state primer plus
the folder-as-project filesystem convention so a user reading settings
gets the full mental model of how data is stored on disk.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Add the new "Importing content" manual section

Workflow-level explanation of the three ways to get content into a project: Finder drag, clipboard paste, and the `![[file]]` embed syntax. Sits right after Getting started.

**Files:**
- Modify: `PortyMcFolio/Views/AppSettingsView.swift` — add `importingContentSection` and insert in `body`.

- [ ] **Step 1: Add the section function**

In `PortyMcFolio/Views/AppSettingsView.swift`, immediately after `gettingStartedSection` (the function you just added), insert:

```swift
    // MARK: - Importing content (manual)

    private var importingContentSection: some View {
        section("Importing content") {
            featureRow(
                icon: "arrow.down.doc",
                title: "Drag from Finder",
                description: "Drop files onto the editor, gallery, or the project folder itself. Files are copied into the project folder and (when dropped on the editor) auto-embedded with ![[filename]]."
            )
            featureRow(
                icon: "doc.on.clipboard",
                title: "Paste from clipboard",
                description: "Files paste in as files. Images paste in as pasted-{timestamp}.png. URLs paste in as link cards. Same handler in the editor and on the project."
            )
            featureRow(
                icon: "chevron.left.forwardslash.chevron.right",
                title: "Embed syntax",
                description: "![[filename]] embeds an image, video, audio file, or link card. Works for files in the project folder or any subfolder (use the relative path: ![[subfolder/image.jpg]])."
            )
            featureRow(
                icon: "arrow.triangle.2.circlepath",
                title: "Renames stay in sync",
                description: "Rename a file inside the app and any ![[…]] embeds in the body, the teaser, and the favorites list update automatically."
            )
        }
    }
```

- [ ] **Step 2: Insert in `body`**

In `body`, find the block you edited in Task 6:

```swift
                zoneHeader("MANUAL")
                gettingStartedSection
                divider
                viewModesSection
```

Replace with:

```swift
                zoneHeader("MANUAL")
                gettingStartedSection
                divider
                importingContentSection
                divider
                viewModesSection
```

- [ ] **Step 3: Build**

```bash
cd <repo> && xcodebuild \
  -project PortyMcFolio.xcodeproj \
  -scheme PortyMcFolio \
  -destination 'platform=macOS' \
  -configuration Debug build \
  2>&1 | grep -E "error:|BUILD" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd <repo> && git add PortyMcFolio/Views/AppSettingsView.swift && git commit -m "$(cat <<'EOF'
feat(settings): add Importing Content manual section

Workflow-level explanation of Finder drag, clipboard paste behavior
(files vs images vs URLs), the ![[file]] embed syntax, and the rename
auto-rewrite guarantee. Sits between Getting Started and View Modes.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Replace `projectsSection` with a focused `projectMetadataSection`

Today's `projectsSection` mixes folder-structure copy (now covered by Getting started), metadata, hidden projects, and an Export row. Slim it to just the metadata fields and move it earlier in the manual order, between Importing content and View modes.

**Files:**
- Modify: `PortyMcFolio/Views/AppSettingsView.swift:570–607` (replace the old `projectsSection` with `projectMetadataSection`)
- Modify: `PortyMcFolio/Views/AppSettingsView.swift` body — drop `projectsSection`, insert `projectMetadataSection` in the new position.

- [ ] **Step 1: Replace `projectsSection` with `projectMetadataSection`**

In `PortyMcFolio/Views/AppSettingsView.swift`, find the existing `projectsSection` (lines 570–607). Replace the whole function — `// MARK: - Projects (existing help content)` comment included — with:

```swift
    // MARK: - Project metadata (manual)

    private var projectMetadataSection: some View {
        section("Project metadata") {
            featureRow(
                icon: "textformat",
                title: "Title",
                description: "The display name of the project. Editable from the project settings popover (\u{2318}9)."
            )
            featureRow(
                icon: "calendar",
                title: "When",
                description: "A year, or a date range. The folder year is derived from this — moving a project's When across years renames its folder automatically."
            )
            featureRow(
                icon: "person.2",
                title: "Client",
                description: "One name, or a comma-separated list. Used as a clickable filter on the overview and shown beneath each project's title."
            )
            featureRow(
                icon: "circle.dashed",
                title: "Status",
                description: "One of three states — empty, in-progress, or archived — shown as a small badge on the table view and inside the carousel."
            )
            featureRow(
                icon: "tag",
                title: "Tags",
                description: "Free-form. Searchable from \u{2318}K. The overview's editorial hover overlay surfaces them as clickable pills."
            )
            featureRow(
                icon: "heart",
                title: "Favorites",
                description: "Per-project list of media filenames. Drives the Carousel order. Press L on a gallery item to toggle."
            )
            featureRow(
                icon: "photo",
                title: "Teaser",
                description: "One image filename used as the project card thumbnail on the overview grid. Set from the project settings popover or via the gallery's right-click menu."
            )
            featureRow(
                icon: "eye.slash",
                title: "Hidden",
                description: "Marks a project hidden. The overview's eye-icon toggle (or the Portfolio preference) filters all hidden projects out — useful for presenting your portfolio without works-in-progress."
            )

            VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                Text("STATUS TYPES")
                    .font(DT.Typography.micro)
                    .foregroundStyle(theme.colors.textTertiary)
                    .tracking(1)

                HStack(spacing: DT.Spacing.md) {
                    ForEach([ProjectStatus.empty, .inProgress, .archived], id: \.self) { s in
                        StatusBadgeView(status: s)
                    }
                }
            }
            .padding(.top, DT.Spacing.xs)
        }
    }
```

- [ ] **Step 2: Update `body` to use the new section in the new position**

In `body`, find the current MANUAL band (after Task 7's edits):

```swift
                zoneHeader("MANUAL")
                gettingStartedSection
                divider
                importingContentSection
                divider
                viewModesSection
                divider
                editorSection
                divider
                gallerySection
                divider
                carouselSection
                divider
                searchSection
                divider
                projectsSection
                divider
                shortcutsSection
```

Replace with:

```swift
                zoneHeader("MANUAL")
                gettingStartedSection
                divider
                importingContentSection
                divider
                projectMetadataSection
                divider
                viewModesSection
                divider
                editorSection
                divider
                gallerySection
                divider
                carouselSection
                divider
                searchSection
                divider
                shortcutsSection
```

(`projectsSection` is removed from the list because the function no longer exists.)

- [ ] **Step 3: Build**

```bash
cd <repo> && xcodebuild \
  -project PortyMcFolio.xcodeproj \
  -scheme PortyMcFolio \
  -destination 'platform=macOS' \
  -configuration Debug build \
  2>&1 | grep -E "error:|BUILD" | tail -3
```

Expected: `** BUILD SUCCEEDED **`. If the build complains that `projectsSection` is referenced anywhere else, grep for it (`grep -n projectsSection PortyMcFolio/Views/AppSettingsView.swift`) and remove the stragglers.

- [ ] **Step 4: Commit**

```bash
cd <repo> && git add PortyMcFolio/Views/AppSettingsView.swift && git commit -m "$(cat <<'EOF'
refactor(settings): replace Projects section with focused Project Metadata

The old Projects section mixed folder-structure copy (now in Getting
Started) with metadata explanations and an Export row. Replace it with
a tighter Project Metadata section that explains each frontmatter
field — title, when, client, status, tags, favorites, teaser, hidden
— and where each one shows up in the UI. Move it to position 3 in the
manual band, right after Importing Content.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Expand `searchSection` with the "Re-index portfolio" callout

The current search section is one paragraph and never mentions the recovery commands available from ⌘K. Spell them out.

**Files:**
- Modify: `PortyMcFolio/Views/AppSettingsView.swift:559–566`

- [ ] **Step 1: Replace `searchSection`**

In `PortyMcFolio/Views/AppSettingsView.swift`, replace the `searchSection` body:

```swift
    private var searchSection: some View {
        section("Search") {
            Text("Press \u{2318}K to open the command palette. Search across projects, files, links, and tags. Use arrow keys to navigate, Enter to open.")
                .font(DT.Typography.body)
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
```

with:

```swift
    private var searchSection: some View {
        section("Search & commands") {
            featureRow(
                icon: "magnifyingglass",
                title: "Search",
                description: "Press \u{2318}K to open the palette. Searches projects, files, links, and tags. Project metadata (title, client, tags, status, folder name) is always matched in full; full-text matches across body + file + link content are unioned on top."
            )
            featureRow(
                icon: "command",
                title: "Commands",
                description: "The same palette runs commands: New Project, Guide, and Re-index portfolio. Re-index rebuilds the search database from disk — the only way to recover from a corrupted FTS index."
            )
            featureRow(
                icon: "arrow.up.arrow.down",
                title: "Keyboard",
                description: "Arrow keys navigate results, Enter opens, Esc closes. Type partial words; matches are prefix-aware."
            )
        }
    }
```

- [ ] **Step 2: Build**

```bash
cd <repo> && xcodebuild \
  -project PortyMcFolio.xcodeproj \
  -scheme PortyMcFolio \
  -destination 'platform=macOS' \
  -configuration Debug build \
  2>&1 | grep -E "error:|BUILD" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd <repo> && git add PortyMcFolio/Views/AppSettingsView.swift && git commit -m "$(cat <<'EOF'
feat(settings): expand Search section with command palette + re-index

Promote Search to "Search & commands" and surface the three things
that today are invisible to a new user: how matching combines metadata
+ FTS, the New Project / Guide / Re-index portfolio commands, and the
keyboard interactions.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Add the new "Themes" manual section

A short section explaining what each of the three themes is for. Sits between Search and Keyboard shortcuts.

**Files:**
- Modify: `PortyMcFolio/Views/AppSettingsView.swift` — add `themesSection`, insert in `body`.

- [ ] **Step 1: Add the section function**

In `PortyMcFolio/Views/AppSettingsView.swift`, just above `// MARK: - Shortcuts (existing help content)` (right before `shortcutsSection`), insert:

```swift
    // MARK: - Themes (manual)

    private var themesSection: some View {
        section("Themes") {
            featureRow(
                icon: "paintpalette",
                title: "Porty",
                description: "Warm, branded palette with the pink accent. The default."
            )
            featureRow(
                icon: "macwindow",
                title: "OSX",
                description: "Native Apple greys and the system blue accent. Disappears into the OS."
            )
            featureRow(
                icon: "circle.lefthalf.filled",
                title: "BW",
                description: "Monochrome — pure black, white, and grey. Lets the work do the talking."
            )
            featureRow(
                icon: "sun.max",
                title: "Light / Dark / System",
                description: "Independent of theme. System follows your OS appearance; Light or Dark force the chosen mode app-wide."
            )
        }
    }
```

- [ ] **Step 2: Insert in `body`**

In `body`, find the current tail of the MANUAL band:

```swift
                searchSection
                divider
                shortcutsSection
```

Replace with:

```swift
                searchSection
                divider
                themesSection
                divider
                shortcutsSection
```

- [ ] **Step 3: Build**

```bash
cd <repo> && xcodebuild \
  -project PortyMcFolio.xcodeproj \
  -scheme PortyMcFolio \
  -destination 'platform=macOS' \
  -configuration Debug build \
  2>&1 | grep -E "error:|BUILD" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd <repo> && git add PortyMcFolio/Views/AppSettingsView.swift && git commit -m "$(cat <<'EOF'
feat(settings): add Themes manual section

One row each on Porty, OSX, BW, plus the System / Light / Dark
appearance override. Covers a corner of the app that's adjustable in
preferences but never explained anywhere.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Add overview arrow-key navigation to Keyboard Shortcuts section

The shortcuts section's Global subsection doesn't mention arrow-key project-list navigation, which is a real feature implemented via an NSEvent local monitor in `ProjectListView`. Add it.

**Files:**
- Modify: `PortyMcFolio/Views/AppSettingsView.swift:613–617` (the `Global` subsection inside `shortcutsSection`)

- [ ] **Step 1: Extend the Global subsection**

In `PortyMcFolio/Views/AppSettingsView.swift`, locate the `Global` subsection inside `shortcutsSection`:

```swift
            subsection("Global") {
                shortcutRow("Search & Commands", "\u{2318}K")
                shortcutRow("New Project", "\u{2318}N")
                shortcutRow("Back to Projects", "\u{238B}")
            }
```

Replace it with:

```swift
            subsection("Global") {
                shortcutRow("Search & Commands", "\u{2318}K")
                shortcutRow("New Project", "\u{2318}N")
                shortcutRow("Back to Projects", "\u{238B}")
            }

            subsection("Project Overview") {
                shortcutRow("Navigate Cards / Rows", "\u{2190}\u{2191}\u{2193}\u{2192}")
                shortcutRow("Open Selected", "\u{21A9}")
                shortcutRow("Project Settings (hovered/selected)", "\u{2318}9")
                shortcutRow("Toggle Grid / Table", "\u{2318}1 / \u{2318}2")
            }
```

- [ ] **Step 2: Build**

```bash
cd <repo> && xcodebuild \
  -project PortyMcFolio.xcodeproj \
  -scheme PortyMcFolio \
  -destination 'platform=macOS' \
  -configuration Debug build \
  2>&1 | grep -E "error:|BUILD" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd <repo> && git add PortyMcFolio/Views/AppSettingsView.swift && git commit -m "$(cat <<'EOF'
feat(settings): document Project Overview keyboard navigation

Surfaces the arrow-key card/row navigation, Enter to open, the ⌘1/⌘2
context-aware grid/table toggle, and ⌘9 for hovered project settings —
all features that today work but are invisible to a new user.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Final smoke verification

Run the full test suite, build Release, and eyeball the affected screens to make sure everything renders.

- [ ] **Step 1: Run the full unit test suite**

```bash
cd <repo> && xcodebuild test \
  -project PortyMcFolio.xcodeproj \
  -scheme PortyMcFolio \
  -destination 'platform=macOS' \
  2>&1 | grep -E "Test Suite 'All tests'|Executed [0-9]+ tests|failed" | tail -5
```

Expected: `Test Suite 'All tests' passed`. Test count is the previous total + 3 (the new persistence tests).

- [ ] **Step 2: Release build**

```bash
cd <repo> && xcodebuild \
  -project PortyMcFolio.xcodeproj \
  -scheme PortyMcFolio \
  -configuration Release \
  -destination 'platform=macOS' build \
  2>&1 | grep -E "error:|BUILD" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual smoke checklist (interactive)**

Open the built app. Verify:

1. Pick an empty folder as the portfolio root. The empty overview shows the WelcomePrimerView card with the WELCOME eyebrow, "How PortyMcFolio works" title, five bullets, and a pink "Create your first project" button. The accent button matches existing primary buttons in the app.
2. Click "Create your first project". The new-project sheet opens (same as ⌘N).
3. Create one project. The primer card disappears immediately; the project shows in the overview.
4. Open Settings (gear icon). Confirm: top zone says **PREFERENCES** (was **SETTINGS**); bottom zone says **MANUAL** (was **REFERENCE**).
5. Under Portfolio, the new "Hide projects marked hidden" switch is present. Toggle it. Quit and relaunch the app. Verify the toggle's state is preserved.
6. Scroll the MANUAL band top-to-bottom. Confirm sections in this order: Getting started → Importing content → Project metadata → View modes → Editor → Gallery & Files → Carousel → Search & commands → Themes → Keyboard shortcuts.
7. Each manual section renders without layout breakage in light, dark, and each of the three themes (porty, osx, bw).

- [ ] **Step 4: Push**

```bash
cd <repo> && git push origin main
```

Plan complete.

---

## Out of scope (deferred)

These were explicitly excluded by the design spec:

- Sample portfolio seeding
- Animated tooltips / coach marks
- Theme visual previews / live demos
- Re-accessible welcome via ⌘K command palette
- Restructuring `AppSettingsView` into tabs / sidebar

Each is a candidate for a future plan if the simple approach proves insufficient in use.
