import XCTest
import Combine
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

    func test_settingAutomaticallyChecks_firesObjectWillChange() {
        let controller = UpdateController()
        var fired = 0
        let cancellable = controller.objectWillChange.sink { fired += 1 }
        controller.automaticallyChecksForUpdates = !controller.automaticallyChecksForUpdates
        XCTAssertEqual(fired, 1, "objectWillChange should fire exactly once on setter")
        _ = cancellable
    }
}
