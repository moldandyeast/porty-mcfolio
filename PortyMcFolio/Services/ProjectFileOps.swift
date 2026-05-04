import Foundation

enum ProjectFileOps {
    /// Updates README references (teaser, body `![[…]]` embeds, favorites)
    /// when a file's project-relative path changes. Caller is responsible
    /// for the actual filesystem move and for posting
    /// `.markdownFileDidChange` / reconciler notifications after this runs.
    /// Returns true if the README was modified and successfully written.
    /// Throws if reading, parsing, or writing the README fails.
    @MainActor
    static func updateReferences(
        in project: Project,
        from oldRelative: String,
        to newRelative: String
    ) throws -> Bool {
        guard oldRelative != newRelative else { return false }

        // Flush any pending debounced editor save BEFORE reading the
        // README from disk, so user-typed-but-not-yet-saved edits don't
        // clobber our rewrite when the editor's debounce fires later.
        NotificationCenter.default.post(name: .markdownSaveNow, object: nil)

        let content = try String(contentsOf: project.readmeURL, encoding: .utf8)
        var parsed = try FrontmatterParser.parse(content)

        var changed = false

        if parsed.teaser == oldRelative {
            parsed.teaser = newRelative
            changed = true
        }

        let oldEmbed = "![[\(oldRelative)]]"
        if parsed.body.contains(oldEmbed) {
            parsed.body = parsed.body.replacingOccurrences(of: oldEmbed, with: "![[\(newRelative)]]")
            changed = true
        }

        let newFavorites = FrontmatterParser.rewritingFavorite(
            in: parsed.favorites, from: oldRelative, to: newRelative
        )
        if newFavorites != parsed.favorites {
            parsed.favorites = newFavorites
            changed = true
        }

        guard changed else { return false }
        let updated = FrontmatterParser.serialize(frontmatter: parsed)
        try updated.write(to: project.readmeURL, atomically: true, encoding: .utf8)
        return true
    }
}
