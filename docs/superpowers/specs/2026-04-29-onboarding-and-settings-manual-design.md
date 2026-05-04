# Onboarding + Settings Manual — Design

> Spec date: 2026-04-29

## Goal

Give a first-time PortyMcFolio user a fast, low-ceremony introduction to the app's mental model — *each project is a folder with a markdown, and you can add files, links, edit the markdown, and mark favorites* — and consolidate every concept and shortcut into a Manual section inside the existing Settings page.

The settings page already mixes preferences with text-only reference sections; this spec leans into that and turns it into a single source of truth for "how does this work".

## Non-goals

- Sample portfolio seeding, sample project content
- Animated tooltips / coach marks anywhere else in the app
- Theme visual previews or live demos beyond a one-line description
- Re-accessible welcome flow (e.g. via the ⌘K palette)
- Restructuring `AppSettingsView` into tabs or a sidebar

## User-facing flow

1. **Splash** — unchanged.
2. **Folder picker** — `FolderPickerView` is unchanged. Title + subtitle + "Choose Folder…" button.
3. **Empty overview with primer card** *(new)*. Shown only when `portfolioRootURL != nil && filteredProjects.isEmpty`. Disappears for good the moment any project exists. Re-access lives in **Settings → Manual** (no other re-entry path).
4. **Populated overview** — unchanged.

A user who picks a folder that already contains projects (e.g. transferred from another machine) skips the primer entirely. Switching the portfolio root from Settings to an empty folder will re-show the primer; this is acceptable and matches the empty-state condition.

## Primer card

### Layout

Centered on the empty overview. One title, five rows, one CTA.

```
        ┌────────────────────────────────────────────┐
        │  WELCOME                                   │
        │  How PortyMcFolio works                    │
        │                                            │
        │  ▸ Each project is a folder with a md file │
        │  ▸ Drop in files: images, video, PDFs      │
        │  ▸ Add links with previews                 │
        │  ▸ Edit the markdown to describe the work  │
        │  ▸ Mark favorites for the carousel         │
        │                                            │
        │  [ Create your first project ]             │
        └────────────────────────────────────────────┘
```

### Content

| # | SF Symbol                  | Copy                                             |
|---|----------------------------|--------------------------------------------------|
| 1 | `folder`                   | Each project is a folder with a markdown file    |
| 2 | `photo.on.rectangle`       | Drop in files: images, video, PDFs               |
| 3 | `link`                     | Add links with previews                          |
| 4 | `square.and.pencil`        | Edit the markdown to describe the work           |
| 5 | `star.fill`                | Mark favorites for the carousel                  |

CTA label: **Create your first project**. Tapping it opens the existing `NewProjectSheet` (no flow change).

### Visual tokens

- Container: `RoundedRectangle(cornerRadius: DT.Radius.medium)` filled with `theme.colors.surface`, stroked with `theme.colors.border` at 0.5pt.
- Title section: small uppercase eyebrow ("WELCOME") in `DT.Typography.micro` with `theme.colors.textTertiary`, then the title in the same heading token used by `AppSettingsView`'s top-level section labels (e.g. "APPEARANCE", "WORKSPACE"). If that token is `DT.Typography.title3` keep it; if it's a different name, match whatever the existing settings page uses so the primer feels native.
- Bullet rows: SF Symbol icon at `theme.colors.textSecondary`, label in `DT.Typography.body` at `theme.colors.textPrimary`. Even vertical spacing using `DT.Spacing.sm`.
- Button: filled accent matching the existing primary button style (e.g. `EditLinkSheet`'s Save button — `theme.colors.accent` background, `theme.colors.accentForeground` label).
- Card max width ~400pt, internal padding `DT.Spacing.xl`.

### File / wiring

- New view: `PortyMcFolio/Views/WelcomePrimerView.swift` — pure presentation, takes one closure (`onCreate: () -> Void`).
- Insertion point: `ProjectListView`'s body, when `filteredProjects.isEmpty && appState.portfolioRootURL != nil`. Replaces whatever empty-state placeholder exists today (or fills the empty grid space).
- The "Create your first project" closure sets `appState.isShowingNewProject = true` — same path as ⌘N.

## Settings reorganization

`AppSettingsView` keeps its single-scroll shape. Add two clearly-labeled top-level bands.

### Preferences band (top)

Existing controls retain their current order and styling. One addition:

- **Portfolio → "Show hidden projects" toggle.** A persisted version of `appState.hideHiddenProjects` (currently a session-only toggle on the overview). This becomes the canonical preference; the overview-side toggle continues to work and writes to the same source.

No other changes to existing preference controls.

### Manual band (bottom)

Replaces the current loose sequence of reference sections. Sections in order:

1. **Getting started** *(new)*. Recap of the 5-bullet primer plus a brief explanation of how a project is stored on disk: folder name shape `{year}_{slug}_{uid}/`, the markdown file inside with YAML frontmatter, and the principle that filesystem is canonical.
2. **Importing content** *(new)*. Three short subsections:
   - Drag from Finder into the editor or gallery → file is copied into the project and embedded.
   - Paste from clipboard — images become `pasted-{timestamp}.png` files, URLs become link cards.
   - The `![[filename]]` embed syntax (works for any media; rename auto-rewrites embeds in body, teaser, favorites).
3. **Project metadata** *(new)*. One line each on tags, clients, status, favorites, teaser, hidden — what they are and where they show up (overview card, search, carousel).
4. **View modes** *(existing, expanded)*. Cover all eight modes (editor, preview, splitGallery, gallery, splitList, list, splitLinks, links, carousel) with their full + shift-variant shortcuts; explain split divider drag and the persisted ratio.
5. **Editor** *(existing, expanded)*. Add the formatting shortcuts: ⌘B / ⌘I / ⌘E / ⌘⇧S / ⌘⇧K, and find (⌘F).
6. **Gallery** *(existing, expanded)*. Add multi-select shortcuts (⌘-click toggle, ⇧-click range, ⌘A all), L (favorite), ⌘⌫ (delete), ⌘[ (up a folder).
7. **Carousel** *(existing)*. Mostly unchanged; mention arrow keys for navigation and reorder via the dedicated sheet.
8. **Search & commands** *(existing, expanded)*. Call out the search palette commands explicitly: New Project, Guide, **Re-index portfolio** (the only recovery path for a corrupted FTS index).
9. **Themes** *(new, brief)*. One line each on porty / osx / bw — what they're for stylistically.
10. **Keyboard shortcuts** *(existing, expanded)*. Final consolidated table covering ⌘N / ⌘K / ⌘1–⌘6 (+ shift variants) / ⌘9 / arrow keys / L / ⌘⌫ / ⌘[ / ⌘F.

### Visual treatment

The two bands use the same internal section styling as today (no new components). The only new chrome is the "PREFERENCES" / "MANUAL" labels themselves — small uppercase eyebrow text in `DT.Typography.micro`, `theme.colors.textTertiary`, with a subtle divider above the Manual band.

## Bug fix bundled

`AppState.swift:52` — `@Published var hideHiddenProjects = false`. No `didSet` write to UserDefaults today. Fix:

- Add `didSet { UserDefaults.standard.set(hideHiddenProjects, forKey: "hideHiddenProjects") }`.
- In `loadLayoutPreferences()`, restore: `if UserDefaults.standard.object(forKey: "hideHiddenProjects") != nil { hideHiddenProjects = UserDefaults.standard.bool(forKey: "hideHiddenProjects") }`.

## Files affected (summary)

- **New:** `PortyMcFolio/Views/WelcomePrimerView.swift`
- **Modified:** `PortyMcFolio/Views/ProjectListView.swift` (empty-state branch)
- **Modified:** `PortyMcFolio/Views/AppSettingsView.swift` (band labels, new sections, expanded copy, "Show hidden projects" preference row)
- **Modified:** `PortyMcFolio/App/AppState.swift` (persist `hideHiddenProjects`)
- **New test:** `PortyMcFolioTests/AppStateHideHiddenPersistenceTests.swift`

## Testing

Per the project convention (no SwiftUI view tests):

- **State persistence:** unit test confirming `hideHiddenProjects` round-trips through UserDefaults.
- **Smoke build:** verify the empty overview shows the primer when projects is empty and portfolioRootURL is set; verify Settings page renders both bands without layout breakage.
- **Manual content** is static text — covered by smoke verification only.

## Open considerations (acknowledged, not blocking)

- The primer's disappearance is tied to `filteredProjects.isEmpty`. If a user has hidden projects only and toggles "Show hidden projects" off, the primer would briefly reappear. Acceptable: it's still a "looks empty" state.
- The Manual band will make `AppSettingsView` longer. If it crosses a comfort threshold, a future revision could move it to a sidebar or tabbed layout — out of scope for this spec.
