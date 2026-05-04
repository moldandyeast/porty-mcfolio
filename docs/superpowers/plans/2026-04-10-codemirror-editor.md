# CodeMirror 6 Editor Rewrite — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Tiptap WYSIWYG editor with a CodeMirror 6 source-with-styling markdown editor where syntax is always visible but beautifully rendered.

**Architecture:** CodeMirror 6 with `@codemirror/lang-markdown` provides the editing surface. Custom `ViewPlugin` decorations handle all visual styling — headings get large fonts, bold gets weight, syntax characters get muted colors. The full markdown file (including frontmatter) is the editor content. Swift integration stays the same: WKWebView + message handlers + `portymcfolio://` scheme for media.

**Tech Stack:** CodeMirror 6, @codemirror/lang-markdown, @lezer/markdown, Vite IIFE build, Swift/WKWebView

---

## File Map

### New files (Editor/src/)
- `Editor/src/index.js` — Entry point, creates editor, exposes `window.PortyEditor` API
- `Editor/src/theme.js` — Light/dark EditorView themes + CSS custom properties
- `Editor/src/keybindings.js` — Cmd+B/I/E/Shift+S, heading shortcuts, Tab indent
- `Editor/src/markdown/decorations.js` — ViewPlugin: headings, inline format, blockquotes, lists, links, HR
- `Editor/src/markdown/frontmatter.js` — ViewPlugin: frontmatter block detection + styling
- `Editor/src/markdown/media.js` — ViewPlugin: `![[file]]` inline preview widgets
- `Editor/src/commands.js` — Slash command menu ViewPlugin
- `Editor/src/bridge.js` — Swift postMessage bridge (contentChanged, editorReady, requestMediaPicker)
- `Editor/src/footer.js` — Footer bar ViewPlugin (word count, char count, dates)

### Modified files
- `Editor/package.json` — Replace Tiptap deps with CodeMirror deps
- `Editor/vite.config.js` — Update `define` for process.env, keep IIFE output
- `PortyMcFolio/Editor/Resources/editor.html` — Simplified HTML shell
- `PortyMcFolio/Editor/Resources/editor.css` — Full rewrite for CodeMirror theme
- `PortyMcFolio/Views/EditorView.swift` — Remove frontmatter stripping, send full file content
- `PortyMcFolio/Editor/EditorBridge.swift` — Remove `loadFrontmatter`, simplify `loadMarkdown`

### Deleted files/directories
- `Editor/src/components/bubble-menu.js`
- `Editor/src/extensions/wikilink.js`
- `Editor/src/extensions/media-embed.js`
- `Editor/src/extensions/slash-commands.js`
- `Editor/src/markdown-serializer.js`

---

## Task 1: Swap Dependencies and Scaffold

**Files:**
- Modify: `Editor/package.json`
- Modify: `Editor/vite.config.js`
- Delete: `Editor/src/components/`, `Editor/src/extensions/`, `Editor/src/markdown-serializer.js`

- [ ] **Step 1: Remove old source files**

```bash
cd <repo>
rm -rf Editor/src/components Editor/src/extensions Editor/src/markdown-serializer.js
```

- [ ] **Step 2: Replace package.json**

Replace the contents of `Editor/package.json` with:

```json
{
  "name": "portymcfolio-editor",
  "version": "2.0.0",
  "private": true,
  "scripts": {
    "build": "vite build",
    "dev": "vite"
  },
  "dependencies": {
    "codemirror": "^6.0.0",
    "@codemirror/lang-markdown": "^6.0.0",
    "@codemirror/language-data": "^6.0.0",
    "@codemirror/search": "^6.0.0",
    "@lezer/markdown": "^1.0.0"
  },
  "devDependencies": {
    "vite": "^5.0.0"
  }
}
```

- [ ] **Step 3: Update vite.config.js**

Replace `Editor/vite.config.js` with:

```javascript
import { defineConfig } from 'vite'
import { resolve } from 'path'

export default defineConfig({
  define: {
    'process.env.NODE_ENV': JSON.stringify('production'),
  },
  build: {
    lib: {
      entry: resolve(__dirname, 'src/index.js'),
      name: 'PortyMcFolioEditor',
      fileName: () => 'editor.bundle.js',
      formats: ['iife'],
    },
    outDir: resolve(__dirname, '../PortyMcFolio/Editor/Resources'),
    emptyOutDir: false,
    rollupOptions: {
      output: {
        entryFileNames: 'editor.bundle.js',
      },
    },
  },
})
```

- [ ] **Step 4: Create directory structure**

```bash
mkdir -p Editor/src/markdown
```

- [ ] **Step 5: Install dependencies**

```bash
cd <repo>/Editor && npm install
```

Expected: `node_modules/codemirror/`, `node_modules/@codemirror/lang-markdown/` etc. exist.

- [ ] **Step 6: Commit**

```bash
git add -A Editor/
git commit -m "chore: swap Tiptap deps for CodeMirror 6, scaffold new structure"
```

---

## Task 2: Minimal Editor + Swift Bridge

Build the bare minimum: a CodeMirror editor that loads markdown, sends changes to Swift, and signals readiness. No styling yet — just a working text editor in WKWebView.

**Files:**
- Create: `Editor/src/index.js`
- Create: `Editor/src/bridge.js`
- Modify: `PortyMcFolio/Editor/Resources/editor.html`
- Modify: `PortyMcFolio/Views/EditorView.swift`
- Modify: `PortyMcFolio/Editor/EditorBridge.swift`

- [ ] **Step 1: Create bridge.js**

Create `Editor/src/bridge.js`:

```javascript
/**
 * Swift WKWebView message bridge.
 * Posts messages to Swift via webkit.messageHandlers.
 */

const DEBOUNCE_MS = 1500
let debounceTimer = null

export function postEditorReady() {
  try {
    window.webkit?.messageHandlers?.editorReady?.postMessage('ready')
  } catch (e) {
    // Not in WKWebView
  }
}

export function postContentChanged(content) {
  clearTimeout(debounceTimer)
  debounceTimer = setTimeout(() => {
    try {
      window.webkit?.messageHandlers?.contentChanged?.postMessage(content)
    } catch (e) {
      // Not in WKWebView
    }
  }, DEBOUNCE_MS)
}

export function postRequestMediaPicker() {
  try {
    window.webkit?.messageHandlers?.requestMediaPicker?.postMessage(null)
  } catch (e) {
    // Not in WKWebView
  }
}
```

- [ ] **Step 2: Create index.js**

Create `Editor/src/index.js`:

```javascript
import { EditorView, keymap, placeholder } from '@codemirror/view'
import { EditorState } from '@codemirror/state'
import { markdown, markdownLanguage } from '@codemirror/lang-markdown'
import { defaultKeymap, history, historyKeymap } from '@codemirror/commands'
import { search, searchKeymap } from '@codemirror/search'
import { postEditorReady, postContentChanged } from './bridge.js'

let view = null

function initEditor() {
  if (view) return

  const el = document.getElementById('editor')
  if (!el) {
    console.error('PortyEditor: #editor element not found')
    return
  }

  const updateListener = EditorView.updateListener.of((update) => {
    if (update.docChanged) {
      postContentChanged(update.state.doc.toString())
    }
  })

  view = new EditorView({
    state: EditorState.create({
      doc: '',
      extensions: [
        markdown({ base: markdownLanguage }),
        history(),
        search(),
        keymap.of([
          ...defaultKeymap,
          ...historyKeymap,
          ...searchKeymap,
        ]),
        placeholder('Start writing, or type / for commands…'),
        updateListener,
        EditorView.lineWrapping,
      ],
    }),
    parent: el,
  })

  postEditorReady()
}

function setMarkdown(content) {
  if (!view) return
  view.dispatch({
    changes: {
      from: 0,
      to: view.state.doc.length,
      insert: content || '',
    },
  })
}

function getMarkdown() {
  if (!view) return ''
  return view.state.doc.toString()
}

function focus() {
  view?.focus()
}

function insertAtCursor(text) {
  if (!view) return
  const pos = view.state.selection.main.head
  view.dispatch({
    changes: { from: pos, to: pos, insert: text },
    selection: { anchor: pos + text.length },
  })
  view.focus()
}

function insertMediaEmbed(filename) {
  insertAtCursor(`![[${filename}]]`)
}

const PortyEditor = { init: initEditor, setMarkdown, getMarkdown, focus, insertMediaEmbed }
window.PortyEditor = PortyEditor

try {
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initEditor)
  } else {
    initEditor()
  }
} catch (e) {
  console.error('PortyEditor init error:', e)
}

export default PortyEditor
```

- [ ] **Step 3: Simplify editor.html**

Replace `PortyMcFolio/Editor/Resources/editor.html` with:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>PortyMcFolio Editor</title>
  <link rel="stylesheet" href="editor.css" />
</head>
<body>
  <div id="editor"></div>
  <div id="footer-bar"></div>
  <script src="editor.bundle.js"></script>
</body>
</html>
```

- [ ] **Step 4: Simplify EditorView.swift — remove frontmatter stripping**

Rewrite `PortyMcFolio/Views/EditorView.swift`. Key change: the full file content (including frontmatter) goes to the editor. No more `splitFrontmatter` or `storedFrontmatter`.

```swift
import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct EditorView: NSViewRepresentable {
    let readmeURL: URL
    var onSave: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(readmeURL: readmeURL, onSave: onSave)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let ucc = configuration.userContentController
        ucc.add(context.coordinator.bridge, name: "contentChanged")
        ucc.add(context.coordinator.bridge, name: "requestMediaPicker")
        ucc.add(context.coordinator.bridge, name: "editorReady")
        configuration.setURLSchemeHandler(context.coordinator.mediaHandler, forURLScheme: "portymcfolio")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        if let htmlURL = Bundle.main.url(forResource: "editor", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: Bundle.main.bundleURL)
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.onSave = onSave
        if context.coordinator.readmeURL != readmeURL {
            context.coordinator.readmeURL = readmeURL
            context.coordinator.mediaHandler.projectFolderURL = readmeURL.deletingLastPathComponent()
            if context.coordinator.editorReady {
                context.coordinator.loadContent()
            } else {
                context.coordinator.pendingLoad = true
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let bridge: EditorBridge
        let mediaHandler: MediaSchemeHandler
        var readmeURL: URL
        var onSave: ((String) -> Void)?
        weak var webView: WKWebView?
        var editorReady = false
        var pendingLoad = false

        init(readmeURL: URL, onSave: ((String) -> Void)?) {
            self.bridge = EditorBridge()
            self.mediaHandler = MediaSchemeHandler()
            self.readmeURL = readmeURL
            self.onSave = onSave
            super.init()
            mediaHandler.projectFolderURL = readmeURL.deletingLastPathComponent()

            bridge.onEditorReady = { [weak self] in
                guard let self else { return }
                self.editorReady = true
                self.loadContent()
            }

            bridge.onContentChanged = { [weak self] content in
                guard let self else { return }
                do {
                    try content.write(to: self.readmeURL, atomically: true, encoding: .utf8)
                    self.onSave?(content)
                } catch {
                    print("[EditorView] Save failed: \(error)")
                }
            }

            bridge.onRequestMediaPicker = { [weak self] in
                guard let self, let webView = self.webView else { return }
                let projectFolder = self.readmeURL.deletingLastPathComponent()
                DispatchQueue.main.async {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.directoryURL = projectFolder
                    panel.allowedContentTypes = [.image, .movie, .mpeg4Movie, .quickTimeMovie, .audio]
                    panel.message = "Select a media file to insert"
                    panel.prompt = "Insert"
                    if panel.runModal() == .OK, let url = panel.url {
                        let filename: String
                        if url.deletingLastPathComponent().path == projectFolder.path {
                            filename = url.lastPathComponent
                        } else {
                            let destURL = projectFolder.appendingPathComponent(url.lastPathComponent)
                            try? FileManager.default.copyItem(at: url, to: destURL)
                            filename = url.lastPathComponent
                        }
                        let escaped = filename.replacingOccurrences(of: "'", with: "\\'")
                        webView.evaluateJavaScript("window.PortyEditor.insertMediaEmbed('\(escaped)')")
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Wait for editorReady from JS
        }

        func loadContent() {
            guard let webView else { return }
            pendingLoad = false
            let content: String
            do {
                content = try String(contentsOf: readmeURL, encoding: .utf8)
            } catch {
                content = ""
            }
            bridge.loadMarkdown(in: webView, content: content)
        }
    }
}
```

- [ ] **Step 5: Simplify EditorBridge.swift**

Replace `PortyMcFolio/Editor/EditorBridge.swift` with:

```swift
import Foundation
import WebKit

final class EditorBridge: NSObject, WKScriptMessageHandler {
    var onContentChanged: ((String) -> Void)?
    var onRequestMediaPicker: (() -> Void)?
    var onEditorReady: (() -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "contentChanged":
            if let content = message.body as? String {
                onContentChanged?(content)
            }
        case "requestMediaPicker":
            onRequestMediaPicker?()
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

- [ ] **Step 6: Create minimal editor.css**

Replace `PortyMcFolio/Editor/Resources/editor.css` with a minimal stylesheet so the editor is visible:

```css
*, *::before, *::after { box-sizing: border-box; }

html, body {
  margin: 0;
  padding: 0;
  height: 100%;
  background: #f5f5f7;
  font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
}

#editor {
  max-width: 720px;
  margin: 0 auto;
  padding: 24px 32px;
  min-height: calc(100vh - 32px);
}

.cm-editor {
  outline: none;
  font-size: 15px;
  line-height: 1.7;
}

.cm-editor .cm-content {
  font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
  caret-color: #1d1d1f;
}

.cm-editor .cm-line {
  padding: 0;
}

.cm-editor .cm-scroller {
  overflow-x: hidden;
}

.cm-editor .cm-gutters {
  display: none;
}

#footer-bar {
  display: none;
}
```

- [ ] **Step 7: Build and verify**

```bash
cd <repo>/Editor && npm run build
```

Expected: `editor.bundle.js` builds without errors.

```bash
cd <repo> && xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Test in browser preview**

Serve the resources directory and verify the editor loads, accepts text, and the `window.PortyEditor` API works:

```javascript
// In browser console or preview:
window.PortyEditor.setMarkdown('# Test\n\nHello **world**')
window.PortyEditor.getMarkdown() // Should return '# Test\n\nHello **world**'
```

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: minimal CodeMirror 6 editor with Swift bridge"
```

---

## Task 3: Theme — Light and Dark

**Files:**
- Create: `Editor/src/theme.js`
- Modify: `Editor/src/index.js` (import theme)
- Modify: `PortyMcFolio/Editor/Resources/editor.css` (CSS variables, dark mode)

- [ ] **Step 1: Create theme.js**

Create `Editor/src/theme.js`:

```javascript
import { EditorView } from '@codemirror/view'

export const lightTheme = EditorView.theme({
  '&': {
    color: '#1d1d1f',
    backgroundColor: 'transparent',
  },
  '.cm-content': {
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif",
    fontSize: '15px',
    lineHeight: '1.7',
    caretColor: '#1d1d1f',
    padding: '0',
  },
  '.cm-cursor': {
    borderLeftColor: '#1d1d1f',
    borderLeftWidth: '1.5px',
  },
  '.cm-selectionBackground': {
    backgroundColor: 'rgba(88, 86, 214, 0.15) !important',
  },
  '&.cm-focused .cm-selectionBackground': {
    backgroundColor: 'rgba(88, 86, 214, 0.2) !important',
  },
  '.cm-activeLine': {
    backgroundColor: 'rgba(0, 0, 0, 0.02)',
  },
  '.cm-gutters': {
    display: 'none',
  },
  '.cm-line': {
    padding: '0',
  },
  '.cm-scroller': {
    overflowX: 'hidden',
  },
  // Placeholder
  '.cm-placeholder': {
    color: '#aeaeb2',
    fontStyle: 'normal',
  },
  // Search panel
  '.cm-panels': {
    backgroundColor: '#f5f5f7',
    borderBottom: '1px solid #d1d1d6',
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif",
  },
  '.cm-searchMatch': {
    backgroundColor: 'rgba(255, 200, 0, 0.3)',
  },
  '.cm-searchMatch-selected': {
    backgroundColor: 'rgba(255, 150, 0, 0.4)',
  },
})

export const darkTheme = EditorView.theme({
  '&': {
    color: '#f5f5f7',
    backgroundColor: 'transparent',
  },
  '.cm-content': {
    fontFamily: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif",
    fontSize: '15px',
    lineHeight: '1.7',
    caretColor: '#f5f5f7',
    padding: '0',
  },
  '.cm-cursor': {
    borderLeftColor: '#f5f5f7',
    borderLeftWidth: '1.5px',
  },
  '.cm-selectionBackground': {
    backgroundColor: 'rgba(124, 122, 255, 0.2) !important',
  },
  '&.cm-focused .cm-selectionBackground': {
    backgroundColor: 'rgba(124, 122, 255, 0.3) !important',
  },
  '.cm-activeLine': {
    backgroundColor: 'rgba(255, 255, 255, 0.03)',
  },
  '.cm-gutters': {
    display: 'none',
  },
  '.cm-line': {
    padding: '0',
  },
  '.cm-scroller': {
    overflowX: 'hidden',
  },
  '.cm-placeholder': {
    color: '#636366',
    fontStyle: 'normal',
  },
  '.cm-panels': {
    backgroundColor: '#1c1c1e',
    borderBottom: '1px solid #48484a',
  },
  '.cm-searchMatch': {
    backgroundColor: 'rgba(255, 200, 0, 0.2)',
  },
  '.cm-searchMatch-selected': {
    backgroundColor: 'rgba(255, 150, 0, 0.3)',
  },
}, { dark: true })

/**
 * Returns the appropriate theme based on system preference.
 */
export function getSystemTheme() {
  if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
    return darkTheme
  }
  return lightTheme
}
```

- [ ] **Step 2: Import theme in index.js**

In `Editor/src/index.js`, add the theme import and use it. Replace the `extensions` array in `EditorState.create`:

Add import at top:
```javascript
import { getSystemTheme } from './theme.js'
```

In the extensions array, add `getSystemTheme()` before `updateListener`.

- [ ] **Step 3: Update editor.css**

Replace `PortyMcFolio/Editor/Resources/editor.css` with:

```css
:root {
  --text: #1d1d1f;
  --text-muted: #86868b;
  --text-faint: #aeaeb2;
  --syntax: #b0b0b4;
  --bg: #f5f5f7;
  --bg-primary: #ffffff;
  --bg-secondary: #f2f2f7;
  --bg-tertiary: #ebebef;
  --accent: #5856d6;
  --accent-muted: #ede9fe;
  --link: #007aff;
  --code-bg: #f2f2f7;
  --code-text: #c41a68;
  --border: #d1d1d6;
  --border-light: #e5e5ea;
  --radius: 6px;
}

@media (prefers-color-scheme: dark) {
  :root {
    --text: #f5f5f7;
    --text-muted: #98989d;
    --text-faint: #636366;
    --syntax: #636366;
    --bg: #1c1c1e;
    --bg-primary: #2c2c2e;
    --bg-secondary: #1c1c1e;
    --bg-tertiary: #3a3a3c;
    --accent: #7c7aff;
    --accent-muted: #2d2b6b;
    --link: #64b5f6;
    --code-bg: #1c1c1e;
    --code-text: #ff6b8a;
    --border: #48484a;
    --border-light: #38383a;
  }
}

*, *::before, *::after { box-sizing: border-box; }

html, body {
  margin: 0;
  padding: 0;
  height: 100%;
  background: var(--bg);
  -webkit-font-smoothing: antialiased;
}

#editor {
  max-width: 720px;
  margin: 0 auto;
  padding: 24px 32px 120px;
  min-height: calc(100vh - 40px);
}

/* ── Footer Bar ──────────────────────────────────────── */

#footer-bar {
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  height: 28px;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 16px;
  padding: 0 16px;
  font-family: -apple-system, BlinkMacSystemFont, sans-serif;
  font-size: 11px;
  color: var(--text-faint);
  background: var(--bg);
  border-top: 1px solid var(--border-light);
}

.footer-item {
  display: inline-flex;
  align-items: center;
  gap: 4px;
}

/* ── Markdown Decoration Classes ─────────────────────── */
/* These classes are applied by decorations.js ViewPlugin */

.cm-md-syntax {
  color: var(--syntax);
}

.cm-md-h1 { font-size: 1.875em; font-weight: 700; line-height: 1.3; }
.cm-md-h2 { font-size: 1.4em; font-weight: 650; line-height: 1.35; }
.cm-md-h3 { font-size: 1.15em; font-weight: 600; line-height: 1.4; }

.cm-md-bold { font-weight: 650; }
.cm-md-italic { font-style: italic; }
.cm-md-strike { text-decoration: line-through; color: var(--text-muted); }

.cm-md-code {
  font-family: 'SF Mono', 'Fira Code', Menlo, monospace;
  font-size: 0.85em;
  background: var(--code-bg);
  border-radius: 3px;
  padding: 0.1em 0;
}

.cm-md-codeblock-line {
  font-family: 'SF Mono', 'Fira Code', Menlo, monospace;
  font-size: 0.85em;
  background: var(--code-bg);
  padding: 0 8px;
}

.cm-md-codeblock-first {
  border-top-left-radius: var(--radius);
  border-top-right-radius: var(--radius);
  padding-top: 8px;
}

.cm-md-codeblock-last {
  border-bottom-left-radius: var(--radius);
  border-bottom-right-radius: var(--radius);
  padding-bottom: 8px;
}

.cm-md-blockquote {
  border-left: 3px solid var(--accent);
  padding-left: 12px;
  color: var(--text-muted);
}

.cm-md-hr {
  color: var(--syntax);
}

.cm-md-link-text { color: var(--link); }
.cm-md-link-url { color: var(--text-faint); font-size: 0.9em; }

.cm-md-list-marker { color: var(--syntax); }

/* ── Frontmatter ─────────────────────────────────────── */

.cm-md-frontmatter-line {
  background: var(--bg-secondary);
  padding: 0 8px;
}

.cm-md-frontmatter-first {
  border-top-left-radius: var(--radius);
  border-top-right-radius: var(--radius);
  padding-top: 6px;
}

.cm-md-frontmatter-last {
  border-bottom-left-radius: var(--radius);
  border-bottom-right-radius: var(--radius);
  padding-bottom: 6px;
  margin-bottom: 8px;
}

.cm-md-frontmatter-key { color: var(--text-faint); }
.cm-md-frontmatter-value { color: var(--text-muted); }
.cm-md-frontmatter-delimiter { color: var(--border); }

/* ── Media Preview Widget ────────────────────────────── */

.cm-media-preview {
  display: block;
  max-width: 100%;
  margin: 4px 0 8px;
}

.cm-media-preview img {
  max-width: 100%;
  max-height: 400px;
  border-radius: var(--radius);
  object-fit: contain;
}

.cm-media-preview video {
  max-width: 100%;
  max-height: 400px;
  border-radius: var(--radius);
}

.cm-media-preview .media-badge {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 6px 12px;
  background: var(--bg-secondary);
  border: 1px solid var(--border-light);
  border-radius: var(--radius);
  font-size: 12px;
  color: var(--text-muted);
  font-family: 'SF Mono', Menlo, monospace;
}

/* ── Slash Command Menu ──────────────────────────────── */

.slash-menu {
  position: absolute;
  z-index: 100;
  background: var(--bg-primary);
  border: 1px solid var(--border);
  border-radius: 10px;
  box-shadow: 0 4px 16px rgba(0,0,0,0.1);
  min-width: 240px;
  max-height: 320px;
  overflow-y: auto;
  padding: 4px;
  font-family: -apple-system, BlinkMacSystemFont, sans-serif;
  animation: menuFadeIn 0.1s ease-out;
}

@media (prefers-color-scheme: dark) {
  .slash-menu {
    box-shadow: 0 4px 16px rgba(0,0,0,0.3);
  }
}

.slash-menu-item {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 7px 10px;
  border-radius: 6px;
  cursor: pointer;
  transition: background 0.08s;
}

.slash-menu-item:hover,
.slash-menu-item.is-selected {
  background: var(--bg-tertiary);
}

.slash-menu-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 30px;
  height: 30px;
  border-radius: 6px;
  background: var(--bg-secondary);
  font-size: 13px;
  flex-shrink: 0;
  color: var(--text-muted);
}

.slash-menu-text {
  display: flex;
  flex-direction: column;
  gap: 1px;
}

.slash-menu-title {
  font-size: 13px;
  font-weight: 500;
  color: var(--text);
}

.slash-menu-description {
  font-size: 11px;
  color: var(--text-faint);
}

/* ── Search Panel Override ───────────────────────────── */

.cm-panel.cm-search {
  background: var(--bg-primary);
  border-bottom: 1px solid var(--border-light);
  padding: 8px 12px;
  font-size: 13px;
}

.cm-panel.cm-search input {
  background: var(--bg-secondary);
  border: 1px solid var(--border);
  border-radius: 4px;
  padding: 4px 8px;
  color: var(--text);
  font-size: 13px;
  outline: none;
}

.cm-panel.cm-search input:focus {
  border-color: var(--accent);
}

.cm-panel.cm-search button {
  background: var(--bg-tertiary);
  border: 1px solid var(--border);
  border-radius: 4px;
  padding: 4px 8px;
  color: var(--text);
  font-size: 12px;
  cursor: pointer;
}

.cm-panel.cm-search button:hover {
  background: var(--border-light);
}

@keyframes menuFadeIn {
  from { opacity: 0; transform: translateY(4px); }
  to { opacity: 1; transform: translateY(0); }
}
```

- [ ] **Step 4: Build and verify themes**

```bash
cd <repo>/Editor && npm run build
```

Verify in browser preview: editor should have clean styling, cursor, selections. Toggle system dark mode to confirm both themes work.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add light/dark themes and editor CSS foundation"
```

---

## Task 4: Markdown Decorations — Headings, Inline Formatting, Blocks

The core visual experience. A `ViewPlugin` that walks the syntax tree and applies CSS classes to heading lines, bold/italic ranges, code blocks, blockquotes, lists, and horizontal rules.

**Files:**
- Create: `Editor/src/markdown/decorations.js`
- Modify: `Editor/src/index.js` (import and add to extensions)

- [ ] **Step 1: Create decorations.js**

Create `Editor/src/markdown/decorations.js`:

```javascript
import { ViewPlugin, Decoration } from '@codemirror/view'
import { syntaxTree } from '@codemirror/language'

const syntaxMark = Decoration.mark({ class: 'cm-md-syntax' })
const boldMark = Decoration.mark({ class: 'cm-md-bold' })
const italicMark = Decoration.mark({ class: 'cm-md-italic' })
const strikeMark = Decoration.mark({ class: 'cm-md-strike' })
const inlineCodeMark = Decoration.mark({ class: 'cm-md-code' })
const linkTextMark = Decoration.mark({ class: 'cm-md-link-text' })
const linkUrlMark = Decoration.mark({ class: 'cm-md-link-url' })
const listMarkerMark = Decoration.mark({ class: 'cm-md-list-marker' })

const headingLine = {
  1: Decoration.line({ class: 'cm-md-h1' }),
  2: Decoration.line({ class: 'cm-md-h2' }),
  3: Decoration.line({ class: 'cm-md-h3' }),
}

const blockquoteLine = Decoration.line({ class: 'cm-md-blockquote' })
const hrLine = Decoration.line({ class: 'cm-md-hr' })

function buildDecorations(view) {
  const decorations = []
  const doc = view.state.doc

  for (const { from, to } of view.visibleRanges) {
    syntaxTree(view.state).iterate({
      from, to,
      enter(node) {
        const type = node.type.name

        // Headings: ATXHeading1, ATXHeading2, ATXHeading3
        if (type.startsWith('ATXHeading')) {
          const level = parseInt(type.replace('ATXHeading', ''), 10)
          if (level >= 1 && level <= 3) {
            const line = doc.lineAt(node.from)
            decorations.push(headingLine[level].range(line.from))
          }
          // Mute the # marks
          const headingMark = node.node.getChild('HeaderMark')
          if (headingMark) {
            decorations.push(syntaxMark.range(headingMark.from, headingMark.to))
          }
        }

        // Bold: StrongEmphasis
        if (type === 'StrongEmphasis') {
          // Mark inner content as bold
          decorations.push(boldMark.range(node.from, node.to))
          // Mute the ** markers (first 2 and last 2 chars)
          decorations.push(syntaxMark.range(node.from, node.from + 2))
          decorations.push(syntaxMark.range(node.to - 2, node.to))
        }

        // Italic: Emphasis
        if (type === 'Emphasis') {
          decorations.push(italicMark.range(node.from, node.to))
          decorations.push(syntaxMark.range(node.from, node.from + 1))
          decorations.push(syntaxMark.range(node.to - 1, node.to))
        }

        // Strikethrough: Strikethrough
        if (type === 'Strikethrough') {
          decorations.push(strikeMark.range(node.from, node.to))
          decorations.push(syntaxMark.range(node.from, node.from + 2))
          decorations.push(syntaxMark.range(node.to - 2, node.to))
        }

        // Inline code: InlineCode
        if (type === 'InlineCode') {
          decorations.push(inlineCodeMark.range(node.from, node.to))
          // Mute backticks
          decorations.push(syntaxMark.range(node.from, node.from + 1))
          decorations.push(syntaxMark.range(node.to - 1, node.to))
        }

        // Code blocks: FencedCode
        if (type === 'FencedCode') {
          const startLine = doc.lineAt(node.from)
          const endLine = doc.lineAt(node.to)
          for (let i = startLine.number; i <= endLine.number; i++) {
            const line = doc.line(i)
            let cls = 'cm-md-codeblock-line'
            if (i === startLine.number) cls += ' cm-md-codeblock-first'
            if (i === endLine.number) cls += ' cm-md-codeblock-last'
            decorations.push(Decoration.line({ class: cls }).range(line.from))
          }
          // Mute the ``` markers
          const codeInfo = node.node.getChild('CodeInfo')
          const codeMark1 = node.node.getChild('CodeMark')
          if (codeMark1) {
            decorations.push(syntaxMark.range(codeMark1.from, codeMark1.to))
          }
          // Mute closing ``` — it's the last CodeMark
          const children = []
          for (let c = node.node.firstChild; c; c = c.nextSibling) {
            if (c.type.name === 'CodeMark') children.push(c)
          }
          if (children.length > 1) {
            const last = children[children.length - 1]
            decorations.push(syntaxMark.range(last.from, last.to))
          }
          if (codeInfo) {
            decorations.push(syntaxMark.range(codeInfo.from, codeInfo.to))
          }
        }

        // Blockquote: Blockquote
        if (type === 'Blockquote') {
          const startLine = doc.lineAt(node.from)
          const endLine = doc.lineAt(node.to)
          for (let i = startLine.number; i <= endLine.number; i++) {
            const line = doc.line(i)
            decorations.push(blockquoteLine.range(line.from))
          }
          // Mute > markers
          for (let c = node.node.firstChild; c; c = c.nextSibling) {
            if (c.type.name === 'QuoteMark') {
              decorations.push(syntaxMark.range(c.from, c.to))
            }
          }
        }

        // Horizontal rule: HorizontalRule
        if (type === 'HorizontalRule') {
          const line = doc.lineAt(node.from)
          decorations.push(hrLine.range(line.from))
          decorations.push(syntaxMark.range(node.from, node.to))
        }

        // Links: Link
        if (type === 'Link') {
          // Find URL and link text children
          const urlNode = node.node.getChild('URL')
          // Mark brackets/parens as syntax
          for (let c = node.node.firstChild; c; c = c.nextSibling) {
            if (c.type.name === 'LinkMark') {
              decorations.push(syntaxMark.range(c.from, c.to))
            }
          }
          if (urlNode) {
            decorations.push(linkUrlMark.range(urlNode.from, urlNode.to))
          }
          // Find the link text (between [ and ])
          const textStart = node.from + 1
          const textEnd = node.node.getChild('LinkMark', 1)?.from ?? node.to
          if (textStart < textEnd) {
            decorations.push(linkTextMark.range(textStart, textEnd))
          }
        }

        // List markers: ListMark
        if (type === 'ListMark') {
          decorations.push(listMarkerMark.range(node.from, node.to))
        }
      }
    })
  }

  // Sort decorations by from position (required by CodeMirror)
  decorations.sort((a, b) => a.from - b.from || a.startSide - b.startSide)
  return Decoration.set(decorations, true)
}

export const markdownDecorations = ViewPlugin.fromClass(
  class {
    constructor(view) {
      this.decorations = buildDecorations(view)
    }
    update(update) {
      if (update.docChanged || update.viewportChanged || update.selectionSet) {
        this.decorations = buildDecorations(update.view)
      }
    }
  },
  { decorations: (v) => v.decorations }
)
```

- [ ] **Step 2: Add decorations to index.js**

In `Editor/src/index.js`, add the import:

```javascript
import { markdownDecorations } from './markdown/decorations.js'
```

Add `markdownDecorations` to the extensions array, after `search()`.

- [ ] **Step 3: Build and test**

```bash
cd <repo>/Editor && npm run build
```

Test in browser preview with:
```javascript
window.PortyEditor.setMarkdown('# Big Heading\n\n## Medium Heading\n\n### Small Heading\n\nSome **bold** and *italic* and ~~struck~~ and `code` text.\n\n- list item\n- another\n\n> a blockquote\n\n---\n\n```js\nconsole.log("hi")\n```\n\n[Link text](https://example.com)')
```

Expected: headings are large, bold is bold, `##` and `**` are muted grey, code blocks have background, blockquotes have left border.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: markdown decorations — headings, inline formatting, code blocks, blockquotes, lists, links"
```

---

## Task 5: Frontmatter Decorations

**Files:**
- Create: `Editor/src/markdown/frontmatter.js`
- Modify: `Editor/src/index.js` (import and add to extensions)

- [ ] **Step 1: Create frontmatter.js**

Create `Editor/src/markdown/frontmatter.js`:

```javascript
import { ViewPlugin, Decoration } from '@codemirror/view'

const delimiterMark = Decoration.mark({ class: 'cm-md-frontmatter-delimiter cm-md-syntax' })
const keyMark = Decoration.mark({ class: 'cm-md-frontmatter-key' })
const valueMark = Decoration.mark({ class: 'cm-md-frontmatter-value' })

function fmLineDecoration(isFirst, isLast) {
  let cls = 'cm-md-frontmatter-line'
  if (isFirst) cls += ' cm-md-frontmatter-first'
  if (isLast) cls += ' cm-md-frontmatter-last'
  return Decoration.line({ class: cls })
}

function buildFrontmatterDecorations(view) {
  const decorations = []
  const doc = view.state.doc

  // Frontmatter must start at line 1 with ---
  const firstLine = doc.line(1)
  if (firstLine.text.trim() !== '---') return Decoration.set([])

  // Find closing ---
  let closingLine = -1
  const lineCount = doc.lines
  for (let i = 2; i <= lineCount; i++) {
    if (doc.line(i).text.trim() === '---') {
      closingLine = i
      break
    }
  }
  if (closingLine === -1) return Decoration.set([])

  // Decorate each line in the frontmatter block
  for (let i = 1; i <= closingLine; i++) {
    const line = doc.line(i)
    const isFirst = i === 1
    const isLast = i === closingLine

    decorations.push(fmLineDecoration(isFirst, isLast).range(line.from))

    // --- delimiters
    if (i === 1 || i === closingLine) {
      decorations.push(delimiterMark.range(line.from, line.to))
      continue
    }

    // YAML key: value pairs
    const colonIndex = line.text.indexOf(':')
    if (colonIndex > 0) {
      // Key part
      decorations.push(keyMark.range(line.from, line.from + colonIndex + 1))
      // Value part (after colon + space)
      const valueStart = line.from + colonIndex + 1
      if (valueStart < line.to) {
        decorations.push(valueMark.range(valueStart, line.to))
      }
    }
  }

  return Decoration.set(decorations, true)
}

export const frontmatterDecorations = ViewPlugin.fromClass(
  class {
    constructor(view) {
      this.decorations = buildFrontmatterDecorations(view)
    }
    update(update) {
      if (update.docChanged) {
        this.decorations = buildFrontmatterDecorations(update.view)
      }
    }
  },
  { decorations: (v) => v.decorations }
)
```

- [ ] **Step 2: Add to index.js**

Import and add `frontmatterDecorations` to extensions:

```javascript
import { frontmatterDecorations } from './markdown/frontmatter.js'
```

Add `frontmatterDecorations` to the extensions array.

- [ ] **Step 3: Build and test**

```bash
cd <repo>/Editor && npm run build
```

Test with:
```javascript
window.PortyEditor.setMarkdown('---\ntitle: "My Project"\ndate: 2026-04-10\ntags: [swift, editor]\nstatus: active\n---\n\n# Hello World')
```

Expected: frontmatter block has subtle background, `---` delimiters are muted, keys are faint, values are muted. Heading below renders large.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: frontmatter block decorations with styled YAML"
```

---

## Task 6: Keyboard Shortcuts

**Files:**
- Create: `Editor/src/keybindings.js`
- Modify: `Editor/src/index.js` (import and add to keymap)

- [ ] **Step 1: Create keybindings.js**

Create `Editor/src/keybindings.js`:

```javascript
/**
 * Markdown keyboard shortcuts.
 * Toggles wrap selection with markdown syntax characters.
 */

function wrapSelection(view, before, after) {
  const { from, to } = view.state.selection.main
  const selected = view.state.sliceDoc(from, to)

  // Check if already wrapped — toggle off
  if (selected.startsWith(before) && selected.endsWith(after)) {
    const unwrapped = selected.slice(before.length, selected.length - after.length)
    view.dispatch({
      changes: { from, to, insert: unwrapped },
      selection: { anchor: from, head: from + unwrapped.length },
    })
    return true
  }

  // Check if surrounding text has the markers — toggle off
  const beforeStart = from - before.length
  const afterEnd = to + after.length
  if (beforeStart >= 0 && afterEnd <= view.state.doc.length) {
    const textBefore = view.state.sliceDoc(beforeStart, from)
    const textAfter = view.state.sliceDoc(to, afterEnd)
    if (textBefore === before && textAfter === after) {
      view.dispatch({
        changes: [
          { from: beforeStart, to: from, insert: '' },
          { from: to, to: afterEnd, insert: '' },
        ],
        selection: { anchor: beforeStart, head: beforeStart + (to - from) },
      })
      return true
    }
  }

  // Wrap selection
  view.dispatch({
    changes: { from, to, insert: before + selected + after },
    selection: { anchor: from + before.length, head: from + before.length + selected.length },
  })
  return true
}

function setHeading(view, level) {
  const { from } = view.state.selection.main
  const line = view.state.doc.lineAt(from)
  const text = line.text

  // Remove existing heading prefix
  const match = text.match(/^(#{1,6})\s/)
  const prefix = '#'.repeat(level) + ' '

  if (match) {
    const existingPrefix = match[0]
    if (existingPrefix === prefix) {
      // Same level — remove heading
      view.dispatch({
        changes: { from: line.from, to: line.from + existingPrefix.length, insert: '' },
      })
    } else {
      // Different level — replace
      view.dispatch({
        changes: { from: line.from, to: line.from + existingPrefix.length, insert: prefix },
      })
    }
  } else {
    // Add heading prefix
    view.dispatch({
      changes: { from: line.from, to: line.from, insert: prefix },
    })
  }
  return true
}

function insertLink(view) {
  const { from, to } = view.state.selection.main
  const selected = view.state.sliceDoc(from, to)

  if (selected) {
    // Wrap selected text as link text
    const insert = `[${selected}]()`
    view.dispatch({
      changes: { from, to, insert },
      selection: { anchor: from + selected.length + 3 }, // cursor inside ()
    })
  } else {
    const insert = '[]()'
    view.dispatch({
      changes: { from, to: from, insert },
      selection: { anchor: from + 1 }, // cursor inside []
    })
  }
  return true
}

export const markdownKeymap = [
  { key: 'Mod-b', run: (view) => wrapSelection(view, '**', '**') },
  { key: 'Mod-i', run: (view) => wrapSelection(view, '*', '*') },
  { key: 'Mod-Shift-s', run: (view) => wrapSelection(view, '~~', '~~') },
  { key: 'Mod-e', run: (view) => wrapSelection(view, '`', '`') },
  { key: 'Mod-Shift-1', run: (view) => setHeading(view, 1) },
  { key: 'Mod-Shift-2', run: (view) => setHeading(view, 2) },
  { key: 'Mod-Shift-3', run: (view) => setHeading(view, 3) },
  { key: 'Mod-Shift-k', run: insertLink },
]
```

- [ ] **Step 2: Add keybindings to index.js**

Import and add to keymap:

```javascript
import { markdownKeymap } from './keybindings.js'
```

In the `keymap.of()` call, add `...markdownKeymap` before `...defaultKeymap`:

```javascript
keymap.of([
  ...markdownKeymap,
  ...defaultKeymap,
  ...historyKeymap,
  ...searchKeymap,
]),
```

- [ ] **Step 3: Build and test**

```bash
cd <repo>/Editor && npm run build
```

Test: select text in editor, press Cmd+B → text should wrap in `**`. Press again → unwrap. Same for Cmd+I, Cmd+E, Cmd+Shift+S. Press Cmd+Shift+1 → line becomes `# heading`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: markdown keyboard shortcuts — bold, italic, strike, code, headings, links"
```

---

## Task 7: Media Preview Widgets

**Files:**
- Create: `Editor/src/markdown/media.js`
- Modify: `Editor/src/index.js` (import and add to extensions)

- [ ] **Step 1: Create media.js**

Create `Editor/src/markdown/media.js`:

```javascript
import { ViewPlugin, Decoration, WidgetType } from '@codemirror/view'

const IMAGE_EXTS = ['jpg', 'jpeg', 'png', 'gif', 'svg', 'webp', 'avif']
const VIDEO_EXTS = ['mp4', 'webm', 'ogg', 'mov']

function getExt(filename) {
  const parts = filename.split('.')
  return parts.length > 1 ? parts[parts.length - 1].toLowerCase() : ''
}

function resolveMediaSrc(filename) {
  if (/^(https?|data|blob):/.test(filename)) return filename
  return `portymcfolio://media/${encodeURIComponent(filename)}`
}

class MediaPreviewWidget extends WidgetType {
  constructor(filename) {
    super()
    this.filename = filename
  }

  eq(other) {
    return this.filename === other.filename
  }

  toDOM() {
    const wrapper = document.createElement('div')
    wrapper.className = 'cm-media-preview'

    const ext = getExt(this.filename)
    const src = resolveMediaSrc(this.filename)

    if (IMAGE_EXTS.includes(ext)) {
      const img = document.createElement('img')
      img.src = src
      img.alt = this.filename
      img.loading = 'lazy'
      img.onerror = () => {
        wrapper.innerHTML = ''
        wrapper.appendChild(createBadge(this.filename))
      }
      wrapper.appendChild(img)
    } else if (VIDEO_EXTS.includes(ext)) {
      const video = document.createElement('video')
      video.src = src
      video.controls = true
      video.preload = 'metadata'
      wrapper.appendChild(video)
    } else {
      wrapper.appendChild(createBadge(this.filename))
    }

    return wrapper
  }

  ignoreEvent() { return true }
}

function createBadge(filename) {
  const badge = document.createElement('div')
  badge.className = 'media-badge'
  badge.textContent = filename
  return badge
}

const mediaEmbedRegex = /^!\[\[([^\]]+)\]\]\s*$/

function buildMediaDecorations(view) {
  const decorations = []
  const doc = view.state.doc

  for (let i = 1; i <= doc.lines; i++) {
    const line = doc.line(i)
    const match = line.text.match(mediaEmbedRegex)
    if (match) {
      const filename = match[1].trim()
      // Mute the ![[...]] syntax
      decorations.push(
        Decoration.mark({ class: 'cm-md-syntax' }).range(line.from, line.to)
      )
      // Add widget below the line
      decorations.push(
        Decoration.widget({
          widget: new MediaPreviewWidget(filename),
          side: 1,
          block: true,
        }).range(line.to)
      )
    }
  }

  return Decoration.set(decorations, true)
}

export const mediaDecorations = ViewPlugin.fromClass(
  class {
    constructor(view) {
      this.decorations = buildMediaDecorations(view)
    }
    update(update) {
      if (update.docChanged) {
        this.decorations = buildMediaDecorations(update.view)
      }
    }
  },
  { decorations: (v) => v.decorations }
)
```

- [ ] **Step 2: Add to index.js**

Import and add `mediaDecorations` to extensions:

```javascript
import { mediaDecorations } from './markdown/media.js'
```

- [ ] **Step 3: Build and test**

```bash
cd <repo>/Editor && npm run build
```

Test with content containing `![[some-image.png]]`. In browser, the image won't load (no scheme handler), but the widget DOM should appear. In the actual app, images from the project folder should display inline.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: media embed preview widgets — inline images, video, file badges"
```

---

## Task 8: Slash Command Menu

**Files:**
- Create: `Editor/src/commands.js`
- Modify: `Editor/src/index.js` (import and add to extensions)

- [ ] **Step 1: Create commands.js**

Create `Editor/src/commands.js`:

```javascript
import { ViewPlugin } from '@codemirror/view'
import { postRequestMediaPicker } from './bridge.js'

const commandItems = [
  { title: 'Heading 1', icon: 'H1', insert: '# ' },
  { title: 'Heading 2', icon: 'H2', insert: '## ' },
  { title: 'Heading 3', icon: 'H3', insert: '### ' },
  { title: 'Bullet List', icon: '\u2022', insert: '- ' },
  { title: 'Ordered List', icon: '1.', insert: '1. ' },
  { title: 'Blockquote', icon: '\u275d', insert: '> ' },
  { title: 'Code Block', icon: '</>', insert: '```\n\n```', cursorOffset: 4 },
  { title: 'Table', icon: '\u229e', insert: '| Column 1 | Column 2 | Column 3 |\n| --- | --- | --- |\n| | | |\n| | | |' },
  { title: 'Horizontal Rule', icon: '\u2014', insert: '---' },
  { title: 'Insert Media', icon: '\ud83d\uddbc', action: 'media' },
]

class SlashCommandMenu {
  constructor() {
    this.el = null
    this.items = commandItems
    this.filteredItems = commandItems
    this.selectedIndex = 0
    this.active = false
    this.slashPos = -1
    this.query = ''
  }

  show(view, pos) {
    this.slashPos = pos
    this.active = true
    this.query = ''
    this.selectedIndex = 0
    this.filteredItems = this.items

    if (!this.el) {
      this.el = document.createElement('div')
      this.el.className = 'slash-menu'
      document.body.appendChild(this.el)
    }

    this.render(view)
    this.position(view, pos)
    this.el.style.display = ''
  }

  hide() {
    this.active = false
    if (this.el) this.el.style.display = 'none'
  }

  position(view, pos) {
    if (!this.el) return
    const coords = view.coordsAtPos(pos)
    if (!coords) return
    this.el.style.left = `${coords.left}px`
    this.el.style.top = `${coords.bottom + 4}px`
  }

  render(view) {
    if (!this.el) return
    this.el.innerHTML = ''

    if (this.filteredItems.length === 0) {
      this.el.innerHTML = '<div class="slash-menu-item" style="color:var(--text-faint);justify-content:center;">No results</div>'
      return
    }

    this.filteredItems.forEach((item, i) => {
      const el = document.createElement('div')
      el.className = 'slash-menu-item' + (i === this.selectedIndex ? ' is-selected' : '')
      el.innerHTML = `
        <span class="slash-menu-icon">${item.icon}</span>
        <div class="slash-menu-text">
          <span class="slash-menu-title">${item.title}</span>
        </div>
      `
      el.addEventListener('mousedown', (e) => {
        e.preventDefault()
        this.execute(view, item)
      })
      el.addEventListener('mouseenter', () => {
        this.selectedIndex = i
        this.render(view)
      })
      this.el.appendChild(el)
    })
  }

  filter(query, view) {
    this.query = query
    this.filteredItems = this.items.filter(item =>
      item.title.toLowerCase().includes(query.toLowerCase())
    )
    this.selectedIndex = 0
    this.render(view)
  }

  execute(view, item) {
    // Remove the /query text
    const from = this.slashPos
    const to = view.state.selection.main.head

    if (item.action === 'media') {
      view.dispatch({ changes: { from, to, insert: '' } })
      postRequestMediaPicker()
    } else {
      const insert = item.insert
      const cursorOffset = item.cursorOffset || insert.length
      view.dispatch({
        changes: { from, to, insert },
        selection: { anchor: from + cursorOffset },
      })
    }

    this.hide()
    view.focus()
  }

  handleKeyDown(view, event) {
    if (!this.active) return false

    if (event.key === 'Escape') {
      this.hide()
      return true
    }
    if (event.key === 'ArrowDown') {
      this.selectedIndex = (this.selectedIndex + 1) % this.filteredItems.length
      this.render(view)
      return true
    }
    if (event.key === 'ArrowUp') {
      this.selectedIndex = (this.selectedIndex + this.filteredItems.length - 1) % this.filteredItems.length
      this.render(view)
      return true
    }
    if (event.key === 'Enter') {
      const item = this.filteredItems[this.selectedIndex]
      if (item) this.execute(view, item)
      return true
    }
    return false
  }
}

const menu = new SlashCommandMenu()

export const slashCommands = ViewPlugin.fromClass(
  class {
    constructor(view) {
      this.view = view
    }

    update(update) {
      if (!update.docChanged) return

      update.changes.iterChanges((fromA, toA, fromB, toB, inserted) => {
        const text = inserted.toString()

        // Detect / typed at start of line or after space
        if (text === '/') {
          const pos = fromB
          const line = update.state.doc.lineAt(pos)
          const charBefore = pos > line.from ? update.state.doc.sliceString(pos - 1, pos) : ''
          if (pos === line.from || charBefore === ' ') {
            menu.show(update.view, pos)
          }
        }

        // Update filter while menu is active
        if (menu.active) {
          const head = update.state.selection.main.head
          const query = update.state.doc.sliceString(menu.slashPos + 1, head)
          if (head <= menu.slashPos || query.includes('\n') || query.includes(' ')) {
            menu.hide()
          } else {
            menu.filter(query, update.view)
          }
        }
      })
    }
  },
  {
    eventHandlers: {
      keydown(event, view) {
        return menu.handleKeyDown(view, event)
      },
      blur() {
        setTimeout(() => menu.hide(), 150)
      },
    },
  }
)
```

- [ ] **Step 2: Add to index.js**

```javascript
import { slashCommands } from './commands.js'
```

Add `slashCommands` to the extensions array.

- [ ] **Step 3: Build and test**

```bash
cd <repo>/Editor && npm run build
```

Test: type `/` at start of a line → menu appears. Type `hea` → filters to headings. Arrow keys navigate, Enter selects, Escape dismisses.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: slash command menu with filtering and keyboard navigation"
```

---

## Task 9: Footer Bar

**Files:**
- Create: `Editor/src/footer.js`
- Modify: `Editor/src/index.js` (import and add to extensions, pass lastModified from Swift)

- [ ] **Step 1: Create footer.js**

Create `Editor/src/footer.js`:

```javascript
import { ViewPlugin } from '@codemirror/view'

let lastModifiedDate = null

export function setLastModified(dateString) {
  lastModifiedDate = dateString
  updateFooter()
}

function extractDateFromFrontmatter(doc) {
  const firstLine = doc.line(1).text.trim()
  if (firstLine !== '---') return null

  for (let i = 2; i <= Math.min(doc.lines, 20); i++) {
    const line = doc.line(i).text
    if (line.trim() === '---') break
    const match = line.match(/^date:\s*(.+)/)
    if (match) return match[1].trim().replace(/['"]/g, '')
  }
  return null
}

function countWords(doc) {
  const text = doc.toString()
  const words = text.match(/[\w\u00C0-\u024F]+/g)
  return words ? words.length : 0
}

function updateFooter(state) {
  const bar = document.getElementById('footer-bar')
  if (!bar) return

  const items = []

  if (state) {
    const words = countWords(state.doc)
    const chars = state.doc.length
    items.push(`<span class="footer-item">${words} words</span>`)
    items.push(`<span class="footer-item">${chars} chars</span>`)

    const created = extractDateFromFrontmatter(state.doc)
    if (created) {
      items.push(`<span class="footer-item">Created ${created}</span>`)
    }
  }

  if (lastModifiedDate) {
    items.push(`<span class="footer-item">Modified ${lastModifiedDate}</span>`)
  }

  bar.innerHTML = items.join('<span class="footer-item" style="color:var(--border);">\u00b7</span>')
  bar.style.display = items.length ? 'flex' : 'none'
}

export const footerPlugin = ViewPlugin.fromClass(
  class {
    constructor(view) {
      updateFooter(view.state)
    }
    update(update) {
      if (update.docChanged) {
        updateFooter(update.state)
      }
    }
    destroy() {
      const bar = document.getElementById('footer-bar')
      if (bar) bar.style.display = 'none'
    }
  }
)
```

- [ ] **Step 2: Add to index.js**

Import and add to extensions:

```javascript
import { footerPlugin, setLastModified } from './footer.js'
```

Add `footerPlugin` to the extensions array.

Add `setLastModified` to the `PortyEditor` API:

```javascript
const PortyEditor = { init: initEditor, setMarkdown, getMarkdown, focus, insertMediaEmbed, setLastModified }
```

- [ ] **Step 3: Update Swift to send last modified date**

In `EditorView.swift`, in `loadContent()`, after calling `bridge.loadMarkdown`, send the last modified date:

Add this after the `bridge.loadMarkdown(in: webView, content: content)` call:

```swift
// Send last modified date
if let attrs = try? FileManager.default.attributesOfItem(atPath: readmeURL.path),
   let modified = attrs[.modificationDate] as? Date {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    let dateStr = formatter.string(from: modified)
    let escaped = dateStr.replacingOccurrences(of: "'", with: "\\'")
    webView.evaluateJavaScript("window.PortyEditor.setLastModified('\(escaped)')")
}
```

- [ ] **Step 4: Build and test**

```bash
cd <repo>/Editor && npm run build
cd <repo> && xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Test in browser: footer should show word count and character count. Created date appears if frontmatter has a `date` field.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: footer bar — word count, char count, created date, last modified"
```

---

## Task 10: Drag & Drop Media

**Files:**
- Modify: `Editor/src/index.js` (add drop handler extension)

- [ ] **Step 1: Add drag & drop handler to index.js**

Add this extension to the `extensions` array in `index.js`. Import `EditorView` if not already imported:

```javascript
const dropHandler = EditorView.domEventHandlers({
  drop(event, view) {
    const files = event.dataTransfer?.files
    if (!files || files.length === 0) return false

    event.preventDefault()

    // Get drop position
    const pos = view.posAtCoords({ x: event.clientX, y: event.clientY })
    if (pos === null) return false

    // For each file, post to Swift to copy and get filename
    // For now, insert the filename directly — Swift bridge handles the copy
    Array.from(files).forEach(file => {
      const filename = file.name
      const insert = `![[${filename}]]\n`
      view.dispatch({
        changes: { from: pos, to: pos, insert },
      })

      // Notify Swift to copy the file to the project folder
      try {
        window.webkit?.messageHandlers?.fileDrop?.postMessage(filename)
      } catch (e) {
        // Not in WKWebView or handler not registered
      }
    })

    return true
  },
})
```

Add `dropHandler` to the extensions array.

Note: Full drag & drop with file copying requires a new `fileDrop` message handler in Swift. For now, this inserts the `![[filename]]` syntax. The actual file copy from Finder requires additional Swift work that can be added later — the editor side is ready.

- [ ] **Step 2: Build and test**

```bash
cd <repo>/Editor && npm run build
```

Test: drag a file onto the editor in browser → `![[filename]]` should be inserted at drop position.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: drag & drop file insertion — inserts media embed syntax at drop position"
```

---

## Task 11: Final Integration, Build, and Verify

**Files:**
- Modify: `Editor/src/index.js` (final review of all extensions)
- Run: Xcode build + test suite

- [ ] **Step 1: Final Xcode build**

```bash
cd <repo>/Editor && npm run build
cd <repo> && xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Run existing test suite**

```bash
cd <repo> && xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' test 2>&1 | grep -E "Executed|TEST"
```

Expected: All 34 tests pass. (Tests are for Swift models/services, not the editor JS.)

- [ ] **Step 3: Browser preview verification**

Start http-server and verify:

1. Editor loads with placeholder text
2. `setMarkdown()` with frontmatter + body renders correctly
3. Frontmatter has styled background, muted keys
4. Headings are large with muted `##`
5. Bold, italic, strike, code all styled with muted syntax chars
6. Code blocks have background
7. Blockquotes have colored left border
8. `![[image.png]]` shows media preview widget
9. Cmd+B/I/E toggles formatting
10. Cmd+F opens search panel
11. `/` opens slash command menu
12. Footer shows word count
13. `getMarkdown()` returns the exact document content

- [ ] **Step 4: Clean up old Tiptap files from git**

Verify no old Tiptap source files remain:

```bash
ls Editor/src/components/ 2>/dev/null && echo "STILL EXISTS" || echo "CLEAN"
ls Editor/src/extensions/ 2>/dev/null && echo "STILL EXISTS" || echo "CLEAN"
ls Editor/src/markdown-serializer.js 2>/dev/null && echo "STILL EXISTS" || echo "CLEAN"
```

Expected: All "CLEAN"

- [ ] **Step 5: Commit final state**

```bash
git add -A
git commit -m "feat: CodeMirror 6 editor v2 — complete rewrite with source-with-styling markdown"
```
