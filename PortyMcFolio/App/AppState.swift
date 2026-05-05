import Foundation
import SwiftUI
import Combine

enum ProjectListMode: String, CaseIterable {
    case grid
    case table
}

/// Discrete aspect ratios offered for the project image on the overview.
/// Stored as the rawValue label so the picker label and persistence stay
/// in lockstep.
enum GridAspectRatio: String, CaseIterable, Codable {
    case threeTwo    = "3:2"
    case fourThree   = "4:3"
    case oneOne      = "1:1"
    case fourFive    = "4:5"
    case sixteenNine = "16:9"

    var value: CGFloat {
        switch self {
        case .threeTwo:    return 3.0 / 2.0
        case .fourThree:   return 4.0 / 3.0
        case .oneOne:      return 1.0
        case .fourFive:    return 4.0 / 5.0
        case .sixteenNine: return 16.0 / 9.0
        }
    }
}

enum ViewMode: Int, Codable, CaseIterable {
    case editor       = 0  // ⌘1
    case preview      = 1  // ⌘2
    case splitGallery = 2  // ⌘3
    case gallery      = 3  // ⌘⇧3
    case splitList    = 4  // ⌘4
    case list         = 5  // ⌘⇧4
    case splitLinks   = 6  // ⌘5
    case links        = 7  // ⌘⇧5
    case carousel     = 8  // ⌘6
}

@MainActor
final class AppState: ObservableObject {
    static let defaultNewProjectTemplate: String = """
        # {{title}}

        Project description here.
        """

    @Published var isReady = false
    @Published var hideHiddenProjects = false {
        didSet { UserDefaults.standard.set(hideHiddenProjects, forKey: "hideHiddenProjects") }
    }
    /// True after the user has dismissed the in-project onboarding primer
    /// at least once. Persisted; the primer never reappears after dismissal.
    @Published var hasSeenProjectOnboarding = false {
        didSet { UserDefaults.standard.set(hasSeenProjectOnboarding, forKey: "hasSeenProjectOnboarding") }
    }
    @Published var portfolioRootURL: URL?
    @Published var projects: [Project] = []
    @Published var selectedProject: Project?
    @Published var searchQuery: String = "" {
        didSet {
            searchController?.setQuery(searchQuery)
        }
    }
    @Published var isShowingNewProject = false
    @Published var isShowingSettings = false
    /// Set to true by the ⌘9 menu handler. Whichever view is visible —
    /// ProjectDetailView or ProjectListView — observes this flag, opens
    /// its Project Settings popover for the relevant project, and resets
    /// the flag to false.
    @Published var isShowingProjectSettings = false
    @Published var viewMode: ViewMode = .editor {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: "viewMode") }
    }
    @Published var splitRatio: CGFloat = 0.6 {
        didSet { UserDefaults.standard.set(splitRatio, forKey: "splitRatio") }
    }
    @Published var projectListMode: ProjectListMode = .grid {
        didSet { UserDefaults.standard.set(projectListMode.rawValue, forKey: "projectListMode") }
    }
    @Published var gridAspectRatio: GridAspectRatio = .fourThree {
        didSet { UserDefaults.standard.set(gridAspectRatio.rawValue, forKey: "gridAspectRatio") }
    }
    @Published var projectSortOrder: [KeyPathComparator<Project>] = [
        KeyPathComparator(\.year, order: .reverse)
    ] {
        didSet { persistSortOrder() }
    }

    // MARK: - Theming + preferences

    @Published var themeID: Theme.ID = .porty {
        didSet { UserDefaults.standard.set(themeID.rawValue, forKey: "themeID") }
    }
    var theme: Theme { Theme.named(themeID) }

    /// Manual override for the system appearance. Defaults to `.system`
    /// which follows `NSApp.effectiveAppearance`. `.light` and `.dark`
    /// force the chosen appearance across the whole app (both SwiftUI
    /// color-scheme and AppKit `NSApp.appearance`).
    enum AppearanceOverride: String, Codable, CaseIterable {
        case system
        case light
        case dark

        /// The value to pass to `.preferredColorScheme(_:)`. `nil` follows
        /// the system.
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light:  return .light
            case .dark:   return .dark
            }
        }

        /// The matching `NSAppearance` to force on `NSApp.appearance`,
        /// or `nil` to let AppKit follow the system.
        var nsAppearance: NSAppearance? {
            switch self {
            case .system: return nil
            case .light:  return NSAppearance(named: .aqua)
            case .dark:   return NSAppearance(named: .darkAqua)
            }
        }
    }

    @Published var appearanceOverride: AppearanceOverride = .system {
        didSet {
            UserDefaults.standard.set(appearanceOverride.rawValue, forKey: "appearanceOverride")
            NSApp.appearance = appearanceOverride.nsAppearance
            appearanceSignal &+= 1
        }
    }

    enum DefaultViewMode: String, Codable, CaseIterable {
        case lastUsed
        case editor
        case preview
        case splitGallery
        case gallery
        case splitList
        case list
        case splitLinks
        case links
        case carousel

        /// Concrete `ViewMode` this preference maps to when a project is
        /// opened. `nil` means "don't change the current viewMode" (lastUsed).
        var resolvedViewMode: ViewMode? {
            switch self {
            case .lastUsed:     return nil
            case .editor:       return .editor
            case .preview:      return .preview
            case .splitGallery: return .splitGallery
            case .gallery:      return .gallery
            case .splitList:    return .splitList
            case .list:         return .list
            case .splitLinks:   return .splitLinks
            case .links:        return .links
            case .carousel:     return .carousel
            }
        }
    }
    @Published var defaultViewMode: DefaultViewMode = .lastUsed {
        didSet { UserDefaults.standard.set(defaultViewMode.rawValue, forKey: "defaultViewMode") }
    }

    @Published var autoSaveDelay: Double = 1.5 {
        didSet { UserDefaults.standard.set(autoSaveDelay, forKey: "autoSaveDelay") }
    }

    @Published var grainEnabled: Bool = true {
        didSet { UserDefaults.standard.set(grainEnabled, forKey: "grainEnabled") }
    }
    @Published var grainOpacityOverride: Double? = nil {
        didSet {
            if let v = grainOpacityOverride {
                UserDefaults.standard.set(v, forKey: "grainOpacityOverride")
            } else {
                UserDefaults.standard.removeObject(forKey: "grainOpacityOverride")
            }
        }
    }

    @Published var newProjectTemplate: String = AppState.defaultNewProjectTemplate {
        didSet { UserDefaults.standard.set(newProjectTemplate, forKey: "newProjectTemplate") }
    }

    /// Transient message shown as a floating pill over the window. Used to
    /// confirm actions whose result isn't visible in the current view (e.g.
    /// adding a file while Links view is active). Set via `showToast(_:)`;
    /// auto-clears after a short delay.
    @Published var toastMessage: String?
    private var toastTask: Task<Void, Never>?

    func showToast(_ message: String, duration: Duration = .milliseconds(1500)) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.toastMessage = nil }
        }
    }

    var effectiveGrainOpacity: Double {
        guard grainEnabled else { return 0 }
        return grainOpacityOverride ?? theme.grainOpacity
    }

    /// Incremented whenever the system appearance or the macOS accent
    /// changes. WebView-hosting views observe this to re-inject the CSS
    /// variables. See Task 6 for the observer wiring.
    @Published var appearanceSignal: Int = 0

    /// Set by search palette to auto-select a file in gallery after navigation
    @Published var pendingFileSelection: URL?
    /// Set by search palette to auto-select a link in gallery after navigation
    @Published var pendingLinkID: String?

    /// All unique tags across projects, sorted by frequency (most used first)
    var suggestedTags: [String] {
        var counts: [String: Int] = [:]
        for project in projects {
            for tag in project.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    /// All unique clients across projects, sorted by frequency (most used first).
    /// Multi-client project entries (stored as a comma-joined string) are split and counted individually.
    var suggestedClients: [String] {
        Self.suggestedClients(from: projects)
    }

    /// Pure extraction of `suggestedClients` for unit testing.
    nonisolated static func suggestedClients(from projects: [Project]) -> [String] {
        var counts: [String: Int] = [:]
        for project in projects {
            let parts = project.client
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for c in parts {
                counts[c, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    private var portfolioStore: PortfolioStore?
    private(set) var searchIndex: SearchIndex?
    /// Cached project metadata, shared with the reconciler.
    private(set) var cache: ProjectMetadataCache?
    /// Background reconciler that owns disk sync.
    private(set) var reconciler: ProjectReconciler?
    /// Debounced, off-main search pipeline. Constructed in `setRoot` once the
    /// search index exists; nil before then or after portfolio teardown.
    private(set) var searchController: SearchController?

    /// uid of a project we want to auto-select once the reconciler reports its insert/update.
    /// Used by refreshProjects(thenSelect:) to bridge the gap between scan-completion
    /// and the published mutation arriving on MainActor.
    private var pendingSelectionUID: String?

    private var fileWatcher: FileWatcher?
    private let bookmarkKey = "portfolioRootBookmark"
    private var accessedURL: URL?

    /// Observers for system appearance + accent changes — bump `appearanceSignal`.
    private var appearanceObservers: [NSObjectProtocol] = []
    private var effectiveAppearanceObservation: NSKeyValueObservation?

    /// Combine subscription forwarding the controller's `objectWillChange`
    /// into our own, so SwiftUI recomputes `filteredProjects` when the
    /// snapshot updates. This is the only Combine usage in the codebase;
    /// keep it scoped.
    private var controllerObserver: AnyCancellable?

    /// Projects visible in the current view, filtered by search query and hidden toggle.
    ///
    /// Projects are the primary entity — any project whose metadata (title, client,
    /// tags, folder name, status) substring-matches the query is ALWAYS included,
    /// regardless of the FTS `LIMIT 30` row cap. FTS `matchedUIDs` are unioned on
    /// top to catch projects whose hit is in body text or an indexed file/link row
    /// (secondary signal).
    var filteredProjects: [Project] {
        let base = hideHiddenProjects ? projects.filter { !$0.hidden } : projects

        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return base }

        let matched = Self.matchedProjectUIDs(
            query: trimmed,
            snapshot: searchController?.snapshot,
            projects: base
        )
        return base.filter { matched.contains($0.uid) }
    }

    /// Compute the set of project uids that match the query, unioning metadata
    /// substring matches with any FTS `matchedUIDs` from a fresh snapshot.
    ///
    /// The metadata pass is authoritative: it guarantees every project whose
    /// title/client/tags/folderName/status contains the query is returned, even
    /// if FTS rank truncation (LIMIT 30) dropped that project's row in favor of
    /// file/link rows from other projects. The FTS union adds projects whose
    /// only match is in indexed body text, file names, or link URLs.
    ///
    /// Pure / nonisolated so it can be unit-tested without constructing a
    /// `SearchController` or `SearchIndex`.
    nonisolated static func matchedProjectUIDs(
        query: String,
        snapshot: SearchController.Snapshot?,
        projects: [Project]
    ) -> Set<String> {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Set(projects.map(\.uid)) }

        var matched = Set<String>()

        // Metadata substring pass — ALWAYS runs; ensures projects are findable
        // regardless of FTS truncation.
        let q = trimmed.lowercased()
        for project in projects {
            if project.title.lowercased().contains(q) ||
                project.client.lowercased().contains(q) ||
                project.tags.contains(where: { $0.lowercased().contains(q) }) ||
                project.folderName.lowercased().contains(q) ||
                project.status.displayName.lowercased().contains(q) {
                matched.insert(project.uid)
            }
        }

        // FTS union — only trust the snapshot if it reflects the current query.
        if let snapshot, snapshot.query == trimmed {
            matched.formUnion(snapshot.matchedUIDs)
        }

        return matched
    }

    func loadSavedRoot() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else {
            isReady = true
            return
        }

        Task { [weak self] in
            // Race bookmark resolution against a 2s deadline. Using a small
            // enum instead of a double-optional keeps the intent readable.
            enum ResolveOutcome {
                case success(URL, Bool)
                case failed
            }

            let outcome: ResolveOutcome = await withTaskGroup(of: ResolveOutcome.self) { group in
                group.addTask {
                    var isStale = false
                    guard let url = try? URL(
                        resolvingBookmarkData: bookmarkData,
                        options: .withSecurityScope,
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    ) else {
                        return .failed
                    }
                    return .success(url, isStale)
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(2))
                    return .failed
                }
                let first = await group.next() ?? .failed
                group.cancelAll()
                return first
            }

            guard let self else { return }
            await MainActor.run {
                switch outcome {
                case .failed:
                    AppLogger.app.warning("Bookmark resolution timed out or failed; falling back to folder picker")
                    UserDefaults.standard.removeObject(forKey: self.bookmarkKey)
                    self.isReady = true
                case .success(let url, let isStale):
                    if isStale {
                        self.saveBookmark(for: url)
                    }
                    self.setRoot(url)
                }
            }
        }
    }

    func loadLayoutPreferences() {
        ViewModeMigration.migrate(.standard)
        if let raw = UserDefaults.standard.string(forKey: "themeID"),
           let id = Theme.ID(rawValue: raw) {
            themeID = id
        }
        if let raw = UserDefaults.standard.string(forKey: "appearanceOverride"),
           let override = AppearanceOverride(rawValue: raw) {
            appearanceOverride = override
        }
        if let raw = UserDefaults.standard.string(forKey: "defaultViewMode") {
            // Legacy rename: "split" → "splitGallery". Idempotent.
            let migrated = raw == "split" ? "splitGallery" : raw
            if let mode = DefaultViewMode(rawValue: migrated) {
                defaultViewMode = mode
            }
        }
        let delay = UserDefaults.standard.double(forKey: "autoSaveDelay")
        if delay >= 0.5 && delay <= 5.0 {
            autoSaveDelay = delay
        }
        if UserDefaults.standard.object(forKey: "grainEnabled") != nil {
            grainEnabled = UserDefaults.standard.bool(forKey: "grainEnabled")
        }
        if UserDefaults.standard.object(forKey: "grainOpacityOverride") != nil {
            let v = UserDefaults.standard.double(forKey: "grainOpacityOverride")
            if v >= 0.0 && v <= 0.10 {
                grainOpacityOverride = v
            }
        }
        if let raw = UserDefaults.standard.string(forKey: "newProjectTemplate") {
            newProjectTemplate = raw
        }
        if let raw = UserDefaults.standard.object(forKey: "viewMode") as? Int,
           let mode = ViewMode(rawValue: raw) {
            viewMode = mode
        }
        let ratio = UserDefaults.standard.double(forKey: "splitRatio")
        if ratio > 0 {
            splitRatio = ratio
        }
        if let listRaw = UserDefaults.standard.string(forKey: "projectListMode"),
           let mode = ProjectListMode(rawValue: listRaw) {
            projectListMode = mode
        }
        if let raw = UserDefaults.standard.string(forKey: "gridAspectRatio"),
           let ratio = GridAspectRatio(rawValue: raw) {
            gridAspectRatio = ratio
        }
        if UserDefaults.standard.object(forKey: "hideHiddenProjects") != nil {
            hideHiddenProjects = UserDefaults.standard.bool(forKey: "hideHiddenProjects")
        }
        if UserDefaults.standard.object(forKey: "hasSeenProjectOnboarding") != nil {
            hasSeenProjectOnboarding = UserDefaults.standard.bool(forKey: "hasSeenProjectOnboarding")
        }
        restoreSortOrder()
    }

    /// Subscribes to AppleInterfaceThemeChangedNotification (dark/light toggle) and
    /// AppleColorPreferencesChangedNotification (system accent color change).
    /// Also KVOs NSApp.effectiveAppearance as a belt-and-suspenders trigger.
    func startAppearanceObservers() {
        let dnc = DistributedNotificationCenter.default()
        let themeObs = dnc.addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.appearanceSignal &+= 1
        }
        let accentObs = dnc.addObserver(
            forName: Notification.Name("AppleColorPreferencesChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.appearanceSignal &+= 1
        }
        appearanceObservers = [themeObs, accentObs]

        effectiveAppearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.appearanceSignal &+= 1 }
        }

        // AppKit-layer views (e.g. MarkdownTextView) can't reach AppState
        // directly. They post .showToast with the message as `object`; we
        // observe it here and fan it into the existing toast API.
        let toastObs = NotificationCenter.default.addObserver(
            forName: .showToast,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let message = note.object as? String else { return }
            self?.showToast(message)
        }
        appearanceObservers.append(toastObs)

        // Trigger a full reconcile when the app becomes active. FSEvents can
        // miss changes during sleep/wake or when the volume was unmounted —
        // this is a cheap reliability backstop.
        let activeObs = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshProjects()
        }
        appearanceObservers.append(activeObs)
    }

    private func persistSortOrder() {
        guard let first = projectSortOrder.first else { return }
        let key: String
        switch first.keyPath {
        case \Project.year: key = "year"
        case \Project.title: key = "title"
        case \Project.client: key = "client"
        case \Project.status: key = "status"
        default: return
        }
        let dir = first.order == .forward ? "asc" : "desc"
        UserDefaults.standard.set("\(key)-\(dir)", forKey: "projectSortKey")
    }

    private func restoreSortOrder() {
        guard let raw = UserDefaults.standard.string(forKey: "projectSortKey") else { return }
        let parts = raw.split(separator: "-")
        guard parts.count == 2 else { return }
        let order: SortOrder = parts[1] == "asc" ? .forward : .reverse
        switch parts[0] {
        case "year": projectSortOrder = [KeyPathComparator(\Project.year, order: order)]
        case "title": projectSortOrder = [KeyPathComparator(\Project.title, order: order)]
        case "client": projectSortOrder = [KeyPathComparator(\Project.client, order: order)]
        case "status": projectSortOrder = [KeyPathComparator(\Project.status, order: order)]
        default: break
        }
    }

    private func saveBookmark(for url: URL) {
        if let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
        }
    }

    func setRoot(_ url: URL) {
        // Acquire access to the new URL BEFORE tearing down any current portfolio,
        // so a failed switch doesn't nuke working state — and so a launch-restore
        // that resolves a stale bookmark can fall back to the folder picker
        // instead of hanging on the splash.
        guard url.startAccessingSecurityScopedResource() else {
            if portfolioRootURL == nil {
                UserDefaults.standard.removeObject(forKey: bookmarkKey)
                isReady = true
            }
            return
        }

        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = url

        saveBookmark(for: url)

        // Tear down services from any previous portfolio so their DatabaseQueue
        // (and file-watcher / reconciler queue) deallocate before we build new
        // ones. Without this teardown, two DatabaseQueue instances coexist on
        // the same search.sqlite file during portfolio switch and produce
        // SQLITE_BUSY errors ("database is locked").
        fileWatcher?.stop()
        fileWatcher = nil
        reconciler?.shutdown()
        reconciler = nil
        controllerObserver?.cancel()
        controllerObserver = nil
        searchController?.cancelAll()  // stop/discard in-flight work before releasing
        searchController = nil
        searchIndex = nil
        cache = nil

        // Clear old state before loading new root
        selectedProject = nil
        projects = []
        searchQuery = ""

        portfolioRootURL = url
        portfolioStore = PortfolioStore(rootURL: url)

        // Construct (or reuse) the SQLite-backed search index + cache.
        do {
            let newIndex = try SearchIndex()
            self.searchIndex = newIndex

            // Build cache first so project_meta exists before any wipe.
            let cache = try ProjectMetadataCache(db: newIndex.databaseQueueForReconciler())
            // If the user switched portfolios, wipe FTS + project_meta atomically.
            if let prevPath = newIndex.lastPortfolioRoot(), prevPath != url.path {
                try newIndex.wipeAllForPortfolioSwitch()
            }
            self.cache = cache
            try? newIndex.setLastPortfolioRoot(url.path)
        } catch {
            AppLogger.app.error("SearchIndex/cache init failed: \(error.localizedDescription, privacy: .public). Will retry on refresh.")
            self.searchIndex = nil
            self.cache = nil
            showToast("Search unavailable — index failed to load. Try re-opening the portfolio.", duration: .seconds(4))
        }

        // Synchronously load cached metadata into self.projects so the UI is immediately populated.
        if let cache = self.cache {
            let cached = (try? cache.loadAll()) ?? []
            self.projects = cached.map { ProjectReconciler.project(from: $0, root: url) }
        }
        // Mark ready as soon as we've loaded cached state — the reconciler runs in the background.
        if !isReady { isReady = true }

        // Construct + start the reconciler.
        if let cache = self.cache, let index = self.searchIndex {
            let recon = ProjectReconciler(
                portfolioRoot: url,
                db: index.databaseQueueForReconciler(),
                cache: cache,
                searchIndex: index,
                publish: { [weak self] mutation in
                    Task { @MainActor [weak self] in
                        self?.applyMutation(mutation)
                    }
                }
            )
            self.reconciler = recon

            // Build the search controller now that index + reconciler exist.
            //
            // `index` is weak-captured so that when setRoot tears down on a
            // later portfolio switch (self.searchIndex = nil, releasing the
            // last strong ref), any detached search kicked off by this
            // controller resolves it as nil and returns []. This prevents the
            // in-flight search from pinning the OLD `SearchIndex` alive and
            // racing with the new one on the shared `search.sqlite` file
            // (SQLITE_BUSY hazard).
            //
            // Populate is intentionally NOT wired here — the AppState-owned
            // controller only drives `filteredProjects` and doesn't need to
            // trigger file/link indexing. The palette's own controller owns
            // that (Task 4), keeping the populate call site single-sourced.
            self.searchController = SearchController(
                search: { [weak index] query in
                    guard let index else { return [] }
                    return try index.search(query: query)
                }
                // onMatchedUIDs left at its no-op default.
            )
            // Forward controller changes so SwiftUI views observing AppState
            // re-render when the snapshot updates.
            controllerObserver = self.searchController?.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            // If the user was mid-query at portfolio-switch time, replay it.
            if !self.searchQuery.isEmpty {
                self.searchController?.setQuery(self.searchQuery)
            }

            // Initial background reconciliation against disk.
            recon.startInitialReconciliation()

            // Wire FileWatcher → reconciler (immediate sync; debounce arrives in Task 5).
            fileWatcher = FileWatcher(path: url.path) { [weak recon] paths in
                guard let recon else { return }
                recon.enqueue(paths)
            }
            fileWatcher?.start()
        }
    }

    func refreshProjects(thenSelect uid: String? = nil) {
        guard let recon = reconciler else { return }
        // Record the desired selection BEFORE triggering the scan, so applyMutation
        // can act on insert/update events that arrive on MainActor in any order.
        if let uid {
            pendingSelectionUID = uid
        }
        recon.reconcileTopLevel { [weak self] in
            Task { @MainActor [weak self] in
                // Fast path: if the project is already in self.projects (no mutation needed),
                // select it now. Otherwise applyMutation will pick it up when the insert/update
                // arrives.
                guard let self, let uid = self.pendingSelectionUID else { return }
                if let project = self.projects.first(where: { $0.uid == uid }) {
                    self.setSelectedProject(project)
                    self.pendingSelectionUID = nil
                }
            }
        }
    }

    func createProject(title: String, when: WhenValue, client: String, tags: [String]) {
        guard let rootURL = portfolioRootURL else { return }

        let now = Date()
        let currentYear = Calendar.current.component(.year, from: now)
        let resolvedYear = ProjectMetadataMutation.resolveFolderYear(
            when: when,
            currentYear: currentYear
        )

        // For range projects the frontmatter `date:` is the start anchor; for
        // year-only it's just `now`. `dateEnd:` is written only for range.
        let frontmatterDate = (when.dateEnd != nil) ? when.date : now
        let body = ProjectTemplate.render(
            newProjectTemplate,
            title: title,
            year: resolvedYear,
            client: client,
            tags: tags,
            date: frontmatterDate
        )

        guard let created = try? ProjectCreator.create(
            title: title,
            year: resolvedYear,
            client: client,
            tags: tags,
            rootURL: rootURL,
            body: body,
            date: frontmatterDate,
            dateEnd: when.dateEnd
        ) else { return }

        // Full refresh — picks up the new folder, populates filePaths, rebuilds index.
        // Auto-select the newly created project so it opens immediately.
        refreshProjects(thenSelect: created.uid)
    }

    func updateProjectMetadata(
        project: Project,
        title: String,
        client: String,
        status: ProjectStatus,
        tags: [String],
        teaser: String,
        hidden: Bool,
        when: WhenValue
    ) throws {
        let derivedYear = ProjectMetadataMutation.resolveFolderYear(
            when: when,
            currentYear: project.year
        )
        let newFolderName = Project.folderName(title: title, year: derivedYear, uid: project.uid)
        let willRenameFolder = newFolderName != project.folderName

        // Pre-flight: if the folder rename would collide, refuse the whole operation
        // before we mutate anything on disk.
        if willRenameFolder, let rootURL = portfolioRootURL {
            let newFolderURL = rootURL.appendingPathComponent(newFolderName)
            // Skip the collision throw when the existing path is our own
            // folder under a case-only rename — APFS is case-insensitive by
            // default, so a "Hello" → "hello" title change reports the
            // destination exists even though it's the same directory.
            let isSameFolderDifferentCase =
                newFolderName.lowercased() == project.folderName.lowercased()
            if !isSameFolderDifferentCase,
               FileManager.default.fileExists(atPath: newFolderURL.path) {
                throw NSError(
                    domain: "com.portymcfolio.app",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "A project folder named \"\(newFolderName)\" already exists."]
                )
            }
        }

        // 1. Read and rewrite the README.
        let originalContent = try String(contentsOf: project.readmeURL, encoding: .utf8)
        var parsed = try FrontmatterParser.parse(originalContent)
        parsed.title = title
        parsed.client = client
        parsed.status = status
        parsed.tags = tags
        parsed.teaser = teaser
        parsed.hidden = hidden

        // The user is actively editing the When through the picker; drop any
        // legacy datePrecision YAML key so the new two-mode model is the
        // source of truth for this project going forward.
        parsed.datePrecisionRaw = nil

        // Apply the When directly. For year-only projects we leave parsed.date
        // alone (legacy preservation). For range projects we set both anchors.
        parsed.dateEnd = when.dateEnd
        if when.dateEnd != nil {
            parsed.date = when.date
        }

        let updated = FrontmatterParser.serialize(frontmatter: parsed)
        try updated.write(to: project.readmeURL, atomically: true, encoding: .utf8)

        // Track what we've done so we can roll back on failure.
        var internalFileRenamed = false
        let oldInternalFile = project.folderURL.appendingPathComponent("\(project.folderName).md")
        let newInternalFile = project.folderURL.appendingPathComponent("\(newFolderName).md")

        do {
            // 2. Rename the internal project file (if any).
            if willRenameFolder, let rootURL = portfolioRootURL {
                if FileManager.default.fileExists(atPath: oldInternalFile.path) {
                    try FileManager.default.moveItem(at: oldInternalFile, to: newInternalFile)
                    internalFileRenamed = true
                }

                // 3. Rename the folder.
                let newFolderURL = rootURL.appendingPathComponent(newFolderName)
                try FileManager.default.moveItem(at: project.folderURL, to: newFolderURL)

                projectFolderRenamed(uid: project.uid, newFolderName: newFolderName)
            }
        } catch {
            // Rollback.
            if internalFileRenamed {
                try? FileManager.default.moveItem(at: newInternalFile, to: oldInternalFile)
            }
            try? originalContent.write(to: project.readmeURL, atomically: true, encoding: .utf8)
            throw error
        }

        // 4. Direct-poke the reconciler to sync this project immediately.
        notifyProjectFileChanged(uid: project.uid)
    }

    /// Set the selected project. Triggers lazy file population for the new project
    /// so file/link search returns results for it, and applies the user's
    /// `defaultViewMode` preference when entering a different project
    /// (`.lastUsed` keeps the current `viewMode` unchanged).
    func setSelectedProject(_ project: Project?) {
        if let project,
           project.uid != selectedProject?.uid,
           let mode = defaultViewMode.resolvedViewMode {
            viewMode = mode
        }
        selectedProject = project
        if let project, let recon = reconciler {
            recon.populateFiles(uid: project.uid)
        }
    }

    /// Dispatch for ⌘1. Context-aware: on the project overview it toggles
    /// the grid view, inside a project it switches to the editor.
    func handlePrimaryShortcut() {
        if selectedProject == nil {
            projectListMode = .grid
        } else {
            viewMode = .editor
        }
    }

    /// Dispatch for ⌘2. Context-aware: on the project overview it toggles
    /// the table view, inside a project it switches to the preview.
    func handleSecondaryShortcut() {
        if selectedProject == nil {
            projectListMode = .table
        } else {
            viewMode = .preview
        }
    }

    /// Dispatch for ⌘3. Inside a project: lands on splitGallery from any other
    /// mode; toggles between splitGallery and full gallery on subsequent presses.
    /// No-op on the project overview.
    func handleGalleryShortcut() {
        guard selectedProject != nil else { return }
        toggleSplitOrFull(splitMode: .splitGallery, fullMode: .gallery)
    }

    /// Dispatch for ⌘4. Same toggle pattern as `handleGalleryShortcut` but for
    /// splitList ↔ list.
    func handleListShortcut() {
        guard selectedProject != nil else { return }
        toggleSplitOrFull(splitMode: .splitList, fullMode: .list)
    }

    /// Dispatch for ⌘5. Same toggle pattern as `handleGalleryShortcut` but for
    /// splitLinks ↔ links.
    func handleLinksShortcut() {
        guard selectedProject != nil else { return }
        toggleSplitOrFull(splitMode: .splitLinks, fullMode: .links)
    }

    /// Toggle between a split-pane and full-pane variant of the same content
    /// type. From any unrelated mode, lands on the split variant first
    /// (preserves the editor) — repeated presses then flip between split and
    /// full.
    private func toggleSplitOrFull(splitMode: ViewMode, fullMode: ViewMode) {
        switch viewMode {
        case splitMode:
            viewMode = fullMode
        case fullMode:
            viewMode = splitMode
        default:
            viewMode = splitMode
        }
    }

    /// Tell the reconciler that a specific project's frontmatter or files were just
    /// modified by code inside the app. Bypasses FSEvent latency.
    func notifyProjectFileChanged(uid: String) {
        reconciler?.notifyProjectFileChanged(uid: uid)
    }

    /// Update the cached folder_name for a project after a folder rename, in place,
    /// avoiding the delete+add flicker that would happen if we waited for FSEvents.
    func projectFolderRenamed(uid: String, newFolderName: String) {
        reconciler?.projectFolderRenamed(uid: uid, newFolderName: newFolderName)
    }

    /// Re-walk every project's files and rebuild the file/link FTS rows from scratch.
    /// Triggered from the "Re-index portfolio" command in ⌘K.
    func reindexEverything() {
        reconciler?.reindexEverything()
    }

    deinit {
        let dnc = DistributedNotificationCenter.default()
        let nc = NotificationCenter.default
        for obs in appearanceObservers {
            dnc.removeObserver(obs)
            nc.removeObserver(obs)
        }
    }

    /// Apply a mutation published by the reconciler. Runs on MainActor.
    private func applyMutation(_ mutation: ProjectReconciler.Mutation) {
        switch mutation {
        case .insert(let project):
            // De-duplicate in case both inserts and re-inserts arrive
            if !projects.contains(where: { $0.uid == project.uid }) {
                projects.append(project)
            } else {
                applyMutation(.update(project))
                return
            }
            // Honor any pending selection that's been waiting for this uid
            if pendingSelectionUID == project.uid {
                setSelectedProject(project)
                pendingSelectionUID = nil
            }
        case .update(let project):
            if let idx = projects.firstIndex(where: { $0.uid == project.uid }) {
                projects[idx] = project
                if selectedProject?.uid == project.uid {
                    selectedProject = project
                }
            } else {
                projects.append(project)
            }
            // Honor any pending selection that's been waiting for this uid
            if pendingSelectionUID == project.uid {
                setSelectedProject(project)
                pendingSelectionUID = nil
            }
        case .remove(let uid):
            projects.removeAll { $0.uid == uid }
            if selectedProject?.uid == uid {
                selectedProject = nil
            }
            // If we were waiting to select this uid, abandon the wait
            if pendingSelectionUID == uid {
                pendingSelectionUID = nil
            }
        case .batch(let mutations):
            for m in mutations { applyMutation(m) }
        }
    }
}
