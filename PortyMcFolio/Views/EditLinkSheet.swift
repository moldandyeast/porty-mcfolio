import SwiftUI

/// Edit an existing link's title and annotation. URL is displayed read-only
/// at the top for reference; the uid and URL itself cannot be changed here.
struct EditLinkSheet: View {
    let link: LinkItem
    let projectFolderURL: URL
    var onSaved: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) var theme
    @FocusState private var focusedField: Field?

    @State private var title: String
    @State private var annotation: String
    @State private var errorMessage: String?

    private enum Field { case title, annotation }

    init(link: LinkItem, projectFolderURL: URL, onSaved: (() -> Void)? = nil) {
        self.link = link
        self.projectFolderURL = projectFolderURL
        self.onSaved = onSaved
        _title = State(initialValue: link.title)
        _annotation = State(initialValue: link.annotation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Read-only URL
            Text(link.url.absoluteString)
                .font(DT.Typography.caption)
                .foregroundStyle(theme.colors.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.bottom, DT.Spacing.xl)

            // Title
            VStack(alignment: .leading, spacing: DT.Spacing.xs) {
                Text("TITLE")
                    .font(DT.Typography.micro)
                    .foregroundStyle(theme.colors.textTertiary)
                    .tracking(1)

                TextField("Optional", text: $title)
                    .font(DT.Typography.body)
                    .foregroundStyle(theme.colors.textPrimary)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, DT.Spacing.sm)
                    .padding(.vertical, DT.Spacing.sm)
                    .background(theme.colors.backgroundAlt, in: RoundedRectangle(cornerRadius: DT.Radius.small))
                    .overlay(RoundedRectangle(cornerRadius: DT.Radius.small).stroke(theme.colors.border, lineWidth: 0.5))
                    .focused($focusedField, equals: .title)
                    .onSubmit { save() }
            }
            .padding(.bottom, DT.Spacing.lg)

            // Annotation
            VStack(alignment: .leading, spacing: DT.Spacing.xs) {
                Text("NOTES")
                    .font(DT.Typography.micro)
                    .foregroundStyle(theme.colors.textTertiary)
                    .tracking(1)

                TextField("Optional", text: $annotation)
                    .font(DT.Typography.body)
                    .foregroundStyle(theme.colors.textPrimary)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, DT.Spacing.sm)
                    .padding(.vertical, DT.Spacing.sm)
                    .background(theme.colors.backgroundAlt, in: RoundedRectangle(cornerRadius: DT.Radius.small))
                    .overlay(RoundedRectangle(cornerRadius: DT.Radius.small).stroke(theme.colors.border, lineWidth: 0.5))
                    .focused($focusedField, equals: .annotation)
                    .onSubmit { save() }
            }
            .padding(.bottom, DT.Spacing.xl)

            if let errorMessage {
                Text(errorMessage)
                    .font(DT.Typography.caption)
                    .foregroundStyle(theme.colors.error)
                    .padding(.bottom, DT.Spacing.sm)
            }

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
                    save()
                } label: {
                    Text("Save")
                        .font(DT.Typography.body)
                        .fontWeight(.medium)
                        .foregroundStyle(theme.colors.accentForeground)
                        .padding(.horizontal, DT.Spacing.lg)
                        .padding(.vertical, DT.Spacing.sm)
                        .background(theme.colors.accent, in: RoundedRectangle(cornerRadius: DT.Radius.small))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DT.Spacing.xl)
        .frame(width: 400)
        .background(theme.colors.surface)
        .onAppear { focusedField = .title }
    }

    private func save() {
        let updated = LinkItem(
            uid: link.uid,
            url: link.url,
            title: title.trimmingCharacters(in: .whitespaces),
            annotation: annotation.trimmingCharacters(in: .whitespaces),
            date: link.date
        )
        let fileURL = projectFolderURL.appendingPathComponent(LinkItem.fileName(uid: link.uid))
        do {
            try updated.toMarkdown().write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
            return
        }
        onSaved?()
        dismiss()
    }
}
