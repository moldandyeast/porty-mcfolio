import XCTest
@testable import PortyMcFolio

final class PortfolioStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testScanFindsProjects() throws {
        _ = try ProjectCreator.create(title: "Project A", client: "", tags: [], rootURL: tempDir, body: "")
        _ = try ProjectCreator.create(title: "Project B", client: "", tags: ["design"], rootURL: tempDir, body: "")
        let store = PortfolioStore(rootURL: tempDir)
        let projects = try store.scanProjects()
        XCTAssertEqual(projects.count, 2)
    }

    func testScanIgnoresNonProjectFolders() throws {
        _ = try ProjectCreator.create(title: "Valid", client: "", tags: [], rootURL: tempDir, body: "")
        let randomDir = tempDir.appendingPathComponent("random-folder")
        try FileManager.default.createDirectory(at: randomDir, withIntermediateDirectories: true)
        let store = PortfolioStore(rootURL: tempDir)
        let projects = try store.scanProjects()
        XCTAssertEqual(projects.count, 1)
    }

    func testScanLoadsReadmeMetadata() throws {
        _ = try ProjectCreator.create(title: "Test Project", client: "Client X", tags: ["ui", "web"], rootURL: tempDir, body: "")
        let store = PortfolioStore(rootURL: tempDir)
        let projects = try store.scanProjects()
        XCTAssertEqual(projects.first?.title, "Test Project")
        XCTAssertEqual(projects.first?.client, "Client X")
        XCTAssertEqual(projects.first?.tags, ["ui", "web"])
    }

    func testScanSortsByYearDescending() throws {
        // Manually create folders with different years
        for (year, folder, _) in [(2023, "2023_old_project_aaaaaaaa", "aaaaaaaa"), (2025, "2025_new_project_bbbbbbbb", "bbbbbbbb")] {
            let url = tempDir.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let readme = "---\ntitle: \"\(folder)\"\ndate: 2025-01-01\ntags: []\nstatus: draft\n---\n\nBody."
            try readme.write(to: url.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        }
        let store = PortfolioStore(rootURL: tempDir)
        let projects = try store.scanProjects()
        XCTAssertEqual(projects.first?.year, 2025)
        XCTAssertEqual(projects.last?.year, 2023)
    }
}
