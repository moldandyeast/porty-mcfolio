import Foundation

enum FilenameDisplay {
    /// Returns `name` with `prefix` removed from its start, if and only if
    /// `name` begins with `prefix`. Otherwise returns `name` unchanged.
    /// `prefix` is matched with a plain `hasPrefix` — no slug/casing normalization.
    static func display(name: String, prefix: String) -> String {
        guard !prefix.isEmpty, name.hasPrefix(prefix) else { return name }
        return String(name.dropFirst(prefix.count))
    }
}
