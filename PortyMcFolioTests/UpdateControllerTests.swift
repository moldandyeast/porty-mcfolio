import XCTest
@testable import PortyMcFolio

@MainActor
final class UpdateControllerTests: XCTestCase {
    func test_currentVersion_readsCFBundleShortVersionString() {
        let controller = UpdateController()
        let expected = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        XCTAssertEqual(controller.currentVersion, expected ?? "?")
    }
}
