import Foundation

enum CarouselPrefetch {
    /// Indices within `[0, count)` to prefetch around `current`, excluding
    /// `current` itself. Walks outward one step at a time so the nearest
    /// neighbors are at the head of the returned array — callers that
    /// submit tasks in order get the most-likely-next slides first.
    static func indicesToPrefetch(around current: Int, count: Int, radius: Int) -> [Int] {
        guard count > 1, radius > 0 else { return [] }
        var out: [Int] = []
        for delta in 1...radius {
            let next = current + delta
            if next < count { out.append(next) }
            let prev = current - delta
            if prev >= 0 { out.append(prev) }
        }
        return out
    }
}
