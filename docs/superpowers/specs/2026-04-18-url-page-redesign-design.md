# URL page redesign

Date: 2026-04-18
Status: Draft

## Problem

Three related UX issues in the GalleryView's URL (Links) handling:

1. **Icons in the bottom gallery toolbar overflow off the right edge** when the breadcrumb is wide (observed: "Openrank & Karma3Labs" truncates the action and view-mode icons).
2. **Adding a URL is hard to discover and access.** The only entry point is a small `link`-icon button in the toolbar that opens a modal `AddLinkSheet`. The empty-state on the Links view literally says "Add a URL from the + menu" — but there is no such menu.
3. **The `link` icon is overloaded** — it appears both as the "Add URL" action and as the "Links" view-mode toggle in the same toolbar, visually adjacent. This is ambiguous.

## Goals

- Make URL entry first-class on the URL (Links) page: no modal, no icon hunt.
- Fix toolbar overflow so action icons are never clipped.
- Remove the ambiguous duplicate `link` icon.
- Auto-fetch page titles so saved URLs get meaningful labels without user effort.

## Non-goals

- Editing an existing URL's title/annotation in-place. (Today there is no edit UI; deferred to a future batch.)
- Importing URLs in bulk.
- Favicons / link-card images beyond what `LinkCardView` already renders.
- Re-indexing existing URLs to auto-fetch titles for them. Auto-fetch applies only to newly-added URLs.

## Design

### 1. Page layout

When `viewMode == .links` in `GalleryView`, the page is arranged top-to-bottom as:

```
┌────────────────────────────────────┐
│                                    │
│   URL list (scrolls)               │
│   LinkCardView, oldest → newest    │
│                                    │
├────────────────────────────────────┤
│ [  Paste a URL…  ]     (composer)  │  ← pinned
├────────────────────────────────────┤
│ Breadcrumb │ Add File │ New Folder │  ← existing toolbar
│ Clean Up │ | │ Grid │ List │ Links │
└────────────────────────────────────┘
```

- **List:** existing `ForEach(links)` content, no visual change per-row. Ordering: `scanProjectFolder` currently sorts links by `$0.date > $1.date` (newest first). Change this to `$0.date < $1.date` (oldest first) so new URLs appear next to the composer at the bottom.
- **Composer:** a single `TextField("Paste a URL…", text: $composerText)` wrapped in a styled container, sitting in its own `HStack` with the design token colors/borders the rest of the app uses. One-line, no multiline.
- **Autofocus:** on first appearance of the Links view (onAppear of the composer host), the TextField receives focus via `@FocusState`.
- **Empty state:** when `links.isEmpty`, the scroll area shows the existing `linksEmptyState` view with the text updated to "Paste a URL below to save it." The composer stays pinned, ready.

### 2. Saving a URL

Flow triggered by pressing Return in the composer:

1. **Validate.** Trim whitespace. Attempt `URL(string:)`. Require `scheme == "http"` or `scheme == "https"`. If invalid, briefly flash the composer border red (or beep via `NSSound.beep()`) and clear nothing. No error modal.
2. **Persist synchronously.** Generate an 8-char hex `uid` via `UID.generate()`. Construct `LinkItem(uid:, url:, title: "", annotation: "")`. Serialize with the existing `LinkItem.serialize` / `LinkItem.fileName(uid:)` helpers. Write atomically to `project.folderURL.appendingPathComponent(LinkItem.fileName(uid: uid))`.
3. **Clear the composer** so the next paste can go in immediately.
4. **Reconciler picks it up** via the existing FileWatcher path. UI re-renders within one debounce window.
5. **Kick off async title fetch.** In a detached `Task`, call `LinkTitleFetcher.fetch(url:)` (new helper) with a 5-second timeout. When the task completes, if a non-empty title is returned, load the `.md` file from disk, parse it into a `LinkItem`, update `title`, re-serialize, write back atomically. FileWatcher + reconciler re-index on the second write.
6. **On fetch failure or timeout:** the `LinkItem.title` stays empty. `LinkCardView` already renders the URL host as a fallback when title is empty; nothing to handle in the UI.

### 3. `LinkTitleFetcher` (new helper)

New file `PortyMcFolio/Services/LinkTitleFetcher.swift`. Responsibilities:

- Single static method `static func fetch(url: URL, timeout: TimeInterval = 5) async -> String?`.
- Internally uses `LPMetadataProvider().startFetchingMetadata(for: url)` and races it against `Task.sleep(for: .seconds(timeout))` using a `withTaskGroup(of: String?.self)` that returns the first non-`nil` result. The sleep branch cancels and returns `nil` on timeout; the fetch branch returns `metadata.title` on success or `nil` on failure.
- Returns `metadata.title` (Apple extracts this from `og:title`, `twitter:title`, and falls back to `<title>`). Returns `nil` if fetch fails, times out, or the returned title is nil/empty.

Isolating this avoids dragging `LinkPresentation` imports and async network code into `GalleryView`. Easily testable (mock-able at integration level via fixed URLs; not testing the macOS framework itself).

### 4. Toolbar cleanup

Three changes in the GalleryView bottom toolbar HStack:

1. **Remove the "Add URL" action button** (the `galleryAction(icon: "link", help: "Add URL") { isShowingAddLink = true }` block and its siblings — the popover for AddLinkSheet, the `@State var isShowingAddLink`, the `.sheet(isPresented: $isShowingAddLink)` modifier, and the call-site at line 629).
2. **Fix breadcrumb-vs-icons overflow.** Add `.layoutPriority(0)` to `BreadcrumbBar` and group the action-plus-view-mode icons in a sibling container with `.layoutPriority(1)`. Effect: when the HStack is tight, the breadcrumb truncates with its existing ellipsis behavior instead of clipping the icons.
3. **Delete `AddLinkSheet.swift`.** No remaining callers. One fewer file to maintain.

### 5. Files touched

- Modify: `PortyMcFolio/Views/GalleryView.swift`
  - Remove `isShowingAddLink` state, the sheet modifier, the Add-URL toolbar button, the second call-site at line ~629.
  - Extend `linksContent` / `linksEmptyState` with the composer (or factor a small subview for the composer area).
  - Add `@FocusState` for the composer.
  - Toolbar layout priority fix.
- Create: `PortyMcFolio/Services/LinkTitleFetcher.swift` — the helper above.
- Delete: `PortyMcFolio/Views/AddLinkSheet.swift`.
- `project.yml` / xcodeproj regen to pick up the new and deleted file.

## Testing plan

- **Unit test** for `LinkTitleFetcher`: hard to test the real `LPMetadataProvider` deterministically; skipped. If we add coverage later, we wrap it behind a protocol and inject a mock.
- **Unit test** for URL validation logic: if we factor the parse-and-validate out of `GalleryView`, add a small test for the `http/https`-only rule. Otherwise manual.
- **Manual acceptance criteria:**
  - Open a project with no links → switch to Links view → composer pinned at bottom with focus in it.
  - Paste `https://example.com`, press Enter → URL appears in list with host as title within ~1s; title updates to page title within ~2-5s.
  - Paste `not a url` → composer gives feedback, nothing saved.
  - Paste an FTP link or non-http URL → rejected.
  - Open a project with existing long breadcrumb → toolbar icons remain fully visible; breadcrumb truncates with ellipsis.
  - Only one `link` icon in the toolbar (the view-mode Links toggle).
  - `AddLinkSheet.swift` no longer in the source tree.

## Risks

- **`LPMetadataProvider` can be slow or hang** on some sites despite the 5s timeout, but our timeout guard covers it — the fetch task finishes one way or the other and the user already has the URL saved.
- **Two disk writes per URL** (save, then save-again with title). Small YAML files; reconciler handles it. Previously identified "database is locked" risk (fixed in Batch A) is not a concern here because writes go through the same reconciler flow that's been hardened.
- **Focus auto-focus on view-mode switch** may require a small amount of tuning to fire at the right moment — SwiftUI `@FocusState` + `NSViewRepresentable` interactions can be finicky. If the simple path doesn't work, fallback is `DispatchQueue.main.asyncAfter` with a short delay.
