import AppKit
import ImageIO
import QuickLookThumbnailing

/// Loads an `NSImage` representation of a file at approximately the given
/// size.
///
/// Fast path (the common case): for JPG/PNG/HEIC/GIF/TIFF/BMP, decode
/// directly with `CGImageSource` + `kCGImageSourceThumbnailMaxPixelSize`.
/// This is several times faster than `QLThumbnailGenerator` because Quick
/// Look is a universal thumbnailer that builds representations for any file
/// type (including PDFs, videos, and icon metadata); skipping that overhead
/// takes JPG decode from hundreds of milliseconds down to tens.
///
/// SVG bypasses both paths — `QLThumbnailGenerator` returns nil for many
/// SVG files and `CGImageSource` doesn't speak SVG — and loads via
/// `NSImage(contentsOf:)` directly (supported natively on macOS 14+).
///
/// Fallback: anything else (PDF, video frames, RAW with extensions we don't
/// list, unknown types) goes through Quick Look.
///
/// Results are cached by (url, integer-rounded size) in a bounded `NSCache`
/// so revisiting a slide/card/thumb doesn't re-do the decode. macOS evicts
/// under memory pressure.
enum ImageThumbnail {

    static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 200
        return c
    }()

    static func cacheKey(url: URL, size: CGSize) -> NSString {
        "\(url.absoluteString)|\(Int(size.width.rounded()))x\(Int(size.height.rounded()))" as NSString
    }

    /// Standard raster formats where `CGImageSource` gives us a fast
    /// downsampled decode. Anything else goes through Quick Look.
    private static let fastPathExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "tif", "bmp"
    ]

    static func load(url: URL, size: CGSize) async -> NSImage? {
        let key = cacheKey(url: url, size: size)
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let ext = url.pathExtension.lowercased()
        let image: NSImage?

        if ext == "svg" {
            image = NSImage(contentsOf: url)
        } else if fastPathExtensions.contains(ext),
                  let cg = downsampledCGImage(url: url, maxPixel: max(size.width, size.height) * 2.0) {
            image = NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height))
        } else {
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: size,
                scale: 2.0,
                representationTypes: .thumbnail
            )
            image = (try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request))?.nsImage
        }

        if let image {
            cache.setObject(image, forKey: key)
        }
        return image
    }

    /// Synchronous ImageIO decode. Safe to call from `load` because `load`
    /// is non-isolated `async` — `await`ing it from `@MainActor` hops off
    /// the main thread for the duration of this call.
    private static func downsampledCGImage(url: URL, maxPixel: CGFloat) -> CGImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
        else { return nil }
        return cg
    }
}
