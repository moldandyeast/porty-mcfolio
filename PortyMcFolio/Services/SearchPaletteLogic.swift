import Foundation

enum SearchPaletteLogic {
    /// Clamps a keyboard-nav selection index to stay valid as the result list changes.
    /// Empty results → 0. In-bounds → unchanged. Out-of-bounds → last valid index.
    static func clampedIndex(current: Int, resultCount: Int) -> Int {
        guard resultCount > 0 else { return 0 }
        return max(0, min(current, resultCount - 1))
    }
}
