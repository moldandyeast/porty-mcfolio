import SwiftUI
import AppKit

// MARK: - MarkdownTextView

final class MarkdownTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }

    var projectFolderURL: URL?
    var maxContentWidth: CGFloat = 720

    private var isUpdatingLayout = false

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard !isUpdatingLayout else { return }
        isUpdatingLayout = true

        let padding: CGFloat = 32
        let availableWidth = newSize.width - padding * 2
        let contentWidth = min(availableWidth, maxContentWidth - padding * 2)
        let horizontalInset = max(padding, (newSize.width - contentWidth) / 2)

        textContainer?.containerSize = NSSize(width: max(contentWidth, 100), height: CGFloat.greatestFiniteMagnitude)
        textContainerInset = NSSize(width: horizontalInset, height: 48)

        isUpdatingLayout = false
    }

    // MARK: - Paste

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        let index = selectedRange().location

        // 1. File URLs from the clipboard.
        let fileURLs = ClipboardPaste.readFileURLs(from: pb)
        if !fileURLs.isEmpty {
            insertFileEmbeds(for: fileURLs, at: index)
            let label = fileURLs.count == 1
                ? "Added: \(fileURLs[0].lastPathComponent)"
                : "Added \(fileURLs.count) files"
            NotificationCenter.default.post(name: .showToast, object: label)
            return
        }

        // 2. Image data from the clipboard.
        if let imageData = ClipboardPaste.readImageData(from: pb) {
            insertImageDataEmbed(imageData, at: index)
            NotificationCenter.default.post(name: .showToast, object: "Image pasted")
            return
        }

        // 3. Plain text (preserved current behavior).
        if let str = pb.string(forType: .string) {
            insertText(str, replacementRange: selectedRange())
        }
    }

    // MARK: - Drag-Drop

    /// Background queue for resolving `NSFilePromiseReceiver` drops — drags
    /// where the source file doesn't yet exist as a `file://` URL on the
    /// pasteboard (screenshot floating thumbnail, browser image drags, Mail
    /// attachments, Photos.app library items).
    private lazy var filePromiseQueue: OperationQueue = {
        let q = OperationQueue()
        q.qualityOfService = .userInitiated
        return q
    }()

    func registerDragTypes() {
        let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes
            .map { NSPasteboard.PasteboardType($0) }
        let imageTypes = NSImage.imageTypes
            .map { NSPasteboard.PasteboardType($0) }
        registerForDraggedTypes([
            .fileURL,
            .URL,
            .tiff,
            .png,
            NSPasteboard.PasteboardType(rawValue: DragPayload.typeIdentifier),
        ] + promiseTypes + imageTypes)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pb = sender.draggingPasteboard
        if pb.canReadObject(forClasses: [NSURL.self, NSFilePromiseReceiver.self, NSImage.self], options: nil) {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        // Capture insertion index synchronously — promise resolution is async,
        // and the cursor/view state may shift before it completes.
        let dropPoint = convert(sender.draggingLocation, from: nil)
        let dropIndex = characterIndexForInsertion(at: dropPoint)

        // 1. In-process multi-file handoff (gallery drag inside the app).
        if let urls = MultiDragSession.active, !urls.isEmpty {
            MultiDragSession.active = nil
            return finishDrop(urls: urls, at: dropIndex)
        }

        let pb = sender.draggingPasteboard

        // 2. Real file URLs on the pasteboard (Finder drags of saved files).
        //    Filter to URLs that point to files that actually exist — some
        //    sources (screenshot thumbnails pre-save, browser in-flight images)
        //    put placeholder URLs on the pasteboard alongside image data.
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] {
            let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
            if !existing.isEmpty {
                return finishDrop(urls: existing, at: dropIndex)
            }
        }

        // 3. Raw image data on the pasteboard (screenshot floating thumbnail,
        //    browser image drags, drags from Preview / Photos). Mirrors the
        //    paste flow: save as `pasted-{timestamp}.png` in the project folder
        //    and embed.
        if let image = NSImage(pasteboard: pb),
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            if let savedURL = writeDroppedImage(png) {
                return finishDrop(urls: [savedURL], at: dropIndex)
            }
        }

        // 4. File promises — file doesn't yet exist on disk; receive it into
        //    the project folder, then embed on the main queue.
        guard let projectFolder = projectFolderURL else {
            return super.performDragOperation(sender)
        }

        var receivers: [NSFilePromiseReceiver] = []
        sender.enumerateDraggingItems(
            options: [],
            for: nil,
            classes: [NSFilePromiseReceiver.self],
            searchOptions: [:]
        ) { item, _, _ in
            if let r = item.item as? NSFilePromiseReceiver {
                receivers.append(r)
            }
        }
        guard !receivers.isEmpty else {
            return super.performDragOperation(sender)
        }

        let group = DispatchGroup()
        let collectedLock = NSLock()
        var collected: [URL] = []

        for receiver in receivers {
            group.enter()
            receiver.receivePromisedFiles(
                atDestination: projectFolder,
                options: [:],
                operationQueue: filePromiseQueue
            ) { url, error in
                if let error {
                    AppLogger.ui.error("MarkdownEditor file-promise drop failed: \(error.localizedDescription, privacy: .public)")
                } else {
                    collectedLock.lock()
                    collected.append(url)
                    collectedLock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            if collected.isEmpty {
                NotificationCenter.default.post(
                    name: .showToast,
                    object: "Couldn't receive dropped file(s)."
                )
                return
            }
            let safeIndex = min(dropIndex, self.textStorage?.length ?? 0)
            _ = self.finishDrop(urls: collected, at: safeIndex)
        }

        return true
    }

    @discardableResult
    private func finishDrop(urls: [URL], at index: Int) -> Bool {
        let inserted = insertFileEmbeds(for: urls, at: index)
        if inserted {
            let label = urls.count == 1
                ? "Added: \(urls[0].lastPathComponent)"
                : "Added \(urls.count) files"
            NotificationCenter.default.post(name: .showToast, object: label)
        }
        return inserted
    }

    /// Write dropped PNG bytes into the project folder as `pasted-{timestamp}.png`
    /// and return the destination URL. Returns nil if there's no project folder,
    /// the file already exists, or the write fails — caller treats nil as "drop
    /// not handled" and falls through to the next path.
    private func writeDroppedImage(_ data: Data) -> URL? {
        guard let projectFolder = projectFolderURL else { return nil }
        let filename = ClipboardPaste.pastedImageName()
        let dest = projectFolder.appendingPathComponent(filename)
        guard !FileManager.default.fileExists(atPath: dest.path) else { return nil }
        do {
            try data.write(to: dest)
            return dest
        } catch {
            AppLogger.ui.error("MarkdownEditor dropped-image write failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Embed insertion helpers (shared by paste and drop)

    /// For each URL: if it's already under `projectFolderURL`, embed by its project-relative
    /// path. Otherwise copy it into the project folder (skip if a file already exists at that
    /// destination) and embed by basename. Inserts the joined `![[…]]` lines at `index` with
    /// line-aware placement.
    @discardableResult
    private func insertFileEmbeds(for urls: [URL], at index: Int) -> Bool {
        guard let ts = textStorage else { return false }
        let fullText = ts.string as NSString

        var embedParts: [String] = []
        for url in urls {
            let fileURL = url.standardizedFileURL
            let filename: String
            if let projectFolder = projectFolderURL?.standardizedFileURL,
               fileURL.path.hasPrefix(projectFolder.path + "/") {
                filename = String(fileURL.path.dropFirst(projectFolder.path.count + 1))
            } else if let projectFolder = projectFolderURL {
                let dest = projectFolder.appendingPathComponent(fileURL.lastPathComponent)
                if !FileManager.default.fileExists(atPath: dest.path) {
                    do {
                        try FileManager.default.copyItem(at: fileURL, to: dest)
                    } catch {
                        AppLogger.ui.error("MarkdownEditor paste/drop copy failed for \(fileURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        NotificationCenter.default.post(
                            name: .showToast,
                            object: "Couldn't copy \(fileURL.lastPathComponent) into project."
                        )
                        continue
                    }
                }
                filename = fileURL.lastPathComponent
            } else {
                filename = fileURL.lastPathComponent
            }
            embedParts.append("![[\(filename)]]")
        }
        guard !embedParts.isEmpty else { return false }

        return insertEmbedText(embedParts.joined(separator: "\n"), at: index, fullText: fullText)
    }

    /// Write PNG bytes into the project folder as `pasted-{timestamp}.png` and insert its embed.
    /// No-ops if there is no `projectFolderURL`, if a file with that name already exists, or if
    /// the write fails — the editor convention is silent failure (drop behavior mirrors this).
    @discardableResult
    private func insertImageDataEmbed(_ data: Data, at index: Int) -> Bool {
        guard let projectFolder = projectFolderURL,
              let ts = textStorage else { return false }
        let filename = ClipboardPaste.pastedImageName()
        let dest = projectFolder.appendingPathComponent(filename)
        guard !FileManager.default.fileExists(atPath: dest.path) else { return false }
        do {
            try data.write(to: dest)
        } catch {
            return false
        }
        let fullText = ts.string as NSString
        return insertEmbedText("![[\(filename)]]", at: index, fullText: fullText)
    }

    /// Line-aware insertion: if the line at `index` is empty or whitespace-only, replace its
    /// content with `text + "\n"`; otherwise append `"\n" + text` at the line's trailing edge.
    @discardableResult
    private func insertEmbedText(_ text: String, at index: Int, fullText: NSString) -> Bool {
        let safeIndex = min(index, fullText.length)
        let lineRange = fullText.lineRange(for: NSRange(location: safeIndex, length: 0))
        let lineText = fullText.substring(with: lineRange).trimmingCharacters(in: .newlines)

        if lineText.trimmingCharacters(in: .whitespaces).isEmpty {
            insertText(text + "\n", replacementRange: NSRange(location: lineRange.location, length: max(0, lineText.count)))
        } else {
            insertText("\n" + text, replacementRange: NSRange(location: NSMaxRange(lineRange) - 1, length: 0))
        }
        return true
    }

    // MARK: - Key Handling

    private static let listRE = try! NSRegularExpression(pattern: #"^(\s*)([-*+]|\d+\.)\s"#)

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Only intercept shortcuts when we're the active text editor.
        // Without this, ⌘V / ⌘C / ⌘X etc. would fire here even when the user
        // has focus elsewhere (e.g. the gallery), causing double-paste bugs.
        guard window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let hasShift = event.modifierFlags.contains(.shift)
        let hasOption = event.modifierFlags.contains(.option)

        switch (chars, hasShift) {
        case ("c", false): copy(nil); return true
        case ("v", false): paste(nil); return true
        case ("x", false): cut(nil); return true
        case ("a", false): selectAll(nil); return true
        case ("z", false): undoManager?.undo(); return true
        case ("z", true): undoManager?.redo(); return true
        case ("b", false): wrapSelection(before: "**", after: "**"); return true
        case ("i", false): wrapSelection(before: "*", after: "*"); return true
        case ("e", false): wrapSelection(before: "`", after: "`"); return true
        case ("s", true): wrapSelection(before: "~~", after: "~~"); return true
        case ("1", false) where hasOption: setHeading(level: 1); return true
        case ("2", false) where hasOption: setHeading(level: 2); return true
        case ("3", false) where hasOption: setHeading(level: 3); return true
        case ("k", true): insertMarkdownLink(); return true
        case ("f", false): performFindPanelAction(nil); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 && !event.modifierFlags.contains(.command) {
            if handleListEnter() { return }
        }
        super.keyDown(with: event)
    }

    private func handleListEnter() -> Bool {
        let text = string as NSString
        let pos = selectedRange().location
        let lineRange = text.lineRange(for: NSRange(location: pos, length: 0))
        let lineText = text.substring(with: lineRange).trimmingCharacters(in: .newlines)
        let nsLine = lineText as NSString

        guard let match = Self.listRE.firstMatch(in: lineText, range: NSRange(location: 0, length: nsLine.length)) else {
            return false
        }
        let indent = nsLine.substring(with: match.range(at: 1))
        let marker = nsLine.substring(with: match.range(at: 2))
        let content = nsLine.substring(from: match.range.length)

        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            insertText("", replacementRange: NSRange(location: lineRange.location, length: lineText.count))
            return true
        }
        let newMarker = Int(marker.replacingOccurrences(of: ".", with: "")).map { "\($0 + 1)." } ?? marker
        insertText("\n\(indent)\(newMarker) ", replacementRange: NSRange(location: pos, length: 0))
        return true
    }

    // MARK: - Formatting Helpers

    private func wrapSelection(before: String, after: String) {
        guard let ts = textStorage else { return }
        let sel = selectedRange()
        let fullText = ts.string as NSString
        let selectedText = fullText.substring(with: sel)

        // Toggle off if already wrapped
        if selectedText.hasPrefix(before) && selectedText.hasSuffix(after) && selectedText.count >= before.count + after.count {
            let inner = String(selectedText.dropFirst(before.count).dropLast(after.count))
            insertText(inner, replacementRange: sel)
            setSelectedRange(NSRange(location: sel.location, length: (inner as NSString).length))
            return
        }
        // Toggle off if surrounding text has markers
        let bStart = sel.location - before.count
        let aEnd = sel.location + sel.length + after.count
        if bStart >= 0 && aEnd <= fullText.length {
            let pre = fullText.substring(with: NSRange(location: bStart, length: before.count))
            let post = fullText.substring(with: NSRange(location: sel.location + sel.length, length: after.count))
            if pre == before && post == after {
                let outerRange = NSRange(location: bStart, length: before.count + sel.length + after.count)
                insertText(fullText.substring(with: sel), replacementRange: outerRange)
                setSelectedRange(NSRange(location: bStart, length: sel.length))
                return
            }
        }
        insertText(before + selectedText + after, replacementRange: sel)
        setSelectedRange(NSRange(location: sel.location + before.count, length: (selectedText as NSString).length))
    }

    private func setHeading(level: Int) {
        guard let ts = textStorage else { return }
        let fullText = ts.string as NSString
        let lineRange = fullText.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        var contentEnd = lineRange.location + lineRange.length
        if contentEnd > lineRange.location && fullText.substring(with: NSRange(location: contentEnd - 1, length: 1)) == "\n" {
            contentEnd -= 1
        }
        let contentRange = NSRange(location: lineRange.location, length: contentEnd - lineRange.location)
        let line = fullText.substring(with: contentRange)
        let prefix = String(repeating: "#", count: level) + " "

        if let match = line.range(of: #"^#{1,6}\s"#, options: .regularExpression) {
            let existing = String(line[match])
            let rest = String(line[match.upperBound...])
            if existing == prefix {
                insertText(rest, replacementRange: contentRange)
            } else {
                insertText(prefix + rest, replacementRange: contentRange)
            }
        } else {
            insertText(prefix + line, replacementRange: contentRange)
        }
    }

    private func insertMarkdownLink() {
        let sel = selectedRange()
        if sel.length == 0 {
            insertText("[]()", replacementRange: sel)
            setSelectedRange(NSRange(location: sel.location + 1, length: 0))
        } else {
            let text = (textStorage!.string as NSString).substring(with: sel)
            insertText("[\(text)]()", replacementRange: sel)
            setSelectedRange(NSRange(location: sel.location + text.count + 3, length: 0))
        }
    }
}

// MARK: - MarkdownEditorView

extension Notification.Name {
    static let markdownFileDidChange = Notification.Name("markdownFileDidChange")
    static let markdownSaveNow = Notification.Name("markdownSaveNow")
    /// Ask AppState to show a transient toast. Posted by AppKit-layer views
    /// (e.g. MarkdownTextView) that can't reach AppState directly.
    /// `object` is the toast message `String`.
    static let showToast = Notification.Name("showToast")
}

struct MarkdownEditorView: NSViewRepresentable {
    let readmeURL: URL
    var onSave: ((String) -> Void)?
    var theme: Theme = .porty
    var appearanceSignal: Int = 0
    var autoSaveDelay: Double = 1.5

    func makeCoordinator() -> Coordinator {
        Coordinator(readmeURL: readmeURL, onSave: onSave, autoSaveDelay: autoSaveDelay)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let maxWidth: CGFloat = 720

        let textView = MarkdownTextView()
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
        textView.textColor = NSColor(theme.colors.textPrimary)
        textView.backgroundColor = NSColor(theme.colors.background)
        textView.insertionPointColor = NSColor(theme.colors.accent)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxContentWidth = maxWidth
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isContinuousSpellCheckingEnabled = false

        textView.delegate = context.coordinator
        scrollView.documentView = textView
        context.coordinator.textView = textView
        textView.registerDragTypes()
        context.coordinator.loadContent()
        context.coordinator.highlighter.applyTheme(theme)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.onSave = onSave
        if context.coordinator.readmeURL != readmeURL {
            // Flush any pending edits to the OLD URL before swapping, so we don't
            // lose unsaved changes when navigating between projects mid-edit.
            context.coordinator.flushPendingSave()
            context.coordinator.readmeURL = readmeURL
            context.coordinator.loadContent()
        }

        let themeKey = "\(theme.id.rawValue)-\(appearanceSignal)"
        if context.coordinator.lastThemeKey != themeKey {
            context.coordinator.lastThemeKey = themeKey
            if let textView = nsView.documentView as? MarkdownTextView {
                textView.textColor = NSColor(theme.colors.textPrimary)
                textView.backgroundColor = NSColor(theme.colors.background)
                textView.insertionPointColor = NSColor(theme.colors.accent)
                context.coordinator.highlighter.applyTheme(theme)
                if let ts = textView.textStorage, ts.length > 0 {
                    context.coordinator.highlighter.highlight(ts, in: NSRange(location: 0, length: ts.length))
                }
            } else {
                context.coordinator.highlighter.applyTheme(theme)
            }
        }

        context.coordinator.autoSaveDelay = autoSaveDelay
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        // Flush any pending debounced save BEFORE the coordinator deinits.
        // This runs on MainActor (guaranteed by NSViewRepresentable), so it
        // can safely touch NSTextView.string.
        coordinator.flushPendingSave()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var readmeURL: URL
        var onSave: ((String) -> Void)?
        weak var textView: MarkdownTextView?
        var debounceTimer: Timer?
        var autoSaveDelay: Double
        var lastThemeKey: String = ""
        private var highlightTimer: Timer?
        private var pendingHighlightRange: NSRange?
        private var isLoadingContent = false
        let highlighter = MarkdownHighlighter()
        /// mtime of `readmeURL` at last successful load or save. Used by
        /// `saveContent` to detect external writes between our read and write
        /// and retry — prevents clobbering reconciler-side favorites rewrites.
        private var lastKnownMTime: Date?

        init(readmeURL: URL, onSave: ((String) -> Void)?, autoSaveDelay: Double) {
            self.readmeURL = readmeURL
            self.onSave = onSave
            self.autoSaveDelay = autoSaveDelay
            super.init()
            NotificationCenter.default.addObserver(
                self, selector: #selector(handleExternalFileChange(_:)),
                name: .markdownFileDidChange, object: nil
            )
            NotificationCenter.default.addObserver(
                self, selector: #selector(handleSaveNow),
                name: .markdownSaveNow, object: nil
            )
        }

        @objc private func handleSaveNow() {
            debounceTimer?.invalidate()
            debounceTimer = nil
            saveContent()
        }

        /// Flush any pending debounced save to the current `readmeURL` immediately.
        /// Safe to call when no save is pending — it's a no-op in that case.
        func flushPendingSave() {
            guard debounceTimer?.isValid == true else { return }
            debounceTimer?.invalidate()
            debounceTimer = nil
            saveContent()
        }

        @objc private func handleExternalFileChange(_ notification: Notification) {
            // Only reload if the notification is for our file (or no specific file)
            if let url = notification.object as? URL, url != readmeURL { return }
            // Don't reload while we're saving (we'd overwrite our own changes)
            guard debounceTimer == nil else { return }
            loadContent()
        }

        func loadContent() {
            guard let textView else { return }
            isLoadingContent = true
            defer { isLoadingContent = false }

            let body: String
            do {
                let content = try String(contentsOf: readmeURL, encoding: .utf8)
                let parsed = try FrontmatterParser.parse(content)
                body = parsed.body
            } catch {
                body = ""
                let url = self.readmeURL
                AppLogger.ui.error("MarkdownEditor load failed for \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                let name = url.deletingPathExtension().lastPathComponent
                NotificationCenter.default.post(
                    name: .showToast,
                    object: "Couldn't load \(name). Editor opened blank — don't type here until you reload the project."
                )
            }
            textView.string = body
            textView.projectFolderURL = readmeURL.deletingLastPathComponent()
            highlighter.highlight(textView.textStorage!, in: NSRange(location: 0, length: (body as NSString).length))
            lastKnownMTime = (try? FileManager.default.attributesOfItem(atPath: readmeURL.path)[.modificationDate]) as? Date
        }

        func textDidChange(_ notification: Notification) {
            guard !isLoadingContent else { return }

            if let ts = textView?.textStorage, ts.editedRange.location != NSNotFound {
                // Fast path: base font/color only
                highlighter.applyBase(ts, in: ts.editedRange)

                // Slow path: debounced full regex highlight
                let editRange = ts.editedRange
                if let pending = pendingHighlightRange {
                    pendingHighlightRange = NSUnionRange(pending, editRange)
                } else {
                    pendingHighlightRange = editRange
                }
                highlightTimer?.invalidate()
                highlightTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
                    guard let self, let ts = self.textView?.textStorage,
                          let range = self.pendingHighlightRange else { return }
                    self.pendingHighlightRange = nil
                    self.highlighter.highlight(ts, in: range)
                }
            }

            debounceTimer?.invalidate()
            debounceTimer = Timer.scheduledTimer(withTimeInterval: autoSaveDelay, repeats: false) { [weak self] _ in
                self?.saveContent()
                // Clear the reference so `handleExternalFileChange`'s
                // `debounceTimer == nil` guard works after a natural fire.
                // Without this, external reloads stay permanently suppressed.
                self?.debounceTimer = nil
            }
        }

        private func saveContent() {
            guard let textView else { return }
            let body = textView.string

            // Retry on race: if the file's mtime changed between our read and the
            // moment we're about to write, another writer (e.g. ProjectReconciler's
            // favorites rewrite) modified it. Re-read and re-serialize, preserving
            // the user's typed body.
            for attempt in 0..<3 {
                do {
                    let preMTime = (try? FileManager.default.attributesOfItem(atPath: readmeURL.path)[.modificationDate]) as? Date
                    let currentContent = try String(contentsOf: readmeURL, encoding: .utf8)
                    var parsed = try FrontmatterParser.parse(currentContent)
                    parsed.body = body
                    let fullContent = FrontmatterParser.serialize(frontmatter: parsed)

                    // If the file changed since we read it, retry with fresh state.
                    let postMTime = (try? FileManager.default.attributesOfItem(atPath: readmeURL.path)[.modificationDate]) as? Date
                    if let preMTime, let postMTime, postMTime > preMTime {
                        continue
                    }

                    try fullContent.write(to: readmeURL, atomically: true, encoding: .utf8)
                    lastKnownMTime = (try? FileManager.default.attributesOfItem(atPath: readmeURL.path)[.modificationDate]) as? Date
                    onSave?(fullContent)
                    return
                } catch {
                    AppLogger.ui.error("MarkdownEditor save failed (attempt \(attempt + 1)): \(error.localizedDescription, privacy: .public)")
                    return
                }
            }
            AppLogger.ui.warning("MarkdownEditor save gave up after retries — file is being modified concurrently")
        }

        deinit {
            // Save flush happens in `MarkdownEditorView.dismantleNSView`
            // (MainActor), not here — deinit is not guaranteed main-thread.
            debounceTimer?.invalidate()
            highlightTimer?.invalidate()
            NotificationCenter.default.removeObserver(self)
        }
    }
}
