import Foundation
import Security

enum UID {
    /// Generate an 8-character lowercase hex string to disambiguate project folder
    /// names. Prefers cryptographically random bytes via `SecRandomCopyBytes`;
    /// falls back to a `UUID`-derived hex if the system RNG call fails.
    ///
    /// UID is not a security token — it's a folder-name suffix. A UUID-derived
    /// fallback is perfectly adequate when `SecRandomCopyBytes` is unavailable,
    /// and is strictly better than crashing the app on project creation.
    static func generate() -> String {
        if let hex = secureRandomHex() {
            return hex
        }
        AppLogger.app.warning("SecRandomCopyBytes unavailable; falling back to UUID-derived UID")
        return fallbackHex()
    }

    /// Internal — exposed for testing. Returns nil if `SecRandomCopyBytes` fails.
    static func secureRandomHex() -> String? {
        var bytes = [UInt8](repeating: 0, count: 4)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { return nil }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Internal — exposed for testing. Returns 8 lowercase hex chars derived
    /// from a fresh `UUID`. Non-cryptographic but collision-resistant enough
    /// for a folder-name suffix.
    static func fallbackHex() -> String {
        let uuid = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return String(uuid.prefix(8))
    }
}
