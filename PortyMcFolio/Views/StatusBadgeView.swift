import SwiftUI

struct StatusBadgeView: View {
    let status: ProjectStatus

    @Environment(\.theme) var theme

    private var color: Color {
        switch status {
        case .empty: theme.colors.statusDraft
        case .inProgress: theme.colors.statusActive
        case .archived: theme.colors.statusArchived
        }
    }

    var body: some View {
        Text(status.displayName)
            .font(DT.Typography.micro)
            .fontWeight(.medium)
            .padding(.horizontal, DT.Spacing.sm)
            .padding(.vertical, DT.Spacing.xs)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.small))
    }
}
