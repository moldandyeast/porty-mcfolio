import SwiftUI

enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
}

struct StyleGuideView: View {
    @Environment(\.theme) var theme
    @State private var appearanceMode: AppearanceMode = .system

    private var colorSchemeOverride: ColorScheme? {
        switch appearanceMode {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with appearance toggle
            HStack {
                Text("Style Guide")
                    .font(DT.Typography.largeTitle)
                    .foregroundStyle(theme.colors.textPrimary)

                Spacer()

                Picker("", selection: $appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .padding(.horizontal, DT.Spacing.xxl)
            .padding(.vertical, DT.Spacing.xl)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DT.Spacing.xxl) {
                    colorPaletteSection
                    typographySection
                    spacingSection
                    radiusSection
                    shadowSection
                    componentSection
                }
                .padding(DT.Spacing.xxl)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(theme.colors.background)
        .preferredColorScheme(colorSchemeOverride)
    }

    // MARK: - Color Palette

    @ViewBuilder
    private var colorPaletteSection: some View {
        sectionHeader("Colors")

        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: DT.Spacing.lg)], spacing: DT.Spacing.lg) {
            colorSwatch("background", theme.colors.background, bordered: true)
            colorSwatch("surface", theme.colors.surface, bordered: true)
            colorSwatch("surfaceHover", theme.colors.surfaceHover)
            colorSwatch("textPrimary", theme.colors.textPrimary)
            colorSwatch("textSecondary", theme.colors.textSecondary)
            colorSwatch("textTertiary", theme.colors.textTertiary)
            colorSwatch("border", theme.colors.border, bordered: true)
            colorSwatch("accent", theme.colors.accent)
            colorSwatch("statusDraft", theme.colors.statusDraft)
            colorSwatch("statusActive", theme.colors.statusActive)
            colorSwatch("statusComplete", theme.colors.statusComplete)
            colorSwatch("statusArchived", theme.colors.statusArchived)
        }
    }

    private func colorSwatch(_ name: String, _ color: Color, bordered: Bool = false) -> some View {
        VStack(spacing: DT.Spacing.sm) {
            RoundedRectangle(cornerRadius: DT.Radius.small)
                .fill(color)
                .frame(height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.small)
                        .strokeBorder(theme.colors.border, lineWidth: bordered ? 1 : 0)
                )

            Text(name)
                .font(DT.Typography.micro)
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(DT.Typography.title)
            .foregroundStyle(theme.colors.textPrimary)
    }

    // MARK: - Typography

    @ViewBuilder
    private var typographySection: some View {
        sectionHeader("Typography")

        VStack(alignment: .leading, spacing: DT.Spacing.lg) {
            typographyRow("largeTitle", DT.Typography.largeTitle, detail: "28pt Semibold")
            typographyRow("title", DT.Typography.title, detail: "18pt Semibold")
            typographyRow("headline", DT.Typography.headline, detail: "15pt Medium")
            typographyRow("body", DT.Typography.body, detail: "14pt Regular")
            typographyRow("caption", DT.Typography.caption, detail: "12pt Regular")
            typographyRow("micro", DT.Typography.micro, detail: "10pt Medium")
        }
    }

    private func typographyRow(_ name: String, _ font: Font, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Portfolio \u{2014} 2026")
                .font(font)
                .foregroundStyle(theme.colors.textPrimary)
                .frame(minWidth: 280, alignment: .leading)

            Text(name)
                .font(DT.Typography.micro)
                .foregroundStyle(theme.colors.textTertiary)
                .frame(width: 80, alignment: .leading)

            Text(detail)
                .font(DT.Typography.micro)
                .foregroundStyle(theme.colors.textTertiary)
        }
    }

    // MARK: - Spacing

    @ViewBuilder
    private var spacingSection: some View {
        sectionHeader("Spacing")

        VStack(alignment: .leading, spacing: DT.Spacing.md) {
            spacingRow("xs", DT.Spacing.xs)
            spacingRow("sm", DT.Spacing.sm)
            spacingRow("md", DT.Spacing.md)
            spacingRow("lg", DT.Spacing.lg)
            spacingRow("xl", DT.Spacing.xl)
            spacingRow("xxl", DT.Spacing.xxl)
        }
    }

    private func spacingRow(_ name: String, _ value: CGFloat) -> some View {
        HStack(spacing: DT.Spacing.md) {
            Text(name)
                .font(DT.Typography.micro)
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: 30, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(theme.colors.accent.opacity(0.3))
                .frame(width: value, height: 20)

            Text("\(Int(value))pt")
                .font(DT.Typography.micro)
                .foregroundStyle(theme.colors.textTertiary)
        }
    }

    // MARK: - Corner Radius

    @ViewBuilder
    private var radiusSection: some View {
        sectionHeader("Corner Radius")

        HStack(spacing: DT.Spacing.xl) {
            radiusSample("small", DT.Radius.small)
            radiusSample("medium", DT.Radius.medium)
            radiusSample("large", DT.Radius.large)
        }
    }

    private func radiusSample(_ name: String, _ radius: CGFloat) -> some View {
        VStack(spacing: DT.Spacing.sm) {
            RoundedRectangle(cornerRadius: radius)
                .fill(theme.colors.surface)
                .frame(width: 100, height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(theme.colors.border, lineWidth: 1)
                )

            Text("\(name) — \(Int(radius))pt")
                .font(DT.Typography.micro)
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    // MARK: - Shadows

    @ViewBuilder
    private var shadowSection: some View {
        sectionHeader("Shadows")

        HStack(spacing: DT.Spacing.xl) {
            shadowSample("card", DT.Shadow.card)
            shadowSample("floating", DT.Shadow.floating)
        }
    }

    private func shadowSample(_ name: String, _ style: DT.Shadow.Style) -> some View {
        VStack(spacing: DT.Spacing.sm) {
            RoundedRectangle(cornerRadius: DT.Radius.medium)
                .fill(theme.colors.surface)
                .frame(width: 140, height: 80)
                .dtShadow(style)

            Text(name)
                .font(DT.Typography.micro)
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    // MARK: - Component Mockups

    @ViewBuilder
    private var componentSection: some View {
        sectionHeader("Components")

        // Status badges
        VStack(alignment: .leading, spacing: DT.Spacing.md) {
            Text("Status Badges")
                .font(DT.Typography.headline)
                .foregroundStyle(theme.colors.textSecondary)

            HStack(spacing: DT.Spacing.sm) {
                mockBadge("Draft", theme.colors.statusDraft)
                mockBadge("Active", theme.colors.statusActive)
                mockBadge("Complete", theme.colors.statusComplete)
                mockBadge("Archived", theme.colors.statusArchived)
            }
        }

        // Sample project card
        VStack(alignment: .leading, spacing: DT.Spacing.md) {
            Text("Project Card")
                .font(DT.Typography.headline)
                .foregroundStyle(theme.colors.textSecondary)

            mockProjectCard
        }
    }

    private func mockBadge(_ label: String, _ color: Color) -> some View {
        Text(label)
            .font(DT.Typography.micro)
            .foregroundStyle(color)
            .padding(.horizontal, DT.Spacing.sm)
            .padding(.vertical, DT.Spacing.xs)
            .background(color.opacity(DT.Opacity.selection))
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.small))
    }

    private var mockProjectCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image placeholder
            RoundedRectangle(cornerRadius: 0)
                .fill(theme.colors.surfaceHover)
                .frame(height: 120)
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundStyle(theme.colors.textTertiary)
                )

            VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                HStack {
                    Text("2026")
                        .font(DT.Typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                    Spacer()
                    mockBadge("Draft", theme.colors.statusDraft)
                }

                Text("Brand Identity System")
                    .font(DT.Typography.title)
                    .foregroundStyle(theme.colors.textPrimary)

                Text("Acme Corp")
                    .font(DT.Typography.body)
                    .foregroundStyle(theme.colors.textSecondary)

                HStack(spacing: DT.Spacing.xs) {
                    mockTag("branding")
                    mockTag("identity")
                    mockTag("print")
                }
            }
            .padding(DT.Spacing.lg)
        }
        .frame(width: 320)
        .background(theme.colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.medium))
        .dtShadow(DT.Shadow.card)
    }

    private func mockTag(_ label: String) -> some View {
        Text(label)
            .font(DT.Typography.micro)
            .foregroundStyle(theme.colors.textSecondary)
            .padding(.horizontal, DT.Spacing.sm)
            .padding(.vertical, DT.Spacing.xs)
            .background(theme.colors.surfaceHover)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.small))
    }
}
