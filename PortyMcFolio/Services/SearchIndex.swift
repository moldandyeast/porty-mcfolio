import Foundation
import GRDB

final class SearchIndex {
    private let db: DatabaseQueue
    private static let schemaVersion = "3"

    /// Exposes the underlying DatabaseQueue so the reconciler can wrap cache + FTS
    /// writes in a single transaction. Do not use from views.
    func databaseQueueForReconciler() -> DatabaseQueue { db }

    init() throws {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("PortyMcFolio", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("search.sqlite")
        db = try DatabaseQueue(path: dbURL.path)

        try migrate()
    }

    /// In-memory database for testing
    init(inMemory: Bool) throws {
        db = try DatabaseQueue()
        try migrate()
    }

    private func migrate() throws {
        try db.write { conn in
            try conn.execute(sql: """
                CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)
                """)

            let row = try Row.fetchOne(conn, sql: "SELECT value FROM meta WHERE key = 'schema_version'")
            let currentVersion = row?["value"] as? String

            if currentVersion != Self.schemaVersion {
                try conn.execute(sql: "DROP TABLE IF EXISTS search_fts")
                try conn.execute(sql: "DROP TABLE IF EXISTS project_meta")
            }

            // Always ensure FTS table exists — guards against corruption/deletion
            try conn.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS search_fts USING fts5(
                    type UNINDEXED,
                    entity_id UNINDEXED,
                    parent_uid UNINDEXED,
                    primary_text,
                    secondary_text,
                    body,
                    tokenize='unicode61 remove_diacritics 2'
                )
                """)

            if currentVersion != Self.schemaVersion {
                try conn.execute(
                    sql: "INSERT OR REPLACE INTO meta (key, value) VALUES ('schema_version', ?)",
                    arguments: [Self.schemaVersion]
                )
            }
        }
    }

    // MARK: - Rebuild (single transaction)

    /// Clear and rebuild the entire index in one transaction.
    /// This is atomic — the index is either fully rebuilt or unchanged.
    func rebuild(
        projects: [Project],
        fileEntries: [(project: Project, fileName: String, relativePath: String, fileNameNoExt: String)],
        linkEntries: [(project: Project, link: LinkItem)],
        tagCounts: [String: Int]
    ) throws {
        try db.write { conn in
            try conn.execute(sql: "DELETE FROM search_fts")

            for project in projects {
                let bodyContent = [project.tags.joined(separator: " "), project.status.rawValue, project.body]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")

                try conn.execute(
                    sql: """
                        INSERT INTO search_fts (type, entity_id, parent_uid, primary_text, secondary_text, body)
                        VALUES ('project', ?, '', ?, ?, ?)
                        """,
                    arguments: [project.uid, project.title, project.client, bodyContent]
                )
            }

            for entry in fileEntries {
                try Self.insertFileRow(
                    conn,
                    fileName: entry.fileName,
                    relativePath: entry.relativePath,
                    fileNameNoExt: entry.fileNameNoExt,
                    parentUID: entry.project.uid,
                    parentTitle: entry.project.title
                )
            }

            for entry in linkEntries {
                try Self.insertLinkRow(
                    conn,
                    link: entry.link,
                    parentUID: entry.project.uid,
                    parentTitle: entry.project.title
                )
            }

            for (tag, count) in tagCounts {
                try conn.execute(
                    sql: """
                        INSERT INTO search_fts (type, entity_id, parent_uid, primary_text, secondary_text, body)
                        VALUES ('tag', ?, '', ?, ?, '')
                        """,
                    arguments: [tag, tag, "\(count) project\(count == 1 ? "" : "s")"]
                )
            }
        }
    }

    // MARK: - Individual operations (used by tests and targeted updates)

    func indexProject(
        uid: String, title: String, tags: [String], client: String,
        status: String, body: String, folderName: String
    ) throws {
        try db.write { conn in
            try conn.execute(
                sql: "DELETE FROM search_fts WHERE type = 'project' AND entity_id = ?",
                arguments: [uid]
            )
            let bodyContent = [tags.joined(separator: " "), status, body]
                .filter { !$0.isEmpty }.joined(separator: "\n")
            try conn.execute(
                sql: """
                    INSERT INTO search_fts (type, entity_id, parent_uid, primary_text, secondary_text, body)
                    VALUES ('project', ?, '', ?, ?, ?)
                    """,
                arguments: [uid, title, client, bodyContent]
            )
        }
    }

    func indexFile(
        relativePath: String, fileName: String, fileNameNoExt: String,
        parentUID: String, parentTitle: String
    ) throws {
        try db.write { conn in
            try conn.execute(
                sql: """
                    INSERT INTO search_fts (type, entity_id, parent_uid, primary_text, secondary_text, body)
                    VALUES ('file', ?, ?, ?, ?, ?)
                    """,
                arguments: [relativePath, parentUID, fileName, parentTitle, fileNameNoExt]
            )
        }
    }

    func indexLink(
        uid: String, url: String, host: String, title: String,
        annotation: String, parentUID: String, parentTitle: String
    ) throws {
        try db.write { conn in
            let bodyContent = [url, annotation].filter { !$0.isEmpty }.joined(separator: "\n")
            let secondary = [host, parentTitle].filter { !$0.isEmpty }.joined(separator: " · ")
            try conn.execute(
                sql: """
                    INSERT INTO search_fts (type, entity_id, parent_uid, primary_text, secondary_text, body)
                    VALUES ('link', ?, ?, ?, ?, ?)
                    """,
                arguments: [uid, parentUID, title.isEmpty ? host : title, secondary, bodyContent]
            )
        }
    }

    func indexTag(name: String, projectCount: Int) throws {
        try db.write { conn in
            try conn.execute(
                sql: """
                    INSERT INTO search_fts (type, entity_id, parent_uid, primary_text, secondary_text, body)
                    VALUES ('tag', ?, '', ?, ?, '')
                    """,
                arguments: [name, name, "\(projectCount) project\(projectCount == 1 ? "" : "s")"]
            )
        }
    }

    func clearAll() throws {
        try db.write { conn in
            try conn.execute(sql: "DELETE FROM search_fts")
        }
    }

    /// Atomically wipe both `search_fts` and `project_meta` in a single transaction.
    /// Used by `AppState.setRoot` when the user switches portfolios to prevent
    /// stale cross-portfolio data from mixing in a half-wiped state.
    ///
    /// Assumes `project_meta` exists (created via `ProjectMetadataCache.migrate`,
    /// which has always run by the time `setRoot` calls this).
    func wipeAllForPortfolioSwitch() throws {
        try db.write { conn in
            try conn.execute(sql: "DELETE FROM search_fts")
            try conn.execute(sql: "DELETE FROM project_meta")
        }
    }

    // MARK: - Last-portfolio-root persistence (in the existing meta table)

    func lastPortfolioRoot() -> String? {
        try? db.read { conn in
            try Row.fetchOne(
                conn,
                sql: "SELECT value FROM meta WHERE key = 'portfolio_root_path'"
            )?["value"] as? String
        } ?? nil
    }

    func setLastPortfolioRoot(_ path: String) throws {
        try db.write { conn in
            try conn.execute(
                sql: "INSERT OR REPLACE INTO meta (key, value) VALUES ('portfolio_root_path', ?)",
                arguments: [path]
            )
        }
    }

    func removeProject(uid: String) throws {
        try db.write { conn in
            try Self.deleteAllRowsForProject(conn, uid: uid)
        }
    }

    // MARK: - Incremental updates (in-transaction)

    /// Replace all FTS rows for a single project (project + files + links).
    /// Tag rows are NOT updated here — call `rebuildTags(from:)` once per batch instead.
    /// Caller wraps this in `db.write { conn in ... }` together with cache.upsertWithin
    /// so cache + FTS commit atomically.
    func upsertProjectWithin(
        _ conn: Database,
        meta: CachedProjectMeta,
        fileEntries: [(fileName: String, relativePath: String, fileNameNoExt: String)],
        linkEntries: [LinkItem]
    ) throws {
        // Drop existing project + file + link rows for this uid
        try Self.deleteAllRowsForProject(conn, uid: meta.uid)

        // Insert project row from cached meta (no need to re-read the .md file)
        let bodyContent = [meta.tags.joined(separator: " "), meta.status.rawValue, meta.body]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        try conn.execute(
            sql: """
                INSERT INTO search_fts (type, entity_id, parent_uid, primary_text, secondary_text, body)
                VALUES ('project', ?, '', ?, ?, ?)
                """,
            arguments: [meta.uid, meta.title, meta.client, bodyContent]
        )

        for f in fileEntries {
            try Self.insertFileRow(
                conn,
                fileName: f.fileName,
                relativePath: f.relativePath,
                fileNameNoExt: f.fileNameNoExt,
                parentUID: meta.uid,
                parentTitle: meta.title
            )
        }

        for link in linkEntries {
            try Self.insertLinkRow(conn, link: link, parentUID: meta.uid, parentTitle: meta.title)
        }
    }

    /// Append file + link FTS rows for a project that already has its project row in FTS.
    /// Used after lazy populateFiles so file/link search becomes available for that project.
    /// Existing file/link rows for the project are cleared first (idempotent).
    func appendFilesAndLinks(
        forProjectUID uid: String,
        fileEntries: [(fileName: String, relativePath: String, fileNameNoExt: String)],
        linkEntries: [LinkItem]
    ) throws {
        try db.write { conn in
            try conn.execute(
                sql: "DELETE FROM search_fts WHERE parent_uid = ? AND type IN ('file', 'link')",
                arguments: [uid]
            )

            // Resolve project title for link secondary_text
            let titleRow = try Row.fetchOne(
                conn,
                sql: "SELECT primary_text FROM search_fts WHERE type = 'project' AND entity_id = ?",
                arguments: [uid]
            )
            let projectTitle: String
            if let row = titleRow, let title = row["primary_text"] as? String {
                projectTitle = title
            } else {
                AppLogger.search.warning("appendFilesAndLinks: project row missing for uid=\(uid, privacy: .public); link/file rows will have empty secondary_text")
                projectTitle = ""
            }

            for f in fileEntries {
                try Self.insertFileRow(
                    conn,
                    fileName: f.fileName,
                    relativePath: f.relativePath,
                    fileNameNoExt: f.fileNameNoExt,
                    parentUID: uid,
                    parentTitle: projectTitle
                )
            }
            for link in linkEntries {
                try Self.insertLinkRow(conn, link: link, parentUID: uid, parentTitle: projectTitle)
            }
        }
    }

    /// Recompute all 'tag' FTS rows from the cache. O(#tags). Call once per reconciliation batch.
    func rebuildTags(from cache: ProjectMetadataCache) throws {
        let counts = try cache.aggregateTagCounts()
        try db.write { conn in
            try conn.execute(sql: "DELETE FROM search_fts WHERE type = 'tag'")
            for (tag, count) in counts {
                try conn.execute(
                    sql: """
                        INSERT INTO search_fts (type, entity_id, parent_uid, primary_text, secondary_text, body)
                        VALUES ('tag', ?, '', ?, ?, '')
                        """,
                    arguments: [tag, tag, "\(count) project\(count == 1 ? "" : "s")"]
                )
            }
        }
    }

    // MARK: - Test-only helper

    #if DEBUG
    /// Test-only wrapper that calls upsertProjectWithin inside its own transaction.
    /// Production code should call upsertProjectWithin within a shared db.write block.
    func testHelper_upsertProjectInOwnTransaction(
        meta: CachedProjectMeta,
        fileEntries: [(fileName: String, relativePath: String, fileNameNoExt: String)],
        linkEntries: [LinkItem]
    ) throws {
        try db.write { conn in
            try upsertProjectWithin(conn, meta: meta, fileEntries: fileEntries, linkEntries: linkEntries)
        }
    }
    #endif

    /// Delete a project's project + file + link rows from FTS, in a caller-controlled
    /// transaction. Pair with `cache.removeWithin` for atomic cache + FTS removal.
    func removeProjectWithin(_ conn: Database, uid: String) throws {
        try Self.deleteAllRowsForProject(conn, uid: uid)
    }

    // MARK: - Internal SQL helpers

    /// Delete the project row AND all child (file/link) rows for a given uid.
    /// Encodes the convention: project rows have `parent_uid = ''`, child rows
    /// have `parent_uid = <uid>`. Both DELETE statements are required.
    private static func deleteAllRowsForProject(_ conn: Database, uid: String) throws {
        try conn.execute(
            sql: "DELETE FROM search_fts WHERE type = 'project' AND entity_id = ?",
            arguments: [uid]
        )
        try conn.execute(
            sql: "DELETE FROM search_fts WHERE parent_uid = ?",
            arguments: [uid]
        )
    }

    /// Insert one file row.
    private static func insertFileRow(
        _ conn: Database,
        fileName: String,
        relativePath: String,
        fileNameNoExt: String,
        parentUID: String,
        parentTitle: String
    ) throws {
        try conn.execute(
            sql: """
                INSERT INTO search_fts (type, entity_id, parent_uid, primary_text, secondary_text, body)
                VALUES ('file', ?, ?, ?, ?, ?)
                """,
            arguments: [relativePath, parentUID, fileName, parentTitle, fileNameNoExt]
        )
    }

    /// Insert one link row.
    private static func insertLinkRow(
        _ conn: Database,
        link: LinkItem,
        parentUID: String,
        parentTitle: String
    ) throws {
        let bodyContent = [link.url.absoluteString, link.annotation]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let secondary = [link.url.host ?? "", parentTitle]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        try conn.execute(
            sql: """
                INSERT INTO search_fts (type, entity_id, parent_uid, primary_text, secondary_text, body)
                VALUES ('link', ?, ?, ?, ?, ?)
                """,
            arguments: [
                link.uid, parentUID,
                link.title.isEmpty ? (link.url.host ?? "") : link.title,
                secondary, bodyContent
            ]
        )
    }

    // MARK: - Search

    func search(query: String) throws -> [SearchResult] {
        let tokens = query.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { "\($0)*" }
        guard !tokens.isEmpty else { return [] }
        let ftsQuery = tokens.joined(separator: " ")

        return try db.read { conn in
            let rows = try Row.fetchAll(
                conn,
                sql: """
                    SELECT type, entity_id, parent_uid, primary_text, secondary_text
                    FROM search_fts
                    WHERE search_fts MATCH ?
                    ORDER BY rank
                    LIMIT 30
                    """,
                arguments: [ftsQuery]
            )
            return rows.compactMap { row -> SearchResult? in
                guard let typeString = row["type"] as? String,
                      let type = SearchResultType(rawValue: typeString) else { return nil }
                let entityID: String = row["entity_id"]
                let parentUID: String = row["parent_uid"]
                let primaryText: String = row["primary_text"]
                let secondaryText: String = row["secondary_text"]
                let resultID: String = {
                    switch type {
                    case .file, .link:
                        return "\(typeString)-\(parentUID)-\(entityID)"
                    case .project, .tag, .command:
                        return "\(typeString)-\(entityID)"
                    }
                }()
                return SearchResult(
                    id: resultID,
                    type: type,
                    entityID: entityID,
                    parentUID: parentUID,
                    primaryText: primaryText,
                    secondaryText: secondaryText
                )
            }
        }
    }
}
