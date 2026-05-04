import Foundation
import Combine

/// Owns the debounced, off-main FTS search pipeline.
///
/// Both `AppState` (for `filteredProjects`) and `SearchPalette` (for grouped
/// results) consume instances of this class. It is deliberately decoupled from
/// `SearchIndex`: callers inject a `search` closure so unit tests can use a stub.
///
/// Concurrency:
/// - Class is `@MainActor` because it publishes to SwiftUI.
/// - Inside `runSearch`, the actual `search` closure is awaited on a detached
///   Task, so FTS5 I/O never blocks the main thread.
/// - Rapid `setQuery(_:)` calls cancel the prior debounce; stale results from
///   in-flight detached tasks are discarded via `latestToken`.
@MainActor
final class SearchController: ObservableObject {

    /// The most recent fully-resolved search result set.
    struct Snapshot: Equatable {
        /// The query string (trimmed) that produced this snapshot. Empty when no
        /// query is active.
        var query: String = ""
        /// Raw FTS results in rank order.
        var results: [SearchResult] = []
        /// Unique project uids surfaced by `results`, in rank order.
        /// Includes project hits (`entityID`) and file/link parent uids.
        /// Useful both for filtering `projects` and for prioritizing lazy
        /// file population.
        var matchedUIDs: [String] = []
    }

    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var lastError: Error?
    @Published private(set) var isSearching = false

    /// Held as `var` so `rebind(...)` can swap them — used by views that
    /// construct the controller as an `@StateObject` before `appState` is
    /// available in `.onAppear`.
    private var searchRef: @Sendable (String) throws -> [SearchResult]
    private var onMatchedUIDsRef: ([String]) -> Void
    private let debounceMs: UInt64

    private var debounceTask: Task<Void, Never>?
    /// Monotonic token incremented on every `runSearch` start. Detached
    /// searches compare against this on completion and drop their results if
    /// a newer query has since fired.
    private var latestToken: UInt64 = 0

    init(
        search: @escaping @Sendable (String) throws -> [SearchResult],
        onMatchedUIDs: @escaping ([String]) -> Void = { _ in },
        debounceMs: UInt64 = 120
    ) {
        self.searchRef = search
        self.onMatchedUIDsRef = onMatchedUIDs
        self.debounceMs = debounceMs
    }

    /// Swap the search and callback closures. Used when an owner (e.g. a view)
    /// constructs the controller before it has access to the real `SearchIndex`
    /// or reconciler, then rebinds once the environment is available.
    ///
    /// Cancels any pending debounce and bumps `latestToken` so any in-flight
    /// detached search that uses the prior `searchRef` has its result
    /// discarded instead of clobbering the snapshot after rebind.
    func rebind(
        search: @escaping @Sendable (String) throws -> [SearchResult],
        onMatchedUIDs: @escaping ([String]) -> Void = { _ in }
    ) {
        debounceTask?.cancel()
        latestToken &+= 1
        self.searchRef = search
        self.onMatchedUIDsRef = onMatchedUIDs
    }

    /// Cancel all pending/in-flight work and reset to empty state.
    ///
    /// Call from the owner's teardown path (e.g. `AppState.setRoot` when
    /// switching portfolios) before releasing the controller. Bumps
    /// `latestToken` so any in-flight detached search — which may still be
    /// running against an old `SearchIndex` / `DatabaseQueue` that the owner
    /// is about to replace — has its result silently discarded.
    ///
    /// Does NOT synchronously cancel the detached FTS call; GRDB reads can't
    /// be interrupted mid-statement. The old query finishes, but its outcome
    /// is discarded. Combined with weak-captured `searchIndex` in the owner's
    /// `search` closure (see AppState.setRoot), this eliminates the window
    /// where two `DatabaseQueue` instances would race on `search.sqlite`.
    func cancelAll() {
        debounceTask?.cancel()
        debounceTask = nil
        latestToken &+= 1
        snapshot = Snapshot()
        lastError = nil
        isSearching = false
    }

    /// Primary entry point. Cancels any pending debounce. Empty queries clear
    /// the snapshot synchronously (no debounce) since the UI shows immediately.
    func setQuery(_ query: String) {
        debounceTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            snapshot = Snapshot()
            lastError = nil
            isSearching = false
            onMatchedUIDsRef([])
            return
        }
        let debounceNs = debounceMs * 1_000_000
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: debounceNs)
            guard !Task.isCancelled, let self else { return }
            await self.runSearch(trimmed)
        }
    }

    private func runSearch(_ query: String) async {
        latestToken &+= 1
        let token = latestToken
        isSearching = true
        let searchFn = self.searchRef
        let outcome: Result<[SearchResult], Error> = await Task.detached(priority: .userInitiated) {
            do { return .success(try searchFn(query)) }
            catch { return .failure(error) }
        }.value
        guard token == latestToken else { return } // newer query in flight
        isSearching = false
        switch outcome {
        case .success(let results):
            lastError = nil
            let uids = Self.matchedUIDs(from: results)
            snapshot = Snapshot(query: query, results: results, matchedUIDs: uids)
            onMatchedUIDsRef(uids)
        case .failure(let err):
            lastError = err
            snapshot = Snapshot(query: query, results: [], matchedUIDs: [])
            onMatchedUIDsRef([])
        }
    }

    /// Extract unique project uids from a result set in rank order.
    /// - Project hits contribute `entityID`.
    /// - File/link hits contribute `parentUID` (when non-empty).
    /// - Tag/command hits contribute nothing.
    nonisolated static func matchedUIDs(from results: [SearchResult]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for r in results {
            let uid: String
            if r.type == .project {
                uid = r.entityID
            } else if !r.parentUID.isEmpty {
                uid = r.parentUID
            } else {
                continue
            }
            if seen.insert(uid).inserted {
                out.append(uid)
            }
        }
        return out
    }
}
