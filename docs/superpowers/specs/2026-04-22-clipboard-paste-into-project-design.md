# Paste Files and Images from System Clipboard into Project

**Date:** 2026-04-22
**Scope:** `PortyMcFolio/Views/GalleryView.swift`, `PortyMcFolio/Views/MarkdownEditorView.swift`, plus a new `PortyMcFolio/Services/ClipboardPaste.swift` and `PortyMcFolioTests/ClipboardPasteTests.swift`.

## Summary

Wire ⌘V in both the gallery and the markdown editor to paste content from the system pasteboard:

- **File URLs** (copied from Finder or any other app) → copy into the project, with the gallery placing them in the currently-viewed folder and the editor copying them to the project root and inserting `![[filename]]` at the cursor.
- **Image data** (copied from Safari, screenshots, Preview, etc.) → materialize as `pasted-{yyyy-MM-dd-HHmmss}.png` in the same destination, and in the editor also insert an `![[…]]` embed.
- **Plain text** (editor only) → unchanged, continues to insert as plain text.

Today neither surface supports paste-from-clipboard for non-text content. The editor has drag-drop for files; the gallery has drag-drop for files plus an internal cut/paste between folders. Clipboard ⌘V is a natural completion of the same workflows, especially for screenshots.

## Motivation

Two workflows that currently require detours:

1. **"I grabbed a screenshot; I want it in my project."** Today the user has to save the screenshot to disk (e.g. Desktop) and then drag it into the app. Cmd+Shift+Ctrl+4 → ⌘V anywhere in the project would skip the intermediate file.
2. **"I copied an image on a website to send to a client."** Safari's "Copy Image" puts PNG bytes on the clipboard with no file path. There's no way to get that image into a project without first saving it to Finder.

File-URL paste is a smaller win (drag-drop already works), but adds the symmetry that makes ⌘V "just work" wherever you are in the app. It also matches the muscle memory of users coming from Finder, Notes, and most image-centric apps.

## Scope

**In scope:**
- New pure helper `ClipboardPaste` exposing `readFileURLs`, `readImageData`, `pastedImageName`.
- Gallery ⌘V handler extended to fall through to system clipboard paste when no internal cut is pending.
- Editor `paste(_:)` extended to try file-URLs and image-data before falling through to plain-text insert. Drag-drop logic is refactored so paste and drop share one insertion path.
- Unit tests for `ClipboardPaste` helpers.

**Out of scope:**
- Paste in other view modes (preview, split, carousel). They have no logical "current folder" or "cursor" and the feature has no natural meaning there.
- Paste of plain text into the gallery (no target for text content in the gallery — the Links composer handles URLs separately and that stays).
- Auto-renaming on collision. Current internal-paste behavior is an alert; we keep that for consistency.
- Dragging from the app OUT to Finder (system drag-source). Unrelated.
- Accepting rich-text / RTF paste as something other than plain text in the editor. The editor's plain-text-only paste rule is a deliberate past decision; preserved.

## Design

### Gallery ⌘V flow

When the gallery has focus and the user hits ⌘V, the handler decides in priority order:

1. **Internal cut pending?** (`cutFileURL != nil`) → execute the existing move-between-folders path (`pasteFile()` as it exists today). Return. No system clipboard reads happen. This preserves muscle memory for the cut→paste flow.
2. **System clipboard has file URLs?** (via `ClipboardPaste.readFileURLs()`) → for each URL:
    - Skip if the URL points at a folder, symlink, or anything that isn't a regular file (`ClipboardPaste.readFileURLs` has already filtered, but the gallery confirms once more at copy time to avoid TOCTOU surprises).
    - `destURL = currentFolderURL / source.lastPathComponent`.
    - If `destURL` already exists → record the conflict, skip.
    - Else `FileManager.copyItem(at: source, to: destURL)` — COPY, not MOVE. Finder keeps its source file.
    - After the loop, if any conflicts occurred, show ONE alert: `"Some files weren't pasted because they already exist here: foo.png, bar.pdf"`. No individual per-file alerts.
3. **System clipboard has image data?** (via `ClipboardPaste.readImageData()`) → write PNG bytes to `currentFolderURL / pastedImageName()`. If that path happens to exist (unusual — would require two pastes in the same clock second), show the same single-file collision alert.
4. **Nothing matched?** → silently no-op.

After any path that produced at least one new file:
- Call the existing `scanProjectFolder()` to refresh the grid/list model.
- Set `selection` to the last successfully pasted file, so the user sees a visible confirmation and can immediately press Space for Quick Look or ⌘[arrow] for the cleanup shortcuts.

The existing `pasteFile()` function is renamed to `pasteInternalCutFile()` to signal it's one of three paths. A new `pasteFromClipboard()` function owns paths 2–3. The top-level `pasteFile()` becomes the dispatcher: checks internal cut first, else calls `pasteFromClipboard()`.

### Editor ⌘V flow

`MarkdownTextView.paste(_:)` at [MarkdownEditorView.swift:32](../../PortyMcFolio/Views/MarkdownEditorView.swift:32) is replaced with a decision tree that mirrors the gallery flow but writes into the project root (same target drop currently uses) and inserts an embed. Priority order:

1. **Clipboard has file URLs?** → for each URL:
    - Determine whether it already lives under `projectFolderURL`. If yes, use its project-relative path as the embed filename. If no, copy it into `projectFolderURL` (skip if the destination already exists — do NOT error), and use its basename.
    - Accumulate `![[filename]]` strings.
    - After the loop, insert the joined embed text at the caret using the existing line-aware insertion logic already in [performDragOperation](../../PortyMcFolio/Views/MarkdownEditorView.swift:78-88) (line-empty → replace line; line-non-empty → append newline + embed).
2. **Clipboard has image data?** → write PNG bytes to `projectFolderURL / pastedImageName()`, then insert `![[pasted-….png]]` at the caret via the same line-aware insertion.
3. **Clipboard has plain text?** → current behavior: `insertText(string, replacementRange: selectedRange())`. Preserved exactly as today; no styled paste, no URL sniffing.
4. **Nothing?** → no-op.

To avoid duplicating the line-aware insertion + auto-copy logic between `paste(_:)` and `performDragOperation(_:)`, both are refactored to call a shared private helper:

```swift
private func insertFileEmbeds(for urls: [URL], at insertionIndex: Int)
```

`performDragOperation` continues to pass the drop-point-derived index; `paste(_:)` passes `selectedRange().location`. The helper does the copy-if-needed + basename-vs-relative-path + line-aware insert, and returns whether anything was inserted.

Image-data paste similarly goes through a second helper:

```swift
private func insertImageDataEmbed(_ data: Data, at insertionIndex: Int)
```

that writes the file and then calls the same underlying insert.

**No error alerts in the editor.** The editor follows its own drop convention: copy-if-not-there is idempotent, the embed always gets inserted (the file is either already at `projectFolderURL / basename` or it's been copied there). If `FileManager.copyItem` throws (disk full, permissions), the embed still inserts pointing at a path that won't resolve — the user sees the missing-file state in the preview and can react. This matches current drop behavior.

### `ClipboardPaste` helper

New file `PortyMcFolio/Services/ClipboardPaste.swift`:

```swift
import AppKit

enum ClipboardPaste {

    /// File URLs on the system pasteboard, filtered to regular files.
    /// Folders, symlinks, and non-file URLs are dropped. Returns [] if
    /// the pasteboard has no file URLs.
    static func readFileURLs(from pb: NSPasteboard = .general) -> [URL] {
        let urls = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []

        return urls.filter { url in
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return exists && !isDir.boolValue
        }
    }

    /// PNG bytes from any image representation on the pasteboard.
    /// Returns nil if no image is present or if encoding fails.
    static func readImageData(from pb: NSPasteboard = .general) -> Data? {
        guard let image = NSImage(pasteboard: pb),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }

    /// Filename for a pasted image, using second-resolution local time.
    /// Example: "pasted-2026-04-22-143022.png".
    static func pastedImageName(date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return "pasted-\(f.string(from: date)).png"
    }
}
```

**Precedence rule** (applied by the call sites, not by the helper): files before images. Finder commonly puts a low-res preview image on the clipboard alongside the file-URL when you ⌘C a file; reading `readFileURLs()` first and only falling through to `readImageData()` when no files are found means we treat the paste as "paste the file," not "paste a thumbnail."

**`NSImage(pasteboard:)` covers the common input types** out of the box: `.png`, `.tiff`, `.pdf` (as an image), file-backed images (though those also appear as file-URLs, which we handle first). The TIFF round-trip into `NSBitmapImageRep` is the standard macOS path to force a PNG re-encode.

### Collision and UX summary

Gallery:
- File-URL paste collision → collect into a list, alert ONCE at the end listing collided filenames.
- Image-data paste collision → effectively impossible (second-resolution timestamp); if it does happen, same alert path.
- Success → `scanProjectFolder()`, select the last-pasted file.
- No progress UI. No per-file confirmation.

Editor:
- File copy collision → silent skip the copy, still insert the embed. Same as current drop behavior.
- Image-data write collision → silent skip (again, unreachable in practice).
- Success → embed inserted at caret using the existing line-aware placement.
- No progress UI.

Keyboard:
- Gallery ⌘V: handled in the view's existing key shortcut wiring at [GalleryView.swift:368](../../PortyMcFolio/Views/GalleryView.swift:368). No new keybinding.
- Editor ⌘V: already routed through `performKeyEquivalent` at [MarkdownEditorView.swift:105](../../PortyMcFolio/Views/MarkdownEditorView.swift:105). The existing `paste(nil)` call now reaches the extended `paste(_:)` override automatically.

### Help / shortcuts docs

The existing Gallery shortcuts section in [AppSettingsView.swift:477](../../PortyMcFolio/Views/AppSettingsView.swift:477) already lists "Paste File" at ⌘V. No change needed — the shortcut is the same; the behavior is broader. The help copy in the Editor section at [AppSettingsView.swift:359](../../PortyMcFolio/Views/AppSettingsView.swift:359) does not currently mention paste; adding a single feature row about it ("Paste files or images from the clipboard to embed them") is in scope.

## Files touched

**New files:**
- `PortyMcFolio/Services/ClipboardPaste.swift` — pure helper (~30 LOC).
- `PortyMcFolioTests/ClipboardPasteTests.swift` — unit tests (~80 LOC).

**Modified files:**
- `PortyMcFolio/Views/GalleryView.swift`:
    - Rename existing `pasteFile()` to `pasteInternalCutFile()` (the body is unchanged).
    - Add a new top-level `pasteFile()` that dispatches: internal cut → internal paste; else → `pasteFromClipboard()`.
    - Add `pasteFromClipboard()` implementing paths 2–3 of the flow.
    - Add `selectFile(url:)` helper (or inline) for post-paste selection.
- `PortyMcFolio/Views/MarkdownEditorView.swift`:
    - Extract the inner body of `performDragOperation` into `insertFileEmbeds(for:at:)`.
    - Add `insertImageDataEmbed(_:at:)` using `ClipboardPaste.pastedImageName()`.
    - Rewrite `paste(_:)` to try file-URLs, then image-data, then fall through to the existing plain-text branch.
- `PortyMcFolio/Views/AppSettingsView.swift`:
    - Append one `featureRow` in the Editor help section describing clipboard paste.

**Regenerated:**
- `PortyMcFolio.xcodeproj/project.pbxproj` (via `xcodegen generate` after the new Swift files are added).

**Not touched:** `project.yml`, `PortyMcFolio.entitlements`, `FrontmatterParser`, `Project`, `AppState`, `ProjectCreator`, any model or service outside `ClipboardPaste`.

## Testing

**Unit tests — `ClipboardPasteTests.swift`:**

- `testPastedImageNameStable` — given a fixed `Date(timeIntervalSince1970: …)`, returns the exact expected string.
- `testReadFileURLsReturnsRegularFiles` — push two file-URLs onto a scratch `NSPasteboard.withUniqueName()`, assert both returned.
- `testReadFileURLsFiltersFolders` — push a directory URL and a file URL, assert only the file returned.
- `testReadFileURLsEmptyOnTextPasteboard` — scratch pasteboard with a `.string`, assert `[]`.
- `testReadImageDataReturnsPNGFromTIFF` — build a known `NSImage`, write its `tiffRepresentation` onto a scratch pasteboard under `.tiff`, assert `readImageData` returns a `Data` that begins with the PNG signature bytes `89 50 4E 47`.
- `testReadImageDataNilWhenNoImage` — scratch pasteboard with just `.string`, returns `nil`.
- `testReadImageDataNilOnEmptyPasteboard` — empty scratch pasteboard, returns `nil`.

Scratch pasteboards are created with `NSPasteboard(name: .init(rawValue: UUID().uuidString))` so tests don't mutate the real `.general` pasteboard.

**No view-level unit tests** for the gallery/editor paste orchestration — this project has no SwiftUI view tests by convention. Manual checklist below.

**Manual verification (run after implementation):**

- Gallery, file paste: in Finder, ⌘C on a file. Switch to PortyMcFolio gallery. ⌘V. File appears in current folder, is selected.
- Gallery, multi-file paste: in Finder, ⌘A + ⌘C on 3 files. Gallery ⌘V. All three appear. Last one selected.
- Gallery, file collision: ⌘V a second time without clearing. Alert lists the colliding filenames.
- Gallery, image paste: take a screenshot to clipboard (Shift+Cmd+Ctrl+4). Gallery ⌘V. `pasted-….png` appears and is selected.
- Gallery, Safari image paste: right-click an image on a website → Copy Image. Gallery ⌘V. `pasted-….png` appears.
- Gallery, internal cut still works: ⌘X a file, navigate to a sibling folder, ⌘V. File moves. System clipboard is NOT consulted. Folder refresh completes.
- Gallery, folder ignored: in Finder, ⌘C on a folder. Gallery ⌘V. Silent no-op.
- Gallery, subfolder target: navigate into a subfolder. ⌘V a file. File lands in the subfolder, not the project root.
- Editor, file paste: Finder ⌘C on a file. Editor ⌘V. File is copied into project root if not already there. `![[filename]]` appears at the caret.
- Editor, image paste: screenshot to clipboard. Editor ⌘V. `pasted-….png` appears in project root, `![[pasted-….png]]` inserted at caret. Preview renders the image.
- Editor, text paste unchanged: ⌘C a sentence from this spec, editor ⌘V. Plain text appears at the caret, no rich formatting.
- Editor, text + file mix: can't easily construct this — acceptable edge case.
- ⌘V in preview / split / carousel: no crash, no action.

## Rollout & revert

Strictly additive for both surfaces. The gallery's internal cut/paste is untouched (one rename, same function body). The editor's plain-text paste is preserved as the fall-through. Drag-drop in the editor is structurally refactored (shared helper with paste) but functionally identical — the manual drop tests can be re-run to confirm.

No migrations. No preference keys. No schema changes.

Revert is `git revert -m 1 <merge-sha>` of the eventual merge. No side effects to roll back: any files the user pasted with the new path stay where they are (just file copies), and the Links composer, Project creation, and carousel features are untouched.
