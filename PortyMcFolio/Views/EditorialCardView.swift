import SwiftUI

/// Image-forward grid card. No border, shadow, or footer chrome — the image
/// is the object, the caption sits below as plain typography. Hover reveals
/// year + clickable tag pills over a dark canvas (status is deliberately
/// omitted on this view). Selection state flows in from the parent so the
/// keyboard-nav machinery in `ProjectListView` can stay unchanged.
struct EditorialCardView: View {
    let project: Project
    let aspectRatio: CGFloat
    let isKeyboardSelected: Bool
    let isHoverHighlighted: Bool
    var onOpen: (() -> Void)?
    var onTagTap: ((String) -> Void)?
    var onClientTap: ((String) -> Void)?

    @State private var teaserImage: NSImage?
    @State private var isOverlayHovered = false
    @Environment(\.theme) var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            imageFrame
            caption
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen?() }
        .onHover { hovering in isOverlayHovered = hovering }
        .task(id: project.teaser) { await loadTeaser() }
    }

    private var imageFrame: some View {
        Rectangle()
            .fill(theme.colors.surface)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                if let image = teaserImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Text(project.title.isEmpty ? "Untitled" : project.title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(theme.colors.textTertiary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(24)
                }
            }
            .overlay {
                if hasOverlayContent {
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(Color.black.opacity(0.90))
                            .allowsHitTesting(false)

                        VStack(alignment: .leading, spacing: 12) {
                            Text(WhenFormatting.summaryString(
                                date: project.date,
                                dateEnd: project.dateEnd,
                                year: project.year
                            ))
                                .font(DT.Typography.micro)
                                .foregroundStyle(.white.opacity(0.6))
                                .tracking(1.4)

                            if !project.tags.isEmpty {
                                FlowLayout(spacing: 5) {
                                    ForEach(project.tags, id: \.self) { tag in
                                        EditorialOverlayTagPill(tag: tag) {
                                            onTagTap?(tag)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .opacity(isOverlayHovered ? 1 : 0)
                    .allowsHitTesting(isOverlayHovered)
                    .animation(.easeInOut(duration: 0.15), value: isOverlayHovered)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.small))
            .overlay {
                RoundedRectangle(cornerRadius: DT.Radius.small)
                    .stroke(selectionStrokeColor, lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }

    private var hasOverlayContent: Bool {
        // The hover overlay is only useful when there's something to surface
        // beyond the folder year (already shown in the year-band heading).
        // Tags or an explicit When (i.e. a range) qualifies; year-only +
        // tagless projects skip the overlay entirely.
        !project.tags.isEmpty || project.dateEnd != nil
    }

    private var selectionStrokeColor: Color {
        if isKeyboardSelected { return theme.colors.accent.opacity(0.6) }
        if isHoverHighlighted { return theme.colors.accent.opacity(0.25) }
        if teaserImage == nil { return theme.colors.border }
        return .clear
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.title.isEmpty ? "Untitled" : project.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            // Always reserve a line for the client row so cards without a
            // client stay vertically uniform with their neighbors in the grid.
            // When empty, render a transparent placeholder with the same font
            // metrics so the layout height matches.
            HStack(spacing: 0) {
                if project.client.isEmpty {
                    Text(" ")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(.clear)
                        .accessibilityHidden(true)
                } else {
                    let clients = project.client
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    ForEach(Array(clients.enumerated()), id: \.offset) { idx, client in
                        EditorialClientButton(label: client) {
                            onClientTap?(client)
                        }
                        if idx < clients.count - 1 {
                            Text(", ")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(1.4)
                                .textCase(.uppercase)
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1)
        }
    }

    private func loadTeaser() async {
        guard !project.teaser.isEmpty else {
            await MainActor.run { teaserImage = nil }
            return
        }
        let teaserURL = project.folderURL.appendingPathComponent(project.teaser)
        guard FileManager.default.fileExists(atPath: teaserURL.path) else {
            await MainActor.run { teaserImage = nil }
            return
        }
        guard let img = await ImageThumbnail.load(
            url: teaserURL,
            size: CGSize(width: 700, height: 500)
        ) else { return }
        await MainActor.run { teaserImage = img }
    }
}

/// White-on-dark tag pill used in the hover overlay. The dark canvas it
/// sits on doesn't track theme appearance, so the pill uses explicit white
/// values instead of theme tokens — they need to read against black in
/// every theme.
private struct EditorialOverlayTagPill: View {
    let tag: String
    let onTap: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            Text(tag)
                .font(DT.Typography.caption)
                .foregroundStyle(.white.opacity(isHovering ? 1.0 : 0.85))
                .padding(.horizontal, DT.Spacing.sm)
                .padding(.vertical, DT.Spacing.xs)
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.small)
                        .stroke(
                            Color.white.opacity(isHovering ? 0.6 : 0.35),
                            lineWidth: 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.small))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }
}

/// Uppercase-tracked client chip below the image. Subtle by default,
/// brightens to textPrimary on hover; tap filters by the client name.
private struct EditorialClientButton: View {
    let label: String
    let onTap: () -> Void
    @Environment(\.theme) var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(isHovering ? theme.colors.textPrimary : theme.colors.textSecondary)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }
}
