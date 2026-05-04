# Keyboard Navigation Redesign

**Date:** 2026-04-22
**Scope:** `PortyMcFolio/App/AppState.swift`, `PortyMcFolio/App/PortyMcFolioApp.swift`, `PortyMcFolio/Views/ProjectDetailView.swift`, `PortyMcFolio/Views/GalleryView.swift` (remove in-pane grid/list/links toggle), `PortyMcFolio/Views/AppSettingsView.swift` (settings picker + help copy), plus Esc handling touch-ups across `ProjectListView`, `ContentView`, and sheets.

## Summary

Restructure the in-project view modes from 5 cases (editor, preview, split, gallery, carousel) to 9 cases that expose every primary/secondary combination directly on the keyboard. Each content type (gallery grid, gallery list, links) gets two shortcuts — one for the split variant (editor on the left) and one for the full-width variant. Fold the Gallery view's in-pane grid/list/links toggle away entirely; the top-level view mode now determines which content appears. Promote Project Settings from `⌘4` to `⌘9` so it has one body-memory home in both the project-detail view and the projects overview. Normalize Esc to a stack-pop gesture with one simple exception in the projects list (clear filter + selection before going back).

## Motivation

The current keyboard layout suffers from three concrete problems, surfaced by a review of every `.keyboardShortcut`, `.onKeyPress`, and `performKeyEquivalent` site in the app:

1. **`⌘1`/`⌘2` are overloaded.** They mean "view mode 1/2" in the app menu and simultaneously "toggle editor↔preview" in `ProjectDetailView`.
2. **Gallery sub-modes (grid / list / links) are unreachable from keyboard.** Users must click the in-pane toggle buttons. The keyboard navigates files within a mode but can't switch the mode itself.
3. **Esc is inconsistent.** It clears selection + filter in the projects list, goes back to the list from detail, closes Settings, cancels sheets — four meanings, no single mental model.

The new scheme gives each view mode its own dedicated `⌘<digit>` or `⌘⇧<digit>` binding and standardizes Esc as "pop the topmost thing".

## Scope

**In scope:**
- New `ViewMode` enum with 9 cases replacing the current 5.
- Delete `GalleryView.GalleryViewMode` (the in-view grid/list/links toggle). Drive content choice from the top-level view mode.
- Remove the three in-pane gallery toggle buttons (grid / list / links).
- Update app menu (`PortyMcFolioApp.swift`) to list all 9 modes + Project Settings with the new shortcuts.
- Update `ProjectDetailView` toolbar icons to match the new `⌘<digit>` semantics (keep 5 icons; see Design → Toolbar).
- Update `ContentView`'s `⌘K` + `⌘N` + (new) `⌘9` plumbing.
- Update `ProjectListView` so `⌘9` opens the highlighted project's settings popover (same popover as today, different key).
- Normalize Esc behavior per the stack-pop rules.
- Migrate the stored `defaultViewMode` UserDefaults preference from legacy values.
- Expand the Settings → Workspace → "Default view mode" picker to the new modes.
- Rewrite the Settings → Help → "Keyboard Shortcuts" section to match.

**Out of scope:**
- Preview doesn't get a split variant (no `⌘⇧2` / no `splitPreview` case). Preview is full-width only — matches existing behavior.
- Carousel doesn't get a split variant (no `⌘⇧6`).
- No new "URL"/"Links" view itself — we reuse the existing links model (`LinkItem`), just reached via the new shortcut.
- App-level Settings ("Porty McFolio" Settings / Preferences window) gets no keyboard shortcut in this pass. It stays toolbar-only. (`⌘,` is not claimed; keeping room for a future pass.)
- Other pain points from the keyboard review — missing Delete key in gallery, no favorite/heart shortcut, no Previous/Next project, sort menu needing keyboard access — are separate concerns. Explicitly deferred.
- No visual redesign of the gallery's top bar beyond removing the three toggle buttons.
- No changes to the editor's `⌘B` / `⌘I` / `⌘E` / `⌘⇧S` / `⌘⇧K` / `⌘F` formatting shortcuts.
- The editor's heading shortcuts **move** from `⌘⇧1 / ⌘⇧2 / ⌘⇧3` to `⌘⌥1 / ⌘⌥2 / ⌘⌥3` to resolve the conflict with the new `⌘⇧3` Gallery-full binding (see Design → Editor heading shortcut conflict).

## Design

### Shortcut map (new)

**Inside a project detail view:**

| Key | Mode |
|---|---|
| `⌘1` | Editor (full) |
| `⌘2` | Preview (full) |
| `⌘3` | Editor + Gallery (grid) — split |
| `⌘⇧3` | Gallery (grid) — full |
| `⌘4` | Editor + List — split |
| `⌘⇧4` | List — full |
| `⌘5` | Editor + Links — split |
| `⌘⇧5` | Links — full |
| `⌘6` | Carousel |
| `⌘9` | Project Settings (popover) |

**In the projects overview:**

| Key | Action |
|---|---|
| `⌘9` | Project Settings for the highlighted/selected project (same popover as in detail view) |

`⌘K` (search palette), `⌘N` (new project), arrow-key navigation inside each view, and all editor formatting shortcuts are unchanged.

### ViewMode enum

Replace the existing `AppState.ViewMode` (5 cases) with:

```swift
enum ViewMode: Int, Codable, CaseIterable {
    case editor       = 0  // ⌘1
    case preview      = 1  // ⌘2
    case splitGallery = 2  // ⌘3
    case gallery      = 3  // ⌘⇧3  (kept at same raw value as old `.gallery`)
    case splitList    = 4  // ⌘4
    case list         = 5  // ⌘⇧4
    case splitLinks   = 6  // ⌘5
    case links        = 7  // ⌘⇧5
    case carousel     = 8  // ⌘6
}
```

Raw-value alignment note: the old enum had `.editor = 0`, `.preview = 1`, `.split = 2`, `.gallery = 3`, `.carousel = 4`. The new layout preserves `editor = 0`, `preview = 1`, `gallery = 3` at the same raw values; old `.split = 2` now means `.splitGallery` (semantically compatible — split used to mean split with gallery). Old `.carousel = 4` shifts to `.carousel = 8`. Migration rule (below) handles the shift.

### Gallery rendering

`GalleryView` today owns a local `@State var viewMode: GalleryViewMode` (an enum with `.grid | .list | .links`) and three in-pane toggle buttons that flip it. Delete the enum, delete the `@State`, delete the three toggle buttons. `GalleryView` gains a required init parameter:

```swift
enum GalleryMode { case grid, list, links }

struct GalleryView: View {
    let project: Project
    let mode: GalleryMode
    // ...
}
```

Parent (`ProjectDetailView`) derives `mode` from the active `ViewMode`:
- `.splitGallery`, `.gallery` → `.grid`
- `.splitList`, `.list` → `.list`
- `.splitLinks`, `.links` → `.links`

Other view modes (editor / preview / carousel) don't mount `GalleryView` at all.

### Split-layout rendering

In any `splitXxx` mode, `ProjectDetailView` renders editor on the left, secondary content on the right, with the existing `splitRatio` drag-to-resize handle. This is exactly what `.split` does today — the only change is that the right pane's content is chosen by the specific `splitXxx` variant.

### Toolbar (in `ProjectDetailView`)

Keep 5 icons. Each click flips to a specific mode (no sub-menu):

| Icon | Tap → | Shortcut shown in tooltip |
|---|---|---|
| `doc.text` | `.editor` | `⌘1` |
| `eye` | `.preview` | `⌘2` |
| `rectangle.split.2x1` | `.splitGallery` | `⌘3` |
| `square.grid.2x2` | `.gallery` | `⌘⇧3` |
| `rectangle.stack.badge.play` | `.carousel` | `⌘6` |

List / split-list, links / split-links are **keyboard and app-menu only**. Four more toolbar icons would crowd the bar; the keyboard muscle memory is the intended primary interface. The app menu exposes everything.

### App menu (`PortyMcFolioApp.swift`)

Replace the current `CommandGroup(replacing: .sidebar)` block with entries listing all 9 view modes plus Project Settings, in shortcut order:

```
View
  Editor            ⌘1
  Preview           ⌘2
  Editor + Gallery  ⌘3
  Gallery           ⌘⇧3
  Editor + List     ⌘4
  List              ⌘⇧4
  Editor + Links    ⌘5
  Links             ⌘⇧5
  Carousel          ⌘6
  ───────────
  Project Settings  ⌘9
```

### Esc behavior

One handler priority chain. First match wins, rest is no-op:

1. **Any sheet open** → cancel/dismiss (each sheet's `.cancelAction` already handles this).
2. **Search palette open** → close (existing behavior at `SearchPalette.swift:200-202`).
3. **Project Settings popover open** → close.
4. **Settings screen (the help/prefs screen) showing** → close (existing `AppSettingsView.swift:53`).
5. **Inside a project detail view** → back to projects list. Today `ProjectDetailView.swift:269-272` already does this on Esc; no change needed.
6. **In the projects list, filter text set OR keyboard selection/hover present** → clear filter + selection + hover (stay in list). Existing at `ProjectListView.swift:177-184`.
7. **Otherwise** → no-op.

The change vs. today is mostly normative: we document the priority rule and verify each layer's Esc actually does what the rule expects. Concrete code changes:
- `ProjectListView`'s Esc handler stays as-is (clear filter + selection). That's layer 6.
- `ProjectDetailView`'s Esc stays as-is (back to list). That's layer 5.
- Sheets, palette, popover, settings already pop on Esc via their own bindings.
- We do NOT introduce any new global keyboard monitor — each layer handles its own Esc as it does today. The rule exists because SwiftUI's sheet/popover presentation already intercepts Esc on top before layer-5/6 get it, so the priority emerges naturally from the responder chain.

### Editor heading shortcut conflict

macOS menu shortcuts fire before any view's `performKeyEquivalent`. So the new `⌘⇧3` menu item ("Gallery full") would always win over the editor's existing `⌘⇧3` binding for Heading 3, even when the editor has focus. `⌘⇧4` and `⌘⇧5` don't collide (editor doesn't bind them).

Resolution: move the editor heading shortcuts from `⌘⇧1 / ⌘⇧2 / ⌘⇧3` to `⌘⌥1 / ⌘⌥2 / ⌘⌥3`. Matches the convention in iA Writer / Bear / Obsidian and preserves the "⌘<n> = split, ⌘⇧<n> = full" symmetry for view modes.

Concrete change in `MarkdownEditorView.swift` at the switch in `performKeyEquivalent` (around line 174-176):

```swift
// old
case ("1", true): setHeading(level: 1); return true
case ("2", true): setHeading(level: 2); return true
case ("3", true): setHeading(level: 3); return true
```

becomes

```swift
case ("1", false) where hasOption: setHeading(level: 1); return true
case ("2", false) where hasOption: setHeading(level: 2); return true
case ("3", false) where hasOption: setHeading(level: 3); return true
```

with `let hasOption = event.modifierFlags.contains(.option)` computed alongside the existing `hasShift`. The `(chars, hasShift)` tuple switch is retained for everything else; heading cases move to a parallel `hasOption` branch.

### Settings — "Default view mode" picker

Currently at `AppSettingsView.swift:184-196`, renders a row of `pillOption` items for the 6-value `DefaultViewMode` enum (`.lastUsed`, `.editor`, `.preview`, `.split`, `.gallery`, `.carousel`). Expand `DefaultViewMode` to match the new `ViewMode`:

```swift
enum DefaultViewMode: String, Codable, CaseIterable {
    case lastUsed
    case editor
    case preview
    case splitGallery
    case gallery
    case splitList
    case list
    case splitLinks
    case links
    case carousel
}
```

Pills become a wrapping 10-item row. Display labels: "Last used", "Editor", "Preview", "Editor + Gallery", "Gallery", "Editor + List", "List", "Editor + Links", "Links", "Carousel".

### Preference migration

On AppState init, `loadLayoutPreferences` reads `defaultViewMode` from UserDefaults. Since `DefaultViewMode` is stored by `rawValue` (string), map legacy values forward once:

```swift
if let raw = UserDefaults.standard.string(forKey: "defaultViewMode") {
    let migrated: String
    switch raw {
    case "split":     migrated = "splitGallery"
    default:          migrated = raw
    }
    if let mode = DefaultViewMode(rawValue: migrated) {
        defaultViewMode = mode
    }
}
```

For the `viewMode` field (stored by `Int` rawValue): legacy `.carousel = 4` collides with new `.splitList = 4` — the raw value alone doesn't tell us which generation it came from. Gate the migration behind a one-shot boolean flag so it runs exactly once.

In `AppState.loadLayoutPreferences`, before reading `viewMode`:

```swift
if !UserDefaults.standard.bool(forKey: "viewModeMigratedToV2") {
    if let legacy = UserDefaults.standard.object(forKey: "viewMode") as? Int {
        // Legacy enum: editor=0, preview=1, split=2, gallery=3, carousel=4
        let migrated: Int
        switch legacy {
        case 0: migrated = 0  // editor
        case 1: migrated = 1  // preview
        case 2: migrated = 2  // split → splitGallery (raw preserved)
        case 3: migrated = 3  // gallery (raw preserved)
        case 4: migrated = 8  // carousel (was 4, now 8)
        default: migrated = 0
        }
        UserDefaults.standard.set(migrated, forKey: "viewMode")
    }
    UserDefaults.standard.set(true, forKey: "viewModeMigratedToV2")
}

// Then the usual load runs unchanged:
if let raw = UserDefaults.standard.object(forKey: "viewMode") as? Int,
   let mode = ViewMode(rawValue: raw) {
    viewMode = mode
}
```

After the first launch, `viewModeMigratedToV2 = true` sits in UserDefaults forever and the migration block is skipped. Users who pick `.splitList` later keep `viewMode = 4` without it being re-translated to `.carousel`.

The `defaultViewMode` string migration doesn't need a flag — `"split"` and `"splitGallery"` are different strings, so the translation is trivially idempotent.

### Settings → Help → Keyboard Shortcuts

Rewrite the shortcuts section at `AppSettingsView.swift:~456-524` to reflect the actual bindings:

**Global**
- Search & Commands — `⌘K`
- New Project — `⌘N`
- Back to Projects — `⎋`

**View Modes (in a project)**
- Editor — `⌘1`
- Preview — `⌘2`
- Editor + Gallery — `⌘3`
- Gallery — `⌘⇧3`
- Editor + List — `⌘4`
- List — `⌘⇧4`
- Editor + Links — `⌘5`
- Links — `⌘⇧5`
- Carousel — `⌘6`
- Project Settings — `⌘9`

**Editor**
- Bold — `⌘B`
- Italic — `⌘I`
- Strikethrough — `⌘⇧S`
- Inline Code — `⌘E`
- Heading 1 / 2 / 3 — `⌘⌥1 / ⌘⌥2 / ⌘⌥3` *(moved from `⌘⇧1-3` to free up `⌘⇧3` for the new Gallery-full view-mode shortcut)*
- Insert Link — `⌘⇧K`
- Find — `⌘F`

**Gallery**
- Quick Look — `␣`
- Cut File — `⌘X`
- Paste File — `⌘V`
- Go Up a Folder — `⌘[`
- Navigate Files — `←↑↓→`

**Carousel**
- Previous / Next Slide — `← / →`

## Files touched

**Modified:**
- `PortyMcFolio/App/AppState.swift` — new `ViewMode` enum; expanded `DefaultViewMode`; migration logic in `loadLayoutPreferences`.
- `PortyMcFolio/App/PortyMcFolioApp.swift` — rebuild the View command group with the 10 menu items (9 modes + Project Settings).
- `PortyMcFolio/Views/ContentView.swift` — route `⌘9` to Project Settings in both list and detail contexts.
- `PortyMcFolio/Views/ProjectListView.swift` — bind `⌘9` to open highlighted project's settings popover; previous `⌘4` binding removed.
- `PortyMcFolio/Views/ProjectDetailView.swift` — toolbar bindings + the mode-based layout switcher (editor / preview / split / gallery / carousel now expanded to 9 branches that route `GalleryView(mode:)` with the right `GalleryMode`). `⌘4` → Project Settings is rebound to `⌘9`. `⌘1` is unified to mean "Editor" only (remove the Editor↔Preview toggle overload).
- `PortyMcFolio/Views/GalleryView.swift` — delete `GalleryViewMode` enum + `@State var viewMode` + the three in-pane toggle buttons; add `let mode: GalleryMode` init parameter that the parent passes.
- `PortyMcFolio/Views/AppSettingsView.swift` — expand the default-view-mode pill row; rewrite the keyboard-shortcuts help section.
- `PortyMcFolio/Views/MarkdownEditorView.swift` — move heading shortcuts from `⌘⇧1/2/3` to `⌘⌥1/2/3` in `performKeyEquivalent`.

**Tests touched:**
- `PortyMcFolioTests/AppStateFilteredProjectsTests.swift` — if any test references `.split`, `.gallery`, `.carousel` by rawValue or case, update to new enum values.
- Add a small test for the migration function: legacy raw=4 (carousel) → new raw=8 (carousel). Optional — migration is tiny enough to inline-verify.

**Not touched:** `FrontmatterParser`, `Project`, `ProjectCreator`, `ProjectReconciler`, `ClipboardPaste`, `ImageThumbnail`, or anything outside the view-mode family.

## Testing

**Unit tests:**
- Optional but recommended: a migration test for `ViewMode` raw-value shift (legacy 4 → new 8), and a `DefaultViewMode` string migration test (`"split"` → `"splitGallery"`).
- Existing `AppState` tests that reference `.split`/`.gallery`/`.carousel` by name will update to match the new enum but their assertions stay semantically identical.

**Manual verification checklist:**
- Open a project. Press `⌘1 ⌘2 ⌘3 ⌘⇧3 ⌘4 ⌘⇧4 ⌘5 ⌘⇧5 ⌘6` in sequence — each shortcut lands on the correct view.
- Gallery shows only the right content (no in-pane toggle buttons visible).
- Split modes render editor on the left, secondary on the right. The drag divider still works.
- `⌘9` opens Project Settings from both the detail view and the projects overview (with the highlighted/selected project as anchor).
- App menu "View" submenu lists all 9 modes + Project Settings in the right order with correct shortcut labels.
- Settings → Workspace → "Default view mode" shows all 10 pill options (last-used + 9 modes). Picking one, relaunching the app, and entering a project lands on that mode.
- Settings → Help → Keyboard Shortcuts shows the new list; no stale `⌘1–3 headings` claim.
- Esc sequence: open a project → open a sheet (e.g. New Folder) → Esc dismisses sheet. Esc again → back to list. In list with filter text set → Esc clears filter. Esc again with empty state → no-op (no crash).
- Legacy preference migration: manually set `defaults write com.portymcfolio.app viewMode 4` in Terminal, relaunch — app opens in Carousel (the new 8), not List.
- Verify existing view-mode toolbar icons in `ProjectDetailView` still work and produce the right modes.
- Editor heading shortcuts: in the editor, type some text, select it, press `⌘⌥1` → becomes `# text`. Repeat with `⌘⌥2` (→ `## text`) and `⌘⌥3` (→ `### text`). Confirm `⌘⇧3` no longer sets Heading 3 — it now switches to Gallery full.

## Rollout & revert

All changes land in one merge. Revert is `git revert -m 1 <merge-sha>` of the eventual merge. Users who upgraded and picked a new-only mode (e.g. `.splitList`) and then downgrade will see their `defaultViewMode` fall back to `.editor` (safe default); old `viewMode = 8` lands outside the 0–4 range of the old enum and falls back to `.editor` via the existing "if let mode = ViewMode(rawValue:)" guard. Acceptable.

No data/schema changes. No file format changes. No network calls. No new dependencies.
