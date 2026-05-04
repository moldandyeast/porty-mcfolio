import SwiftUI

/// Small floating pill that confirms an action whose result the user can't
/// see in the current view (e.g. adding a file while viewing Links, or
/// adding a URL while viewing Grid/List). Auto-dismissed by `AppState`.
struct ToastView: View {
    let message: String
    @Environment(\.theme) var theme

    var body: some View {
        Text(message)
            .font(DT.Typography.caption)
            .foregroundStyle(theme.colors.textPrimary)
            .padding(.horizontal, DT.Spacing.md)
            .padding(.vertical, DT.Spacing.sm)
            .background(theme.colors.surface, in: Capsule())
            .overlay(
                Capsule().stroke(theme.colors.border, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }
}
