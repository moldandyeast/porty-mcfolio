import SwiftUI

/// Toolbar chip used for clickable metadata (client, tag) in the title row.
/// Brightens the text to primary on hover so the user knows it's clickable —
/// the original inline buttons rendered as flat tertiary text with no affordance.
private struct ToolbarChipButton: View {
    let label: String
    let action: () -> Void
    @Environment(\.theme) var theme
    @State private var isHovering = false

    var body: some View {
        Button(label, action: action)
            .buttonStyle(.plain)
            .foregroundStyle(isHovering ? theme.colors.textPrimary : theme.colors.textTertiary)
            .onHover { isHovering = $0 }
            .animation(.easeInOut(duration: 0.12), value: isHovering)
    }
}

struct ProjectDetailView: View {
    let project: Project
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme
    @State private var isShowingSettings = false
    @State private var previewBody = ""

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let minEditor: CGFloat = 300
            let minGallery: CGFloat = 300

            ZStack(alignment: .bottomTrailing) {
                // Main content
                HStack(spacing: 0) {
                    switch appState.viewMode {
                    case .editor:
                        MarkdownEditorView(
                            readmeURL: project.readmeURL,
                            onSave: { _ in appState.notifyProjectFileChanged(uid: project.uid) },
                            theme: appState.theme,
                            appearanceSignal: appState.appearanceSignal,
                            autoSaveDelay: appState.autoSaveDelay
                        )
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)

                    case .preview:
                        MarkdownPreviewView(
                            markdown: previewBody,
                            projectFolderURL: project.folderURL,
                            theme: appState.theme,
                            appearanceSignal: appState.appearanceSignal
                        )
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)

                    case .splitGallery, .splitList, .splitLinks:
                        let editorWidth = max(minEditor, min(totalWidth - minGallery, totalWidth * appState.splitRatio))

                        MarkdownEditorView(
                            readmeURL: project.readmeURL,
                            onSave: { _ in appState.notifyProjectFileChanged(uid: project.uid) },
                            theme: appState.theme,
                            appearanceSignal: appState.appearanceSignal,
                            autoSaveDelay: appState.autoSaveDelay
                        )
                        .frame(width: editorWidth)
                        .clipped()

                        SplitDivider(
                            ratio: $appState.splitRatio,
                            totalWidth: totalWidth,
                            minLeft: minEditor,
                            minRight: minGallery
                        )

                        GalleryView(project: project, mode: galleryMode(for: appState.viewMode))
                            .frame(width: totalWidth - editorWidth)
                            .clipped()

                    case .gallery, .list, .links:
                        GalleryView(project: project, mode: galleryMode(for: appState.viewMode))
                            .frame(maxWidth: .infinity)
                            .transition(.opacity)

                    case .carousel:
                        CarouselView(project: project)
                            .frame(maxWidth: .infinity)
                            .transition(.opacity)
                    }
                }
                .coordinateSpace(name: "splitContainer")

                // Export button — only in preview mode
                if appState.viewMode == .preview {
                    Button {
                        MarkdownPreviewView.export(
                            markdown: previewBody,
                            projectFolderURL: project.folderURL,
                            projectTitle: project.title,
                            projectYear: project.year,
                            theme: appState.theme
                        )
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.colors.textTertiary)
                    }
                    .iconButton()
                    .help("Export as HTML")
                    .padding(DT.Spacing.lg)
                    .transition(.opacity)
                }
            }
        }
        .onChange(of: appState.viewMode) { _, _ in
            NotificationCenter.default.post(name: .markdownSaveNow, object: nil)
        }
        .animation(.easeInOut(duration: 0.2), value: appState.viewMode)
        .toolbar {
            // Left: back button
            ToolbarItem(placement: .navigation) {
                Button {
                    appState.setSelectedProject(nil)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.colors.textSecondary)
                }
                .iconButton()
                .help("Back to projects")
            }

            // Center: PROJECT (YYYY) · Client · Tags
            ToolbarItem(placement: .principal) {
                HStack(spacing: 0) {
                    if project.hidden {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.colors.textTertiary)
                            .padding(.trailing, DT.Spacing.xs)
                    }

                    Text(project.title.isEmpty ? "Untitled" : project.title)
                        .foregroundStyle(theme.colors.textPrimary)
                        .fontWeight(.semibold)

                    Text("(\(String(project.year)))")
                        .foregroundStyle(theme.colors.textTertiary)
                        .padding(.leading, DT.Spacing.xs)

                    if !project.client.isEmpty {
                        let clients = project.client.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        sectionSeparator
                        ForEach(Array(clients.enumerated()), id: \.offset) { idx, client in
                            ToolbarChipButton(label: client) {
                                searchAndGoBack(client)
                            }
                            if idx < clients.count - 1 {
                                inlineSeparator
                            }
                        }
                    }

                    if !project.tags.isEmpty {
                        sectionSeparator
                        ForEach(Array(project.tags.enumerated()), id: \.offset) { idx, tag in
                            ToolbarChipButton(label: tag) {
                                searchAndGoBack(tag)
                            }
                            if idx < project.tags.count - 1 {
                                inlineSeparator
                            }
                        }
                    }
                }
                .font(DT.Typography.caption)
                .lineLimit(1)
            }

            // Right: view-mode buttons in keyboard-shortcut order (⌘1..⌘6), then settings (⌘9).
            // Each button sets its specific viewMode — no toggles, no modifier behavior.
            ToolbarItemGroup(placement: .automatic) {
                toolbarModeButton(mode: .editor,       icon: "doc.text",                     help: "Editor (⌘1)")
                toolbarModeButton(mode: .preview,      icon: "eye",                          help: "Preview (⌘2)")
                toolbarModeButton(mode: .splitGallery, icon: "square.grid.2x2",              help: "Editor + Gallery (⌘3)")
                toolbarModeButton(mode: .splitList,    icon: "list.bullet",                  help: "Editor + List (⌘4)")
                toolbarModeButton(mode: .splitLinks,   icon: "link",                         help: "Editor + Links (⌘5)")
                toolbarModeButton(mode: .carousel,     icon: "rectangle.stack.badge.play",   help: "Carousel (⌘6)")

                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.colors.textTertiary)
                }
                .iconButton()
                .help("Project settings (⌘9)")
            }
        }
        .overlay {
            if !appState.hasSeenProjectOnboarding {
                ZStack {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { dismissOnboarding() }
                    ProjectOnboardingPrimerView(onDismiss: dismissOnboarding)
                }
                .transition(.opacity)
            }
        }
        .background {
            if !appState.hasSeenProjectOnboarding {
                Button("") { dismissOnboarding() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .opacity(0)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.15), value: appState.hasSeenProjectOnboarding)
        .sheet(isPresented: $isShowingSettings) {
            ProjectSettingsPopover(
                project: project,
                isPresented: $isShowingSettings
            )
            .environmentObject(appState)
        }
        .onAppear {
            handlePendingSelection()
            if appState.viewMode == .preview {
                loadPreviewBody()
            }
        }
        .onChange(of: appState.pendingFileSelection) { _, newValue in
            if newValue != nil { handlePendingSelection() }
        }
        .onChange(of: appState.pendingLinkID) { _, newValue in
            if newValue != nil { handlePendingSelection() }
        }
        .onChange(of: appState.viewMode) { _, newValue in
            // Entering preview via any path (menu, toolbar, programmatic):
            // flush pending editor saves, then re-read the body from disk so
            // the WebView renders the user's latest keystrokes.
            guard newValue == .preview else { return }
            NotificationCenter.default.post(name: .markdownSaveNow, object: nil)
            loadPreviewBody()
        }
        .onReceive(NotificationCenter.default.publisher(for: .markdownFileDidChange)) { note in
            // Keep the preview in sync after external rewrites (rename,
            // folder-rename, teaser change). Only relevant in preview mode.
            guard appState.viewMode == .preview else { return }
            if let url = note.object as? URL, url != project.readmeURL { return }
            loadPreviewBody()
        }
        .background {
            if appState.hasSeenProjectOnboarding {
                Button("") { appState.setSelectedProject(nil) }
                    .keyboardShortcut(.escape, modifiers: [])
                    .opacity(0)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: appState.isShowingProjectSettings) { _, newValue in
            guard newValue else { return }
            appState.isShowingProjectSettings = false
            // Only handle the flag when WE are the visible view (project is selected).
            guard appState.selectedProject != nil else { return }
            isShowingSettings = true
        }
    }

    private func dismissOnboarding() {
        appState.hasSeenProjectOnboarding = true
    }

    private func searchAndGoBack(_ query: String) {
        appState.searchQuery = query
        appState.setSelectedProject(nil)
    }

    /// Separator between major sections of the toolbar title row
    /// (title-year block vs clients vs tags). Wider gutter for hierarchy.
    private var sectionSeparator: some View {
        Text("·")
            .foregroundStyle(theme.colors.textTertiary.opacity(DT.Opacity.muted))
            .padding(.horizontal, DT.Spacing.sm)
    }

    /// Separator between peer items (tag↔tag, client↔client). Tight gutter.
    private var inlineSeparator: some View {
        Text("·")
            .foregroundStyle(theme.colors.textTertiary.opacity(DT.Opacity.muted))
            .padding(.horizontal, DT.Spacing.xs)
    }

    @ViewBuilder
    private func toolbarModeButton(mode: ViewMode, icon: String, help: String) -> some View {
        Button {
            appState.viewMode = mode
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(appState.viewMode == mode ? theme.colors.textPrimary : theme.colors.textTertiary)
        }
        .iconButton()
        .help(help)
    }

    private func loadPreviewBody() {
        guard let content = try? String(contentsOf: project.readmeURL, encoding: .utf8),
              let parsed = try? FrontmatterParser.parse(content) else {
            previewBody = ""
            return
        }
        previewBody = parsed.body
    }

    private func handlePendingSelection() {
        let showsGallery: Set<ViewMode> = [.splitGallery, .gallery, .splitList, .list]
        let showsLinks: Set<ViewMode> = [.splitLinks, .links]

        if appState.pendingFileSelection != nil, !showsGallery.contains(appState.viewMode) {
            appState.viewMode = .splitGallery
        }
        if appState.pendingLinkID != nil, !showsLinks.contains(appState.viewMode) {
            appState.viewMode = .splitLinks
        }
    }

    private func galleryMode(for viewMode: ViewMode) -> GalleryMode {
        switch viewMode {
        case .splitList, .list:       return .list
        case .splitLinks, .links:     return .links
        default:                       return .grid
        }
    }
}

// MARK: - Split Divider

struct SplitDivider: View {
    @Binding var ratio: CGFloat
    let totalWidth: CGFloat
    let minLeft: CGFloat
    let minRight: CGFloat

    @Environment(\.theme) var theme
    @State private var isDragging = false
    @State private var isHovering = false

    var body: some View {
        ZStack {
            // Vertical border line
            Rectangle()
                .fill(theme.colors.border)
                .frame(width: 1)

            // Handle pill
            Capsule()
                .fill(isDragging ? theme.colors.accent : isHovering ? theme.colors.textTertiary : theme.colors.border)
                .frame(width: 4, height: 36)
        }
        .frame(width: 10)
        .contentShape(Rectangle())
            .cursor(.resizeLeftRight)
            .onHover { hovering in
                isHovering = hovering
            }
            .gesture(
                DragGesture(coordinateSpace: .named("splitContainer"))
                    .onChanged { value in
                        isDragging = true
                        let newLeft = max(minLeft, min(totalWidth - minRight, value.location.x))
                        ratio = newLeft / totalWidth
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    ratio = 0.6
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isDragging)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
    }
}

// MARK: - Cursor Extension

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside { cursor.set() } else { NSCursor.arrow.set() }
        }
    }
}

// MARK: - ViewMode Helpers

extension ViewMode {
    var label: String {
        switch self {
        case .editor: "Editor"
        case .preview: "Preview"
        case .splitGallery: "Editor + Gallery"
        case .gallery: "Gallery"
        case .splitList: "Editor + List"
        case .list: "List"
        case .splitLinks: "Editor + Links"
        case .links: "Links"
        case .carousel: "Carousel"
        }
    }

    var icon: String {
        switch self {
        case .editor: "doc.text"
        case .preview: "eye"
        case .splitGallery: "rectangle.split.2x1"
        case .gallery: "square.grid.2x2"
        case .splitList: "rectangle.split.2x1"
        case .list: "list.bullet"
        case .splitLinks: "rectangle.split.2x1"
        case .links: "link"
        case .carousel: "rectangle.stack.badge.play"
        }
    }
}
