# PortyMcFolio Editor v2 — CodeMirror 6 Rewrite

## Summary

Replace the Tiptap WYSIWYG editor with a CodeMirror 6 source-with-styling editor. The markdown source is always visible — syntax characters (`##`, `**`, `` ` ``, `---`) are shown but styled subtly so they don't compete with the rendered content. Headings are big, bold is bold, code gets mono treatment. The file is the truth and the editor shows it honestly.

## Design Principles

- **Honesty meets rendering** — syntax is always visible, never hidden. But styling makes it beautiful.
- **The file is the editor** — frontmatter, body, everything lives in one editable surface. No separate bars or panels.
- **Keyboard-first** — standard shortcuts for everything. No toolbar needed.
- **Portfolio-native** — media files from the project folder render inline. Drag and drop works.

## Architecture

```
Editor/
  src/
    index.js              # Entry point, creates CodeMirror editor, exposes window.PortyEditor API
    theme.js              # Light/dark theme (CSS custom properties + EditorView.theme)
    keybindings.js        # Cmd+B, Cmd+I, Cmd+K, etc.
    markdown/
      decorations.js      # Line & inline decorations for styled markdown rendering
      frontmatter.js      # Frontmatter block detection and styling
      media.js            # ![[file]] inline preview widget (images, video, file badges)
      syntax-hiding.js    # Muted styling for syntax chars (##, **, `, ---)
    search.js             # Cmd+F in-document find & replace
    commands.js           # Slash command menu (/ trigger)
    bridge.js             # postMessage bridge to Swift (contentChanged, editorReady, requestMediaPicker)
  vite.config.js          # Builds IIFE bundle → editor.bundle.js
  package.json            # codemirror, @codemirror/lang-markdown, @lezer/markdown
```

The Swift side stays mostly unchanged: WKWebView loads `editor.html`, registers message handlers (`contentChanged`, `editorReady`, `requestMediaPicker`), MediaSchemeHandler serves `portymcfolio://media/` URLs. The JS API surface stays the same: `window.PortyEditor = { init, setMarkdown, getMarkdown, focus }`.

## Frontmatter

Frontmatter lives in the document as editable YAML text:

```
---
title: "Cogito"
date: 2026-03-15
tags: [swift, macos, editor]
client: Internal
status: active
---
```

Styling:
- The `---` delimiters render as subtle horizontal lines (thin, muted color)
- Keys (`title:`, `date:`, `tags:`) are muted/grey
- Values are normal text color
- The entire block has a subtle background tint to distinguish it from body content
- Array values like tags could optionally render as inline pills (stretch goal)

Frontmatter is no longer stripped by Swift. The full file content (frontmatter + body) goes to CodeMirror. CodeMirror saves the full file content back. Swift's `FrontmatterParser` is used only by `PortfolioStore` for indexing/display in the project list — the editor doesn't need to know about frontmatter structure.

## Markdown Rendering

All rendering is done through CodeMirror decorations. The source text is never modified — decorations are visual overlays.

### Headings
- `# Heading 1` — the `#` is rendered in muted color (40% opacity), the heading text is 1.875em, font-weight 700
- `## Heading 2` — `##` muted, text 1.4em, font-weight 650
- `### Heading 3` — `###` muted, text 1.15em, font-weight 600

### Inline formatting
- `**bold**` — the `**` markers are muted, the text between is font-weight 650
- `*italic*` — the `*` markers are muted, the text between is italic
- `~~strike~~` — the `~~` markers are muted, the text between has line-through
- `` `code` `` — the backticks are muted, the text gets mono font + subtle background

### Code blocks
- The ``` markers are muted
- The entire block gets a background, mono font, rounded corners
- Language identifier (if any) is styled as a subtle label

### Blockquotes
- `>` marker is styled as a colored left border
- Quote text is muted

### Lists
- `-` and `1.` markers are styled in muted color
- Proper indentation preserved

### Horizontal rules
- `---` in body (not frontmatter position) renders as a styled divider line

### Links
- `[text](url)` — brackets/parens are muted, text is link-colored, url is muted
- Cmd+click opens the URL

### Media embeds
- `![[filename.jpg]]` — the syntax is shown muted, AND an actual image preview is rendered below the line as a CodeMirror widget decoration
- `![[filename.mov]]` — video player widget
- Other files — file badge with icon and filename
- Images resolve via `portymcfolio://media/filename` (existing scheme handler)
- Max preview width: 100% of editor width, max height ~400px for images

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd+B | Toggle bold (`**`) around selection |
| Cmd+I | Toggle italic (`*`) around selection |
| Cmd+Shift+S | Toggle strikethrough (`~~`) |
| Cmd+E | Toggle inline code (`` ` ``) |
| Cmd+Shift+1 | Heading 1 |
| Cmd+Shift+2 | Heading 2 |
| Cmd+Shift+3 | Heading 3 |
| Cmd+F | Find & replace in document |
| Cmd+K | Reserved for cross-project search (future) |
| Cmd+Shift+K | Insert link |
| Cmd+Z / Cmd+Shift+Z | Undo / Redo |
| Tab / Shift+Tab | Indent / Dedent in lists and code blocks |

## Slash Commands

Typing `/` at the start of a line (or after a space) triggers a floating command palette. Same commands as current:

- Heading 1, 2, 3
- Bullet List, Ordered List
- Blockquote
- Code Block
- Table (inserts a 3x3 template)
- Horizontal Rule
- Insert Media (opens native file picker via Swift bridge)

Implementation: CodeMirror `ViewPlugin` that watches for `/` input, shows a floating DOM menu positioned at the cursor, filters on typing, inserts markdown text on selection.

## Footer Bar

A persistent bar at the bottom of the editor showing:

- Word count
- Character count
- Date created (from frontmatter `date` field)
- Last modified (file system timestamp, passed from Swift)

Styled subtly — small text, muted color, doesn't compete with content.

## Media Handling

- **Insert from folder**: Slash command "Insert Media" → Swift opens `NSOpenPanel` scoped to project folder → inserts `![[filename]]`
- **Insert from anywhere**: Same picker but allows any location → file is copied to project folder first → inserts `![[filename]]`
- **Drag & drop**: Drag file from Finder into editor → copies to project folder → inserts `![[filename]]` at drop position
- **Preview**: Widget decoration renders below the `![[...]]` line showing the actual image/video/file badge

## Search

### v1: In-document (Cmd+F)
- CodeMirror's built-in search extension (`@codemirror/search`)
- Find & replace panel at top of editor
- Regex support
- Styled to match the editor theme

### Future: Cross-project (Cmd+K)
- Deferred. Will search across all project READMEs using the existing SQLite FTS5 index.

## Theme

Two themes: light and dark, following system preference via `prefers-color-scheme`.

CSS custom properties for all colors so theming is straightforward. The visual language from the current `editor.css` carries over — same accent colors, same font stack, same border radii.

Key tokens:
- `--text` / `--text-muted` / `--text-faint` — content hierarchy
- `--syntax` — color for markdown syntax characters (muted, ~40% opacity feel)
- `--bg` / `--bg-secondary` — backgrounds
- `--accent` — links, selections, active states
- `--code-bg` / `--code-text` — code styling
- `--border` — subtle separators

## What's Being Removed

- **Tiptap** — entire `@tiptap/*` dependency tree
- **tiptap-markdown** — no longer needed, CodeMirror works with raw text
- **tippy.js** — slash command menu will use simple positioned DOM
- **Bubble menu** — replaced by keyboard shortcuts
- **Wiki-links extension** — deferred to future version
- **Separate frontmatter bar** — frontmatter lives in the document
- **Markdown pre/post processing** — no conversion needed, source is the content

## What Stays the Same

- **Swift side**: WKWebView, EditorBridge, MediaSchemeHandler, message handler pattern
- **JS API**: `window.PortyEditor = { init, setMarkdown, getMarkdown, focus }`
- **Build pipeline**: Vite IIFE bundle → `editor.bundle.js`
- **File format**: Standard markdown with YAML frontmatter, `![[media]]` embeds
- **editor.html / editor.css**: Same files, new content

## Dependencies

```json
{
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

## Out of Scope

- Cross-project search (Cmd+K) — future
- Wiki-links — future
- Syntax highlighting within code blocks (language-specific) — nice-to-have, not v1
- Collaborative editing — not planned
- Vim/Emacs keybindings — not planned
- Export to PDF/HTML — not planned
