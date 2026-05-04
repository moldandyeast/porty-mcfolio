import Foundation

enum ProjectError: Error, LocalizedError {
    case invalidFolderName(String)

    var errorDescription: String? {
        switch self {
        case .invalidFolderName(let name):
            return "Invalid project folder name: \(name). Expected format: {4-digit year}_{slug}_{8-char hex uid}"
        }
    }
}

/// Transport struct for the When metadata. Used as a binding for `WhenPicker`
/// and as a parameter on `AppState.updateProjectMetadata`.
///
/// Two states:
/// - **Year only** — `dateEnd == nil`. The project lives under `yearOnlyYear`.
/// - **Range** — `dateEnd != nil`. `date` is the range start; folder year derives
///   from the year of `dateEnd`.
struct WhenValue: Equatable {
    /// Range start anchor when `dateEnd != nil`. Otherwise unused (legacy/preserved).
    var date: Date
    /// Range end. `nil` ⇒ year-only.
    var dateEnd: Date?
    /// User-picked year when in year-only mode. `nil` and ignored when `dateEnd != nil`.
    var yearOnlyYear: Int?

    var isYearOnly: Bool { dateEnd == nil }
    var isRange: Bool { dateEnd != nil }

    static func yearOnly(year: Int, anchor: Date) -> WhenValue {
        WhenValue(date: anchor, dateEnd: nil, yearOnlyYear: year)
    }
}

struct Project: Identifiable, Equatable {
    let uid: String
    let year: Int
    let folderName: String
    let folderURL: URL
    var title: String
    var date: Date
    var dateEnd: Date? = nil
    var tags: [String]
    var client: String
    var status: ProjectStatus
    var body: String
    var teaser: String
    var favorites: [String] = []
    var hidden: Bool = false
    /// Cached relative file paths (excluding README.md and link files) for fallback search,
    /// populated by refreshProjects().
    var filePaths: [String] = []
    /// mtime of the frontmatter file ({folderName}.md or README.md) at last sync.
    /// nil for projects loaded only from cache and not yet validated against disk.
    var frontmatterMTime: Date? = nil

    var id: String { uid }

    /// Project file: {year}_{slug}_{uid}.md (same stem as folder).
    /// Falls back to README.md for backward compatibility with older projects.
    var readmeURL: URL {
        let projectFile = folderURL.appendingPathComponent("\(folderName).md")
        if FileManager.default.fileExists(atPath: projectFile.path) {
            return projectFile
        }
        let legacy = folderURL.appendingPathComponent("README.md")
        if FileManager.default.fileExists(atPath: legacy.path) {
            return legacy
        }
        // Default to new convention for new projects
        return projectFile
    }

    /// Build the standard folder name: {Year}_{slug}_{uid}
    static func folderName(title: String, year: Int, uid: String) -> String {
        "\(year)_\(Slug.underscoreFrom(title))_\(uid)"
    }

    /// Parse a project from its folder name and root URL.
    /// Folder must match pattern: {4-digit year}_{slug}_{8-char hex uid}
    static func from(folderName: String, rootURL: URL) throws -> Project {
        let components = folderName.components(separatedBy: "_")

        // Need at minimum: year + at least one slug part + uid = 3 parts
        guard components.count >= 3 else {
            throw ProjectError.invalidFolderName(folderName)
        }

        // First component must be a 4-digit year
        guard let year = Int(components[0]), components[0].count == 4, year >= 1000, year <= 9999 else {
            throw ProjectError.invalidFolderName(folderName)
        }

        // Last component must be an 8-character hex UID
        let uid = components.last!
        guard uid.count == 8, uid.allSatisfy({ $0.isHexDigit }) else {
            throw ProjectError.invalidFolderName(folderName)
        }

        let folderURL = rootURL.appendingPathComponent(folderName)

        return Project(
            uid: uid,
            year: year,
            folderName: folderName,
            folderURL: folderURL,
            title: "",
            date: Date(),
            dateEnd: nil,
            tags: [],
            client: "",
            status: .empty,
            body: "",
            teaser: "",
            favorites: []
        )
    }

    /// Load frontmatter from README.md on disk into this project.
    mutating func loadReadme() throws {
        let content = try String(contentsOf: readmeURL, encoding: .utf8)
        let parsed = try FrontmatterParser.parse(content)
        title = parsed.title
        date = parsed.date
        dateEnd = parsed.dateEnd
        tags = parsed.tags
        client = parsed.client
        status = parsed.status
        body = parsed.body
        teaser = parsed.teaser
        favorites = parsed.favorites
        hidden = parsed.hidden
    }
}
