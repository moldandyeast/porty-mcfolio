import Foundation
import Sparkle
import SwiftUI

@MainActor
final class UpdateController: NSObject, ObservableObject {
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}
