import XCTest
import GRDB
@testable import PortyMcFolio

final class ProjectMetadataCacheTests: XCTestCase {
    var db: DatabaseQueue!
    var cache: ProjectMetadataCache!

    override func setUp() {
        super.setUp()
        db = try! DatabaseQueue()  // in-memory
        cache = try! ProjectMetadataCache(db: db)
    }

    override func tearDown() {
        cache = nil
        db = nil
        super.tearDown()
    }

    private func makeMeta(
        uid: String = "abcd1234",
        folderName: String? = nil,
        year: Int = 2025,
        title: String = "Test",
        client: String = "ACME",
        status: ProjectStatus = .empty,
        tags: [String] = ["a", "b"],
        teaser: String = "",
        body: String = "Body text",
        hidden: Bool = false,
        date: Date = Date(timeIntervalSince1970: 1_700_000_000),
        dateEnd: Date? = nil,
        mtime: Date = Date(timeIntervalSince1970: 1_700_000_500)
    ) -> CachedProjectMeta {
        CachedProjectMeta(
            uid: uid,
            folderName: folderName ?? "\(year)_test_\(uid)",
            year: year,
            title: title,
            client: client,
            status: status,
            tags: tags,
            teaser: teaser,
            favorites: [],
            body: body,
            hidden: hidden,
            date: date,
            dateEnd: dateEnd,
            frontmatterMTime: mtime
        )
    }

    func testEmptyCacheReturnsEmptyArray() throws {
        XCTAssertEqual(try cache.loadAll(), [])
    }

    func testUpsertThenLoadRoundTrips() throws {
        let m = makeMeta(tags: ["UI", "Brand"])
        try cache.upsert(m)
        let loaded = try cache.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0], m)
    }

    func testUpsertReplacesExistingRow() throws {
        try cache.upsert(makeMeta(title: "Old"))
        try cache.upsert(makeMeta(title: "New"))
        let loaded = try cache.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].title, "New")
    }

    func testRemoveDropsRow() throws {
        try cache.upsert(makeMeta(uid: "aaaa1111"))
        try cache.upsert(makeMeta(uid: "bbbb2222"))
        try cache.remove(uid: "aaaa1111")
        let loaded = try cache.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].uid, "bbbb2222")
    }

    func testClearWipesEverything() throws {
        try cache.upsert(makeMeta(uid: "aaaa1111"))
        try cache.upsert(makeMeta(uid: "bbbb2222"))
        try cache.clear()
        XCTAssertEqual(try cache.loadAll(), [])
    }

    func testCorruptTagsJsonDropsRowGracefully() throws {
        try cache.upsert(makeMeta(uid: "good1111"))
        // Manually inject a row with malformed tags_json
        try db.write { conn in
            try conn.execute(sql: """
                INSERT INTO project_meta (uid, folder_name, year, title, client, status,
                    tags_json, teaser, body, hidden, date_iso, frontmatter_mtime, cached_at)
                VALUES ('bad22222', '2025_bad_bad22222', 2025, 'Bad', 'X', 'empty',
                    'NOT VALID JSON{{', '', '', 0, '2024-01-01', 1700000000, 1700000000)
                """)
        }
        // loadAll should skip the corrupt row and return the good one
        let loaded = try cache.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].uid, "good1111")
    }

    func testFrontmatterMTimeRoundTripsAtSecondPrecision() throws {
        let mtime = Date(timeIntervalSince1970: 1_700_000_555)
        try cache.upsert(makeMeta(mtime: mtime))
        let loaded = try cache.loadAll()
        XCTAssertEqual(loaded[0].frontmatterMTime.timeIntervalSince1970, mtime.timeIntervalSince1970, accuracy: 1.0)
    }

    func testHiddenBoolRoundTripsBothValues() throws {
        try cache.upsert(makeMeta(uid: "vis11111", hidden: false))
        try cache.upsert(makeMeta(uid: "hid22222", hidden: true))
        let loaded = try cache.loadAll().sorted { $0.uid < $1.uid }
        XCTAssertEqual(loaded[0].hidden, true)   // hid22222 < vis11111
        XCTAssertEqual(loaded[1].hidden, false)
    }

    func testAggregateTagCountsAcrossProjects() throws {
        try cache.upsert(makeMeta(uid: "p1aaaaaa", tags: ["UI", "Brand"]))
        try cache.upsert(makeMeta(uid: "p2bbbbbb", tags: ["UI", "Strategy"]))
        try cache.upsert(makeMeta(uid: "p3cccccc", tags: ["UI"]))
        let counts = try cache.aggregateTagCounts()
        XCTAssertEqual(counts["UI"], 3)
        XCTAssertEqual(counts["Brand"], 1)
        XCTAssertEqual(counts["Strategy"], 1)
    }

    func testReplaceFolderNameUpdatesInPlace() throws {
        try cache.upsert(makeMeta(uid: "rn111111", folderName: "2024_old_rn111111"))
        try cache.replaceFolderName(uid: "rn111111", newFolderName: "2025_new_rn111111")
        let loaded = try cache.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].folderName, "2025_new_rn111111")
        XCTAssertEqual(loaded[0].uid, "rn111111")
    }

    // MARK: - When field (dateEnd) round-trip tests

    private func makeDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testUpsertAndLoad_yearOnly_roundtripsNilDateEnd() throws {
        let m = makeMeta(uid: "aaaaaaaa", dateEnd: nil)
        try cache.upsert(m)
        let loaded = cache.load(uid: "aaaaaaaa")
        XCTAssertNotNil(loaded)
        XCTAssertNil(loaded?.dateEnd)
    }

    func testUpsertAndLoad_range_roundtripsDateEnd() throws {
        let m = makeMeta(
            uid: "bbbbbbbb",
            date: makeDate(2025, 3, 1),
            dateEnd: makeDate(2025, 6, 30)
        )
        try cache.upsert(m)
        let loaded = cache.load(uid: "bbbbbbbb")
        XCTAssertEqual(loaded?.dateEnd, makeDate(2025, 6, 30))
    }

    func testLoadAll_includesDateEndField() throws {
        let m = makeMeta(uid: "dddddddd", dateEnd: makeDate(2025, 6, 30))
        try cache.upsert(m)
        let all = try cache.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.dateEnd, makeDate(2025, 6, 30))
    }
}
