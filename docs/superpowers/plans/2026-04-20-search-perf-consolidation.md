# Search Perf Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate per-keystroke main-thread FTS5 thrash by introducing a single `SearchController` that owns query debouncing, off-main FTS, and result publishing; both `SearchPalette` and `AppState.filteredProjects` consume its snapshot. Surface FTS errors and add regression coverage for the fallback branch.

**Architecture:** New `@MainActor ObservableObject` class `SearchController`. On `setQuery(_:)` it cancels any in-flight debounce, schedules a ~120 ms debounced run, then performs the FTS call on a detached Task. Results are published as a `Snapshot { query, results, matchedUIDs }` plus a `lastError: Error?`. Two instances are used: one owned by `AppState` (drives `filteredProjects`), one owned by `SearchPalette` (drives the palette's grouped list and kicks off lazy file population via an `onMatchedUIDs` callback). Because the controller is reusable and stateless across portfolio switches, `AppState` constructs/tears it down alongside `searchIndex`.

**Tech Stack:** Swift 5.9, SwiftUI, structured concurrency (`Task.detached`, `Task.sleep`), GRDB (already a dep, unchanged), XCTest. No new dependencies.

**Spec:** This plan derives from an ad-hoc search review conducted in conversation on 2026-04-20. Relevant findings:
- `SearchPalette.swift:283-288` runs synchronous `try? index.search(...)` on every keystroke.
- `AppState.swift:103-115` `filteredProjects` also runs synchronous FTS on every view render.
- `AppState.swift:408` `populateFilesForLikelyMatches` runs FTS a *third* time to pick uids.
- Errors from FTS are swallowed (`try?`) and never surfaced.
- The fallback branch in `filteredProjects` (when FTS returns empty) has no test coverage.

**Out of scope (deferred to follow-up plans):** BM25 column weighting, per-type result limits, typo/substring fuzzy fallback, non-incremental `rebuildTags`, schema migration instead of wipe, hidden-project filter in SQL, periodic `pragma optimize`, `parent_uid` sidecar table.

**Known trade-offs accepted in this plan:**

1. **120 ms snapshot-lag window on `filteredProjects`.** During the debounce window, `snapshot.query` reflects the previous query. The plan's `filteredProjects` falls through to case-insensitive substring matching on metadata when the snapshot is stale. That fallback has different result ordering from FTS (and for non-prefix matches, different result sets), so for ~120 ms after the last keystroke the main project list may reorder or show slightly different projects before snapping to the FTS snapshot. Acceptable because (a) the window is short, (b) substring matching returns a reasonable approximation for the common case (title/client match), and (c) the alternative — freezing the list until FTS catches up — is worse UX. Manual verification step 3 explicitly watches for visible flicker; if objectionable, a follow-up could use "if `snapshot.query` is a prefix of the current trimmed query, reuse the snapshot" as a cheaper approximation than substring fallback.
2. **2-char minimum query guard is dropped.** Task 5 removes it; see that task for rationale.
3. **`@StateObject` two-phase init in `SearchPalette`.** The palette's `SearchController` is instantiated with a no-op `search: { _ in [] }` and immediately `rebind`-ed in `.onAppear`. Ugly but bounded — no visible effect to the user because `.onAppear` fires before the TextField can accept input.

## A note on line numbers in this plan

The plan cites current source line numbers (e.g. "currently line 221") to help the executor navigate. Those numbers drift as earlier tasks add lines to the same files. When a step's cited line number doesn't match what you see, **don't guess** — Grep for a stable string from the surrounding code (the doc-comment, a unique variable name, an exact SQL literal) to re-anchor, then apply the edit.

---

## Prerequisites

This plan is authored on branch `dev/large-portfolio-perf`. There is one uncommitted file at plan-write time: `.claude/settings.local.json` (unrelated to search). Before executing, either commit that or stash it; it will not conflict with the files this plan touches.

```bash
git status --short
```

Expected: `M .claude/settings.local.json` (or clean).

---

## Conventions

**Test command** (xcodebuild needs code-signing disabled for headless test runs):

```bash
xcodebuild test \
    -project PortyMcFolio.xcodeproj \
    -scheme PortyMcFolioTests \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
    2>&1 | grep -E '(Test Case|Executed|passed|failed|error:)' | tail -40
```

**Targeted single-test run** (use while developing a specific test):

```bash
xcodebuild test \
    -project PortyMcFolio.xcodeproj \
    -scheme PortyMcFolioTests \
    -destination 'platform=macOS' \
    -only-testing:PortyMcFolioTests/SearchControllerTests/testName \
    CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
    2>&1 | grep -E '(Test Case|Executed|passed|failed|error:)' | tail -20
```

**Build command:**

```bash
xcodebuild build \
    -project PortyMcFolio.xcodeproj \
    -scheme PortyMcFolio \
    -destination 'platform=macOS' \
    2>&1 | grep -E '(error:|BUILD)' | tail -5
```

**After creating any new `.swift` file, regenerate the Xcode project:**

```bash
cd <repo> && xcodegen generate
```

`xcodegen` is at `/opt/homebrew/bin/xcodegen`. Do **not** hand-edit the `.xcodeproj`. Per the project memory, if Xcode later reports "Entitlements file 'PortyMcFolio.entitlements' was modified during the build", that's a stale DerivedData symptom — fix is `⇧⌘K` in Xcode, not a project.yml refactor.

---

## File Structure

| Path | Action | Responsibility |
|------|--------|----------------|
| `PortyMcFolio/Services/SearchController.swift` | **create** (Task 1) | `@MainActor ObservableObject`. Owns debounce, off-main FTS call, snapshot publishing, error surfacing. No direct `SearchIndex` dependency — takes a `@Sendable (String) throws -> [SearchResult]` closure so it's fully unit-testable. |
| `PortyMcFolioTests/SearchControllerTests.swift` | **create** (Task 1) | Unit tests for debounce coalescing, stale-result discard, error surfacing, matchedUIDs ordering, empty-query clear, onMatchedUIDs callback. |
| `PortyMcFolio/App/AppState.swift` | **modify** (Task 2, 3, 5) | Construct/tear down `searchController` alongside `searchIndex`. Forward `searchQuery` changes into the controller via `didSet`. Rewrite `filteredProjects` to read the snapshot. Delete `populateFilesForLikelyMatches`. |
| `PortyMcFolio/Views/SearchPalette.swift` | **modify** (Task 4) | Use its own local `@StateObject SearchController` instead of synchronous `try? index.search(...)`. Remove duplicate populate call. Display `lastError` in footer. |
| `PortyMcFolioTests/AppStateFilteredProjectsTests.swift` | **create** (Task 6) | Regression coverage for the FTS-matched vs substring-fallback branch in `filteredProjects`. |

---

## Task 1: Create `SearchController` with TDD

**Files:**
- Create: `PortyMcFolio/Services/SearchController.swift`
- Test: `PortyMcFolioTests/SearchControllerTests.swift`

### Step 1a: Write failing tests

- [ ] **Step 1a.1: Create the test file.**

Create `PortyMcFolioTests/SearchControllerTests.swift`:

```swift
import XCTest
@testable import PortyMcFolio

@MainActor
final class SearchControllerTests: XCTestCase {

    // MARK: - Helpers

    /// A stub search provider that records every call and returns canned results.
    final class FakeIndex: @unchecked Sendable {
        var calls: [String] = []
        var handler: (String) throws -> [SearchResult] = { _ in [] }
        private let lock = NSLock()

        func search(_ q: String) throws -> [SearchResult] {
            lock.lock()
            calls.append(q)
            let h = handler
            lock.unlock()
            return try h(q)
        }
    }

    /// Wait until `condition()` returns true or `timeout` elapses.
    /// Polls on MainActor every 10ms so we don't need to hardcode waits.
    func waitUntil(
        timeout: TimeInterval = 1.0,
        _ condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        XCTFail("waitUntil timed out", file: file, line: line)
    }

    func makeResult(type: SearchResultType, entityID: String, parentUID: String = "") -> SearchResult {
        SearchResult(
            id: "\(type.rawValue)-\(parentUID)-\(entityID)",
            type: type,
            entityID: entityID,
            parentUID: parentUID,
            primaryText: entityID,
            secondaryText: ""
        )
    }

    // MARK: - Debounce

    func testDebounceCoalescesRapidSetQuery() async {
        let fake = FakeIndex()
        fake.handler = { [fake] q in [self.makeResult(type: .project, entityID: q)] }
        let controller = SearchController(
            search: { [fake] q in try fake.search(q) },
            debounceMs: 20
        )

        controller.setQuery("a")
        controller.setQuery("ab")
        controller.setQuery("abc")

        await waitUntil { controller.snapshot.query == "abc" }
        XCTAssertEqual(fake.calls, ["abc"])
    }

    // MARK: - Empty query

    func testEmptyQueryClearsImmediatelyWithoutCallingSearch() async {
        let fake = FakeIndex()
        fake.handler = { _ in [self.makeResult(type: .project, entityID: "x")] }
        let controller = SearchController(
            search: { [fake] q in try fake.search(q) },
            debounceMs: 20
        )

        // Prime with a non-empty query.
        controller.setQuery("foo")
        await waitUntil { controller.snapshot.query == "foo" }
        XCTAssertEqual(fake.calls, ["foo"])

        // Now clear. Expect immediate empty snapshot, no additional search call.
        controller.setQuery("")
        XCTAssertEqual(controller.snapshot.query, "")
        XCTAssertTrue(controller.snapshot.results.isEmpty)
        XCTAssertTrue(controller.snapshot.matchedUIDs.isEmpty)

        // Give it room to run an errant scheduled search; ensure none fired.
        try? await Task.sleep(nanoseconds: 60_000_000) // 60ms > debounce
        XCTAssertEqual(fake.calls, ["foo"])
    }

    // MARK: - Stale discard

    func testStaleResultsDiscarded() async {
        let fake = FakeIndex()
        // "a" is slow (100ms). "b" is fast.
        fake.handler = { [self] q in
            if q == "a" { Thread.sleep(forTimeInterval: 0.1) }
            return [self.makeResult(type: .project, entityID: q)]
        }
        let controller = SearchController(
            search: { [fake] q in try fake.search(q) },
            debounceMs: 10
        )

        controller.setQuery("a")
        try? await Task.sleep(nanoseconds: 30_000_000) // let debounce fire, search "a" starts
        controller.setQuery("b") // cancels debounce, schedules new run

        await waitUntil { controller.snapshot.query == "b" }
        XCTAssertEqual(controller.snapshot.query, "b")
        XCTAssertEqual(controller.snapshot.results.first?.entityID, "b")
    }

    // MARK: - Error surfacing

    func testErrorIsSurfacedViaLastError() async {
        struct FakeError: Error, Equatable {}
        let fake = FakeIndex()
        fake.handler = { _ in throw FakeError() }
        let controller = SearchController(
            search: { [fake] q in try fake.search(q) },
            debounceMs: 10
        )

        controller.setQuery("anything")
        await waitUntil { controller.lastError != nil }
        XCTAssertNotNil(controller.lastError)
        XCTAssertEqual(controller.snapshot.query, "anything")
        XCTAssertTrue(controller.snapshot.results.isEmpty)
    }

    func testErrorIsClearedBySuccessfulQuery() async {
        struct FakeError: Error {}
        let fake = FakeIndex()
        fake.handler = { _ in throw FakeError() }
        let controller = SearchController(
            search: { [fake] q in try fake.search(q) },
            debounceMs: 10
        )
        controller.setQuery("err")
        await waitUntil { controller.lastError != nil }

        fake.handler = { [self] q in [self.makeResult(type: .project, entityID: q)] }
        controller.setQuery("ok")
        await waitUntil { controller.snapshot.query == "ok" }
        XCTAssertNil(controller.lastError)
    }

    // MARK: - matchedUIDs ordering

    func testMatchedUIDsPreservesFTSRankOrderAndDedupes() async {
        let fake = FakeIndex()
        fake.handler = { [self] _ in
            [
                self.makeResult(type: .project, entityID: "A"),
                self.makeResult(type: .file, entityID: "x.md", parentUID: "A"),   // dup uid A
                self.makeResult(type: .project, entityID: "B"),
                self.makeResult(type: .link, entityID: "lnk1", parentUID: "C"),
                self.makeResult(type: .tag, entityID: "branding"),                // ignored (no uid)
            ]
        }
        let controller = SearchController(
            search: { [fake] q in try fake.search(q) },
            debounceMs: 10
        )
        controller.setQuery("q")
        await waitUntil { !controller.snapshot.matchedUIDs.isEmpty }
        XCTAssertEqual(controller.snapshot.matchedUIDs, ["A", "B", "C"])
    }

    // MARK: - onMatchedUIDs callback

    func testOnMatchedUIDsFiresAfterSnapshotPublishes() async {
        let fake = FakeIndex()
        fake.handler = { [self] _ in [self.makeResult(type: .project, entityID: "A")] }

        var received: [[String]] = []
        let controller = SearchController(
            search: { [fake] q in try fake.search(q) },
            onMatchedUIDs: { uids in received.append(uids) },
            debounceMs: 10
        )
        controller.setQuery("q")
        await waitUntil { !received.isEmpty }
        XCTAssertEqual(received, [["A"]])
    }

    func testOnMatchedUIDsReceivesEmptyArrayOnError() async {
        struct FakeError: Error {}
        let fake = FakeIndex()
        fake.handler = { _ in throw FakeError() }

        var received: [[String]] = []
        let controller = SearchController(
            search: { [fake] q in try fake.search(q) },
            onMatchedUIDs: { uids in received.append(uids) },
            debounceMs: 10
        )
        controller.setQuery("q")
        await waitUntil { !received.isEmpty }
        XCTAssertEqual(received, [[]])
    }

    // MARK: - rebind

    func testRebindSwapsSearchAndCallback() async {
        let fakeA = FakeIndex()
        fakeA.handler = { [self] _ in [self.makeResult(type: .project, entityID: "A")] }
        let fakeB = FakeIndex()
        fakeB.handler = { [self] _ in [self.makeResult(type: .project, entityID: "B")] }

        var received: [[String]] = []
        let controller = SearchController(
            search: { [fakeA] q in try fakeA.search(q) },
            onMatchedUIDs: { _ in received.append(["via-A"]) },
            debounceMs: 10
        )
        controller.setQuery("q")
        await waitUntil { controller.snapshot.results.first?.entityID == "A" }

        controller.rebind(
            search: { [fakeB] q in try fakeB.search(q) },
            onMatchedUIDs: { uids in received.append(uids) }
        )
        controller.setQuery("q2")
        await waitUntil { controller.snapshot.results.first?.entityID == "B" }
        XCTAssertEqual(received.last, ["B"])
    }

    func testRebindDiscardsMidFlightDetachedSearch() async {
        // Mid-flight simulation: the first search for "slow" takes 80ms.
        // We rebind to a new search function during that window and verify
        // the old search's result does NOT clobber the post-rebind snapshot.
        let fakeSlow = FakeIndex()
        fakeSlow.handler = { [self] q in
            Thread.sleep(forTimeInterval: 0.08)
            return [self.makeResult(type: .project, entityID: "from-slow")]
        }
        let fakeFast = FakeIndex()
        fakeFast.handler = { [self] q in
            [self.makeResult(type: .project, entityID: "from-fast")]
        }
        let controller = SearchController(
            search: { [fakeSlow] q in try fakeSlow.search(q) },
            debounceMs: 10
        )
        controller.setQuery("slow")
        // Wait long enough for debounce to fire and slow search to START
        // but not long enough for it to complete.
        try? await Task.sleep(nanoseconds: 30_000_000)
        controller.rebind(
            search: { [fakeFast] q in try fakeFast.search(q) }
        )
        controller.setQuery("fast")
        await waitUntil { controller.snapshot.results.first?.entityID == "from-fast" }
        // Wait a further 100ms so the slow search definitely completes.
        try? await Task.sleep(nanoseconds: 100_000_000)
        // Snapshot must still be the fast result; slow's outcome was discarded.
        XCTAssertEqual(controller.snapshot.results.first?.entityID, "from-fast")
    }

    // MARK: - cancelAll

    func testCancelAllClearsStateAndDiscardsInFlight() async {
        let fakeSlow = FakeIndex()
        fakeSlow.handler = { [self] q in
            Thread.sleep(forTimeInterval: 0.08)
            return [self.makeResult(type: .project, entityID: q)]
        }
        let controller = SearchController(
            search: { [fakeSlow] q in try fakeSlow.search(q) },
            debounceMs: 10
        )
        controller.setQuery("abc")
        try? await Task.sleep(nanoseconds: 30_000_000)  // slow search in flight

        controller.cancelAll()
        XCTAssertEqual(controller.snapshot.query, "")
        XCTAssertTrue(controller.snapshot.results.isEmpty)
        XCTAssertNil(controller.lastError)

        // Wait for the in-flight slow search to finish; it must NOT repopulate snapshot.
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(controller.snapshot.query, "")
        XCTAssertTrue(controller.snapshot.results.isEmpty)
    }
}
```

- [ ] **Step 1a.2: Run the tests to verify they fail (type doesn't exist yet).**

Run:

```bash
xcodebuild test \
    -project PortyMcFolio.xcodeproj \
    -scheme PortyMcFolioTests \
    -destination 'platform=macOS' \
    -only-testing:PortyMcFolioTests/SearchControllerTests \
    CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
    2>&1 | tail -30
```

Expected: compile error `cannot find 'SearchController' in scope`.

### Step 1b: Implement `SearchController`

- [ ] **Step 1b.1: Create the class file.**

Create `PortyMcFolio/Services/SearchController.swift`:

```swift
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
```

- [ ] **Step 1b.2: Regenerate the Xcode project so it picks up the new file.**

Run:

```bash
cd <repo> && /opt/homebrew/bin/xcodegen generate
```

Expected: `Loaded project: ...` then `Created project at ...PortyMcFolio.xcodeproj`.

- [ ] **Step 1b.3: Run tests — they should all pass.**

Run:

```bash
xcodebuild test \
    -project PortyMcFolio.xcodeproj \
    -scheme PortyMcFolioTests \
    -destination 'platform=macOS' \
    -only-testing:PortyMcFolioTests/SearchControllerTests \
    CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
    2>&1 | grep -E '(Test Case|Executed|passed|failed|error:)' | tail -20
```

Expected: all 10 tests pass. Sample output:

```
Test Case '-[PortyMcFolioTests.SearchControllerTests testDebounceCoalescesRapidSetQuery]' passed
...
Executed 10 tests, with 0 failures
```

- [ ] **Step 1b.4: Commit.**

```bash
git add PortyMcFolio/Services/SearchController.swift PortyMcFolioTests/SearchControllerTests.swift PortyMcFolio.xcodeproj
git commit -m "feat: SearchController with debounced off-main FTS + error surfacing

Central owner of the search pipeline. Consumers inject a search closure so
the class is fully unit-testable without a real SearchIndex. Debounce is
instance-configurable so tests can run with a 10-20ms window."
```

---

## Task 2: Own a `SearchController` on `AppState`; forward `searchQuery`

No behavior change yet — `filteredProjects` still uses its computed path. This task just wires the plumbing so Task 3 can flip the switch atomically.

**Files:**
- Modify: `PortyMcFolio/App/AppState.swift`

- [ ] **Step 2.1: Add a `searchController` property.**

In `AppState.swift`, just after the existing `private(set) var reconciler: ProjectReconciler?` line (currently at line 83), add:

```swift
    /// Debounced, off-main search pipeline. Constructed in `setRoot` once the
    /// search index exists; nil before then or after portfolio teardown.
    private(set) var searchController: SearchController?
```

- [ ] **Step 2.2: Forward `searchQuery` changes to the controller.**

Locate the existing `@Published var searchQuery: String = ""` declaration (currently line 23) and add a `didSet`:

```swift
    @Published var searchQuery: String = "" {
        didSet {
            searchController?.setQuery(searchQuery)
        }
    }
```

- [ ] **Step 2.3: Construct the controller in `setRoot`.**

In `setRoot(_ url: URL)`, after the `self.reconciler = recon` assignment (currently around line 273) and **before** `recon.startInitialReconciliation()`, insert:

```swift
            // Build the search controller now that index + reconciler exist.
            //
            // `index` is weak-captured (not `self`) because the `search`
            // closure is `@Sendable` and runs off-MainActor via Task.detached.
            // Capturing `[weak self]` and reading `self.searchIndex` would
            // violate MainActor isolation from the Sendable closure.
            // Weak-capturing the local `index` binding is semantically
            // equivalent: when setRoot tears down (self.searchIndex = nil
            // releases the last strong ref), the weak `index` becomes nil
            // and the closure returns []. Prevents the in-flight search
            // from pinning the OLD `SearchIndex` alive and racing with the
            // new one on the shared `search.sqlite` file (SQLITE_BUSY
            // hazard).
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
            // If the user was mid-query at portfolio-switch time, replay it.
            if !self.searchQuery.isEmpty {
                self.searchController?.setQuery(self.searchQuery)
            }
```

- [ ] **Step 2.4: Tear down the controller in `setRoot`'s teardown block.**

In the teardown block near the top of `setRoot`, after the existing `reconciler = nil` (line 221), add the two lines marked below. `cancelAll()` must run **before** the `searchIndex = nil` assignment so that any in-flight detached search has its result silently discarded rather than arriving on MainActor after the old index has been released but before the new one is constructed.

```swift
        fileWatcher?.stop()
        fileWatcher = nil
        reconciler?.shutdown()
        reconciler = nil
        searchController?.cancelAll()  // ← ADD: stop/discard in-flight work
        searchController = nil         // ← ADD
        searchIndex = nil
        cache = nil
```

- [ ] **Step 2.5: Build and verify.**

Run:

```bash
xcodebuild build \
    -project PortyMcFolio.xcodeproj \
    -scheme PortyMcFolio \
    -destination 'platform=macOS' \
    2>&1 | grep -E '(error:|BUILD)' | tail -5
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 2.6: Run the full test suite — nothing should regress.**

```bash
xcodebuild test \
    -project PortyMcFolio.xcodeproj \
    -scheme PortyMcFolioTests \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
    2>&1 | grep -E '(Executed|failed|error:)' | tail -5
```

Expected: all existing tests pass, zero failures.

- [ ] **Step 2.7: Commit.**

```bash
git add PortyMcFolio/App/AppState.swift
git commit -m "refactor: wire SearchController into AppState (no behavior change yet)

AppState now constructs a SearchController alongside SearchIndex and
forwards searchQuery changes to it. filteredProjects still uses the old
computed path; the next commit switches it over."
```

---

## Task 3: Rewrite `filteredProjects` to consume the snapshot

This is the behavior change: `filteredProjects` stops running FTS itself and reads from `searchController.snapshot`. Fallback substring behavior is preserved.

**Files:**
- Modify: `PortyMcFolio/App/AppState.swift`

- [ ] **Step 3.1: Replace the `filteredProjects` computed property.**

Find the current body (lines 94-126):

```swift
    /// Projects visible in the current view, filtered by search query and hidden toggle.
    var filteredProjects: [Project] {
        let base = hideHiddenProjects ? projects.filter { !$0.hidden } : projects

        guard !searchQuery.isEmpty else {
            return base
        }

        // Try FTS search first — includes files, links, tags so we can surface their parent projects
        if let index = searchIndex,
           let results = try? index.search(query: searchQuery), !results.isEmpty {
            var matchingUIDs = Set<String>()
            for result in results {
                if result.type == .project {
                    matchingUIDs.insert(result.entityID)
                } else if !result.parentUID.isEmpty {
                    matchingUIDs.insert(result.parentUID)
                }
            }
            let matched = base.filter { matchingUIDs.contains($0.uid) }
            if !matched.isEmpty { return matched }
        }

        // Fallback: substring on metadata (no longer searches filePaths — lazy)
        let q = searchQuery.lowercased()
        return base.filter { project in
            project.title.lowercased().contains(q) ||
            project.client.lowercased().contains(q) ||
            project.tags.contains { $0.lowercased().contains(q) } ||
            project.folderName.lowercased().contains(q) ||
            project.status.displayName.lowercased().contains(q)
        }
    }
```

Replace with:

```swift
    /// Projects visible in the current view, filtered by search query and hidden toggle.
    ///
    /// Uses the most recent FTS snapshot from `searchController` when it matches
    /// the active query. Otherwise (snapshot stale, empty, or FTS failed) falls
    /// back to case-insensitive substring matching on project metadata.
    var filteredProjects: [Project] {
        let base = hideHiddenProjects ? projects.filter { !$0.hidden } : projects

        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return base }

        // FTS path: only trust the snapshot if it reflects the current query.
        if let snapshot = searchController?.snapshot,
           snapshot.query == trimmed,
           !snapshot.matchedUIDs.isEmpty {
            let matchedSet = Set(snapshot.matchedUIDs)
            let matched = base.filter { matchedSet.contains($0.uid) }
            if !matched.isEmpty { return matched }
        }

        // Substring fallback: used when the snapshot hasn't caught up, when FTS
        // returned empty, or when the index is unavailable (pre-setRoot,
        // post-teardown, or an init failure).
        let q = trimmed.lowercased()
        return base.filter { project in
            project.title.lowercased().contains(q) ||
            project.client.lowercased().contains(q) ||
            project.tags.contains { $0.lowercased().contains(q) } ||
            project.folderName.lowercased().contains(q) ||
            project.status.displayName.lowercased().contains(q)
        }
    }
```

Key differences:
- No direct `index.search(...)` call.
- Snapshot is only used when `snapshot.query == trimmed` (so mid-debounce keystrokes fall through to fallback, which is desirable — substring match keeps the list responsive during the 120 ms debounce window).
- `trimmed` is computed once.

- [ ] **Step 3.2: Add `import Combine` to the top of `AppState.swift`.**

The next step introduces a Combine sink. Add it on its own line right after `import SwiftUI`:

```swift
import Foundation
import SwiftUI
import Combine
```

This is the first use of Combine in the codebase (verified by grep — see "Grep: Combine|cancellables|sink" returned no hits pre-plan). Keep Combine confined to this single sink; don't cascade its use into other AppState code.

- [ ] **Step 3.3: Make `filteredProjects` re-evaluate when the snapshot updates.**

`filteredProjects` is a computed property, so SwiftUI recomputes it when any `@Published` it touches changes. It currently touches `projects`, `hideHiddenProjects`, and `searchQuery`. After this change it ALSO touches `searchController?.snapshot`, but `searchController` itself is a plain `var` (not `@Published`) and nested ObservableObjects do not automatically propagate change notifications.

Fix: have `AppState` observe the controller and re-publish via its own `objectWillChange`.

Add near the top of `AppState` (just after the existing private properties, e.g. after `private var accessedURL: URL?` on line 92):

```swift
    /// Cancellables for downstream ObservableObject forwarding.
    private var controllerObserver: AnyCancellable?
```

In `setRoot`, immediately after `self.searchController = SearchController(...)` (Step 2.3), add:

```swift
            // Forward controller changes so SwiftUI views observing AppState
            // re-render when the snapshot updates.
            controllerObserver = self.searchController?.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
```

And in the teardown block (Step 2.4), just before `searchController = nil`, add:

```swift
        controllerObserver?.cancel()
        controllerObserver = nil
```

- [ ] **Step 3.4: Build and run full tests.**

```bash
xcodebuild build \
    -project PortyMcFolio.xcodeproj \
    -scheme PortyMcFolio \
    -destination 'platform=macOS' \
    2>&1 | grep -E '(error:|BUILD)' | tail -5
```

Expected: `BUILD SUCCEEDED`.

```bash
xcodebuild test \
    -project PortyMcFolio.xcodeproj \
    -scheme PortyMcFolioTests \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
    2>&1 | grep -E '(Executed|failed|error:)' | tail -5
```

Expected: all tests pass. No existing test should break — `filteredProjects` is used implicitly by ProjectListView which has no direct tests.

- [ ] **Step 3.5: Commit.**

```bash
git add PortyMcFolio/App/AppState.swift
git commit -m "perf: filteredProjects reads SearchController snapshot instead of running FTS

filteredProjects no longer calls index.search on every SwiftUI render.
During the 120ms debounce window, it falls back to case-insensitive
substring matching on metadata — same code path as before when FTS
returns empty. Net effect: up to ~30 synchronous main-thread FTS reads
per second eliminated for fast typers."
```

---

## Task 4: Rewrite `SearchPalette` to consume a local `SearchController`

**Files:**
- Modify: `PortyMcFolio/Views/SearchPalette.swift`

The palette currently holds `@State private var query = ""` and recomputes `GroupedResults` synchronously on every keystroke, calling both `index.search(...)` and `populateFilesForLikelyMatches` (which internally calls `index.search(...)` again). After this task, the palette owns a local `@StateObject SearchController`, pipes the query to it, and builds `GroupedResults` from the published snapshot. Commands and tag-count aggregation still happen locally because they're cheap.

- [ ] **Step 4.1: Replace the state declarations at the top of `SearchPalette`.**

Find the existing state (lines 6-9):

```swift
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var grouped = GroupedResults()
    @FocusState private var isFieldFocused: Bool
```

Replace with:

```swift
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var selectedIndex = 0
    @StateObject private var controller = SearchController(
        search: { _ in [] },  // Replaced in .onAppear once appState.searchIndex is known.
        debounceMs: 120
    )
    @FocusState private var isFieldFocused: Bool
```

- [ ] **Step 4.2: Remove the now-unused private helpers `matchFiles`, `matchLinks`, and the FTS-calling block inside `computeGrouped`.**

Locate `computeGrouped()` (lines 47-111). Replace the body with a version that reads the controller's snapshot:

```swift
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
```

Delete `matchFiles(_:excluding:)` (lines 147-151) and `matchLinks(_:excluding:)` (lines 153-157) — they returned `[]` and are no longer referenced.

Keep `matchProjects(_:excluding:)` (lines 122-145) and `matchTags(_:)` (lines 159-181) as-is.

- [ ] **Step 4.3: Replace the body's `.onChange(of: query)` block.**

Find (lines 283-288):

```swift
        .onChange(of: query) { _, newValue in
            grouped = computeGrouped()
            selectedIndex = 0
            // Trigger lazy file/link population so file/link results surface.
            appState.populateFilesForLikelyMatches(query: newValue)
        }
```

Replace with:

```swift
        .onChange(of: query) { _, newValue in
            controller.setQuery(newValue)
            selectedIndex = 0
        }
```

No explicit `.onChange(of: controller.snapshot)` is needed: the body reads
`controller.snapshot` via `computeGrouped()`, and because `controller` is an
`@StateObject`, SwiftUI re-renders the body when snapshot changes.

- [ ] **Step 4.4: Remove the stale `grouped` state and replace uses with a computed derivation.**

In the body (line 186), find:

```swift
        let flat = grouped.flatItems
```

And the `ForEach(Array(flat.enumerated())...)` block uses `grouped` indirectly via `flat`. Replace the line with:

```swift
        let grouped = computeGrouped()
        let flat = grouped.flatItems
```

At the top of the file, delete the `@State private var grouped = GroupedResults()` (it was already replaced in Step 4.1 — verify it's gone).

Also find and delete the `.onAppear` line that sets `grouped`:

```swift
        .onAppear {
            isFieldFocused = true
            grouped = computeGrouped()
        }
```

Replace with:

```swift
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
```

- [ ] **Step 4.5: Build and run all tests.**

```bash
xcodebuild build \
    -project PortyMcFolio.xcodeproj \
    -scheme PortyMcFolio \
    -destination 'platform=macOS' \
    2>&1 | grep -E '(error:|BUILD)' | tail -5
```

Expected: `BUILD SUCCEEDED`.

```bash
xcodebuild test \
    -project PortyMcFolio.xcodeproj \
    -scheme PortyMcFolioTests \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
    2>&1 | grep -E '(Executed|failed|error:)' | tail -5
```

Expected: all tests pass.

- [ ] **Step 4.6: Commit.**

```bash
git add PortyMcFolio/Views/SearchPalette.swift
git commit -m "perf: SearchPalette consumes SearchController snapshot

Palette no longer calls try? index.search(...) synchronously on every
keystroke. It owns a local @StateObject SearchController, pipes query
into it, and renders from the published snapshot. Lazy file population
is driven by the controller's onMatchedUIDs callback using the same
result set — so palette-side FTS work drops from two calls per keystroke
(one in computeGrouped + one in populateFilesForLikelyMatches) to one,
and that one is debounced and off-main."
```

---

## Task 5: Delete `AppState.populateFilesForLikelyMatches` (now dead)

**Files:**
- Modify: `PortyMcFolio/App/AppState.swift`

After Task 4, no caller remains. Delete the method to keep AppState tight.

- [ ] **Step 5.1: Confirm no callers exist.**

```bash
cd <repo>
```

Then use Grep tool (via the assistant's tools, not shell):

Search pattern: `populateFilesForLikelyMatches`

Expected: only the definition in `AppState.swift` remains after Task 4. If any call site is found, investigate before deleting.

- [ ] **Step 5.2: Delete the method.**

In `AppState.swift`, find (lines 402-423):

```swift
    /// Populate file/link FTS rows for the top metadata-matched projects.
    /// Called by SearchPalette as the user types so file/link results become available.
    func populateFilesForLikelyMatches(query: String) {
        guard let recon = reconciler, let index = searchIndex else { return }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= ProjectReconciler.lazyPopulateMinQueryLength else { return }
        guard let results = try? index.search(query: trimmed), !results.isEmpty else { return }

        // Take the top N project uids that appear in matches (either project hits or via parent_uid)
        var seen: [String] = []
        for r in results {
            let uid: String
            if r.type == .project { uid = r.entityID }
            else if !r.parentUID.isEmpty { uid = r.parentUID }
            else { continue }
            if !seen.contains(uid) { seen.append(uid) }
            if seen.count >= ProjectReconciler.lazyPopulateFanout { break }
        }
        for uid in seen {
            recon.populateFiles(uid: uid)
        }
    }
```

Delete the entire method (including its doc comment).

**Note on `lazyPopulateMinQueryLength`:** the old method skipped work for queries shorter than 2 characters. The new controller-driven path does **not** apply that guard — every non-empty query fires FTS after debounce. This is intentional: SQLite FTS5 on `a*` is still fast (≤ few ms), and the debounce (120 ms) + off-main execution make single-char queries cheap. If profiling shows single-char queries cost real time on large portfolios, add the guard inside `SearchController.runSearch` as a follow-up.

- [ ] **Step 5.3: Build and test.**

```bash
xcodebuild build \
    -project PortyMcFolio.xcodeproj \
    -scheme PortyMcFolio \
    -destination 'platform=macOS' \
    2>&1 | grep -E '(error:|BUILD)' | tail -5
```

Expected: `BUILD SUCCEEDED`.

```bash
xcodebuild test \
    -project PortyMcFolio.xcodeproj \
    -scheme PortyMcFolioTests \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
    2>&1 | grep -E '(Executed|failed|error:)' | tail -5
```

Expected: all tests pass.

- [ ] **Step 5.4: Commit.**

```bash
git add PortyMcFolio/App/AppState.swift
git commit -m "chore: delete AppState.populateFilesForLikelyMatches (now dead)

SearchController.onMatchedUIDs handles lazy file population after
Task 4. The method had one caller, which no longer exists."
```

---

## Task 6: Add regression test for `filteredProjects` fallback branch + surface `lastError` in palette footer

Two small wins bundled: the reliability item (test the FTS-or-fallback switch) and the error-surfacing item.

**Files:**
- Create: `PortyMcFolioTests/AppStateFilteredProjectsTests.swift`
- Modify: `PortyMcFolio/Views/SearchPalette.swift`

- [ ] **Step 6.1: Write the fallback-branch test.**

Create `PortyMcFolioTests/AppStateFilteredProjectsTests.swift`:

```swift
import XCTest
@testable import PortyMcFolio

@MainActor
final class AppStateFilteredProjectsTests: XCTestCase {

    /// Project helper — no disk. Uses defaulted params for rarely-varied fields
    /// (hidden, filePaths, frontmatterMTime) so tests that exercise them can
    /// set only the field they care about.
    func makeProject(
        uid: String,
        title: String,
        year: Int = 2025,
        client: String = "",
        tags: [String] = [],
        hidden: Bool = false
    ) -> Project {
        Project(
            uid: uid,
            year: year,
            folderName: "\(year)_\(title.lowercased().replacingOccurrences(of: " ", with: "-"))_\(uid)",
            folderURL: URL(fileURLWithPath: "/tmp/fake-\(uid)"),
            title: title,
            date: Date(timeIntervalSince1970: 0),
            tags: tags,
            client: client,
            status: .empty,
            body: "",
            teaser: "",
            hidden: hidden
        )
    }

    // MARK: - Empty query

    func testEmptyQueryReturnsAllProjects() {
        let state = AppState()
        state.projects = [
            makeProject(uid: "11111111", title: "Alpha"),
            makeProject(uid: "22222222", title: "Beta"),
        ]
        state.searchQuery = ""
        XCTAssertEqual(state.filteredProjects.map(\.uid), ["11111111", "22222222"])
    }

    // MARK: - Substring fallback (searchController is nil)

    func testFallbackMatchesByTitle() {
        let state = AppState()
        state.projects = [
            makeProject(uid: "11111111", title: "Brand Identity"),
            makeProject(uid: "22222222", title: "Packaging"),
        ]
        state.searchQuery = "brand"
        // No searchController in a unit-init AppState → substring fallback.
        XCTAssertEqual(state.filteredProjects.map(\.uid), ["11111111"])
    }

    func testFallbackMatchesByClient() {
        let state = AppState()
        state.projects = [
            makeProject(uid: "11111111", title: "Project", client: "Acme Corp"),
            makeProject(uid: "22222222", title: "Project", client: "Globex"),
        ]
        state.searchQuery = "acme"
        XCTAssertEqual(state.filteredProjects.map(\.uid), ["11111111"])
    }

    func testFallbackMatchesByTag() {
        let state = AppState()
        state.projects = [
            makeProject(uid: "11111111", title: "A", tags: ["branding"]),
            makeProject(uid: "22222222", title: "B", tags: ["ui"]),
        ]
        state.searchQuery = "brand"
        XCTAssertEqual(state.filteredProjects.map(\.uid), ["11111111"])
    }

    func testFallbackMatchesByFolderName() {
        let state = AppState()
        state.projects = [
            makeProject(uid: "11111111", title: "Alpha"),
        ]
        // folderName is derived in makeProject as "2025_alpha_11111111"
        state.searchQuery = "11111111"
        XCTAssertEqual(state.filteredProjects.map(\.uid), ["11111111"])
    }

    // MARK: - Hidden filter

    func testHiddenProjectsExcludedWhenToggleOn() {
        let state = AppState()
        state.projects = [
            makeProject(uid: "11111111", title: "Hidden Brand", hidden: true),
            makeProject(uid: "22222222", title: "Visible Brand"),
        ]
        state.hideHiddenProjects = true
        state.searchQuery = "brand"
        XCTAssertEqual(state.filteredProjects.map(\.uid), ["22222222"])
    }

    func testHiddenProjectsIncludedWhenToggleOff() {
        let state = AppState()
        state.projects = [
            makeProject(uid: "11111111", title: "Hidden Brand", hidden: true),
            makeProject(uid: "22222222", title: "Visible Brand"),
        ]
        state.hideHiddenProjects = false
        state.searchQuery = "brand"
        XCTAssertEqual(Set(state.filteredProjects.map(\.uid)), Set(["11111111", "22222222"]))
    }

    // MARK: - Whitespace trimming

    func testQueryWithOnlyWhitespaceReturnsAllProjects() {
        let state = AppState()
        state.projects = [
            makeProject(uid: "11111111", title: "Alpha"),
            makeProject(uid: "22222222", title: "Beta"),
        ]
        state.searchQuery = "   "
        XCTAssertEqual(state.filteredProjects.count, 2)
    }
}
```

Note: these tests do **not** exercise the FTS-hit branch — that requires a live `SearchIndex` and `SearchController`, which would be an integration test. They lock down the fallback, empty-query, whitespace-trim, and hidden-filter paths. The FTS-hit branch is exercised implicitly by `SearchControllerTests` (which proves the snapshot flows) plus manual verification in the next section.

`Project`'s synthesized memberwise init accepts `hidden: Bool = false`, `filePaths: [String] = []`, and `frontmatterMTime: Date? = nil` as defaulted params (see `PortyMcFolio/Models/Project.swift:26-32`), so the helper above compiles as written.

- [ ] **Step 6.2: Add `lastError` display to the palette footer.**

In `SearchPalette.swift`, find the footer hint bar (lines 261-269):

```swift
            HStack(spacing: DT.Spacing.lg) {
                shortcutHint("↑↓", label: "navigate")
                shortcutHint("↵", label: "open")
                shortcutHint("esc", label: "close")
            }
            .padding(.horizontal, DT.Spacing.lg)
            .padding(.vertical, DT.Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(DT.Colors.surfaceHover.opacity(0.6))
```

Wrap with a conditional error banner above:

```swift
            if let err = controller.lastError {
                HStack(spacing: DT.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange)
                    Text("Search error: \(err.localizedDescription)")
                        .font(DT.Typography.caption)
                        .foregroundStyle(DT.Colors.textSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, DT.Spacing.lg)
                .padding(.vertical, DT.Spacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
            }

            HStack(spacing: DT.Spacing.lg) {
                shortcutHint("↑↓", label: "navigate")
                shortcutHint("↵", label: "open")
                shortcutHint("esc", label: "close")
            }
            .padding(.horizontal, DT.Spacing.lg)
            .padding(.vertical, DT.Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(DT.Colors.surfaceHover.opacity(0.6))
```

- [ ] **Step 6.3: Build and run all tests.**

```bash
xcodebuild build \
    -project PortyMcFolio.xcodeproj \
    -scheme PortyMcFolio \
    -destination 'platform=macOS' \
    2>&1 | grep -E '(error:|BUILD)' | tail -5
```

Expected: `BUILD SUCCEEDED`.

```bash
xcodebuild test \
    -project PortyMcFolio.xcodeproj \
    -scheme PortyMcFolioTests \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
    2>&1 | grep -E '(Executed|failed|error:)' | tail -5
```

Expected: all tests pass.

- [ ] **Step 6.4: Commit.**

```bash
git add PortyMcFolioTests/AppStateFilteredProjectsTests.swift PortyMcFolio/Views/SearchPalette.swift PortyMcFolio.xcodeproj
git commit -m "feat+test: surface FTS errors in palette footer; lock down filteredProjects fallback

Orange warning banner appears above the palette's shortcut hints when the
SearchController reports lastError. Adds AppStateFilteredProjectsTests
covering the substring-fallback branch (empty query, title/client/tag/
folderName match, hidden filter, whitespace trim) — the branch that was
previously untested and shipped in the f12c102 'deferred review' batch
without regression coverage."
```

---

## Manual verification checklist

Before considering this plan complete, the executor should manually drive the app. `xcodebuild test` alone does not verify the perf/UX gains; an integration test would be expensive to write, and eyeballing is faster.

1. **Launch the app** on a real portfolio root (ideally 50+ projects).
2. **Cmd+K** to open the palette.
3. **Type a multi-char query rapidly** (e.g. "brand"). Observe:
   - No visible stutter in the TextField as characters appear.
   - Results populate after a short (~120 ms) pause on the last keystroke.
   - During the pause, the list shows results from the previous keystroke (not flashing empty).
4. **Type a query that matches only via file name** (e.g. part of a filename in a known project). Wait ~1 s after typing. Observe: file result appears once `populateFiles` completes.
5. **Type a query with no matches.** Observe: "No results for ..." footer appears.
6. **Close the palette (esc), open the main list's search field**, type the same query. Observe: `filteredProjects` filters without blocking keystrokes.
7. **Switch portfolio root** via the folder picker. Open palette, type a query, confirm results from the *new* root only (no cross-portfolio bleed).
8. **Force an error:** the simplest way is to delete `~/Library/Application Support/PortyMcFolio/search.sqlite` while the app is running, then type in the palette. The orange error banner should appear at the footer.
9. **Re-index command:** in the palette, type "re", select "Re-index portfolio", press Enter. Observe: palette closes, reconciler runs (check console logs), typing a query afterward still works.
10. **Check thread hygiene with Instruments** (optional but valuable): attach Instruments' "Time Profiler" and the "Main Thread Checker". Type rapidly in the palette. Confirm `SearchIndex.search` frames appear on a non-main thread.

---

## Future work (deferred)

These findings from the review are intentionally not addressed in this plan; each deserves its own plan:

- **BM25 column weighting** — swap `ORDER BY rank` for `ORDER BY bm25(search_fts, 0, 0, 0, 10, 5, 1)` style to weight title > secondary > body.
- **Per-type result limits** — split the `LIMIT 30` into per-type caps so e.g. 30 file matches don't starve projects.
- **Typo / substring fallback** — trigram distance against `project_meta` for queries that return empty FTS.
- **Non-incremental `rebuildTags`** — currently recomputes all tag rows for any project change; incrementalize.
- **In-place schema migration** — version bumps currently wipe both `search_fts` and `project_meta`; large portfolios cold-rescan after every update.
- **Hidden filter in SQL** — move `hidden` into an indexed column on `project_meta` and JOIN at search time instead of filtering post-hoc in Swift.
- **Periodic FTS optimize** — `INSERT INTO search_fts(search_fts) VALUES('optimize')` on a cadence.
- **`parent_uid` sidecar table** — virtual tables can't index `UNINDEXED` columns, so project-level deletes are full scans; a regular sidecar table fixes this.

---

## Self-review notes (author)

Run during plan-writing:

- **Spec coverage:** All five findings from the "perf consolidation" scope are addressed — debounce (Task 1), off-main (Task 1), dedupe of three FTS sites (Tasks 3 + 4 + 5), error surfacing (Task 6), fallback-branch test (Task 6).
- **Placeholder scan:** No TODOs, no "similar to Task N", all code blocks are complete.
- **Type consistency:** `SearchController.Snapshot` has `query`, `results`, `matchedUIDs: [String]` — same across Tasks 1, 3, 4. `rebind` introduced in Task 1 alongside `searchRef`/`onMatchedUIDsRef` so Task 4 can call it without renames.
- **Out-of-scope items** are explicitly enumerated in the "Future work" section so they don't get silently forgotten.

## Code-review notes (second pass, 2026-04-20)

After initial draft, the plan went through `superpowers:code-reviewer`. Findings applied:

- **Portfolio-switch DatabaseQueue race (blocker):** Added `SearchController.cancelAll()` (Task 1) and call site in `setRoot` teardown (Task 2.4). `AppState`'s controller now weak-captures `self` in its `search` closure so an in-flight FTS call doesn't pin the old `SearchIndex` alive during switch.
- **Duplicate populate work across two controllers (concern):** `AppState`'s controller no longer sets `onMatchedUIDs` (Task 2.3). The palette's local controller is the single source of lazy file population. Eliminates the "populate called twice for the same UID" waste the reviewer called out.
- **`lastError` persistence across palette open/close (concern):** Palette's `.onAppear` now calls `controller.cancelAll()` first thing (Task 4 step 4.4), clearing any stale error from a prior session before rebinding.
- **`import Combine` visibility (concern):** Promoted to its own step (Task 3 Step 3.2) so executors can't miss it.
- **Mid-flight `rebind` test (concern):** Added `testRebindDiscardsMidFlightDetachedSearch` and `testCancelAllClearsStateAndDiscardsInFlight` in Task 1.
- **Snapshot-lag flicker on `filteredProjects` (concern):** Acknowledged as an accepted trade-off in the new "Known trade-offs" section; manual verification step 3 watches for it.
- **Line-number drift across tasks (nit):** Added "A note on line numbers in this plan" near the top instructing the executor to Grep-re-anchor when cited numbers don't match.

Deferred nits (N1 fix is directional, not per-citation; N2 is false alarm; N3 and N5 are taste-level).
