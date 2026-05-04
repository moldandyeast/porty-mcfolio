import Foundation
import GRDB

struct CachedProjectMeta: Equatable {
    let uid: String
    let folderName: String
    let year: Int
    var title: String
    var client: String
    var status: ProjectStatus
    var tags: [String]
    var teaser: String
    var favorites: [String]
    var body: String
    var hidden: Bool
    var date: Date
    var dateEnd: Date?
    var frontmatterMTime: Date
}

final class ProjectMetadataCache {
    private let db: DatabaseQueue

    /// Shared, thread-safe formatter for `date_iso` round-trips.
    /// Hoisted to avoid allocating a new formatter per row in `decode` / `upsert`.
    private static let iso8601: ISO8601DateFormatter = ISO8601DateFormatter()

    init(db: DatabaseQueue) throws {
        self.db = db
        try migrate()
    }

    private func migrate() throws {
        try db.write { conn in
            try conn.execute(sql: """
                CREATE TABLE IF NOT EXISTS project_meta (
                    uid               TEXT PRIMARY KEY,
                    folder_name       TEXT NOT NULL,
                    year              INTEGER NOT NULL,
                    title             TEXT NOT NULL,
                    client            TEXT NOT NULL,
                    status            TEXT NOT NULL,
                    tags_json         TEXT NOT NULL,
                    teaser            TEXT NOT NULL,
                    favorites_json    TEXT NOT NULL DEFAULT '[]',
                    body              TEXT NOT NULL,
                    hidden            INTEGER NOT NULL,
                    date_iso          TEXT NOT NULL,
                    frontmatter_mtime REAL NOT NULL,
                    date_end_iso      TEXT NULL,
                    date_precision    TEXT NOT NULL DEFAULT 'year',
                    cached_at         REAL NOT NULL
                )
                """)
            // Additive migration: existing DBs created before favorites existed.
            // Swallow the "duplicate column" error so migrations are idempotent.
            do {
                try conn.execute(sql: """
                    ALTER TABLE project_meta
                    ADD COLUMN favorites_json TEXT NOT NULL DEFAULT '[]'
                    """)
            } catch {
                // SQLite throws on duplicate column; that's expected on re-runs.
                AppLogger.cache.debug("ALTER TABLE favorites_json ignored (likely already exists): \(error.localizedDescription, privacy: .public)")
            }
            do {
                try conn.execute(sql: """
                    ALTER TABLE project_meta
                    ADD COLUMN date_end_iso TEXT
                    """)
            } catch {
                AppLogger.cache.debug("ALTER TABLE date_end_iso ignored (likely already exists): \(error.localizedDescription, privacy: .public)")
            }
            do {
                try conn.execute(sql: """
                    ALTER TABLE project_meta
                    ADD COLUMN date_precision TEXT NOT NULL DEFAULT 'year'
                    """)
            } catch {
                AppLogger.cache.debug("ALTER TABLE date_precision ignored (likely already exists): \(error.localizedDescription, privacy: .public)")
            }
            try conn.execute(sql: """
                CREATE INDEX IF NOT EXISTS idx_project_meta_year ON project_meta(year)
                """)
        }
    }

    // MARK: - Public API (own-transaction)

    func loadAll() throws -> [CachedProjectMeta] {
        try db.read { conn in
            let rows = try Row.fetchAll(conn, sql: """
                SELECT uid, folder_name, year, title, client, status,
                       tags_json, teaser, favorites_json, body, hidden, date_iso, frontmatter_mtime,
                       date_end_iso
                FROM project_meta
                """)
            return rows.compactMap(Self.decode)
        }
    }

    /// Load a single project meta by uid, or nil if not present.
    /// Cheaper than `loadAll()` for the reconciler's per-uid sync path.
    func load(uid: String) -> CachedProjectMeta? {
        let row: Row?
        do {
            row = try db.read { conn in
                try Row.fetchOne(conn, sql: """
                    SELECT uid, folder_name, year, title, client, status,
                           tags_json, teaser, favorites_json, body, hidden, date_iso, frontmatter_mtime,
                           date_end_iso
                    FROM project_meta
                    WHERE uid = ?
                    """, arguments: [uid])
            }
        } catch {
            AppLogger.cache.error("load(uid:) failed for \(uid, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return row.flatMap(Self.decode)
    }

    func upsert(_ meta: CachedProjectMeta) throws {
        try db.write { conn in try Self.upsert(conn, meta) }
    }

    func remove(uid: String) throws {
        try db.write { conn in try Self.remove(conn, uid: uid) }
    }

    func clear() throws {
        try db.write { conn in
            try conn.execute(sql: "DELETE FROM project_meta")
        }
    }

    func replaceFolderName(uid: String, newFolderName: String) throws {
        try db.write { conn in
            try conn.execute(
                sql: "UPDATE project_meta SET folder_name = ?, cached_at = ? WHERE uid = ?",
                arguments: [newFolderName, Date().timeIntervalSince1970, uid]
            )
        }
    }

    func aggregateTagCounts() throws -> [String: Int] {
        let rows = try db.read { conn in
            try Row.fetchAll(conn, sql: "SELECT tags_json FROM project_meta")
        }
        var counts: [String: Int] = [:]
        for row in rows {
            let tagsJson: String = row["tags_json"]
            guard let data = tagsJson.data(using: .utf8),
                  let tags = try? JSONDecoder().decode([String].self, from: data) else { continue }
            for tag in tags { counts[tag, default: 0] += 1 }
        }
        return counts
    }

    // MARK: - In-transaction variants (for atomic cache + FTS writes)

    func upsertWithin(_ db: Database, _ meta: CachedProjectMeta) throws {
        try Self.upsert(db, meta)
    }

    func removeWithin(_ db: Database, uid: String) throws {
        try Self.remove(db, uid: uid)
    }

    // MARK: - Private helpers

    private static func upsert(_ conn: Database, _ meta: CachedProjectMeta) throws {
        let tagsData = try JSONEncoder().encode(meta.tags)
        let tagsJson = String(data: tagsData, encoding: .utf8) ?? "[]"
        let favoritesData = try JSONEncoder().encode(meta.favorites)
        let favoritesJson = String(data: favoritesData, encoding: .utf8) ?? "[]"
        let dateEndIso = meta.dateEnd.map { Self.iso8601.string(from: $0) }
        try conn.execute(sql: """
            INSERT INTO project_meta
                (uid, folder_name, year, title, client, status,
                 tags_json, teaser, favorites_json, body, hidden, date_iso, frontmatter_mtime,
                 date_end_iso, cached_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(uid) DO UPDATE SET
                folder_name = excluded.folder_name,
                year = excluded.year,
                title = excluded.title,
                client = excluded.client,
                status = excluded.status,
                tags_json = excluded.tags_json,
                teaser = excluded.teaser,
                favorites_json = excluded.favorites_json,
                body = excluded.body,
                hidden = excluded.hidden,
                date_iso = excluded.date_iso,
                frontmatter_mtime = excluded.frontmatter_mtime,
                date_end_iso = excluded.date_end_iso,
                cached_at = excluded.cached_at
            """, arguments: [
                meta.uid, meta.folderName, meta.year, meta.title, meta.client, meta.status.rawValue,
                tagsJson, meta.teaser, favoritesJson, meta.body, meta.hidden ? 1 : 0,
                Self.iso8601.string(from: meta.date),
                meta.frontmatterMTime.timeIntervalSince1970,
                dateEndIso,
                Date().timeIntervalSince1970
            ])
    }

    private static func remove(_ conn: Database, uid: String) throws {
        try conn.execute(sql: "DELETE FROM project_meta WHERE uid = ?", arguments: [uid])
    }

    private static func decode(_ row: Row) -> CachedProjectMeta? {
        let uid: String = row["uid"]
        let tagsJson: String = row["tags_json"]
        guard let data = tagsJson.data(using: .utf8),
              let tags = try? JSONDecoder().decode([String].self, from: data) else {
            AppLogger.cache.error("dropping corrupt row uid=\(uid, privacy: .public) (bad tags_json)")
            return nil
        }
        let favoritesJson: String = row["favorites_json"]
        let favorites: [String] = (favoritesJson.data(using: .utf8).flatMap {
            try? JSONDecoder().decode([String].self, from: $0)
        }) ?? []
        let statusRaw: String = row["status"]
        let status = ProjectStatus(rawValue: statusRaw) ?? .empty
        let dateIso: String = row["date_iso"]
        guard let date = Self.iso8601.date(from: dateIso) else {
            AppLogger.cache.error("dropping corrupt row uid=\(uid, privacy: .public) (bad date_iso)")
            return nil
        }
        let mtimeSec: Double = row["frontmatter_mtime"]
        let hiddenInt: Int = row["hidden"]
        let dateEnd: Date?
        if let endIso: String = row["date_end_iso"], !endIso.isEmpty {
            dateEnd = Self.iso8601.date(from: endIso)
        } else {
            dateEnd = nil
        }
        return CachedProjectMeta(
            uid: uid,
            folderName: row["folder_name"],
            year: row["year"],
            title: row["title"],
            client: row["client"],
            status: status,
            tags: tags,
            teaser: row["teaser"],
            favorites: favorites,
            body: row["body"],
            hidden: hiddenInt != 0,
            date: date,
            dateEnd: dateEnd,
            frontmatterMTime: Date(timeIntervalSince1970: mtimeSec)
        )
    }
}
