# PortyMcFolio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS Swift app for creatives to manage a local portfolio — combining a project organizer, gallery-first file browser with rich previews, and an Obsidian-compatible Tiptap WYSIWYG markdown editor with full-text search.

**Architecture:** SwiftUI shell for navigation and gallery, WKWebView + Tiptap v2 for the markdown editor, SQLite FTS5 for search, FSEvents for file watching. Two-level drill-down: project list -> project detail (editor + gallery). All data lives on the filesystem; the SQLite index is derived and rebuildable.

**Tech Stack:** Swift 5.9+, SwiftUI, macOS 14+, WKWebView, Tiptap v2 (bundled JS), GRDB.swift (SQLite), Yams (YAML parsing), XcodeGen (project generation), Vite (editor bundling)

---

## File Structure

```
PortyMcFolio/
├── project.yml                          # XcodeGen project definition
├── Package.swift                        # SPM dependencies (GRDB, Yams)
├── PortyMcFolio/
│   ├── App/
│   │   ├── PortyMcFolioApp.swift        # @main app entry, window setup
│   │   └── AppState.swift               # ObservableObject: selected project, portfolio root, navigation
│   ├── Models/
│   │   ├── ProjectStatus.swift          # Enum: draft, active, complete, archived
│   │   ├── Project.swift                # Project struct: folder path, parsed frontmatter
│   │   └── LinkItem.swift               # LinkItem struct: url, title, annotation, date
│   ├── Services/
│   │   ├── FrontmatterParser.swift      # Parse/serialize YAML frontmatter from markdown strings
│   │   ├── Slug.swift                   # String slugification utility
│   │   ├── PortfolioStore.swift         # Root folder bookmark, scan for projects, CRUD
│   │   ├── ProjectCreator.swift         # Create project folders + starter README.md
│   │   ├── SearchIndex.swift            # SQLite FTS5: index projects, query
│   │   └── FileWatcher.swift            # FSEvents wrapper for portfolio root
│   ├── Views/
│   │   ├── ContentView.swift            # Root: onboarding vs main navigation
│   │   ├── FolderPickerView.swift       # NSOpenPanel onboarding for portfolio root
│   │   ├── ProjectListView.swift        # Level 1: grid of project cards + search bar
│   │   ├── ProjectCardView.swift        # Single project card: title, year, status, tags
│   │   ├── TagPillView.swift            # Reusable tag pill component
│   │   ├── StatusBadgeView.swift        # Reusable status badge component
│   │   ├── NewProjectSheet.swift        # Sheet: name, client, tags -> create project
│   │   ├── ProjectDetailView.swift      # Level 2: back button + editor/gallery tabs
│   │   ├── EditorView.swift             # NSViewRepresentable wrapping WKWebView for Tiptap
│   │   ├── GalleryView.swift            # LazyVGrid of thumbnails + link cards
│   │   ├── GalleryItemView.swift        # Single file thumbnail with label
│   │   ├── LinkCardView.swift           # Link item card in gallery
│   │   └── AddLinkSheet.swift           # Sheet: URL, title, annotation -> create link file
│   ├── Editor/
│   │   ├── EditorBridge.swift           # WKScriptMessageHandler: Swift <-> JS communication
│   │   └── Resources/
│   │       ├── editor.html              # HTML shell loading Tiptap
│   │       ├── editor.css               # Editor theme/typography
│   │       └── editor.bundle.js         # Built Tiptap bundle (output from Editor/ npm project)
│   └── QuickLook/
│       └── QuickLookCoordinator.swift   # QLPreviewPanel integration for space-bar preview
├── PortyMcFolioTests/
│   ├── FrontmatterParserTests.swift
│   ├── SlugTests.swift
│   ├── ProjectTests.swift
│   ├── LinkItemTests.swift
│   ├── ProjectCreatorTests.swift
│   ├── PortfolioStoreTests.swift
│   └── SearchIndexTests.swift
└── Editor/                              # npm project for building Tiptap bundle
    ├── package.json
    ├── vite.config.js
    └── src/
        ├── index.js                     # Tiptap editor setup + Swift bridge
        ├── markdown-serializer.js       # MD <-> Tiptap document conversion
        └── extensions/
            ├── frontmatter.js           # YAML frontmatter node
            ├── wikilink.js              # [[Wiki Link]] inline node
            └── media-embed.js           # ![[file]] embed node
```

---

### Task 1: Project Scaffolding

**Files:**
- Create: `project.yml`
- Create: `Package.swift`
- Create: `PortyMcFolio/App/PortyMcFolioApp.swift`
- Create: `PortyMcFolioTests/.gitkeep`

- [ ] **Step 1: Install XcodeGen if needed**

Run: `brew install xcodegen`
Expected: xcodegen available on PATH

- [ ] **Step 2: Create Package.swift for SPM dependencies**

Create `Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PortyMcFolioDeps",
    platforms: [.macOS(.v14)],
    products: [],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: []
)
```

- [ ] **Step 3: Create project.yml for XcodeGen**

Create `project.yml`:

```yaml
name: PortyMcFolio
options:
  bundleIdPrefix: com.portymcfolio
  deploymentTarget:
    macOS: "14.0"
  xcodeVersion: "15.0"
  createIntermediateGroups: true

packages:
  GRDB:
    url: https://github.com/groue/GRDB.swift.git
    from: 7.0.0
  Yams:
    url: https://github.com/jpsim/Yams.git
    from: 5.0.0

targets:
  PortyMcFolio:
    type: application
    platform: macOS
    sources:
      - path: PortyMcFolio
    resources:
      - path: PortyMcFolio/Editor/Resources
        buildPhase: resources
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.portymcfolio.app
        INFOPLIST_KEY_LSApplicationCategoryType: "public.app-category.productivity"
        INFOPLIST_KEY_NSHumanReadableCopyright: ""
        MACOSX_DEPLOYMENT_TARGET: "14.0"
        SWIFT_VERSION: "5.9"
        PRODUCT_NAME: PortyMcFolio
    dependencies:
      - package: GRDB
        product: GRDB
      - package: Yams
    entitlements:
      path: PortyMcFolio/PortyMcFolio.entitlements
      properties:
        com.apple.security.app-sandbox: true
        com.apple.security.files.user-selected.read-write: true

  PortyMcFolioTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: PortyMcFolioTests
    dependencies:
      - target: PortyMcFolio
      - package: GRDB
        product: GRDB
      - package: Yams
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.portymcfolio.tests
```

- [ ] **Step 4: Create minimal app entry point**

Create `PortyMcFolio/App/PortyMcFolioApp.swift`:

```swift
import SwiftUI

@main
struct PortyMcFolioApp: App {
    var body: some Scene {
        WindowGroup {
            Text("PortyMcFolio")
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.titleBar)
    }
}
```

- [ ] **Step 5: Create entitlements file**

Create `PortyMcFolio/PortyMcFolio.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 6: Create test placeholder**

Create `PortyMcFolioTests/PortyMcFolioTests.swift`:

```swift
import XCTest

final class PortyMcFolioTests: XCTestCase {
    func testAppLaunches() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 7: Generate Xcode project and verify build**

Run: `cd /path/to/PortyMcFolio && xcodegen generate`
Expected: `Generated PortyMcFolio.xcodeproj`

Run: `xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

Run: `xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' test`
Expected: TEST SUCCEEDED, 1 test passed

- [ ] **Step 8: Commit**

```bash
git add project.yml Package.swift PortyMcFolio/ PortyMcFolioTests/
git commit -m "feat: scaffold Xcode project with XcodeGen, GRDB, and Yams"
```

---

### Task 2: Data Models — ProjectStatus, Slug, FrontmatterParser

**Files:**
- Create: `PortyMcFolio/Models/ProjectStatus.swift`
- Create: `PortyMcFolio/Services/Slug.swift`
- Create: `PortyMcFolio/Services/FrontmatterParser.swift`
- Create: `PortyMcFolioTests/SlugTests.swift`
- Create: `PortyMcFolioTests/FrontmatterParserTests.swift`

- [ ] **Step 1: Write failing tests for ProjectStatus**

Create `PortyMcFolioTests/FrontmatterParserTests.swift` (we'll add frontmatter tests in a later step — start with status):

```swift
import XCTest
@testable import PortyMcFolio

final class ProjectStatusTests: XCTestCase {
    func testStatusRawValues() {
        XCTAssertEqual(ProjectStatus.draft.rawValue, "draft")
        XCTAssertEqual(ProjectStatus.active.rawValue, "active")
        XCTAssertEqual(ProjectStatus.complete.rawValue, "complete")
        XCTAssertEqual(ProjectStatus.archived.rawValue, "archived")
    }

    func testStatusFromRawValue() {
        XCTAssertEqual(ProjectStatus(rawValue: "draft"), .draft)
        XCTAssertEqual(ProjectStatus(rawValue: "invalid"), nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: FAIL — `ProjectStatus` not found

- [ ] **Step 3: Implement ProjectStatus**

Create `PortyMcFolio/Models/ProjectStatus.swift`:

```swift
import Foundation

enum ProjectStatus: String, Codable, CaseIterable, Identifiable {
    case draft
    case active
    case complete
    case archived

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodegen generate && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Write failing tests for Slug**

Create `PortyMcFolioTests/SlugTests.swift`:

```swift
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
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: FAIL — `Slug` not found

- [ ] **Step 7: Implement Slug**

Create `PortyMcFolio/Services/Slug.swift`:

```swift
import Foundation

enum Slug {
    static func from(_ input: String) -> String {
        let slug = input
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .replacingOccurrences(
                of: "[^a-z0-9\\s-]",
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: "[\\s-]+",
                with: "-",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return slug.isEmpty ? "untitled" : slug
    }
}
```

- [ ] **Step 8: Run test to verify it passes**

Run: `xcodegen generate && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 9: Write failing tests for FrontmatterParser**

Create `PortyMcFolioTests/FrontmatterParserTests.swift` (replace the status-only file):

```swift
import XCTest
@testable import PortyMcFolio

final class ProjectStatusTests: XCTestCase {
    func testStatusRawValues() {
        XCTAssertEqual(ProjectStatus.draft.rawValue, "draft")
        XCTAssertEqual(ProjectStatus.active.rawValue, "active")
        XCTAssertEqual(ProjectStatus.complete.rawValue, "complete")
        XCTAssertEqual(ProjectStatus.archived.rawValue, "archived")
    }

    func testStatusFromRawValue() {
        XCTAssertEqual(ProjectStatus(rawValue: "draft"), .draft)
        XCTAssertEqual(ProjectStatus(rawValue: "invalid"), nil)
    }
}

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
        XCTAssertEqual(result.status, .active)
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
        XCTAssertEqual(result.status, .draft)
        XCTAssertTrue(result.body.contains("Just a heading"))
    }

    func testSerializeFrontmatter() throws {
        let parsed = try FrontmatterParser.parse(sampleMarkdown)
        let serialized = FrontmatterParser.serialize(frontmatter: parsed)
        XCTAssertTrue(serialized.hasPrefix("---\n"))
        XCTAssertTrue(serialized.contains("title: \"Brand Identity — Acme\""))
        XCTAssertTrue(serialized.contains("status: active"))
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
}
```

- [ ] **Step 10: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: FAIL — `FrontmatterParser` not found

- [ ] **Step 11: Implement FrontmatterParser**

Create `PortyMcFolio/Services/FrontmatterParser.swift`:

```swift
import Foundation
import Yams

struct ParsedFrontmatter {
    var title: String
    var date: Date
    var tags: [String]
    var client: String
    var status: ProjectStatus
    var body: String
}

enum FrontmatterParser {
    private static let frontmatterPattern = try! NSRegularExpression(
        pattern: "\\A---\\n(.*?)\\n---\\n?",
        options: [.dotMatchesLineSeparators]
    )

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func parse(_ markdown: String) throws -> ParsedFrontmatter {
        let range = NSRange(markdown.startIndex..., in: markdown)
        guard let match = frontmatterPattern.firstMatch(in: markdown, range: range),
              let yamlRange = Range(match.range(at: 1), in: markdown) else {
            return ParsedFrontmatter(
                title: "",
                date: Date(),
                tags: [],
                client: "",
                status: .draft,
                body: markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        let yamlString = String(markdown[yamlRange])
        let fullMatchRange = Range(match.range, in: markdown)!
        let body = String(markdown[fullMatchRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let yaml = try Yams.load(yaml: yamlString) as? [String: Any] else {
            return ParsedFrontmatter(
                title: "", date: Date(), tags: [], client: "", status: .draft, body: body
            )
        }

        let title = yaml["title"] as? String ?? ""
        let client = yaml["client"] as? String ?? ""
        let tags = yaml["tags"] as? [String] ?? []
        let statusStr = yaml["status"] as? String ?? "draft"
        let status = ProjectStatus(rawValue: statusStr) ?? .draft

        var date = Date()
        if let dateStr = yaml["date"] as? String,
           let parsed = dateFormatter.date(from: dateStr) {
            date = parsed
        } else if let dateVal = yaml["date"] as? Date {
            date = dateVal
        }

        return ParsedFrontmatter(
            title: title,
            date: date,
            tags: tags,
            client: client,
            status: status,
            body: body
        )
    }

    static func serialize(frontmatter fm: ParsedFrontmatter) -> String {
        let tagsStr = fm.tags.isEmpty ? "[]" : "[\(fm.tags.joined(separator: ", "))]"
        let dateStr = dateFormatter.string(from: fm.date)
        let clientLine = fm.client.isEmpty ? "client: \"\"" : "client: \"\(fm.client)\""

        return """
        ---
        title: "\(fm.title)"
        date: \(dateStr)
        tags: \(tagsStr)
        \(clientLine)
        status: \(fm.status.rawValue)
        ---

        \(fm.body)
        """
    }
}
```

- [ ] **Step 12: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: ALL PASS

- [ ] **Step 13: Commit**

```bash
git add PortyMcFolio/Models/ProjectStatus.swift PortyMcFolio/Services/Slug.swift PortyMcFolio/Services/FrontmatterParser.swift PortyMcFolioTests/
git commit -m "feat: add ProjectStatus, Slug, and FrontmatterParser with tests"
```

---

### Task 3: Data Models — Project and LinkItem

**Files:**
- Create: `PortyMcFolio/Models/Project.swift`
- Create: `PortyMcFolio/Models/LinkItem.swift`
- Create: `PortyMcFolioTests/ProjectTests.swift`
- Create: `PortyMcFolioTests/LinkItemTests.swift`

- [ ] **Step 1: Write failing tests for Project**

Create `PortyMcFolioTests/ProjectTests.swift`:

```swift
import XCTest
@testable import PortyMcFolio

final class ProjectTests: XCTestCase {
    func testProjectFromFolderName() throws {
        let project = try Project.from(
            folderName: "2025-brand-identity-acme-a3f1b2c4",
            rootURL: URL(fileURLWithPath: "/tmp/portfolio")
        )
        XCTAssertEqual(project.year, 2025)
        XCTAssertEqual(project.uid, "a3f1b2c4")
        XCTAssertEqual(project.folderName, "2025-brand-identity-acme-a3f1b2c4")
        XCTAssertEqual(
            project.folderURL.path,
            "/tmp/portfolio/2025-brand-identity-acme-a3f1b2c4"
        )
        XCTAssertEqual(
            project.readmeURL.path,
            "/tmp/portfolio/2025-brand-identity-acme-a3f1b2c4/README.md"
        )
    }

    func testProjectFolderName() {
        let name = Project.folderName(title: "Brand Identity — Acme", year: 2025, uid: "a3f1b2c4")
        XCTAssertEqual(name, "2025-brand-identity-acme-a3f1b2c4")
    }

    func testProjectFromInvalidFolderNameThrows() {
        XCTAssertThrowsError(try Project.from(
            folderName: "not-a-valid-folder",
            rootURL: URL(fileURLWithPath: "/tmp/portfolio")
        ))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: FAIL — `Project` not found

- [ ] **Step 3: Implement Project**

Create `PortyMcFolio/Models/Project.swift`:

```swift
import Foundation

struct Project: Identifiable, Equatable {
    let uid: String
    let year: Int
    let folderName: String
    let folderURL: URL
    var title: String
    var date: Date
    var tags: [String]
    var client: String
    var status: ProjectStatus
    var body: String

    var id: String { uid }

    var readmeURL: URL {
        folderURL.appendingPathComponent("README.md")
    }

    /// Build the standard folder name: {Year}-{slug}-{uid}
    static func folderName(title: String, year: Int, uid: String) -> String {
        let slug = Slug.from(title)
        return "\(year)-\(slug)-\(uid)"
    }

    /// Parse a project from its folder name and root URL.
    /// Folder must match pattern: {4-digit year}-{slug}-{8-char hex uid}
    static func from(folderName: String, rootURL: URL) throws -> Project {
        let parts = folderName.split(separator: "-")
        guard parts.count >= 3,
              let year = Int(parts[0]),
              year >= 1900 && year <= 2100,
              parts.last!.count == 8 else {
            throw ProjectError.invalidFolderName(folderName)
        }

        let uid = String(parts.last!)
        let folderURL = rootURL.appendingPathComponent(folderName)

        return Project(
            uid: uid,
            year: year,
            folderName: folderName,
            folderURL: folderURL,
            title: "",
            date: Date(),
            tags: [],
            client: "",
            status: .draft,
            body: ""
        )
    }

    /// Load frontmatter from README.md on disk into this project.
    mutating func loadReadme() throws {
        let content = try String(contentsOf: readmeURL, encoding: .utf8)
        let parsed = try FrontmatterParser.parse(content)
        title = parsed.title
        date = parsed.date
        tags = parsed.tags
        client = parsed.client
        status = parsed.status
        body = parsed.body
    }
}

enum ProjectError: Error, LocalizedError {
    case invalidFolderName(String)

    var errorDescription: String? {
        switch self {
        case .invalidFolderName(let name):
            return "Invalid project folder name: \(name)"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Write failing tests for LinkItem**

Create `PortyMcFolioTests/LinkItemTests.swift`:

```swift
import XCTest
@testable import PortyMcFolio

final class LinkItemTests: XCTestCase {

    func testParseLinkMarkdown() throws {
        let md = """
        ---
        type: link
        url: "https://dribbble.com/shots/12345"
        title: "Dribbble — Final Concepts"
        annotation: "Client loved option B"
        date: 2025-03-15
        ---
        """

        let link = try LinkItem.parse(markdown: md)
        XCTAssertEqual(link.url.absoluteString, "https://dribbble.com/shots/12345")
        XCTAssertEqual(link.title, "Dribbble — Final Concepts")
        XCTAssertEqual(link.annotation, "Client loved option B")
    }

    func testLinkFileName() {
        let name = LinkItem.fileName(uid: "b2c4d6e8")
        XCTAssertEqual(name, "link-b2c4d6e8.md")
    }

    func testSerializeLinkMarkdown() throws {
        let link = LinkItem(
            uid: "b2c4d6e8",
            url: URL(string: "https://example.com")!,
            title: "Example",
            annotation: "A test link",
            date: ISO8601DateFormatter().date(from: "2025-03-15T00:00:00Z")!
        )
        let md = link.toMarkdown()
        XCTAssertTrue(md.contains("type: link"))
        XCTAssertTrue(md.contains("url: \"https://example.com\""))
        XCTAssertTrue(md.contains("title: \"Example\""))
        XCTAssertTrue(md.contains("annotation: \"A test link\""))
    }

    func testIsLinkFile() {
        XCTAssertTrue(LinkItem.isLinkFile(name: "link-a3f1b2c4.md"))
        XCTAssertFalse(LinkItem.isLinkFile(name: "README.md"))
        XCTAssertFalse(LinkItem.isLinkFile(name: "link-short.md"))
    }
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: FAIL — `LinkItem` not found

- [ ] **Step 7: Implement LinkItem**

Create `PortyMcFolio/Models/LinkItem.swift`:

```swift
import Foundation
import Yams

struct LinkItem: Identifiable, Equatable {
    let uid: String
    let url: URL
    var title: String
    var annotation: String
    var date: Date

    var id: String { uid }

    static func fileName(uid: String) -> String {
        "link-\(uid).md"
    }

    static func isLinkFile(name: String) -> Bool {
        let pattern = #"^link-[a-f0-9]{8}\.md$"#
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    static func parse(markdown: String) throws -> LinkItem {
        let frontmatterPattern = try NSRegularExpression(
            pattern: "\\A---\\n(.*?)\\n---",
            options: [.dotMatchesLineSeparators]
        )
        let range = NSRange(markdown.startIndex..., in: markdown)
        guard let match = frontmatterPattern.firstMatch(in: markdown, range: range),
              let yamlRange = Range(match.range(at: 1), in: markdown),
              let yaml = try Yams.load(yaml: String(markdown[yamlRange])) as? [String: Any],
              let urlStr = yaml["url"] as? String,
              let url = URL(string: urlStr) else {
            throw LinkItemError.invalidFormat
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        var date = Date()
        if let dateStr = yaml["date"] as? String,
           let parsed = dateFormatter.date(from: dateStr) {
            date = parsed
        } else if let dateVal = yaml["date"] as? Date {
            date = dateVal
        }

        // Extract UID from filename pattern if available, otherwise generate
        let uid = String(UUID().uuidString.prefix(8)).lowercased()

        return LinkItem(
            uid: uid,
            url: url,
            title: yaml["title"] as? String ?? "",
            annotation: yaml["annotation"] as? String ?? "",
            date: date
        )
    }

    func toMarkdown() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        return """
        ---
        type: link
        url: "\(url.absoluteString)"
        title: "\(title)"
        annotation: "\(annotation)"
        date: \(dateFormatter.string(from: date))
        ---
        """
    }
}

enum LinkItemError: Error {
    case invalidFormat
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: ALL PASS

- [ ] **Step 9: Commit**

```bash
git add PortyMcFolio/Models/ PortyMcFolioTests/
git commit -m "feat: add Project and LinkItem models with parsing and serialization"
```

---

### Task 4: ProjectCreator Service

**Files:**
- Create: `PortyMcFolio/Services/ProjectCreator.swift`
- Create: `PortyMcFolioTests/ProjectCreatorTests.swift`

- [ ] **Step 1: Write failing tests**

Create `PortyMcFolioTests/ProjectCreatorTests.swift`:

```swift
import XCTest
@testable import PortyMcFolio

final class ProjectCreatorTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testCreateProject() throws {
        let project = try ProjectCreator.create(
            title: "Brand Identity — Acme",
            client: "Acme Corp",
            tags: ["branding", "identity"],
            rootURL: tempDir
        )

        // Folder exists
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: project.folderURL.path, isDirectory: &isDir
        ))
        XCTAssertTrue(isDir.boolValue)

        // README.md exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.readmeURL.path))

        // Folder name matches pattern
        let name = project.folderName
        let year = Calendar.current.component(.year, from: Date())
        XCTAssertTrue(name.hasPrefix("\(year)-brand-identity-acme-"))
        XCTAssertEqual(project.uid.count, 8)

        // README content is valid
        let content = try String(contentsOf: project.readmeURL, encoding: .utf8)
        let parsed = try FrontmatterParser.parse(content)
        XCTAssertEqual(parsed.title, "Brand Identity — Acme")
        XCTAssertEqual(parsed.client, "Acme Corp")
        XCTAssertEqual(parsed.tags, ["branding", "identity"])
        XCTAssertEqual(parsed.status, .draft)
    }

    func testCreateProjectSlugsName() throws {
        let project = try ProjectCreator.create(
            title: "My Cool Project!!!",
            client: "",
            tags: [],
            rootURL: tempDir
        )
        XCTAssertTrue(project.folderName.contains("my-cool-project"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: FAIL — `ProjectCreator` not found

- [ ] **Step 3: Implement ProjectCreator**

Create `PortyMcFolio/Services/ProjectCreator.swift`:

```swift
import Foundation

enum ProjectCreator {
    static func create(
        title: String,
        client: String,
        tags: [String],
        rootURL: URL
    ) throws -> Project {
        let uid = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
        let year = Calendar.current.component(.year, from: Date())
        let folderName = Project.folderName(title: title, year: year, uid: uid)
        let folderURL = rootURL.appendingPathComponent(folderName)

        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let now = Date()
        let frontmatter = ParsedFrontmatter(
            title: title,
            date: now,
            tags: tags,
            client: client,
            status: .draft,
            body: "# \(title)\n\nProject description here."
        )

        let content = FrontmatterParser.serialize(frontmatter: frontmatter)
        let readmeURL = folderURL.appendingPathComponent("README.md")
        try content.write(to: readmeURL, atomically: true, encoding: .utf8)

        var project = try Project.from(folderName: folderName, rootURL: rootURL)
        try project.loadReadme()
        return project
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Services/ProjectCreator.swift PortyMcFolioTests/ProjectCreatorTests.swift
git commit -m "feat: add ProjectCreator service for creating project folders with README"
```

---

### Task 5: PortfolioStore Service

**Files:**
- Create: `PortyMcFolio/Services/PortfolioStore.swift`
- Create: `PortyMcFolioTests/PortfolioStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Create `PortyMcFolioTests/PortfolioStoreTests.swift`:

```swift
import XCTest
@testable import PortyMcFolio

final class PortfolioStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testScanFindsProjects() throws {
        // Create two project folders with READMEs
        _ = try ProjectCreator.create(title: "Project A", client: "", tags: [], rootURL: tempDir)
        _ = try ProjectCreator.create(title: "Project B", client: "", tags: ["design"], rootURL: tempDir)

        let store = PortfolioStore(rootURL: tempDir)
        let projects = try store.scanProjects()

        XCTAssertEqual(projects.count, 2)
    }

    func testScanIgnoresNonProjectFolders() throws {
        // Create a valid project
        _ = try ProjectCreator.create(title: "Valid", client: "", tags: [], rootURL: tempDir)

        // Create a non-project folder
        let randomDir = tempDir.appendingPathComponent("random-folder")
        try FileManager.default.createDirectory(at: randomDir, withIntermediateDirectories: true)

        let store = PortfolioStore(rootURL: tempDir)
        let projects = try store.scanProjects()

        XCTAssertEqual(projects.count, 1)
    }

    func testScanLoadsReadmeMetadata() throws {
        _ = try ProjectCreator.create(
            title: "Test Project",
            client: "Client X",
            tags: ["ui", "web"],
            rootURL: tempDir
        )

        let store = PortfolioStore(rootURL: tempDir)
        let projects = try store.scanProjects()

        XCTAssertEqual(projects.first?.title, "Test Project")
        XCTAssertEqual(projects.first?.client, "Client X")
        XCTAssertEqual(projects.first?.tags, ["ui", "web"])
    }

    func testScanSortsByYearDescending() throws {
        // Manually create folders with different years
        let folder2023 = "2023-old-project-aaaaaaaa"
        let folder2025 = "2025-new-project-bbbbbbbb"
        for folder in [folder2023, folder2025] {
            let url = tempDir.appendingPathComponent(folder)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let readme = """
            ---
            title: "\(folder)"
            date: 2025-01-01
            tags: []
            status: draft
            ---

            Body.
            """
            try readme.write(
                to: url.appendingPathComponent("README.md"),
                atomically: true,
                encoding: .utf8
            )
        }

        let store = PortfolioStore(rootURL: tempDir)
        let projects = try store.scanProjects()
        XCTAssertEqual(projects.first?.year, 2025)
        XCTAssertEqual(projects.last?.year, 2023)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: FAIL — `PortfolioStore` not found

- [ ] **Step 3: Implement PortfolioStore**

Create `PortyMcFolio/Services/PortfolioStore.swift`:

```swift
import Foundation

final class PortfolioStore {
    let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    func scanProjects() throws -> [Project] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var projects: [Project] = []
        for url in contents {
            let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues.isDirectory == true else { continue }

            let folderName = url.lastPathComponent
            guard let project = try? Project.from(folderName: folderName, rootURL: rootURL) else {
                continue
            }

            var loaded = project
            guard (try? loaded.loadReadme()) != nil else { continue }
            projects.append(loaded)
        }

        projects.sort { $0.year > $1.year }
        return projects
    }

    func listFiles(in project: Project) throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: project.folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return contents.filter { url in
            let name = url.lastPathComponent
            return name != "README.md"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Services/PortfolioStore.swift PortyMcFolioTests/PortfolioStoreTests.swift
git commit -m "feat: add PortfolioStore for scanning and listing portfolio projects"
```

---

### Task 6: SearchIndex Service (SQLite FTS5)

**Files:**
- Create: `PortyMcFolio/Services/SearchIndex.swift`
- Create: `PortyMcFolioTests/SearchIndexTests.swift`

- [ ] **Step 1: Write failing tests**

Create `PortyMcFolioTests/SearchIndexTests.swift`:

```swift
import XCTest
import GRDB
@testable import PortyMcFolio

final class SearchIndexTests: XCTestCase {
    var index: SearchIndex!

    override func setUp() {
        super.setUp()
        index = try! SearchIndex(inMemory: true)
    }

    override func tearDown() {
        index = nil
        super.tearDown()
    }

    func testIndexAndSearchByTitle() throws {
        try index.indexProject(
            uid: "aaa11111",
            title: "Brand Identity Acme",
            tags: ["branding"],
            client: "Acme",
            status: "active",
            body: "A full rebrand for Acme Corp.",
            folderName: "2025-brand-identity-acme-aaa11111"
        )

        let results = try index.search(query: "Brand Identity")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.uid, "aaa11111")
    }

    func testSearchByTag() throws {
        try index.indexProject(
            uid: "bbb22222",
            title: "Website",
            tags: ["web", "react"],
            client: "",
            status: "draft",
            body: "A website project.",
            folderName: "2025-website-bbb22222"
        )

        let results = try index.search(query: "react")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchByBody() throws {
        try index.indexProject(
            uid: "ccc33333",
            title: "Logo",
            tags: [],
            client: "",
            status: "draft",
            body: "Designed a geometric wordmark with custom kerning.",
            folderName: "2025-logo-ccc33333"
        )

        let results = try index.search(query: "geometric wordmark")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchReturnsEmpty() throws {
        try index.indexProject(
            uid: "ddd44444",
            title: "Something",
            tags: [],
            client: "",
            status: "draft",
            body: "Nothing relevant.",
            folderName: "2025-something-ddd44444"
        )

        let results = try index.search(query: "nonexistent")
        XCTAssertEqual(results.count, 0)
    }

    func testReindexUpdatesExisting() throws {
        try index.indexProject(
            uid: "eee55555",
            title: "Old Title",
            tags: [],
            client: "",
            status: "draft",
            body: "Old body.",
            folderName: "2025-old-title-eee55555"
        )

        try index.indexProject(
            uid: "eee55555",
            title: "New Title",
            tags: ["updated"],
            client: "",
            status: "active",
            body: "New body content.",
            folderName: "2025-old-title-eee55555"
        )

        let oldResults = try index.search(query: "Old Title")
        XCTAssertEqual(oldResults.count, 0)

        let newResults = try index.search(query: "New Title")
        XCTAssertEqual(newResults.count, 1)
    }

    func testRemoveFromIndex() throws {
        try index.indexProject(
            uid: "fff66666",
            title: "To Delete",
            tags: [],
            client: "",
            status: "draft",
            body: "Will be removed.",
            folderName: "2025-to-delete-fff66666"
        )

        try index.removeProject(uid: "fff66666")
        let results = try index.search(query: "To Delete")
        XCTAssertEqual(results.count, 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: FAIL — `SearchIndex` not found

- [ ] **Step 3: Implement SearchIndex**

Create `PortyMcFolio/Services/SearchIndex.swift`:

```swift
import Foundation
import GRDB

struct SearchResult: Equatable {
    let uid: String
    let folderName: String
    let title: String
}

final class SearchIndex {
    private let dbQueue: DatabaseQueue

    init(inMemory: Bool = false) throws {
        if inMemory {
            dbQueue = try DatabaseQueue()
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first!.appendingPathComponent("PortyMcFolio")
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            let dbPath = appSupport.appendingPathComponent("search.sqlite").path
            dbQueue = try DatabaseQueue(path: dbPath)
        }
        try migrate()
    }

    private func migrate() throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS projects_fts USING fts5(
                    uid UNINDEXED,
                    folder_name UNINDEXED,
                    title,
                    tags,
                    client,
                    status,
                    body,
                    content='',
                    contentless_delete=1
                )
            """)
        }
    }

    func indexProject(
        uid: String,
        title: String,
        tags: [String],
        client: String,
        status: String,
        body: String,
        folderName: String
    ) throws {
        try dbQueue.write { db in
            // Remove existing entry
            try db.execute(
                sql: "DELETE FROM projects_fts WHERE uid = ?",
                arguments: [uid]
            )
            // Insert new
            try db.execute(
                sql: """
                INSERT INTO projects_fts (uid, folder_name, title, tags, client, status, body)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [uid, folderName, title, tags.joined(separator: " "), client, status, body]
            )
        }
    }

    func removeProject(uid: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM projects_fts WHERE uid = ?",
                arguments: [uid]
            )
        }
    }

    func search(query: String) throws -> [SearchResult] {
        let sanitized = query
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { "\($0)*" }
            .joined(separator: " ")

        guard !sanitized.isEmpty else { return [] }

        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT uid, folder_name, title
                FROM projects_fts
                WHERE projects_fts MATCH ?
                ORDER BY rank
            """, arguments: [sanitized])

            return rows.map { row in
                SearchResult(
                    uid: row["uid"],
                    folderName: row["folder_name"],
                    title: row["title"]
                )
            }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Services/SearchIndex.swift PortyMcFolioTests/SearchIndexTests.swift
git commit -m "feat: add SearchIndex with SQLite FTS5 for full-text project search"
```

---

### Task 7: FileWatcher Service (FSEvents)

**Files:**
- Create: `PortyMcFolio/Services/FileWatcher.swift`

- [ ] **Step 1: Implement FileWatcher**

Create `PortyMcFolio/Services/FileWatcher.swift`:

```swift
import Foundation

final class FileWatcher {
    typealias Callback = ([String]) -> Void

    private var stream: FSEventStreamRef?
    private let callback: Callback
    private let path: String

    init(path: String, callback: @escaping Callback) {
        self.path = path
        self.callback = callback
    }

    func start() {
        let pathsToWatch = [path] as CFArray
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        guard let stream = FSEventStreamCreate(
            nil,
            { (_, info, numEvents, eventPaths, _, _) in
                guard let info = info else { return }
                let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
                let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
                watcher.callback(Array(paths.prefix(numEvents)))
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // 1 second latency
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else { return }

        self.stream = stream
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }
}
```

- [ ] **Step 2: Regenerate project and verify build**

Run: `xcodegen generate && xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add PortyMcFolio/Services/FileWatcher.swift
git commit -m "feat: add FileWatcher service wrapping FSEvents for file change detection"
```

---

### Task 8: AppState and ContentView (Navigation Shell)

**Files:**
- Create: `PortyMcFolio/App/AppState.swift`
- Modify: `PortyMcFolio/App/PortyMcFolioApp.swift`
- Create: `PortyMcFolio/Views/ContentView.swift`

- [ ] **Step 1: Implement AppState**

Create `PortyMcFolio/App/AppState.swift`:

```swift
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var portfolioRootURL: URL?
    @Published var projects: [Project] = []
    @Published var selectedProject: Project?
    @Published var searchQuery: String = ""
    @Published var isShowingNewProject = false

    private var portfolioStore: PortfolioStore?
    private var searchIndex: SearchIndex?
    private var fileWatcher: FileWatcher?

    private let bookmarkKey = "portfolioRootBookmark"

    var filteredProjects: [Project] {
        guard !searchQuery.isEmpty else { return projects }
        if let index = searchIndex,
           let results = try? index.search(query: searchQuery) {
            let matchingUIDs = Set(results.map(\.uid))
            return projects.filter { matchingUIDs.contains($0.uid) }
        }
        return projects
    }

    func loadSavedRoot() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return }

        if isStale {
            saveBookmark(for: url)
        }

        guard url.startAccessingSecurityScopedResource() else { return }
        setRoot(url)
    }

    func setRoot(_ url: URL) {
        portfolioRootURL = url
        saveBookmark(for: url)

        let store = PortfolioStore(rootURL: url)
        self.portfolioStore = store
        self.searchIndex = try? SearchIndex()

        refreshProjects()
        startWatching()
    }

    func refreshProjects() {
        guard let store = portfolioStore else { return }
        if let loaded = try? store.scanProjects() {
            projects = loaded
            reindexAll()
        }
    }

    func createProject(title: String, client: String, tags: [String]) {
        guard let rootURL = portfolioRootURL else { return }
        guard let project = try? ProjectCreator.create(
            title: title, client: client, tags: tags, rootURL: rootURL
        ) else { return }

        projects.insert(project, at: 0)
        indexProject(project)
    }

    private func saveBookmark(for url: URL) {
        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    private func reindexAll() {
        for project in projects {
            indexProject(project)
        }
    }

    private func indexProject(_ project: Project) {
        try? searchIndex?.indexProject(
            uid: project.uid,
            title: project.title,
            tags: project.tags,
            client: project.client,
            status: project.status.rawValue,
            body: project.body,
            folderName: project.folderName
        )
    }

    private func startWatching() {
        guard let rootURL = portfolioRootURL else { return }
        fileWatcher?.stop()
        fileWatcher = FileWatcher(path: rootURL.path) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshProjects()
            }
        }
        fileWatcher?.start()
    }
}
```

- [ ] **Step 2: Implement ContentView**

Create `PortyMcFolio/Views/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.portfolioRootURL == nil {
                FolderPickerView()
            } else if let project = appState.selectedProject {
                ProjectDetailView(project: project)
            } else {
                ProjectListView()
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            appState.loadSavedRoot()
        }
    }
}
```

- [ ] **Step 3: Update PortyMcFolioApp to use AppState and ContentView**

Replace `PortyMcFolio/App/PortyMcFolioApp.swift`:

```swift
import SwiftUI

@main
struct PortyMcFolioApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .windowStyle(.titleBar)
    }
}
```

- [ ] **Step 4: Create stub views so the project compiles**

Create `PortyMcFolio/Views/FolderPickerView.swift`:

```swift
import SwiftUI

struct FolderPickerView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to PortyMcFolio")
                .font(.largeTitle)
            Text("Select your portfolio folder to get started.")
                .foregroundStyle(.secondary)
            Button("Choose Folder...") {
                pickFolder()
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select your portfolio root folder"
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            appState.setRoot(url)
        }
    }
}
```

Create `PortyMcFolio/Views/ProjectListView.swift`:

```swift
import SwiftUI

struct ProjectListView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Text("Project List — \(appState.projects.count) projects")
    }
}
```

Create `PortyMcFolio/Views/ProjectDetailView.swift`:

```swift
import SwiftUI

struct ProjectDetailView: View {
    let project: Project

    var body: some View {
        Text("Project Detail: \(project.title)")
    }
}
```

- [ ] **Step 5: Regenerate project and verify build**

Run: `xcodegen generate && xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add PortyMcFolio/App/ PortyMcFolio/Views/
git commit -m "feat: add AppState, ContentView, and navigation shell with folder picker"
```

---

### Task 9: Project List View

**Files:**
- Modify: `PortyMcFolio/Views/ProjectListView.swift`
- Create: `PortyMcFolio/Views/ProjectCardView.swift`
- Create: `PortyMcFolio/Views/TagPillView.swift`
- Create: `PortyMcFolio/Views/StatusBadgeView.swift`
- Create: `PortyMcFolio/Views/NewProjectSheet.swift`

- [ ] **Step 1: Implement TagPillView**

Create `PortyMcFolio/Views/TagPillView.swift`:

```swift
import SwiftUI

struct TagPillView: View {
    let tag: String
    var onTap: (() -> Void)?

    var body: some View {
        Text(tag)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary)
            .clipShape(Capsule())
            .onTapGesture {
                onTap?()
            }
    }
}
```

- [ ] **Step 2: Implement StatusBadgeView**

Create `PortyMcFolio/Views/StatusBadgeView.swift`:

```swift
import SwiftUI

struct StatusBadgeView: View {
    let status: ProjectStatus

    private var color: Color {
        switch status {
        case .draft: .gray
        case .active: .blue
        case .complete: .green
        case .archived: .orange
        }
    }

    var body: some View {
        Text(status.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
```

- [ ] **Step 3: Implement ProjectCardView**

Create `PortyMcFolio/Views/ProjectCardView.swift`:

```swift
import SwiftUI

struct ProjectCardView: View {
    let project: Project
    var onTagTap: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(project.year))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                StatusBadgeView(status: project.status)
            }

            Text(project.title)
                .font(.headline)
                .lineLimit(2)

            if !project.client.isEmpty {
                Text(project.client)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !project.tags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(project.tags, id: \.self) { tag in
                        TagPillView(tag: tag) {
                            onTagTap?(tag)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}

/// Simple horizontal flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalHeight = y + rowHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}
```

- [ ] **Step 4: Implement NewProjectSheet**

Create `PortyMcFolio/Views/NewProjectSheet.swift`:

```swift
import SwiftUI

struct NewProjectSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var title = ""
    @State private var client = ""
    @State private var tagsText = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("New Project")
                .font(.title2)
                .fontWeight(.semibold)

            TextField("Project Title", text: $title)
                .textFieldStyle(.roundedBorder)

            TextField("Client (optional)", text: $client)
                .textFieldStyle(.roundedBorder)

            TextField("Tags (comma separated)", text: $tagsText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private func create() {
        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        appState.createProject(title: title, client: client, tags: tags)
        dismiss()
    }
}
```

- [ ] **Step 5: Implement full ProjectListView**

Replace `PortyMcFolio/Views/ProjectListView.swift`:

```swift
import SwiftUI

struct ProjectListView: View {
    @EnvironmentObject var appState: AppState

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                TextField("Search projects...", text: $appState.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)

                Spacer()

                Button {
                    appState.isShowingNewProject = true
                } label: {
                    Label("New Project", systemImage: "plus")
                }
                .controlSize(.large)
            }
            .padding()

            Divider()

            // Project grid
            ScrollView {
                if appState.filteredProjects.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)
                        Text(appState.searchQuery.isEmpty
                             ? "No projects yet. Create one to get started."
                             : "No projects match your search.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(appState.filteredProjects) { project in
                            ProjectCardView(project: project) { tag in
                                appState.searchQuery = tag
                            }
                            .onTapGesture {
                                appState.selectedProject = project
                            }
                            .contentShape(Rectangle())
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $appState.isShowingNewProject) {
            NewProjectSheet()
        }
    }
}
```

- [ ] **Step 6: Regenerate project and verify build**

Run: `xcodegen generate && xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add PortyMcFolio/Views/
git commit -m "feat: add project list view with card grid, tags, status badges, and new project sheet"
```

---

### Task 10: Project Detail View (Editor + Gallery Tabs)

**Files:**
- Modify: `PortyMcFolio/Views/ProjectDetailView.swift`
- Create: `PortyMcFolio/Views/GalleryView.swift`
- Create: `PortyMcFolio/Views/GalleryItemView.swift`
- Create: `PortyMcFolio/Views/LinkCardView.swift`
- Create: `PortyMcFolio/Views/AddLinkSheet.swift`

- [ ] **Step 1: Implement GalleryItemView**

Create `PortyMcFolio/Views/GalleryItemView.swift`:

```swift
import SwiftUI
import QuickLookThumbnailing

struct GalleryItemView: View {
    let fileURL: URL
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 140, height: 100)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(fileURL.lastPathComponent)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 140)
        }
        .task {
            await loadThumbnail()
        }
    }

    private var iconName: String {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext"
        case "mp4", "mov", "avi": return "film"
        case "mp3", "wav", "aiff": return "waveform"
        case "usdz", "obj": return "cube"
        default: return "doc"
        }
    }

    private func loadThumbnail() async {
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: CGSize(width: 280, height: 200),
            scale: 2.0,
            representationTypes: .thumbnail
        )
        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            thumbnail = representation.nsImage
        } catch {
            // Thumbnail generation failed — icon fallback is already shown
        }
    }
}
```

- [ ] **Step 2: Implement LinkCardView**

Create `PortyMcFolio/Views/LinkCardView.swift`:

```swift
import SwiftUI

struct LinkCardView: View {
    let link: LinkItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "link")
                    .foregroundStyle(.blue)
                Text(link.title.isEmpty ? link.url.host ?? "Link" : link.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }

            Text(link.url.absoluteString)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !link.annotation.isEmpty {
                Text(link.annotation)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(width: 140, height: 100, alignment: .topLeading)
        .background(.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.blue.opacity(0.2), lineWidth: 1)
        )
        .onTapGesture {
            NSWorkspace.shared.open(link.url)
        }
    }
}
```

- [ ] **Step 3: Implement AddLinkSheet**

Create `PortyMcFolio/Views/AddLinkSheet.swift`:

```swift
import SwiftUI

struct AddLinkSheet: View {
    let projectFolderURL: URL
    @Environment(\.dismiss) var dismiss
    var onCreated: (() -> Void)?

    @State private var urlText = ""
    @State private var title = ""
    @State private var annotation = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Link")
                .font(.title2)
                .fontWeight(.semibold)

            TextField("URL", text: $urlText)
                .textFieldStyle(.roundedBorder)

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            TextField("Annotation (optional)", text: $annotation)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") { addLink() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(URL(string: urlText) == nil)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private func addLink() {
        guard let url = URL(string: urlText) else { return }
        let uid = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
        let link = LinkItem(uid: uid, url: url, title: title, annotation: annotation, date: Date())
        let fileName = LinkItem.fileName(uid: uid)
        let fileURL = projectFolderURL.appendingPathComponent(fileName)

        do {
            try link.toMarkdown().write(to: fileURL, atomically: true, encoding: .utf8)
            onCreated?()
            dismiss()
        } catch {
            // Write failed — sheet stays open, user can retry
        }
    }
}
```

- [ ] **Step 4: Implement GalleryView**

Create `PortyMcFolio/Views/GalleryView.swift`:

```swift
import SwiftUI

struct GalleryView: View {
    let project: Project
    @State private var files: [URL] = []
    @State private var links: [LinkItem] = []
    @State private var isShowingAddLink = false
    @State private var selectedFileURL: URL?

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 180), spacing: 12)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Gallery toolbar
            HStack {
                Spacer()
                Button {
                    isShowingAddLink = true
                } label: {
                    Label("Add Link", systemImage: "link.badge.plus")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    // Link items
                    ForEach(links) { link in
                        LinkCardView(link: link)
                    }

                    // File items
                    ForEach(files, id: \.absoluteString) { fileURL in
                        GalleryItemView(fileURL: fileURL)
                            .onTapGesture(count: 2) {
                                NSWorkspace.shared.open(fileURL)
                            }
                            .onTapGesture(count: 1) {
                                selectedFileURL = fileURL
                            }
                    }
                }
                .padding()
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDrop(providers)
                return true
            }
        }
        .onAppear { refresh() }
        .sheet(isPresented: $isShowingAddLink) {
            AddLinkSheet(projectFolderURL: project.folderURL) {
                refresh()
            }
        }
        .onKeyPress(.space) {
            if let url = selectedFileURL {
                QuickLookCoordinator.shared.preview(url: url)
                return .handled
            }
            return .ignored
        }
    }

    private func refresh() {
        let store = PortfolioStore(rootURL: project.folderURL.deletingLastPathComponent())
        files = (try? store.listFiles(in: project)) ?? []

        // Separate links from files
        var parsedLinks: [LinkItem] = []
        files.removeAll { url in
            let name = url.lastPathComponent
            guard LinkItem.isLinkFile(name: name),
                  let content = try? String(contentsOf: url, encoding: .utf8),
                  let link = try? LinkItem.parse(markdown: content) else {
                return false
            }
            parsedLinks.append(link)
            return true
        }
        links = parsedLinks
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url") { data, _ in
                guard let data = data as? Data,
                      let sourceURL = URL(dataRepresentation: data, relativeTo: nil) else { return }
                let destURL = project.folderURL.appendingPathComponent(sourceURL.lastPathComponent)
                try? FileManager.default.copyItem(at: sourceURL, to: destURL)
                DispatchQueue.main.async { refresh() }
            }
        }
    }
}
```

- [ ] **Step 5: Implement full ProjectDetailView**

Replace `PortyMcFolio/Views/ProjectDetailView.swift`:

```swift
import SwiftUI

struct ProjectDetailView: View {
    let project: Project
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    appState.selectedProject = nil
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)

                Text(project.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Picker("View", selection: $selectedTab) {
                    Text("Editor").tag(0)
                    Text("Gallery").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .padding()

            Divider()

            // Content
            Group {
                switch selectedTab {
                case 0:
                    EditorView(readmeURL: project.readmeURL)
                case 1:
                    GalleryView(project: project)
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
```

- [ ] **Step 6: Create stub EditorView and QuickLookCoordinator so project compiles**

Create `PortyMcFolio/Views/EditorView.swift`:

```swift
import SwiftUI

struct EditorView: View {
    let readmeURL: URL

    var body: some View {
        Text("Editor loading for: \(readmeURL.lastPathComponent)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

Create `PortyMcFolio/QuickLook/QuickLookCoordinator.swift`:

```swift
import AppKit
import Quartz

final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLookCoordinator()

    private var previewURL: URL?

    func preview(url: URL) {
        previewURL = url
        if let panel = QLPreviewPanel.shared() {
            panel.dataSource = self
            if panel.isVisible {
                panel.reloadData()
            } else {
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL != nil ? 1 : 0
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewURL as? NSURL
    }
}
```

- [ ] **Step 7: Regenerate project and verify build**

Run: `xcodegen generate && xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add PortyMcFolio/Views/ PortyMcFolio/QuickLook/
git commit -m "feat: add project detail view with gallery, link cards, drag-and-drop, and Quick Look"
```

---

### Task 11: Tiptap Editor — Web Bundle

**Files:**
- Create: `Editor/package.json`
- Create: `Editor/vite.config.js`
- Create: `Editor/src/index.js`
- Create: `Editor/src/markdown-serializer.js`
- Create: `Editor/src/extensions/frontmatter.js`
- Create: `Editor/src/extensions/wikilink.js`
- Create: `Editor/src/extensions/media-embed.js`
- Create: `PortyMcFolio/Editor/Resources/editor.html`
- Create: `PortyMcFolio/Editor/Resources/editor.css`

- [ ] **Step 1: Create npm project**

Create `Editor/package.json`:

```json
{
  "name": "portymcfolio-editor",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "build": "vite build",
    "dev": "vite"
  },
  "dependencies": {
    "@tiptap/core": "^2.6.0",
    "@tiptap/starter-kit": "^2.6.0",
    "@tiptap/extension-link": "^2.6.0",
    "@tiptap/extension-image": "^2.6.0",
    "@tiptap/extension-table": "^2.6.0",
    "@tiptap/extension-table-row": "^2.6.0",
    "@tiptap/extension-table-cell": "^2.6.0",
    "@tiptap/extension-table-header": "^2.6.0",
    "@tiptap/extension-placeholder": "^2.6.0",
    "tiptap-markdown": "^0.8.0"
  },
  "devDependencies": {
    "vite": "^5.0.0"
  }
}
```

- [ ] **Step 2: Create Vite config**

Create `Editor/vite.config.js`:

```js
import { defineConfig } from 'vite'
import { resolve } from 'path'

export default defineConfig({
  build: {
    lib: {
      entry: resolve(__dirname, 'src/index.js'),
      name: 'PortyMcFolioEditor',
      fileName: () => 'editor.bundle.js',
      formats: ['iife'],
    },
    outDir: resolve(__dirname, '../PortyMcFolio/Editor/Resources'),
    emptyOutDir: false,
    rollupOptions: {
      output: {
        entryFileNames: 'editor.bundle.js',
      },
    },
  },
})
```

- [ ] **Step 3: Create frontmatter extension**

Create `Editor/src/extensions/frontmatter.js`:

```js
import { Node, mergeAttributes } from '@tiptap/core'

export const Frontmatter = Node.create({
  name: 'frontmatter',
  group: 'block',
  content: 'text*',
  code: true,
  defining: true,
  isolating: true,

  parseHTML() {
    return [{ tag: 'pre[data-type="frontmatter"]' }]
  },

  renderHTML({ HTMLAttributes }) {
    return [
      'pre',
      mergeAttributes(HTMLAttributes, { 'data-type': 'frontmatter', class: 'frontmatter-block' }),
      ['code', 0],
    ]
  },

  addKeyboardShortcuts() {
    return {
      'Mod-Shift-f': () => false, // Reserve for future use
    }
  },
})
```

- [ ] **Step 4: Create wiki-link extension**

Create `Editor/src/extensions/wikilink.js`:

```js
import { Node, mergeAttributes } from '@tiptap/core'
import { InputRule } from '@tiptap/core'

export const WikiLink = Node.create({
  name: 'wikiLink',
  group: 'inline',
  inline: true,
  atom: true,

  addAttributes() {
    return {
      target: { default: null },
    }
  },

  parseHTML() {
    return [{ tag: 'span[data-type="wiki-link"]' }]
  },

  renderHTML({ node, HTMLAttributes }) {
    return [
      'span',
      mergeAttributes(HTMLAttributes, {
        'data-type': 'wiki-link',
        class: 'wiki-link',
      }),
      `[[${node.attrs.target}]]`,
    ]
  },

  addInputRules() {
    return [
      new InputRule({
        find: /\[\[([^\]]+)\]\]$/,
        handler: ({ state, range, match }) => {
          const target = match[1]
          const node = this.type.create({ target })
          const tr = state.tr.replaceWith(range.from, range.to, node)
          return tr
        },
      }),
    ]
  },
})
```

- [ ] **Step 5: Create media embed extension**

Create `Editor/src/extensions/media-embed.js`:

```js
import { Node, mergeAttributes } from '@tiptap/core'
import { InputRule } from '@tiptap/core'

export const MediaEmbed = Node.create({
  name: 'mediaEmbed',
  group: 'block',
  atom: true,

  addAttributes() {
    return {
      src: { default: null },
      alt: { default: '' },
    }
  },

  parseHTML() {
    return [{ tag: 'div[data-type="media-embed"]' }]
  },

  renderHTML({ node, HTMLAttributes }) {
    const src = node.attrs.src
    const ext = src?.split('.').pop()?.toLowerCase() || ''
    const imageExts = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg']
    const videoExts = ['mp4', 'mov', 'webm']

    if (imageExts.includes(ext)) {
      return [
        'div',
        mergeAttributes(HTMLAttributes, { 'data-type': 'media-embed', class: 'media-embed' }),
        ['img', { src, alt: node.attrs.alt, loading: 'lazy' }],
      ]
    }

    if (videoExts.includes(ext)) {
      return [
        'div',
        mergeAttributes(HTMLAttributes, { 'data-type': 'media-embed', class: 'media-embed' }),
        ['video', { src, controls: 'true', preload: 'metadata' }],
      ]
    }

    return [
      'div',
      mergeAttributes(HTMLAttributes, { 'data-type': 'media-embed', class: 'media-embed media-embed--file' }),
      ['span', `📎 ${src}`],
    ]
  },

  addInputRules() {
    return [
      new InputRule({
        find: /!\[\[([^\]]+)\]\]$/,
        handler: ({ state, range, match }) => {
          const src = match[1]
          const node = this.type.create({ src })
          const tr = state.tr.replaceWith(range.from, range.to, node)
          return tr
        },
      }),
    ]
  },
})
```

- [ ] **Step 6: Create markdown serializer helper**

Create `Editor/src/markdown-serializer.js`:

```js
/**
 * Custom markdown transformations for Obsidian compatibility.
 * tiptap-markdown handles standard markdown; these handle our custom nodes.
 */

export function preProcessMarkdown(md) {
  // Convert YAML frontmatter to a code block with marker so Tiptap can parse it
  const frontmatterRegex = /^---\n([\s\S]*?)\n---\n?/
  const match = md.match(frontmatterRegex)
  if (match) {
    const yaml = match[1]
    const rest = md.slice(match[0].length)
    return `<pre data-type="frontmatter"><code>${escapeHtml(yaml)}</code></pre>\n${rest}`
  }
  return md
}

export function postProcessMarkdown(md) {
  // Convert wiki-link spans back to [[target]]
  md = md.replace(/<span data-type="wiki-link"[^>]*>\[\[([^\]]+)\]\]<\/span>/g, '[[$1]]')

  // Convert media embeds back to ![[src]]
  md = md.replace(/<div data-type="media-embed"[^>]*>.*?<\/div>/g, (match) => {
    const srcMatch = match.match(/src="([^"]+)"/)
    return srcMatch ? `![[${srcMatch[1]}]]` : match
  })

  return md
}

export function frontmatterToMarkdown(html) {
  const match = html.match(/<pre data-type="frontmatter"><code>([\s\S]*?)<\/code><\/pre>/)
  if (match) {
    return `---\n${unescapeHtml(match[1])}\n---`
  }
  return ''
}

function escapeHtml(str) {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
}

function unescapeHtml(str) {
  return str.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
}
```

- [ ] **Step 7: Create main editor entry point with Swift bridge**

Create `Editor/src/index.js`:

```js
import { Editor } from '@tiptap/core'
import StarterKit from '@tiptap/starter-kit'
import Link from '@tiptap/extension-link'
import Image from '@tiptap/extension-image'
import Table from '@tiptap/extension-table'
import TableRow from '@tiptap/extension-table-row'
import TableCell from '@tiptap/extension-table-cell'
import TableHeader from '@tiptap/extension-table-header'
import Placeholder from '@tiptap/extension-placeholder'
import { Markdown } from 'tiptap-markdown'
import { Frontmatter } from './extensions/frontmatter.js'
import { WikiLink } from './extensions/wikilink.js'
import { MediaEmbed } from './extensions/media-embed.js'
import { preProcessMarkdown, postProcessMarkdown, frontmatterToMarkdown } from './markdown-serializer.js'

let editor = null
let debounceTimer = null

function initEditor() {
  editor = new Editor({
    element: document.getElementById('editor'),
    extensions: [
      StarterKit.configure({
        codeBlock: { HTMLAttributes: { class: 'code-block' } },
      }),
      Link.configure({ openOnClick: false }),
      Image,
      Table.configure({ resizable: false }),
      TableRow,
      TableCell,
      TableHeader,
      Placeholder.configure({ placeholder: 'Start writing...' }),
      Markdown.configure({
        html: true,
        transformPastedText: true,
        transformCopiedText: true,
      }),
      Frontmatter,
      WikiLink,
      MediaEmbed,
    ],
    onUpdate({ editor }) {
      clearTimeout(debounceTimer)
      debounceTimer = setTimeout(() => {
        const md = getMarkdown()
        window.webkit?.messageHandlers?.contentChanged?.postMessage(md)
      }, 1500)
    },
  })
}

function setMarkdown(md) {
  if (!editor) return
  const processed = preProcessMarkdown(md)
  editor.commands.setContent(processed)
}

function getMarkdown() {
  if (!editor) return ''
  let md = editor.storage.markdown?.getMarkdown() || ''
  md = postProcessMarkdown(md)

  // Re-attach frontmatter
  const html = editor.getHTML()
  const fm = frontmatterToMarkdown(html)
  if (fm) {
    md = fm + '\n\n' + md.replace(/<pre data-type="frontmatter">[\s\S]*?<\/pre>\n?/, '')
  }

  return md
}

// Expose to Swift bridge
window.PortyEditor = {
  init: initEditor,
  setMarkdown,
  getMarkdown,
  focus: () => editor?.commands.focus(),
}

// Auto-init when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initEditor)
} else {
  initEditor()
}
```

- [ ] **Step 8: Create editor HTML shell**

Create `PortyMcFolio/Editor/Resources/editor.html`:

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" href="editor.css">
</head>
<body>
  <div id="editor"></div>
  <script src="editor.bundle.js"></script>
</body>
</html>
```

- [ ] **Step 9: Create editor CSS**

Create `PortyMcFolio/Editor/Resources/editor.css`:

```css
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
  font-size: 15px;
  line-height: 1.65;
  color: #1d1d1f;
  background: transparent;
  padding: 32px;
  max-width: 720px;
  margin: 0 auto;
}

@media (prefers-color-scheme: dark) {
  body {
    color: #f5f5f7;
  }
}

#editor {
  outline: none;
}

/* Tiptap editor styles */
.tiptap {
  outline: none;
}

.tiptap > *:first-child {
  margin-top: 0;
}

.tiptap h1 { font-size: 2em; font-weight: 700; margin: 1.2em 0 0.4em; }
.tiptap h2 { font-size: 1.5em; font-weight: 600; margin: 1em 0 0.3em; }
.tiptap h3 { font-size: 1.2em; font-weight: 600; margin: 0.8em 0 0.2em; }

.tiptap p {
  margin: 0.6em 0;
}

.tiptap a {
  color: #0066cc;
  text-decoration: underline;
  text-decoration-color: rgba(0, 102, 204, 0.3);
}

.tiptap a:hover {
  text-decoration-color: rgba(0, 102, 204, 0.8);
}

/* Frontmatter block */
.frontmatter-block {
  background: rgba(0, 0, 0, 0.04);
  border: 1px solid rgba(0, 0, 0, 0.08);
  border-radius: 8px;
  padding: 16px;
  margin-bottom: 24px;
  font-family: 'SF Mono', 'Menlo', monospace;
  font-size: 13px;
  line-height: 1.5;
  white-space: pre-wrap;
}

@media (prefers-color-scheme: dark) {
  .frontmatter-block {
    background: rgba(255, 255, 255, 0.05);
    border-color: rgba(255, 255, 255, 0.1);
  }
}

/* Code blocks */
.code-block {
  background: rgba(0, 0, 0, 0.04);
  border-radius: 6px;
  padding: 12px 16px;
  font-family: 'SF Mono', 'Menlo', monospace;
  font-size: 13px;
  overflow-x: auto;
}

code {
  background: rgba(0, 0, 0, 0.06);
  border-radius: 3px;
  padding: 1px 4px;
  font-family: 'SF Mono', 'Menlo', monospace;
  font-size: 0.9em;
}

/* Wiki links */
.wiki-link {
  color: #6b4ce6;
  cursor: pointer;
  padding: 1px 2px;
  border-radius: 3px;
}

.wiki-link:hover {
  background: rgba(107, 76, 230, 0.1);
}

/* Media embeds */
.media-embed {
  margin: 16px 0;
}

.media-embed img {
  max-width: 100%;
  border-radius: 8px;
}

.media-embed video {
  max-width: 100%;
  border-radius: 8px;
}

.media-embed--file {
  padding: 12px;
  background: rgba(0, 0, 0, 0.04);
  border-radius: 8px;
  font-size: 14px;
}

/* Tables */
table {
  border-collapse: collapse;
  width: 100%;
  margin: 1em 0;
}

th, td {
  border: 1px solid rgba(0, 0, 0, 0.12);
  padding: 8px 12px;
  text-align: left;
}

th {
  background: rgba(0, 0, 0, 0.04);
  font-weight: 600;
}

/* Blockquotes */
blockquote {
  border-left: 3px solid rgba(0, 0, 0, 0.15);
  padding-left: 16px;
  margin: 1em 0;
  color: rgba(0, 0, 0, 0.6);
}

@media (prefers-color-scheme: dark) {
  blockquote {
    border-left-color: rgba(255, 255, 255, 0.2);
    color: rgba(255, 255, 255, 0.6);
  }
}

/* Lists */
ul, ol {
  padding-left: 24px;
  margin: 0.5em 0;
}

li {
  margin: 0.2em 0;
}

/* Placeholder */
.tiptap p.is-editor-empty:first-child::before {
  content: attr(data-placeholder);
  float: left;
  color: rgba(0, 0, 0, 0.25);
  pointer-events: none;
  height: 0;
}

/* Images */
.tiptap img {
  max-width: 100%;
  border-radius: 8px;
  margin: 8px 0;
}

/* Horizontal rule */
hr {
  border: none;
  border-top: 1px solid rgba(0, 0, 0, 0.1);
  margin: 2em 0;
}
```

- [ ] **Step 10: Build the editor bundle**

Run: `cd Editor && npm install && npm run build`
Expected: `editor.bundle.js` created in `PortyMcFolio/Editor/Resources/`

- [ ] **Step 11: Verify the bundle exists and project builds**

Run: `ls -la PortyMcFolio/Editor/Resources/`
Expected: `editor.html`, `editor.css`, `editor.bundle.js` all present

Run: `xcodegen generate && xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 12: Commit**

```bash
git add Editor/ PortyMcFolio/Editor/Resources/
git commit -m "feat: add Tiptap editor web bundle with frontmatter, wiki-links, and media embeds"
```

---

### Task 12: Editor Swift Integration (WKWebView + Bridge)

**Files:**
- Create: `PortyMcFolio/Editor/EditorBridge.swift`
- Modify: `PortyMcFolio/Views/EditorView.swift`

- [ ] **Step 1: Implement EditorBridge**

Create `PortyMcFolio/Editor/EditorBridge.swift`:

```swift
import Foundation
import WebKit

final class EditorBridge: NSObject, WKScriptMessageHandler {
    var onContentChanged: ((String) -> Void)?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        switch message.name {
        case "contentChanged":
            if let markdown = message.body as? String {
                onContentChanged?(markdown)
            }
        default:
            break
        }
    }

    func loadMarkdown(in webView: WKWebView, content: String) {
        let escaped = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
        webView.evaluateJavaScript("window.PortyEditor.setMarkdown(`\(escaped)`)")
    }

    func getMarkdown(from webView: WKWebView) async throws -> String {
        try await webView.evaluateJavaScript("window.PortyEditor.getMarkdown()") as? String ?? ""
    }
}
```

- [ ] **Step 2: Implement EditorView with WKWebView**

Replace `PortyMcFolio/Views/EditorView.swift`:

```swift
import SwiftUI
import WebKit

struct EditorView: NSViewRepresentable {
    let readmeURL: URL
    var onSave: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(readmeURL: readmeURL, onSave: onSave)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator.bridge, name: "contentChanged")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        // Allow access to local project files for media embeds
        let projectDir = readmeURL.deletingLastPathComponent()
        if let editorURL = Bundle.main.url(forResource: "editor", withExtension: "html", subdirectory: "Resources") {
            webView.loadFileURL(editorURL, allowingReadAccessTo: projectDir)
        }

        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Only reload if the readme URL changed
        if context.coordinator.readmeURL != readmeURL {
            context.coordinator.readmeURL = readmeURL
            context.coordinator.loadContent()
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let bridge = EditorBridge()
        var readmeURL: URL
        var onSave: ((String) -> Void)?
        weak var webView: WKWebView?

        init(readmeURL: URL, onSave: ((String) -> Void)?) {
            self.readmeURL = readmeURL
            self.onSave = onSave
            super.init()

            bridge.onContentChanged = { [weak self] markdown in
                guard let self, let url = Optional(self.readmeURL) else { return }
                try? markdown.write(to: url, atomically: true, encoding: .utf8)
                self.onSave?(markdown)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loadContent()
        }

        func loadContent() {
            guard let webView else { return }
            guard let content = try? String(contentsOf: readmeURL, encoding: .utf8) else { return }
            bridge.loadMarkdown(in: webView, content: content)
        }
    }
}
```

- [ ] **Step 3: Regenerate project and verify build**

Run: `xcodegen generate && xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Editor/EditorBridge.swift PortyMcFolio/Views/EditorView.swift
git commit -m "feat: integrate Tiptap editor via WKWebView with Swift bridge and auto-save"
```

---

### Task 13: Wire Up Search in Project List

**Files:**
- Modify: `PortyMcFolio/App/AppState.swift` (already has search logic)

This task verifies the search wiring is complete. The `AppState.filteredProjects` computed property already queries the `SearchIndex`. The `ProjectListView` already binds to `appState.searchQuery`. We need to verify indexing happens when projects are loaded and when the editor saves.

- [ ] **Step 1: Update EditorView in ProjectDetailView to re-index on save**

Modify `PortyMcFolio/Views/ProjectDetailView.swift` — update the `EditorView` usage to trigger re-indexing:

```swift
import SwiftUI

struct ProjectDetailView: View {
    let project: Project
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    appState.selectedProject = nil
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)

                Text(project.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Picker("View", selection: $selectedTab) {
                    Text("Editor").tag(0)
                    Text("Gallery").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .padding()

            Divider()

            // Content
            Group {
                switch selectedTab {
                case 0:
                    EditorView(readmeURL: project.readmeURL) { _ in
                        appState.refreshProjects()
                    }
                case 1:
                    GalleryView(project: project)
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodegen generate && xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Run all tests**

Run: `xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Views/ProjectDetailView.swift
git commit -m "feat: wire editor save to search re-indexing"
```

---

### Task 14: Final Integration — Tag Click Search and Keyboard Shortcuts

**Files:**
- Modify: `PortyMcFolio/Views/ProjectCardView.swift`
- Modify: `PortyMcFolio/Views/ProjectListView.swift`

- [ ] **Step 1: Verify tag click already wired**

The `ProjectListView` already passes `onTagTap` to `ProjectCardView`, which sets `appState.searchQuery`. Verify this compiles and the flow is correct by reading both files.

- [ ] **Step 2: Add Cmd+F keyboard shortcut to focus search**

Modify `PortyMcFolio/Views/ProjectListView.swift` — add a `@FocusState` for the search field:

Replace the toolbar section in `ProjectListView`:

```swift
import SwiftUI

struct ProjectListView: View {
    @EnvironmentObject var appState: AppState
    @FocusState private var isSearchFocused: Bool

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                TextField("Search projects...", text: $appState.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
                    .focused($isSearchFocused)

                Spacer()

                Button {
                    appState.isShowingNewProject = true
                } label: {
                    Label("New Project", systemImage: "plus")
                }
                .controlSize(.large)
            }
            .padding()

            Divider()

            // Project grid
            ScrollView {
                if appState.filteredProjects.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "folder")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)
                        Text(appState.searchQuery.isEmpty
                             ? "No projects yet. Create one to get started."
                             : "No projects match your search.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(appState.filteredProjects) { project in
                            ProjectCardView(project: project) { tag in
                                appState.searchQuery = tag
                            }
                            .onTapGesture {
                                appState.selectedProject = project
                            }
                            .contentShape(Rectangle())
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $appState.isShowingNewProject) {
            NewProjectSheet()
        }
        .onKeyPress(characters: .init("f"), modifiers: .command) {
            isSearchFocused = true
            return .handled
        }
    }
}
```

- [ ] **Step 3: Verify build and run all tests**

Run: `xcodegen generate && xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

Run: `xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' 2>&1 | tail -20`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Views/ProjectListView.swift
git commit -m "feat: add Cmd+F keyboard shortcut to focus project search"
```

---

### Note: Rich Inline Previews (Deferred)

The spec describes enhanced inline previews (AVPlayerView for video, PDFView for PDFs, SceneView for 3D). The v1 gallery uses `QLThumbnailGenerator` for thumbnails and `QLPreviewPanel` for the space-bar Quick Look experience, which covers all file types natively. The richer per-type inline previews (inline video playback, PDF page navigation, 3D orbit) are a natural follow-up once the core gallery is working — they enhance existing items rather than requiring new architecture.

---

### Task 15: Final Verification and Cleanup

- [ ] **Step 1: Full clean build**

Run: `xcodegen generate && xcodebuild clean build -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -15`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Full test suite**

Run: `xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolioTests -destination 'platform=macOS' 2>&1 | tail -30`
Expected: ALL PASS — tests for FrontmatterParser, Slug, Project, LinkItem, ProjectCreator, PortfolioStore, SearchIndex

- [ ] **Step 3: Verify file structure matches plan**

Run: `find PortyMcFolio -name '*.swift' | sort`
Expected: All files from the file structure section exist

- [ ] **Step 4: Add .gitignore and commit**

Create `.gitignore`:

```
# Xcode
*.xcodeproj/
xcuserdata/
DerivedData/
*.xcworkspace/
build/

# Swift Package Manager
.build/
.swiftpm/
Packages/

# Node
Editor/node_modules/
Editor/dist/

# OS
.DS_Store
```

```bash
git add .gitignore
git commit -m "chore: add .gitignore for Xcode, SPM, and Node artifacts"
```
