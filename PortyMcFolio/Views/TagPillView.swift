import SwiftUI

struct TagPillView: View {
    let tag: String
    var onTap: (() -> Void)?

    @Environment(\.theme) var theme
    @State private var isHovering = false

    var body: some View {
        Button {
            onTap?()
        } label: {
            Text(tag)
                .font(DT.Typography.caption)
                .foregroundStyle(isHovering ? theme.colors.textPrimary : theme.colors.textSecondary)
                .padding(.horizontal, DT.Spacing.sm)
                .padding(.vertical, DT.Spacing.xs)
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.small)
                        .stroke(isHovering ? theme.colors.accent : theme.colors.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.small))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }
}
