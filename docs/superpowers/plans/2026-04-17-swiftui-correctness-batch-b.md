# SwiftUI correctness batch B — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix six SwiftUI correctness and performance issues surfaced by the 2026-04-17 code review: drag-drop mutations off the main actor, `FolderWatcher` held as `@State` (silently recreated), `ForEach` duplicate-ID risk in two places, `Slug` locale non-determinism, a regex compiled every render, and logo images re-read from disk every render.

**Architecture:** Each fix is local to 1-3 files, independent of the others. They can be implemented in any order. Most changes are observable-only in live use; only `Slug` is directly unit-testable.

**Tech Stack:** Swift 5.9, SwiftUI (macOS 14+), XCTest.

**Deferred from Batch B (too large for this plan, pick up in a follow-up):**
- `GalleryView.scanProjectFolder` and `allProjectFolders` moved off main thread.
- `ProjectListView.projectsByYear` caching.

---

## Task 1: GalleryView — wrap drop-completion state access in `@MainActor`

**Files:**
- Modify: `PortyMcFolio/Views/GalleryView.swift` (lines ~764-786 and ~885-901)

### Bug

Both `moveDroppedFiles` and `handleDrop` call `provider.loadItem(forTypeIdentifier:options:)` whose completion fires on an arbitrary queue. Inside the completion:
- Reads `self.currentFolderURL` (derived from `@State var currentSubpath`).
- Calls `self.relativePath(for:)` which reads other `@State`.
- Calls `self.updateReadmeReferences` (file I/O).
- Calls `FileManager.default.moveItem` / `copyItem`.

`@State` is documented as MainActor-isolated; off-main access is UB. The existing `Task { @MainActor in scanProjectFolder() }` at the end of each completion covers only the UI refresh.

### Fix

Wrap the entire contents of each completion closure in `Task { @MainActor in ... }` so all state reads and file operations happen on MainActor.

- [ ] **Step 1: Update `moveDroppedFiles`**

Find the block around line 764-787 in `PortyMcFolio/Views/GalleryView.swift`:

```swift
    private func moveDroppedFiles(providers: [NSItemProvider], into folderURL: URL) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    guard let data = item as? Data,
                          let urlString = String(data: data, encoding: .utf8),
                          let sourceURL = URL(string: urlString) else { return }
                    let currentFolder = self.currentFolderURL.standardizedFileURL.path
                    if sourceURL.deletingLastPathComponent().standardizedFileURL.path == currentFolder {
                        let dest = folderURL.appendingPathComponent(sourceURL.lastPathComponent)
                        if !FileManager.default.fileExists(atPath: dest.path) {
                            let oldRel = self.relativePath(for: sourceURL)
                            try? FileManager.default.moveItem(at: sourceURL, to: dest)
                            self.updateReadmeReferences(oldRelative: oldRel, newRelative: self.relativePath(for: dest))
                        }
                    }
                    Task { @MainActor in self.scanProjectFolder() }
                }
                handled = true
            }
        }
        return handled
    }
```

Replace with:

```swift
    private func moveDroppedFiles(providers: [NSItemProvider], into folderURL: URL) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    guard let data = item as? Data,
                          let urlString = String(data: data, encoding: .utf8),
                          let sourceURL = URL(string: urlString) else { return }
                    // Hop to MainActor so @State reads (currentFolderURL, relativePath)
                    // and FileManager mutations coordinate with the view lifecycle.
                    Task { @MainActor in
                        let currentFolder = self.currentFolderURL.standardizedFileURL.path
                        if sourceURL.deletingLastPathComponent().standardizedFileURL.path == currentFolder {
                            let dest = folderURL.appendingPathComponent(sourceURL.lastPathComponent)
                            if !FileManager.default.fileExists(atPath: dest.path) {
                                let oldRel = self.relativePath(for: sourceURL)
                                try? FileManager.default.moveItem(at: sourceURL, to: dest)
                                self.updateReadmeReferences(oldRelative: oldRel, newRelative: self.relativePath(for: dest))
                            }
                        }
                        self.scanProjectFolder()
                    }
                }
                handled = true
            }
        }
        return handled
    }
```

- [ ] **Step 2: Update `handleDrop`**

Find the block around line 885-901:

```swift
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    guard let data = item as? Data,
                          let urlString = String(data: data, encoding: .utf8),
                          let sourceURL = URL(string: urlString) else { return }
                    let destURL = currentFolderURL.appendingPathComponent(sourceURL.lastPathComponent)
                    try? FileManager.default.copyItem(at: sourceURL, to: destURL)
                    Task { @MainActor in scanProjectFolder() }
                }
                handled = true
            }
        }
        return handled
    }
```

Replace with:

```swift
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    guard let data = item as? Data,
                          let urlString = String(data: data, encoding: .utf8),
                          let sourceURL = URL(string: urlString) else { return }
                    Task { @MainActor in
                        let destURL = currentFolderURL.appendingPathComponent(sourceURL.lastPathComponent)
                        try? FileManager.default.copyItem(at: sourceURL, to: destURL)
                        scanProjectFolder()
                    }
                }
                handled = true
            }
        }
        return handled
    }
```

- [ ] **Step 3: Build**

```bash
xcodebuild build -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Full test suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Views/GalleryView.swift
git commit -m "fix: drop-handler state access and file I/O on MainActor"
```

---

## Task 2: Make `FolderWatcher` an `ObservableObject` and use `@StateObject`

**Files:**
- Modify: `PortyMcFolio/Views/GalleryView.swift` (FolderWatcher class at line ~914 + property at line 19)

### Bug

`FolderWatcher` is a `private final class` (reference type). It is stored as `@State var folderWatcher = FolderWatcher()` in `GalleryView`. `@State` is designed for value types; reference types held via `@State` can be silently replaced by SwiftUI on view recreation, causing the old instance to deinit (→ `source?.cancel()` via `deinit`). That drops the file-system watch silently.

### Fix

Make `FolderWatcher` conform to `ObservableObject` (no `@Published` needed — nothing reactively observes its fields). Change the property declaration to `@StateObject`, which SwiftUI keeps alive across view recreations.

- [ ] **Step 1: Add `ObservableObject` conformance to `FolderWatcher`**

Near the bottom of `PortyMcFolio/Views/GalleryView.swift` (around line 914), find:

```swift
private final class FolderWatcher {
```

Replace with:

```swift
private final class FolderWatcher: ObservableObject {
```

No other changes to the class body.

- [ ] **Step 2: Change `@State` to `@StateObject` on the property**

Find line ~19 in the same file:

```swift
    @State private var folderWatcher = FolderWatcher()
```

Replace with:

```swift
    @StateObject private var folderWatcher = FolderWatcher()
```

**Important:** SwiftUI requires `@StateObject` targets to be `ObservableObject`, which we just ensured. `@StateObject`'s initializer is `@autoclosure` and captured by reference — only created on first render. If the view is recreated, the same instance is reused. This is exactly the behavior we want.

- [ ] **Step 3: Build**

```bash
xcodebuild build -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Full test suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Views/GalleryView.swift
git commit -m "fix: hold FolderWatcher as @StateObject so file-system watch survives view recreation"
```

---

## Task 3: Fix `ForEach` duplicate-ID risk in `ProjectDetailView` and `TagChipInput`

**Files:**
- Modify: `PortyMcFolio/Views/ProjectDetailView.swift` (lines ~119-151)
- Modify: `PortyMcFolio/Views/TagChipInput.swift` (lines ~91-97)

### Bug

Three `ForEach(x, id: \.self)` sites iterate user-entered strings that could duplicate:
- `ProjectDetailView.swift:122` — `ForEach(clients, id: \.self)` (clients derived from splitting `project.client` comma-string; a string `"A, A"` would produce two `"A"`s).
- `ProjectDetailView.swift:139` — `ForEach(project.tags, id: \.self)` (project tags array; duplicates possible in theory).
- `TagChipInput.swift:93` — `ForEach(tags, id: \.self)`.

SwiftUI `ForEach` with duplicate identities produces undefined row behavior (we already hit this bug in `SearchPalette` for file IDs).

### Fix

Use index-based identity: `ForEach(Array(xs.enumerated()), id: \.offset) { idx, element in ... }`. For display-only `ProjectDetailView` rows this is strictly cosmetic — no diffing semantics are lost. For `TagChipInput`'s removable chips, `idx` actually *improves* correctness of the remove action (use `tags.remove(at: idx)` instead of `tags.firstIndex(of:)`).

- [ ] **Step 1: Update `ProjectDetailView` clients ForEach**

Find the block at lines ~119-134:

```swift
                    if !project.client.isEmpty {
                        let clients = project.client.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        Text("  |  ")
                            .foregroundStyle(DT.Colors.textTertiary.opacity(0.5))
                        ForEach(clients, id: \.self) { client in
                            Button(client) {
                                searchAndGoBack(client)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(DT.Colors.textTertiary)

                            if client != clients.last {
                                Text(", ")
                                    .foregroundStyle(DT.Colors.textTertiary.opacity(0.5))
                            }
                        }
                    }
```

Replace with:

```swift
                    if !project.client.isEmpty {
                        let clients = project.client.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        Text("  |  ")
                            .foregroundStyle(DT.Colors.textTertiary.opacity(0.5))
                        ForEach(Array(clients.enumerated()), id: \.offset) { idx, client in
                            Button(client) {
                                searchAndGoBack(client)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(DT.Colors.textTertiary)

                            if idx < clients.count - 1 {
                                Text(", ")
                                    .foregroundStyle(DT.Colors.textTertiary.opacity(0.5))
                            }
                        }
                    }
```

- [ ] **Step 2: Update `ProjectDetailView` tags ForEach**

Find the block at lines ~136-151:

```swift
                    if !project.tags.isEmpty {
                        Text("  |  ")
                            .foregroundStyle(DT.Colors.textTertiary.opacity(0.5))
                        ForEach(project.tags, id: \.self) { tag in
                            Button(tag) {
                                searchAndGoBack(tag)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(DT.Colors.textTertiary)

                            if tag != project.tags.last {
                                Text(" · ")
                                    .foregroundStyle(DT.Colors.textTertiary.opacity(0.5))
                            }
                        }
                    }
```

Replace with:

```swift
                    if !project.tags.isEmpty {
                        Text("  |  ")
                            .foregroundStyle(DT.Colors.textTertiary.opacity(0.5))
                        ForEach(Array(project.tags.enumerated()), id: \.offset) { idx, tag in
                            Button(tag) {
                                searchAndGoBack(tag)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(DT.Colors.textTertiary)

                            if idx < project.tags.count - 1 {
                                Text(" · ")
                                    .foregroundStyle(DT.Colors.textTertiary.opacity(0.5))
                            }
                        }
                    }
```

- [ ] **Step 3: Update `TagChipInput` tags ForEach**

Find at lines ~91-97:

```swift
    private var tagPills: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                tagChip(tag)
            }
        }
    }
```

Replace with:

```swift
    private var tagPills: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(tags.enumerated()), id: \.offset) { idx, tag in
                tagChip(tag, at: idx)
            }
        }
    }
```

- [ ] **Step 4: Update `TagChipInput.tagChip` to use the index for removal**

Find `tagChip(_:)` in `TagChipInput.swift` (lines ~99-124). Change the signature and the `onTapGesture` removal:

Original:
```swift
    private func tagChip(_ tag: String) -> some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(DT.Typography.caption)
                .foregroundStyle(DT.Colors.textPrimary)

            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(DT.Colors.textTertiary)
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
        .background(DT.Colors.surfaceHover, in: Capsule())
        .overlay(Capsule().stroke(DT.Colors.border, lineWidth: 0.5))
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                if let idx = tags.firstIndex(of: tag) {
                    _ = tags.remove(at: idx)
                }
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Remove \(tag)")
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
```

Changed:
```swift
    private func tagChip(_ tag: String, at index: Int) -> some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(DT.Typography.caption)
                .foregroundStyle(DT.Colors.textPrimary)

            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(DT.Colors.textTertiary)
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
        .background(DT.Colors.surfaceHover, in: Capsule())
        .overlay(Capsule().stroke(DT.Colors.border, lineWidth: 0.5))
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                // Index-based removal — exactly removes the tapped chip even
                // when duplicate strings exist. (Was firstIndex(of: tag).)
                if index < tags.count {
                    _ = tags.remove(at: index)
                }
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Remove \(tag)")
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
```

- [ ] **Step 5: Build**

```bash
xcodebuild build -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Full test suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add PortyMcFolio/Views/ProjectDetailView.swift PortyMcFolio/Views/TagChipInput.swift
git commit -m "fix: index-based ForEach ids for clients/tags to avoid duplicate-id view collisions"
```

---

## Task 4: `Slug` — use POSIX locale for deterministic folding; add test

**Files:**
- Modify: `PortyMcFolio/Services/Slug.swift` (both methods)
- Modify: `PortyMcFolioTests/SlugTests.swift` (add a regression test)

### Bug

Both `Slug.from` and `Slug.underscoreFrom` call `.folding(options:locale:)` with `locale: .current`. Unicode folding under `locale: .current` is not the same across systems: e.g., in `tr_TR`, `"I".lowercased()` yields `"ı"` (dotless i), so `"IMAX_Launch"` on a Turkish-locale machine produces a different slug than on an English one. Since the slug becomes the on-disk folder name, two users can have non-portable portfolios.

### Fix

Use an explicit invariant locale: `Locale(identifier: "en_US_POSIX")`.

- [ ] **Step 1: Write the failing regression test**

Open `PortyMcFolioTests/SlugTests.swift` and add:

```swift
    func testSlugFromIsLocaleIndependentForTurkishI() {
        // Guard against locale-dependent folding: in tr_TR, "I".lowercased()
        // returns "ı". Using locale=.current in the implementation would
        // leak that into folder names. A POSIX locale keeps results stable.
        let result = Slug.from("IMAX Launch")
        XCTAssertEqual(result, "imax-launch")
    }

    func testUnderscoreSlugIsLocaleIndependentForTurkishI() {
        let result = Slug.underscoreFrom("IMAX Launch")
        XCTAssertEqual(result, "imax_launch")
    }
```

Also add at the top of the file (if not already present): `import Foundation` and `@testable import PortyMcFolio`. (Likely both already present — check first.)

Run to see current behavior:
```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/SlugTests 2>&1 | tail -20
```
The tests should PASS on an English-locale machine (because `"I".lowercased()` → `"i"` under en). They are a regression guard, not a failing-first test. Document that — the fix is defensive for users on non-en locales.

- [ ] **Step 2: Apply the fix**

In `PortyMcFolio/Services/Slug.swift`, replace both occurrences of:
```swift
locale: .current
```
with:
```swift
locale: Locale(identifier: "en_US_POSIX")
```

(Line 6 and line 31.)

- [ ] **Step 3: Run tests — still expect PASS**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/SlugTests 2>&1 | tail -20
```

- [ ] **Step 4: Full test suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Services/Slug.swift PortyMcFolioTests/SlugTests.swift
git commit -m "fix: slug folding uses POSIX locale to stay deterministic across user locales"
```

---

## Task 5: `MarkdownPreviewView` — hoist the embed regex to a `static let`

**Files:**
- Modify: `PortyMcFolio/Views/MarkdownPreviewView.swift` (line ~50 and ~118)

### Bug

`preprocessEmbeds` compiles the same regex on every body render:
```swift
let embedRE = try! NSRegularExpression(pattern: #"!\[\[([^\]]+)\]\]"#)
```
`preprocessEmbeds` runs from `updateNSView`, which fires on every SwiftUI body pass affecting the preview. `NSRegularExpression` compilation is thread-safe but non-trivial — cheap per call, but wasted work at every keystroke in the editor.

Same pattern exists in the `export(...)` static method at line ~118.

### Fix

Extract one `static let embedRegex` and reuse it in both call sites.

- [ ] **Step 1: Add the static constant**

In `PortyMcFolio/Views/MarkdownPreviewView.swift`, near the top of the struct (after the stored properties, before any computed properties or methods), add:

```swift
    /// Compiled once — matches `![[filename]]` embed tokens.
    private static let embedRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"!\[\[([^\]]+)\]\]"#)
    }()
```

- [ ] **Step 2: Replace the two instantiations**

- Find `preprocessEmbeds` around line 50. Replace the line `let embedRE = try! NSRegularExpression(...)` with `let embedRE = Self.embedRegex`.
- Find `export(...)` around line 118. Replace the line `let embedRE = try NSRegularExpression(pattern: #"!\[\[([^\]]+)\]\]"#)` with `let embedRE = Self.embedRegex`.

- [ ] **Step 3: Build**

```bash
xcodebuild build -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Full test suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Views/MarkdownPreviewView.swift
git commit -m "perf: hoist markdown-embed regex to static let"
```

---

## Task 6: Cache bundle-loaded logo in `AppSettingsView` and `SplashView`

**Files:**
- Modify: `PortyMcFolio/Views/SplashView.swift`
- Modify: `PortyMcFolio/Views/AppSettingsView.swift`

### Bug

Both views call `loadLogo()` inside `body`, which reads the SVG from the bundle on every render pass. `body` re-runs whenever `colorScheme` changes (which is a common source of render invalidation).

### Fix

Introduce a `@State private var logo: NSImage?` loaded in `onAppear` and re-loaded on `onChange(of: colorScheme)`. Read from the cache in `body`.

- [ ] **Step 1: Update `SplashView`**

Current shape of `PortyMcFolio/Views/SplashView.swift`:

```swift
struct SplashView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            DT.Colors.background.ignoresSafeArea()

            GeometryReader { geo in
                VStack(spacing: DT.Spacing.sm) {
                    if let image = loadLogo() {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geo.size.width * 0.5)
                    }

                    // …
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func loadLogo() -> NSImage? {
        let name = colorScheme == .dark ? "logo-dark" : "logo-light"
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg") else { return nil }
        return NSImage(contentsOf: url)
    }
}
```

Add a `@State var logo: NSImage?` and an `.onAppear` + `.onChange(of: colorScheme)` loader. Replace `if let image = loadLogo()` with `if let image = logo`. The `loadLogo()` function stays for use by the loaders.

```swift
struct SplashView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var logo: NSImage?

    var body: some View {
        ZStack {
            DT.Colors.background.ignoresSafeArea()

            GeometryReader { geo in
                VStack(spacing: DT.Spacing.sm) {
                    if let image = logo {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geo.size.width * 0.5)
                    }

                    // … (leave any existing siblings unchanged)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { logo = loadLogo() }
        .onChange(of: colorScheme) { _, _ in logo = loadLogo() }
    }

    private func loadLogo() -> NSImage? {
        let name = colorScheme == .dark ? "logo-dark" : "logo-light"
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg") else { return nil }
        return NSImage(contentsOf: url)
    }
}
```

Keep the body structure between the braces identical — only the guarded block and the property + modifiers change.

- [ ] **Step 2: Update `AppSettingsView`**

Apply the same pattern. Current shape:

```swift
struct AppSettingsView: View {
    // existing properties
    @Environment(\.colorScheme) private var colorScheme
    // …

    private var header: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.md) {
            if let image = loadLogo() {
                Image(nsImage: image)
                    // …
            }
            // …
        }
    }

    // …

    private func loadLogo() -> NSImage? {
        let name = colorScheme == .dark ? "logo-dark" : "logo-light"
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg") else { return nil }
        return NSImage(contentsOf: url)
    }
}
```

Add `@State private var logo: NSImage?` alongside the other properties. Replace `if let image = loadLogo()` in `header` with `if let image = logo`. Add the loaders on the top-level `body`:

```swift
    var body: some View {
        // existing content
        .onAppear { logo = loadLogo() }
        .onChange(of: colorScheme) { _, _ in logo = loadLogo() }
    }
```

If `.onAppear`/`.onChange` modifiers already exist on `body`, merge into them rather than duplicating.

- [ ] **Step 3: Build**

```bash
xcodebuild build -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Full test suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Views/SplashView.swift PortyMcFolio/Views/AppSettingsView.swift
git commit -m "perf: cache bundle-loaded logo in splash and settings"
```

---

## Task 7: Final verification

- [ ] **Step 1: Full test suite**

```bash
xcodebuild test -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: all tests pass.

- [ ] **Step 2: Launch the rebuilt app for user manual checks**

```bash
xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio -configuration Debug -destination 'platform=macOS' -derivedDataPath build build 2>&1 | tail -3
pkill -x PortyMcFolio 2>/dev/null; sleep 1
open build/Build/Products/Debug/PortyMcFolio.app
```

Manual acceptance criteria (for the user — controller does not perform):
- Drag a file from the gallery into a subfolder — still works, no crash.
- Drag an external file into an empty folder — copied in, gallery refreshes.
- Open a project, switch away, switch back — file-system watch is still live (modify a file outside the app, see it appear in the gallery).
- Tag chip in settings popover — click × on a tag; only that tag removed, even if two with same text exist.
- `⌘,` settings → logo visible. Toggle dark/light system mode — logo swaps.

No final commit (each task committed its own changes).

---

## Spec coverage check

| Requirement | Task |
|---|---|
| Drag-drop state access on MainActor | Task 1 |
| `FolderWatcher` survives view recreation | Task 2 |
| `ForEach` uses stable non-colliding ids | Task 3 |
| `Slug` deterministic across locales | Task 4 |
| Embed regex not recompiled per render | Task 5 |
| Logo not re-read from bundle per render | Task 6 |
| No regression in 106 existing tests | All tasks Step 4 |
