# Native NSTextView Editor Rewrite — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the WKWebView/CodeMirror 6 editor with a native NSTextView that provides reliable cursor positioning, native drag-drop, and markdown syntax highlighting.

**Architecture:** NSViewRepresentable wrapping NSScrollView + NSTextView. Markdown highlighting via NSTextStorage delegate. Rich embeds via NSTextAttachment. Formatting via keyboard shortcut handlers. Save via debounced textDidChange.

**Tech Stack:** AppKit (NSTextView, NSTextStorage, NSTextAttachment, NSPopover), SwiftUI (NSViewRepresentable), existing FrontmatterParser and LinkItem services.

---

## File Structure

**New files:**
- `PortyMcFolio/Views/MarkdownEditorView.swift` — NSViewRepresentable shell, coordinator (load/save/project-switch), MarkdownTextView subclass
- `PortyMcFolio/Editor/MarkdownHighlighter.swift` — Regex-based syntax highlighting applied to NSTextStorage
- `PortyMcFolio/Editor/EmbedAttachment.swift` — NSTextAttachment subclass + custom NSView cells for image/link/file embeds
- `PortyMcFolio/Editor/SlashCommandPopover.swift` — NSPopover with filtered command list

**Modified files:**
- `PortyMcFolio/Views/ProjectDetailView.swift:30` — Replace `EditorView(readmeURL:)` with `MarkdownEditorView(readmeURL:)`

**Deleted files (final task):**
- `PortyMcFolio/Views/EditorView.swift`
- `PortyMcFolio/Editor/EditorBridge.swift`
- `PortyMcFolio/Editor/MediaSchemeHandler.swift`
- `PortyMcFolio/Editor/Resources/editor.bundle.js`
- `PortyMcFolio/Editor/Resources/editor.html`
- `PortyMcFolio/Editor/Resources/editor.css`

---

### Task 1: Basic Shell — Load, Edit, Save

**Files:**
- Create: `PortyMcFolio/Views/MarkdownEditorView.swift`
- Modify: `PortyMcFolio/Views/ProjectDetailView.swift:30`

This task creates a working plain-text markdown editor with load/save. No highlighting, no embeds. Just a native text view that opens README files and saves on edit.

- [ ] **Step 1: Create MarkdownEditorView.swift**

```swift
import SwiftUI
import AppKit

struct MarkdownEditorView: NSViewRepresentable {
    let readmeURL: URL
    var onSave: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(readmeURL: readmeURL, onSave: onSave)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = MarkdownTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 24)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        // Typography
        textView.font = NSFont.systemFont(ofSize: 15, weight: .regular)
        textView.textColor = NSColor.labelColor

        // Max content width centered
        textView.textContainer?.lineFragmentPadding = 32
        textView.textContainer?.widthTracksTextView = true

        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        scrollView.documentView = textView
        context.coordinator.loadContent()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onSave = onSave
        if context.coordinator.readmeURL != readmeURL {
            context.coordinator.readmeURL = readmeURL
            context.coordinator.loadContent()
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var readmeURL: URL
        var onSave: ((String) -> Void)?
        weak var textView: MarkdownTextView?
        private var saveTimer: Timer?
        private var isLoadingContent = false

        init(readmeURL: URL, onSave: ((String) -> Void)?) {
            self.readmeURL = readmeURL
            self.onSave = onSave
        }

        func loadContent() {
            guard let textView else { return }
            isLoadingContent = true
            saveTimer?.invalidate()

            let body: String
            do {
                let content = try String(contentsOf: readmeURL, encoding: .utf8)
                let parsed = try FrontmatterParser.parse(content)
                body = parsed.body
            } catch {
                body = ""
            }

            textView.string = body
            isLoadingContent = false
        }

        func textDidChange(_ notification: Notification) {
            guard !isLoadingContent else { return }
            saveTimer?.invalidate()
            saveTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                self?.saveContent()
            }
        }

        private func saveContent() {
            guard let textView else { return }
            let body = textView.string
            do {
                let currentContent = try String(contentsOf: readmeURL, encoding: .utf8)
                let parsed = try FrontmatterParser.parse(currentContent)
                let fullContent = FrontmatterParser.serialize(frontmatter: ParsedFrontmatter(
                    title: parsed.title,
                    date: parsed.date,
                    tags: parsed.tags,
                    client: parsed.client,
                    status: parsed.status,
                    body: body,
                    teaser: parsed.teaser
                ))
                try fullContent.write(to: readmeURL, atomically: true, encoding: .utf8)
                onSave?(fullContent)
            } catch {
                print("[MarkdownEditor] Save failed: \(error)")
            }
        }

        deinit {
            saveTimer?.invalidate()
        }
    }
}

// MARK: - MarkdownTextView

final class MarkdownTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }
}
```

- [ ] **Step 2: Wire into ProjectDetailView**

In `PortyMcFolio/Views/ProjectDetailView.swift`, replace line 30:

```swift
// Old:
EditorView(readmeURL: project.readmeURL) { _ in
    appState.refreshProjects()
}

// New:
MarkdownEditorView(readmeURL: project.readmeURL) { _ in
    appState.refreshProjects()
}
```

- [ ] **Step 3: Build and manually test**

Run: `xcodebuild -scheme PortyMcFolio -configuration Debug build`

Open the app, select a project, verify:
- Text loads from README (body only, no frontmatter)
- Cursor works correctly (click anywhere, type)
- Edits are saved (wait 1.5s, check file on disk)
- Switching projects loads the new content
- Undo/redo works (Cmd+Z, Cmd+Shift+Z)

- [ ] **Step 4: Run existing tests**

Run: `xcodebuild -scheme PortyMcFolio -configuration Debug test -destination 'platform=macOS'`

All 52 tests should pass (they don't test the editor UI directly).

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Views/MarkdownEditorView.swift PortyMcFolio/Views/ProjectDetailView.swift
git commit -m "feat(editor): native NSTextView shell with load/save"
```

---

### Task 2: Markdown Syntax Highlighting

**Files:**
- Create: `PortyMcFolio/Editor/MarkdownHighlighter.swift`
- Modify: `PortyMcFolio/Views/MarkdownEditorView.swift`

- [ ] **Step 1: Create MarkdownHighlighter.swift**

```swift
import AppKit

final class MarkdownHighlighter {

    // MARK: - Style Definitions

    private let baseFont = NSFont.systemFont(ofSize: 15, weight: .regular)
    private let monoFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private let syntaxColor = NSColor.tertiaryLabelColor

    private var headingFonts: [Int: NSFont] {
        [
            1: NSFont.systemFont(ofSize: 28, weight: .bold),
            2: NSFont.systemFont(ofSize: 21, weight: .semibold),
            3: NSFont.systemFont(ofSize: 17, weight: .semibold),
        ]
    }

    // MARK: - Regex Patterns

    private static let patterns: [(NSRegularExpression, String)] = {
        func re(_ pattern: String) -> NSRegularExpression {
            try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        }
        return [
            (re(#"^(#{1,3})\s(.+)$"#), "heading"),
            (re(#"\*\*(.+?)\*\*"#), "bold"),
            (re(#"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#), "italic"),
            (re(#"~~(.+?)~~"#), "strike"),
            (re(#"`([^`\n]+)`"#), "inlineCode"),
            (re(#"^```[\s\S]*?^```"#), "codeBlock"),
            (re(#"^(>\s.*)$"#), "blockquote"),
            (re(#"^(---|\*\*\*|___)\s*$"#), "hr"),
            (re(#"\[([^\]]+)\]\(([^\)]+)\)"#), "link"),
            (re(#"^(\s*[-*+]|\s*\d+\.)\s"#), "listMarker"),
            (re(#"^!\[\[.+\]\]\s*$"#), "embed"),
        ]
    }()

    // MARK: - Apply

    func highlight(_ textStorage: NSTextStorage, in editedRange: NSRange) {
        let string = textStorage.string as NSString
        // Expand range to cover full lines
        let lineRange = string.lineRange(for: editedRange)

        // Reset to base style
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
            .strikethroughStyle: 0,
            .paragraphStyle: NSParagraphStyle.default,
        ]
        textStorage.setAttributes(baseAttrs, range: lineRange)

        // Apply each pattern
        for (regex, kind) in Self.patterns {
            regex.enumerateMatches(in: string as String, range: lineRange) { match, _, _ in
                guard let match else { return }
                applyStyle(kind, match: match, textStorage: textStorage)
            }
        }
    }

    private func applyStyle(_ kind: String, match: NSTextCheckingResult, textStorage: NSTextStorage) {
        let full = match.range

        switch kind {
        case "heading":
            let markerRange = match.range(at: 1)
            let level = min(markerRange.length, 3)
            if let font = headingFonts[level] {
                textStorage.addAttribute(.font, value: font, range: full)
            }
            textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: markerRange)

        case "bold":
            textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 15, weight: .bold), range: full)
            // Mute the ** markers
            let start = NSRange(location: full.location, length: 2)
            let end = NSRange(location: full.location + full.length - 2, length: 2)
            textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: start)
            textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: end)

        case "italic":
            textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 15, weight: .regular).with(traits: .italicFont), range: full)
            let start = NSRange(location: full.location, length: 1)
            let end = NSRange(location: full.location + full.length - 1, length: 1)
            textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: start)
            textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: end)

        case "strike":
            textStorage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: full)
            textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: full)
            let start = NSRange(location: full.location, length: 2)
            let end = NSRange(location: full.location + full.length - 2, length: 2)
            textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: start)
            textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: end)

        case "inlineCode":
            textStorage.addAttribute(.font, value: monoFont, range: full)
            textStorage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: full)
            let start = NSRange(location: full.location, length: 1)
            let end = NSRange(location: full.location + full.length - 1, length: 1)
            textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: start)
            textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: end)

        case "codeBlock":
            textStorage.addAttribute(.font, value: monoFont, range: full)
            textStorage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: full)

        case "blockquote":
            textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: full)

        case "hr":
            textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: full)

        case "link":
            let textRange = match.range(at: 1)
            let urlRange = match.range(at: 2)
            textStorage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: textRange)
            textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: urlRange)

        case "listMarker":
            let markerRange = match.range(at: 1)
            textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: markerRange)

        case "embed":
            textStorage.addAttribute(.foregroundColor, value: syntaxColor, range: full)

        default:
            break
        }
    }
}

// MARK: - NSFont Helper

private extension NSFont {
    func with(traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
```

- [ ] **Step 2: Wire highlighter into MarkdownEditorView**

Add a `highlighter` property to the Coordinator and call it from `textDidChange` and `loadContent`:

In `MarkdownEditorView.swift`, add to the Coordinator class:

```swift
private let highlighter = MarkdownHighlighter()
```

Update `loadContent()` — after `textView.string = body`, add:

```swift
let fullRange = NSRange(location: 0, length: (body as NSString).length)
highlighter.highlight(textView.textStorage!, in: fullRange)
```

Update `textDidChange(_:)` — after the `guard !isLoadingContent` line, add:

```swift
if let textView, let textStorage = textView.textStorage {
    let editedRange = textStorage.editedRange
    if editedRange.location != NSNotFound {
        highlighter.highlight(textStorage, in: editedRange)
    }
}
```

- [ ] **Step 3: Build and manually test**

Run: `xcodebuild -scheme PortyMcFolio -configuration Debug build`

Open a project with existing markdown. Verify:
- Headings are large and bold, `#` marks are muted
- `**bold**` renders bold, `*italic*` renders italic
- `code` has monospace font and background
- Links show blue text
- List markers are muted
- Typing new markdown gets highlighted as you type

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Editor/MarkdownHighlighter.swift PortyMcFolio/Views/MarkdownEditorView.swift
git commit -m "feat(editor): markdown syntax highlighting"
```

---

### Task 3: Formatting Keyboard Shortcuts

**Files:**
- Modify: `PortyMcFolio/Views/MarkdownEditorView.swift`

- [ ] **Step 1: Add keyboard shortcut handling to MarkdownTextView**

Replace the `MarkdownTextView` class at the bottom of `MarkdownEditorView.swift`:

```swift
final class MarkdownTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else {
            super.keyDown(with: event)
            return
        }

        let shift = event.modifierFlags.contains(.shift)
        let char = event.charactersIgnoringModifiers ?? ""

        switch (char, shift) {
        case ("b", false): wrapSelection(before: "**", after: "**")
        case ("i", false): wrapSelection(before: "*", after: "*")
        case ("e", false): wrapSelection(before: "`", after: "`")
        case ("S", true), ("s", true): wrapSelection(before: "~~", after: "~~")
        case ("1", true): setHeading(level: 1)
        case ("2", true): setHeading(level: 2)
        case ("3", true): setHeading(level: 3)
        case ("K", true), ("k", true): insertMarkdownLink()
        default:
            super.keyDown(with: event)
        }
    }

    private func wrapSelection(before: String, after: String) {
        let range = selectedRange()
        let selected = (string as NSString).substring(with: range)

        // Toggle off if already wrapped
        if selected.hasPrefix(before) && selected.hasSuffix(after) {
            let inner = String(selected.dropFirst(before.count).dropLast(after.count))
            insertText(inner, replacementRange: range)
            setSelectedRange(NSRange(location: range.location, length: inner.count))
            return
        }

        let wrapped = before + selected + after
        insertText(wrapped, replacementRange: range)
        setSelectedRange(NSRange(location: range.location + before.count, length: selected.count))
    }

    private func setHeading(level: Int) {
        let range = selectedRange()
        let lineRange = (string as NSString).lineRange(for: NSRange(location: range.location, length: 0))
        let lineText = (string as NSString).substring(with: lineRange).trimmingCharacters(in: .newlines)

        let prefix = String(repeating: "#", count: level) + " "

        // Remove existing heading prefix
        if let match = lineText.range(of: #"^#{1,6}\s"#, options: .regularExpression) {
            let existing = String(lineText[match])
            if existing == prefix {
                // Same level — remove
                insertText(String(lineText.dropFirst(existing.count)), replacementRange: lineRange)
            } else {
                // Different level — replace
                let newText = prefix + lineText.dropFirst(existing.count)
                insertText(newText + "\n", replacementRange: lineRange)
            }
        } else {
            insertText(prefix + lineText + "\n", replacementRange: lineRange)
        }
    }

    private func insertMarkdownLink() {
        let range = selectedRange()
        let selected = (string as NSString).substring(with: range)

        if selected.isEmpty {
            insertText("[]()", replacementRange: range)
            setSelectedRange(NSRange(location: range.location + 1, length: 0))
        } else {
            let link = "[\(selected)]()"
            insertText(link, replacementRange: range)
            setSelectedRange(NSRange(location: range.location + selected.count + 3, length: 0))
        }
    }
}
```

- [ ] **Step 2: Build and manually test**

Run: `xcodebuild -scheme PortyMcFolio -configuration Debug build`

Test each shortcut:
- Select text, Cmd+B → wraps with `**`, Cmd+B again → unwraps
- Cmd+I → italic, Cmd+E → inline code
- Cmd+Shift+S → strikethrough
- Cmd+Shift+1/2/3 → heading levels
- Cmd+Shift+K → inserts `[]()`

- [ ] **Step 3: Commit**

```bash
git add PortyMcFolio/Views/MarkdownEditorView.swift
git commit -m "feat(editor): markdown formatting keyboard shortcuts"
```

---

### Task 4: Drag-Drop from Gallery

**Files:**
- Modify: `PortyMcFolio/Views/MarkdownEditorView.swift`

- [ ] **Step 1: Add drag-drop to MarkdownTextView**

Add to `MarkdownTextView` class, below the keyboard shortcut code:

```swift
    // MARK: - Drag & Drop

    private static let mediaExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "svg", "webp", "avif",
        "mp4", "webm", "ogg", "mov",
        "mp3", "wav", "aac", "m4a",
    ]

    /// Project folder URL, set by the coordinator after creation.
    var projectFolderURL: URL?

    override func awakeFromNib() {
        super.awakeFromNib()
        registerDragTypes()
    }

    func registerDragTypes() {
        registerForDraggedTypes([.fileURL, .URL])
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self]) else { return [] }
        return .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              let projectFolder = projectFolderURL else { return false }

        // Get the character position at the drop point
        let dropPoint = convert(sender.draggingLocation, from: nil)
        let dropIndex = characterIndexForInsertion(at: dropPoint)

        for url in urls where url.isFileURL {
            let projectPath = projectFolder.standardizedFileURL.path

            // Resolve relative path (copy file into project if external)
            let filename: String
            let filePath = url.standardizedFileURL.path
            if filePath.hasPrefix(projectPath + "/") {
                filename = String(filePath.dropFirst(projectPath.count + 1))
            } else {
                let dest = projectFolder.appendingPathComponent(url.lastPathComponent)
                if !FileManager.default.fileExists(atPath: dest.path) {
                    try? FileManager.default.copyItem(at: url, to: dest)
                }
                filename = url.lastPathComponent
            }

            let embed = "![[\(filename)]]"
            let line = (string as NSString).lineRange(for: NSRange(location: dropIndex, length: 0))
            let lineText = (string as NSString).substring(with: line).trimmingCharacters(in: .newlines)

            let insert: String
            let insertAt: Int
            if lineText.isEmpty {
                insert = embed + "\n"
                insertAt = line.location
            } else {
                insert = "\n" + embed + "\n"
                insertAt = line.location + line.length - 1  // before the newline
            }

            insertText(insert, replacementRange: NSRange(location: insertAt, length: 0))
        }
        return true
    }
```

- [ ] **Step 2: Set projectFolderURL from the coordinator**

In the coordinator's `loadContent()`, after setting `textView.string = body`, add:

```swift
textView.projectFolderURL = readmeURL.deletingLastPathComponent()
```

And in `makeNSView`, after `context.coordinator.textView = textView`, add:

```swift
textView.registerDragTypes()
```

- [ ] **Step 3: Build and manually test**

Drag a file from the gallery to the editor. Verify:
- `![[filename]]` is inserted at the drop position
- External files are copied into the project folder
- Files already in the project use relative paths

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Views/MarkdownEditorView.swift
git commit -m "feat(editor): native drag-drop with positional insert"
```

---

### Task 5: Rich Embed Attachments (Images)

**Files:**
- Create: `PortyMcFolio/Editor/EmbedAttachment.swift`
- Modify: `PortyMcFolio/Editor/MarkdownHighlighter.swift`

- [ ] **Step 1: Create EmbedAttachment.swift with image support**

```swift
import AppKit

final class ImageEmbedCell: NSTextAttachmentCell {
    private let imageView: NSImageView
    private let filename: String

    init(image: NSImage, filename: String) {
        self.filename = filename
        self.imageView = NSImageView(image: image)
        super.init()
        self.image = image
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func cellSize() -> NSSize {
        guard let image else { return .zero }
        let maxWidth: CGFloat = 660  // 720 - 2*32 padding
        let maxHeight: CGFloat = 400
        let imageSize = image.size
        let scale = min(maxWidth / imageSize.width, maxHeight / imageSize.height, 1.0)
        return NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        guard let image else { return }
        let radius: CGFloat = 6
        let path = NSBezierPath(roundedRect: cellFrame, xRadius: radius, yRadius: radius)
        path.addClip()
        image.draw(in: cellFrame, from: .zero, operation: .sourceOver, fraction: 1.0)
    }
}

enum EmbedAttachmentFactory {
    private static let imageExts: Set<String> = [
        "jpg", "jpeg", "png", "gif", "svg", "webp", "avif", "heic", "tiff"
    ]

    static func createAttachment(filename: String, projectFolder: URL) -> NSTextAttachment? {
        let ext = (filename as NSString).pathExtension.lowercased()

        if imageExts.contains(ext) {
            let fileURL = projectFolder.appendingPathComponent(filename)
            guard let image = NSImage(contentsOf: fileURL) else { return nil }
            let attachment = NSTextAttachment()
            attachment.attachmentCell = ImageEmbedCell(image: image, filename: filename)
            return attachment
        }

        // Non-image files: show as text badge for now (embed support can be extended later)
        return nil
    }
}
```

- [ ] **Step 2: Wire embed replacement into the highlighter**

In `MarkdownHighlighter.swift`, add a method and a property:

```swift
var projectFolderURL: URL?

func replaceEmbedsIfNeeded(_ textStorage: NSTextStorage) {
    guard let projectFolder = projectFolderURL else { return }
    let string = textStorage.string as NSString
    let fullRange = NSRange(location: 0, length: string.length)
    let regex = try! NSRegularExpression(pattern: #"^!\[\[(.+)\]\]\s*$"#, options: .anchorsMatchLines)

    // Work backwards so ranges don't shift
    let matches = regex.matches(in: string as String, range: fullRange).reversed()
    for match in matches {
        let filenameRange = match.range(at: 1)
        let filename = string.substring(with: filenameRange).trimmingCharacters(in: .whitespaces)

        // Skip if already replaced with an attachment
        var hasAttachment = false
        textStorage.enumerateAttribute(.attachment, in: match.range) { value, _, _ in
            if value != nil { hasAttachment = true }
        }
        if hasAttachment { continue }

        if let attachment = EmbedAttachmentFactory.createAttachment(filename: filename, projectFolder: projectFolder) {
            let attachString = NSAttributedString(attachment: attachment)
            textStorage.replaceCharacters(in: match.range, with: attachString)
        }
    }
}
```

Call `replaceEmbedsIfNeeded` from the coordinator's `loadContent()`, after the `highlight` call:

```swift
highlighter.projectFolderURL = readmeURL.deletingLastPathComponent()
highlighter.replaceEmbedsIfNeeded(textView.textStorage!)
```

- [ ] **Step 3: Build and manually test**

Open a project that has `![[image.png]]` lines in the README. Verify:
- Images render inline as rounded previews
- Non-image embeds remain as text
- Cursor works around image attachments

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Editor/EmbedAttachment.swift PortyMcFolio/Editor/MarkdownHighlighter.swift PortyMcFolio/Views/MarkdownEditorView.swift
git commit -m "feat(editor): inline image embed attachments"
```

---

### Task 6: Slash Command Popover

**Files:**
- Create: `PortyMcFolio/Editor/SlashCommandPopover.swift`
- Modify: `PortyMcFolio/Views/MarkdownEditorView.swift`

- [ ] **Step 1: Create SlashCommandPopover.swift**

```swift
import SwiftUI
import AppKit

struct SlashCommand: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let action: (NSTextView) -> Void
}

let slashCommands: [SlashCommand] = [
    SlashCommand(label: "Heading 1", icon: "textformat.size.larger") { tv in
        tv.insertText("# ", replacementRange: tv.selectedRange())
    },
    SlashCommand(label: "Heading 2", icon: "textformat.size") { tv in
        tv.insertText("## ", replacementRange: tv.selectedRange())
    },
    SlashCommand(label: "Heading 3", icon: "textformat.size.smaller") { tv in
        tv.insertText("### ", replacementRange: tv.selectedRange())
    },
    SlashCommand(label: "Bullet List", icon: "list.bullet") { tv in
        tv.insertText("- ", replacementRange: tv.selectedRange())
    },
    SlashCommand(label: "Numbered List", icon: "list.number") { tv in
        tv.insertText("1. ", replacementRange: tv.selectedRange())
    },
    SlashCommand(label: "Blockquote", icon: "text.quote") { tv in
        tv.insertText("> ", replacementRange: tv.selectedRange())
    },
    SlashCommand(label: "Code Block", icon: "chevron.left.forwardslash.chevron.right") { tv in
        tv.insertText("```\n\n```", replacementRange: tv.selectedRange())
    },
    SlashCommand(label: "Horizontal Rule", icon: "minus") { tv in
        tv.insertText("---\n", replacementRange: tv.selectedRange())
    },
]

final class SlashCommandController {
    private var popover: NSPopover?
    private weak var textView: NSTextView?
    private var slashRange: NSRange?

    func show(in textView: NSTextView, at range: NSRange) {
        self.textView = textView
        self.slashRange = range
        dismiss()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 220, height: 300)

        let view = SlashCommandListView(commands: slashCommands) { [weak self] command in
            self?.executeCommand(command)
        }
        popover.contentViewController = NSHostingController(rootView: view)

        // Position at the cursor
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y

        self.popover = popover
        popover.show(relativeTo: rect, of: textView, preferredEdge: .maxY)
    }

    func dismiss() {
        popover?.close()
        popover = nil
    }

    private func executeCommand(_ command: SlashCommand) {
        guard let textView, let slashRange else { return }
        dismiss()
        // Remove the "/" trigger character
        textView.insertText("", replacementRange: slashRange)
        command.action(textView)
    }
}

private struct SlashCommandListView: View {
    let commands: [SlashCommand]
    let onSelect: (SlashCommand) -> Void
    @State private var selected = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                    HStack(spacing: 8) {
                        Image(systemName: command.icon)
                            .frame(width: 24)
                            .foregroundStyle(.secondary)
                        Text(command.label)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(index == selected ? Color.accentColor.opacity(0.12) : .clear)
                    .cornerRadius(6)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(command) }
                }
            }
            .padding(4)
        }
    }
}
```

- [ ] **Step 2: Wire slash detection into the coordinator**

Add to the Coordinator class:

```swift
private let slashController = SlashCommandController()

func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
        slashController.dismiss()
        return false
    }
    return false
}
```

In `textDidChange(_:)`, add slash detection after the `isLoadingContent` guard:

```swift
// Slash command detection
if let textView {
    let pos = textView.selectedRange().location
    if pos > 0 {
        let charBefore = (textView.string as NSString).substring(with: NSRange(location: pos - 1, length: 1))
        if charBefore == "/" {
            // Check if at line start or after whitespace
            let isLineStart = pos == 1 || (textView.string as NSString).substring(with: NSRange(location: pos - 2, length: 1)) == "\n"
            let isAfterSpace = pos >= 2 && (textView.string as NSString).substring(with: NSRange(location: pos - 2, length: 1)) == " "
            if isLineStart || isAfterSpace {
                slashController.show(in: textView, at: NSRange(location: pos - 1, length: 1))
            }
        } else {
            slashController.dismiss()
        }
    }
}
```

- [ ] **Step 3: Build and manually test**

Type `/` at the start of a line. Verify:
- Popover appears with command list
- Clicking a command inserts the markdown
- The `/` trigger character is removed
- Pressing Escape dismisses the popover

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Editor/SlashCommandPopover.swift PortyMcFolio/Views/MarkdownEditorView.swift
git commit -m "feat(editor): slash command popover"
```

---

### Task 7: Delete Old WKWebView Editor Code

**Files:**
- Delete: `PortyMcFolio/Views/EditorView.swift`
- Delete: `PortyMcFolio/Editor/EditorBridge.swift`
- Delete: `PortyMcFolio/Editor/MediaSchemeHandler.swift`
- Delete: `PortyMcFolio/Editor/Resources/editor.bundle.js`
- Delete: `PortyMcFolio/Editor/Resources/editor.html`
- Delete: `PortyMcFolio/Editor/Resources/editor.css`
- Modify: `project.yml` or Xcode project — remove deleted file references

- [ ] **Step 1: Verify no remaining references to old editor**

```bash
grep -r "EditorView\|EditorBridge\|MediaSchemeHandler\|DropTargetWebView" PortyMcFolio/ --include="*.swift" | grep -v "MarkdownEditorView"
```

If any references remain outside the files being deleted, update them first.

- [ ] **Step 2: Delete the old files**

```bash
git rm PortyMcFolio/Views/EditorView.swift
git rm PortyMcFolio/Editor/EditorBridge.swift
git rm PortyMcFolio/Editor/MediaSchemeHandler.swift
git rm PortyMcFolio/Editor/Resources/editor.bundle.js
git rm PortyMcFolio/Editor/Resources/editor.html
git rm PortyMcFolio/Editor/Resources/editor.css
```

- [ ] **Step 3: Update the Xcode project to remove file references**

Remove the deleted files from the Xcode project's source and resource build phases. This can be done via `project.yml` and re-running XcodeGen, or manually in Xcode.

- [ ] **Step 4: Build and run full test suite**

```bash
xcodebuild -scheme PortyMcFolio -configuration Debug build
xcodebuild -scheme PortyMcFolio -configuration Debug test -destination 'platform=macOS'
```

All 52 tests must pass. The app must build and run without the old editor files.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(editor): delete old WKWebView/CodeMirror stack"
```

---

### Task 8: Final Verification

- [ ] **Step 1: Full end-to-end test**

Open the app and test every editor scenario:
- Open a project → text loads with syntax highlighting
- Type text → cursor is correctly positioned at all times
- Cmd+B, Cmd+I, Cmd+E → formatting works
- Cmd+Z → undo works
- Drag file from gallery → inserts at drop position
- Switch projects → content changes, no corruption
- Toggle dark/light mode → editor adapts immediately
- Type `/` → slash command popover appears
- Image embeds render inline
- Wait 1.5s after edit → file is saved (check with `cat`)

- [ ] **Step 2: Push**

```bash
git push origin dev/v1-implementation
```
