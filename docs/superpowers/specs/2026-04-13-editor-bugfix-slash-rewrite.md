# Editor Bug Fixes & Slash Command Rewrite

**Date:** 2026-04-13
**Status:** Spec
**Scope:** Fix critical editor bugs + rewrite slash commands using CM6 autocompletion

---

## Problem

The editor has several critical bugs making it essentially unusable:

1. **Slash menu keyboard handling broken** — Enter/Arrow keys never reach the slash menu because CodeMirror's `defaultKeymap` processes them first (ViewPlugin `eventHandlers` run at lower priority than keymaps). Pressing Enter inserts a newline instead of executing the selected command.
2. **Link insertion cursor misplaced** — Cmd+K with selected text lands cursor after `)` instead of inside `()` for the URL.
3. **Empty selection Cmd+K cursor wrong** — lands in `[]` instead of `()`.
4. **Media file escaping vulnerability** — filenames with quotes/special chars break JavaScript evaluation in Swift bridge.
5. **Video embeds have no error handling** — broken videos show empty player with no fallback.
6. **Slash menu clips at viewport edge** — fixed positioning but no flip logic in current implementation.

## Approach

### Slash Commands: Rewrite with CM6 Autocompletion

Replace the custom `SlashCommandMenu` class and ViewPlugin with CodeMirror 6's built-in `autocompletion()` extension (`@codemirror/autocomplete`, already installed at v6.20.1).

**Why:** The autocompletion framework handles keyboard interception at the correct priority level, viewport-aware positioning (auto-flips near edges), filtering, accessibility, and scroll tracking — all things the custom implementation gets wrong or doesn't handle.

#### Completion Source

```javascript
function slashCommandSource(context) {
  const match = context.matchBefore(/\/\w*/)
  if (!match && !context.explicit) return null

  return {
    from: match.from,
    options: commandItems,
    validFor: /^\/\w*$/
  }
}
```

The source triggers when the cursor is preceded by `/` optionally followed by word characters. CM6's built-in filtering narrows by typed query against `label`. The `validFor` regex allows reusing cached results while the user continues typing after `/`.

#### Command Items as Completion Objects

Each command becomes a `Completion` object:

```javascript
{
  label: "Heading 1",
  type: "keyword",          // For default icon styling (overridden by addToOptions)
  section: formattingSection,
  apply: (view, completion, from, to) => {
    view.dispatch({
      changes: { from, to, insert: "# " },
      selection: { anchor: from + 2 },
      annotations: pickedCompletion.of(completion)
    })
  }
}
```

The `apply` function handles:
- **Simple inserts** (Heading, List, Blockquote, HR): replace `/query` with markdown syntax, cursor at end
- **Multi-line inserts** (Code Block, Table): replace `/query` with template, cursor positioned inside
- **Actions** (Insert Media): clear `/query`, call `postRequestMediaPicker()`, no text insertion

#### Sections (Grouping)

Commands grouped into sections for visual organization:

| Section | Commands |
|---------|----------|
| Headings | Heading 1, Heading 2, Heading 3 |
| Lists | Bullet List, Ordered List |
| Blocks | Blockquote, Code Block, Table, Horizontal Rule |
| Media | Insert Media |

Sections use `CompletionSection` objects with `rank` for ordering.

#### Custom Icons via addToOptions

```javascript
autocompletion({
  override: [slashCommandSource],
  icons: false,
  addToOptions: [{
    render: (completion) => {
      const el = document.createElement('span')
      el.className = 'slash-cmd-icon'
      el.textContent = completion.icon  // stored as custom property
      return el
    },
    position: 20  // Before label (position 50)
  }]
})
```

Each completion carries an `icon` property (e.g., `"H1"`, `"•"`, `"</>"`, `"\u{1F5BC}"`). The `addToOptions` renderer creates a styled icon element.

#### Autocompletion Config

```javascript
autocompletion({
  override: [slashCommandSource],
  icons: false,
  activateOnTyping: true,
  closeOnBlur: true,
  defaultKeymap: true,
  optionClass: () => 'slash-cmd-option',
  tooltipClass: () => 'slash-cmd-tooltip'
})
```

Key settings:
- `override`: Only our slash source, no default completions
- `icons: false`: We render our own via `addToOptions`
- `defaultKeymap: true`: Enter, Arrow, Escape handled automatically at correct priority
- `closeOnBlur: true`: Dismiss on editor blur

#### CSS Styling

Override CM6 autocomplete tooltip classes to match the current design:

```css
/* Override autocomplete tooltip to match slash menu design */
.cm-tooltip.slash-cmd-tooltip {
  border: 1px solid var(--border);
  border-radius: 10px;
  box-shadow: 0 4px 16px rgba(0,0,0,0.1);
  min-width: 240px;
  max-height: 320px;
  padding: 4px;
  font-family: -apple-system, BlinkMacSystemFont, sans-serif;
  animation: menuFadeIn 0.1s ease-out;
}

.slash-cmd-icon {
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
```

The existing `.slash-menu*` CSS classes are removed entirely.

### Integration in index.js

```javascript
import { slashCommands } from './commands.js'
// slashCommands is now the autocompletion() extension

// In extensions array:
extensions: [
  markdown({ base: markdownLanguage }),
  history(),
  search(),
  slashCommands,  // autocompletion extension
  // ... rest of extensions
]
```

Import `completionKeymap` from `@codemirror/autocomplete` and add it to the keymap array:

```javascript
import { completionKeymap } from '@codemirror/autocomplete'

keymap.of([
  ...markdownKeymap,
  ...completionKeymap,
  ...defaultKeymap,
  ...historyKeymap,
  ...searchKeymap,
])
```

`completionKeymap` must come before `defaultKeymap` so Enter/Arrow/Escape are intercepted by the completion system when the menu is open.

---

## Other Bug Fixes

### Fix 1: Link Cursor Position (keybindings.js)

**With selected text** — inserts `[text]()`, cursor should land between `()` for URL entry:
- Inserted string: `[` + selected + `]()`
- Position of `(`: `from + 1 + selected.length + 1` = `from + selected.length + 2`
- Current code: `anchor: from + selected.length + 3` (one past `)`, wrong)
- Fix: `anchor: from + selected.length + 2`

**Empty selection** — inserts `[]()`, cursor should land between `()`:
- Current code: `anchor: from + 1` (inside `[]`, wrong)
- Fix: `anchor: from + 3` (inside `()`)

### Fix 2: Media File Escaping (EditorView.swift)

Replace single-quote escaping with proper JSON serialization:

```swift
// Current (vulnerable):
let escaped = filename.replacingOccurrences(of: "'", with: "\\'")
webView.evaluateJavaScript("window.PortyEditor.insertMediaEmbed('\(escaped)')")

// Fix:
guard let jsonData = try? JSONSerialization.data(withJSONObject: filename),
      let jsonString = String(data: jsonData, encoding: .utf8) else { return }
webView.evaluateJavaScript("window.PortyEditor.insertMediaEmbed(\(jsonString))")
```

### Fix 3: Video Error Handling (media.js)

Add `onerror` fallback to video elements, matching the existing image error pattern:

```javascript
video.onerror = () => {
  wrapper.innerHTML = ''
  wrapper.appendChild(createBadge(filename))
}
```

---

## Files Changed

| File | Change |
|------|--------|
| `Editor/src/commands.js` | **Rewrite**: custom menu → CM6 autocompletion source |
| `Editor/src/index.js` | Update imports, add `completionKeymap`, remove old `slashCommands` |
| `Editor/src/keybindings.js` | Fix link cursor offsets (2 lines) |
| `Editor/src/markdown/media.js` | Add video `onerror` handler |
| `PortyMcFolio/Editor/Resources/editor.css` | Remove `.slash-menu*` styles, add `.slash-cmd-*` overrides |
| `PortyMcFolio/Views/EditorView.swift` | Fix media filename escaping |
| `PortyMcFolio/Editor/Resources/editor.bundle.js` | Rebuilt |

## Files Deleted

None. `commands.js` is rewritten in place.

## Testing

1. **Slash menu opens** — type `/` at start of line, menu appears
2. **Filtering works** — type `/he`, only Heading options shown
3. **Enter selects** — press Enter, command inserts correctly, `/` query removed
4. **Arrow navigation** — ArrowDown/Up move selection in menu
5. **Escape dismisses** — press Escape, menu closes, `/` text remains
6. **Viewport flip** — type `/` near bottom of editor, menu flips upward
7. **Click selection** — click a menu item, command executes
8. **All commands insert correctly** — test each: H1-H3, Bullet, Ordered, Blockquote, Code Block, Table, HR, Media
9. **Code Block cursor** — cursor lands between the triple backticks
10. **Table cursor** — cursor lands at a useful position
11. **Media triggers picker** — Insert Media clears `/` and calls Swift bridge
12. **Link with selection** — select text, Cmd+K, cursor in `()`
13. **Link without selection** — Cmd+K, cursor in `()`
14. **Media escaping** — insert media with filename containing quotes
15. **Video error** — embed a non-existent video, see badge fallback
