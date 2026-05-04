import Foundation

struct BodyEmbedResult: Equatable {
    let body: String
    let repaired: [Repair]
    let orphaned: [String]

    struct Repair: Equatable {
        let oldPath: String
        let newPath: String
    }
}

/// Pure reconciliation for `![[…]]` embeds in a project body. Mirrors
/// `FavoritesReconciliation` / `TeaserReconciliation`: repairs references to
/// renamed files when the basename is unique on disk, leaves everything else
/// alone.
///
/// - Embeds with absolute (`/…`) or dot-dot (`..`) paths are skipped entirely
///   and appear in neither list.
/// - `repaired` deduplicates by `(oldPath, newPath)` pair: a body with three
///   `![[hero.jpg]]` references that all repair to `new/hero.jpg` produces
///   exactly one entry in `repaired` (and three rewrites in `body`).
/// - `orphaned` also deduplicates by path.
/// - Non-embed text is preserved byte-for-byte.
enum BodyEmbedReconciliation {
    private static let embedRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"!\[\[([^\]]+)\]\]"#)
    }()

    static func reconcile(
        body: String,
        onDiskPaths: Set<String>
    ) -> BodyEmbedResult {
        let nsBody = body as NSString
        let fullRange = NSRange(location: 0, length: nsBody.length)
        let matches = embedRegex.matches(in: body, range: fullRange)

        // Pre-index on-disk paths by lowercased basename.
        var byBasename: [String: [String]] = [:]
        for path in onDiskPaths {
            let basename = (path as NSString).lastPathComponent.lowercased()
            byBasename[basename, default: []].append(path)
        }

        // Decisions applied in reverse so earlier NSRange indices stay valid.
        struct Rewrite { let range: NSRange; let newPath: String }
        var rewrites: [Rewrite] = []
        var repaired: [BodyEmbedResult.Repair] = []
        var repairedKeys: Set<String> = []  // "oldPath\u{0}newPath"
        var orphaned: [String] = []
        var orphanedSeen: Set<String> = []

        for match in matches {
            guard match.numberOfRanges == 2 else { continue }
            let pathRange = match.range(at: 1)
            let oldPath = nsBody.substring(with: pathRange).trimmingCharacters(in: .whitespaces)

            if oldPath.hasPrefix("/") || oldPath.contains("..") { continue }
            if onDiskPaths.contains(oldPath) { continue }

            let basename = (oldPath as NSString).lastPathComponent.lowercased()
            let candidates = byBasename[basename] ?? []
            if candidates.count == 1, let new = candidates.first {
                rewrites.append(Rewrite(range: pathRange, newPath: new))
                let key = "\(oldPath)\u{0}\(new)"
                if !repairedKeys.contains(key) {
                    repairedKeys.insert(key)
                    repaired.append(.init(oldPath: oldPath, newPath: new))
                }
            } else {
                if !orphanedSeen.contains(oldPath) {
                    orphanedSeen.insert(oldPath)
                    orphaned.append(oldPath)
                }
            }
        }

        // Apply rewrites in reverse so earlier ranges remain valid.
        var out = body
        for rewrite in rewrites.reversed() {
            guard let swiftRange = Range(rewrite.range, in: out) else { continue }
            out.replaceSubrange(swiftRange, with: rewrite.newPath)
        }

        return BodyEmbedResult(body: out, repaired: repaired, orphaned: orphaned)
    }
}
