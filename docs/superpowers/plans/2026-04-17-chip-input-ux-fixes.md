# Chip-input UX fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix three UX bugs in the chip-input fields (Client, Tags) used by the New-Project sheet and Project Settings popover: Tab should commit pending text + advance focus, clicking a suggestion should add the chip, and the Client field should have autocomplete sourced from existing projects.

**Architecture:** All three bugs live in one SwiftUI component (`TagChipInput`) and one piece of data (`AppState.suggestedClients`). Fix `TagChipInput` internally so every consumer benefits. Add a `suggestedClients` computed property mirroring `suggestedTags`, and wire it into the two call-sites that have a Client field.

**Tech Stack:** SwiftUI (macOS 14+), Swift 5.9, XcodeGen, XCTest. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-04-17-chip-input-ux-fixes-design.md`

**Testing approach:** The codebase has no unit tests for `TagChipInput` or `AppState.suggestedTags` (both UI / view-layer code that relies on `@MainActor` `AppState`). Matching that convention, this plan verifies via **manual checks against a dev build**. One small logic test is added for `suggestedClients` by extracting its pure logic as a `static` helper so it can be exercised without instantiating `AppState`.

---

## File Structure

**Modified:**
- `PortyMcFolio/Views/TagChipInput.swift` — add Tab handler; relax suggestions-panel visibility gate.
- `PortyMcFolio/App/AppState.swift` — add `suggestedClients` computed property (delegates to a static helper).
- `PortyMcFolio/Views/NewProjectSheet.swift` — pass `appState.suggestedClients` to the Client `TagChipInput`.
- `PortyMcFolio/Views/ProjectSettingsPopover.swift` — pass `appState.suggestedClients` to the Client `TagChipInput`.

**Created:**
- `PortyMcFolioTests/SuggestedClientsTests.swift` — unit test for the `suggestedClients` extraction logic.

---

## Task 1: Extract `suggestedClients` logic behind a testable static helper

**Files:**
- Modify: `PortyMcFolio/App/AppState.swift` (add computed property + static helper after `suggestedTags` around line 55)
- Create: `PortyMcFolioTests/SuggestedClientsTests.swift`

**Rationale:** `AppState` is `@MainActor` and binds to the full app lifecycle. Testing a pure computation through it is awkward. A `static` helper keeps the test trivial and matches how the rest of the codebase separates pure logic (`Slug`, `FrontmatterParser`, etc.) from stateful coordinators.

- [ ] **Step 1: Write the failing test**

Create `PortyMcFolioTests/SuggestedClientsTests.swift`:

```swift
import XCTest
@testable import PortyMcFolio

final class SuggestedClientsTests: XCTestCase {
    func testSplitsCommaJoinedClientsAndRanksByFrequency() {
        let projects = [
            makeProject(client: "Acme, Globex"),
            makeProject(client: "Acme"),
            makeProject(client: "Globex, Initech"),
            makeProject(client: "Acme"),
        ]

        let result = AppState.suggestedClients(from: projects)

        // Acme: 3, Globex: 2, Initech: 1
        XCTAssertEqual(result, ["Acme", "Globex", "Initech"])
    }

    func testTrimsWhitespaceAndSkipsEmpties() {
        let projects = [
            makeProject(client: "  Acme  ,  , Globex"),
            makeProject(client: ""),
            makeProject(client: "   "),
        ]

        let result = AppState.suggestedClients(from: projects)

        XCTAssertEqual(result, ["Acme", "Globex"])
    }

    // MARK: - helpers

    private func makeProject(client: String) -> Project {
        Project(
            uid: "aaaaaaaa",
            year: 2025,
            folderName: "2025_test_aaaaaaaa",
            folderURL: URL(fileURLWithPath: "/tmp/portfolio/2025_test_aaaaaaaa"),
            title: "Test",
            date: Date(),
            tags: [],
            client: client,
            status: .empty,
            body: "",
            teaser: ""
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run from the repo root:
```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/SuggestedClientsTests 2>&1 | tail -40
```
Expected: FAIL with a compile error along the lines of `type 'AppState' has no member 'suggestedClients'`.

- [ ] **Step 3: Add the static helper + computed property on `AppState`**

Edit `PortyMcFolio/App/AppState.swift`. Find the existing `suggestedTags` computed property (around line 47). Immediately after its closing brace, insert:

```swift
    /// All unique clients across projects, sorted by frequency (most used first).
    /// Multi-client project entries (stored as a comma-joined string) are split and counted individually.
    var suggestedClients: [String] {
        Self.suggestedClients(from: projects)
    }

    /// Pure extraction of `suggestedClients` for unit testing.
    static func suggestedClients(from projects: [Project]) -> [String] {
        var counts: [String: Int] = [:]
        for project in projects {
            let parts = project.client
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for c in parts {
                counts[c, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }
```

- [ ] **Step 4: Regenerate Xcode project so the new test file is picked up**

XcodeGen manages the `.xcodeproj`; new source files under `PortyMcFolioTests/` need a regen to be compiled.
```bash
xcodegen
```
Expected: `Created project at PortyMcFolio.xcodeproj`. No errors.

- [ ] **Step 5: Run test to verify it passes**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/SuggestedClientsTests 2>&1 | tail -40
```
Expected: `** TEST SUCCEEDED **`, both `testSplitsCommaJoinedClientsAndRanksByFrequency` and `testTrimsWhitespaceAndSkipsEmpties` pass.

- [ ] **Step 6: Run the full test suite to confirm no regressions**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add PortyMcFolio/App/AppState.swift PortyMcFolioTests/SuggestedClientsTests.swift PortyMcFolio.xcodeproj
git commit -m "feat: AppState.suggestedClients computed from existing projects"
```

---

## Task 2: Wire `suggestedClients` into the New-Project sheet

**Files:**
- Modify: `PortyMcFolio/Views/NewProjectSheet.swift` (line 53 — the Client `TagChipInput`)

- [ ] **Step 1: Pass the suggestions argument**

Find this block in `NewProjectSheet.swift` (around line 47–55):

```swift
            // Client
            VStack(alignment: .leading, spacing: DT.Spacing.xs) {
                Text("CLIENT")
                    .font(DT.Typography.micro)
                    .foregroundStyle(DT.Colors.textTertiary)
                    .tracking(1)

                TagChipInput(tags: $clients, placeholder: "Type and press Enter\u{2026}")
            }
```

Replace the `TagChipInput(...)` line with:

```swift
                TagChipInput(
                    tags: $clients,
                    placeholder: "Type and press Enter\u{2026}",
                    suggestions: appState.suggestedClients
                )
```

- [ ] **Step 2: Build to confirm it compiles**

```bash
xcodebuild build -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add PortyMcFolio/Views/NewProjectSheet.swift
git commit -m "feat: client suggestions in New Project sheet"
```

---

## Task 3: Wire `suggestedClients` into the Project Settings popover

**Files:**
- Modify: `PortyMcFolio/Views/ProjectSettingsPopover.swift` (line 38 — the Client `TagChipInput`)

- [ ] **Step 1: Pass the suggestions argument**

Find this block in `ProjectSettingsPopover.swift` (around line 36–39):

```swift
            // Client
            settingsField("CLIENT") {
                TagChipInput(tags: $clients, placeholder: "Add client\u{2026}")
            }
```

Replace the `TagChipInput(...)` line with:

```swift
                TagChipInput(
                    tags: $clients,
                    placeholder: "Add client\u{2026}",
                    suggestions: appState.suggestedClients
                )
```

- [ ] **Step 2: Build to confirm it compiles**

```bash
xcodebuild build -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add PortyMcFolio/Views/ProjectSettingsPopover.swift
git commit -m "feat: client suggestions in Project Settings popover"
```

---

## Task 4: Fix the suggestions-panel click race in `TagChipInput`

**Files:**
- Modify: `PortyMcFolio/Views/TagChipInput.swift` (line 52 — the visibility gate)

**Rationale:** Currently `if !filteredSuggestions.isEmpty && isInputFocused` means clicking a suggestion blurs the field → `isInputFocused` flips false → the panel hides before the button's action fires. `filteredSuggestions` is derived from `inputText`, which empties naturally when the user commits a chip or clears the field, so the `isInputFocused` gate is redundant and harmful.

- [ ] **Step 1: Relax the visibility gate**

Find this line in `TagChipInput.swift` (line 52):

```swift
            if !filteredSuggestions.isEmpty && isInputFocused {
```

Replace it with:

```swift
            if !filteredSuggestions.isEmpty {
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Launch the app and verify the click fix manually**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -configuration Debug -destination 'platform=macOS' build 2>&1 | tail -3
open build/Debug/PortyMcFolio.app 2>/dev/null || open -a PortyMcFolio
```

(If the app's build output lives elsewhere, launch it from Xcode with ⌘R instead.)

Manual checks:
1. Open the portfolio.
2. Press ⌘N to open the New Project sheet.
3. Click into **Tags**. Type a prefix matching an existing tag — the suggestions panel appears.
4. Click the first suggestion. **Expected:** the suggestion is added as a chip, the input clears, focus returns to the Tags field, the panel disappears on its own (because `inputText` is now empty).
5. In **Client**, type a prefix matching an existing client (any client from a project you already have). **Expected:** suggestions appear; clicking one adds the chip.

If step 4 or 5 shows the panel is still dismissed before the click lands, STOP. Note the observed behavior and revisit — the fallback would be `.onMouseDown` on the suggestion rows to capture the click before blur.

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Views/TagChipInput.swift
git commit -m "fix: suggestions panel swallowed click when input blurred"
```

---

## Task 5: Add Tab-to-commit in `TagChipInput`

**Files:**
- Modify: `PortyMcFolio/Views/TagChipInput.swift` (around line 43–49 — alongside the existing `.return` handler)

- [ ] **Step 1: Add the `.onKeyPress(.tab)` handler**

Find this block in `TagChipInput.swift` (around line 43–49):

```swift
                .onKeyPress(.return) {
                    if !inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                        addTag()
                        return .handled
                    }
                    return .ignored // empty field — let Enter propagate to Create/Save
                }
```

Add a new handler immediately after (before the closing `}` of the `TextField` modifier chain):

```swift
                .onKeyPress(.tab) {
                    if !inputText.trimmingCharacters(in: .whitespaces).isEmpty {
                        addTag()
                    }
                    // Always return .ignored so SwiftUI advances focus to the next field.
                    return .ignored
                }
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Launch and verify Tab behavior manually**

Run the app (Xcode ⌘R, or re-launch the built binary).

Manual checks:

1. Open the New Project sheet (⌘N).
2. Enter a title, Tab into Client. Type `Acme`. Press **Tab**. **Expected:** an `Acme` chip appears in Client, *and* focus is now in Tags. (Looking at the field to confirm focus moved is enough — a cursor is in the Tags input.)
3. Type `branding`. Press **Tab**. **Expected:** chip appears in Tags, focus moves to whatever comes next in the tab order (likely the Cancel / Create buttons or the title field).
4. With an empty Client field, press Tab. **Expected:** no empty chip is created, focus still advances.
5. Regression: type `foo` in Tags and press **Enter**. **Expected:** chip added, focus stays in Tags (existing behavior).
6. Regression: type `a,b,c,` in Tags. **Expected:** three chips. (Existing comma behavior.)
7. Regression: with Tags input empty, press **Enter**. **Expected:** default action fires (the sheet attempts to Create, as long as title is valid).
8. Open an existing project's Settings popover (the ⋯ or equivalent). Repeat checks 2–4 for its Client and Tags fields.

If step 2's focus does NOT advance (chip appears but cursor stays in Client), the SwiftUI `.ignored` return didn't propagate focus — implement the fallback: explicit focus advancement via `@FocusState` in `NewProjectSheet` (already has a `Field` enum) and `ProjectSettingsPopover` (add one). Exposing a new callback from `TagChipInput` such as `onTabPressed: (() -> Void)?` and calling it after `addTag()` keeps the component self-contained.

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Views/TagChipInput.swift
git commit -m "feat: Tab commits chip and advances focus in TagChipInput"
```

---

## Task 6: Final verification sweep

**Goal:** confirm the whole spec is satisfied end-to-end in one run.

- [ ] **Step 1: Run the full test suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 2: Launch the app and walk through every acceptance criterion from the spec**

Re-run the manual checklist. Every item must pass:

1. **Tab commits + advances.** Client → type `Acme` → Tab → chip appears, focus moves to Tags.
2. **Tab on empty field.** Focus Client, empty → Tab → no empty chip, focus advances.
3. **Enter still commits in place.** Tags → type, Enter → chip, focus stays.
4. **Comma still commits.** `foo,bar,` → two chips.
5. **Click suggestion adds chip.** Tags → type prefix → click suggestion → chip added.
6. **Client suggestions appear on type.** New Project sheet → Client → type prefix → suggestions list.
7. **Client suggestions in Settings popover.** Same check in the per-project Settings.
8. **Create button still works.** Fill title → Enter in title → project created.

- [ ] **Step 3: If anything failed, STOP and debug before claiming completion.**

Use the `superpowers:systematic-debugging` skill.

- [ ] **Step 4: No final commit needed** — each task committed its own changes.

---

## Spec coverage check

| Spec requirement | Task |
|---|---|
| Tab commits pending text | Task 5 |
| Tab advances focus | Task 5 (+ fallback if `.ignored` doesn't propagate) |
| Click on suggestion adds chip | Task 4 |
| Client field has autocomplete suggestions | Task 2 (New Project), Task 3 (Settings popover), Task 1 (data source) |
| Existing Enter / comma / Create behavior preserved | Task 5 Step 3 regression checks, Task 6 final sweep |
