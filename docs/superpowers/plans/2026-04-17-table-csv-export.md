# Table CSV Export — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a download button at the right edge of the project-list table header that exports the currently filtered + sorted projects to a CSV file the user picks via `NSSavePanel`.

**Architecture:** A new pure-Swift `CSVExporter` service (`Services/CSVExporter.swift`) builds an RFC 4180 CSV string from `[Project]`. `ProjectListView` adds a small icon button to its existing `tableHeaderRow`, runs `NSSavePanel`, and writes the exporter's output to the chosen URL. No changes to `AppState`, `Project`, or any other file.

**Tech Stack:** Swift, SwiftUI, AppKit (`NSSavePanel`), XCTest. No new dependencies.

**Spec:** [docs/superpowers/specs/2026-04-17-table-csv-export-design.md](../specs/2026-04-17-table-csv-export-design.md)

**Conventions used in this plan:**

- The test command in this project is:
  ```bash
  xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' 2>&1 | grep -E '(Test Case|FAIL|error:|PASS|passed|failed)'
  ```
  Filtered greps are shown after each step.
- `project.yml` source globbing picks up new files in `PortyMcFolio/` and `PortyMcFolioTests/` automatically. **After creating any new `.swift` file, regenerate the Xcode project with `xcodegen generate` before running tests.**

---

## File Structure

| Path | Action | Responsibility |
|------|--------|----------------|
| `PortyMcFolio/Services/CSVExporter.swift` | **create** | Pure functions: `escape(_:)` and `csv(for:)`. No SwiftUI, no FileManager, no AppKit. |
| `PortyMcFolioTests/CSVExporterTests.swift` | **create** | XCTest cases for escape rules and full-document construction. |
| `PortyMcFolio/Views/ProjectListView.swift` | **modify** | Append download button to `tableHeaderRow`, reserve width for it in `tableView`'s geometry math, add `exportCSV()` and `defaultExportFilename()` helpers. |

No other files are touched. No entitlements changes (`com.apple.security.files.user-selected.read-write` is already declared).

---

## Task 1: `CSVExporter.escape` — RFC 4180 field escaping

**Files:**
- Create: `PortyMcFolio/Services/CSVExporter.swift`
- Create: `PortyMcFolioTests/CSVExporterTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `PortyMcFolioTests/CSVExporterTests.swift`:

```swift
import XCTest
@testable import PortyMcFolio

final class CSVExporterTests: XCTestCase {

    // MARK: - escape(_:)

    func testEscape_plainStringIsUnchanged() {
        XCTAssertEqual(CSVExporter.escape("hello"), "hello")
    }

    func testEscape_commaIsQuoted() {
        XCTAssertEqual(CSVExporter.escape("Dango, Grug"), "\"Dango, Grug\"")
    }

    func testEscape_quoteIsDoubledAndWrapped() {
        // Input:  Concept "PostBox"
        // Output: "Concept ""PostBox"""
        XCTAssertEqual(
            CSVExporter.escape("Concept \"PostBox\""),
            "\"Concept \"\"PostBox\"\"\""
        )
    }

    func testEscape_newlineIsQuoted() {
        XCTAssertEqual(CSVExporter.escape("line1\nline2"), "\"line1\nline2\"")
    }

    func testEscape_carriageReturnIsQuoted() {
        XCTAssertEqual(CSVExporter.escape("a\rb"), "\"a\rb\"")
    }

    func testEscape_emptyStringStaysEmpty() {
        // Empty must stay empty — NOT the two-character `""`
        XCTAssertEqual(CSVExporter.escape(""), "")
    }
}
```

- [ ] **Step 2: Create the empty `CSVExporter` source file**

Create `PortyMcFolio/Services/CSVExporter.swift`:

```swift
import Foundation

enum CSVExporter {
}
```

- [ ] **Step 3: Regenerate Xcode project so it picks up the new files**

Run:
```bash
cd <repo> && xcodegen generate
```
Expected: `Created project at PortyMcFolio.xcodeproj`.

- [ ] **Step 4: Run tests to verify they fail**

Run:
```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' 2>&1 | grep -E '(error:|Test Case.*failed|FAIL)'
```
Expected: compile error — `Type 'CSVExporter' has no member 'escape'`.

- [ ] **Step 5: Implement `escape(_:)`**

Replace the contents of `PortyMcFolio/Services/CSVExporter.swift` with:

```swift
import Foundation

enum CSVExporter {

    /// RFC 4180 escape: wrap in `"…"` only if the field contains `,`, `"`,
    /// CR, or LF. Internal `"` is doubled. Empty input stays empty (not `""`).
    static func escape(_ field: String) -> String {
        if field.isEmpty { return "" }
        let needsQuoting = field.contains(",")
            || field.contains("\"")
            || field.contains("\n")
            || field.contains("\r")
        guard needsQuoting else { return field }
        let doubled = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(doubled)\""
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run:
```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' -only-testing:PortyMcFolioTests/CSVExporterTests 2>&1 | grep -E '(Test Case|passed|failed|error:)'
```
Expected: 6 cases, all passed.

- [ ] **Step 7: Commit**

```bash
git add PortyMcFolio/Services/CSVExporter.swift PortyMcFolioTests/CSVExporterTests.swift PortyMcFolio.xcodeproj
git commit -m "feat: CSVExporter.escape with RFC 4180 rules"
```

---

## Task 2: `CSVExporter.csv(for:)` — full document builder

**Files:**
- Modify: `PortyMcFolio/Services/CSVExporter.swift`
- Modify: `PortyMcFolioTests/CSVExporterTests.swift`

- [ ] **Step 1: Add a `Project` test helper and the failing tests**

Append to `PortyMcFolioTests/CSVExporterTests.swift` (inside the `final class CSVExporterTests` body, after the existing tests):

```swift
    // MARK: - csv(for:) helpers

    private func makeProject(
        uid: String = "abcd1234",
        year: Int = 2025,
        title: String = "Test",
        client: String = "ACME",
        status: ProjectStatus = .empty,
        tags: [String] = []
    ) -> Project {
        Project(
            uid: uid,
            year: year,
            folderName: "\(year)_test_\(uid)",
            folderURL: URL(fileURLWithPath: "/tmp/\(year)_test_\(uid)"),
            title: title,
            date: Date(timeIntervalSince1970: 0),
            tags: tags,
            client: client,
            status: status,
            body: "",
            teaser: ""
        )
    }

    // MARK: - csv(for:)

    func testCSV_startsWithBOM() {
        let csv = CSVExporter.csv(for: [])
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}"), "CSV should start with UTF-8 BOM")
    }

    func testCSV_headerOrderIsFixed() {
        let csv = CSVExporter.csv(for: [])
        XCTAssertTrue(
            csv.hasPrefix("\u{FEFF}Year,Title,Client,Status,Tags\r\n"),
            "Expected BOM + fixed header followed by CRLF, got: \(csv.debugDescription)"
        )
    }

    func testCSV_emptyProjectsListReturnsHeaderOnly() {
        let csv = CSVExporter.csv(for: [])
        XCTAssertEqual(csv, "\u{FEFF}Year,Title,Client,Status,Tags\r\n")
    }

    func testCSV_usesCRLFBetweenRows() {
        let projects = [
            makeProject(year: 2025, title: "A", client: "X"),
            makeProject(uid: "ffff0000", year: 2024, title: "B", client: "Y"),
        ]
        let csv = CSVExporter.csv(for: projects)
        // Two data rows + header = 3 CRLFs (one after each)
        let crlfCount = csv.components(separatedBy: "\r\n").count - 1
        XCTAssertEqual(crlfCount, 3)
    }

    func testCSV_endsWithTrailingCRLF() {
        let projects = [makeProject(title: "Only")]
        let csv = CSVExporter.csv(for: projects)
        XCTAssertTrue(csv.hasSuffix("\r\n"))
    }

    func testCSV_tagsAreSemicolonJoined() {
        let projects = [makeProject(title: "T", tags: ["A", "B", "C"])]
        let csv = CSVExporter.csv(for: projects)
        XCTAssertTrue(csv.contains("A; B; C"), "Got: \(csv)")
    }

    func testCSV_emptyTagsProduceEmptyCell() {
        let projects = [makeProject(title: "T", tags: [])]
        let csv = CSVExporter.csv(for: projects)
        // Last column is tags — line should end with a comma then CRLF
        XCTAssertTrue(csv.contains(",\r\n"), "Got: \(csv)")
    }

    func testCSV_statusUsesDisplayName() {
        let projects = [makeProject(title: "T", status: .inProgress)]
        let csv = CSVExporter.csv(for: projects)
        XCTAssertTrue(csv.contains(",In Progress,"), "Got: \(csv)")
        XCTAssertFalse(csv.contains("inProgress"), "rawValue should not appear")
    }

    func testCSV_titleWithCommaAndQuoteIsEscaped() {
        // Title:  Hello, "world"
        // Cell:   "Hello, ""world"""
        let projects = [makeProject(title: "Hello, \"world\"")]
        let csv = CSVExporter.csv(for: projects)
        XCTAssertTrue(
            csv.contains("\"Hello, \"\"world\"\"\""),
            "Expected escaped title in output, got: \(csv)"
        )
    }

    func testCSV_yearIsNotQuoted() {
        let projects = [makeProject(year: 2026, title: "X", client: "Y")]
        let csv = CSVExporter.csv(for: projects)
        // Row should start with `2026,` (no quotes around the year)
        XCTAssertTrue(csv.contains("\r\n2026,X,Y,Empty,\r\n"), "Got: \(csv)")
    }

    func testCSV_emptyTitleEmitsEmptyCell_notUntitled() {
        let projects = [makeProject(title: "", client: "C")]
        let csv = CSVExporter.csv(for: projects)
        // Title cell is empty, so we should see `,,C,` in the row
        XCTAssertTrue(csv.contains(",,C,"), "Got: \(csv)")
        XCTAssertFalse(csv.contains("Untitled"), "CSV must export raw value, not display fallback")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' -only-testing:PortyMcFolioTests/CSVExporterTests 2>&1 | grep -E '(error:|Test Case.*failed|FAIL)'
```
Expected: compile error — `Type 'CSVExporter' has no member 'csv'`.

- [ ] **Step 3: Implement `csv(for:)`**

Append to `PortyMcFolio/Services/CSVExporter.swift`, inside the `enum CSVExporter` body:

```swift
    /// Build the full CSV document for the given projects, in the order provided.
    /// Output is UTF-8 with a BOM prefix, CRLF line endings, and a trailing CRLF
    /// after the last row (header-only when `projects` is empty).
    static func csv(for projects: [Project]) -> String {
        let bom = "\u{FEFF}"
        let header = "Year,Title,Client,Status,Tags"

        var out = bom + header + "\r\n"
        for project in projects {
            let cells = [
                String(project.year),
                escape(project.title),
                escape(project.client),
                escape(project.status.displayName),
                escape(project.tags.joined(separator: "; ")),
            ]
            out += cells.joined(separator: ",") + "\r\n"
        }
        return out
    }
```

- [ ] **Step 4: Run all CSVExporter tests to verify they pass**

Run:
```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' -only-testing:PortyMcFolioTests/CSVExporterTests 2>&1 | grep -E '(Test Case|passed|failed|error:)'
```
Expected: all CSVExporterTests cases passed (6 escape + 11 csv = 17 cases).

- [ ] **Step 5: Run the full suite to confirm no regressions**

Run:
```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' 2>&1 | grep -E '(Executed|failed|error:)' | tail -10
```
Expected: `Executed N tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add PortyMcFolio/Services/CSVExporter.swift PortyMcFolioTests/CSVExporterTests.swift
git commit -m "feat: CSVExporter.csv(for:) builds full CSV document"
```

---

## Task 3: Add the download button to the table header

This task is UI-only — no unit tests. Verification is by build + manual smoke test in Task 4.

**Files:**
- Modify: `PortyMcFolio/Views/ProjectListView.swift`

- [ ] **Step 1: Reserve width for the button in `tableView`**

In `PortyMcFolio/Views/ProjectListView.swift`, find the `tableView` computed property (currently around line 258). Replace its body:

```swift
    private var tableView: some View {
        GeometryReader { geo in
            let c = Col.widths(for: geo.size.width - DT.Spacing.lg * 2)

            VStack(spacing: 0) {
                tableHeaderRow(c: c)
                    .padding(.horizontal, DT.Spacing.lg)
```

with this version, which subtracts the export-button reservation from the available width so header and data rows stay aligned and leave room for the button at the right edge:

```swift
    private var tableView: some View {
        GeometryReader { geo in
            // Reserve room at the right edge for the export button (icon + gap).
            let exportReserve: CGFloat = 22 + Col.gap
            let c = Col.widths(for: geo.size.width - DT.Spacing.lg * 2 - exportReserve)

            VStack(spacing: 0) {
                tableHeaderRow(c: c)
                    .padding(.horizontal, DT.Spacing.lg)
```

Leave the rest of the `tableView` body unchanged.

- [ ] **Step 2: Add the button to `tableHeaderRow`**

In the same file, find `tableHeaderRow(c:)` (currently around line 284). Replace its body:

```swift
    private func tableHeaderRow(c: Col.Widths) -> some View {
        HStack(spacing: Col.gap) {
            sortButton("Year", field: .year)
                .frame(width: c.year, alignment: .leading)
            sortButton("Title", field: .title)
                .frame(width: c.title, alignment: .leading)
            if c.showClient {
                sortButton("Client", field: .client)
                    .frame(width: c.client, alignment: .leading)
            }
            if c.showStatus {
                sortButton("Status", field: .status)
                    .frame(width: c.status, alignment: .leading)
            }
            if c.showTags {
                Text("Tags")
                    .font(DT.Typography.micro)
                    .foregroundStyle(DT.Colors.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .frame(width: c.tags, alignment: .leading)
            }
        }
        .padding(.vertical, DT.Spacing.sm)
    }
```

with this version, which appends a `Spacer()` and the export button:

```swift
    private func tableHeaderRow(c: Col.Widths) -> some View {
        HStack(spacing: Col.gap) {
            sortButton("Year", field: .year)
                .frame(width: c.year, alignment: .leading)
            sortButton("Title", field: .title)
                .frame(width: c.title, alignment: .leading)
            if c.showClient {
                sortButton("Client", field: .client)
                    .frame(width: c.client, alignment: .leading)
            }
            if c.showStatus {
                sortButton("Status", field: .status)
                    .frame(width: c.status, alignment: .leading)
            }
            if c.showTags {
                Text("Tags")
                    .font(DT.Typography.micro)
                    .foregroundStyle(DT.Colors.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .frame(width: c.tags, alignment: .leading)
            }
            Spacer(minLength: 0)
            exportButton
        }
        .padding(.vertical, DT.Spacing.sm)
    }
```

- [ ] **Step 3: Add the `exportButton` view**

In the same file, immediately after the `sortButton(_:field:)` method (around line 333, just before `tableDataRow(_:c:)`), insert:

```swift
    @State private var isExportHovering = false

    private var exportButton: some View {
        Button(action: exportCSV) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 11))
                .foregroundStyle(
                    isExportHovering
                        ? DT.Colors.textPrimary
                        : DT.Colors.textTertiary
                )
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(sortedProjects.isEmpty)
        .opacity(sortedProjects.isEmpty ? 0.4 : 1.0)
        .onHover { hovering in isExportHovering = hovering }
        .help("Export visible projects as CSV")
    }

    private func exportCSV() {
        // Implemented in Task 4.
    }
```

- [ ] **Step 4: Build to verify it compiles**

Run:
```bash
xcodebuild build -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | grep -E '(error:|warning:|BUILD)' | tail -20
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Views/ProjectListView.swift
git commit -m "feat: add CSV export button to table header (no-op action)"
```

---

## Task 4: Wire `exportCSV()` to `NSSavePanel` and `CSVExporter`

**Files:**
- Modify: `PortyMcFolio/Views/ProjectListView.swift`

- [ ] **Step 1: Add the `AppKit` import (if not already present)**

At the top of `PortyMcFolio/Views/ProjectListView.swift`, the file currently imports `SwiftUI` only. SwiftUI on macOS already brings AppKit, so `NSSavePanel` is available without an explicit `import AppKit`. **Verify** by searching the file:

```bash
head -5 PortyMcFolio/Views/ProjectListView.swift
```
If only `import SwiftUI` is present, leave it as-is. (No edit required for this step.)

- [ ] **Step 2: Replace the placeholder `exportCSV()` and add `defaultExportFilename()`**

In `PortyMcFolio/Views/ProjectListView.swift`, find the placeholder added in Task 3:

```swift
    private func exportCSV() {
        // Implemented in Task 4.
    }
```

Replace it with:

```swift
    private func exportCSV() {
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
    }

    private func defaultExportFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: Date())

        let raw = appState.portfolioRootURL?.lastPathComponent ?? ""
        let slug = sanitizeFilenameStem(raw)
        let stem = slug.isEmpty ? "PortyMcFolio" : slug
        return "\(stem)-\(date).csv"
    }

    /// Lossy normalize a folder name into a safe filename stem:
    /// runs of whitespace → single `-`; any character outside `[A-Za-z0-9._-]` is dropped.
    private func sanitizeFilenameStem(_ raw: String) -> String {
        // Collapse whitespace runs to single hyphen
        let hyphenated = raw.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        // Keep only safe filename characters
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        return String(hyphenated.unicodeScalars.filter { allowed.contains($0) })
    }
```

- [ ] **Step 3: Add `import UniformTypeIdentifiers` for `.commaSeparatedText`**

`UTType.commaSeparatedText` lives in `UniformTypeIdentifiers`. At the top of the file, change:

```swift
import SwiftUI
```

to:

```swift
import SwiftUI
import UniformTypeIdentifiers
```

- [ ] **Step 4: Build to verify it compiles**

Run:
```bash
xcodebuild build -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | grep -E '(error:|BUILD)' | tail -10
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Run the full test suite to confirm nothing broke**

Run:
```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' 2>&1 | grep -E '(Executed|failed|error:)' | tail -5
```
Expected: `Executed N tests, with 0 failures`.

- [ ] **Step 6: Manual smoke test**

This step requires running the app interactively. Launch from Xcode (`Cmd+R`) or:
```bash
open -a Xcode PortyMcFolio.xcodeproj
```

Verify in order:
1. Open a portfolio with at least 2 projects.
2. Switch to **Table** mode (⌘2 or the table icon in the toolbar).
3. Confirm a small download arrow icon is visible at the right edge of the header row, after the Tags column.
4. Hover the icon — color lifts from tertiary to primary.
5. Click it — `NSSavePanel` appears with default filename `{folder}-{yyyy-MM-dd}.csv`.
6. Save to Desktop. Open the file in Numbers or a text editor.
7. Verify:
   - Five columns: `Year`, `Title`, `Client`, `Status`, `Tags`.
   - Row order matches the on-screen sort.
   - Applying a filter (typing in the search field) and re-exporting produces only the matching rows.
   - A project with multiple tags shows them as `tag1; tag2; tag3` in one cell.
   - A project with a comma in its title or client is correctly quoted.
8. Resize the window narrow enough to hide the Status / Tags / Client columns. Confirm the export button is still visible at the right edge, and the exported CSV still contains all five columns.
9. Filter to a query with zero matches. Confirm the export button is disabled (greyed out) and not clickable.

If any step fails, fix the issue, re-run Steps 4–5, then redo this step.

- [ ] **Step 7: Commit**

```bash
git add PortyMcFolio/Views/ProjectListView.swift
git commit -m "feat: wire CSV export button to NSSavePanel + CSVExporter"
```

---

## Self-Review

**Spec coverage:**

| Spec section | Implemented in |
|---|---|
| `CSVExporter.swift` with `csv(for:)` and `escape(_:)` | Tasks 1, 2 |
| `CSVExporterTests.swift` with all 11 test cases | Tasks 1, 2 (renumbered as 6 escape + 11 csv tests; spec's 11 are all covered, plus 2 extra: `testCSV_emptyTagsProduceEmptyCell`, `testCSV_yearIsNotQuoted`, `testCSV_emptyTitleEmitsEmptyCell_notUntitled`) |
| Header row: column order `Year,Title,Client,Status,Tags` | Task 2, Step 3 |
| BOM + CRLF + trailing CRLF | Task 2, Step 3; tests in Step 1 |
| Status as `displayName` | Task 2, Step 3; test in Step 1 |
| Tags joined with `"; "` | Task 2, Step 3; test in Step 1 |
| RFC 4180 escaping (only quote when needed; double internal `"`; empty stays empty) | Task 1 |
| Button at end of header row, always visible | Task 3, Steps 1–3 |
| `square.and.arrow.down` icon, size 11, tertiary color, hover lifts to primary | Task 3, Step 3 |
| 22×22 hit area, `.help(...)`, `.buttonStyle(.plain)` | Task 3, Step 3 |
| Disabled when `sortedProjects.isEmpty` | Task 3, Step 3 (`.disabled(...)` + opacity) |
| `NSSavePanel` config (`.commaSeparatedText`, title, canCreateDirectories) | Task 4, Step 2 |
| Default filename `{slug}-{yyyy-MM-dd}.csv`, fallback `PortyMcFolio-…` | Task 4, Step 2 (`defaultExportFilename`, `sanitizeFilenameStem`) |
| Write via `try csv.write(to:atomically:encoding:)`, console-log on error | Task 4, Step 2 |
| No entitlements changes | (verified — none needed) |

**Placeholder scan:** None. Every step contains the exact code or command to run.

**Type / name consistency:**
- `CSVExporter.escape(_:)` and `CSVExporter.csv(for:)` — referenced consistently across Tasks 1, 2, 4.
- `exportButton`, `exportCSV()`, `defaultExportFilename()`, `sanitizeFilenameStem(_:)`, `isExportHovering` — all defined in Task 3 or 4 and referenced consistently.
- `Col.gap` (already exists in the file, value `12`) — referenced in Task 3, Step 1's `exportReserve` calculation.
- `DT.Colors.textPrimary`, `DT.Colors.textTertiary`, `DT.Spacing.lg` — already exist in the codebase.
- `sortedProjects` (already exists in `ProjectListView`, line 205) — referenced in Tasks 3 and 4.
- `appState.portfolioRootURL` (already exists in `AppState`) — referenced in Task 4.
- `ProjectStatus.displayName` returns `"Empty" | "In Progress" | "Archived"` — verified in [ProjectStatus.swift:10](../../../PortyMcFolio/Models/ProjectStatus.swift) — matches `testCSV_statusUsesDisplayName`.
- `Project` memberwise initializer signature matches the `makeProject` test helper — verified in [Project.swift:14](../../../PortyMcFolio/Models/Project.swift).
