import Foundation

struct FavoritesResult: Equatable {
    let reconciled: [String]
    /// Favorites entries that had no single-match basename on disk —
    /// 0 matches OR ≥2 matches (ambiguous). Duplicates in the input that
    /// resolve to the same path are NOT counted as drops.
    let droppedCount: Int
}

/// Pure-function reconciliation of a project's favorites against the current
/// on-disk file tree. Used by `ProjectReconciler` as a safety net for external
/// (Finder-driven) moves the app's in-app hooks didn't see.
///
/// Algorithm, per entry in order:
/// 1. If the path still exists on disk, keep it.
/// 2. Otherwise, look for a file with the same basename (case-insensitive)
///    elsewhere on disk. Exactly one match → update to the new path.
/// 3. Zero matches → drop the entry (external delete or rename).
/// 4. Multiple matches → drop the entry (ambiguous; safer than guessing).
///
/// Result is de-duplicated (first occurrence wins) while preserving original
/// order. `droppedCount` counts cases 3 and 4 only.
enum FavoritesReconciliation {
    static func reconcile(
        favorites: [String],
        onDiskPaths: Set<String>
    ) -> FavoritesResult {
        var byBasename: [String: [String]] = [:]
        for path in onDiskPaths {
            let basename = (path as NSString).lastPathComponent.lowercased()
            byBasename[basename, default: []].append(path)
        }

        var reconciled: [String] = []
        var seen: Set<String> = []
        var droppedCount = 0

        for fav in favorites {
            let resolved: String?
            if onDiskPaths.contains(fav) {
                resolved = fav
            } else {
                let basename = (fav as NSString).lastPathComponent.lowercased()
                let candidates = byBasename[basename] ?? []
                resolved = candidates.count == 1 ? candidates.first : nil
            }

            if let path = resolved {
                if !seen.contains(path) {
                    reconciled.append(path)
                    seen.insert(path)
                }
                // else: duplicate — dedup silently, NOT a drop.
            } else {
                droppedCount += 1
            }
        }

        return FavoritesResult(reconciled: reconciled, droppedCount: droppedCount)
    }
}
