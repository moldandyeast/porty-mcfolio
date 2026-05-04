# Gallery Multi-Select Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Finder-style multi-select to the PortyMcFolio gallery (grid + list), with batch delete to Trash, drag-to-move between folders, drag-into-editor, and bulk favorite.

**Architecture:** Replace single `selection: GallerySelection?` in `GalleryView` with `selectedItems: Set<GallerySelection>` + `cursor: GallerySelection?`. Extract pure logic (range, move validation, favorite majority) to a testable `MultiSelectLogic` service. Interactions hook into existing tap / keyboard handlers. Multi-file drag writes multiple `public.file-url` entries to the pasteboard via `NSPasteboardWriting` on a host `NSView` wrapper.

**Tech Stack:** SwiftUI + AppKit (macOS 15), XCTest, `FileManager.trashItem`, `NSItemProvider` / `NSPasteboard`.

**Spec:** [docs/superpowers/specs/2026-04-23-gallery-multiselect-design.md](../specs/2026-04-23-gallery-multiselect-design.md)

---

## File Structure

**Create:**
- `PortyMcFolio/Models/GallerySelection.swift` — extracted enum + `Hashable` conformance
- `PortyMcFolio/Services/MultiSelectLogic.swift` — pure helpers: range, move validation, favorite majority
- `PortyMcFolio/Services/DragPayload.swift` — multi-file drag encoding (NSPasteboard writer)
- `PortyMcFolioTests/GallerySelectionTests.swift`
- `PortyMcFolioTests/MultiSelectLogicTests.swift`
- `PortyMcFolioTests/DragPayloadTests.swift`

**Modify:**
- `PortyMcFolio/Views/GalleryView.swift` — state refactor, mouse/keyboard handlers, drag source, drop handlers, batch operations
- `PortyMcFolio/Views/ProjectSettingsPopover.swift:282` — small alignment: `removeItem` → `trashItem` for teaser-overwrite safety

---

## Task 1: Extract `GallerySelection` and add `Hashable`

**Files:**
- Create: `PortyMcFolio/Models/GallerySelection.swift`
- Modify: `PortyMcFolio/Views/GalleryView.swift` (remove enum at lines 9–13)
- Test: `PortyMcFolioTests/GallerySelectionTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// PortyMcFolioTests/GallerySelectionTests.swift
import XCTest
@testable import PortyMcFolio

final class GallerySelectionTests: XCTestCase {
    func testIsHashableInSet() {
        let a = GallerySelection.file(URL(fileURLWithPath: "/a.png"))
        let b = GallerySelection.file(URL(fileURLWithPath: "/b.png"))
        let aDup = GallerySelection.file(URL(fileURLWithPath: "/a.png"))

        var set: Set<GallerySelection> = []
        set.insert(a)
        set.insert(b)
        set.insert(aDup)

        XCTAssertEqual(set.count, 2)
        XCTAssertTrue(set.contains(a))
    }

    func testDistinctCasesAreDistinct() {
        let file = GallerySelection.file(URL(fileURLWithPath: "/x"))
        let folder = GallerySelection.folder(URL(fileURLWithPath: "/x"))
        XCTAssertNotEqual(file, folder)
    }
}
```

- [ ] **Step 2: Run test — expect compile failure**

Run: `xcodebuild test -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/GallerySelectionTests`

Expected: compile fails because `GallerySelection` isn't accessible as a top-level type yet (it's currently nested inside `GalleryView.swift` without `@testable` import reach if it stays file-private — it's already non-private, but extraction is still the right move).

- [ ] **Step 3: Create the extracted file**

```swift
// PortyMcFolio/Models/GallerySelection.swift
import Foundation

enum GallerySelection: Hashable {
    case file(URL)
    case folder(URL)
    case link(String)  // LinkItem.id
}
```

- [ ] **Step 4: Remove the old enum from `GalleryView.swift`**

Delete lines 9–13 (the existing `enum GallerySelection: Equatable { ... }` definition).

- [ ] **Step 5: Regenerate Xcode project and run tests**

Run: `xcodegen generate && xcodebuild test -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/GallerySelectionTests`

Expected: PASS (2 tests).

- [ ] **Step 6: Run the full suite to ensure nothing broke**

Run: `xcodebuild test -scheme PortyMcFolio -destination 'platform=macOS'`

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add PortyMcFolio/Models/GallerySelection.swift PortyMcFolio/Views/GalleryView.swift PortyMcFolioTests/GallerySelectionTests.swift PortyMcFolio.xcodeproj/project.pbxproj
git commit -m "refactor(gallery): extract GallerySelection, add Hashable"
```

---

## Task 2: `MultiSelectLogic.rangeBetween`

**Files:**
- Create: `PortyMcFolio/Services/MultiSelectLogic.swift`
- Test: `PortyMcFolioTests/MultiSelectLogicTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// PortyMcFolioTests/MultiSelectLogicTests.swift
import XCTest
@testable import PortyMcFolio

final class MultiSelectLogicTests: XCTestCase {
    private func sel(_ i: Int) -> GallerySelection {
        .file(URL(fileURLWithPath: "/\(i).png"))
    }

    func testRangeForwardInclusive() {
        let seq = [sel(0), sel(1), sel(2), sel(3), sel(4)]
        let range = MultiSelectLogic.rangeBetween(sel(1), sel(3), in: seq)
        XCTAssertEqual(range, [sel(1), sel(2), sel(3)])
    }

    func testRangeReverseFlips() {
        let seq = [sel(0), sel(1), sel(2), sel(3), sel(4)]
        let range = MultiSelectLogic.rangeBetween(sel(3), sel(1), in: seq)
        XCTAssertEqual(range, [sel(1), sel(2), sel(3)])
    }

    func testRangeSameIndex() {
        let seq = [sel(0), sel(1), sel(2)]
        let range = MultiSelectLogic.rangeBetween(sel(1), sel(1), in: seq)
        XCTAssertEqual(range, [sel(1)])
    }

    func testRangeMissingAnchorReturnsEmpty() {
        let seq = [sel(0), sel(1), sel(2)]
        let range = MultiSelectLogic.rangeBetween(sel(99), sel(1), in: seq)
        XCTAssertEqual(range, [])
    }

    func testRangeMissingTargetReturnsEmpty() {
        let seq = [sel(0), sel(1), sel(2)]
        let range = MultiSelectLogic.rangeBetween(sel(1), sel(99), in: seq)
        XCTAssertEqual(range, [])
    }
}
```

- [ ] **Step 2: Run — expect compile failure**

Run: `xcodegen generate && xcodebuild test -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/MultiSelectLogicTests`

Expected: fails because `MultiSelectLogic` doesn't exist.

- [ ] **Step 3: Create the service file**

```swift
// PortyMcFolio/Services/MultiSelectLogic.swift
import Foundation

enum MultiSelectLogic {
    /// Inclusive slice of `sequence` from `a` to `b` (order-independent).
    /// Returns `[]` if either endpoint isn't in `sequence`.
    static func rangeBetween(
        _ a: GallerySelection,
        _ b: GallerySelection,
        in sequence: [GallerySelection]
    ) -> [GallerySelection] {
        guard let ia = sequence.firstIndex(of: a),
              let ib = sequence.firstIndex(of: b) else { return [] }
        let lo = min(ia, ib)
        let hi = max(ia, ib)
        return Array(sequence[lo...hi])
    }
}
```

- [ ] **Step 4: Regenerate + run tests — expect PASS**

Run: `xcodegen generate && xcodebuild test -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/MultiSelectLogicTests`

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Services/MultiSelectLogic.swift PortyMcFolioTests/MultiSelectLogicTests.swift PortyMcFolio.xcodeproj/project.pbxproj
git commit -m "feat(multiselect): rangeBetween helper"
```

---

## Task 3: `MultiSelectLogic.validateMove`

**Files:**
- Modify: `PortyMcFolio/Services/MultiSelectLogic.swift`
- Modify: `PortyMcFolioTests/MultiSelectLogicTests.swift`

- [ ] **Step 1: Write failing tests**

Append to `MultiSelectLogicTests.swift`:

```swift
    // MARK: - validateMove

    func testMoveIntoDifferentFolderAllowed() {
        let target = URL(fileURLWithPath: "/root/dest")
        let items = [URL(fileURLWithPath: "/root/a.png")]
        XCTAssertEqual(
            MultiSelectLogic.validateMove(items: items, into: target),
            .allowed
        )
    }

    func testMoveFolderIntoItselfRejected() {
        let target = URL(fileURLWithPath: "/root/dest")
        let items = [target]  // trying to move /root/dest into /root/dest
        XCTAssertEqual(
            MultiSelectLogic.validateMove(items: items, into: target),
            .rejected(reason: .targetInSelection)
        )
    }

    func testMoveFolderIntoItsDescendantRejected() {
        let parent = URL(fileURLWithPath: "/root/parent")
        let child = URL(fileURLWithPath: "/root/parent/child")
        XCTAssertEqual(
            MultiSelectLogic.validateMove(items: [parent], into: child),
            .rejected(reason: .targetIsDescendantOfSelection)
        )
    }

    func testMoveWhenTargetIsOneOfTheItemsRejected() {
        let target = URL(fileURLWithPath: "/root/dest")
        let items = [URL(fileURLWithPath: "/root/a.png"), target]
        XCTAssertEqual(
            MultiSelectLogic.validateMove(items: items, into: target),
            .rejected(reason: .targetInSelection)
        )
    }
```

- [ ] **Step 2: Run — expect compile failure (unknown types)**

Run: `xcodebuild test -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/MultiSelectLogicTests`

- [ ] **Step 3: Extend `MultiSelectLogic` with `validateMove`**

Append to `MultiSelectLogic.swift`:

```swift
extension MultiSelectLogic {
    enum MoveValidation: Equatable {
        case allowed
        case rejected(reason: MoveRejectionReason)
    }

    enum MoveRejectionReason: Equatable {
        case targetInSelection
        case targetIsDescendantOfSelection
    }

    /// Validates moving `items` into the folder `target`.
    /// Path checks use prefix semantics on `standardizedFileURL.path`.
    static func validateMove(items: [URL], into target: URL) -> MoveValidation {
        let targetPath = target.standardizedFileURL.path
        for item in items {
            let itemPath = item.standardizedFileURL.path
            if itemPath == targetPath {
                return .rejected(reason: .targetInSelection)
            }
            // Target is a descendant of item (moving a folder into its own subtree)
            if targetPath.hasPrefix(itemPath + "/") {
                return .rejected(reason: .targetIsDescendantOfSelection)
            }
        }
        return .allowed
    }
}
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `xcodebuild test -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/MultiSelectLogicTests`

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Services/MultiSelectLogic.swift PortyMcFolioTests/MultiSelectLogicTests.swift
git commit -m "feat(multiselect): validateMove helper"
```

---

## Task 4: `MultiSelectLogic.favoriteToggleDirection`

**Files:**
- Modify: `PortyMcFolio/Services/MultiSelectLogic.swift`
- Modify: `PortyMcFolioTests/MultiSelectLogicTests.swift`

- [ ] **Step 1: Write failing tests**

Append to `MultiSelectLogicTests.swift`:

```swift
    // MARK: - favoriteToggleDirection

    func testFavoriteDirectionAllFavoritedUnfavorites() {
        let selected = [
            URL(fileURLWithPath: "/root/a.png"),
            URL(fileURLWithPath: "/root/b.png"),
        ]
        let favorites = ["a.png", "b.png", "c.png"]
        let projectRoot = URL(fileURLWithPath: "/root")
        XCTAssertEqual(
            MultiSelectLogic.favoriteToggleDirection(
                selected: selected, projectRoot: projectRoot, favorites: favorites
            ),
            .unfavoriteAll
        )
    }

    func testFavoriteDirectionNoneFavoritedFavorites() {
        let selected = [
            URL(fileURLWithPath: "/root/a.png"),
            URL(fileURLWithPath: "/root/b.png"),
        ]
        let favorites = ["c.png"]
        let projectRoot = URL(fileURLWithPath: "/root")
        XCTAssertEqual(
            MultiSelectLogic.favoriteToggleDirection(
                selected: selected, projectRoot: projectRoot, favorites: favorites
            ),
            .favoriteAll
        )
    }

    func testFavoriteDirectionMixedFavorites() {
        let selected = [
            URL(fileURLWithPath: "/root/a.png"),
            URL(fileURLWithPath: "/root/b.png"),
        ]
        let favorites = ["a.png"]  // only a is favorited
        let projectRoot = URL(fileURLWithPath: "/root")
        XCTAssertEqual(
            MultiSelectLogic.favoriteToggleDirection(
                selected: selected, projectRoot: projectRoot, favorites: favorites
            ),
            .favoriteAll
        )
    }

    func testFavoriteDirectionEmptyNoop() {
        let projectRoot = URL(fileURLWithPath: "/root")
        XCTAssertEqual(
            MultiSelectLogic.favoriteToggleDirection(
                selected: [], projectRoot: projectRoot, favorites: ["a.png"]
            ),
            .noop
        )
    }
```

- [ ] **Step 2: Run — expect compile failure**

Run: `xcodebuild test -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/MultiSelectLogicTests`

- [ ] **Step 3: Extend `MultiSelectLogic` with the helper**

Append to `MultiSelectLogic.swift`:

```swift
extension MultiSelectLogic {
    enum FavoriteAction: Equatable {
        case favoriteAll
        case unfavoriteAll
        case noop
    }

    /// Finder-style majority rule: if every selected file is already in
    /// `favorites`, the action is `.unfavoriteAll`. Otherwise `.favoriteAll`.
    /// Paths in `favorites` are project-root-relative; selected URLs are
    /// converted to the same form via `projectRoot`.
    static func favoriteToggleDirection(
        selected: [URL],
        projectRoot: URL,
        favorites: [String]
    ) -> FavoriteAction {
        guard !selected.isEmpty else { return .noop }
        let rootPath = projectRoot.standardizedFileURL.path
        let selectedRelative: [String] = selected.compactMap { url in
            let p = url.standardizedFileURL.path
            guard p.hasPrefix(rootPath + "/") else { return nil }
            return String(p.dropFirst(rootPath.count + 1))
        }
        guard !selectedRelative.isEmpty else { return .noop }
        let favSet = Set(favorites)
        let allFavorited = selectedRelative.allSatisfy { favSet.contains($0) }
        return allFavorited ? .unfavoriteAll : .favoriteAll
    }
}
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `xcodebuild test -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/MultiSelectLogicTests`

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Services/MultiSelectLogic.swift PortyMcFolioTests/MultiSelectLogicTests.swift
git commit -m "feat(multiselect): favoriteToggleDirection helper"
```

---

## Task 5: Refactor `GalleryView` state to multi-selection (no new behavior)

**Files:**
- Modify: `PortyMcFolio/Views/GalleryView.swift`

**Goal of this task:** replace single-selection state with multi-selection state, keeping click behavior identical to before (a plain click still selects exactly one item). No new interactions yet.

- [ ] **Step 1: Read current state declarations and selection helpers**

Read `PortyMcFolio/Views/GalleryView.swift` — note the lines that declare `selection`, read `selection ==`, write `selection =`, and the `clearSelection()` / `selectedFileURL` / `selectedLinkID` helpers. Enumerate them. You'll replace or re-route each.

- [ ] **Step 2: Replace the state declaration**

Find:

```swift
@State private var selection: GallerySelection?
```

Replace with:

```swift
@State private var selectedItems: Set<GallerySelection> = []
@State private var cursor: GallerySelection? = nil
```

- [ ] **Step 3: Add read helpers near the state**

Insert right after the new state:

```swift
private func isSelected(_ item: GallerySelection) -> Bool {
    selectedItems.contains(item)
}

private var selectedFileURLs: [URL] {
    selectedItems.compactMap {
        if case .file(let u) = $0 { return u } else { return nil }
    }
}

private var selectedFolderURLs: [URL] {
    selectedItems.compactMap {
        if case .folder(let u) = $0 { return u } else { return nil }
    }
}
```

- [ ] **Step 4: Update the existing convenience computed properties**

Replace:

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

with:

```swift
private var selectedFileURL: URL? {
    if case .file(let url) = cursor, selectedItems.contains(cursor!) { return url }
    return nil
}
private var selectedLinkID: String? {
    if case .link(let id) = cursor, selectedItems.contains(cursor!) { return id }
    return nil
}
```

(These stay scoped to "focused single item" semantics for call-sites that only want one thing — QuickLook, link edit modal, etc.)

- [ ] **Step 5: Rewrite `clearSelection()`**

Find the existing `clearSelection()` helper and replace body:

```swift
private func clearSelection() {
    selectedItems.removeAll()
    cursor = nil
}
```

- [ ] **Step 6: Update all `selection == .file(url)` and `selection == .folder(url)` reads**

Grep the file for `selection ==` and `selection != nil`. Replace:

- `selection == .file(url)` → `isSelected(.file(url))`
- `selection == .folder(url)` → `isSelected(.folder(url))`
- `selection == .link(id)` → `isSelected(.link(id))`
- `selection != nil` → `!selectedItems.isEmpty`
- `selection = nil` → `clearSelection()`

- [ ] **Step 7: Update all single-selection `selection = .file(...)` writes to be single-item set**

Every plain click / tap handler that was doing:

```swift
selection = .file(fileURL)
```

becomes:

```swift
selectedItems = [.file(fileURL)]
cursor = .file(fileURL)
```

Same for `.folder(...)` and `.link(...)`. Examples to touch:
- `folderGridItem(_:)` `.onTapGesture(count: 1)`
- `fileGridItem(_:)` — goes through `FileGridTileWithHeart.onSelect` closure, which does `selection = .file(fileURL)`
- List mode row taps (search for `.onTapGesture` in list section)
- Link row taps in `linksContent`

- [ ] **Step 8: Update `navigate(_:)` to move `cursor` and replace selection to cursor**

Find the `navigate(_ direction:)` method in `GalleryView`. Wherever it currently sets `selection = ...`, change to:

```swift
cursor = newItem
selectedItems = [newItem]
```

- [ ] **Step 9: Update `handleSpaceKey` / `handleReturnKey` / cut-paste to read from `cursor`**

These handlers currently check `selection`. Switch to:

- QuickLook / space: use `cursor` (single-item semantics).
- Return / enter: use `cursor`.
- Cut: `if case .file(let url) = cursor { cutFileURL = url }`.

- [ ] **Step 10a: Pass `isCursor` into cells so the focus ring can show even when cursor is not in selectedItems**

Currently `FolderGridCell` and `GalleryItemView` show the focus ring only when `isFocused && isSelected`. After ⌘-click toggles an item out of the selection, cursor stays on it but the ring disappears — user loses the anchor visual.

Add an `isCursor: Bool` parameter to both cells:

```swift
// FolderGridCell
let folderURL: URL
let isSelected: Bool
let isFocused: Bool
let isCursor: Bool   // NEW

// in body, replace:
.opacity(isFocused && isSelected ? 1 : 0)
// with:
.opacity(isFocused && (isSelected || isCursor) ? 1 : 0)
```

Same change in `GalleryItemView`.

Pass it through from the call-sites:

```swift
// folderGridItem
FolderGridCell(
    folderURL: folderURL,
    isSelected: isSelected(.folder(folderURL)),
    isFocused: isGalleryFocused,
    isCursor: cursor == .folder(folderURL)
)

// fileGridItem / FileGridTileWithHeart
FileGridTileWithHeart(
    fileURL: fileURL,
    ...
    isSelected: isSelected(.file(fileURL)),
    isCursor: cursor == .file(fileURL),
    ...
)
```

`FileGridTileWithHeart` passes through to `GalleryItemView` — thread the param.

Also apply to list mode rows (whatever the equivalent struct is — grep for the list-mode row container that currently takes `isSelected`).

- [ ] **Step 10b: Update the `.onKeyPress(.escape)` handler**

Currently (post-earlier-fix):

```swift
.onKeyPress(.escape) {
    if selection != nil {
        clearSelection()
        return .handled
    }
    return .ignored
}
```

Change the check:

```swift
.onKeyPress(.escape) {
    if !selectedItems.isEmpty {
        clearSelection()
        return .handled
    }
    return .ignored
}
```

- [ ] **Step 11: Build and run the app manually**

Run: `xcodebuild build -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -3 && killall PortyMcFolio 2>/dev/null; sleep 1 && open -a <DerivedData>/PortyMcFolio.app`

Manual verification checklist:
- Click a file → highlighted.
- Click a different file → the new one is highlighted, the old one isn't.
- Click a folder → highlighted.
- Double-click folder → navigates in.
- Arrow keys → cursor moves, selection follows.
- ESC (with selection) → selection clears.
- ESC (without selection) → goes back to project list.

- [ ] **Step 12: Run the full test suite**

Run: `xcodebuild test -scheme PortyMcFolio -destination 'platform=macOS'`

Expected: all tests pass (no regressions — no new tests yet for this task).

- [ ] **Step 13: Commit**

```bash
git add PortyMcFolio/Views/GalleryView.swift
git commit -m "refactor(gallery): single selection → selectedItems+cursor

Pure state refactor. Click behavior unchanged — selecting an item replaces
selectedItems with that single item. Prepares for multi-select interactions."
```

---

## Task 6: ⌘-click toggle + ⇧-click range

**Files:**
- Modify: `PortyMcFolio/Views/GalleryView.swift`

- [ ] **Step 1: Add a centralized click handler**

Near the other private helpers in `GalleryView`, add:

```swift
/// Applies Finder-style mouse-click semantics to a tap on `item`.
/// Reads NSEvent.modifierFlags at the moment of the tap.
private func handleTap(on item: GallerySelection) {
    let flags = NSEvent.modifierFlags

    if flags.contains(.command) {
        // Toggle in/out of the selection; cursor always moves here.
        if selectedItems.contains(item) {
            selectedItems.remove(item)
        } else {
            selectedItems.insert(item)
        }
        cursor = item
    } else if flags.contains(.shift), let anchor = cursor {
        // Range select from cursor (anchor) to item.
        let range = MultiSelectLogic.rangeBetween(anchor, item, in: navigableSequence)
        if !range.isEmpty {
            selectedItems = Set(range)
        } else {
            // Fallback: plain click if anchor isn't in the current sequence
            selectedItems = [item]
            cursor = item
        }
    } else {
        // Plain click.
        selectedItems = [item]
        cursor = item
    }
}
```

- [ ] **Step 2: Route grid folder taps through `handleTap`**

In `folderGridItem(_:)`, replace:

```swift
.onTapGesture(count: 1) {
    selectedItems = [.folder(folderURL)]
    cursor = .folder(folderURL)
}
```

with:

```swift
.onTapGesture(count: 1) {
    handleTap(on: .folder(folderURL))
}
```

- [ ] **Step 3: Route grid file taps through `handleTap`**

`fileGridItem(_:)` passes an `onSelect: { ... }` closure into `FileGridTileWithHeart`. Change:

```swift
onSelect: {
    selectedItems = [.file(fileURL)]
    cursor = .file(fileURL)
},
```

to:

```swift
onSelect: { handleTap(on: .file(fileURL)) },
```

- [ ] **Step 4: Route list-mode row taps through `handleTap`**

Grep list-mode render code for `.onTapGesture` that set selection. Route each through `handleTap(on: .file(url))` or `handleTap(on: .folder(url))`.

- [ ] **Step 5: Leave links-mode tap handler alone**

Links-mode taps should continue to replace-to-single — `handleTap` does that when no modifiers are held, which is fine. But links mode has its own tap (opens URL) — don't route that through `handleTap`. Selection in links mode stays as it was: single-item selection assignment.

- [ ] **Step 6: Build + manual verify**

Run: `xcodebuild build -scheme PortyMcFolio -destination 'platform=macOS' && killall PortyMcFolio 2>/dev/null; sleep 1 && open -a <DerivedData>/PortyMcFolio.app`

Manual checklist:
- Plain click: replaces selection to one item.
- ⌘-click on unselected: adds to selection.
- ⌘-click on selected: removes from selection; cursor still moves onto that item.
- ⇧-click: selects range from cursor to clicked item.
- Repeat ⇧-click elsewhere: range is recomputed from cursor (anchor stays; new set from anchor to new click).

- [ ] **Step 7: Commit**

```bash
git add PortyMcFolio/Views/GalleryView.swift
git commit -m "feat(gallery): command-click toggle and shift-click range"
```

---

## Task 7: ⌘A select-all

**Files:**
- Modify: `PortyMcFolio/Views/GalleryView.swift`

- [ ] **Step 1: Find the ⌘-modified `.onKeyPress` block**

Locate the existing `.onKeyPress(phases: .down) { keyPress in guard keyPress.modifiers.contains(.command) else { return .ignored } switch keyPress.characters { ... } }` block (around line 352).

- [ ] **Step 2: Add the "a" case**

Inside the `switch keyPress.characters` block, add:

```swift
case "a":
    selectedItems = Set(navigableSequence)
    cursor = navigableSequence.last
    return .handled
```

(Preserve the existing `"x"`, `"v"`, `"["` cases.)

- [ ] **Step 3: Build + manual verify**

Run: `xcodebuild build -scheme PortyMcFolio -destination 'platform=macOS' && killall PortyMcFolio 2>/dev/null; sleep 1 && open -a <DerivedData>/PortyMcFolio.app`

Manual checklist:
- In grid or list mode, ⌘A selects all visible folders + files in the current folder.
- Cursor jumps to the last item.
- ⌘A in links mode: selects all link cards (acceptable — links mode doesn't care much about multi-select but this shouldn't break anything).

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Views/GalleryView.swift
git commit -m "feat(gallery): command-A selects all visible items"
```

---

## Task 8: ⇧-arrow extends selection

**Files:**
- Modify: `PortyMcFolio/Views/GalleryView.swift`

- [ ] **Step 1: Find the arrow-key handlers**

Look at the existing `.onKeyPress(keys: [.upArrow], phases: .down)`, `[.downArrow]`, `[.leftArrow]`, `[.rightArrow]` handlers — they each call `navigate(direction)`.

- [ ] **Step 2: Update `navigate(_:)` to support extending**

Refactor `navigate(_ direction:)` so it takes an extra param:

```swift
private func navigate(_ direction: NavDirection, extending: Bool = false) {
    // ... compute newItem based on direction, navigableSequence, and cursor ...
    guard let newItem else { return }
    cursor = newItem
    if extending {
        selectedItems.insert(newItem)
    } else {
        selectedItems = [newItem]
    }
}
```

(Keep existing direction logic unchanged — only the final state assignment is different.)

- [ ] **Step 3: Update arrow handlers to pass `extending` from the shift modifier**

Each handler currently looks like:

```swift
.onKeyPress(keys: [.upArrow], phases: .down) { key in
    if key.modifiers.contains(.command) {
        navigate(.first)
    } else {
        navigate(.up)
    }
    return .handled
}
```

Change to:

```swift
.onKeyPress(keys: [.upArrow], phases: .down) { key in
    if key.modifiers.contains(.command) {
        navigate(.first)
    } else {
        navigate(.up, extending: key.modifiers.contains(.shift))
    }
    return .handled
}
```

Repeat for `.downArrow`, `.leftArrow`, `.rightArrow`.

- [ ] **Step 4: Build + manual verify**

Run: `xcodebuild build -scheme PortyMcFolio -destination 'platform=macOS' && killall PortyMcFolio 2>/dev/null; sleep 1 && open -a <DerivedData>/PortyMcFolio.app`

Manual checklist:
- Plain arrow: cursor moves, selection = {cursor}.
- Shift+arrow: cursor moves, new cursor added to selection, old selection retained.
- ⌘+arrow (no shift): first/last, selection = {cursor}.

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Views/GalleryView.swift
git commit -m "feat(gallery): shift-arrow extends selection"
```

---

## Task 9: Batch delete (⌘⌫) with Trash + confirm

**Files:**
- Modify: `PortyMcFolio/Views/GalleryView.swift`
- Possibly modify: existing `ConfirmationSheet` invocation in `GalleryView`

- [ ] **Step 1: Add the ⌘⌫ keyboard handler**

In the existing ⌘-modified `.onKeyPress` block (where ⌘A now lives), add:

```swift
case String(Character(UnicodeScalar(0x7F)!)):   // delete / backspace
    if !selectedItems.isEmpty {
        showBatchDeleteConfirm = true
        return .handled
    }
    return .ignored
```

NOTE: `.onKeyPress(phases: .down)` reads `keyPress.characters` which for delete may be empty or a DEL character. If that doesn't work reliably, use a dedicated `.onKeyPress(keys: [.delete], phases: .down) { key in guard key.modifiers.contains(.command) else { return .ignored } ; ... return .handled }`.

Prefer the dedicated handler:

```swift
.onKeyPress(keys: [.delete], phases: .down) { key in
    guard key.modifiers.contains(.command), !selectedItems.isEmpty else { return .ignored }
    showBatchDeleteConfirm = true
    return .handled
}
```

Add this alongside the other `.onKeyPress` declarations.

- [ ] **Step 2: Add `showBatchDeleteConfirm` state**

Near other `@State` vars:

```swift
@State private var showBatchDeleteConfirm = false
```

- [ ] **Step 3: Add confirm sheet presentation**

Find where the existing single-file `.sheet(isPresented: ...)` or `ConfirmationSheet` is used; add alongside:

```swift
.confirmationDialog(
    "Move \(selectedItems.count) items to Trash?",
    isPresented: $showBatchDeleteConfirm,
    titleVisibility: .visible
) {
    Button("Move to Trash", role: .destructive) { performBatchDelete() }
    Button("Cancel", role: .cancel) { }
}
```

(If your existing single-file flow uses a custom `ConfirmationSheet` view rather than `confirmationDialog`, mirror that pattern instead, with a `count`-aware message.)

- [ ] **Step 4: Implement `performBatchDelete()`**

```swift
private func performBatchDelete() {
    var trashed = 0
    var failed = 0
    var remainingFailures: Set<GallerySelection> = []

    for item in selectedItems {
        let url: URL
        switch item {
        case .file(let u), .folder(let u):
            url = u
        case .link:
            continue  // links not deleted by this path
        }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            trashed += 1
        } catch {
            failed += 1
            remainingFailures.insert(item)
        }
    }

    if failed == 0 {
        NotificationCenter.default.post(name: .showToast, object: "\(trashed) items moved to Trash")
        clearSelection()
    } else {
        NotificationCenter.default.post(name: .showToast, object: "Moved \(trashed) of \(trashed + failed) items; \(failed) failed")
        selectedItems = remainingFailures
        cursor = remainingFailures.first
    }
    scanProjectFolder()
}
```

- [ ] **Step 5: Build + manual verify**

Run: `xcodebuild build -scheme PortyMcFolio -destination 'platform=macOS' && killall PortyMcFolio 2>/dev/null; sleep 1 && open -a <DerivedData>/PortyMcFolio.app`

Manual:
- Select two files, ⌘⌫, confirm → both move to Trash, toast appears.
- Select files + folder, ⌘⌫, confirm → all moved, toast counts correctly.
- Verify in Finder (cmd-space "Trash") that items actually landed in Trash.

- [ ] **Step 6: Commit**

```bash
git add PortyMcFolio/Views/GalleryView.swift
git commit -m "feat(gallery): batch delete via cmd-backspace with Trash + confirm"
```

---

## Task 10: Align teaser replace to Trash

**Files:**
- Modify: `PortyMcFolio/Views/ProjectSettingsPopover.swift`

- [ ] **Step 1: Find the offending line**

In `ProjectSettingsPopover.swift` around line 282:

```swift
if FileManager.default.fileExists(atPath: dest.path) {
    try FileManager.default.removeItem(at: dest)
}
try FileManager.default.copyItem(at: url, to: dest)
```

- [ ] **Step 2: Replace `removeItem` with `trashItem`**

```swift
if FileManager.default.fileExists(atPath: dest.path) {
    try FileManager.default.trashItem(at: dest, resultingItemURL: nil)
}
try FileManager.default.copyItem(at: url, to: dest)
```

- [ ] **Step 3: Build + run full suite**

Run: `xcodebuild test -scheme PortyMcFolio -destination 'platform=macOS'`

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Views/ProjectSettingsPopover.swift
git commit -m "fix(settings): teaser replace moves old file to Trash instead of removing"
```

---

## Task 11: Bulk favorite toggle (L)

**Files:**
- Modify: `PortyMcFolio/Views/GalleryView.swift`

- [ ] **Step 1: Add the `L` key handler**

Add to the `.onKeyPress` stack:

```swift
.onKeyPress(keys: ["l"], phases: .down) { key in
    // Only plain L (no modifiers). With modifiers, let other handlers have it.
    guard key.modifiers.isEmpty else { return .ignored }
    performBulkFavorite()
    return .handled
}
```

- [ ] **Step 2: Implement `performBulkFavorite()`**

Mirrors the existing `toggleFavorite(_ url: URL)` (around line 1170 in GalleryView.swift) — reads the README, mutates the `favorites` array in the parsed frontmatter, writes it back once, posts the file-change + reconciler notifications. One read + one write for the whole batch.

```swift
private func performBulkFavorite() {
    let files = selectedFileURLs
    guard !files.isEmpty else { return }

    let action = MultiSelectLogic.favoriteToggleDirection(
        selected: files,
        projectRoot: project.folderURL,
        favorites: project.favorites
    )
    guard action != .noop else { return }

    // Flush any pending editor save before reading the README
    NotificationCenter.default.post(name: .markdownSaveNow, object: nil)

    // Compute relative paths and validate
    let relPaths: [String] = files
        .map { relativePath(for: $0) }
        .filter { FrontmatterParser.isValidFavoritePath($0) }
    guard !relPaths.isEmpty else { return }

    guard let content = try? String(contentsOf: project.readmeURL, encoding: .utf8),
          var parsed = try? FrontmatterParser.parse(content) else { return }

    var favSet = Set(parsed.favorites)
    switch action {
    case .favoriteAll:   favSet.formUnion(relPaths)
    case .unfavoriteAll: favSet.subtract(relPaths)
    case .noop:          return
    }
    // Keep original ordering where possible, append new ones at end
    var newFavorites = parsed.favorites.filter { favSet.contains($0) }
    for rel in relPaths where !newFavorites.contains(rel) && favSet.contains(rel) {
        newFavorites.append(rel)
    }
    parsed.favorites = newFavorites

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

    let verb = (action == .favoriteAll) ? "Favorited" : "Unfavorited"
    NotificationCenter.default.post(name: .showToast, object: "\(verb) \(relPaths.count) items")
}
```

- [ ] **Step 3: Build + manual verify**

Manual:
- Select 3 unfavorited files, press L → all become favorited, toast "Favorited 3 items".
- Select 3 favorited files, press L → all become unfavorited.
- Select mixed (some favorited, some not), press L → all become favorited (majority rule).
- Select only folders → L is a noop (no toast, no beep necessary; just nothing happens).

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Views/GalleryView.swift
git commit -m "feat(gallery): L toggles favorite on selected files (majority rule)"
```

---

## Task 12: Multi-file drag source + internal drop-to-folder

**Files:**
- Create: `PortyMcFolio/Services/DragPayload.swift`
- Modify: `PortyMcFolio/Views/GalleryView.swift`

This is the biggest task. Two sub-parts:
1. Encode a multi-file drag.
2. Decode on drop into a folder; validate + execute the move.

- [ ] **Step 1: Write failing tests for the payload round-trip**

`PortyMcFolioTests/DragPayloadTests.swift`:

```swift
import XCTest
@testable import PortyMcFolio

final class DragPayloadTests: XCTestCase {
    func testEncodeDecodeSingleURL() throws {
        let urls = [URL(fileURLWithPath: "/a.png")]
        let data = try DragPayload.encode(urls: urls)
        let decoded = try DragPayload.decode(data: data)
        XCTAssertEqual(decoded, urls)
    }

    func testEncodeDecodeMultipleURLs() throws {
        let urls = [
            URL(fileURLWithPath: "/a.png"),
            URL(fileURLWithPath: "/sub/b.png"),
            URL(fileURLWithPath: "/c"),
        ]
        let data = try DragPayload.encode(urls: urls)
        let decoded = try DragPayload.decode(data: data)
        XCTAssertEqual(decoded, urls)
    }

    func testDecodeRejectsMalformed() {
        let junk = Data([0xff, 0xfe, 0xfd])
        XCTAssertThrowsError(try DragPayload.decode(data: junk))
    }
}
```

- [ ] **Step 2: Run — expect compile failure**

Run: `xcodebuild test -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/DragPayloadTests`

- [ ] **Step 3: Implement `DragPayload`**

```swift
// PortyMcFolio/Services/DragPayload.swift
import Foundation
import UniformTypeIdentifiers

enum DragPayload {
    /// Custom pasteboard / item-provider type used for internal multi-file drags.
    /// External consumers (Finder, other apps) ignore this and use the primary
    /// public.file-url entry instead.
    static let typeIdentifier = "com.portymcfolio.drag.urllist"

    enum Error: Swift.Error { case malformed }

    static func encode(urls: [URL]) throws -> Data {
        let strings = urls.map(\.absoluteString)
        return try JSONEncoder().encode(strings)
    }

    static func decode(data: Data) throws -> [URL] {
        let strings = try JSONDecoder().decode([String].self, from: data)
        let urls = strings.compactMap { URL(string: $0) }
        guard urls.count == strings.count else { throw Error.malformed }
        return urls
    }
}
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `xcodegen generate && xcodebuild test -scheme PortyMcFolio -destination 'platform=macOS' -only-testing:PortyMcFolioTests/DragPayloadTests`

- [ ] **Step 5: Update the drag source — single call-site at file grid cell**

In `fileGridItem(_:)` (or wherever the existing `.onDrag { NSItemProvider(object: fileURL as NSURL) }` lives), replace the single-provider approach with a multi-aware one:

```swift
.onDrag {
    let urlsForDrag: [URL] = {
        // If user initiated drag on a selected item with multi-select active,
        // drag the whole selection. Otherwise replace selection to this one
        // and drag just it.
        if selectedItems.contains(.file(fileURL)) && selectedItems.count >= 2 {
            return selectedItems.compactMap {
                switch $0 {
                case .file(let u), .folder(let u): return u
                case .link: return nil
                }
            }
        } else {
            selectedItems = [.file(fileURL)]
            cursor = .file(fileURL)
            return [fileURL]
        }
    }()

    let provider = NSItemProvider()
    // Primary (what external apps / Finder consume)
    provider.registerObject(urlsForDrag[0] as NSURL, visibility: .all)
    // Internal multi-file payload (what our drop target looks for)
    if urlsForDrag.count > 1,
       let encoded = try? DragPayload.encode(urls: urlsForDrag) {
        provider.registerDataRepresentation(
            forTypeIdentifier: DragPayload.typeIdentifier,
            visibility: .ownProcess
        ) { completion in
            completion(encoded, nil)
            return nil
        }
    }
    return provider
}
```

Do the same at the list-mode equivalent drag site (search for the other `.onDrag` in the file).

- [ ] **Step 6: Update folder-tile drop handler to read multi-payload first, fall back to single**

In `folderGridItem(_:)` and the list-mode folder row, the `.onDrop(of: [.fileURL])` handlers currently call `moveDroppedFiles(providers: providers, into: folderURL)`. Extend that helper (see Step 7).

- [ ] **Step 7: Extend `moveDroppedFiles` to consult `DragPayload` first**

Find the existing `moveDroppedFiles(providers:into:)` (around line 1293). Modify:

```swift
@discardableResult
private func moveDroppedFiles(providers: [NSItemProvider], into folderURL: URL) -> Bool {
    // Fast path for internal multi-drag.
    for provider in providers {
        if provider.hasItemConformingToTypeIdentifier(DragPayload.typeIdentifier) {
            provider.loadDataRepresentation(forTypeIdentifier: DragPayload.typeIdentifier) { data, _ in
                guard let data, let urls = try? DragPayload.decode(data: data) else { return }
                DispatchQueue.main.async {
                    self.performMove(urls: urls, into: folderURL)
                }
            }
            return true
        }
    }

    // Fallback: single-file / external drag with one public.file-url.
    var urls: [URL] = []
    let group = DispatchGroup()
    for provider in providers {
        group.enter()
        _ = provider.loadObject(ofClass: NSURL.self) { url, _ in
            defer { group.leave() }
            if let u = url as? URL { urls.append(u) }
        }
    }
    group.notify(queue: .main) {
        self.performMove(urls: urls, into: folderURL)
    }
    return true
}

private func performMove(urls: [URL], into folderURL: URL) {
    let validation = MultiSelectLogic.validateMove(items: urls, into: folderURL)
    switch validation {
    case .rejected(reason: .targetInSelection):
        NotificationCenter.default.post(name: .showToast, object: "Can't move a folder into itself.")
        return
    case .rejected(reason: .targetIsDescendantOfSelection):
        NotificationCenter.default.post(name: .showToast, object: "Can't move a folder into its own subtree.")
        return
    case .allowed:
        break
    }

    var moved = 0
    var skipped = 0
    for src in urls {
        let dest = folderURL.appendingPathComponent(src.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) {
            skipped += 1
            continue
        }
        do {
            try FileManager.default.moveItem(at: src, to: dest)
            moved += 1
        } catch {
            skipped += 1
        }
    }

    let toast: String
    if skipped == 0 {
        toast = "Moved \(moved) items to /\(folderURL.lastPathComponent)"
    } else {
        toast = "Moved \(moved) items to /\(folderURL.lastPathComponent), \(skipped) skipped (name already exists)"
    }
    NotificationCenter.default.post(name: .showToast, object: toast)
    clearSelection()
    scanProjectFolder()
}
```

- [ ] **Step 8: Regenerate Xcode project and build**

Run: `xcodegen generate && xcodebuild build -scheme PortyMcFolio -destination 'platform=macOS' 2>&1 | tail -3 && killall PortyMcFolio 2>/dev/null; sleep 1 && open -a <DerivedData>/PortyMcFolio.app`

Manual verification:
- Create a subfolder in a project.
- Select 3 files, drag onto the subfolder → all 3 move, toast "Moved 3 items to /subfolder".
- Create a file with the same name in the destination, try again → skipped count appears.
- Try to drag a folder onto itself → rejection toast.
- Drag a folder onto one of its children → subtree rejection toast.
- Drag a single file onto a subfolder (no multi-select involved) → still works as before.

- [ ] **Step 9: Commit**

```bash
git add PortyMcFolio/Services/DragPayload.swift PortyMcFolioTests/DragPayloadTests.swift PortyMcFolio/Views/GalleryView.swift PortyMcFolio.xcodeproj/project.pbxproj
git commit -m "feat(gallery): multi-file drag source + drop-to-folder with conflict checks"
```

---

## Task 13: Multi-drag to editor

**Files:**
- Verify / modify: `PortyMcFolio/Views/MarkdownEditorView.swift` (likely no changes needed)

- [ ] **Step 1: Read `MarkdownTextView.performDragOperation`**

Confirm it iterates `readObjects(forClasses: [NSURL.self])` into `insertFileEmbeds(for: urls, at: index)` (it does — this is the existing behavior).

- [ ] **Step 2: Extend to read `DragPayload` if present**

In `performDragOperation(_:)`, before the existing `readObjects` call, check the pasteboard for `DragPayload.typeIdentifier`:

```swift
override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let pb = sender.draggingPasteboard

    // Prefer internal multi-file payload when present.
    if let data = pb.data(forType: NSPasteboard.PasteboardType(rawValue: DragPayload.typeIdentifier)),
       let urls = try? DragPayload.decode(data: data),
       !urls.isEmpty {
        let dropPoint = convert(sender.draggingLocation, from: nil)
        let index = characterIndexForInsertion(at: dropPoint)
        let inserted = insertFileEmbeds(for: urls, at: index)
        if inserted {
            let label = urls.count == 1
                ? "Added: \(urls[0].lastPathComponent)"
                : "Added \(urls.count) files"
            NotificationCenter.default.post(name: .showToast, object: label)
        }
        return inserted
    }

    // Fallback (external drags, single-file): existing behavior
    guard let urls = pb.readObjects(forClasses: [NSURL.self], options: [
        .urlReadingFileURLsOnly: true
    ]) as? [URL], !urls.isEmpty else {
        return super.performDragOperation(sender)
    }

    let dropPoint = convert(sender.draggingLocation, from: nil)
    let index = characterIndexForInsertion(at: dropPoint)
    let inserted = insertFileEmbeds(for: urls, at: index)
    if inserted {
        let label = urls.count == 1
            ? "Added: \(urls[0].lastPathComponent)"
            : "Added \(urls.count) files"
        NotificationCenter.default.post(name: .showToast, object: label)
    }
    return inserted
}
```

- [ ] **Step 3: Register the custom type in `registerDragTypes`**

In `MarkdownTextView.registerDragTypes()`:

```swift
func registerDragTypes() {
    registerForDraggedTypes([
        .fileURL,
        .URL,
        NSPasteboard.PasteboardType(rawValue: DragPayload.typeIdentifier),
    ])
}
```

- [ ] **Step 4: Build + manual verify**

Manual:
- Split mode (editor + gallery), select 3 files in gallery, drag into editor → 3 `![[…]]` embeds appear at cursor, one per line.
- Single file drag from gallery → 1 embed, as before.
- Drag from Finder → external flow still works.

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Views/MarkdownEditorView.swift
git commit -m "feat(editor): accept multi-file drag payload → N embed lines"
```

---

## Task 14: Lifecycle edge cases

**Files:**
- Modify: `PortyMcFolio/Views/GalleryView.swift`

- [ ] **Step 1: Clear selection on folder navigation**

Find `scanProjectFolder()` and the places that mutate `currentSubpath` (breadcrumb `onNavigate` callback at ~line 201-213, and the folder double-tap in `folderGridItem` at ~line 902-906). After each navigation, call `clearSelection()`.

Double-tap on folder already calls `clearSelection()` — confirm. Breadcrumb navigation may not — add it.

- [ ] **Step 2: Prune externally-deleted items from selection**

In the code path that updates `files` / `folders` arrays after `scanProjectFolder()` or after a reconciler event, add:

```swift
let validURLs = Set(files + folders)
selectedItems = selectedItems.filter {
    switch $0 {
    case .file(let u), .folder(let u): return validURLs.contains(u)
    case .link: return true
    }
}
if let c = cursor {
    switch c {
    case .file(let u), .folder(let u):
        if !validURLs.contains(u) { cursor = nil }
    case .link: break
    }
}
```

- [ ] **Step 3: Keep selection across grid ↔ list mode switch**

The `mode` prop is passed into `GalleryView` from `ProjectDetailView`. State is lost when the view itself is re-instantiated. Confirm by inspection: if the parent uses `.id(something)` that changes between modes, state is lost. If not, state persists.

Check `ProjectDetailView` lines 41-67 (the `GalleryView(project:mode:)` call sites). If you see `.id(...)` that varies by mode, remove it or stabilize on `project.uid` only so the gallery view instance persists across mode flips.

Manual verify after:
- Select 3 items in grid mode.
- Switch to list mode (⌘4 or toolbar) → selection still there.
- Switch back → still there.

- [ ] **Step 4: Build + manual verify all edge cases**

Run: `xcodebuild build -scheme PortyMcFolio -destination 'platform=macOS' && killall PortyMcFolio 2>/dev/null; sleep 1 && open -a <DerivedData>/PortyMcFolio.app`

Checklist:
- Navigate into subfolder → selection clears.
- Navigate up via breadcrumb → selection clears.
- Grid ↔ list mode switch → selection survives.
- Delete a selected item via Finder (while app is open) → FSEvent fires, reconciler updates, the item disappears from selection.

- [ ] **Step 5: Commit**

```bash
git add PortyMcFolio/Views/GalleryView.swift PortyMcFolio/Views/ProjectDetailView.swift
git commit -m "feat(gallery): clear selection on navigation, prune stale items, keep across mode"
```

---

## Task 15: Drag count badge + final polish

**Files:**
- Modify: `PortyMcFolio/Views/GalleryView.swift` (if customizing drag preview)

- [ ] **Step 1: Add a count badge to the drag preview when |selection| ≥ 2**

SwiftUI's `.onDrag` accepts a second `preview:` closure (macOS 13+). Use it when `|selectedItems| >= 2`:

```swift
.onDrag({
    // ... returns NSItemProvider as in Task 12 ...
}, preview: {
    if selectedItems.count >= 2 && selectedItems.contains(.file(fileURL)) {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 36))
                .foregroundStyle(theme.colors.textSecondary)
                .padding(16)
                .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: 10))
            Text("\(selectedItems.count)")
                .font(.caption).bold()
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.red, in: Capsule())
                .offset(x: 8, y: -8)
        }
    } else {
        // Fallback: default preview (no explicit View = system default)
        EmptyView()
    }
})
```

- [ ] **Step 2: Run full test suite**

Run: `xcodebuild test -scheme PortyMcFolio -destination 'platform=macOS'`

Expected: all tests pass.

- [ ] **Step 3: Manual end-to-end walkthrough**

- ⌘-click builds a selection.
- ⇧-click extends.
- Arrow keys move cursor, shift-arrow extends.
- ⌘A selects all.
- ⌘⌫ opens confirm, Trash moves items.
- L toggles favorite on files only.
- Drag a selected item → preview shows count badge when ≥ 2.
- Drop on folder → moves.
- Drop on editor → embeds.
- ESC with selection → clears. ESC without → back to project list.

- [ ] **Step 4: Commit**

```bash
git add PortyMcFolio/Views/GalleryView.swift
git commit -m "feat(gallery): count badge on multi-file drag preview"
```

---

## Post-implementation

- [ ] Run the full test suite once more.
- [ ] Check `git log --oneline feature/gallery-multiselect ^main` — should read as a tidy progression.
- [ ] Open PR against `main` with the spec linked.
- [ ] Do the verification checklist from the spec's "Testing / Manual" section before merging.
