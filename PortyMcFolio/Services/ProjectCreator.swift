import Foundation

enum ProjectCreator {

    enum CreationError: Error {
        case directoryCreationFailed(URL)
        case readmeWriteFailed(URL)
    }

    static func create(
        title: String,
        year: Int? = nil,
        client: String,
        tags: [String],
        rootURL: URL,
        body: String,
        date: Date = Date(),
        dateEnd: Date? = nil
    ) throws -> Project {
        // 1. Generate an 8-char hex UID from UUID
        let uid = UID.generate()

        // 2. Use provided year or current year
        let year = year ?? Calendar.current.component(.year, from: Date())

        // 3. Build folder name using Project.folderName(title:year:uid:)
        let folder = Project.folderName(title: title, year: year, uid: uid)

        // 4. Create the directory
        let folderURL = rootURL.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        // 5. Create project file ({folder}.md) with frontmatter
        let frontmatter = ParsedFrontmatter(
            title: title,
            date: date,
            dateEnd: dateEnd,
            tags: tags,
            client: client,
            status: .empty,
            body: body,
            teaser: ""
        )
        let readmeContent = FrontmatterParser.serialize(frontmatter: frontmatter)
        let projectFileURL = folderURL.appendingPathComponent("\(folder).md")
        try readmeContent.write(to: projectFileURL, atomically: true, encoding: .utf8)

        // 6. Return a Project loaded via Project.from() + loadReadme()
        var project = try Project.from(folderName: folder, rootURL: rootURL)
        try project.loadReadme()
        return project
    }
}
