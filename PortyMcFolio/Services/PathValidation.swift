import Foundation

enum PathValidation {
    /// Returns true if `fileURL` resolves to a path inside `folderURL`.
    /// Resolves symlinks to prevent traversal via symbolic links.
    static func isContained(fileURL: URL, within folderURL: URL) -> Bool {
        let filePath = fileURL.standardizedFileURL.resolvingSymlinksInPath().path
        let folderPath = folderURL.standardizedFileURL.resolvingSymlinksInPath().path
        // Ensure folder path ends with / so "/foo/bar" doesn't match "/foo/barbaz"
        let prefix = folderPath.hasSuffix("/") ? folderPath : folderPath + "/"
        return filePath.hasPrefix(prefix)
    }
}
