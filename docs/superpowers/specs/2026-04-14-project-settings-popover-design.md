# Project Settings Popover

**Date:** 2026-04-14
**Branch:** `dev/v1-implementation`

---

## Philosophy

The frontmatter is project metadata — title, year, client, status, tags. It shouldn't live as YAML in the editor. The editor is for writing. Metadata gets a proper form: a popover triggered from the project header. Changes to title or year rename the project folder on disk.

---

## Folder Name Format

**New format:** `YYYY_Slugified_Title_UID`

Examples:
- `2026_brand_identity_a3f1b2c4`
- `2025_website_redesign_7e2d9f01`

- Year: 4-digit year (from the `date` field, or current year on create)
- Title slug: `Slug.underscoreFrom(title)` — lowercase, underscores, special chars stripped
- UID: 8-char hex (generated once at creation, never changes)

**Breaking change from old format** (`YYYY-slug-uid` with hyphens). No migration — old test folders can be recreated.

**Parsing:** Split folder name on `_`. First component must be 4-digit year. Last component must be 8-char hex UID. Everything in between is the title slug (rejoin with `_`). Minimum 3 components (year + at least one slug segment + uid).

---

## Features

### 1. Project Settings Popover

Click the project title in `ProjectDetailView` header → `.popover()`:

**Fields:**
- **Title**: text field (required). Changing this renames the project folder on save.
- **Year**: text field or stepper (4-digit year). Changing this renames the project folder on save.
- **Client**: text field (optional).
- **Status**: `Picker` dropdown — draft, active, complete, archived.
- **Tags**: chip input. Text field + Enter to add a pill. × button on each pill to remove.
- **Teaser**: shows current teaser filename. "Change" button opens NSOpenPanel scoped to project folder. "Clear" removes teaser.

**Actions:**
- **Save**: applies all changes atomically — writes frontmatter to README.md, renames folder if title/year changed, updates all in-memory state. On error (rename fails, write fails) shows NSAlert and does not close the popover.
- **Cancel**: discards all changes, closes popover.

**Integration with AppState:**
- Popover receives `project: Project` and uses `@EnvironmentObject var appState: AppState` (same pattern as `ProjectDetailView`).
- On save, calls `appState.updateProjectMetadata(...)` which handles the entire save-rename-refresh flow.
- After successful save, popover dismisses itself.

### 2. AppState.updateProjectMetadata

New method on AppState that handles the atomic save + rename:

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
    // 1. Read current README, update frontmatter, write back
    let content = try String(contentsOf: project.readmeURL, encoding: .utf8)
    var parsed = try FrontmatterParser.parse(content)
    parsed.title = title
    parsed.date = /* date with new year, keep month/day */
    parsed.client = client
    parsed.status = status
    parsed.tags = tags
    parsed.teaser = teaser
    let updated = FrontmatterParser.serialize(frontmatter: parsed)
    try updated.write(to: project.readmeURL, atomically: true, encoding: .utf8)

    // 2. Rename folder if title or year changed
    let newFolderName = Project.folderName(title: title, year: year, uid: project.uid)
    if newFolderName != project.folderName, let rootURL = portfolioRootURL {
        let newFolderURL = rootURL.appendingPathComponent(newFolderName)
        try FileManager.default.moveItem(at: project.folderURL, to: newFolderURL)
    }

    // 3. Refresh projects (re-scans from disk, rebuilds Project objects)
    refreshProjects()

    // 4. Re-select the project by UID (folder name changed, but UID is stable)
    selectedProject = projects.first { $0.uid == project.uid }
}
```

Key: The UID is stable across renames, so we find the project by UID after refresh.

### 3. Hide Frontmatter in Editor

The editor no longer shows or edits YAML frontmatter.

**JS editor changes:**
- Delete `Editor/src/markdown/frontmatter.js` entirely
- In `Editor/src/index.js`:
  - Remove import of `frontmatterDecorations, frontmatterGuard`
  - Remove from extensions array
  - Remove all frontmatter bar code: `updateFrontmatterBar()`, `checkFrontmatterVisibility()`, `setupFrontmatterScroll()`, `parseFrontmatter()`, `fmBarContent` variable
  - Remove `setupFrontmatterScroll()` call in `initEditor()`
  - Remove `updateFrontmatterBar(update.state.doc)` from updateListener
  - Remove `updateFrontmatterBar(view.state.doc)` from `setMarkdown()`
  - Keep the footer word count regex `text.replace(/^---[\s\S]*?---\n*/, '')` as a safety net (harmless if no frontmatter present)
- In `PortyMcFolio/Editor/Resources/editor.html`: remove `<div id="frontmatter-bar"></div>`
- In `PortyMcFolio/Editor/Resources/editor.css`: remove all frontmatter CSS:
  - `#frontmatter-bar` and related (`.fm-item`, `.fm-label`, `.fm-value`)
  - `.cm-md-frontmatter-line`, `.cm-md-frontmatter-first`, `.cm-md-frontmatter-last`
  - `.cm-md-frontmatter-key`, `.cm-md-frontmatter-value`, `.cm-md-frontmatter-delimiter`
  - `.cm-md-frontmatter-line.cm-md-hr` override

**Swift EditorView changes:**
- `loadContent()`: parse README with `FrontmatterParser.parse()`, send only `parsed.body` to JS editor
- `contentChanged` callback: receives body-only from JS. Re-reads frontmatter from disk each time (never cache — avoids stale state if popover changed frontmatter between keystrokes). Writes `FrontmatterParser.serialize(frontmatter: currentFrontmatter) + body` back to README.md.
- Remove `loadLinkMetadata` call — keep this, it's unrelated to frontmatter
- Remove the "Send last-modified date to footer" block — keep this too, unrelated

### 4. Update Project.folderName Format

```swift
static func folderName(title: String, year: Int, uid: String) -> String {
    "\(year)_\(Slug.underscoreFrom(title))_\(uid)"
}
```

`Project.from(folderName:rootURL:)` parsing:
```swift
let components = folderName.components(separatedBy: "_")
// Minimum: year + one slug segment + uid = 3 components
guard components.count >= 3 else { throw ... }
guard let year = Int(components[0]), components[0].count == 4, year >= 1000, year <= 9999 else { throw ... }
let uid = components.last!
guard uid.count == 8, uid.allSatisfy({ $0.isHexDigit }) else { throw ... }
// Title slug is everything in between (may have underscores)
// Not stored — title comes from README frontmatter, not from folder name
```

### 5. Update ProjectCreator

Uses the new folder name format via `Project.folderName()`. No other changes.

---

## What Changes

### New files
- `PortyMcFolio/Views/ProjectSettingsPopover.swift` — the metadata form with title, year, client, status picker, tag chips, teaser picker, Save/Cancel buttons
- `PortyMcFolio/Views/TagChipInput.swift` — reusable tag chip input: text field + Enter to add, × to remove, displays as pills

### Modified files (Swift)
- `PortyMcFolio/Views/ProjectDetailView.swift` — title becomes a Button, `.popover()` opens ProjectSettingsPopover
- `PortyMcFolio/Models/Project.swift` — new folder name format (`_` separators), updated parser
- `PortyMcFolio/Services/ProjectCreator.swift` — uses new folder name format (via Project.folderName)
- `PortyMcFolio/Views/EditorView.swift` — strip frontmatter before sending to editor, re-read and re-attach on save
- `PortyMcFolio/App/AppState.swift` — add `updateProjectMetadata()` method for atomic save+rename+refresh

### Modified files (JS editor)
- `Editor/src/index.js` — remove frontmatter bar code + frontmatter extension imports
- `Editor/src/markdown/frontmatter.js` — **delete entire file**
- `PortyMcFolio/Editor/Resources/editor.css` — remove frontmatter bar CSS + frontmatter syntax highlighting CSS
- `PortyMcFolio/Editor/Resources/editor.html` — remove `#frontmatter-bar` div

### Test files
- `PortyMcFolioTests/ProjectTests.swift` — update for new folder name format (underscores)
- `PortyMcFolioTests/ProjectCreatorTests.swift` — update for new folder name format

### Unchanged
- `PortyMcFolio/Services/FrontmatterParser.swift` — still used for README read/write
- `PortyMcFolioTests/FrontmatterParserTests.swift` — no changes needed
- `PortyMcFolio/Views/NewProjectSheet.swift` — calls AppState.createProject which calls ProjectCreator, no direct changes

---

## Error Handling

- **Folder rename fails** (permissions, disk full): `updateProjectMetadata` throws. Popover catches the error and shows NSAlert. Popover stays open so user can retry or cancel.
- **README write fails**: same — throws, popover shows error.
- **Frontmatter re-read on editor save**: if README read fails, editor save is skipped (current behavior with `try?`). No data loss since editor content is still in memory.

---

## Out of Scope

- Migration of old project folders
- Inline title editing in the editor
- Project duplication / archive / export
- Year field as a date picker (just a 4-digit text field / stepper)
