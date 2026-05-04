# Table CSV Export — Design

**Status:** Approved
**Date:** 2026-04-17
**Branch:** dev/v1-implementation

## Goal

Let the user export the project list (as currently filtered and sorted in the table view) to a CSV file via a single click. The button lives at the right edge of the table header row.

## Non-goals

- Per-project / per-row export.
- Export from grid mode.
- Export of body text, file lists, or link metadata. Only the columns visible in the table are exported.
- Re-import. CSV is one-way out.
- Keyboard shortcut. May be added later.
- Localization of the CSV header row.

## User flow

1. User is in the project list, table mode (`projectListMode == .table`).
2. User clicks the small download icon at the right edge of the table header row.
3. A standard macOS save panel appears, pre-filled with `{portfolioFolderName}-{yyyy-MM-dd}.csv`.
4. User confirms (or renames / picks another location).
5. The CSV is written. No success toast.
6. If the write fails, the failure is logged to the console and otherwise silent. (Sandbox + user-picked location makes failure rare; if a visible error becomes desired, an `NSAlert` can be added trivially later.)

## Architecture

### New files

#### `PortyMcFolio/Services/CSVExporter.swift`

Pure, dependency-free. No SwiftUI, no FileManager, no AppKit.

```swift
enum CSVExporter {
    /// Build the full CSV document (with BOM, CRLF line endings, trailing newline)
    /// for the given projects, in the order provided.
    static func csv(for projects: [Project]) -> String

    /// RFC 4180 escape: wrap in double quotes only if the field contains
    /// `,`, `"`, CR, or LF. Internal `"` becomes `""`. Empty stays empty.
    static func escape(_ field: String) -> String
}
```

#### `PortyMcFolioTests/CSVExporterTests.swift`

XCTest cases listed under "Tests" below. Constructs `Project` values directly via the memberwise initializer — no filesystem.

### Modified files

#### `PortyMcFolio/Views/ProjectListView.swift`

- Append a download button to `tableHeaderRow(c:)`, after a trailing `Spacer()`, anchored to the right edge regardless of which optional columns are visible.
- Add a private `exportCSV()` method that runs `NSSavePanel`, calls `CSVExporter.csv(for: sortedProjects)`, and writes to the chosen URL.
- Add a private `defaultExportFilename()` helper that builds `{slug(portfolioFolderName)}-{yyyy-MM-dd}.csv`, falling back to `PortyMcFolio-{yyyy-MM-dd}.csv` if `appState.portfolioRootURL` is nil.

No changes to `AppState`, `Project`, or any other file.

## CSV format

### Columns (fixed order)

`Year,Title,Client,Status,Tags`

### Per-field rules

| Field  | Source                          | Notes                                                                 |
|--------|---------------------------------|-----------------------------------------------------------------------|
| Year   | `project.year`                  | Integer, never quoted.                                                |
| Title  | `project.title`                 | RFC 4180 escaped. Empty title emitted as empty (NOT "Untitled").      |
| Client | `project.client`                | RFC 4180 escaped.                                                     |
| Status | `project.status.displayName`    | The human-readable label ("Empty", "In Progress", …) — matches badge. |
| Tags   | `project.tags.joined(", " → "; ")` | Joined inside one cell with `"; "` (semicolon + space), then RFC 4180 escaped as a whole. |

### Document-level rules

- **Header row**: literal `Year,Title,Client,Status,Tags` followed by CRLF.
- **Row order**: `sortedProjects` from the view, so the file matches the on-screen filter and sort.
- **Line endings**: `\r\n` between every row, including after the last data row.
- **Encoding**: UTF-8 with BOM (`\u{FEFF}` as the very first character of the document) so Excel on Windows opens non-ASCII tags correctly.

### Escaping (RFC 4180)

A field is wrapped in `"…"` **only** if it contains any of: `,`, `"`, `\r`, `\n`.
Internal `"` is doubled to `""`. Empty strings stay empty (not `""`).

Example:

```csv
Year,Title,Client,Status,Tags
2026,Dango,"Dango, Grug",Empty,Brand; UX; UI; Strategy; Identity
2026,"Concept ""PostBox""",Mold&Yeast,In Progress,Concept; Idea
2025,GTE.xyz,GTE,Empty,UX; UI; Brand
```

## Button placement & visual

Inserted at the end of `tableHeaderRow(c:)`:

```
[Year][Title][Client?][Status?][Tags?]   ← Spacer →   [⤓]
```

- **Always visible** in table mode at every window width. The export still includes all columns regardless of which ones the layout currently shows.
- **Icon**: SF Symbol `square.and.arrow.down`, size 11.
- **Color**: `DT.Colors.textTertiary`; lifts to `DT.Colors.textPrimary` on hover (consistent with sort buttons in the same row).
- **Hit area**: 22×22.
- **Style**: `.buttonStyle(.plain)`.
- **Tooltip**: `.help("Export visible projects as CSV")`.
- **Disabled** when `sortedProjects.isEmpty` — prevents producing a header-only CSV by accident.

## Save flow

```swift
let panel = NSSavePanel()
panel.allowedContentTypes = [.commaSeparatedText]
panel.nameFieldStringValue = defaultExportFilename()
panel.canCreateDirectories = true
panel.title = "Export Projects as CSV"

guard panel.runModal() == .OK, let url = panel.url else { return }

let csv = CSVExporter.csv(for: sortedProjects)
do {
    try csv.write(to: url, atomically: true, encoding: .utf8)
} catch {
    print("[CSVExport] write failed: \(error)")
}
```

### Default filename

`{portfolioFolderSlug}-{yyyy-MM-dd}.csv`, e.g. `My-Portfolio-2026-04-17.csv`.

The slug is derived from `appState.portfolioRootURL?.lastPathComponent`:

- Replace runs of whitespace with a single `-`.
- Strip any character outside `[A-Za-z0-9._-]`.
- If the result is empty, use `PortyMcFolio`.

Date is formatted with a fixed `yyyy-MM-dd` pattern, POSIX locale, UTC — stable across users.

### Sandbox

`com.apple.security.files.user-selected.read-write` is already declared in `PortyMcFolio/PortyMcFolio.entitlements`. No entitlement changes required.

## Tests

In `PortyMcFolioTests/CSVExporterTests.swift`:

1. `testEscape_plainStringIsUnchanged` — `escape("hello")` → `hello`.
2. `testEscape_commaIsQuoted` — `escape("Dango, Grug")` → `"Dango, Grug"`.
3. `testEscape_quoteIsDoubledAndWrapped` — `escape("Concept \"PostBox\"")` → `"Concept ""PostBox"""`.
4. `testEscape_newlineIsQuoted` — embedded `\n` triggers wrapping; the newline survives inside the quotes.
5. `testEscape_emptyStringStaysEmpty` — `escape("")` → `""` (the empty string, not the two-char `""`).
6. `testCSV_headerOrderIsFixed` — first line after the BOM is exactly `Year,Title,Client,Status,Tags`.
7. `testCSV_emptyProjectsListReturnsHeaderOnly` — output is BOM + header + CRLF, nothing else.
8. `testCSV_tagsAreSemicolonJoined` — `["A","B","C"]` → `A; B; C`.
9. `testCSV_statusUsesDisplayName` — a project with `.inProgress` produces `In Progress` in the row.
10. `testCSV_startsWithBOMAndUsesCRLF` — first character is `\u{FEFF}`; lines are separated by `\r\n`.
11. `testCSV_titleWithCommaAndQuoteRoundTrips` — a project titled `Hello, "world"` produces a correctly escaped line.

Test fixtures construct `Project` values directly with the memberwise initializer; no filesystem access.

## Out of scope (deferred)

- ⌘E keyboard shortcut.
- Visible error UI (`NSAlert`) on write failure.
- Excluding the BOM (current default is "include BOM" for Excel-on-Windows compatibility).
- Configurable column set / order.
- Alternative tag delimiters.
