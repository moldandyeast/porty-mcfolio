# Project "When" Field — Rev 2 Refactor

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the Rev 1 implementation into the two-mode design described in the Rev 2 section of `docs/superpowers/specs/2026-04-27-project-when-field-design.md` — Year-only or Range only, drop `DatePrecision`, drop the YearStepper from settings, derive folder year from the When's End on save.

**Architecture:** Most plumbing from Rev 1 stays (cache columns, reconciler factory, frontmatter parser reading `dateEnd`, `WhenFormatting` helper, `ProjectSort` comparator). The picker is rewritten, the `DatePrecision` enum is deleted, the YearStepper is removed from the settings sheet, and `AppState.updateProjectMetadata` no longer takes a `year:` parameter — it derives the new folder year from the supplied `WhenValue`.

**Tech Stack:** Swift 5.9, SwiftUI, GRDB, XCTest. Build via `xcodebuild`; new files require `xcodegen generate`.

**Project conventions:**
- No SwiftUI view tests (only model/service/state tests).
- Commit style: `type(scope): summary`. Co-author trailer required.
- Branch: `feature/project-when-field` (already in worktree at `.worktrees/project-when-field`).

---

## Task 1: Drop `DatePrecision` and reshape `WhenValue`

Remove the precision concept. `WhenValue` keeps `date: Date` and `dateEnd: Date?` and gains `yearOnlyYear: Int?` (used only when `dateEnd == nil`, captures the year the user picked in year-only mode). All call sites update.

**Files:**
- Modify: `PortyMcFolio/Models/Project.swift`
- Modify: `PortyMcFolio/Services/FrontmatterParser.swift`
- Modify: `PortyMcFolio/Services/ProjectMetadataCache.swift`
- Modify: `PortyMcFolio/Services/ProjectReconciler.swift`
- Modify: `PortyMcFolio/Views/EditorialCardView.swift`
- Modify: `PortyMcFolioTests/FrontmatterParserTests.swift`
- Modify: `PortyMcFolioTests/ProjectMetadataCacheTests.swift`
- Modify: `PortyMcFolioTests/ProjectReconcilerTests.swift`
- Modify: `PortyMcFolioTests/SearchIndexTests.swift`

- [ ] **Step 1: Delete the `DatePrecision` enum and reshape `WhenValue`**

In `PortyMcFolio/Models/Project.swift`, delete the `DatePrecision` enum entirely. Replace the `WhenValue` struct with:

```swift
/// Transport struct for the When metadata. Used as a binding for `WhenPicker`
/// and as a parameter on `AppState.updateProjectMetadata`.
///
/// Two states:
/// - **Year only** — `dateEnd == nil`. The project lives under `yearOnlyYear`.
/// - **Range** — `dateEnd != nil`. `date` is the range start; folder year derives
///   from the year of `dateEnd`.
struct WhenValue: Equatable {
    /// Range start anchor when `dateEnd != nil`. Otherwise unused (legacy/preserved).
    var date: Date
    /// Range end. `nil` ⇒ year-only.
    var dateEnd: Date?
    /// User-picked year when in year-only mode. `nil` and ignored when `dateEnd != nil`.
    var yearOnlyYear: Int?

    var isYearOnly: Bool { dateEnd == nil }
    var isRange: Bool { dateEnd != nil }

    static func yearOnly(year: Int, anchor: Date) -> WhenValue {
        WhenValue(date: anchor, dateEnd: nil, yearOnlyYear: year)
    }
}
```

Inside `struct Project`, remove the `var datePrecision: DatePrecision = .year` line. Keep `var dateEnd: Date? = nil`. Update `Project.from(folderName:rootURL:)` to drop `datePrecision: .year` from the initializer call (just remove that argument).

- [ ] **Step 2: Update `ParsedFrontmatter`**

In `PortyMcFolio/Services/FrontmatterParser.swift`, remove `var datePrecision: DatePrecision = .year` from the `ParsedFrontmatter` struct. Keep `var dateEnd: Date? = nil`.

In `parse(_:)`, remove the `datePrecision` parsing block (the `dict["datePrecision"]` lookup). Tolerate the key's presence by simply not reading it. Keep the `dateEnd` parsing and clamp logic.

In `serialize(frontmatter:)`, remove the `if fm.datePrecision != .year { lines.append("datePrecision: \(fm.datePrecision.rawValue)") }` block. Keep the conditional `dateEnd` emission.

In the final `return ParsedFrontmatter(...)` of `parse(_:)`, drop the `datePrecision: datePrecision,` argument.

- [ ] **Step 3: Update `Project.loadReadme`**

In `PortyMcFolio/Models/Project.swift`'s `loadReadme()`, remove the `datePrecision = parsed.datePrecision` line. Keep the `dateEnd = parsed.dateEnd` assignment.

- [ ] **Step 4: Update the cache**

In `PortyMcFolio/Services/ProjectMetadataCache.swift`:

- Remove `var datePrecision: DatePrecision` from `CachedProjectMeta`. Keep `var dateEnd: Date?`.
- In `migrate()`, leave the `date_precision` column ALTER TABLE in place (idempotent, no harm to existing DBs). Stop writing the column from `upsert` — remove `meta.datePrecision.rawValue` from the bound arguments and remove `date_precision` from the INSERT column list and the ON CONFLICT excluded list. SQLite will use the column's `DEFAULT 'year'` for new inserts and leave it alone on updates; we just stop caring about it.
- In the `decode` function, drop the `precisionRaw` / `datePrecision` block. Stop reading the `date_precision` column from the SELECT lists in `loadAll()` and `load(uid:)`. Drop `datePrecision: datePrecision,` from the returned `CachedProjectMeta(...)`.

The full updated upsert SQL after this task should bind 14 parameters (was 16 — drop the precision column and its excluded reference).

- [ ] **Step 5: Update the reconciler**

In `PortyMcFolio/Services/ProjectReconciler.swift`:

- The `CachedProjectMeta(...)` builder around line 447 — remove `datePrecision: parsed.datePrecision,` from the call.
- The `static func project(from meta:root:)` factory — remove `datePrecision: meta.datePrecision,` from the `Project(...)` call.

- [ ] **Step 6: Update `EditorialCardView`**

In `PortyMcFolio/Views/EditorialCardView.swift`, the `Text(WhenFormatting.summaryString(...))` call currently passes `precision: project.datePrecision`. Remove the `precision:` argument — the new `WhenFormatting.summaryString` signature (Task 2) takes only `date`, `dateEnd`, `year`, and optional `locale`.

The complete updated call:

```swift
Text(WhenFormatting.summaryString(
    date: project.date,
    dateEnd: project.dateEnd,
    year: project.year
))
```

- [ ] **Step 7: Sweep tests for `DatePrecision` and `datePrecision:` references**

Run:

```bash
cd <repo>/.worktrees/project-when-field && grep -rn "datePrecision\|DatePrecision" PortyMcFolioTests --include='*.swift'
```

Every match must go. For each test:
- If the test specifically validates a `.month` or `.day` precision behavior, **delete** the test (those modes are removed). Examples in `FrontmatterParserTests`: `testParse_datePrecisionDay`, `testParse_malformedDatePrecision_fallsBackToYear`, `testSerialize_monthSingle_emitsPrecisionOnly`, `testSerialize_monthRange_emitsBoth` (rewrite without the precision assertion — see below), `testSerialize_dayRange_roundtripsCleanly` (delete entirely).
- If the test asserts that absent precision defaults to year (`testParse_whenAbsent_defaultsToYearPrecisionAndNilEnd`) — delete the precision assertion, keep the dateEnd nil check.
- If the test passes `datePrecision:` as an argument to `CachedProjectMeta(...)` or `WhenValue(...)`, just remove the argument.

Rewrite `testSerialize_monthRange_emitsBoth` to assert only the `dateEnd:` line (no datePrecision):

```swift
func testSerialize_range_emitsDateEnd() {
    let fm = ParsedFrontmatter(
        title: "T",
        date: makeDate(2025, 3, 1),
        dateEnd: makeDate(2025, 6, 30),
        tags: [],
        client: "C",
        status: .empty,
        body: "",
        teaser: "",
        favorites: [],
        hidden: false
    )
    let s = FrontmatterParser.serialize(frontmatter: fm)
    XCTAssertTrue(s.contains("dateEnd: 2025-06-30"))
    XCTAssertFalse(s.contains("datePrecision"))
}
```

Rewrite `testSerialize_yearPrecision_omitsBothNewFields` to drop the precision check (still verify no `dateEnd` line):

```swift
func testSerialize_yearOnly_omitsDateEnd() {
    let fm = ParsedFrontmatter(
        title: "T",
        date: makeDate(2025, 1, 1),
        dateEnd: nil,
        tags: [],
        client: "C",
        status: .empty,
        body: "",
        teaser: "",
        favorites: [],
        hidden: false
    )
    let s = FrontmatterParser.serialize(frontmatter: fm)
    XCTAssertFalse(s.contains("dateEnd"))
    XCTAssertFalse(s.contains("datePrecision"))
}
```

In `ProjectMetadataCacheTests`: rewrite the `test_upsertAndLoad_*Precision*` tests to drop `datePrecision` and just assert the `dateEnd` round-trips correctly. Delete the test that exercised `.day` precision specifically.

In `ProjectReconcilerTests` and `SearchIndexTests`: any `CachedProjectMeta(...)` call with `datePrecision:` — remove the argument.

- [ ] **Step 8: Build + run tests**

```bash
cd <repo>/.worktrees/project-when-field && xcodegen generate 2>&1 | tail -3 && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|Executed [0-9]+ tests|failed" | tail -5
```

Expected: build succeeds; full suite passes (count drops by ~6 tests since we deleted a few precision-specific tests — should be ~407 passing).

If anything outside the listed files fails to compile, fix the call sites by removing `datePrecision:` arguments.

- [ ] **Step 9: Commit**

```bash
cd <repo>/.worktrees/project-when-field && git add -A && git commit -m "refactor(when): drop DatePrecision, simplify WhenValue to year-only or range

Remove the DatePrecision enum and the .month/.day modes. The When data
is now binary: dateEnd nil means year-only; dateEnd present means range
with date as the start. WhenValue gains yearOnlyYear for the year-only
case; precision field removed.

Cache stops writing the date_precision column (the column itself stays
for safety, no migration needed). Existing project files with legacy
datePrecision: keys parse cleanly — the field is ignored.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `WhenFormatting` — three cases only

**Files:**
- Modify: `PortyMcFolio/Services/WhenFormatting.swift`
- Modify: `PortyMcFolioTests/WhenFormattingTests.swift`

- [ ] **Step 1: Rewrite the formatter**

Replace the entire `WhenFormatting` enum with this version:

```swift
import Foundation

/// Pure formatting for the project When summary used by the editorial card
/// hover overlay. Output is locale-aware (defaults to en_US_POSIX) and uses
/// em-dashes for ranges.
///
/// Three shapes:
/// - Year only — returns the bare year (e.g. "2025").
/// - Range, same year — collapses to "MMM YYYY" if start month equals end
///   month, otherwise "MMM — MMM YYYY".
/// - Range, cross-year — "MMM YYYY — MMM YYYY".
enum WhenFormatting {

    /// Produce the summary string. `year` is the canonical (folder) year and
    /// is used only when `dateEnd == nil` (year-only).
    static func summaryString(
        date: Date,
        dateEnd: Date?,
        year: Int,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> String {
        guard let end = dateEnd else {
            return String(year)
        }

        let cal = utcGregorian(locale: locale)
        let startMonth = cal.component(.month, from: date)
        let startYear = cal.component(.year, from: date)
        let endMonth = cal.component(.month, from: end)
        let endYear = cal.component(.year, from: end)

        let startStr = monthAbbrev(month: startMonth, locale: locale).uppercased()
        let endStr = monthAbbrev(month: endMonth, locale: locale).uppercased()

        if startYear == endYear {
            if startMonth == endMonth {
                return "\(startStr) \(startYear)"
            }
            return "\(startStr) — \(endStr) \(startYear)"
        }
        return "\(startStr) \(startYear) — \(endStr) \(endYear)"
    }

    private static func utcGregorian(locale: Locale) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.locale = locale
        return cal
    }

    private static func monthAbbrev(month: Int, locale: Locale) -> String {
        let df = DateFormatter()
        df.locale = locale
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "MMM"
        var comps = DateComponents()
        comps.year = 2000
        comps.month = month
        comps.day = 1
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: comps)!
        return df.string(from: date)
    }
}
```

- [ ] **Step 2: Replace the test file**

Overwrite `PortyMcFolioTests/WhenFormattingTests.swift` with:

```swift
import XCTest
@testable import PortyMcFolio

final class WhenFormattingTests: XCTestCase {

    private func makeDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func test_yearOnly_returnsYearString() {
        let s = WhenFormatting.summaryString(
            date: makeDate(2025, 1, 1),
            dateEnd: nil,
            year: 2025
        )
        XCTAssertEqual(s, "2025")
    }

    func test_range_sameYear_differentMonths() {
        let s = WhenFormatting.summaryString(
            date: makeDate(2025, 3, 1),
            dateEnd: makeDate(2025, 6, 30),
            year: 2025
        )
        XCTAssertEqual(s, "MAR — JUN 2025")
    }

    func test_range_sameYear_sameMonth_collapsesToSingleMonth() {
        let s = WhenFormatting.summaryString(
            date: makeDate(2025, 3, 1),
            dateEnd: makeDate(2025, 3, 31),
            year: 2025
        )
        XCTAssertEqual(s, "MAR 2025")
    }

    func test_range_crossYear() {
        let s = WhenFormatting.summaryString(
            date: makeDate(2024, 9, 1),
            dateEnd: makeDate(2025, 2, 28),
            year: 2025
        )
        XCTAssertEqual(s, "SEP 2024 — FEB 2025")
    }

    func test_yearOnly_ignoresDateArgument() {
        // When year-only, the start date should not influence output.
        let s = WhenFormatting.summaryString(
            date: makeDate(2030, 11, 1),  // bogus
            dateEnd: nil,
            year: 2025
        )
        XCTAssertEqual(s, "2025")
    }
}
```

- [ ] **Step 3: Build + run tests**

```bash
cd <repo>/.worktrees/project-when-field && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/WhenFormattingTests 2>&1 | grep -E "Test Suite|Executed|failed" | tail -5
```

Expected: 5 tests pass.

- [ ] **Step 4: Commit**

```bash
cd <repo>/.worktrees/project-when-field && git add PortyMcFolio/Services/WhenFormatting.swift PortyMcFolioTests/WhenFormattingTests.swift && git commit -m "refactor(when): WhenFormatting collapses to three cases

Year-only / range-same-year (with single-month collapse) / range-cross-year.
Day-precision branches removed.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `ProjectSort` — drop the precision switch

**Files:**
- Modify: `PortyMcFolio/Services/ProjectSort.swift`
- Modify: `PortyMcFolioTests/ProjectSortTests.swift`

- [ ] **Step 1: Rewrite `effectiveSortDate`**

In `PortyMcFolio/Services/ProjectSort.swift`, replace the body of `effectiveSortDate(for:)` so the year-only branch uses Jan 1 of the folder year and the range branch uses `dateEnd`:

```swift
    static func effectiveSortDate(for project: Project) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        if let end = project.dateEnd {
            return end
        }
        return calendar.date(from: DateComponents(year: project.year, month: 1, day: 1))
            ?? project.date
    }
```

`sortedWithinYear` is unchanged.

- [ ] **Step 2: Update tests**

In `PortyMcFolioTests/ProjectSortTests.swift`:

Update `makeProject` to drop the `precision: DatePrecision = .year` parameter (no longer exists). Pass only `dateEnd`. Replace the helper signature and call sites with:

```swift
    private func makeProject(
        uid: String,
        title: String,
        year: Int,
        date: Date,
        dateEnd: Date? = nil
    ) -> Project {
        Project(
            uid: uid,
            year: year,
            folderName: "\(year)_\(title.lowercased())_\(uid)",
            folderURL: URL(fileURLWithPath: "/tmp/\(uid)"),
            title: title,
            date: date,
            dateEnd: dateEnd,
            tags: [],
            client: "",
            status: .empty,
            body: "",
            teaser: "",
            favorites: []
        )
    }
```

Adjust the existing tests:
- `test_effectiveSortDate_yearPrecision_isJan1OfFolderYear` → keep, just drop the `precision: .year` arg.
- `test_effectiveSortDate_monthPrecision_isFirstOfMonth` → DELETE (month-precision concept gone).
- `test_effectiveSortDate_dayPrecision_isExactDate` → DELETE.
- `test_sortedWithinYear_explicitWhensDescend` → call sites: replace `precision: .month` with `dateEnd: makeDate(2025, X, ...)` (any month-end date). Adjust to verify the same descending behavior with explicit `dateEnd` values.
- `test_sortedWithinYear_yearOnlyProjectsFallToEnd` → call sites: drop `precision: .month` for the dated project; pass `dateEnd: makeDate(2025, 3, 31)`. Year-only projects pass no `dateEnd`.
- `test_sortedWithinYear_alphaTieBreakOnSameDate` → drop `precision: .month`; pass identical `dateEnd` values to both projects.
- `test_sortedWithinYear_dayPrecisionOrdersWithinMonth` → DELETE (day precision gone). Replace with a `test_effectiveSortDate_range_isDateEnd` test that asserts `effectiveSortDate(for:)` returns the `dateEnd` value when set:

```swift
    func test_effectiveSortDate_range_isDateEnd() {
        let p = makeProject(
            uid: "00000004", title: "P", year: 2025,
            date: makeDate(2025, 3, 1),
            dateEnd: makeDate(2025, 6, 30)
        )
        XCTAssertEqual(ProjectSort.effectiveSortDate(for: p), makeDate(2025, 6, 30))
    }
```

- [ ] **Step 3: Build + run tests**

```bash
cd <repo>/.worktrees/project-when-field && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/ProjectSortTests 2>&1 | grep -E "Test Suite|Executed|failed" | tail -5
```

Expected: 5 tests pass (was 7; we deleted 2).

- [ ] **Step 4: Commit**

```bash
cd <repo>/.worktrees/project-when-field && git add PortyMcFolio/Services/ProjectSort.swift PortyMcFolioTests/ProjectSortTests.swift && git commit -m "refactor(sort): use dateEnd directly; drop precision branches

Effective sort date is now project.dateEnd when present, else Jan 1 of the
folder year for year-only projects. The .month and .day branches go away
with DatePrecision.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `updateProjectMetadata` derives folder year from `WhenValue`

The signature changes — no more `year:` parameter. The folder year is computed from the supplied `WhenValue`. The previously-extracted `ProjectMetadataMutation.resolveYearChange` helper is replaced by a simpler `resolveFolderYear` helper.

**Files:**
- Modify: `PortyMcFolio/Services/ProjectMetadataMutation.swift`
- Modify: `PortyMcFolioTests/ProjectMetadataMutationTests.swift`
- Modify: `PortyMcFolio/App/AppState.swift`

- [ ] **Step 1: Rewrite the helper**

Replace `PortyMcFolio/Services/ProjectMetadataMutation.swift` with:

```swift
import Foundation

/// Pure helpers used by `AppState.updateProjectMetadata` to keep the
/// frontmatter consistent on metadata changes.
enum ProjectMetadataMutation {

    /// Derives the canonical folder year from a `WhenValue`.
    ///
    /// - Year-only (`dateEnd == nil`): uses the user-picked `yearOnlyYear` if
    ///   present, otherwise falls back to the supplied `currentYear` (legacy
    ///   data without a year-only year set).
    /// - Range (`dateEnd != nil`): uses the year of `dateEnd`.
    static func resolveFolderYear(
        when: WhenValue,
        currentYear: Int,
        calendar: Calendar = utcGregorian()
    ) -> Int {
        if let end = when.dateEnd {
            return calendar.component(.year, from: end)
        }
        return when.yearOnlyYear ?? currentYear
    }

    private static func utcGregorian() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }
}
```

- [ ] **Step 2: Replace the helper tests**

Replace `PortyMcFolioTests/ProjectMetadataMutationTests.swift` with:

```swift
import XCTest
@testable import PortyMcFolio

final class ProjectMetadataMutationTests: XCTestCase {

    private func makeDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func test_yearOnly_usesPickedYearOnlyYear() {
        let when = WhenValue.yearOnly(year: 2025, anchor: makeDate(2025, 1, 1))
        let derived = ProjectMetadataMutation.resolveFolderYear(when: when, currentYear: 2024)
        XCTAssertEqual(derived, 2025)
    }

    func test_yearOnly_fallsBackToCurrentYearWhenYearOnlyYearMissing() {
        let when = WhenValue(date: makeDate(2025, 1, 1), dateEnd: nil, yearOnlyYear: nil)
        let derived = ProjectMetadataMutation.resolveFolderYear(when: when, currentYear: 2030)
        XCTAssertEqual(derived, 2030)
    }

    func test_range_usesYearOfDateEnd() {
        let when = WhenValue(
            date: makeDate(2024, 9, 1),
            dateEnd: makeDate(2025, 2, 28),
            yearOnlyYear: nil
        )
        let derived = ProjectMetadataMutation.resolveFolderYear(when: when, currentYear: 2024)
        XCTAssertEqual(derived, 2025)
    }

    func test_range_dateEndOverridesYearOnlyYearIfBothSet() {
        let when = WhenValue(
            date: makeDate(2024, 9, 1),
            dateEnd: makeDate(2025, 2, 28),
            yearOnlyYear: 9999
        )
        let derived = ProjectMetadataMutation.resolveFolderYear(when: when, currentYear: 2024)
        XCTAssertEqual(derived, 2025)
    }
}
```

- [ ] **Step 3: Update `AppState.updateProjectMetadata`**

In `PortyMcFolio/App/AppState.swift`, replace the `updateProjectMetadata(...)` function. The `year:` parameter is removed; `when:` is now the source of truth for the folder year:

```swift
    func updateProjectMetadata(
        project: Project,
        title: String,
        client: String,
        status: ProjectStatus,
        tags: [String],
        teaser: String,
        hidden: Bool,
        when: WhenValue
    ) throws {
        let derivedYear = ProjectMetadataMutation.resolveFolderYear(
            when: when,
            currentYear: project.year
        )
        let newFolderName = Project.folderName(title: title, year: derivedYear, uid: project.uid)
        let willRenameFolder = newFolderName != project.folderName

        // Pre-flight: if the folder rename would collide, refuse the whole operation
        // before we mutate anything on disk.
        if willRenameFolder, let rootURL = portfolioRootURL {
            let newFolderURL = rootURL.appendingPathComponent(newFolderName)
            guard !FileManager.default.fileExists(atPath: newFolderURL.path) else {
                throw NSError(
                    domain: "com.portymcfolio.app",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "A project folder named \"\(newFolderName)\" already exists."]
                )
            }
        }

        // 1. Read and rewrite the README.
        let originalContent = try String(contentsOf: project.readmeURL, encoding: .utf8)
        var parsed = try FrontmatterParser.parse(originalContent)
        parsed.title = title
        parsed.client = client
        parsed.status = status
        parsed.tags = tags
        parsed.teaser = teaser
        parsed.hidden = hidden

        // Apply the When directly. For year-only projects we leave parsed.date
        // alone (legacy preservation). For range projects we set both anchors.
        parsed.dateEnd = when.dateEnd
        if when.dateEnd != nil {
            parsed.date = when.date
        }

        let updated = FrontmatterParser.serialize(frontmatter: parsed)
        try updated.write(to: project.readmeURL, atomically: true, encoding: .utf8)

        // Track what we've done so we can roll back on failure.
        var internalFileRenamed = false
        let oldInternalFile = project.folderURL.appendingPathComponent("\(project.folderName).md")
        let newInternalFile = project.folderURL.appendingPathComponent("\(newFolderName).md")

        do {
            // 2. Rename the internal project file (if any).
            if willRenameFolder, let rootURL = portfolioRootURL {
                if FileManager.default.fileExists(atPath: oldInternalFile.path) {
                    try FileManager.default.moveItem(at: oldInternalFile, to: newInternalFile)
                    internalFileRenamed = true
                }

                // 3. Rename the folder.
                let newFolderURL = rootURL.appendingPathComponent(newFolderName)
                try FileManager.default.moveItem(at: project.folderURL, to: newFolderURL)

                projectFolderRenamed(uid: project.uid, newFolderName: newFolderName)
            }
        } catch {
            // Rollback.
            if internalFileRenamed {
                try? FileManager.default.moveItem(at: newInternalFile, to: oldInternalFile)
            }
            try? originalContent.write(to: project.readmeURL, atomically: true, encoding: .utf8)
            throw error
        }

        // 4. Direct-poke the reconciler to sync this project immediately.
        notifyProjectFileChanged(uid: project.uid)
    }
```

- [ ] **Step 4: Update the only caller in test code**

`FrontmatterFolderRenameTests.swift` calls `appState.updateProjectMetadata(...)` with `year:`. Drop the `year:` argument from each call (the new signature derives it from `when`). The tests pass `when: WhenValue.yearOnly(anchor:)` placeholders — update to the new factory signature `WhenValue.yearOnly(year: project.year, anchor: project.date)`.

The signature change will also break `ProjectSettingsPopover.save()`. Update that call site too: drop `year: year,` (the local `year` state variable in the popover will become irrelevant once Task 6 removes the YearStepper, but for now leave the local state alone — the call simply no longer takes it).

- [ ] **Step 5: Build + run all tests**

```bash
cd <repo>/.worktrees/project-when-field && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|Executed [0-9]+ tests|failed" | tail -5
```

Expected: ~405 tests pass.

- [ ] **Step 6: Commit**

```bash
cd <repo>/.worktrees/project-when-field && git add -A && git commit -m "refactor(state): updateProjectMetadata derives folder year from When

Drop the year: parameter. The folder year is now computed from the
WhenValue: year-of-dateEnd for range projects, yearOnlyYear for
year-only projects (falling back to the project's current year if the
yearOnlyYear field isn't set). Folder rename triggers automatically
when the derived year changes.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Rewrite `WhenPicker`

The new picker has a 2-button mode toggle and explicit Start/End buttons in Range mode. Each Start/End button opens an inline month grid (year nav + 12 months). No tests (project convention).

**Files:**
- Modify: `PortyMcFolio/Views/WhenPicker.swift`

- [ ] **Step 1: Replace the file contents**

Overwrite `PortyMcFolio/Views/WhenPicker.swift` with:

```swift
import SwiftUI

/// A trigger + popover picker for setting a project's optional When.
///
/// Two modes selected via a 2-button toggle:
/// - **Year only** — a year nav (‹ YYYY ›). The folder year is the picked year.
/// - **Range** — explicit Start and End fields, each opening an inline month
///   picker. The folder year is the year-component of End.
///
/// Writes through to `Binding<WhenValue>` continuously; persistence happens
/// when the surrounding `ProjectSettingsPopover` saves.
struct WhenPicker: View {
    @Binding var value: WhenValue

    @State private var isOpen = false
    @State private var activeField: ActiveField? = nil

    @Environment(\.theme) var theme

    private enum ActiveField { case start, end }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private var displayYear: Int {
        if let end = value.dateEnd {
            return calendar.component(.year, from: end)
        }
        return value.yearOnlyYear ?? calendar.component(.year, from: Date())
    }

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            HStack(spacing: DT.Spacing.sm) {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.colors.textTertiary)
                Text(triggerLabel)
                    .font(DT.Typography.body)
                    .foregroundStyle(value.isYearOnly ? theme.colors.textTertiary : theme.colors.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .padding(.horizontal, DT.Spacing.md)
            .padding(.vertical, DT.Spacing.sm)
            .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: DT.Radius.small))
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.small)
                    .stroke(theme.colors.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .top) {
            popoverBody
                .frame(width: 320)
                .padding(DT.Spacing.md)
                .background(theme.colors.surface)
        }
    }

    private var triggerLabel: String {
        WhenFormatting.summaryString(
            date: value.date,
            dateEnd: value.dateEnd,
            year: displayYear
        )
    }

    @ViewBuilder
    private var popoverBody: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.md) {
            modeToggle
            if value.isYearOnly {
                yearOnlyBody
            } else {
                rangeBody
            }
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 4) {
            modeButton(title: "Year only", isActive: value.isYearOnly) {
                guard !value.isYearOnly else { return }
                let yr = calendar.component(.year, from: value.dateEnd ?? value.date)
                value = WhenValue.yearOnly(year: yr, anchor: value.date)
                activeField = nil
            }
            modeButton(title: "Range", isActive: value.isRange) {
                guard !value.isRange else { return }
                // Bootstrap a range from the current year-only year.
                let yr = value.yearOnlyYear ?? calendar.component(.year, from: Date())
                let start = calendar.date(from: DateComponents(year: yr, month: 1, day: 1))!
                let end = lastDay(of: 1, year: yr)
                value = WhenValue(date: start, dateEnd: end, yearOnlyYear: nil)
                activeField = .end
            }
        }
        .padding(3)
        .background(theme.colors.backgroundAlt, in: RoundedRectangle(cornerRadius: DT.Radius.small))
    }

    private func modeButton(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DT.Typography.caption)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(isActive ? Color.white : theme.colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DT.Spacing.xs)
                .background(
                    isActive ? theme.colors.accent : Color.clear,
                    in: RoundedRectangle(cornerRadius: DT.Radius.small - 2)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Year-only body

    private var yearOnlyBody: some View {
        VStack(spacing: DT.Spacing.md) {
            HStack {
                Button { stepYearOnlyYear(by: -1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .medium))
                }
                .iconButton()
                Spacer()
                Text(String(displayYear))
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer()
                Button { stepYearOnlyYear(by: 1) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium))
                }
                .iconButton()
            }
            .padding(.horizontal, DT.Spacing.sm)
            .padding(.vertical, DT.Spacing.xs)
            .background(theme.colors.backgroundAlt, in: RoundedRectangle(cornerRadius: DT.Radius.small))

            Text("Project filed under \(String(displayYear)).")
                .font(DT.Typography.caption)
                .foregroundStyle(theme.colors.textTertiary)
                .frame(maxWidth: .infinity)
        }
    }

    private func stepYearOnlyYear(by delta: Int) {
        let yr = (value.yearOnlyYear ?? calendar.component(.year, from: Date())) + delta
        value = WhenValue.yearOnly(year: yr, anchor: value.date)
    }

    // MARK: - Range body

    private var rangeBody: some View {
        VStack(spacing: DT.Spacing.sm) {
            rangeFieldRow(label: "Start", date: value.date, field: .start)
            rangeFieldRow(label: "End", date: value.dateEnd ?? value.date, field: .end)

            if let active = activeField {
                inlineMonthPicker(for: active)
            }

            HStack(spacing: DT.Spacing.sm) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.colors.accent)
                Text("Filed under \(filedUnderYear) (year of End)")
                    .font(DT.Typography.caption)
                    .foregroundStyle(theme.colors.accent)
                Spacer()
            }
            .padding(.horizontal, DT.Spacing.sm)
            .padding(.vertical, DT.Spacing.xs)
            .background(theme.colors.accent.opacity(DT.Opacity.selection), in: RoundedRectangle(cornerRadius: DT.Radius.small))
        }
    }

    private var filedUnderYear: String {
        if let end = value.dateEnd {
            return String(calendar.component(.year, from: end))
        }
        return String(displayYear)
    }

    private func rangeFieldRow(label: String, date: Date, field: ActiveField) -> some View {
        HStack(spacing: DT.Spacing.md) {
            Text(label.uppercased())
                .font(DT.Typography.micro)
                .foregroundStyle(theme.colors.textSecondary)
                .tracking(1.2)
                .frame(width: 44, alignment: .leading)
            Button {
                activeField = (activeField == field) ? nil : field
            } label: {
                HStack {
                    Text(formatMonthYear(date))
                        .font(DT.Typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(theme.colors.textTertiary)
                }
                .padding(.horizontal, DT.Spacing.sm)
                .padding(.vertical, DT.Spacing.xs)
                .background(theme.colors.backgroundAlt, in: RoundedRectangle(cornerRadius: DT.Radius.small))
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.small)
                        .stroke(activeField == field ? theme.colors.accent : Color.clear, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func inlineMonthPicker(for field: ActiveField) -> some View {
        let date = (field == .start) ? value.date : (value.dateEnd ?? value.date)
        let visibleYear = calendar.component(.year, from: date)
        let visibleMonth = calendar.component(.month, from: date)

        return VStack(spacing: DT.Spacing.xs) {
            HStack {
                Button {
                    shiftField(field, byYears: -1)
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .medium))
                }
                .iconButton()
                Spacer()
                Text(String(visibleYear))
                    .font(DT.Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer()
                Button {
                    shiftField(field, byYears: 1)
                } label: {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium))
                }
                .iconButton()
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 4)
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(1...12, id: \.self) { month in
                    Button {
                        setField(field, month: month, year: visibleYear)
                    } label: {
                        Text(monthAbbrev(month))
                            .font(DT.Typography.caption)
                            .fontWeight(month == visibleMonth ? .semibold : .regular)
                            .foregroundStyle(month == visibleMonth ? Color.white : theme.colors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DT.Spacing.xs)
                            .background(
                                month == visibleMonth ? theme.colors.accent : Color.clear,
                                in: RoundedRectangle(cornerRadius: DT.Radius.small)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(DT.Spacing.sm)
        .background(theme.colors.backgroundAlt, in: RoundedRectangle(cornerRadius: DT.Radius.small))
    }

    private func shiftField(_ field: ActiveField, byYears delta: Int) {
        switch field {
        case .start:
            let yr = calendar.component(.year, from: value.date) + delta
            let m = calendar.component(.month, from: value.date)
            if let newStart = calendar.date(from: DateComponents(year: yr, month: m, day: 1)) {
                value.date = newStart
            }
        case .end:
            let baseEnd = value.dateEnd ?? value.date
            let yr = calendar.component(.year, from: baseEnd) + delta
            let m = calendar.component(.month, from: baseEnd)
            value.dateEnd = lastDay(of: m, year: yr)
        }
    }

    private func setField(_ field: ActiveField, month: Int, year: Int) {
        switch field {
        case .start:
            if let newStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)) {
                value.date = newStart
                // If the new start is after the current end, push end forward.
                if let end = value.dateEnd, newStart > end {
                    value.dateEnd = lastDay(of: month, year: year)
                }
            }
        case .end:
            let newEnd = lastDay(of: month, year: year)
            value.dateEnd = newEnd
            // If the new end is before the current start, pull start back.
            if newEnd < value.date {
                value.date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? value.date
            }
        }
    }

    private func lastDay(of month: Int, year: Int) -> Date {
        let cal = calendar
        let firstOfNext = cal.date(from: DateComponents(year: year, month: month + 1, day: 1))!
        return cal.date(byAdding: .day, value: -1, to: firstOfNext)!
    }

    private func monthAbbrev(_ month: Int) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "MMM"
        let date = calendar.date(from: DateComponents(year: 2000, month: month, day: 1))!
        return df.string(from: date)
    }

    private func formatMonthYear(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "MMM yyyy"
        return df.string(from: date).uppercased()
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd <repo>/.worktrees/project-when-field && xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -configuration Debug build 2>&1 | grep -E "error:|BUILD" | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
cd <repo>/.worktrees/project-when-field && git add PortyMcFolio/Views/WhenPicker.swift && git commit -m "refactor(views): WhenPicker rewritten — two modes, explicit Start/End

Two-button mode toggle (Year only / Range). Year-only mode shows a year
nav stepper. Range mode shows two explicit Start/End fields, each
opening an inline month picker on tap. Folder year is derived from the
End in Range mode and auto-updates the trigger label.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Drop the YearStepper from `ProjectSettingsPopover`

**Files:**
- Modify: `PortyMcFolio/Views/ProjectSettingsPopover.swift`

- [ ] **Step 1: Remove the YearStepper field and the related state**

In `PortyMcFolio/Views/ProjectSettingsPopover.swift`:

- Delete the `@State private var year: Int = 2026` line.
- In the body, find and delete the entire `settingsField("Year") { YearStepper(year: $year) }` block. The When picker (already present from Task 9 of Rev 1) becomes the year control.
- Also delete the inline note block that begins with `if when.precision != .year { Text("Changing year won't shift your When range.") ... }` — this rendered immediately after the `WhenPicker` and is no longer relevant. (The `when.precision` reference would also fail to compile after Task 1 anyway.)
- In `.onAppear`, delete the `year = project.year` line.
- In the `WhenPicker` initializer, remove the `projectYear: year` argument — the picker no longer needs it (it derives `displayYear` from its own state).

The `WhenPicker(value: $when, projectYear: year)` becomes simply:

```swift
WhenPicker(value: $when)
```

- Update the `.onAppear` hydration of `when` to bootstrap `yearOnlyYear` from `project.year` for projects that load without an explicit range:

```swift
when = WhenValue(
    date: project.date,
    dateEnd: project.dateEnd,
    yearOnlyYear: project.dateEnd == nil ? project.year : nil
)
```

- In `save()`, the call to `appState.updateProjectMetadata(...)` must drop the `year:` argument (Task 4 already removed it from the function signature). Update:

```swift
            try appState.updateProjectMetadata(
                project: project,
                title: trimmedTitle,
                client: clients.joined(separator: ", "),
                status: status,
                tags: tags,
                teaser: teaser,
                hidden: hidden,
                when: when
            )
```

- [ ] **Step 2: Build + run all tests**

```bash
cd <repo>/.worktrees/project-when-field && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|Executed [0-9]+ tests|failed" | tail -5
```

Expected: build succeeds; tests pass.

- [ ] **Step 3: Commit**

```bash
cd <repo>/.worktrees/project-when-field && git add PortyMcFolio/Views/ProjectSettingsPopover.swift && git commit -m "refactor(views): drop YearStepper from settings; year flows from When

The When picker now owns year. Year-only projects step year via the
picker's built-in year nav; range projects derive the year from the End
field. The 'Changing year won't shift your When range' note is gone —
it's no longer possible.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Final sweep + manual smoke

- [ ] **Step 1: Full unit test suite + Release build**

```bash
cd <repo>/.worktrees/project-when-field && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|Executed [0-9]+ tests|failed" | tail -3 && xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -configuration Release build 2>&1 | grep -E "error:|BUILD" | tail -3
```

Expected: Test Suite 'All tests' passed; BUILD SUCCEEDED.

- [ ] **Step 2: Refresh the dist app**

```bash
cd <repo>/.worktrees/project-when-field && rm -rf <repo>/dist/PortyMcFolio-when-field.app && cp -R <DerivedData>/PortyMcFolio/Build/Products/Release/PortyMcFolio.app <repo>/dist/PortyMcFolio-when-field.app && open <repo>/dist/PortyMcFolio-when-field.app && echo "Refreshed"
```

- [ ] **Step 3: Manual smoke checklist**

Verify by interacting with the running app:

1. **Existing year-only projects** — Settings sheet shows the When picker labeled `2025` (muted). No YearStepper. No "Changing year won't shift" note. The picker opens to Year-only mode by default.
2. **Switch to Range mode** — toggle clicks; UI shows Start/End fields with a sane bootstrap (e.g. Jan–Jan of current year). The accent "Filed under … (year of End)" pill appears.
3. **Pick End = Mar 2025** — End label updates to "MAR 2025"; trigger label collapses to "MAR 2025" if start month equals end month, otherwise shows the range.
4. **Pick End = Feb 2026 (cross-year)** — trigger shows "JAN 2025 — FEB 2026" (or whatever Start is). The "Filed under" pill shows 2026.
5. **Save** — the project moves to the 2026 band on the overview. Reopen the project's settings; the When persists.
6. **Switch back to Year-only** — toggle clears the range. The picker shows the year nav. Save → the project reverts to Year-only behavior.
7. **Hover overlay on the overview** — shows the formatted summary string (year alone, range, or cross-year).
8. **Sort** — within a year band, range projects descend by End; year-only fall to the bottom alphabetically.
9. **Folder rename** — verify the project's on-disk folder name updated when the End year changed (check Finder or `ls` the portfolio root).

If everything passes, this task is done. If you find a bug, fix it inline and commit before considering the plan complete.

- [ ] **Step 4: Final tidy commit (only if any inline fixes were made)**

If smoke testing surfaced fixes, commit them:

```bash
cd <repo>/.worktrees/project-when-field && git status
```

If the working tree is clean, you're done. Otherwise commit any small tidy fixes with a `fix(...)` message.
