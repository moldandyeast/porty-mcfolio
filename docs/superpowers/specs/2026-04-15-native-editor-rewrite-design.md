# Native NSTextView Editor Rewrite

## Context

The current editor uses CodeMirror 6 inside a WKWebView with a hand-rolled JS bridge. This architecture has caused persistent bugs: cursor misalignment (RTL hack, drawSelection), stale bindings (NSViewRepresentable coordinator), content corruption (debounce race on project switch), drag-drop inserting at random positions, and two competing embed systems. Every fix creates new problems because the bridge is inherently async and lossy.

The rewrite replaces the entire WKWebView/JS stack with a native NSTextView. This eliminates the bridge, gives us native cursor/selection/drag-drop/undo/IME for free, and makes every piece debuggable in Swift.

## External Contract (unchanged)

```swift
EditorView(readmeURL: URL, onSave: ((String) -> Void)?)
```

The rest of the app (AppState, models, services, gallery, search, ProjectDetailView) is untouched. Only the editor internals change.

## Architecture

### 1. MarkdownEditorView (NSViewRepresentable)

The shell. Wraps an `NSScrollView` containing a `MarkdownTextView` (NSTextView subclass).

**Coordinator responsibilities:**
- Load: read README, strip frontmatter, set text view content
- Save: on text change (debounced 1.5s), read frontmatter from disk, prepend to body, write file
- Project switch: cancel pending save, load new content
- Formatting shortcuts: Cmd+B (bold), Cmd+I (italic), Cmd+Shift+S (strikethrough), Cmd+E (code), Cmd+Shift+1/2/3 (headings), Cmd+Shift+K (link)

**MarkdownTextView (NSTextView subclass):**
- Registers for drag types (.fileURL, .URL)
- Override `performDragOperation` -- files dropped at the native drop position (NSTextView handles coordinate conversion automatically)
- Slash command detection in `textDidChange`

### 2. MarkdownHighlighter

Applied via `NSTextStorage.delegate` or a custom `NSTextStorage` subclass. On every edit, re-highlights the edited paragraph range (not the whole document).

**Patterns detected (regex-based):**

| Pattern | Style |
|---------|-------|
| `# Heading` | SF Pro 28px bold, extra padding |
| `## Heading` | SF Pro 21px semibold |
| `### Heading` | SF Pro 17px semibold |
| `**bold**` | Bold weight, syntax marks muted |
| `*italic*` | Italic, syntax marks muted |
| `~~strike~~` | Strikethrough, syntax marks muted |
| `` `code` `` | SF Mono, background pill |
| ```` ``` ```` blocks | SF Mono, background block |
| `[text](url)` | Blue text, URL muted |
| `- ` / `* ` / `1. ` | Muted marker |
| `> blockquote` | Left border (via paragraph style), muted |
| `---` | Horizontal rule (thin line via paragraph style) |
| `![[filename]]` | Replaced by embed attachment |

**Syntax mark muting:** The `**`, `*`, `` ` ``, `#` characters are rendered in a faint color (not hidden). This avoids the cursor-in-hidden-range issues that plagued the CM6 approach.

### 3. Rich Embeds (NSTextAttachment)

Lines matching `![[filename]]` are replaced with an `NSTextAttachment` containing a custom `NSView`. The attachment is a single character in the text storage, so cursor/selection/delete work natively.

**Embed types:**

- **Images** (jpg, png, gif, svg, webp, etc.): `NSImageView` loaded from the project folder via `portymcfolio://` scheme or direct file URL. Max height 400px, scales to content width.
- **Link files** (`link-{uid}.md`): Card view showing link icon + title + domain. Click opens URL in browser. Metadata read from the link file's YAML frontmatter.
- **Other files**: Badge view showing file icon + filename. Click opens in Finder.

Each embed has an X button (visible on hover) that removes the attachment and deletes the `![[]]` line from the text.

**Rebuild strategy:** After any text edit, scan for `![[...]]` lines that don't have attachments and add them. This runs on the edited range only, not the whole document.

### 4. Save Pipeline

```
textDidChange → debounce 1.5s → read frontmatter from disk → prepend to body → write file → call onSave
```

On project switch: cancel pending save immediately (no race condition because there's no async bridge hop).

### 5. Slash Commands

When the user types `/` at the beginning of a line or after whitespace:

1. Show an `NSPopover` anchored at the cursor position
2. Popover contains a filtered list of commands (same set as today: headings, lists, blocks, media, link, file)
3. Typing filters the list
4. Arrow keys navigate, Enter selects, Escape dismisses
5. Selection executes the command (insert markdown, open file picker, etc.)

### 6. Deleted Code

The following files/systems are removed entirely:

- `Editor/` directory (src/*.js, package.json, vite.config.js, node_modules)
- `PortyMcFolio/Editor/EditorBridge.swift`
- `PortyMcFolio/Editor/MediaSchemeHandler.swift`
- `PortyMcFolio/Editor/Resources/editor.bundle.js`
- `PortyMcFolio/Editor/Resources/editor.html`
- `PortyMcFolio/Editor/Resources/editor.css`
- `DropTargetWebView` class in EditorView.swift
- The `portymcfolio://` custom URL scheme handler
- The entire npm/Vite build step

### 7. Design Tokens

The editor uses the existing `DesignTokens` (DT) system for colors, typography, and spacing. Dark/light mode is handled automatically via `NSAppearance` -- no manual theme switching needed.

## Build Order

1. **Basic shell** -- MarkdownEditorView + NSTextView, load/save working, no highlighting
2. **Markdown highlighting** -- syntax coloring for all patterns
3. **Formatting shortcuts** -- Cmd+B, Cmd+I, etc.
4. **Rich embeds** -- NSTextAttachment for images, links, files
5. **Slash commands** -- NSPopover with command list
6. **Delete old code** -- remove WKWebView stack after new editor is verified

## Verification

- Open a project with existing markdown content -- renders with highlighting
- Type text -- cursor is always correctly positioned
- Cmd+B to bold -- wraps selection with `**`
- Drag image from gallery to editor -- inserts `![[image.png]]` at drop position, shows preview
- Switch projects rapidly -- no content corruption
- Toggle dark/light mode -- editor updates immediately
- Type `/` -- slash command popover appears
- All 52 existing tests still pass
