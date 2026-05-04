import XCTest
import AppKit
@testable import PortyMcFolio

final class ClipboardPasteTests: XCTestCase {

    private func scratchPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name(rawValue: "test-\(UUID().uuidString)"))
    }

    func testPastedImageNameStable() {
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 22
        components.hour = 14
        components.minute = 30
        components.second = 22
        let date = Calendar.current.date(from: components)!

        let name = ClipboardPaste.pastedImageName(date: date)
        XCTAssertEqual(name, "pasted-2026-04-22-143022.png")
    }

    func testReadFileURLsReturnsRegularFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let file1 = tempDir.appendingPathComponent("test1-\(UUID().uuidString).txt")
        let file2 = tempDir.appendingPathComponent("test2-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: file1)
        try Data("world".utf8).write(to: file2)
        defer {
            try? FileManager.default.removeItem(at: file1)
            try? FileManager.default.removeItem(at: file2)
        }

        let pb = scratchPasteboard()
        pb.clearContents()
        pb.writeObjects([file1 as NSURL, file2 as NSURL])

        let urls = ClipboardPaste.readFileURLs(from: pb)
        XCTAssertEqual(
            Set(urls.map { $0.standardizedFileURL }),
            Set([file1, file2].map { $0.standardizedFileURL })
        )
    }

    func testReadFileURLsFiltersFolders() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let folder = tempDir.appendingPathComponent("testfolder-\(UUID().uuidString)")
        let file = tempDir.appendingPathComponent("testfile-\(UUID().uuidString).txt")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("hello".utf8).write(to: file)
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: file)
        }

        let pb = scratchPasteboard()
        pb.clearContents()
        pb.writeObjects([folder as NSURL, file as NSURL])

        let urls = ClipboardPaste.readFileURLs(from: pb)
        XCTAssertEqual(
            urls.map { $0.standardizedFileURL },
            [file.standardizedFileURL]
        )
    }

    func testReadFileURLsEmptyOnTextPasteboard() {
        let pb = scratchPasteboard()
        pb.clearContents()
        pb.setString("hello", forType: .string)

        XCTAssertTrue(ClipboardPaste.readFileURLs(from: pb).isEmpty)
    }

    func testReadImageDataReturnsPNGFromTIFF() throws {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        image.unlockFocus()
        let tiff = try XCTUnwrap(image.tiffRepresentation)

        let pb = scratchPasteboard()
        pb.clearContents()
        pb.setData(tiff, forType: .tiff)

        let data = try XCTUnwrap(ClipboardPaste.readImageData(from: pb))
        // PNG signature: 89 50 4E 47
        XCTAssertEqual(data.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    func testReadImageDataNilWhenNoImage() {
        let pb = scratchPasteboard()
        pb.clearContents()
        pb.setString("hello", forType: .string)

        XCTAssertNil(ClipboardPaste.readImageData(from: pb))
    }

    func testReadImageDataNilOnEmptyPasteboard() {
        let pb = scratchPasteboard()
        pb.clearContents()

        XCTAssertNil(ClipboardPaste.readImageData(from: pb))
    }
}
