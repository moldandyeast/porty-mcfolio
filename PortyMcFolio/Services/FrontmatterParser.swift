import Foundation
import Yams

struct ParsedFrontmatter {
    var title: String
    var date: Date
    var dateEnd: Date? = nil
    /// Opaque storage for legacy `datePrecision:` YAML keys (`year`, `month`,
    /// `day`, or anything else) so external authoring is preserved through
    /// reconciler rewrites. The picker writes a clean two-mode model and
    /// `AppState.updateProjectMetadata` clears this field when the user
    /// actively edits the When; everywhere else it round-trips untouched.
    var datePrecisionRaw: String? = nil
    var tags: [String]
    var client: String
    var status: ProjectStatus
    var body: String
    var teaser: String
    var favorites: [String] = []
    var hidden: Bool = false
}

enum FrontmatterParser {

    enum ParseError: Error {
        case invalidYAML
        case missingField(String)
    }

    /// Rejects absolute paths, `~`-relative paths, `../` escapes, null bytes,
    /// and empty strings. Everything else is treated as a valid project-relative
    /// path (we don't verify it exists here — reconciler handles missing files).
    static func isValidFavoritePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("~"),
              !path.contains(".."),
              !path.contains("\0")
        else { return false }
        return true
    }

    /// Rewrites a favorites list when a file is renamed/moved/trashed.
    /// - `to` is the new relative path, or empty string if the file was trashed.
    /// - Rewrites every occurrence of `from` to `to` (preserves duplicates).
    /// - If `to` is empty, removes every occurrence of `from`.
    static func rewritingFavorite(
        in favorites: [String],
        from oldRelative: String,
        to newRelative: String
    ) -> [String] {
        if newRelative.isEmpty {
            return favorites.filter { $0 != oldRelative }
        }
        return favorites.map { $0 == oldRelative ? newRelative : $0 }
    }

    /// Rewrites a favorites list when a folder is renamed. Matches entries
    /// whose path begins with `from + "/"` and swaps only that prefix.
    /// Uses a proper path-component match so `photos` doesn't accidentally
    /// match `otherphotos`.
    static func rewritingFavoritePrefix(
        in favorites: [String],
        from oldPrefix: String,
        to newPrefix: String
    ) -> [String] {
        let old = "\(oldPrefix)/"
        let new = "\(newPrefix)/"
        return favorites.map { path in
            path.hasPrefix(old)
                ? new + path.dropFirst(old.count)
                : path
        }
    }

    /// Applies a folder rename across every referencing field of a frontmatter
    /// (body embeds `![[oldPrefix/...]]`, teaser prefix, favorite prefixes) via
    /// parsed-field edits instead of a naive whole-file string replace, which
    /// would risk corrupting YAML frontmatter. Returns the rewritten frontmatter
    /// and whether any field changed.
    static func rewritingFolderRename(
        in frontmatter: ParsedFrontmatter,
        from oldPrefix: String,
        to newPrefix: String
    ) -> (ParsedFrontmatter, Bool) {
        var out = frontmatter
        var changed = false

        let oldBodyPrefix = "![[\(oldPrefix)/"
        let newBodyPrefix = "![[\(newPrefix)/"
        if out.body.contains(oldBodyPrefix) {
            out.body = out.body.replacingOccurrences(of: oldBodyPrefix, with: newBodyPrefix)
            changed = true
        }

        let teaserFolderPrefix = "\(oldPrefix)/"
        if out.teaser.hasPrefix(teaserFolderPrefix) {
            out.teaser = "\(newPrefix)/" + out.teaser.dropFirst(teaserFolderPrefix.count)
            changed = true
        }

        let newFavorites = rewritingFavoritePrefix(
            in: out.favorites,
            from: oldPrefix,
            to: newPrefix
        )
        if newFavorites != out.favorites {
            out.favorites = newFavorites
            changed = true
        }

        return (out, changed)
    }

    /// Extracts YAML frontmatter from a markdown string and returns structured data plus body text.
    static func parse(_ markdown: String) throws -> ParsedFrontmatter {
        let normalized = markdown.hasPrefix("\n") ? String(markdown.dropFirst()) : markdown

        // Check for frontmatter delimiters
        guard normalized.hasPrefix("---") else {
            // No frontmatter — return defaults with full string as body
            return ParsedFrontmatter(
                title: "",
                date: Date(),
                tags: [],
                client: "",
                status: .empty,
                body: markdown,
                teaser: "",
                favorites: [],
                hidden: false
            )
        }

        // Split on --- boundaries
        let lines = normalized.components(separatedBy: "\n")
        guard lines.first == "---" else {
            return ParsedFrontmatter(
                title: "",
                date: Date(),
                tags: [],
                client: "",
                status: .empty,
                body: markdown,
                teaser: "",
                favorites: [],
                hidden: false
            )
        }

        // Find closing ---
        var closingIndex: Int? = nil
        for i in 1..<lines.count {
            if lines[i] == "---" {
                closingIndex = i
                break
            }
        }

        guard let closing = closingIndex else {
            // No closing delimiter — treat entire string as body
            return ParsedFrontmatter(
                title: "",
                date: Date(),
                tags: [],
                client: "",
                status: .empty,
                body: markdown,
                teaser: "",
                favorites: [],
                hidden: false
            )
        }

        let yamlLines = lines[1..<closing]
        let yamlString = yamlLines.joined(separator: "\n")

        // Body is everything after the closing ---
        let bodyLines = lines[(closing + 1)...]
        // Strip leading blank line if present
        var bodyArray = Array(bodyLines)
        if bodyArray.first == "" {
            bodyArray.removeFirst()
        }
        let body = bodyArray.joined(separator: "\n")

        // Parse YAML — propagate errors instead of swallowing them
        let yaml: Any?
        do {
            yaml = try Yams.load(yaml: yamlString)
        } catch {
            AppLogger.frontmatter.error("YAML parse error: \(error.localizedDescription, privacy: .public)")
            throw ParseError.invalidYAML
        }
        guard let dict = yaml as? [String: Any] else {
            throw ParseError.invalidYAML
        }

        let title = dict["title"] as? String ?? ""
        let client = dict["client"] as? String ?? ""

        // Parse tags
        let tags: [String]
        if let tagsArray = dict["tags"] as? [String] {
            tags = tagsArray
        } else if let tagsArray = dict["tags"] as? [Any] {
            tags = tagsArray.compactMap { $0 as? String }
        } else {
            tags = []
        }

        // Parse status (with legacy mapping)
        let statusRaw = dict["status"] as? String ?? "empty"
        let status = ProjectStatus(rawValue: statusRaw) ?? ProjectStatus.from(statusRaw)

        // Parse date
        let date: Date
        if let dateString = dict["date"] as? String {
            date = parseDate(dateString) ?? Date()
        } else if let dateValue = dict["date"] as? Date {
            date = dateValue
        } else {
            date = Date()
        }

        // Parse dateEnd (optional)
        let dateEndRaw: Date?
        if let s = dict["dateEnd"] as? String {
            dateEndRaw = parseDate(s)
        } else if let d = dict["dateEnd"] as? Date {
            dateEndRaw = d
        } else {
            dateEndRaw = nil
        }

        // Clamp dateEnd to >= date so downstream code can rely on the invariant.
        let dateEnd: Date?
        if let end = dateEndRaw, end < date {
            AppLogger.frontmatter.warning("dateEnd before date — clamping to date")
            dateEnd = date
        } else {
            dateEnd = dateEndRaw
        }

        let datePrecisionRaw = dict["datePrecision"] as? String

        let teaser = dict["teaser"] as? String ?? ""

        // Parse favorites — defensive: drop non-strings and invalid paths.
        let favoritesRaw = dict["favorites"] as? [Any] ?? []
        let favorites = favoritesRaw
            .compactMap { $0 as? String }
            .filter { isValidFavoritePath($0) }

        let hidden = dict["hidden"] as? Bool ?? false

        return ParsedFrontmatter(
            title: title,
            date: date,
            dateEnd: dateEnd,
            datePrecisionRaw: datePrecisionRaw,
            tags: tags,
            client: client,
            status: status,
            body: body,
            teaser: teaser,
            favorites: favorites,
            hidden: hidden
        )
    }

    /// Converts a ParsedFrontmatter back to a markdown string with YAML frontmatter.
    static func serialize(frontmatter fm: ParsedFrontmatter) -> String {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let dateString = dateFormatter.string(from: fm.date)

        let tagsYAML: String
        if fm.tags.isEmpty {
            tagsYAML = "[]"
        } else {
            let tagItems = fm.tags.map { yamlEscaped($0) }.joined(separator: ", ")
            tagsYAML = "[\(tagItems)]"
        }

        var lines = [
            "---",
            "title: \(yamlEscaped(fm.title))",
            "date: \(dateString)",
            "tags: \(tagsYAML)",
            "client: \(yamlEscaped(fm.client))",
            "status: \(fm.status.rawValue)",
        ]
        if !fm.teaser.isEmpty {
            lines.append("teaser: \(yamlEscaped(fm.teaser))")
        }
        if let dateEnd = fm.dateEnd {
            let endString = dateFormatter.string(from: dateEnd)
            lines.append("dateEnd: \(endString)")
        }
        if let precision = fm.datePrecisionRaw, !precision.isEmpty {
            lines.append("datePrecision: \(precision)")
        }
        if !fm.favorites.isEmpty {
            let items = fm.favorites.map { yamlEscaped($0) }.joined(separator: ", ")
            lines.append("favorites: [\(items)]")
        }
        if fm.hidden {
            lines.append("hidden: true")
        }
        lines.append("---")
        let header = lines.joined(separator: "\n")

        let body = fm.body.isEmpty ? "" : "\n\(fm.body)"
        return header + "\n" + body
    }

    // MARK: - Private helpers

    /// Escape a string for use inside a double-quoted YAML value.
    private static func yamlEscaped(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

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
