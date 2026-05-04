import AVKit
import AppKit
import SwiftUI
import QuickLookThumbnailing

struct CarouselView: View {
    let project: Project
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme

    @State private var currentIndex: Int = 0
    @State private var slideImage: NSImage?
    @State private var showTray: Bool = false
    @State private var isShowingReorder: Bool = false
    @State private var isRenaming: Bool = false
    @State private var renameText: String = ""

    var body: some View {
        ZStack {
            if project.favorites.isEmpty {
                emptyState
            } else {
                slideshowBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.background)
        .onChange(of: project.favorites) { oldFavorites, newFavorites in
            // Preserve the currently-viewed slide across reorders: if the old
            // slide's path still exists in the new list, follow it to its new
            // index. Otherwise fall through to clampIndex (mid-session removal,
            // reconciler drop, etc.).
            let currentPath: String? = oldFavorites.indices.contains(currentIndex)
                ? oldFavorites[currentIndex]
                : nil
            if let path = currentPath, let newIdx = newFavorites.firstIndex(of: path) {
                currentIndex = newIdx
            } else {
                clampIndex(for: newFavorites)
            }
        }
        .onAppear {
            clampIndex(for: project.favorites)
            loadCurrentSlide()
            prefetchAroundCurrent()
        }
        .onChange(of: currentIndex) { _, _ in
            loadCurrentSlide()
            prefetchAroundCurrent()
        }
        .background {
            // ←/→ navigation — bare arrows; no ScrollView to conflict.
            Button("") { step(-1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .opacity(0)
                .allowsHitTesting(false)
            Button("") { step(1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .opacity(0)
                .allowsHitTesting(false)
        }
        .sheet(isPresented: $isShowingReorder) {
            CarouselReorderSheet(project: project)
                .environmentObject(appState)
        }
        .sheet(isPresented: $isRenaming) {
            RenameFileSheet(
                prefix: filePrefix,
                name: $renameText,
                fileExtension: currentSlideURL?.pathExtension ?? "",
                onConfirm: { performRename() }
            )
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: DT.Spacing.md) {
            Image(systemName: "rectangle.stack.badge.play")
                .font(.system(size: 48))
                .foregroundStyle(theme.colors.textTertiary)
            Text("No favorites yet")
                .font(DT.Typography.title)
                .foregroundStyle(theme.colors.textPrimary)
            Text("Click the heart on media files in Gallery (⌘3) to build your carousel.")
                .font(DT.Typography.body)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Slideshow

    private var slideshowBody: some View {
        VStack(spacing: 0) {
            slide
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 24)
            trayZone
            bottomBar
        }
    }

    /// Reserved 72pt strip above the bottom bar. Hover-reveals the tray.
    /// Keeps the tray out of the slide's frame so video controls (AVKit's
    /// native transport at the bottom of the video) are never covered.
    private var trayZone: some View {
        ZStack {
            tray
                .opacity(showTray ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: showTray)
        }
        .frame(height: 72)
        .contentShape(Rectangle())
        .onHover { hovering in
            showTray = hovering
        }
    }

    private var bottomBar: some View {
        HStack(spacing: DT.Spacing.sm) {
            copyButton
            Text(currentFilename)
                .font(DT.Typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { openRename() }
                .help("Double-click to rename")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(currentIndex + 1) / \(project.favorites.count)")
                .font(DT.Typography.caption)
                .foregroundStyle(theme.colors.textTertiary)
            reorderButton
        }
        .padding(.leading, DT.Spacing.lg)
        .padding(.trailing, DT.Spacing.xl)
        .padding(.vertical, DT.Spacing.sm)
    }

    private var copyButton: some View {
        Button {
            copyCurrentFileToClipboard()
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.textTertiary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .iconButton()
        .tint(theme.colors.textTertiary)
        .disabled(currentSlideURL == nil)
        .help("Copy file to clipboard")
    }

    @ViewBuilder
    private var slide: some View {
        if let url = currentSlideURL {
            switch MediaKind.from(url: url) {
            case .image:
                imageSlide(for: url)
            case .video:
                videoSlide(for: url)
            case .audio:
                audioSlide(for: url)
            case .none:
                missingPlaceholder(for: url)
            }
        } else {
            missingPlaceholder(for: nil)
        }
    }

    private func imageSlide(for url: URL) -> some View {
        Group {
            if let image = slideImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // Loading placeholder
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func missingPlaceholder(for url: URL?) -> some View {
        VStack(spacing: DT.Spacing.sm) {
            Image(systemName: "questionmark.square.dashed")
                .font(.system(size: 48))
                .foregroundStyle(theme.colors.textTertiary)
            Text("Media unavailable")
                .font(DT.Typography.body)
                .foregroundStyle(theme.colors.textSecondary)
            if let url {
                Text(url.lastPathComponent)
                    .font(DT.Typography.caption)
                    .foregroundStyle(theme.colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Slide logic

    private var currentSlideURL: URL? {
        guard currentIndex >= 0, currentIndex < project.favorites.count else { return nil }
        let rel = project.favorites[currentIndex]
        let url = project.folderURL.appendingPathComponent(rel)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private var currentFilename: String {
        guard currentIndex >= 0, currentIndex < project.favorites.count else { return "" }
        return (project.favorites[currentIndex] as NSString).lastPathComponent
    }

    private func step(_ delta: Int) {
        let newIndex = currentIndex + delta
        guard newIndex >= 0, newIndex < project.favorites.count else { return }   // no wrap
        currentIndex = newIndex
    }

    private func clampIndex(for favorites: [String]) {
        if favorites.isEmpty {
            currentIndex = 0   // irrelevant when empty; empty state renders
            slideImage = nil
        } else if currentIndex >= favorites.count {
            currentIndex = favorites.count - 1
        } else if currentIndex < 0 {
            currentIndex = 0
        }
    }

    // MARK: - Audio

    @ViewBuilder
    private func audioSlide(for url: URL) -> some View {
        VStack(spacing: DT.Spacing.lg) {
            Text(url.lastPathComponent)
                .font(DT.Typography.headline)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DT.Spacing.lg)
            AudioPlayerView(url: url)
                .frame(height: 44)
                .id(url)   // rebuild on slide change so transport resets
        }
        .frame(maxWidth: 480)
        .padding(DT.Spacing.xl)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: DT.Radius.medium))
    }

    // MARK: - Video

    @ViewBuilder
    private func videoSlide(for url: URL) -> some View {
        VideoPlayerSlide(url: url)
            .id(url)  // Force re-init when the slide changes so the player resets.
    }

    // MARK: - Thumbnail tray

    private var tray: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: DT.Spacing.xs) {
                    ForEach(Array(project.favorites.enumerated()), id: \.element) { index, rel in
                        thumb(at: index, relativePath: rel)
                            .id(index)
                    }
                }
                .padding(.horizontal, DT.Spacing.lg)
            }
            .frame(height: 72)
            .onChange(of: currentIndex) { _, newIndex in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
            .onAppear {
                proxy.scrollTo(currentIndex, anchor: .center)
            }
        }
        .background(theme.colors.surface.opacity(DT.Opacity.muted))
    }

    private var reorderButton: some View {
        Button {
            isShowingReorder = true
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.textTertiary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .iconButton()
        .tint(theme.colors.textTertiary)   // override app-level .tint(accent)
        .help("Reorder Carousel")
    }

    @ViewBuilder
    private func thumb(at index: Int, relativePath rel: String) -> some View {
        let url = project.folderURL.appendingPathComponent(rel)
        CarouselThumb(
            url: url,
            isCurrent: index == currentIndex
        )
        .onTapGesture { currentIndex = index }
        .overlay(alignment: .topTrailing) {
            // × removes this favorite — visible on hover.
            ThumbRemoveButton {
                removeFavorite(at: index)
            }
            .padding(4)
        }
    }

    private func removeFavorite(at index: Int) {
        guard index >= 0, index < project.favorites.count else { return }
        let toRemove = project.favorites[index]
        NotificationCenter.default.post(name: .markdownSaveNow, object: nil)
        guard let content = try? String(contentsOf: project.readmeURL, encoding: .utf8),
              var parsed = try? FrontmatterParser.parse(content) else { return }
        parsed.favorites = FrontmatterParser.rewritingFavorite(
            in: parsed.favorites, from: toRemove, to: ""
        )
        let updated = FrontmatterParser.serialize(frontmatter: parsed)
        try? updated.write(to: project.readmeURL, atomically: true, encoding: .utf8)
        NotificationCenter.default.post(name: .markdownFileDidChange, object: project.readmeURL)
        appState.notifyProjectFileChanged(uid: project.uid)
        // clampIndex runs via onChange(project.favorites).
    }

    private func copyCurrentFileToClipboard() {
        guard let url = currentSlideURL else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        // Write both a file-URL item (modern receivers like Finder) and a
        // NSFilenamesPboardType list (legacy). Using the raw data on a
        // pasteboard item ensures Finder pastes the FILE — not the path
        // string — because the pasteboard advertises the correct type.
        let item = NSPasteboardItem()
        item.setData(url.dataRepresentation, forType: .fileURL)
        pb.writeObjects([item])
        pb.setPropertyList(
            [url.path],
            forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")
        )
        NotificationCenter.default.post(name: .showToast, object: "Copied \(url.lastPathComponent)")
    }

    private var filePrefix: String {
        "\(project.year)_\(Slug.underscoreFrom(project.title))_"
    }

    private func openRename() {
        guard let url = currentSlideURL else { return }
        // Pre-fill with the description portion: everything between the
        // project prefix and the extension. Legacy files that don't match
        // the convention are stripped of just the extension.
        let base = (url.lastPathComponent as NSString).deletingPathExtension
        let pfx = filePrefix
        renameText = base.hasPrefix(pfx) ? String(base.dropFirst(pfx.count)) : base
        isRenaming = true
    }

    private func performRename() {
        guard let oldURL = currentSlideURL else {
            isRenaming = false
            return
        }
        let slugged = Slug.underscoreFrom(renameText)
        guard !slugged.isEmpty, slugged != "untitled" else {
            isRenaming = false
            return
        }
        let ext = oldURL.pathExtension
        let newName = ext.isEmpty
            ? "\(filePrefix)\(slugged)"
            : "\(filePrefix)\(slugged).\(ext)"
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newName)

        if newURL == oldURL {
            isRenaming = false
            return
        }
        if FileManager.default.fileExists(atPath: newURL.path) {
            NotificationCenter.default.post(
                name: .showToast, object: "\"\(newName)\" already exists"
            )
            return
        }

        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
        } catch {
            NotificationCenter.default.post(
                name: .showToast,
                object: "Rename failed: \(error.localizedDescription)"
            )
            return
        }

        let rootPath = project.folderURL.path + "/"
        let oldRel = oldURL.path.replacingOccurrences(of: rootPath, with: "")
        let newRel = newURL.path.replacingOccurrences(of: rootPath, with: "")
        let didRewrite: Bool
        do {
            didRewrite = try ProjectFileOps.updateReferences(in: project, from: oldRel, to: newRel)
        } catch {
            AppLogger.ui.error("CarouselView: updateReferences failed: \(error.localizedDescription, privacy: .public)")
            didRewrite = false
        }
        if didRewrite {
            NotificationCenter.default.post(name: .markdownFileDidChange, object: project.readmeURL)
            appState.notifyProjectFileChanged(uid: project.uid)
        }
        isRenaming = false
    }

    private func loadCurrentSlide() {
        guard let url = currentSlideURL,
              MediaKind.from(url: url) == .image
        else { return }
        // Keep the previous image visible during the QL roundtrip so navigation
        // doesn't flash a spinner — the cache makes revisits instant, and a
        // brief stale-image frame on first-visit is far less jarring than a
        // ProgressView pop. The ProgressView only renders on first-ever load.
        Task {
            guard let img = await ImageThumbnail.load(url: url, size: CGSize(width: 1600, height: 1200)) else { return }
            await MainActor.run {
                // Guard against a stale async completion landing after the user advanced.
                if self.currentSlideURL == url {
                    self.slideImage = img
                }
            }
        }
    }

    /// Warms the thumbnail cache for slides on either side of the current one
    /// so arrow-key navigation doesn't wait on a decode. Radius 2 covers the
    /// typical "flick through" pattern without holding too many large decoded
    /// images at once (NSCache evicts under pressure anyway).
    private func prefetchAroundCurrent() {
        let indices = CarouselPrefetch.indicesToPrefetch(
            around: currentIndex,
            count: project.favorites.count,
            radius: 2
        )
        for i in indices {
            let rel = project.favorites[i]
            let url = project.folderURL.appendingPathComponent(rel)
            guard FileManager.default.fileExists(atPath: url.path),
                  MediaKind.from(url: url) == .image
            else { continue }
            Task(priority: .utility) {
                _ = await ImageThumbnail.load(url: url, size: CGSize(width: 1600, height: 1200))
            }
        }
    }
}

private struct VideoPlayerSlide: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                Color.clear
            }
        }
        .onAppear {
            player = AVPlayer(url: url)
            // Manual click to play — do not call player.play() here.
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

private struct CarouselThumb: View {
    let url: URL
    let isCurrent: Bool
    @Environment(\.theme) var theme
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .frame(width: 96, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.small))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.small)
                .stroke(
                    isCurrent ? theme.colors.accent : theme.colors.border.opacity(DT.Opacity.faint),
                    lineWidth: isCurrent ? 2 : 0.5
                )
        )
        .task { await loadThumbnail() }
    }

    @ViewBuilder
    private var placeholder: some View {
        let kind = MediaKind.from(url: url)
        ZStack {
            Rectangle().fill(theme.colors.surfaceHover)
            Image(systemName: kind == .audio ? "waveform" : (kind == .video ? "play.rectangle" : "questionmark"))
                .font(.system(size: 20))
                .foregroundStyle(theme.colors.textTertiary)
        }
    }

    private func loadThumbnail() async {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let img = await ImageThumbnail.load(url: url, size: CGSize(width: 192, height: 128)) else { return }
        await MainActor.run { self.image = img }
    }
}

private struct ThumbRemoveButton: View {
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onRemove) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .background(Circle().fill(.black.opacity(0.6)))
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .opacity(hovering ? 1 : 0)
        .onHover { hovering = $0 }
    }
}
