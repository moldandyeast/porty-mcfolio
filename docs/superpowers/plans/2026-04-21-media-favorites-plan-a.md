# Media Favorites — Plan A (Data + Gallery Hearts + Scaffolding)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Users can favorite individual media files in the Gallery view (heart icon). Favorites persist as a new `favorites:` YAML array in the project's frontmatter and survive in-app rename/move/trash via the existing `updateReadmeReferences` / `renameFolder` hooks. ⌘5 and a new toolbar icon open an empty-state placeholder view — the actual `CarouselView` ships in Plan B.

**Architecture:** Strictly additive. New pure service `MediaKind` (delegates to the existing `GallerySort.category(for:)`). New `favorites: [String]` property on `Project` + `ParsedFrontmatter`, parsed/serialized via the `teaser`/`hidden` "omit-when-empty" pattern with path-safety validation. Two small pure helpers on `FrontmatterParser` rewrite favorites for exact-path (file rename/move) and prefix (folder rename); both are called from `GalleryView.updateReadmeReferences` / `renameFolder`. Heart button is an overlay on `GalleryItemView` in a `ZStack`, with tap-isolation verified at implementation time. New `ViewMode.carousel` case, ⌘5 in `CommandMenu("View")`, new toolbar icon in `ProjectDetailView`, and a placeholder view that renders when `viewMode == .carousel`.

**Tech Stack:** SwiftUI macOS 14+ (deployment 14.0), AppKit, XCTest, XcodeGen for project regeneration, Yams for YAML, GRDB (unchanged).

**Spec:** `docs/superpowers/specs/2026-04-21-media-favorites-carousel-design.md`
**Branch:** `feature/media-favorites-carousel`
**Worktree:** `<repo>/.worktrees/media-favorites/`

---

## File map

| File | Change |
|---|---|
| `PortyMcFolio/Services/MediaKind.swift` | **Create.** Pure enum delegating to `GallerySort.category(for:)`. |
| `PortyMcFolioTests/MediaKindTests.swift` | **Create.** Delegation + nil for non-media. |
| `PortyMcFolio/Models/Project.swift` | Add `favorites: [String] = []` property. Default value in initializer. |
| `PortyMcFolio/Services/FrontmatterParser.swift` | Add `favorites` to `ParsedFrontmatter`, parse + serialize blocks, `isValidFavoritePath` validator, two rewrite helpers (`rewritingFavorite(in:from:to:)` and `rewritingFavoritePrefix(in:from:to:)`). |
| `PortyMcFolioTests/FrontmatterParserTests.swift` | Add tests for favorites parse/serialize/validation/helpers. |
| `PortyMcFolio/Views/GalleryView.swift` | Extend `updateReadmeReferences` to rewrite favorites via helper. Extend `renameFolder` to rewrite favorites prefix via helper. Add heart overlay button on `fileGridItem` and the list row. Add `toggleFavorite(_:)` + `isFavorited(_:)` helpers. |
| `PortyMcFolio/App/AppState.swift` | Add `case carousel = 4` to `ViewMode` enum. |
| `PortyMcFolio/App/PortyMcFolioApp.swift` | Add ⌘5 Button to `CommandMenu("View")`. |
| `PortyMcFolio/Views/ProjectDetailView.swift` | Add `.carousel` case in view-mode switch (returns placeholder). Add Carousel toolbar icon. |
| `project.yml` | **Not modified.** XcodeGen's recursive sources pattern picks up new files automatically. |
| `PortyMcFolio.xcodeproj/project.pbxproj` | Regenerated via `xcodegen generate` when new files are added (Tasks 1, 2). |

## Shared commands

Run all commands from inside the worktree: `cd <repo>/.worktrees/media-favorites`.

**Build:**
```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' -quiet build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

**Test:**
```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test 2>&1 \
  | grep -E "(Test Suite 'All tests'|failed|error:)" | tail -5
```
Expected: `Test Suite 'All tests' passed`.

**Regenerate xcodeproj** (after adding new source files):
```bash
xcodegen generate
```
Expected: `Created project at PortyMcFolio.xcodeproj`. Commit the resulting `project.pbxproj` delta.

**Manual run** (launch the app from the worktree's DerivedData):
```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' -derivedDataPath build -quiet build \
  && open build/Build/Products/Debug/PortyMcFolio.app
```

---

### Task 1: `MediaKind` service + tests

Create the media-classification service that everything else depends on. It delegates to `GallerySort.category(for:)` — single source of truth for extension classification.

**Files:**
- Create: `PortyMcFolio/Services/MediaKind.swift`
- Create: `PortyMcFolioTests/MediaKindTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `PortyMcFolioTests/MediaKindTests.swift`:

```swift
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
```

- [ ] **Step 2: Regenerate project and verify test fails (missing type)**

```bash
xcodegen generate
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' -quiet test 2>&1 | tail -10
```
Expected: compile error `cannot find 'MediaKind' in scope` in `MediaKindTests.swift`.

- [ ] **Step 3: Write the implementation**

Create `PortyMcFolio/Services/MediaKind.swift`:

```swift
import Foundation

/// Classifies a file URL as image / video / audio by delegating to
/// `GallerySort.category(for:)`. Single source of truth for extension
/// classification — if GallerySort gains or changes an extension, the
/// carousel picks it up automatically.
enum MediaKind: String {
    case image
    case video
    case audio

    static func from(url: URL) -> MediaKind? {
        switch GallerySort.category(for: url) {
        case .image: return .image
        case .video: return .video
        case .audio: return .audio
        default:     return nil
        }
    }

    static func isMedia(url: URL) -> Bool {
        from(url: url) != nil
    }
}
```

- [ ] **Step 4: Regenerate and run tests**

```bash
xcodegen generate
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test 2>&1 | grep -E "(MediaKindTests|All tests)" | tail -10
```
Expected: `Test Suite 'MediaKindTests' passed` + `Test Suite 'All tests' passed`.

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Services/MediaKind.swift PortyMcFolioTests/MediaKindTests.swift PortyMcFolio.xcodeproj
git commit -m "feat: MediaKind service delegating to GallerySort"
```

---

### Task 2: `Project.favorites` property

Add the favorites storage to the model. Defaults to empty. No parsing/serializing yet — just the property and its initializer default.

**Files:**
- Modify: `PortyMcFolio/Models/Project.swift`

- [ ] **Step 1: Add the property + initializer default**

In `Project.swift`, after the `var teaser: String` line (around line 25), add:

```swift
var teaser: String
var favorites: [String] = []
var hidden: Bool = false
```

Then update the `from(folderName:, rootURL:)` initializer (around line 79) — the explicit `Project(...)` construction needs the default too. Since the property has a default value (`= []`), Swift's memberwise initializer is fine, but the explicit `Project(...)` call inside `from` must pass `favorites: []`:

```swift
return Project(
    uid: uid,
    year: year,
    folderName: folderName,
    folderURL: folderURL,
    title: "",
    date: Date(),
    tags: [],
    client: "",
    status: .empty,
    body: "",
    teaser: "",
    favorites: []
)
```

Note the argument order matches Swift's memberwise synthesis (same order as the struct fields).

- [ ] **Step 2: Update `loadReadme` to read the new field**

Find the `mutating func loadReadme()` (around line 95) and add one line after `teaser = parsed.teaser`:

```swift
teaser = parsed.teaser
favorites = parsed.favorites
hidden = parsed.hidden
```

(You'll extend `ParsedFrontmatter.favorites` in Task 3 — this line refers ahead, which is fine because Task 3 adds the field and a compile error here will be fixed there.)

- [ ] **Step 3: Build to verify the ordering**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' -quiet build 2>&1 | tail -5
```
Expected: a compile error on `parsed.favorites` ("has no member 'favorites'") — normal, we fix in Task 3. **Do not commit this yet** — Task 3 lands the compile fix in the same commit flow.

---

### Task 3: `FrontmatterParser` parse + serialize + path validation

Extend the parser to read and write the `favorites:` field, validating entries on parse to reject absolute / `~` / `../` paths and non-string YAML entries.

**Files:**
- Modify: `PortyMcFolio/Services/FrontmatterParser.swift`
- Modify: `PortyMcFolioTests/FrontmatterParserTests.swift`

- [ ] **Step 1: Write the failing tests**

In `PortyMcFolioTests/FrontmatterParserTests.swift`, append inside `final class FrontmatterParserTests`:

```swift
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
```

- [ ] **Step 2: Run tests to verify failure**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test 2>&1 | tail -10
```
Expected: compile errors — `ParsedFrontmatter` has no `favorites` member, `FrontmatterParser` has no `isValidFavoritePath`.

- [ ] **Step 3: Add `favorites` to `ParsedFrontmatter`**

In `FrontmatterParser.swift`, add the field to the struct (around line 11):

```swift
struct ParsedFrontmatter {
    var title: String
    var date: Date
    var tags: [String]
    var client: String
    var status: ProjectStatus
    var body: String
    var teaser: String
    var favorites: [String] = []
    var hidden: Bool = false
}
```

- [ ] **Step 4: Add `isValidFavoritePath`**

In `FrontmatterParser.swift`, add this public helper (after the `enum ParseError` and before the existing `parse(_:)` function):

```swift
/// Rejects absolute paths, `~`-relative paths, `../` escapes, null bytes,
/// and empty strings. Everything else is treated as a valid project-relative
/// path (we don't verify it exists here — reconciler handles missing files).
static func isValidFavoritePath(_ path: String) -> Bool {
    guard !path.isEmpty,
          !path.hasPrefix("/"),
          !path.hasPrefix("~"),
          !path.contains(".."),
          !path.contains("\0")
    else { return false }
    return true
}
```

- [ ] **Step 5: Parse favorites**

In `FrontmatterParser.parse(_:)`, after the `teaser` parse line (around line 130) and before the `hidden` parse line, add:

```swift
let teaser = dict["teaser"] as? String ?? ""

// Parse favorites — defensive: drop non-strings and invalid paths.
let favoritesRaw = dict["favorites"] as? [Any] ?? []
let favorites = favoritesRaw
    .compactMap { $0 as? String }
    .filter { isValidFavoritePath($0) }

let hidden = dict["hidden"] as? Bool ?? false
```

Then update the return statement to include `favorites`:

```swift
return ParsedFrontmatter(
    title: title,
    date: date,
    tags: tags,
    client: client,
    status: status,
    body: body,
    teaser: teaser,
    favorites: favorites,
    hidden: hidden
)
```

Also update the other early-return `ParsedFrontmatter(...)` constructions in the same function (the "no frontmatter" and "no closing delimiter" branches) to include `favorites: []`:

```swift
return ParsedFrontmatter(
    title: "",
    date: Date(),
    tags: [],
    client: "",
    status: .empty,
    body: markdown,
    teaser: "",
    favorites: [],
    hidden: false
)
```

There are three such early-return sites — update all three.

- [ ] **Step 6: Serialize favorites**

In `FrontmatterParser.serialize(frontmatter:)`, after the `teaser` append block and before the `hidden` block (around line 170):

```swift
if !fm.teaser.isEmpty {
    lines.append("teaser: \(yamlEscaped(fm.teaser))")
}
if !fm.favorites.isEmpty {
    let items = fm.favorites.map { yamlEscaped($0) }.joined(separator: ", ")
    lines.append("favorites: [\(items)]")
}
if fm.hidden {
    lines.append("hidden: true")
}
```

Same "omit when empty" pattern as `teaser` / `hidden`.

- [ ] **Step 7: Run tests — should pass**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test 2>&1 \
  | grep -E "(FrontmatterParser|All tests)" | tail -10
```
Expected: `Test Suite 'FrontmatterParserTests' passed` and `Test Suite 'All tests' passed`.

- [ ] **Step 8: Commit Tasks 2 + 3 together**

Task 2's Project.swift edit left a compile error that Task 3 fixes. Ship them as one commit:

```bash
git add PortyMcFolio/Models/Project.swift \
        PortyMcFolio/Services/FrontmatterParser.swift \
        PortyMcFolioTests/FrontmatterParserTests.swift
git commit -m "feat: Project.favorites with parse/serialize + path validation"
```

---

### Task 4: `FrontmatterParser` rewrite helpers

Two small pure helpers that rewrite favorites when a file is renamed/moved/trashed (exact match) or a folder is renamed (prefix match). They're pure functions on arrays so they're easy to unit-test; `GalleryView` calls them in Task 5.

**Files:**
- Modify: `PortyMcFolio/Services/FrontmatterParser.swift`
- Modify: `PortyMcFolioTests/FrontmatterParserTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `FrontmatterParserTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify failure**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test 2>&1 | tail -10
```
Expected: compile errors — `FrontmatterParser` has no `rewritingFavorite` or `rewritingFavoritePrefix`.

- [ ] **Step 3: Add the helpers**

In `FrontmatterParser.swift`, after `isValidFavoritePath` (the helper from Task 3):

```swift
/// Rewrites a favorites list when a file is renamed/moved/trashed.
/// - `to` is the new relative path, or empty string if the file was trashed.
/// - Rewrites every occurrence of `from` to `to` (preserves duplicates).
/// - If `to` is empty, removes every occurrence of `from`.
static func rewritingFavorite(
    in favorites: [String],
    from oldRelative: String,
    to newRelative: String
) -> [String] {
    if newRelative.isEmpty {
        return favorites.filter { $0 != oldRelative }
    }
    return favorites.map { $0 == oldRelative ? newRelative : $0 }
}

/// Rewrites a favorites list when a folder is renamed. Matches entries
/// whose path begins with `from + "/"` and swaps only that prefix.
/// Uses a proper path-component match so `photos` doesn't accidentally
/// match `otherphotos`.
static func rewritingFavoritePrefix(
    in favorites: [String],
    from oldPrefix: String,
    to newPrefix: String
) -> [String] {
    let old = "\(oldPrefix)/"
    let new = "\(newPrefix)/"
    return favorites.map { path in
        path.hasPrefix(old)
            ? new + path.dropFirst(old.count)
            : path
    }
}
```

- [ ] **Step 4: Run tests — should pass**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test 2>&1 \
  | grep -E "(FrontmatterParserTests|All tests)" | tail -5
```
Expected: `Test Suite 'FrontmatterParserTests' passed`.

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Services/FrontmatterParser.swift \
        PortyMcFolioTests/FrontmatterParserTests.swift
git commit -m "feat: FrontmatterParser rewrite helpers for favorites"
```

---

### Task 5: Wire favorites rewrites into `GalleryView`

Extend `updateReadmeReferences` (exact-path) and `renameFolder` (folder prefix) to rewrite favorites in lockstep with teaser / body embeds, via the helpers from Task 4. No UI change yet.

**Files:**
- Modify: `PortyMcFolio/Views/GalleryView.swift`

- [ ] **Step 1: Extend `updateReadmeReferences`**

Find `updateReadmeReferences(oldRelative:, newRelative:)` around line 1112. After the "2. Body image embeds" block and before the `guard changed else { return }`:

```swift
// 2. Body image embeds
let oldEmbed = "![[\(oldRelative)]]"
if parsed.body.contains(oldEmbed) {
    parsed.body = parsed.body.replacingOccurrences(of: oldEmbed, with: "![[\(newRelative)]]")
    changed = true
}

// 3. Frontmatter favorites array
let newFavorites = FrontmatterParser.rewritingFavorite(
    in: parsed.favorites,
    from: oldRelative,
    to: newRelative
)
if newFavorites != parsed.favorites {
    parsed.favorites = newFavorites
    changed = true
}

guard changed else { return }
```

- [ ] **Step 2: Extend `renameFolder`**

Find `renameFolder()` around line 1225. Locate the inline rewrite block (around line 1250) that checks `parsed.body` and `parsed.teaser`. After the teaser prefix rewrite and before the `if changed` write-back:

```swift
let teaserFolderPrefix = "\(oldPrefix)/"
if parsed.teaser.hasPrefix(teaserFolderPrefix) {
    parsed.teaser = "\(newPrefix)/" + parsed.teaser.dropFirst(teaserFolderPrefix.count)
    changed = true
}

// Favorites prefix rewrite
let newFavorites = FrontmatterParser.rewritingFavoritePrefix(
    in: parsed.favorites,
    from: oldPrefix,
    to: newPrefix
)
if newFavorites != parsed.favorites {
    parsed.favorites = newFavorites
    changed = true
}

if changed {
    let updated = FrontmatterParser.serialize(frontmatter: parsed)
    ...
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' -quiet build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual verify — smoke test with a hand-edited frontmatter**

1. Pick any project in your portfolio.
2. Quit the app if running.
3. Edit its project markdown file: add a `favorites: ["test.jpg"]` line to the frontmatter (ensure `test.jpg` exists in the project folder — or use any existing image's relative path).
4. Launch the app, open the project.
5. In Gallery, drag that file into a subfolder (or use cut/paste).
6. Quit the app.
7. Re-open the markdown file in a text editor. Verify the `favorites:` entry now points to the new path.

Expected: the favorite path in frontmatter matches the file's new location. If the drag invoked `updateReadmeReferences` correctly, the rewrite happened automatically.

If this doesn't work, check:
- Did the path actually change via `moveFile` or `moveDroppedFiles`? Both call `updateReadmeReferences`.
- Is `parsed.favorites` being written? Add a `print("[fav] rewrote \(newFavorites)")` inside the new block to confirm.

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Views/GalleryView.swift
git commit -m "feat(gallery): rewrite favorites on file + folder rename/move"
```

---

### Task 6: Heart button on Gallery grid tile

Add the heart button overlay on media-file tiles in the grid. Click toggles the favorite. Always-visible: outline heart for non-favorited, filled for favorited. Hover brightens the outline to full opacity. Click is tap-isolated from the tile's existing select/open gestures.

**Files:**
- Modify: `PortyMcFolio/Views/GalleryView.swift`

- [ ] **Step 1: Add `toggleFavorite` and `isFavorited` helpers**

Find `setTeaser(_:)` around line 1067. Add these next to it:

```swift
private func isFavorited(_ url: URL) -> Bool {
    project.favorites.contains(relativePath(for: url))
}

private func toggleFavorite(_ url: URL) {
    // Flush any pending editor save before we read the README, so the user's
    // typed-but-not-yet-saved edits are on disk when we rewrite frontmatter.
    NotificationCenter.default.post(name: .markdownSaveNow, object: nil)

    let rel = relativePath(for: url)
    guard let content = try? String(contentsOf: project.readmeURL, encoding: .utf8),
          var parsed = try? FrontmatterParser.parse(content) else { return }

    if let idx = parsed.favorites.firstIndex(of: rel) {
        parsed.favorites.remove(at: idx)
    } else {
        parsed.favorites.append(rel)
    }

    let updated = FrontmatterParser.serialize(frontmatter: parsed)
    do {
        try updated.write(to: project.readmeURL, atomically: true, encoding: .utf8)
    } catch {
        showAlert(title: "Can't Update Favorites",
                  message: "Failed to save: \(error.localizedDescription)")
        return
    }
    NotificationCenter.default.post(name: .markdownFileDidChange, object: project.readmeURL)
    appState.notifyProjectFileChanged(uid: project.uid)
}
```

- [ ] **Step 2: Extract a heart-button subview**

In `GalleryView.swift`, above `fileGridItem(_ fileURL: URL)` (around line 864):

```swift
@ViewBuilder
private func favoriteHeartButton(for fileURL: URL, isHovering: Bool) -> some View {
    let favorited = isFavorited(fileURL)
    Button {
        toggleFavorite(fileURL)
    } label: {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 22, height: 22)
            Image(systemName: favorited ? "heart.fill" : "heart")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(
                    favorited
                        ? theme.colors.accent
                        : theme.colors.textPrimary.opacity(isHovering ? 1.0 : 0.5)
                )
        }
    }
    .buttonStyle(.plain)
    .contentShape(Circle())
    .help(favorited ? "Remove from carousel" : "Add to carousel")
}
```

- [ ] **Step 3: Overlay the heart on the grid tile — try the simple approach**

Modify `fileGridItem(_ fileURL: URL)`. First, wrap in a ZStack with a `@State` hover flag. Replace the current body (around lines 864-877) with:

```swift
private func fileGridItem(_ fileURL: URL) -> some View {
    FileGridTileWithHeart(
        fileURL: fileURL,
        displayName: FilenameDisplay.display(name: fileURL.lastPathComponent, prefix: displayPrefix),
        isSelected: selection == .file(fileURL),
        isTeaser: isTeaserFile(fileURL),
        isCut: cutFileURL == fileURL,
        isFocused: isGalleryFocused,
        showHeart: MediaKind.isMedia(url: fileURL),
        heartButton: { hovering in
            favoriteHeartButton(for: fileURL, isHovering: hovering)
        },
        onSelect: { selection = .file(fileURL) },
        onOpen: { NSWorkspace.shared.open(fileURL) },
        fileContextMenu: { fileContextMenu(fileURL) }
    )
}
```

Then add the `FileGridTileWithHeart` wrapper inside `GalleryView`'s file (top-level, or inside an `extension` block near the other subviews):

```swift
/// Wraps `GalleryItemView` with a hover-aware heart overlay and keeps
/// the original tap / drag / context gestures attached to the tile.
/// The heart's `Button` naturally wins hit-test precedence over the
/// tile's tap gestures because it's the topmost layer in the ZStack.
private struct FileGridTileWithHeart<HeartButton: View, FileMenu: View>: View {
    let fileURL: URL
    let displayName: String
    let isSelected: Bool
    let isTeaser: Bool
    let isCut: Bool
    let isFocused: Bool
    let showHeart: Bool
    @ViewBuilder let heartButton: (_ isHovering: Bool) -> HeartButton
    let onSelect: () -> Void
    let onOpen: () -> Void
    @ViewBuilder let fileContextMenu: () -> FileMenu

    @State private var isHovering: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GalleryItemView(
                fileURL: fileURL,
                displayName: displayName,
                isSelected: isSelected,
                isTeaser: isTeaser,
                isCut: isCut,
                isFocused: isFocused
            )
            .onTapGesture(count: 2) { onOpen() }
            .onTapGesture(count: 1) { onSelect() }
            .onDrag { NSItemProvider(object: fileURL as NSURL) }
            .contextMenu { fileContextMenu() }

            if showHeart {
                heartButton(isHovering)
                    .padding(6)
            }
        }
        .onHover { hovering in isHovering = hovering }
    }
}
```

- [ ] **Step 4: Build**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' -quiet build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual verify — heart click + tap isolation**

1. Launch the app, open a project with a mix of media files (`.jpg`, `.mp4`, `.mp3`) and non-media (`.txt`).
2. Go to Gallery (⌘3).
3. Confirm heart appears ONLY on media tiles; non-media (`.txt`, `.md`) has no heart.
4. Hover a media tile → outline heart goes to full opacity. Mouse away → back to 50%.
5. Click the heart → heart fills with accent color. Also: tile is NOT selected, did NOT open in QuickLook. (If selection changes or QuickLook opens, tap-isolation is broken — see fallback below.)
6. Click a non-heart area of the tile → tile selects as before.
7. Double-click a non-heart area → file opens in QuickLook as before.
8. Re-click the heart → heart un-fills (outline).
9. Close and re-open the project. The previously-favorited files still show filled hearts (persisted to frontmatter).

**Fallback if Step 5 shows tap-isolation is broken** (double-fire: click heart AND select the tile):

Restructure `FileGridTileWithHeart` to hoist the tap gestures. Replace the two `.onTapGesture` modifiers on `GalleryItemView` with a single `.onTapGesture` on the `ZStack`, and have that handler decide whether the click was in the heart area (by tracking hover location) or on the tile. That's more involved; do this only if the simple approach double-fires. The simple approach is tried first because macOS SwiftUI generally honors the topmost-child-wins rule for taps.

- [ ] **Step 6: Commit**

```bash
git add PortyMcFolio/Views/GalleryView.swift
git commit -m "feat(gallery): heart button on media tiles in grid"
```

---

### Task 7: Heart button on Gallery list row

Same toggle in list mode. The list-mode file row is built around line 954-969 of `GalleryView.swift` — `GalleryListRow(...)` with chained `.onTapGesture(count: 2)`, `.onTapGesture(count: 1)`, `.onDrag`, `.contextMenu`. Wrap it in a ZStack-overlay pattern similar to `FileGridTileWithHeart`.

**Files:**
- Modify: `PortyMcFolio/Views/GalleryView.swift`

- [ ] **Step 1: Add a `FileListRowWithHeart` wrapper**

In `GalleryView.swift`, next to `FileGridTileWithHeart` (from Task 6), add:

```swift
/// Wraps `GalleryListRow` with a trailing heart overlay. Mirrors
/// `FileGridTileWithHeart` but uses a trailing-aligned ZStack so the
/// heart sits at the row's right edge instead of the top-right corner.
private struct FileListRowWithHeart<HeartButton: View, FileMenu: View>: View {
    let fileURL: URL
    let displayName: String
    let isTeaser: Bool
    let isSelected: Bool
    let isCut: Bool
    let isFocused: Bool
    let showHeart: Bool
    @ViewBuilder let heartButton: (_ isHovering: Bool) -> HeartButton
    let onSelect: () -> Void
    let onOpen: () -> Void
    @ViewBuilder let fileContextMenu: () -> FileMenu

    @State private var isHovering: Bool = false

    var body: some View {
        ZStack(alignment: .trailing) {
            GalleryListRow(
                url: fileURL,
                displayName: displayName,
                isFolder: false,
                isTeaser: isTeaser,
                isSelected: isSelected,
                isCut: isCut,
                isFocused: isFocused
            )
            .onTapGesture(count: 2) { onOpen() }
            .onTapGesture(count: 1) { onSelect() }
            .onDrag { NSItemProvider(object: fileURL as NSURL) }
            .contextMenu { fileContextMenu() }

            if showHeart {
                heartButton(isHovering)
                    .padding(.trailing, DT.Spacing.md)
            }
        }
        .onHover { hovering in isHovering = hovering }
    }
}
```

- [ ] **Step 2: Replace the list row construction**

Find the list-mode `ForEach(content.files, ...)` block around line 954. Replace the entire inline `GalleryListRow(...)` + gestures block with:

```swift
ForEach(content.files, id: \.absoluteString) { fileURL in
    FileListRowWithHeart(
        fileURL: fileURL,
        displayName: FilenameDisplay.display(name: fileURL.lastPathComponent, prefix: displayPrefix),
        isTeaser: isTeaserFile(fileURL),
        isSelected: selection == .file(fileURL),
        isCut: cutFileURL == fileURL,
        isFocused: isGalleryFocused,
        showHeart: MediaKind.isMedia(url: fileURL),
        heartButton: { hovering in
            favoriteHeartButton(for: fileURL, isHovering: hovering)
        },
        onSelect: { selection = .file(fileURL) },
        onOpen: { NSWorkspace.shared.open(fileURL) },
        fileContextMenu: { fileContextMenu(fileURL) }
    )
    .padding(.horizontal, DT.Spacing.lg)
    Divider().padding(.leading, Self.listDividerInset)
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' -quiet build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manual verify**

1. Launch the app, switch Gallery to list mode.
2. Media rows show a heart at the trailing edge. Non-media rows and folder rows have no heart.
3. Hover a row → outline heart brightens. Mouse away → back to 50% opacity.
4. Click the heart → heart fills with accent color, frontmatter updates.
5. Clicking elsewhere on the row still selects; double-click still opens.
6. Switch to grid — the same files show the filled heart (state persists via frontmatter).

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Views/GalleryView.swift
git commit -m "feat(gallery): heart button on media rows in list mode"
```

---

### Task 8: `ViewMode.carousel` + ⌘5 + toolbar icon + empty-state placeholder

Scaffold the view-mode plumbing without writing the actual slideshow. Pressing ⌘5 or clicking the new toolbar icon switches to a placeholder view that says the full carousel is coming in Plan B. This lets users verify favoriting works end-to-end and that the scaffolding is sound.

**Files:**
- Modify: `PortyMcFolio/App/AppState.swift`
- Modify: `PortyMcFolio/App/PortyMcFolioApp.swift`
- Modify: `PortyMcFolio/Views/ProjectDetailView.swift`

- [ ] **Step 1: Add `carousel` to `ViewMode`**

In `PortyMcFolio/App/AppState.swift` (around line 10):

```swift
enum ViewMode: Int, Codable {
    case editor = 0
    case preview = 1
    case split = 2
    case gallery = 3
    case carousel = 4
}
```

- [ ] **Step 2: Add ⌘5 to the App's `CommandMenu("View")`**

In `PortyMcFolio/App/PortyMcFolioApp.swift` (around line 40, after the Gallery button):

```swift
Button("Gallery") {
    appState.viewMode = .gallery
}
.keyboardShortcut("3", modifiers: .command)

Button("Carousel") {
    appState.viewMode = .carousel
}
.keyboardShortcut("5", modifiers: .command)
```

- [ ] **Step 3: Add the toolbar icon to `ProjectDetailView`**

In `PortyMcFolio/Views/ProjectDetailView.swift`, inside the `ToolbarItemGroup(placement: .automatic)` block (around line 215, after the Gallery button):

```swift
// Gallery
Button {
    appState.viewMode = .gallery
} label: {
    Image(systemName: "square.grid.2x2")
        .font(.system(size: 12))
        .foregroundStyle(appState.viewMode == .gallery ? theme.colors.textPrimary : theme.colors.textTertiary)
}
.buttonStyle(.plain)
.help("Gallery")

// Carousel
Button {
    appState.viewMode = .carousel
} label: {
    Image(systemName: "rectangle.stack.badge.play")
        .font(.system(size: 12))
        .foregroundStyle(appState.viewMode == .carousel ? theme.colors.textPrimary : theme.colors.textTertiary)
}
.buttonStyle(.plain)
.help("Carousel")
```

- [ ] **Step 4: Add the placeholder view**

In `ProjectDetailView.swift`, find the top-level `switch appState.viewMode` (around line 24). Add a `.carousel` case:

```swift
case .gallery:
    GalleryView(project: project)
        .frame(maxWidth: .infinity)
        .transition(.opacity)

case .carousel:
    CarouselPlaceholderView(project: project)
        .frame(maxWidth: .infinity)
        .transition(.opacity)
}
```

Then add `CarouselPlaceholderView` below `ProjectDetailView`'s body (same file, top level, or at the bottom as a private helper struct):

```swift
private struct CarouselPlaceholderView: View {
    let project: Project
    @Environment(\.theme) var theme

    var body: some View {
        VStack(spacing: DT.Spacing.md) {
            Image(systemName: "rectangle.stack.badge.play")
                .font(.system(size: 48))
                .foregroundStyle(theme.colors.textTertiary)

            if project.favorites.isEmpty {
                Text("No favorites yet")
                    .font(DT.Typography.title)
                    .foregroundStyle(theme.colors.textPrimary)
                Text("Heart items in Gallery (⌘3) to build your carousel.")
                    .font(DT.Typography.body)
                    .foregroundStyle(theme.colors.textSecondary)
            } else {
                Text("\(project.favorites.count) favorited")
                    .font(DT.Typography.title)
                    .foregroundStyle(theme.colors.textPrimary)
                Text("Carousel slideshow ships in Plan B.")
                    .font(DT.Typography.body)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
    }
}
```

- [ ] **Step 5: Build**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' -quiet build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Manual verify**

1. Launch the app, open any project.
2. Press ⌘5 → placeholder shows either "No favorites yet" (if empty) or "N favorited" (if Task 6 was used to favorite some files).
3. Click the new toolbar icon → same placeholder opens.
4. Press ⌘1 (Editor) → editor shows. Press ⌘5 → placeholder. Press ⌘2 (Split in App menu) → split shows. Confirm ⌘5 doesn't accidentally fire from split-mode editor focus.
5. Open View menu (top bar) → "Carousel" entry appears with ⌘5.
6. From the carousel placeholder, press ESC → back to overview (same as other view modes).
7. Toolbar icon for carousel highlights (`textPrimary` color) when `viewMode == .carousel`, dim (`textTertiary`) otherwise.

- [ ] **Step 7: Commit**

```bash
git add PortyMcFolio/App/AppState.swift \
        PortyMcFolio/App/PortyMcFolioApp.swift \
        PortyMcFolio/Views/ProjectDetailView.swift
git commit -m "feat: ViewMode.carousel + ⌘5 + toolbar icon + placeholder view"
```

---

### Task 9: End-to-end verification pass

One integrated walkthrough to catch anything the per-task checks missed.

- [ ] **Step 1: Full build + test**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' -quiet build 2>&1 | tail -5
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio \
  -destination 'platform=macOS' test 2>&1 \
  | grep -E "(Test Suite 'All tests'|failed)" | tail -5
```
Expected: `** BUILD SUCCEEDED **` and `Test Suite 'All tests' passed`.

- [ ] **Step 2: Favoriting round-trip in the running app**

1. Open a project, go to Gallery (⌘3).
2. Heart three media files (grid).
3. Switch to list mode. Confirm those three show filled hearts.
4. Heart a fourth from list mode. Switch back to grid — fourth is filled.
5. Press ⌘5 → placeholder says "4 favorited".
6. Quit the app entirely.
7. Open the project's markdown in a plain text editor. Verify:
   ```yaml
   favorites: ["photos/a.jpg", "videos/b.mp4", "audio/c.mp3", "photos/d.png"]
   ```
8. Re-launch app, open the project, Gallery → same four filled hearts.

- [ ] **Step 3: Rename/move preserves favorites**

1. Start from the state above (four favorites).
2. In Gallery, drag one of the favorited files into a subfolder.
3. Verify its heart still shows filled after the drag.
4. Quit the app. Open the markdown. Confirm the favorite's path reflects the new location.
5. Open the app. Rename the containing folder via the folder context menu.
6. Verify the favorites in the file now all reflect the renamed folder's path.

- [ ] **Step 4: Trash removes from favorites**

1. Heart a file.
2. Trash it via Gallery context menu.
3. Markdown no longer contains that entry in `favorites:`.

- [ ] **Step 5: Hand-edit safety**

1. Quit the app.
2. Edit the markdown. Add bad entries to `favorites`: `favorites: ["ok.jpg", "/abs/evil.jpg", "../escape.jpg", "~/home.jpg"]` (keep `ok.jpg` pointing at an existing file).
3. Launch the app, open the project. Only the valid entry is used — Gallery shows one filled heart, carousel placeholder says "1 favorited".
4. Heart another file → save flushes. Open the markdown. The bad entries are gone (they were dropped on parse).

- [ ] **Step 6: No commit needed**

Verification only. If any step fails, fix in the relevant task before declaring Plan A done.

---

## Completion checklist

- [ ] Tasks 1–8 complete with green `xcodebuild build` + `test` after each
- [ ] 8 commits on `feature/media-favorites-carousel` (one per implementation task)
- [ ] Task 9 end-to-end verification passes
- [ ] `MediaKind`, `Project.favorites`, frontmatter parse/serialize, rewrite helpers, GalleryView wiring, heart UI (grid + list), `ViewMode.carousel` scaffolding, ⌘5, toolbar icon, placeholder view all in place
- [ ] No modifications to `ProjectReconciler`, `AppState.updateProjectMetadata`, or the existing view modes (`.editor / .preview / .split / .gallery`)

Plan B picks up from here: real `CarouselView.swift`, image/video/audio rendering, thumbnail tray, and the reconciler's basename-heuristic safety net.
