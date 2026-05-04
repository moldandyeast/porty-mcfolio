import SwiftUI
import QuickLookThumbnailing

// File-level formatters shared by GalleryListRow regardless of its generic parameter.
private let galleryListDateFormatter: DateFormatter = {
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .none
    return df
}()

private let galleryListSizeFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f
}()

struct GalleryListRow<Accessory: View>: View {
    let url: URL
    let displayName: String
    let isFolder: Bool
    let isTeaser: Bool
    let isSelected: Bool
    let isCut: Bool
    let isFocused: Bool
    let isCursor: Bool
    @ViewBuilder var trailingAccessory: () -> Accessory

    @State private var thumbnail: NSImage?
    @State private var fileSize: String = ""
    @State private var fileDate: String = ""
    @State private var isHovering: Bool = false
    @Environment(\.theme) var theme

    var body: some View {
        HStack(spacing: DT.Spacing.md) {
            // Leading accent bar for selection
            Rectangle()
                .fill(isSelected ? theme.colors.accent : Color.clear)
                .frame(width: 2)

            // Thumbnail (or folder icon)
            ZStack {
                RoundedRectangle(cornerRadius: DT.Radius.small)
                    .fill(theme.colors.surfaceHover)

                if let thumb = thumbnail, !isFolder {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.small))
                } else {
                    Image(systemName: GallerySort.fallbackSymbol(for: url, isFolder: isFolder))
                        .font(.system(size: 14))
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
            .frame(width: 32, height: 32)

            HStack(spacing: DT.Spacing.xs) {
                Text(displayName)
                    .font(DT.Typography.body)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if isTeaser {
                    Image(systemName: "star.fill")
                        .font(DT.Typography.micro)
                        .foregroundStyle(.yellow)
                }
            }
            .help(url.lastPathComponent)

            Spacer()

            // Trailing accessory (e.g. heart button for media rows) — EmptyView by default
            trailingAccessory()

            if !isFolder {
                Text(fileSize)
                    .font(DT.Typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(width: 70, alignment: .trailing)
            }

            Text(fileDate)
                .font(DT.Typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: 90, alignment: .trailing)
                .padding(.trailing, DT.Spacing.lg)
        }
        .padding(.vertical, DT.Spacing.sm)
        .background(
            isSelected ? theme.colors.accent.opacity(DT.Opacity.selection)
                : isHovering ? theme.colors.surfaceHover
                : Color.clear
        )
        .overlay(
            // Focus ring for list row — subtle hairline on selected+focused (or cursor+focused)
            RoundedRectangle(cornerRadius: 0)
                .stroke(theme.colors.accent, lineWidth: 1)
                .opacity(isFocused && (isSelected || isCursor) ? 1 : 0)
        )
        .opacity(isCut ? 0.4 : 1.0)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .task(id: url) {
            await loadThumbnail()
            loadFileInfo()
        }
    }

    private func loadThumbnail() async {
        guard !isFolder else { return }
        guard let img = await ImageThumbnail.load(url: url, size: CGSize(width: 64, height: 64)) else {
            return
        }
        await MainActor.run { thumbnail = img }
    }

    @MainActor
    private func loadFileInfo() {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        if let size = values.fileSize {
            fileSize = galleryListSizeFormatter.string(fromByteCount: Int64(size))
        }
        if let date = values.contentModificationDate {
            fileDate = galleryListDateFormatter.string(from: date)
        }
    }
}

// MARK: - Default init (no trailing accessory)

extension GalleryListRow where Accessory == EmptyView {
    init(
        url: URL,
        displayName: String,
        isFolder: Bool,
        isTeaser: Bool,
        isSelected: Bool,
        isCut: Bool,
        isFocused: Bool,
        isCursor: Bool
    ) {
        self.init(
            url: url,
            displayName: displayName,
            isFolder: isFolder,
            isTeaser: isTeaser,
            isSelected: isSelected,
            isCut: isCut,
            isFocused: isFocused,
            isCursor: isCursor,
            trailingAccessory: { EmptyView() }
        )
    }
}
