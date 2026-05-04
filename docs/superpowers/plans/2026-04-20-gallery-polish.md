# Gallery Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Modernize the project Gallery (grid + list) with card-style cells, prefix-stripped filenames, extension badges, list-row thumbnails, name/kind sort, stronger selection/focus states, 2-D keyboard navigation, and two targeted Cleanup popup bug fixes.

**Architecture:** Two pure helper types (`FilenameDisplay`, `GallerySort`) land first with TDD. Then the `selectedFileURL` / `selectedLinkID` pair in `GalleryView` is consolidated behind a `GallerySelection` enum (refactor, no user-visible change). Visual and interaction changes layer on top: grid cell card, list row thumbnail, sort toolbar, selection/focus ring, 2-D keyboard nav. Cleanup bug fixes close the work.

**Tech Stack:** Swift 5.9, SwiftUI (macOS 14+), XCTest. No new dependencies. No `project.yml` changes.

**Reference spec:** [docs/superpowers/specs/2026-04-20-gallery-polish-design.md](../specs/2026-04-20-gallery-polish-design.md)

---

## File Structure

**New files:**

| Path                                                | Responsibility                                                       |
| --------------------------------------------------- | -------------------------------------------------------------------- |
| `PortyMcFolio/Services/FilenameDisplay.swift`       | Pure function that strips a per-project prefix from a filename.      |
| `PortyMcFolio/Services/GallerySort.swift`           | Pure types + comparator: name/kind, asc/desc, folders-first.         |
| `PortyMcFolioTests/FilenameDisplayTests.swift`      | Unit tests for prefix stripping.                                     |
| `PortyMcFolioTests/GallerySortTests.swift`          | Unit tests for sort comparator + category mapping.                   |

**Modified files:**

| Path                                            | What changes                                                         |
| ----------------------------------------------- | -------------------------------------------------------------------- |
| `PortyMcFolio/Views/GalleryView.swift`          | Selection refactor, sort state, grid-column math, keyboard handlers, sparkles-button fix, tap handlers for folder selection. |
| `PortyMcFolio/Views/GalleryItemView.swift`      | Card chrome, filename treatment, extension badge, selection/focus visuals. |
| `PortyMcFolio/Views/GalleryListView.swift`      | Leading thumbnail, prefix-stripped filename, selection bar, focus ring, divider inset. |
| `PortyMcFolio/Views/CleanupPopup.swift`         | Stale-thumbnail callback guard (5a).                                 |

## Running tests

From the repo root, all commands use the same scheme/destination:

```bash
xcodebuild -project PortyMcFolio.xcodeproj \
           -scheme PortyMcFolio \
           -destination 'platform=macOS' \
           test
```

Filter to a single test class with `-only-testing:PortyMcFolioTests/<ClassName>` and to a single method with `-only-testing:PortyMcFolioTests/<ClassName>/<methodName>`.

---

## Task 1: FilenameDisplay helper

**Files:**
- Create: `PortyMcFolio/Services/FilenameDisplay.swift`
- Test: `PortyMcFolioTests/FilenameDisplayTests.swift`

- [ ] **Step 1.1: Write failing tests**

Create `PortyMcFolioTests/FilenameDisplayTests.swift`:

```swift
import XCTest
@testable import PortyMcFolio

final class FilenameDisplayTests: XCTestCase {
    func testStripsMatchingPrefix() {
        XCTAssertEqual(
            FilenameDisplay.display(name: "2026_foo_bar_baz.mp4", prefix: "2026_foo_"),
            "bar_baz.mp4"
        )
    }

    func testLeavesNonMatchingPrefixUntouched() {
        XCTAssertEqual(
            FilenameDisplay.display(name: "2026_foo_bar.mp4", prefix: "2025_foo_"),
            "2026_foo_bar.mp4"
        )
    }

    func testEmptyPrefixIsNoOp() {
        XCTAssertEqual(
            FilenameDisplay.display(name: "foo.mp4", prefix: ""),
            "foo.mp4"
        )
    }

    func testNameExactlyEqualsPrefixReturnsEmpty() {
        XCTAssertEqual(
            FilenameDisplay.display(name: "2026_foo_", prefix: "2026_foo_"),
            ""
        )
    }

    func testUnicodePrefix() {
        XCTAssertEqual(
            FilenameDisplay.display(name: "2026_café_x.jpg", prefix: "2026_café_"),
            "x.jpg"
        )
    }

    func testPrefixComputedFromTitleAndYear() {
        // Mirrors how callers derive it: Slug.underscoreFrom(title) joined with year
        let prefix = "2026_\(Slug.underscoreFrom("Acme Rebrand"))_"
        XCTAssertEqual(prefix, "2026_acme_rebrand_")
        XCTAssertEqual(
            FilenameDisplay.display(name: "2026_acme_rebrand_logo.png", prefix: prefix),
            "logo.png"
        )
    }
}
```

- [ ] **Step 1.2: Run tests, verify they fail**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test \
  -only-testing:PortyMcFolioTests/FilenameDisplayTests
```

Expected: compile error (`cannot find 'FilenameDisplay' in scope`).

- [ ] **Step 1.3: Implement the helper**

Create `PortyMcFolio/Services/FilenameDisplay.swift`:

```swift
import Foundation

enum FilenameDisplay {
    /// Returns `name` with `prefix` removed from its start, if and only if
    /// `name` begins with `prefix`. Otherwise returns `name` unchanged.
    /// `prefix` is matched with a plain `hasPrefix` — no slug/casing normalization.
    static func display(name: String, prefix: String) -> String {
        guard !prefix.isEmpty, name.hasPrefix(prefix) else { return name }
        return String(name.dropFirst(prefix.count))
    }
}
```

- [ ] **Step 1.4: Run tests, verify they pass**

Same command as Step 1.2. Expected: all 6 tests pass.

- [ ] **Step 1.5: Commit**

```bash
git add PortyMcFolio/Services/FilenameDisplay.swift \
        PortyMcFolioTests/FilenameDisplayTests.swift
git commit -m "feat: FilenameDisplay helper for per-project prefix stripping"
```

---

## Task 2: GallerySort helper

**Files:**
- Create: `PortyMcFolio/Services/GallerySort.swift`
- Test: `PortyMcFolioTests/GallerySortTests.swift`

- [ ] **Step 2.1: Write failing tests**

Create `PortyMcFolioTests/GallerySortTests.swift`:

```swift
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
        // All three are .image; within category, sort by name ascending.
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
        // Folders have no extension → always `.other` category; within folders we
        // still want a consistent name ordering instead of arbitrary input order.
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
}
```

- [ ] **Step 2.2: Run tests, verify they fail**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test \
  -only-testing:PortyMcFolioTests/GallerySortTests
```

Expected: compile errors on `GallerySort`, `.image`, `.video`, etc.

- [ ] **Step 2.3: Implement the helper**

Create `PortyMcFolio/Services/GallerySort.swift`:

```swift
import Foundation

enum GallerySort {
    enum SortKey: String, CaseIterable {
        case name
        case kind
    }

    enum Category: Int, Comparable {
        case image = 0
        case video = 1
        case audio = 2
        case doc = 3
        case threeD = 4
        case other = 5

        static func < (lhs: Category, rhs: Category) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    struct Result: Equatable {
        let folders: [URL]
        let files: [URL]
    }

    static func category(for url: URL) -> Category {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "svg", "webp", "avif", "heic":
            return .image
        case "mp4", "mov", "avi", "mkv", "m4v":
            return .video
        case "mp3", "wav", "aac", "m4a", "flac", "aiff":
            return .audio
        case "pdf", "md", "txt", "rtf", "doc", "docx":
            return .doc
        case "usdz", "obj", "stl", "dae", "scn":
            return .threeD
        default:
            return .other
        }
    }

    static func sort(
        files: [URL],
        folders: [URL],
        by key: SortKey,
        ascending: Bool
    ) -> Result {
        let folderCmp: (URL, URL) -> Bool = { a, b in
            a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
        }
        // Folders always sort by name. Reverse direction flips within-group order.
        let sortedFolders = folders.sorted { ascending ? folderCmp($0, $1) : folderCmp($1, $0) }

        let fileCmp: (URL, URL) -> Bool
        switch key {
        case .name:
            fileCmp = { a, b in
                a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
            }
        case .kind:
            fileCmp = { a, b in
                let ca = category(for: a)
                let cb = category(for: b)
                if ca != cb { return ca < cb }
                return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
            }
        }
        let sortedFiles = files.sorted { ascending ? fileCmp($0, $1) : fileCmp($1, $0) }

        return Result(folders: sortedFolders, files: sortedFiles)
    }

    // MARK: Persistence

    static func encode(key: SortKey, ascending: Bool) -> String {
        "\(key.rawValue)-\(ascending ? "asc" : "desc")"
    }

    static func decode(raw: String) -> (key: SortKey, ascending: Bool)? {
        let parts = raw.split(separator: "-", maxSplits: 1)
        guard parts.count == 2,
              let key = SortKey(rawValue: String(parts[0])) else { return nil }
        switch parts[1] {
        case "asc": return (key, true)
        case "desc": return (key, false)
        default: return nil
        }
    }
}
```

- [ ] **Step 2.4: Run tests, verify they pass**

Same command as Step 2.2. Expected: all tests pass.

- [ ] **Step 2.5: Commit**

```bash
git add PortyMcFolio/Services/GallerySort.swift \
        PortyMcFolioTests/GallerySortTests.swift
git commit -m "feat: GallerySort helper with name/kind sort and folders-first rule"
```

---

## Task 3: GallerySelection enum refactor

This is a behavior-neutral refactor. Replace `selectedFileURL` and `selectedLinkID` with a single `selection: GallerySelection?` var. Add a `.folder(URL)` case so future steps can make folders selectable, but do **not** change any tap handlers yet. The app should look and behave identically after this task.

**Files:**
- Modify: `PortyMcFolio/Views/GalleryView.swift`

- [ ] **Step 3.1: Add the enum**

Add near the top of `GalleryView.swift`, above `struct GalleryView`:

```swift
enum GallerySelection: Equatable {
    case file(URL)
    case folder(URL)
    case link(String)  // LinkItem.id
}
```

- [ ] **Step 3.2: Replace the two @State vars with one**

In `GalleryView`, replace:

```swift
@State private var selectedFileURL: URL?
@State private var selectedLinkID: String?
```

with:

```swift
@State private var selection: GallerySelection?
```

- [ ] **Step 3.3: Add derived accessors**

Immediately below the `@State` declarations, add helpers so existing read sites stay terse:

```swift
private var selectedFileURL: URL? {
    if case .file(let url) = selection { return url }
    return nil
}
private var selectedLinkID: String? {
    if case .link(let id) = selection { return id }
    return nil
}
```

Keep these as computed properties (not methods) — most read sites use them as vars today. Do **not** make them settable. All writes must go through `selection = …` to keep the invariant (exactly one kind selected). A `selectedFolderURL` accessor is deliberately not added — folder reads in later tasks use `selection == .folder(url)` inline.

- [ ] **Step 3.4: Rewrite every write site to use `selection = …`**

Grep the file for `selectedFileURL = ` and `selectedLinkID = `. Replace each write according to intent:

| Old code                                             | New code                            |
| ---------------------------------------------------- | ----------------------------------- |
| `selectedFileURL = fileURL`                          | `selection = .file(fileURL)`        |
| `selectedLinkID = linkID` / `selectedLinkID = id`    | `selection = .link(linkID)`         |
| `selectedFileURL = nil` **or** `selectedLinkID = nil` alone | delete the line if paired below, else `selection = nil` |
| Paired `selectedFileURL = X; selectedLinkID = nil`   | `selection = .file(X)`              |
| Paired `selectedLinkID = X; selectedFileURL = nil`   | `selection = .link(X)`              |

In `clearSelection()` (currently around line 302):

```swift
private func clearSelection() {
    selection = nil
    cutFileURL = nil
}
```

In the stale-selection cleanup inside `scanProjectFolder()` (around lines 362-367):

```swift
// Clean stale selection
switch selection {
case .file(let url) where !files.contains(url):
    selection = nil
case .folder(let url) where !folders.contains(url):
    selection = nil
case .link(let id) where !links.contains(where: { $0.id == id }):
    selection = nil
default:
    break
}
```

- [ ] **Step 3.5: Verify read sites still compile**

The computed properties added in Step 3.3 mean every existing `if let url = selectedFileURL { … }`, `selectedFileURL == fileURL`, etc. keeps working. No changes needed at read sites.

- [ ] **Step 3.6: Build and run the full test suite**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test
```

Expected: build succeeds, all existing tests still pass.

- [ ] **Step 3.7: Manual smoke test**

1. Launch the app (`⌘R` in Xcode, or build and run).
2. Open a project with at least one file and one link.
3. Click a file in grid view → confirm accent wash still appears.
4. Click a link in links view → confirm accent wash still appears.
5. Switch between view modes → selection persists / clears as before.
6. Arrow keys still navigate files.

If anything visually differs from `main`, stop and check the diff — this task is a pure refactor.

- [ ] **Step 3.8: Commit**

```bash
git add PortyMcFolio/Views/GalleryView.swift
git commit -m "refactor: consolidate Gallery selection behind GallerySelection enum"
```

---

## Task 4: Grid cell redesign

Card-style chrome, filename with prefix stripping + middle truncation, extension badge, selection/hover visuals. Move the card body into `GalleryItemView` and slim the wrapping call site in `GalleryView.fileGridItem`.

**Files:**
- Modify: `PortyMcFolio/Views/GalleryItemView.swift`
- Modify: `PortyMcFolio/Views/GalleryView.swift` (call site only)

- [ ] **Step 4.1: Extend `GalleryItemView`'s parameters**

Replace the entire contents of `PortyMcFolio/Views/GalleryItemView.swift` with:

```swift
import SwiftUI
import QuickLookThumbnailing

struct GalleryItemView: View {
    let fileURL: URL
    let displayName: String
    let isSelected: Bool
    let isTeaser: Bool
    let isCut: Bool
    let isFocused: Bool

    @State private var thumbnail: NSImage?

    private var fallbackIcon: String {
        switch fileURL.pathExtension.lowercased() {
        case "pdf":                              return "doc.richtext"
        case "mp4", "mov", "avi", "mkv", "m4v":  return "film"
        case "mp3", "wav", "aac", "m4a",
             "flac", "aiff":                     return "waveform"
        case "usdz", "obj", "stl", "dae", "scn": return "cube"
        default:                                 return "doc"
        }
    }

    private var extensionBadge: String? {
        let ext = fileURL.pathExtension
        guard !ext.isEmpty else { return nil }
        return String(ext.uppercased().prefix(4))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail area
            ZStack {
                Rectangle()
                    .fill(DT.Colors.surfaceHover)

                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: fallbackIcon)
                        .font(.system(size: 32))
                        .foregroundStyle(DT.Colors.textSecondary)
                }

                // Extension badge (bottom-right of thumbnail area)
                if let badge = extensionBadge {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(badge)
                                .font(DT.Typography.micro)
                                .foregroundStyle(DT.Colors.textSecondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    DT.Colors.surface.opacity(0.85),
                                    in: RoundedRectangle(cornerRadius: DT.Radius.small)
                                )
                                .padding(6)
                        }
                    }
                }

                // Teaser star (top-right)
                if isTeaser {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.yellow)
                                .padding(6)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: 140, height: 100)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: DT.Radius.medium,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: DT.Radius.medium
                )
            )

            // Filename strip
            HStack {
                Text(displayName)
                    .font(DT.Typography.caption)
                    .foregroundStyle(DT.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DT.Spacing.sm)
            .padding(.vertical, DT.Spacing.xs)
            .frame(width: 140, alignment: .leading)
        }
        .background(
            isSelected ? DT.Colors.accent.opacity(0.12) : DT.Colors.surface,
            in: RoundedRectangle(cornerRadius: DT.Radius.medium)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.medium)
                .stroke(
                    isSelected ? DT.Colors.accent : DT.Colors.border,
                    lineWidth: isSelected ? 1.0 : 0.5
                )
        )
        .overlay(
            // Focus ring — only when the gallery has keyboard focus AND this is selected
            RoundedRectangle(cornerRadius: DT.Radius.medium)
                .stroke(DT.Colors.accent, lineWidth: 1)
                .opacity(isFocused && isSelected ? 1 : 0)
                .padding(-2)
        )
        .dtShadow(isSelected ? DT.Shadow.card : DT.Shadow.Style(color: .clear, radius: 0, y: 0))
        .opacity(isCut ? 0.4 : 1.0)
        .help(fileURL.lastPathComponent)  // tooltip shows full on-disk name
        .task(id: fileURL) {
            await loadThumbnail()
        }
        .onDrag {
            NSItemProvider(object: fileURL as NSURL)
        }
    }

    private func loadThumbnail() async {
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: CGSize(width: 280, height: 200),
            scale: 2.0,
            representationTypes: .thumbnail
        )
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return
        }
        await MainActor.run { thumbnail = rep.nsImage }
    }
}
```

Note: the `.task(id: fileURL)` uses SwiftUI's built-in cancellation — if `fileURL` changes the task is cancelled and restarted, so the grid cell never suffers from the Cleanup stale-callback issue. This is already safe; the change is a no-op correctness improvement while we're here.

- [ ] **Step 4.2: Update the call site in `GalleryView.swift`**

Find the `fileGridItem` function (around line 656) and replace with:

```swift
private func fileGridItem(_ fileURL: URL) -> some View {
    GalleryItemView(
        fileURL: fileURL,
        displayName: FilenameDisplay.display(name: fileURL.lastPathComponent, prefix: displayPrefix),
        isSelected: selection == .file(fileURL),
        isTeaser: isTeaserFile(fileURL),
        isCut: cutFileURL == fileURL,
        isFocused: isGalleryFocused
    )
    .onTapGesture(count: 2) { NSWorkspace.shared.open(fileURL) }
    .onTapGesture(count: 1) { selection = .file(fileURL) }
    .onDrag { NSItemProvider(object: fileURL as NSURL) }
    .contextMenu { fileContextMenu(fileURL) }
}
```

Delete the `.overlay(alignment: .topTrailing)` teaser block (now inside GalleryItemView) and the background/clipShape wrapper (now inside GalleryItemView).

- [ ] **Step 4.3: Add `displayPrefix` and `isGalleryFocused` to `GalleryView`**

Near the existing state declarations in `GalleryView`:

```swift
@FocusState private var isGalleryFocused: Bool
```

Replace the existing `.focusable().focusEffectDisabled()` at the end of the VStack with:

```swift
.focusable()
.focusEffectDisabled()
.focused($isGalleryFocused)
```

And add a computed property on `GalleryView`:

```swift
private var displayPrefix: String {
    "\(project.year)_\(Slug.underscoreFrom(project.title))_"
}
```

- [ ] **Step 4.4: Update the folder grid item to use the card chrome**

Folders stay visually simple but need to pick up the new selection chrome. Replace `folderGridItem` (around line 603) with:

```swift
private func folderGridItem(_ folderURL: URL) -> some View {
    let isSel = selection == .folder(folderURL)
    return VStack(spacing: 0) {
        ZStack {
            Rectangle()
                .fill(DT.Colors.surfaceHover)
            Image(systemName: "folder.fill")
                .font(.system(size: 36))
                .foregroundStyle(DT.Colors.textSecondary)
        }
        .frame(width: 140, height: 100)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: DT.Radius.medium,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: DT.Radius.medium
            )
        )

        HStack {
            Text(folderURL.lastPathComponent)
                .font(DT.Typography.caption)
                .foregroundStyle(DT.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DT.Spacing.sm)
        .padding(.vertical, DT.Spacing.xs)
        .frame(width: 140, alignment: .leading)
    }
    .background(
        isSel ? DT.Colors.accent.opacity(0.12) : DT.Colors.surface,
        in: RoundedRectangle(cornerRadius: DT.Radius.medium)
    )
    .overlay(
        RoundedRectangle(cornerRadius: DT.Radius.medium)
            .stroke(
                isSel ? DT.Colors.accent : DT.Colors.border,
                lineWidth: isSel ? 1.0 : 0.5
            )
    )
    .overlay(
        RoundedRectangle(cornerRadius: DT.Radius.medium)
            .stroke(DT.Colors.accent, lineWidth: 1)
            .opacity(isGalleryFocused && isSel ? 1 : 0)
            .padding(-2)
    )
    .help(folderURL.lastPathComponent)
    .onTapGesture(count: 2) {
        currentSubpath.append(folderURL.lastPathComponent)
        clearSelection()
        scanProjectFolder()
    }
    .onTapGesture(count: 1) {
        selection = .folder(folderURL)
    }
    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
        moveDroppedFiles(providers: providers, into: folderURL)
    }
    .contextMenu { folderContextMenu(folderURL) }
}
```

- [ ] **Step 4.5: Build, run, and eyeball the grid**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' build
```

Launch in Xcode, open a project with several files and a subfolder:
- Confirm cards render with rounded rect + border.
- Confirm filenames strip the `{year}_{slug}_` prefix.
- Confirm extension badges appear in the bottom-right (JPG, MP4, etc.).
- Confirm teaser star still shows top-right.
- Single-click a file → accent border + tinted bg + shadow.
- Single-click a folder → same treatment.
- Double-click a folder → enters folder.
- Hover — no badge or ring flicker.
- Tooltips show full filenames.

- [ ] **Step 4.6: Commit**

```bash
git add PortyMcFolio/Views/GalleryItemView.swift \
        PortyMcFolio/Views/GalleryView.swift
git commit -m "feat: card-style grid cells with prefix-stripped filenames and ext badge"
```

---

## Task 5: List row redesign

Leading thumbnail replaces the SF-symbol, filename uses the same prefix-stripping, selection shows a 2pt accent leading bar.

**Files:**
- Modify: `PortyMcFolio/Views/GalleryListView.swift`
- Modify: `PortyMcFolio/Views/GalleryView.swift` (call site + divider inset)

- [ ] **Step 5.1: Rewrite `GalleryListRow`**

Replace the entire contents of `PortyMcFolio/Views/GalleryListView.swift` with:

```swift
import SwiftUI
import QuickLookThumbnailing

struct GalleryListRow: View {
    let url: URL
    let displayName: String
    let isFolder: Bool
    let isTeaser: Bool
    let isSelected: Bool
    let isCut: Bool
    let isFocused: Bool

    @State private var thumbnail: NSImage?
    @State private var fileSize: String = ""
    @State private var fileDate: String = ""

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    private static let sizeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    private var fallbackIcon: String {
        if isFolder { return "folder.fill" }
        switch url.pathExtension.lowercased() {
        case "pdf":                              return "doc.richtext"
        case "mp4", "mov", "avi", "mkv", "m4v":  return "film"
        case "mp3", "wav", "aac", "m4a",
             "flac", "aiff":                     return "waveform"
        case "jpg", "jpeg", "png", "gif",
             "svg", "webp", "avif", "heic":      return "photo"
        case "usdz", "obj", "stl", "dae", "scn": return "cube"
        default:                                 return "doc"
        }
    }

    var body: some View {
        HStack(spacing: DT.Spacing.md) {
            // Leading accent bar for selection
            Rectangle()
                .fill(isSelected ? DT.Colors.accent : Color.clear)
                .frame(width: 2)

            // Thumbnail (or folder icon)
            ZStack {
                RoundedRectangle(cornerRadius: DT.Radius.small)
                    .fill(DT.Colors.surfaceHover)

                if let thumb = thumbnail, !isFolder {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.small))
                } else {
                    Image(systemName: fallbackIcon)
                        .font(.system(size: 14))
                        .foregroundStyle(DT.Colors.textSecondary)
                }
            }
            .frame(width: 32, height: 32)

            HStack(spacing: DT.Spacing.xs) {
                Text(displayName)
                    .font(DT.Typography.body)
                    .foregroundStyle(DT.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if isTeaser {
                    Image(systemName: "star.fill")
                        .font(DT.Typography.micro)
                        .foregroundStyle(.yellow)
                }
            }
            .help(url.lastPathComponent)

            Spacer()

            if !isFolder {
                Text(fileSize)
                    .font(DT.Typography.caption)
                    .foregroundStyle(DT.Colors.textSecondary)
                    .frame(width: 70, alignment: .trailing)
            }

            Text(fileDate)
                .font(DT.Typography.caption)
                .foregroundStyle(DT.Colors.textSecondary)
                .frame(width: 90, alignment: .trailing)
                .padding(.trailing, DT.Spacing.lg)
        }
        .padding(.vertical, DT.Spacing.sm)
        .background(isSelected ? DT.Colors.accent.opacity(0.12) : Color.clear)
        .overlay(
            // Focus ring for list row — subtle bottom/top hairlines on selected+focused
            RoundedRectangle(cornerRadius: 0)
                .stroke(DT.Colors.accent, lineWidth: 1)
                .opacity(isFocused && isSelected ? 1 : 0)
        )
        .opacity(isCut ? 0.4 : 1.0)
        .contentShape(Rectangle())
        .task(id: url) {
            await loadThumbnail()
            loadFileInfo()
        }
    }

    private func loadThumbnail() async {
        guard !isFolder else { return }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 64, height: 64),
            scale: 2.0,
            representationTypes: .thumbnail
        )
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return
        }
        await MainActor.run { thumbnail = rep.nsImage }
    }

    private func loadFileInfo() {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        if let size = values.fileSize {
            fileSize = Self.sizeFormatter.string(fromByteCount: Int64(size))
        }
        if let date = values.contentModificationDate {
            fileDate = Self.dateFormatter.string(from: date)
        }
    }
}
```

Note the row now has no leading horizontal padding — the leading accent bar sits flush at the row's leading edge. Horizontal padding is handled at the `LazyVStack` level in the caller.

- [ ] **Step 5.2: Update the list-content call sites in `GalleryView.swift`**

Find `listContent` (around line 720) and replace the `folders` and `files` ForEach bodies:

```swift
@ViewBuilder
private var listContent: some View {
    LazyVStack(spacing: 0) {
        ForEach(folders, id: \.absoluteString) { folderURL in
            GalleryListRow(
                url: folderURL,
                displayName: folderURL.lastPathComponent,
                isFolder: true,
                isTeaser: false,
                isSelected: selection == .folder(folderURL),
                isCut: false,
                isFocused: isGalleryFocused
            )
            .padding(.horizontal, DT.Spacing.lg)
            .onTapGesture(count: 2) {
                currentSubpath.append(folderURL.lastPathComponent)
                clearSelection()
                scanProjectFolder()
            }
            .onTapGesture(count: 1) {
                selection = .folder(folderURL)
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                moveDroppedFiles(providers: providers, into: folderURL)
            }
            .contextMenu { folderContextMenu(folderURL) }
            Divider().padding(.leading, DT.Spacing.lg + 2 + DT.Spacing.md + 32 + DT.Spacing.md)
        }

        ForEach(files, id: \.absoluteString) { fileURL in
            GalleryListRow(
                url: fileURL,
                displayName: FilenameDisplay.display(name: fileURL.lastPathComponent, prefix: displayPrefix),
                isFolder: false,
                isTeaser: isTeaserFile(fileURL),
                isSelected: selection == .file(fileURL),
                isCut: cutFileURL == fileURL,
                isFocused: isGalleryFocused
            )
            .padding(.horizontal, DT.Spacing.lg)
            .onTapGesture(count: 2) { NSWorkspace.shared.open(fileURL) }
            .onTapGesture(count: 1) { selection = .file(fileURL) }
            .onDrag { NSItemProvider(object: fileURL as NSURL) }
            .contextMenu { fileContextMenu(fileURL) }
            Divider().padding(.leading, DT.Spacing.lg + 2 + DT.Spacing.md + 32 + DT.Spacing.md)
        }
    }
    .padding(.bottom, 48)
}
```

The divider inset `DT.Spacing.lg + 2 + DT.Spacing.md + 32 + DT.Spacing.md` lines up with the filename column: outer padding (`lg=16`) + accent bar (`2`) + bar→thumb gap (`md=12`) + thumb (`32`) + thumb→name gap (`md=12`) = 74.

- [ ] **Step 5.3: Build, run, and eyeball the list**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' build
```

Launch, switch to list mode, confirm:
- Each row shows a 32×32 thumbnail for files; folder icon for folders.
- Filenames strip the project prefix.
- Selected row shows a 2pt accent bar on the leading edge and accent-tinted bg.
- Hover and cut states still work.
- Divider aligns under the filename (not under the thumbnail).

- [ ] **Step 5.4: Commit**

```bash
git add PortyMcFolio/Views/GalleryListView.swift \
        PortyMcFolio/Views/GalleryView.swift
git commit -m "feat: list rows with leading thumbnails and accent-bar selection"
```

---

## Task 6: Sort toolbar + persistence

Add a menu button to the bottom toolbar. Sort key + direction persist in `UserDefaults`. Grid and list both render the sorted output.

**Files:**
- Modify: `PortyMcFolio/Views/GalleryView.swift`

- [ ] **Step 6.1: Add sort state to GalleryView**

Near the other `@State` declarations:

```swift
@State private var sortKey: GallerySort.SortKey = .name
@State private var sortAscending: Bool = true
```

Add lifecycle helpers:

```swift
private static let sortDefaultsKey = "gallerySortKey"

private func loadSort() {
    guard let raw = UserDefaults.standard.string(forKey: Self.sortDefaultsKey),
          let decoded = GallerySort.decode(raw: raw) else { return }
    sortKey = decoded.key
    sortAscending = decoded.ascending
}

private func persistSort() {
    UserDefaults.standard.set(
        GallerySort.encode(key: sortKey, ascending: sortAscending),
        forKey: Self.sortDefaultsKey
    )
}
```

Call `loadSort()` from the existing `.onAppear` block inside `body` (where `scanProjectFolder()` is already called).

Persist with `.onChange` modifiers on the body (add them near the existing `.onAppear`/`.onDisappear`):

```swift
.onChange(of: sortKey) { _, _ in persistSort() }
.onChange(of: sortAscending) { _, _ in persistSort() }
```

This is more reliable than `didSet` on `@State` (which does not fire on all Swift/SwiftUI versions).

- [ ] **Step 6.2: Introduce sorted accessors**

Replace the direct `files` and `folders` reads in `gridContent` and `listContent` with a precomputed result, so sort runs once per render:

Add a computed property:

```swift
private var sortedContent: GallerySort.Result {
    GallerySort.sort(files: files, folders: folders, by: sortKey, ascending: sortAscending)
}
```

In `gridContent`:

```swift
@ViewBuilder
private var gridContent: some View {
    let content = sortedContent
    LazyVGrid(columns: columns, spacing: DT.Spacing.lg) {
        ForEach(content.folders, id: \.absoluteString) { folderURL in
            folderGridItem(folderURL)
        }
        ForEach(content.files, id: \.absoluteString) { fileURL in
            fileGridItem(fileURL)
        }
    }
    .padding(DT.Spacing.lg)
    .padding(.bottom, 48)
}
```

In `listContent`, do the same — bind `let content = sortedContent` at the top, iterate `content.folders` and `content.files`.

- [ ] **Step 6.3: Add the sort button to the toolbar**

Locate the bottom toolbar `HStack` (around line 104 — starts with `HStack(spacing: DT.Spacing.xs) { // Action buttons`). Insert the sort menu between the action cluster and the separator rectangle:

```swift
// Sort menu
Menu {
    Section("Sort by") {
        Button {
            sortKey = .name
        } label: {
            if sortKey == .name { Image(systemName: "checkmark") }
            Text("Name")
        }
        Button {
            sortKey = .kind
        } label: {
            if sortKey == .kind { Image(systemName: "checkmark") }
            Text("Kind")
        }
    }
    Section("Order") {
        Button {
            sortAscending = true
        } label: {
            if sortAscending { Image(systemName: "checkmark") }
            Text("Ascending")
        }
        Button {
            sortAscending = false
        } label: {
            if !sortAscending { Image(systemName: "checkmark") }
            Text("Descending")
        }
    }
} label: {
    Image(systemName: "arrow.up.arrow.down")
        .font(.system(size: 12))
        .foregroundStyle(DT.Colors.textTertiary)
        .frame(width: 26, height: 26)
        .contentShape(Rectangle())
}
.menuStyle(.borderlessButton)
.menuIndicator(.hidden)
.fixedSize()
.help("Sort")
```

- [ ] **Step 6.4: Remove the old hard-coded sorted reads in `scanProjectFolder`**

`scanProjectFolder` currently does:

```swift
files = scannedFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }
folders = scannedFolders.sorted { $0.lastPathComponent < $1.lastPathComponent }
```

Leave these alone for now — they provide a stable order for things that look at raw `files` / `folders` (stale-selection cleanup, Cleanup popup initial list). The `sortedContent` computed property does the display-time sort on top. This preserves existing behavior for callers that expect alphabetical order.

- [ ] **Step 6.5: Build, run, and verify**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' build
```

Manual checks:
- Open a project with files of varied kinds (at least one image, one video, one doc).
- Click the new sort icon in the bottom toolbar → menu opens.
- Switch to Kind → files regroup by category (image, video, audio, doc, 3d, other).
- Switch to Descending → order reverses within each section.
- Switch views (grid ↔ list) — same order.
- Quit and relaunch — sort setting persists.

- [ ] **Step 6.6: Commit**

```bash
git add PortyMcFolio/Views/GalleryView.swift
git commit -m "feat: name/kind sort menu in gallery toolbar with persistence"
```

---

## Task 7: 2-D keyboard navigation

Rewrite `navigateSelection` to treat the grid as a true 2-D structure and include folders in the navigable sequence. List mode uses the same sequence, ignores ←/→. Enter on a folder enters it.

**Files:**
- Modify: `PortyMcFolio/Views/GalleryView.swift`

- [ ] **Step 7.1: Track the grid's measured width**

Add a state var:

```swift
@State private var gridWidth: CGFloat = 0
```

Wrap the `gridContent` body in a `GeometryReader`:

```swift
@ViewBuilder
private var gridContent: some View {
    let content = sortedContent
    GeometryReader { geo in
        LazyVGrid(columns: columns, spacing: DT.Spacing.lg) {
            ForEach(content.folders, id: \.absoluteString) { folderURL in
                folderGridItem(folderURL)
            }
            ForEach(content.files, id: \.absoluteString) { fileURL in
                fileGridItem(fileURL)
            }
        }
        .padding(DT.Spacing.lg)
        .padding(.bottom, 48)
        .onAppear { gridWidth = geo.size.width }
        .onChange(of: geo.size.width) { _, newValue in gridWidth = newValue }
    }
}
```

- [ ] **Step 7.2: Introduce a navigable-sequence helper**

Add inside `GalleryView`:

```swift
/// Flat sequence of selectable items in current-view render order.
/// Used for keyboard navigation. Links mode returns link ids; all other
/// modes return folders-then-files as GallerySelection cases.
private var navigableSequence: [GallerySelection] {
    if viewMode == .links {
        return links.map { .link($0.id) }
    }
    let content = sortedContent
    return content.folders.map { GallerySelection.folder($0) }
         + content.files.map { GallerySelection.file($0) }
}

private var gridColumnCount: Int {
    max(1, Int((gridWidth / 150).rounded(.down)))
}
```

- [ ] **Step 7.3: Rewrite `navigateSelection`**

Replace the existing `navigateSelection(by:)` (around line 802) with two functions:

```swift
private enum NavDirection {
    case left, right, up, down, first, last
}

private func navigate(_ direction: NavDirection) {
    let seq = navigableSequence
    guard !seq.isEmpty else { return }

    let currentIdx = selection.flatMap { seq.firstIndex(of: $0) }

    let newIdx: Int
    switch direction {
    case .left:
        newIdx = currentIdx.map { max(0, $0 - 1) } ?? 0
    case .right:
        newIdx = currentIdx.map { min(seq.count - 1, $0 + 1) } ?? 0
    case .up:
        let step = viewMode == .grid ? gridColumnCount : 1
        newIdx = currentIdx.map { max(0, $0 - step) } ?? 0
    case .down:
        let step = viewMode == .grid ? gridColumnCount : 1
        newIdx = currentIdx.map { min(seq.count - 1, $0 + step) } ?? 0
    case .first:
        newIdx = 0
    case .last:
        newIdx = seq.count - 1
    }

    selection = seq[newIdx]

    // If QuickLook is open on a file, follow the selection
    if previewURL != nil, case .file(let url) = selection {
        previewURL = nil
        DispatchQueue.main.async { previewURL = url }
    }
}
```

- [ ] **Step 7.4: Rewrite the key-press handlers**

Replace the existing four arrow-key `.onKeyPress` handlers (around lines 177-180) with the keyed-phase form below. The keyed form receives a `KeyPress` struct so we can check modifiers; the 1-arg `.onKeyPress(.upArrow)` form does not supply one.

```swift
.onKeyPress(keys: [.upArrow], phases: .down) { key in
    if key.modifiers.contains(.command) {
        navigate(.first)
    } else {
        navigate(.up)
    }
    return .handled
}
.onKeyPress(keys: [.downArrow], phases: .down) { key in
    if key.modifiers.contains(.command) {
        navigate(.last)
    } else {
        navigate(.down)
    }
    return .handled
}
.onKeyPress(keys: [.leftArrow], phases: .down) { _ in
    if viewMode == .list { return .ignored }
    navigate(.left)
    return .handled
}
.onKeyPress(keys: [.rightArrow], phases: .down) { _ in
    if viewMode == .list { return .ignored }
    navigate(.right)
    return .handled
}
```

The existing `.onKeyPress(phases: .down) { keyPress in … }` block for `⌘X`, `⌘V`, `⌘[` still applies. Update its `⌘X` branch to match the new selection type:

```swift
case "x":
    if case .file(let url) = selection { cutFileURL = url }
    return .handled
```

- [ ] **Step 7.5: Update `handleReturnKey` to dive into folders**

Replace `handleReturnKey` (around line 289):

```swift
private func handleReturnKey() -> KeyPress.Result {
    switch selection {
    case .file(let url):
        if let index = files.firstIndex(of: url) {
            startCleanup(from: index)
            return .handled
        }
        return .ignored
    case .folder(let url):
        currentSubpath.append(url.lastPathComponent)
        clearSelection()
        scanProjectFolder()
        return .handled
    case .link(let id):
        if let link = links.first(where: { $0.id == id }) {
            NSWorkspace.shared.open(link.url)
            return .handled
        }
        return .ignored
    case .none:
        return .ignored
    }
}
```

- [ ] **Step 7.6: Update `handleSpaceKey` for GallerySelection**

Replace `handleSpaceKey` (around line 274):

```swift
private func handleSpaceKey() -> KeyPress.Result {
    switch selection {
    case .file(let url):
        previewURL = nil
        DispatchQueue.main.async { previewURL = url }
        return .handled
    case .link(let id):
        if let link = links.first(where: { $0.id == id }) {
            LinkPreviewPanel.shared.preview(url: link.url, title: link.title)
            return .handled
        }
        return .ignored
    case .folder, .none:
        return .ignored
    }
}
```

- [ ] **Step 7.7: Build, run, and verify navigation**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' build
```

Manual checks (grid with 4+ columns, at least one folder and 8+ files):
- Click one file to select → focus ring appears on that cell.
- ↓ moves to the cell visually below (not one cell right).
- ↑ at top row: ignored (no move, no beep).
- ←/→ wrap across rows.
- ⌘↑ jumps to the first folder; ⌘↓ jumps to the last file.
- Enter on a folder enters the folder.
- Enter on a file starts Cleanup on that file.
- Switch to list mode: ↑/↓ work, ←/→ ignored.
- Switch to links mode: ↑/↓ walk through links.

- [ ] **Step 7.8: Commit**

```bash
git add PortyMcFolio/Views/GalleryView.swift
git commit -m "feat: 2-D keyboard navigation for gallery with folder-dive on Enter"
```

---

## Task 8: Cleanup popup — stale thumbnail guard (5a)

**Files:**
- Modify: `PortyMcFolio/Views/CleanupPopup.swift`

- [ ] **Step 8.1: Guard the callback against stale fires**

In `loadCurrentFile()` (around line 274), replace:

```swift
QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
    DispatchQueue.main.async {
        thumbnail = rep?.nsImage
    }
}
```

with:

```swift
let targetURL = file
QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
    DispatchQueue.main.async {
        guard self.currentFile == targetURL else { return }
        thumbnail = rep?.nsImage
    }
}
```

- [ ] **Step 8.2: Manual verification**

1. Build and launch.
2. Open a project with several video files in the same folder.
3. Click the sparkles "Clean Up" button.
4. Rapidly press `⌘→` through the sequence (faster than thumbnails generate).
5. Confirm the thumbnail shown always matches the filename in the "FILE N OF M" strip and the rename input.

- [ ] **Step 8.3: Commit**

```bash
git add PortyMcFolio/Views/CleanupPopup.swift
git commit -m "fix: Cleanup popup guards thumbnail callback against stale fires"
```

---

## Task 9: Cleanup popup — sparkles button respects selection (5b)

**Files:**
- Modify: `PortyMcFolio/Views/GalleryView.swift`

- [ ] **Step 9.1: Compute start index from selection**

Find the sparkles `galleryAction` call (around line 148):

```swift
galleryAction(icon: "sparkles", help: "Clean Up") {
    startCleanup()
}
```

Replace with:

```swift
galleryAction(icon: "sparkles", help: "Clean Up") {
    let idx: Int
    if case .file(let url) = selection, let i = files.firstIndex(of: url) {
        idx = i
    } else {
        idx = 0
    }
    startCleanup(from: idx)
}
```

- [ ] **Step 9.2: Manual verification**

1. Build and launch; open a project with several files.
2. Click the 3rd file in the grid to select it.
3. Click the sparkles button.
4. Confirm the Cleanup popup opens on that file (title bar: `FILE 3 OF N`), not `FILE 1 OF N`.
5. Clear selection (click empty space or ESC), click sparkles → opens on file 1.

- [ ] **Step 9.3: Commit**

```bash
git add PortyMcFolio/Views/GalleryView.swift
git commit -m "fix: Cleanup sparkles button starts at the selected file's index"
```

---

## Task 10: Final verification pass

No code changes — end-to-end walk-through of every spec requirement.

- [ ] **Step 10.1: Run the full test suite**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test
```

Expected: all tests pass. If any fail, return to the relevant task before declaring done.

- [ ] **Step 10.2: Manual verification — grid**

Open a project with:
- At least 2 subfolders (one with a long name)
- At least 6 files: 1 image, 1 video, 1 audio, 1 pdf, 1 with an 8+-char description after the project prefix, 1 without any prefix.

Verify:
- Cells render as rounded cards with borders.
- Files with matching `{year}_{slug}_` prefix show only the suffix.
- The file without a matching prefix shows its full name.
- Long descriptions truncate in the middle (e.g. `some_long_nam…part2.mp4`).
- Extension badges appear (JPG, MP4, MP3, PDF).
- Teaser star renders top-right when applicable.
- Tooltips show full on-disk names.
- Single-click a file → accent border, accent-tinted bg, small shadow.
- Single-click a folder → same selection treatment.
- Double-click a folder → enters it.
- Hover on idle cell → darker surface.
- Cut (⌘X) dims cell to 40% opacity.

- [ ] **Step 10.3: Manual verification — list**

Same project, switch to list view.
- Every file row has a 32×32 thumbnail (image for images, fallback SF icon while generating).
- Folder rows show the folder icon at the same 32×32 slot.
- Filenames strip prefix same as grid.
- Selected row shows 2pt accent leading bar + tinted bg.
- Size + date columns still render.
- Divider aligns under the filename column (not under the thumbnail).

- [ ] **Step 10.4: Manual verification — sort**

- Default on first launch: Name / Ascending (matches pre-change behavior).
- Switch to Kind / Ascending → files group `image, video, audio, doc, 3d, other`.
- Within each kind group, files are alphabetical.
- Switch to Descending → all sections and files reverse.
- Switch between grid and list → same order.
- Quit and relaunch → sort setting persists.

- [ ] **Step 10.5: Manual verification — selection / focus**

- Click inside the editor, then click back into the gallery area (but not on any cell) → gallery has focus but no selection ring visible.
- Arrow-key into the grid → focus ring appears on selected cell.
- Tab / click into editor → focus ring disappears (selection bg tint remains).
- Tab / click back into gallery → focus ring reappears.

- [ ] **Step 10.6: Manual verification — keyboard nav**

- ↓ in a 4-column grid moves by 4; ↑ by 4.
- ←/→ wrap across rows.
- At top row, ↑ is a no-op.
- ⌘↑ jumps to the first folder; ⌘↓ to the last file.
- In list mode, ↑/↓ walk the folders-then-files sequence; ←/→ do nothing.
- Enter on a file starts Cleanup at that file; Enter on a folder enters it.
- Space on a file opens QuickLook; Space on a folder is a no-op.

- [ ] **Step 10.7: Manual verification — Cleanup popup**

- Spam ⌘→ through a video-heavy folder. No thumbnail/filename mismatch.
- Select file 3, click sparkles → Cleanup opens on file 3.
- Click sparkles with no selection → opens on file 1.

- [ ] **Step 10.8: Confirm no stray regressions**

- Drag a file out of the grid onto an editor line → still embeds as `![[...]]`.
- Drag a file from Finder into the grid → still copies into current folder.
- Rename a folder via its context menu → references in the readme still rewrite.
- Set a file as teaser → star appears top-right in the grid.

If every step checks out, the implementation matches the spec.

---

## Post-implementation

**Flagged follow-ups** (spec §Follow-ups) — not part of this plan:
- Responsive grid thumbnails / size slider.
- Unified browse + preview pane.
- `trashFile` leaves dangling `![[folder/file]]` embeds when a folder is deleted.
- Multi-select + batch operations.
- Per-project sort override.
