# Theming System — Design Spec

**Date:** 2026-04-20
**Status:** design approved pending user review
**Scope:** Introduce a runtime-swappable theme system with three themes (Porty, OSX, BW), each responding to macOS system appearance (light/dark). Rebuild the existing "Guide" view as a real Settings tab housing the theme picker and four other preferences. Extend theming into the two WKWebView surfaces (markdown preview, CodeMirror editor).

## Goal

`DT.Colors.*` is currently a static enum of `Color(light:dark:)` values baked into the app. The UI feels branded and cohesive but there is no user choice. Users have asked for alternative themes — specifically a native-macOS look and a monochrome look — while keeping automatic response to the system's light/dark setting.

This spec introduces:
- A `Theme` struct with three instances (`.porty`, `.osx`, `.bw`), each a full palette.
- SwiftUI environment injection so theme changes propagate with SwiftUI's normal invalidation.
- A Settings tab that replaces the current info-only Guide view, housing the theme picker and four other workspace preferences, with the Guide content kept as a "Help & Shortcuts" section below.
- A CSS-variable bridge into the two WKWebViews so the markdown preview and CodeMirror editor reflect the active theme.

## Non-goals

- **No appearance override.** The app follows macOS system light/dark. No in-app "force light" / "force dark" toggle.
- **No typography theming.** `DT.Typography` stays theme-independent. (Deferred.)
- **No user-configurable accent.** The three themes' accents are fixed (Porty + BW use `B34778`, OSX uses `NSColor.controlAccentColor`). No user override. (Deferred.)
- **No Settings tab beyond the five items below.** Other prefs (font size, accessibility scaling, theme-aware iconography) are out of scope.
- **No feature flag.** Themes are always on.
- **No migration of existing user data.** First launch defaults to Porty (identical to today).

## Deployment target

Bump `MACOSX_DEPLOYMENT_TARGET` from `14.0` to `15.0` in `project.yml`, then run `xcodegen generate`. This unlocks the `@Entry` macro for cleaner environment key definitions.

## Affected files

### New

- `PortyMcFolio/Design/Theme.swift` — `Theme`, `ThemeColors`, `Theme.ID`, three palette definitions, CSS-variable export.
- `PortyMcFolio/Design/ColorHex.swift` — `Color.hex(for: NSAppearance)` helper.
- `PortyMcFolioTests/ThemeTests.swift` — round-trip + CSS-variable tests.

### Modified

- `PortyMcFolio/Design/DesignTokens.swift` — delete `enum DT.Colors`. Also delete the unused `GrainTexture` struct and `.dtGrain()` view modifier (dead code; only `GrainNSView` is used). Keep `DT.Typography/Spacing/Radius/Shadow` and the `GrainNSView` class. `DT.Grain.opacity` constant can stay as a safety fallback (the `effectiveGrainOpacity` computation never needs it in the happy path, but it's a 1-line constant).
- `PortyMcFolio/App/AppState.swift` — add `themeID: Theme.ID`, computed `theme: Theme`, load/persist.
- `PortyMcFolio/App/PortyMcFolioApp.swift` — inject `.environment(\.theme, appState.theme)` + `.tint(appState.theme.colors.accent)` at the root. Grain view lifecycle updated.
- `PortyMcFolio/Views/AppSettingsView.swift` — full rewrite: Appearance + Workspace + Portfolio sections above the existing Help & Shortcuts content. Toolbar title "Settings".
- All view files that read `DT.Colors.*` (~38 files) — add `@Environment(\.theme) var theme`, migrate call sites to `theme.colors.*`.
- `PortyMcFolio/Editor/PreviewSchemeHandler.swift` — CSS custom properties in the HTML template.
- `PortyMcFolio/Views/MarkdownPreviewView.swift` — pass active theme into `export()`.
- `Editor/src/theme.ts` (approximate path; confirm during implementation) — CodeMirror theme rewritten to read CSS variables.
- `project.yml` — deployment target bump.

No new Swift packages, no new npm deps for the editor bundle.

## 1. Theme architecture

### Types

Place in `PortyMcFolio/Design/Theme.swift`:

```swift
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

    static let porty: Theme = /* Section 2 */
    static let osx: Theme   = /* Section 2 */
    static let bw: Theme    = /* Section 2 */

    static let all: [Theme] = [.porty, .osx, .bw]

    static func named(_ id: ID) -> Theme {
        switch id {
        case .porty: return .porty
        case .osx:   return .osx
        case .bw:    return .bw
        }
    }
}
```

### Environment wiring

```swift
extension EnvironmentValues {
    @Entry var theme: Theme = .porty
}
```

### AppState additions

All preferences added in this spec live on `AppState` as `@Published` values with `didSet` persistence to UserDefaults. Loaded inside the existing `loadLayoutPreferences()` on launch.

```swift
// Theme
@Published var themeID: Theme.ID = .porty {
    didSet { UserDefaults.standard.set(themeID.rawValue, forKey: "themeID") }
}
var theme: Theme { Theme.named(themeID) }

// Default view mode when opening a project
enum DefaultViewMode: String, CaseIterable, Codable {
    case lastUsed, editor, preview, split, gallery
}
@Published var defaultViewMode: DefaultViewMode = .lastUsed {
    didSet { UserDefaults.standard.set(defaultViewMode.rawValue, forKey: "defaultViewMode") }
}

// Editor auto-save debounce delay (seconds)
@Published var autoSaveDelay: Double = 1.5 {
    didSet { UserDefaults.standard.set(autoSaveDelay, forKey: "autoSaveDelay") }
}

// Grain overlay
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

/// The effective grain opacity after applying toggle + user override + theme default.
/// `GrainNSView.updateOpacity(_:)` and any SwiftUI grain overlay read this.
var effectiveGrainOpacity: Double {
    guard grainEnabled else { return 0 }
    return grainOpacityOverride ?? theme.grainOpacity
}

// Appearance + accent signal — incremented whenever the system appearance
// or the OSX theme's accent changes (see Section 4).
@Published var appearanceSignal: Int = 0
```

`loadLayoutPreferences()` adds matching load paths for each key. Keys missing → default values.

### Root injection

In `PortyMcFolioApp.body`:

```swift
ContentView()
    .environmentObject(appState)
    .environment(\.theme, appState.theme)
    .tint(appState.theme.colors.accent)
```

When `appState.themeID` changes:
- `appState.objectWillChange` fires (via `@Published`).
- The WindowGroup's body re-evaluates (it observes appState via `@StateObject`).
- A new `Theme` is passed to `.environment(\.theme, …)`.
- Every view that reads `@Environment(\.theme)` invalidates and redraws.
- `.tint(…)` reapplies the new accent across SwiftUI controls.

### `DT` namespace fate

- `DT.Typography`, `DT.Spacing`, `DT.Radius`, `DT.Shadow` — **unchanged**, theme-independent.
- `DT.Colors` — **deleted**. Every call site migrates to `theme.colors.X`. No deprecated shim (a shim that returned Porty's values would silently break OSX and BW).
- `DT.Grain.opacity` — kept as a **fallback** constant (0.03) but the AppKit `GrainNSView` reads `appState.theme.grainOpacity` at init.

## 2. Palettes

### Porty (unchanged from today)

| Role            | Light    | Dark     |
| --------------- | -------- | -------- |
| background      | `F0F1F5` | `1C1E22` |
| backgroundAlt   | `E2E4EB` | `262A30` |
| surface         | `F8F9FB` | `2C2F36` |
| surfaceHover    | `EAECF1` | `393D47` |
| textPrimary     | `1A1D24` | `ECEEF3` |
| textSecondary   | `5C6275` | `A8AEBD` |
| textTertiary    | `8B92A4` | `7B8295` |
| border          | `D8DBE3` | `353940` |
| accent          | `B34778` | `B34778` |
| statusDraft     | `8E8E93` | `8E8E93` |
| statusActive    | `B34778` | `B34778` |
| statusComplete  | `3478F6` | `4A9AFF` |
| statusArchived  | `FF9500` | `FFA733` |
| error           | `E5484D` | `F85149` |

Grain opacity: `0.03`.

Name for picker: "Porty". Description: "Warm, branded".

### OSX (system defaults via `NSColor` bridges)

Constructed via `Color(nsColor:)` — each value pulls from the live AppKit semantic color, so dark/light and the user's system accent all flow through without any hex.

| Role            | NSColor binding                  |
| --------------- | -------------------------------- |
| background      | `.windowBackgroundColor`         |
| backgroundAlt   | `.underPageBackgroundColor`      |
| surface         | `.controlBackgroundColor`        |
| surfaceHover    | `.quaternaryLabelColor`          |
| textPrimary     | `.labelColor`                    |
| textSecondary   | `.secondaryLabelColor`           |
| textTertiary    | `.tertiaryLabelColor`            |
| border          | `.separatorColor`                |
| accent          | `.controlAccentColor`            |
| statusDraft     | `.systemGray`                    |
| statusActive    | `.systemBlue`                    |
| statusComplete  | `.systemGreen`                   |
| statusArchived  | `.systemOrange`                  |
| error           | `.systemRed`                     |

Grain opacity: `0.0` (OSX feel is clean, no texture).

Name for picker: "OSX". Description: "Native Apple".

### BW (monochrome surfaces, Porty accent)

| Role            | Light    | Dark     |
| --------------- | -------- | -------- |
| background      | `FFFFFF` | `000000` |
| backgroundAlt   | `F5F5F5` | `0F0F0F` |
| surface         | `FAFAFA` | `1A1A1A` |
| surfaceHover    | `F0F0F0` | `2A2A2A` |
| textPrimary     | `000000` | `FFFFFF` |
| textSecondary   | `555555` | `AAAAAA` |
| textTertiary    | `999999` | `666666` |
| border          | `DDDDDD` | `333333` |
| accent          | `B34778` | `B34778` |
| statusDraft     | `999999` | `666666` |
| statusActive    | `B34778` | `B34778` |
| statusComplete  | `000000` | `FFFFFF` |
| statusArchived  | `555555` | `AAAAAA` |
| error           | `000000` | `FFFFFF` |

Grain opacity: `0.02` (very subtle).

Name for picker: "BW". Description: "Monochrome".

Note: error color in BW is the primary-text color (not red) to preserve the monochrome constraint. Error states in UI lean on icon + weight rather than color. If this reads as "error state isn't visible enough" during manual verification, fall back to `#6B0A0A` light / `#FF6B6B` dark.

## 3. Settings tab UI

Rewrite `AppSettingsView` with this top-to-bottom order:

1. **Header** — logo + tagline. Unchanged.
2. **Appearance** — three theme cards (Porty, OSX, BW).
3. **Workspace** — default view mode, auto-save delay, grain overlay.
4. **Portfolio** — reset portfolio root button.
5. **Help & Shortcuts** — all existing Guide content (View Modes, Editor, Gallery, Search, Projects, Keyboard Shortcuts).
6. **Footer** — "Minimal Lovable Software by Mold&Yeast". Unchanged.

Toolbar title changes from "Guide" to "Settings".

### Appearance section

Horizontal `HStack` of three theme cards (wraps to a vertical stack on narrow windows). Each card:

- **Preview swatch row** — 4 colored squares (~20×20 with 2pt gap): background, surface, textPrimary, accent. Each resolved using the theme's light/dark values for the *current* system appearance.
- **Name** — "Porty" / "OSX" / "BW" (headline font).
- **Description** — one-line description (caption font, textSecondary).
- **Selected state** — 2pt accent border, `accent.opacity(0.12)` background tint.
- **Idle state** — 0.5pt border, surface background.
- **Hover state** — `surfaceHover` background.

Clicking a card sets `appState.themeID`. Live update — entire app repaints immediately.

Pseudo-layout:

```
┌─ Appearance ─────────────────────────────────────────────┐
│                                                          │
│ ┌──────────────────┐ ┌──────────────────┐ ┌──────────────┐
│ │ ▢ ▢ ▢ ▢          │ │ ▢ ▢ ▢ ▢          │ │ ▢ ▢ ▢ ▢      │
│ │                  │ │                  │ │              │
│ │ Porty  (active)  │ │ OSX              │ │ BW           │
│ │ Warm, branded    │ │ Native Apple     │ │ Monochrome   │
│ └──────────────────┘ └──────────────────┘ └──────────────┘
└──────────────────────────────────────────────────────────┘
```

### Workspace section

Three rows, each with a label + control + caption.

- **Default view mode** — segmented `Picker` bound to a new `@Published` on AppState: `defaultViewMode: DefaultViewMode` (enum: `.lastUsed`, `.editor`, `.preview`, `.split`, `.gallery`). `.lastUsed` is the default and matches today's behavior. Persisted to UserDefaults key `"defaultViewMode"`. When a project opens, if setting is `.lastUsed`, read the current `viewMode`; otherwise set `viewMode` to the explicit choice.
- **Auto-save delay** — `Slider` 0.5 → 5.0 step 0.5. Label shows current value (e.g., "1.5s"). Bound to `appState.autoSaveDelay`. Default 1.5. The debounce today lives inside the CodeMirror bundle; the Swift-side `MarkdownEditorView` passes the delay via the existing message bridge on init and whenever `autoSaveDelay` changes. The CodeMirror debouncer reconfigures on the message.
- **Grain overlay** — `Toggle` + `Slider`. Toggle bound to `appState.grainEnabled` (default `true`). Slider bound to `appState.grainOpacityOverride` (range `0.0` → `0.10` step `0.01`; `nil` means "use theme default"). The slider has a "Reset to theme default" button next to it that sets the override back to `nil`. `GrainNSView.updateOpacity(_:)` is called with `appState.effectiveGrainOpacity` whenever any of `grainEnabled`, `grainOpacityOverride`, or `themeID` changes.

### Portfolio section

Single row:

- **Current portfolio** — label "Portfolio folder" + truncated path (e.g., `…/PortyMcFolio Content`). Truncation uses `.truncationMode(.middle)`.
- **Change…** button — triggers the same folder picker currently used in `FolderPickerView`. On selection, calls `appState.setRoot(newURL)` which already tears down cleanly and reloads.
- No confirm dialog — `AppState.setRoot` is safe to call at any time; it stops the security-scoped bookmark for the old root before acquiring the new one.

### Help & Shortcuts section

Wrap all existing Guide content (the current `viewModesSection / editorSection / gallerySection / searchSection / projectsSection / shortcutsSection` blocks) under one heading "Help & Shortcuts". Separator (existing `divider` helper) above it.

### Visual language

- Typography: `DT.Typography.title` for the "Settings" screen title, `DT.Typography.headline` for each section header ("Appearance", "Workspace", etc.), `DT.Typography.body` for labels and descriptions, `DT.Typography.caption` for captions under controls.
- Spacing: keep the current rhythm — `DT.Spacing.xl` outer padding, `DT.Spacing.lg` between items inside a section, `DT.Spacing.md` within rows. Section separators unchanged (existing `divider` helper).
- Max content width: 640pt (unchanged).

## 4. WKWebView bridge (markdown preview + CodeMirror editor)

### Swift side: CSS-variable export

New method on `Theme`:

```swift
extension Theme {
    /// CSS custom property declarations for the current appearance.
    /// NSColor-bridged values resolve to hex at call time.
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

`Color.hex(for:)` in a new file `PortyMcFolio/Design/ColorHex.swift`:

```swift
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
            Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255))
        )
    }
}
```

`performAsCurrentDrawingAppearance(_:)` is macOS 11+ — safe on the new macOS 15 deployment target.

### Injection into WKWebView

Each `WKWebView` gets a `WKUserScript` at document start that injects:

```html
<style id="porty-theme-vars">/* initial CSS variables */</style>
```

Into `document.head`, populated with the active theme's CSS at load time.

On theme change OR appearance change OR system-accent change, the hosting view calls:

```swift
let css = theme.cssVariables(appearance: currentAppearance)
webView.evaluateJavaScript("""
  document.getElementById('porty-theme-vars').textContent = `\(css)`;
""")
```

Browsers re-evaluate `var(--…)` references immediately. No reload, no scroll jump.

### Triggers for re-injection

`AppState` listens via Combine:

- `AppleInterfaceThemeChangedNotification` (`DistributedNotificationCenter`) — fires on macOS dark/light toggle.
- `NSApplication.didChangeScreenParametersNotification` — loose-coupling for appearance/screen changes.
- KVO on `NSApp.effectiveAppearance` — the strict hook for appearance changes.

Exposed via a single `@Published var appearanceSignal: Int` that increments on any of the above. Views hosting WebViews observe both `appState.theme` and `appState.appearanceSignal`; either change triggers a re-inject.

### Markdown preview adjustments

`PreviewSchemeHandler` currently inlines colors in its HTML `<style>` block. Replace each literal hex with a `var(--color-…)` reference. No new CSS tokens invented — every existing color maps 1:1 to a theme variable. A per-file audit happens during implementation; the plan spec will enumerate the exact substitutions.

### Editor adjustments

CodeMirror 6 theme rewritten as a `EditorView.theme(...)` that reads CSS variables:

```ts
import { EditorView } from "@codemirror/view"

export const portyTheme = EditorView.theme({
  "&": {
    backgroundColor: "var(--color-background)",
    color: "var(--color-text-primary)",
  },
  ".cm-content": { caretColor: "var(--color-accent)" },
  ".cm-cursor": { borderLeftColor: "var(--color-accent)" },
  ".cm-selectionBackground, .cm-content ::selection": {
    backgroundColor: "color-mix(in srgb, var(--color-accent) 22%, transparent)"
  },
  ".cm-gutters": {
    backgroundColor: "var(--color-background-alt)",
    borderRight: "1px solid var(--color-border)",
  },
  ".cm-lineNumbers .cm-gutterElement": { color: "var(--color-text-tertiary)" },
  ".cm-activeLine": {
    backgroundColor: "color-mix(in srgb, var(--color-accent) 6%, transparent)"
  },
  // Syntax highlighting — map existing token colors to palette roles:
  // (exact mappings to be audited during implementation)
})
```

Bundle rebuilt with `npm run build` in `Editor/`. Resulting JS/CSS served by the existing bundle pipeline.

Syntax colors (keywords, strings, comments, etc.) are not part of the `ThemeColors` struct — they can be derived from a small set of semantic colors (e.g., keyword = accent, string = statusComplete, comment = textTertiary). Exact mapping audited during implementation; no new Swift-side tokens are added.

### Export HTML

`MarkdownPreviewView.export(…)` currently bakes colors inline. Take `theme: Theme` as a parameter; call sites (`ProjectDetailView`) pass `appState.theme`. Use `theme.cssVariables(appearance:)` with the current appearance at export time. The exported HTML is self-contained and looks correct offline.

### OSX live accent response

When the user changes their macOS system accent in System Settings while the app is running:
- SwiftUI side: `.tint(appState.theme.colors.accent)` re-resolves — but only when the view body re-evaluates. `NSColor.controlAccentColor` is a dynamic provider that updates lazily. The `AppleColorPreferencesChangedNotification` fires via `DistributedNotificationCenter.default`. AppState listens for it and increments `appearanceSignal` to force a refresh.
- WebView side: same signal triggers the `evaluateJavaScript` re-inject.

Single consolidated observer on AppState is the source of truth; all WebView-hosting views read `appearanceSignal`.

## 5. Migration strategy

### The 500+ call-site migration

Two-pass per view file:

**Pass 1 — add the environment declaration.** For each view file that reads `DT.Colors.X`:

```swift
struct SomeView: View {
    // ... existing state ...
    @Environment(\.theme) var theme  // <-- add this
    ...
}
```

This is a hand-written change — an `@Environment` declaration must land in the struct body at a consistent location, which sed can't reliably place.

**Pass 2 — find-and-replace** within that file: `DT.Colors.` → `theme.colors.`. Sed-safe.

After the two passes, **delete** `enum DT.Colors` from `DesignTokens.swift`. The compiler surfaces any remaining non-view call sites; fix each individually.

### Non-view call sites

These are the known places `DT.Colors` is read outside a SwiftUI view body. Each has a specific fix:

| File / function | Current form | Resolution |
| --------------- | ------------ | ---------- |
| `PortyMcFolioApp.configureWindow()` — `window.backgroundColor = NSColor(DT.Colors.background)` | Runs in `DispatchQueue.main.async` at scene launch | Inject `appState` into the scene closure; read `appState.theme.colors.background`. Re-run on `.onChange(of: appState.theme)` at the WindowGroup level. |
| `GrainNSView.init` — `layer?.opacity = Float(DT.Grain.opacity)` | AppKit view, no theme awareness | Add `func updateOpacity(_ value: Double)` that sets `layer?.opacity = Float(value)`. `addWindowGrain()` passes `appState.effectiveGrainOpacity` at creation. A tiny observer view inside `PortyMcFolioApp.body` (a hidden `.onChange(of: appState.effectiveGrainOpacity)` hook) walks `NSApplication.shared.windows.first?.contentView?.subviews` to the `GrainNSView` and calls `updateOpacity(newValue)`. Alternative: retain a reference to the `GrainNSView` inside `AppState` (weak) and call through that. Pick the simpler one during implementation. |
| `MarkdownPreviewView.export(…)` — static, bakes colors | No view context | Accept `theme: Theme` parameter; callers pass `appState.theme`. |
| `PreviewSchemeHandler` — template HTML with literal colors | Not a View | Hold a weak reference to `AppState`; read `appState.theme` at request time. Alternative: inject via an init parameter that the handler updates on theme change. |
| Anywhere the compiler flags post-delete | TBD | If startup / helper: read from injected `AppState`. If pure transform: add `theme: Theme` parameter. |

### Test previews

SwiftUI previews using `DT.Colors.*` today won't compile after the migration. Two options:
- Add `.environment(\.theme, .porty)` to preview scopes. Explicit but verbose.
- Rely on the environment default (`.porty`) — existing previews "just work" because the default matches.

Preferred: rely on the default. Add explicit `.environment(\.theme, .osx)` or `.bw` only when a preview specifically wants to show a non-default theme.

## 6. Testing

### Unit tests (low-value for data, still worth it for contracts)

`PortyMcFolioTests/ThemeTests.swift`:

- `testNamedRoundTrip` — `Theme.named(.porty).id == .porty`, same for `.osx` and `.bw`.
- `testAllEnumerates` — `Theme.all.count == 3` and `Theme.all.map(\.id) == [.porty, .osx, .bw]`.
- `testCSSVariablesIncludeAllKeys` — `theme.cssVariables(appearance:)` contains every expected `--color-…` variable name (one assertion per variable, to protect against refactor drift).
- `testBWPaletteIsDevoidOfColor` — for every non-accent color in BW (both light and dark), check `R == G && G == B` (monochrome). Accent + status colors exempted.

### Manual verification checklist (per-theme sweep)

Six combos: Porty × {Light, Dark}, OSX × {Light, Dark}, BW × {Light, Dark}.

For each combo, verify:
- Project list — cards render correctly, hover/selection visible.
- Project detail editor — cursor, selection, syntax colors legible.
- Project detail preview — headings, body text, links, embedded images, link cards, file badges.
- Gallery grid + list — cards, thumbnails, selection states, folders.
- Cleanup popup — preview, form, buttons.
- Search palette — input, results, footer (error + hints).
- Settings tab — all sections, theme cards (clicking them switches live).
- Empty states (no projects, no files, no links).

Cross-cutting:
- Theme switch: no flicker, no scroll-position jump, no state loss (text field contents, selection).
- macOS appearance toggle mid-session: SwiftUI + WebViews both respond.
- macOS accent change mid-session (OSX theme only): SwiftUI tint + WebView accent update within a few hundred ms.
- Exported HTML in all six combos: open in Safari, confirm self-contained, colors match.

## 7. Rollout

- Default theme: **Porty**. First launch is visually identical to today.
- UserDefaults keys: `"themeID"`, `"defaultViewMode"`, `"autoSaveDelay"`, `"grainEnabled"`, `"grainOpacityOverride"`.
- No migration of existing user data needed.
- No feature flag.

## 8. Follow-ups (explicitly deferred)

- **Typography per theme** (SF Pro for OSX, serif for BW).
- **User-configurable accent** (regardless of theme).
- **Accessibility scale multiplier** for typography.
- **Theme-aware iconography** (different status icons per theme).
- **Accent-follows-system-accent for Porty and BW** (currently only OSX does).
- **In-app appearance override** (force light / force dark / follow system).
