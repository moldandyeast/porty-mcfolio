# Branded Confirmation Sheet

**Date:** 2026-04-22
**Scope:** New `PortyMcFolio/Views/ConfirmationSheet.swift`; two call-site swaps in `PortyMcFolio/Views/GalleryView.swift`.

## Summary

Replace the two native `.alert(...)` modal dialogs in the gallery (Move-to-Trash delete confirmation and Rename-Folder text input) with a new branded `ConfirmationSheet` view that matches the app's existing modal-sheet language (`NewProjectSheet`, `CarouselReorderSheet`, `EditLinkSheet`).

The current `.alert` modifier uses system chrome — system font, system buttons, no theming — which reads as foreign against the porty/osx/bw theming everywhere else. This pass gives confirmations the same branded look as the rest of the app.

## Motivation

The app uses `@Environment(\.theme)` + `DT.Typography` / `DT.Spacing` / `DT.Radius` design tokens and ships three themes (porty, osx, bw). Every other piece of chrome — cards, buttons, sheets, pills — picks up the active theme. The two `.alert` dialogs are the only holdouts using raw system UI. The destructive delete confirmation in particular feels jarring because it sits inside a warmly-themed gallery but dresses like a stock macOS modal.

Rewriting as a branded sheet takes the existing modal-sheet pattern that already works in this app and applies it to confirmations — same backdrop, same width, same typography, same pill buttons.

## Scope

**In scope:**
- New `ConfirmationSheet<Content: View>` component with a `@ViewBuilder` middle slot.
- Support for destructive and non-destructive variants (red vs accent confirm button).
- Keyboard shortcuts: Return → confirm, Esc → cancel. TextField `.onSubmit` also confirms.
- Replace `.alert("Move to Trash?", ...)` at `GalleryView.swift:413` with a `.sheet` hosting `ConfirmationSheet`.
- Replace `.alert("Rename Folder", ...)` at `GalleryView.swift:419` with the same component.
- Auto-focus the TextField in the rename case on sheet appear.

**Out of scope:**
- Rewriting the error-alert path (`showAlert(title:message:)` helper, ~15 call sites). Error alerts stay system modals for now — they're rare, terse, and reworking them is scope creep.
- Adding a `theme.colors.destructive` token per theme. Using system `.red` for this pass; a future cleanup can wire a branded destructive color without changing the component's API.
- Replacing any other system UI (native file pickers, Quick Look, etc.) — those are system services, not ours to style.
- Undo-snackbar pattern for delete. Retaining explicit confirmation — different behavior, different conversation.

## Design

### Component: `ConfirmationSheet<Content: View>`

New file `PortyMcFolio/Views/ConfirmationSheet.swift`:

```swift
import SwiftUI

struct ConfirmationSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    let title: String
    let confirmLabel: String
    let isDestructive: Bool
    let onConfirm: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            Text(title)
                .font(DT.Typography.headline)
                .foregroundStyle(theme.colors.textPrimary)
                .padding(.bottom, DT.Spacing.md)

            // Caller-supplied middle slot (Text / TextField / etc.)
            content()
                .padding(.bottom, DT.Spacing.xl)

            // Buttons
            HStack(spacing: DT.Spacing.sm) {
                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(DT.Typography.body)
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(.horizontal, DT.Spacing.lg)
                        .padding(.vertical, DT.Spacing.sm)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Button {
                    onConfirm()
                    dismiss()
                } label: {
                    Text(confirmLabel)
                        .font(DT.Typography.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, DT.Spacing.lg)
                        .padding(.vertical, DT.Spacing.sm)
                        .background(
                            isDestructive ? Color.red : theme.colors.accent,
                            in: RoundedRectangle(cornerRadius: DT.Radius.small)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DT.Spacing.xl)
        .frame(width: 400)
        .background(theme.colors.surface)
    }
}
```

**Callers are responsible for the middle slot's styling.** That keeps the component YAGNI-pure — no "if text vs input" branches — and matches how `NewProjectSheet` lets its caller own the content layout. A caller that forgets the typography stands out visually, which is the right kind of feedback.

### Gallery call-site: delete confirmation

Replace the existing `.alert("Move to Trash?", ...)` at `GalleryView.swift:413` with:

```swift
.sheet(isPresented: $showDeleteConfirm) {
    ConfirmationSheet(
        title: "Move to Trash?",
        confirmLabel: "Move to Trash",
        isDestructive: true,
        onConfirm: {
            if let url = fileToDelete {
                trashFile(url)
            }
        }
    ) {
        if let url = fileToDelete {
            Text("\"\(url.lastPathComponent)\" will be moved to the Trash.")
                .font(DT.Typography.body)
                .foregroundStyle(theme.colors.textSecondary)
        }
    }
}
```

Behavior:
- Esc cancels (via `.keyboardShortcut(.cancelAction)`).
- Return confirms (via `.keyboardShortcut(.defaultAction)`).
- Red confirm button (destructive).
- The sheet reads `fileToDelete` lazily; dismissing the sheet does not clear `fileToDelete`, but the `showDeleteConfirm` binding goes false, so the presenter flag controls visibility. This matches the current `.alert` lifecycle (the state is reset the next time the user triggers a delete).

### Gallery call-site: rename folder

Replace the existing `.alert("Rename Folder", ...)` at `GalleryView.swift:419` with:

```swift
.sheet(isPresented: Binding(
    get: { folderToRename != nil },
    set: { if !$0 { folderToRename = nil } }
)) {
    RenameFolderSheet(
        name: $folderRenameText,
        onConfirm: { renameFolder() }
    )
}
```

**Subtlety with auto-focus inside a `@ViewBuilder` slot.** The rename case needs the TextField focused on sheet appear. `@FocusState` must be declared as a property on a view, not created inside a closure. Two ways:

1. **Inline the TextField into the caller's content closure AND hoist the @FocusState onto `GalleryView`.** Workable, but adds view-level state for a concern that belongs to the sheet.

2. **Wrap in a dedicated `RenameFolderSheet` view that owns its `@FocusState`.** Single-responsibility; caller just passes the binding and `onConfirm`.

Design picks (2) — define a small `RenameFolderSheet` in the same new file:

```swift
struct RenameFolderSheet: View {
    @Environment(\.theme) private var theme
    @FocusState private var isFocused: Bool

    @Binding var name: String
    let onConfirm: () -> Void

    var body: some View {
        ConfirmationSheet(
            title: "Rename Folder",
            confirmLabel: "Rename",
            isDestructive: false,
            onConfirm: onConfirm
        ) {
            TextField("Folder name", text: $name)
                .textFieldStyle(.plain)
                .font(DT.Typography.body)
                .foregroundStyle(theme.colors.textPrimary)
                .padding(DT.Spacing.sm)
                .background(
                    theme.colors.background,
                    in: RoundedRectangle(cornerRadius: DT.Radius.small)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.small)
                        .stroke(theme.colors.border, lineWidth: 0.5)
                )
                .focused($isFocused)
                .onSubmit(onConfirm)
                .onAppear { isFocused = true }
        }
    }
}
```

`onSubmit` makes the Return key submit from inside the TextField (otherwise the `.keyboardShortcut(.defaultAction)` on the underlying confirm button may not fire while the field has focus — depends on macOS SwiftUI version quirks; `.onSubmit` is the reliable path).

### Keyboard

Both sheets dismiss on Esc via the Cancel button's `.cancelAction` shortcut. Delete confirms on Return via the confirm button's `.defaultAction`. Rename confirms on Return via the TextField's `.onSubmit` (and the confirm button's `.defaultAction` as a fallback when focus is elsewhere).

### Theming

All colors come from `@Environment(\.theme)` except the destructive button background, which is system `Color.red`. In the porty theme the red reads as a warm crimson; in osx as system red; in bw still distinguishable from the mostly-monochrome palette. Acceptable across all three.

If a later pass wants a per-theme destructive red, add `destructive: Color` to `ThemeColors` and swap `Color.red` for `theme.colors.destructive`. One-line change; no API break.

### Backward compatibility

No data or persistence changes. State variables (`showDeleteConfirm`, `fileToDelete`, `folderToRename`, `folderRenameText`) are untouched — only the presentation modifier changes from `.alert` to `.sheet`. Call sites that set these state variables (context menus, key handlers) continue to work unchanged.

## Files touched

**New:**
- `PortyMcFolio/Views/ConfirmationSheet.swift` — `ConfirmationSheet<Content>` + `RenameFolderSheet` (~90 LOC total).

**Modified:**
- `PortyMcFolio/Views/GalleryView.swift` — replace two `.alert` blocks with two `.sheet` blocks (net ~0 LOC, same shape different presenter).
- `PortyMcFolio.xcodeproj/project.pbxproj` — regenerated by `xcodegen generate` to pick up the new Swift file.

**Not touched:** `project.yml`, entitlements, any other file.

## Testing

**No unit tests** for this change. `ConfirmationSheet` is a pure presentation view with no business logic; the project has no SwiftUI view tests by convention. Manual verification covers it.

**Manual verification checklist:**

- Open a project → gallery → right-click a file → Delete. Sheet appears with branded typography, message reads "\"filename\" will be moved to the Trash.", Cancel is plain text, Move-to-Trash button is red.
- Press Esc → sheet dismisses, file untouched.
- Press Return → file moves to Trash, sheet dismisses.
- Click Cancel → same as Esc.
- Click Move-to-Trash → same as Return.
- Right-click a folder → Rename. Sheet appears with a bordered text field pre-focused and pre-filled with the current name. Typing works; cursor is at the end (standard TextField behavior).
- Press Return while typing → rename confirms.
- Press Esc → sheet dismisses, folder unchanged.
- Rename sheet's Rename button is accent-colored (porty: orange; osx: blue; bw: black), NOT red.
- Test in all three themes — visual check for contrast and theme consistency.
- Keyboard-only: delete a file using only ⌘X context-menu-equivalent flow, confirm via Return / cancel via Esc. Same for rename.

## Rollout & revert

Strictly additive. Reverting the commit restores the two `.alert` blocks. No data migration, no user setting, no model change.

If the new sheet exhibits a SwiftUI layout bug in some future macOS version, fallback is to revert the one commit and ship — the `.alert` path still works in the Swift code it came from.
