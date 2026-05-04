import Foundation
import Yams

enum LinkItemError: Error {
    case invalidFormat
}

struct LinkItem: Identifiable, Equatable {
    let uid: String
    let url: URL
    var title: String
    var annotation: String
    var date: Date

    var id: String { uid }

    /// Returns the filename for a link file: "link-{uid}.md"
    static func fileName(uid: String) -> String {
        "link-\(uid).md"
    }

    /// Returns true if the given filename matches the pattern "link-{8-char-hex}.md"
    static func isLinkFile(name: String) -> Bool {
        guard name.hasPrefix("link-"), name.hasSuffix(".md") else { return false }
        let inner = name.dropFirst("link-".count).dropLast(".md".count)
        return inner.count == 8 && inner.allSatisfy({ $0.isHexDigit })
    }

    /// Normalizes user-entered URL text. Returns nil for empty/invalid input.
    /// Bare domains (no scheme) get prepended with `https://`. URLs that
    /// already have a scheme (http, https, ftp, file, mailto, etc.) pass through.
    static func normalizeURL(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return URL(string: trimmed)
        }

        if trimmed.contains("://") {
            return URL(string: trimmed)
        }

        return URL(string: "https://\(trimmed)")
    }

    /// Parse a LinkItem from a markdown string with YAML frontmatter.
    static func parse(markdown: String, overrideUID: String? = nil) throws -> LinkItem {
        let normalized = markdown.hasPrefix("\n") ? String(markdown.dropFirst()) : markdown

        guard normalized.hasPrefix("---") else {
            throw LinkItemError.invalidFormat
        }

        let lines = normalized.components(separatedBy: "\n")
        guard lines.first == "---" else {
            throw LinkItemError.invalidFormat
        }

        var closingIndex: Int? = nil
        for i in 1..<lines.count {
            if lines[i] == "---" {
                closingIndex = i
                break
            }
        }

        guard let closing = closingIndex else {
            throw LinkItemError.invalidFormat
        }

        let yamlLines = lines[1..<closing]
        let yamlString = yamlLines.joined(separator: "\n")

        guard let yaml = try? Yams.load(yaml: yamlString),
              let dict = yaml as? [String: Any] else {
            throw LinkItemError.invalidFormat
        }

        guard let urlString = dict["url"] as? String,
              let url = URL(string: urlString) else {
            throw LinkItemError.invalidFormat
        }

        let title = dict["title"] as? String ?? ""
        let annotation = dict["annotation"] as? String ?? ""

        let date: Date
        if let dateString = dict["date"] as? String {
            date = parseDate(dateString) ?? Date()
        } else if let dateValue = dict["date"] as? Date {
            date = dateValue
        } else {
            date = Date()
        }

        return LinkItem(
            uid: overrideUID ?? UID.generate(),
            url: url,
            title: title,
            annotation: annotation,
            date: date
        )
    }

    /// Serialize this LinkItem back to markdown with YAML frontmatter.
    func toMarkdown() -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let dateString = dateFormatter.string(from: date)

        return """
        ---
        type: link
        url: \(Self.yamlEscaped(url.absoluteString))
        title: \(Self.yamlEscaped(title))
        annotation: \(Self.yamlEscaped(annotation))
        date: \(dateString)
        ---
        """
    }

    /// Escape a string for use inside a double-quoted YAML value.
    private static func yamlEscaped(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    // MARK: - Private helpers

    private static func parseDate(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        if let date = iso.date(from: string) {
            return date
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd", "yyyy/MM/dd", "MM/dd/yyyy"] {
            df.dateFormat = format
            if let date = df.date(from: string) {
                return date
            }
        }
        return nil
    }
}
