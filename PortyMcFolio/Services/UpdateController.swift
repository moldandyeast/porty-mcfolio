import Foundation
import Sparkle
import SwiftUI

@MainActor
final class UpdateController: NSObject, ObservableObject {
    private let standardController: SPUStandardUpdaterController

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
        self.standardController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }
}
