import XCTest
@testable import PortyMcFolio

final class FrontmatterParserTests: XCTestCase {
    let sampleMarkdown = """
    ---
    title: "Brand Identity — Acme"
    date: 2025-03-15
    tags: [branding, identity]
    client: "Acme Corp"
    status: active
    ---

    # Brand Identity — Acme

    Project description here.
    """

    func testParseFrontmatter() throws {
        let result = try FrontmatterParser.parse(sampleMarkdown)
        XCTAssertEqual(result.title, "Brand Identity — Acme")
        XCTAssertEqual(result.tags, ["branding", "identity"])
        XCTAssertEqual(result.client, "Acme Corp")
        XCTAssertEqual(result.status, .inProgress)
    }

    func testParseDate() throws {
        let result = try FrontmatterParser.parse(sampleMarkdown)
        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.year, from: result.date), 2025)
        XCTAssertEqual(calendar.component(.month, from: result.date), 3)
        XCTAssertEqual(calendar.component(.day, from: result.date), 15)
    }

    func testParseBody() throws {
        let result = try FrontmatterParser.parse(sampleMarkdown)
        XCTAssertTrue(result.body.contains("# Brand Identity"))
        XCTAssertTrue(result.body.contains("Project description here."))
        XCTAssertFalse(result.body.contains("---"))
    }

    func testParseNoFrontmatter() throws {
        let md = "# Just a heading\n\nSome text."
        let result = try FrontmatterParser.parse(md)
        XCTAssertEqual(result.title, "")
        XCTAssertEqual(result.tags, [])
        XCTAssertEqual(result.status, .empty)
        XCTAssertTrue(result.body.contains("Just a heading"))
    }

    func testSerializeFrontmatter() throws {
        let parsed = try FrontmatterParser.parse(sampleMarkdown)
        let serialized = FrontmatterParser.serialize(frontmatter: parsed)
        XCTAssertTrue(serialized.hasPrefix("---\n"))
        XCTAssertTrue(serialized.contains("title: \"Brand Identity — Acme\""))
        XCTAssertTrue(serialized.contains("status: inProgress"))
        XCTAssertTrue(serialized.contains("# Brand Identity"))
    }

    func testParseEmptyTags() throws {
        let md = """
        ---
        title: "Test"
        date: 2025-01-01
        tags: []
        status: draft
        ---

        Body.
        """
        let result = try FrontmatterParser.parse(md)
        XCTAssertEqual(result.tags, [])
    }

    func testParseTeaserField() throws {
        let md = """
        ---
        title: "Test"
        date: 2025-01-01
        tags: []
        status: draft
        teaser: "photos/hero.jpg"
        ---

        Body.
        """
        let result = try FrontmatterParser.parse(md)
        XCTAssertEqual(result.teaser, "photos/hero.jpg")
    }

    func testParseMissingTeaser() throws {
        let result = try FrontmatterParser.parse(sampleMarkdown)
        XCTAssertEqual(result.teaser, "")
    }

    func testSerializeTeaserField() throws {
        var parsed = try FrontmatterParser.parse(sampleMarkdown)
        parsed.teaser = "photos/hero.jpg"
        let serialized = FrontmatterParser.serialize(frontmatter: parsed)
        XCTAssertTrue(serialized.contains("teaser: \"photos/hero.jpg\""))
    }

    func testSerializeEmptyTeaserOmitted() throws {
        let parsed = try FrontmatterParser.parse(sampleMarkdown)
        let serialized = FrontmatterParser.serialize(frontmatter: parsed)
        XCTAssertFalse(serialized.contains("teaser:"))
    }

    // MARK: - Favorites

    func testParseFavoritesAbsent() throws {
        let md = """
        ---
        title: "X"
        date: 2025-01-01
        tags: []
        client: ""
        status: empty
        ---
        """
        let result = try FrontmatterParser.parse(md)
        XCTAssertEqual(result.favorites, [])
    }

    func testParseFavoritesPresent() throws {
        let md = """
        ---
        title: "X"
        date: 2025-01-01
        tags: []
        client: ""
        status: empty
        favorites: ["photos/hero.jpg", "videos/reel.mp4"]
        ---
        """
        let result = try FrontmatterParser.parse(md)
        XCTAssertEqual(result.favorites, ["photos/hero.jpg", "videos/reel.mp4"])
    }

    func testParseFavoritesDropsInvalidPaths() throws {
        let md = """
        ---
        title: "X"
        date: 2025-01-01
        tags: []
        client: ""
        status: empty
        favorites: ["ok.jpg", "/absolute.jpg", "../escape.jpg", "~/home.jpg", "", "good/path.png"]
        ---
        """
        let result = try FrontmatterParser.parse(md)
        XCTAssertEqual(result.favorites, ["ok.jpg", "good/path.png"])
    }

    func testParseFavoritesDropsNonStrings() throws {
        // Non-string YAML entries get dropped (matches tags defensive pattern).
        let md = """
        ---
        title: "X"
        date: 2025-01-01
        tags: []
        client: ""
        status: empty
        favorites: ["a.jpg", 42, "b.png", null, "c.mp4"]
        ---
        """
        let result = try FrontmatterParser.parse(md)
        XCTAssertEqual(result.favorites, ["a.jpg", "b.png", "c.mp4"])
    }

    func testSerializeFavoritesEmpty() {
        let fm = ParsedFrontmatter(
            title: "X", date: Date(), tags: [], client: "",
            status: .empty, body: "", teaser: "", favorites: [], hidden: false
        )
        let yaml = FrontmatterParser.serialize(frontmatter: fm)
        XCTAssertFalse(yaml.contains("favorites:"),
            "empty favorites array must be omitted from YAML")
    }

    func testSerializeFavoritesNonEmpty() {
        let fm = ParsedFrontmatter(
            title: "X", date: Date(), tags: [], client: "",
            status: .empty, body: "", teaser: "",
            favorites: ["photos/a.jpg", "videos/b.mp4"], hidden: false
        )
        let yaml = FrontmatterParser.serialize(frontmatter: fm)
        XCTAssertTrue(yaml.contains("favorites: [\"photos/a.jpg\", \"videos/b.mp4\"]"))
    }

    func testRoundTripFavorites() throws {
        let original = ParsedFrontmatter(
            title: "X", date: Date(), tags: [], client: "",
            status: .empty, body: "Body text", teaser: "",
            favorites: ["a/b.jpg", "c.mp4"], hidden: false
        )
        let yaml = FrontmatterParser.serialize(frontmatter: original)
        let parsed = try FrontmatterParser.parse(yaml)
        XCTAssertEqual(parsed.favorites, original.favorites)
    }

    func testIsValidFavoritePath() {
        XCTAssertTrue(FrontmatterParser.isValidFavoritePath("a.jpg"))
        XCTAssertTrue(FrontmatterParser.isValidFavoritePath("sub/folder/x.png"))

        XCTAssertFalse(FrontmatterParser.isValidFavoritePath(""))
        XCTAssertFalse(FrontmatterParser.isValidFavoritePath("/abs.jpg"))
        XCTAssertFalse(FrontmatterParser.isValidFavoritePath("~/home.jpg"))
        XCTAssertFalse(FrontmatterParser.isValidFavoritePath("../escape.jpg"))
        XCTAssertFalse(FrontmatterParser.isValidFavoritePath("sub/../x.jpg"))
        XCTAssertFalse(FrontmatterParser.isValidFavoritePath("null\u{0}byte.jpg"))
    }

    // MARK: - Favorites rewrite helpers

    func testRewritingFavoriteExactMatch() {
        let favs = ["a/b.jpg", "c.mp4", "a/b.jpg"]  // duplicate is intentional
        let out = FrontmatterParser.rewritingFavorite(
            in: favs, from: "a/b.jpg", to: "a/moved.jpg")
        XCTAssertEqual(out, ["a/moved.jpg", "c.mp4", "a/moved.jpg"])
    }

    func testRewritingFavoriteNoMatch() {
        let favs = ["a.jpg", "b.mp4"]
        let out = FrontmatterParser.rewritingFavorite(
            in: favs, from: "never.png", to: "x.png")
        XCTAssertEqual(out, favs)
    }

    func testRewritingFavoriteToEmptyRemoves() {
        // newRelative == "" means "trash" — entry is removed.
        let favs = ["a.jpg", "b.mp4", "a.jpg"]
        let out = FrontmatterParser.rewritingFavorite(
            in: favs, from: "a.jpg", to: "")
        XCTAssertEqual(out, ["b.mp4"])
    }

    func testRewritingFavoritePrefixMatch() {
        let favs = ["photos/a.jpg", "photos/b.png", "videos/c.mp4"]
        let out = FrontmatterParser.rewritingFavoritePrefix(
            in: favs, from: "photos", to: "pics")
        XCTAssertEqual(out, ["pics/a.jpg", "pics/b.png", "videos/c.mp4"])
    }

    func testRewritingFavoritePrefixNoMatch() {
        let favs = ["photos/a.jpg", "videos/b.mp4"]
        let out = FrontmatterParser.rewritingFavoritePrefix(
            in: favs, from: "audio", to: "sounds")
        XCTAssertEqual(out, favs)
    }

    func testRewritingFavoritePrefixNestedFolder() {
        // "photos" should only match exact path component, not arbitrary substring.
        let favs = ["photos/a.jpg", "otherphotos/b.jpg", "photos/sub/c.png"]
        let out = FrontmatterParser.rewritingFavoritePrefix(
            in: favs, from: "photos", to: "pics")
        XCTAssertEqual(out, ["pics/a.jpg", "otherphotos/b.jpg", "pics/sub/c.png"])
    }

    // MARK: - When field parsing

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testParse_whenAbsent_defaultsToNilEnd() throws {
        let result = try FrontmatterParser.parse(sampleMarkdown)
        XCTAssertNil(result.dateEnd)
    }

    func testParse_dateEndPresent_isReadAsDate() throws {
        let md = """
        ---
        title: "T"
        date: 2025-03-01
        dateEnd: 2025-06-30
        tags: []
        client: "C"
        status: empty
        ---
        """
        let result = try FrontmatterParser.parse(md)
        XCTAssertEqual(result.dateEnd, makeDate(2025, 6, 30))
    }

    func testParse_legacyDatePrecisionKey_isPreserved() throws {
        // Files with datePrecision: day in their YAML should parse without error;
        // the field is now preserved in datePrecisionRaw for round-trip fidelity.
        let md = """
        ---
        title: "T"
        date: 2025-03-15
        datePrecision: day
        tags: []
        client: "C"
        status: empty
        ---
        """
        let result = try FrontmatterParser.parse(md)
        // Parse succeeds; dateEnd is nil; datePrecisionRaw is preserved.
        XCTAssertNil(result.dateEnd)
        XCTAssertEqual(result.datePrecisionRaw, "day")
    }

    func testParse_dateEndBeforeDate_isClampedToDate() throws {
        let md = """
        ---
        title: "T"
        date: 2025-06-01
        dateEnd: 2025-03-01
        tags: []
        client: "C"
        status: empty
        ---
        """
        let result = try FrontmatterParser.parse(md)
        XCTAssertEqual(result.dateEnd, makeDate(2025, 6, 1))
    }

    // MARK: - When field serialization

    func testSerialize_yearOnly_omitsDateEnd() {
        let fm = ParsedFrontmatter(
            title: "T",
            date: makeDate(2025, 1, 1),
            dateEnd: nil,
            tags: [],
            client: "C",
            status: .empty,
            body: "",
            teaser: "",
            favorites: [],
            hidden: false
        )
        let s = FrontmatterParser.serialize(frontmatter: fm)
        XCTAssertFalse(s.contains("dateEnd"))
        XCTAssertFalse(s.contains("datePrecision"))
    }

    func testSerialize_range_emitsDateEnd() {
        let fm = ParsedFrontmatter(
            title: "T",
            date: makeDate(2025, 3, 1),
            dateEnd: makeDate(2025, 6, 30),
            tags: [],
            client: "C",
            status: .empty,
            body: "",
            teaser: "",
            favorites: [],
            hidden: false
        )
        let s = FrontmatterParser.serialize(frontmatter: fm)
        XCTAssertTrue(s.contains("dateEnd: 2025-06-30"))
        XCTAssertFalse(s.contains("datePrecision"))
    }

    // MARK: - datePrecision round-trip

    func testRoundTrip_legacyDatePrecisionKey_isPreserved() throws {
        let md = """
        ---
        title: "T"
        date: 2025-03-15
        datePrecision: day
        tags: []
        client: "C"
        status: empty
        ---
        """
        let parsed = try FrontmatterParser.parse(md)
        XCTAssertEqual(parsed.datePrecisionRaw, "day")

        let serialized = FrontmatterParser.serialize(frontmatter: parsed)
        XCTAssertTrue(serialized.contains("datePrecision: day"))

        let reparsed = try FrontmatterParser.parse(serialized)
        XCTAssertEqual(reparsed.datePrecisionRaw, "day")
    }

    func testSerialize_omitsDatePrecisionWhenRawIsNil() {
        let fm = ParsedFrontmatter(
            title: "T",
            date: makeDate(2025, 1, 1),
            dateEnd: nil,
            datePrecisionRaw: nil,
            tags: [],
            client: "C",
            status: .empty,
            body: "",
            teaser: "",
            favorites: [],
            hidden: false
        )
        let s = FrontmatterParser.serialize(frontmatter: fm)
        XCTAssertFalse(s.contains("datePrecision"))
    }

    func testRoundTrip_unknownDatePrecisionValue_isPreserved() throws {
        // Future-proof: any future external authoring convention round-trips.
        let md = """
        ---
        title: "T"
        date: 2025-01-01
        datePrecision: weekly
        tags: []
        client: "C"
        status: empty
        ---
        """
        let parsed = try FrontmatterParser.parse(md)
        XCTAssertEqual(parsed.datePrecisionRaw, "weekly")
        let serialized = FrontmatterParser.serialize(frontmatter: parsed)
        XCTAssertTrue(serialized.contains("datePrecision: weekly"))
    }
}

final class ProjectStatusTests: XCTestCase {
    func testStatusRawValues() {
        XCTAssertEqual(ProjectStatus.empty.rawValue, "empty")
        XCTAssertEqual(ProjectStatus.inProgress.rawValue, "inProgress")
        XCTAssertEqual(ProjectStatus.archived.rawValue, "archived")
    }
    func testStatusFromRawValue() {
        XCTAssertEqual(ProjectStatus(rawValue: "empty"), .empty)
        XCTAssertEqual(ProjectStatus(rawValue: "invalid"), nil)
    }
    func testStatusFromLegacyStrings() {
        XCTAssertEqual(ProjectStatus.from("draft"), .empty)
        XCTAssertEqual(ProjectStatus.from("active"), .inProgress)
        XCTAssertEqual(ProjectStatus.from("complete"), .archived)
    }
}
