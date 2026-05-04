import Foundation

final class PortfolioStore {
    let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    /// Scan the root folder for valid project directories, load their READMEs, sort by year desc
    func scanProjects() throws -> [Project] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var projects: [Project] = []

        for url in contents {
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues?.isDirectory == true else { continue }

            let folderName = url.lastPathComponent

            var project: Project
            do {
                project = try Project.from(folderName: folderName, rootURL: rootURL)
            } catch {
                // Folder name doesn't match the {year}_{slug}_{uid} pattern — not
                // necessarily a problem (it could be a user's own non-project folder),
                // so don't log noisily here.
                continue
            }

            do {
                try project.loadReadme()
            } catch {
                // This is a real signal: the folder name parses as a project but
                // its markdown file is missing/corrupt/locked. Log and skip so the
                // user has a trail when a project "disappears."
                AppLogger.portfolio.error("loadReadme failed for \(folderName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                continue
            }

            projects.append(project)
        }

        return projects.sorted { $0.year > $1.year }
    }

    /// List all files in a project folder except the project markdown file
    func listFiles(in project: Project) throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: project.folderURL,
            includingPropertiesForKeys: nil,
            options: []
        )

        let projectFileName = "\(project.folderName).md"
        return contents.filter { name in
            name.lastPathComponent != "README.md" && name.lastPathComponent != projectFileName
        }
    }
}
