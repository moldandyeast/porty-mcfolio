import XCTest
@testable import PortyMcFolio

final class BodyEmbedReconciliationTests: XCTestCase {
    func testBodyWithNoEmbedsIsUnchanged() {
        let body = "# Title\n\nJust prose, no embeds."
        let result = BodyEmbedReconciliation.reconcile(body: body, onDiskPaths: ["hero.jpg"])
        XCTAssertEqual(result.body, body)
        XCTAssertTrue(result.repaired.isEmpty)
        XCTAssertTrue(result.orphaned.isEmpty)
    }

    func testEmbedThatResolvesIsUnchanged() {
        let body = "# Title\n\n![[hero.jpg]]"
        let result = BodyEmbedReconciliation.reconcile(body: body, onDiskPaths: ["hero.jpg"])
        XCTAssertEqual(result.body, body)
        XCTAssertTrue(result.repaired.isEmpty)
        XCTAssertTrue(result.orphaned.isEmpty)
    }

    func testStaleEmbedWithOneMatchIsRepaired() {
        let body = "# Title\n\n![[hero.jpg]]\n"
        let result = BodyEmbedReconciliation.reconcile(
            body: body,
            onDiskPaths: ["subfolder/hero.jpg"]
        )
        XCTAssertEqual(result.body, "# Title\n\n![[subfolder/hero.jpg]]\n")
        XCTAssertEqual(result.repaired, [
            .init(oldPath: "hero.jpg", newPath: "subfolder/hero.jpg")
        ])
        XCTAssertTrue(result.orphaned.isEmpty)
    }

    func testStaleEmbedWithZeroMatchesIsOrphaned() {
        let body = "# Title\n\n![[hero.jpg]]"
        let result = BodyEmbedReconciliation.reconcile(
            body: body,
            onDiskPaths: ["other.jpg"]
        )
        XCTAssertEqual(result.body, body)
        XCTAssertTrue(result.repaired.isEmpty)
        XCTAssertEqual(result.orphaned, ["hero.jpg"])
    }

    func testStaleEmbedWithMultipleMatchesIsOrphaned() {
        let body = "![[hero.jpg]]"
        let result = BodyEmbedReconciliation.reconcile(
            body: body,
            onDiskPaths: ["a/hero.jpg", "b/hero.jpg"]
        )
        XCTAssertEqual(result.body, body)
        XCTAssertTrue(result.repaired.isEmpty)
        XCTAssertEqual(result.orphaned, ["hero.jpg"])
    }

    func testTwoEmbedsPointingToSameRenamedFileAreRewrittenConsistentlyAndDedupedInRepaired() {
        let body = "![[hero.jpg]]\nSome text.\n![[hero.jpg]]"
        let result = BodyEmbedReconciliation.reconcile(
            body: body,
            onDiskPaths: ["new/hero.jpg"]
        )
        XCTAssertEqual(result.body, "![[new/hero.jpg]]\nSome text.\n![[new/hero.jpg]]")
        // Deduplicated by (oldPath, newPath) — one entry even though two rewrites happened.
        XCTAssertEqual(result.repaired, [
            .init(oldPath: "hero.jpg", newPath: "new/hero.jpg")
        ])
        XCTAssertTrue(result.orphaned.isEmpty)
    }

    func testEmbedWithAbsolutePathIsSkipped() {
        let body = "![[/etc/passwd]]"
        let result = BodyEmbedReconciliation.reconcile(
            body: body,
            onDiskPaths: ["passwd"]
        )
        XCTAssertEqual(result.body, body)
        XCTAssertTrue(result.repaired.isEmpty)
        XCTAssertTrue(result.orphaned.isEmpty)
    }

    func testEmbedWithDotDotPathIsSkipped() {
        let body = "![[../sibling.jpg]]"
        let result = BodyEmbedReconciliation.reconcile(
            body: body,
            onDiskPaths: ["sibling.jpg"]
        )
        XCTAssertEqual(result.body, body)
        XCTAssertTrue(result.repaired.isEmpty)
        XCTAssertTrue(result.orphaned.isEmpty)
    }

    func testRewritePreservesSurroundingTextByteForByte() {
        let body = """
        # Header

        ```swift
        let x = 1  // ![[code.jpg]] is literal here but the pattern still matches
        ```

        ![[hero.jpg]]

        More text **with** _markdown_.
        """
        let result = BodyEmbedReconciliation.reconcile(
            body: body,
            onDiskPaths: ["new/hero.jpg", "new/code.jpg"]
        )
        // Both embeds get rewritten (the regex doesn't know about code fences — that's OK).
        XCTAssertTrue(result.body.contains("![[new/hero.jpg]]"))
        XCTAssertTrue(result.body.contains("![[new/code.jpg]]"))
        XCTAssertTrue(result.body.contains("# Header"))
        XCTAssertTrue(result.body.contains("More text **with** _markdown_"))
        XCTAssertFalse(result.body.contains("![[hero.jpg]]"))
        XCTAssertFalse(result.body.contains("![[code.jpg]]"))
    }

    func testOrphanedListDedupes() {
        let body = "![[missing.jpg]] and then ![[missing.jpg]] again"
        let result = BodyEmbedReconciliation.reconcile(
            body: body,
            onDiskPaths: []
        )
        XCTAssertEqual(result.orphaned, ["missing.jpg"])
    }
}
