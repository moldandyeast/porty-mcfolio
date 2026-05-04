# Gallery Cleanup Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the gallery into a file cleanup workspace with grid/list views, folder navigation, a rename-review popup, and teaser image support.

**Architecture:** All changes are Swift/SwiftUI. No editor (JS) changes. The gallery gets folder-awareness (recursive scan, breadcrumb nav), a view toggle (grid/list), a cleanup popup (rename queue), and teaser stored in README.md frontmatter. No new data files — the folder structure is the organization.

**Tech Stack:** Swift 5.9, SwiftUI, macOS 14, QuickLookThumbnailing, FileManager

**Spec:** `docs/superpowers/specs/2026-04-14-gallery-cleanup-workspace-design.md`

---

## File Structure

### New files
- `PortyMcFolio/Views/GalleryListView.swift` — List/table row view for gallery items (filename, type, size, date)
- `PortyMcFolio/Views/BreadcrumbBar.swift` — Folder navigation breadcrumb path bar
- `PortyMcFolio/Views/CleanupPopup.swift` — Modal rename popup with preview, prefix input, folder chips

### Modified files
- `PortyMcFolio/Models/Project.swift` — Add `teaser` field
- `PortyMcFolio/Services/FrontmatterParser.swift` — Parse/serialize `teaser` field
- `PortyMcFolio/Views/GalleryView.swift` — Folder navigation state, view toggle, cleanup trigger, updated FABs, recursive scan
- `PortyMcFolio/Views/GalleryItemView.swift` — Teaser badge overlay, folder item variant
- `PortyMcFolio/Views/ProjectCardView.swift` — Show teaser thumbnail
- `PortyMcFolio/Services/Slug.swift` — Add underscore variant for filename prefix

### Test files
- `PortyMcFolioTests/FrontmatterParserTests.swift` — Test teaser parse/serialize

---

## Task 1: Teaser field in frontmatter

**Files:**
- Modify: `PortyMcFolio/Models/Project.swift`
- Modify: `PortyMcFolio/Services/FrontmatterParser.swift`
- Modify: `PortyMcFolioTests/FrontmatterParserTests.swift`

- [ ] **Step 1: Add teaser to ParsedFrontmatter and Project**

In `PortyMcFolio/Services/FrontmatterParser.swift`, add `teaser` to the struct (after `body`):

```swift
struct ParsedFrontmatter {
    var title: String
    var date: Date
    var tags: [String]
    var client: String
    var status: ProjectStatus
    var body: String
    var teaser: String
}
```

In `PortyMcFolio/Models/Project.swift`, add `teaser` to the struct (after `body` on line 24):

```swift
var body: String
var teaser: String
```

Update `Project.from(folderName:rootURL:)` to initialize teaser (line 72, in the return statement):

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
    status: .draft,
    body: "",
    teaser: ""
)
```

Update `Project.loadReadme()` to load teaser (after line 84):

```swift
mutating func loadReadme() throws {
    let content = try String(contentsOf: readmeURL, encoding: .utf8)
    let parsed = try FrontmatterParser.parse(content)
    title = parsed.title
    date = parsed.date
    tags = parsed.tags
    client = parsed.client
    status = parsed.status
    body = parsed.body
    teaser = parsed.teaser
}
```

- [ ] **Step 2: Parse teaser in FrontmatterParser**

In `FrontmatterParser.parse()`, after `let date: Date` block (around line 114), add:

```swift
let teaser = dict["teaser"] as? String ?? ""
```

Update the return statement (line 116-123) to include teaser:

```swift
return ParsedFrontmatter(
    title: title,
    date: date,
    tags: tags,
    client: client,
    status: status,
    body: body,
    teaser: teaser
)
```

Also update ALL the early-return `ParsedFrontmatter(...)` calls (lines 27-34, 40-47, 61-68) to include `teaser: ""`.

- [ ] **Step 3: Serialize teaser in FrontmatterParser**

In `FrontmatterParser.serialize()`, update the header string (lines 140-148) to include teaser when non-empty:

```swift
static func serialize(frontmatter fm: ParsedFrontmatter) -> String {
    let dateFormatter = ISO8601DateFormatter()
    dateFormatter.formatOptions = [.withFullDate]
    let dateString = dateFormatter.string(from: fm.date)

    let tagsYAML: String
    if fm.tags.isEmpty {
        tagsYAML = "[]"
    } else {
        let tagItems = fm.tags.map { "\"\($0)\"" }.joined(separator: ", ")
        tagsYAML = "[\(tagItems)]"
    }

    var lines = [
        "---",
        "title: \"\(fm.title)\"",
        "date: \(dateString)",
        "tags: \(tagsYAML)",
        "client: \"\(fm.client)\"",
        "status: \(fm.status.rawValue)",
    ]
    if !fm.teaser.isEmpty {
        lines.append("teaser: \"\(fm.teaser)\"")
    }
    lines.append("---")

    let header = lines.joined(separator: "\n")
    let body = fm.body.isEmpty ? "" : "\n\(fm.body)"
    return header + "\n" + body
}
```

- [ ] **Step 4: Add teaser tests**

In `PortyMcFolioTests/FrontmatterParserTests.swift`, add:

```swift
func testParseTeaserField() throws {
    let md = """
    ---
    title: "Test"
    date: 2025-01-01
    tags: []
    client: ""
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
    var fm = try FrontmatterParser.parse(sampleMarkdown)
    fm.teaser = "photos/hero.jpg"
    let serialized = FrontmatterParser.serialize(frontmatter: fm)
    XCTAssertTrue(serialized.contains("teaser: \"photos/hero.jpg\""))
}

func testSerializeEmptyTeaserOmitted() throws {
    let fm = try FrontmatterParser.parse(sampleMarkdown)
    let serialized = FrontmatterParser.serialize(frontmatter: fm)
    XCTAssertFalse(serialized.contains("teaser"))
}
```

- [ ] **Step 5: Build and run tests**

Run: `xcodebuild -scheme PortyMcFolio -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

Run: `xcodebuild test -scheme PortyMcFolio -configuration Debug -destination 'platform=macOS' 2>&1 | tail -15`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add PortyMcFolio/Models/Project.swift PortyMcFolio/Services/FrontmatterParser.swift PortyMcFolioTests/FrontmatterParserTests.swift
git commit -m "feat: teaser field in frontmatter — parse, serialize, and test"
```

---

## Task 2: Underscore slug for filename prefix

**Files:**
- Modify: `PortyMcFolio/Services/Slug.swift`
- Modify: `PortyMcFolioTests/SlugTests.swift`

- [ ] **Step 1: Add underscoreFrom method**

In `PortyMcFolio/Services/Slug.swift`, add a new method after the existing `from()`:

```swift
/// Like `from()` but uses underscores instead of hyphens.
/// Used for filename prefixes: "Acme Rebrand" → "acme_rebrand"
static func underscoreFrom(_ input: String) -> String {
    let folded = input.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
    let lowercased = folded.lowercased()
    let allowed = lowercased.unicodeScalars.filter { scalar in
        let c = Character(scalar)
        return c.isLetter || c.isNumber || c == " " || c == "-" || c == "_"
    }
    let filtered = String(String.UnicodeScalarView(allowed))
    let components = filtered.components(separatedBy: CharacterSet(charactersIn: " -_"))
    let joined = components.filter { !$0.isEmpty }.joined(separator: "_")
    let trimmed = joined.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    return trimmed.isEmpty ? "untitled" : trimmed
}
```

- [ ] **Step 2: Add tests**

In `PortyMcFolioTests/SlugTests.swift`, add:

```swift
func testUnderscoreSlug() {
    XCTAssertEqual(Slug.underscoreFrom("Acme Rebrand"), "acme_rebrand")
}

func testUnderscoreSlugSpecialChars() {
    XCTAssertEqual(Slug.underscoreFrom("Brand Identity — Acme"), "brand_identity_acme")
}

func testUnderscoreSlugEmpty() {
    XCTAssertEqual(Slug.underscoreFrom(""), "untitled")
}
```

- [ ] **Step 3: Build and run tests**

Run: `xcodebuild test -scheme PortyMcFolio -configuration Debug -destination 'platform=macOS' 2>&1 | tail -15`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Services/Slug.swift PortyMcFolioTests/SlugTests.swift
git commit -m "feat: Slug.underscoreFrom() for filename prefix generation"
```

---

## Task 3: Folder-aware gallery scan + breadcrumb

**Files:**
- Create: `PortyMcFolio/Views/BreadcrumbBar.swift`
- Modify: `PortyMcFolio/Views/GalleryView.swift`

- [ ] **Step 1: Create BreadcrumbBar**

Create `PortyMcFolio/Views/BreadcrumbBar.swift`:

```swift
import SwiftUI

struct BreadcrumbBar: View {
    let projectName: String
    let relativePath: [String]  // e.g. ["wireframes", "v2"]
    let onNavigate: (Int) -> Void  // index into relativePath, -1 = root

    var body: some View {
        HStack(spacing: 4) {
            Button {
                onNavigate(-1)
            } label: {
                Text(projectName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(relativePath.isEmpty ? .primary : .secondary)
            }
            .buttonStyle(.plain)

            ForEach(Array(relativePath.enumerated()), id: \.offset) { index, segment in
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)

                Button {
                    onNavigate(index)
                } label: {
                    Text(segment)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(index == relativePath.count - 1 ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
```

- [ ] **Step 2: Add folder navigation state to GalleryView**

In `PortyMcFolio/Views/GalleryView.swift`, add state for current subfolder and view mode. Replace the existing state declarations (lines 7-11) with:

```swift
@State private var links: [LinkItem] = []
@State private var files: [URL] = []
@State private var folders: [URL] = []
@State private var selectedFileURL: URL?
@State private var isShowingAddLink = false
@State private var folderWatcher = FolderWatcher()
@State private var currentSubpath: [String] = []  // path segments relative to project root
@State private var viewMode: GalleryViewMode = .grid

enum GalleryViewMode {
    case grid, list
}
```

Add a computed property for the current folder URL:

```swift
private var currentFolderURL: URL {
    var url = project.folderURL
    for segment in currentSubpath {
        url = url.appendingPathComponent(segment)
    }
    return url
}
```

- [ ] **Step 3: Update scanProjectFolder for folder awareness**

Replace the existing `scanProjectFolder()` method with:

```swift
private func scanProjectFolder() {
    let fm = FileManager.default
    let folderURL = currentFolderURL
    guard let contents = try? fm.contentsOfDirectory(
        at: folderURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else { return }

    var scannedLinks: [LinkItem] = []
    var scannedFiles: [URL] = []
    var scannedFolders: [URL] = []

    for url in contents {
        let name = url.lastPathComponent
        if name == "README.md" || name == ".gallery.json" { continue }

        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

        if isDirectory {
            scannedFolders.append(url)
        } else if LinkItem.isLinkFile(name: name) && currentSubpath.isEmpty {
            // Only show link files at root level
            if let markdown = try? String(contentsOf: url, encoding: .utf8),
               var link = try? LinkItem.parse(markdown: markdown) {
                let uidFromName = String(name.dropFirst("link-".count).dropLast(".md".count))
                link = LinkItem(
                    uid: uidFromName,
                    url: link.url,
                    title: link.title,
                    annotation: link.annotation,
                    date: link.date
                )
                scannedLinks.append(link)
            }
        } else if !LinkItem.isLinkFile(name: name) {
            scannedFiles.append(url)
        }
    }

    links = scannedLinks.sorted { $0.date > $1.date }
    files = scannedFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }
    folders = scannedFolders.sorted { $0.lastPathComponent < $1.lastPathComponent }
}
```

- [ ] **Step 4: Add breadcrumb and folder items to the body**

Replace the GalleryView `body` with:

```swift
var body: some View {
    VStack(spacing: 0) {
        // Toolbar: view toggle + breadcrumb
        HStack(spacing: 8) {
            BreadcrumbBar(
                projectName: project.title.isEmpty ? "Project" : project.title,
                relativePath: currentSubpath,
                onNavigate: { index in
                    if index < 0 {
                        currentSubpath = []
                    } else {
                        currentSubpath = Array(currentSubpath.prefix(index + 1))
                    }
                    scanProjectFolder()
                }
            )

            Picker("", selection: $viewMode) {
                Image(systemName: "square.grid.2x2").tag(GalleryViewMode.grid)
                Image(systemName: "list.bullet").tag(GalleryViewMode.list)
            }
            .pickerStyle(.segmented)
            .frame(width: 80)
            .padding(.trailing, 16)
        }

        Divider()

        // Content
        ScrollView {
            if viewMode == .grid {
                gridContent
            } else {
                listContent
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        .onKeyPress(.space) {
            guard let url = selectedFileURL else { return .ignored }
            QuickLookCoordinator.shared.preview(url: url)
            return .handled
        }
        .focusable()
    }
    .overlay(alignment: .bottomTrailing) {
        fabButtons
    }
    .onAppear {
        scanProjectFolder()
        folderWatcher.watch(url: project.folderURL) {
            scanProjectFolder()
        }
    }
    .onDisappear {
        folderWatcher.stop()
    }
    .sheet(isPresented: $isShowingAddLink) {
        AddLinkSheet(projectFolderURL: project.folderURL)
    }
}
```

- [ ] **Step 5: Extract grid content with folder items**

Add computed properties for grid and list content:

```swift
@ViewBuilder
private var gridContent: some View {
    LazyVGrid(columns: columns, spacing: 16) {
        // Folders first
        ForEach(folders, id: \.absoluteString) { folderURL in
            VStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                    .frame(width: 140, height: 100)

                Text(folderURL.lastPathComponent)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 140)
            }
            .onTapGesture(count: 2) {
                currentSubpath.append(folderURL.lastPathComponent)
                scanProjectFolder()
            }
        }

        // Links (only at root)
        ForEach(links) { link in
            LinkCardView(link: link, projectFolderURL: project.folderURL)
        }

        // Files
        ForEach(files, id: \.absoluteString) { fileURL in
            GalleryItemView(fileURL: fileURL)
                .overlay(alignment: .topTrailing) {
                    if isTeaserFile(fileURL) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                            .padding(6)
                    }
                }
                .background(
                    selectedFileURL == fileURL
                        ? Color.accentColor.opacity(0.15)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture(count: 2) {
                    NSWorkspace.shared.open(fileURL)
                }
                .onTapGesture(count: 1) {
                    selectedFileURL = fileURL
                }
                .contextMenu {
                    Button("Set as Teaser") {
                        setTeaser(fileURL)
                    }
                }
        }
    }
    .padding(16)
    .padding(.bottom, 48)
}
```

- [ ] **Step 6: Add teaser helper methods**

```swift
private func isTeaserFile(_ url: URL) -> Bool {
    guard !project.teaser.isEmpty else { return false }
    let teaserURL = project.folderURL.appendingPathComponent(project.teaser)
    return url.standardizedFileURL == teaserURL.standardizedFileURL
}

private func setTeaser(_ url: URL) {
    let relativePath = url.path.replacingOccurrences(
        of: project.folderURL.path + "/",
        with: ""
    )
    // Read current README, update teaser, write back
    guard let content = try? String(contentsOf: project.readmeURL, encoding: .utf8),
          var parsed = try? FrontmatterParser.parse(content) else { return }
    parsed.teaser = relativePath
    let updated = FrontmatterParser.serialize(frontmatter: parsed)
    try? updated.write(to: project.readmeURL, atomically: true, encoding: .utf8)
}
```

- [ ] **Step 7: Extract FAB buttons**

```swift
private var fabButtons: some View {
    HStack(spacing: 12) {
        if currentSubpath.isEmpty {
            Button { isShowingAddLink = true } label: {
                Label("URL", systemImage: "link")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        }

        Button { showFilePicker() } label: {
            Label("File", systemImage: "doc.badge.plus")
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

        Button { startCleanup() } label: {
            Label("Clean up", systemImage: "wand.and.stars")
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
    .padding(16)
}
```

- [ ] **Step 8: Add cleanup stub and regenerate xcodeproj**

Add state and stub method for cleanup (will be implemented in Task 5):

```swift
@State private var isShowingCleanup = false
@State private var cleanupStartIndex: Int = 0

private func startCleanup(from index: Int = 0) {
    cleanupStartIndex = index
    isShowingCleanup = true
}
```

Run: `xcodegen generate && xcodebuild -scheme PortyMcFolio -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 9: Commit**

```bash
git add PortyMcFolio/Views/BreadcrumbBar.swift PortyMcFolio/Views/GalleryView.swift PortyMcFolio.xcodeproj/project.pbxproj
git commit -m "feat: folder navigation with breadcrumb, view toggle, teaser context menu"
```

---

## Task 4: List view

**Files:**
- Create: `PortyMcFolio/Views/GalleryListView.swift`
- Modify: `PortyMcFolio/Views/GalleryView.swift`

- [ ] **Step 1: Create GalleryListView**

Create `PortyMcFolio/Views/GalleryListView.swift`:

```swift
import SwiftUI

struct GalleryListRow: View {
    let url: URL
    let isFolder: Bool
    let isTeaser: Bool
    let isSelected: Bool

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

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Group {
                if isFolder {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.secondary)
                } else {
                    fileIcon
                }
            }
            .frame(width: 20)

            // Filename
            HStack(spacing: 4) {
                Text(url.lastPathComponent)
                    .font(.system(size: 13))
                    .lineLimit(1)
                if isTeaser {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow)
                }
            }

            Spacer()

            // Size (files only)
            if !isFolder {
                Text(fileSize)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }

            // Date
            Text(fileDate)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .task {
            loadFileInfo()
        }
    }

    private var fileIcon: some View {
        let ext = url.pathExtension.lowercased()
        let icon: String
        switch ext {
        case "pdf": icon = "doc.richtext"
        case "mp4", "mov", "avi", "mkv", "m4v": icon = "film"
        case "mp3", "wav", "aac", "m4a": icon = "waveform"
        case "jpg", "jpeg", "png", "gif", "svg", "webp", "avif": icon = "photo"
        default: icon = "doc"
        }
        return Image(systemName: icon)
            .foregroundStyle(.secondary)
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

- [ ] **Step 2: Add listContent to GalleryView**

In `PortyMcFolio/Views/GalleryView.swift`, add the list content computed property:

```swift
@ViewBuilder
private var listContent: some View {
    LazyVStack(spacing: 0) {
        // Folders
        ForEach(folders, id: \.absoluteString) { folderURL in
            GalleryListRow(
                url: folderURL,
                isFolder: true,
                isTeaser: false,
                isSelected: false
            )
            .onTapGesture(count: 2) {
                currentSubpath.append(folderURL.lastPathComponent)
                scanProjectFolder()
            }
            Divider().padding(.leading, 46)
        }

        // Files
        ForEach(files, id: \.absoluteString) { fileURL in
            GalleryListRow(
                url: fileURL,
                isFolder: false,
                isTeaser: isTeaserFile(fileURL),
                isSelected: selectedFileURL == fileURL
            )
            .onTapGesture(count: 2) {
                NSWorkspace.shared.open(fileURL)
            }
            .onTapGesture(count: 1) {
                selectedFileURL = fileURL
            }
            .contextMenu {
                Button("Set as Teaser") {
                    setTeaser(fileURL)
                }
            }
            Divider().padding(.leading, 46)
        }
    }
    .padding(.bottom, 48)
}
```

- [ ] **Step 3: Regenerate xcodeproj and build**

Run: `xcodegen generate && xcodebuild -scheme PortyMcFolio -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Views/GalleryListView.swift PortyMcFolio/Views/GalleryView.swift PortyMcFolio.xcodeproj/project.pbxproj
git commit -m "feat: gallery list view with file size, date, and folder rows"
```

---

## Task 5: Cleanup popup

**Files:**
- Create: `PortyMcFolio/Views/CleanupPopup.swift`
- Modify: `PortyMcFolio/Views/GalleryView.swift`

- [ ] **Step 1: Create CleanupPopup**

Create `PortyMcFolio/Views/CleanupPopup.swift`:

```swift
import SwiftUI
import QuickLookThumbnailing

struct CleanupPopup: View {
    let project: Project
    let files: [URL]
    let existingFolders: [String]
    @Binding var isPresented: Bool
    let startIndex: Int
    let onFileRenamed: () -> Void

    @State private var currentIndex: Int = 0
    @State private var userInput: String = ""
    @State private var selectedFolder: String = ""
    @State private var thumbnail: NSImage?
    @State private var errorMessage: String?
    @State private var isCreatingFolder = false
    @State private var newFolderName: String = ""

    private var currentFile: URL? {
        guard currentIndex >= 0 && currentIndex < files.count else { return nil }
        return files[currentIndex]
    }

    private var prefix: String {
        "\(project.year)_\(Slug.underscoreFrom(project.title))_"
    }

    private var currentExtension: String {
        currentFile?.pathExtension ?? ""
    }

    private var previewName: String {
        let name = userInput.isEmpty ? "..." : Slug.underscoreFrom(userInput)
        return "\(prefix)\(name).\(currentExtension)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Preview area
            ZStack {
                Color(nsColor: .windowBackgroundColor).opacity(0.5)

                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 320, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "doc")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 240)

            VStack(alignment: .leading, spacing: 16) {
                // Progress
                Text("File \(currentIndex + 1) of \(files.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                // Current filename
                Text(currentFile?.lastPathComponent ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)

                // Rename input
                HStack(spacing: 0) {
                    Text(prefix)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .quaternaryLabelColor))

                    TextField("description", text: $userInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .onSubmit { rename() }

                    Text(".\(currentExtension)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .quaternaryLabelColor))
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 1)
                )

                // Preview
                Text("→ \(previewName)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)

                // Folder chips
                HStack(spacing: 6) {
                    Text("Folder:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    folderChip(name: "/", path: "")

                    ForEach(existingFolders, id: \.self) { folder in
                        folderChip(name: folder, path: folder)
                    }

                    Button {
                        isCreatingFolder = true
                    } label: {
                        Text("+ New")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(nsColor: .quaternaryLabelColor), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $isCreatingFolder) {
                        VStack(spacing: 8) {
                            TextField("Folder name", text: $newFolderName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                                .onSubmit { createFolder() }
                            Button("Create") { createFolder() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        }
                        .padding(12)
                    }
                }

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }

                // Actions
                HStack {
                    HStack(spacing: 8) {
                        Button { navigatePrevious() } label: {
                            Image(systemName: "arrow.left")
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color(nsColor: .quaternaryLabelColor), in: RoundedRectangle(cornerRadius: 6))
                        .keyboardShortcut(.leftArrow, modifiers: [])

                        Button { navigateNext() } label: {
                            Image(systemName: "arrow.right")
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color(nsColor: .quaternaryLabelColor), in: RoundedRectangle(cornerRadius: 6))
                        .keyboardShortcut(.rightArrow, modifiers: [])

                        Text("Skip")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        Text("ESC to exit")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Button { rename() } label: {
                            Text("Rename ↵")
                                .font(.system(size: 13, weight: .medium))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(.white)
                        .keyboardShortcut(.return, modifiers: [])
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 480)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 8)
        .onAppear {
            currentIndex = min(startIndex, files.count - 1)
            loadCurrentFile()
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    private func folderChip(name: String, path: String) -> some View {
        Button {
            selectedFolder = path
        } label: {
            Text(name)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    selectedFolder == path
                        ? Color.accentColor.opacity(0.2)
                        : Color(nsColor: .quaternaryLabelColor),
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
    }

    private func loadCurrentFile() {
        guard let file = currentFile else { return }
        userInput = ""
        errorMessage = nil
        thumbnail = nil

        let size = CGSize(width: 640, height: 440)
        let request = QLThumbnailGenerator.Request(
            fileAt: file,
            size: size,
            scale: 2.0,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            DispatchQueue.main.async {
                thumbnail = rep?.nsImage
            }
        }
    }

    private func navigateNext() {
        if currentIndex < files.count - 1 {
            currentIndex += 1
            loadCurrentFile()
        }
    }

    private func navigatePrevious() {
        if currentIndex > 0 {
            currentIndex -= 1
            loadCurrentFile()
        }
    }

    private func rename() {
        guard let file = currentFile else { return }
        let slugged = Slug.underscoreFrom(userInput)
        guard !slugged.isEmpty, slugged != "untitled" else {
            errorMessage = "Enter a description"
            return
        }

        let newName = "\(prefix)\(slugged).\(currentExtension)"
        let targetFolder: URL
        if selectedFolder.isEmpty {
            targetFolder = file.deletingLastPathComponent()
        } else {
            targetFolder = project.folderURL.appendingPathComponent(selectedFolder)
            // Create folder if it doesn't exist
            try? FileManager.default.createDirectory(at: targetFolder, withIntermediateDirectories: true)
        }
        let targetURL = targetFolder.appendingPathComponent(newName)

        if FileManager.default.fileExists(atPath: targetURL.path) {
            errorMessage = "File already exists: \(newName)"
            return
        }

        do {
            try FileManager.default.moveItem(at: file, to: targetURL)
            errorMessage = nil
            onFileRenamed()
            // Auto-advance
            if currentIndex < files.count - 1 {
                // Don't increment — the file list will refresh and shift
                loadCurrentFile()
            } else {
                isPresented = false
            }
        } catch {
            errorMessage = "Rename failed: \(error.localizedDescription)"
        }
    }

    private func createFolder() {
        let name = Slug.underscoreFrom(newFolderName)
        guard !name.isEmpty, name != "untitled" else { return }
        let folderURL = project.folderURL.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        selectedFolder = name
        newFolderName = ""
        isCreatingFolder = false
        onFileRenamed()  // Triggers rescan to pick up new folder
    }
}
```

- [ ] **Step 2: Wire cleanup popup into GalleryView**

In GalleryView, add the `.sheet` for the cleanup popup. After the existing `.sheet(isPresented: $isShowingAddLink)` add:

```swift
.sheet(isPresented: $isShowingCleanup) {
    if !files.isEmpty {
        CleanupPopup(
            project: project,
            files: files,
            existingFolders: folders.map { $0.lastPathComponent },
            isPresented: $isShowingCleanup,
            startIndex: cleanupStartIndex,
            onFileRenamed: { scanProjectFolder() }
        )
    }
}
```

Update `startCleanup` method:

```swift
private func startCleanup(from index: Int = 0) {
    cleanupStartIndex = index
    isShowingCleanup = true
}
```

Also add Enter key to start cleanup from selected file. In the grid content ForEach for files, add to the file item:

In the `.onKeyPress` handler, add Enter support alongside Space:

```swift
.onKeyPress(.return) {
    guard let url = selectedFileURL,
          let index = files.firstIndex(of: url) else { return .ignored }
    startCleanup(from: index)
    return .handled
}
```

- [ ] **Step 3: Regenerate xcodeproj and build**

Run: `xcodegen generate && xcodebuild -scheme PortyMcFolio -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Views/CleanupPopup.swift PortyMcFolio/Views/GalleryView.swift PortyMcFolio.xcodeproj/project.pbxproj
git commit -m "feat: cleanup popup — rename queue with prefix, folder chips, keyboard nav"
```

---

## Task 6: Teaser in project card

**Files:**
- Modify: `PortyMcFolio/Views/ProjectCardView.swift`

- [ ] **Step 1: Add teaser thumbnail to ProjectCardView**

Update `ProjectCardView` to show the teaser image. Add a thumbnail state and loader:

```swift
struct ProjectCardView: View {
    let project: Project
    var onTagTap: ((String) -> Void)?

    @State private var teaserImage: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Teaser image
            if let image = teaserImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 120)
                    .clipped()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(String(project.year))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    StatusBadgeView(status: project.status)
                }

                Text(project.title.isEmpty ? "Untitled" : project.title)
                    .font(.headline)
                    .lineLimit(2)

                if !project.client.isEmpty {
                    Text(project.client)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
            .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
        .task {
            await loadTeaser()
        }
    }

    private func loadTeaser() async {
        guard !project.teaser.isEmpty else { return }
        let teaserURL = project.folderURL.appendingPathComponent(project.teaser)
        guard FileManager.default.fileExists(atPath: teaserURL.path) else { return }

        let size = CGSize(width: 600, height: 240)
        let request = QLThumbnailGenerator.Request(
            fileAt: teaserURL,
            size: size,
            scale: 2.0,
            representationTypes: .thumbnail
        )
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return }
        await MainActor.run {
            teaserImage = rep.nsImage
        }
    }
}
```

- [ ] **Step 2: Add QuickLookThumbnailing import**

Add at the top of `ProjectCardView.swift`:

```swift
import QuickLookThumbnailing
```

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme PortyMcFolio -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Views/ProjectCardView.swift
git commit -m "feat: project card shows teaser thumbnail image"
```

---

## Task 7: Final build and test

- [ ] **Step 1: Full build**

Run: `xcodebuild -scheme PortyMcFolio -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Run tests**

Run: `xcodebuild test -scheme PortyMcFolio -configuration Debug -destination 'platform=macOS' 2>&1 | tail -15`
Expected: All tests pass.

- [ ] **Step 3: Commit any remaining changes**

```bash
git status
# If clean, done. If not, add and commit.
```
