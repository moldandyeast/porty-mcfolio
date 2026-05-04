# Code Review: Bug Fixes & UX Improvements

**Date:** 2026-04-13
**Branch:** `dev/v1-implementation`
**Scope:** Full-stack — Editor (JS/CodeMirror) + Swift app

---

## P0 — Security

### S1. Path traversal in MediaSchemeHandler

**File:** `PortyMcFolio/Editor/MediaSchemeHandler.swift:16-18`

**Problem:** The custom `portymcfolio://` URL scheme handler extracts a filename from the URL path and appends it to the project folder via `appendingPathComponent()` with no boundary validation. A crafted URL like `portymcfolio://media/../../etc/passwd` resolves outside the project directory.

**Fix:** Add a shared path validation helper and apply it after resolving the file URL:

```swift
// Shared utility (new file or extension)
func isContained(fileURL: URL, within folderURL: URL) -> Bool {
    let filePath = fileURL.standardizedFileURL.path
    let folderPath = folderURL.standardizedFileURL.path + "/"
    return filePath.hasPrefix(folderPath)
}
```

Apply in `MediaSchemeHandler.webView(_:start:)` before reading the file. Return `fileDoesNotExist` error if validation fails.

### Q5. Path traversal in openFile handler

**File:** `PortyMcFolio/Views/EditorView.swift:134-138`

**Problem:** Same issue — `bridge.onOpenFile` appends a JS-provided path to the project folder and opens it with `NSWorkspace`. A `../../` path escapes the project.

**Fix:** Apply the same `isContained` check before calling `NSWorkspace.shared.open()`. Silently ignore invalid paths (no UI needed — this is a defense-in-depth check).

---

## P1 — Data Loss Bugs

### B1. Delete button deletes wrong media embed

**File:** `Editor/src/markdown/media.js:49-71`

**Problem:** `createCloseButton(searchText)` finds the *first* line containing the search text via `line.text.includes(searchText)`. With duplicate `![[image.png]]` embeds, clicking X on the second one deletes the first.

**Fix:** Pass the decoration's `from` position to the widget at construction time. The close button uses this position to look up the current line (positions shift after edits, so resolve `from` to a line at click time via `doc.lineAt(from)`). This is safe because CodeMirror rebuilds decorations on every doc change, so the `from` stored in the widget always reflects the latest state.

Changes:
- `MediaPreviewWidget` and `LinkCardWidget` constructors accept `from` (line start position)
- `createCloseButton(from)` uses `doc.lineAt(from)` to find the exact line to delete
- `buildMediaDecorations()` passes `line.from` to widget constructors

### B2. Embed callout delete is ambiguous

**File:** `Editor/src/markdown/embeds.js:10-31`

**Problem:** Same pattern — `createEmbedCloseButton("> [!link]")` searches for the first matching line. With two link callouts, the wrong block gets deleted.

**Fix:** Same approach as B1 — pass `blockFrom` position to widget constructors. The close button resolves the position to a line at click time, then calls `parseCalloutBlock()` from that line to find the full block range.

Changes:
- `LinkCardWidget` and `FileCardWidget` constructors accept `blockFrom`
- `createEmbedCloseButton(blockFrom)` resolves position at click time
- `buildEmbedDecorations()` passes `blockFrom` to widget constructors

### B3. Silent file copy failures

**Files:** `PortyMcFolio/Views/EditorView.swift:152-154`, `175-177`

**Problem:** Both `insertMediaFile()` and `insertFileReference()` use `try?` when copying external files into the project folder. If the copy fails (permissions, disk full, name collision), the embed is still inserted referencing a file that doesn't exist. The user sees a broken preview with no feedback.

**Fix:** Replace `try?` with `do/try/catch`. On failure, show an `NSAlert` with the error message and return early (don't insert the embed).

```swift
do {
    try FileManager.default.copyItem(at: url, to: destURL)
} catch {
    DispatchQueue.main.async {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
    return
}
```

---

## P2 — UX Issues

### U1. Gallery doesn't refresh after editor changes

**File:** `PortyMcFolio/Views/GalleryView.swift:65-67`

**Problem:** `scanProjectFolder()` runs only on `.onAppear` and after `AddLinkSheet` dismissal. Links added via the editor (drag-drop, `/link` command) don't appear in the gallery until the user navigates away and back.

**Fix:** Add a `refreshID` (UUID) to the parent that both EditorView and GalleryView observe. When EditorView's `onSave` fires and the content includes new embeds, or when a link/file is inserted, bump the `refreshID`. GalleryView watches this via `.onChange(of: refreshID)` and re-scans.

Alternative (simpler): Use a `DispatchSource.makeFileSystemObjectSource` on the project folder inside GalleryView to watch for file creates/deletes and auto-rescan. This is self-contained and doesn't require threading state through the parent.

**Recommended:** The `DispatchSource` approach — it's local to GalleryView and catches all changes regardless of source.

### U2. Slash commands trigger mid-word

**File:** `Editor/src/commands.js:169`

**Problem:** The regex `/\/\w*/` matches `/` anywhere. Typing `path/to` or a URL opens the command autocomplete.

**Fix:** Check the character before `match.from`. If it's not whitespace or start-of-line, return `null`:

```js
function slashCommandSource(context) {
  const match = context.matchBefore(/\/\w*/)
  if (!match) return null

  // Only trigger at line start or after whitespace
  if (match.from > 0) {
    const before = context.state.doc.sliceString(match.from - 1, match.from)
    if (before !== ' ' && before !== '\t' && before !== '\n') return null
  }

  return {
    from: match.from,
    filter: false,
    options: filterCommands(context.state.doc.sliceString(match.from + 1, context.pos)),
  }
}
```

### U3. Heading commands should be line-level

**File:** `Editor/src/commands.js:14-45`

**Problem:** Heading commands replace only the `/trigger` text with `# `. If there's text before the `/` on the same line, the heading marker ends up mid-line (e.g., `some text # heading`).

**Fix:** For heading commands, replace from `line.from` to `to` (the trigger end). This makes the heading take over the full line, which is the correct behavior since headings are block-level elements. Any text before the `/` on that line becomes part of the heading — which is the user's likely intent when they type text then decide to make it a heading.

```js
apply: (view, completion, from, to) => {
  const line = view.state.doc.lineAt(from)
  view.dispatch({
    changes: { from: line.from, to, insert: '# ' },
    selection: { anchor: line.from + 2 },
    annotations: pickedCompletion.of(completion),
  })
}
```

### U4. Link metadata cache grows unbounded

**File:** `Editor/src/markdown/media.js:11`

**Problem:** `linkMetadataCache` is a plain object that accumulates entries across project switches. When `setMarkdown()` is called for a new project, stale metadata from the previous project remains.

**Fix:** Export a `clearLinkMetadataCache()` function from `media.js`. Call it from `setMarkdown()` in `index.js` before setting new content.

```js
export function clearLinkMetadataCache() {
  for (const key of Object.keys(linkMetadataCache)) {
    delete linkMetadataCache[key]
  }
}
```

### U5. Frontmatter bar visibility check

**File:** `Editor/src/index.js:313`

**Problem:** `coords.bottom < 0` assumes the viewport starts at y=0. If the editor has padding, or the WKWebView's viewport is offset, the threshold is wrong.

**Fix:** Compare against the scroller's actual top position:

```js
const scroller = view.dom.querySelector('.cm-scroller')
const scrollerTop = scroller ? scroller.getBoundingClientRect().top : 0
if (coords.bottom < scrollerTop) {
  bar.classList.add('visible')
} else {
  bar.classList.remove('visible')
}
```

---

## P3 — Code Cleanup

### Q1. Duplicate `esc()` helper

**Files:** `index.js:255`, `media.js:36`, `embeds.js:81`

**Fix:** Create `Editor/src/utils.js` with the shared `esc()` function. Import from all three files. Remove the local copies.

### Q2. Duplicate `getDomain()` helper

**Files:** `media.js:42`, `embeds.js:76`

**Fix:** Move to `utils.js` alongside `esc()`.

### Q3. Two separate `_editorView` globals

**Files:** `media.js:12` (`_editorView`), `embeds.js:4` (`_embedView`)

**Fix:** Move to `utils.js` as a single shared `editorView` reference with `setEditorView()` / `getEditorView()`. Call `setEditorView(view)` once in `index.js` after creating the view. Both `media.js` and `embeds.js` import `getEditorView()`.

### Q4. Inconsistent UID generation

**Files:** `PortyMcFolio/Models/LinkItem.swift`, `PortyMcFolio/Services/ProjectCreator.swift`, `PortyMcFolio/Views/AddLinkSheet.swift`

**Fix:** Create a shared utility function in a new file or as a static method:

```swift
enum UID {
    static func generate(length: Int = 8) -> String {
        var bytes = [UInt8](repeating: 0, count: length / 2)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
```

Use `UID.generate()` in all three locations. The `SecRandomCopyBytes` approach is the most correct (cryptographically random, no UUID truncation).

---

## Summary

| ID | Priority | Area | Fix Complexity |
|----|----------|------|---------------|
| S1 | P0 | Security | Small — add path check |
| Q5 | P0 | Security | Small — add path check |
| B1 | P1 | Editor JS | Medium — refactor widget constructors |
| B2 | P1 | Editor JS | Medium — refactor widget constructors |
| B3 | P1 | Swift | Small — error handling |
| U1 | P2 | Swift | Medium — folder watcher in GalleryView |
| U2 | P2 | Editor JS | Small — context check |
| U3 | P2 | Editor JS | Small — line-level replace |
| U4 | P2 | Editor JS | Small — cache clear |
| U5 | P2 | Editor JS | Small — coord comparison |
| Q1 | P3 | Editor JS | Small — extract utility |
| Q2 | P3 | Editor JS | Small — extract utility |
| Q3 | P3 | Editor JS | Small — shared reference |
| Q4 | P3 | Swift | Small — shared UID |
