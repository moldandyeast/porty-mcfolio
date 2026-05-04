import XCTest
@testable import PortyMcFolio

final class GallerySortTests: XCTestCase {
    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/project/\(name)")
    }

    // MARK: Category mapping

    func testCategoryImageExtensions() {
        for ext in ["jpg", "jpeg", "png", "gif", "svg", "webp", "avif", "heic"] {
            XCTAssertEqual(GallerySort.category(for: url("x.\(ext)")), .image, ext)
        }
    }

    func testCategoryVideoExtensions() {
        for ext in ["mp4", "mov", "avi", "mkv", "m4v"] {
            XCTAssertEqual(GallerySort.category(for: url("x.\(ext)")), .video, ext)
        }
    }

    func testCategoryAudioExtensions() {
        for ext in ["mp3", "wav", "aac", "m4a", "flac", "aiff"] {
            XCTAssertEqual(GallerySort.category(for: url("x.\(ext)")), .audio, ext)
        }
    }

    func testCategoryDocExtensions() {
        for ext in ["pdf", "md", "txt", "rtf", "doc", "docx"] {
            XCTAssertEqual(GallerySort.category(for: url("x.\(ext)")), .doc, ext)
        }
    }

    func testCategory3DExtensions() {
        for ext in ["usdz", "obj", "stl", "dae", "scn"] {
            XCTAssertEqual(GallerySort.category(for: url("x.\(ext)")), .threeD, ext)
        }
    }

    func testCategoryUnknownFallsToOther() {
        XCTAssertEqual(GallerySort.category(for: url("x.xyz")), .other)
        XCTAssertEqual(GallerySort.category(for: url("x")), .other)  // no extension
    }

    func testCategoryIsCaseInsensitive() {
        XCTAssertEqual(GallerySort.category(for: url("PHOTO.JPG")), .image)
    }

    // MARK: Sort — name

    func testSortByNameAscending() {
        let files = [url("banana.png"), url("Apple.png"), url("cherry.png")]
        let result = GallerySort.sort(files: files, folders: [], by: .name, ascending: true)
        XCTAssertEqual(result.folders, [])
        XCTAssertEqual(result.files.map(\.lastPathComponent), ["Apple.png", "banana.png", "cherry.png"])
    }

    func testSortByNameDescending() {
        let files = [url("Apple.png"), url("banana.png")]
        let result = GallerySort.sort(files: files, folders: [], by: .name, ascending: false)
        XCTAssertEqual(result.files.map(\.lastPathComponent), ["banana.png", "Apple.png"])
    }

    // MARK: Sort — kind

    func testSortByKindAscendingFollowsCategoryOrder() {
        let files = [
            url("notes.pdf"),      // doc
            url("clip.mov"),       // video
            url("photo.jpg"),      // image
            url("song.mp3"),       // audio
            url("model.usdz"),     // 3d
            url("weird.xyz"),      // other
        ]
        let result = GallerySort.sort(files: files, folders: [], by: .kind, ascending: true)
        XCTAssertEqual(
            result.files.map(\.lastPathComponent),
            ["photo.jpg", "clip.mov", "song.mp3", "notes.pdf", "model.usdz", "weird.xyz"]
        )
    }

    func testSortByKindTieBreaksOnName() {
        let files = [url("b.png"), url("a.png"), url("c.jpg")]
        let result = GallerySort.sort(files: files, folders: [], by: .kind, ascending: true)
        XCTAssertEqual(result.files.map(\.lastPathComponent), ["a.png", "b.png", "c.jpg"])
    }

    func testSortByKindDescendingReversesCategoryOrder() {
        let files = [url("photo.jpg"), url("clip.mov"), url("weird.xyz")]
        let result = GallerySort.sort(files: files, folders: [], by: .kind, ascending: false)
        XCTAssertEqual(result.files.map(\.lastPathComponent), ["weird.xyz", "clip.mov", "photo.jpg"])
    }

    // MARK: Folders-first

    func testFoldersAlwaysFirstRegardlessOfDirection() {
        let folders = [url("zebra"), url("apple")]
        let files = [url("a.png"), url("z.png")]

        let asc = GallerySort.sort(files: files, folders: folders, by: .name, ascending: true)
        XCTAssertEqual(asc.folders.map(\.lastPathComponent), ["apple", "zebra"])
        XCTAssertEqual(asc.files.map(\.lastPathComponent), ["a.png", "z.png"])

        let desc = GallerySort.sort(files: files, folders: folders, by: .name, ascending: false)
        XCTAssertEqual(desc.folders.map(\.lastPathComponent), ["zebra", "apple"])
        XCTAssertEqual(desc.files.map(\.lastPathComponent), ["z.png", "a.png"])
    }

    func testFoldersUseNameOrderWhenSortingByKind() {
        let folders = [url("zebra"), url("apple")]
        let asc = GallerySort.sort(files: [], folders: folders, by: .kind, ascending: true)
        XCTAssertEqual(asc.folders.map(\.lastPathComponent), ["apple", "zebra"])
    }

    // MARK: Persistence key round-trip

    func testPersistenceKeyRoundTrip() {
        for key in GallerySort.SortKey.allCases {
            for asc in [true, false] {
                let raw = GallerySort.encode(key: key, ascending: asc)
                let decoded = GallerySort.decode(raw: raw)
                XCTAssertEqual(decoded?.key, key, raw)
                XCTAssertEqual(decoded?.ascending, asc, raw)
            }
        }
    }

    func testPersistenceKeyHandlesUnknownRaw() {
        XCTAssertNil(GallerySort.decode(raw: "garbage"))
        XCTAssertNil(GallerySort.decode(raw: "name-sideways"))
    }

    // MARK: Empty input

    func testEmptyInputsReturnEmpty() {
        let result = GallerySort.sort(files: [], folders: [], by: .name, ascending: true)
        XCTAssertEqual(result.folders, [])
        XCTAssertEqual(result.files, [])
    }

    /// Pin the current semantics: descending kind sort reverses BOTH the category
    /// order and the name order within a category. (Matches macOS Finder's Kind
    /// column when toggled to descending.)
    func testSortByKindDescendingTieBreakFullyReverses() {
        let files = [url("b.jpg"), url("a.jpg"), url("video.mp4")]
        let result = GallerySort.sort(files: files, folders: [], by: .kind, ascending: false)
        // Category order reverses: video (1) comes before image (0).
        // Within the image category, names reverse too: b.jpg before a.jpg.
        XCTAssertEqual(
            result.files.map(\.lastPathComponent),
            ["video.mp4", "b.jpg", "a.jpg"]
        )
    }

    // MARK: Fallback symbol

    func testFallbackSymbolForFolder() {
        XCTAssertEqual(GallerySort.fallbackSymbol(for: url("x.png"), isFolder: true), "folder.fill")
    }

    func testFallbackSymbolByCategory() {
        XCTAssertEqual(GallerySort.fallbackSymbol(for: url("x.jpg")), "photo")
        XCTAssertEqual(GallerySort.fallbackSymbol(for: url("x.mp4")), "film")
        XCTAssertEqual(GallerySort.fallbackSymbol(for: url("x.mp3")), "waveform")
        XCTAssertEqual(GallerySort.fallbackSymbol(for: url("x.pdf")), "doc.richtext")
        XCTAssertEqual(GallerySort.fallbackSymbol(for: url("x.usdz")), "cube")
        XCTAssertEqual(GallerySort.fallbackSymbol(for: url("x.xyz")), "doc")
    }
}
