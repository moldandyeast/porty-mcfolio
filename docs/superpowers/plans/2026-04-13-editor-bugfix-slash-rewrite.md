# Editor Bug Fixes & Slash Command Rewrite — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all critical editor bugs and rewrite slash commands using CM6's built-in autocompletion so keyboard handling, positioning, and filtering all work correctly.

**Architecture:** Replace the custom `SlashCommandMenu` class + ViewPlugin with a `CompletionSource` fed to `autocompletion()`. Fix link cursor math in `keybindings.js`, media escaping in `EditorView.swift`, and video error handling in `media.js`.

**Tech Stack:** CodeMirror 6, `@codemirror/autocomplete@6.20.1` (already installed via `codemirror` umbrella), Swift/WKWebView

---

### Task 1: Rewrite commands.js — CM6 autocompletion source

**Files:**
- Rewrite: `Editor/src/commands.js`

- [ ] **Step 1: Replace entire file with autocompletion-based implementation**

Replace the contents of `Editor/src/commands.js` with:

```javascript
import { autocompletion, pickedCompletion, completionKeymap } from '@codemirror/autocomplete'
import { postRequestMediaPicker } from './bridge.js'

const headingsSection = { name: 'Headings', rank: 1 }
const listsSection = { name: 'Lists', rank: 2 }
const blocksSection = { name: 'Blocks', rank: 3 }
const mediaSection = { name: 'Media', rank: 4 }

const commandItems = [
  {
    label: 'Heading 1',
    icon: 'H1',
    section: headingsSection,
    apply: (view, completion, from, to) => {
      view.dispatch({
        changes: { from, to, insert: '# ' },
        selection: { anchor: from + 2 },
        annotations: pickedCompletion.of(completion),
      })
    },
  },
  {
    label: 'Heading 2',
    icon: 'H2',
    section: headingsSection,
    apply: (view, completion, from, to) => {
      view.dispatch({
        changes: { from, to, insert: '## ' },
        selection: { anchor: from + 3 },
        annotations: pickedCompletion.of(completion),
      })
    },
  },
  {
    label: 'Heading 3',
    icon: 'H3',
    section: headingsSection,
    apply: (view, completion, from, to) => {
      view.dispatch({
        changes: { from, to, insert: '### ' },
        selection: { anchor: from + 4 },
        annotations: pickedCompletion.of(completion),
      })
    },
  },
  {
    label: 'Bullet List',
    icon: '\u2022',
    section: listsSection,
    apply: (view, completion, from, to) => {
      view.dispatch({
        changes: { from, to, insert: '- ' },
        selection: { anchor: from + 2 },
        annotations: pickedCompletion.of(completion),
      })
    },
  },
  {
    label: 'Ordered List',
    icon: '1.',
    section: listsSection,
    apply: (view, completion, from, to) => {
      view.dispatch({
        changes: { from, to, insert: '1. ' },
        selection: { anchor: from + 3 },
        annotations: pickedCompletion.of(completion),
      })
    },
  },
  {
    label: 'Blockquote',
    icon: '\u275d',
    section: blocksSection,
    apply: (view, completion, from, to) => {
      view.dispatch({
        changes: { from, to, insert: '> ' },
        selection: { anchor: from + 2 },
        annotations: pickedCompletion.of(completion),
      })
    },
  },
  {
    label: 'Code Block',
    icon: '</>',
    section: blocksSection,
    apply: (view, completion, from, to) => {
      const insert = '```\n\n```'
      view.dispatch({
        changes: { from, to, insert },
        selection: { anchor: from + 4 },
        annotations: pickedCompletion.of(completion),
      })
    },
  },
  {
    label: 'Table',
    icon: '\u229e',
    section: blocksSection,
    apply: (view, completion, from, to) => {
      const insert = '| Column 1 | Column 2 | Column 3 |\n| --- | --- | --- |\n| | | |\n| | | |'
      view.dispatch({
        changes: { from, to, insert },
        selection: { anchor: from + insert.length },
        annotations: pickedCompletion.of(completion),
      })
    },
  },
  {
    label: 'Horizontal Rule',
    icon: '\u2014',
    section: blocksSection,
    apply: (view, completion, from, to) => {
      view.dispatch({
        changes: { from, to, insert: '---' },
        selection: { anchor: from + 3 },
        annotations: pickedCompletion.of(completion),
      })
    },
  },
  {
    label: 'Insert Media',
    icon: '\ud83d\uddbc',
    section: mediaSection,
    apply: (view, completion, from, to) => {
      view.dispatch({
        changes: { from, to, insert: '' },
        annotations: pickedCompletion.of(completion),
      })
      postRequestMediaPicker()
    },
  },
]

function slashCommandSource(context) {
  const match = context.matchBefore(/\/\w*/)
  if (!match) return null

  return {
    from: match.from,
    options: commandItems,
    validFor: /^\/\w*$/,
  }
}

function renderIcon(completion) {
  const el = document.createElement('span')
  el.className = 'slash-cmd-icon'
  el.textContent = completion.icon || ''
  return el
}

export { completionKeymap }

export const slashCommands = autocompletion({
  override: [slashCommandSource],
  icons: false,
  activateOnTyping: true,
  closeOnBlur: true,
  defaultKeymap: true,
  optionClass: () => 'slash-cmd-option',
  tooltipClass: () => 'slash-cmd-tooltip',
  addToOptions: [{
    render: renderIcon,
    position: 20,
  }],
})
```

- [ ] **Step 2: Verify file saved correctly**

Run: `head -5 Editor/src/commands.js`
Expected: Starts with `import { autocompletion, pickedCompletion, completionKeymap } from '@codemirror/autocomplete'`

---

### Task 2: Update index.js — wire new autocompletion extension

**Files:**
- Modify: `Editor/src/index.js`

- [ ] **Step 1: Update imports**

Replace the current import line:

```javascript
import { slashCommands } from './commands.js'
```

With:

```javascript
import { slashCommands, completionKeymap } from './commands.js'
```

- [ ] **Step 2: Add completionKeymap to keymap array**

Replace the keymap block:

```javascript
        keymap.of([
          ...markdownKeymap,
          ...defaultKeymap,
          ...historyKeymap,
          ...searchKeymap,
        ]),
```

With:

```javascript
        keymap.of([
          ...markdownKeymap,
          ...completionKeymap,
          ...defaultKeymap,
          ...historyKeymap,
          ...searchKeymap,
        ]),
```

`completionKeymap` must come before `defaultKeymap` so Enter/Arrow/Escape are intercepted by autocompletion when the menu is open.

- [ ] **Step 3: Verify no other references to old slash menu**

Run: `grep -n "SlashCommandMenu\|slash-menu\|ViewPlugin" Editor/src/commands.js`
Expected: No matches (old code fully removed)

---

### Task 3: Update CSS — remove old styles, add autocomplete overrides

**Files:**
- Modify: `PortyMcFolio/Editor/Resources/editor.css`

- [ ] **Step 1: Remove old slash menu CSS**

Remove the entire `/* ── Slash Command Menu ── */` section (lines 197–263 in current file), from the comment header through `.slash-menu-description`.

- [ ] **Step 2: Add autocompletion override styles**

Insert the following in place of the removed section:

```css
/* ── Slash Command Menu (CM6 Autocomplete) ──────────── */

.cm-tooltip.slash-cmd-tooltip {
  background: var(--bg-primary);
  border: 1px solid var(--border);
  border-radius: 10px;
  box-shadow: 0 4px 16px rgba(0,0,0,0.1);
  min-width: 240px;
  max-height: 320px;
  padding: 4px;
  font-family: -apple-system, BlinkMacSystemFont, sans-serif;
  animation: menuFadeIn 0.1s ease-out;
}

@media (prefers-color-scheme: dark) {
  .cm-tooltip.slash-cmd-tooltip {
    box-shadow: 0 4px 16px rgba(0,0,0,0.3);
  }
}

.cm-tooltip.slash-cmd-tooltip ul {
  margin: 0;
  padding: 0;
  list-style: none;
}

.cm-tooltip.slash-cmd-tooltip ul li {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 7px 10px;
  border-radius: 6px;
  cursor: pointer;
  transition: background 0.08s;
}

.cm-tooltip.slash-cmd-tooltip ul li[aria-selected="true"] {
  background: var(--bg-tertiary);
}

.cm-tooltip.slash-cmd-tooltip .cm-completionLabel {
  font-size: 13px;
  font-weight: 500;
  color: var(--text);
}

.cm-tooltip.slash-cmd-tooltip .cm-completionMatchedText {
  text-decoration: none;
  font-weight: 600;
}

.cm-tooltip.slash-cmd-tooltip .cm-completionDetail {
  font-size: 11px;
  color: var(--text-faint);
  margin-left: auto;
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

/* Hide default CM autocomplete icon slot */
.cm-tooltip.slash-cmd-tooltip .cm-completionIcon {
  display: none;
}

/* Section headers */
.cm-tooltip.slash-cmd-tooltip .cm-completionSection {
  padding: 4px 10px 2px;
  font-size: 10px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--text-faint);
}
```

---

### Task 4: Fix link cursor positions in keybindings.js

**Files:**
- Modify: `Editor/src/keybindings.js:77-95`

- [ ] **Step 1: Fix cursor with selected text**

In the `insertLink` function, change line 85:

```javascript
      selection: { anchor: from + selected.length + 3 },
```

To:

```javascript
      selection: { anchor: from + selected.length + 2 },
```

This places the cursor between `()` in `[text]()` instead of after `)`.

- [ ] **Step 2: Fix cursor with empty selection**

Change line 91:

```javascript
      selection: { anchor: from + 1 },
```

To:

```javascript
      selection: { anchor: from + 3 },
```

This places the cursor between `()` in `[]()` instead of inside `[]`.

---

### Task 5: Fix media file escaping in EditorView.swift

**Files:**
- Modify: `PortyMcFolio/Views/EditorView.swift:100-101`

- [ ] **Step 1: Replace string escaping with JSON serialization**

Replace these two lines:

```swift
                        let escaped = filename.replacingOccurrences(of: "'", with: "\\'")
                        webView.evaluateJavaScript("window.PortyEditor.insertMediaEmbed('\(escaped)')")
```

With:

```swift
                        if let jsonData = try? JSONSerialization.data(withJSONObject: filename),
                           let jsonString = String(data: jsonData, encoding: .utf8) {
                            webView.evaluateJavaScript("window.PortyEditor.insertMediaEmbed(\(jsonString))")
                        }
```

This properly handles filenames containing quotes, backslashes, newlines, and other special characters.

---

### Task 6: Add video error handling in media.js

**Files:**
- Modify: `Editor/src/markdown/media.js:43-48`

- [ ] **Step 1: Add onerror handler to video elements**

Replace the video creation block:

```javascript
    } else if (VIDEO_EXTS.includes(ext)) {
      const video = document.createElement('video')
      video.src = src
      video.controls = true
      video.preload = 'metadata'
      wrapper.appendChild(video)
```

With:

```javascript
    } else if (VIDEO_EXTS.includes(ext)) {
      const video = document.createElement('video')
      video.src = src
      video.controls = true
      video.preload = 'metadata'
      video.onerror = () => {
        wrapper.innerHTML = ''
        wrapper.appendChild(createBadge(this.filename))
      }
      wrapper.appendChild(video)
```

This matches the existing image error handling pattern — if the video fails to load, fall back to a file badge.

---

### Task 7: Build, verify, and commit

**Files:**
- Rebuild: `PortyMcFolio/Editor/Resources/editor.bundle.js`

- [ ] **Step 1: Build the editor bundle**

Run: `cd <repo>/Editor && npm run build`
Expected: `✓ built in ~500ms`, no errors

- [ ] **Step 2: Verify slash menu in browser preview**

1. Start preview server: `editor-test` on port 5199
2. Navigate to `/editor.html`
3. Click into editor, type `/`
4. Verify: autocomplete popup appears with command list
5. Check console for errors — expect none
6. Type `he` — verify filtering to Heading 1/2/3
7. Press Enter — verify `# ` is inserted and `/he` is removed
8. Type `/` again, press ArrowDown twice, press Enter — verify correct command executes

- [ ] **Step 3: Verify slash menu near viewport bottom**

1. Insert many newlines to push cursor near bottom
2. Type `/`
3. Verify: menu flips above cursor (CM6 handles this automatically)

- [ ] **Step 4: Verify link cursor positions**

1. Type `hello`, select it, press Cmd+Shift+K
2. Verify: `[hello]()` inserted with cursor between `(` and `)`
3. Press Escape, move to empty line, press Cmd+Shift+K
4. Verify: `[]()` inserted with cursor between `(` and `)`

- [ ] **Step 5: Commit all changes**

```bash
git add Editor/src/commands.js Editor/src/index.js Editor/src/keybindings.js Editor/src/markdown/media.js PortyMcFolio/Editor/Resources/editor.css PortyMcFolio/Views/EditorView.swift PortyMcFolio/Editor/Resources/editor.bundle.js
git commit -m "fix: rewrite slash commands with CM6 autocompletion, fix editor bugs

- Replace custom SlashCommandMenu with @codemirror/autocomplete
- Fix Enter/Arrow/Escape keyboard handling (was intercepted by defaultKeymap)
- Fix link cursor position (Cmd+K lands in URL parens)
- Fix media filename escaping (JSON serialization)
- Add video embed error handling (onerror fallback to badge)"
```
