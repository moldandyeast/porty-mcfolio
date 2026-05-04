# Rich Embeds — Link Cards & File References

**Date:** 2026-04-13
**Status:** Spec
**Scope:** Add rich card rendering for links and non-media file references in the editor

---

## Goal

Embed URLs and non-media files (PDF, .sketch, .fig, .zip, etc.) as styled cards in the markdown editor. Cards show title, icon/favicon, and description. Support insertion via slash commands, drag from gallery, drag from Finder, and URL paste.

## Markdown Format

Use Obsidian-compatible callout/admonition syntax. This renders as plain blockquotes in standard markdown renderers and is fully portable.

### Link Card

```markdown
> [!link]
> url: https://example.com
> title: Example Site
> description: A great resource for designers
```

### File Reference Card

```markdown
> [!file]
> path: report.pdf
> title: Q4 Design Report
```

The `title` field is optional for files — defaults to the filename.

## Insertion Triggers

| Trigger | What happens |
|---------|-------------|
| `/link` slash command | Prompts for URL → Swift fetches metadata → inserts link card block |
| `/file` slash command | Opens file picker (non-media types) → inserts file card block |
| Drag media from gallery/Finder | Existing behavior: `![[filename]]` with preview |
| Drag non-media file from gallery/Finder | Inserts `> [!file]` card block |
| Paste/drop a URL | Detects URL → Swift fetches metadata → inserts link card block |

### Smart file type routing

When a file is dropped or dragged, the system decides based on extension:

- **Media** (jpg, png, gif, mp4, mov, etc.) → `![[filename]]` embed with preview
- **Non-media** (pdf, sketch, fig, zip, docx, etc.) → `> [!file]` card block

This logic lives in Swift (`DropTargetWebView` and `insertMediaFile`), which already has the extension lists.

## Editor Rendering

### Link Card Widget

A CodeMirror decoration that detects `> [!link]` blocks and renders them as a styled card:

```
┌─────────────────────────────────────────┐
│ 🔗  Example Site                        │
│     example.com                         │
│     A great resource for designers      │
└─────────────────────────────────────────┘
```

- Rounded corners, subtle border, secondary background
- Link icon (or favicon if available)
- Title in medium weight, domain in muted, description in faint
- Click anywhere on card → opens URL in default browser
- Syntax text hidden by default, revealed when cursor is on the block (same pattern as media embeds and HR)

### File Card Widget

```
┌─────────────────────────────────────────┐
│ 📄  Q4 Design Report                   │
│     report.pdf · PDF                    │
└─────────────────────────────────────────┘
```

- File type icon (📄 PDF, 🎨 Sketch/Figma, 📦 Archive, 📁 Generic)
- Title (or filename), file extension label
- Click → opens file with default app (`NSWorkspace.shared.open`)

## URL Metadata Fetching

When a link card is inserted, Swift fetches metadata:

1. JS sends URL to Swift via bridge message `requestLinkMetadata`
2. Swift uses `LPMetadataProvider` (LinkPresentation framework) to fetch:
   - Page title
   - Description (from meta tags)
   - Icon/favicon URL
3. Swift sends metadata back to JS via `window.PortyEditor.insertLinkCard(url, title, description)`
4. JS inserts the `> [!link]` block with the fetched data

If fetch fails (timeout, offline), insert with just the URL and domain as title.

## New Slash Commands

Add to the existing command list in `commands.js`:

| Command | Icon | Section | Behavior |
|---------|------|---------|----------|
| Insert Link | 🔗 | Media | Triggers `requestLinkInput` bridge message → Swift shows URL input → fetches metadata → inserts card |
| Insert File | 📎 | Media | Triggers `requestFilePicker` bridge message → Swift shows file picker (non-media types) → inserts card |

## Bridge Messages (JS → Swift)

| Message | Purpose |
|---------|---------|
| `requestLinkInput` | Ask Swift to show a URL input dialog |
| `requestFilePicker` | Ask Swift to show file picker for non-media files |

## Bridge Callbacks (Swift → JS)

| Function | Purpose |
|----------|---------|
| `window.PortyEditor.insertLinkCard(url, title, description)` | Insert a `> [!link]` block |
| `window.PortyEditor.insertFileCard(path, title)` | Insert a `> [!file]` block |

## Files Changed

| File | Change |
|------|--------|
| `Editor/src/commands.js` | Add Insert Link and Insert File slash commands |
| `Editor/src/index.js` | Add `insertLinkCard` and `insertFileCard` functions to PortyEditor API |
| `Editor/src/markdown/embeds.js` | **New file**: decoration plugin for `> [!link]` and `> [!file]` card rendering |
| `Editor/src/bridge.js` | Add `postRequestLinkInput` and `postRequestFilePicker` bridge messages |
| `PortyMcFolio/Editor/Resources/editor.css` | Card styles (`.cm-embed-card`, `.cm-embed-link`, `.cm-embed-file`) |
| `PortyMcFolio/Views/EditorView.swift` | Add bridge handlers for link input dialog, file picker, metadata fetching; update `insertMediaFile` to route non-media to file cards |
| `PortyMcFolio/Editor/EditorBridge.swift` | Register new message handlers |
| `PortyMcFolio/Editor/Resources/editor.bundle.js` | Rebuilt |

## What Does NOT Change

- Media embed behavior (`![[]]` for images/video) — unchanged
- Gallery view — unchanged (drag source already works)
- Frontmatter — unchanged

## Edge Cases

- **Metadata fetch timeout**: 5 second timeout, fall back to URL domain as title
- **Offline**: Insert card with URL only, no description
- **File moved/deleted**: File card shows filename with "missing" indicator
- **Long URLs**: Truncate display URL to domain + path, full URL in the markdown
- **Duplicate file names**: Use relative path from project folder
