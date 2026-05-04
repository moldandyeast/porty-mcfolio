import AppKit

enum ClipboardPaste {

    /// File URLs on the system pasteboard, filtered to regular files.
    /// Folders, symlinks, and non-existent or non-file URLs are dropped.
    static func readFileURLs(from pb: NSPasteboard = .general) -> [URL] {
        let urls = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []

        return urls.filter { url in
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return exists && !isDir.boolValue
        }
    }

    /// PNG bytes from any image representation on the pasteboard.
    /// Returns nil if no image is present or if encoding fails.
    static func readImageData(from pb: NSPasteboard = .general) -> Data? {
        guard let image = NSImage(pasteboard: pb),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }

    /// Filename for a pasted image, using second-resolution local time.
    /// Example: `pasted-2026-04-22-143022.png`.
    static func pastedImageName(date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return "pasted-\(f.string(from: date)).png"
    }
}
