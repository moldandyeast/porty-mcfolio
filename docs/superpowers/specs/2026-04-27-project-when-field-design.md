# Project "When" Field — Finer-Grained Date for In-Year Sort

**Date:** 2026-04-27
**Scope:** `Models/Project.swift`, `Services/FrontmatterParser.swift`, `Views/ProjectSettingsPopover.swift`, `Views/ProjectListView.swift`, `Views/EditorialCardView.swift`, `App/AppState.swift`, plus new `Views/WhenPicker.swift` and `Services/WhenFormatting.swift`.
**Stacks on:** the editorial-grid commit `66c1a91` (image-forward overview, hover-overlay shows year).

> **Rev 2 (2026-04-27, end of day):** After implementing Rev 1 in commits `9277630..bbe8a9d` and live-testing, the dual Year-stepper-plus-When sheet was confusing — the two could disagree (e.g. Year `2026` vs When `NOV — DEC 2030`). The model is rewritten as **two modes only — Year-only or Range**, the YearStepper is removed from settings, the folder year auto-derives from the Range's End on save, and `DatePrecision` and the day-precision UI are dropped. The Rev 1 sections below are historical context for what was built first; the **Rev 2 Redesign** section at the bottom of this spec is the current contract. The Rev 2 follow-up plan is at `docs/superpowers/plans/2026-04-27-project-when-field-rev2.md`.

## Summary

Add an optional, finer-grained "When" to each project so projects within a year band have a stable, meaningful order — without disturbing the canonical year (which the folder name owns).

The new field is a precision-aware date or date-range:

- year-only (existing behavior, default for legacy projects)
- single month (e.g. `Mar 2025`)
- month range (e.g. `Mar – Jun 2025`, may cross years)
- single day (e.g. `Mar 15, 2025`) — opt-in, for day-bound projects
- day range (e.g. `Mar 15 – Apr 2, 2025`) — opt-in

The When surfaces in the editorial card hover overlay (replacing the lonely `2025`) and drives sort within a year band. It is editable from Project Settings via a single popover control. No migration, no folder changes, no breakage of existing year semantics.

## Motivation

The editorial grid groups projects under year bands. Within a band, order is currently incidental (insertion order / dictionary key order). For users with multiple projects per year this makes the overview hard to scan in any meaningful temporal sense. Adding a year-only field is too coarse — many projects fall in a specific month or run across a few months. We want the user to express that level of detail without forcing a brittle "exact day" model on every project.

## Design

### Schema (frontmatter)

Three keys, all optional:

| key | type | meaning |
|--|--|--|
| `date` | full-date `YYYY-MM-DD` | **start anchor** of the When range. Field already exists and continues to be parsed exactly as today. |
| `dateEnd` | full-date `YYYY-MM-DD` | end anchor. Present only when the When is a range. |
| `datePrecision` | enum: `year`, `month`, `day` | granularity. Absent ⇒ `year`. |

Examples:

```yaml
# Year-only (legacy and default)
date: 2025-01-01
# datePrecision absent

# Single month: March 2025
date: 2025-03-01
datePrecision: month

# Month range: Mar – Jun 2025
date: 2025-03-01
dateEnd: 2025-06-30
datePrecision: month

# Single day
date: 2025-03-15
datePrecision: day

# Day range
date: 2025-03-15
dateEnd: 2025-04-02
datePrecision: day
```

Why reuse `date:` rather than introduce `dateStart:` — the existing field is already a real `Date`, parses with the existing formatter, and is currently never displayed. Repurposing it as the start anchor gives the model a single date entry point and zero migration: every legacy project already has a valid `date:` and an absent `datePrecision`, which decodes to `year`. They render the same as before.

### Project model

```swift
enum DatePrecision: String, Codable, CaseIterable {
    case year, month, day
}

struct Project {
    // … existing fields unchanged …
    let date: Date              // existing — now also acts as the When start
    let dateEnd: Date?          // new — present only for ranges
    let datePrecision: DatePrecision  // new — defaults to .year
}
```

`Project.from(folderName:rootURL:)` reads the two new fields from the parsed frontmatter; absence of `datePrecision` falls back to `.year`. Folder-name parsing is untouched; `year: Int` continues to come from the folder name and is the source of truth for the year band.

### FrontmatterParser

- `parse` reads `dateEnd` (using the same formatter chain as `date`) and `datePrecision` (string lookup against `DatePrecision.allCases`). Malformed/unknown values fall back to nil/`.year` and log via `AppLogger`.
- `serialize` emits `dateEnd` only when present, and emits `datePrecision` only when not `.year` (keeps frontmatter clean for legacy projects).
- New unit tests cover roundtrip for every precision shape, malformed values, and absence of `datePrecision` defaulting to `.year`.

### Input UX — `WhenPicker`

A new SwiftUI control rendered inside `ProjectSettingsPopover`, anchored under the existing `YearStepper`. Closed state:

```
When (optional)
[ 📅  Year only  ▾ ]
```

The trigger label reflects the current value: `Year only` / `Mar 2025` / `Mar – Jun 2025` / `Mar 15, 2025` / etc. Clicking opens a popover:

```
‹  2025  ›

[Jan] [Feb] [Mar] [Apr]
[May] [Jun] [Jul] [Aug]
[Sep] [Oct] [Nov] [Dec]

Mar – Jun 2025                      Be specific…  Clear
```

Behavior:

- Clicking a month sets a single-month When (precision = `month`, `date` = first day of that month, `dateEnd` = nil).
- Clicking a second month sets a range (precision = `month`, `date` = first day of earlier month, `dateEnd` = last day of later month). Order-independent — the picker normalizes start ≤ end.
- The `‹` / `›` arrows shift the visible year by ±1 (visual only — does **not** change the project's year). A range can span years: pick May in 2024, navigate to 2025, pick Feb. Footer summary becomes `May 2024 – Feb 2025`.
- `Clear` resets to year-only (precision = `.year`, `dateEnd` = nil; `date` is left as-is so legacy stays legacy).
- `Be specific…` reveals a day-level refinement on top of the chosen month(s) — a small day grid for the start month and (if a range) the end month, letting the user tighten to specific days. Setting any day in the refinement pane upgrades precision to `.day` and writes exact dates. Hidden by default to keep the common path uncluttered.
- The popover writes through to its `Binding<WhenValue>` continuously — clicking a month updates the value (and the trigger label) immediately. There is no separate "Done" button inside the picker; persistence happens when the user clicks Save in the surrounding `ProjectSettingsPopover`.

The picker takes a `Binding<WhenValue>` where `WhenValue` is a small struct wrapping `(date, dateEnd, precision)` so the surrounding form can compose it with the rest of project metadata.

### Display — hover overlay

`EditorialCardView`'s hover overlay currently renders `Text(String(project.year))`. It will instead render the formatted When summary (from the new `WhenFormatting` helper):

| precision | shape | example |
|--|--|--|
| year | `2025` | `2025` |
| month, single | `MMM YYYY` | `MAR 2025` |
| month, range, same year | `MMM — MMM YYYY` | `MAR — JUN 2025` |
| month, range, cross-year | `MMM YYYY — MMM YYYY` | `SEP 2024 — FEB 2025` |
| day, single | `MMM D, YYYY` | `MAR 15, 2025` |
| day, range, same month | `MMM D — D, YYYY` | `MAR 15 — 22, 2025` |
| day, range, different months | `MMM D — MMM D, YYYY` | `MAR 15 — APR 2, 2025` |

Visual treatment is unchanged: same `DT.Typography.micro`, uppercase, tracking 1.4, white at 0.6 opacity. Locale-aware month names via a fixed `DateFormatter` instance; em-dashes (`—`) for ranges to match the editorial typographic voice.

The always-visible caption (title + uppercase client) is unchanged. The When does not appear there.

### Sort — within a year band

Today: `ProjectListView.computeProjectsByYear` groups by `project.year`, year-keys sorted descending; the in-band order is whatever `Dictionary(grouping:)` yielded. We replace the in-band order with an explicit comparator:

1. **Effective sort date** is computed deterministically:
   - `datePrecision == .year` → Jan 1 of `project.year` (the folder year — ignores whatever `project.date` happens to hold, so legacy noise doesn't influence order).
   - `datePrecision == .month` → first day of `project.date`'s month.
   - `datePrecision == .day` → `project.date` directly.
2. Sort descending by effective sort date — most recent first.
3. All year-only projects collide on Jan 1 of their year and fall at the end of the band when other projects have explicit Whens. Break ties alphabetically by title (case-insensitive).

This keeps year-only projects at the bottom of each band (they're "vague — show last") and orders dated projects newest-first. Cross-year ranges are grouped by the project's folder year (the canonical year), regardless of where their start anchor falls.

The table view's sort is **not** affected by this change; the table continues to expose Year/Title/Client/Status as sortable columns. A future change can add a When column.

### Year-change contract

`AppState.updateProjectMetadata` currently rewrites the frontmatter `date:` year-component when the user changes the year (`AppState.swift:749–756`). We split the behavior on precision:

- **`datePrecision == .year`** (legacy and default): keep existing behavior. Replace the year of `date:`, preserve month/day. `dateEnd` and `datePrecision` are absent so nothing else to do.
- **`datePrecision == .month` or `.day`**: leave `date:` and `dateEnd:` exactly as the user set them. Folder gets renamed, frontmatter `title`/`tags`/etc. get rewritten as today, but the When range is the user's explicit intent and we don't quietly mutate it.

The settings sheet adds a small inline note next to the year stepper when precision is non-year: *"Changing year won't shift your When range."* — terse, no shouty styling.

### Edge cases

- **Validation**: the picker enforces `dateEnd >= date`. If a malformed YAML has `dateEnd < date`, the parser clamps `dateEnd = date` and logs a warning via `AppLogger.app`; the project still loads.
- **Cross-year ranges**: fully supported. The folder year (and grid band) is whichever the user picked. The hover overlay shows both years (`SEP 2024 — FEB 2025`).
- **Day refinement off-month**: if the user picks Mar then refines to Apr 5, precision upgrades to `.day` and the dates are written as exact days; the picker no longer renders as a "month range" in its closed form.
- **Search**: no FTS column added. The folder-name year remains the only year-substring match (`AppState.matchedProjectUIDs`); the hover overlay text is enough disambiguation in the UI.
- **CSV export**: untouched in this change. CSV continues to emit the year column. A future change can add a When column once we've lived with the field for a while.
- **Reconciliation**: the reconciler already round-trips frontmatter without inspecting these fields. New fields ride along as part of the parsed dict.

## Files touched

| file | change |
|--|--|
| `Models/Project.swift` | new `DatePrecision` enum; `dateEnd: Date?` and `datePrecision: DatePrecision` properties; `Project.from()` reads them. |
| `Services/FrontmatterParser.swift` | parse + serialize the two new keys; conditional emit. |
| `Views/ProjectSettingsPopover.swift` | render the new `WhenPicker` under the `YearStepper`; pipe its value through to `updateProjectMetadata`. Add the inline note when precision is non-year. |
| `Views/WhenPicker.swift` (new) | the popover control: trigger + month grid + footer + day-refinement panel. |
| `Services/WhenFormatting.swift` (new) | pure helpers — `summaryString(date:dateEnd:precision:locale:)`, `pickerLabel(...)`. |
| `Views/EditorialCardView.swift` | hover overlay renders the formatted summary. |
| `App/AppState.swift` | precision-aware year-sync rule in `updateProjectMetadata`; new signature accepts a `WhenValue` (date, dateEnd, datePrecision) alongside the existing year/title/client/status/tags/teaser/hidden parameters. |
| `Views/ProjectListView.swift` | replace `computeProjectsByYear` in-band ordering with the new comparator. |

`ProjectCreator` does not need changes — new projects start as year-only by default.

## Testing

- `FrontmatterParserTests` — roundtrip every precision shape; absent `datePrecision` ⇒ `.year`; malformed `datePrecision` falls back; `dateEnd < date` is clamped and logs.
- `WhenFormattingTests` (new) — every row in the display table above; locale stability (en_US_POSIX); cross-year handling.
- `ProjectSortTests` (new) — within-year ordering: explicit Whens descend by start; year-only projects at end; alpha tie-break.
- `AppStateMetadataUpdateTests` (extend if exists, else new) — year change preserves When for non-year precision; year change still sync-rewrites `date:` for year-only.
- No view tests (per the project convention).

## Out of scope

- A "When" column on the table view.
- Sorting on When across years (we keep year as the primary band).
- A timeline visualization of project ranges.
- Search-on-When (typing "march 2025" into the filter). The hover overlay is the surfacing mechanism for this iteration.
- Bulk-edit of When across multiple projects.

---

## Rev 2 Redesign — Two modes, year auto-derives

The Rev 1 picker shipped (commits `9277630..bbe8a9d`). Smoke testing surfaced two confusions:

1. The Year stepper and the When picker are independent controls. Their year fields can disagree (Year `2026` vs When `NOV — DEC 2030`), and the user has to mentally reconcile them. The "Changing year won't shift your When range" note in the sheet is correct under Rev 1's contract but reveals the model is wrong.
2. Four precision shapes (year, single-month, month-range, single-day, day-range) is too many concepts. Day precision was always a stub; single-month is just "range with start = end."

Rev 2 collapses the model to two modes and makes the year an output, not an input.

### Modes

Exactly two:

- **Year only** — no months known. The user just picks a year. A year-only project carries no `dateStart`/`dateEnd` data; it lives in the folder year.
- **Range** — explicit Start month-year and End month-year. May span years (e.g. `SEP 2024 — FEB 2025`). When start month-year equals end month-year, the display collapses to a single month (e.g. `MAR 2025`); the data is still a range with `dateStart == first-of-month`, `dateEnd == last-of-month`.

`DatePrecision` is removed. The mode is implicit: range when `dateEnd != nil`, year-only otherwise. Day-precision and the single-month mode go away.

### Folder year is derived

For year-only projects, the folder year is whatever year the user picked in the picker (replaces the YearStepper's role).

For range projects, the folder year is the year-component of `dateEnd`. **When the user changes End to a month in a different year, the folder is renamed automatically on save.** The "Changing year won't shift your When range" note is removed — it's no longer a thing the user can do, because year is no longer an independent input.

The folder-rename machinery (`AppState.updateProjectMetadata` already renames on year change) is reused; the only change is *what* feeds the new year (now: derived from the When, not user-typed).

### Schema (frontmatter)

| key | type | meaning |
|--|--|--|
| `date` | full-date `YYYY-MM-DD` | **Range start.** Present only when the project is a range. Absent ⇒ year-only. (Existing `date:` field is repurposed; legacy projects that have a stale `date:` but no `dateEnd` are read as year-only — the legacy `date` value is preserved on save but ignored for When semantics.) |
| `dateEnd` | full-date `YYYY-MM-DD` | **Range end.** Present only when the project is a range. Absence ⇒ year-only. |
| `datePrecision` | (removed) | Dropped from new writes. The parser tolerates the field's presence on existing files (ignored). |

Examples:

```yaml
# Year-only — no When fields written by the new code.
# (Existing projects may still have a legacy `date:` line; it's preserved
# on save but doesn't drive When.)

# Range — Mar to Jun 2025
date: 2025-03-01
dateEnd: 2025-06-30

# Range — Sep 2024 to Feb 2025 (cross-year). Folder year is 2025.
date: 2024-09-01
dateEnd: 2025-02-28
```

### Project model

```swift
struct Project {
    // … existing fields unchanged …
    let date: Date              // legacy / range start anchor — see whenStart computed
    let dateEnd: Date?          // range end; nil for year-only
    // dateRange / WhenValue derive from `dateEnd != nil`
}
```

`DatePrecision` enum is removed. `WhenValue` keeps `date: Date` and `dateEnd: Date?`, drops `precision`. The struct's "year-only" state is just `dateEnd == nil`. New helper:

```swift
extension WhenValue {
    var isYearOnly: Bool { dateEnd == nil }
    var isRange: Bool { dateEnd != nil }
}
```

### `WhenPicker` (rewritten)

The view is a single trigger button that opens a popover. The popover has two modes selected via a 2-button toggle.

**Year-only mode:**
- A year nav row (`‹ 2025 ›`).
- A small caption confirming where the project will be filed: *"Project filed under 2025."*
- Trigger label: `2025` (muted color).

**Range mode:**
- Two input buttons stacked: `Start: [▾ MAR 2025]` and `End: [▾ JUN 2025]` — each opens an inline month picker (year nav + 12-month grid) when clicked.
- A small accent pill below: *"↦ Filed under 2025 (year of End)"*.
- A `Clear` action that wipes the range and switches the toggle back to Year-only.
- Trigger label: `MAR — JUN 2025` (or `SEP 2024 — FEB 2025` cross-year, or `MAR 2025` collapse when start equals end).

The picker writes through to `Binding<WhenValue>` continuously. Switching from Range to Year-only sets `dateEnd = nil` (start anchor preserved on the struct but unused).

### `ProjectSettingsPopover`

The YearStepper is **removed**. The When picker takes its place under the Title field. The "Changing year won't shift your When range." inline note is removed.

`AppState.updateProjectMetadata` learns to derive the year for the folder rename:

```swift
let derivedYear: Int = {
    if let dateEnd = when.dateEnd {
        return calendar.component(.year, from: dateEnd)
    }
    return when.yearOnlyYear  // user-picked year for year-only mode
}()
```

`WhenValue` gains a `yearOnlyYear: Int?` field used only by year-only mode (the year the user picked in the picker's year nav). When dateEnd is set, this field is ignored. Folder rename triggers when `derivedYear != project.year`, just like today's stepper-driven rename.

### `WhenFormatting`

Reduces from seven cases to three (year-only, range same year, range cross-year) plus the same-month collapse:

| state | format | example |
|--|--|--|
| year-only | `YYYY` | `2025` |
| range, same year, different months | `MMM — MMM YYYY` | `MAR — JUN 2025` |
| range, same year, same month | `MMM YYYY` | `MAR 2025` |
| range, cross-year | `MMM YYYY — MMM YYYY` | `SEP 2024 — FEB 2025` |

Day-precision branches are deleted.

### `ProjectSort`

Effective sort date for the within-year comparator:

- Range: `dateEnd`.
- Year-only: Jan 1 of the folder year — collapses these to the bottom of the band when other projects have explicit Whens. (Same as Rev 1.)

Day-precision branches are deleted.

### Migration / parser tolerance

No data migration runs. Existing project files on disk in any combination — legacy `date:` only, Rev 1 `date + dateEnd + datePrecision: month`, Rev 1 `date + datePrecision: day`, etc. — are loaded as follows:

- `dateEnd` present and parsable → range (use `date` as start, `dateEnd` as end).
- `dateEnd` absent → year-only (legacy `date:` is ignored for When but preserved on save).
- `datePrecision` is parsed and discarded (no struct field to populate). On save, the field is no longer written.

A user re-saves an old project once and the obsolete `datePrecision` line drops out of its frontmatter.

### Files touched (Rev 2)

| file | change |
|--|--|
| `Models/Project.swift` | remove `DatePrecision` enum and `datePrecision` property; keep `dateEnd`. |
| `Services/FrontmatterParser.swift` | remove `datePrecision` from `ParsedFrontmatter`; stop writing the YAML key on serialize; tolerate the key on parse (ignore). |
| `Services/WhenFormatting.swift` | reduce to three cases (year-only, range same/cross year, single-month collapse); drop day code. |
| `Services/ProjectSort.swift` | drop the `.month` and `.day` branches; effective sort date = `dateEnd ?? Jan 1 of folder year`. |
| `Services/ProjectMetadataMutation.swift` | replace `resolveYearChange` with logic that derives the new folder year from `WhenValue` instead of taking it as input. |
| `Services/ProjectMetadataCache.swift` | retain the existing `date_end_iso` column. The `date_precision` column is left in place but written as the empty string or `"range"` / `"year"` — pick one and document. (Easiest: stop writing the column from upsert; parser already tolerates legacy values.) |
| `App/AppState.swift` | `updateProjectMetadata` no longer accepts a `year:` parameter; the folder year is derived from the `WhenValue` passed in. The signature becomes `(project, title, client, status, tags, teaser, hidden, when)`. |
| `Views/WhenPicker.swift` | rewrite for two-mode toggle + Start/End fields. |
| `Views/ProjectSettingsPopover.swift` | drop YearStepper and the inline note; year is now an output of the picker. |
| `Views/EditorialCardView.swift` | unchanged from Rev 1 — uses `WhenFormatting.summaryString(...)`. |
| `Views/ProjectListView.swift` | unchanged from Rev 1 — uses `ProjectSort.sortedWithinYear(...)`. |
| Tests | update `WhenFormattingTests`, `ProjectSortTests`, `FrontmatterParserTests`, `ProjectMetadataMutationTests`, `ProjectMetadataCacheWhenTests` to the new shape. The existing tests that depend on `DatePrecision` are deleted or rewritten; the cache round-trip tests stay (the `date_end_iso` column survives). |

### Out of scope (Rev 2)

- Day-grain precision returns. (If we ever want it, reintroduce as a richer Range mode that takes day pickers.)
- A "Range with only one bound set" state (e.g. "Started Mar 2025 — ongoing"). For now Range requires both Start and End.
- Reordering year-only projects within the bottom of their band by anything other than alphabetical.
- Editing `WhenValue` from anywhere outside the picker (e.g. drag a card into a different year band on the overview).
