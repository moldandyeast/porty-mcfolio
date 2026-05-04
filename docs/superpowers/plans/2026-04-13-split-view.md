# Editor + Gallery Split View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a split view mode so the editor and gallery can be open side by side with a draggable divider, with persisted layout preference.

**Architecture:** Add a `ViewMode` enum (editor/split/gallery) persisted in `UserDefaults` via `AppState`. `ProjectDetailView` switches between full-width editor, full-width gallery, or an `HSplitView` with both. Gallery thumbnails gain `.onDrag` so files can be dragged into the editor in split mode.

**Tech Stack:** SwiftUI, `HSplitView`, `NSItemProvider`, `UserDefaults`

---

### Task 1: Add ViewMode to AppState with persistence

**Files:**
- Modify: `PortyMcFolio/App/AppState.swift`

- [ ] **Step 1: Add ViewMode enum and persisted properties**

Add the following at the top of `AppState.swift`, before the `AppState` class:

```swift
enum ViewMode: Int, Codable {
    case editor = 0
    case split = 1
    case gallery = 2
}
```

Then add two new published properties inside the `AppState` class, after the `isShowingNewProject` line:

```swift
    @Published var viewMode: ViewMode = .editor {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: "viewMode") }
    }
    @Published var splitRatio: CGFloat = 0.6 {
        didSet { UserDefaults.standard.set(splitRatio, forKey: "splitRatio") }
    }
```

- [ ] **Step 2: Load persisted values on init**

Add a method to `AppState` after the `loadSavedRoot()` method:

```swift
    func loadLayoutPreferences() {
        if let raw = UserDefaults.standard.object(forKey: "viewMode") as? Int,
           let mode = ViewMode(rawValue: raw) {
            viewMode = mode
        }
        let ratio = UserDefaults.standard.double(forKey: "splitRatio")
        if ratio > 0 {
            splitRatio = ratio
        }
    }
```

- [ ] **Step 3: Call loadLayoutPreferences from the app entry point**

Find where `loadSavedRoot()` is called (in `PortyMcFolioApp.swift`) and add `loadLayoutPreferences()` right after it. Read `PortyMcFolio/App/PortyMcFolioApp.swift` to find the exact location. The call should look like:

```swift
appState.loadSavedRoot()
appState.loadLayoutPreferences()
```

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/App/AppState.swift PortyMcFolio/App/PortyMcFolioApp.swift
git commit -m "feat: add ViewMode enum with UserDefaults persistence"
```

---

### Task 2: Update ProjectDetailView with 3-mode segmented control and split layout

**Files:**
- Modify: `PortyMcFolio/Views/ProjectDetailView.swift`

- [ ] **Step 1: Replace the entire ProjectDetailView with the new implementation**

Replace the contents of `PortyMcFolio/Views/ProjectDetailView.swift` with:

```swift
import SwiftUI

struct ProjectDetailView: View {
    let project: Project
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Button {
                    appState.selectedProject = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)

                Text(project.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Picker("", selection: $appState.viewMode) {
                    Text("Editor").tag(ViewMode.editor)
                    Text("Split").tag(ViewMode.split)
                    Text("Gallery").tag(ViewMode.gallery)
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Content
            switch appState.viewMode {
            case .editor:
                editorPane
            case .gallery:
                GalleryView(project: project)
            case .split:
                GeometryReader { geometry in
                    let minEditor: CGFloat = 300
                    let minGallery: CGFloat = 200
                    let totalWidth = geometry.size.width
                    let editorWidth = max(minEditor, min(totalWidth - minGallery, totalWidth * appState.splitRatio))

                    HStack(spacing: 0) {
                        editorPane
                            .frame(width: editorWidth)

                        SplitDivider(
                            ratio: $appState.splitRatio,
                            totalWidth: totalWidth,
                            minLeft: minEditor,
                            minRight: minGallery
                        )

                        GalleryView(project: project)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var editorPane: some View {
        EditorView(readmeURL: project.readmeURL) { _ in
            appState.refreshProjects()
        }
    }
}

struct SplitDivider: View {
    @Binding var ratio: CGFloat
    let totalWidth: CGFloat
    let minLeft: CGFloat
    let minRight: CGFloat

    @State private var isDragging = false

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .cursor(.resizeLeftRight)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                isDragging = true
                                let newLeft = max(minLeft, min(totalWidth - minRight, value.location.x))
                                ratio = newLeft / totalWidth
                            }
                            .onEnded { _ in
                                isDragging = false
                            }
                    )
            )
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project PortyMcFolio.xcodeproj -scheme PortyMcFolio build 2>&1 | tail -5`

If there are build errors related to `cursor` or `NSCursor`, the `.cursor()` modifier may need adjustment for the macOS version. Check the error and fix accordingly.

- [ ] **Step 3: Commit**

```bash
git add PortyMcFolio/Views/ProjectDetailView.swift
git commit -m "feat: add split view mode with draggable divider"
```

---

### Task 3: Add drag source to GalleryItemView

**Files:**
- Modify: `PortyMcFolio/Views/GalleryItemView.swift`
- Modify: `PortyMcFolio/Views/GalleryView.swift`

- [ ] **Step 1: Add .onDrag to GalleryItemView**

In `PortyMcFolio/Views/GalleryItemView.swift`, add `.onDrag` to the outer `VStack`. Replace the closing of the VStack (after the `.task` modifier) so the end of the `body` looks like:

```swift
        .task {
            await loadThumbnail()
        }
        .onDrag {
            NSItemProvider(object: fileURL as NSURL)
        }
```

- [ ] **Step 2: Verify gallery items are draggable**

Open Xcode, run the app, switch to Split mode, and verify you can drag a file thumbnail from the gallery. The drag image should appear. Dropping it in the editor should insert `![[filename]]`.

- [ ] **Step 3: Commit**

```bash
git add PortyMcFolio/Views/GalleryItemView.swift
git commit -m "feat: add drag source to gallery items for editor drop"
```

---

### Task 4: Test and polish

- [ ] **Step 1: Test all three modes**

1. Open a project, verify Editor mode works (full width editor)
2. Switch to Gallery mode, verify full width gallery
3. Switch to Split mode, verify editor left + gallery right
4. Drag the divider, verify it resizes both panes
5. Quit and relaunch, verify the mode and split ratio are preserved

- [ ] **Step 2: Test drag from gallery to editor**

1. In Split mode, drag a file from the gallery onto the editor
2. Verify `![[filename]]` is inserted at the cursor position
3. Verify the media preview renders

- [ ] **Step 3: Final commit with all files**

```bash
git add -A
git commit -m "feat: editor + gallery split view with drag-to-insert"
```
