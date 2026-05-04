# External-Edit Resilience — Design

> **Scope:** make the app a good citizen when users edit portfolio files externally (Finder, text editor, `mv`, scripts). Specifically: auto-repair stale **teaser** and **body-embed** references the same way `FavoritesReconciliation` already auto-repairs favorites, and surface a toast when favorites are dropped outright.

**Status:** Approved design. Ready for implementation planning (Plan 4).

**Prerequisites landed:** Error-handling plan (AppLogger + silent-write fixes), data-integrity plan (atomic rename with rollback, editor↔reconciler race via mtime-retry + `.markdownFileDidChange`).

## Motivation

A portfolio folder is source of truth; users will inevitably rename `hero.jpg` to `cover.jpg` in Finder. Today:

- **Favorites** are repaired silently via basename match in `FavoritesReconciliation` (1 match = update, else = drop). Drops are invisible to the user.
- **Teaser** is not repaired at all — the `teaser:` path in frontmatter stays pointed at the old path forever. Grid cards show a fallback thumbnail.
- **Body embeds** (`![[hero.jpg]]` in the body) are not repaired either. Preview renders a broken image; the editor still shows the stale `![[…]]` string.

This plan adds teaser + body-embed repair with the same basename-match semantics favorites already use, in the same reconciliation pass, with a single atomic write. It also adds a toast when favorites are dropped so the user learns when something was actually lost.

## Non-goals

- No ambiguous-rename picker UI. If basename match produces 2+ candidates, the reference stays stale.
- No content-hash / mtime-proximity / fuzzy-name heuristics. Basename uniqueness is the repair signal, period.
- No detection of "user intentionally broke the reference" — repair if we can, leave alone if we can't.
- No recursive walk outside what `enumerateMediaPaths` already visits.
- No toast for teaser or body-embed changes (too chatty). Only favorite drops get a toast.

## Architecture

Three new/changed pure helpers, hooked into a single call site in `ProjectReconciler.syncProject`. No new notification names, no new DB columns, no new frontmatter fields.

### New: `TeaserReconciliation`

```swift
enum TeaserOutcome: Equatable {
    case unchanged
    case repaired(newPath: String)
    case orphaned
}

enum TeaserReconciliation {
    static func reconcile(
        teaser: String,
        onDiskPaths: Set<String>
    ) -> TeaserOutcome
}
```

- Empty teaser → `.unchanged`.
- Teaser path present in `onDiskPaths` → `.unchanged`.
- Teaser missing, basename has exactly 1 match in `onDiskPaths` → `.repaired(newPath:)` with the matched path.
- Teaser missing, 0 or ≥2 basename matches → `.orphaned`.
- Teaser path contains `..` or starts with `/` → `.unchanged` (treat as anomalous; don't repair, don't mark orphaned).

### New: `BodyEmbedReconciliation`

```swift
struct BodyEmbedResult: Equatable {
    let body: String
    let repaired: [(oldPath: String, newPath: String)]
    let orphaned: [String]
}

enum BodyEmbedReconciliation {
    static func reconcile(
        body: String,
        onDiskPaths: Set<String>
    ) -> BodyEmbedResult
}
```

- Regex: `!\[\[([^\]]+)\]\]` (same pattern `MarkdownPreviewView.preprocessEmbeds` uses).
- For each embed:
  - Present on disk → leave alone.
  - Missing, basename has exactly 1 disk match → rewrite that embed's `![[…]]` to the matched relative path; record in `repaired`.
  - Missing, 0 or ≥2 matches → leave alone; record in `orphaned`.
- Multiple embeds pointing to the same renamed file: all rewritten consistently (same basename → same match → same new path).
- Embed path with `..` or leading `/` → skipped, NOT listed in `repaired` or `orphaned`.
- Rewrites preserve all non-embed text byte-for-byte.

### Changed: `FavoritesReconciliation.reconcile`

Today returns `[String]`. Change to:

```swift
struct FavoritesResult: Equatable {
    let reconciled: [String]
    let droppedCount: Int  // entries in original not represented in reconciled,
                           // counted as drops (relocations don't count)
}

static func reconcile(
    favorites: [String],
    onDiskPaths: Set<String>
) -> FavoritesResult
```

All existing call sites (currently one, inside `ProjectReconciler.syncProject`) are updated to read `.reconciled` for the list and `.droppedCount` for the toast decision.

### Changed: `ProjectReconciler.syncProject`

Ordering inside the reparse branch (after frontmatter is parsed):

```
enumerate on-disk media paths (single walk, shared by all three)
  → FavoritesReconciliation.reconcile → (reconciled, droppedCount)
  → TeaserReconciliation.reconcile(parsed.teaser, onDisk)
  → BodyEmbedReconciliation.reconcile(parsed.body, onDisk)
if any of the three produced changes:
  apply updates to `parsed`
  serialize
  atomic write
  post .markdownFileDidChange
if droppedCount > 0:
  post .showToast "<N> favorite(s) removed from \"<Project Title>\" — files gone."
upsert cache + FTS
publish mutation
```

**Write atomicity:** even if all three produce changes, we serialize once and write once. Race protection for the editor comes from Plan 2's mtime-retry in `saveContent` and the `.markdownFileDidChange` post (already in place).

**No-op skip:** if none of the three produced changes, no disk write, no `.markdownFileDidChange` post. Keeps FSEvent churn honest.

**Error handling:** write failure goes through the existing `AppLogger.reconciler.error` path (same as the favorites-write path today). No rollback of in-memory state — next pass tries again.

## Toast copy

Exactly one toast pattern, fired per-project per-pass, only when `droppedCount > 0`:

- N == 1: `"1 favorite removed from \"<project title>\" — file is gone."`
- N >= 2: `"\(N) favorites removed from \"<project title>\" — files are gone."`

Pluralization inline, no helper. Posted via `NotificationCenter.default.post(name: .showToast, object: message)`, same path `ProjectReconciler.syncProject` uses today for the parse-failure toast.

## Edge cases and invariants

- **Teaser pointing to a link file or non-image media.** Teaser is meant to be a thumbnail image but the frontmatter field accepts any relative path. Reconciliation doesn't care about file type — basename match works regardless. If the teaser references `link-abc12345.md` and that file is renamed, the same repair applies. Acceptable.
- **Same file appears in favorites AND body embed AND teaser.** Each is reconciled independently. A single rename gets repaired three times in three different parts of the frontmatter. One write covers all three. ✓
- **Ambiguous basename (two `hero.jpg` in different subfolders).** All three reconciliations return "orphaned"/"unchanged" — reference stays as-is. User sees broken reference but no data loss.
- **Empty on-disk set** (project folder was just created with no media yet): all embeds/teaser paths are orphaned. No repair, no toast for orphans (by policy). Favorites would all be dropped → toast fires once.
- **Body is very long with many embeds.** `BodyEmbedReconciliation` runs once per reconciliation pass per project. Cost is regex + basename-dictionary lookup: O(body length + embed count). Cheap.
- **Embed path with URL-encoded characters (`![[my%20photo.jpg]]`).** Reconciliation compares against `onDiskPaths` directly. If on-disk paths are decoded and embeds are encoded (or vice versa), matching fails silently — reference stays stale. Acceptable first-cut; leave a note for future refinement if users hit this.
- **Re-entrancy:** if the reconciler's own write triggers a FSEvent that re-enters the reconciler pass, the no-op-skip (nothing to change on the second pass) prevents a write loop. The `.markdownFileDidChange` post doesn't trigger a reconciler pass — it only notifies the editor.

## Testing

### Unit — pure, isolated

**`TeaserReconciliationTests`:**
- empty teaser → `.unchanged`
- teaser matches on-disk path → `.unchanged`
- teaser stale, 1 basename match → `.repaired(newPath:)`
- teaser stale, 2+ basename matches → `.orphaned`
- teaser stale, 0 matches → `.orphaned`
- teaser path contains `..` → `.unchanged`
- teaser path starts with `/` → `.unchanged`

**`BodyEmbedReconciliationTests`:**
- body with zero embeds → unchanged, empty `repaired`, empty `orphaned`
- body with one embed matching disk → unchanged
- body with one stale embed + 1 basename match → body rewritten, 1 entry in `repaired`
- body with one stale embed + 0 matches → body unchanged, 1 entry in `orphaned`
- body with one stale embed + 2+ matches → body unchanged, 1 entry in `orphaned`
- body with two embeds pointing to the same renamed file → both occurrences in body rewritten; `repaired` deduplicates by `(oldPath, newPath)` pair so it contains exactly 1 entry, not 2
- body with embed containing `..` → left alone, not in either list
- body with embed starting with `/` → left alone, not in either list
- body rewrite preserves all non-embed text byte-for-byte (assert with a body containing markdown headers, code fences, etc.)

**`FavoritesReconciliationTests` (extend existing):**
- add `droppedCount` assertions for: all kept, some relocated, some dropped, all dropped, empty input.

### Integration — against real reconciler

Add to `ProjectReconcilerTests`:
- **Combined repair, single write:** project with teaser + 2 body embeds + 3 favorites, all pointing at `hero.jpg`. Rename `hero.jpg` → `cover.jpg` on disk (unique basename). Run reconciler. Assert: README rewritten exactly once; teaser is `cover.jpg`; both embeds are `![[cover.jpg]]`; favorites contains `cover.jpg`; one `.markdownFileDidChange` posted.
- **Favorite drop toast:** project with 2 favorites, delete both files on disk (no basename matches). Run reconciler. Assert: reconciled favorites is empty; `.showToast` posted once with the "2 favorites removed" message.
- **No-op skip:** project with 1 favorite + 1 teaser + 1 embed, all paths resolve on disk. Run reconciler. Assert: README was NOT rewritten; no `.markdownFileDidChange` posted.

### What we don't test

- No UI-level toast rendering test — `showToast` + its AppState observer are already exercised by existing paths.
- No concurrent editor-vs-reconciler stress test — Plan 2's mtime-retry + `.markdownFileDidChange` is already covered by the 352-test suite passing under that race.
- No test for the FSEvent → reconciler dispatch path — orthogonal, covered by existing `ProjectReconcilerDebounceTests`.

## Files touched

- Create: `PortyMcFolio/Services/TeaserReconciliation.swift`
- Create: `PortyMcFolio/Services/BodyEmbedReconciliation.swift`
- Modify: `PortyMcFolio/Services/FavoritesReconciliation.swift` (return type + usages)
- Modify: `PortyMcFolio/Services/ProjectReconciler.swift` (`syncProject` body, single call site)
- Create: `PortyMcFolioTests/TeaserReconciliationTests.swift`
- Create: `PortyMcFolioTests/BodyEmbedReconciliationTests.swift`
- Modify: `PortyMcFolioTests/FavoritesReconciliationTests.swift` (add `droppedCount` coverage)
- Modify: `PortyMcFolioTests/ProjectReconcilerTests.swift` (add 3 integration tests)

## Rollout

No migration. The changes are purely additive reconciliation behavior. On first reconciliation pass after upgrade, existing stale teaser/body references will get repaired in place where possible; users may see a one-time burst of "N favorites removed" toasts if they have long-standing broken favorites that were previously silent drops. Acceptable one-time surprise.
