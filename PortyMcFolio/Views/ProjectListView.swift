import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Clickable client entry in the table row. Filter-by-client on tap, with
/// the same subtle hover brightening the toolbar's ToolbarChipButton uses.
private struct TableClientButton: View {
    let label: String
    let onTap: () -> Void
    @Environment(\.theme) var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(DT.Typography.caption)
                .foregroundStyle(isHovering ? theme.colors.textPrimary : theme.colors.textSecondary)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }
}

struct ProjectListView: View {
    @Environment(\.theme) var theme
    @EnvironmentObject var appState: AppState
    @State private var projectToDelete: Project?
    @State private var projectForSettings: Project?
    // Two independent selection sources:
    //  - hoveredProjectID is ephemeral (cleared on mouse-leave)
    //  - keyboardSelectedProjectID is sticky (cleared by ESC / mode switch / filter change)
    // The accent border and ⌘9 (Project Settings) prefer keyboard over hover. Return opens
    // ONLY the keyboard selection so a stale mouse-hover can't cause accidental opens.
    @State private var hoveredProjectID: String?
    @State private var keyboardSelectedProjectID: String?
    @State private var gridWidth: CGFloat = 0
    @FocusState private var filterFocused: Bool

    /// Bumped on every `moveSelection()` call. The grid and table observe this
    /// (not `keyboardSelectedProjectID`) so the selected card is scrolled back
    /// into view even when the ID didn't change — e.g. user reached the edge,
    /// or user scrolled away with the trackpad and pressed an arrow.
    @State private var scrollTick: Int = 0

    /// NSEvent local monitor for bare arrow keys. SwiftUI's
    /// `.keyboardShortcut(.upArrow, modifiers: [])` does NOT get menu-dispatch
    /// priority on macOS — once the ScrollView becomes the key responder (mouse
    /// moves into its bounds), it swallows arrows for native scrolling and the
    /// keyboardShortcut Button never fires. The monitor runs before any
    /// responder chain, so arrows keep working regardless of what the mouse
    /// has touched.
    @State private var keyMonitor: Any?

    private var highlightedProjectID: String? {
        keyboardSelectedProjectID ?? hoveredProjectID
    }

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 400), spacing: DT.Spacing.sm)
    ]

    var body: some View {
        VStack(spacing: 0) {
            if appState.projects.isEmpty {
                emptyState
            } else if appState.filteredProjects.isEmpty {
                noResultsState
            } else {
                switch appState.projectListMode {
                case .grid:
                    gridView
                case .table:
                    tableView
                }
            }
        }
        .onChange(of: appState.projectListMode) { _, _ in
            hoveredProjectID = nil
            keyboardSelectedProjectID = nil
        }
        .onAppear {
            projectsByYear = Self.computeProjectsByYear(appState.filteredProjects)
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .onChange(of: appState.filteredProjects) { _, newValue in
            projectsByYear = Self.computeProjectsByYear(newValue)
            let ids = Set(newValue.map(\.id))
            if let id = hoveredProjectID, !ids.contains(id) { hoveredProjectID = nil }
            if let id = keyboardSelectedProjectID, !ids.contains(id) { keyboardSelectedProjectID = nil }
        }
        .toolbar {
            // Left: folder name
            ToolbarItem(placement: .navigation) {
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.prompt = "Choose"
                    panel.message = "Select a folder to use as your portfolio root."
                    if panel.runModal() == .OK, let url = panel.url {
                        appState.setRoot(url)
                    }
                } label: {
                    HStack(spacing: DT.Spacing.xs) {
                        Image(systemName: "folder")
                            .font(.system(size: 12))
                        Text(appState.portfolioRootURL?.lastPathComponent ?? "Portfolio")
                            .font(DT.Typography.body)
                    }
                    .foregroundStyle(theme.colors.textPrimary)
                }
                .buttonStyle(.plain)
                .help("Change portfolio folder")
            }

            // Center: filter
            ToolbarItem(placement: .principal) {
                HStack(spacing: DT.Spacing.xs) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.colors.textTertiary)
                    TextField("Filter…", text: $appState.searchQuery)
                        .textFieldStyle(.plain)
                        .font(DT.Typography.body)
                        .focused($filterFocused)
                    Button {
                        appState.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.colors.textTertiary)
                    }
                    .iconButton()
                    .opacity(appState.searchQuery.isEmpty ? 0 : 1)
                }
                .frame(width: 220)
                .padding(.horizontal, DT.Spacing.sm)
                .padding(.vertical, DT.Spacing.xs)
                .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: DT.Radius.small))
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.small)
                        .stroke(theme.colors.border, lineWidth: 0.5)
                )
            }

            // Right: new project, view toggle, settings
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    appState.isShowingNewProject = true
                } label: {
                    Image(systemName: "plus.square")
                        .font(.system(size: 12))
                        .frame(width: 26, height: 26)
                }
                .iconButton()
                .foregroundStyle(theme.colors.textSecondary)
                .help("New Project (\u{2318}N)")

                listModeIcon(
                    appState.hideHiddenProjects ? "eye.slash" : "eye",
                    help: appState.hideHiddenProjects ? "Show all projects" : "Hide hidden projects",
                    active: appState.hideHiddenProjects
                ) {
                    appState.hideHiddenProjects.toggle()
                }

                listModeIcon("square.grid.2x2", help: "Grid", active: appState.projectListMode == .grid) {
                    appState.projectListMode = .grid
                }

                listModeIcon("list.bullet", help: "Table", active: appState.projectListMode == .table) {
                    appState.projectListMode = .table
                }

                Button {
                    appState.isShowingSettings = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 12))
                        .frame(width: 26, height: 26)
                }
                .iconButton()
                .foregroundStyle(theme.colors.textSecondary)
                .help("Guide")
            }
        }
        .sheet(isPresented: $appState.isShowingNewProject) {
            NewProjectSheet()
                .environmentObject(appState)
        }
        .sheet(item: $projectToDelete) { project in
            DeleteProjectSheet(project: project) {
                deleteProject(project)
                projectToDelete = nil
            }
        }
        .sheet(item: $projectForSettings) { project in
            ProjectSettingsPopover(
                project: project,
                isPresented: Binding(
                    get: { projectForSettings != nil },
                    set: { if !$0 { projectForSettings = nil } }
                )
            )
            .environmentObject(appState)
        }
        .background {
            // ESC clears both selections and the filter.
            Button("") {
                if hoveredProjectID != nil { hoveredProjectID = nil }
                if keyboardSelectedProjectID != nil { keyboardSelectedProjectID = nil }
                if !appState.searchQuery.isEmpty {
                    appState.searchQuery = ""
                }
            }
            .keyboardShortcut(.escape, modifiers: [])
            .opacity(0)
            .allowsHitTesting(false)

            // Return (bare) opens the KEYBOARD-selected project — a stale mouse hover
            // must not cause accidental opens. Gated on filter focus so Return inside
            // the filter TextField still submits/commits normally.
            Button("") { openSelected() }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(filterFocused)
                .opacity(0)
                .allowsHitTesting(false)
        }
        .onChange(of: appState.isShowingProjectSettings) { _, newValue in
            guard newValue else { return }
            appState.isShowingProjectSettings = false

            // Only handle the flag when WE are the visible view (no selected project).
            guard appState.selectedProject == nil else { return }
            guard let id = highlightedProjectID,
                  let project = appState.filteredProjects.first(where: { $0.id == id })
            else { return }
            projectForSettings = project
        }
    }

    // MARK: - Grid View

    @State private var projectsByYear: [(year: Int, projects: [Project])] = []

    /// Pure helper — groups projects by year and sorts newest-first. Used by the
    /// onAppear/onChange cache update below; avoids re-grouping on every body pass.
    private static func computeProjectsByYear(_ projects: [Project]) -> [(year: Int, projects: [Project])] {
        let grouped = Dictionary(grouping: projects) { $0.year }
        return grouped.keys.sorted(by: >).map { year in
            (year: year, projects: ProjectSort.sortedWithinYear(grouped[year]!))
        }
    }

    /// Number of columns the adaptive LazyVGrid will produce at the current width.
    /// Mirrors the math SwiftUI does internally: floor((available + spacing) / (minItem + spacing)).
    private var gridColumnCount: Int {
        let minItem: CGFloat = 280                    // GridItem(.adaptive(minimum: 280, …))
        let spacing: CGFloat = DT.Spacing.sm          // columns' internal spacing
        let usable = gridWidth - DT.Spacing.lg * 2    // matches .padding(DT.Spacing.lg)
        guard usable > 0 else { return 1 }
        return max(1, Int(floor((usable + spacing) / (minItem + spacing))))
    }

    private var gridView: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 48) {
                        ForEach(projectsByYear, id: \.year) { group in
                            VStack(alignment: .leading, spacing: DT.Spacing.md) {
                                // Year divider
                                HStack(spacing: DT.Spacing.sm) {
                                    Text(String(group.year))
                                        .font(DT.Typography.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(theme.colors.textTertiary)
                                        .textCase(.uppercase)
                                        .tracking(1)
                                    Rectangle()
                                        .fill(theme.colors.border)
                                        .frame(height: 0.5)
                                }
                                .padding(.horizontal, DT.Spacing.xs)

                                // Cards for this year
                                LazyVGrid(columns: columns, spacing: 40) {
                                    ForEach(group.projects) { project in
                                        gridCard(for: project)
                                            .onHover { hovering in
                                                // Hover is independent of keyboard selection — otherwise
                                                // auto-scroll after ⌘+arrow would re-fire onHover on cards
                                                // sliding under a stationary cursor and clobber the
                                                // keyboard target. Press ESC to exit keyboard mode.
                                                if hovering {
                                                    hoveredProjectID = project.id
                                                } else if hoveredProjectID == project.id {
                                                    hoveredProjectID = nil
                                                }
                                            }
                                            .contextMenu { projectContextMenu(for: project) }
                                            .id(project.id)
                                    }
                                }
                            }
                        }
                    }
                    .padding(DT.Spacing.lg)
                }
                .onAppear { gridWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, newWidth in gridWidth = newWidth }
                .onChange(of: scrollTick) { _, _ in
                    guard let id = keyboardSelectedProjectID else { return }
                    // Minimum-movement scroll: stays put when the target is
                    // already visible, edges into view otherwise. Re-centering
                    // on every arrow press was the cause of the "jumpy" feel.
                    // Fires on every move (not just ID change) so the selection
                    // is re-revealed even at edges or after trackpad-scroll drift.
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    /// Renders the per-project card for the grid. Selection ring is drawn
    /// inside `EditorialCardView` around just the image, so no parent
    /// overlay is needed.
    private func gridCard(for project: Project) -> some View {
        EditorialCardView(
            project: project,
            aspectRatio: appState.gridAspectRatio.value,
            isKeyboardSelected: keyboardSelectedProjectID == project.id,
            isHoverHighlighted: hoveredProjectID == project.id,
            onOpen: { appState.setSelectedProject(project) },
            onTagTap: { tag in appState.searchQuery = tag },
            onClientTap: { client in appState.searchQuery = client }
        )
    }

    // MARK: - Table View

    private enum SortField: String {
        case year, title, client, status
    }

    @State private var sortField: SortField = .year
    @State private var sortAscending = false
    @State private var expandedTagIDs: Set<String> = []

    private var sortedProjects: [Project] {
        let projects = appState.filteredProjects
        return projects.sorted { a, b in
            let result: Bool
            switch sortField {
            case .year: result = a.year < b.year
            case .title: result = a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            case .client: result = a.client.localizedCaseInsensitiveCompare(b.client) == .orderedAscending
            case .status: result = a.status.rawValue < b.status.rawValue
            }
            return sortAscending ? result : !result
        }
    }

    private struct Col {
        static let gap: CGFloat = 12
        static let yearW: CGFloat = 44
        static let statusW: CGFloat = 85

        struct Widths {
            let year: CGFloat
            let title: CGFloat
            let client: CGFloat   // 0 = hidden
            let status: CGFloat   // 0 = hidden
            let tags: CGFloat     // 0 = hidden
            var showClient: Bool { client > 0 }
            var showStatus: Bool { status > 0 }
            var showTags: Bool { tags > 0 }
        }

        static func widths(for total: CGFloat) -> Widths {
            let y = yearW

            if total < 400 {
                // Tiny: year + title only
                return Widths(year: y, title: total - y - gap, client: 0, status: 0, tags: 0)
            }
            if total < 550 {
                // Small: year + title + client
                let flex = total - y - gap * 2
                return Widths(year: y, title: flex * 0.55, client: flex * 0.45, status: 0, tags: 0)
            }
            if total < 750 {
                // Medium: year + title + client + status
                let flex = total - y - statusW - gap * 3
                return Widths(year: y, title: flex * 0.55, client: flex * 0.45, status: statusW, tags: 0)
            }
            // Full: all columns
            let flex = total - y - statusW - gap * 4
            return Widths(year: y, title: flex * 0.38, client: flex * 0.22, status: statusW, tags: flex * 0.40)
        }
    }

    private var tableView: some View {
        GeometryReader { geo in
            let c = Col.widths(for: geo.size.width - DT.Spacing.lg * 2)

            VStack(spacing: 0) {
                tableHeaderRow(c: c)
                    .padding(.horizontal, DT.Spacing.lg)

                Rectangle()
                    .fill(theme.colors.border)
                    .frame(height: 0.5)
                    .padding(.horizontal, DT.Spacing.lg)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(sortedProjects) { project in
                                tableDataRow(project, c: c)
                                    .padding(.horizontal, DT.Spacing.lg)
                                    .id(project.id)
                            }
                        }
                        .padding(.top, 2)
                    }
                    .onChange(of: scrollTick) { _, _ in
                        guard let id = keyboardSelectedProjectID else { return }
                        // Minimum-movement scroll — see grid-view note above.
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(id)
                        }
                    }
                }
            }
        }
    }

    private func tableHeaderRow(c: Col.Widths) -> some View {
        HStack(spacing: Col.gap) {
            sortButton("Year", field: .year)
                .frame(width: c.year, alignment: .leading)
            sortButton("Title", field: .title)
                .frame(width: c.title, alignment: .leading)
            if c.showClient {
                sortButton("Client", field: .client)
                    .frame(width: c.client, alignment: .leading)
            }
            if c.showStatus {
                sortButton("Status", field: .status)
                    .frame(width: c.status, alignment: .leading)
            }
            if c.showTags {
                HStack(spacing: 0) {
                    Text("Tags")
                        .font(DT.Typography.micro)
                        .foregroundStyle(theme.colors.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer(minLength: 0)
                    exportButton
                }
                .frame(width: c.tags, alignment: .leading)
            }
        }
        .padding(.vertical, DT.Spacing.sm)
    }

    private func sortButton(_ label: String, field: SortField) -> some View {
        Button {
            if sortField == field {
                sortAscending.toggle()
            } else {
                sortField = field
                sortAscending = field == .title || field == .client
            }
        } label: {
            HStack(spacing: 3) {
                Text(label)
                    .font(DT.Typography.micro)
                    .foregroundStyle(sortField == field ? theme.colors.textPrimary : theme.colors.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                if sortField == field {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(theme.colors.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var exportButton: some View {
        Button(action: exportCSV) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 11))
                .foregroundStyle(theme.colors.textTertiary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .iconButton()
        .disabled(sortedProjects.isEmpty)
        .opacity(sortedProjects.isEmpty ? 0.4 : 1.0)
        .help("Export visible projects as CSV")
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = defaultExportFilename()
        panel.canCreateDirectories = true
        panel.title = "Export Projects as CSV"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let csv = CSVExporter.csv(for: sortedProjects)
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            AppLogger.ui.error("CSV export write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func defaultExportFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: Date())

        let raw = appState.portfolioRootURL?.lastPathComponent ?? ""
        let slug = sanitizeFilenameStem(raw)
        let stem = slug.isEmpty ? "PortyMcFolio" : slug
        return "\(stem)-\(date).csv"
    }

    /// Lossy normalize a folder name into a safe filename stem:
    /// runs of whitespace → single `-`; any character outside `[A-Za-z0-9._-]` is dropped.
    private func sanitizeFilenameStem(_ raw: String) -> String {
        // Collapse whitespace runs to single hyphen
        let hyphenated = raw.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        // Keep only safe filename characters
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        return String(hyphenated.unicodeScalars.filter { allowed.contains($0) })
    }

    private func tableDataRow(_ project: Project, c: Col.Widths) -> some View {
        let isKeyboardSelected = keyboardSelectedProjectID == project.id
        let isHovered = hoveredProjectID == project.id

        return HStack(spacing: Col.gap) {
            Text(String(project.year))
                .font(DT.Typography.caption)
                .foregroundStyle(theme.colors.textTertiary)
                .frame(width: c.year, alignment: .leading)

            Text(project.title.isEmpty ? "Untitled" : project.title)
                .font(DT.Typography.body)
                .fontWeight(.medium)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1)
                .frame(width: c.title, alignment: .leading)

            if c.showClient {
                let clients = project.client
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                HStack(spacing: 0) {
                    ForEach(Array(clients.enumerated()), id: \.offset) { idx, client in
                        TableClientButton(label: client) {
                            appState.searchQuery = client
                        }
                        if idx < clients.count - 1 {
                            Text(", ")
                                .font(DT.Typography.caption)
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                    }
                }
                .lineLimit(1)
                .frame(width: c.client, alignment: .leading)
            }

            if c.showStatus {
                StatusBadgeView(status: project.status)
                    .frame(width: c.status, alignment: .leading)
            }

            if c.showTags {
                let isExpanded = expandedTagIDs.contains(project.uid)

                // Greedy fit: estimate each tag pill's width from its text length and
                // pack as many as will fit in the tag column width, reserving room for
                // the overflow "+N" pill.
                let maxVisible: Int = {
                    if isExpanded { return project.tags.count }
                    let charWidth: CGFloat = 6.5              // rough avg for DT.Typography.micro
                    let pillHPadding: CGFloat = 16            // TagPillView horizontal padding (x2)
                    let pillGap: CGFloat = DT.Spacing.xs
                    let overflowPillBudget: CGFloat = 36      // space reserved for "+N" (plus gap)
                    var remaining = c.tags
                    var count = 0
                    for (idx, tag) in project.tags.enumerated() {
                        let pillWidth = CGFloat(tag.count) * charWidth + pillHPadding
                        let isLast = idx == project.tags.count - 1
                        let tailReserved: CGFloat = isLast ? 0 : overflowPillBudget + pillGap
                        let cost = pillWidth + (count > 0 ? pillGap : 0)
                        if cost + tailReserved <= remaining {
                            remaining -= cost
                            count += 1
                        } else {
                            break
                        }
                    }
                    return max(1, min(count, project.tags.count))
                }()

                let visibleTags = isExpanded ? project.tags : Array(project.tags.prefix(maxVisible))
                FlowLayout(spacing: DT.Spacing.xs) {
                    ForEach(visibleTags, id: \.self) { tag in
                        TagPillView(tag: tag) {
                            appState.searchQuery = tag
                        }
                    }
                    if project.tags.count > maxVisible {
                        TagPillView(tag: isExpanded ? "\u{2212}" : "+\(project.tags.count - maxVisible)") {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if isExpanded {
                                    expandedTagIDs.remove(project.uid)
                                } else {
                                    expandedTagIDs.insert(project.uid)
                                }
                            }
                        }
                    }
                }
                .frame(width: c.tags, alignment: .leading)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, DT.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.small)
                .fill(
                    isKeyboardSelected
                        ? theme.colors.accent.opacity(DT.Opacity.selection)
                        : isHovered
                            ? theme.colors.surfaceHover
                            : Color.clear
                )
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredProjectID = project.id
            } else if hoveredProjectID == project.id {
                hoveredProjectID = nil
            }
        }
        .onTapGesture {
            appState.setSelectedProject(project)
        }
        .contextMenu { projectContextMenu(for: project) }
    }

    // MARK: - Keyboard navigation

    private func moveSelection(_ direction: ProjectNavigation.Direction) {
        // Seed from keyboard selection if set, else hover — so bare arrow can start from
        // "whatever I'm currently looking at."
        let start = highlightedProjectID

        // If nothing is highlighted, any arrow press seeds to the first visible card
        // (the helper returns nil for up/left in that case — unhelpful for a user
        // who just pressed any arrow expecting something to happen).
        if start == nil {
            let first: String?
            switch appState.projectListMode {
            case .grid:  first = projectsByYear.first?.projects.first?.id
            case .table: first = sortedProjects.first?.id
            }
            keyboardSelectedProjectID = first
            scrollTick &+= 1
            return
        }

        let next: String?
        switch appState.projectListMode {
        case .grid:
            let groups = projectsByYear.map { $0.projects.map { $0.id } }
            next = ProjectNavigation.nextHighlightIDInGroupedGrid(
                current: start,
                groups: groups,
                direction: direction,
                columnCount: gridColumnCount
            )
        case .table:
            next = ProjectNavigation.nextHighlightID(
                current: start,
                in: sortedProjects.map { $0.id },
                direction: direction,
                columnCount: 1,
                mode: .table
            )
        }
        keyboardSelectedProjectID = next
        scrollTick &+= 1
    }

    // MARK: - NSEvent key monitor

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Only handle arrows on the overview, and never when the filter is
            // focused (text cursor) or any sheet is up (the sheet should own
            // the event).
            guard appState.selectedProject == nil,
                  !filterFocused,
                  !appState.isShowingNewProject,
                  !appState.isShowingSettings,
                  projectToDelete == nil,
                  projectForSettings == nil
            else { return event }

            // Ignore if any modifier is held — let ⌘←/⌘→ text-nav shortcuts
            // or other modified shortcuts fall through.
            let mods: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
            if !event.modifierFlags.intersection(mods).isEmpty {
                return event
            }

            switch event.keyCode {
            case 123: moveSelection(.left);  return nil
            case 124: moveSelection(.right); return nil
            case 125: moveSelection(.down);  return nil
            case 126: moveSelection(.up);    return nil
            default: return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func openSelected() {
        // Return opens only the keyboard-selected project — a stale mouse hover
        // must not trigger an accidental open.
        guard let id = keyboardSelectedProjectID,
              let project = appState.filteredProjects.first(where: { $0.id == id })
        else { return }
        appState.setSelectedProject(project)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func projectContextMenu(for project: Project) -> some View {
        Button { appState.setSelectedProject(project) } label: {
            Label("Open", systemImage: "doc.text")
        }
        Button { projectForSettings = project } label: {
            Label("Project Settings\u{2026}", systemImage: "slider.horizontal.3")
        }
        Button {
            NSWorkspace.shared.open(project.folderURL)
        } label: {
            Label("Open in Finder", systemImage: "folder")
        }
        Divider()
        Button(role: .destructive) { projectToDelete = project } label: {
            Label("Delete\u{2026}", systemImage: "trash")
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 0) {
                Spacer(minLength: 0)
                WelcomePrimerView {
                    appState.isShowingNewProject = true
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 80)
            .padding(.horizontal, DT.Spacing.xl)
        }
    }

    @ViewBuilder
    private var noResultsState: some View {
        VStack(spacing: DT.Spacing.md) {
            Image(systemName: appState.hideHiddenProjects ? "eye.slash" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(theme.colors.textTertiary)
            Text("No Matching Projects")
                .font(DT.Typography.title)
                .foregroundStyle(theme.colors.textPrimary)
            Text(appState.hideHiddenProjects
                 ? "All projects are hidden. Toggle the eye icon to show them."
                 : "Try a different search term.")
                .font(DT.Typography.body)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Helpers

    private func listModeIcon(_ icon: String, help: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(active ? theme.colors.textPrimary : theme.colors.textTertiary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .iconButton()
        .help(help)
    }

    private func deleteProject(_ project: Project) {
        try? FileManager.default.trashItem(at: project.folderURL, resultingItemURL: nil)
        appState.refreshProjects()
    }
}

// MARK: - Delete Confirmation Sheet

struct DeleteProjectSheet: View {
    let project: Project
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) var theme
    @State private var confirmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Warning icon + title
            HStack(spacing: DT.Spacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(theme.colors.error)
                Text("Delete Project")
                    .font(DT.Typography.title)
                    .foregroundStyle(theme.colors.textPrimary)
            }
            .padding(.bottom, DT.Spacing.lg)

            // Project info
            VStack(alignment: .leading, spacing: DT.Spacing.xs) {
                Text(project.title.isEmpty ? "Untitled" : project.title)
                    .font(DT.Typography.headline)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(project.folderName)
                    .font(DT.Typography.monoSmall)
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .padding(DT.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.backgroundAlt, in: RoundedRectangle(cornerRadius: DT.Radius.small))
            .padding(.bottom, DT.Spacing.lg)

            Text("This will move the entire project folder and all its files to Trash.")
                .font(DT.Typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, DT.Spacing.xl)

            // Confirmation checkbox
            Button {
                confirmed.toggle()
            } label: {
                HStack(spacing: DT.Spacing.sm) {
                    Image(systemName: confirmed ? "checkmark.square.fill" : "square")
                        .font(.system(size: 16))
                        .foregroundStyle(confirmed ? theme.colors.accent : theme.colors.textTertiary)
                    Text("I understand, delete this project")
                        .font(DT.Typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                }
            }
            .buttonStyle(.plain)
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
                    onConfirm()
                    dismiss()
                } label: {
                    Text("Delete")
                        .font(DT.Typography.body)
                        .fontWeight(.medium)
                        .foregroundStyle(confirmed ? .white : theme.colors.textTertiary)
                        .padding(.horizontal, DT.Spacing.lg)
                        .padding(.vertical, DT.Spacing.sm)
                        .background(
                            confirmed ? theme.colors.error : theme.colors.surfaceHover,
                            in: RoundedRectangle(cornerRadius: DT.Radius.small)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!confirmed)
            }
        }
        .padding(DT.Spacing.xl)
        .frame(width: 380)
        .background(theme.colors.surface)
    }
}
