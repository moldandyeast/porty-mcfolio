# Markdown Preview Renderer

## Context

The editor is now a clean monospace NSTextView that shows raw markdown. We need a preview that renders the markdown as beautiful, feature-complete HTML. The HTML should be exportable as a self-contained document.

## Architecture

One new file: `PortyMcFolio/Views/MarkdownPreviewView.swift`

A SwiftUI `NSViewRepresentable` wrapping a `WKWebView`. Takes a markdown string and a project folder URL. Renders as styled HTML.

## Pipeline

1. **Swift pre-processing**: Replace `![[filename]]` embeds with HTML before markdown conversion
   - `![[image.png]]` → `<img src="portymcfolio://media/image.png">`
   - `![[link-uid.md]]` → read link file frontmatter, emit `<div class="link-card">` with title + domain + URL
   - `![[other.pdf]]` → `<div class="file-badge">` with icon + filename
2. **WKWebView**: loads an HTML template containing:
   - Inlined marked.js (~40KB) for markdown → HTML conversion
   - A `<style>` block with all styling
   - A JS function `renderMarkdown(html)` that sets the body content
3. **Swift calls** `evaluateJavaScript("renderMarkdown(html)")` with the pre-processed markdown

## Custom URL Scheme

Re-use the `portymcfolio://media/` scheme for images. Add a `MediaSchemeHandler` to the preview's WKWebView configuration (same concept as the old editor, but simpler — read-only, just serves files from the project folder).

## CSS Design

- Font: -apple-system, 16px, line-height 1.7
- Max-width: 720px, centered with auto margins
- Headings: h1 2em bold, h2 1.5em semibold, h3 1.17em semibold
- Bold, italic, strikethrough: standard
- Inline code: monospace, subtle background pill
- Code blocks: monospace, background, rounded corners, padding
- Blockquotes: left border 3px, muted text, padding-left
- Lists: standard indentation
- Images: max-width 100%, rounded corners, margin
- HR: thin centered line, margin
- Links: accent color, underline on hover
- Link cards: bordered box with title + domain, clickable
- File badges: small inline box with icon + filename
- Dark/light: automatic via `@media (prefers-color-scheme: dark)`

## Export

A method `exportHTML(markdown: String, projectFolder: URL) -> String` that:
1. Pre-processes embeds (same as preview, but uses base64 data URIs for images instead of portymcfolio:// scheme)
2. Runs marked.js conversion (or a Swift-side conversion for export)
3. Wraps in a complete `<!DOCTYPE html>` document with inlined CSS
4. Returns the self-contained HTML string

Export is a future addition — the preview comes first.

## Integration

For now, the preview is a standalone view used in ProjectDetailView alongside the editor. The exact layout (side-by-side, toggle, tab) will be decided after the renderer works.

```swift
MarkdownPreviewView(markdown: bodyText, projectFolderURL: folder)
```

## Files

- Create: `PortyMcFolio/Views/MarkdownPreviewView.swift`
- Create: `PortyMcFolio/Editor/Resources/marked.min.js` (vendored, ~40KB)
- Create: `PortyMcFolio/Editor/Resources/preview.html` (template with CSS + JS)
- Modify: `PortyMcFolio/Views/ProjectDetailView.swift` (add preview alongside editor)
