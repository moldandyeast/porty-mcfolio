# Project "When" Field Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional, precision-aware date or date-range to each project so projects sort meaningfully within a year band, without disturbing year semantics.

**Architecture:** Three optional frontmatter keys (`date` reused as start anchor, new `dateEnd` and `datePrecision`). Pure formatting and sort helpers under `Services/`. New `WhenPicker` SwiftUI control rendered inside `ProjectSettingsPopover`. `EditorialCardView` hover overlay reads the formatted summary. `AppState.updateProjectMetadata` learns a precision-aware year-sync rule.

**Tech Stack:** Swift 5.9, SwiftUI (macOS 15+), Yams (YAML), GRDB (untouched), XCTest. Spec at `docs/superpowers/specs/2026-04-27-project-when-field-design.md`.

**Project conventions:**
- No SwiftUI view tests (`PortyMcFolioTests/` only contains model/service/state tests). View changes are smoke-tested by running the app.
- xcodegen owns the project; new files require `xcodegen generate` before `xcodebuild`.
- Commit style: `type(scope): summary` (e.g. `feat(model)`, `feat(parser)`, `feat(sort)`).

**Intentional deviation from the spec — day-level refinement UI is stubbed.** The spec describes a `Be specific…` panel that lets the user tighten a chosen month range to exact start/end days. This plan implements the full data model, parser, formatter, and sort for `.day` precision, but the picker UI in this iteration only writes `.month` precision through the popover. Day-precision projects loaded from external edits will display correctly via `WhenFormatting`. A short follow-up plan can extend `WhenPicker` with a day-grid panel without touching anything else. This keeps the diff focused and ships the higher-leverage work (in-year sort, hover summary) in one cycle.

---

## Task 1: Add `DatePrecision`, `WhenValue`, and Project/ParsedFrontmatter properties

Add the new types and storage. No behavior change yet — this task gets the codebase compiling with the new shape so subsequent tasks can target it.

**Files:**
- Modify: `PortyMcFolio/Models/Project.swift`
- Modify: `PortyMcFolio/Services/FrontmatterParser.swift`

- [ ] **Step 1: Add `DatePrecision` enum and `WhenValue` struct in `Project.swift`**

Insert the two type declarations near the top of `PortyMcFolio/Models/Project.swift`, right after the `ProjectError` enum and before `struct Project`:

```swift
/// Granularity of the optional "When" date on a project.
/// `year` (default) means no specific date — only the folder year matters.
enum DatePrecision: String, Codable, CaseIterable {
    case year, month, day
}

/// Transport struct for the When metadata. Used as a binding for `WhenPicker`
/// and as a parameter group on `AppState.updateProjectMetadata`.
struct WhenValue: Equatable {
    var date: Date
    var dateEnd: Date?
    var precision: DatePrecision

    static func yearOnly(anchor: Date) -> WhenValue {
        WhenValue(date: anchor, dateEnd: nil, precision: .year)
    }
}
```

- [ ] **Step 2: Add `dateEnd` and `datePrecision` properties on `Project`**

In `PortyMcFolio/Models/Project.swift`, inside `struct Project`, add the two new stored properties after the existing `date` property and before `tags`:

```swift
    var date: Date
    var dateEnd: Date? = nil
    var datePrecision: DatePrecision = .year
    var tags: [String]
```

Update `Project.from(folderName:rootURL:)` so the constructed `Project` initializer also sets the new fields explicitly to their defaults (so the call site is self-describing — Swift would default them anyway):

```swift
        return Project(
            uid: uid,
            year: year,
            folderName: folderName,
            folderURL: folderURL,
            title: "",
            date: Date(),
            dateEnd: nil,
            datePrecision: .year,
            tags: [],
            client: "",
            status: .empty,
            body: "",
            teaser: "",
            favorites: []
        )
```

- [ ] **Step 3: Add the same fields to `ParsedFrontmatter`**

In `PortyMcFolio/Services/FrontmatterParser.swift`, modify the `ParsedFrontmatter` struct at the top of the file:

```swift
struct ParsedFrontmatter {
    var title: String
    var date: Date
    var dateEnd: Date? = nil
    var datePrecision: DatePrecision = .year
    var tags: [String]
    var client: String
    var status: ProjectStatus
    var body: String
    var teaser: String
    var favorites: [String] = []
    var hidden: Bool = false
}
```

The parser is not yet reading these fields — this task only adds storage. Existing tests still pass because the new fields have defaults.

- [ ] **Step 4: Build to verify the codebase still compiles**

Run:

```bash
cd <repo> && xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -configuration Debug build 2>&1 | grep -E "error:|BUILD" | tail -5
```

Expected: `** BUILD SUCCEEDED **` with no errors. (Pre-existing Sendable/deprecation warnings are fine.)

- [ ] **Step 5: Commit**

```bash
cd <repo> && git add PortyMcFolio/Models/Project.swift PortyMcFolio/Services/FrontmatterParser.swift && git commit -m "feat(model): add DatePrecision, WhenValue, and Project When fields

Add optional dateEnd and datePrecision to Project and ParsedFrontmatter,
plus a WhenValue transport struct. No parser/serializer behavior change
yet — types only.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Frontmatter parser reads `dateEnd` and `datePrecision`

Make the YAML parser populate the two new optional fields. Validate `dateEnd >= date` and clamp on violation. TDD.

**Files:**
- Modify: `PortyMcFolio/Services/FrontmatterParser.swift`
- Modify: `PortyMcFolioTests/FrontmatterParserTests.swift`

- [ ] **Step 1: Write failing tests for the new parsing**

Append the following tests to `PortyMcFolioTests/FrontmatterParserTests.swift`, just before the closing `}` of the test class:

```swift
    // MARK: - When field parsing

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testParse_whenAbsent_defaultsToYearPrecisionAndNilEnd() throws {
        let result = try FrontmatterParser.parse(sampleMarkdown)
        XCTAssertEqual(result.datePrecision, .year)
        XCTAssertNil(result.dateEnd)
    }

    func testParse_dateEndPresent_isReadAsDate() throws {
        let md = """
        ---
        title: "T"
        date: 2025-03-01
        dateEnd: 2025-06-30
        datePrecision: month
        tags: []
        client: "C"
        status: empty
        ---
        """
        let result = try FrontmatterParser.parse(md)
        XCTAssertEqual(result.datePrecision, .month)
        XCTAssertEqual(result.dateEnd, makeDate(2025, 6, 30))
    }

    func testParse_datePrecisionDay() throws {
        let md = """
        ---
        title: "T"
        date: 2025-03-15
        datePrecision: day
        tags: []
        client: "C"
        status: empty
        ---
        """
        let result = try FrontmatterParser.parse(md)
        XCTAssertEqual(result.datePrecision, .day)
        XCTAssertNil(result.dateEnd)
    }

    func testParse_malformedDatePrecision_fallsBackToYear() throws {
        let md = """
        ---
        title: "T"
        date: 2025-03-15
        datePrecision: weekly
        tags: []
        client: "C"
        status: empty
        ---
        """
        let result = try FrontmatterParser.parse(md)
        XCTAssertEqual(result.datePrecision, .year)
    }

    func testParse_dateEndBeforeDate_isClampedToDate() throws {
        let md = """
        ---
        title: "T"
        date: 2025-06-01
        dateEnd: 2025-03-01
        datePrecision: month
        tags: []
        client: "C"
        status: empty
        ---
        """
        let result = try FrontmatterParser.parse(md)
        XCTAssertEqual(result.dateEnd, makeDate(2025, 6, 1))
    }
```

- [ ] **Step 2: Run the new tests, confirm they fail**

Run:

```bash
cd <repo> && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/FrontmatterParserTests 2>&1 | grep -E "Test Case|failed|passed" | tail -20
```

Expected: the four new tests (`testParse_dateEndPresent_*`, `testParse_datePrecisionDay`, `testParse_malformedDatePrecision_*`, `testParse_dateEndBeforeDate_*`) fail. `testParse_whenAbsent_defaultsTo*` may pass already because of the field defaults.

- [ ] **Step 3: Implement the parsing**

In `PortyMcFolio/Services/FrontmatterParser.swift`, inside `parse(_:)`, after the existing date-parsing block (around the `let teaser = ...` line) and before the `let teaser = ...` assignment, insert the dateEnd + datePrecision parsing:

```swift
        // Parse dateEnd (optional)
        let dateEndRaw: Date?
        if let s = dict["dateEnd"] as? String {
            dateEndRaw = parseDate(s)
        } else if let d = dict["dateEnd"] as? Date {
            dateEndRaw = d
        } else {
            dateEndRaw = nil
        }

        // Parse datePrecision (optional, defaults to .year)
        let precisionRaw = dict["datePrecision"] as? String ?? "year"
        let datePrecision = DatePrecision(rawValue: precisionRaw) ?? .year

        // Clamp dateEnd to >= date so downstream code can rely on the invariant.
        let dateEnd: Date?
        if let end = dateEndRaw, end < date {
            AppLogger.frontmatter.warning("dateEnd before date — clamping to date")
            dateEnd = date
        } else {
            dateEnd = dateEndRaw
        }
```

Then update the final `return ParsedFrontmatter(...)` call at the bottom of `parse(_:)` so it also passes the new values:

```swift
        return ParsedFrontmatter(
            title: title,
            date: date,
            dateEnd: dateEnd,
            datePrecision: datePrecision,
            tags: tags,
            client: client,
            status: status,
            body: body,
            teaser: teaser,
            favorites: favorites,
            hidden: hidden
        )
```

- [ ] **Step 4: Run tests, confirm they pass**

```bash
cd <repo> && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/FrontmatterParserTests 2>&1 | grep -E "Test Suite.*FrontmatterParserTests|failed|passed" | tail -5
```

Expected: all FrontmatterParserTests pass.

- [ ] **Step 5: Commit**

```bash
cd <repo> && git add PortyMcFolio/Services/FrontmatterParser.swift PortyMcFolioTests/FrontmatterParserTests.swift && git commit -m "feat(parser): read dateEnd and datePrecision from frontmatter

Parse optional dateEnd (Date) and datePrecision (year|month|day) from the
YAML frontmatter. Absent datePrecision defaults to .year. Malformed values
fall back to .year. dateEnd < date is clamped and logged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Frontmatter serializer emits `dateEnd` and `datePrecision`

Round-trip the new fields. TDD.

**Files:**
- Modify: `PortyMcFolio/Services/FrontmatterParser.swift`
- Modify: `PortyMcFolioTests/FrontmatterParserTests.swift`

- [ ] **Step 1: Write failing serializer tests**

Append to `PortyMcFolioTests/FrontmatterParserTests.swift` (inside the test class, after the parsing tests added in Task 2):

```swift
    // MARK: - When field serialization

    func testSerialize_yearPrecision_omitsBothNewFields() {
        let fm = ParsedFrontmatter(
            title: "T",
            date: makeDate(2025, 1, 1),
            dateEnd: nil,
            datePrecision: .year,
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

    func testSerialize_monthSingle_emitsPrecisionOnly() {
        let fm = ParsedFrontmatter(
            title: "T",
            date: makeDate(2025, 3, 1),
            dateEnd: nil,
            datePrecision: .month,
            tags: [],
            client: "C",
            status: .empty,
            body: "",
            teaser: "",
            favorites: [],
            hidden: false
        )
        let s = FrontmatterParser.serialize(frontmatter: fm)
        XCTAssertTrue(s.contains("datePrecision: month"))
        XCTAssertFalse(s.contains("dateEnd"))
    }

    func testSerialize_monthRange_emitsBoth() {
        let fm = ParsedFrontmatter(
            title: "T",
            date: makeDate(2025, 3, 1),
            dateEnd: makeDate(2025, 6, 30),
            datePrecision: .month,
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
        XCTAssertTrue(s.contains("datePrecision: month"))
    }

    func testSerialize_dayRange_roundtripsCleanly() throws {
        let fm = ParsedFrontmatter(
            title: "T",
            date: makeDate(2025, 3, 15),
            dateEnd: makeDate(2025, 4, 2),
            datePrecision: .day,
            tags: [],
            client: "C",
            status: .empty,
            body: "Body",
            teaser: "",
            favorites: [],
            hidden: false
        )
        let s = FrontmatterParser.serialize(frontmatter: fm)
        let reparsed = try FrontmatterParser.parse(s)
        XCTAssertEqual(reparsed.date, fm.date)
        XCTAssertEqual(reparsed.dateEnd, fm.dateEnd)
        XCTAssertEqual(reparsed.datePrecision, fm.datePrecision)
    }
```

- [ ] **Step 2: Run tests, confirm the new serializer tests fail**

```bash
cd <repo> && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/FrontmatterParserTests 2>&1 | grep -E "testSerialize_(month|day|year)|failed" | tail -10
```

Expected: the four new serializer tests fail (output won't contain `datePrecision`).

- [ ] **Step 3: Implement serializer additions**

In `PortyMcFolio/Services/FrontmatterParser.swift`, inside `serialize(frontmatter:)`, modify the section that builds `lines`. After the existing `if !fm.teaser.isEmpty { ... }` block and before the `if !fm.favorites.isEmpty { ... }` block, insert:

```swift
        if let dateEnd = fm.dateEnd {
            let endString = dateFormatter.string(from: dateEnd)
            lines.append("dateEnd: \(endString)")
        }
        if fm.datePrecision != .year {
            lines.append("datePrecision: \(fm.datePrecision.rawValue)")
        }
```

- [ ] **Step 4: Run tests, confirm pass**

```bash
cd <repo> && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/FrontmatterParserTests 2>&1 | grep -E "Test Suite.*FrontmatterParserTests|failed" | tail -5
```

Expected: all FrontmatterParserTests pass; no "failed" lines.

- [ ] **Step 5: Commit**

```bash
cd <repo> && git add PortyMcFolio/Services/FrontmatterParser.swift PortyMcFolioTests/FrontmatterParserTests.swift && git commit -m "feat(parser): serialize dateEnd and datePrecision

Round-trip the new When fields. dateEnd is emitted only when present;
datePrecision is emitted only when not the default (.year), keeping
legacy frontmatter clean.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `Project.loadReadme` reads the new fields into the model

The parser is now populating `ParsedFrontmatter.dateEnd` and `.datePrecision`; `Project.loadReadme()` needs to copy them onto the project.

**Files:**
- Modify: `PortyMcFolio/Models/Project.swift`

- [ ] **Step 1: Update `loadReadme()`**

In `PortyMcFolio/Models/Project.swift`, modify `mutating func loadReadme()` to assign the new fields:

```swift
    mutating func loadReadme() throws {
        let content = try String(contentsOf: readmeURL, encoding: .utf8)
        let parsed = try FrontmatterParser.parse(content)
        title = parsed.title
        date = parsed.date
        dateEnd = parsed.dateEnd
        datePrecision = parsed.datePrecision
        tags = parsed.tags
        client = parsed.client
        status = parsed.status
        body = parsed.body
        teaser = parsed.teaser
        favorites = parsed.favorites
        hidden = parsed.hidden
    }
```

- [ ] **Step 2: Build to verify**

```bash
cd <repo> && xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -configuration Debug build 2>&1 | grep -E "error:|BUILD" | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd <repo> && git add PortyMcFolio/Models/Project.swift && git commit -m "feat(model): Project.loadReadme reads When fields

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: `WhenFormatting` helper for the hover-overlay summary

Pure formatting. Covers every row in the spec's display table. TDD.

**Files:**
- Create: `PortyMcFolio/Services/WhenFormatting.swift`
- Create: `PortyMcFolioTests/WhenFormattingTests.swift`

- [ ] **Step 1: Write failing tests**

Create `PortyMcFolioTests/WhenFormattingTests.swift`:

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
            precision: .year,
            year: 2025
        )
        XCTAssertEqual(s, "2025")
    }

    func test_singleMonth_returnsMonthYearUppercase() {
        let s = WhenFormatting.summaryString(
            date: makeDate(2025, 3, 1),
            dateEnd: nil,
            precision: .month,
            year: 2025
        )
        XCTAssertEqual(s, "MAR 2025")
    }

    func test_monthRange_sameYear() {
        let s = WhenFormatting.summaryString(
            date: makeDate(2025, 3, 1),
            dateEnd: makeDate(2025, 6, 30),
            precision: .month,
            year: 2025
        )
        XCTAssertEqual(s, "MAR — JUN 2025")
    }

    func test_monthRange_crossYear() {
        let s = WhenFormatting.summaryString(
            date: makeDate(2024, 9, 1),
            dateEnd: makeDate(2025, 2, 28),
            precision: .month,
            year: 2025
        )
        XCTAssertEqual(s, "SEP 2024 — FEB 2025")
    }

    func test_singleDay_returnsMonthDayYear() {
        let s = WhenFormatting.summaryString(
            date: makeDate(2025, 3, 15),
            dateEnd: nil,
            precision: .day,
            year: 2025
        )
        XCTAssertEqual(s, "MAR 15, 2025")
    }

    func test_dayRange_sameMonth() {
        let s = WhenFormatting.summaryString(
            date: makeDate(2025, 3, 15),
            dateEnd: makeDate(2025, 3, 22),
            precision: .day,
            year: 2025
        )
        XCTAssertEqual(s, "MAR 15 — 22, 2025")
    }

    func test_dayRange_differentMonths_sameYear() {
        let s = WhenFormatting.summaryString(
            date: makeDate(2025, 3, 15),
            dateEnd: makeDate(2025, 4, 2),
            precision: .day,
            year: 2025
        )
        XCTAssertEqual(s, "MAR 15 — APR 2, 2025")
    }

    func test_dayRange_crossYear() {
        let s = WhenFormatting.summaryString(
            date: makeDate(2024, 12, 28),
            dateEnd: makeDate(2025, 1, 5),
            precision: .day,
            year: 2025
        )
        XCTAssertEqual(s, "DEC 28, 2024 — JAN 5, 2025")
    }

    func test_monthRange_collapsesToSingleMonth_whenStartEqualsEnd() {
        let s = WhenFormatting.summaryString(
            date: makeDate(2025, 3, 1),
            dateEnd: makeDate(2025, 3, 31),
            precision: .month,
            year: 2025
        )
        XCTAssertEqual(s, "MAR 2025")
    }

    func test_dayRange_collapsesToSingleDay_whenStartEqualsEnd() {
        let s = WhenFormatting.summaryString(
            date: makeDate(2025, 3, 15),
            dateEnd: makeDate(2025, 3, 15),
            precision: .day,
            year: 2025
        )
        XCTAssertEqual(s, "MAR 15, 2025")
    }
}
```

- [ ] **Step 2: Create the helper file**

Create `PortyMcFolio/Services/WhenFormatting.swift`:

```swift
import Foundation

/// Pure formatting for the project When summary used by the editorial card
/// hover overlay. Output is locale-aware (defaults to en_US_POSIX), uppercase,
/// and uses em-dashes for ranges to match the editorial typographic voice.
enum WhenFormatting {

    /// Produce the human-readable summary string for a project's When.
    /// Year is the canonical (folder) year — only used when `precision == .year`.
    static func summaryString(
        date: Date,
        dateEnd: Date?,
        precision: DatePrecision,
        year: Int,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> String {
        switch precision {
        case .year:
            return String(year)
        case .month:
            return monthSummary(date: date, dateEnd: dateEnd, locale: locale)
        case .day:
            return daySummary(date: date, dateEnd: dateEnd, locale: locale)
        }
    }

    // MARK: - Month-precision

    private static func monthSummary(date: Date, dateEnd: Date?, locale: Locale) -> String {
        let cal = utcGregorian(locale: locale)
        let startMonth = cal.component(.month, from: date)
        let startYear = cal.component(.year, from: date)
        let startStr = monthAbbrev(month: startMonth, locale: locale).uppercased()

        guard let end = dateEnd else {
            return "\(startStr) \(startYear)"
        }

        let endMonth = cal.component(.month, from: end)
        let endYear = cal.component(.year, from: end)
        let endStr = monthAbbrev(month: endMonth, locale: locale).uppercased()

        if startYear == endYear {
            if startMonth == endMonth {
                return "\(startStr) \(startYear)"
            }
            return "\(startStr) — \(endStr) \(startYear)"
        }
        return "\(startStr) \(startYear) — \(endStr) \(endYear)"
    }

    // MARK: - Day-precision

    private static func daySummary(date: Date, dateEnd: Date?, locale: Locale) -> String {
        let cal = utcGregorian(locale: locale)
        let startMonth = cal.component(.month, from: date)
        let startDay = cal.component(.day, from: date)
        let startYear = cal.component(.year, from: date)
        let startMonthStr = monthAbbrev(month: startMonth, locale: locale).uppercased()

        guard let end = dateEnd else {
            return "\(startMonthStr) \(startDay), \(startYear)"
        }

        let endMonth = cal.component(.month, from: end)
        let endDay = cal.component(.day, from: end)
        let endYear = cal.component(.year, from: end)
        let endMonthStr = monthAbbrev(month: endMonth, locale: locale).uppercased()

        if startYear == endYear && startMonth == endMonth {
            if startDay == endDay {
                return "\(startMonthStr) \(startDay), \(startYear)"
            }
            return "\(startMonthStr) \(startDay) — \(endDay), \(startYear)"
        }
        if startYear == endYear {
            return "\(startMonthStr) \(startDay) — \(endMonthStr) \(endDay), \(startYear)"
        }
        return "\(startMonthStr) \(startDay), \(startYear) — \(endMonthStr) \(endDay), \(endYear)"
    }

    // MARK: - Helpers

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
        let cal = Calendar(identifier: .gregorian)
        let date = cal.date(from: comps)!
        return df.string(from: date)
    }
}
```

- [ ] **Step 3: Regenerate the Xcode project to pick up the new files**

```bash
cd <repo> && xcodegen generate 2>&1 | tail -3
```

- [ ] **Step 4: Run the new tests**

```bash
cd <repo> && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/WhenFormattingTests 2>&1 | grep -E "Test Suite.*WhenFormattingTests|failed|passed" | tail -5
```

Expected: all 10 WhenFormattingTests pass.

- [ ] **Step 5: Commit**

```bash
cd <repo> && git add PortyMcFolio.xcodeproj/project.pbxproj PortyMcFolio/Services/WhenFormatting.swift PortyMcFolioTests/WhenFormattingTests.swift && git commit -m "feat(services): WhenFormatting summary helper

Pure formatter for the When summary string used by the editorial card
hover overlay. Handles every precision/range combination including
cross-year ranges. Locale-aware, defaults to en_US_POSIX. Tested.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: `ProjectSort` within-year comparator

Pure helper that orders projects within a year band. Year-only projects fall at the end via a deterministic effective-sort-date. TDD.

**Files:**
- Create: `PortyMcFolio/Services/ProjectSort.swift`
- Create: `PortyMcFolioTests/ProjectSortTests.swift`

- [ ] **Step 1: Write failing tests**

Create `PortyMcFolioTests/ProjectSortTests.swift`:

```swift
import XCTest
@testable import PortyMcFolio

final class ProjectSortTests: XCTestCase {

    private func makeDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func makeProject(
        uid: String,
        title: String,
        year: Int,
        date: Date,
        dateEnd: Date? = nil,
        precision: DatePrecision = .year
    ) -> Project {
        Project(
            uid: uid,
            year: year,
            folderName: "\(year)_\(title.lowercased())_\(uid)",
            folderURL: URL(fileURLWithPath: "/tmp/\(uid)"),
            title: title,
            date: date,
            dateEnd: dateEnd,
            datePrecision: precision,
            tags: [],
            client: "",
            status: .empty,
            body: "",
            teaser: "",
            favorites: []
        )
    }

    func test_effectiveSortDate_yearPrecision_isJan1OfFolderYear() {
        // Folder year 2025; project's `date` happens to be in 2026 (legacy noise)
        let p = makeProject(
            uid: "00000001", title: "P", year: 2025,
            date: makeDate(2026, 6, 15),
            precision: .year
        )
        XCTAssertEqual(ProjectSort.effectiveSortDate(for: p), makeDate(2025, 1, 1))
    }

    func test_effectiveSortDate_monthPrecision_isFirstOfMonth() {
        let p = makeProject(
            uid: "00000002", title: "P", year: 2025,
            date: makeDate(2025, 3, 17),
            precision: .month
        )
        XCTAssertEqual(ProjectSort.effectiveSortDate(for: p), makeDate(2025, 3, 1))
    }

    func test_effectiveSortDate_dayPrecision_isExactDate() {
        let p = makeProject(
            uid: "00000003", title: "P", year: 2025,
            date: makeDate(2025, 3, 17),
            precision: .day
        )
        XCTAssertEqual(ProjectSort.effectiveSortDate(for: p), makeDate(2025, 3, 17))
    }

    func test_sortedWithinYear_explicitWhensDescend() {
        let mar = makeProject(uid: "a1111111", title: "March", year: 2025, date: makeDate(2025, 3, 1), precision: .month)
        let jun = makeProject(uid: "a2222222", title: "June", year: 2025, date: makeDate(2025, 6, 1), precision: .month)
        let sep = makeProject(uid: "a3333333", title: "Sept", year: 2025, date: makeDate(2025, 9, 1), precision: .month)
        let sorted = ProjectSort.sortedWithinYear([mar, jun, sep])
        XCTAssertEqual(sorted.map(\.title), ["Sept", "June", "March"])
    }

    func test_sortedWithinYear_yearOnlyProjectsFallToEnd() {
        let dated = makeProject(uid: "b1111111", title: "Dated", year: 2025, date: makeDate(2025, 3, 1), precision: .month)
        let yearOnlyA = makeProject(uid: "b2222222", title: "Alpha", year: 2025, date: makeDate(2025, 1, 1), precision: .year)
        let yearOnlyB = makeProject(uid: "b3333333", title: "Bravo", year: 2025, date: makeDate(2025, 1, 1), precision: .year)
        let sorted = ProjectSort.sortedWithinYear([yearOnlyA, dated, yearOnlyB])
        XCTAssertEqual(sorted.map(\.title), ["Dated", "Alpha", "Bravo"])
    }

    func test_sortedWithinYear_alphaTieBreakOnSameDate() {
        let zebra = makeProject(uid: "c1111111", title: "Zebra", year: 2025, date: makeDate(2025, 3, 1), precision: .month)
        let apple = makeProject(uid: "c2222222", title: "Apple", year: 2025, date: makeDate(2025, 3, 1), precision: .month)
        let sorted = ProjectSort.sortedWithinYear([zebra, apple])
        XCTAssertEqual(sorted.map(\.title), ["Apple", "Zebra"])
    }

    func test_sortedWithinYear_dayPrecisionOrdersWithinMonth() {
        let mar15 = makeProject(uid: "d1111111", title: "Mid", year: 2025, date: makeDate(2025, 3, 15), precision: .day)
        let mar01 = makeProject(uid: "d2222222", title: "First", year: 2025, date: makeDate(2025, 3, 1), precision: .day)
        let sorted = ProjectSort.sortedWithinYear([mar01, mar15])
        XCTAssertEqual(sorted.map(\.title), ["Mid", "First"])
    }
}
```

- [ ] **Step 2: Create the helper**

Create `PortyMcFolio/Services/ProjectSort.swift`:

```swift
import Foundation

/// Pure helpers that order projects within a single year band.
///
/// The grid groups projects by `Project.year` (folder year). Within each band,
/// we sort by an "effective sort date" so projects with explicit Whens land
/// in chronological order (newest first) and year-only projects collapse to
/// Jan 1 — pushing them past everything dated, where they tie-break on title.
enum ProjectSort {

    /// Returns the date used to order a project within its band.
    /// Year-only projects collapse to Jan 1 of the folder year so legacy
    /// `date:` noise (e.g. an old project with `date: 2026-...` due to
    /// the parser default) cannot influence ordering.
    static func effectiveSortDate(for project: Project) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        switch project.datePrecision {
        case .year:
            return calendar.date(from: DateComponents(year: project.year, month: 1, day: 1))
                ?? project.date
        case .month:
            let comps = calendar.dateComponents([.year, .month], from: project.date)
            return calendar.date(from: comps) ?? project.date
        case .day:
            return project.date
        }
    }

    /// Orders projects within a year band.
    /// Explicit Whens descend (most recent start first); year-only projects
    /// land at the end and tie-break alphabetically by title.
    static func sortedWithinYear(_ projects: [Project]) -> [Project] {
        projects.sorted { a, b in
            let aDate = effectiveSortDate(for: a)
            let bDate = effectiveSortDate(for: b)
            if aDate != bDate {
                return aDate > bDate
            }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }
}
```

- [ ] **Step 3: Regenerate project + run tests**

```bash
cd <repo> && xcodegen generate 2>&1 | tail -3 && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/ProjectSortTests 2>&1 | grep -E "Test Suite.*ProjectSortTests|failed|passed" | tail -5
```

Expected: all 7 ProjectSortTests pass.

- [ ] **Step 4: Commit**

```bash
cd <repo> && git add PortyMcFolio.xcodeproj/project.pbxproj PortyMcFolio/Services/ProjectSort.swift PortyMcFolioTests/ProjectSortTests.swift && git commit -m "feat(sort): within-year comparator using effective sort date

Pure helper that orders projects within a year band. Effective sort date
is Jan 1 of the folder year for .year precision, first-of-month for
.month, exact date for .day. Year-only projects fall at the end of the
band and tie-break alphabetically by title.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: `ProjectMetadataMutation` year-change resolver + AppState plumbing

Extract the year-change-affects-date logic into a pure helper, test it, and have `AppState.updateProjectMetadata` use it. Add the new fields to the function signature so callers can pass When through.

**Files:**
- Create: `PortyMcFolio/Services/ProjectMetadataMutation.swift`
- Create: `PortyMcFolioTests/ProjectMetadataMutationTests.swift`
- Modify: `PortyMcFolio/App/AppState.swift`

- [ ] **Step 1: Write failing tests**

Create `PortyMcFolioTests/ProjectMetadataMutationTests.swift`:

```swift
import XCTest
@testable import PortyMcFolio

final class ProjectMetadataMutationTests: XCTestCase {

    private func makeDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func test_yearPrecision_yearChange_rewritesYearComponentOnDate() {
        let result = ProjectMetadataMutation.resolveYearChange(
            currentDate: makeDate(2024, 3, 15),
            currentDateEnd: nil,
            precision: .year,
            newYear: 2025
        )
        XCTAssertEqual(result.date, makeDate(2025, 3, 15))
        XCTAssertNil(result.dateEnd)
    }

    func test_monthPrecision_yearChange_leavesDateUntouched() {
        let result = ProjectMetadataMutation.resolveYearChange(
            currentDate: makeDate(2024, 3, 1),
            currentDateEnd: makeDate(2024, 6, 30),
            precision: .month,
            newYear: 2025
        )
        XCTAssertEqual(result.date, makeDate(2024, 3, 1))
        XCTAssertEqual(result.dateEnd, makeDate(2024, 6, 30))
    }

    func test_dayPrecision_yearChange_leavesDateUntouched() {
        let result = ProjectMetadataMutation.resolveYearChange(
            currentDate: makeDate(2024, 3, 15),
            currentDateEnd: makeDate(2024, 4, 2),
            precision: .day,
            newYear: 2025
        )
        XCTAssertEqual(result.date, makeDate(2024, 3, 15))
        XCTAssertEqual(result.dateEnd, makeDate(2024, 4, 2))
    }

    func test_yearPrecision_yearChange_dateEndStaysNil() {
        let result = ProjectMetadataMutation.resolveYearChange(
            currentDate: makeDate(2024, 3, 15),
            currentDateEnd: nil,
            precision: .year,
            newYear: 2030
        )
        XCTAssertNil(result.dateEnd)
    }
}
```

- [ ] **Step 2: Create the helper**

Create `PortyMcFolio/Services/ProjectMetadataMutation.swift`:

```swift
import Foundation

/// Pure helpers used by `AppState.updateProjectMetadata` to keep the
/// frontmatter consistent on metadata changes. Extracted so the rules can
/// be unit-tested without spinning up the full app state.
enum ProjectMetadataMutation {

    /// Decides what `date` and `dateEnd` should be after the user changes the
    /// project's year in Project Settings.
    ///
    /// - For `.year` precision (legacy default): rewrite the year component of
    ///   `date`, preserve month/day. `dateEnd` stays nil. This matches the
    ///   pre-existing covert behavior so legacy projects keep working.
    /// - For `.month` and `.day` precision: leave `date` and `dateEnd`
    ///   untouched. The user explicitly set a When; the year-change should not
    ///   silently shift it.
    static func resolveYearChange(
        currentDate: Date,
        currentDateEnd: Date?,
        precision: DatePrecision,
        newYear: Int,
        calendar: Calendar = utcGregorian()
    ) -> (date: Date, dateEnd: Date?) {
        switch precision {
        case .year:
            var comps = calendar.dateComponents([.month, .day], from: currentDate)
            comps.year = newYear
            let newDate = calendar.date(from: comps) ?? currentDate
            return (newDate, currentDateEnd)
        case .month, .day:
            return (currentDate, currentDateEnd)
        }
    }

    private static func utcGregorian() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }
}
```

- [ ] **Step 3: Update `AppState.updateProjectMetadata` signature**

In `PortyMcFolio/App/AppState.swift`, replace the `updateProjectMetadata` function. Find the existing definition (starts around line 685) and replace it entirely with this version. The new signature accepts a `WhenValue`; the year-sync logic delegates to the new helper:

```swift
    func updateProjectMetadata(
        project: Project,
        title: String,
        year: Int,
        client: String,
        status: ProjectStatus,
        tags: [String],
        teaser: String,
        hidden: Bool,
        when: WhenValue
    ) throws {
        let newFolderName = Project.folderName(title: title, year: year, uid: project.uid)
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

        // Apply the year-change rule: legacy (precision .year) projects get
        // their date year rewritten to keep frontmatter tidy; explicit-When
        // projects keep date and dateEnd untouched.
        let resolved = ProjectMetadataMutation.resolveYearChange(
            currentDate: when.date,
            currentDateEnd: when.dateEnd,
            precision: when.precision,
            newYear: year
        )
        parsed.date = resolved.date
        parsed.dateEnd = resolved.dateEnd
        parsed.datePrecision = when.precision

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

This signature change will break the only caller (`ProjectSettingsPopover.save()`), which Task 9 fixes. Build will fail until then — that's expected.

- [ ] **Step 4: Regen project + run the helper tests**

```bash
cd <repo> && xcodegen generate 2>&1 | tail -3 && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/ProjectMetadataMutationTests 2>&1 | grep -E "Test Suite.*ProjectMetadataMutationTests|failed|passed" | tail -5
```

Expected: all 4 ProjectMetadataMutationTests pass. The full app build will fail because `ProjectSettingsPopover.save()` doesn't yet pass `when:`. That's resolved in Task 9.

- [ ] **Step 5: Commit (red build is expected here)**

```bash
cd <repo> && git add PortyMcFolio.xcodeproj/project.pbxproj PortyMcFolio/Services/ProjectMetadataMutation.swift PortyMcFolio/App/AppState.swift PortyMcFolioTests/ProjectMetadataMutationTests.swift && git commit -m "feat(state): precision-aware year-change rule + WhenValue parameter

Extract year-change-affects-date logic into ProjectMetadataMutation helper
and have updateProjectMetadata delegate. New 'when' parameter on the
update API. Year-only projects keep the legacy date-year rewrite; .month
and .day precision leave date/dateEnd untouched on year change.

ProjectSettingsPopover not yet updated for the new signature — build is
intentionally red until Task 9 wires the caller.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: `WhenPicker` SwiftUI view

The picker control: trigger button + month-grid popover + footer with Clear/Be specific. No tests (project convention forbids SwiftUI view tests).

**Files:**
- Create: `PortyMcFolio/Views/WhenPicker.swift`

- [ ] **Step 1: Create `WhenPicker.swift`**

Create `PortyMcFolio/Views/WhenPicker.swift`:

```swift
import SwiftUI

/// A trigger + popover picker for setting a project's optional "When".
/// Year-only by default; clicking a month sets a single-month When; clicking
/// a second month sets a range (which may cross years via the ‹ › nav).
/// `Be specific…` reveals a day-level refinement panel for the rare cases
/// when a project is genuinely day-bound.
///
/// The control writes through to its `Binding<WhenValue>` continuously —
/// there is no commit step inside the popover. Persistence happens when the
/// user clicks Save in the surrounding `ProjectSettingsPopover`.
struct WhenPicker: View {
    @Binding var value: WhenValue
    /// The canonical year (folder year). Used as the default visible year in
    /// the popover and as the implicit year for "Year only" reset.
    let projectYear: Int

    @State private var isOpen = false
    @State private var visibleYear: Int = 0
    @State private var pendingStartMonth: DateComponents?
    @State private var showDayRefinement = false

    @Environment(\.theme) var theme

    var body: some View {
        Button {
            if !isOpen {
                visibleYear = startYear ?? projectYear
                pendingStartMonth = nil
                showDayRefinement = (value.precision == .day)
            }
            isOpen.toggle()
        } label: {
            HStack(spacing: DT.Spacing.sm) {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.colors.textTertiary)
                Text(triggerLabel)
                    .font(DT.Typography.body)
                    .foregroundStyle(triggerColor)
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

    // MARK: - Computed

    private var triggerLabel: String {
        switch value.precision {
        case .year:
            return "Year only"
        case .month, .day:
            return WhenFormatting.summaryString(
                date: value.date,
                dateEnd: value.dateEnd,
                precision: value.precision,
                year: projectYear
            )
        }
    }

    private var triggerColor: Color {
        value.precision == .year ? theme.colors.textTertiary : theme.colors.textPrimary
    }

    private var startYear: Int? {
        guard value.precision != .year else { return nil }
        return calendar.component(.year, from: value.date)
    }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    // MARK: - Popover body

    private var popoverBody: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.md) {
            // Year nav
            HStack {
                Button { visibleYear -= 1 } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .medium))
                }
                .iconButton()
                Spacer()
                Text(String(visibleYear))
                    .font(DT.Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer()
                Button { visibleYear += 1 } label: {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium))
                }
                .iconButton()
            }

            // Month grid
            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(1...12, id: \.self) { month in
                    monthCell(month: month)
                }
            }

            // Footer
            HStack {
                Text(footerSummary)
                    .font(DT.Typography.caption)
                    .foregroundStyle(theme.colors.textPrimary)
                    .fontWeight(value.precision == .year ? .regular : .medium)
                Spacer()
                Button("Be specific…") { showDayRefinement.toggle() }
                    .buttonStyle(.plain)
                    .font(DT.Typography.caption)
                    .foregroundStyle(theme.colors.accent)
                Button("Clear") { clearToYearOnly() }
                    .buttonStyle(.plain)
                    .font(DT.Typography.caption)
                    .foregroundStyle(theme.colors.textTertiary)
            }

            if showDayRefinement && value.precision != .year {
                Divider()
                Text("Day refinement (start \(formatDay(value.date))) — coming next iteration")
                    .font(DT.Typography.caption)
                    .foregroundStyle(theme.colors.textTertiary)
                    .padding(.vertical, DT.Spacing.xs)
            }
        }
    }

    // MARK: - Month cell

    @ViewBuilder
    private func monthCell(month: Int) -> some View {
        let state = cellState(for: month, year: visibleYear)
        Button {
            tap(month: month, year: visibleYear)
        } label: {
            Text(monthAbbrev(month))
                .font(DT.Typography.caption)
                .fontWeight(state == .none ? .regular : .semibold)
                .foregroundStyle(foregroundColor(for: state))
                .frame(maxWidth: .infinity)
                .padding(.vertical, DT.Spacing.sm)
                .background(backgroundColor(for: state))
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.small))
        }
        .buttonStyle(.plain)
    }

    private enum CellState { case none, anchor, inRange }

    private func cellState(for month: Int, year: Int) -> CellState {
        guard value.precision != .year else { return .none }
        let cal = calendar
        let startY = cal.component(.year, from: value.date)
        let startM = cal.component(.month, from: value.date)
        if year == startY && month == startM { return .anchor }
        if let end = value.dateEnd {
            let endY = cal.component(.year, from: end)
            let endM = cal.component(.month, from: end)
            if year == endY && month == endM { return .anchor }

            // In-range: this (year, month) sits strictly between start and end.
            let startKey = startY * 12 + startM
            let endKey = endY * 12 + endM
            let key = year * 12 + month
            if key > startKey && key < endKey { return .inRange }
        }
        return .none
    }

    private func backgroundColor(for state: CellState) -> Color {
        switch state {
        case .none: return .clear
        case .anchor: return theme.colors.accent
        case .inRange: return theme.colors.accent.opacity(DT.Opacity.selection)
        }
    }

    private func foregroundColor(for state: CellState) -> Color {
        switch state {
        case .none: return theme.colors.textPrimary
        case .anchor: return .white
        case .inRange: return theme.colors.accent
        }
    }

    // MARK: - Tap handling

    private func tap(month: Int, year: Int) {
        let cal = calendar
        let firstOfMonth = cal.date(from: DateComponents(year: year, month: month, day: 1))!
        let endOfMonth = lastDay(of: month, year: year)

        if value.precision == .year || pendingStartMonth != nil {
            // Begin (or restart) a selection.
            value = WhenValue(date: firstOfMonth, dateEnd: nil, precision: .month)
            pendingStartMonth = DateComponents(year: year, month: month)
            return
        }

        // We have an anchor month (start of value.date) and the user is picking a second month → form a range.
        let startOfExisting = value.date
        let existingY = cal.component(.year, from: startOfExisting)
        let existingM = cal.component(.month, from: startOfExisting)
        let existingKey = existingY * 12 + existingM
        let newKey = year * 12 + month

        if newKey == existingKey {
            // Re-tap same month: collapse range to single month.
            value = WhenValue(date: firstOfMonth, dateEnd: nil, precision: .month)
        } else if newKey > existingKey {
            value = WhenValue(date: startOfExisting, dateEnd: endOfMonth, precision: .month)
        } else {
            // User picked an earlier month — swap so start <= end.
            let endOfExisting = lastDay(of: existingM, year: existingY)
            value = WhenValue(date: firstOfMonth, dateEnd: endOfExisting, precision: .month)
        }
        pendingStartMonth = nil
    }

    private func clearToYearOnly() {
        // Year-only resets precision but preserves the underlying date so
        // legacy round-tripping stays clean.
        value = WhenValue(date: value.date, dateEnd: nil, precision: .year)
        pendingStartMonth = nil
        showDayRefinement = false
    }

    // MARK: - Helpers

    private var footerSummary: String {
        switch value.precision {
        case .year:
            return "Year only"
        case .month, .day:
            return WhenFormatting.summaryString(
                date: value.date,
                dateEnd: value.dateEnd,
                precision: value.precision,
                year: projectYear
            )
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

    private func formatDay(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "MMM d, yyyy"
        return df.string(from: date)
    }
}
```

**Note on day refinement:** the popover stub for day-level precision is intentionally minimal in this task ("coming next iteration"). The data model and serialization fully support `.day` precision (Tasks 1–4); the picker presents month-grain UI but won't write `.day` precision through this control. Day-precision projects coming from external edits load and display correctly. A follow-up plan can extend the picker with the day-grid panel — out of scope for this iteration to keep the diff focused.

- [ ] **Step 2: Regen project + verify build**

```bash
cd <repo> && xcodegen generate 2>&1 | tail -3 && xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -configuration Debug build 2>&1 | grep -E "error:|BUILD" | tail -5
```

Expected: still red on `ProjectSettingsPopover.save()` (signature mismatch from Task 7) — but **only** that file. If `WhenPicker.swift` itself errors, fix and retry.

- [ ] **Step 3: Commit**

```bash
cd <repo> && git add PortyMcFolio.xcodeproj/project.pbxproj PortyMcFolio/Views/WhenPicker.swift && git commit -m "feat(views): WhenPicker control

Trigger button + month-grid popover for setting a project's optional When.
Click month → single month; click second month → range (cross-year via
year nav). Clear → year only. Day refinement is stubbed for a follow-up.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Wire `WhenPicker` into `ProjectSettingsPopover`

Render the picker under the `YearStepper`, plumb its value through `save()` to the new `updateProjectMetadata` signature. Add the inline note when precision is non-year.

**Files:**
- Modify: `PortyMcFolio/Views/ProjectSettingsPopover.swift`

**Convention:** This popover hydrates `@State` inside `.onAppear` (not a custom `init`). Add the new state with a bootstrap default and then overwrite it in the existing `.onAppear` block.

- [ ] **Step 1: Add the `when` state**

In `PortyMcFolio/Views/ProjectSettingsPopover.swift`, alongside the other `@State private var ...` declarations near the top of the struct (around lines 9–17), add:

```swift
    @State private var when: WhenValue = .yearOnly(anchor: Date())
```

The bootstrap value is irrelevant — `.onAppear` overwrites it from the project.

- [ ] **Step 2: Hydrate from the project on appear**

Find the `.onAppear { ... }` block (around line 200) where the other fields are copied from `project`. Append at the end of that block, before `loadTeaserImage()`:

```swift
            when = WhenValue(
                date: project.date,
                dateEnd: project.dateEnd,
                precision: project.datePrecision
            )
```

- [ ] **Step 3: Render the picker after the YearStepper**

Find the `YearStepper(year: $year)` call (around line 34). Append immediately after it (same form section):

```swift
                WhenPicker(value: $when, projectYear: year)

                if when.precision != .year {
                    Text("Changing year won't shift your When range.")
                        .font(DT.Typography.caption)
                        .foregroundStyle(theme.colors.textTertiary)
                        .padding(.top, DT.Spacing.xs)
                }
```

- [ ] **Step 4: Pass `when` through to `updateProjectMetadata`**

Inside `save()` (around line 236), update the call to add `when:`:

```swift
            try appState.updateProjectMetadata(
                project: project,
                title: trimmedTitle,
                year: year,
                client: clients.joined(separator: ", "),
                status: status,
                tags: tags,
                teaser: teaser,
                hidden: hidden,
                when: when
            )
```

- [ ] **Step 5: Build to verify**

```bash
cd <repo> && xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -configuration Debug build 2>&1 | grep -E "error:|BUILD" | tail -5
```

Expected: `** BUILD SUCCEEDED **`. The signature mismatch from Task 7 is now resolved.

- [ ] **Step 6: Commit**

```bash
cd <repo> && git add PortyMcFolio/Views/ProjectSettingsPopover.swift && git commit -m "feat(views): wire WhenPicker into Project Settings

Render WhenPicker under the year stepper, plumb its value through save()
to updateProjectMetadata. Inline note clarifies year-change behavior when
the user has set an explicit When.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: Editorial card hover overlay shows the When summary

`EditorialCardView` currently shows `Text(String(project.year))`. Swap it for the formatted summary so single-month/range projects display as `MAR 2025` / `MAR — JUN 2025` etc.

**Files:**
- Modify: `PortyMcFolio/Views/EditorialCardView.swift`

- [ ] **Step 1: Replace the year line in the hover overlay**

In `PortyMcFolio/Views/EditorialCardView.swift`, find this block in the hover overlay:

```swift
                            Text(String(project.year))
                                .font(DT.Typography.micro)
                                .foregroundStyle(.white.opacity(0.6))
                                .textCase(.uppercase)
                                .tracking(1.4)
```

Replace it with:

```swift
                            Text(WhenFormatting.summaryString(
                                date: project.date,
                                dateEnd: project.dateEnd,
                                precision: project.datePrecision,
                                year: project.year
                            ))
                                .font(DT.Typography.micro)
                                .foregroundStyle(.white.opacity(0.6))
                                .tracking(1.4)
```

`WhenFormatting.summaryString` already returns uppercase — drop the `.textCase(.uppercase)` modifier so we don't double-case.

- [ ] **Step 2: Build**

```bash
cd <repo> && xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -configuration Debug build 2>&1 | grep -E "error:|BUILD" | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd <repo> && git add PortyMcFolio/Views/EditorialCardView.swift && git commit -m "feat(views): editorial hover overlay shows When summary

Replace the bare year with the formatted When summary (MAR 2025 /
MAR — JUN 2025 / SEP 2024 — FEB 2025 / etc). Year-only projects keep
the existing 4-digit year display.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: `ProjectListView` uses the within-year sort

The grid groups projects by year and renders them in `Dictionary(grouping:)` order today. Replace the in-band order with `ProjectSort.sortedWithinYear`.

**Files:**
- Modify: `PortyMcFolio/Views/ProjectListView.swift`

- [ ] **Step 1: Update `computeProjectsByYear`**

In `PortyMcFolio/Views/ProjectListView.swift`, find the static helper:

```swift
    private static func computeProjectsByYear(_ projects: [Project]) -> [(year: Int, projects: [Project])] {
        let grouped = Dictionary(grouping: projects) { $0.year }
        return grouped.keys.sorted(by: >).map { year in
            (year: year, projects: grouped[year]!)
        }
    }
```

Replace its body so the within-band list runs through the new comparator:

```swift
    private static func computeProjectsByYear(_ projects: [Project]) -> [(year: Int, projects: [Project])] {
        let grouped = Dictionary(grouping: projects) { $0.year }
        return grouped.keys.sorted(by: >).map { year in
            (year: year, projects: ProjectSort.sortedWithinYear(grouped[year]!))
        }
    }
```

- [ ] **Step 2: Build**

```bash
cd <repo> && xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -configuration Debug build 2>&1 | grep -E "error:|BUILD" | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd <repo> && git add PortyMcFolio/Views/ProjectListView.swift && git commit -m "feat(overview): sort projects within year band by When

Use ProjectSort.sortedWithinYear so explicit Whens descend (most recent
first) and year-only projects fall at the end alphabetically. Year band
ordering itself (newest year first) is unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 12: Full test sweep + manual smoke test

Run the full test suite, then run the app and exercise the picker, hover overlay, and sort behavior end-to-end.

- [ ] **Step 1: Full unit test suite**

```bash
cd <repo> && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | grep -E "Test Suite 'All tests'|failed|with [0-9]+ tests" | tail -5
```

Expected: `Test Suite 'All tests' passed`. No failures.

- [ ] **Step 2: Build and run the app**

```bash
cd <repo> && xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -configuration Debug build 2>&1 | grep -E "error:|BUILD SUCCEEDED" | tail -3 && open <DerivedData>/PortyMcFolio/Build/Products/Debug/PortyMcFolio.app
```

- [ ] **Step 3: Manual smoke test checklist**

In the running app, verify each of these:

1. **Existing year-only projects load and look identical** — overview cards show their captions (title + uppercase client); hover still shows the bare year (e.g. `2025`).
2. **Open a project's settings (⌘9 from inside it, or right-click → Project Settings on the overview).** The new "When (optional)" picker appears below the Year stepper, labeled **Year only**.
3. **Click the picker** → popover opens with year nav + month grid. The footer summary reads `Year only`.
4. **Click a month (e.g. March)** → that cell highlights, footer becomes `MAR 2025`, trigger label updates immediately.
5. **Click a second month later in the year (e.g. June)** → range fills (March–June), footer becomes `MAR — JUN 2025`.
6. **Click `›` to advance to next year, then click February** → range becomes `MAR 2025 — FEB 2026`. Tip: tapping an earlier-than-anchor month should swap the range so start ≤ end.
7. **Save settings** → the project persists; reopen settings to confirm the When sticks.
8. **Hover the project's card on the overview** → the hover overlay shows `MAR — JUN 2025` (or whatever you set) in the same uppercase-tracked voice.
9. **Within-year sort:** in a year band that has both dated and year-only projects, the dated ones come first (most recent month first); year-only sit at the end alphabetically.
10. **Year change while precision is `.month`:** open settings on a project with a When set, change the year by ±1, save. Reopen settings — the When range did NOT shift; only the folder year changed. (And the inline note "Changing year won't shift your When range" was visible while you were in the sheet.)
11. **Year change while precision is `.year`:** open settings on a year-only project, change year ±1, save. Verify the project is still year-only and the new year sticks.
12. **Clear button:** in the picker, click `Clear` → trigger reverts to "Year only", footer reads "Year only", the inline note disappears.

- [ ] **Step 4: If everything passes, commit any incidental cleanup**

If the smoke test surfaces nothing to fix, this task is done. If you found a small bug, fix it inline and commit with a tight `fix(...)` message before considering the plan complete.

```bash
cd <repo> && git status
```

Expected: working tree clean.

---

## Summary of files touched

| file | tasks | nature |
|--|--|--|
| `Models/Project.swift` | 1, 4 | new types + props + loadReadme update |
| `Services/FrontmatterParser.swift` | 1, 2, 3 | ParsedFrontmatter props + parse + serialize |
| `Services/WhenFormatting.swift` | 5 | new pure helper |
| `Services/ProjectSort.swift` | 6 | new pure helper |
| `Services/ProjectMetadataMutation.swift` | 7 | new pure helper |
| `App/AppState.swift` | 7 | updateProjectMetadata signature + delegation |
| `Views/WhenPicker.swift` | 8 | new SwiftUI view |
| `Views/ProjectSettingsPopover.swift` | 9 | wire the picker, pass `when:` through |
| `Views/EditorialCardView.swift` | 10 | hover overlay reads summary |
| `Views/ProjectListView.swift` | 11 | within-year sort |
| `PortyMcFolioTests/FrontmatterParserTests.swift` | 2, 3 | new tests |
| `PortyMcFolioTests/WhenFormattingTests.swift` | 5 | new file |
| `PortyMcFolioTests/ProjectSortTests.swift` | 6 | new file |
| `PortyMcFolioTests/ProjectMetadataMutationTests.swift` | 7 | new file |
| `PortyMcFolio.xcodeproj/project.pbxproj` | 5, 6, 7, 8 | xcodegen regen for new files |
