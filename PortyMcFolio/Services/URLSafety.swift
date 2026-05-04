import Foundation

extension URL {
    /// True if this URL has a scheme safe to hand to `NSWorkspace.open(_:)`
    /// for user-initiated external navigation. Conservative allowlist:
    /// `http`, `https`, `mailto`. Rejects `file://` (Finder escape),
    /// `javascript:` (no effect on macOS, but a crafted link shouldn't be
    /// treated as openable), `data:`, custom schemes, and anything else.
    var isSafeExternalScheme: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "mailto"
    }
}
