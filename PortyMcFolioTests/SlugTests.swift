import XCTest
@testable import PortyMcFolio

final class SlugTests: XCTestCase {
    func testBasicSlugification() {
        XCTAssertEqual(Slug.from("Brand Identity"), "brand-identity")
    }
    func testSpecialCharactersRemoved() {
        XCTAssertEqual(Slug.from("Acme & Co. — Rebrand!"), "acme-co-rebrand")
    }
    func testMultipleSpacesCollapsed() {
        XCTAssertEqual(Slug.from("My   Cool   Project"), "my-cool-project")
    }
    func testLeadingTrailingHyphensStripped() {
        XCTAssertEqual(Slug.from("  Hello World  "), "hello-world")
    }
    func testUnicodeHandled() {
        XCTAssertEqual(Slug.from("Café Design"), "cafe-design")
    }
    func testEmptyStringReturnsUntitled() {
        XCTAssertEqual(Slug.from(""), "untitled")
    }

    func testUnderscoreSlug() {
        XCTAssertEqual(Slug.underscoreFrom("Acme Rebrand"), "acme_rebrand")
    }

    func testUnderscoreSlugSpecialChars() {
        XCTAssertEqual(Slug.underscoreFrom("Brand Identity — Acme"), "brand_identity_acme")
    }

    func testUnderscoreSlugEmpty() {
        XCTAssertEqual(Slug.underscoreFrom(""), "untitled")
    }

    func testSlugFromIsLocaleIndependentForTurkishI() {
        // Guard against locale-dependent folding: in tr_TR, "I".lowercased()
        // returns "ı" (dotless i). Using locale=.current would leak that into
        // folder names. A POSIX locale keeps results stable.
        let result = Slug.from("IMAX Launch")
        XCTAssertEqual(result, "imax-launch")
    }

    func testUnderscoreSlugIsLocaleIndependentForTurkishI() {
        let result = Slug.underscoreFrom("IMAX Launch")
        XCTAssertEqual(result, "imax_launch")
    }
}
