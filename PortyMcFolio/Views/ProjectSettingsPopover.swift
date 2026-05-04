import SwiftUI

struct ProjectSettingsPopover: View {
    let project: Project
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @Environment(\.theme) var theme

    @State private var title: String = ""
    @State private var clients: [String] = []
    @State private var status: ProjectStatus = .empty
    @State private var tags: [String] = []
    @State private var teaser: String = ""
    @State private var teaserImage: NSImage?
    @State private var hidden: Bool = false
    @State private var errorMessage: String?
    @State private var when: WhenValue = .yearOnly(year: 2025, anchor: Date())

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero title
            TextField("Project title", text: $title)
                .font(DT.Typography.largeTitle)
                .foregroundStyle(theme.colors.textPrimary)
                .textFieldStyle(.plain)
                .padding(.bottom, DT.Spacing.xl)

            // Year
            settingsField("YEAR") {
                WhenPicker(value: $when)
            }

            // Client
            settingsField("CLIENT") {
                TagChipInput(
                    tags: $clients,
                    placeholder: "Add client\u{2026}",
                    suggestions: appState.suggestedClients
                )
            }

            // Status
            settingsField("STATUS") {
                HStack(spacing: DT.Spacing.sm) {
                    ForEach([ProjectStatus.empty, .inProgress, .archived], id: \.self) { s in
                        Button {
                            status = s
                        } label: {
                            Text(s.displayName)
                                .font(DT.Typography.caption)
                                .foregroundStyle(status == s ? theme.colors.textPrimary : theme.colors.textTertiary)
                                .padding(.horizontal, DT.Spacing.sm)
                                .padding(.vertical, DT.Spacing.xs)
                                .background(
                                    status == s ? theme.colors.surfaceHover : Color.clear,
                                    in: RoundedRectangle(cornerRadius: DT.Radius.small)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: DT.Radius.small)
                                        .stroke(status == s ? theme.colors.border : Color.clear, lineWidth: 0.5)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Tags
            settingsField("TAGS") {
                TagChipInput(tags: $tags, placeholder: "Add tag\u{2026}", suggestions: appState.suggestedTags)
            }

            // Teaser
            settingsField("TEASER") {
                VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                    if let image = teaserImage {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .frame(height: 140)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.medium))
                            .allowsHitTesting(false)
                    }

                    HStack(spacing: DT.Spacing.sm) {
                        if !teaser.isEmpty {
                            Text(teaser)
                                .font(DT.Typography.caption)
                                .foregroundStyle(theme.colors.textTertiary)
                                .lineLimit(1)
                            Spacer()
                            Button("Clear") {
                                teaser = ""
                                teaserImage = nil
                            }
                            .font(DT.Typography.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(theme.colors.textSecondary)

                            Button("Change\u{2026}") { pickTeaser() }
                                .font(DT.Typography.caption)
                                .buttonStyle(.plain)
                                .foregroundStyle(theme.colors.accent)
                        } else {
                            Button("Choose image\u{2026}") { pickTeaser() }
                                .font(DT.Typography.caption)
                                .buttonStyle(.plain)
                                .foregroundStyle(theme.colors.accent)
                        }
                    }
                }
            }

            // Visibility
            settingsField("VISIBILITY") {
                HStack(spacing: DT.Spacing.sm) {
                    ForEach([(false, "Visible", "eye"), (true, "Hidden", "eye.slash")], id: \.0) { value, label, icon in
                        Button {
                            hidden = value
                        } label: {
                            HStack(spacing: DT.Spacing.xs) {
                                Image(systemName: icon)
                                    .font(.system(size: 10))
                                Text(label)
                                    .font(DT.Typography.caption)
                            }
                            .foregroundStyle(hidden == value ? theme.colors.textPrimary : theme.colors.textTertiary)
                            .padding(.horizontal, DT.Spacing.sm)
                            .padding(.vertical, DT.Spacing.xs)
                            .background(
                                hidden == value ? theme.colors.surfaceHover : Color.clear,
                                in: RoundedRectangle(cornerRadius: DT.Radius.small)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DT.Radius.small)
                                    .stroke(hidden == value ? theme.colors.border : Color.clear, lineWidth: 0.5)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Error
            if let error = errorMessage {
                Text(error)
                    .font(DT.Typography.caption)
                    .foregroundStyle(theme.colors.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DT.Spacing.sm)
            }

            // Actions
            HStack(spacing: DT.Spacing.md) {
                Spacer()

                Button {
                    isPresented = false
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
                        .foregroundStyle(canSave ? theme.colors.accentForeground : theme.colors.textTertiary)
                        .padding(.horizontal, DT.Spacing.lg)
                        .padding(.vertical, DT.Spacing.sm)
                        .background(
                            canSave ? theme.colors.accent : theme.colors.surfaceHover,
                            in: RoundedRectangle(cornerRadius: DT.Radius.small)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(.top, DT.Spacing.xl)
        }
        .padding(DT.Spacing.xl)
        .frame(width: 400)
        .background(theme.colors.surface)
        .onAppear {
            title = project.title
            clients = project.client
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            status = project.status
            tags = project.tags
            teaser = project.teaser
            hidden = project.hidden
            when = WhenValue(
                date: project.date,
                dateEnd: project.dateEnd,
                yearOnlyYear: project.dateEnd == nil ? project.year : nil
            )
            loadTeaserImage()
        }
    }

    // MARK: - Field wrapper

    private func settingsField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DT.Spacing.xs) {
            Text(label)
                .font(DT.Typography.micro)
                .foregroundStyle(theme.colors.textTertiary)
                .tracking(1)
            content()
        }
        .padding(.bottom, DT.Spacing.lg)
    }

    // MARK: - Actions

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }
        errorMessage = nil

        do {
            try appState.updateProjectMetadata(
                project: project,
                title: trimmedTitle,
                client: clients.joined(separator: ", "),
                status: status,
                tags: tags,
                teaser: teaser,
                hidden: hidden,
                when: when
            )
            isPresented = false
        } catch {
            AppLogger.ui.error("ProjectSettings save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func loadTeaserImage() {
        guard !teaser.isEmpty else {
            teaserImage = nil
            return
        }
        let url = project.folderURL.appendingPathComponent(teaser)
        teaserImage = NSImage(contentsOf: url)
    }

    private func pickTeaser() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = project.folderURL
        panel.allowedContentTypes = [.image]
        panel.message = "Select teaser image"
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let projectPath = project.folderURL.path + "/"
        let relativePath: String
        if url.path.hasPrefix(projectPath) {
            relativePath = url.path.replacingOccurrences(of: projectPath, with: "")
        } else {
            // File is outside the project folder — copy it in
            let dest = project.folderURL.appendingPathComponent(url.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.trashItem(at: dest, resultingItemURL: nil)
                }
                try FileManager.default.copyItem(at: url, to: dest)
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Could not copy image: \(error.localizedDescription)"
                }
                return
            }
            relativePath = url.lastPathComponent
        }

        let image = NSImage(contentsOf: url)

        DispatchQueue.main.async {
            self.teaser = relativePath
            self.teaserImage = image
        }
    }
}
