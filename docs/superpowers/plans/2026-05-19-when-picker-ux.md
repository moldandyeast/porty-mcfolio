# WhenPicker UX Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make project date selection less annoying — keyboard arrow nav in year-only mode (via reused `YearStepper`), and Range mode that bootstraps from the current month instead of `Jan 1 → Jan 31` of a carry-over year.

**Architecture:** All changes live in `PortyMcFolio/Views/WhenPicker.swift` plus one new static helper on `WhenValue`. The bootstrap math is extracted into a pure function (`WhenValue.rangeBootstrap(from:)`) so it's unit-testable. Year-only nav delegates to the existing `YearStepper` component, deleting ~30 lines of duplicate UI code.

**Tech Stack:** SwiftUI (macOS 14+), AppKit `NSTextView` adjacent, XCTest, XcodeGen.

**Spec:** [docs/superpowers/specs/2026-05-19-when-picker-ux-design.md](../specs/2026-05-19-when-picker-ux-design.md)

---

### Task 1: Add `WhenValue.rangeBootstrap(from:)` (TDD)

**Files:**
- Modify: `PortyMcFolio/Models/Project.swift` (extend `WhenValue` near the existing `static func yearOnly`)
- Test: `PortyMcFolioTests/WhenValueRangeBootstrapTests.swift` (new)

- [ ] **Step 1: Write the failing tests**

Create `PortyMcFolioTests/WhenValueRangeBootstrapTests.swift`:

```swift
import XCTest
@testable import PortyMcFolio

final class WhenValueRangeBootstrapTests: XCTestCase {

    private var utcCal: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func makeDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utcCal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func test_midYear_startIsFirstOfPrevMonth_endIsLastOfCurrentMonth() {
        let now = makeDate(2026, 5, 19)
        let v = WhenValue.rangeBootstrap(from: now)
        XCTAssertEqual(v.date, makeDate(2026, 4, 1))
        XCTAssertEqual(v.dateEnd, makeDate(2026, 5, 31))
        XCTAssertNil(v.yearOnlyYear)
    }

    func test_january_rollsBackToDecemberOfPriorYear() {
        let now = makeDate(2026, 1, 15)
        let v = WhenValue.rangeBootstrap(from: now)
        XCTAssertEqual(v.date, makeDate(2025, 12, 1))
        XCTAssertEqual(v.dateEnd, makeDate(2026, 1, 31))
    }

    func test_december_endIsDec31() {
        let now = makeDate(2026, 12, 7)
        let v = WhenValue.rangeBootstrap(from: now)
        XCTAssertEqual(v.date, makeDate(2026, 11, 1))
        XCTAssertEqual(v.dateEnd, makeDate(2026, 12, 31))
    }

    func test_february_endIsLastDayOfFebruary_nonLeap() {
        let now = makeDate(2026, 2, 10)
        let v = WhenValue.rangeBootstrap(from: now)
        XCTAssertEqual(v.date, makeDate(2026, 1, 1))
        XCTAssertEqual(v.dateEnd, makeDate(2026, 2, 28))
    }

    func test_february_endIsLastDayOfFebruary_leap() {
        let now = makeDate(2024, 2, 10)
        let v = WhenValue.rangeBootstrap(from: now)
        XCTAssertEqual(v.date, makeDate(2024, 1, 1))
        XCTAssertEqual(v.dateEnd, makeDate(2024, 2, 29))
    }
}
```

- [ ] **Step 2: Add the file to the test target and run — should fail (no `rangeBootstrap`)**

Run:

```bash
cd ~/Documents/porty-mcfolio && \
  xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -configuration Debug -derivedDataPath build/DerivedData \
  -only-testing:PortyMcFolioTests/WhenValueRangeBootstrapTests test 2>&1 | tail -20
```

Expected: build fails with `cannot find 'rangeBootstrap' in type 'WhenValue'`. (XcodeGen auto-includes new files matching `PortyMcFolioTests/**/*.swift` per `project.yml`, so no project regen is needed; if Xcode reports the file isn't in the target, run `xcodegen generate` and retry.)

- [ ] **Step 3: Implement `rangeBootstrap` on `WhenValue`**

In `PortyMcFolio/Models/Project.swift`, immediately below the existing `static func yearOnly(...)` (line 34) inside the `WhenValue` struct, add:

```swift
    /// Bootstrap a Range from a reference date.
    /// Start = first day of (now − 1 month). End = last day of (now's month).
    /// Year rollover (e.g. January → December of prior year) handled by Calendar.
    static func rangeBootstrap(from now: Date) -> WhenValue {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let y = cal.component(.year, from: now)
        let m = cal.component(.month, from: now)
        let firstOfCurrent = cal.date(from: DateComponents(year: y, month: m, day: 1))!
        let firstOfPrev = cal.date(byAdding: .month, value: -1, to: firstOfCurrent)!
        let firstOfNext = cal.date(from: DateComponents(year: y, month: m + 1, day: 1))!
        let lastOfCurrent = cal.date(byAdding: .day, value: -1, to: firstOfNext)!
        return WhenValue(date: firstOfPrev, dateEnd: lastOfCurrent, yearOnlyYear: nil)
    }
```

- [ ] **Step 4: Re-run the tests — all five pass**

Run:

```bash
cd ~/Documents/porty-mcfolio && \
  xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -configuration Debug -derivedDataPath build/DerivedData \
  -only-testing:PortyMcFolioTests/WhenValueRangeBootstrapTests test 2>&1 | tail -10
```

Expected: `Executed 5 tests, with 0 failures` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/porty-mcfolio && \
  git add PortyMcFolio/Models/Project.swift PortyMcFolioTests/WhenValueRangeBootstrapTests.swift && \
  git commit -m "$(cat <<'EOF'
feat(when): add WhenValue.rangeBootstrap from reference date

Pure helper that produces a Range anchored at "now": Start = first day
of prev month, End = last day of current month. Tested for mid-year,
January (year rollover), December, and February (leap + non-leap).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Wire `WhenPicker` Range button to the helper

**Files:**
- Modify: `PortyMcFolio/Views/WhenPicker.swift:96-104` (inside `modeToggle`, the `modeButton(title: "Range", ...)` action closure)

- [ ] **Step 1: Replace the Range action body**

In `PortyMcFolio/Views/WhenPicker.swift`, the existing Range button action reads:

```swift
            modeButton(title: "Range", isActive: value.isRange) {
                guard !value.isRange else { return }
                // Bootstrap a range from the current year-only year.
                let yr = value.yearOnlyYear ?? calendar.component(.year, from: Date())
                let start = calendar.date(from: DateComponents(year: yr, month: 1, day: 1))!
                let end = lastDay(of: 1, year: yr)
                value = WhenValue(date: start, dateEnd: end, yearOnlyYear: nil)
                activeField = .end
            }
```

Replace with:

```swift
            modeButton(title: "Range", isActive: value.isRange) {
                guard !value.isRange else { return }
                value = WhenValue.rangeBootstrap(from: Date())
                activeField = .end
            }
```

- [ ] **Step 2: Build to confirm it compiles**

Run:

```bash
cd ~/Documents/porty-mcfolio && \
  xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -configuration Debug -derivedDataPath build/DerivedData build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manually verify in the app**

Run:

```bash
pkill -x PortyMcFolio 2>/dev/null; sleep 0.3; \
  open /Users/rm/Documents/porty-mcfolio/build/DerivedData/Build/Products/Debug/PortyMcFolio.app
```

In the app:
1. Open a project's Settings or click "+" for New Project.
2. Click the When picker → it opens in Year-only.
3. Click "Range".
4. Confirm: Start row shows the previous month/year; End row shows the current month/year.

If today is May 19, 2026: Start = `APR 2026`, End = `MAY 2026`.

- [ ] **Step 4: Commit**

```bash
cd ~/Documents/porty-mcfolio && \
  git add PortyMcFolio/Views/WhenPicker.swift && \
  git commit -m "$(cat <<'EOF'
fix(when-picker): bootstrap Range from current month, not carry-over year

Toggling Year-only → Range was producing Jan 1 → Jan 31 of the year the
user happened to be on. The common case is "I just finished a project,"
so default to (prev month → current month) instead. Delegates to the
tested WhenValue.rangeBootstrap helper.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Replace year-only nav with `YearStepper`

**Files:**
- Modify: `PortyMcFolio/Views/WhenPicker.swift` (`yearOnlyBody`, `stepYearOnlyYear`, focus state)

- [ ] **Step 1: Add a `@FocusState` for the year-only stepper**

In `PortyMcFolio/Views/WhenPicker.swift`, near the existing `@State private var activeField`, add:

```swift
    @FocusState private var yearOnlyFocused: Bool
```

- [ ] **Step 2: Replace `yearOnlyBody` with a `YearStepper`-backed version**

Find the existing `yearOnlyBody` (around line 128) and the helper `stepYearOnlyYear(by:)` (around line 156). Replace both with:

```swift
    private var yearOnlyBody: some View {
        VStack(spacing: DT.Spacing.md) {
            YearStepper(year: yearOnlyBinding)
                .focused($yearOnlyFocused)
                .onAppear { yearOnlyFocused = true }

            Text("Project filed under \(String(displayYear)).")
                .font(DT.Typography.caption)
                .foregroundStyle(theme.colors.textTertiary)
                .frame(maxWidth: .infinity)
        }
    }

    private var yearOnlyBinding: Binding<Int> {
        Binding(
            get: { value.yearOnlyYear ?? calendar.component(.year, from: Date()) },
            set: { newYear in
                value = WhenValue.yearOnly(year: newYear, anchor: value.date)
            }
        )
    }
```

Why `.focused($yearOnlyFocused) + .onAppear`: `YearStepper`'s internal `@FocusState` is private, so we can't reach it. Wrapping with our own `.focused(...)` binding and toggling it on appear is the smallest reliable way to grab keyboard focus when the popover opens.

- [ ] **Step 3: Build**

Run:

```bash
cd ~/Documents/porty-mcfolio && \
  xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -configuration Debug -derivedDataPath build/DerivedData build 2>&1 | tail -8
```

Expected: `** BUILD SUCCEEDED **`. If you see "value of type 'YearStepper' has no member 'focused'", it does — `.focused(_:)` is on `View`, not the type — re-check copy-paste.

- [ ] **Step 4: Manually verify in the app**

Run:

```bash
pkill -x PortyMcFolio 2>/dev/null; sleep 0.3; \
  open /Users/rm/Documents/porty-mcfolio/build/DerivedData/Build/Products/Debug/PortyMcFolio.app
```

Open any project's When picker (Settings or New Project). In Year-only mode:

1. Without clicking anywhere in the popover first, press `←` — year decrements by 1.
2. Press `→` repeatedly — year increments, capped at 2310 (chevron dims).
3. Click the year text — TextField appears; type `1999`, press Enter — year becomes 1999.
4. Press `←` again — year becomes 1998.
5. Close popover, reopen — year is 1998 (round-tripped through `WhenValue`).

Toggle to Range and back to Year-only:
6. Range bootstraps to prev-month → current-month (Task 2 still working).
7. Toggling back to Year-only restores a sensible year (whichever `WhenValue.yearOnly` resolves from the range's `dateEnd`).

- [ ] **Step 5: Run full test suite to confirm no regressions**

Run:

```bash
cd ~/Documents/porty-mcfolio && \
  xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -configuration Debug -derivedDataPath build/DerivedData test 2>&1 | tail -8
```

Expected: `Executed 434 tests, with 0 failures` (429 existing + 5 new from Task 1). `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/porty-mcfolio && \
  git add PortyMcFolio/Views/WhenPicker.swift && \
  git commit -m "$(cat <<'EOF'
feat(when-picker): year-only mode uses YearStepper (keyboard arrows + tap-to-edit)

Replaces ~30 LOC of inline chevron+text duplication with the existing
YearStepper. Popover auto-focuses the stepper on appear so ←/→ work
immediately without an extra click.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Push

**Files:** none (deploy step)

- [ ] **Step 1: Push commits to origin**

Run:

```bash
cd ~/Documents/porty-mcfolio && git push
```

Expected: three commits pushed to `main` (one per Task 1–3).

---

## Spec coverage check

- Spec §A "Year-only mode uses YearStepper" → Task 3 ✓
- Spec §A auto-focus fallback → Task 3 uses `@FocusState + .onAppear` directly (skipped `.defaultFocus()` since the FocusState approach is more reliable in popovers) ✓
- Spec §B "Range bootstrap from current month" → Task 1 (helper + tests) + Task 2 (wiring) ✓
- Spec "Tests" section → Task 1 covers mid-year, January, December, Feb leap/non-leap ✓
- Spec "Acceptance criteria" 1 (arrow nav) → Task 3 manual verification step 4.1–4.2
- Spec "Acceptance criteria" 2 (range default) → Task 2 manual verification + Task 1 unit tests
- Spec "Acceptance criteria" 3 (existing range projects unchanged) → guarded by `guard !value.isRange else { return }` in Task 2's action closure
- Spec "Acceptance criteria" 4 (tests pass + new test) → Task 3 step 5
- Spec "Acceptance criteria" 5 (NewProject/Settings unchanged) → no callers modified
