import XCTest
@testable import PortyMcFolio

final class MediaKindTests: XCTestCase {
    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name)")
    }

    func testImageExtensionsAreImage() {
        XCTAssertEqual(MediaKind.from(url: url("hero.jpg")),  .image)
        XCTAssertEqual(MediaKind.from(url: url("Hero.PNG")),  .image)
        XCTAssertEqual(MediaKind.from(url: url("pic.heic")),  .image)
        XCTAssertEqual(MediaKind.from(url: url("vec.svg")),   .image)
        XCTAssertEqual(MediaKind.from(url: url("img.avif")),  .image)
    }

    func testVideoExtensionsAreVideo() {
        XCTAssertEqual(MediaKind.from(url: url("reel.mp4")),  .video)
        XCTAssertEqual(MediaKind.from(url: url("clip.mov")),  .video)
        XCTAssertEqual(MediaKind.from(url: url("film.m4v")),  .video)
    }

    func testAudioExtensionsAreAudio() {
        XCTAssertEqual(MediaKind.from(url: url("track.mp3")), .audio)
        XCTAssertEqual(MediaKind.from(url: url("demo.wav")),  .audio)
        XCTAssertEqual(MediaKind.from(url: url("song.flac")), .audio)
    }

    func testNonMediaReturnsNil() {
        XCTAssertNil(MediaKind.from(url: url("notes.txt")))
        XCTAssertNil(MediaKind.from(url: url("README.md")))
        XCTAssertNil(MediaKind.from(url: url("data.json")))
        XCTAssertNil(MediaKind.from(url: url("no-extension")))
    }

    func testIsMediaMatchesFrom() {
        XCTAssertTrue(MediaKind.isMedia(url: url("a.jpg")))
        XCTAssertTrue(MediaKind.isMedia(url: url("b.mp4")))
        XCTAssertTrue(MediaKind.isMedia(url: url("c.mp3")))
        XCTAssertFalse(MediaKind.isMedia(url: url("d.txt")))
    }
}
