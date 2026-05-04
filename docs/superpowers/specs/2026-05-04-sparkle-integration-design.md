# Sparkle Integration — Design

> Spec date: 2026-05-04

## Goal

Add Sparkle-based auto-updates so Porty McFolio can ship improvements after launch without users manually re-downloading. Update feed lives on a `gh-pages` branch of this repo for v1; migration to Amore's hosted feed is a one-line `Info.plist` change in a future release.

## Non-goals

- Beta / alpha channels — single stable channel for v1
- Phased rollouts (`<sparkle:phasedRolloutInterval>`) — small user base, no useful signal
- Delta updates — Sparkle supports them but adds release-pipeline complexity for marginal benefit on a ~10MB app
- Migration to the Amore-hosted appcast — separate small change once Amore approves the FOSS slot
- Custom update UI — standard Sparkle "Update Available" sheet is well-tested and familiar
- Automated testing of Sparkle's network/check flow — covered by Sparkle's own suite, not worth re-implementing

## Decisions

The five product decisions made during brainstorming:

| # | Choice | Why |
|---|---|---|
| 1 | Hybrid feed hosting: GitHub Pages for v1, migrate to Amore later | Decouples launch from Amore approval queue; migration is one `Info.plist` change shipped in a v1.0.x release |
| 2 | Auto-check ON by default, telemetry OFF | Matches the local-first, no-phone-home brand; users want fixes for a free OSS app |
| 3 | Inline HTML release notes in `<description>`, generated at release time from per-version markdown | Source of truth is markdown (matches docs); no extra hosting beyond the appcast |
| 4 | Standard Settings UI: toggle + "Check Now" + version + last-checked + explicit privacy paragraph | "No telemetry" callout is brand-positive; mirrors how AppSettingsView documents other features |
| 5 | New `scripts/release.sh` that wraps `build-dmg.sh` for the publish step | Keeps `build-dmg.sh` focused on producing a DMG; release pipeline has different failure modes |

## Architecture

```
PortyMcFolioApp.swift @main
   │ creates SPUStandardUpdaterController + UpdateController wrapper
   ▼
Sparkle background timer (every 24h if auto-check on)
   │
   ▼
GET https://moldandyeast.github.io/porty-mcfolio/appcast.xml
   │
   ▼
Parse XML → latest <item> has sparkle:version + enclosure URL + EdDSA signature
   │
   ├── version <= current: silent, refresh last-checked timestamp
   └── version >  current: show standard "Update Available" sheet
                            └── user accepts → download DMG → verify EdDSA → relaunch
```

## Code structure

### `UpdateController.swift` (new)

A `@MainActor` `ObservableObject` wrapping `SPUStandardUpdaterController`. Single responsibility: own the Sparkle controller and expose the SwiftUI-bindable surface needed by Settings and the menu.

```swift
@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var canCheckForUpdates: Bool

    var automaticallyChecksForUpdates: Bool { get set }   // bridges to Sparkle, persists via Sparkle's UserDefaults
    var currentVersion: String { get }                    // CFBundleShortVersionString
    func checkNow()

    // SPUUpdaterDelegate
    func updater(_:didFinishUpdateCycleFor:error:)        // refresh published state
}
```

Sparkle's user-driver stays at default — the standard update sheet ships free; no custom UI to maintain. Conforming to `SPUUpdaterDelegate` is purely to learn when a check finishes so `lastCheckedAt` can refresh.

### `PortyMcFolioApp.swift` modifications

Additive only:

```swift
@StateObject private var updateController = UpdateController()

WindowGroup { ContentView().environmentObject(appState).environmentObject(updateController) }
    .commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updateController.checkNow() }
                .disabled(!updateController.canCheckForUpdates)
        }
    }
```

The "Check for Updates…" item lands in the canonical macOS slot — App menu, immediately after "About Porty McFolio".

### `AppSettingsView.swift` modifications

A new `manualSection(title: "Updates", icon: "arrow.down.circle")` containing, in order:

1. Brief paragraph: *"Porty McFolio checks for updates daily by default. Updates are downloaded only after you confirm. No usage data, system information, or telemetry is sent during update checks — only a request to fetch the public release feed."*
2. `Toggle("Automatically check for updates", isOn: $updateController.automaticallyChecksForUpdates)`
3. Disclosure block: `Current version: 1.0.0` + `Last checked: <relative date>` (omitted if never checked)
4. `Button("Check for Updates Now")`, disabled while `canCheckForUpdates == false`

No restructuring of the existing manual sections. Insert position: after "Keyboard Navigation" as the last section of the manual — Updates is about app maintenance, not about using the app, so it sits naturally at the bottom.

### `project.yml` additions

- New SPM dependency: `Sparkle` from `https://github.com/sparkle-project/Sparkle.git` from `2.6.0`
- New `INFOPLIST_KEY_*` entries:
  - `SUFeedURL` = `https://moldandyeast.github.io/porty-mcfolio/appcast.xml`
  - `SUPublicEDKey` = (the public half of the EdDSA keypair generated during operational setup)
  - `SUEnableAutomaticChecks` = `YES`
  - `SUEnableSystemProfiling` = `NO` ← the explicit telemetry-off knob
  - `SUAutomaticallyUpdate` = `NO` (always confirm before install)

### Sandbox / entitlements impact

Sparkle 2 ships with an XPC service for sandboxed apps; the SPM package handles the bundle copy automatically. No changes to `PortyMcFolio.entitlements` beyond what's already there (`app-sandbox`, `network.client`, `files.user-selected.read-write`, `files.bookmarks.app-scope`).

## Release pipeline

### Per-version source of truth

Each release has a markdown file at `docs/release-notes/v<X.Y.Z>.md`. Format is short — bullet list of user-facing changes, optional "Fixes" / "Known issues" subsections. This is what end users see in the Sparkle update dialog *and* on the GitHub release page — single source.

### `scripts/release.sh` flow (~150 lines on top of `build-dmg.sh`)

```
release.sh v1.0.0 [--critical]
  1. Preflight: working tree clean, on main, $VERSION matches MARKETING_VERSION in project.yml,
     docs/release-notes/v$VERSION.md exists, cmark-gfm available, sign_update available
  2. Call build-dmg.sh → dist/PortyMcFolio-$VERSION-$DATE.dmg (signed + notarized)
  3. sign_update dist/...dmg          → captures EdDSA signature + byte length
  4. cmark-gfm docs/release-notes/v$VERSION.md → release-notes.html
  5. Render new <item> XML from template + values from steps 2-4
  6. git fetch origin gh-pages; git worktree add /tmp/porty-gh-pages gh-pages
  7. Prepend new <item> to /tmp/porty-gh-pages/appcast.xml; commit + push gh-pages
  8. gh release create v$VERSION --notes-file docs/release-notes/v$VERSION.md dist/...dmg
  9. Tag v$VERSION on main; push
  10. Print success summary with the appcast URL and release URL
```

`set -euo pipefail` + a trap that removes the gh-pages worktree on exit. If steps 7+ fail (network, auth), the local DMG is still in `dist/` for manual recovery — preflight idempotency will let you re-run.

A `--bootstrap` mode (one-time) creates the orphan `gh-pages` branch and writes a header-only `appcast.xml`. A `--dry-run` mode does everything except git push, gh release create, and gh-pages publish — and renders the would-be appcast `<item>` to stdout.

### `appcast.xml` schema

Hosted at `https://moldandyeast.github.io/porty-mcfolio/appcast.xml`. Standard Sparkle 2 format:

```xml
<?xml version="1.0" standalone="yes"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Porty McFolio</title>
    <link>https://moldandyeast.github.io/porty-mcfolio/appcast.xml</link>
    <description>Updates for Porty McFolio</description>
    <language>en</language>
    <item>
      <title>Version 1.0.0</title>
      <pubDate>Mon, 04 May 2026 13:00:00 +0200</pubDate>
      <sparkle:version>1</sparkle:version>
      <sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<h2>What's new</h2>... rendered HTML ...]]></description>
      <enclosure
        url="https://github.com/moldandyeast/porty-mcfolio/releases/download/v1.0.0/PortyMcFolio-1.0.0-2026-05-04.dmg"
        sparkle:edSignature="..."
        length="6774011"
        type="application/octet-stream"/>
    </item>
  </channel>
</rss>
```

A `--critical` invocation adds `<sparkle:criticalUpdate />` inside the `<item>` — Sparkle then treats it as a forced update.

### gh-pages branch structure

```
gh-pages/
└── appcast.xml
```

That's the whole branch. DMGs live on GitHub Releases (free hosting up to 2GB per file). The appcast just points at the GitHub-hosted URLs.

## One-time operational setup

Things done once for the project's lifetime, in this order. The implementation plan executes steps 1–3; step 4 verifies.

1. **Tooling** — `brew install cmark-gfm`. Sparkle's `generate_keys` and `sign_update` discovered via SPM after first `xcodebuild -resolvePackageDependencies`, then invoked via absolute path from `release.sh`. Pre-existing and verified: Developer ID Application certificate, `portymcfolio-notary` keychain credential profile, xcodegen.
2. **EdDSA keypair** — `generate_keys` prints the public key and stores the private key in macOS Keychain (generic password, service `https://sparkle-project.org`, account `ed25519`). Public key goes into `project.yml` as `INFOPLIST_KEY_SUPublicEDKey`. **Back up the private key offsite** to 1Password (or equivalent). Loss of the key means the project can never issue another auto-update — recovery would require every existing user to manually download and reinstall. The implementation plan halts at this step until backup is confirmed.
3. **GitHub Pages bootstrap** — `./scripts/release.sh --bootstrap` creates the orphan `gh-pages` branch, writes a header-only `appcast.xml`, commits, pushes. In repo Settings → Pages: enable Pages from `gh-pages` branch root. Wait ~30s for GitHub to deploy.
4. **Verify** — `curl -fsS https://moldandyeast.github.io/porty-mcfolio/appcast.xml` returns valid XML with the channel header and zero items. Build the app with the new `SUPublicEDKey`, launch, confirm Settings → Updates renders, and "Check Now" reports "You're up to date".

## Files affected

- **New:** `PortyMcFolio/Services/UpdateController.swift` — ~80 lines, `@MainActor` `ObservableObject` wrapping Sparkle.
- **New:** `scripts/release.sh` — ~150 lines, modes `<version>`, `<version> --dry-run`, `<version> --critical`, `--bootstrap`.
- **New (per release):** `docs/release-notes/v<X.Y.Z>.md` — short markdown notes.
- **New test:** `PortyMcFolioTests/UpdateControllerTests.swift` — narrow unit tests for `currentVersion`, `automaticallyChecksForUpdates` round-trip via `SUEnableAutomaticChecks`, and `objectWillChange` firing on toggle.
- **Modified:** `PortyMcFolio/App/PortyMcFolioApp.swift` — instantiate `UpdateController`, inject as `EnvironmentObject`, add `Check for Updates…` command.
- **Modified:** `PortyMcFolio/Views/AppSettingsView.swift` — new `manualSection` for Updates.
- **Modified:** `project.yml` — Sparkle SPM dep + `INFOPLIST_KEY_SU*` entries; xcodegen regen.

## Testing

Sparkle is hard to unit-test (concrete `SPUStandardUpdaterController`, background timers, network, codesign verification, OS dialogs). The project also skips SwiftUI view tests by convention. So testing is mostly *integration* and *operational*, with one small unit-test surface and one dry-run mode for the release script.

### Automated

`UpdateControllerTests.swift` — narrow scope:
- `currentVersion` reads `CFBundleShortVersionString` from `Bundle.main`
- `automaticallyChecksForUpdates` getter/setter round-trips through Sparkle's `SUEnableAutomaticChecks` UserDefaults key
- `objectWillChange` fires when the toggle setter is invoked

The network/check flow is not unit-tested.

### Manual — first integration (during implementation)

Before any release exists, point Sparkle at a local file:

```sh
defaults write com.portymcfolio.app SUFeedURL "file:///Users/$USER/local-appcast.xml"
```

Hand-craft `local-appcast.xml` with three scenarios in succession (one at a time):

1. **No items** → "Check Now" reports "up to date"; toggle ON/OFF; verify last-checked timestamp updates.
2. **Item with version > current** → standard Sparkle dialog appears with rendered HTML release notes; "Skip" / "Remind Me Later" / "Install" all work; Install completes a relaunch into the new build.
3. **Item flagged `<sparkle:criticalUpdate />`** → dialog presents the update as critical (different copy, harder to dismiss).

After verification, `defaults delete com.portymcfolio.app SUFeedURL` to restore the production URL.

### Manual — first real release (the actual launch)

1. Build & install v1.0.0 via the DMG (drag to /Applications).
2. Confirm Settings → Updates renders correctly with "1.0.0" + "never checked" + toggle ON + privacy paragraph.
3. Bump `MARKETING_VERSION` to 1.0.1 in `project.yml`, regenerate, write `docs/release-notes/v1.0.1.md` with one line.
4. `./scripts/release.sh v1.0.1 --dry-run` → inspect output, confirm sane.
5. `./scripts/release.sh v1.0.1` → real publish.
6. From the running v1.0.0 instance, click "Check Now" in Settings → confirm dialog appears with the v1.0.1 release notes, install completes, app relaunches as v1.0.1.

### Ongoing per-release verification (lightweight)

- `curl -fsS <appcast URL>` after each release returns valid XML with the new item at top.
- One "Check Now" from a previously-installed version.

### Failure modes explicitly accepted (won't unit-test)

- Sparkle network errors → handled by Sparkle, surfaced via its own UI.
- EdDSA signature mismatch → handled by Sparkle, update is rejected with a sheet.
- Notarization revocation by Apple → out of our control; recovery is a fresh signed build + new release.

## Open considerations (acknowledged, not blocking)

- The EdDSA private key lives in the keychain of one signing machine. If the user works from multiple Macs, the keychain item must be exported/imported. The spec doesn't automate this — it's a one-time per-machine step.
- The first real release (v1.0.0 with Sparkle baked in) cannot test the update flow against itself — by definition there's no prior version to update *from*. The first verifiable update cycle is v1.0.0 → v1.0.1.
- `<sparkle:minimumSystemVersion>` is hard-coded to `15.0` in the appcast template, matching the current `MACOSX_DEPLOYMENT_TARGET`. If the deployment target ever changes, `release.sh` reads it from `project.yml` rather than the hard-coded value.
- A user running v1.0.0 who never opts in to checking will stay on v1.0.0 indefinitely. This is by design — "automatic checks" is a user choice, not an obligation.
- If GitHub Pages goes down, update checks fail silently (Sparkle handles the network error). Users can still manually re-download the latest DMG from GitHub Releases. Acceptable single-point-of-failure for v1.
