import Foundation
import GRDB

final class ProjectReconciler {
    typealias PublishHandler = (Mutation) -> Void

    enum Mutation {
        case insert(Project)
        case update(Project)
        case remove(uid: String)
        case batch([Mutation])
    }

    private let portfolioRoot: URL
    private let db: DatabaseQueue
    private let cache: ProjectMetadataCache
    private let searchIndex: SearchIndex
    private let publish: PublishHandler
    private let queue = DispatchQueue(label: "com.portymcfolio.reconciler", qos: .userInitiated)

    /// Bookkeeping for projects whose files have been lazily populated.
    /// Used by syncProject to decide whether to re-walk file/link rows.
    private var populatedFileUIDs: Set<String> = []

    // MARK: - Debouncer state

    private static let debounceWindow: TimeInterval = 0.25
    private static let debounceCap: TimeInterval = 1.0
    static let lazyPopulateFanout = 10
    static let lazyPopulateMinQueryLength = 2

    private var pendingPaths: Set<String> = []
    private var debounceTimer: DispatchSourceTimer?
    private var debounceFirstEnqueueAt: Date?

    /// Test hook: invoked at the start of every reconciliation pass.
    var testHookOnReconciliationPass: (() -> Void)?

    init(
        portfolioRoot: URL,
        db: DatabaseQueue,
        cache: ProjectMetadataCache,
        searchIndex: SearchIndex,
        publish: @escaping PublishHandler
    ) {
        self.portfolioRoot = portfolioRoot
        self.db = db
        self.cache = cache
        self.searchIndex = searchIndex
        self.publish = publish
    }

    func shutdown() {
        queue.sync {
            debounceTimer?.cancel()
            debounceTimer = nil
            pendingPaths.removeAll()
            debounceFirstEnqueueAt = nil
        }
    }

    // MARK: - Public entry points

    /// Initial reconciliation pass — top-level scan + per-project sync for all uids
    /// (those on disk and those in cache). `completion` runs on the reconciler queue
    /// after the pass finishes.
    func startInitialReconciliation(completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            self?.runReconciliationPass()
            completion?()
        }
    }

    /// Top-level scan only — finds new/deleted project folders. Used between launches
    /// and from inside `enqueue` (Task 5).
    func reconcileTopLevel(completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            self?.runReconciliationPass()
            completion?()
        }
    }

    /// Sync a single project immediately (no debounce). Used by direct-poke callers
    /// (editor save, settings popover save, gallery teaser/rename writes).
    func notifyProjectFileChanged(uid: String, completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            self.syncProject(uid: uid)
            // Tags depend on cache aggregate — refresh after each direct-poke sync.
            do {
                try self.searchIndex.rebuildTags(from: self.cache)
            } catch {
                AppLogger.reconciler.error("rebuildTags failed after direct-poke sync: \(error.localizedDescription, privacy: .public)")
            }
            completion?()
        }
    }

    /// Walk a project folder, populate its file + link FTS rows, and mark the uid
    /// as "files loaded" so future syncProject calls re-walk to keep the index current.
    /// Idempotent: a second call for the same uid short-circuits — stale data is
    /// caught by the syncProject re-population guard when frontmatter mtime changes.
    /// To FORCE a re-walk (e.g., the "Re-index portfolio" command), call
    /// `repopulateFilesForUID` directly via `reindexEverything`.
    func populateFiles(uid: String, completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            let alreadyPopulated = self.populatedFileUIDs.contains(uid)
            self.populatedFileUIDs.insert(uid)
            if !alreadyPopulated,
               let filePaths = self.repopulateFilesForUID(uid),
               let cached = self.cache.load(uid: uid) {
                var project = Self.project(from: cached, root: self.portfolioRoot)
                project.filePaths = filePaths
                self.publish(.update(project))
            }
            completion?()
        }
    }

    /// Re-walk every project on disk and rebuild file/link FTS rows for all of them.
    /// Used by the "Re-index portfolio" command. One-shot; runs on the reconciler queue.
    /// Bypasses populateFiles' short-circuit by directly calling repopulateFilesForUID.
    func reindexEverything(completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            let folders = self.scanRootForProjectFolders()
            for folder in folders {
                self.populatedFileUIDs.insert(folder.uid)
                if let filePaths = self.repopulateFilesForUID(folder.uid),
                   let cached = self.cache.load(uid: folder.uid) {
                    var project = Self.project(from: cached, root: self.portfolioRoot)
                    project.filePaths = filePaths
                    self.publish(.update(project))
                }
            }
            do {
                try self.searchIndex.rebuildTags(from: self.cache)
            } catch {
                AppLogger.reconciler.error("rebuildTags failed during reindexEverything: \(error.localizedDescription, privacy: .public)")
            }
            completion?()
        }
    }

    /// Re-index file/link FTS rows for a project and return the file relative paths.
    /// Does NOT publish — callers are responsible for building a `Project` with
    /// the returned paths and publishing. Returns `nil` on missing folder or indexing error.
    @discardableResult
    private func repopulateFilesForUID(_ uid: String) -> [String]? {
        guard let folder = scanRootForProjectFolders().first(where: { $0.uid == uid }) else {
            return nil
        }
        let entries = enumerateFilesAndLinks(folderURL: folder.folderURL, folderName: folder.folderName)
        do {
            try searchIndex.appendFilesAndLinks(
                forProjectUID: uid,
                fileEntries: entries.files,
                linkEntries: entries.links
            )
        } catch {
            AppLogger.reconciler.error("appendFilesAndLinks failed for uid=\(uid, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return entries.files.map { $0.relativePath }
    }

    private struct EnumeratedEntries {
        let files: [(fileName: String, relativePath: String, fileNameNoExt: String)]
        let links: [LinkItem]
    }

    private func enumerateFilesAndLinks(folderURL: URL, folderName: String) -> EnumeratedEntries {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return EnumeratedEntries(files: [], links: []) }

        var files: [(fileName: String, relativePath: String, fileNameNoExt: String)] = []
        var links: [LinkItem] = []

        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name == "README.md" || name == "\(folderName).md" { continue }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir { continue }

            let relativePath = url.path.replacingOccurrences(
                of: folderURL.path + "/", with: ""
            )

            if LinkItem.isLinkFile(name: name) {
                let fileUID = String(name.dropFirst("link-".count).dropLast(".md".count))
                if let md = try? String(contentsOf: url, encoding: .utf8),
                   let link = try? LinkItem.parse(markdown: md, overrideUID: fileUID) {
                    links.append(link)
                }
            } else {
                files.append((
                    fileName: name,
                    relativePath: relativePath,
                    fileNameNoExt: url.deletingPathExtension().lastPathComponent
                ))
            }
        }
        return EnumeratedEntries(files: files, links: links)
    }

    /// Enqueue paths from an FSEvent batch. Coalesces with other events arriving
    /// within the debounce window. After the window expires, runs one reconciliation
    /// pass that syncs all affected uids and a top-level scan.
    func enqueue(_ paths: [String]) {
        queue.async { [weak self] in
            guard let self else { return }
            let now = Date()
            if self.debounceFirstEnqueueAt == nil {
                self.debounceFirstEnqueueAt = now
            }
            self.pendingPaths.formUnion(paths)
            self.scheduleDebouncedFire(now: now)
        }
    }

    private func scheduleDebouncedFire(now: Date) {
        // Determine fire time: min(now + window, firstEnqueue + cap)
        let earliestFire = now.addingTimeInterval(Self.debounceWindow)
        let cappedFire: Date
        if let first = debounceFirstEnqueueAt {
            cappedFire = first.addingTimeInterval(Self.debounceCap)
        } else {
            cappedFire = earliestFire
        }
        let fireAt = min(earliestFire, cappedFire)
        let delay = max(0, fireAt.timeIntervalSince(now))

        debounceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.fireDebouncedPass()
        }
        timer.resume()
        debounceTimer = timer
    }

    private func fireDebouncedPass() {
        let paths = pendingPaths
        pendingPaths.removeAll()
        debounceFirstEnqueueAt = nil
        debounceTimer?.cancel()
        debounceTimer = nil
        runReconciliationPass(forPaths: paths)
    }

    /// Update the cached folder_name for a project after AppState renames the folder.
    /// Avoids the delete+add flicker that would happen if we waited for FSEvents.
    /// Runs on the reconciler queue so it can't race with concurrent reconciliation passes.
    func projectFolderRenamed(uid: String, newFolderName: String, completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try self.cache.replaceFolderName(uid: uid, newFolderName: newFolderName)
                // Republish so the UI sees the new folderName
                if let entry = self.cache.load(uid: uid) {
                    self.publish(.update(Self.project(from: entry, root: self.portfolioRoot)))
                }
            } catch {
                AppLogger.reconciler.error("projectFolderRenamed failed for uid=\(uid, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            completion?()
        }
    }

    // MARK: - Internal: reconciliation pass

    private func runReconciliationPass() {
        runReconciliationPass(forPaths: nil)
    }

    private func runReconciliationPass(forPaths paths: Set<String>?) {
        testHookOnReconciliationPass?()

        // 1. Always run a top-level scan to find new/deleted project folders.
        let onDiskFolders = scanRootForProjectFolders()
        var folderMap: [String: OnDiskFolder] = [:]
        folderMap.reserveCapacity(onDiskFolders.count)
        for folder in onDiskFolders { folderMap[folder.uid] = folder }
        let onDiskUIDs = Set(folderMap.keys)

        let cachedUIDs: Set<String>
        do {
            cachedUIDs = Set(try cache.loadAll().map(\.uid))
        } catch {
            AppLogger.reconciler.error("cache.loadAll failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        // 2. Compute the union of "uids to consider":
        //    - All uids present on disk (handles new projects)
        //    - All cached uids (handles deletions)
        //    - For incremental events: all uids resolved from event paths
        var affectedUIDs = onDiskUIDs.union(cachedUIDs)
        if let paths {
            for path in paths {
                if let uid = uidFromEventPath(path) { affectedUIDs.insert(uid) }
            }
        }

        // 3. Sync each affected uid.
        for uid in affectedUIDs {
            syncProject(uid: uid, folderMap: folderMap)
        }

        // 4. Recompute tag rows once per pass.
        do {
            try searchIndex.rebuildTags(from: cache)
        } catch {
            AppLogger.reconciler.error("rebuildTags failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Sync a single project. Caller is the reconciler queue.
    /// `folderMap` is supplied by `runReconciliationPass` to avoid an N+1 root scan;
    /// when nil (direct-poke path), this method scans the root just for the one uid.
    private func syncProject(uid: String, folderMap: [String: OnDiskFolder]? = nil) {
        // Locate the project's folder. Prefer the pre-built map; fall back to a fresh scan.
        let onDiskFolder: OnDiskFolder?
        if let folderMap {
            onDiskFolder = folderMap[uid]
        } else {
            onDiskFolder = scanRootForProjectFolders().first { $0.uid == uid }
        }

        // Project deleted?
        guard let folderInfo = onDiskFolder else {
            do {
                try db.write { conn in
                    try cache.removeWithin(conn, uid: uid)
                    try searchIndex.removeProjectWithin(conn, uid: uid)
                }
                publish(.remove(uid: uid))
                populatedFileUIDs.remove(uid)
            } catch {
                AppLogger.reconciler.error("removal write failed for uid=\(uid, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            return
        }

        let readmeURL = readmeURL(forFolder: folderInfo.folderURL, folderName: folderInfo.folderName)
        guard let mtime = mtimeOf(readmeURL) else { return }

        let cachedEntry: CachedProjectMeta? = cache.load(uid: uid)

        // Up-to-date and no in-memory file population? Skip entirely.
        if let cached = cachedEntry,
           cached.frontmatterMTime.timeIntervalSince1970 == mtime.timeIntervalSince1970,
           !populatedFileUIDs.contains(uid) {
            return
        }

        // Re-parse frontmatter
        guard let content = try? String(contentsOf: readmeURL, encoding: .utf8),
              let parsed0 = try? FrontmatterParser.parse(content) else {
            AppLogger.reconciler.warning("parse failed for uid=\(uid, privacy: .public) — leaving cache as-is")
            let folderName = folderInfo.folderName
            NotificationCenter.default.post(
                name: .showToast,
                object: "Couldn't read \"\(folderName)\". Check the frontmatter for syntax errors."
            )
            return
        }

        // External-edit resilience: reconcile favorites, teaser, and body embeds
        // against the on-disk file tree so Finder moves/renames are caught.
        // See spec for rationale; in-app moves are already handled upstream.
        var parsed = parsed0
        var needsWrite = false
        var droppedFavoritesCount = 0

        // Single on-disk walk, shared by all three reconciliations.
        let mediaPaths = enumerateMediaPaths(under: folderInfo.folderURL)

        // 1. Favorites
        if !parsed.favorites.isEmpty {
            let favResult = FavoritesReconciliation.reconcile(
                favorites: parsed.favorites,
                onDiskPaths: mediaPaths
            )
            if favResult.reconciled != parsed.favorites {
                parsed.favorites = favResult.reconciled
                needsWrite = true
            }
            droppedFavoritesCount = favResult.droppedCount
        }

        // 2. Teaser
        if !parsed.teaser.isEmpty {
            let teaserOutcome = TeaserReconciliation.reconcile(
                teaser: parsed.teaser,
                onDiskPaths: mediaPaths
            )
            if case .repaired(let newPath) = teaserOutcome {
                parsed.teaser = newPath
                needsWrite = true
            }
        }

        // 3. Body embeds
        if !parsed.body.isEmpty {
            let bodyResult = BodyEmbedReconciliation.reconcile(
                body: parsed.body,
                onDiskPaths: mediaPaths
            )
            if bodyResult.body != parsed.body {
                parsed.body = bodyResult.body
                needsWrite = true
            }
        }

        // Write once if anything changed.
        if needsWrite {
            let updated = FrontmatterParser.serialize(frontmatter: parsed)
            do {
                try updated.write(to: readmeURL, atomically: true, encoding: .utf8)
                NotificationCenter.default.post(name: .markdownFileDidChange, object: readmeURL)
            } catch {
                AppLogger.reconciler.error("reconciliation rewrite failed for uid=\(uid, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        // Toast favorites drops (separate from the write — fires even when
        // droppedCount > 0 but needsWrite happens to be false, e.g. the
        // favorites list was already empty after a prior reconciliation).
        if droppedFavoritesCount > 0 {
            let message: String
            if droppedFavoritesCount == 1 {
                message = "1 favorite removed from \"\(parsed.title)\" — file is gone."
            } else {
                message = "\(droppedFavoritesCount) favorites removed from \"\(parsed.title)\" — files are gone."
            }
            NotificationCenter.default.post(name: .showToast, object: message)
        }

        let meta = CachedProjectMeta(
            uid: uid,
            folderName: folderInfo.folderName,
            year: folderInfo.year,
            title: parsed.title,
            client: parsed.client,
            status: parsed.status,
            tags: parsed.tags,
            teaser: parsed.teaser,
            favorites: parsed.favorites,
            body: parsed.body,
            hidden: parsed.hidden,
            date: parsed.date,
            dateEnd: parsed.dateEnd,
            frontmatterMTime: mtime
        )

        let isInsert = (cachedEntry == nil)

        // Atomic cache + FTS write in a single transaction.
        do {
            try db.write { conn in
                try cache.upsertWithin(conn, meta)
                try searchIndex.upsertProjectWithin(
                    conn, meta: meta,
                    fileEntries: [],   // file/link rows added via lazy populate (Task 6)
                    linkEntries: []
                )
            }
        } catch {
            AppLogger.reconciler.error("atomic write failed for uid=\(uid, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }

        // If files were lazily populated, re-index and carry the fresh paths into
        // the single publish below. (Previously this path published twice and the
        // second publish silently wiped filePaths.)
        let filePaths: [String]
        if populatedFileUIDs.contains(uid) {
            filePaths = repopulateFilesForUID(uid) ?? []
        } else {
            filePaths = []
        }

        var project = Self.project(from: meta, root: portfolioRoot)
        project.filePaths = filePaths
        publish(isInsert ? .insert(project) : .update(project))
    }

    // MARK: - Internal helpers (some exposed for tests)

    struct OnDiskFolder {
        let uid: String
        let year: Int
        let folderName: String
        let folderURL: URL
    }

    private func scanRootForProjectFolders() -> [OnDiskFolder] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: portfolioRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [OnDiskFolder] = []
        for url in contents {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }
            let folderName = url.lastPathComponent
            guard let project = try? Project.from(folderName: folderName, rootURL: portfolioRoot) else { continue }
            result.append(OnDiskFolder(uid: project.uid, year: project.year, folderName: folderName, folderURL: url))
        }
        return result
    }

    private func readmeURL(forFolder folderURL: URL, folderName: String) -> URL {
        let projectFile = folderURL.appendingPathComponent("\(folderName).md")
        if FileManager.default.fileExists(atPath: projectFile.path) { return projectFile }
        return folderURL.appendingPathComponent("README.md")
    }

    private func mtimeOf(_ url: URL) -> Date? {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            return attrs[.modificationDate] as? Date
        } catch {
            AppLogger.reconciler.warning("mtime read failed for \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Resolve an FSEvent path to a project uid by stripping the portfolio root prefix
    /// and parsing the first relative path component as a project folder name.
    /// Returns nil for the portfolio root itself, paths outside the root, or unparseable
    /// folder names.
    func uidFromEventPath(_ path: String) -> String? {
        let rootPrefix = portfolioRoot.path.hasSuffix("/") ? portfolioRoot.path : portfolioRoot.path + "/"
        guard path.hasPrefix(rootPrefix) else { return nil }
        let relative = String(path.dropFirst(rootPrefix.count))
        guard !relative.isEmpty else { return nil }
        let firstComponent = String(relative.split(separator: "/").first ?? "")
        guard !firstComponent.isEmpty else { return nil }
        return (try? Project.from(folderName: firstComponent, rootURL: portfolioRoot))?.uid
    }

    /// Enumerate all media files under a project folder, returning their
    /// project-relative paths. Used by the favorites reconciliation pass.
    private func enumerateMediaPaths(under folderURL: URL) -> Set<String> {
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let prefix = folderURL.path + "/"
        var result: Set<String> = []
        for case let fileURL as URL in enumerator {
            let isRegularFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            guard isRegularFile else { continue }
            guard MediaKind.isMedia(url: fileURL) else { continue }
            let rel = fileURL.path.replacingOccurrences(of: prefix, with: "")
            result.insert(rel)
        }
        return result
    }

    /// Build a `Project` value from a cached metadata entry.
    static func project(from meta: CachedProjectMeta, root: URL) -> Project {
        Project(
            uid: meta.uid,
            year: meta.year,
            folderName: meta.folderName,
            folderURL: root.appendingPathComponent(meta.folderName),
            title: meta.title,
            date: meta.date,
            dateEnd: meta.dateEnd,
            tags: meta.tags,
            client: meta.client,
            status: meta.status,
            body: meta.body,
            teaser: meta.teaser,
            favorites: meta.favorites,
            hidden: meta.hidden,
            filePaths: [],
            frontmatterMTime: meta.frontmatterMTime
        )
    }
}
