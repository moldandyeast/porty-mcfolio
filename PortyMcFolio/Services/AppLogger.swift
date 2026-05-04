import Foundation
import os

/// Namespaced `os.Logger` instances used across the app.
///
/// One subsystem (`com.portymcfolio.app`), many categories. Filter in Console.app
/// by `subsystem:com.portymcfolio.app` and a specific category when debugging a
/// single subsystem.
///
/// Default string-interpolation privacy for `os.Logger` is `.private` in release
/// builds, which masks values with `<private>`. For this app — a single-user,
/// local-only portfolio tool — that is overzealous. Pass `privacy: .public` on
/// values you want to appear literally in logs (uids, paths, error descriptions).
enum AppLogger {
    private static let subsystem = "com.portymcfolio.app"

    static let app         = Logger(subsystem: subsystem, category: "app")
    static let reconciler  = Logger(subsystem: subsystem, category: "reconciler")
    static let cache       = Logger(subsystem: subsystem, category: "cache")
    static let search      = Logger(subsystem: subsystem, category: "search")
    static let frontmatter = Logger(subsystem: subsystem, category: "frontmatter")
    static let portfolio   = Logger(subsystem: subsystem, category: "portfolio")
    static let ui          = Logger(subsystem: subsystem, category: "ui")
}
