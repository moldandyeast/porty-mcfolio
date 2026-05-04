# Large-Portfolio Performance — Design

**Status:** Approved
**Date:** 2026-04-17
**Branch:** main

## Goal

Make PortyMcFolio launch instantly and stay responsive as the user's portfolio grows toward ~100GB and ~50–200K files, mixed across projects of varying weight (heavy video/RAW projects alongside many-small-asset projects).

The cold-start cliff today is `AppState.refreshProjects` → `performScan` → recursive `enumerateFiles` per project. At 100K files this becomes 5-30s of unresponsive splash before the first project is visible. FSEvents storms (e.g., copying a 50GB folder) trigger repeated full rescans. FTS5 is rebuilt from scratch on every refresh.

## Non-goals

- Network drives / iCloud Drive sync optimization. We assume local SSD.
- Full-text search of file *contents* (we already only index file *names*).
- Lazy-loading the editor body, gallery scroll virtualization, WKWebView preview optimization. These are separate concerns; the gallery's existing per-item async `QLThumbnailGenerator` is already lazy enough.
- Full reactive observability into external file changes from inside `GalleryView` (today gallery refreshes only on user actions; the new design does not change this).
- Memory-pressure eviction of populated `filePaths`. Deferred to v2 if it becomes a real issue.
- Concurrent multi-portfolio open. The app supports one portfolio root at a time; the design assumes that.

## Constraints

- macOS 14+ SwiftUI app, sandboxed, security-scoped portfolio root.
- SQLite via GRDB (already a dependency). One SQLite file at `~/Library/Application Support/PortyMcFolio/search.sqlite`.
- Must preserve existing user-visible behaviors: filter/sort, search palette, gallery, editor, settings popover, CSV export.
- The portfolio filesystem is canonical. Any cache is derived state and must be reconstructible from disk.

## Architecture overview

Three new abstractions sit between the filesystem and `AppState`:

```
                     ┌──────────────────────────────────┐
                     │           AppState               │
                     │  @Published projects: [Project]  │
                     │  @Published selectedProject      │
                     └────────────┬─────────────────────┘
                                  │ subscribes / commands
                                  │
              ┌───────────────────┴────────────────────┐
              │           ProjectReconciler            │
              │  - serial DispatchQueue                │
              │  - debounces FSEvent batches           │
              │  - per-project sync via mtime check    │
              │  - lazy file/link population           │
              │  - batched MainActor publishing        │
              └───┬──────────────┬──────────────┬──────┘
                  │              │              │
        ┌─────────▼────────┐  ┌──▼─────────┐  ┌─▼──────────────┐
        │ ProjectMetadata- │  │ SearchIndex│  │  FileWatcher   │
        │     Cache        │  │  (FTS5)    │  │  (FSEvents)    │
        │ (project_meta)   │  │ (search_fts)│ │  → enqueue     │
        └────────┬─────────┘  └──────┬─────┘  └────────────────┘
                 │                   │
                 └────── shared DatabaseQueue (search.sqlite) ──────┘
```

Views never call cache or reconciler directly. They observe `appState.projects` and call `appState.setSelectedProject(_:)` etc., which in turn delegate to the reconciler.

## File structure

| Path | Action | Responsibility |
|------|--------|----------------|
| `PortyMcFolio/Services/ProjectMetadataCache.swift` | **create** | Pure data layer: `loadAll() -> [CachedProjectMeta]`, `upsert(_:)`, `remove(uid:)`, `clear()`, `aggregateTagCounts() -> [String: Int]`, `replaceFolderName(uid:newFolderName:)`. Owns the `project_meta` SQL table. No business logic. |
| `PortyMcFolio/Services/ProjectReconciler.swift` | **create** | The sync engine. Owns the serial queue, debouncing, per-project sync, lazy file/link population, batched publishing. Depends on `ProjectMetadataCache`, `SearchIndex`, `FileWatcher`, `PortfolioStore`. |
| `PortyMcFolioTests/ProjectMetadataCacheTests.swift` | **create** | Unit tests for the cache (in-memory `DatabaseQueue`). |
| `PortyMcFolioTests/ProjectReconcilerTests.swift` | **create** | Integration tests for the reconciler (real temp directory + in-memory SQLite). |
| `PortyMcFolioTests/ProjectReconcilerDebounceTests.swift` | **create** | Debounce-window timing tests with manual clock injection. |
| `PortyMcFolio/Models/Project.swift` | **modify** | Add `var frontmatterMTime: Date?` field. |
| `PortyMcFolio/Services/SearchIndex.swift` | **modify** | Add `upsertProject(meta:fileEntries:linkEntries:)`, `appendFilesAndLinks(forProjectUID:fileEntries:linkEntries:)`, `rebuildTags(from:)`. Keep existing `rebuild(...)` for the "Re-index everything" command and schema migration. Bump `schemaVersion` from `"2"` to `"3"`. |
| `PortyMcFolio/App/AppState.swift` | **modify** | `setRoot` constructs cache + reconciler; `refreshProjects(thenSelect:)` becomes a thin shim delegating to `reconciler.reconcileTopLevel()`; new `setSelectedProject(_:)` triggers lazy populate; deletes the old `performScan` / `enumerateFiles` static methods and the `cachedLinks` array (moved to reconciler-managed state). |
| `PortyMcFolio/Views/SearchPalette.swift` | **modify** | On query change, calls `appState.populateFilesForLikelyMatches(query:)` to lazily populate file/link FTS rows for the top metadata-matched projects. |
| `PortyMcFolio/Views/GalleryView.swift` | **modify** | After `setTeaser` and `updateReadmeReferences` write to the readme, call `appState.notifyProjectFileChanged(uid:)` so reconciler immediately syncs without waiting for FSEvents. |
| `PortyMcFolio/Views/MarkdownEditorView.swift` | **modify** (small) | Existing `onSave` callback already calls `appState.refreshProjects()`. Replace with `appState.notifyProjectFileChanged(uid:)` for targeted sync. |
| `PortyMcFolio/Models/SearchResult.swift` etc. | **no change** | |
| All other view files | **no change** | They consume `appState.projects` reactively. |

## Persistent metadata cache

Stored alongside the FTS index in `~/Library/Application Support/PortyMcFolio/search.sqlite`. Reuses the existing `DatabaseQueue` so cache + FTS writes can share transactions.

### Schema

```sql
CREATE TABLE IF NOT EXISTS project_meta (
    uid               TEXT PRIMARY KEY,
    folder_name       TEXT NOT NULL,
    year              INTEGER NOT NULL,
    title             TEXT NOT NULL,
    client            TEXT NOT NULL,
    status            TEXT NOT NULL,            -- ProjectStatus.rawValue
    tags_json         TEXT NOT NULL,            -- JSON-encoded [String]
    teaser            TEXT NOT NULL,
    body              TEXT NOT NULL,            -- frontmatter body, source for FTS rebuild
    hidden            INTEGER NOT NULL,         -- 0/1
    date_iso          TEXT NOT NULL,            -- frontmatter `date` field, ISO8601
    frontmatter_mtime REAL NOT NULL,            -- seconds since 1970, the staleness check
    cached_at         REAL NOT NULL             -- when this row was written
);

CREATE INDEX IF NOT EXISTS idx_project_meta_year ON project_meta(year);
```

### Versioning

Piggybacks on the existing `meta` table's `schema_version` row. Bumping `SearchIndex.schemaVersion` from `"2"` → `"3"` (this change) triggers `DROP TABLE IF EXISTS search_fts` AND `DROP TABLE IF EXISTS project_meta` during `migrate()`. Reconciler then performs a one-time full disk scan to repopulate. Same pattern for any future schema change.

### Persisted "last portfolio root"

A new row in the existing `meta` key/value table stores `key='portfolio_root_path', value=<path>`. `setRoot` compares this against the new root URL on switch. If the path differs, `cache.clear()` runs synchronously before any other initialization to prevent the flash-of-old-projects problem.

### What's cached vs. not

| Cached in `project_meta` | Not cached |
|---|---|
| Everything needed to render: project list, gallery card, settings popover | `filePaths` (lazy — see "Lazy file enumeration") |
| `body` so the FTS index can rebuild without re-reading the markdown file | Per-link metadata (lazy, see same) |
| `frontmatter_mtime` (the staleness check) | Folder mtime (we discover stale entries via FSEvents) |

Estimated size: ~2KB per project. 1000 projects → 2MB. 10,000 projects → 20MB.

### API surface

```swift
struct CachedProjectMeta: Equatable {
    let uid: String
    let folderName: String
    let year: Int
    var title: String
    var client: String
    var status: ProjectStatus
    var tags: [String]
    var teaser: String
    var body: String
    var hidden: Bool
    var date: Date
    var frontmatterMTime: Date
}

final class ProjectMetadataCache {
    init(db: DatabaseQueue) throws
    func loadAll() throws -> [CachedProjectMeta]
    func upsert(_ meta: CachedProjectMeta) throws            // wraps its own transaction
    func remove(uid: String) throws                          // wraps its own transaction
    func clear() throws
    func replaceFolderName(uid: String, newFolderName: String) throws
    func aggregateTagCounts() throws -> [String: Int]

    // Variants for use inside a caller-controlled transaction (so cache + FTS
    // writes can commit atomically together). The reconciler is the only caller.
    func upsertWithin(_ db: Database, _ meta: CachedProjectMeta) throws
    func removeWithin(_ db: Database, uid: String) throws
}
```

The reconciler is the only writer. Views never call this directly.

### Corruption handling

`loadAll()` iterates rows and decodes individually. A row that fails to decode (e.g., malformed `tags_json`) is logged (`[Cache] dropping corrupt row uid=...`) and skipped, never thrown. The corrupt uid will look "missing" to the reconciler on its next pass and be re-created from disk.

## Cold-start flow

`AppState.setRoot(_ url: URL)` sequence after this change:

```
 1. accessedURL?.stopAccessingSecurityScopedResource()
 2. url.startAccessingSecurityScopedResource()
 3. saveBookmark(for: url)
 4. Compare url.path against meta.portfolio_root_path:
       - If different: cache.clear() + searchIndex.clearAll() + meta.portfolio_root_path = new path
       - If same: no-op
 5. Construct DatabaseQueue (existing search.sqlite)
 6. Construct ProjectMetadataCache, SearchIndex, ProjectReconciler
 7. cached = cache.loadAll()                                    [SYNC, ~50ms]
 8. self.projects = cached.map { Project(from: $0) }            [filePaths empty]
 9. self.isReady = true                                         [splash dismisses]
10. fileWatcher = FileWatcher(path: url.path) { paths in
       reconciler.enqueue(paths)
    }
11. fileWatcher.start()
12. reconciler.startInitialReconciliation()                     [BACKGROUND]
```

`startInitialReconciliation` runs on the reconciler's serial queue:

- Top-level scan: `contentsOfDirectory(at: portfolioRoot)`, filter to entries that match the project folder name pattern.
- For each on-disk uid: `syncProject(uid:)` — uses the cached entry's `frontmatter_mtime` if present, falls back to a full read for new uids.
- For each cached uid not on disk: `syncProject(uid:)` detects the missing folder and removes from cache + FTS.
- Batches changes onto MainActor every 100ms or at end of pass.

### Time-to-interactive estimates

| Scenario | Cold-start time |
|---|---|
| 1000 cached projects, nothing changed since last launch | ~100ms |
| 1000 projects, 50 modified externally | ~200-500ms |
| Empty cache (first launch after upgrade), 1000 projects on disk | ~1-3s, with progressive UI updates |
| 10,000 projects, no changes | ~200-500ms |

### Behavioral change

Today, `appState.isReady` flips to true only after the first scan publishes results. Under the new flow, `isReady` flips after the cached load (~50ms). The reconciler then runs in the background. **Stale data may be visible for ~100ms-1s on launch.** This is an explicit and acceptable trade-off — the user sees their projects faster, and any external changes propagate visibly within seconds.

## Reconciler

`ProjectReconciler` is the only writer to `project_meta`, `search_fts`, and `appState.projects` (post-launch).

### Threading model

- Owns one serial `DispatchQueue(label: "com.portymcfolio.reconciler", qos: .userInitiated)`.
- All cache + FTS writes happen on this queue. (`DatabaseQueue` already serializes its own access; the queue gives us a stable execution context for ordering.)
- FileWatcher callback enqueues paths and returns immediately.
- Publishes to MainActor in batches (every 100ms or at end of pass).

### Entry points

```swift
final class ProjectReconciler {
    init(
        portfolioRoot: URL,
        cache: ProjectMetadataCache,
        searchIndex: SearchIndex,
        publish: @MainActor @escaping (Mutation) -> Void
    )

    /// Called by FileWatcher; coalesces via debounce.
    func enqueue(_ paths: [String])

    /// Initial pass at launch. Reconciles cache against disk top-to-bottom.
    func startInitialReconciliation()

    /// Called when the app explicitly knows a project's frontmatter file was modified
    /// (editor save, settings popover save, gallery setTeaser, etc.). Bypasses FSEvent latency.
    func notifyProjectFileChanged(uid: String)

    /// Called when AppState.updateProjectMetadata renamed a folder.
    /// Updates cache.folderName in place; does NOT delete + re-add (avoids UI flicker).
    func projectFolderRenamed(uid: String, newFolderName: String)

    /// Called when a project is opened (selectedProject became non-nil) or when
    /// search palette wants to surface file/link results from a project.
    /// Walks the project folder, populates filePaths and link FTS rows.
    /// Idempotent.
    func populateFiles(uid: String) async

    /// Triggered by the "Re-index portfolio" command in ⌘K.
    /// Runs populateFiles for every project. One-shot.
    func reindexEverything() async

    /// Cancel in-flight tasks and disconnect from cache/searchIndex.
    /// Called by AppState.setRoot before constructing a new reconciler for a new portfolio.
    func shutdown()
}

enum Mutation {
    case insert(Project)
    case update(Project)
    case remove(uid: String)
    case batch([Mutation])
}
```

### Debouncing

```
FSEvent batch arrives → reconciler.enqueue(paths)
  - Append paths to a pending Set<String>
  - (Re)schedule a 250ms timer on the reconciler queue
  - When the timer fires:
      - Drain the pending set
      - Reconcile (see below)

If new events arrive during the 250ms window → timer is reset (sliding).
Hard cap: 1000ms total accumulated delay. After that, the reconciler runs even
if events keep arriving, to prevent indefinite delay during heavy writes.
```

### Reconciliation pass

1. **Always** call `reconcileTopLevel()` once per pass. Cheap (a single shallow `contentsOfDirectory`); avoids fragile path-pattern logic to decide whether folders were added/removed.
2. For each path in the drained set, resolve to a uid by stripping the portfolio root prefix and parsing the first path component. Collect a `Set<String>` of affected uids.
3. For each affected uid, call `syncProject(uid:)`.
4. After all per-project syncs in this pass: `searchIndex.rebuildTags(from: cache)` (cheap O(#tags); needed because tag counts cross projects).
5. Publish accumulated mutations to MainActor.

### Per-project sync (the inner loop)

```swift
func syncProject(uid: String) {
    let folderURL = portfolioRoot.appendingPathComponent(folderName(for: uid))

    // Project deleted?
    if !FileManager.default.fileExists(atPath: folderURL.path) {
        cache.remove(uid: uid)
        searchIndex.removeProject(uid: uid)
        accumulate(.remove(uid: uid))
        return
    }

    // Determine readme URL (new convention or legacy README.md)
    let readmeURL = readmeURL(for: folderURL)
    guard let mtime = mtime(of: readmeURL) else { return }

    let cachedEntry = cache.entry(for: uid)

    // Up-to-date and no in-memory file population? Skip entirely.
    if let cached = cachedEntry,
       cached.frontmatterMTime == mtime,
       !hasPopulatedFiles(uid: uid) {
        return
    }

    // Re-parse frontmatter
    guard let content = try? String(contentsOf: readmeURL, encoding: .utf8),
          let parsed = try? FrontmatterParser.parse(content) else {
        // Parse failure: leave cache alone if we have a good entry, else skip.
        // Logged. Will retry on next mtime change.
        return
    }

    let meta = CachedProjectMeta(/* fields from parsed + mtime */)

    // Atomic write to cache + FTS in a single DB transaction.
    db.write { conn in
        cache.upsertWithin(conn, meta)
        searchIndex.upsertProjectWithin(conn, meta: meta, /* file/link entries if populated */)
    }

    accumulate(.update(Project(from: meta)))

    // If files for this project were already populated in memory, refresh them too.
    if hasPopulatedFiles(uid: uid) {
        repopulateFiles(uid: uid)  // re-walk folder, re-upsert file/link FTS rows
    }
}
```

The atomic-write piece is critical: cache and FTS share the `DatabaseQueue`, so wrapping both writes in a single `db.write { ... }` ensures they commit or roll back together. Eliminates the "cache says fresh, FTS is stale" corruption mode.

### FSEvent path → uid resolution

```swift
private func uidFromEventPath(_ path: String) -> String? {
    let rootPrefix = portfolioRoot.path + "/"
    guard path.hasPrefix(rootPrefix) else { return nil }
    let relative = String(path.dropFirst(rootPrefix.count))
    let firstComponent = String(relative.split(separator: "/").first ?? "")
    guard !firstComponent.isEmpty else { return nil }
    // Folder name pattern: {YYYY}_{slug}_{8-hex-uid}
    return try? Project.from(folderName: firstComponent, rootURL: portfolioRoot).uid
}
```

Edge cases:

- Path equals portfolio root → no uid; the unconditional `reconcileTopLevel()` per pass handles new/deleted folders.
- Path's first component doesn't parse as a project folder → ignore (e.g., user dropped a stray file in the root).
- Path's first component is an unknown new project folder → `reconcileTopLevel()` discovers and adds it.

### Direct-poke pattern

Code that writes to a project's markdown file calls `appState.notifyProjectFileChanged(uid:)` (which forwards to the reconciler) immediately after the write. The reconciler runs `syncProject(uid:)` directly without debounce — much faster than waiting for FSEvents.

Even if FSEvents fires later for the same write, the second sync sees mtime unchanged and no-ops. Idempotent.

Affected call sites:

| Call site | Action |
|---|---|
| `MarkdownEditorView.saveContent` (via `onSave` callback) | Replace existing `appState.refreshProjects()` with `appState.notifyProjectFileChanged(uid:)` |
| `AppState.updateProjectMetadata` | Call `reconciler.notifyProjectFileChanged(uid:)` after the write. If a folder rename also happened, call `reconciler.projectFolderRenamed(uid:newFolderName:)` *before* `notifyProjectFileChanged`. |
| `GalleryView.setTeaser` | Call `appState.notifyProjectFileChanged(uid: project.uid)` after the write. |
| `GalleryView.updateReadmeReferences` | Same. |

### Folder rename without flicker

`projectFolderRenamed(uid:newFolderName:)` updates `project_meta.folder_name` for the row in place. No delete + insert. `appState.projects` mutation is `.update(...)`, not `.remove + .insert`. UI sees the project's folder name change atomically.

### Lazy file population

`populateFiles(uid:)` is the on-demand walker. It:

1. Recursively enumerates the project folder (one pass).
2. For each non-link file: appends to in-memory `filePaths` for that uid + records a file FTS entry.
3. For each `link-{uid}.md`: parses it + records a link FTS entry.
4. Issues one `searchIndex.appendFilesAndLinks(forProjectUID:fileEntries:linkEntries:)` call (clears existing file/link rows for this uid first, then inserts).
5. Updates `appState.projects[uid].filePaths` on MainActor.

Triggered by:

- **Project open:** `AppState.setSelectedProject(_:)` calls `reconciler.populateFiles(uid:)` as a fire-and-forget Task before the navigation completes. The view shows the project even if file population isn't done yet — file-related searches just return empty for that project for ~10-100ms.
- **⌘K with file/link query:** `SearchPalette` `onChange(of: query)` calls `appState.populateFilesForLikelyMatches(query:)`, which:
  - Runs the FTS search to find metadata matches.
  - Picks the top `lazyPopulateFanout = 10` matched project uids (named constant on the reconciler).
  - Calls `reconciler.populateFiles(uid:)` for each.
  - Gated to queries with at least `lazyPopulateMinQueryLength = 2` chars (avoids thrashing on single-char input).

Once a project has populated files, subsequent `syncProject(uid:)` calls (triggered by FSEvents or direct-poke) re-walk and re-upsert to keep the populated state current.

## Incremental FTS updates

### New `SearchIndex` methods

```swift
/// Replace all FTS rows for a single project (project + file + link rows for that uid).
/// Used for both fresh inserts and updates.
/// Caller is expected to wrap this + the cache.upsert in one transaction.
func upsertProjectWithin(_ conn: Connection, meta: CachedProjectMeta,
                        fileEntries: [(fileName: String, relativePath: String, fileNameNoExt: String)],
                        linkEntries: [LinkItem]) throws

/// Append file + link rows after a lazy populateFiles. Existing file/link rows
/// for the project are cleared first.
func appendFilesAndLinks(forProjectUID uid: String,
                         fileEntries: [(fileName: String, relativePath: String, fileNameNoExt: String)],
                         linkEntries: [LinkItem]) throws

/// Recompute all 'tag' rows from the cache. Cheap — O(#tags).
func rebuildTags(from cache: ProjectMetadataCache) throws
```

### Why tags get a global rebuild per pass

A tag's `secondary_text` shows its project count, which aggregates across all projects. When project X loses tag "UI", the global "UI" count must drop by 1. Rebuilding all tag rows once per reconciliation batch is the cleanest expression of "tag rows are derived from `project_meta.tags_json` aggregated."

Cost: O(#tags). For a portfolio with even thousands of projects, total unique tags is in the hundreds. ~1ms.

### When `rebuild` (the bulk method) is still used

1. Schema migration in `SearchIndex.migrate()` — cache + FTS both empty, reconciler does a full pass that effectively "rebuilds" by upserting every project.
2. `reindexEverything()` — the user-triggered "Re-index portfolio" command in ⌘K.

## Failure modes

### Schema migration

`schemaVersion` bump → `DROP TABLE` for both `search_fts` and `project_meta` → next launch starts with an empty cache → reconciler does a full disk scan. Same cost as today's startup but only once per schema bump. Future column additions follow this pattern.

### App Support directory deleted by user

`DatabaseQueue` recreates the SQLite file. `migrate()` runs schema setup. `cache.loadAll()` returns empty. Reconciler does full scan. This is also the documented user emergency path: "delete `search.sqlite` to force re-index."

### Frontmatter parse failure

Logged (`[Reconciler] parse failed for uid=...`). If a cached entry exists for that uid, it's left untouched (don't replace good data with nothing). If it's a new uid, it's not added. Retried on next mtime change.

### Cache row corruption

`loadAll()` skips corrupt rows individually (logged). The reconciler treats them as missing → re-creates from disk on the next pass.

### Disk full / write permission errors

Logged. Cache + FTS writes are wrapped in one transaction → both fail atomically. The cached entry remains stale. Subsequent retries on next mtime change. App stays responsive.

### Reconciler queue starvation under heavy writes

Pathological: a script touches 10,000 files per second.

- 250ms debounce + 1000ms cap → at most one reconciliation per second.
- Each pass re-stats every project, but cache mtime checks let almost all projects skip the read+parse+write path. Only actually-changed projects do work.
- Worst realistic case: ~1000 stat() calls per second + a handful of upserts. Manageable.

### `setRoot` to a different portfolio

`reconciler.shutdown()` cancels in-flight tasks, drops FileWatcher, closes the queue. Then `cache.clear()` (because `meta.portfolio_root_path` differs). Then a fresh reconciler/cache is constructed for the new root. No stale data leaks across portfolios.

## Cleanup of dead code

After implementation, the following can be removed from `AppState`:

- `private nonisolated static func performScan(...)` — logic moves to `ProjectReconciler.startInitialReconciliation` + `syncProject`.
- `private nonisolated static func enumerateFiles(...)` — logic moves to `ProjectReconciler.populateFiles`.
- `cachedLinks: [CachedLink]` array and the `CachedLink` nested struct — replaced by reconciler-managed lazy state.
- `private var refreshTask`, `private var scanTask` — reconciler owns its own task management.

`refreshProjects(thenSelect:)` becomes a thin compatibility shim that delegates to `reconciler.reconcileTopLevel()` then sets `selectedProject` from the result. Keeps existing call sites' signatures unchanged for the migration.

## Testing strategy

### `ProjectMetadataCacheTests.swift` (in-memory `DatabaseQueue`, no filesystem)

1. `testEmptyCacheReturnsEmptyArray`
2. `testUpsertThenLoadRoundTrips`
3. `testUpsertReplacesExistingRow` (same uid twice)
4. `testRemoveDropsRow`
5. `testClearWipesEverything`
6. `testCorruptTagsJsonDropsRowGracefully` (manual malformed insert)
7. `testFrontmatterMTimeRoundTripsAtSecondPrecision`
8. `testHiddenBoolRoundTripsBothValues`
9. `testAggregateTagCountsAcrossProjects`
10. `testReplaceFolderNameUpdatesInPlace`

### `ProjectReconcilerTests.swift` (real temp directory + in-memory SQLite)

11. `testInitialReconciliationOnEmptyPortfolio`
12. `testInitialReconciliationDiscoversProjectOnDisk`
13. `testReconciliationTrustsCacheWhenMTimeUnchanged` (asserts `FrontmatterParser.parse` is not called for a fresh cache)
14. `testReconciliationDetectsStaleEntryViaMTime`
15. `testReconciliationRemovesDeletedProject`
16. `testReconciliationDiscoversNewProject`
17. `testCacheAndFTSWritesAreAtomic` (inject failing search index; assert cache row rolled back)
18. `testProjectFolderRenamedUpdatesFolderNameInPlace`
19. `testNotifyProjectFileChangedTriggersImmediateSync`
20. `testPopulateFilesAddsFTSFileAndLinkRows`
21. `testPopulateFilesIsIdempotent` (call twice, no duplicates)
22. `testRePopulatesAfterSyncWhenFilesAlreadyLoaded`
23. `testFSEventPathToUIDResolution` (positive and negative cases)
24. `testParseFailureLeavesCachedEntryAlone`

### `ProjectReconcilerDebounceTests.swift` (manual clock injection)

25. `testEnqueueSingleEventTriggersAfterDebounce` (advance virtual clock 250ms)
26. `testRapidEnqueueCoalescesIntoOneRun` (100 events in 100ms → 1 run)
27. `testSlidingWindowCapsAt1000ms` (events every 100ms for 2s → fires at 1000ms)

### Manual smoke tests (deferred to user after implementation)

| Scenario | What to verify |
|---|---|
| Fresh launch on a 50+ project portfolio | Project list visible in <500ms |
| Cold launch with no changes since last launch | Splash dismisses fast, no rebuild flash |
| Edit a project's frontmatter via Finder | Project list reflects new title within 1s |
| Drop a folder of files into a project via Finder | No spinner storms; gallery shows files when navigated |
| Switch portfolio root | Old projects vanish before new ones appear (no flash mixing the two) |
| ⌘K search before opening any project | Project + tag results appear; file/link results may be empty for never-opened projects |
| ⌘K search after opening some projects | File/link results from opened projects appear |
| "Re-index portfolio" command | Brief activity, then file/link results from all projects available |
| Quit + re-launch | Same instant launch as case 1 |

### What we deliberately don't test

- End-to-end FSEvents (would require triggering real OS events; flaky). The reconciler's per-event handling is tested with synthetic path inputs; we trust `FileWatcher`'s existing shape.
- SwiftUI re-rendering on `appState.projects` mutations (visual; covered by manual smoke tests).
- QuickLook thumbnail latency (out of scope).

### Test infrastructure notes

- `ProjectReconciler` accepts dependencies via init for test injection (`ProjectMetadataCache`, `SearchIndex`, `publish:` closure).
- For temp-directory tests, `FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)` + cleanup in `tearDown`. Pattern already in `ProjectCreatorTests.swift` and `PortfolioStoreTests.swift`.
- For debounce tests, a `ManualClock` abstraction injected into the reconciler. If we don't have one yet, swap to small real-time `Thread.sleep` (acceptable; slow but not flaky).

Roughly **27 new tests**, ~150-250 lines of test code.

## Out of scope (deferred to future work)

- Memory-pressure eviction of populated `filePaths` for projects opened earlier in the session.
- LRU eviction of `cachedLinks` from memory.
- Auto-refresh of `GalleryView` on external FSEvents (today gallery refreshes only on user actions).
- Full-text search of file contents (PDF, doc, etc.).
- Network drive / iCloud Drive optimization.
- Rich progress UI for long-running reconciliation passes (we accept "stale data for ~1s on launch" as the trade-off).
- Concurrent multi-portfolio support.
