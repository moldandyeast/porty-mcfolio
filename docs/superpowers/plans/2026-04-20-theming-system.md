# Theming System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce a runtime-swappable theme system with three themes (Porty, OSX via `NSColor` bridges, BW monochrome + Porty accent), each following macOS system appearance. Rebuild `AppSettingsView` as a real Settings tab. Extend theming into the markdown preview and CodeMirror editor via CSS custom properties over the existing WKWebView bridge.

**Architecture:** Pure `Theme` struct with three instances (`.porty`, `.osx`, `.bw`). Injected through `@Environment(\.theme)` from the root. `DT.Colors` is deleted; every view reads `theme.colors.X`. WebViews receive CSS variables via a user script at load and via `evaluateJavaScript` on theme/appearance change.

**Tech Stack:** Swift 5.9, SwiftUI (macOS **15+**), AppKit (`NSColor`, `NSAppearance.performAsCurrentDrawingAppearance`), WKWebView, CodeMirror 6 + Vite, XCTest.

**Reference spec:** [docs/superpowers/specs/2026-04-20-theming-system-design.md](../specs/2026-04-20-theming-system-design.md)

---

## File Structure

**New files:**

| Path                                                | Responsibility                                                   |
| --------------------------------------------------- | ---------------------------------------------------------------- |
| `PortyMcFolio/Design/Theme.swift`                   | `ThemeColors`, `Theme`, three palette definitions, `cssVariables(appearance:)`. |
| `PortyMcFolio/Design/ColorHex.swift`                | `Color.hex(for: NSAppearance)` helper.                            |
| `PortyMcFolioTests/ThemeTests.swift`                | Round-trip, palette, CSS-variable, and BW-monochrome tests.       |

**Modified files (infrastructure):**

| Path                                             | What changes                                              |
| ------------------------------------------------ | --------------------------------------------------------- |
| `project.yml`                                    | `MACOSX_DEPLOYMENT_TARGET: "15.0"`.                       |
| `PortyMcFolio/Design/DesignTokens.swift`         | Delete `DT.Colors`, `GrainTexture`, `dtGrain()`.          |
| `PortyMcFolio/App/AppState.swift`                | Add theme + preference fields, load/persist, signal.      |
| `PortyMcFolio/App/PortyMcFolioApp.swift`         | Root env injection, tint, grain lifecycle.                |
| `PortyMcFolio/Views/AppSettingsView.swift`       | Full rewrite (Appearance + Workspace + Portfolio + Help).|
| `PortyMcFolio/Views/MarkdownPreviewView.swift`   | Theme-aware CSS variable injection + export.              |
| `PortyMcFolio/Views/MarkdownEditorView.swift`    | Theme-aware CSS variable injection + auto-save delay.     |
| `PortyMcFolio/Editor/Resources/preview.html`     | Rename CSS vars to match Swift export; strip `@media`.    |
| `Editor/src/theme.js`                            | Rewrite as single theme reading CSS variables.            |

**Modified files (migration — `DT.Colors.X` → `theme.colors.X`):**

21 view files, grouped by size (in Tasks 7–9):

*Tiny (2–3 DT.Colors refs):* `TagPillView.swift`, `SplashView.swift`, `FolderPickerView.swift`, `ContentView.swift`, `StatusBadgeView.swift`.

*Small (6–10 refs):* `LinkCardView.swift`, `YearStepper.swift`, `BreadcrumbBar.swift`, `ProjectCardView.swift`, `GalleryListView.swift`, `NewProjectSheet.swift`, `GalleryItemView.swift`, `TagChipInput.swift`.

*Medium (13–20 refs):* `EditLinkSheet.swift`, `ProjectSettingsPopover.swift`, `ProjectDetailView.swift`, `SearchPalette.swift`.

*Large (24+ refs):* `GalleryView.swift`, `CleanupPopup.swift`, `ProjectListView.swift`, `StyleGuideView.swift`.

---

## Running tests

All commands from the repo root, same scheme/destination:

```bash
xcodebuild -project PortyMcFolio.xcodeproj \
           -scheme PortyMcFolio \
           -destination 'platform=macOS' \
           test
```

Filter a single test class: `-only-testing:PortyMcFolioTests/<ClassName>`. Filter one method: `-only-testing:PortyMcFolioTests/<ClassName>/<method>`.

When a task adds a new Swift file, after saving the file run `xcodegen generate` so the `.xcodeproj` picks it up, then commit the regen as a separate `chore:` commit.

---

## Task 1: Bump deployment target to macOS 15

**Files:**
- Modify: `project.yml`
- Regenerate: `PortyMcFolio.xcodeproj/project.pbxproj` (via xcodegen)

- [ ] **Step 1.1: Update `project.yml`**

Change the `MACOSX_DEPLOYMENT_TARGET` line inside `targets.PortyMcFolio.settings.base`:

```yaml
MACOSX_DEPLOYMENT_TARGET: "15.0"
```

- [ ] **Step 1.2: Regenerate xcodeproj**

```bash
xcodegen generate
```

- [ ] **Step 1.3: Build to confirm the bump doesn't break anything existing**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 1.4: Commit**

```bash
git add project.yml PortyMcFolio.xcodeproj/project.pbxproj
git commit -m "chore: bump deployment target to macOS 15"
```

---

## Task 2: `ColorHex` helper (TDD)

**Files:**
- Create: `PortyMcFolio/Design/ColorHex.swift`
- Create: `PortyMcFolioTests/ColorHexTests.swift`

- [ ] **Step 2.1: Write the failing tests**

Create `PortyMcFolioTests/ColorHexTests.swift`:

```swift
import XCTest
import SwiftUI
import AppKit
@testable import PortyMcFolio

final class ColorHexTests: XCTestCase {
    private let aqua = NSAppearance(named: .aqua)!
    private let darkAqua = NSAppearance(named: .darkAqua)!

    func testStaticColorResolvesToHex() {
        let white = Color.white
        XCTAssertEqual(white.hex(for: aqua), "#FFFFFF")
    }

    func testBlackResolvesToHex() {
        XCTAssertEqual(Color.black.hex(for: aqua), "#000000")
    }

    func testDynamicColorPicksLightUnderAqua() {
        let c = Color(light: Color(hex: "112233"), dark: Color(hex: "AABBCC"))
        XCTAssertEqual(c.hex(for: aqua), "#112233")
    }

    func testDynamicColorPicksDarkUnderDarkAqua() {
        let c = Color(light: Color(hex: "112233"), dark: Color(hex: "AABBCC"))
        XCTAssertEqual(c.hex(for: darkAqua), "#AABBCC")
    }

    func testRoundsComponents() {
        // Component 0.501 must round to 128 (0x80), not 127.
        let c = Color(red: 0.501, green: 0.501, blue: 0.501)
        XCTAssertEqual(c.hex(for: aqua), "#808080")
    }
}
```

- [ ] **Step 2.2: Run tests, confirm they fail**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test \
  -only-testing:PortyMcFolioTests/ColorHexTests
```

Expected: compile error — `cannot find 'hex(for:)' in scope`.

- [ ] **Step 2.3: Implement the helper**

Create `PortyMcFolio/Design/ColorHex.swift`:

```swift
import SwiftUI
import AppKit

extension Color {
    /// Resolve to a hex string under the specified appearance. NSColor
    /// dynamic providers (used by `Color(light:dark:)` and `Color(nsColor:)`
    /// bindings to semantic AppKit colors) evaluate against the current
    /// drawing appearance — use `performAsCurrentDrawingAppearance` to
    /// pin it during the resolution.
    func hex(for appearance: NSAppearance) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        appearance.performAsCurrentDrawingAppearance {
            NSColor(self)
                .usingColorSpace(.sRGB)?
                .getRed(&r, green: &g, blue: &b, alpha: &a)
        }
        return String(
            format: "#%02X%02X%02X",
            Int(round(r * 255)),
            Int(round(g * 255)),
            Int(round(b * 255))
        )
    }
}
```

- [ ] **Step 2.4: Regenerate xcodeproj**

```bash
xcodegen generate
```

- [ ] **Step 2.5: Run tests, confirm they pass**

Same command as Step 2.2. Expected: all 5 tests pass.

- [ ] **Step 2.6: Commit**

```bash
git add PortyMcFolio/Design/ColorHex.swift \
        PortyMcFolioTests/ColorHexTests.swift
git commit -m "feat: ColorHex helper for per-appearance hex resolution"
```

- [ ] **Step 2.7: Commit xcodeproj regen**

```bash
git add PortyMcFolio.xcodeproj/project.pbxproj
git commit -m "chore: regenerate xcodeproj for ColorHex sources"
```

---

## Task 3: `Theme` struct with three palettes (TDD)

**Files:**
- Create: `PortyMcFolio/Design/Theme.swift`
- Create: `PortyMcFolioTests/ThemeTests.swift`

- [ ] **Step 3.1: Write failing tests**

Create `PortyMcFolioTests/ThemeTests.swift`:

```swift
import XCTest
import SwiftUI
import AppKit
@testable import PortyMcFolio

final class ThemeTests: XCTestCase {
    private let aqua = NSAppearance(named: .aqua)!
    private let darkAqua = NSAppearance(named: .darkAqua)!

    // MARK: Identity

    func testNamedRoundTrip() {
        XCTAssertEqual(Theme.named(.porty).id, .porty)
        XCTAssertEqual(Theme.named(.osx).id, .osx)
        XCTAssertEqual(Theme.named(.bw).id, .bw)
    }

    func testAllEnumerates() {
        XCTAssertEqual(Theme.all.map(\.id), [.porty, .osx, .bw])
    }

    func testNamesAreHumanReadable() {
        XCTAssertEqual(Theme.porty.name, "Porty")
        XCTAssertEqual(Theme.osx.name, "OSX")
        XCTAssertEqual(Theme.bw.name, "BW")
    }

    // MARK: Porty palette

    func testPortyAccentIsPink() {
        XCTAssertEqual(Theme.porty.colors.accent.hex(for: aqua), "#B34778")
        XCTAssertEqual(Theme.porty.colors.accent.hex(for: darkAqua), "#B34778")
    }

    func testPortyLightBackground() {
        XCTAssertEqual(Theme.porty.colors.background.hex(for: aqua), "#F0F1F5")
    }

    func testPortyDarkBackground() {
        XCTAssertEqual(Theme.porty.colors.background.hex(for: darkAqua), "#1C1E22")
    }

    func testPortyGrainOpacity() {
        XCTAssertEqual(Theme.porty.grainOpacity, 0.03, accuracy: 0.0001)
    }

    // MARK: OSX palette

    func testOSXAccentUsesSystemAccent() {
        // OSX accent is NSColor.controlAccentColor. It's dynamic — we just
        // verify it resolves to a non-empty, valid hex (not our Porty pink).
        let light = Theme.osx.colors.accent.hex(for: aqua)
        XCTAssertTrue(light.hasPrefix("#"))
        XCTAssertEqual(light.count, 7)
    }

    func testOSXGrainOpacity() {
        XCTAssertEqual(Theme.osx.grainOpacity, 0.0, accuracy: 0.0001)
    }

    // MARK: BW palette

    func testBWLightBackgroundIsPureWhite() {
        XCTAssertEqual(Theme.bw.colors.background.hex(for: aqua), "#FFFFFF")
    }

    func testBWDarkBackgroundIsPureBlack() {
        XCTAssertEqual(Theme.bw.colors.background.hex(for: darkAqua), "#000000")
    }

    func testBWAccentIsPortyPink() {
        XCTAssertEqual(Theme.bw.colors.accent.hex(for: aqua), "#B34778")
    }

    func testBWSurfacesAreMonochrome() {
        // R == G == B for every non-accent color in both light and dark.
        let bw = Theme.bw.colors
        let mono: [Color] = [
            bw.background, bw.backgroundAlt, bw.surface, bw.surfaceHover,
            bw.textPrimary, bw.textSecondary, bw.textTertiary, bw.border,
            bw.statusDraft, bw.statusComplete, bw.statusArchived, bw.error,
        ]
        for color in mono {
            for app in [aqua, darkAqua] {
                let hex = color.hex(for: app)
                // Hex like #RRGGBB — check R == G == B.
                let r = hex[hex.index(hex.startIndex, offsetBy: 1)..<hex.index(hex.startIndex, offsetBy: 3)]
                let g = hex[hex.index(hex.startIndex, offsetBy: 3)..<hex.index(hex.startIndex, offsetBy: 5)]
                let b = hex[hex.index(hex.startIndex, offsetBy: 5)..<hex.index(hex.startIndex, offsetBy: 7)]
                XCTAssertEqual(String(r), String(g), "Not monochrome: \(hex)")
                XCTAssertEqual(String(g), String(b), "Not monochrome: \(hex)")
            }
        }
    }
}
```

- [ ] **Step 3.2: Run tests, confirm they fail**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test \
  -only-testing:PortyMcFolioTests/ThemeTests
```

Expected: compile errors — `cannot find 'Theme' in scope`, etc.

- [ ] **Step 3.3: Implement `Theme` and the three palettes**

Create `PortyMcFolio/Design/Theme.swift`:

```swift
import SwiftUI
import AppKit

struct ThemeColors: Hashable {
    let background: Color
    let backgroundAlt: Color
    let surface: Color
    let surfaceHover: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let border: Color
    let accent: Color
    let statusDraft: Color
    let statusActive: Color
    let statusComplete: Color
    let statusArchived: Color
    let error: Color
}

struct Theme: Hashable {
    enum ID: String, CaseIterable, Codable {
        case porty
        case osx
        case bw
    }

    let id: ID
    let name: String
    let colors: ThemeColors
    let grainOpacity: Double

    static let all: [Theme] = [.porty, .osx, .bw]

    static func named(_ id: ID) -> Theme {
        switch id {
        case .porty: return .porty
        case .osx:   return .osx
        case .bw:    return .bw
        }
    }

    // MARK: Porty

    static let porty = Theme(
        id: .porty,
        name: "Porty",
        colors: ThemeColors(
            background:     Color(light: Color(hex: "F0F1F5"), dark: Color(hex: "1C1E22")),
            backgroundAlt:  Color(light: Color(hex: "E2E4EB"), dark: Color(hex: "262A30")),
            surface:        Color(light: Color(hex: "F8F9FB"), dark: Color(hex: "2C2F36")),
            surfaceHover:   Color(light: Color(hex: "EAECF1"), dark: Color(hex: "393D47")),
            textPrimary:    Color(light: Color(hex: "1A1D24"), dark: Color(hex: "ECEEF3")),
            textSecondary:  Color(light: Color(hex: "5C6275"), dark: Color(hex: "A8AEBD")),
            textTertiary:   Color(light: Color(hex: "8B92A4"), dark: Color(hex: "7B8295")),
            border:         Color(light: Color(hex: "D8DBE3"), dark: Color(hex: "353940")),
            accent:         Color(hex: "B34778"),
            statusDraft:    Color(hex: "8E8E93"),
            statusActive:   Color(hex: "B34778"),
            statusComplete: Color(light: Color(hex: "3478F6"), dark: Color(hex: "4A9AFF")),
            statusArchived: Color(light: Color(hex: "FF9500"), dark: Color(hex: "FFA733")),
            error:          Color(light: Color(hex: "E5484D"), dark: Color(hex: "F85149"))
        ),
        grainOpacity: 0.03
    )

    // MARK: OSX (NSColor bridges)

    static let osx = Theme(
        id: .osx,
        name: "OSX",
        colors: ThemeColors(
            background:     Color(nsColor: .windowBackgroundColor),
            backgroundAlt:  Color(nsColor: .underPageBackgroundColor),
            surface:        Color(nsColor: .controlBackgroundColor),
            surfaceHover:   Color(nsColor: .quaternaryLabelColor),
            textPrimary:    Color(nsColor: .labelColor),
            textSecondary:  Color(nsColor: .secondaryLabelColor),
            textTertiary:   Color(nsColor: .tertiaryLabelColor),
            border:         Color(nsColor: .separatorColor),
            accent:         Color(nsColor: .controlAccentColor),
            statusDraft:    Color(nsColor: .systemGray),
            statusActive:   Color(nsColor: .systemBlue),
            statusComplete: Color(nsColor: .systemGreen),
            statusArchived: Color(nsColor: .systemOrange),
            error:          Color(nsColor: .systemRed)
        ),
        grainOpacity: 0.0
    )

    // MARK: BW (monochrome + Porty accent)

    static let bw = Theme(
        id: .bw,
        name: "BW",
        colors: ThemeColors(
            background:     Color(light: Color(hex: "FFFFFF"), dark: Color(hex: "000000")),
            backgroundAlt:  Color(light: Color(hex: "F5F5F5"), dark: Color(hex: "0F0F0F")),
            surface:        Color(light: Color(hex: "FAFAFA"), dark: Color(hex: "1A1A1A")),
            surfaceHover:   Color(light: Color(hex: "F0F0F0"), dark: Color(hex: "2A2A2A")),
            textPrimary:    Color(light: Color(hex: "000000"), dark: Color(hex: "FFFFFF")),
            textSecondary:  Color(light: Color(hex: "555555"), dark: Color(hex: "AAAAAA")),
            textTertiary:   Color(light: Color(hex: "999999"), dark: Color(hex: "666666")),
            border:         Color(light: Color(hex: "DDDDDD"), dark: Color(hex: "333333")),
            accent:         Color(hex: "B34778"),
            statusDraft:    Color(light: Color(hex: "999999"), dark: Color(hex: "666666")),
            statusActive:   Color(hex: "B34778"),
            statusComplete: Color(light: Color(hex: "000000"), dark: Color(hex: "FFFFFF")),
            statusArchived: Color(light: Color(hex: "555555"), dark: Color(hex: "AAAAAA")),
            error:          Color(light: Color(hex: "000000"), dark: Color(hex: "FFFFFF"))
        ),
        grainOpacity: 0.02
    )
}
```

- [ ] **Step 3.4: Regenerate xcodeproj**

```bash
xcodegen generate
```

- [ ] **Step 3.5: Run tests, confirm they pass**

Same command as Step 3.2. Expected: all 13 tests pass.

- [ ] **Step 3.6: Commit**

```bash
git add PortyMcFolio/Design/Theme.swift \
        PortyMcFolioTests/ThemeTests.swift
git commit -m "feat: Theme struct with Porty, OSX, and BW palettes"
```

- [ ] **Step 3.7: Commit xcodeproj regen**

```bash
git add PortyMcFolio.xcodeproj/project.pbxproj
git commit -m "chore: regenerate xcodeproj for Theme sources"
```

---

## Task 4: Theme environment key

**Files:**
- Modify: `PortyMcFolio/Design/Theme.swift` (append)

- [ ] **Step 4.1: Add the environment key**

At the bottom of `PortyMcFolio/Design/Theme.swift`, append:

```swift
extension EnvironmentValues {
    @Entry var theme: Theme = .porty
}
```

(`@Entry` is a SwiftUI 5 macro, available with the macOS 15 bump in Task 1.)

- [ ] **Step 4.2: Build to confirm**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4.3: Commit**

```bash
git add PortyMcFolio/Design/Theme.swift
git commit -m "feat: @Environment(\.theme) key with .porty default"
```

---

## Task 5: `AppState` additions

Add theme + preference fields with UserDefaults persistence. Keep `DT.Colors` alive for now; the migration happens later.

**Files:**
- Modify: `PortyMcFolio/App/AppState.swift`

- [ ] **Step 5.1: Add the new fields**

Insert near the existing `@Published` declarations in `AppState` (around line 19–45, after `portfolioRootURL` and before `selectedProject`):

```swift
    // MARK: - Theming + preferences

    @Published var themeID: Theme.ID = .porty {
        didSet { UserDefaults.standard.set(themeID.rawValue, forKey: "themeID") }
    }
    var theme: Theme { Theme.named(themeID) }

    enum DefaultViewMode: String, CaseIterable, Codable {
        case lastUsed, editor, preview, split, gallery
    }
    @Published var defaultViewMode: DefaultViewMode = .lastUsed {
        didSet { UserDefaults.standard.set(defaultViewMode.rawValue, forKey: "defaultViewMode") }
    }

    @Published var autoSaveDelay: Double = 1.5 {
        didSet { UserDefaults.standard.set(autoSaveDelay, forKey: "autoSaveDelay") }
    }

    @Published var grainEnabled: Bool = true {
        didSet { UserDefaults.standard.set(grainEnabled, forKey: "grainEnabled") }
    }
    @Published var grainOpacityOverride: Double? = nil {
        didSet {
            if let v = grainOpacityOverride {
                UserDefaults.standard.set(v, forKey: "grainOpacityOverride")
            } else {
                UserDefaults.standard.removeObject(forKey: "grainOpacityOverride")
            }
        }
    }
    var effectiveGrainOpacity: Double {
        guard grainEnabled else { return 0 }
        return grainOpacityOverride ?? theme.grainOpacity
    }

    /// Incremented whenever the system appearance or the macOS accent
    /// changes. WebView-hosting views observe this to re-inject the CSS
    /// variables. See Task 6 for the observer wiring.
    @Published var appearanceSignal: Int = 0
```

- [ ] **Step 5.2: Load from UserDefaults in `loadLayoutPreferences`**

Find `loadLayoutPreferences()` (around line 192–206) and add these reads **before** the existing `restoreSortOrder()` call:

```swift
        if let raw = UserDefaults.standard.string(forKey: "themeID"),
           let id = Theme.ID(rawValue: raw) {
            themeID = id
        }
        if let raw = UserDefaults.standard.string(forKey: "defaultViewMode"),
           let mode = DefaultViewMode(rawValue: raw) {
            defaultViewMode = mode
        }
        let delay = UserDefaults.standard.double(forKey: "autoSaveDelay")
        if delay >= 0.5 && delay <= 5.0 {
            autoSaveDelay = delay
        }
        if UserDefaults.standard.object(forKey: "grainEnabled") != nil {
            grainEnabled = UserDefaults.standard.bool(forKey: "grainEnabled")
        }
        if UserDefaults.standard.object(forKey: "grainOpacityOverride") != nil {
            let v = UserDefaults.standard.double(forKey: "grainOpacityOverride")
            if v >= 0.0 && v <= 0.10 {
                grainOpacityOverride = v
            }
        }
```

- [ ] **Step 5.3: Build**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5.4: Run full test suite to confirm no regression**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test
```

Expected: all existing tests still pass.

- [ ] **Step 5.5: Commit**

```bash
git add PortyMcFolio/App/AppState.swift
git commit -m "feat: AppState gains theme + workspace preference fields"
```

---

## Task 6: Root environment injection + appearance signal observer

Inject the active theme into the environment, apply accent tint, wire the `GrainNSView` to `effectiveGrainOpacity`, and listen for macOS appearance + accent changes to bump `appearanceSignal`.

**Files:**
- Modify: `PortyMcFolio/App/PortyMcFolioApp.swift`
- Modify: `PortyMcFolio/App/AppState.swift`

- [ ] **Step 6.1: Add the appearance observer to AppState**

Open `PortyMcFolio/App/AppState.swift`. Add these fields near the other private state (around the `cancellables` area, or create one if none):

```swift
    /// Observers for system appearance + accent changes — bump `appearanceSignal`.
    private var appearanceObservers: [NSObjectProtocol] = []
    private var effectiveAppearanceObservation: NSKeyValueObservation?
```

Add a private method:

```swift
    /// Subscribes to AppleInterfaceThemeChangedNotification (dark/light toggle) and
    /// AppleColorPreferencesChangedNotification (system accent color change).
    /// Also KVOs NSApp.effectiveAppearance as a belt-and-suspenders trigger.
    func startAppearanceObservers() {
        let dnc = DistributedNotificationCenter.default()
        let themeObs = dnc.addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.appearanceSignal &+= 1
        }
        let accentObs = dnc.addObserver(
            forName: Notification.Name("AppleColorPreferencesChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.appearanceSignal &+= 1
        }
        appearanceObservers = [themeObs, accentObs]

        effectiveAppearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.appearanceSignal &+= 1 }
        }
    }

    deinit {
        let dnc = DistributedNotificationCenter.default()
        for obs in appearanceObservers { dnc.removeObserver(obs) }
    }
```

- [ ] **Step 6.2: Call the observer setup in `PortyMcFolioApp`'s `onAppear`**

Open `PortyMcFolio/App/PortyMcFolioApp.swift`. In `body`, after `addWindowGrain()`, call:

```swift
                .onAppear {
                    configureWindow()
                    addWindowGrain()
                    appState.startAppearanceObservers()
                }
```

- [ ] **Step 6.3: Inject the theme into the environment + apply tint**

Still in `PortyMcFolioApp.body`, replace:

```swift
ContentView()
    .environmentObject(appState)
    .tint(DT.Colors.accent)
```

with:

```swift
ContentView()
    .environmentObject(appState)
    .environment(\.theme, appState.theme)
    .tint(appState.theme.colors.accent)
```

- [ ] **Step 6.4: Make `configureWindow` and `addWindowGrain` theme-aware**

Rewrite `configureWindow()` to read from `appState`:

```swift
    private func configureWindow() {
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                window.titlebarAppearsTransparent = true
                window.backgroundColor = NSColor(appState.theme.colors.background)
                window.titlebarSeparatorStyle = .none
            }
            UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")
        }
    }
```

Rewrite `addWindowGrain()` to pass `effectiveGrainOpacity` and keep the `GrainNSView` reference on the grain view:

```swift
    private func addWindowGrain() {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first,
                  let contentView = window.contentView else { return }

            contentView.subviews.compactMap { $0 as? GrainNSView }.forEach { $0.removeFromSuperview() }

            let grainView = GrainNSView(opacity: appState.effectiveGrainOpacity)
            grainView.frame = contentView.bounds
            grainView.autoresizingMask = [.width, .height]
            contentView.addSubview(grainView)
        }
    }
```

- [ ] **Step 6.5: Give `GrainNSView` an `updateOpacity(_:)` method and an opacity-taking init**

In `PortyMcFolio/Design/DesignTokens.swift`, replace `GrainNSView`'s `init(frame:)` with:

```swift
final class GrainNSView: NSView {
    init(opacity: Double) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.opacity = Float(opacity)
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateOpacity(_ value: Double) {
        layer?.opacity = Float(value)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let width = Int(bounds.width)
        let height = Int(bounds.height)
        let count = Int(Double(width * height) * 0.05)

        for _ in 0..<count {
            let x = CGFloat.random(in: 0..<bounds.width)
            let y = CGFloat.random(in: 0..<bounds.height)
            let b = CGFloat.random(in: 0...1)
            ctx.setFillColor(NSColor(white: b, alpha: 1).cgColor)
            ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
    }

    override var mouseDownCanMoveWindow: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
```

- [ ] **Step 6.6: Observe theme/grain changes and update the window**

Add `.onChange` modifiers to the `ContentView()` in `PortyMcFolioApp.body`:

```swift
ContentView()
    .environmentObject(appState)
    .environment(\.theme, appState.theme)
    .tint(appState.theme.colors.accent)
    .onAppear {
        configureWindow()
        addWindowGrain()
        appState.startAppearanceObservers()
    }
    .onChange(of: appState.theme) { _, _ in
        configureWindow()
        updateGrainOpacity()
    }
    .onChange(of: appState.effectiveGrainOpacity) { _, _ in
        updateGrainOpacity()
    }
```

Add the helper:

```swift
    private func updateGrainOpacity() {
        if let window = NSApplication.shared.windows.first,
           let grain = window.contentView?.subviews.compactMap({ $0 as? GrainNSView }).first {
            grain.updateOpacity(appState.effectiveGrainOpacity)
        }
    }
```

- [ ] **Step 6.7: Build**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' build
```

Expected: `BUILD SUCCEEDED`. The app still compiles because `DT.Colors` is still alive — migration happens in Tasks 7–10.

- [ ] **Step 6.8: Commit**

```bash
git add PortyMcFolio/App/PortyMcFolioApp.swift \
        PortyMcFolio/App/AppState.swift \
        PortyMcFolio/Design/DesignTokens.swift
git commit -m "feat: inject theme at root, wire grain lifecycle, appearance observer"
```

---

## Task 7: Migrate views — batch 1 (tiny + small)

13 files with 2–10 `DT.Colors.*` references each. Each file gets the same 2-step treatment: add `@Environment(\.theme) var theme` inside the view struct, then sed-replace `DT.Colors.` with `theme.colors.` inside the file.

**Files:**
- Modify: `PortyMcFolio/Views/TagPillView.swift`
- Modify: `PortyMcFolio/Views/SplashView.swift`
- Modify: `PortyMcFolio/Views/FolderPickerView.swift`
- Modify: `PortyMcFolio/Views/ContentView.swift`
- Modify: `PortyMcFolio/Views/StatusBadgeView.swift`
- Modify: `PortyMcFolio/Views/LinkCardView.swift`
- Modify: `PortyMcFolio/Views/YearStepper.swift`
- Modify: `PortyMcFolio/Views/BreadcrumbBar.swift`
- Modify: `PortyMcFolio/Views/ProjectCardView.swift`
- Modify: `PortyMcFolio/Views/GalleryListView.swift`
- Modify: `PortyMcFolio/Views/NewProjectSheet.swift`
- Modify: `PortyMcFolio/Views/GalleryItemView.swift`
- Modify: `PortyMcFolio/Views/TagChipInput.swift`

- [ ] **Step 7.1: For each file, add the environment declaration**

Open each file. Inside the primary `struct ... : View` body, near the existing `@State` / `@Binding` / `@Environment` declarations, add:

```swift
@Environment(\.theme) var theme
```

If the file contains multiple `struct X: View` definitions that reference `DT.Colors`, each gets its own `@Environment(\.theme) var theme` declaration.

For `struct GalleryListRow: View` in `GalleryListView.swift`, the declaration goes alongside the existing `@State private var thumbnail: NSImage?` etc.

For the private `struct FolderGridCell: View` defined near the top of `GalleryView.swift` — note it's in a DIFFERENT file (migration handled in Task 9), skip here.

- [ ] **Step 7.2: Find-and-replace inside each file**

For each of the 13 files, run:

```bash
sed -i '' 's/DT\.Colors\./theme.colors./g' PortyMcFolio/Views/<filename>.swift
```

Or with a single command for all 13:

```bash
for f in TagPillView SplashView FolderPickerView ContentView StatusBadgeView LinkCardView YearStepper BreadcrumbBar ProjectCardView GalleryListView NewProjectSheet GalleryItemView TagChipInput; do
  sed -i '' 's/DT\.Colors\./theme.colors./g' "PortyMcFolio/Views/${f}.swift"
done
```

- [ ] **Step 7.3: Build**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' build
```

Expected: `BUILD SUCCEEDED`. If compile errors mention missing `theme`, the `@Environment` declaration was missed — add it and rebuild.

- [ ] **Step 7.4: Run full test suite**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test
```

Expected: all tests pass.

- [ ] **Step 7.5: Commit**

```bash
git add PortyMcFolio/Views/TagPillView.swift \
        PortyMcFolio/Views/SplashView.swift \
        PortyMcFolio/Views/FolderPickerView.swift \
        PortyMcFolio/Views/ContentView.swift \
        PortyMcFolio/Views/StatusBadgeView.swift \
        PortyMcFolio/Views/LinkCardView.swift \
        PortyMcFolio/Views/YearStepper.swift \
        PortyMcFolio/Views/BreadcrumbBar.swift \
        PortyMcFolio/Views/ProjectCardView.swift \
        PortyMcFolio/Views/GalleryListView.swift \
        PortyMcFolio/Views/NewProjectSheet.swift \
        PortyMcFolio/Views/GalleryItemView.swift \
        PortyMcFolio/Views/TagChipInput.swift
git commit -m "refactor: migrate tiny + small views to @Environment(\.theme)"
```

---

## Task 8: Migrate views — batch 2 (medium)

4 files with 13–20 `DT.Colors.*` references each.

**Files:**
- Modify: `PortyMcFolio/Views/EditLinkSheet.swift`
- Modify: `PortyMcFolio/Views/ProjectSettingsPopover.swift`
- Modify: `PortyMcFolio/Views/ProjectDetailView.swift`
- Modify: `PortyMcFolio/Views/SearchPalette.swift`

- [ ] **Step 8.1: Add `@Environment(\.theme) var theme` to each file's primary `View` struct**

Note: some of these have multiple helper struct views in the same file (e.g. `SplitDivider` inside `ProjectDetailView.swift`). Every struct that references `DT.Colors.*` gets its own declaration.

`ProjectDetailView.swift` has `struct ProjectDetailView` and `struct SplitDivider`. Check each for `DT.Colors` usage and add the declaration where needed.

`SearchPalette.swift` is a large file — check every `struct X: View` for usage.

- [ ] **Step 8.2: Find-and-replace inside each file**

```bash
for f in EditLinkSheet ProjectSettingsPopover ProjectDetailView SearchPalette; do
  sed -i '' 's/DT\.Colors\./theme.colors./g' "PortyMcFolio/Views/${f}.swift"
done
```

- [ ] **Step 8.3: Build**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 8.4: Run full test suite**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test
```

Expected: all tests pass.

- [ ] **Step 8.5: Commit**

```bash
git add PortyMcFolio/Views/EditLinkSheet.swift \
        PortyMcFolio/Views/ProjectSettingsPopover.swift \
        PortyMcFolio/Views/ProjectDetailView.swift \
        PortyMcFolio/Views/SearchPalette.swift
git commit -m "refactor: migrate medium views to @Environment(\.theme)"
```

---

## Task 9: Migrate views — batch 3 (large)

4 files with 24+ `DT.Colors.*` references each. Includes `GalleryView.swift` which also defines the private `FolderGridCell` struct.

**Files:**
- Modify: `PortyMcFolio/Views/GalleryView.swift`
- Modify: `PortyMcFolio/Views/CleanupPopup.swift`
- Modify: `PortyMcFolio/Views/ProjectListView.swift`
- Modify: `PortyMcFolio/Views/StyleGuideView.swift`

- [ ] **Step 9.1: Add `@Environment(\.theme) var theme` to each `View` struct in each file**

In `GalleryView.swift`, declarations go in:
- `struct GalleryView: View`
- `private struct FolderGridCell: View`

In `ProjectListView.swift`, declarations go in every `struct X: View` (there are helper views inside the file — check all).

In `StyleGuideView.swift`, the single `struct StyleGuideView: View`.

In `CleanupPopup.swift`, the single `struct CleanupPopup: View`.

- [ ] **Step 9.2: Find-and-replace**

```bash
for f in GalleryView CleanupPopup ProjectListView StyleGuideView; do
  sed -i '' 's/DT\.Colors\./theme.colors./g' "PortyMcFolio/Views/${f}.swift"
done
```

- [ ] **Step 9.3: Build**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 9.4: Run full test suite**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test
```

Expected: all tests pass.

- [ ] **Step 9.5: Commit**

```bash
git add PortyMcFolio/Views/GalleryView.swift \
        PortyMcFolio/Views/CleanupPopup.swift \
        PortyMcFolio/Views/ProjectListView.swift \
        PortyMcFolio/Views/StyleGuideView.swift
git commit -m "refactor: migrate large views to @Environment(\.theme)"
```

---

## Task 10: Delete `DT.Colors` + clean up dead code

All views now read `theme.colors.X`. Delete the static `DT.Colors` enum, the unused `GrainTexture` / `dtGrain()`, and fix any compile errors that surface.

**Files:**
- Modify: `PortyMcFolio/Design/DesignTokens.swift`

- [ ] **Step 10.1: Delete `enum DT.Colors`**

Open `PortyMcFolio/Design/DesignTokens.swift`. Delete the entire `// MARK: Colors` block and its `enum Colors { ... }`. Keep `Typography`, `Spacing`, `Radius`, `Shadow`, `Grain` (just the `opacity` constant).

- [ ] **Step 10.2: Delete the unused `GrainTexture` struct and `.dtGrain()` modifier**

In the same file, delete:
- `struct GrainTexture: View { ... }` (around line 125–143)
- `extension View { func dtGrain() -> some View { ... } }` (around line 145–149)

Keep `final class GrainNSView` — it's used by `PortyMcFolioApp.addWindowGrain()`.

- [ ] **Step 10.3: Build and resolve any remaining errors**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' build
```

If compile errors mention `DT.Colors` in files not yet migrated, migrate them (repeat Task 7-style treatment on each). If errors come from non-view sites (e.g., the previously-skipped `AppSettingsView.swift` which hasn't been rewritten yet), do one of:
- **For AppSettingsView specifically:** it gets fully rewritten in Task 12, so if it still reads `DT.Colors`, temporarily migrate it using the same pattern as Task 7 (add `@Environment(\.theme)`, sed-replace). The full rewrite in Task 12 supersedes this.
- **For any other non-view site:** add `@Environment(\.theme) var theme` if it's a view, or take `theme: Theme` as a parameter if it's a helper.

Repeat build until clean.

- [ ] **Step 10.4: Run full test suite**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test
```

Expected: all tests pass.

- [ ] **Step 10.5: Commit**

```bash
git add PortyMcFolio/Design/DesignTokens.swift
# also any temporary AppSettingsView migration if it was needed
git commit -m "refactor: delete DT.Colors and unused GrainTexture dead code"
```

---

## Task 11: `Theme.cssVariables(appearance:)` method (TDD)

The method exports the active theme as a CSS `:root { --color-…: …; }` block with NSColor bridges resolved to hex.

**Files:**
- Modify: `PortyMcFolio/Design/Theme.swift`
- Create: `PortyMcFolioTests/ThemeCSSTests.swift`

- [ ] **Step 11.1: Write the failing tests**

Create `PortyMcFolioTests/ThemeCSSTests.swift`:

```swift
import XCTest
import AppKit
@testable import PortyMcFolio

final class ThemeCSSTests: XCTestCase {
    private let aqua = NSAppearance(named: .aqua)!
    private let darkAqua = NSAppearance(named: .darkAqua)!

    private let expectedVars = [
        "--color-background",
        "--color-background-alt",
        "--color-surface",
        "--color-surface-hover",
        "--color-text-primary",
        "--color-text-secondary",
        "--color-text-tertiary",
        "--color-border",
        "--color-accent",
        "--color-status-draft",
        "--color-status-active",
        "--color-status-complete",
        "--color-status-archived",
        "--color-error",
    ]

    func testPortyCSSContainsAllVariables() {
        let css = Theme.porty.cssVariables(appearance: aqua)
        for name in expectedVars {
            XCTAssertTrue(css.contains(name), "missing \(name) in Porty CSS")
        }
    }

    func testOSXCSSContainsAllVariables() {
        let css = Theme.osx.cssVariables(appearance: darkAqua)
        for name in expectedVars {
            XCTAssertTrue(css.contains(name), "missing \(name) in OSX CSS")
        }
    }

    func testBWCSSContainsAllVariables() {
        let css = Theme.bw.cssVariables(appearance: aqua)
        for name in expectedVars {
            XCTAssertTrue(css.contains(name), "missing \(name) in BW CSS")
        }
    }

    func testPortyLightBackgroundHexInCSS() {
        let css = Theme.porty.cssVariables(appearance: aqua)
        XCTAssertTrue(css.contains("--color-background: #F0F1F5"),
                      "expected Porty light background hex in CSS, got:\n\(css)")
    }

    func testPortyDarkBackgroundHexInCSS() {
        let css = Theme.porty.cssVariables(appearance: darkAqua)
        XCTAssertTrue(css.contains("--color-background: #1C1E22"),
                      "expected Porty dark background hex in CSS, got:\n\(css)")
    }

    func testCSSStartsWithRootSelector() {
        let css = Theme.porty.cssVariables(appearance: aqua)
        XCTAssertTrue(css.contains(":root"),
                      "expected `:root` selector in CSS, got:\n\(css)")
    }
}
```

- [ ] **Step 11.2: Run tests, confirm they fail**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test \
  -only-testing:PortyMcFolioTests/ThemeCSSTests
```

Expected: compile error — `cannot find 'cssVariables' in scope`.

- [ ] **Step 11.3: Implement `cssVariables`**

Append to `PortyMcFolio/Design/Theme.swift`:

```swift
extension Theme {
    /// CSS custom property declarations for the current appearance. NSColor
    /// bridges (used by the OSX theme) resolve to hex at call time.
    /// Called by both the markdown preview and the CodeMirror editor
    /// bundle whenever the theme or appearance changes.
    func cssVariables(appearance: NSAppearance) -> String {
        let c = colors
        return """
        :root {
          --color-background: \(c.background.hex(for: appearance));
          --color-background-alt: \(c.backgroundAlt.hex(for: appearance));
          --color-surface: \(c.surface.hex(for: appearance));
          --color-surface-hover: \(c.surfaceHover.hex(for: appearance));
          --color-text-primary: \(c.textPrimary.hex(for: appearance));
          --color-text-secondary: \(c.textSecondary.hex(for: appearance));
          --color-text-tertiary: \(c.textTertiary.hex(for: appearance));
          --color-border: \(c.border.hex(for: appearance));
          --color-accent: \(c.accent.hex(for: appearance));
          --color-status-draft: \(c.statusDraft.hex(for: appearance));
          --color-status-active: \(c.statusActive.hex(for: appearance));
          --color-status-complete: \(c.statusComplete.hex(for: appearance));
          --color-status-archived: \(c.statusArchived.hex(for: appearance));
          --color-error: \(c.error.hex(for: appearance));
        }
        """
    }
}
```

- [ ] **Step 11.4: Regenerate xcodeproj**

```bash
xcodegen generate
```

- [ ] **Step 11.5: Run tests, confirm they pass**

Same command as Step 11.2. Expected: all 6 tests pass.

- [ ] **Step 11.6: Commit**

```bash
git add PortyMcFolio/Design/Theme.swift \
        PortyMcFolioTests/ThemeCSSTests.swift
git commit -m "feat: Theme.cssVariables(appearance:) for WebView injection"
```

- [ ] **Step 11.7: Commit xcodeproj regen**

```bash
git add PortyMcFolio.xcodeproj/project.pbxproj
git commit -m "chore: regenerate xcodeproj for ThemeCSSTests"
```

---

## Task 12: Settings tab rewrite

Replace `AppSettingsView` with a real settings tab. New top-to-bottom order: Header, Appearance, Workspace, Portfolio, Help & Shortcuts, Footer.

**Files:**
- Modify: `PortyMcFolio/Views/AppSettingsView.swift`

- [ ] **Step 12.1: Rewrite the file**

Replace the ENTIRE contents of `PortyMcFolio/Views/AppSettingsView.swift` with:

```swift
import SwiftUI

struct AppSettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var logo: NSImage?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                divider
                appearanceSection
                divider
                workspaceSection
                divider
                portfolioSection
                divider
                Text("Help & Shortcuts")
                    .font(DT.Typography.title)
                    .foregroundStyle(theme.colors.textPrimary)
                    .padding(.bottom, DT.Spacing.lg)
                viewModesSection
                divider
                editorSection
                divider
                gallerySection
                divider
                searchSection
                divider
                projectsSection
                divider
                shortcutsSection

                HStack {
                    Spacer()
                    Text("Minimal Lovable Software by Mold&Yeast")
                        .font(DT.Typography.caption)
                        .foregroundStyle(theme.colors.textTertiary)
                    Spacer()
                }
                .padding(.top, 48)
            }
            .padding(DT.Spacing.xl)
            .padding(.bottom, 64)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.background)
        .background {
            Button("") { appState.isShowingSettings = false }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
                .allowsHitTesting(false)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    appState.isShowingSettings = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.colors.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Back to projects")
            }
            ToolbarItem(placement: .principal) {
                Text("Settings")
                    .font(DT.Typography.headline)
                    .foregroundStyle(theme.colors.textPrimary)
            }
        }
        .onAppear { logo = loadLogo() }
        .onChange(of: colorScheme) { _, _ in logo = loadLogo() }
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(theme.colors.border)
            .frame(height: 0.5)
            .padding(.vertical, 32)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.md) {
            if let image = logo {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 160, height: 160)
                    .padding(.bottom, DT.Spacing.sm)
            }

            Text("Porty McFolio")
                .font(DT.Typography.largeTitle)
                .foregroundStyle(theme.colors.textPrimary)

            Text("A minimal portfolio manager for creatives. Organize projects in folders, write markdown documentation, manage files and links, and export when ready.")
                .font(DT.Typography.body)
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        section("Appearance") {
            HStack(spacing: DT.Spacing.md) {
                ForEach(Theme.all, id: \.id) { t in
                    themeCard(t)
                }
            }
        }
    }

    private func themeCard(_ t: Theme) -> some View {
        let isSelected = t.id == appState.themeID
        return VStack(alignment: .leading, spacing: DT.Spacing.sm) {
            HStack(spacing: 2) {
                swatch(t.colors.background)
                swatch(t.colors.surface)
                swatch(t.colors.textPrimary)
                swatch(t.colors.accent)
            }
            Text(t.name)
                .font(DT.Typography.headline)
                .foregroundStyle(theme.colors.textPrimary)
            Text(description(for: t.id))
                .font(DT.Typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .padding(DT.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected ? theme.colors.accent.opacity(0.12) : theme.colors.surface,
            in: RoundedRectangle(cornerRadius: DT.Radius.medium)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.medium)
                .stroke(
                    isSelected ? theme.colors.accent : theme.colors.border,
                    lineWidth: isSelected ? 2 : 0.5
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            appState.themeID = t.id
        }
    }

    private func swatch(_ c: Color) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(c)
            .frame(width: 20, height: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(theme.colors.border, lineWidth: 0.5)
            )
    }

    private func description(for id: Theme.ID) -> String {
        switch id {
        case .porty: return "Warm, branded"
        case .osx:   return "Native Apple"
        case .bw:    return "Monochrome"
        }
    }

    // MARK: - Workspace

    private var workspaceSection: some View {
        section("Workspace") {
            // Default view mode
            VStack(alignment: .leading, spacing: DT.Spacing.xs) {
                Text("Default view mode")
                    .font(DT.Typography.body)
                    .foregroundStyle(theme.colors.textPrimary)
                Picker("", selection: $appState.defaultViewMode) {
                    Text("Last used").tag(AppState.DefaultViewMode.lastUsed)
                    Text("Editor").tag(AppState.DefaultViewMode.editor)
                    Text("Preview").tag(AppState.DefaultViewMode.preview)
                    Text("Split").tag(AppState.DefaultViewMode.split)
                    Text("Gallery").tag(AppState.DefaultViewMode.gallery)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("Which mode opens first when you enter a project.")
                    .font(DT.Typography.caption)
                    .foregroundStyle(theme.colors.textTertiary)
            }

            // Auto-save delay
            VStack(alignment: .leading, spacing: DT.Spacing.xs) {
                HStack {
                    Text("Auto-save delay")
                        .font(DT.Typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                    Spacer()
                    Text(String(format: "%.1fs", appState.autoSaveDelay))
                        .font(DT.Typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .monospacedDigit()
                }
                Slider(value: $appState.autoSaveDelay, in: 0.5...5.0, step: 0.5)
                Text("How long the editor waits after your last keystroke before saving.")
                    .font(DT.Typography.caption)
                    .foregroundStyle(theme.colors.textTertiary)
            }

            // Grain overlay
            VStack(alignment: .leading, spacing: DT.Spacing.xs) {
                Toggle(isOn: $appState.grainEnabled) {
                    Text("Grain overlay")
                        .font(DT.Typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                }
                if appState.grainEnabled {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { appState.grainOpacityOverride ?? theme.grainOpacity },
                                set: { appState.grainOpacityOverride = $0 }
                            ),
                            in: 0.0...0.10,
                            step: 0.01
                        )
                        Button("Reset") {
                            appState.grainOpacityOverride = nil
                        }
                        .buttonStyle(.borderless)
                        .font(DT.Typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                    }
                }
                Text("Subtle film-grain texture over the window.")
                    .font(DT.Typography.caption)
                    .foregroundStyle(theme.colors.textTertiary)
            }
        }
    }

    // MARK: - Portfolio

    private var portfolioSection: some View {
        section("Portfolio") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Portfolio folder")
                        .font(DT.Typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(appState.portfolioRootURL?.path ?? "—")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Change…") {
                    pickPortfolioFolder()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func pickPortfolioFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select your portfolio folder"
        panel.prompt = "Use This Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        appState.setRoot(url)
    }

    // MARK: - View Modes (existing help content)

    private var viewModesSection: some View {
        section("View Modes") {
            featureRow(
                icon: "doc.text",
                title: "Editor",
                description: "Write and edit your project markdown file. Auto-saves after 1.5 seconds of inactivity."
            )
            featureRow(
                icon: "eye",
                title: "Preview",
                description: "Rendered markdown with embedded media, link cards, and file badges. Export to HTML from here."
            )
            featureRow(
                icon: "rectangle.split.2x1",
                title: "Split",
                description: "Editor on the left, gallery on the right. Drag the divider to resize, double-click to reset."
            )
            featureRow(
                icon: "square.grid.2x2",
                title: "Gallery",
                description: "Browse project files, folders, and saved links. Grid, list, or links view."
            )
        }
    }

    // MARK: - Editor (existing help content)

    private var editorSection: some View {
        section("Editor") {
            featureRow(
                icon: "photo",
                title: "Embeds",
                description: "Type ![[filename]] to embed images, videos, audio, or file cards. Drag files from Finder to auto-insert."
            )
            featureRow(
                icon: "slash.circle",
                title: "Slash Commands",
                description: "Type / to open the command menu. Insert headings, lists, code blocks, tables, media, and links."
            )
            featureRow(
                icon: "list.bullet",
                title: "Smart Lists",
                description: "Press Enter to continue bullet or numbered lists. Empty items exit the list. Numbering auto-increments."
            )
        }
    }

    // MARK: - Gallery (existing help content)

    private var gallerySection: some View {
        section("Gallery & Files") {
            featureRow(
                icon: "folder.badge.plus",
                title: "File Management",
                description: "Add files, create folders, drag to rearrange. Cut and paste files between folders. Right-click for more actions."
            )
            featureRow(
                icon: "link",
                title: "Links",
                description: "Save URLs with titles and notes. Stored as markdown files in your project folder. Switch to links view to browse."
            )
            featureRow(
                icon: "sparkles",
                title: "Cleanup",
                description: "Step through files one by one. Rename, move to folders, or delete. Navigate with \u{2318}Arrow keys."
            )
        }
    }

    // MARK: - Search (existing help content)

    private var searchSection: some View {
        section("Search") {
            Text("Press \u{2318}K to open the command palette. Search across projects, files, links, and tags. Use arrow keys to navigate, Enter to open.")
                .font(DT.Typography.body)
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Projects (existing help content)

    private var projectsSection: some View {
        section("Projects") {
            featureRow(
                icon: "eye.slash",
                title: "Hidden Projects",
                description: "Mark projects as hidden in their settings. Toggle the eye icon in the toolbar to filter them out — one click to make your portfolio presentation-safe."
            )
            featureRow(
                icon: "folder",
                title: "Folder Structure",
                description: "Each project lives in a folder named year_slug_uid. The project file (same name as the folder, .md) holds metadata as YAML frontmatter and your project body as markdown."
            )
            featureRow(
                icon: "tag",
                title: "Metadata",
                description: "Title, year, client, status, tags, and teaser image. Edit from the gear icon inside a project."
            )
            featureRow(
                icon: "square.and.arrow.up",
                title: "Export",
                description: "In preview mode, click the export icon to save as a standalone HTML page with all referenced assets."
            )

            VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                Text("STATUS TYPES")
                    .font(DT.Typography.micro)
                    .foregroundStyle(theme.colors.textTertiary)
                    .tracking(1)

                HStack(spacing: DT.Spacing.md) {
                    ForEach([ProjectStatus.empty, .inProgress, .archived], id: \.self) { s in
                        StatusBadgeView(status: s)
                    }
                }
            }
            .padding(.top, DT.Spacing.xs)
        }
    }

    // MARK: - Shortcuts (existing help content)

    private var shortcutsSection: some View {
        section("Keyboard Shortcuts") {
            subsection("Global") {
                shortcutRow("Search & Commands", "\u{2318}K")
                shortcutRow("New Project", "\u{2318}N")
                shortcutRow("Editor / Preview", "\u{2318}1")
                shortcutRow("Split View", "\u{2318}2")
                shortcutRow("Gallery", "\u{2318}3")
                shortcutRow("Project Settings", "\u{2318}4")
                shortcutRow("Back to Projects", "\u{238B}")
            }

            subsection("Editor") {
                shortcutRow("Bold", "\u{2318}B")
                shortcutRow("Italic", "\u{2318}I")
                shortcutRow("Strikethrough", "\u{2318}\u{21E7}S")
                shortcutRow("Inline Code", "\u{2318}E")
                shortcutRow("Heading 1 / 2 / 3", "\u{2318}\u{21E7}1\u{2013}3")
                shortcutRow("Insert Link", "\u{2318}\u{21E7}K")
                shortcutRow("Find", "\u{2318}F")
            }

            subsection("Gallery") {
                shortcutRow("Quick Look", "\u{2423}")
                shortcutRow("Cut File", "\u{2318}X")
                shortcutRow("Paste File", "\u{2318}V")
                shortcutRow("Go Up a Folder", "\u{2318}[")
                shortcutRow("Navigate Files", "\u{2190}\u{2191}\u{2193}\u{2192}")
            }
        }
    }

    // MARK: - Helpers

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DT.Spacing.lg) {
            Text(title)
                .font(DT.Typography.title)
                .foregroundStyle(theme.colors.textPrimary)

            content()
        }
    }

    private func subsection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DT.Spacing.xs) {
            Text(title.uppercased())
                .font(DT.Typography.micro)
                .foregroundStyle(theme.colors.textTertiary)
                .tracking(1)
                .padding(.bottom, DT.Spacing.xs)

            content()
        }
        .padding(.bottom, DT.Spacing.sm)
    }

    private func shortcutRow(_ label: String, _ keys: String) -> some View {
        HStack {
            Text(label)
                .font(DT.Typography.body)
                .foregroundStyle(theme.colors.textSecondary)
            Spacer()
            Text(keys)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.horizontal, DT.Spacing.sm)
                .padding(.vertical, 3)
                .background(theme.colors.backgroundAlt, in: RoundedRectangle(cornerRadius: DT.Radius.small))
        }
        .padding(.vertical, 2)
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: DT.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.textTertiary)
                .frame(width: 24, height: 20, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DT.Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(description)
                    .font(DT.Typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loadLogo() -> NSImage? {
        let name = colorScheme == .dark ? "logo-dark" : "logo-light"
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg") else { return nil }
        return NSImage(contentsOf: url)
    }
}
```

- [ ] **Step 12.2: Build**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 12.3: Run full test suite**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test
```

Expected: all tests pass.

- [ ] **Step 12.4: Manual smoke**

Launch the app, open Settings:
- Appearance section shows 3 theme cards; click each, confirm the whole app repaints.
- Workspace section: Default view mode picker, Auto-save delay slider, Grain toggle + slider + Reset.
- Portfolio section: current path shown, Change… button opens folder picker.
- Help & Shortcuts content renders like before.

- [ ] **Step 12.5: Commit**

```bash
git add PortyMcFolio/Views/AppSettingsView.swift
git commit -m "feat: Settings tab with theme picker + workspace preferences"
```

---

## Task 13: Markdown preview WebView bridge

Rename CSS vars in `preview.html` to match Swift's `cssVariables(appearance:)` output. Inject the `<style id="porty-theme-vars">` block via `WKUserScript` at load, and update it live via `evaluateJavaScript` on theme/appearance change.

**Files:**
- Modify: `PortyMcFolio/Editor/Resources/preview.html`
- Modify: `PortyMcFolio/Views/MarkdownPreviewView.swift`

- [ ] **Step 13.1: Update `preview.html` to use the new CSS variable names**

Open `PortyMcFolio/Editor/Resources/preview.html`. Find the `:root { ... }` block and the `@media (prefers-color-scheme: dark) { :root { ... } }` block. Replace the entire `:root` (and delete the `@media` block) with a hollow placeholder that Swift will fill at load time:

```html
<style id="porty-theme-vars">
/* Populated at load time by MarkdownPreviewView. */
:root {
  --color-background: #F0F1F5;
  --color-background-alt: #E2E4EB;
  --color-surface: #F8F9FB;
  --color-surface-hover: #EAECF1;
  --color-text-primary: #1A1D24;
  --color-text-secondary: #5C6275;
  --color-text-tertiary: #8B92A4;
  --color-border: #D8DBE3;
  --color-accent: #B34778;
}
</style>
```

Then find-and-replace the existing variable names in the remaining CSS (inside the subsequent `<style>` block):

| Old var          | New var                     |
| ---------------- | --------------------------- |
| `--text`         | `--color-text-primary`      |
| `--text-secondary` | `--color-text-secondary`  |
| `--text-tertiary`  | `--color-text-tertiary`   |
| `--bg`           | `--color-background`        |
| `--bg-code`      | `--color-background-alt`    |
| `--surface`      | `--color-surface`           |
| `--surface-hover` | `--color-surface-hover`    |
| `--border`       | `--color-border`            |
| `--accent`       | `--color-accent`            |

Bulk replacement (run from the repo root):

```bash
f=PortyMcFolio/Editor/Resources/preview.html
sed -i '' -E '
s/var\(--text\)/var(--color-text-primary)/g;
s/var\(--text-secondary\)/var(--color-text-secondary)/g;
s/var\(--text-tertiary\)/var(--color-text-tertiary)/g;
s/var\(--bg-code\)/var(--color-background-alt)/g;
s/var\(--bg\)/var(--color-background)/g;
s/var\(--surface-hover\)/var(--color-surface-hover)/g;
s/var\(--surface\)/var(--color-surface)/g;
s/var\(--border\)/var(--color-border)/g;
s/var\(--accent\)/var(--color-accent)/g;
' "$f"
```

Open the file and visually confirm — some fragments may have rare usages (e.g. `rgba(179, 71, 120, …)` literals in the `::selection` rule, which should become `color-mix(in srgb, var(--color-accent) 25%, transparent)` or just kept as a literal since it's a static selection color). Leave static literals alone unless clearly wrong.

- [ ] **Step 13.2: Inject the theme at WebView load time in `MarkdownPreviewView.swift`**

Open `PortyMcFolio/Views/MarkdownPreviewView.swift`. Find where the WKWebView is configured (around line 40–60). Add a user content controller with a user script that replaces the `porty-theme-vars` style block's text content with the active theme's CSS:

```swift
// Inside the view's makeNSView or similar setup — alongside the existing
// WKWebViewConfiguration setup:

let config = WKWebViewConfiguration()
// ... existing config ...

let css = appState.theme.cssVariables(appearance: NSApp.effectiveAppearance)
let escaped = css.replacingOccurrences(of: "\\", with: "\\\\")
               .replacingOccurrences(of: "`", with: "\\`")
               .replacingOccurrences(of: "$", with: "\\$")
let js = """
(function() {
  const style = document.getElementById('porty-theme-vars');
  if (style) { style.textContent = `\(escaped)`; }
})();
"""
let userScript = WKUserScript(
    source: js,
    injectionTime: .atDocumentEnd,
    forMainFrameOnly: true
)
config.userContentController.addUserScript(userScript)
```

Also add an observer on the view that re-invokes the injection when `appState.theme` or `appState.appearanceSignal` changes. The exact placement depends on `MarkdownPreviewView`'s current structure (SwiftUI `View` wrapping an `NSViewRepresentable`). Pattern:

```swift
// In the SwiftUI View body:
.onChange(of: appState.theme) { _, _ in reapplyTheme(webView) }
.onChange(of: appState.appearanceSignal) { _, _ in reapplyTheme(webView) }

// Helper:
private func reapplyTheme(_ webView: WKWebView) {
    let css = appState.theme.cssVariables(appearance: NSApp.effectiveAppearance)
    let escaped = css.replacingOccurrences(of: "\\", with: "\\\\")
                   .replacingOccurrences(of: "`", with: "\\`")
                   .replacingOccurrences(of: "$", with: "\\$")
    webView.evaluateJavaScript("""
      (function(){
        const s = document.getElementById('porty-theme-vars');
        if (s) { s.textContent = `\(escaped)`; }
      })();
    """)
}
```

Because `MarkdownPreviewView`'s structure may vary (check current code), the implementer adapts: if the WebView is held in an `ObservableObject` coordinator, call through it; if it's a stored property on an `NSViewRepresentable`, hold a reference in a `Coordinator` and invoke from there.

- [ ] **Step 13.3: Build and manual smoke**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' build
```

Expected: `BUILD SUCCEEDED`.

Launch, open a project with embedded images/links, switch to Preview mode. Confirm:
- Preview renders with Porty colors (default).
- Switch to BW via Settings → preview repaints to monochrome.
- Switch to OSX → preview picks up system accent color in links/headings.
- Toggle macOS dark/light → preview repaints.

- [ ] **Step 13.4: Commit**

```bash
git add PortyMcFolio/Editor/Resources/preview.html \
        PortyMcFolio/Views/MarkdownPreviewView.swift
git commit -m "feat: markdown preview reflects active theme via CSS variables"
```

---

## Task 14: CodeMirror editor theme + Vite rebuild

Rewrite `Editor/src/theme.js` as a single theme reading CSS variables. Remove the `prefers-color-scheme` watcher. Inject CSS vars from Swift at load + on change (same pattern as Task 13).

**Files:**
- Modify: `Editor/src/theme.js`
- Modify: `Editor/src/index.js` (remove watcher call)
- Modify: `PortyMcFolio/Views/MarkdownEditorView.swift` (inject CSS, observe theme)
- Rebuild: `Editor/dist/*` (via `npm run build` in the `Editor/` directory)

- [ ] **Step 14.1: Rewrite `Editor/src/theme.js`**

Replace the entire contents of `Editor/src/theme.js` with:

```js
import { EditorView } from '@codemirror/view'

/**
 * Single theme that reads CSS custom properties. The hosting Swift view
 * (MarkdownEditorView) injects a <style id="porty-theme-vars"> block at
 * load time and updates it on theme / appearance change via evaluateJavaScript.
 */
export const portyTheme = EditorView.theme({
  '&': {
    color: 'var(--color-text-primary)',
    backgroundColor: 'transparent',
    outline: 'none',
  },
  '&.cm-focused': {
    outline: 'none',
  },
  '.cm-content': {
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif",
    fontSize: '15px',
    lineHeight: '1.7',
    caretColor: 'var(--color-accent)',
    padding: '0',
  },
  '.cm-cursor': {
    borderLeftColor: 'var(--color-accent)',
  },
  '.cm-activeLine': {
    backgroundColor: 'color-mix(in srgb, var(--color-accent) 6%, transparent)',
  },
  '.cm-selectionBackground, .cm-content ::selection': {
    backgroundColor: 'color-mix(in srgb, var(--color-accent) 25%, transparent)',
  },
  '.cm-gutters': { display: 'none' },
  '.cm-line': { padding: '0' },
  '.cm-scroller': { overflowX: 'hidden' },
  '.cm-placeholder': {
    color: 'var(--color-text-tertiary)',
    fontStyle: 'normal',
  },
  '.cm-panels': {
    backgroundColor: 'var(--color-background-alt)',
    borderBottom: '1px solid var(--color-border)',
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
  },
  '.cm-searchMatch': {
    backgroundColor: 'color-mix(in srgb, var(--color-status-archived) 30%, transparent)',
  },
  '.cm-searchMatch-selected': {
    backgroundColor: 'color-mix(in srgb, var(--color-status-archived) 45%, transparent)',
  },
})
```

- [ ] **Step 14.2: Update `Editor/src/index.js` to use the single theme**

Find (around line 8):

```js
import { getSystemTheme, watchSystemTheme } from './theme.js'
```

Replace with:

```js
import { portyTheme } from './theme.js'
```

Find (around line 52 — inside the `extensions: [...]` array):

```js
getSystemTheme(),
```

Replace with:

```js
portyTheme,
```

Find (around line 63):

```js
watchSystemTheme(view)
```

Delete that line entirely. System dark/light is now driven by Swift-injected CSS variables.

- [ ] **Step 14.3: Inject CSS vars into the editor WebView in `MarkdownEditorView.swift`**

Open `PortyMcFolio/Views/MarkdownEditorView.swift`. Find the WKWebView configuration.

Look for where the editor's HTML file is loaded. Add a `WKUserScript` at `.atDocumentEnd` that inserts a `<style id="porty-theme-vars">...</style>` into `document.head` if not already present, populated with `appState.theme.cssVariables(...)`.

The editor's `index.html` probably does NOT currently have a `porty-theme-vars` style block (check — if it does, same as preview; if not, inject one). Safer to inject from Swift:

```swift
let css = appState.theme.cssVariables(appearance: NSApp.effectiveAppearance)
let escaped = css.replacingOccurrences(of: "\\", with: "\\\\")
               .replacingOccurrences(of: "`", with: "\\`")
               .replacingOccurrences(of: "$", with: "\\$")

let js = """
(function(){
  let style = document.getElementById('porty-theme-vars');
  if (!style) {
    style = document.createElement('style');
    style.id = 'porty-theme-vars';
    document.head.appendChild(style);
  }
  style.textContent = `\(escaped)`;
})();
"""
let userScript = WKUserScript(
    source: js,
    injectionTime: .atDocumentEnd,
    forMainFrameOnly: true
)
config.userContentController.addUserScript(userScript)
```

Add a live-update hook the same way as Task 13.2:

```swift
.onChange(of: appState.theme) { _, _ in reapplyTheme() }
.onChange(of: appState.appearanceSignal) { _, _ in reapplyTheme() }
```

Where `reapplyTheme()` re-runs the same `evaluateJavaScript` snippet on the webView.

- [ ] **Step 14.4: Pipe `autoSaveDelay` into the editor bundle**

Look for where `MarkdownEditorView` currently posts messages to the JS bridge (see `Editor/src/bridge.js` for the message API). Add an `updateAutoSaveDelay(_:)` method to the Swift side that posts the new delay to JS whenever `appState.autoSaveDelay` changes.

The JS side (in `Editor/src/index.js`) currently has hardcoded debounce behavior inside `postContentChanged` — update that to accept an updated delay via a new `window.PortyEditor.setAutoSaveDelay(seconds)` function. Wire the Swift `updateAutoSaveDelay(_:)` to call `webView.evaluateJavaScript("window.PortyEditor.setAutoSaveDelay(\(delay));")`.

**Note:** if the editor's current debounce is implemented in `bridge.js` (not `index.js`), update `bridge.js` instead. The implementer should inspect the current debounce site before editing.

- [ ] **Step 14.5: Rebuild the editor bundle**

```bash
cd Editor
npm run build
cd ..
```

- [ ] **Step 14.6: Build the Swift app**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 14.7: Manual smoke**

Launch, open a project, enter editor mode. Confirm:
- Cursor, selection, active-line highlight use the accent color.
- Switch to OSX theme → cursor becomes system blue.
- Switch to BW → cursor stays Porty pink (BW's accent).
- Toggle macOS dark/light → editor text + cursor color respond.
- Change auto-save delay in Settings → type in editor → saves fire at the new debounce.

- [ ] **Step 14.8: Commit**

```bash
git add Editor/src/theme.js \
        Editor/src/index.js \
        Editor/dist \
        PortyMcFolio/Views/MarkdownEditorView.swift
git commit -m "feat: CodeMirror editor reads CSS variables for theme + delay"
```

(If `Editor/dist/` is gitignored, only the `src/` files are committed; the build artifact is produced at build time.)

---

## Task 15: Export HTML theming

`MarkdownPreviewView.export(...)` currently generates a standalone HTML file with colors baked in. Make it take the active theme as a parameter and bake the theme's CSS variables into the exported HTML.

**Files:**
- Modify: `PortyMcFolio/Views/MarkdownPreviewView.swift`
- Modify: `PortyMcFolio/Views/ProjectDetailView.swift` (the single call site)

- [ ] **Step 15.1: Take `theme: Theme` as a parameter**

In `MarkdownPreviewView.swift`, find the static `export(...)` method. Update its signature to accept `theme: Theme`:

```swift
static func export(
    markdown: String,
    projectFolderURL: URL,
    projectTitle: String,
    projectYear: Int,
    theme: Theme
) {
    // ...
}
```

Inside the method, where the HTML is assembled with a `<style>` block, prepend a `:root { ... }` block populated from `theme.cssVariables(appearance: NSApp.effectiveAppearance)`. The existing `<style>` block then uses `var(--color-...)` references as Task 13 set up in `preview.html`.

- [ ] **Step 15.2: Update the call site in `ProjectDetailView.swift`**

Find the existing call:

```swift
MarkdownPreviewView.export(
    markdown: previewBody,
    projectFolderURL: project.folderURL,
    projectTitle: project.title,
    projectYear: project.year
)
```

Update to pass the theme (AppState is already an `@EnvironmentObject` in this view):

```swift
MarkdownPreviewView.export(
    markdown: previewBody,
    projectFolderURL: project.folderURL,
    projectTitle: project.title,
    projectYear: project.year,
    theme: appState.theme
)
```

- [ ] **Step 15.3: Build**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 15.4: Manual smoke**

Export a project in Porty, OSX, and BW. Open each exported HTML in Safari — confirm visual correctness, self-contained, colors match the theme at export time.

- [ ] **Step 15.5: Commit**

```bash
git add PortyMcFolio/Views/MarkdownPreviewView.swift \
        PortyMcFolio/Views/ProjectDetailView.swift
git commit -m "feat: exported HTML bakes the active theme's palette"
```

---

## Task 16: Final verification pass

End-to-end manual walk-through of the spec. No code changes — only test and observe.

- [ ] **Step 16.1: Full test suite**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test
```

Expected: all tests pass (Theme, ThemeCSS, ColorHex, plus all prior tests).

- [ ] **Step 16.2: Six-combo visual sweep**

For each combination (Porty × Light, Porty × Dark, OSX × Light, OSX × Dark, BW × Light, BW × Dark), launch the app and walk every major surface:

- Project list view (grid + table)
- Project detail editor
- Project detail preview (with embedded images + links)
- Gallery grid + list + links
- Cleanup popup
- Search palette (⌘K)
- New project sheet
- Project settings popover
- Settings tab (every section)
- Folder picker / splash

Look for: illegible text, invisible borders, missing hover/selection states, accent-color inconsistencies.

- [ ] **Step 16.3: Live-change verification**

Starting in any theme:
- Click a theme card in Settings → whole app repaints within one animation frame, no lost state (text field contents, scroll positions, selection).
- Toggle macOS appearance (System Settings → Appearance) mid-session → SwiftUI repaints, markdown preview repaints, editor repaints.
- Change macOS system accent color mid-session (OSX theme) → SwiftUI tint updates, editor/preview accent updates.

- [ ] **Step 16.4: Settings controls verification**

- Default view mode picker: set to Editor, open a project that was last in Preview → opens in Editor.
- Default view mode picker: set to Last used, open a project that was last in Gallery → opens in Gallery.
- Auto-save delay: set to 3.0s, type in editor, confirm save fires after ~3 seconds.
- Grain overlay: toggle off → grain disappears instantly. Toggle on → returns to theme default. Set opacity override via slider → grain intensity changes. Hit Reset → slider returns to theme default.
- Portfolio folder: Change… opens picker. Pick a different folder → app reloads with new portfolio. Pick the original back → restored.

- [ ] **Step 16.5: Export verification**

From each of the 3 themes, use the export icon in Preview mode. Open each exported HTML file in Safari with Safari's dark/light setting both ways. Confirm colors are self-contained (don't change with Safari's dark/light toggle — the theme is baked at export time).

- [ ] **Step 16.6: No commit**

Task 16 is verification-only. If all steps pass, the theming system is ready. If any step surfaces a regression, the fix happens as a targeted commit before merging the branch.

---

## Post-implementation

**Explicitly deferred follow-ups** (from the spec):

- Typography per theme (SF Pro for OSX, serif for BW).
- User-configurable accent regardless of theme.
- Accessibility scale multiplier for typography.
- Theme-aware iconography.
- Accent-follows-system-accent for Porty and BW.
- In-app appearance override (force light / force dark).
