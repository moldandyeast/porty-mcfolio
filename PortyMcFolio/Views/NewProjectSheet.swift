import SwiftUI

struct NewProjectSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) var theme

    @State private var title = ""
    @State private var when: WhenValue = .yearOnly(year: Calendar.current.component(.year, from: Date()), anchor: Date())
    @State private var clients: [String] = []
    @State private var tags: [String] = []
    @FocusState private var focusedField: Field?

    private enum Field { case title, tags }

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var folderYear: Int {
        ProjectMetadataMutation.resolveFolderYear(
            when: when,
            currentYear: Calendar.current.component(.year, from: Date())
        )
    }

    private var folderPreview: String {
        let slug = Slug.underscoreFrom(title.isEmpty ? "untitled" : title)
        return "\(folderYear)_\(slug)_xxxxxxxx"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero title
            TextField("Project title", text: $title)
                .font(DT.Typography.largeTitle)
                .foregroundStyle(theme.colors.textPrimary)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .title)
                .onSubmit { if canCreate { create() } }
                .padding(.bottom, DT.Spacing.xl)

            // When picker (replaces the YEAR stepper)
            VStack(alignment: .leading, spacing: DT.Spacing.xs) {
                Text("WHEN")
                    .font(DT.Typography.micro)
                    .foregroundStyle(theme.colors.textTertiary)
                    .tracking(1)

                WhenPicker(value: $when)
            }
            .padding(.bottom, DT.Spacing.lg)

            // Client
            VStack(alignment: .leading, spacing: DT.Spacing.xs) {
                Text("CLIENT")
                    .font(DT.Typography.micro)
                    .foregroundStyle(theme.colors.textTertiary)
                    .tracking(1)

                TagChipInput(
                    tags: $clients,
                    placeholder: "Type and press Enter\u{2026}",
                    suggestions: appState.suggestedClients
                )
            }
            .padding(.bottom, DT.Spacing.lg)

            // Tags
            VStack(alignment: .leading, spacing: DT.Spacing.xs) {
                Text("TAGS")
                    .font(DT.Typography.micro)
                    .foregroundStyle(theme.colors.textTertiary)
                    .tracking(1)

                TagChipInput(
                    tags: $tags,
                    placeholder: "Type and press Enter\u{2026}",
                    suggestions: appState.suggestedTags
                )
            }
            .padding(.bottom, DT.Spacing.xl)

            // Folder preview
            HStack(spacing: DT.Spacing.xs) {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                Text(folderPreview)
                    .font(DT.Typography.monoSmall)
            }
            .foregroundStyle(theme.colors.textTertiary)
            .padding(.bottom, DT.Spacing.xl)

            // Actions
            HStack {
                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(DT.Typography.body)
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(.horizontal, DT.Spacing.lg)
                        .padding(.vertical, DT.Spacing.sm)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Button {
                    create()
                } label: {
                    Text("Create")
                        .font(DT.Typography.body)
                        .fontWeight(.medium)
                        .foregroundStyle(canCreate ? theme.colors.accentForeground : theme.colors.textTertiary)
                        .padding(.horizontal, DT.Spacing.lg)
                        .padding(.vertical, DT.Spacing.sm)
                        .background(
                            canCreate ? theme.colors.accent : theme.colors.surfaceHover,
                            in: RoundedRectangle(cornerRadius: DT.Radius.small)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
            }
        }
        .padding(DT.Spacing.xl)
        .frame(width: 400)
        .background(theme.colors.surface)
        .onAppear { focusedField = .title }
    }

    private func create() {
        appState.createProject(title: title, when: when, client: clients.joined(separator: ", "), tags: tags)
        dismiss()
    }
}
