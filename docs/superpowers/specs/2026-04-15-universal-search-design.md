# Universal Cmd+K Search — Design Spec

**Date:** 2026-04-15
**Status:** Draft

## Overview

Replace the broken Cmd+K search palette with a universal search that finds projects, files, links, and tags across the entire portfolio, plus a small set of app commands. The goal is a fast, reliable, keyboard-driven way to navigate anywhere in the app.

## Problems With Current Implementation

1. **FTS index dropped on every launch** — `migrate()` runs `DROP TABLE` + `CREATE VIRTUAL TABLE` unconditionally, destroying and rebuilding the index every time the app starts.
2. **Prefix-only matching** — search tokenizes the query and appends `*` to each token. Only prefix matches work; substring matches fail.
3. **Single blob per project** — files, links, and body text are concatenated into one `body` field. There's no way to know *what* matched or return typed results.
4. **Only searches projects** — placeholder says "projects, files, tags…" but only project-level results are returned.
5. **No match context** — results don't indicate why they matched.
6. **Duplicate search paths** — `SearchPalette` and `AppState.filteredProjects` each implement their own FTS-with-fallback logic independently.
7. **No grouping** — flat list capped at 20, no type indicators.
8. **Tags joined with spaces** — loses structure; multi-word tags are indistinguishable from separate tags.

## Design

### Searchable Entity Types

| Type | What Gets Indexed | Displayed Fields | Action on Select |
|------|------------------|-----------------|-----------------|
| `project` | title, client, tags (space-separated), status, body (README markdown) | Title, client, year, status badge | Navigate to project detail |
| `file` | filename, filename without extension | Filename, parent project title | Navigate to project, select file in gallery |
| `link` | url, host, title, annotation | Link title (or host), parent project title | Navigate to project, select link in gallery links tab |
| `tag` | tag name | Tag name, number of projects with this tag | Set `searchQuery` to tag, dismiss palette, stay on/return to project list |
| `command` | — (client-side filter only) | Command name, keyboard shortcut if any | Execute: open new project sheet / open settings |

### Search Index

#### Schema

Replace the single `projects_fts` table with a typed FTS5 table:

```sql
CREATE VIRTUAL TABLE search_fts USING fts5(
    type UNINDEXED,
    entity_id UNINDEXED,
    parent_uid UNINDEXED,
    primary_text,
    secondary_text,
    body,
    tokenize='unicode61 remove_diacritics 2'
);
```

Column mapping by type:

| Type | entity_id | parent_uid | primary_text | secondary_text | body |
|------|-----------|-----------|-------------|---------------|------|
| project | project uid | — (empty) | title | client | tags + status + README body |
| file | relative path from project folder | project uid | filename | filename without extension | — |
| link | link uid | project uid | link title | url + host | annotation |
| tag | tag name | — (empty) | tag name | — | — |

#### Migration

Use a schema version stored in a separate `meta` table:

```sql
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
```

On launch, read the `schema_version` key. If it doesn't match the current version (e.g., `"2"`), drop `search_fts` and recreate. Otherwise leave the table alone.

Index is always fully rebuilt on `refreshProjects()` — this matches current behavior and is acceptable for local portfolios (dozens of projects, hundreds of files). The rebuild:

1. `DELETE FROM search_fts`
2. For each project: insert one `project` row
3. For each file in each project folder (excluding README.md): insert one `file` row
4. For each link file: insert one `link` row (instead of a `file` row)
5. Collect all unique tags with counts: insert one `tag` row per unique tag

#### Search Method

```
func search(query:) -> [SearchResult]
```

Tokenize the query, build the FTS5 match expression with prefix wildcards (`token*`), and return results ordered by `rank`. Each `SearchResult` carries `type`, `entityID`, `parentUID`, `primaryText`, `secondaryText`.

The caller groups results by type and applies per-type caps.

### SearchPalette UI

#### Layout (top to bottom)

1. **Search input** — NSTextField wrapper (keep current `SearchPaletteTextField` for reliable focus + arrow key handling). Placeholder: "Search projects, files, links, tags…"
2. **Divider**
3. **Grouped results** — sections with headers, each section is a type. Section order: Commands, Projects, Files, Links, Tags. Empty sections hidden.
4. **Hints bar** — arrow keys, enter, esc (keep current)

#### Section Headers

Light, uppercase caption text (using `DT.Typography.caption`), e.g. "PROJECTS", "FILES". No chrome, just a label.

#### Result Rows

Each row:
- **Icon** (left, 20x20 frame):
  - Project: `folder.fill`
  - File: SF Symbol based on file extension (`doc.fill` for docs, `photo` for images, `film` for video, `music.note` for audio, `doc` as default)
  - Link: `link`
  - Tag: `tag`
  - Command: `command`
- **Primary text** — title/filename/tag name. `.system(size: 13, weight: .medium)`.
- **Secondary text** — context. `.system(size: 11)`, `.secondary` color.
  - Project: year + client (if any)
  - File: parent project title
  - Link: host or URL, parent project title
  - Tag: "N projects"
  - Command: keyboard shortcut badge (e.g. "Cmd+N")
- **Selection highlight** — accent color at 12% opacity (keep current)

#### Result Caps Per Group

- Projects: 5
- Files: 5
- Links: 3
- Tags: 3
- Commands: 2

These are starting values — adjust based on real usage.

#### Empty Query Behavior

When the query is empty, show:
- **Commands** section (always visible: "New Project", "Settings")
- **Projects** section showing all projects (capped at 5, sorted by most recent year)

This makes Cmd+K useful as a quick launcher even without typing.

#### Keyboard Navigation

Same as current — arrow up/down moves across all visible rows (across sections), Enter selects, Esc closes. Selection wraps within the flattened list of all visible rows.

#### Result Actions

On selection (Enter or click):

| Type | Action |
|------|--------|
| Project | `appState.selectedProject = project` |
| File | `appState.selectedProject = parentProject`, then set `selectedFileURL` on the detail view to auto-select in gallery |
| Link | Same as file — navigate to project, gallery switches to links tab, link is selected |
| Tag | `appState.searchQuery = tagName`, navigate to project list |
| Command: New Project | `appState.isShowingNewProject = true` |
| Command: Settings | `appState.isShowingSettings = true` |

All actions dismiss the palette.

### Commands

Hardcoded list, not indexed. Filtered client-side by checking if the command name contains the query (case-insensitive).

```swift
struct SearchCommand {
    let name: String
    let icon: String          // SF Symbol
    let shortcut: String?     // display-only, e.g. "Cmd+N"
    let action: (AppState) -> Void
}
```

Commands:
1. **New Project** — icon: `plus.rectangle`, shortcut: "Cmd+N", action: set `isShowingNewProject = true`
2. **Settings** — icon: `gearshape`, shortcut: nil, action: set `isShowingSettings = true`

### Toolbar Filter Removal

Remove the `TextField("Filter…")` from `ProjectListView`'s toolbar. The toolbar center slot becomes empty (or removed).

`AppState.searchQuery` remains — it's still used for tag-click filtering (clicking a tag pill sets `searchQuery` to that tag). The search palette's tag result does the same thing.

`AppState.filteredProjects` continues to use `searchQuery` for filtering the project list, but this is now only set by tag clicks and the palette's tag action — not by a dedicated text field.

### SearchResult Model

```swift
enum SearchResultType: String {
    case project, file, link, tag, command
}

struct SearchResult: Identifiable, Equatable {
    let id: String              // type + entityID for uniqueness
    let type: SearchResultType
    let entityID: String        // uid, relative path, tag name, command name
    let parentUID: String       // project uid for file/link, empty otherwise
    let primaryText: String     // display title
    let secondaryText: String   // context line
}
```

### File Selection Plumbing

For file/link results to navigate into a project *and* select a specific file, we need:

- `AppState` gains an optional `pendingFileSelection: URL?`
- When a file/link search result is selected: set `selectedProject` and `pendingFileSelection`
- `ProjectDetailView` / `GalleryView` observes `pendingFileSelection` on appear — if set, switches to gallery mode, selects the file, and clears the pending value
- For links: additionally switch gallery to the links tab

### What This Design Does NOT Include

- Search within file *contents* (only filenames are indexed)
- Fuzzy matching (FTS5 prefix matching is sufficient for now)
- Recent/frequent project boosting (can be added later as a ranking signal)
- Inline preview of search results
- Search history

These can be layered on later without changing the architecture.

## Files to Change

| File | Change |
|------|--------|
| `Services/SearchIndex.swift` | Rewrite: new schema, typed rows, versioned migration, new `search()` return type |
| `Views/SearchPalette.swift` | Rewrite: grouped results, richer rows, command support, empty-state |
| `App/AppState.swift` | Add `pendingFileSelection`, remove `searchIndexAccess`, update `refreshProjects()` indexing |
| `Views/ProjectListView.swift` | Remove toolbar filter `TextField` |
| `Views/ProjectDetailView.swift` | Handle `pendingFileSelection` to auto-select file in gallery |
| `Views/GalleryView.swift` | Accept and act on `pendingFileSelection` |
| `Models/SearchResult.swift` | New file: `SearchResult`, `SearchResultType`, `SearchCommand` |
| `Tests/SearchIndexTests.swift` | Rewrite: test typed indexing, per-type search, tag deduplication |
