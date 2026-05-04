import Foundation

enum TeaserOutcome: Equatable {
    case unchanged
    case repaired(newPath: String)
    case orphaned
}

/// Pure reconciliation for a project's `teaser` frontmatter field against the
/// current on-disk file tree. Used by `ProjectReconciler` as a safety net for
/// external (Finder-driven) renames.
///
/// Mirrors `FavoritesReconciliation`'s basename-match algorithm:
/// 1. Empty, absolute (`/…`), or dot-dot (`..`) paths → `.unchanged`.
/// 2. Teaser path still resolves on disk → `.unchanged`.
/// 3. Exactly one file on disk shares the teaser's lowercased basename → `.repaired(newPath:)`.
/// 4. Zero or multiple basename matches → `.orphaned`.
enum TeaserReconciliation {
    static func reconcile(
        teaser: String,
        onDiskPaths: Set<String>
    ) -> TeaserOutcome {
        guard !teaser.isEmpty else { return .unchanged }
        if teaser.hasPrefix("/") || teaser.contains("..") { return .unchanged }
        if onDiskPaths.contains(teaser) { return .unchanged }

        let basename = (teaser as NSString).lastPathComponent.lowercased()
        let candidates = onDiskPaths.filter {
            ($0 as NSString).lastPathComponent.lowercased() == basename
        }
        guard candidates.count == 1, let new = candidates.first else {
            return .orphaned
        }
        return .repaired(newPath: new)
    }
}
