import SwiftUI
import UniformTypeIdentifiers
import QuickLook

enum GalleryMode {
    case grid, list, links
}

private struct FolderDropTarget<Content: View>: View {
    let onDrop: ([NSItemProvider]) -> Bool
    @ViewBuilder var content: () -> Content
    @Environment(\.theme) var theme
    @State private var isTargeted: Bool = false

    var body: some View {
        content()
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.medium)
                    .stroke(theme.colors.accent, lineWidth: 1.5)
                    .opacity(isTargeted ? 1 : 0)
                    .padding(-2)
                    .allowsHitTesting(false)
            )
            .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { providers in
                onDrop(providers)
            }
    }
}

private struct FolderGridCell: View {
    let folderURL: URL
    let isSelected: Bool
    let isFocused: Bool
    let isCursor: Bool
    @Environment(\.theme) var theme
    @State private var isHovering: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Rectangle()
                    .fill(theme.colors.surfaceHover)
                Image(systemName: "folder.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(theme.colors.textSecondary)
            }
            .frame(width: 140, height: 100)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: DT.Radius.medium,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: DT.Radius.medium
                )
            )

            HStack {
                Text(folderURL.lastPathComponent)
                    .font(DT.Typography.caption)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DT.Spacing.sm)
            .padding(.vertical, DT.Spacing.xs)
            .frame(width: 140, alignment: .leading)
        }
        .background(
            isSelected ? theme.colors.accent.opacity(DT.Opacity.selection)
                : isHovering ? theme.colors.surfaceHover
                : theme.colors.surface,
            in: RoundedRectangle(cornerRadius: DT.Radius.medium)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.medium)
                .stroke(
                    isSelected ? theme.colors.accent : theme.colors.border,
                    lineWidth: isSelected ? 1.0 : 0.5
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.medium)
                .stroke(theme.colors.accent, lineWidth: 1)
                .opacity(isFocused && (isSelected || isCursor) ? 1 : 0)
                .padding(-2)
        )
        .dtShadow(isSelected ? DT.Shadow.card : DT.Shadow.Style(color: .clear, radius: 0, y: 0))
        .onHover { isHovering = $0 }
        .help(folderURL.lastPathComponent)
    }
}

struct GalleryView: View {
    let project: Project
    let mode: GalleryMode
    @Environment(\.theme) var theme
    @EnvironmentObject var appState: AppState

    @State private var links: [LinkItem] = []
    @State private var files: [URL] = []
    @State private var folders: [URL] = []
    @State private var selectedItems: Set<GallerySelection> = []
    @State private var cursor: GallerySelection? = nil
    @StateObject private var folderWatcher = FolderWatcher()

    private func isSelected(_ item: GallerySelection) -> Bool {
        selectedItems.contains(item)
    }

    private var selectedFileURLs: [URL] {
        selectedItems.compactMap {
            if case .file(let u) = $0 { return u } else { return nil }
        }
    }

    private var selectedFolderURLs: [URL] {
        selectedItems.compactMap {
            if case .folder(let u) = $0 { return u } else { return nil }
        }
    }

    private var selectedFileURL: URL? {
        if case .file(let url) = cursor, selectedItems.contains(.file(url)) { return url }
        return nil
    }
    private var selectedLinkID: String? {
        if case .link(let id) = cursor, selectedItems.contains(.link(id)) { return id }
        return nil
    }
    @State private var currentSubpath: [String] = []
    @State private var isShowingCleanup = false
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var cleanupStartIndex: Int = 0
    @State private var cutFileURL: URL?
    @State private var previewURL: URL?
    @State private var showDeleteConfirm = false
    @State private var fileToDelete: URL?
    @State private var showBatchDeleteConfirm = false
    @State private var folderToRename: URL?
    @State private var folderRenameText = ""
    @State private var composerText = ""
    @State private var composerShake = false
    @FocusState private var composerFocused: Bool
    @FocusState private var isGalleryFocused: Bool
    @State private var linkToEdit: LinkItem?
    @State private var sortKey: GallerySort.SortKey = .name
    @State private var sortAscending: Bool = true
    @State private var gridWidth: CGFloat = 0

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 180))
    ]

    private var currentFolderURL: URL {
        var url = project.folderURL
        for segment in currentSubpath {
            url = url.appendingPathComponent(segment)
        }
        return url
    }

    private var displayPrefix: String {
        "\(project.year)_\(Slug.underscoreFrom(project.title))_"
    }

    /// Inset that aligns the row divider with the leading edge of the filename
    /// column: outer horizontal padding + accent bar + gap + thumbnail + gap.
    private static let listDividerInset: CGFloat =
        DT.Spacing.lg + 2 + DT.Spacing.md + 32 + DT.Spacing.md

    private var isEmpty: Bool {
        files.isEmpty && folders.isEmpty
    }

    // MARK: - Sort persistence

    private static let sortDefaultsKey = "gallerySortKey"

    private func loadSort() {
        guard let raw = UserDefaults.standard.string(forKey: Self.sortDefaultsKey),
              let decoded = GallerySort.decode(raw: raw) else { return }
        sortKey = decoded.key
        sortAscending = decoded.ascending
    }

    private func persistSort() {
        UserDefaults.standard.set(
            GallerySort.encode(key: sortKey, ascending: sortAscending),
            forKey: Self.sortDefaultsKey
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Content
            if mode == .links {
                Group {
                    if links.isEmpty {
                        linksEmptyState
                            .contextMenu { galleryBackgroundMenu }
                    } else {
                        linksContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onDrop(of: [.fileURL, .url, .text, .image], isTargeted: nil) { providers in
                    handleDrop(providers: providers)
                }
                urlComposer
            } else if isEmpty {
                emptyState
                    .contextMenu { galleryBackgroundMenu }
            } else {
                ScrollView {
                    if mode == .grid {
                        gridContent
                    } else {
                        listContent
                    }
                }
                .onDrop(of: [.fileURL, .url, .text, .image], isTargeted: nil) { providers in
                    handleDrop(providers: providers)
                }
                .contextMenu { galleryBackgroundMenu }
            }

            // Bottom bar: breadcrumb + view toggle
            HStack(spacing: DT.Spacing.xs) {
                BreadcrumbBar(
                    projectName: project.title.isEmpty ? "Project" : project.title,
                    relativePath: currentSubpath,
                    currentFolderURL: currentFolderURL,
                    onNavigate: { index in
                        if index < 0 {
                            currentSubpath = []
                        } else {
                            currentSubpath = Array(currentSubpath.prefix(index + 1))
                        }
                        clearSelection()
                        scanProjectFolder()
                    },
                    onRenameCurrentFolder: currentSubpath.isEmpty ? nil : {
                        folderRenameText = currentSubpath.last ?? ""
                        folderToRename = currentFolderURL
                    }
                )
                .layoutPriority(0)

                HStack(spacing: DT.Spacing.xs) {
                    // Action buttons
                    galleryAction(icon: "doc.badge.plus", help: "Add File") {
                        showFilePicker()
                    }
                    galleryAction(icon: "folder.badge.plus", help: "New Folder") {
                        isCreatingFolder = true
                    }
                    .popover(isPresented: $isCreatingFolder) {
                        VStack(spacing: DT.Spacing.sm) {
                            TextField("Folder name", text: $newFolderName)
                                .textFieldStyle(.plain)
                                .font(DT.Typography.body)
                                .padding(.horizontal, DT.Spacing.sm)
                                .padding(.vertical, DT.Spacing.sm)
                                .background(theme.colors.backgroundAlt, in: RoundedRectangle(cornerRadius: DT.Radius.small))
                                .overlay(RoundedRectangle(cornerRadius: DT.Radius.small).stroke(theme.colors.border, lineWidth: 0.5))
                                .frame(width: 180)
                                .onSubmit { createFolder() }
                            HStack {
                                Button("Cancel") {
                                    newFolderName = ""
                                    isCreatingFolder = false
                                }
                                .font(DT.Typography.caption)
                                .buttonStyle(.plain)
                                .foregroundStyle(theme.colors.textSecondary)

                                Button {
                                    createFolder()
                                } label: {
                                    Text("Create")
                                        .font(DT.Typography.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(theme.colors.accentForeground)
                                        .padding(.horizontal, DT.Spacing.md)
                                        .padding(.vertical, DT.Spacing.xs)
                                        .background(theme.colors.accent, in: RoundedRectangle(cornerRadius: DT.Radius.small))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(DT.Spacing.md)
                    }
                    galleryAction(icon: "sparkles", help: "Clean Up") {
                        let idx: Int
                        if case .file(let url) = cursor, let i = files.firstIndex(of: url) {
                            idx = i
                        } else {
                            idx = 0
                        }
                        startCleanup(from: idx)
                    }

                    // Sort menu
                    Menu {
                        Section("Sort by") {
                            Button {
                                sortKey = .name
                            } label: {
                                if sortKey == .name { Image(systemName: "checkmark") }
                                Text("Name")
                            }
                            Button {
                                sortKey = .kind
                            } label: {
                                if sortKey == .kind { Image(systemName: "checkmark") }
                                Text("Kind")
                            }
                        }
                        Section("Order") {
                            Button {
                                sortAscending = true
                            } label: {
                                if sortAscending { Image(systemName: "checkmark") }
                                Text("Ascending")
                            }
                            Button {
                                sortAscending = false
                            } label: {
                                if !sortAscending { Image(systemName: "checkmark") }
                                Text("Descending")
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.colors.textTertiary)
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Sort")
                }
                .layoutPriority(1)
            }
            .padding(.leading, DT.Spacing.lg)
            .padding(.trailing, DT.Spacing.xl)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isGalleryFocused)
        // Keyboard handlers
        .onKeyPress(.space) { handleSpaceKey() }
        .onKeyPress(.return) { handleReturnKey() }
        .onKeyPress(.escape) {
            // Only consume ESC if we actually cleared something; otherwise
            // let it propagate so the project-detail ESC handler can fire
            // (go back to the project list).
            if !selectedItems.isEmpty {
                clearSelection()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(keys: [.upArrow], phases: .down) { key in
            if key.modifiers.contains(.command) {
                navigate(.first)
            } else {
                navigate(.up, extending: key.modifiers.contains(.shift))
            }
            return .handled
        }
        .onKeyPress(keys: [.downArrow], phases: .down) { key in
            if key.modifiers.contains(.command) {
                navigate(.last)
            } else {
                navigate(.down, extending: key.modifiers.contains(.shift))
            }
            return .handled
        }
        .onKeyPress(keys: [.leftArrow], phases: .down) { key in
            if mode == .list || mode == .links { return .ignored }
            navigate(.left, extending: key.modifiers.contains(.shift))
            return .handled
        }
        .onKeyPress(keys: [.rightArrow], phases: .down) { key in
            if mode == .list || mode == .links { return .ignored }
            navigate(.right, extending: key.modifiers.contains(.shift))
            return .handled
        }
        .onKeyPress(keys: [.delete], phases: .down) { key in
            guard key.modifiers.contains(.command), !selectedItems.isEmpty else { return .ignored }
            showBatchDeleteConfirm = true
            return .handled
        }
        .onKeyPress(keys: ["l"], phases: .down) { key in
            guard key.modifiers.isEmpty else { return .ignored }
            performBulkFavorite()
            return .handled
        }
        .onKeyPress(phases: .down) { keyPress in
            guard keyPress.modifiers.contains(.command) else { return .ignored }
            switch keyPress.characters {
            case "a":
                selectedItems = Set(navigableSequence)
                cursor = navigableSequence.last
                return .handled
            case "x":
                if case .file(let url) = cursor { cutFileURL = url }
                return .handled
            case "v":
                pasteFile()
                return .handled
            case "[":
                goUpOneFolder()
                return .handled
            default:
                return .ignored
            }
        }
        // FAB buttons removed — actions moved to toolbar
        .onAppear {
            loadSort()
            scanProjectFolder()
            consumePendingSelection()
            folderWatcher.watch(url: project.folderURL) {
                scanProjectFolder()
            }
            // Give keyboard focus to the gallery by default so ⌘V / ⌘X / ⌘[
            // and arrow-key navigation fire without requiring a first click.
            // The composer's own .onAppear in Links mode takes focus back for
            // typing URLs (runs after this via main-queue async).
            if mode != .links {
                DispatchQueue.main.async { isGalleryFocused = true }
            }
        }
        .onChange(of: mode) { _, newMode in
            if newMode != .links {
                DispatchQueue.main.async { isGalleryFocused = true }
            }
        }
        .onDisappear {
            folderWatcher.stop()
        }
        .onChange(of: sortKey) { _, _ in persistSort() }
        .onChange(of: sortAscending) { _, _ in persistSort() }
        .sheet(isPresented: $isShowingCleanup) {
            if !files.isEmpty {
                CleanupPopup(
                    project: project,
                    initialFiles: files,
                    existingFolders: allProjectFolders(),
                    isPresented: $isShowingCleanup,
                    startIndex: cleanupStartIndex,
                    onFileRenamed: { scanProjectFolder() },
                    onFileMoved: { oldRel, newRel in
                        updateReadmeReferences(oldRelative: oldRel, newRelative: newRel)
                    }
                )
            }
        }
        .sheet(item: $linkToEdit) { link in
            EditLinkSheet(
                link: link,
                projectFolderURL: project.folderURL,
                onSaved: { scanProjectFolder() }
            )
        }
        .sheet(isPresented: $showDeleteConfirm) {
            ConfirmationSheet(
                title: "Move to Trash?",
                confirmLabel: "Move to Trash",
                isDestructive: true,
                onConfirm: {
                    if let url = fileToDelete {
                        trashFile(url)
                    }
                }
            ) {
                if let url = fileToDelete {
                    Text("\"\(url.lastPathComponent)\" will be moved to the Trash.")
                        .font(DT.Typography.body)
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
        }
        .confirmationDialog(
            "Move \(selectedItems.count) items to Trash?",
            isPresented: $showBatchDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) { performBatchDelete() }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: Binding(
            get: { folderToRename != nil },
            set: { if !$0 { folderToRename = nil } }
        )) {
            RenameFolderSheet(
                name: $folderRenameText,
                onConfirm: { renameFolder() }
            )
        }
        .quickLookPreview($previewURL, in: files)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: DT.Spacing.sm) {
            Spacer()
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(.quaternary)
            Text("No files yet")
                .font(DT.Typography.headline)
                .foregroundStyle(theme.colors.textSecondary)
            Text("Drop files here or use the buttons below")
                .font(DT.Typography.caption)
                .foregroundStyle(theme.colors.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .text, .image], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - Keyboard handlers

    private func handleSpaceKey() -> KeyPress.Result {
        switch cursor {
        case .file(let url):
            previewURL = nil
            DispatchQueue.main.async { previewURL = url }
            return .handled
        case .link(let id):
            if let link = links.first(where: { $0.id == id }) {
                LinkPreviewPanel.shared.preview(url: link.url, title: link.title)
                return .handled
            }
            return .ignored
        case .folder, .none:
            return .ignored
        }
    }

    private func handleReturnKey() -> KeyPress.Result {
        // Never fire while the URL composer has focus — let its .onSubmit own
        // Enter so pasting a URL + pressing Enter adds the link cleanly.
        guard !composerFocused else { return .ignored }

        switch cursor {
        case .file(let url):
            if let index = files.firstIndex(of: url) {
                startCleanup(from: index)
                return .handled
            }
            return .ignored
        case .folder(let url):
            currentSubpath.append(url.lastPathComponent)
            clearSelection()
            scanProjectFolder()
            return .handled
        case .link(let id):
            if let link = links.first(where: { $0.id == id }) {
                linkToEdit = link
                return .handled
            }
            return .ignored
        case .none:
            return .ignored
        }
    }

    private func clearSelection() {
        selectedItems.removeAll()
        cursor = nil
        cutFileURL = nil
    }

    /// Applies Finder-style mouse-click semantics to a tap on `item`.
    /// Reads NSEvent.modifierFlags at the moment of the tap.
    private func handleTap(on item: GallerySelection) {
        let flags = NSEvent.modifierFlags

        if flags.contains(.command) {
            // Toggle; cursor always moves onto item regardless of toggle direction.
            if selectedItems.contains(item) {
                selectedItems.remove(item)
            } else {
                selectedItems.insert(item)
            }
            cursor = item
        } else if flags.contains(.shift), let anchor = cursor {
            let range = MultiSelectLogic.rangeBetween(anchor, item, in: navigableSequence)
            if !range.isEmpty {
                selectedItems = Set(range)
            } else {
                selectedItems = [item]
                cursor = item
            }
        } else {
            selectedItems = [item]
            cursor = item
        }
    }

    private func goUpOneFolder() {
        guard !currentSubpath.isEmpty else { return }
        currentSubpath.removeLast()
        clearSelection()
        scanProjectFolder()
    }

    // MARK: - Scan

    private func scanProjectFolder() {
        let fm = FileManager.default
        let folderURL = currentFolderURL
        guard let contents = try? fm.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var scannedLinks: [LinkItem] = []
        var scannedFiles: [URL] = []
        var scannedFolders: [URL] = []

        for url in contents {
            let name = url.lastPathComponent
            // Skip project file (new-style or legacy) and hidden files
            if name == "README.md" || name == "\(project.folderName).md" || name.hasPrefix(".") { continue }

            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

            if isDirectory {
                scannedFolders.append(url)
            } else if LinkItem.isLinkFile(name: name) {
                if let markdown = try? String(contentsOf: url, encoding: .utf8),
                   var link = try? LinkItem.parse(markdown: markdown) {
                    let uidFromName = String(name.dropFirst("link-".count).dropLast(".md".count))
                    link = LinkItem(
                        uid: uidFromName,
                        url: link.url,
                        title: link.title,
                        annotation: link.annotation,
                        date: link.date
                    )
                    scannedLinks.append(link)
                }
            } else {
                scannedFiles.append(url)
            }
        }

        links = scannedLinks.sorted { $0.date < $1.date }
        files = scannedFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }
        folders = scannedFolders.sorted { $0.lastPathComponent < $1.lastPathComponent }

        // Clean stale selection
        selectedItems = selectedItems.filter { item in
            switch item {
            case .file(let url): return files.contains(url)
            case .folder(let url): return folders.contains(url)
            case .link(let id): return links.contains(where: { $0.id == id })
            }
        }
        if let c = cursor, !selectedItems.contains(c) {
            cursor = nil
        }
        if let cut = cutFileURL, !FileManager.default.fileExists(atPath: cut.path) {
            cutFileURL = nil
        }
    }

    private func consumePendingSelection() {
        if let fileURL = appState.pendingFileSelection {
            let relativePath = fileURL.path.replacingOccurrences(
                of: project.folderURL.path + "/",
                with: ""
            )
            let components = relativePath.components(separatedBy: "/")

            if components.count > 1 {
                currentSubpath = Array(components.dropLast())
                scanProjectFolder()
            }

            selectedItems = [.file(fileURL)]
            cursor = .file(fileURL)
            appState.pendingFileSelection = nil
        }

        if let linkID = appState.pendingLinkID {
            appState.viewMode = .splitLinks
            selectedItems = [.link(linkID)]
            cursor = .link(linkID)
            appState.pendingLinkID = nil
        }
    }

    // MARK: - Links content

    private var linksContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(links) { link in
                    LinkCardView(link: link, projectFolderURL: project.folderURL)
                        .background(
                            isSelected(.link(link.id))
                                ? Color.accentColor.opacity(0.1)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: DT.Radius.medium)
                        )
                        .onHover { hovering in
                            guard hovering else { return }
                            selectedItems = [.link(link.id)]
                            cursor = .link(link.id)
                            // If the user isn't mid-typing a URL, move focus
                            // off the composer so Enter reaches the gallery's
                            // handler (opens Edit Link modal) instead of the
                            // composer's .onSubmit.
                            if composerText.isEmpty {
                                composerFocused = false
                                DispatchQueue.main.async { isGalleryFocused = true }
                            }
                        }
                        .onTapGesture {
                            if link.url.isSafeExternalScheme {
                                NSWorkspace.shared.open(link.url)
                            }
                        }
                        .contextMenu {
                            Button("Open in Browser") {
                                if link.url.isSafeExternalScheme {
                                    NSWorkspace.shared.open(link.url)
                                }
                            }
                            Button("Edit…") { linkToEdit = link }
                            Button("Copy URL") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(link.url.absoluteString, forType: .string)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                let linkFileURL = project.folderURL.appendingPathComponent(LinkItem.fileName(uid: link.uid))
                                fileToDelete = linkFileURL
                                showDeleteConfirm = true
                            }
                        }
                }
            }
            .padding(.leading, DT.Spacing.md)
            .padding(.trailing, DT.Spacing.xl)
            .padding(.vertical, DT.Spacing.sm)
        }
    }

    private var linksEmptyState: some View {
        VStack(spacing: DT.Spacing.md) {
            Spacer()
            Image(systemName: "link")
                .font(.system(size: 28))
                .foregroundStyle(theme.colors.textTertiary)
            Text("No links yet")
                .font(DT.Typography.body)
                .foregroundStyle(theme.colors.textSecondary)
            Text("Paste a URL below to save it.")
                .font(DT.Typography.caption)
                .foregroundStyle(theme.colors.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var urlComposer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(composerFocused ? theme.colors.accent.opacity(0.6) : theme.colors.border)
                .frame(height: composerFocused ? 1 : 0.5)
                .animation(.easeInOut(duration: 0.15), value: composerFocused)
            TextField("Paste a URL…", text: $composerText)
                .textFieldStyle(.plain)
                .font(DT.Typography.body)
                .foregroundStyle(theme.colors.textPrimary)
                .focused($composerFocused)
                .onSubmit { submitComposer() }
                .onPasteCommand(of: [.text]) { providers in
                    handleComposerPaste(providers: providers)
                }
                .padding(.horizontal, DT.Spacing.md)
                .padding(.vertical, DT.Spacing.sm)
                .background(composerShake ? theme.colors.error.opacity(DT.Opacity.selection) : Color.clear)
                .animation(.easeInOut(duration: 0.15), value: composerShake)
        }
        .onAppear {
            // Best-effort focus. If SwiftUI's @FocusState doesn't steal
            // responder from the editor's NSTextView (split view), the user
            // clicks the composer to focus it manually. The accent-tinted
            // divider above makes focus state visible.
            DispatchQueue.main.async { composerFocused = true }
        }
    }

    /// Handle a paste event targeted at the composer TextField. `.onPasteCommand`
    /// only fires when the TextField has focus, so Cmd+V pasted into the editor
    /// (or anywhere else) is never affected.
    private func handleComposerPaste(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { item, _ in
            let pasted: String?
            if let s = item as? String {
                pasted = s
            } else if let d = item as? Data, let s = String(data: d, encoding: .utf8) {
                pasted = s
            } else {
                pasted = nil
            }
            guard let text = pasted,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            DispatchQueue.main.async {
                composerText = text
                submitComposer()
            }
        }
    }

    private func submitComposer() {
        if tryAddLinkFromText(composerText) {
            composerText = ""
        } else {
            flashComposerError()
        }
    }

    /// Validate `text` as an http(s) URL and, if valid, persist it as a
    /// link-{uid}.md file in the project root, refresh the list, and async
    /// fetch the page title. Returns true on success.
    ///
    /// Shared by the composer's submit path, the gallery-level ⌘V fallback
    /// for plain-text URLs on the clipboard, and the drop handler when a URL
    /// or plain-text URL is dragged in.
    @discardableResult
    private func tryAddLinkFromText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = LinkItem.normalizeURL(trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return false
        }

        let uid = UID.generate()
        let link = LinkItem(
            uid: uid,
            url: url,
            title: "",
            annotation: "",
            date: Date()
        )
        let fileURL = project.folderURL.appendingPathComponent(LinkItem.fileName(uid: uid))
        do {
            try link.toMarkdown().write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            AppLogger.ui.error("GalleryView: failed to save link: \(error.localizedDescription, privacy: .public)")
            return false
        }

        // Ensure the list picks it up without waiting for FSEvent.
        scanProjectFolder()
        fetchAndApplyTitle(for: uid, url: url)
        // Toast only when the user can't see the new link in the current mode
        // (they won't see it in Grid/List; Links view renders it immediately).
        if mode != .links {
            let host = url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
            appState.showToast("Link added: \(host)")
        }
        return true
    }

    /// After a fresh link save, fetch the page title and write it back into the
    /// link file. The existing `FileWatcher → reconciler` path re-indexes the
    /// second write, and `scanProjectFolder()` on MainActor refreshes the UI.
    private func fetchAndApplyTitle(for uid: String, url: URL) {
        Task.detached { [project] in
            guard let title = await LinkTitleFetcher.fetch(url: url) else { return }

            let fileURL = project.folderURL.appendingPathComponent(LinkItem.fileName(uid: uid))
            guard let existing = try? String(contentsOf: fileURL, encoding: .utf8),
                  let parsed = try? LinkItem.parse(markdown: existing, overrideUID: uid) else {
                return
            }
            guard parsed.title.isEmpty else { return } // user may have set a title in the meantime; don't clobber

            let updated = LinkItem(
                uid: uid,
                url: parsed.url,
                title: title,
                annotation: parsed.annotation,
                date: parsed.date
            )
            do {
                try updated.toMarkdown().write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                AppLogger.ui.error("GalleryView: failed to write fetched title: \(error.localizedDescription, privacy: .public)")
                return
            }

            await MainActor.run { self.scanProjectFolder() }
        }
    }

    private func flashComposerError() {
        composerShake = true
        NSSound.beep()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            composerShake = false
        }
    }

    // MARK: - Sorted accessors

    private var sortedContent: GallerySort.Result {
        GallerySort.sort(files: files, folders: folders, by: sortKey, ascending: sortAscending)
    }

    /// Flat sequence of selectable items in current-view render order.
    /// Used for keyboard navigation. Links mode returns link ids; all other
    /// modes return folders-then-files as GallerySelection cases.
    private var navigableSequence: [GallerySelection] {
        if mode == .links {
            return links.map { .link($0.id) }
        }
        let content = sortedContent
        return content.folders.map { GallerySelection.folder($0) }
             + content.files.map { GallerySelection.file($0) }
    }

    /// Best-effort column count for 2-D keyboard navigation. Must match what
    /// SwiftUI's `.adaptive(minimum: 150)` grid actually renders.
    ///
    /// Derivation: `LazyVGrid` lays out columns with `DT.Spacing.lg` between them,
    /// and the grid's content has `.padding(DT.Spacing.lg)` horizontal on both sides.
    /// Available width for columns is `gridWidth - 2 * DT.Spacing.lg`. Each column
    /// takes at least `150 + DT.Spacing.lg` of extrinsic width (its minimum + the
    /// trailing gap), except the last column which has no trailing gap. Solving:
    ///   floor((available + spacing) / (min + spacing))
    /// matches SwiftUI's adaptive resolver for this configuration.
    private var gridColumnCount: Int {
        let available = gridWidth - 2 * DT.Spacing.lg
        let slot = 150.0 + DT.Spacing.lg
        let count = Int(((available + DT.Spacing.lg) / slot).rounded(.down))
        return max(1, count)
    }

    // MARK: - Grid content

    @ViewBuilder
    private var gridContent: some View {
        let content = sortedContent
        LazyVGrid(columns: columns, spacing: DT.Spacing.lg) {
            ForEach(content.folders, id: \.absoluteString) { folderURL in
                folderGridItem(folderURL)
            }
            ForEach(content.files, id: \.absoluteString) { fileURL in
                fileGridItem(fileURL)
            }
        }
        .padding(DT.Spacing.lg)
        .padding(.bottom, 48)
        .background(
            // Measure the grid's own width via an invisible backing layer.
            // Wrapping the grid in a GeometryReader directly breaks layout
            // inside a ScrollView (GR claims all available space, grid cells
            // stop receiving hit tests) — the .background form sizes itself
            // to the grid's frame and stays out of the layout and hit path.
            GeometryReader { geo in
                Color.clear
                    .onAppear { gridWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, newValue in gridWidth = newValue }
            }
        )
    }

    private func folderGridItem(_ folderURL: URL) -> some View {
        FolderDropTarget(
            onDrop: { providers in moveDroppedFiles(providers: providers, into: folderURL) }
        ) {
            FolderGridCell(
                folderURL: folderURL,
                isSelected: isSelected(.folder(folderURL)),
                isFocused: isGalleryFocused,
                isCursor: cursor == .folder(folderURL)
            )
            .onTapGesture(count: 2) {
                currentSubpath.append(folderURL.lastPathComponent)
                clearSelection()
                scanProjectFolder()
            }
            .onTapGesture(count: 1) {
                handleTap(on: .folder(folderURL))
            }
            .contextMenu { folderContextMenu(folderURL) }
        }
    }

    @ViewBuilder
    private func favoriteHeartButton(for fileURL: URL, isHovering: Bool) -> some View {
        let favorited = isFavorited(fileURL)
        Button {
            toggleFavorite(fileURL)
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 22, height: 22)
                Image(systemName: favorited ? "heart.fill" : "heart")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        favorited
                            ? theme.colors.accent
                            : theme.colors.textPrimary.opacity(isHovering ? 1.0 : 0.5)
                    )
                    // SF Symbols native bounce — fires whenever `favorited`
                    // flips so toggling in or out gets the same satisfying
                    // little pop. Pairs with the swap from heart → heart.fill.
                    .symbolEffect(.bounce, value: favorited)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .help(favorited ? "Remove from carousel" : "Add to carousel")
    }

    private func fileGridItem(_ fileURL: URL) -> some View {
        FileGridTileWithHeart(
            fileURL: fileURL,
            displayName: FilenameDisplay.display(name: fileURL.lastPathComponent, prefix: displayPrefix),
            isSelected: isSelected(.file(fileURL)),
            isTeaser: isTeaserFile(fileURL),
            isCut: cutFileURL == fileURL,
            isFocused: isGalleryFocused,
            isCursor: cursor == .file(fileURL),
            showHeart: MediaKind.isMedia(url: fileURL),
            dragCount: selectedItems.count,
            heartButton: { hovering in
                favoriteHeartButton(for: fileURL, isHovering: hovering)
            },
            onSelect: { handleTap(on: .file(fileURL)) },
            onOpen: { NSWorkspace.shared.open(fileURL) },
            onDragProvider: { makeFileDragProvider(for: fileURL) },
            fileContextMenu: { fileContextMenu(fileURL) }
        )
    }

    @ViewBuilder
    private func folderContextMenu(_ folderURL: URL) -> some View {
        Button("Open") {
            currentSubpath.append(folderURL.lastPathComponent)
            clearSelection()
            scanProjectFolder()
        }
        Button("Reveal in Finder") {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folderURL.path)
        }
        Divider()
        Button("Rename…") {
            folderRenameText = folderURL.lastPathComponent
            folderToRename = folderURL
        }
        Divider()
        Button("Delete", role: .destructive) {
            fileToDelete = folderURL
            showDeleteConfirm = true
        }
    }

    @ViewBuilder
    private func fileContextMenu(_ fileURL: URL) -> some View {
        Button("Set as Teaser") { setTeaser(fileURL) }
        Divider()
        Button("Cut") { cutFileURL = fileURL }
        if !folders.isEmpty {
            Menu("Move to…") {
                ForEach(folders, id: \.absoluteString) { folder in
                    Button(folder.lastPathComponent) {
                        moveFile(fileURL, into: folder)
                    }
                }
            }
        }
        Divider()
        Button("Delete", role: .destructive) {
            fileToDelete = fileURL
            showDeleteConfirm = true
        }
    }

    // MARK: - List content

    @ViewBuilder
    private var listContent: some View {
        let content = sortedContent
        LazyVStack(spacing: 0) {
            ForEach(content.folders, id: \.absoluteString) { folderURL in
                FolderDropTarget(
                    onDrop: { providers in moveDroppedFiles(providers: providers, into: folderURL) }
                ) {
                    GalleryListRow(
                        url: folderURL,
                        displayName: folderURL.lastPathComponent,
                        isFolder: true,
                        isTeaser: false,
                        isSelected: isSelected(.folder(folderURL)),
                        isCut: false,
                        isFocused: isGalleryFocused,
                        isCursor: cursor == .folder(folderURL)
                    )
                    .padding(.horizontal, DT.Spacing.lg)
                    .onTapGesture(count: 2) {
                        currentSubpath.append(folderURL.lastPathComponent)
                        clearSelection()
                        scanProjectFolder()
                    }
                    .onTapGesture(count: 1) {
                        handleTap(on: .folder(folderURL))
                    }
                    .contextMenu { folderContextMenu(folderURL) }
                }
                Divider().padding(.leading, Self.listDividerInset)
            }

            ForEach(content.files, id: \.absoluteString) { fileURL in
                GalleryListRow(
                    url: fileURL,
                    displayName: FilenameDisplay.display(name: fileURL.lastPathComponent, prefix: displayPrefix),
                    isFolder: false,
                    isTeaser: isTeaserFile(fileURL),
                    isSelected: isSelected(.file(fileURL)),
                    isCut: cutFileURL == fileURL,
                    isFocused: isGalleryFocused,
                    isCursor: cursor == .file(fileURL),
                    trailingAccessory: {
                        if MediaKind.isMedia(url: fileURL) {
                            FileRowHeartAccessory { hovering in
                                favoriteHeartButton(for: fileURL, isHovering: hovering)
                            }
                        }
                    }
                )
                .padding(.horizontal, DT.Spacing.lg)
                .onTapGesture(count: 2) { NSWorkspace.shared.open(fileURL) }
                .onTapGesture(count: 1) {
                    handleTap(on: .file(fileURL))
                }
                .onDrag({ makeFileDragProvider(for: fileURL) }, preview: {
                    if selectedItems.contains(.file(fileURL)) && selectedItems.count >= 2 {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 36))
                                .foregroundStyle(theme.colors.textSecondary)
                                .padding(16)
                                .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: 10))
                            Text("\(selectedItems.count)")
                                .font(.caption).bold()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(theme.colors.error, in: Capsule())
                                .offset(x: 8, y: -8)
                        }
                    } else {
                        EmptyView()
                    }
                })
                .contextMenu { fileContextMenu(fileURL) }
                Divider().padding(.leading, Self.listDividerInset)
            }
        }
        .padding(.bottom, 48)
    }

    // MARK: - FABs

    @ViewBuilder
    private var galleryBackgroundMenu: some View {
        Button { showFilePicker() } label: {
            Label("Import File\u{2026}", systemImage: "doc.badge.plus")
        }
        Button { isCreatingFolder = true } label: {
            Label("New Folder", systemImage: "folder.badge.plus")
        }
        if let url = selectedFileURL {
            Divider()
            Button(role: .destructive) {
                fileToDelete = url
                showDeleteConfirm = true
            } label: {
                Label("Delete \u{201C}\(url.lastPathComponent)\u{201D}", systemImage: "trash")
            }
        }
    }

    private func galleryAction(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.textTertiary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .iconButton()
        .help(help)
    }

    // MARK: - Arrow key navigation

    private enum NavDirection {
        case left, right, up, down, first, last
    }

    private func navigate(_ direction: NavDirection, extending: Bool = false) {
        let seq = navigableSequence
        guard !seq.isEmpty else { return }

        let currentIdx = cursor.flatMap { seq.firstIndex(of: $0) }

        let newIdx: Int
        switch direction {
        case .left:
            newIdx = currentIdx.map { max(0, $0 - 1) } ?? 0
        case .right:
            newIdx = currentIdx.map { min(seq.count - 1, $0 + 1) } ?? 0
        case .up:
            let step = mode == .grid ? gridColumnCount : 1
            newIdx = currentIdx.map { max(0, $0 - step) } ?? 0
        case .down:
            let step = mode == .grid ? gridColumnCount : 1
            newIdx = currentIdx.map { min(seq.count - 1, $0 + step) } ?? 0
        case .first:
            newIdx = 0
        case .last:
            newIdx = seq.count - 1
        }

        let newItem = seq[newIdx]
        cursor = newItem
        if extending {
            selectedItems.insert(newItem)
        } else {
            selectedItems = [newItem]
        }

        // If QuickLook is open on a file, follow the selection
        if previewURL != nil, case .file(let url) = newItem {
            previewURL = nil
            DispatchQueue.main.async { previewURL = url }
        }
    }

    // MARK: - Teaser helpers

    private func isTeaserFile(_ url: URL) -> Bool {
        guard !project.teaser.isEmpty else { return false }
        let teaserURL = project.folderURL.appendingPathComponent(project.teaser)
        return url.standardizedFileURL == teaserURL.standardizedFileURL
    }

    private func setTeaser(_ url: URL) {
        let rel = relativePath(for: url)
        guard let content = try? String(contentsOf: project.readmeURL, encoding: .utf8),
              var parsed = try? FrontmatterParser.parse(content) else { return }
        parsed.teaser = rel
        let updated = FrontmatterParser.serialize(frontmatter: parsed)
        do {
            try updated.write(to: project.readmeURL, atomically: true, encoding: .utf8)
        } catch {
            showAlert(title: "Can't Set Teaser", message: "Failed to save teaser: \(error.localizedDescription)")
            return
        }
        appState.notifyProjectFileChanged(uid: project.uid)
    }

    private func isFavorited(_ url: URL) -> Bool {
        project.favorites.contains(relativePath(for: url))
    }

    private func toggleFavorite(_ url: URL) {
        // Flush any pending editor save before we read the README, so the user's
        // typed-but-not-yet-saved edits are on disk when we rewrite frontmatter.
        NotificationCenter.default.post(name: .markdownSaveNow, object: nil)

        let rel = relativePath(for: url)
        // Defense: never write a path that wouldn't survive a re-parse. Guards
        // against symlinks / external moves mid-click producing absolute paths.
        guard FrontmatterParser.isValidFavoritePath(rel) else { return }
        guard let content = try? String(contentsOf: project.readmeURL, encoding: .utf8),
              var parsed = try? FrontmatterParser.parse(content) else { return }

        if let idx = parsed.favorites.firstIndex(of: rel) {
            parsed.favorites.remove(at: idx)
        } else {
            parsed.favorites.append(rel)
        }

        let updated = FrontmatterParser.serialize(frontmatter: parsed)
        do {
            try updated.write(to: project.readmeURL, atomically: true, encoding: .utf8)
        } catch {
            showAlert(title: "Can't Update Favorites",
                      message: "Failed to save: \(error.localizedDescription)")
            return
        }
        NotificationCenter.default.post(name: .markdownFileDidChange, object: project.readmeURL)
        appState.notifyProjectFileChanged(uid: project.uid)
    }

    private func performBulkFavorite() {
        let files = selectedFileURLs
        guard !files.isEmpty else { return }

        let action = MultiSelectLogic.favoriteToggleDirection(
            selected: files,
            projectRoot: project.folderURL,
            favorites: project.favorites
        )
        guard action != .noop else { return }

        // Flush any pending editor save before reading the README
        NotificationCenter.default.post(name: .markdownSaveNow, object: nil)

        let relPaths: [String] = files
            .map { relativePath(for: $0) }
            .filter { FrontmatterParser.isValidFavoritePath($0) }
        guard !relPaths.isEmpty else { return }

        guard let content = try? String(contentsOf: project.readmeURL, encoding: .utf8),
              var parsed = try? FrontmatterParser.parse(content) else { return }

        var favSet = Set(parsed.favorites)
        switch action {
        case .favoriteAll:   favSet.formUnion(relPaths)
        case .unfavoriteAll: favSet.subtract(relPaths)
        case .noop:          return
        }
        // Preserve existing order; append new favorites at end
        var newFavorites = parsed.favorites.filter { favSet.contains($0) }
        for rel in relPaths where !newFavorites.contains(rel) && favSet.contains(rel) {
            newFavorites.append(rel)
        }
        parsed.favorites = newFavorites

        let updated = FrontmatterParser.serialize(frontmatter: parsed)
        do {
            try updated.write(to: project.readmeURL, atomically: true, encoding: .utf8)
        } catch {
            showAlert(title: "Can't Update Favorites",
                      message: "Failed to save: \(error.localizedDescription)")
            return
        }
        NotificationCenter.default.post(name: .markdownFileDidChange, object: project.readmeURL)
        appState.notifyProjectFileChanged(uid: project.uid)

        let verb = (action == .favoriteAll) ? "Favorited" : "Unfavorited"
        NotificationCenter.default.post(name: .showToast, object: "\(verb) \(relPaths.count) items")
    }

    // MARK: - File operations

    /// Returns all subfolder paths in the project, relative to the project root.
    /// E.g. ["wireframes", "wireframes/v2", "photos", "photos/finals"]
    private func allProjectFolders() -> [String] {
        let fm = FileManager.default
        let root = project.folderURL.path + "/"
        guard let enumerator = fm.enumerator(
            at: project.folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [String] = []
        for case let url as URL in enumerator {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                let rel = url.path.replacingOccurrences(of: root, with: "")
                if !rel.isEmpty {
                    result.append(rel)
                }
            }
        }
        return result.sorted()
    }

    private func relativePath(for url: URL) -> String {
        url.path.replacingOccurrences(of: project.folderURL.path + "/", with: "")
    }

    private func updateReadmeReferences(oldRelative: String, newRelative: String) {
        let didRewrite: Bool
        do {
            didRewrite = try ProjectFileOps.updateReferences(in: project, from: oldRelative, to: newRelative)
        } catch {
            AppLogger.ui.error("GalleryView: updateReferences failed: \(error.localizedDescription, privacy: .public)")
            didRewrite = false
        }
        if didRewrite {
            NotificationCenter.default.post(name: .markdownFileDidChange, object: project.readmeURL)
            appState.notifyProjectFileChanged(uid: project.uid)
        }
    }

    private func moveFile(_ fileURL: URL, into folderURL: URL) {
        let dest = folderURL.appendingPathComponent(fileURL.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: dest.path) else {
            showAlert(title: "Can't Move", message: "A file named \"\(fileURL.lastPathComponent)\" already exists in \"\(folderURL.lastPathComponent)\".")
            return
        }
        let oldRel = relativePath(for: fileURL)
        do {
            try FileManager.default.moveItem(at: fileURL, to: dest)
        } catch {
            showAlert(title: "Can't Move", message: "Failed to move \"\(fileURL.lastPathComponent)\": \(error.localizedDescription)")
            return
        }
        updateReadmeReferences(oldRelative: oldRel, newRelative: relativePath(for: dest))
        if selectedFileURL == fileURL {
            selectedItems.remove(.file(fileURL))
            if cursor == .file(fileURL) { cursor = nil }
        }
        scanProjectFolder()
    }

    /// Builds an NSItemProvider for a file drag. When `fileURL` belongs to a
    /// multi-item selection, a private `DragPayload` entry rides alongside the
    /// primary `public.file-url` so our own drop targets can move every item
    /// in one go. External consumers (Finder, other apps) only see the
    /// primary URL.
    private func makeFileDragProvider(for fileURL: URL) -> NSItemProvider {
        let urlsForDrag: [URL] = {
            if selectedItems.contains(.file(fileURL)) && selectedItems.count >= 2 {
                return selectedItems.compactMap {
                    switch $0 {
                    case .file(let u), .folder(let u): return u
                    case .link: return nil
                    }
                }
            } else {
                selectedItems = [.file(fileURL)]
                cursor = .file(fileURL)
                return [fileURL]
            }
        }()

        // Stash for in-process drop handlers (see MultiDragSession).
        // A new drag always overwrites, so a cancelled drag won't leave
        // stale state affecting the next one.
        MultiDragSession.active = urlsForDrag.count > 1 ? urlsForDrag : nil

        let provider = NSItemProvider()
        // Primary (what Finder / other apps consume)
        provider.registerObject(urlsForDrag[0] as NSURL, visibility: .all)
        return provider
    }

    @discardableResult
    private func moveDroppedFiles(providers: [NSItemProvider], into folderURL: URL) -> Bool {
        // Fast path for internal multi-drag (see MultiDragSession).
        if let urls = MultiDragSession.active, !urls.isEmpty {
            MultiDragSession.active = nil
            performMove(urls: urls, into: folderURL)
            return true
        }

        // Split providers: those with a real file URL vs. those that only
        // expose image data (screenshot thumbnail, browser image drag).
        let urlProviders = providers.filter { $0.canLoadObject(ofClass: NSURL.self) }
        let imageOnlyProviders = providers.filter {
            !$0.canLoadObject(ofClass: NSURL.self) && $0.canLoadObject(ofClass: NSImage.self)
        }

        if !urlProviders.isEmpty {
            var urls: [URL] = []
            let group = DispatchGroup()
            for provider in urlProviders {
                group.enter()
                _ = provider.loadObject(ofClass: NSURL.self) { url, _ in
                    defer { group.leave() }
                    if let u = url as? URL { urls.append(u) }
                }
            }
            group.notify(queue: .main) {
                self.performMove(urls: urls, into: folderURL)
            }
        }

        for provider in imageOnlyProviders {
            _ = provider.loadObject(ofClass: NSImage.self) { obj, _ in
                guard let image = obj as? NSImage,
                      let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else { return }
                Task { @MainActor in
                    let filename = ClipboardPaste.pastedImageName()
                    let dest = folderURL.appendingPathComponent(filename)
                    guard !FileManager.default.fileExists(atPath: dest.path) else { return }
                    do {
                        try png.write(to: dest)
                        self.scanProjectFolder()
                        self.appState.showToast("Added: \(filename) to /\(folderURL.lastPathComponent)")
                    } catch {
                        self.showAlert(title: "Can't Add", message: "Failed to save image: \(error.localizedDescription)")
                    }
                }
            }
        }

        return !urlProviders.isEmpty || !imageOnlyProviders.isEmpty
    }

    private func performMove(urls: [URL], into folderURL: URL) {
        let validation = MultiSelectLogic.validateMove(items: urls, into: folderURL)
        switch validation {
        case .rejected(reason: .targetInSelection):
            NotificationCenter.default.post(name: .showToast, object: "Can't move a folder into itself.")
            return
        case .rejected(reason: .targetIsDescendantOfSelection):
            NotificationCenter.default.post(name: .showToast, object: "Can't move a folder into its own subtree.")
            return
        case .allowed:
            break
        }

        // Sources inside the project are moved (rearrange + README refs).
        // Sources outside (Finder drag from elsewhere) are copied (import).
        let projectPath = project.folderURL.standardizedFileURL.path + "/"

        var moved = 0
        var imported = 0
        var skipped = 0
        for src in urls {
            let dest = folderURL.appendingPathComponent(src.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                skipped += 1
                continue
            }
            let isInternal = src.standardizedFileURL.path.hasPrefix(projectPath)
            do {
                if isInternal {
                    let oldRel = relativePath(for: src)
                    try FileManager.default.moveItem(at: src, to: dest)
                    updateReadmeReferences(oldRelative: oldRel, newRelative: relativePath(for: dest))
                    moved += 1
                } else {
                    try FileManager.default.copyItem(at: src, to: dest)
                    imported += 1
                }
            } catch {
                skipped += 1
            }
        }

        let destLabel = "/\(folderURL.lastPathComponent)"
        let toast: String
        switch (moved, imported, skipped) {
        case (_, 0, 0):
            toast = "Moved \(moved) items to \(destLabel)"
        case (0, _, 0):
            toast = "Added \(imported) items to \(destLabel)"
        case (_, _, 0):
            toast = "Moved \(moved), added \(imported) to \(destLabel)"
        case (_, 0, _):
            toast = "Moved \(moved) to \(destLabel), \(skipped) skipped (name already exists)"
        case (0, _, _):
            toast = "Added \(imported) to \(destLabel), \(skipped) skipped (name already exists)"
        default:
            toast = "Moved \(moved), added \(imported) to \(destLabel), \(skipped) skipped"
        }
        NotificationCenter.default.post(name: .showToast, object: toast)
        if moved > 0 {
            clearSelection()
        }
        scanProjectFolder()
    }

    private func pasteInternalCutFile() {
        guard let source = cutFileURL else { return }
        let dest = currentFolderURL.appendingPathComponent(source.lastPathComponent)
        guard source != dest else { cutFileURL = nil; return }
        guard !FileManager.default.fileExists(atPath: dest.path) else {
            showAlert(title: "Can't Paste", message: "A file named \"\(source.lastPathComponent)\" already exists here.")
            return
        }
        let oldRel = relativePath(for: source)
        do {
            try FileManager.default.moveItem(at: source, to: dest)
        } catch {
            showAlert(title: "Can't Paste", message: "Failed to paste \"\(source.lastPathComponent)\": \(error.localizedDescription)")
            return
        }
        updateReadmeReferences(oldRelative: oldRel, newRelative: relativePath(for: dest))
        cutFileURL = nil
        selectedItems.removeAll()
        cursor = nil
        scanProjectFolder()
    }

    private func pasteFile() {
        if cutFileURL != nil {
            pasteInternalCutFile()
        } else {
            pasteFromClipboard()
        }
    }

    private func pasteFromClipboard() {
        let fileURLs = ClipboardPaste.readFileURLs()
        if !fileURLs.isEmpty {
            pasteFileURLsFromClipboard(fileURLs)
            return
        }
        if let imageData = ClipboardPaste.readImageData() {
            pasteImageDataFromClipboard(imageData)
            return
        }
        // Plain-text URL on the clipboard → save as a link.
        if let text = NSPasteboard.general.string(forType: .string),
           tryAddLinkFromText(text) {
            return
        }
        // Nothing on the clipboard we know how to paste; silent no-op.
    }

    private func pasteFileURLsFromClipboard(_ urls: [URL]) {
        var collisions: [String] = []
        var lastPasted: URL?

        for source in urls {
            let dest = currentFolderURL.appendingPathComponent(source.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                collisions.append(source.lastPathComponent)
                continue
            }
            do {
                try FileManager.default.copyItem(at: source, to: dest)
                lastPasted = dest
            } catch {
                showAlert(
                    title: "Can't Paste",
                    message: "Failed to paste \"\(source.lastPathComponent)\": \(error.localizedDescription)"
                )
                // Keep any prior successes visible; stop the loop on a hard failure.
                break
            }
        }

        if let last = lastPasted {
            scanProjectFolder()
            selectedItems = [.file(last)]
            cursor = .file(last)
            // Confirm only when the user can't see the result in the current mode.
            if mode == .links {
                let pastedCount = urls.count - collisions.count
                let label = pastedCount == 1
                    ? "Added: \(last.lastPathComponent)"
                    : "Added \(pastedCount) files"
                appState.showToast(label)
            }
        }

        if !collisions.isEmpty {
            let names = collisions.map { "\"\($0)\"" }.joined(separator: ", ")
            showAlert(
                title: "Some Files Not Pasted",
                message: "These files already exist here: \(names)"
            )
        }
    }

    private func pasteImageDataFromClipboard(_ data: Data) {
        let name = ClipboardPaste.pastedImageName()
        let dest = currentFolderURL.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: dest.path) else {
            showAlert(
                title: "Can't Paste",
                message: "A file named \"\(name)\" already exists here."
            )
            return
        }
        do {
            try data.write(to: dest, options: .atomic)
        } catch {
            showAlert(
                title: "Can't Paste",
                message: "Failed to write pasted image: \(error.localizedDescription)"
            )
            return
        }
        scanProjectFolder()
        selectedItems = [.file(dest)]
        cursor = .file(dest)
        if mode == .links {
            appState.showToast("Saved: \(name)")
        }
    }

    private func confirmDeleteSelected() {
        if let url = selectedFileURL {
            fileToDelete = url
            showDeleteConfirm = true
        }
    }

    private func performBatchDelete() {
        var trashed = 0
        var failed = 0
        var remainingFailures: Set<GallerySelection> = []

        for item in selectedItems {
            let url: URL
            switch item {
            case .file(let u), .folder(let u):
                url = u
            case .link:
                continue
            }
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                trashed += 1
            } catch {
                failed += 1
                remainingFailures.insert(item)
            }
        }

        if failed == 0 {
            NotificationCenter.default.post(name: .showToast, object: "\(trashed) items moved to Trash")
            clearSelection()
        } else {
            NotificationCenter.default.post(name: .showToast, object: "Moved \(trashed) of \(trashed + failed) items; \(failed) failed")
            selectedItems = remainingFailures
            cursor = remainingFailures.first
        }
        scanProjectFolder()
    }

    private func renameFolder() {
        guard let folder = folderToRename else { return }
        let newName = folderRenameText.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, newName != folder.lastPathComponent else {
            folderToRename = nil
            return
        }
        let dest = folder.deletingLastPathComponent().appendingPathComponent(newName)
        guard !FileManager.default.fileExists(atPath: dest.path) else {
            showAlert(title: "Can't Rename", message: "A folder named \"\(newName)\" already exists.")
            return
        }

        // Flush any pending editor save BEFORE reading the readme, so the user's
        // typed-but-not-yet-saved edits are on disk when we rewrite references.
        NotificationCenter.default.post(name: .markdownSaveNow, object: nil)

        let oldPrefix = relativePath(for: folder)
        do {
            try FileManager.default.moveItem(at: folder, to: dest)
        } catch {
            folderToRename = nil
            showAlert(
                title: "Can't Rename",
                message: "Failed to rename folder: \(error.localizedDescription)"
            )
            return
        }
        let newPrefix = relativePath(for: dest)

        if let content = try? String(contentsOf: project.readmeURL, encoding: .utf8),
           let parsed = try? FrontmatterParser.parse(content) {
            let (rewritten, changed) = FrontmatterParser.rewritingFolderRename(
                in: parsed,
                from: oldPrefix,
                to: newPrefix
            )
            if changed {
                let updated = FrontmatterParser.serialize(frontmatter: rewritten)
                do {
                    try updated.write(to: project.readmeURL, atomically: true, encoding: .utf8)
                    NotificationCenter.default.post(name: .markdownFileDidChange, object: project.readmeURL)
                    appState.notifyProjectFileChanged(uid: project.uid)
                } catch {
                    showAlert(
                        title: "Rename Partially Applied",
                        message: "Folder renamed, but couldn't update references in the project file: \(error.localizedDescription)"
                    )
                }
            }
        }

        // If we renamed the folder we're currently inside, update the breadcrumb path
        if let idx = currentSubpath.firstIndex(of: folder.lastPathComponent) {
            currentSubpath[idx] = newName
        }
        folderToRename = nil
        scanProjectFolder()
    }

    private func trashFile(_ url: URL) {
        let oldRel = relativePath(for: url)
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            showAlert(title: "Can't Delete", message: "Failed to move \"\(url.lastPathComponent)\" to Trash: \(error.localizedDescription)")
            return
        }
        // Clear embed references to deleted file
        updateReadmeReferences(oldRelative: oldRel, newRelative: "")
        if selectedFileURL == url {
            selectedItems.remove(.file(url))
            if cursor == .file(url) { cursor = nil }
        }
        if cutFileURL == url { cutFileURL = nil }
        scanProjectFolder()
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let folderURL = currentFolderURL.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            showAlert(title: "Can't Create Folder", message: "Failed to create \"\(name)\": \(error.localizedDescription)")
            return
        }
        newFolderName = ""
        isCreatingFolder = false
        scanProjectFolder()
    }

    private func startCleanup(from index: Int = 0) {
        cleanupStartIndex = index
        isShowingCleanup = true
    }

    private func showFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = currentFolderURL
        panel.message = "Select files or folders to add"
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        var failures: [(name: String, error: String)] = []
        for url in panel.urls {
            let dest = currentFolderURL.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                failures.append((url.lastPathComponent, "already exists here"))
                continue
            }
            do {
                try FileManager.default.copyItem(at: url, to: dest)
            } catch {
                failures.append((url.lastPathComponent, error.localizedDescription))
            }
        }
        if !failures.isEmpty {
            let summary = failures.map { "\u{2022} \($0.name): \($0.error)" }.joined(separator: "\n")
            showAlert(title: "Some Files Were Not Added", message: summary)
        }
        scanProjectFolder()
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    guard let data = item as? Data,
                          let urlString = String(data: data, encoding: .utf8),
                          let sourceURL = URL(string: urlString) else { return }
                    Task { @MainActor in
                        let destURL = self.currentFolderURL.appendingPathComponent(sourceURL.lastPathComponent)
                        var copied = false
                        if FileManager.default.fileExists(atPath: destURL.path) {
                            self.showAlert(title: "Can't Add", message: "A file named \"\(sourceURL.lastPathComponent)\" already exists here.")
                        } else {
                            do {
                                try FileManager.default.copyItem(at: sourceURL, to: destURL)
                                copied = true
                            } catch {
                                self.showAlert(title: "Can't Add", message: "Failed to add \"\(sourceURL.lastPathComponent)\": \(error.localizedDescription)")
                            }
                        }
                        self.scanProjectFolder()
                        if copied && self.mode == .links {
                            self.appState.showToast("Added: \(sourceURL.lastPathComponent)")
                        }
                    }
                }
                handled = true
            } else if provider.hasItemConformingToTypeIdentifier("public.url") {
                provider.loadItem(forTypeIdentifier: "public.url", options: nil) { item, _ in
                    let text: String?
                    if let data = item as? Data {
                        text = String(data: data, encoding: .utf8)
                    } else if let s = item as? String {
                        text = s
                    } else if let url = item as? URL {
                        text = url.absoluteString
                    } else {
                        text = nil
                    }
                    guard let text else { return }
                    Task { @MainActor in
                        _ = self.tryAddLinkFromText(text)
                    }
                }
                handled = true
            } else if provider.hasItemConformingToTypeIdentifier("public.plain-text") {
                provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { item, _ in
                    let text: String?
                    if let data = item as? Data {
                        text = String(data: data, encoding: .utf8)
                    } else if let s = item as? String {
                        text = s
                    } else {
                        text = nil
                    }
                    guard let text else { return }
                    Task { @MainActor in
                        _ = self.tryAddLinkFromText(text)
                    }
                }
                handled = true
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                // Raw image data (screenshot floating thumbnail, browser image
                // drag, Photos.app, etc.) — no public.file-url on the
                // pasteboard. Save the PNG bytes into the current folder.
                let destFolder = self.currentFolderURL
                _ = provider.loadObject(ofClass: NSImage.self) { obj, _ in
                    guard let image = obj as? NSImage,
                          let tiff = image.tiffRepresentation,
                          let rep = NSBitmapImageRep(data: tiff),
                          let png = rep.representation(using: .png, properties: [:]) else { return }
                    Task { @MainActor in
                        let filename = ClipboardPaste.pastedImageName()
                        let dest = destFolder.appendingPathComponent(filename)
                        guard !FileManager.default.fileExists(atPath: dest.path) else { return }
                        do {
                            try png.write(to: dest)
                            self.scanProjectFolder()
                            self.appState.showToast("Added: \(filename)")
                        } catch {
                            self.showAlert(title: "Can't Add", message: "Failed to save image: \(error.localizedDescription)")
                        }
                    }
                }
                handled = true
            }
        }
        return handled
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

// MARK: - FileGridTileWithHeart

/// Wraps `GalleryItemView` with a hover-aware heart overlay and keeps
/// the original tap / drag / context gestures attached to the tile.
/// The heart's `Button` naturally wins hit-test precedence over the
/// tile's tap gestures because it's the topmost layer in the ZStack.
private struct FileGridTileWithHeart<HeartButton: View, FileMenu: View>: View {
    let fileURL: URL
    let displayName: String
    let isSelected: Bool
    let isTeaser: Bool
    let isCut: Bool
    let isFocused: Bool
    let isCursor: Bool
    let showHeart: Bool
    /// Total number of selected items at the moment a drag begins. When ≥ 2
    /// and this tile is part of the selection, a count badge is shown in the
    /// drag preview.
    let dragCount: Int
    @ViewBuilder let heartButton: (_ isHovering: Bool) -> HeartButton
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onDragProvider: () -> NSItemProvider
    @ViewBuilder let fileContextMenu: () -> FileMenu

    @Environment(\.theme) private var theme
    @State private var isHovering: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GalleryItemView(
                fileURL: fileURL,
                displayName: displayName,
                isSelected: isSelected,
                isTeaser: isTeaser,
                isCut: isCut,
                isFocused: isFocused,
                isCursor: isCursor
            )

            if showHeart {
                heartButton(isHovering)
                    .padding(6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen() }
        .onTapGesture(count: 1) { onSelect() }
        .onDrag(onDragProvider, preview: {
            if isSelected && dragCount >= 2 {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 36))
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(16)
                        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: 10))
                    Text("\(dragCount)")
                        .font(.caption).bold()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(theme.colors.error, in: Capsule())
                        .offset(x: 8, y: -8)
                }
            } else {
                EmptyView()
            }
        })
        .contextMenu { fileContextMenu() }
        .onHover { hovering in isHovering = hovering }
    }
}

// MARK: - FileRowHeartAccessory

/// Owns hover state for the heart button in list-mode media rows.
/// Renders the heart and forwards `isHovering` into the button closure
/// so the outline brightens on pointer entry — consistent with grid mode.
private struct FileRowHeartAccessory<HeartButton: View>: View {
    @ViewBuilder let heartButton: (_ isHovering: Bool) -> HeartButton
    @State private var isHovering: Bool = false

    var body: some View {
        heartButton(isHovering)
            .onHover { hovering in isHovering = hovering }
    }
}

// MARK: - FolderWatcher

private final class FolderWatcher: ObservableObject {
    private var source: DispatchSourceFileSystemObject?

    func watch(url: URL, onChange: @escaping () -> Void) {
        stop()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { onChange() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit { stop() }
}
