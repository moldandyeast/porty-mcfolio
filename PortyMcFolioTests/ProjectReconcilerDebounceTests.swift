import XCTest
import GRDB
@testable import PortyMcFolio

final class ProjectReconcilerDebounceTests: XCTestCase {
    var tempRoot: URL!
    var db: DatabaseQueue!
    var cache: ProjectMetadataCache!
    var index: SearchIndex!
    var reconciler: ProjectReconciler!
    var passCount = 0

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectReconcilerDebounceTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        index = try! SearchIndex(inMemory: true)
        db = index.databaseQueueForReconciler()
        cache = try! ProjectMetadataCache(db: db)
        passCount = 0
        reconciler = ProjectReconciler(
            portfolioRoot: tempRoot,
            db: db, cache: cache, searchIndex: index,
            publish: { _ in }
        )
        reconciler.testHookOnReconciliationPass = { [weak self] in self?.passCount += 1 }
    }

    override func tearDown() {
        reconciler.shutdown()
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    /// Synchronously wait until passCount reaches `target` or `timeout` elapses.
    /// Polls every 25ms.
    private func waitForPasses(_ target: Int, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while passCount < target && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.025))
        }
    }

    /// Wait up to `window` seconds and verify `passCount` does NOT exceed `expected`.
    /// Used to prove coalescing worked — a runaway pass would arrive within one
    /// debounce-window after the first one fires.
    private func expectNoExtraPass(beyond expected: Int, window: TimeInterval) {
        let deadline = Date().addingTimeInterval(window)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.025))
            if passCount > expected {
                XCTFail("Extra pass arrived; passCount=\(passCount), expected=\(expected)")
                return
            }
        }
        XCTAssertEqual(passCount, expected)
    }

    func testEnqueueSingleEventTriggersOnePassAfterDebounce() {
        reconciler.enqueue([tempRoot.appendingPathComponent("anything").path])
        waitForPasses(1, timeout: 1.0)
        XCTAssertEqual(passCount, 1)
    }

    func testRapidEnqueueCoalescesIntoOnePass() {
        // Fire 50 events in rapid succession (well within the 250ms debounce window).
        for i in 0..<50 {
            reconciler.enqueue([tempRoot.appendingPathComponent("file\(i)").path])
        }
        waitForPasses(1, timeout: 1.0)
        // Watch for 750ms (three debounce windows) to confirm no extra pass sneaks in.
        expectNoExtraPass(beyond: 1, window: 0.75)
    }

    func testSlidingWindowCapsAt1000ms() {
        // Continuously enqueue every 100ms. Without a cap, the sliding window
        // would never fire. With a 1000ms cap, the first pass should fire at ~1.0s
        // after the first enqueue.
        let start = Date()
        let burstDeadline = start.addingTimeInterval(1.5)
        while Date() < burstDeadline && passCount == 0 {
            reconciler.enqueue([tempRoot.appendingPathComponent("p").path])
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        // passCount should already be 1 by now if the cap fired; give a brief
        // window in case the event handler is just about to run.
        waitForPasses(1, timeout: 0.5)

        let elapsed = Date().timeIntervalSince(start)
        XCTAssertGreaterThanOrEqual(passCount, 1, "Expected the cap to fire at least one pass")
        // Tight band: cap is 1000ms; allow 200ms below (overdrive) and 500ms above
        // (CI jitter). A regression that removed the cap would blow past 1.5s.
        XCTAssertGreaterThan(elapsed, 0.8, "Pass fired far too early — cap logic may be broken")
        XCTAssertLessThan(elapsed, 1.5, "Pass took much longer than the 1000ms cap")
    }
}
