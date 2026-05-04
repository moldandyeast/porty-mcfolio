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
