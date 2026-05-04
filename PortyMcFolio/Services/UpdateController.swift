import Combine
import Foundation
import Sparkle
import SwiftUI

@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    private var standardController: SPUStandardUpdaterController!

    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var canCheckForUpdates: Bool = false

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var automaticallyChecksForUpdates: Bool {
        get { standardController.updater.automaticallyChecksForUpdates }
        set {
            standardController.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }

    override init() {
        super.init()
        self.standardController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        refreshState()
    }

    func checkNow() {
        standardController.checkForUpdates(nil)
    }

    private func refreshState() {
        lastCheckedAt = standardController.updater.lastUpdateCheckDate
        canCheckForUpdates = standardController.updater.canCheckForUpdates
    }

    // MARK: SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        Task { @MainActor [weak self] in
            self?.refreshState()
        }
    }
}
