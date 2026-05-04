import XCTest
@testable import PortyMcFolio

@MainActor
final class UpdateControllerTests: XCTestCase {
    func test_currentVersion_readsCFBundleShortVersionString() {
        let controller = UpdateController()
        let expected = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        XCTAssertEqual(controller.currentVersion, expected ?? "?")
    }

    func test_automaticallyChecksForUpdates_writesToSparkleUserDefaults() {
        let controller = UpdateController()
        controller.automaticallyChecksForUpdates = false
        XCTAssertEqual(UserDefaults.standard.bool(forKey: "SUEnableAutomaticChecks"), false)
        controller.automaticallyChecksForUpdates = true
        XCTAssertEqual(UserDefaults.standard.bool(forKey: "SUEnableAutomaticChecks"), true)
    }

    func test_automaticallyChecksForUpdates_readsFromSparkle() {
        UserDefaults.standard.set(false, forKey: "SUEnableAutomaticChecks")
        let controller = UpdateController()
        XCTAssertEqual(controller.automaticallyChecksForUpdates, false)
        UserDefaults.standard.set(true, forKey: "SUEnableAutomaticChecks")
        XCTAssertEqual(controller.automaticallyChecksForUpdates, true)
    }
}
