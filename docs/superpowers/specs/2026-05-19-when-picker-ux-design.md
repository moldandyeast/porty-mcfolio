# WhenPicker UX improvements

## Goal

Make project date selection in NewProject and Project Settings feel less
annoying. Two targeted improvements:

1. **Year-only mode** — keyboard `←` / `→` step the year (parity with the
   stand-alone `YearStepper` component used elsewhere in the app).
2. **Range mode** — bootstrap from "now" instead of `Jan 1 → Jan 31 of
   carry-over year`.

Both sheets — `NewProjectSheet` and `ProjectSettingsPopover` — use the
same `WhenPicker.swift`. One file changes, both screens benefit.

## Scope

In scope (`PortyMcFolio/Views/WhenPicker.swift`):

- Replace the inline `‹ YYYY ›` year-only nav with the existing
  `YearStepper` component (`PortyMcFolio/Views/YearStepper.swift`).
- Change the range-mode bootstrap math in `modeToggle.Range` action.

Out of scope (deliberately):

- Range body's inline month picker year nav — chevrons stay click-only.
  (Approach 3 deferred.)
- Visual styling of WhenPicker outside the year area.
- Any change to `WhenValue` model, `WhenFormatting`, or persistence.
- Any change to NewProjectSheet or ProjectSettingsPopover (callers stay
  the same — `WhenPicker(value: $when)`).

## Changes

### A. Year-only mode uses `YearStepper`

`yearOnlyBody` currently renders an inline HStack: `‹ button`, monospaced
year text, `› button`, all wrapped in a `backgroundAlt` rounded rect. No
keyboard support.

Replace the HStack with a `YearStepper` bound to a computed `Binding<Int>`
that reads/writes `value.yearOnlyYear` (with current-year fallback when
nil):

```swift
private var yearOnlyBinding: Binding<Int> {
    Binding(
        get: { value.yearOnlyYear ?? calendar.component(.year, from: Date()) },
        set: { newYear in
            value = WhenValue.yearOnly(year: newYear, anchor: value.date)
        }
    )
}
```

`YearStepper` already provides:

- `←` / `→` arrow-key stepping when focused
- Tap-to-edit (type a year directly, Enter to commit, bounds-checked)
- 1337–2310 bounds with disabled chevron styling at edges
- `.iconButton()`-styled chevrons + accent focus ring

The "Project filed under YYYY." caption row stays unchanged.

`stepYearOnlyYear(by:)` becomes unused — delete it.

Auto-focus: `YearStepper` is `.focusable(!isEditing)` but has no auto-focus
on appear. To make `←`/`→` work the moment the popover opens, wrap the
year-only body in a `.defaultFocus()`-marked container (macOS 14+, already
in deployment target). If `.defaultFocus()` proves flaky in a popover, fall
back to a `@FocusState` toggled in `.onAppear`.

### B. Range bootstrap from current month

`modeToggle`'s Range button currently runs:

```swift
let yr = value.yearOnlyYear ?? calendar.component(.year, from: Date())
let start = calendar.date(from: DateComponents(year: yr, month: 1, day: 1))!
let end = lastDay(of: 1, year: yr)
value = WhenValue(date: start, dateEnd: end, yearOnlyYear: nil)
activeField = .end
```

Replace with:

```swift
let now = Date()
let currentYear = calendar.component(.year, from: now)
let currentMonth = calendar.component(.month, from: now)
let firstOfCurrent = calendar.date(from: DateComponents(year: currentYear, month: currentMonth, day: 1))!
let firstOfPrev = calendar.date(byAdding: .month, value: -1, to: firstOfCurrent)!

value = WhenValue(
    date: firstOfPrev,
    dateEnd: lastDay(of: currentMonth, year: currentYear),
    yearOnlyYear: nil
)
activeField = .end
```

Behavior: opening on May 19, 2026 → range = `APR 2026 → MAY 2026`. The
year-only carry-over is intentionally dropped; "now" is the better default
than "year you happened to be on".

January edge case: previous month becomes December of (current year − 1).
`calendar.date(byAdding: .month, value: -1, ...)` handles year rollover.

## Edge cases

- **Reopening a project already in Range mode**: no change — we only touch
  the bootstrap path, which only runs when the user actively toggles from
  Year-only to Range. Existing range values stay put.
- **Year bounds in YearStepper**: 1337–2310. If a stored `yearOnlyYear` is
  somehow outside this range, the binding reads it correctly but the user
  can't increment past the bound. Treat this as a future-data-cleanup
  concern, not blocking.
- **Empty `yearOnlyYear`**: binding falls back to current year. Writing
  through the binding creates a `.yearOnly(year:anchor:)` with that year.
- **Popover focus**: if `.defaultFocus()` doesn't reliably grab focus in a
  popover on macOS 14, fall back to a `@FocusState` bound from the popover
  parent and set it in `.onAppear` of `yearOnlyBody`. Verified manually.

## Tests

- Add a unit test asserting the new Range-bootstrap math for a frozen
  `now` (parametrize over months including January → December rollover and
  a generic mid-year month). Test lives next to the existing
  `WhenFormattingTests` — same area of code.
- No unit test for the keyboard interaction itself (covered by manual
  verification — `←`/`→` are AppKit key events, awkward to test
  headless).

## Acceptance criteria

1. Opening WhenPicker in year-only mode, `←` / `→` step the year by 1
   without clicking. Chevron buttons still work.
2. Toggling Year-only → Range produces a range whose End year-month is
   the current year-month and whose Start year-month is one month prior.
3. Existing range projects open unchanged.
4. All existing tests pass; one new test covers the bootstrap math.
5. NewProjectSheet and ProjectSettingsPopover require no source changes.

## Out of scope (revisit later if still annoying)

- Arrow nav inside Range body's month picker year header.
- Keyboard nav across modeToggle (Year-only ↔ Range).
- Direct typing of dates in Range fields.
