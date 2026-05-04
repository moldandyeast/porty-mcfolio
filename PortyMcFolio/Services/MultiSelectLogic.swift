// PortyMcFolio/Services/MultiSelectLogic.swift
import Foundation

enum MultiSelectLogic {
    /// Inclusive slice of `sequence` from `a` to `b` (order-independent).
    /// Returns `[]` if either endpoint isn't in `sequence`.
    static func rangeBetween(
        _ a: GallerySelection,
        _ b: GallerySelection,
        in sequence: [GallerySelection]
    ) -> [GallerySelection] {
        guard let ia = sequence.firstIndex(of: a),
              let ib = sequence.firstIndex(of: b) else { return [] }
        let lo = min(ia, ib)
        let hi = max(ia, ib)
        return Array(sequence[lo...hi])
    }
}

extension MultiSelectLogic {
    enum MoveValidation: Equatable {
        case allowed
        case rejected(reason: MoveRejectionReason)
    }

    enum MoveRejectionReason: Equatable {
        case targetInSelection
        case targetIsDescendantOfSelection
    }

    /// Validates moving `items` into the folder `target`.
    /// Path checks use prefix semantics on `standardizedFileURL.path`.
    static func validateMove(items: [URL], into target: URL) -> MoveValidation {
        let targetPath = target.standardizedFileURL.path
        for item in items {
            let itemPath = item.standardizedFileURL.path
            if itemPath == targetPath {
                return .rejected(reason: .targetInSelection)
            }
            if targetPath.hasPrefix(itemPath + "/") {
                return .rejected(reason: .targetIsDescendantOfSelection)
            }
        }
        return .allowed
    }
}

extension MultiSelectLogic {
    enum FavoriteAction: Equatable {
        case favoriteAll
        case unfavoriteAll
        case noop
    }

    /// Finder-style majority rule: if every selected file is already in
    /// `favorites`, the action is `.unfavoriteAll`. Otherwise `.favoriteAll`.
    /// Paths in `favorites` are project-root-relative; selected URLs are
    /// converted to the same form via `projectRoot`.
    static func favoriteToggleDirection(
        selected: [URL],
        projectRoot: URL,
        favorites: [String]
    ) -> FavoriteAction {
        guard !selected.isEmpty else { return .noop }
        let rootPath = projectRoot.standardizedFileURL.path
        let selectedRelative: [String] = selected.compactMap { url in
            let p = url.standardizedFileURL.path
            guard p.hasPrefix(rootPath + "/") else { return nil }
            return String(p.dropFirst(rootPath.count + 1))
        }
        guard !selectedRelative.isEmpty else { return .noop }
        let favSet = Set(favorites)
        let allFavorited = selectedRelative.allSatisfy { favSet.contains($0) }
        return allFavorited ? .unfavoriteAll : .favoriteAll
    }
}
