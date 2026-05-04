import Foundation

/// Classifies a file URL as image / video / audio by delegating to
/// `GallerySort.category(for:)`. Single source of truth for extension
/// classification — if GallerySort gains or changes an extension, the
/// carousel picks it up automatically.
enum MediaKind: String {
    case image
    case video
    case audio

    static func from(url: URL) -> MediaKind? {
        switch GallerySort.category(for: url) {
        case .image: return .image
        case .video: return .video
        case .audio: return .audio
        default:     return nil
        }
    }

    static func isMedia(url: URL) -> Bool {
        from(url: url) != nil
    }
}
