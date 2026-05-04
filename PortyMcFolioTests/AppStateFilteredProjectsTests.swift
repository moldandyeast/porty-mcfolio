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

    // MARK: - matchedProjectUIDs union semantics
    //
    // These tests exercise the static helper directly so we can simulate a
    // truncated FTS snapshot (the real-world bug scenario) without having to
    // construct a live SearchController + SearchIndex.

    func snapshot(query: String, matchedUIDs: [String]) -> SearchController.Snapshot {
        SearchController.Snapshot(query: query, results: [], matchedUIDs: matchedUIDs)
    }

    func testMetadataMatchesAreAlwaysIncludedEvenWhenFTSTruncated() {
        // Scenario: user has 5 LEGO-titled projects. FTS LIMIT 30 was dominated
        // by file rows, so snapshot.matchedUIDs only surfaced 2 of them.
        let projects = [
            makeProject(uid: "00000001", title: "LEGO 70358"),
            makeProject(uid: "00000002", title: "LEGO 70350 : Three Brothers"),
            makeProject(uid: "00000003", title: "LEGO Nature"),
            makeProject(uid: "00000004", title: "LEGO Golden Gate Bridge"),
            makeProject(uid: "00000005", title: "LEGO 70347 : King's Guard"),
            makeProject(uid: "00000006", title: "Unrelated Poster"),
        ]
        let truncated = snapshot(query: "lego", matchedUIDs: ["00000001", "00000002"])

        let matched = AppState.matchedProjectUIDs(
            query: "lego",
            snapshot: truncated,
            projects: projects
        )
        XCTAssertEqual(matched, Set(["00000001", "00000002", "00000003", "00000004", "00000005"]))
    }

    func testFTSUIDsAreUnionedForBodyOnlyMatches() {
        // Scenario: a project whose metadata does NOT contain "lego" but whose
        // body does — FTS surfaces it, metadata substring doesn't.
        let projects = [
            makeProject(uid: "00000001", title: "Toy Design Study", tags: []),
            makeProject(uid: "00000002", title: "LEGO Nature"),
        ]
        let fts = snapshot(query: "lego", matchedUIDs: ["00000001"])
        let matched = AppState.matchedProjectUIDs(
            query: "lego",
            snapshot: fts,
            projects: projects
        )
        XCTAssertEqual(matched, Set(["00000001", "00000002"]))
    }

    func testStaleSnapshotIsIgnoredButMetadataStillMatches() {
        // Scenario: user typed "legos" but the snapshot still reflects "lego"
        // (mid-debounce). The stale snapshot must not contribute its UIDs; the
        // metadata pass for "legos" is the only contribution.
        let projects = [
            makeProject(uid: "00000001", title: "LEGO 70358"),
            makeProject(uid: "00000002", title: "Legos in the Garden"),
            makeProject(uid: "00000003", title: "Unrelated"),
        ]
        let staleForLego = snapshot(query: "lego", matchedUIDs: ["00000001"])
        let matched = AppState.matchedProjectUIDs(
            query: "legos",
            snapshot: staleForLego,
            projects: projects
        )
        // Only the "Legos in the Garden" project matches "legos" as a substring;
        // the stale snapshot's "lego" uids do NOT leak in.
        XCTAssertEqual(matched, Set(["00000002"]))
    }

    func testNoSnapshotFallsBackToMetadataOnly() {
        let projects = [
            makeProject(uid: "00000001", title: "LEGO Nature"),
            makeProject(uid: "00000002", title: "Unrelated"),
        ]
        let matched = AppState.matchedProjectUIDs(
            query: "lego",
            snapshot: nil,
            projects: projects
        )
        XCTAssertEqual(matched, Set(["00000001"]))
    }

    func testEmptyQueryReturnsAllProjectUIDs() {
        let projects = [
            makeProject(uid: "00000001", title: "Alpha"),
            makeProject(uid: "00000002", title: "Beta"),
        ]
        XCTAssertEqual(
            AppState.matchedProjectUIDs(query: "", snapshot: nil, projects: projects),
            Set(["00000001", "00000002"])
        )
        XCTAssertEqual(
            AppState.matchedProjectUIDs(query: "   ", snapshot: nil, projects: projects),
            Set(["00000001", "00000002"])
        )
    }
}
