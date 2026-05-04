# Code Review Bug Fixes & UX Improvements — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix security vulnerabilities, data-loss bugs, and UX issues identified in the code review of PortyMcFolio.

**Architecture:** Fixes span Swift (macOS app) and JS (CodeMirror editor). Each task is self-contained. JS changes go through Editor/src/ and are built with `cd Editor && npm run build`. Swift changes build via `xcodebuild -scheme PortyMcFolio -configuration Debug build`.

**Tech Stack:** Swift 5.9 / macOS 14, CodeMirror 6, Vite, GRDB, WebKit (WKWebView)

**Spec:** `docs/superpowers/specs/2026-04-13-code-review-bugfix-ux-design.md`

---

## File Structure

### New files
- `Editor/src/utils.js` — shared helpers (`esc`, `getDomain`, editor view singleton)
- `PortyMcFolio/Services/UID.swift` — shared UID generation
- `PortyMcFolio/Services/PathValidation.swift` — path containment check

### Modified files
- `PortyMcFolio/Editor/MediaSchemeHandler.swift` — add path traversal check (S1)
- `PortyMcFolio/Views/EditorView.swift` — path validation on openFile (Q5), error handling on file copy (B3)
- `Editor/src/markdown/media.js` — position-based delete (B1), use shared utils, export cache clear (U4)
- `Editor/src/markdown/embeds.js` — position-based delete (B2), use shared utils
- `Editor/src/commands.js` — slash command context check (U2), heading line-level apply (U3)
- `Editor/src/index.js` — call clearLinkMetadataCache in setMarkdown (U4), fix frontmatter bar coords (U5), use shared utils
- `PortyMcFolio/Views/GalleryView.swift` — DispatchSource folder watcher (U1)
- `PortyMcFolio/Models/LinkItem.swift` — use shared UID (Q4)
- `PortyMcFolio/Services/ProjectCreator.swift` — use shared UID (Q4)
- `PortyMcFolio/Views/AddLinkSheet.swift` — use shared UID (Q4)

---

## Task 1: Create shared JS utilities (Q1, Q2, Q3)

**Files:**
- Create: `Editor/src/utils.js`
- Modify: `Editor/src/markdown/media.js`
- Modify: `Editor/src/markdown/embeds.js`
- Modify: `Editor/src/index.js`

- [ ] **Step 1: Create `Editor/src/utils.js`**

```js
let _editorView = null

export function setEditorView(view) {
  _editorView = view
}

export function getEditorView() {
  return _editorView
}

export function esc(str) {
  const el = document.createElement('span')
  el.textContent = str
  return el.innerHTML
}

export function getDomain(url) {
  try { return new URL(url).hostname.replace(/^www\./, '') }
  catch { return url }
}
```

- [ ] **Step 2: Update `Editor/src/markdown/media.js` to use shared utils**

Remove the local `_editorView`, `setMediaEditorView`, `esc()`, and `getDomain()`. Replace with imports:

```js
// At top of file, replace existing imports with:
import { Decoration, WidgetType, EditorView } from '@codemirror/view'
import { StateField, Annotation } from '@codemirror/state'
import { getEditorView, esc, getDomain } from '../utils.js'
```

Remove these lines (current lines 12, 14-16, 36-40, 42-45):
- `let _editorView = null`
- `export function setMediaEditorView(view) { ... }`
- `function esc(str) { ... }`
- `function getDomain(url) { ... }`

Replace all `_editorView` references with `getEditorView()` throughout the file. Specifically in:
- `setLinkMetadata` (line 21): `if (_editorView)` → `const view = getEditorView(); if (view)`
- `createCloseButton` (line 56): `if (!_editorView) return` → `const view = getEditorView(); if (!view) return`, and `_editorView.state.doc` → `view.state.doc`, `_editorView.dispatch` → `view.dispatch`, `_editorView.focus()` → `view.focus()`

- [ ] **Step 3: Update `Editor/src/markdown/embeds.js` to use shared utils**

Remove `_embedView`, `setEmbedEditorView`, `esc()`, `getDomain()`. Replace with imports:

```js
// At top of file, replace existing imports with:
import { EditorView, Decoration, WidgetType } from '@codemirror/view'
import { StateField } from '@codemirror/state'
import { getEditorView, esc, getDomain } from '../utils.js'
```

Remove these lines (current lines 4-5, 76-79, 81-85):
- `let _embedView = null`
- `export function setEmbedEditorView(view) { ... }`
- `function getDomain(url) { ... }`
- `function esc(str) { ... }`

Replace all `_embedView` references with `getEditorView()`. Specifically in `createEmbedCloseButton` (line 17): `if (!_embedView) return` → `const view = getEditorView(); if (!view) return`, and all `_embedView.state.doc` → `view.state.doc`, `_embedView.dispatch` → `view.dispatch`, `_embedView.focus()` → `view.focus()`.

- [ ] **Step 4: Update `Editor/src/index.js` to use shared `setEditorView`**

Replace the two `setMediaEditorView` / `setEmbedEditorView` calls with one shared call.

Change the imports at the top of the file:

```js
// Remove these imports:
// import { mediaDecorations, setLinkMetadata, setMediaEditorView } from './markdown/media.js'
// import { embedDecorations, setEmbedEditorView } from './markdown/embeds.js'

// Replace with:
import { setEditorView } from './utils.js'
import { mediaDecorations, setLinkMetadata } from './markdown/media.js'
import { embedDecorations } from './markdown/embeds.js'
```

Replace lines 102-103:
```js
// Remove:
// setMediaEditorView(view)
// setEmbedEditorView(view)

// Replace with:
setEditorView(view)
```

Also remove the local `esc()` function (lines 255-259) and add import:

```js
import { setEditorView, esc } from './utils.js'
```

- [ ] **Step 5: Build and verify**

Run: `cd Editor && npm run build`
Expected: Build succeeds with no errors.

- [ ] **Step 6: Commit**

```bash
git add Editor/src/utils.js Editor/src/markdown/media.js Editor/src/markdown/embeds.js Editor/src/index.js
git commit -m "refactor: extract shared JS utilities — esc, getDomain, editorView singleton"
```

---

## Task 2: Position-based delete for media embeds (B1)

**Files:**
- Modify: `Editor/src/markdown/media.js`

- [ ] **Step 1: Refactor `createCloseButton` to use position**

Replace the existing `createCloseButton` function (lines 49-71) with:

```js
function createCloseButton(fromPos) {
  const btn = document.createElement('button')
  btn.className = 'cm-embed-close'
  btn.textContent = '\u00d7'
  btn.title = 'Remove'
  btn.addEventListener('click', (e) => {
    e.stopPropagation()
    const view = getEditorView()
    if (!view) return
    const doc = view.state.doc
    // fromPos points to line.from at decoration build time.
    // Decorations rebuild on every docChanged, so this is always current.
    if (fromPos < 0 || fromPos >= doc.length) return
    const line = doc.lineAt(fromPos)
    const from = line.from
    const to = Math.min(line.to + 1, doc.length)
    view.dispatch({ changes: { from, to } })
    view.focus()
  })
  return btn
}
```

- [ ] **Step 2: Update `wrapWithClose` to accept `fromPos` instead of `searchText`**

Replace the existing `wrapWithClose` function (lines 73-97) with:

```js
function wrapWithClose(innerEl, fromPos, labelText) {
  const outer = document.createElement('div')
  outer.className = 'cm-embed-wrapper'
  outer.appendChild(innerEl)

  if (labelText) {
    const footer = document.createElement('div')
    footer.className = 'cm-embed-footer'

    const label = document.createElement('span')
    label.className = 'cm-embed-footer-label'
    label.textContent = labelText

    footer.appendChild(label)
    footer.appendChild(createCloseButton(fromPos))
    outer.appendChild(footer)
  } else {
    // For cards without a separate label, put X in the card itself
    innerEl.appendChild(createCloseButton(fromPos))
    innerEl.classList.add('cm-embed-wrapper')
    return innerEl
  }

  return outer
}
```

- [ ] **Step 3: Update widget constructors to accept `fromPos`**

Update `MediaPreviewWidget`:

```js
class MediaPreviewWidget extends WidgetType {
  constructor(filename, fromPos) {
    super()
    this.filename = filename
    this.fromPos = fromPos
  }

  eq(other) {
    return this.filename === other.filename
  }

  toDOM() {
    // ... (existing DOM creation code stays the same until the return)
    return wrapWithClose(wrapper, this.fromPos, this.filename)
  }

  ignoreEvent() { return true }
}
```

Update `LinkCardWidget`:

```js
class LinkCardWidget extends WidgetType {
  constructor(filename, fromPos) {
    super()
    this.filename = filename
    this.fromPos = fromPos
    const meta = linkMetadataCache[filename]
    this.metaTitle = meta?.title || ''
    this.metaUrl = meta?.url || ''
  }

  eq(other) {
    return this.filename === other.filename
      && this.metaTitle === other.metaTitle
      && this.metaUrl === other.metaUrl
  }

  toDOM() {
    // ... (existing DOM creation code stays the same until the return)
    return wrapWithClose(card, this.fromPos, null)
  }

  ignoreEvent() { return true }
}
```

- [ ] **Step 4: Update `buildMediaDecorations` to pass `line.from`**

In the `buildMediaDecorations` function, update the widget construction (around current line 243-244):

```js
const widget = isLink
  ? new LinkCardWidget(filename, line.from)
  : new MediaPreviewWidget(filename, line.from)
```

- [ ] **Step 5: Build and verify**

Run: `cd Editor && npm run build`
Expected: Build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Editor/src/markdown/media.js
git commit -m "fix: delete button uses line position instead of substring search (B1)"
```

---

## Task 3: Position-based delete for embed callouts (B2)

**Files:**
- Modify: `Editor/src/markdown/embeds.js`

- [ ] **Step 1: Refactor `createEmbedCloseButton` to use position**

Replace the existing `createEmbedCloseButton` function (lines 10-31) with:

```js
function createEmbedCloseButton(blockFromPos) {
  const btn = document.createElement('button')
  btn.className = 'cm-embed-close'
  btn.textContent = '\u00d7'
  btn.title = 'Remove'
  btn.addEventListener('click', (e) => {
    e.stopPropagation()
    const view = getEditorView()
    if (!view) return
    const doc = view.state.doc
    if (blockFromPos < 0 || blockFromPos >= doc.length) return
    const startLine = doc.lineAt(blockFromPos)
    const block = parseCalloutBlock(doc, startLine.number)
    if (!block) return
    const from = doc.line(block.startLine).from
    const to = Math.min(doc.line(block.endLine).to + 1, doc.length)
    view.dispatch({ changes: { from, to } })
    view.focus()
  })
  return btn
}
```

- [ ] **Step 2: Update `wrapEmbedWithClose` to accept position**

Replace:

```js
function wrapEmbedWithClose(cardEl, blockFromPos) {
  cardEl.appendChild(createEmbedCloseButton(blockFromPos))
  return cardEl
}
```

- [ ] **Step 3: Update widget constructors to accept `blockFrom`**

Update `LinkCardWidget`:

```js
class LinkCardWidget extends WidgetType {
  constructor(url, title, blockFrom) {
    super()
    this.url = url
    this.title = title || getDomain(url)
    this.blockFrom = blockFrom
  }

  eq(other) {
    return this.url === other.url && this.title === other.title
  }

  toDOM() {
    const card = document.createElement('div')
    card.className = 'cm-embed-card cm-embed-link'
    card.innerHTML = `
      <span class="cm-embed-icon">\ud83d\udd17</span>
      <span class="cm-embed-title">${esc(this.title)}</span>
    `
    card.addEventListener('click', () => {
      try { window.webkit?.messageHandlers?.openURL?.postMessage(this.url) }
      catch { window.open(this.url, '_blank') }
    })
    return wrapEmbedWithClose(card, this.blockFrom)
  }

  ignoreEvent() { return true }
}
```

Update `FileCardWidget`:

```js
class FileCardWidget extends WidgetType {
  constructor(path, title, blockFrom) {
    super()
    this.path = path
    this.title = title || stripExtension(path)
    this.blockFrom = blockFrom
  }

  eq(other) {
    return this.path === other.path && this.title === other.title
  }

  toDOM() {
    const card = document.createElement('div')
    card.className = 'cm-embed-card cm-embed-file'
    card.innerHTML = `
      <span class="cm-embed-icon">${getFileIcon(this.path)}</span>
      <span class="cm-embed-title">${esc(this.title)}</span>
    `
    card.addEventListener('click', () => {
      try { window.webkit?.messageHandlers?.openFile?.postMessage(this.path) }
      catch {}
    })
    return wrapEmbedWithClose(card, this.blockFrom)
  }

  ignoreEvent() { return true }
}
```

- [ ] **Step 4: Update `buildEmbedDecorations` to pass `blockFrom`**

In the `buildEmbedDecorations` function, update the widget construction (around current line 157-158):

```js
const widget = block.type === 'link'
  ? new LinkCardWidget(block.fields.url, block.fields.title, blockFrom)
  : new FileCardWidget(block.fields.path, block.fields.title, blockFrom)
```

- [ ] **Step 5: Build and verify**

Run: `cd Editor && npm run build`
Expected: Build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Editor/src/markdown/embeds.js
git commit -m "fix: embed callout delete uses block position instead of substring search (B2)"
```

---

## Task 4: Slash command context check and heading fix (U2, U3)

**Files:**
- Modify: `Editor/src/commands.js`

- [ ] **Step 1: Fix slash command triggering mid-word (U2)**

Update the `slashCommandSource` function (lines 168-177):

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

- [ ] **Step 2: Fix heading commands to be line-level (U3)**

Update the three heading command `apply` functions. Replace the Heading 1 apply (lines 14-19):

```js
apply: (view, completion, from, to) => {
  const line = view.state.doc.lineAt(from)
  view.dispatch({
    changes: { from: line.from, to, insert: '# ' },
    selection: { anchor: line.from + 2 },
    annotations: pickedCompletion.of(completion),
  })
},
```

Replace the Heading 2 apply (lines 26-31):

```js
apply: (view, completion, from, to) => {
  const line = view.state.doc.lineAt(from)
  view.dispatch({
    changes: { from: line.from, to, insert: '## ' },
    selection: { anchor: line.from + 3 },
    annotations: pickedCompletion.of(completion),
  })
},
```

Replace the Heading 3 apply (lines 38-43):

```js
apply: (view, completion, from, to) => {
  const line = view.state.doc.lineAt(from)
  view.dispatch({
    changes: { from: line.from, to, insert: '### ' },
    selection: { anchor: line.from + 4 },
    annotations: pickedCompletion.of(completion),
  })
},
```

- [ ] **Step 3: Build and verify**

Run: `cd Editor && npm run build`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Editor/src/commands.js
git commit -m "fix: slash commands only trigger after whitespace; headings replace from line start (U2, U3)"
```

---

## Task 5: Clear link metadata cache on project switch (U4)

**Files:**
- Modify: `Editor/src/markdown/media.js`
- Modify: `Editor/src/index.js`

- [ ] **Step 1: Export `clearLinkMetadataCache` from media.js**

Add this function after the existing `setLinkMetadata` function in `media.js`:

```js
export function clearLinkMetadataCache() {
  for (const key of Object.keys(linkMetadataCache)) {
    delete linkMetadataCache[key]
  }
}
```

- [ ] **Step 2: Call it from `setMarkdown` in index.js**

Update the imports in `index.js`:

```js
import { mediaDecorations, setLinkMetadata, clearLinkMetadataCache } from './markdown/media.js'
```

Update the `setMarkdown` function to clear the cache before loading new content:

```js
function setMarkdown(content) {
  if (!view) return
  clearLinkMetadataCache()
  view.dispatch({
    changes: {
      from: 0,
      to: view.state.doc.length,
      insert: content || '',
    },
  })
  updateFooter(view.state.doc)
  updateFrontmatterBar(view.state.doc)
}
```

- [ ] **Step 3: Update `PortyEditor` export to include `setLinkMetadata`**

The `setLinkMetadata` export on line 331 should already be there. Verify the export object includes it:

```js
const PortyEditor = { init: initEditor, setMarkdown, getMarkdown, focus, insertMediaEmbed, insertLinkCard, insertFileCard, setLastModified, setLinkMetadata }
```

- [ ] **Step 4: Build and verify**

Run: `cd Editor && npm run build`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Editor/src/markdown/media.js Editor/src/index.js
git commit -m "fix: clear link metadata cache on project switch (U4)"
```

---

## Task 6: Fix frontmatter bar visibility check (U5)

**Files:**
- Modify: `Editor/src/index.js`

- [ ] **Step 1: Update `checkFrontmatterVisibility` to use scroller bounds**

Replace the `checkFrontmatterVisibility` function (lines 298-318):

```js
function checkFrontmatterVisibility() {
  if (!view) return
  const bar = document.getElementById('frontmatter-bar')
  if (!bar || !fmBarContent) return

  const doc = view.state.doc
  const text = doc.toString()
  const fmMatch = text.match(/^---\n[\s\S]*?\n---/)
  if (!fmMatch) { bar.classList.remove('visible'); return }

  const fmEndPos = fmMatch[0].length
  const coords = view.coordsAtPos(fmEndPos)
  if (!coords) return

  // Compare against the scroller's actual top, not hard-coded 0
  const scroller = view.dom.querySelector('.cm-scroller')
  const scrollerTop = scroller ? scroller.getBoundingClientRect().top : 0

  if (coords.bottom < scrollerTop) {
    bar.classList.add('visible')
  } else {
    bar.classList.remove('visible')
  }
}
```

- [ ] **Step 2: Build and verify**

Run: `cd Editor && npm run build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Editor/src/index.js
git commit -m "fix: frontmatter bar uses scroller bounds instead of hard-coded 0 (U5)"
```

---

## Task 7: Path validation helper and security fixes (S1, Q5)

**Files:**
- Create: `PortyMcFolio/Services/PathValidation.swift`
- Modify: `PortyMcFolio/Editor/MediaSchemeHandler.swift`
- Modify: `PortyMcFolio/Views/EditorView.swift`

- [ ] **Step 1: Create `PathValidation.swift`**

```swift
import Foundation

enum PathValidation {
    /// Returns true if `fileURL` resolves to a path inside `folderURL`.
    static func isContained(fileURL: URL, within folderURL: URL) -> Bool {
        let filePath = fileURL.standardizedFileURL.path
        let folderPath = folderURL.standardizedFileURL.path
        // Ensure folder path ends with / so "/foo/bar" doesn't match "/foo/barbaz"
        let prefix = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
        return filePath.hasPrefix(prefix)
    }
}
```

- [ ] **Step 2: Add path check to `MediaSchemeHandler.swift` (S1)**

Add the check after resolving `fileURL` (after current line 18, before the `fileExists` check):

```swift
let filename = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
let decodedFilename = filename.removingPercentEncoding ?? filename
let fileURL = projectFolder.appendingPathComponent(decodedFilename)

// Prevent path traversal outside the project folder
guard PathValidation.isContained(fileURL: fileURL, within: projectFolder) else {
    urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
    return
}

guard FileManager.default.fileExists(atPath: fileURL.path) else {
```

- [ ] **Step 3: Add path check to `openFile` handler in `EditorView.swift` (Q5)**

Update the `bridge.onOpenFile` closure (current lines 133-138):

```swift
bridge.onOpenFile = { [weak self] path in
    guard let self else { return }
    let projectFolder = self.readmeURL.deletingLastPathComponent()
    let fileURL = projectFolder.appendingPathComponent(path)
    guard PathValidation.isContained(fileURL: fileURL, within: projectFolder) else { return }
    NSWorkspace.shared.open(fileURL)
}
```

- [ ] **Step 4: Build and verify**

Run: `xcodebuild -scheme PortyMcFolio -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Services/PathValidation.swift PortyMcFolio/Editor/MediaSchemeHandler.swift PortyMcFolio/Views/EditorView.swift
git commit -m "fix: prevent path traversal in media scheme handler and openFile (S1, Q5)"
```

---

## Task 8: Error handling for file copy operations (B3)

**Files:**
- Modify: `PortyMcFolio/Views/EditorView.swift`

- [ ] **Step 1: Fix `insertMediaFile` to handle copy errors**

Replace the `try?` copy block in `insertMediaFile` (current lines 151-155):

```swift
let filename: String
if filePath.hasPrefix(projectPath + "/") {
    filename = String(filePath.dropFirst(projectPath.count + 1))
} else {
    let destURL = projectFolder.appendingPathComponent(url.lastPathComponent)
    if !FileManager.default.fileExists(atPath: destURL.path) {
        do {
            try FileManager.default.copyItem(at: url, to: destURL)
        } catch {
            DispatchQueue.main.async {
                let alert = NSAlert(error: error)
                alert.messageText = "Failed to import media"
                alert.runModal()
            }
            return
        }
    }
    filename = url.lastPathComponent
}
```

- [ ] **Step 2: Fix `insertFileReference` to handle copy errors**

Replace the `try?` copy block in `insertFileReference` (current lines 174-178):

```swift
let filename: String
if filePath.hasPrefix(projectPath + "/") {
    filename = String(filePath.dropFirst(projectPath.count + 1))
} else {
    let destURL = projectFolder.appendingPathComponent(url.lastPathComponent)
    if !FileManager.default.fileExists(atPath: destURL.path) {
        do {
            try FileManager.default.copyItem(at: url, to: destURL)
        } catch {
            DispatchQueue.main.async {
                let alert = NSAlert(error: error)
                alert.messageText = "Failed to import file"
                alert.runModal()
            }
            return
        }
    }
    filename = url.lastPathComponent
}
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -scheme PortyMcFolio -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Views/EditorView.swift
git commit -m "fix: show error alert when file import fails instead of silent failure (B3)"
```

---

## Task 9: Gallery auto-refresh with DispatchSource (U1)

**Files:**
- Modify: `PortyMcFolio/Views/GalleryView.swift`

- [ ] **Step 1: Add a folder watcher to GalleryView**

Add a `FolderWatcher` helper class at the bottom of `GalleryView.swift` (after the closing `}` of `GalleryView`):

```swift
private final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?

    func watch(url: URL, onChange: @escaping () -> Void) {
        stop()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { onChange() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit { stop() }
}
```

- [ ] **Step 2: Wire the watcher into GalleryView**

Add a `@State` property for the watcher and connect it in `.onAppear` / `.onDisappear`. Update the state declarations at the top of GalleryView:

```swift
@State private var links: [LinkItem] = []
@State private var files: [URL] = []
@State private var selectedFileURL: URL?
@State private var isShowingAddLink = false
@State private var folderWatcher = FolderWatcher()
```

Update the `.onAppear` modifier to start watching:

```swift
.onAppear {
    scanProjectFolder()
    folderWatcher.watch(url: project.folderURL) { [self] in
        scanProjectFolder()
    }
}
.onDisappear {
    folderWatcher.stop()
}
```

Remove the manual `scanProjectFolder()` call from the `.sheet` modifier's `onCreated` closure since the watcher will handle it:

```swift
.sheet(isPresented: $isShowingAddLink) {
    AddLinkSheet(projectFolderURL: project.folderURL)
}
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -scheme PortyMcFolio -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Views/GalleryView.swift
git commit -m "feat: gallery auto-refreshes when project folder changes (U1)"
```

---

## Task 10: Shared UID generation (Q4)

**Files:**
- Create: `PortyMcFolio/Services/UID.swift`
- Modify: `PortyMcFolio/Models/LinkItem.swift`
- Modify: `PortyMcFolio/Services/ProjectCreator.swift`
- Modify: `PortyMcFolio/Views/AddLinkSheet.swift`

- [ ] **Step 1: Create `UID.swift`**

```swift
import Foundation
import Security

enum UID {
    /// Generate an 8-character hex string using cryptographically random bytes.
    static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 4)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 2: Update `LinkItem.parse()` in `LinkItem.swift`**

Replace line 80:

```swift
// Old:
// let uid = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(8).description

// New:
let uid = UID.generate()
```

- [ ] **Step 3: Update `ProjectCreator.create()` in `ProjectCreator.swift`**

Replace line 17:

```swift
// Old:
// let uid = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()

// New:
let uid = UID.generate()
```

- [ ] **Step 4: Update `AddLinkSheet` in `AddLinkSheet.swift`**

Replace the `generateUID()` method call on line 77 with `UID.generate()`:

```swift
let uid = UID.generate()
```

Remove the private `generateUID()` method (lines 102-106).

- [ ] **Step 5: Build and run tests**

Run: `xcodebuild -scheme PortyMcFolio -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

Run: `xcodebuild test -scheme PortyMcFolioTests -configuration Debug 2>&1 | tail -10`
Expected: Tests pass.

- [ ] **Step 6: Commit**

```bash
git add PortyMcFolio/Services/UID.swift PortyMcFolio/Models/LinkItem.swift PortyMcFolio/Services/ProjectCreator.swift PortyMcFolio/Views/AddLinkSheet.swift
git commit -m "refactor: consolidate UID generation into shared UID.generate() (Q4)"
```

---

## Task 11: Final build and verification

- [ ] **Step 1: Full JS build**

Run: `cd Editor && npm run build`
Expected: Build succeeds.

- [ ] **Step 2: Full Swift build**

Run: `xcodebuild -scheme PortyMcFolio -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Run Swift tests**

Run: `xcodebuild test -scheme PortyMcFolioTests -configuration Debug 2>&1 | tail -10`
Expected: All tests pass.
