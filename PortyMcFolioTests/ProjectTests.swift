import XCTest
@testable import PortyMcFolio

final class ProjectTests: XCTestCase {
    func testProjectFromFolderName() throws {
        let project = try Project.from(
            folderName: "2025_brand_identity_a3f1b2c4",
            rootURL: URL(fileURLWithPath: "/tmp/portfolio")
        )
        XCTAssertEqual(project.year, 2025)
        XCTAssertEqual(project.uid, "a3f1b2c4")
        XCTAssertEqual(project.folderName, "2025_brand_identity_a3f1b2c4")
        XCTAssertEqual(project.folderURL.path, "/tmp/portfolio/2025_brand_identity_a3f1b2c4")
        XCTAssertEqual(project.readmeURL.path, "/tmp/portfolio/2025_brand_identity_a3f1b2c4/2025_brand_identity_a3f1b2c4.md")
    }

    func testProjectFromMultiWordSlug() throws {
        let project = try Project.from(
            folderName: "2026_my_cool_long_project_7e2d9f01",
            rootURL: URL(fileURLWithPath: "/tmp/portfolio")
        )
        XCTAssertEqual(project.year, 2026)
        XCTAssertEqual(project.uid, "7e2d9f01")
    }

    func testProjectFolderName() {
        let name = Project.folderName(title: "Brand Identity", year: 2025, uid: "a3f1b2c4")
        XCTAssertEqual(name, "2025_brand_identity_a3f1b2c4")
    }

    func testProjectFromInvalidFolderNameThrows() {
        XCTAssertThrowsError(try Project.from(
            folderName: "not-a-valid-folder",
            rootURL: URL(fileURLWithPath: "/tmp/portfolio")
        ))
    }

    func testProjectFromTooFewComponents() {
        XCTAssertThrowsError(try Project.from(
            folderName: "2025_a3f1b2c4",
            rootURL: URL(fileURLWithPath: "/tmp/portfolio")
        ))
    }

    func testProjectStatusComparable() {
        let statuses: [ProjectStatus] = [.archived, .empty, .inProgress]
        let sorted = statuses.sorted()
        XCTAssertEqual(sorted, [.empty, .inProgress, .archived])
    }
}
