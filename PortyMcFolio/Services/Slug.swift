import Foundation

enum Slug {
    static func from(_ input: String) -> String {
        // Strip diacritics and fold to ASCII
        let folded = input.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))

        // Lowercase
        let lowercased = folded.lowercased()

        // Remove characters that are not alphanumeric, space, or hyphen
        let allowed = lowercased.unicodeScalars.filter { scalar in
            let c = Character(scalar)
            return c.isLetter || c.isNumber || c == " " || c == "-"
        }
        let filtered = String(String.UnicodeScalarView(allowed))

        // Replace runs of spaces/hyphens with a single hyphen
        let components = filtered.components(separatedBy: CharacterSet(charactersIn: " -"))
        let joined = components.filter { !$0.isEmpty }.joined(separator: "-")

        // Trim leading/trailing hyphens (already handled by filter above, but be safe)
        let trimmed = joined.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return trimmed.isEmpty ? "untitled" : trimmed
    }

    /// Like `from()` but uses underscores instead of hyphens.
    /// Used for filename prefixes: "Acme Rebrand" → "acme_rebrand"
    static func underscoreFrom(_ input: String) -> String {
        let folded = input.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let lowercased = folded.lowercased()
        let allowed = lowercased.unicodeScalars.filter { scalar in
            let c = Character(scalar)
            return c.isLetter || c.isNumber || c == " " || c == "-" || c == "_"
        }
        let filtered = String(String.UnicodeScalarView(allowed))
        let components = filtered.components(separatedBy: CharacterSet(charactersIn: " -_"))
        let joined = components.filter { !$0.isEmpty }.joined(separator: "_")
        let trimmed = joined.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return trimmed.isEmpty ? "untitled" : trimmed
    }
}
