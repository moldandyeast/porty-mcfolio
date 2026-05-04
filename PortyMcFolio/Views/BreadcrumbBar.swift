import SwiftUI

struct BreadcrumbBar: View {
    let projectName: String
    let relativePath: [String]
    let currentFolderURL: URL
    let onNavigate: (Int) -> Void  // -1 = root, 0+ = index into relativePath
    var onRenameCurrentFolder: (() -> Void)?

    @Environment(\.theme) var theme

    var body: some View {
        HStack(spacing: 4) {
            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: currentFolderURL.path)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.colors.textTertiary)
                    .padding(DT.Spacing.xs)
                    .contentShape(Rectangle())
            }
            .iconButton()
            .help("Reveal in Finder")

            if relativePath.isEmpty {
                // At root — just show project name
                BreadcrumbSegment(
                    text: projectName,
                    isActive: true,
                    action: { onNavigate(-1) }
                )
            } else if relativePath.count <= 2 {
                // Short path — show all segments
                BreadcrumbSegment(
                    text: projectName,
                    isActive: false,
                    action: { onNavigate(-1) }
                )

                ForEach(Array(relativePath.enumerated()), id: \.offset) { index, segment in
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.colors.textTertiary)

                    let isLast = index == relativePath.count - 1
                    BreadcrumbSegment(
                        text: segment,
                        isActive: isLast,
                        action: { onNavigate(index) }
                    )
                    .if(isLast && onRenameCurrentFolder != nil) { view in
                        view.contextMenu {
                            Button("Rename…") { onRenameCurrentFolder?() }
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: currentFolderURL.path)
                            }
                        }
                    }
                }
            } else {
                // Deep path — show: root > … (menu) > last segment
                BreadcrumbSegment(
                    text: projectName,
                    isActive: false,
                    action: { onNavigate(-1) }
                )

                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.colors.textTertiary)

                // Collapsed middle segments as a menu
                Menu {
                    ForEach(Array(relativePath.dropLast().enumerated()), id: \.offset) { index, segment in
                        Button(segment) { onNavigate(index) }
                    }
                } label: {
                    Text("…")
                        .font(DT.Typography.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(.horizontal, DT.Spacing.xs)
                        .padding(.vertical, DT.Spacing.xs)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.colors.textTertiary)

                // Last segment (current folder)
                let lastIndex = relativePath.count - 1
                BreadcrumbSegment(
                    text: relativePath.last ?? "",
                    isActive: true,
                    action: { onNavigate(lastIndex) }
                )
                .if(onRenameCurrentFolder != nil) { view in
                    view.contextMenu {
                        Button("Rename…") { onRenameCurrentFolder?() }
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: currentFolderURL.path)
                        }
                    }
                }
            }

            Spacer()
        }
        .lineLimit(1)
        .padding(.horizontal, DT.Spacing.lg)
        .padding(.vertical, DT.Spacing.sm)
    }
}

// MARK: - Conditional modifier

private extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Breadcrumb Segment

private struct BreadcrumbSegment: View {
    let text: String
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.theme) var theme

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(DT.Typography.caption)
                .fontWeight(.medium)
                .foregroundStyle(isActive ? theme.colors.textPrimary : theme.colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, DT.Spacing.sm)
                .padding(.vertical, DT.Spacing.xs)
                .background(
                    isHovering && !isActive
                        ? theme.colors.surfaceHover
                        : Color.clear,
                    in: RoundedRectangle(cornerRadius: DT.Radius.small)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}
