import SwiftUI

struct LinkCardView: View {
    let link: LinkItem
    let projectFolderURL: URL

    @State private var isHovering = false
    @Environment(\.theme) var theme

    var displayTitle: String {
        if !link.title.isEmpty {
            return link.title
        }
        return link.url.host ?? link.url.absoluteString
    }

    var domain: String {
        link.url.host?.replacingOccurrences(of: "www.", with: "") ?? link.url.absoluteString
    }

    private var linkFileURL: URL {
        projectFolderURL.appendingPathComponent(LinkItem.fileName(uid: link.uid))
    }

    private var faviconURL: URL? {
        guard let host = link.url.host else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?sz=32&domain=\(host)")
    }

    var body: some View {
        HStack(spacing: DT.Spacing.md) {
            // Favicon
            Group {
                if let faviconURL {
                    AsyncImage(url: faviconURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        default:
                            faviconFallback
                        }
                    }
                } else {
                    faviconFallback
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.small))

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(DT.Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)

                Text(domain)
                    .font(DT.Typography.caption)
                    .foregroundStyle(theme.colors.textTertiary)
                    .lineLimit(1)

                if !link.annotation.isEmpty {
                    Text(link.annotation)
                        .font(DT.Typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DT.Spacing.md)
        .padding(.vertical, DT.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isHovering ? theme.colors.surfaceHover : Color.clear,
            in: RoundedRectangle(cornerRadius: DT.Radius.medium)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onDrag {
            NSItemProvider(object: linkFileURL as NSURL)
        }
    }

    private var faviconFallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DT.Radius.small)
                .fill(theme.colors.surfaceHover)
            Image(systemName: "link")
                .font(.system(size: 13))
                .foregroundStyle(theme.colors.textTertiary)
        }
    }
}
