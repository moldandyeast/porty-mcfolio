# Chip-input UX fixes

Date: 2026-04-17
Status: Draft

## Problem

Three related UX bugs in the Client / Tags chip-input fields used by the New-Project sheet and the Project Settings popover:

1. **Tab discards pending text.** When a user types a client or tag and presses Tab to move to the next field, whatever they typed is lost — `TagChipInput` only commits on Enter or comma.
2. **Clicking a suggestion does nothing.** When the autocomplete panel is visible and the user clicks a suggestion, the chip is not added. The likely cause is a focus/blur race: clicking the suggestion blurs the `TextField`, which flips `isInputFocused` to false, which hides the panel before the click registers on the button.
3. **Client field has no suggestions.** Only the Tags chip-input is passed `suggestions:`. The Client field has no autocomplete, even though users re-type the same client names repeatedly.

## Goals

- Tab commits pending text as a chip *and* advances focus, in one keystroke.
- Clicking a suggestion reliably adds that suggestion as a chip.
- The Client field shows autocomplete suggestions sourced from existing projects, ranked by frequency — matching the Tags field's behavior.

## Non-goals

- Showing suggestions before the user types (empty-state suggestions list). Can be revisited later.
- Introducing a general `SuggestionSource` abstraction across the app. Two call-sites don't justify it yet.
- Any changes to the non-chip fields (title, year, status, teaser).

## Design

### 1. Tab-to-commit in `TagChipInput`

Add an `.onKeyPress(.tab)` handler to the input `TextField` alongside the existing `.return` handler:

- If the input has non-whitespace content, call `addTag()` and return `.ignored` so SwiftUI continues with normal focus advancement.
- If the input is empty, return `.ignored` — Tab behaves as it does today.

This gives the user one-Tab-does-both semantics (commit + advance) while preserving native Tab behavior when the field is empty.

**Risk:** On rare SwiftUI focus quirks, `.ignored` may not propagate focus advancement cleanly. Fallback: advance focus explicitly from each parent using its existing `@FocusState`. `NewProjectSheet` already has a `Field` enum and `@FocusState` wiring; `ProjectSettingsPopover` would need to add one. Only done if the simple approach doesn't work in practice.

### 2. Click-on-suggestion fix

Change the suggestions panel's visibility gate from:

```swift
if !filteredSuggestions.isEmpty && isInputFocused { … }
```

to:

```swift
if !filteredSuggestions.isEmpty { … }
```

Rationale: `filteredSuggestions` is derived from `inputText` — it naturally empties when the user clears the field, commits a chip, or deletes the last character. Removing the `isInputFocused` gate eliminates the blur-before-click race without needing special-case focus handling or `.onMouseDown` tricks.

The panel will stay visible briefly if the user clicks somewhere outside the field while typed text remains. In practice the user either clicks a suggestion (desired), clicks back into the field (panel stays, fine), or clicks Create/Cancel (sheet dismisses, moot). If this proves annoying we add an explicit dismiss-on-commit later.

### 3. Client suggestions

Add a computed property to `AppState` that mirrors `suggestedTags`, but splits each project's `client` string on commas (since `Project.client` is a single `String` that multi-client entries join with `", "`):

```swift
var suggestedClients: [String] {
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

Wire this into both chip-inputs:

- `NewProjectSheet.swift:53` — pass `suggestions: appState.suggestedClients` to the Client `TagChipInput`.
- `ProjectSettingsPopover.swift:38` — same.

## Files touched

- `PortyMcFolio/Views/TagChipInput.swift` — add `.onKeyPress(.tab)`, relax visibility gate.
- `PortyMcFolio/App/AppState.swift` — add `suggestedClients` computed property.
- `PortyMcFolio/Views/NewProjectSheet.swift` — pass suggestions to Client field.
- `PortyMcFolio/Views/ProjectSettingsPopover.swift` — pass suggestions to Client field.

## Testing plan

Manual verification (XCTest coverage for `TagChipInput` is thin; no unit tests will be added unless a Tab-key regression test is straightforward to write):

1. **Tab commits + advances.** New Project sheet → type "Acme" in Client → press Tab → Acme chip appears *and* focus is now in Tags.
2. **Tab on empty field.** New Project sheet → focus Client, leave empty → press Tab → focus moves to Tags, no empty chip created.
3. **Enter still works.** Type in Tags → Enter → chip appears, stays in field. (Regression check.)
4. **Comma still works.** Type "foo,bar," in Tags → two chips appear. (Regression check.)
5. **Click suggestion.** In Tags, type a prefix matching an existing tag → click the suggestion → chip added, input cleared, focus stays in Tags.
6. **Client suggestions appear.** New Project sheet, with existing projects that have clients → type a prefix → matching clients appear as suggestions.
7. **Client suggestions in settings popover.** Same check inside `ProjectSettingsPopover`.
8. **Create button still works.** Fill title → press Enter in title → project created. Fill tags, press Enter in Tags with empty input → default action fires (Create).

## Risks

- SwiftUI `.onKeyPress(.tab)` + `.ignored` focus behavior: minor risk it doesn't advance focus on macOS 14. Mitigation covered in Design §1.
- Relaxed visibility gate could surprise users with a lingering panel. Mitigation discussed in Design §2; if real, add explicit dismiss-on-commit.
