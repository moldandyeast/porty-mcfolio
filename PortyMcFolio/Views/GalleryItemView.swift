import SwiftUI
import QuickLookThumbnailing

struct GalleryItemView: View {
    let fileURL: URL
    let displayName: String
    let isSelected: Bool
    let isTeaser: Bool
    let isCut: Bool
    let isFocused: Bool
    let isCursor: Bool

    @State private var thumbnail: NSImage?
    @State private var isHovering: Bool = false
    @Environment(\.theme) var theme

    private var extensionBadge: String? {
        let ext = fileURL.pathExtension
        guard !ext.isEmpty else { return nil }
        return String(ext.uppercased().prefix(4))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail area
            ZStack {
                Rectangle()
                    .fill(theme.colors.surfaceHover)

                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: GallerySort.fallbackSymbol(for: fileURL))
                        .font(.system(size: 32))
                        .foregroundStyle(theme.colors.textSecondary)
                }

                // Extension badge (bottom-right of thumbnail area)
                if let badge = extensionBadge {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(badge)
                                .font(DT.Typography.micro)
                                .foregroundStyle(theme.colors.textSecondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    theme.colors.surface.opacity(0.85),
                                    in: RoundedRectangle(cornerRadius: DT.Radius.small)
                                )
                                .padding(6)
                        }
                    }
                }

                // Teaser star (top-left — top-right is reserved for the heart / favorite).
                // Mirror the heart badge's chrome so the two corners read as a
                // matched pair: same ultraThinMaterial circle, same icon size.
                if isTeaser {
                    VStack {
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 22, height: 22)
                                Image(systemName: "star.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.yellow)
                            }
                            .padding(6)
                            .help("Teaser image")
                            Spacer()
                        }
                        Spacer()
                    }
                }
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

            // Filename strip
            HStack {
                Text(displayName)
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
            // Focus ring — only when the gallery has keyboard focus AND this is selected or is the cursor
            RoundedRectangle(cornerRadius: DT.Radius.medium)
                .stroke(theme.colors.accent, lineWidth: 1)
                .opacity(isFocused && (isSelected || isCursor) ? 1 : 0)
                .padding(-2)
        )
        .dtShadow(isSelected ? DT.Shadow.card : DT.Shadow.Style(color: .clear, radius: 0, y: 0))
        .opacity(isCut ? 0.4 : 1.0)
        .onHover { isHovering = $0 }
        .help(fileURL.lastPathComponent)  // tooltip shows full on-disk name
        .task(id: fileURL) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        guard let img = await ImageThumbnail.load(url: fileURL, size: CGSize(width: 280, height: 200)) else {
            return
        }
        await MainActor.run { thumbnail = img }
    }
}
