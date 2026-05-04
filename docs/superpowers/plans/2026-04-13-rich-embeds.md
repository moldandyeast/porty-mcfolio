# Rich Embeds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add rich card rendering for link URLs and non-media file references in the editor, with insertion via slash commands, drag & drop, and URL input.

**Architecture:** New `embeds.js` decoration plugin detects `> [!link]` and `> [!file]` callout blocks and renders them as styled cards. Swift handles URL metadata fetching via `LPMetadataProvider`, file picking, and smart routing of drops (media → `![[]]`, non-media → `> [!file]`). Bridge extended with new messages for link input and file picker.

**Tech Stack:** CodeMirror 6 (StateField decorations, WidgetType), Swift/WKWebView, LinkPresentation framework, NSOpenPanel

---

### Task 1: Add bridge messages and JS insertion functions

**Files:**
- Modify: `Editor/src/bridge.js`
- Modify: `Editor/src/index.js`

- [ ] **Step 1: Add new bridge messages to bridge.js**

Add these two functions at the end of `Editor/src/bridge.js`:

```javascript
export function postRequestLinkInput() {
  try {
    window.webkit?.messageHandlers?.requestLinkInput?.postMessage(null)
  } catch (e) {
    // Not in WKWebView
  }
}

export function postRequestFilePicker() {
  try {
    window.webkit?.messageHandlers?.requestFilePicker?.postMessage(null)
  } catch (e) {
    // Not in WKWebView
  }
}
```

- [ ] **Step 2: Add insertLinkCard and insertFileCard to index.js**

Add these two functions in `Editor/src/index.js`, after the `insertMediaEmbed` function:

```javascript
function insertLinkCard(url, title, description) {
  if (!view) return
  const doc = view.state.doc
  const pos = view.state.selection.main.head
  const line = doc.lineAt(pos)

  const lines = [`> [!link]`, `> url: ${url}`]
  if (title) lines.push(`> title: ${title}`)
  if (description) lines.push(`> description: ${description}`)
  const block = lines.join('\n')

  let insertPos, insert
  if (line.text.trim() === '') {
    insertPos = line.from
    insert = block + '\n'
  } else {
    insertPos = line.to
    insert = '\n\n' + block + '\n'
  }

  view.dispatch({
    changes: { from: insertPos, to: insertPos, insert },
    selection: { anchor: insertPos + insert.length },
  })
  view.focus()
}

function insertFileCard(path, title) {
  if (!view) return
  const doc = view.state.doc
  const pos = view.state.selection.main.head
  const line = doc.lineAt(pos)

  const lines = [`> [!file]`, `> path: ${path}`]
  if (title && title !== path) lines.push(`> title: ${title}`)
  const block = lines.join('\n')

  let insertPos, insert
  if (line.text.trim() === '') {
    insertPos = line.from
    insert = block + '\n'
  } else {
    insertPos = line.to
    insert = '\n\n' + block + '\n'
  }

  view.dispatch({
    changes: { from: insertPos, to: insertPos, insert },
    selection: { anchor: insertPos + insert.length },
  })
  view.focus()
}
```

Then update the `PortyEditor` object to include both:

```javascript
const PortyEditor = { init: initEditor, setMarkdown, getMarkdown, focus, insertMediaEmbed, insertLinkCard, insertFileCard, setLastModified }
```

- [ ] **Step 3: Commit**

```bash
git add Editor/src/bridge.js Editor/src/index.js
git commit -m "feat: add bridge messages and JS functions for link/file cards"
```

---

### Task 2: Add slash commands for Insert Link and Insert File

**Files:**
- Modify: `Editor/src/commands.js`

- [ ] **Step 1: Import the new bridge functions**

In `Editor/src/commands.js`, update the import line:

```javascript
import { postRequestMediaPicker, postRequestLinkInput, postRequestFilePicker } from './bridge.js'
```

- [ ] **Step 2: Add the two new command items**

Add these two items to the `commandItems` array, after the `Insert Media` entry (before the closing `]`):

```javascript
  {
    label: 'Insert Link',
    icon: '\ud83d\udd17',
    section: mediaSection,
    apply: (view, completion, from, to) => {
      view.dispatch({
        changes: { from, to, insert: '' },
        annotations: pickedCompletion.of(completion),
      })
      postRequestLinkInput()
    },
  },
  {
    label: 'Insert File',
    icon: '\ud83d\udcce',
    section: mediaSection,
    apply: (view, completion, from, to) => {
      view.dispatch({
        changes: { from, to, insert: '' },
        annotations: pickedCompletion.of(completion),
      })
      postRequestFilePicker()
    },
  },
```

- [ ] **Step 3: Commit**

```bash
git add Editor/src/commands.js
git commit -m "feat: add Insert Link and Insert File slash commands"
```

---

### Task 3: Create embeds decoration plugin

**Files:**
- Create: `Editor/src/markdown/embeds.js`
- Modify: `Editor/src/index.js`

- [ ] **Step 1: Create the embeds.js decoration plugin**

Create `Editor/src/markdown/embeds.js` with the following content:

```javascript
import { EditorView, Decoration, WidgetType } from '@codemirror/view'
import { StateField } from '@codemirror/state'

const CALLOUT_RE = /^> \[!(link|file)\]\s*$/
const FIELD_RE = /^> (\w+): (.+)$/

function parseCalloutBlock(doc, startLine) {
  const typeMatch = doc.line(startLine).text.match(CALLOUT_RE)
  if (!typeMatch) return null

  const type = typeMatch[1]
  const fields = {}
  let endLine = startLine

  for (let i = startLine + 1; i <= doc.lines; i++) {
    const line = doc.line(i)
    const fieldMatch = line.text.match(FIELD_RE)
    if (fieldMatch) {
      fields[fieldMatch[1]] = fieldMatch[2]
      endLine = i
    } else {
      break
    }
  }

  if (type === 'link' && !fields.url) return null
  if (type === 'file' && !fields.path) return null

  return { type, fields, startLine, endLine }
}

function getFileIcon(path) {
  const ext = path.split('.').pop()?.toLowerCase() || ''
  const icons = {
    pdf: '\ud83d\udcc4',
    sketch: '\ud83c\udfa8', fig: '\ud83c\udfa8', figma: '\ud83c\udfa8',
    zip: '\ud83d\udce6', rar: '\ud83d\udce6', tar: '\ud83d\udce6', gz: '\ud83d\udce6',
    doc: '\ud83d\udcc4', docx: '\ud83d\udcc4', txt: '\ud83d\udcc4', rtf: '\ud83d\udcc4',
    xls: '\ud83d\udcc4', xlsx: '\ud83d\udcc4', csv: '\ud83d\udcc4',
    ppt: '\ud83d\udcc4', pptx: '\ud83d\udcc4', key: '\ud83d\udcc4',
  }
  return icons[ext] || '\ud83d\udcc1'
}

function getDomain(url) {
  try { return new URL(url).hostname.replace(/^www\./, '') }
  catch { return url }
}

class LinkCardWidget extends WidgetType {
  constructor(url, title, description) {
    super()
    this.url = url
    this.title = title || getDomain(url)
    this.description = description || ''
  }

  eq(other) {
    return this.url === other.url && this.title === other.title && this.description === other.description
  }

  toDOM() {
    const card = document.createElement('div')
    card.className = 'cm-embed-card cm-embed-link'
    card.innerHTML = `
      <span class="cm-embed-icon">\ud83d\udd17</span>
      <div class="cm-embed-body">
        <div class="cm-embed-title">${esc(this.title)}</div>
        <div class="cm-embed-subtitle">${esc(getDomain(this.url))}</div>
        ${this.description ? `<div class="cm-embed-desc">${esc(this.description)}</div>` : ''}
      </div>
    `
    card.addEventListener('click', () => {
      try { window.webkit?.messageHandlers?.openURL?.postMessage(this.url) }
      catch { window.open(this.url, '_blank') }
    })
    card.style.cursor = 'pointer'
    return card
  }

  ignoreEvent() { return true }
}

class FileCardWidget extends WidgetType {
  constructor(path, title) {
    super()
    this.path = path
    this.title = title || path
  }

  eq(other) {
    return this.path === other.path && this.title === other.title
  }

  toDOM() {
    const ext = this.path.split('.').pop()?.toUpperCase() || 'FILE'
    const card = document.createElement('div')
    card.className = 'cm-embed-card cm-embed-file'
    card.innerHTML = `
      <span class="cm-embed-icon">${getFileIcon(this.path)}</span>
      <div class="cm-embed-body">
        <div class="cm-embed-title">${esc(this.title)}</div>
        <div class="cm-embed-subtitle">${esc(this.path)} · ${ext}</div>
      </div>
    `
    card.addEventListener('click', () => {
      try { window.webkit?.messageHandlers?.openFile?.postMessage(this.path) }
      catch {}
    })
    card.style.cursor = 'pointer'
    return card
  }

  ignoreEvent() { return true }
}

function esc(str) {
  const el = document.createElement('span')
  el.textContent = str
  return el.innerHTML
}

function buildEmbedDecorations(state) {
  const decorations = []
  const doc = state.doc

  for (let i = 1; i <= doc.lines; i++) {
    const block = parseCalloutBlock(doc, i)
    if (!block) continue

    // Hide the callout lines (show on focus via CSS)
    for (let ln = block.startLine; ln <= block.endLine; ln++) {
      decorations.push(
        Decoration.line({ class: 'cm-embed-source-line' }).range(doc.line(ln).from)
      )
    }

    // Add widget before the block
    const widget = block.type === 'link'
      ? new LinkCardWidget(block.fields.url, block.fields.title, block.fields.description)
      : new FileCardWidget(block.fields.path, block.fields.title)

    decorations.push(
      Decoration.widget({
        widget,
        side: -1,
        block: true,
      }).range(doc.line(block.startLine).from)
    )

    // Skip to end of block
    i = block.endLine
  }

  return Decoration.set(decorations, true)
}

const embedField = StateField.define({
  create(state) {
    return buildEmbedDecorations(state)
  },
  update(decorations, tr) {
    if (tr.docChanged) {
      return buildEmbedDecorations(tr.state)
    }
    return decorations
  },
  provide(field) {
    return EditorView.decorations.from(field)
  },
})

export const embedDecorations = embedField
```

- [ ] **Step 2: Wire embedDecorations into the editor extensions**

In `Editor/src/index.js`, add the import after the existing markdown imports:

```javascript
import { embedDecorations } from './markdown/embeds.js'
```

Then add `embedDecorations` to the extensions array, after `mediaDecorations`:

```javascript
        mediaDecorations,
        embedDecorations,
```

- [ ] **Step 3: Commit**

```bash
git add Editor/src/markdown/embeds.js Editor/src/index.js
git commit -m "feat: add embed decoration plugin for link and file cards"
```

---

### Task 4: Add CSS styles for embed cards

**Files:**
- Modify: `PortyMcFolio/Editor/Resources/editor.css`

- [ ] **Step 1: Add embed card styles**

Add the following CSS before the `/* ── Slash Command Menu */` section in `editor.css`:

```css
/* ── Embed Cards (Link & File) ──────────────────────── */

.cm-embed-card {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  padding: 12px 16px;
  margin: 8px 0;
  background: var(--bg-secondary);
  border: 1px solid var(--border-light);
  border-radius: 10px;
  font-family: -apple-system, BlinkMacSystemFont, sans-serif;
  transition: border-color 0.15s;
}

.cm-embed-card:hover {
  border-color: var(--border);
}

.cm-embed-icon {
  font-size: 20px;
  line-height: 1;
  flex-shrink: 0;
  padding-top: 2px;
}

.cm-embed-body {
  min-width: 0;
  flex: 1;
}

.cm-embed-title {
  font-size: 13px;
  font-weight: 550;
  color: var(--text);
  line-height: 1.3;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.cm-embed-subtitle {
  font-size: 11px;
  color: var(--text-faint);
  line-height: 1.3;
  margin-top: 1px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.cm-embed-desc {
  font-size: 11px;
  color: var(--text-muted);
  line-height: 1.4;
  margin-top: 4px;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.cm-embed-link {
  cursor: pointer;
}

.cm-embed-file {
  cursor: pointer;
}

/* Source lines hidden by default, shown when cursor is on them */
.cm-embed-source-line {
  font-size: 11px !important;
  line-height: 1.4 !important;
  color: var(--text-faint) !important;
  padding-top: 1px !important;
  padding-bottom: 1px !important;
}
```

- [ ] **Step 2: Commit**

```bash
git add PortyMcFolio/Editor/Resources/editor.css
git commit -m "feat: add CSS styles for link and file embed cards"
```

---

### Task 5: Add Swift bridge handlers — link input, file picker, metadata fetching, smart routing

**Files:**
- Modify: `PortyMcFolio/Editor/EditorBridge.swift`
- Modify: `PortyMcFolio/Views/EditorView.swift`

- [ ] **Step 1: Update EditorBridge with new message handlers**

Replace the entire contents of `PortyMcFolio/Editor/EditorBridge.swift` with:

```swift
import Foundation
import WebKit

final class EditorBridge: NSObject, WKScriptMessageHandler {
    var onContentChanged: ((String) -> Void)?
    var onRequestMediaPicker: (() -> Void)?
    var onRequestLinkInput: (() -> Void)?
    var onRequestFilePicker: (() -> Void)?
    var onOpenURL: ((String) -> Void)?
    var onOpenFile: ((String) -> Void)?
    var onEditorReady: (() -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "contentChanged":
            if let content = message.body as? String {
                onContentChanged?(content)
            }
        case "requestMediaPicker":
            onRequestMediaPicker?()
        case "requestLinkInput":
            onRequestLinkInput?()
        case "requestFilePicker":
            onRequestFilePicker?()
        case "openURL":
            if let urlString = message.body as? String {
                onOpenURL?(urlString)
            }
        case "openFile":
            if let path = message.body as? String {
                onOpenFile?(path)
            }
        case "editorReady":
            onEditorReady?()
        default: break
        }
    }

    func loadMarkdown(in webView: WKWebView, content: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: [content]),
              let jsonArray = String(data: data, encoding: .utf8) else { return }
        let jsonString = String(jsonArray.dropFirst().dropLast())
        webView.evaluateJavaScript("window.PortyEditor.setMarkdown(\(jsonString))")
    }
}
```

- [ ] **Step 2: Register new message handlers and add bridge callbacks in EditorView.swift**

In `PortyMcFolio/Views/EditorView.swift`, in the `makeNSView` function, add the new message handler registrations after the existing ones:

```swift
        ucc.add(context.coordinator.bridge, name: "requestLinkInput")
        ucc.add(context.coordinator.bridge, name: "requestFilePicker")
        ucc.add(context.coordinator.bridge, name: "openURL")
        ucc.add(context.coordinator.bridge, name: "openFile")
```

- [ ] **Step 3: Add bridge handler closures in Coordinator init**

In the Coordinator's `init`, after the `bridge.onRequestMediaPicker` closure, add:

```swift
            bridge.onRequestLinkInput = { [weak self] in
                guard let self, let webView = self.webView else { return }
                DispatchQueue.main.async {
                    self.showLinkInputDialog(webView: webView)
                }
            }

            bridge.onRequestFilePicker = { [weak self] in
                guard let self, let webView = self.webView else { return }
                let projectFolder = self.readmeURL.deletingLastPathComponent()
                DispatchQueue.main.async {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.directoryURL = projectFolder
                    panel.message = "Select a file to reference"
                    panel.prompt = "Insert"
                    if panel.runModal() == .OK, let url = panel.url {
                        self.insertFileReference(url: url)
                    }
                }
            }

            bridge.onOpenURL = { urlString in
                if let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            }

            bridge.onOpenFile = { [weak self] path in
                guard let self else { return }
                let projectFolder = self.readmeURL.deletingLastPathComponent()
                let fileURL = projectFolder.appendingPathComponent(path)
                NSWorkspace.shared.open(fileURL)
            }
```

- [ ] **Step 4: Add the helper methods to Coordinator**

Add these methods to the Coordinator class, after the `insertMediaFile` method:

```swift
        func insertFileReference(url: URL) {
            guard let webView else { return }
            let projectFolder = readmeURL.deletingLastPathComponent()
            let projectPath = projectFolder.standardizedFileURL.path
            let filePath = url.standardizedFileURL.path

            let filename: String
            if filePath.hasPrefix(projectPath + "/") {
                filename = String(filePath.dropFirst(projectPath.count + 1))
            } else {
                let destURL = projectFolder.appendingPathComponent(url.lastPathComponent)
                if !FileManager.default.fileExists(atPath: destURL.path) {
                    try? FileManager.default.copyItem(at: url, to: destURL)
                }
                filename = url.lastPathComponent
            }

            let title = url.deletingPathExtension().lastPathComponent
            evaluateJS(webView: webView, fn: "insertFileCard", args: [filename, title])
        }

        func showLinkInputDialog(webView: WKWebView) {
            let alert = NSAlert()
            alert.messageText = "Insert Link"
            alert.informativeText = "Enter a URL:"
            alert.addButton(withTitle: "Insert")
            alert.addButton(withTitle: "Cancel")

            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            input.placeholderString = "https://example.com"
            alert.accessoryView = input
            alert.window.initialFirstResponder = input

            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let urlString = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !urlString.isEmpty else { return }

            let url = urlString.hasPrefix("http") ? urlString : "https://\(urlString)"
            fetchLinkMetadata(url: url, webView: webView)
        }

        func fetchLinkMetadata(url: String, webView: WKWebView) {
            guard let linkURL = URL(string: url) else {
                evaluateJS(webView: webView, fn: "insertLinkCard", args: [url, "", ""])
                return
            }

            let provider = LPMetadataProvider()
            provider.timeout = 5

            provider.startFetchingMetadata(for: linkURL) { [weak self] metadata, error in
                DispatchQueue.main.async {
                    let title = metadata?.title ?? ""
                    let description = metadata?.value(forKey: "summary") as? String ?? ""
                    self?.evaluateJS(webView: webView, fn: "insertLinkCard", args: [url, title, description])
                }
            }
        }

        private func evaluateJS(webView: WKWebView, fn: String, args: [String]) {
            guard let jsonData = try? JSONSerialization.data(withJSONObject: args),
                  let jsonArray = String(data: jsonData, encoding: .utf8) else { return }
            // Convert ["a","b","c"] to "a","b","c" for function call
            let argsString = String(jsonArray.dropFirst().dropLast())
            webView.evaluateJavaScript("window.PortyEditor.\(fn)(\(argsString))")
        }
```

- [ ] **Step 5: Add LinkPresentation import**

At the top of `PortyMcFolio/Views/EditorView.swift`, add:

```swift
import LinkPresentation
```

- [ ] **Step 6: Commit**

```bash
git add PortyMcFolio/Editor/EditorBridge.swift PortyMcFolio/Views/EditorView.swift
git commit -m "feat: add Swift bridge for link input, file picker, metadata fetching"
```

---

### Task 6: Smart file routing — media vs non-media on drop

**Files:**
- Modify: `PortyMcFolio/Views/EditorView.swift`

- [ ] **Step 1: Update DropTargetWebView to accept all files and route by type**

In `DropTargetWebView`, rename `mediaExtensions` and add the routing logic. Replace the entire `DropTargetWebView` class with:

```swift
final class DropTargetWebView: WKWebView {
    weak var coordinator: EditorView.Coordinator?

    private static let mediaExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "svg", "webp", "avif",
        "mp4", "webm", "ogg", "mov",
        "mp3", "wav", "aac", "m4a",
    ]

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard hasFiles(sender) else { return [] }
        return .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
            return false
        }

        for url in urls {
            let ext = url.pathExtension.lowercased()
            if Self.mediaExtensions.contains(ext) {
                coordinator?.insertMediaFile(url: url)
            } else {
                coordinator?.insertFileReference(url: url)
            }
        }

        return true
    }

    private func hasFiles(_ info: NSDraggingInfo) -> Bool {
        guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
            return false
        }
        return !urls.isEmpty
    }
}
```

Key changes:
- `draggingEntered` accepts ANY file (not just media)
- `performDragOperation` routes: media extensions → `insertMediaFile`, everything else → `insertFileReference`
- `hasFiles` checks for any file, not just media
- Removed `pdf` from `mediaExtensions` (PDFs are now file cards)

- [ ] **Step 2: Commit**

```bash
git add PortyMcFolio/Views/EditorView.swift
git commit -m "feat: smart file routing — media embeds vs file cards on drop"
```

---

### Task 7: Build, verify, and commit

- [ ] **Step 1: Build the editor bundle**

Run: `cd <repo>/Editor && npm run build`
Expected: Build succeeds, no errors

- [ ] **Step 2: Build Xcode project**

Run: `xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio build 2>&1 | grep -E "error:|BUILD"`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Verify in app**

1. Type `/link` — should show Insert Link in slash menu
2. Select it — URL input dialog appears
3. Enter a URL — card renders with fetched title/description
4. Type `/file` — shows Insert File
5. Select it — file picker opens
6. Pick a PDF — file card renders with icon and filename
7. Drag a PDF from Finder — file card inserted
8. Drag an image from Finder — media embed inserted (existing behavior)
9. Click a link card — opens URL in browser
10. Click a file card — opens file in default app

- [ ] **Step 4: Final commit**

```bash
git add PortyMcFolio/Editor/Resources/editor.bundle.js
git commit -m "feat: rich embeds — link cards and file references with cards, drag & drop, metadata"
```
