# Project Settings Popover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move project metadata (title, year, client, status, tags) from in-editor YAML to a proper popover form, with folder rename on save. Hide frontmatter from the editor entirely.

**Architecture:** The popover reads project metadata and presents a form. On save, it writes frontmatter to README.md and renames the folder if title/year changed. The editor strips frontmatter before display and re-attaches it on save. All frontmatter JS code is deleted.

**Tech Stack:** Swift 5.9, SwiftUI, macOS 14, CodeMirror 6, Vite

**Spec:** `docs/superpowers/specs/2026-04-14-project-settings-popover-design.md`

---

## File Structure

### New files
- `PortyMcFolio/Views/ProjectSettingsPopover.swift` — metadata form (title, year, client, status, tags, teaser)
- `PortyMcFolio/Views/TagChipInput.swift` — reusable tag chip input component

### Modified files (Swift)
- `PortyMcFolio/Models/Project.swift` — new folder name format (`_` separators)
- `PortyMcFolio/Services/ProjectCreator.swift` — uses new folder name (via Project.folderName)
- `PortyMcFolio/App/AppState.swift` — add `updateProjectMetadata()` method
- `PortyMcFolio/Views/ProjectDetailView.swift` — title clickable, opens popover
- `PortyMcFolio/Views/EditorView.swift` — strip frontmatter on load, re-attach on save

### Modified files (JS/CSS/HTML)
- `Editor/src/index.js` — remove frontmatter imports, extensions, bar code
- `Editor/src/markdown/frontmatter.js` — **delete**
- `PortyMcFolio/Editor/Resources/editor.css` — remove frontmatter CSS
- `PortyMcFolio/Editor/Resources/editor.html` — remove `#frontmatter-bar` div

### Test files
- `PortyMcFolioTests/ProjectTests.swift` — new folder format
- `PortyMcFolioTests/ProjectCreatorTests.swift` — new folder format

---

## Task 1: New folder name format

**Files:**
- Modify: `PortyMcFolio/Models/Project.swift`
- Modify: `PortyMcFolioTests/ProjectTests.swift`

- [ ] **Step 1: Update Project.folderName()**

In `PortyMcFolio/Models/Project.swift`, replace the `folderName` static method and the `from` parser:

```swift
/// Build the standard folder name: {Year}_{slug}_{uid}
static func folderName(title: String, year: Int, uid: String) -> String {
    "\(year)_\(Slug.underscoreFrom(title))_\(uid)"
}

/// Parse a project from its folder name and root URL.
/// Folder must match pattern: {4-digit year}_{slug}_{8-char hex uid}
static func from(folderName: String, rootURL: URL) throws -> Project {
    let components = folderName.components(separatedBy: "_")

    // Need at minimum: year + at least one slug part + uid = 3 parts
    guard components.count >= 3 else {
        throw ProjectError.invalidFolderName(folderName)
    }

    // First component must be a 4-digit year
    guard let year = Int(components[0]), components[0].count == 4, year >= 1000, year <= 9999 else {
        throw ProjectError.invalidFolderName(folderName)
    }

    // Last component must be an 8-character hex UID
    let uid = components.last!
    guard uid.count == 8, uid.allSatisfy({ $0.isHexDigit }) else {
        throw ProjectError.invalidFolderName(folderName)
    }

    let folderURL = rootURL.appendingPathComponent(folderName)

    return Project(
        uid: uid,
        year: year,
        folderName: folderName,
        folderURL: folderURL,
        title: "",
        date: Date(),
        tags: [],
        client: "",
        status: .draft,
        body: "",
        teaser: ""
    )
}
```

Also update the error description:
```swift
return "Invalid project folder name: \(name). Expected format: {4-digit year}_{slug}_{8-char hex uid}"
```

- [ ] **Step 2: Update ProjectTests**

Replace `PortyMcFolioTests/ProjectTests.swift`:

```swift
import XCTest
@testable import PortyMcFolio

final class ProjectTests: XCTestCase {
    func testProjectFromFolderName() throws {
        let project = try Project.from(
            folderName: "2025_brand_identity_a3f1b2c4",
            rootURL: URL(fileURLWithPath: "/tmp/portfolio")
        )
        XCTAssertEqual(project.year, 2025)
        XCTAssertEqual(project.uid, "a3f1b2c4")
        XCTAssertEqual(project.folderName, "2025_brand_identity_a3f1b2c4")
        XCTAssertEqual(project.folderURL.path, "/tmp/portfolio/2025_brand_identity_a3f1b2c4")
        XCTAssertEqual(project.readmeURL.path, "/tmp/portfolio/2025_brand_identity_a3f1b2c4/README.md")
    }

    func testProjectFromMultiWordSlug() throws {
        let project = try Project.from(
            folderName: "2026_my_cool_long_project_7e2d9f01",
            rootURL: URL(fileURLWithPath: "/tmp/portfolio")
        )
        XCTAssertEqual(project.year, 2026)
        XCTAssertEqual(project.uid, "7e2d9f01")
    }

    func testProjectFolderName() {
        let name = Project.folderName(title: "Brand Identity", year: 2025, uid: "a3f1b2c4")
        XCTAssertEqual(name, "2025_brand_identity_a3f1b2c4")
    }

    func testProjectFromInvalidFolderNameThrows() {
        XCTAssertThrowsError(try Project.from(
            folderName: "not-a-valid-folder",
            rootURL: URL(fileURLWithPath: "/tmp/portfolio")
        ))
    }

    func testProjectFromTooFewComponents() {
        XCTAssertThrowsError(try Project.from(
            folderName: "2025_a3f1b2c4",
            rootURL: URL(fileURLWithPath: "/tmp/portfolio")
        ))
    }
}
```

- [ ] **Step 3: Update ProjectCreatorTests**

In `PortyMcFolioTests/ProjectCreatorTests.swift`, update line 40 and line 59:

```swift
// Line 40: change from hyphen check to underscore check
XCTAssertTrue(name.hasPrefix("\(year)_brand_identity"))

// Line 59: change from hyphen to underscore
XCTAssertTrue(project.folderName.contains("my_cool_project"))
```

- [ ] **Step 4: Build and test**

Run: `xcodebuild test -scheme PortyMcFolio -configuration Debug -destination 'platform=macOS' 2>&1 | tail -15`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Models/Project.swift PortyMcFolioTests/ProjectTests.swift PortyMcFolioTests/ProjectCreatorTests.swift
git commit -m "feat: new folder name format YYYY_slug_uid with underscores"
```

---

## Task 2: TagChipInput component

**Files:**
- Create: `PortyMcFolio/Views/TagChipInput.swift`

- [ ] **Step 1: Create TagChipInput**

```swift
import SwiftUI

struct TagChipInput: View {
    @Binding var tags: [String]
    @State private var inputText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Tag pills
            if !tags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                                .font(.system(size: 12))
                            Button {
                                tags.removeAll { $0 == tag }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1), in: Capsule())
                    }
                }
            }

            // Input field
            TextField("Add tag…", text: $inputText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { addTag() }
        }
    }

    private func addTag() {
        // Support comma-separated input
        let newTags = inputText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !tags.contains($0) }
        tags.append(contentsOf: newTags)
        inputText = ""
    }
}
```

Note: `FlowLayout` already exists in `ProjectCardView.swift`. It's a public struct so it's accessible.

- [ ] **Step 2: Regenerate xcodeproj and build**

```bash
xcodegen generate
xcodebuild -scheme PortyMcFolio -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add PortyMcFolio/Views/TagChipInput.swift PortyMcFolio.xcodeproj/project.pbxproj
git commit -m "feat: TagChipInput — reusable tag pill input with comma support"
```

---

## Task 3: AppState.updateProjectMetadata

**Files:**
- Modify: `PortyMcFolio/App/AppState.swift`

- [ ] **Step 1: Add updateProjectMetadata method**

Add this method to `AppState` (after `createProject`):

```swift
func updateProjectMetadata(
    project: Project,
    title: String,
    year: Int,
    client: String,
    status: ProjectStatus,
    tags: [String],
    teaser: String
) throws {
    // 1. Read current README and update frontmatter
    let content = try String(contentsOf: project.readmeURL, encoding: .utf8)
    var parsed = try FrontmatterParser.parse(content)
    parsed.title = title
    parsed.client = client
    parsed.status = status
    parsed.tags = tags
    parsed.teaser = teaser

    // Update year in date (keep month/day from existing date)
    var calendar = Calendar.current
    calendar.timeZone = TimeZone(identifier: "UTC")!
    var dateComponents = calendar.dateComponents([.month, .day], from: parsed.date)
    dateComponents.year = year
    if let newDate = calendar.date(from: dateComponents) {
        parsed.date = newDate
    }

    let updated = FrontmatterParser.serialize(frontmatter: parsed)
    try updated.write(to: project.readmeURL, atomically: true, encoding: .utf8)

    // 2. Rename folder if needed
    let newFolderName = Project.folderName(title: title, year: year, uid: project.uid)
    if newFolderName != project.folderName, let rootURL = portfolioRootURL {
        let newFolderURL = rootURL.appendingPathComponent(newFolderName)
        try FileManager.default.moveItem(at: project.folderURL, to: newFolderURL)
    }

    // 3. Refresh and re-select by UID
    refreshProjects()
    selectedProject = projects.first { $0.uid == project.uid }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme PortyMcFolio -configuration Debug build 2>&1 | tail -5`

- [ ] **Step 3: Commit**

```bash
git add PortyMcFolio/App/AppState.swift
git commit -m "feat: AppState.updateProjectMetadata — atomic save + folder rename"
```

---

## Task 4: ProjectSettingsPopover

**Files:**
- Create: `PortyMcFolio/Views/ProjectSettingsPopover.swift`
- Modify: `PortyMcFolio/Views/ProjectDetailView.swift`

- [ ] **Step 1: Create ProjectSettingsPopover**

```swift
import SwiftUI

struct ProjectSettingsPopover: View {
    let project: Project
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool

    @State private var title: String = ""
    @State private var year: Int = 2026
    @State private var client: String = ""
    @State private var status: ProjectStatus = .draft
    @State private var tags: [String] = []
    @State private var teaser: String = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Project Settings")
                .font(.headline)

            // Title
            VStack(alignment: .leading, spacing: 4) {
                Text("Title")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Project title", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            // Year
            HStack {
                Text("Year")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("", value: $year, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .multilineTextAlignment(.center)
            }

            // Client
            VStack(alignment: .leading, spacing: 4) {
                Text("Client")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Client name", text: $client)
                    .textFieldStyle(.roundedBorder)
            }

            // Status
            HStack {
                Text("Status")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $status) {
                    Text("Draft").tag(ProjectStatus.draft)
                    Text("Active").tag(ProjectStatus.active)
                    Text("Complete").tag(ProjectStatus.complete)
                    Text("Archived").tag(ProjectStatus.archived)
                }
                .frame(width: 140)
            }

            // Tags
            VStack(alignment: .leading, spacing: 4) {
                Text("Tags")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TagChipInput(tags: $tags)
            }

            // Teaser
            HStack {
                Text("Teaser")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !teaser.isEmpty {
                    Text(teaser)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button("Clear") { teaser = "" }
                        .controlSize(.small)
                }
                Button("Choose…") { pickTeaser() }
                    .controlSize(.small)
            }

            // Error
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Actions
            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear {
            title = project.title
            year = project.year
            client = project.client
            status = project.status
            tags = project.tags
            teaser = project.teaser
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

        do {
            try appState.updateProjectMetadata(
                project: project,
                title: trimmedTitle,
                year: year,
                client: client.trimmingCharacters(in: .whitespaces),
                status: status,
                tags: tags,
                teaser: teaser
            )
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func pickTeaser() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = project.folderURL
        panel.allowedContentTypes = [.image]
        panel.message = "Select teaser image"
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Compute relative path
        let projectPath = project.folderURL.path + "/"
        if url.path.hasPrefix(projectPath) {
            teaser = url.path.replacingOccurrences(of: projectPath, with: "")
        } else {
            teaser = url.lastPathComponent
        }
    }
}
```

- [ ] **Step 2: Update ProjectDetailView header**

In `PortyMcFolio/Views/ProjectDetailView.swift`, add state and make title clickable.

Add state variable:
```swift
@State private var isShowingSettings = false
```

Replace the title `Text` (line 20-22) with a clickable button:
```swift
// Replace:
// Text(project.title)
//     .font(.headline)
//     .lineLimit(1)

// With:
Button {
    isShowingSettings = true
} label: {
    HStack(spacing: 4) {
        Text(project.title.isEmpty ? "Untitled" : project.title)
            .font(.headline)
            .lineLimit(1)
        Image(systemName: "chevron.down")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
    }
}
.buttonStyle(.plain)
.popover(isPresented: $isShowingSettings) {
    ProjectSettingsPopover(
        project: project,
        isPresented: $isShowingSettings
    )
    .environmentObject(appState)
}
```

- [ ] **Step 3: Regenerate xcodeproj and build**

```bash
xcodegen generate
xcodebuild -scheme PortyMcFolio -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Views/ProjectSettingsPopover.swift PortyMcFolio/Views/ProjectDetailView.swift PortyMcFolio.xcodeproj/project.pbxproj
git commit -m "feat: project settings popover — metadata form with save + folder rename"
```

---

## Task 5: Hide frontmatter in editor (Swift side)

**Files:**
- Modify: `PortyMcFolio/Views/EditorView.swift`

- [ ] **Step 1: Strip frontmatter on load**

In `EditorView.Coordinator.loadContent()`, replace the content loading section:

```swift
func loadContent() {
    guard let webView else { return }
    pendingLoad = false

    // Read README, extract body only (strip frontmatter)
    let body: String
    do {
        let content = try String(contentsOf: readmeURL, encoding: .utf8)
        let parsed = try FrontmatterParser.parse(content)
        body = parsed.body
    } catch {
        body = ""
    }
    bridge.loadMarkdown(in: webView, content: body)

    // Send link metadata to JS for card rendering
    loadLinkMetadata(webView: webView)

    // Send last-modified date to footer
    if let attrs = try? FileManager.default.attributesOfItem(atPath: readmeURL.path),
       let modified = attrs[.modificationDate] as? Date {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let relative = formatter.localizedString(for: modified, relativeTo: Date())
        if let jsonData = try? JSONSerialization.data(withJSONObject: [relative]),
           let jsonArray = String(data: jsonData, encoding: .utf8) {
            let jsonString = String(jsonArray.dropFirst().dropLast())
            webView.evaluateJavaScript("window.PortyEditor.setLastModified(\(jsonString))")
        }
    }
}
```

- [ ] **Step 2: Re-attach frontmatter on save**

Replace the `contentChanged` callback in `init`:

```swift
bridge.onContentChanged = { [weak self] body in
    guard let self else { return }
    do {
        // Re-read current frontmatter from disk (may have been updated by popover)
        let currentContent = try String(contentsOf: self.readmeURL, encoding: .utf8)
        let parsed = try FrontmatterParser.parse(currentContent)
        // Write frontmatter + new body
        let fullContent = FrontmatterParser.serialize(frontmatter: ParsedFrontmatter(
            title: parsed.title,
            date: parsed.date,
            tags: parsed.tags,
            client: parsed.client,
            status: parsed.status,
            body: body,
            teaser: parsed.teaser
        ))
        try fullContent.write(to: self.readmeURL, atomically: true, encoding: .utf8)
        self.onSave?(fullContent)
    } catch {
        print("[EditorView] Save failed: \(error)")
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme PortyMcFolio -configuration Debug build 2>&1 | tail -5`

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Views/EditorView.swift
git commit -m "feat: editor strips frontmatter on load, re-attaches on save"
```

---

## Task 6: Remove frontmatter from JS editor

**Files:**
- Modify: `Editor/src/index.js`
- Delete: `Editor/src/markdown/frontmatter.js`
- Modify: `PortyMcFolio/Editor/Resources/editor.html`
- Modify: `PortyMcFolio/Editor/Resources/editor.css`

- [ ] **Step 1: Update index.js**

Remove the frontmatter import (line 10):
```js
// DELETE this line:
// import { frontmatterDecorations, frontmatterGuard } from './markdown/frontmatter.js'
```

Remove from extensions array (lines 82-83):
```js
// DELETE these lines:
// frontmatterDecorations,
// frontmatterGuard,
```

Remove `updateFrontmatterBar(update.state.doc)` from updateListener (line 69).

Remove `updateFrontmatterBar(view.state.doc)` and `checkFrontmatterVisibility()` from `setMarkdown()` (lines 121-122).

Remove `setupFrontmatterScroll()` call from `initEditor()` (line 106).

Delete the entire frontmatter bar section (lines 257-319):
```js
// DELETE everything from:
// // ── Frontmatter Collapsed Bar ────────────────────────
// through:
// function setupFrontmatterScroll() { ... }
```

- [ ] **Step 2: Delete frontmatter.js**

```bash
rm Editor/src/markdown/frontmatter.js
```

- [ ] **Step 3: Update editor.html**

Remove the `#frontmatter-bar` div (line 10):
```html
<!-- DELETE: <div id="frontmatter-bar"></div> -->
```

- [ ] **Step 4: Update editor.css**

Remove all frontmatter CSS. Delete these sections:
- Lines 90-137: `#frontmatter-bar`, `.fm-item`, `.fm-label`, `.fm-value` (the collapsed bar)
- Lines 253-261: `.cm-md-frontmatter-line.cm-md-hr` overrides
- Lines 270-299: `.cm-md-frontmatter-line`, `.cm-md-frontmatter-first`, `.cm-md-frontmatter-last`, `.cm-md-frontmatter-key`, `.cm-md-frontmatter-value`, `.cm-md-frontmatter-delimiter`

- [ ] **Step 5: Build JS bundle**

```bash
cd Editor && npm run build
```

- [ ] **Step 6: Build Swift**

```bash
xcodebuild -scheme PortyMcFolio -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 7: Commit**

```bash
git add Editor/src/index.js PortyMcFolio/Editor/Resources/editor.bundle.js PortyMcFolio/Editor/Resources/editor.html PortyMcFolio/Editor/Resources/editor.css
git rm Editor/src/markdown/frontmatter.js
git commit -m "feat: remove frontmatter from editor — delete YAML block, bar, and all related code"
```

---

## Task 7: Final build and test

- [ ] **Step 1: Full JS build**

Run: `cd Editor && npm run build`

- [ ] **Step 2: Full Swift build**

Run: `xcodebuild -scheme PortyMcFolio -configuration Debug build 2>&1 | tail -5`

- [ ] **Step 3: Run tests**

Run: `xcodebuild test -scheme PortyMcFolio -configuration Debug -destination 'platform=macOS' 2>&1 | tail -15`
Expected: All tests pass.
