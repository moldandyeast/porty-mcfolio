import XCTest
@testable import PortyMcFolio

@MainActor
final class AppStateShortcutDispatchTests: XCTestCase {

    private func makeProject(uid: String = "11111111") -> Project {
        Project(
            uid: uid,
            year: 2025,
            folderName: "2025_test_\(uid)",
            folderURL: URL(fileURLWithPath: "/tmp/fake-\(uid)"),
            title: "Test",
            date: Date(timeIntervalSince1970: 0),
            tags: [],
            client: "",
            status: .empty,
            body: "",
            teaser: ""
        )
    }

    // MARK: - Primary shortcut (⌘1)

    func testPrimaryShortcutOnOverviewSetsGridMode() {
        let state = AppState()
        state.selectedProject = nil
        state.projectListMode = .table

        state.handlePrimaryShortcut()

        XCTAssertEqual(state.projectListMode, .grid)
    }

    func testPrimaryShortcutOnDetailSetsEditorViewMode() {
        let state = AppState()
        state.selectedProject = makeProject()
        state.viewMode = .preview

        state.handlePrimaryShortcut()

        XCTAssertEqual(state.viewMode, .editor)
    }

    func testPrimaryShortcutOnOverviewDoesNotChangeViewMode() {
        let state = AppState()
        state.selectedProject = nil
        state.viewMode = .carousel

        state.handlePrimaryShortcut()

        XCTAssertEqual(state.viewMode, .carousel)
    }

    func testPrimaryShortcutOnDetailDoesNotChangeProjectListMode() {
        let state = AppState()
        state.selectedProject = makeProject()
        state.projectListMode = .table

        state.handlePrimaryShortcut()

        XCTAssertEqual(state.projectListMode, .table)
    }

    // MARK: - Secondary shortcut (⌘2)

    func testSecondaryShortcutOnOverviewSetsTableMode() {
        let state = AppState()
        state.selectedProject = nil
        state.projectListMode = .grid

        state.handleSecondaryShortcut()

        XCTAssertEqual(state.projectListMode, .table)
    }

    func testSecondaryShortcutOnDetailSetsPreviewViewMode() {
        let state = AppState()
        state.selectedProject = makeProject()
        state.viewMode = .editor

        state.handleSecondaryShortcut()

        XCTAssertEqual(state.viewMode, .preview)
    }

    // MARK: - Gallery shortcut (⌘3)

    func testGalleryShortcutFromEditorGoesToSplitGallery() {
        let state = AppState()
        state.selectedProject = makeProject()
        state.viewMode = .editor

        state.handleGalleryShortcut()

        XCTAssertEqual(state.viewMode, .splitGallery)
    }

    func testGalleryShortcutFromSplitGalleryGoesToFullGallery() {
        let state = AppState()
        state.selectedProject = makeProject()
        state.viewMode = .splitGallery

        state.handleGalleryShortcut()

        XCTAssertEqual(state.viewMode, .gallery)
    }

    func testGalleryShortcutFromFullGalleryGoesToSplitGallery() {
        let state = AppState()
        state.selectedProject = makeProject()
        state.viewMode = .gallery

        state.handleGalleryShortcut()

        XCTAssertEqual(state.viewMode, .splitGallery)
    }

    func testGalleryShortcutOnOverviewIsNoOp() {
        let state = AppState()
        state.selectedProject = nil
        state.viewMode = .editor

        state.handleGalleryShortcut()

        XCTAssertEqual(state.viewMode, .editor)
    }

    // MARK: - List shortcut (⌘4)

    func testListShortcutFromEditorGoesToSplitList() {
        let state = AppState()
        state.selectedProject = makeProject()
        state.viewMode = .editor

        state.handleListShortcut()

        XCTAssertEqual(state.viewMode, .splitList)
    }

    func testListShortcutFromSplitListGoesToFullList() {
        let state = AppState()
        state.selectedProject = makeProject()
        state.viewMode = .splitList

        state.handleListShortcut()

        XCTAssertEqual(state.viewMode, .list)
    }

    func testListShortcutFromFullListGoesToSplitList() {
        let state = AppState()
        state.selectedProject = makeProject()
        state.viewMode = .list

        state.handleListShortcut()

        XCTAssertEqual(state.viewMode, .splitList)
    }

    func testListShortcutOnOverviewIsNoOp() {
        let state = AppState()
        state.selectedProject = nil
        state.viewMode = .editor

        state.handleListShortcut()

        XCTAssertEqual(state.viewMode, .editor)
    }

    // MARK: - Links shortcut (⌘5)

    func testLinksShortcutFromEditorGoesToSplitLinks() {
        let state = AppState()
        state.selectedProject = makeProject()
        state.viewMode = .editor

        state.handleLinksShortcut()

        XCTAssertEqual(state.viewMode, .splitLinks)
    }

    func testLinksShortcutFromSplitLinksGoesToFullLinks() {
        let state = AppState()
        state.selectedProject = makeProject()
        state.viewMode = .splitLinks

        state.handleLinksShortcut()

        XCTAssertEqual(state.viewMode, .links)
    }

    func testLinksShortcutFromFullLinksGoesToSplitLinks() {
        let state = AppState()
        state.selectedProject = makeProject()
        state.viewMode = .links

        state.handleLinksShortcut()

        XCTAssertEqual(state.viewMode, .splitLinks)
    }

    func testLinksShortcutOnOverviewIsNoOp() {
        let state = AppState()
        state.selectedProject = nil
        state.viewMode = .editor

        state.handleLinksShortcut()

        XCTAssertEqual(state.viewMode, .editor)
    }
}
