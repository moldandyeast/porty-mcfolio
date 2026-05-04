# In-Project Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a one-time centered overlay primer on first-ever project entry that explains the six view modes (Editor / Preview / Editor+Gallery / Editor+List / Editor+Links / Carousel) with name, shortcut, and one-line description; persist a `hasSeenProjectOnboarding` flag so the primer never reappears once dismissed.

**Architecture:** Three changes — a persisted flag on `AppState` (mirrors the existing `hideHiddenProjects` pattern), a new pure-presentation SwiftUI view `ProjectOnboardingPrimerView`, and a conditional `.overlay` in `ProjectDetailView` plus a hidden Esc keyboard-shortcut button. No new services, no schema changes, no third-party dependencies. Spec: `docs/superpowers/specs/2026-04-29-in-project-onboarding-design.md`.

**Tech Stack:** Swift 5.9, SwiftUI, XCTest. Build via `xcodebuild`. New `.swift` files under `PortyMcFolio/` or `PortyMcFolioTests/` are auto-discovered by `xcodegen` — run `xcodegen generate` after creating any new file. Project conventions: `type(scope): summary` commit style with the `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` trailer; **no SwiftUI view tests** — only model/service/state tests.

---

## Task 1: Persist `hasSeenProjectOnboarding` across launches

A new `@Published` flag on `AppState` written to UserDefaults via `didSet` and restored in `loadLayoutPreferences()`. Same pattern as `hideHiddenProjects` (`AppState.swift:52`).

**Files:**
- Create: `PortyMcFolioTests/AppStateProjectOnboardingPersistenceTests.swift`
- Modify: `PortyMcFolio/App/AppState.swift` (add property near line 52, restore block in `loadLayoutPreferences()` near line 445)

- [ ] **Step 1: Write the failing test**

Create `PortyMcFolioTests/AppStateProjectOnboardingPersistenceTests.swift` with:

```swift
import XCTest
@testable import PortyMcFolio

@MainActor
final class AppStateProjectOnboardingPersistenceTests: XCTestCase {

    private let key = "hasSeenProjectOnboarding"

    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: key)
    }

    func test_setting_writes_to_defaults() {
        let appState = AppState()
        appState.hasSeenProjectOnboarding = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))

        appState.hasSeenProjectOnboarding = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: key))
    }

    func test_loadLayoutPreferences_restoresStoredValue() {
        UserDefaults.standard.set(true, forKey: key)
        let appState = AppState()
        appState.loadLayoutPreferences()
        XCTAssertTrue(appState.hasSeenProjectOnboarding)
    }

    func test_loadLayoutPreferences_noStoredValue_keepsFalseDefault() {
        let appState = AppState()
        appState.loadLayoutPreferences()
        XCTAssertFalse(appState.hasSeenProjectOnboarding)
    }
}
```

- [ ] **Step 2: Regenerate Xcode project so the new test file is picked up**

```bash
cd <repo> && xcodegen generate
```

- [ ] **Step 3: Run the test to confirm it fails**

```bash
cd <repo> && xcodebuild test \
  -project PortyMcFolio.xcodeproj \
  -scheme PortyMcFolio \
  -destination 'platform=macOS' \
  -only-testing:PortyMcFolioTests/AppStateProjectOnboardingPersistenceTests \
  2>&1 | grep -E "Test Case|failed|passed|error:" | tail -10
```

Expected: build fails because `AppState` doesn't have a `hasSeenProjectOnboarding` property yet.

- [ ] **Step 4: Add the property to `AppState`**

In `PortyMcFolio/App/AppState.swift`, locate the `hideHiddenProjects` property (around line 52). Just below it, add:

```swift
    /// True after the user has dismissed the in-project onboarding primer
    /// at least once. Persisted; the primer never reappears after dismissal.
    @Published var hasSeenProjectOnboarding = false {
        didSet { UserDefaults.standard.set(hasSeenProjectOnboarding, forKey: "hasSeenProjectOnboarding") }
    }
```

Keep the existing `hideHiddenProjects` property intact above it.

- [ ] **Step 5: Restore the value in `loadLayoutPreferences()`**

In `PortyMcFolio/App/AppState.swift`, find the `hideHiddenProjects` restore block in `loadLayoutPreferences()` (around line 445). Just below it (still inside `loadLayoutPreferences()` and still before `restoreSortOrder()`), add:

```swift
        if UserDefaults.standard.object(forKey: "hasSeenProjectOnboarding") != nil {
            hasSeenProjectOnboarding = UserDefaults.standard.bool(forKey: "hasSeenProjectOnboarding")
        }
```

- [ ] **Step 6: Run the targeted test to confirm it passes**

```bash
cd <repo> && xcodebuild test \
  -project PortyMcFolio.xcodeproj \
  -scheme PortyMcFolio \
  -destination 'platform=macOS' \
  -only-testing:PortyMcFolioTests/AppStateProjectOnboardingPersistenceTests \
  2>&1 | grep -E "Test Case|failed|passed" | tail -10
```

Expected: all three tests pass.

- [ ] **Step 7: Run the full test suite to confirm no regressions**

```bash
cd <repo> && xcodebuild test \
  -project PortyMcFolio.xcodeproj \
  -scheme PortyMcFolio \
  -destination 'platform=macOS' \
  2>&1 | grep -E "Test Suite 'All tests'|Executed [0-9]+ tests|failed" | tail -5
```

Expected: `Test Suite 'All tests' passed`. Test count should be the previous total + 3.

- [ ] **Step 8: Commit**

```bash
cd <repo> && git add PortyMcFolio/App/AppState.swift PortyMcFolioTests/AppStateProjectOnboardingPersistenceTests.swift PortyMcFolio.xcodeproj/project.pbxproj && git commit -m "$(cat <<'EOF'
feat(state): add hasSeenProjectOnboarding persisted flag

A new @Published bool on AppState, written to UserDefaults via didSet
and restored in loadLayoutPreferences. Will be flipped to true the
first time the user dismisses the in-project onboarding primer (next
task), and prevents the primer from re-showing on subsequent project
entries.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Create `ProjectOnboardingPrimerView`

A new SwiftUI view containing the centered card content. Pure presentation — takes one `onDismiss: () -> Void` closure. Uses theme tokens that already exist (verified during the welcome primer implementation: `theme.colors.backgroundAlt/border/textPrimary/textSecondary/textTertiary/accent/accentForeground`, `DT.Spacing.{xs,sm,md,lg,xl}`, `DT.Radius.{small,medium}`, `DT.Typography.{micro,title,body,caption}`).

**Files:**
- Create: `PortyMcFolio/Views/ProjectOnboardingPrimerView.swift`

- [ ] **Step 1: Create the view file**

Write `PortyMcFolio/Views/ProjectOnboardingPrimerView.swift`:

```swift
import SwiftUI

/// One-time centered primer shown on `ProjectDetailView` when a user enters
/// any project for the first time. Explains the six view modes with name,
/// keyboard shortcut, and a one-line description. Dismissable; sets
/// `hasSeenProjectOnboarding` so it never reappears.
struct ProjectOnboardingPrimerView: View {
    let onDismiss: () -> Void
    @Environment(\.theme) var theme

    private struct Mode: Identifiable {
        let id: String
        let symbol: String
        let name: String
        let shortcut: String
        let description: String
    }

    private static let modes: [Mode] = [
        Mode(id: "editor",
             symbol: "doc.text",
             name: "Editor",
             shortcut: "\u{2318}1",
             description: "Write the markdown that describes the work"),
        Mode(id: "preview",
             symbol: "eye",
             name: "Preview",
             shortcut: "\u{2318}2",
             description: "Rendered markdown with embeds and link cards"),
        Mode(id: "splitGallery",
             symbol: "square.grid.2x2",
             name: "Editor + Gallery",
             shortcut: "\u{2318}3",
             description: "Editor and your media side-by-side"),
        Mode(id: "splitList",
             symbol: "list.bullet",
             name: "Editor + List",
             shortcut: "\u{2318}4",
             description: "Editor and a sortable file list"),
        Mode(id: "splitLinks",
             symbol: "link",
             name: "Editor + Links",
             shortcut: "\u{2318}5",
             description: "Editor and saved links"),
        Mode(id: "carousel",
             symbol: "rectangle.stack.badge.play",
             name: "Carousel",
             shortcut: "\u{2318}6",
             description: "Full-screen slideshow of favorites"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.lg) {
            VStack(alignment: .leading, spacing: DT.Spacing.xs) {
                Text("WELCOME TO YOUR FIRST PROJECT")
                    .font(DT.Typography.micro)
                    .tracking(1.4)
                    .foregroundStyle(theme.colors.textTertiary)
                Text("Switch views to work different ways")
                    .font(DT.Typography.title)
                    .foregroundStyle(theme.colors.textPrimary)
            }

            VStack(alignment: .leading, spacing: DT.Spacing.md) {
                ForEach(Self.modes) { mode in
                    HStack(alignment: .top, spacing: DT.Spacing.md) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 16))
                            .foregroundStyle(theme.colors.textSecondary)
                            .frame(width: 22, alignment: .center)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.name)
                                .font(DT.Typography.body)
                                .fontWeight(.medium)
                                .foregroundStyle(theme.colors.textPrimary)
                            Text(mode.description)
                                .font(DT.Typography.caption)
                                .foregroundStyle(theme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Text(mode.shortcut)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.colors.textTertiary)
                            .padding(.horizontal, DT.Spacing.sm)
                            .padding(.vertical, 3)
                            .background(theme.colors.backgroundAlt, in: RoundedRectangle(cornerRadius: DT.Radius.small))
                            .overlay(
                                RoundedRectangle(cornerRadius: DT.Radius.small)
                                    .stroke(theme.colors.border, lineWidth: 0.5)
                            )
                    }
                }
            }

            Text("All shortcuts in Settings → Manual → Keyboard Shortcuts.")
                .font(DT.Typography.caption)
                .foregroundStyle(theme.colors.textTertiary)

            Button(action: onDismiss) {
                Text("Got it")
                    .font(DT.Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(theme.colors.accentForeground)
                    .padding(.horizontal, DT.Spacing.lg)
                    .padding(.vertical, DT.Spacing.sm)
                    .background(theme.colors.accent, in: RoundedRectangle(cornerRadius: DT.Radius.small))
            }
            .buttonStyle(.plain)
        }
        .padding(DT.Spacing.xl)
        .frame(maxWidth: 480)
        .background(theme.colors.backgroundAlt, in: RoundedRectangle(cornerRadius: DT.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.medium)
                .stroke(theme.colors.border, lineWidth: 1)
        )
    }
}
```

The shortcut chip uses the `\u{2318}` escape (U+2318 ⌘) for consistency with other shortcut strings in the codebase (e.g., `AppSettingsView.swift`'s `shortcutRow` calls).

- [ ] **Step 2: Regenerate the Xcode project**

```bash
cd <repo> && xcodegen generate
```

- [ ] **Step 3: Build to verify it compiles**

```bash
cd <repo> && xcodebuild \
  -project PortyMcFolio.xcodeproj \
  -scheme PortyMcFolio \
  -destination 'platform=macOS' \
  -configuration Debug build \
  2>&1 | grep -E "error:|BUILD" | tail -3
```

Expected: `** BUILD SUCCEEDED **`. (All referenced tokens — `DT.Spacing.{xs,sm,md,lg,xl}`, `DT.Radius.{small,medium}`, `DT.Typography.{micro,title,body,caption}`, `theme.colors.*` — were already verified during the welcome primer work.)

- [ ] **Step 4: Commit**

```bash
cd <repo> && git add PortyMcFolio/Views/ProjectOnboardingPrimerView.swift PortyMcFolio.xcodeproj/project.pbxproj && git commit -m "$(cat <<'EOF'
feat(views): ProjectOnboardingPrimerView for first-project tour

Centered card explaining the six view modes — Editor, Preview,
Editor+Gallery, Editor+List, Editor+Links, Carousel — with name,
keyboard shortcut, and a one-line description per mode. Pure
presentation; takes an onDismiss closure. Wired into ProjectDetailView
in the next task.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Mount the primer as an overlay on `ProjectDetailView`

Add the dimmed-backdrop overlay, the centered primer card, and the three dismissal paths (Got it / tap-outside / Esc).

**Files:**
- Modify: `PortyMcFolio/Views/ProjectDetailView.swift` — insert two modifiers (`.overlay` and `.background`) right before the existing `.sheet(isPresented: $isShowingSettings)` modifier (around line 204), and add a `dismissOnboarding()` private method.

- [ ] **Step 1: Add the dismissal helper method**

In `PortyMcFolio/Views/ProjectDetailView.swift`, locate the section just below the body (after the body's closing brace and before the next computed property or method). Add this private method anywhere inside the `struct ProjectDetailView` (a sensible spot is right above `private func handlePendingSelection()` if it exists, or just below the body's closing `}`):

```swift
    private func dismissOnboarding() {
        appState.hasSeenProjectOnboarding = true
    }
```

If you can't find an obvious slot, add it right above the closing `}` of the struct.

- [ ] **Step 2: Add the overlay + Esc handler in `body`**

In `PortyMcFolio/Views/ProjectDetailView.swift`, find the existing `.sheet(isPresented: $isShowingSettings)` modifier (around line 204). It currently looks like:

```swift
        .sheet(isPresented: $isShowingSettings) {
            ProjectSettingsPopover(
                project: project,
                isPresented: $isShowingSettings
            )
            .environmentObject(appState)
        }
        .onAppear {
```

Insert the following two modifier blocks **immediately before** `.sheet(isPresented: $isShowingSettings)`:

```swift
        .overlay {
            if !appState.hasSeenProjectOnboarding {
                ZStack {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { dismissOnboarding() }
                    ProjectOnboardingPrimerView(onDismiss: dismissOnboarding)
                }
                .transition(.opacity)
            }
        }
        .background {
            if !appState.hasSeenProjectOnboarding {
                Button("") { dismissOnboarding() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .opacity(0)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.15), value: appState.hasSeenProjectOnboarding)
```

The full transition reads: dimmed-backdrop ZStack covers the project content; tapping the backdrop dismisses; the primer card sits centered above; the hidden `.background` Button wires Esc to the same dismiss path; the animation smooths show/hide.

- [ ] **Step 3: Build**

```bash
cd <repo> && xcodebuild \
  -project PortyMcFolio.xcodeproj \
  -scheme PortyMcFolio \
  -destination 'platform=macOS' \
  -configuration Debug build \
  2>&1 | grep -E "error:|BUILD" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd <repo> && git add PortyMcFolio/Views/ProjectDetailView.swift && git commit -m "$(cat <<'EOF'
feat(views): mount ProjectOnboardingPrimerView on first project entry

Add a conditional overlay on ProjectDetailView that shows the primer
card on a dimmed backdrop until hasSeenProjectOnboarding flips true.
Three dismissal paths — the Got it button, tap-outside on the
backdrop, and the Esc keyboard shortcut — all route through one
dismissOnboarding() method that sets the flag.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Final smoke verification

Run the full test suite, do a Release build, and walk through the manual smoke checklist.

- [ ] **Step 1: Run the full unit test suite**

```bash
cd <repo> && xcodebuild test \
  -project PortyMcFolio.xcodeproj \
  -scheme PortyMcFolio \
  -destination 'platform=macOS' \
  2>&1 | grep -E "Test Suite 'All tests'|Executed [0-9]+ tests|failed" | tail -5
```

Expected: `Test Suite 'All tests' passed`. Test count is the prior total + 3 (the new persistence tests).

- [ ] **Step 2: Release build**

```bash
cd <repo> && xcodebuild \
  -project PortyMcFolio.xcodeproj \
  -scheme PortyMcFolio \
  -configuration Release \
  -destination 'platform=macOS' build \
  2>&1 | grep -E "error:|BUILD" | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual smoke checklist (interactive)**

Build and launch the app. Run through:

1. **Reset the flag** so you can see the primer again:

   ```bash
   defaults delete com.portymcfolio.app hasSeenProjectOnboarding 2>/dev/null
   ```

2. Launch the app. Open any existing project from the overview (or create a new one).
3. The centered overlay primer appears. Confirm:
   - Eyebrow reads "WELCOME TO YOUR FIRST PROJECT"
   - Six rows, each with the right SF Symbol, name, ⌘N shortcut chip, and description
   - Footer: "All shortcuts in Settings → Manual → Keyboard Shortcuts."
   - Filled "Got it" button matches the existing primary-button style
   - Card has visible contrast against the dimmed page (no blending)
4. Try each dismissal path on a fresh primer (relaunch + reset between each):
   - Click "Got it" → primer disappears, project becomes interactive.
   - Tap on the dimmed backdrop → same behavior.
   - Press Esc → same behavior.
5. After dismissal, verify persistence:

   ```bash
   defaults read com.portymcfolio.app hasSeenProjectOnboarding
   ```

   Expected: `1`.
6. Quit and relaunch the app. Open a project. The primer should not reappear.
7. Open Settings to confirm nothing else regressed (the welcome primer's settings revamp should still look right).
8. Verify the primer renders cleanly in light + dark mode and across all three themes (porty / osx / bw).

- [ ] **Step 4: Push**

```bash
cd <repo> && git push origin main
```

(If you're working on a feature branch instead of `main`, push that branch and open a PR.)

Plan complete.

---

## Out of scope (deferred)

These were explicitly excluded by the design spec:

- Coach marks pointing at individual toolbar buttons (richer but layout-fragile)
- A reset / "show me again" affordance — Settings → Manual → Getting Started is the canonical re-read
- Per-feature mini-tours elsewhere (Gallery, Links, Carousel, Settings)
- Tracking which view modes the user has tried; the primer is single-shot

Each is a candidate for a future plan if needed.
