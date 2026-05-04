import Foundation

enum GallerySort {
    enum SortKey: String, CaseIterable {
        case name
        case kind
    }

    enum Category: Int, Comparable {
        case image = 0
        case video = 1
        case audio = 2
        case doc = 3
        case threeD = 4
        case other = 5

        static func < (lhs: Category, rhs: Category) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    struct Result: Equatable {
        let folders: [URL]
        let files: [URL]
    }

    static func category(for url: URL) -> Category {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "svg", "webp", "avif", "heic", "tiff":
            return .image
        case "mp4", "mov", "avi", "mkv", "m4v":
            return .video
        case "mp3", "wav", "aac", "m4a", "flac", "aiff":
            return .audio
        case "pdf", "md", "txt", "rtf", "doc", "docx":
            return .doc
        case "usdz", "obj", "stl", "dae", "scn":
            return .threeD
        default:
            return .other
        }
    }

    /// SF Symbol name for the fallback icon used when a thumbnail can't be
    /// produced for a file, or unconditionally for a folder. Keeps the grid
    /// and list views visually consistent.
    static func fallbackSymbol(for url: URL, isFolder: Bool = false) -> String {
        if isFolder { return "folder.fill" }
        switch category(for: url) {
        case .image:  return "photo"
        case .video:  return "film"
        case .audio:  return "waveform"
        case .doc:    return "doc.richtext"
        case .threeD: return "cube"
        case .other:  return "doc"
        }
    }

    static func sort(
        files: [URL],
        folders: [URL],
        by key: SortKey,
        ascending: Bool
    ) -> Result {
        let folderCmp: (URL, URL) -> Bool = { a, b in
            a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
        }
        // Folders always sort by name. Reverse direction flips within-group order.
        let sortedFolders = folders.sorted { ascending ? folderCmp($0, $1) : folderCmp($1, $0) }

        let fileCmp: (URL, URL) -> Bool
        switch key {
        case .name:
            fileCmp = { a, b in
                a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
            }
        case .kind:
            fileCmp = { a, b in
                let ca = category(for: a)
                let cb = category(for: b)
                if ca != cb { return ca < cb }
                return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
            }
        }
        let sortedFiles = files.sorted { ascending ? fileCmp($0, $1) : fileCmp($1, $0) }

        return Result(folders: sortedFolders, files: sortedFiles)
    }

    // MARK: Persistence

    static func encode(key: SortKey, ascending: Bool) -> String {
        "\(key.rawValue)-\(ascending ? "asc" : "desc")"
    }

    static func decode(raw: String) -> (key: SortKey, ascending: Bool)? {
        let parts = raw.split(separator: "-", maxSplits: 1)
        guard parts.count == 2,
              let key = SortKey(rawValue: String(parts[0])) else { return nil }
        switch parts[1] {
        case "asc": return (key, true)
        case "desc": return (key, false)
        default: return nil
        }
    }
}
