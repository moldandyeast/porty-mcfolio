# In-Project Onboarding — Design

> Spec date: 2026-04-29

## Goal

When a user enters a project for the very first time, surface a one-time primer that explains the six view modes (Editor / Preview / Editor+Gallery / Editor+List / Editor+Links / Carousel) and how to switch between them, so the toolbar's icon group becomes immediately legible.

The toolbar already exposes these modes as icon buttons with hover tooltips; this spec adds the missing affordance — *what they are and when to use which* — at the moment a user can act on the information.

## Non-goals

- Coach marks pointing at individual toolbar buttons (richer but layout-fragile in SwiftUI)
- A reset / "show me again" affordance (Settings → Manual → Getting Started is the canonical re-read)
- Per-feature mini-tours elsewhere in the app (Gallery, Links, Carousel, Settings — all separate concerns)
- Empty-project pedagogy (a different trigger, possible future revision)
- Tracking *which* modes the user has tried; the primer is single-shot, not adaptive

## Trigger

A new persisted flag `hasSeenProjectOnboarding: Bool` lives on `AppState`, default `false`, written to UserDefaults via `didSet` and restored in `loadLayoutPreferences()`. Pattern mirrors `hideHiddenProjects` (`AppState.swift:52`).

The primer appears on `ProjectDetailView` whenever `appState.hasSeenProjectOnboarding == false`. It does **not** care whether the project has body / files / links — first-ever project entry is the trigger, regardless of project content. After dismissal the flag flips to `true` and the primer never reappears.

A user who upgrades the app with the flag absent (no key in UserDefaults yet) sees the primer once on their next project entry. This is acceptable for v1 — existing users get the same one-time learning moment as new users.

## Visual

A new SwiftUI view `ProjectOnboardingPrimerView` in `PortyMcFolio/Views/`. Layout mirrors `WelcomePrimerView`:

- **Eyebrow:** "WELCOME TO YOUR FIRST PROJECT" — `DT.Typography.micro`, `theme.colors.textTertiary`, tracked.
- **Title:** "Switch views to work different ways" — same heading token as `WelcomePrimerView`'s title.
- **Six rows.** Each row: SF Symbol (matching the toolbar icon) + name + keyboard shortcut on the right + one-line description below the name. Specifically:

| SF Symbol | Mode | Shortcut | Description |
|-----------|------|----------|-------------|
| `doc.text` | Editor | ⌘1 | Write the markdown that describes the work |
| `eye` | Preview | ⌘2 | Rendered markdown with embeds and link cards |
| `square.grid.2x2` | Editor + Gallery | ⌘3 | Editor and your media side-by-side |
| `list.bullet` | Editor + List | ⌘4 | Editor and a sortable file list |
| `link` | Editor + Links | ⌘5 | Editor and saved links |
| `rectangle.stack.badge.play` | Carousel | ⌘6 | Full-screen slideshow of favorites |

- **Footer line:** "All shortcuts in Settings → Manual → Keyboard Shortcuts." — `DT.Typography.caption`, `theme.colors.textTertiary`. Quiet, just a pointer.
- **CTA:** filled "Got it" button — same style as `WelcomePrimerView`'s "Create your first project" (theme accent background, accentForeground label).

### Visual tokens

- Card container: `RoundedRectangle(cornerRadius: DT.Radius.medium)` filled with `theme.colors.backgroundAlt`, stroked with `theme.colors.border` at 1pt. (Matches the visibility-fixed `WelcomePrimerView`.)
- Card max width: ~480pt (slightly wider than the welcome primer's 420 to fit the row layout with shortcut hints).
- Internal padding: `DT.Spacing.xl`.
- Each row: `HStack` with leading SF Symbol (16pt size), name + description in a leading `VStack`, trailing keyboard-shortcut chip styled like the existing `shortcutRow` helper in `AppSettingsView` (monospaced caption inside a small `backgroundAlt` rounded rect).

## Presentation

Mounted as an `.overlay` on `ProjectDetailView`'s body, local to the project detail surface. Backdrop is `Color.black.opacity(0.2).ignoresSafeArea()` — same dimming used by `ContentView`'s search palette overlay (`ContentView.swift:24`). Card is centered.

Mounting it on `ProjectDetailView` rather than at `ContentView` level keeps the responsibility scoped: the search palette and the welcome primer don't have to know about it, and any future per-surface onboarding stays isolated.

```swift
.overlay {
    if !appState.hasSeenProjectOnboarding {
        ProjectOnboardingPrimerView(onDismiss: dismissOnboarding)
    }
}
```

The view animates in/out via `.transition(.opacity)` matching the existing search-palette pattern.

## Dismissal

Three paths, all setting `appState.hasSeenProjectOnboarding = true`:

1. **"Got it" button** — explicit confirm.
2. **Click on the dimmed backdrop** — escape via tap-outside.
3. **Esc key** — keyboard escape.

All three route through one `dismissOnboarding()` method on `ProjectDetailView`. The Esc path is wired via the same hidden-button pattern used in `ContentView` for ⌘K (`Button("") { dismiss }.keyboardShortcut(.escape, modifiers: []).opacity(0)`).

## Files affected

- **New:** `PortyMcFolio/Views/ProjectOnboardingPrimerView.swift` — pure presentation, takes `onDismiss: () -> Void`. ~80 lines, similar shape to `WelcomePrimerView`.
- **Modified:** `PortyMcFolio/Views/ProjectDetailView.swift` — adds the `.overlay`, the `dismissOnboarding()` method, and the Esc keyboard-shortcut hidden button.
- **Modified:** `PortyMcFolio/App/AppState.swift` — adds `hasSeenProjectOnboarding` `@Published` with `didSet` UserDefaults write; restore block in `loadLayoutPreferences()` (just before `restoreSortOrder()` to match the `hideHiddenProjects` placement).
- **New test:** `PortyMcFolioTests/AppStateProjectOnboardingPersistenceTests.swift` — round-trip test for the flag, parallels `AppStateHideHiddenPersistenceTests`.

## Testing

Per the project's "no SwiftUI view tests" convention:

- **State persistence:** unit test confirming `hasSeenProjectOnboarding` round-trips through UserDefaults — three tests (writes-on-set, restores-stored-value, no-stored-keeps-default), same shape as the existing persistence test.
- **Manual smoke:** clear the flag → enter a project → primer appears centered, six rows readable in light + dark, all three themes → dismiss via each path → flag persists in UserDefaults → re-entering a project never re-shows the primer.

## Open considerations (acknowledged, not blocking)

- The flag is global — every user on this Mac shares it. If someone wants to demo the app to a colleague, they can clear the UserDefaults key manually. Acceptable for a single-user macOS app.
- A user who creates and immediately discards their first project still has the flag set after dismissal, even if they never came back to a project. They've seen the primer; that's the contract. Fine.
- Future work could add a "Reset onboarding tips" button in Settings → Manual that flips the flag back. Out of scope here.
