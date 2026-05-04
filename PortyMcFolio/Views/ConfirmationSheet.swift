import SwiftUI

/// Branded two-button confirmation dialog. Replaces native `.alert` in places
/// where the app's themed language is important.
///
/// Shape: title → caller-supplied middle content → Cancel (plain) + Confirm (filled pill).
/// Keyboard: Esc cancels, Return confirms.
struct ConfirmationSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    let title: String
    let confirmLabel: String
    let isDestructive: Bool
    let onConfirm: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(DT.Typography.headline)
                .foregroundStyle(theme.colors.textPrimary)
                .padding(.bottom, DT.Spacing.md)

            content()
                .padding(.bottom, DT.Spacing.xl)

            HStack(spacing: DT.Spacing.sm) {
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
                    onConfirm()
                    dismiss()
                } label: {
                    Text(confirmLabel)
                        .font(DT.Typography.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, DT.Spacing.lg)
                        .padding(.vertical, DT.Spacing.sm)
                        .background(
                            isDestructive ? theme.colors.error : theme.colors.accent,
                            in: RoundedRectangle(cornerRadius: DT.Radius.small)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DT.Spacing.xl)
        .frame(width: 400)
        .background(theme.colors.surface)
    }
}

/// Rename-specific wrapper: owns the `@FocusState` needed to auto-focus the
/// TextField on appear, and wires Return (via `.onSubmit`) to confirm.
struct RenameFolderSheet: View {
    @Environment(\.theme) private var theme
    @FocusState private var isFocused: Bool

    @Binding var name: String
    let onConfirm: () -> Void

    var body: some View {
        ConfirmationSheet(
            title: "Rename Folder",
            confirmLabel: "Rename",
            isDestructive: false,
            onConfirm: onConfirm
        ) {
            TextField("Folder name", text: $name)
                .textFieldStyle(.plain)
                .font(DT.Typography.body)
                .foregroundStyle(theme.colors.textPrimary)
                .padding(DT.Spacing.sm)
                .background(
                    theme.colors.background,
                    in: RoundedRectangle(cornerRadius: DT.Radius.small)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.small)
                        .stroke(theme.colors.border, lineWidth: 0.5)
                )
                .focused($isFocused)
                .onSubmit(onConfirm)
                .onAppear { isFocused = true }
        }
    }
}

/// Rename a file using the project's naming convention:
/// `{year}_{projectSlug}_{description}.{ext}` — matching Cleanup mode.
/// Binding holds just the description; prefix and extension are shown but
/// non-editable, and the description is slugged on submit.
struct RenameFileSheet: View {
    @Environment(\.theme) private var theme
    @FocusState private var isFocused: Bool

    let prefix: String
    @Binding var name: String
    let fileExtension: String
    let onConfirm: () -> Void

    private var previewName: String {
        let slug = name.isEmpty ? "\u{2026}" : Slug.underscoreFrom(name)
        return fileExtension.isEmpty
            ? "\(prefix)\(slug)"
            : "\(prefix)\(slug).\(fileExtension)"
    }

    var body: some View {
        ConfirmationSheet(
            title: "Rename File",
            confirmLabel: "Rename",
            isDestructive: false,
            onConfirm: onConfirm
        ) {
            VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                HStack(spacing: 0) {
                    Text(prefix)
                        .font(DT.Typography.mono)
                        .foregroundStyle(theme.colors.textTertiary)
                        .padding(.horizontal, DT.Spacing.sm)
                        .padding(.vertical, DT.Spacing.sm)
                        .background(theme.colors.backgroundAlt)

                    TextField("description", text: $name)
                        .textFieldStyle(.plain)
                        .font(DT.Typography.mono)
                        .foregroundStyle(theme.colors.textPrimary)
                        .padding(.horizontal, DT.Spacing.sm)
                        .padding(.vertical, DT.Spacing.sm)
                        .focused($isFocused)
                        .onSubmit(onConfirm)

                    if !fileExtension.isEmpty {
                        Text(".\(fileExtension)")
                            .font(DT.Typography.mono)
                            .foregroundStyle(theme.colors.textTertiary)
                            .padding(.horizontal, DT.Spacing.sm)
                            .padding(.vertical, DT.Spacing.sm)
                            .background(theme.colors.backgroundAlt)
                    }
                }
                .background(theme.colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.small))
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.small)
                        .stroke(theme.colors.border, lineWidth: 0.5)
                )

                Text("\u{2192} \(previewName)")
                    .font(DT.Typography.monoSmall)
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .onAppear { isFocused = true }
        }
    }
}
