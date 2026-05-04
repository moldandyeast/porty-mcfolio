# Markdown Preview Renderer — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render markdown as beautiful, feature-complete HTML in a WKWebView preview panel alongside the editor.

**Architecture:** Swift pre-processes `![[embed]]` syntax into HTML, passes the result to a WKWebView that uses inlined marked.js for markdown→HTML conversion and a custom CSS stylesheet. A `portymcfolio://` URL scheme handler serves project images.

**Tech Stack:** WKWebView, marked.js (vendored, ~40KB), custom CSS, MediaSchemeHandler (file server for project images).

---

## File Structure

**New files:**
- `PortyMcFolio/Views/MarkdownPreviewView.swift` — NSViewRepresentable wrapping WKWebView, pre-processes embeds, sends markdown to JS
- `PortyMcFolio/Editor/PreviewSchemeHandler.swift` — WKURLSchemeHandler serving project files via `portymcfolio://media/` URLs
- `PortyMcFolio/Editor/Resources/preview.html` — HTML template with inlined CSS + marked.js loader
- `PortyMcFolio/Editor/Resources/marked.min.js` — vendored marked.js library

**Modified files:**
- `PortyMcFolio/Views/ProjectDetailView.swift` — add preview panel alongside editor
- `PortyMcFolio.xcodeproj/project.pbxproj` — add new files to build

---

### Task 1: Vendor marked.js and create the HTML template

**Files:**
- Create: `PortyMcFolio/Editor/Resources/marked.min.js`
- Create: `PortyMcFolio/Editor/Resources/preview.html`

- [ ] **Step 1: Download marked.js**

```bash
curl -o PortyMcFolio/Editor/Resources/marked.min.js https://cdn.jsdelivr.net/npm/marked/marked.min.js
```

- [ ] **Step 2: Create preview.html**

Create `PortyMcFolio/Editor/Resources/preview.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
:root {
  --text: #1d1d1f;
  --text-muted: #86868b;
  --text-faint: #aeaeb2;
  --bg: #ffffff;
  --bg-secondary: #f5f5f7;
  --bg-code: #f2f2f7;
  --border: #d1d1d6;
  --accent: #007aff;
  --radius: 6px;
}
@media (prefers-color-scheme: dark) {
  :root {
    --text: #f5f5f7;
    --text-muted: #98989d;
    --text-faint: #636366;
    --bg: #1c1c1e;
    --bg-secondary: #2c2c2e;
    --bg-code: #2a2a2e;
    --border: #48484a;
    --accent: #64b5f6;
  }
}
*, *::before, *::after { box-sizing: border-box; }
html { -webkit-font-smoothing: antialiased; }
body {
  font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif;
  font-size: 16px;
  line-height: 1.7;
  color: var(--text);
  background: var(--bg);
  max-width: 720px;
  margin: 0 auto;
  padding: 24px 32px 120px;
}
h1 { font-size: 2em; font-weight: 700; margin: 1.5em 0 0.5em; line-height: 1.2; }
h2 { font-size: 1.5em; font-weight: 650; margin: 1.3em 0 0.4em; line-height: 1.3; }
h3 { font-size: 1.17em; font-weight: 600; margin: 1.1em 0 0.3em; line-height: 1.4; }
h4, h5, h6 { font-weight: 600; margin: 1em 0 0.3em; }
p { margin: 0 0 1em; }
a { color: var(--accent); text-decoration: none; }
a:hover { text-decoration: underline; }
strong { font-weight: 650; }
del { color: var(--text-muted); }
code {
  font-family: 'SF Mono', 'Fira Code', Menlo, monospace;
  font-size: 0.85em;
  background: var(--bg-code);
  border-radius: 3px;
  padding: 0.15em 0.4em;
}
pre {
  background: var(--bg-code);
  border-radius: var(--radius);
  padding: 16px;
  overflow-x: auto;
  margin: 1em 0;
}
pre code { background: none; padding: 0; font-size: 0.85em; }
blockquote {
  border-left: 3px solid var(--border);
  padding-left: 16px;
  margin: 1em 0;
  color: var(--text-muted);
}
hr {
  border: none;
  height: 1px;
  background: var(--border);
  margin: 2em 0;
}
ul, ol { padding-left: 1.5em; margin: 0.5em 0 1em; }
li { margin: 0.25em 0; }
img {
  max-width: 100%;
  height: auto;
  border-radius: var(--radius);
  margin: 0.5em 0;
}
table {
  border-collapse: collapse;
  width: 100%;
  margin: 1em 0;
}
th, td {
  border: 1px solid var(--border);
  padding: 8px 12px;
  text-align: left;
}
th { background: var(--bg-secondary); font-weight: 600; }
.link-card {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 14px;
  margin: 0.5em 0;
  background: var(--bg-secondary);
  border: 1px solid var(--border);
  border-radius: 8px;
  text-decoration: none;
  color: var(--text);
  transition: border-color 0.15s;
}
.link-card:hover { border-color: var(--accent); text-decoration: none; }
.link-card-icon { font-size: 18px; }
.link-card-body { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.link-card-title { font-weight: 500; font-size: 14px; }
.link-card-domain { font-size: 12px; color: var(--text-faint); }
.file-badge {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 4px 10px;
  background: var(--bg-secondary);
  border: 1px solid var(--border);
  border-radius: var(--radius);
  font-size: 13px;
  color: var(--text-muted);
  font-family: 'SF Mono', Menlo, monospace;
  margin: 0.25em 0;
}
.file-badge::before { content: '📎'; }
</style>
</head>
<body>
<div id="content"></div>
<script src="marked.min.js"></script>
<script>
function renderMarkdown(md) {
  document.getElementById('content').innerHTML = marked.parse(md, { gfm: true, breaks: true });
}
</script>
</body>
</html>
```

- [ ] **Step 3: Add files to Xcode project**

Add `preview.html` and `marked.min.js` to the Xcode project as resources (PBXFileReference, PBXBuildFile in Resources build phase, group membership).

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Editor/Resources/preview.html PortyMcFolio/Editor/Resources/marked.min.js PortyMcFolio.xcodeproj/project.pbxproj
git commit -m "feat(preview): vendor marked.js and create HTML template"
```

---

### Task 2: PreviewSchemeHandler (serves project files)

**Files:**
- Create: `PortyMcFolio/Editor/PreviewSchemeHandler.swift`

- [ ] **Step 1: Create PreviewSchemeHandler.swift**

```swift
import Foundation
import WebKit
import UniformTypeIdentifiers

final class PreviewSchemeHandler: NSObject, WKURLSchemeHandler {
    var projectFolderURL: URL?

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let projectFolder = projectFolderURL else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let filename = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let decodedFilename = filename.removingPercentEncoding ?? filename
        let fileURL = projectFolder.appendingPathComponent(decodedFilename)

        guard PathValidation.isContained(fileURL: fileURL, within: projectFolder),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let response = URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: nil)
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
```

- [ ] **Step 2: Add to Xcode project, build**

```bash
# Add to pbxproj, then:
xcodebuild -scheme PortyMcFolio -configuration Debug build
```

- [ ] **Step 3: Commit**

```bash
git add PortyMcFolio/Editor/PreviewSchemeHandler.swift PortyMcFolio.xcodeproj/project.pbxproj
git commit -m "feat(preview): scheme handler serves project files"
```

---

### Task 3: MarkdownPreviewView

**Files:**
- Create: `PortyMcFolio/Views/MarkdownPreviewView.swift`

- [ ] **Step 1: Create MarkdownPreviewView.swift**

```swift
import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    let markdown: String
    let projectFolderURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let handler = PreviewSchemeHandler()
        handler.projectFolderURL = projectFolderURL
        config.setURLSchemeHandler(handler, forURLScheme: "portymcfolio")
        context.coordinator.schemeHandler = handler

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        if let htmlURL = Bundle.main.url(forResource: "preview", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: Bundle.main.bundleURL)
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.schemeHandler?.projectFolderURL = projectFolderURL
        context.coordinator.pendingMarkdown = preprocessEmbeds(markdown)
        if context.coordinator.isReady {
            context.coordinator.render()
        }
    }

    /// Replace ![[filename]] with HTML before passing to marked.js
    private func preprocessEmbeds(_ md: String) -> String {
        let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "svg", "webp", "avif", "heic", "tiff"]
        let linkFileRE = /^link-[0-9a-f]{8}\.md$/

        var result = md
        let embedRE = try! NSRegularExpression(pattern: #"!\[\[([^\]]+)\]\]"#)
        let matches = embedRE.matches(in: result, range: NSRange(location: 0, length: (result as NSString).length))

        // Work backwards to preserve ranges
        for match in matches.reversed() {
            let fullRange = Range(match.range, in: result)!
            let filenameRange = Range(match.range(at: 1), in: result)!
            let filename = String(result[filenameRange]).trimmingCharacters(in: .whitespaces)
            let ext = (filename as NSString).pathExtension.lowercased()

            let replacement: String
            if imageExts.contains(ext) {
                let src = "portymcfolio://media/\(filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename)"
                replacement = "<img src=\"\(src)\" alt=\"\(escapeHTML(filename))\">"
            } else if filename.wholeMatch(of: linkFileRE) != nil {
                replacement = buildLinkCard(filename: filename)
            } else {
                replacement = "<span class=\"file-badge\">\(escapeHTML(filename))</span>"
            }

            result.replaceSubrange(fullRange, with: replacement)
        }

        return result
    }

    private func buildLinkCard(filename: String) -> String {
        let fileURL = projectFolderURL.appendingPathComponent(filename)
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
              let link = try? LinkItem.parse(markdown: content) else {
            return "<span class=\"file-badge\">\(escapeHTML(filename))</span>"
        }
        let title = link.title.isEmpty ? (link.url.host ?? link.url.absoluteString) : link.title
        let domain = link.url.host?.replacingOccurrences(of: "www.", with: "") ?? ""
        return """
        <a class="link-card" href="\(escapeHTML(link.url.absoluteString))" target="_blank">
          <span class="link-card-icon">🔗</span>
          <span class="link-card-body">
            <span class="link-card-title">\(escapeHTML(title))</span>
            <span class="link-card-domain">\(escapeHTML(domain))</span>
          </span>
        </a>
        """
    }

    private func escapeHTML(_ str: String) -> String {
        str.replacingOccurrences(of: "&", with: "&amp;")
           .replacingOccurrences(of: "<", with: "&lt;")
           .replacingOccurrences(of: ">", with: "&gt;")
           .replacingOccurrences(of: "\"", with: "&quot;")
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var schemeHandler: PreviewSchemeHandler?
        var pendingMarkdown: String?
        var isReady = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            render()
        }

        func render() {
            guard let webView, let md = pendingMarkdown else { return }
            guard let data = try? JSONSerialization.data(withJSONObject: [md]),
                  let jsonArray = String(data: data, encoding: .utf8) else { return }
            let jsonString = String(jsonArray.dropFirst().dropLast())
            webView.evaluateJavaScript("renderMarkdown(\(jsonString))")
        }
    }
}
```

- [ ] **Step 2: Add to Xcode project, build**

- [ ] **Step 3: Commit**

```bash
git add PortyMcFolio/Views/MarkdownPreviewView.swift PortyMcFolio.xcodeproj/project.pbxproj
git commit -m "feat(preview): MarkdownPreviewView with embed preprocessing"
```

---

### Task 4: Wire preview into ProjectDetailView

**Files:**
- Modify: `PortyMcFolio/Views/ProjectDetailView.swift`

- [ ] **Step 1: Add preview state and view**

Add a `@State private var showPreview = false` to ProjectDetailView.

In the toolbar, add a preview toggle button (eye icon):

```swift
Button {
    showPreview.toggle()
} label: {
    Image(systemName: showPreview ? "eye.fill" : "eye")
        .font(.system(size: 12))
        .foregroundStyle(showPreview ? DT.Colors.accent : DT.Colors.textTertiary)
}
.buttonStyle(.plain)
.help("Toggle preview")
```

In the body, when `showPreview` is true and `viewMode` is `.editor` or `.split`, show the preview alongside the editor. Read the current body from the README for the preview:

```swift
// Inside the HStack, after the EditorView:
if showPreview {
    MarkdownPreviewView(
        markdown: editorBody(for: project),
        projectFolderURL: project.folderURL
    )
    .frame(maxWidth: .infinity)
}
```

Add a helper that reads the current body:

```swift
private func editorBody(for project: Project) -> String {
    guard let content = try? String(contentsOf: project.readmeURL, encoding: .utf8),
          let parsed = try? FrontmatterParser.parse(content) else { return "" }
    return parsed.body
}
```

- [ ] **Step 2: Build and manually test**

Open a project, click the eye icon. Verify the preview appears with rendered HTML.

- [ ] **Step 3: Run tests**

```bash
xcodebuild -scheme PortyMcFolio -configuration Debug test -destination 'platform=macOS'
```

All 52 tests pass.

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Views/ProjectDetailView.swift
git commit -m "feat(preview): wire preview toggle into ProjectDetailView"
```

---

### Task 5: Live update preview on editor save

**Files:**
- Modify: `PortyMcFolio/Views/ProjectDetailView.swift`

- [ ] **Step 1: Update preview body on save**

Add a `@State private var previewBody = ""` to ProjectDetailView.

Update the `MarkdownEditorView` onSave callback to also update the preview body:

```swift
MarkdownEditorView(readmeURL: project.readmeURL) { savedContent in
    appState.refreshProjects()
    if let parsed = try? FrontmatterParser.parse(savedContent) {
        previewBody = parsed.body
    }
}
```

Use `previewBody` for the preview:

```swift
MarkdownPreviewView(
    markdown: previewBody,
    projectFolderURL: project.folderURL
)
```

Load initial body in `.onAppear`:

```swift
.onAppear {
    handlePendingSelection()
    previewBody = editorBody(for: project)
}
```

- [ ] **Step 2: Build and test**

Edit text in the editor, wait 1.5s for save, verify the preview updates.

- [ ] **Step 3: Commit and push**

```bash
git add PortyMcFolio/Views/ProjectDetailView.swift
git commit -m "feat(preview): live update on editor save"
git push origin dev/v1-implementation
```
