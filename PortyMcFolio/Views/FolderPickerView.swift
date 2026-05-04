import SwiftUI
import AppKit

struct FolderPickerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.theme) var theme

    var body: some View {
        VStack(spacing: DT.Spacing.lg) {
            Text("PortyMcFolio")
                .font(DT.Typography.largeTitle)
                .fontWeight(.bold)

            Text("Choose a folder to store your portfolio projects.")
                .font(DT.Typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                openFolderPicker()
            } label: {
                Text("Choose Folder\u{2026}")
                    .font(DT.Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(theme.colors.accentForeground)
                    .padding(.horizontal, DT.Spacing.lg)
                    .padding(.vertical, DT.Spacing.sm)
                    .background(theme.colors.accent, in: RoundedRectangle(cornerRadius: DT.Radius.small))
            }
            .buttonStyle(.plain)
        }
        .padding(DT.Spacing.xxl)
        .frame(minWidth: 400, minHeight: 300)
    }

    private func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select a folder to use as your portfolio root."

        if panel.runModal() == .OK, let url = panel.url {
            appState.setRoot(url)
        }
    }
}
