import XCTest
@testable import PortyMcFolio

final class SuggestedClientsTests: XCTestCase {
    func testSplitsCommaJoinedClientsAndRanksByFrequency() {
        let projects = [
            makeProject(client: "Acme, Globex"),
            makeProject(client: "Acme"),
            makeProject(client: "Globex, Initech"),
            makeProject(client: "Acme"),
        ]

        let result = AppState.suggestedClients(from: projects)

        // Acme: 3, Globex: 2, Initech: 1
        XCTAssertEqual(result, ["Acme", "Globex", "Initech"])
    }

    func testTrimsWhitespaceAndSkipsEmpties() {
        let projects = [
            makeProject(client: "  Acme  ,  , Globex"),
            makeProject(client: ""),
            makeProject(client: "   "),
        ]

        let result = AppState.suggestedClients(from: projects)

        // Both clients appear exactly once, so order is unspecified — assert membership.
        XCTAssertEqual(Set(result), ["Acme", "Globex"])
        XCTAssertEqual(result.count, 2)
    }

    // MARK: - helpers

    private func makeProject(client: String) -> Project {
        Project(
            uid: "aaaaaaaa",
            year: 2025,
            folderName: "2025_test_aaaaaaaa",
            folderURL: URL(fileURLWithPath: "/tmp/portfolio/2025_test_aaaaaaaa"),
            title: "Test",
            date: Date(),
            tags: [],
            client: client,
            status: .empty,
            body: "",
            teaser: ""
        )
    }
}
