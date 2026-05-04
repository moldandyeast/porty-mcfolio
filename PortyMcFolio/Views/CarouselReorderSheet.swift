import SwiftUI
import AppKit
import QuickLookThumbnailing

/// Sheet that lets the user reorder the project's favorites using SwiftUI's
/// native `List.onMove`. Opens from the carousel tray's reorder button.
///
/// Each drop commits live via the established flush → read → rewrite → write →
/// notify pattern, mirroring `GalleryView.toggleFavorite` / `setTeaser`.
struct CarouselReorderSheet: View {
    let project: Project
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
        }
        .frame(width: 480, height: 480)
        .background(theme.colors.background)
    }

    private var header: some View {
        HStack {
            Text("Reorder Carousel")
                .font(DT.Typography.headline)
                .foregroundStyle(theme.colors.textPrimary)
            Spacer()
            Button { dismiss() } label: {
                Text("Done")
                    .font(DT.Typography.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(theme.colors.accentForeground)
                    .padding(.horizontal, DT.Spacing.md)
                    .padding(.vertical, DT.Spacing.xs)
                    .background(theme.colors.accent, in: RoundedRectangle(cornerRadius: DT.Radius.small))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, DT.Spacing.lg)
        .padding(.vertical, DT.Spacing.md)
        .background(theme.colors.background)
    }

    private var list: some View {
        List {
            ForEach(project.favorites, id: \.self) { rel in
                row(for: rel)
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(theme.colors.border.opacity(DT.Opacity.faint))
            }
            .onMove { from, to in
                reorderFavorites(from: from, to: to)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.colors.background)
    }

    private func row(for rel: String) -> some View {
        let url = project.folderURL.appendingPathComponent(rel)
        return HStack(spacing: DT.Spacing.sm) {
            ReorderRowThumb(url: url)
            Text(rel)
                .font(DT.Typography.caption)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .frame(height: 32)
    }

    /// Applies `Array.move(fromOffsets:toOffset:)` to the favorites on disk.
    /// Matches the save pattern used by `GalleryView.toggleFavorite`.
    private func reorderFavorites(from source: IndexSet, to destination: Int) {
        NotificationCenter.default.post(name: .markdownSaveNow, object: nil)
        guard let content = try? String(contentsOf: project.readmeURL, encoding: .utf8),
              var parsed = try? FrontmatterParser.parse(content) else { return }
        parsed.favorites.move(fromOffsets: source, toOffset: destination)
        let updated = FrontmatterParser.serialize(frontmatter: parsed)
        try? updated.write(to: project.readmeURL, atomically: true, encoding: .utf8)
        NotificationCenter.default.post(name: .markdownFileDidChange, object: project.readmeURL)
        appState.notifyProjectFileChanged(uid: project.uid)
    }
}

/// Small thumbnail used in the reorder sheet's rows.
private struct ReorderRowThumb: View {
    let url: URL
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
        .frame(width: 32, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.small))
        .task { await loadThumbnail() }
    }

    @ViewBuilder
    private var placeholder: some View {
        let kind = MediaKind.from(url: url)
        ZStack {
            Rectangle().fill(theme.colors.surfaceHover)
            Image(systemName: kind == .audio ? "waveform" : (kind == .video ? "play.rectangle" : "questionmark"))
                .font(.system(size: 10))
                .foregroundStyle(theme.colors.textTertiary)
        }
    }

    private func loadThumbnail() async {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let img = await ImageThumbnail.load(url: url, size: CGSize(width: 64, height: 48)) else { return }
        await MainActor.run { self.image = img }
    }
}
