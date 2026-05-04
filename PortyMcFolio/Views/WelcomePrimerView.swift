import SwiftUI

/// Empty-state primer shown on `ProjectListView` when the user has picked a
/// portfolio root but hasn't created any projects yet. The card disappears
/// for good once any project exists; re-access via Settings → Manual.
struct WelcomePrimerView: View {
    let onCreate: () -> Void
    @Environment(\.theme) var theme

    private struct Bullet: Identifiable {
        let id = UUID()
        let symbol: String
        let label: String
    }

    private static let bullets: [Bullet] = [
        Bullet(symbol: "folder",
               label: "Each project is a folder with a markdown file"),
        Bullet(symbol: "photo.on.rectangle",
               label: "Drop in files: images, video, PDFs"),
        Bullet(symbol: "link",
               label: "Add links with previews"),
        Bullet(symbol: "square.and.pencil",
               label: "Edit the markdown to describe the work"),
        Bullet(symbol: "star.fill",
               label: "Mark favorites for the carousel"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.lg) {
            VStack(alignment: .leading, spacing: DT.Spacing.xs) {
                Text("WELCOME")
                    .font(DT.Typography.micro)
                    .tracking(1.4)
                    .foregroundStyle(theme.colors.textTertiary)
                Text("How PortyMcFolio works")
                    .font(DT.Typography.title)
                    .foregroundStyle(theme.colors.textPrimary)
            }

            VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                ForEach(Self.bullets) { bullet in
                    HStack(alignment: .firstTextBaseline, spacing: DT.Spacing.sm) {
                        Image(systemName: bullet.symbol)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.colors.textSecondary)
                            .frame(width: 18, alignment: .center)
                        Text(bullet.label)
                            .font(DT.Typography.body)
                            .foregroundStyle(theme.colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Button(action: onCreate) {
                Text("Create your first project")
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
        .frame(maxWidth: 420)
        .background(theme.colors.backgroundAlt, in: RoundedRectangle(cornerRadius: DT.Radius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.medium)
                .stroke(theme.colors.border, lineWidth: 1)
        )
    }
}
