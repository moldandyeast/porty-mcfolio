import SwiftUI

struct SearchPalette: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @Environment(\.theme) var theme
    @State private var query = ""
    @State private var selectedIndex = 0
    @StateObject private var controller = SearchController(
        search: { _ in [] },  // Replaced in .onAppear once appState.searchIndex is known.
        debounceMs: 120
    )
    @FocusState private var isFieldFocused: Bool

    // MARK: - Grouped results

    struct GroupedResults {
        var commands: [SearchCommand] = []
        var projects: [SearchResult] = []
        var files: [SearchResult] = []
        var links: [SearchResult] = []
        var tags: [SearchResult] = []

        var flatItems: [FlatItem] {
            var items: [FlatItem] = []
            for cmd in commands { items.append(.command(cmd)) }
            for r in projects { items.append(.result(r)) }
            for r in files { items.append(.result(r)) }
            for r in links { items.append(.result(r)) }
            for r in tags { items.append(.result(r)) }
            return items
        }

        var isEmpty: Bool {
            commands.isEmpty && projects.isEmpty && files.isEmpty && links.isEmpty && tags.isEmpty
        }
    }

    enum FlatItem: Identifiable {
        case command(SearchCommand)
        case result(SearchResult)

        var id: String {
            switch self {
            case .command(let cmd): return cmd.id
            case .result(let r): return r.id
            }
        }
    }

    private func computeGrouped() -> GroupedResults {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        let commands = SearchCommand.matching(trimmed)

        let hiddenUIDs: Set<String> = appState.hideHiddenProjects
            ? Set(appState.projects.filter(\.hidden).map(\.uid))
            : []

        if trimmed.isEmpty {
            let recentProjects = appState.projects
                .filter { !hiddenUIDs.contains($0.uid) }
                .sorted { $0.year > $1.year }
                .prefix(5)
                .map { project in
                    SearchResult(
                        id: "project-\(project.uid)",
                        type: .project,
                        entityID: project.uid,
                        parentUID: "",
                        primaryText: project.title.isEmpty ? "Untitled" : project.title,
                        secondaryText: [String(project.year), project.client]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · ")
                    )
                }
            return GroupedResults(commands: commands, projects: Array(recentProjects))
        }

        // Pull FTS results from the controller snapshot. If the snapshot hasn't
        // caught up (mid-debounce) it reflects an older query — we still render
        // it so the list isn't empty; the next snapshot update rerenders.
        let snapshot = controller.snapshot
        let visible: [SearchResult]
        if hiddenUIDs.isEmpty {
            visible = snapshot.results
        } else {
            visible = snapshot.results.filter { r in
                switch r.type {
                case .project: !hiddenUIDs.contains(r.entityID)
                case .file, .link: !hiddenUIDs.contains(r.parentUID)
                case .tag, .command: true
                }
            }
        }

        let ftsProjects = visible.filter { $0.type == .project }
        let ftsFiles = visible.filter { $0.type == .file }
        let ftsLinks = visible.filter { $0.type == .link }
        let ftsTags = visible.filter { $0.type == .tag }

        // Merge FTS + metadata-substring fallback for projects only; files and
        // links have no lazy fallback in this pass.
        let projects = Array(
            mergeResults(fts: ftsProjects, fallback: matchProjects(trimmed, excluding: hiddenUIDs))
                .prefix(5)
        )
        let files = Array(ftsFiles.prefix(5))
        let links = Array(ftsLinks.prefix(3))
        let tags = Array(mergeResults(fts: ftsTags, fallback: matchTags(trimmed)).prefix(3))

        return GroupedResults(
            commands: commands,
            projects: projects,
            files: files,
            links: links,
            tags: tags
        )
    }

    /// Merge FTS results with fallback results, deduplicating by entityID.
    /// FTS results appear first and take priority.
    private func mergeResults(fts: [SearchResult], fallback: [SearchResult]) -> [SearchResult] {
        guard !fallback.isEmpty else { return fts }
        guard !fts.isEmpty else { return fallback }
        let ftsIDs = Set(fts.map(\.entityID))
        return fts + fallback.filter { !ftsIDs.contains($0.entityID) }
    }

    private func matchProjects(_ query: String, excluding hiddenUIDs: Set<String>) -> [SearchResult] {
        let q = query.lowercased()
        return appState.projects
            .filter { project in
                !hiddenUIDs.contains(project.uid) &&
                (project.title.lowercased().contains(q) ||
                 project.client.lowercased().contains(q) ||
                 project.tags.contains { $0.lowercased().contains(q) } ||
                 project.folderName.lowercased().contains(q))
            }
            .prefix(5)
            .map { project in
                SearchResult(
                    id: "project-\(project.uid)",
                    type: .project,
                    entityID: project.uid,
                    parentUID: "",
                    primaryText: project.title.isEmpty ? "Untitled" : project.title,
                    secondaryText: [String(project.year), project.client]
                        .filter { !$0.isEmpty }
                        .joined(separator: " · ")
                )
            }
    }

    private func matchTags(_ query: String) -> [SearchResult] {
        let q = query.lowercased()
        var tagCounts: [String: Int] = [:]
        for project in appState.projects {
            for tag in project.tags {
                tagCounts[tag, default: 0] += 1
            }
        }
        return tagCounts
            .filter { $0.key.lowercased().contains(q) }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { tag, count in
                SearchResult(
                    id: "tag-\(tag)",
                    type: .tag,
                    entityID: tag,
                    parentUID: "",
                    primaryText: tag,
                    secondaryText: "\(count) project\(count == 1 ? "" : "s")"
                )
            }
    }

    // MARK: - Body

    var body: some View {
        let grouped = computeGrouped()
        let flat = grouped.flatItems

        VStack(spacing: 0) {
            TextField("Search projects, files, links, tags…", text: $query)
                .textFieldStyle(.plain)
                .font(DT.Typography.headline)
                .focused($isFieldFocused)
                .onKeyPress(.upArrow) {
                    guard !flat.isEmpty else { return .handled }
                    selectedIndex = selectedIndex > 0 ? selectedIndex - 1 : flat.count - 1
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    guard !flat.isEmpty else { return .handled }
                    selectedIndex = selectedIndex < flat.count - 1 ? selectedIndex + 1 : 0
                    return .handled
                }
                .onKeyPress(.escape) {
                    isPresented = false
                    return .handled
                }
                .onSubmit {
                    selectItem(at: selectedIndex, from: flat)
                }
                .padding(.horizontal, DT.Spacing.lg)
                .padding(.vertical, DT.Spacing.md)

            Rectangle()
                .fill(theme.colors.border)
                .frame(height: 0.5)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(flat.enumerated()), id: \.element.id) { index, item in
                            switch item {
                            case .command(let cmd):
                                if index == commandsStartIndex(in: flat) {
                                    sectionHeader("COMMANDS")
                                }
                                CommandRow(command: cmd, isSelected: index == selectedIndex)
                                    .id(item.id)
                                    .onTapGesture { executeCommand(cmd) }

                            case .result(let result):
                                if isSectionStart(for: result.type, at: index, in: flat) {
                                    sectionHeader(result.type.sectionTitle)
                                }
                                ResultRow(result: result, isSelected: index == selectedIndex)
                                    .id(item.id)
                                    .onTapGesture { executeResult(result) }
                            }
                        }

                        if grouped.isEmpty && !query.isEmpty {
                            HStack {
                                Spacer()
                                Text("No results for \"\(query)\"")
                                    .font(DT.Typography.caption)
                                    .foregroundStyle(theme.colors.textTertiary)
                                    .padding(.vertical, DT.Spacing.xl)
                                Spacer()
                            }
                        }
                    }
                }
                .frame(maxHeight: 400)
                .onChange(of: selectedIndex) { _, newValue in
                    guard newValue < flat.count else { return }
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(flat[newValue].id, anchor: .center)
                    }
                }
            }

            if let err = controller.lastError {
                HStack(spacing: DT.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(theme.colors.error)
                    Text("Search error: \(err.localizedDescription)")
                        .font(DT.Typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, DT.Spacing.lg)
                .padding(.vertical, DT.Spacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.colors.error.opacity(0.08))
            }

            HStack(spacing: DT.Spacing.lg) {
                shortcutHint("↑↓", label: "navigate")
                shortcutHint("↵", label: "open")
                shortcutHint("esc", label: "close")
            }
            .padding(.horizontal, DT.Spacing.lg)
            .padding(.vertical, DT.Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(theme.colors.surfaceHover.opacity(0.6))
        }
        .frame(width: 560)
        .background(theme.colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.xlarge))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.xlarge)
                .stroke(theme.colors.border, lineWidth: 0.5)
        )
        .dtShadow(DT.Shadow.floating)
        .onAppear {
            isFieldFocused = true
            // Clear any stale error from a prior palette session so a transient
            // FTS failure doesn't leave an orange banner on next open.
            controller.cancelAll()
            // Rebind the controller's search closure now that we can see
            // appState.searchIndex. The palette's local controller owns the
            // lazy file-population trigger (AppState's controller does not,
            // to avoid duplicate populate calls per query).
            //
            // Bind `index` and `recon` to locals here (on MainActor), then
            // weak-capture those inside the closures. The `search` closure is
            // `@Sendable` and runs off-main, so it cannot touch `appState`'s
            // @MainActor-isolated properties directly. `[weak index]` keeps
            // the closure from pinning the old SearchIndex alive across a
            // portfolio switch.
            let index = appState.searchIndex
            let recon = appState.reconciler
            controller.rebind(
                search: { [weak index] query in
                    guard let index else { return [] }
                    return try index.search(query: query)
                },
                onMatchedUIDs: { [weak recon] uids in
                    guard let recon else { return }
                    let top = uids.prefix(ProjectReconciler.lazyPopulateFanout)
                    for uid in top {
                        recon.populateFiles(uid: uid)
                    }
                }
            )
            // If the TextField was opened with a pre-filled query (not the
            // current case, but reserved), kick off a search.
            if !query.isEmpty {
                controller.setQuery(query)
            }
        }
        .onChange(of: query) { _, newValue in
            controller.setQuery(newValue)
        }
        .onChange(of: flat.count) { _, newCount in
            selectedIndex = SearchPaletteLogic.clampedIndex(
                current: selectedIndex,
                resultCount: newCount
            )
        }
    }

    /// Returns the index of the first command in the flat list, or -1 if none.
    private func commandsStartIndex(in flat: [FlatItem]) -> Int {
        flat.firstIndex { if case .command = $0 { return true }; return false } ?? -1
    }

    /// Returns true if this is the first result of its type in the flat list.
    private func isSectionStart(for type: SearchResultType, at index: Int, in flat: [FlatItem]) -> Bool {
        if index == 0 { return true }
        guard case .result(let prev) = flat[index - 1] else { return true }
        return prev.type != type
    }

    // MARK: - Actions

    private func selectItem(at index: Int, from flat: [FlatItem]) {
        guard index < flat.count else { return }
        switch flat[index] {
        case .command(let cmd):
            executeCommand(cmd)
        case .result(let result):
            executeResult(result)
        }
    }

    private func executeCommand(_ command: SearchCommand) {
        command.action(appState)
        isPresented = false
    }

    private func executeResult(_ result: SearchResult) {
        switch result.type {
        case .project:
            // Primary: uid match. Fallback: title match, to recover from stale
            // FTS rows whose uid no longer matches any project (e.g. after a
            // folder rename / reconciliation race). Without this fallback the
            // click silently fails and the user sees the palette dismiss with
            // no navigation.
            let project = appState.projects.first(where: { $0.uid == result.entityID })
                ?? appState.projects.first(where: { !result.primaryText.isEmpty && $0.title == result.primaryText })
            if project == nil {
                AppLogger.search.warning("project result not found in appState.projects — uid=\(result.entityID, privacy: .public) title=\(result.primaryText, privacy: .public); click ignored")
            }
            appState.setSelectedProject(project)
        case .file:
            let project = appState.projects.first(where: { $0.uid == result.parentUID })
                ?? appState.projects.first(where: { !result.secondaryText.isEmpty && $0.title == result.secondaryText })
            if let project {
                let fileURL = project.folderURL.appendingPathComponent(result.entityID)
                appState.pendingFileSelection = fileURL
                appState.setSelectedProject(project)
            } else {
                AppLogger.search.warning("file result parent not found — parentUID=\(result.parentUID, privacy: .public) parentTitle=\(result.secondaryText, privacy: .public)")
            }
        case .link:
            let project = appState.projects.first(where: { $0.uid == result.parentUID })
                ?? appState.projects.first(where: { !result.secondaryText.isEmpty && result.secondaryText.hasSuffix($0.title) })
            if let project {
                appState.pendingLinkID = result.entityID
                appState.setSelectedProject(project)
            } else {
                AppLogger.search.warning("link result parent not found — parentUID=\(result.parentUID, privacy: .public) secondary=\(result.secondaryText, privacy: .public)")
            }
        case .tag:
            appState.searchQuery = result.entityID
            appState.setSelectedProject(nil)
        case .command:
            break
        }
        isPresented = false
    }

    // MARK: - Subviews

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(DT.Typography.micro)
                .foregroundStyle(theme.colors.textTertiary)
                .tracking(0.8)
            Spacer()
        }
        .padding(.horizontal, DT.Spacing.lg)
        .padding(.top, DT.Spacing.md)
        .padding(.bottom, DT.Spacing.xs)
    }

    private func shortcutHint(_ key: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(DT.Typography.micro)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(theme.colors.border, in: RoundedRectangle(cornerRadius: 3))
            Text(label)
                .font(DT.Typography.micro)
                .foregroundStyle(theme.colors.textTertiary)
        }
    }
}

// MARK: - Command Row

private struct CommandRow: View {
    let command: SearchCommand
    let isSelected: Bool
    @Environment(\.theme) var theme

    var body: some View {
        HStack(spacing: DT.Spacing.sm) {
            Image(systemName: command.icon)
                .font(.system(size: 13))
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: 24, height: 24)

            Text(command.name)
                .font(DT.Typography.body)
                .fontWeight(.medium)
                .foregroundStyle(theme.colors.textPrimary)

            Spacer()

            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(DT.Typography.micro)
                    .foregroundStyle(theme.colors.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(theme.colors.border)
                    )
            }
        }
        .padding(.horizontal, DT.Spacing.lg)
        .padding(.vertical, DT.Spacing.sm)
        .background(
            isSelected
                ? theme.colors.accent.opacity(DT.Opacity.selection)
                : Color.clear
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Result Row

private struct ResultRow: View {
    let result: SearchResult
    let isSelected: Bool
    @Environment(\.theme) var theme

    private var icon: String {
        switch result.type {
        case .project: "folder.fill"
        case .file: fileIcon(for: result.primaryText)
        case .link: "link"
        case .tag: "tag"
        case .command: "command"
        }
    }

    var body: some View {
        HStack(spacing: DT.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(result.primaryText)
                    .font(DT.Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)

                if !result.secondaryText.isEmpty {
                    Text(result.secondaryText)
                        .font(DT.Typography.caption)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, DT.Spacing.lg)
        .padding(.vertical, DT.Spacing.sm)
        .background(
            isSelected
                ? theme.colors.accent.opacity(DT.Opacity.selection)
                : Color.clear
        )
        .contentShape(Rectangle())
    }

    private func fileIcon(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext"
        case "jpg", "jpeg", "png", "gif", "webp", "heic", "tiff", "svg":
            return "photo"
        case "mp4", "mov", "avi", "mkv":
            return "film"
        case "mp3", "wav", "aac", "m4a":
            return "music.note"
        case "sketch", "fig":
            return "paintbrush"
        case "psd", "ai":
            return "paintpalette"
        case "zip", "tar", "gz":
            return "doc.zipper"
        default:
            return "doc"
        }
    }
}

