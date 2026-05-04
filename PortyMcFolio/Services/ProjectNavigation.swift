import Foundation

/// Pure, view-free navigation math for the project overview (grid and table).
///
/// Given a current highlighted ID and the visible, ordered list, compute the next ID
/// for an arrow-key move. Matches Finder semantics: stop at edges (no wrap), soft-clamp
/// when a stride overshoots so the last item is always reachable.
enum ProjectNavigation {
    enum Direction {
        case up, down, left, right
    }

    enum Mode {
        case grid, table
    }

    /// Returns the new highlight ID for an arrow press.
    ///
    /// - `current`: the currently-highlighted ID, or nil if nothing is highlighted.
    /// - `list`: the ordered IDs the user sees (year-desc for grid, sort-order for table).
    /// - `direction`: which arrow was pressed.
    /// - `columnCount`: grid columns (ignored in table mode; `0` is treated as `1`).
    /// - `mode`: grid or table. Table ignores horizontal arrows.
    ///
    /// Returns nil only when `current` was nil AND the direction is ↑/← (nothing to do).
    /// When `current` is non-nil and the move would overshoot, returns the clamped edge ID.
    /// If `current` is already at the clamped edge (or list is empty), returns `current` unchanged.
    static func nextHighlightID(
        current: String?,
        in list: [String],
        direction: Direction,
        columnCount: Int,
        mode: Mode
    ) -> String? {
        guard !list.isEmpty else { return current }

        let stride: Int
        switch mode {
        case .grid:
            stride = (direction == .up || direction == .down) ? max(1, columnCount) : 1
        case .table:
            if direction == .left || direction == .right { return current }
            stride = 1
        }

        let idx: Int? = current.flatMap { list.firstIndex(of: $0) }

        if let idx {
            let delta = (direction == .down || direction == .right) ? stride : -stride
            let clamped = max(0, min(list.count - 1, idx + delta))
            return clamped == idx ? current : list[clamped]
        } else {
            switch direction {
            case .down, .right: return list.first
            case .up, .left:    return current
            }
        }
    }
}

extension ProjectNavigation {
    /// Year-aware (grouped) grid nav. Each sub-array in `groups` is one year's IDs
    /// in display order; `groups` themselves are in display order (typically year-desc).
    ///
    /// - ←/→ operates on the flat concatenation of all groups (row-wrap across years).
    /// - ↑/↓ operates within a group by `columnCount`, preserving column across year
    ///   boundaries. If the target column doesn't exist in the destination row
    ///   (partial last row, or shorter neighboring group), soft-clamps to the last
    ///   card in that row.
    /// - Stop at edges: ↑ from the first row of the first group, ↓ from the last row
    ///   of the last group — both no-op (return `current`).
    /// - Nil/stale current: ↓/→ picks first flat ID; ↑/← returns `current`.
    /// - `columnCount: 0` treated as `1`.
    static func nextHighlightIDInGroupedGrid(
        current: String?,
        groups: [[String]],
        direction: Direction,
        columnCount: Int
    ) -> String? {
        let cols = max(1, columnCount)
        let flat = groups.flatMap { $0 }
        guard !flat.isEmpty else { return current }

        // Locate current in groups; stale/nil fall through to the "nothing highlighted" path.
        var currentGroupIdx: Int? = nil
        var currentItemIdx: Int? = nil
        if let id = current {
            for (g, ids) in groups.enumerated() {
                if let i = ids.firstIndex(of: id) {
                    currentGroupIdx = g
                    currentItemIdx = i
                    break
                }
            }
        }

        guard let gIdx = currentGroupIdx, let iIdx = currentItemIdx else {
            switch direction {
            case .down, .right: return flat.first
            case .up, .left:    return current
            }
        }

        // ←/→: flat-list move, stop at edges.
        if direction == .left || direction == .right {
            let flatIdx = flat.firstIndex(of: groups[gIdx][iIdx]) ?? 0
            let delta = direction == .right ? 1 : -1
            let target = max(0, min(flat.count - 1, flatIdx + delta))
            return target == flatIdx ? current : flat[target]
        }

        // ↑/↓: year-aware.
        let col = iIdx % cols
        let row = iIdx / cols
        let group = groups[gIdx]

        if direction == .down {
            let targetRow = row + 1
            let lastRowOfCurrent = (group.count - 1) / cols
            if targetRow <= lastRowOfCurrent {
                let targetIdx = min(targetRow * cols + col, group.count - 1)
                return group[targetIdx]
            }
            // Move to next non-empty group, preserving column (clamp if shorter).
            var nextG = gIdx + 1
            while nextG < groups.count && groups[nextG].isEmpty { nextG += 1 }
            if nextG < groups.count {
                let ng = groups[nextG]
                let targetIdx = min(col, ng.count - 1)
                return ng[targetIdx]
            }
            return current  // at very bottom
        } else { // .up
            if row > 0 {
                let targetIdx = (row - 1) * cols + col
                return group[targetIdx]
            }
            var prevG = gIdx - 1
            while prevG >= 0 && groups[prevG].isEmpty { prevG -= 1 }
            if prevG >= 0 {
                let pg = groups[prevG]
                let lastRowOfPrev = (pg.count - 1) / cols
                let targetIdx = min(lastRowOfPrev * cols + col, pg.count - 1)
                return pg[targetIdx]
            }
            return current  // at very top
        }
    }
}
