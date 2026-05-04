import SwiftUI

/// One-time centered primer shown on `ProjectDetailView` when a user enters
/// any project for the first time. Explains the six view modes with name,
/// keyboard shortcut, and a one-line description. Dismissable; sets
/// `hasSeenProjectOnboarding` so it never reappears.
struct ProjectOnboardingPrimerView: View {
    let onDismiss: () -> Void
    @Environment(\.theme) var theme

    private struct Mode: Identifiable {
        let id: String
        let symbol: String
        let name: String
        let shortcut: String
        let description: String
    }

    private static let modes: [Mode] = [
        Mode(id: "editor",
             symbol: "doc.text",
             name: "Editor",
             shortcut: "\u{2318}1",
             description: "Write the markdown that describes the work"),
        Mode(id: "preview",
             symbol: "eye",
             name: "Preview",
             shortcut: "\u{2318}2",
             description: "Rendered markdown with embeds and link cards"),
        Mode(id: "splitGallery",
             symbol: "square.grid.2x2",
             name: "Editor + Gallery",
             shortcut: "\u{2318}3",
             description: "Editor and your media side-by-side"),
        Mode(id: "splitList",
             symbol: "list.bullet",
             name: "Editor + List",
             shortcut: "\u{2318}4",
             description: "Editor and a sortable file list"),
        Mode(id: "splitLinks",
             symbol: "link",
             name: "Editor + Links",
             shortcut: "\u{2318}5",
             description: "Editor and saved links"),
        Mode(id: "carousel",
             symbol: "rectangle.stack.badge.play",
             name: "Carousel",
             shortcut: "\u{2318}6",
             description: "Full-screen slideshow of favorites"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.lg) {
            VStack(alignment: .leading, spacing: DT.Spacing.xs) {
                Text("WELCOME TO YOUR FIRST PROJECT")
                    .font(DT.Typography.micro)
                    .tracking(1.4)
                    .foregroundStyle(theme.colors.textTertiary)
                Text("Switch views to work different ways")
                    .font(DT.Typography.title)
                    .foregroundStyle(theme.colors.textPrimary)
            }

            VStack(alignment: .leading, spacing: DT.Spacing.md) {
                ForEach(Self.modes) { mode in
                    HStack(alignment: .top, spacing: DT.Spacing.md) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 16))
                            .foregroundStyle(theme.colors.textSecondary)
                            .frame(width: 22, alignment: .center)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.name)
                                .font(DT.Typography.body)
                                .fontWeight(.medium)
                                .foregroundStyle(theme.colors.textPrimary)
                            Text(mode.description)
                                .font(DT.Typography.caption)
                                .foregroundStyle(theme.colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Text(mode.shortcut)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.colors.textTertiary)
                            .padding(.horizontal, DT.Spacing.sm)
                            .padding(.vertical, 3)
                            .background(theme.colors.backgroundAlt, in: RoundedRectangle(cornerRadius: DT.Radius.small))
                            .overlay(
                                RoundedRectangle(cornerRadius: DT.Radius.small)
                                    .stroke(theme.colors.border, lineWidth: 0.5)
                            )
                    }
                }
            }

            Text("All shortcuts in Settings → Manual → Keyboard Shortcuts.")
                .font(DT.Typography.caption)
                .foregroundStyle(theme.colors.textTertiary)

            Button(action: onDismiss) {
                Text("Got it")
                    .font(DT.Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(theme.colors.accentForeground)
                    .padding(.horizontal, DT.Spacing.lg)
                    .padding(.vertical, DT.Spacing.sm)
                    .background(theme.colors.accent, in: RoundedRectangle(cornerRadius: DT.Radius.small))
            }
            .buttonStyle(.plain)
        }
        .padding(DT.Spacing.xl)
        .frame(maxWidth: 480)
        .background(theme.colors.backgroundAlt, in: RoundedRectangle(cornerRadius: DT.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.medium)
                .stroke(theme.colors.border, lineWidth: 1)
        )
    }
}
