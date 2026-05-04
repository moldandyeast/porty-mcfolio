import XCTest
@testable import PortyMcFolio

@MainActor
final class AppStateProjectOnboardingPersistenceTests: XCTestCase {

    private let key = "hasSeenProjectOnboarding"

    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: key)
    }

    func test_setting_writes_to_defaults() {
        let appState = AppState()
        appState.hasSeenProjectOnboarding = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))

        appState.hasSeenProjectOnboarding = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: key))
    }

    func test_loadLayoutPreferences_restoresStoredValue() {
        UserDefaults.standard.set(true, forKey: key)
        let appState = AppState()
        appState.loadLayoutPreferences()
        XCTAssertTrue(appState.hasSeenProjectOnboarding)
    }

    func test_loadLayoutPreferences_noStoredValue_keepsFalseDefault() {
        let appState = AppState()
        appState.loadLayoutPreferences()
        XCTAssertFalse(appState.hasSeenProjectOnboarding)
    }
}
