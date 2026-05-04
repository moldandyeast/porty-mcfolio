# New Project Template Setting

**Date:** 2026-04-22
**Scope:** `PortyMcFolio/App/AppState.swift`, `PortyMcFolio/Services/ProjectCreator.swift`, `PortyMcFolio/Views/AppSettingsView.swift`, plus a new `Services/ProjectTemplate.swift` and `PortyMcFolioTests/ProjectTemplateTests.swift`.

## Summary

Add a user-editable template for the markdown body that gets written into every newly created project. The template lives in Settings → Workspace as a multi-line text editor with a "Reset default" button. It supports five placeholders — `{{title}}`, `{{year}}`, `{{client}}`, `{{tags}}`, `{{date}}` — which are substituted at creation time using the values the user entered in the New Project sheet.

Frontmatter is not templated. Title, year, client, tags, status, and date are still captured by the sheet and written into YAML by the existing `FrontmatterParser.serialize` path.

## Motivation

`ProjectCreator.create` currently hardcodes the body of every new project to:

```
# {title}

Project description here.
```

Users who always start from the same structure (a case-study outline, a brief skeleton, a research log) have to retype it every time, or clone an existing project and edit. A single workspace-level template — with placeholders for the values the user already types into the New Project sheet — turns "retype boilerplate" into "fill the blanks."

We intentionally keep the feature minimal: single template (not multiple named templates), body only (not frontmatter), literal string substitution (no conditionals, no loops). This is a YAGNI-first cut that can grow later without breaking anything.

## Scope

**In scope:**
- New `newProjectTemplate: String` preference on `AppState`, persisted via `UserDefaults`.
- New pure helper `ProjectTemplate.render(_:title:year:client:tags:date:) -> String` doing literal `{{var}}` substitution.
- `ProjectCreator.create` takes the rendered body instead of hardcoding it.
- `AppState.createProject` passes the current template in.
- New inline editor in the existing Workspace section of `AppSettingsView`, with help text and a "Reset default" button.
- Unit tests for `ProjectTemplate.render` covering substitution, empties, unknown placeholders, and date format. One end-to-end assertion added to existing `ProjectCreatorTests` to confirm a template reaches disk.

**Out of scope:**
- Multiple named templates / template picker in the New Project sheet.
- Template control over frontmatter (status, default tags, teaser).
- Click-to-insert variable chips in the editor.
- Live preview of the substituted result.
- Per-project template overrides.
- A dedicated sheet or external-file editing model for the template.

## Design

### Storage

New published string on `AppState`:

```swift
@Published var newProjectTemplate: String {
    didSet { UserDefaults.standard.set(newProjectTemplate, forKey: Keys.newProjectTemplate) }
}
```

- `Keys.newProjectTemplate` = `"newProjectTemplate"` (add to the existing `Keys` enum alongside `themeID`, `autoSaveDelay`, etc.).
- On init: read from `UserDefaults.standard.string(forKey:)`. If the key has never been set (`nil`), fall back to `AppState.defaultNewProjectTemplate`. An empty string is preserved as-is — it means the user deliberately wants an empty body, not "missing preference."

### Default template

Kept minimal — mirrors the current hardcoded body, with the placeholder syntax:

```
# {{title}}

Project description here.
```

Exported as `static let defaultNewProjectTemplate: String` on `AppState` so the Reset button and the init fallback share one source.

### Template rendering

New file `Services/ProjectTemplate.swift`:

```swift
enum ProjectTemplate {
    static func render(
        _ template: String,
        title: String,
        year: Int,
        client: String,
        tags: [String],
        date: Date
    ) -> String {
        var out = template
        out = out.replacingOccurrences(of: "{{title}}",  with: title)
        out = out.replacingOccurrences(of: "{{year}}",   with: String(year))
        out = out.replacingOccurrences(of: "{{client}}", with: client)
        out = out.replacingOccurrences(of: "{{tags}}",   with: tags.joined(separator: ", "))
        out = out.replacingOccurrences(of: "{{date}}",   with: Self.isoDate(date))
        return out
    }

    private static func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
```

**Semantics:**
- Case-sensitive literal replacement. `{{Title}}` is not `{{title}}`.
- Unknown placeholders (e.g. `{{foo}}`) are left as literal text — surfaces typos, no magic.
- Empty `client` → empty string insertion.
- Empty `tags` → empty string insertion (not `"[]"`, not `","`).
- Multi-tag join uses `", "` (comma + space) to match the chip-input display.
- Date format is `yyyy-MM-dd` in the current timezone, matching how dates already appear in frontmatter elsewhere in the app.
- No escape syntax. A user wanting a literal `{{title}}` in their output currently cannot have one — accepted limitation.

### `ProjectCreator` integration

Change `ProjectCreator.create(title:year:client:tags:rootURL:)` to accept a rendered body:

```swift
static func create(
    title: String,
    year: Int? = nil,
    client: String,
    tags: [String],
    rootURL: URL,
    body: String
) throws -> Project
```

The hardcoded body literal at `ProjectCreator.swift:37` is removed — callers supply the body. All substitution happens at the call site (`AppState.createProject`), not inside `ProjectCreator`. This keeps `ProjectCreator` ignorant of templating and makes `ProjectTemplate` testable in isolation.

`AppState.createProject` resolves the final year (same fallback `?? Calendar.current.component(.year, from: Date())` that `ProjectCreator` does today, hoisted one level up), renders the template, and passes `body` through:

```swift
let resolvedYear = year ?? Calendar.current.component(.year, from: Date())
let body = ProjectTemplate.render(
    newProjectTemplate,
    title: title,
    year: resolvedYear,
    client: client,
    tags: tags,
    date: Date()
)
let project = try ProjectCreator.create(
    title: title,
    year: resolvedYear,
    client: client,
    tags: tags,
    rootURL: rootURL,
    body: body
)
```

The `Date()` passed to `render` is the same moment that lands in frontmatter — so `{{date}}` and the YAML `date:` line agree to the second.

### Settings UI

Placed as the 4th item inside the existing **Workspace** section of `AppSettingsView`, after "Grain overlay" and before the section divider. Follows the same visual language as the rest of that section (label + control + help-caption stack).

Layout:

```
Workspace
├── Default view mode     [pills...]
├── Auto-save delay       [slider]
├── Grain overlay         [off|on] [slider]
└── New project template
    ┌──────────────────────────────────────┐
    │ # {{title}}                          │
    │                                      │
    │ Project description here.            │
    │                                      │
    │                                      │
    └──────────────────────────────────────┘
    Available: {{title}} {{year}} {{client}} {{tags}} {{date}}
    Used as the body of every new project.
    Frontmatter is set in the New Project sheet.        [Reset default]
```

**Widget details:**

- `TextEditor(text: $appState.newProjectTemplate)`:
  - `.font(.system(size: 12, design: .monospaced))`
  - `.foregroundStyle(theme.colors.textPrimary)`
  - `.scrollContentBackground(.hidden)` + `.background(theme.colors.surface)` so the native inset panel color doesn't leak through the theme.
  - `.frame(minHeight: 220)` — ~12 lines at 12pt monospaced. Fixed height; TextEditor handles its own vertical scrolling if content exceeds.
  - `.overlay(RoundedRectangle(cornerRadius: DT.Radius.small).stroke(theme.colors.border, lineWidth: 0.5))`
  - `.clipShape(RoundedRectangle(cornerRadius: DT.Radius.small))`
  - Horizontal padding inside the rounded container via `.padding(DT.Spacing.sm)` on the `TextEditor` itself (matching how other surfaces breathe in Settings).

- Variable list caption, rendered as a single line of muted monospaced text (wraps if the window is narrow):
  - `Text("Available: {{title}} {{year}} {{client}} {{tags}} {{date}}")`
  - `DT.Typography.caption`, `theme.colors.textTertiary`, monospaced only for the placeholder tokens (use `AttributedString` to mix; if that adds meaningful code weight, plain caption is acceptable).

- Help copy below the variable list, matching other Workspace captions (`DT.Typography.caption`, `textTertiary`):
  - "Used as the body of every new project. Frontmatter is set in the New Project sheet."

- Right-aligned `pillButton("Reset default")` (existing helper at `AppSettingsView.swift:283`) on the same row as the help text, pushed right with a `Spacer()`. Setting it back assigns `appState.newProjectTemplate = AppState.defaultNewProjectTemplate`.

No changes to other settings sections, no new keyboard shortcuts, no changes to the New Project sheet UI. Creation flow is unchanged from the user's perspective — they just get a different body when they hit Create.

### Edge cases

- **Empty template string.** Allowed. A created project file is frontmatter only, then a blank line. Not distinguished from "user deliberately wants an empty body." The Reset button remains the way back to the default.
- **Template with zero placeholders.** Rendered verbatim. Supported.
- **Template larger than the visible editor area.** Vertical scroll inside the TextEditor. No extra UI.
- **Year fallback.** `AppState.createProject` resolves the year the same way `ProjectCreator` did, then passes the resolved value into both `render` and `create`. `ProjectCreator` keeps its `year: Int? = nil` parameter for source-compatibility, but its internal fallback becomes unreachable from the app path (still used by tests that call `ProjectCreator.create` directly).
- **Typos in placeholders.** `{{titel}}` is preserved as literal `{{titel}}` in the output. User sees the typo in their new project and fixes it.
- **Preference migration.** First launch after the feature lands: no stored key → default is used. Not a schema change, no versioning needed.

## Files touched

**New files:**
- `PortyMcFolio/Services/ProjectTemplate.swift` — pure rendering helper.
- `PortyMcFolioTests/ProjectTemplateTests.swift` — unit tests for the helper.

**Modified files:**
- `PortyMcFolio/App/AppState.swift`:
  - Add `@Published var newProjectTemplate: String` with UserDefaults read/write.
  - Add `static let defaultNewProjectTemplate: String`.
  - Add `Keys.newProjectTemplate` case.
  - Update `createProject` to resolve year, render template, pass body through.
- `PortyMcFolio/Services/ProjectCreator.swift`:
  - Add `body: String` parameter; remove the hardcoded literal at line 37.
- `PortyMcFolio/Views/AppSettingsView.swift`:
  - Add the "New project template" block at the end of `workspaceSection`.
- `PortyMcFolioTests/ProjectCreatorTests.swift`:
  - Add a single assertion that a passed-through body with a substituted `{{title}}` lands in the written `.md` file.
- `project.yml` — unchanged (XcodeGen picks up new Swift files via directory glob).
- `PortyMcFolio.xcodeproj/project.pbxproj` — regenerated.

No changes to `FrontmatterParser`, `Project`, `NewProjectSheet`, `PortfolioStore`, or any other module.

## Testing

**Unit tests — `ProjectTemplateTests.swift`:**

- `testTitleSubstitution` — `"# {{title}}"` with title `"Hello"` → `"# Hello"`.
- `testYearSubstitution` — year `2026` → `"2026"`.
- `testClientSubstitution` — `"Client: {{client}}"` with `"Acme"` → `"Client: Acme"`.
- `testTagsMultipleJoin` — tags `["design", "branding"]` → `"design, branding"`.
- `testTagsEmpty` — tags `[]` → empty string, not `"[]"` or `","`.
- `testTagsSingle` — tags `["design"]` → `"design"` (no trailing comma).
- `testClientEmpty` — client `""` → empty string.
- `testDateISO` — known `Date` → `yyyy-MM-dd` string matching the frontmatter format used elsewhere.
- `testUnknownPlaceholderPreserved` — `"{{titel}}"` → left as `{{titel}}` in output.
- `testNoPlaceholders` — `"Just prose."` → `"Just prose."`.
- `testAllVariablesTogether` — one template exercising every placeholder at once, all substituted in one pass.

**Unit test addition — `ProjectCreatorTests.swift`:**

- One new case: `create(..., body: "# Templated\n\nHello {{irrelevant}}")` writes that exact body (no further substitution inside `ProjectCreator`) to disk, confirming `ProjectCreator` is now a dumb pass-through.

**Manual:**

- Launch the app, open Settings. Workspace section shows the new editor with the default template rendered.
- Edit the template to e.g. `"# {{title}} ({{year}})\n\nClient: {{client}}\nTags: {{tags}}\nCreated: {{date}}"`. The change persists across app relaunch.
- Create a new project titled "Test" with client "Acme", tags "design, branding", year 2026. Open the created `.md`. Body is the rendered template with all values filled.
- Create a new project with no client and no tags. The corresponding lines show empty values — `"Client: "` and `"Tags: "` — no crashes, no weird formatting.
- Hit "Reset default" in Settings. Editor snaps back to the default template. Next created project uses the default body.
- Clear the editor entirely (empty string). New project's `.md` has valid frontmatter followed by a blank body. File opens cleanly in editor and preview.

## Rollout & revert

Strictly additive on top of the current creation path. Old projects are untouched — the template only affects `ProjectCreator.create` going forward. No migration, no schema change.

A user with an unsaved template preference on first launch sees the default, which is visually identical to today's hardcoded body. No surprise.

Revert is `git revert -m 1 <merge-sha>` of the eventual merge. Removing the UserDefaults key is not necessary — a future reintroduction would read and use it.
