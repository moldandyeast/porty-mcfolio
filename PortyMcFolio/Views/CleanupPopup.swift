import SwiftUI
import QuickLookThumbnailing

struct CleanupPopup: View {
    let project: Project
    let initialFiles: [URL]
    @Environment(\.theme) var theme
    let existingFolders: [String]
    @Binding var isPresented: Bool
    let startIndex: Int
    let onFileRenamed: () -> Void
    let onFileMoved: ((_ oldRelative: String, _ newRelative: String) -> Void)?

    @State private var files: [URL] = []
    @State private var currentIndex: Int = 0
    @State private var userInput: String = ""
    @State private var selectedFolder: String = "."
    @State private var thumbnail: NSImage?
    @State private var errorMessage: String?
    @State private var isCreatingFolder = false
    @State private var newFolderName: String = ""

    private var currentFile: URL? {
        guard currentIndex >= 0 && currentIndex < files.count else { return nil }
        return files[currentIndex]
    }

    private var prefix: String {
        "\(project.year)_\(Slug.underscoreFrom(project.title))_"
    }

    private var currentExtension: String {
        currentFile?.pathExtension ?? ""
    }

    private var previewName: String {
        let name = userInput.isEmpty ? "\u{2026}" : Slug.underscoreFrom(userInput)
        return "\(prefix)\(name).\(currentExtension)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Preview area
            ZStack {
                theme.colors.backgroundAlt
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 320, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.medium))
                } else {
                    Image(systemName: "doc")
                        .font(.system(size: 48))
                        .foregroundStyle(theme.colors.textTertiary)
                }
            }
            .frame(height: 240)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: DT.Radius.xlarge,
                    topTrailingRadius: DT.Radius.xlarge
                )
            )

            VStack(alignment: .leading, spacing: DT.Spacing.lg) {
                // Progress + filename
                HStack {
                    Text("FILE \(currentIndex + 1) OF \(files.count)")
                        .font(DT.Typography.micro)
                        .foregroundStyle(theme.colors.textTertiary)
                        .tracking(1)
                    Spacer()
                    Text(currentFile?.lastPathComponent ?? "")
                        .font(DT.Typography.monoSmall)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                }

                // Rename input — three parts
                HStack(spacing: 0) {
                    Text(prefix)
                        .font(DT.Typography.mono)
                        .foregroundStyle(theme.colors.textTertiary)
                        .padding(.horizontal, DT.Spacing.sm)
                        .padding(.vertical, DT.Spacing.sm)
                        .background(theme.colors.backgroundAlt)

                    TextField("description", text: $userInput)
                        .textFieldStyle(.plain)
                        .font(DT.Typography.mono)
                        .foregroundStyle(theme.colors.textPrimary)
                        .padding(.horizontal, DT.Spacing.sm)
                        .padding(.vertical, DT.Spacing.sm)
                        .onSubmit { rename() }

                    Text(".\(currentExtension)")
                        .font(DT.Typography.mono)
                        .foregroundStyle(theme.colors.textTertiary)
                        .padding(.horizontal, DT.Spacing.sm)
                        .padding(.vertical, DT.Spacing.sm)
                        .background(theme.colors.backgroundAlt)
                }
                .background(theme.colors.surface)
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.small))
                .overlay(RoundedRectangle(cornerRadius: DT.Radius.small).stroke(theme.colors.border, lineWidth: 0.5))

                // Preview of result
                Text("\u{2192} \(previewName)")
                    .font(DT.Typography.monoSmall)
                    .foregroundStyle(theme.colors.textTertiary)

                // Folder picker
                VStack(alignment: .leading, spacing: DT.Spacing.xs) {
                    Text("FOLDER")
                        .font(DT.Typography.micro)
                        .foregroundStyle(theme.colors.textTertiary)
                        .tracking(1)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DT.Spacing.xs) {
                            folderChip("/ (keep here)", tag: ".")
                            folderChip(project.title.isEmpty ? "Root" : project.title, tag: "")
                            ForEach(existingFolders, id: \.self) { folder in
                                folderChip(folder, tag: folder)
                            }
                            Button {
                                isCreatingFolder = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(theme.colors.textTertiary)
                                    .frame(width: 24, height: 24)
                                    .background(theme.colors.backgroundAlt, in: RoundedRectangle(cornerRadius: DT.Radius.small))
                                    .overlay(RoundedRectangle(cornerRadius: DT.Radius.small).stroke(theme.colors.border, lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .help("New folder")
                        }
                    }
                    .popover(isPresented: $isCreatingFolder) {
                        VStack(spacing: DT.Spacing.sm) {
                            TextField("Folder name", text: $newFolderName)
                                .textFieldStyle(.plain)
                                .font(DT.Typography.body)
                                .padding(.horizontal, DT.Spacing.sm)
                                .padding(.vertical, DT.Spacing.sm)
                                .background(theme.colors.backgroundAlt, in: RoundedRectangle(cornerRadius: DT.Radius.small))
                                .overlay(RoundedRectangle(cornerRadius: DT.Radius.small).stroke(theme.colors.border, lineWidth: 0.5))
                                .frame(width: 180)
                                .onSubmit { createFolder() }
                            HStack {
                                Button("Cancel") {
                                    newFolderName = ""
                                    isCreatingFolder = false
                                }
                                .font(DT.Typography.caption)
                                .buttonStyle(.plain)
                                .foregroundStyle(theme.colors.textSecondary)

                                Button {
                                    createFolder()
                                } label: {
                                    Text("Create")
                                        .font(DT.Typography.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(theme.colors.accentForeground)
                                        .padding(.horizontal, DT.Spacing.md)
                                        .padding(.vertical, DT.Spacing.xs)
                                        .background(theme.colors.accent, in: RoundedRectangle(cornerRadius: DT.Radius.small))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(DT.Spacing.md)
                    }
                }

                // Error
                if let error = errorMessage {
                    Text(error)
                        .font(DT.Typography.micro)
                        .foregroundStyle(theme.colors.error)
                }

                // Actions
                HStack {
                    HStack(spacing: DT.Spacing.sm) {
                        navButton(icon: "arrow.left") { navigatePrevious() }
                            .keyboardShortcut(.leftArrow, modifiers: .command)

                        navButton(icon: "arrow.right") { navigateNext() }
                            .keyboardShortcut(.rightArrow, modifiers: .command)

                        Text("\u{2318}\u{2190} \u{2318}\u{2192} Skip")
                            .font(DT.Typography.micro)
                            .foregroundStyle(theme.colors.textTertiary)
                    }

                    Spacer()

                    HStack(spacing: DT.Spacing.md) {
                        Button {
                            isPresented = false
                        } label: {
                            Text("ESC to exit")
                                .font(DT.Typography.micro)
                                .foregroundStyle(theme.colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.escape, modifiers: [])

                        Button { rename() } label: {
                            Text("Rename \u{21B5}")
                                .font(DT.Typography.body)
                                .fontWeight(.medium)
                                .foregroundStyle(theme.colors.accentForeground)
                                .padding(.horizontal, DT.Spacing.lg)
                                .padding(.vertical, DT.Spacing.sm)
                                .background(theme.colors.accent, in: RoundedRectangle(cornerRadius: DT.Radius.small))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.return, modifiers: [])
                    }
                }
            }
            .padding(DT.Spacing.xl)
        }
        .frame(width: 480)
        .background(theme.colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.xlarge))
        .overlay(RoundedRectangle(cornerRadius: DT.Radius.xlarge).stroke(theme.colors.border, lineWidth: 0.5))
        .dtShadow(DT.Shadow.floating)
        .onAppear {
            files = initialFiles
            currentIndex = min(startIndex, max(0, files.count - 1))
            loadCurrentFile()
        }
    }

    private func folderChip(_ label: String, tag: String) -> some View {
        Button {
            selectedFolder = tag
        } label: {
            Text(label)
                .font(DT.Typography.caption)
                .foregroundStyle(selectedFolder == tag ? theme.colors.textPrimary : theme.colors.textTertiary)
                .padding(.horizontal, DT.Spacing.sm)
                .padding(.vertical, DT.Spacing.xs)
                .background(
                    selectedFolder == tag ? theme.colors.surfaceHover : Color.clear,
                    in: RoundedRectangle(cornerRadius: DT.Radius.small)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.small)
                        .stroke(selectedFolder == tag ? theme.colors.border : Color.clear, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func navButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(theme.colors.backgroundAlt, in: RoundedRectangle(cornerRadius: DT.Radius.small))
        .overlay(RoundedRectangle(cornerRadius: DT.Radius.small).stroke(theme.colors.border, lineWidth: 0.5))
    }

    private func loadCurrentFile() {
        guard let file = currentFile else { return }
        userInput = ""
        errorMessage = nil
        selectedFolder = "."
        thumbnail = nil

        let size = CGSize(width: 640, height: 440)
        let request = QLThumbnailGenerator.Request(fileAt: file, size: size, scale: 2.0, representationTypes: .thumbnail)
        let targetURL = file
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            DispatchQueue.main.async {
                guard self.currentFile == targetURL else { return }
                thumbnail = rep?.nsImage
            }
        }
    }

    private func navigateNext() {
        if currentIndex < files.count - 1 {
            currentIndex += 1
            loadCurrentFile()
        }
    }

    private func navigatePrevious() {
        if currentIndex > 0 {
            currentIndex -= 1
            loadCurrentFile()
        }
    }

    private func rename() {
        guard let file = currentFile else { return }
        let slugged = Slug.underscoreFrom(userInput)
        guard !slugged.isEmpty, slugged != "untitled" else {
            errorMessage = "Enter a description"
            return
        }

        let newName = "\(prefix)\(slugged).\(currentExtension)"
        let targetFolder: URL
        if selectedFolder == "." {
            // Keep in current folder
            targetFolder = file.deletingLastPathComponent()
        } else if selectedFolder.isEmpty {
            // Project root
            targetFolder = project.folderURL
        } else {
            // Specific subfolder
            targetFolder = project.folderURL.appendingPathComponent(selectedFolder)
            try? FileManager.default.createDirectory(at: targetFolder, withIntermediateDirectories: true)
        }
        let targetURL = targetFolder.appendingPathComponent(newName)

        if FileManager.default.fileExists(atPath: targetURL.path) {
            errorMessage = "File already exists: \(newName)"
            return
        }

        do {
            let oldRelative = file.path.replacingOccurrences(of: project.folderURL.path + "/", with: "")
            try FileManager.default.moveItem(at: file, to: targetURL)
            let newRelative = targetURL.path.replacingOccurrences(of: project.folderURL.path + "/", with: "")
            onFileMoved?(oldRelative, newRelative)
            errorMessage = nil
            onFileRenamed()
            // Remove the renamed file from our working list
            files.remove(at: currentIndex)
            if files.isEmpty {
                isPresented = false
            } else {
                // Clamp index (if we were at the end, step back)
                currentIndex = min(currentIndex, files.count - 1)
                loadCurrentFile()
            }
        } catch {
            errorMessage = "Rename failed: \(error.localizedDescription)"
        }
    }

    private func createFolder() {
        let name = Slug.underscoreFrom(newFolderName)
        guard !name.isEmpty, name != "untitled" else { return }
        let folderURL = project.folderURL.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        } catch {
            errorMessage = "Couldn't create folder: \(error.localizedDescription)"
            return
        }
        selectedFolder = name
        newFolderName = ""
        isCreatingFolder = false
        errorMessage = nil
        onFileRenamed()
    }
}
