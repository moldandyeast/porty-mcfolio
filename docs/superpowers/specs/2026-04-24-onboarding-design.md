# Onboarding — Design

**Status:** Approved for implementation planning.

## Goal

First-launch onboarding that sets up the tool, explains the shape of the app, and leaves the user with the sense that Porty is for them. Single-pass on first launch; re-openable from Help → Show Welcome. Eight screens; window-takeover shape; warm, honest, fun copy; interactive keyboard-shortcut primer on the final screen.

## Positioning

Porty is a **tool for creatives who have folders and folders of past work** — not cleanly organized, scattered across disks, hard to browse. Porty is **part file browser, part archive**. It organizes work project-by-project: each project is a folder with a markdown file, open to whatever messy files you drop in. The app is a nice experience around a portfolio folder you own — **no cloud, no lock-in**. If Porty breaks, the folder is still yours.

## Shape

- **Full-window takeover** on first launch. The wizard view *replaces* `ContentView` inside the `WindowGroup` when onboarding mode is active — the wizard is not overlaid on ContentView. This means shortcuts defined in `ContentView` (e.g., ⌘K at `ContentView.swift:68`) are not reachable during the wizard, which is desirable: we intercept keyboard input via our own monitor in S8.
- **Window size:** no forced resize. The wizard centers its content within whatever the current window size is, with generous padding. This avoids jank when transitioning to the main app.
- **8 screens**, linear, one concept per screen, dot-progress at the bottom.
- **No visible "Skip" button** — users walk through. Escape key closes the wizard as a power-user escape hatch.
- **Per-screen CTA buttons have specific, warm labels** ("Start," "Let's go," "Got it," "Nice," "Sweet," "Open my portfolio") — not generic "Next."
- **Auto-skip branch**: if the folder the user picks in screen 3 already contains `{year}_{slug}_{uid}` project folders, screen 3 flips to a "Welcome back" state offering `Show me the tour` (continue) or `Open my portfolio` (skip to main app).
- **Logo appears on screen 1 only.** Every other screen is text + visual only.

## Screens

### 1 — Hi

- Visual: the app logo (pink square with a "p").
- Headline: **Hi, I'm Porty.**
- Sub: **Part file browser, part archive — for your pile of past work.**
- CTA: `Start`

### 2 — Why

- Visual: 6 scattered folder emojis in a loose grid (📁📁📁 / 📁📁📁).
- Headline: **Folders in folders in folders.**
- Sub: **Years of work, scattered. Porty puts it in one place — one project at a time. Drop in your files and links, write what & why, find it again later.**
- CTA: `Let's go`

### 3 — Pick folder (two states)

**Initial state:**
- Visual: single 📁.
- Headline: **Pick your folder.**
- Sub: **New or existing — it's yours either way.**
- CTA: `Choose Folder…` (opens `NSOpenPanel`).
- Reassurance (small, below button): **No cloud. No lock-in. Porty just helps you use your folder. If Porty ever breaks, your work is still right there on disk.**
- No "Next" button — picking the folder advances.

**After picking — existing folder detected:**
- Detection criterion: the selected folder contains ≥1 subfolder matching `^\d{4}_.+_[0-9a-f]{8}$`.
- Visual: a green success chip `✓ Found N existing projects in this folder.`
- Headline: **Welcome back.**
- Sub: **Looks like you've used Porty before. Want the full tour, or jump straight into your work?**
- Buttons: `Show me the tour` (continues to S4) · `Open my portfolio` (dismisses wizard → main app).

**After picking — fresh folder:**
- Visual: a neutral chip `📁 Portfolio/ is ready.`
- Headline: **Great choice.**
- Sub: **Let's quickly cover how projects work.**
- CTA: `Next` → S4.

### 4 — Overview

- Visual: a 3×2 grid of 6 mock project cards with varied gradient thumbs and plausible real titles (Brand Identity — Acme / Site Redesign — Muse / Editorial Zine / Poster Set / Packaging / Exhibit Signage).
- Headline: **See all your projects.**
- Sub: **Each one is a folder with a markdown, waiting for all your files.**
- CTA: `Cool`

### 5 — Content (drop/paste/write, URL is the hero)

- Visual: mini split-view editor. Left pane: markdown source showing `# Brand Identity` / `![[hero.jpg]]` / body text. Right pane: rendered preview with a hero image and an auto-fetched **link card** (title + URL shown in accent color).
- Three small hint tags under the editor: `drag file` · **`paste URL →`** (accent-colored) · `write md`.
- Headline: **Drop. Paste. Write.**
- Sub: **Drag files from Finder. Paste a URL → it becomes a saved link with a fetched title. Write context in markdown, preview beside you.**
- CTA: `Nice`

### 6 — Many views

- Visual: 2×2 grid of the same project in four view modes. Each tile has a small label with its shortcut:
  - `Editor ⌘1` — ghost lines representing markdown.
  - `Gallery ⌘⇧3` — 3×2 grid of gradient tiles.
  - `List ⌘⇧4` — horizontal rows with colored markers.
  - `Carousel ⌘6` — single large gradient with slide dots.
- Headline: **One project, many views.**
- Sub: **Write in the editor. Flip to the gallery to browse. Carousel for a slideshow. Your call.**
- CTA: `Got it`

### 7 — Gallery (❤️ → gallery)

- Visual: one file thumbnail with a ❤️ badge → arrow → 4×2 gallery grid growing out of it.
- Headline: **Heart the good ones.**
- Sub: **Every ❤️ file shows up in the project's gallery. Build a curated slideshow without extra work.**
- CTA: `Sweet`

### 8 — Keyboard (interactive)

- Visual: a list of four shortcut rows, each with a key-cap style key and a `try it ↗` affordance on the right.

| Key | Label | State |
|---|---|---|
| `⌘K` | Search everything | `try it ↗` → `✓ tried` (on fire) |
| `⌘N` | New project | `try it ↗` → `✓ tried` |
| `⌘1–⌘6` | Switch views | `try it ↗` → `✓ tried` |
| `⌘,` | Settings | `try it ↗` → `✓ tried` |

- Headline: **Best at full speed.**
- Sub: **Porty is built for the keyboard. Try any shortcut — it'll actually fire.**
- CTA: `Open my portfolio` (dismisses wizard unconditionally).

**Precondition — ⌘, must be wired in the main app.** Currently the app toggles `appState.isShowingSettings = true` from gear buttons and the search palette's "Settings" command, but there is no ⌘, keyboard shortcut. This spec includes a small addition to `PortyMcFolioApp.commands` that adds a hidden `Button` with `.keyboardShortcut(",", modifiers: .command)` binding to `appState.isShowingSettings = true`. Without this, the S8 primer would be teaching a shortcut that doesn't exist.

**Interaction:** the wizard is the window's content (the main `ContentView` is not rendered until dismissal), so shortcuts do NOT fire real app actions during onboarding. Instead, screen 8 installs an `NSEvent.addLocalMonitorForEvents` for the four tracked shortcuts (`⌘K`, `⌘N`, `⌘1–⌘6`, `⌘,`). On press, the monitor:
1. **Consumes** the event (doesn't propagate to the app's command menus — important: this prevents the wizard from accidentally triggering ⌘, or ⌘N on itself since those are now bound at the scene level).
2. Flips that row's `try it ↗` to `✓ tried` (green).
3. Briefly shows a **preview bubble** next to the row — a tiny illustration of what the shortcut does (e.g., ⌘K → a mini search palette card slides in for ~1s with placeholder text like "Search everything…"; ⌘N → a new-project form silhouette; ⌘1–⌘6 → four view-tile thumbnails; ⌘, → a tiny gear). Bubble fades after ~1.5s.

Rationale for NOT firing real actions: it keeps the onboarding window self-contained (no interleaved real palettes/sheets popping over a tutorial), keeps behavior consistent across all four shortcuts (⌘3–⌘6 would require a selected project to be interesting, which doesn't exist yet), and avoids the user accidentally creating a project they don't understand.

Tracked state (`triedShortcuts: Set<TrackedShortcut>`) is per-session — not persisted. Users who re-open the wizard from Help → Show Welcome start with all rows at "try it ↗".

The user clicks `Open my portfolio` to dismiss the wizard and land in the real app. From there, all shortcuts work normally.

## State & persistence

- New `UserDefaults` key: `hasCompletedOnboarding: Bool`. Set to `true` when the wizard is dismissed from S3b (existing folder) or S8.
- On launch, `AppState.loadSavedRoot` decides:
  - If bookmark exists AND `hasCompletedOnboarding == true` → load portfolio as today.
  - If bookmark exists AND `hasCompletedOnboarding == false` → load portfolio BUT present the wizard. (Unusual — happens only if user cleared the flag, e.g., via Help menu.)
  - If no bookmark → present the wizard starting at S1.
- Help menu gains a new item: **Help → Show Welcome** (no keyboard shortcut, to avoid conflicts). SwiftUI idiom: `CommandGroup(after: .help) { Button("Show Welcome") { … } }` inside `PortyMcFolioApp.commands`. Resets `hasCompletedOnboarding = false` and shows the wizard from S1.
- Escape key or ⌘W during the wizard:
  - Before S3 has a picked folder: quits the app (nothing to save).
  - After S3: dismisses the wizard, keeps whatever folder was picked. `hasCompletedOnboarding` is set to `true` (treat dismissal as completion).

## Navigation

- Forward: click the CTA button OR press `Enter`/`Return`.
- Back: small left-arrow chevron in the top-left of the titlebar area (becomes visible from S2 onward). Left-arrow key also goes back. S3's "after pick" states can go back to the initial S3 (allowing re-pick).
- Dots at the bottom are indicators only — not clickable.
- Progress through S4-S7 is linear; no skip.

## Window

- **No forced size.** The wizard adopts whatever window size is active. Content is centered with padding so it doesn't look stretched on a large window. A minimum wizard content width of ~480pt keeps text readable; the surrounding window can be larger.
- After wizard dismiss: the window already has the right size; ContentView just takes over the content area. No resize event.
- Titlebar: transparent, same as the main app — the wizard is rendered inside `WindowGroup`'s main window, not a separate one.

## Visual language

- Matches the existing app theme (reads `@Environment(\.theme)`).
- Accent color from theme for CTAs and key accents (hover states, `try it ↗`).
- Uses existing `DT.Typography.largeTitle` (28pt semibold) for headlines, `DT.Typography.caption` for subs. **No new design tokens.** 28pt is already the size we want — no need for a new `onboardingHeadline` token.
- Dot progress uses theme accent for the active dot, `theme.colors.border` for inactive.
- All mock visuals inside the wizard are drawn in SwiftUI (no image assets) so they re-theme correctly.

## Components

- **`OnboardingView`** — root SwiftUI view; handles screen switching and chrome (titlebar, dots, back chevron).
- **`OnboardingViewModel`** (`@MainActor ObservableObject`) — holds `currentStep: Int`, `pickedFolderURL: URL?`, `detectedExistingProjects: Int?`, `triedShortcuts: Set<TrackedShortcut>`. Public `next()`, `back()`, `dismiss()`, `pickFolder()`, `jumpToMainApp()`.
- **`OnboardingChrome`** — titlebar + footer wrapper, takes the current step index and child content.
- **`OnboardingScreen1Hi` … `OnboardingScreen8Keyboard`** — one view per screen. Each is a stateless SwiftUI view that takes the view model as input and renders the screen.
- **`OnboardingShortcutMonitor`** — wraps `NSEvent.addLocalMonitorForEvents` for S8. Publishes "shortcut fired" events to the view model. Ownership: view model creates and destroys with S8 lifecycle.
- **Mock drawing helpers** — small private views rendering the project card, editor split, gallery teaser, view tiles, etc. All SwiftUI, all theme-aware.
- **`AppState.isShowingOnboarding: Bool`** — new `@Published` flag. `ContentView` checks this and renders `OnboardingView` in place of its normal branches when true. Set from `loadSavedRoot` on first launch (no bookmark and not onboarded) or from the Help menu.
- **Scene-level wiring (`PortyMcFolioApp`)** — add ⌘, Button to the existing `.commands` block (as a sibling of the ⌘9 Project Settings button). Add `CommandGroup(after: .help) { Button("Show Welcome") { appState.showOnboardingAgain() } }`.

## Testing

- Unit-testable parts:
  - `OnboardingViewModel.detectExistingProjects(in:)` — pure function against a mocked file tree. Tests: 0 matching folders → nil; 1+ matching → count. Basename regex validation.
  - `OnboardingViewModel.currentStep` advancement: `next()` from step N goes to N+1; `back()` from step N goes to N-1; bounds clamp.
  - S3 branching: `pickFolder(url:)` with existing projects → state becomes `.existingDetected(count:)`; with empty folder → `.freshPicked`.
- UI tests (XCUITest) are out of scope for v1 — the 8-screen flow is manually verified.

## Copy — final

| # | Headline | Sub | CTA |
|---|---|---|---|
| 1 | Hi, I'm Porty. | Part file browser, part archive — for your pile of past work. | Start |
| 2 | Folders in folders in folders. | Years of work, scattered. Porty puts it in one place — one project at a time. Drop in your files and links, write what & why, find it again later. | Let's go |
| 3 | Pick your folder. | New or existing — it's yours either way. · No cloud. No lock-in. If Porty ever breaks, your work is still right there on disk. | Choose Folder… |
| 3b (existing) | Welcome back. | Looks like you've used Porty before. Want the full tour, or jump straight into your work? | Show me the tour · Open my portfolio |
| 3b (fresh) | Great choice. | Let's quickly cover how projects work. | Next |
| 4 | See all your projects. | Each one is a folder with a markdown, waiting for all your files. | Cool |
| 5 | Drop. Paste. Write. | Drag files from Finder. Paste a URL → it becomes a saved link with a fetched title. Write context in markdown, preview beside you. | Nice |
| 6 | One project, many views. | Write in the editor. Flip to the gallery to browse. Carousel for a slideshow. Your call. | Got it |
| 7 | Heart the good ones. | Every ❤️ file shows up in the project's gallery. Build a curated slideshow without extra work. | Sweet |
| 8 | Best at full speed. | Porty is built for the keyboard. Try any shortcut — it'll actually fire. | Open my portfolio |

## Non-goals

- Video/animation-heavy onboarding. Subtle fade/slide between screens is fine; nothing cinematic.
- Tracking (analytics) on which screens users drop off at. No telemetry.
- Localization. English only for v1.
- Settings-within-onboarding. Settings (theme, appearance override, etc.) are discoverable later via ⌘,.
- A "teach yourself in-app" coach-mark overlay after the wizard. Wizard alone is enough for v1.

## Out of scope (explicitly deferred)

- Onboarding for **returning users who cleared their bookmark** (e.g., moved the folder) — they'll get the wizard again; acceptable for v1.
- **Import from another portfolio-manager tool** — no conversion wizard.
- **Empty-state coaching in the main app** (e.g., "you have no projects yet — press ⌘N") — adjacent but separate UI.

## Rollout

- New users: wizard shows on first launch automatically.
- Existing users (upgrading to the version that ships this): wizard does NOT show retroactively — a one-time check sets `hasCompletedOnboarding = true` for anyone who already has a bookmark on disk, so they skip the wizard entirely on the first launch of the new version. They can re-open it via Help → Show Welcome if curious.
