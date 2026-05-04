# Gallery Cleanup Workspace

**Date:** 2026-04-14
**Branch:** `dev/v1-implementation`

---

## Philosophy

The project folder IS the portfolio. The app is a nice window into it — not a database, not lock-in. Designers have messy project folders (screenshots with bad names, unsorted files). The gallery's job is to make cleanup effortless: rename files with consistent names, sort them into folders, and pick a hero image.

No tags. No per-file metadata. No manifest files. The folder structure is the organization. The only metadata the app adds is `teaser:` in the README.md frontmatter.

---

## Features

### 1. Grid + List View Toggle

A segmented control in the gallery toolbar toggles between two views:

**Grid view** (current) — Thumbnail cards in a LazyVGrid. Good for visual browsing. Keeps existing layout: adaptive columns (min 150, max 180), link cards + file cards, drag-and-drop.

**List view** — Table-style rows: icon/thumbnail (small, 28px), filename, file type, file size, modification date. Sortable by clicking column headers. Better for cleanup and renaming — you can see all filenames at a glance.

Both views share the same data source (`scanProjectFolder`). Folders appear as items in both views — with a folder icon. Double-click a folder to enter it.

### 2. Folder Navigation

**Breadcrumb path bar** at the top of the gallery, below the view toggle:

```
Project › wireframes › v2
```

- Each segment is clickable — jumps to that folder level
- Root shows the project name
- Updates as you navigate into subfolders

**Folder items in the gallery:**
- Folders appear as items in both grid and list views (folder icon + name)
- Double-click to enter a folder
- Files can be dragged onto folder items to move them inside
- `scanProjectFolder` becomes recursive-aware: scans the current subfolder, shows its contents + child folders

**Create new folders:**
- From cleanup popup (folder chips have a "+ New" button)
- From right-click context menu in the gallery → "New Folder"

### 3. Cleanup Mode (Rename Popup)

A modal popup for renaming files one by one in a review queue.

**Entry points:**
- **"Clean up" FAB button** (bottom-right alongside URL and File buttons) — queues all files in the current folder, starts from the first file
- **Select a file then press Enter** — starts cleanup from that file, queues remaining files after it
- In both cases, only files are queued (not folders, not link-*.md, not README.md)

**Popup layout:**
- **File preview** — QuickLook thumbnail of the current file, centered, generous size
- **Current filename** — shown as muted text above the input (the "messy" name)
- **Rename input** — three-part field:
  - Prefix (read-only, muted): `YYYY_Project_Name_` derived from `project.year` + slugified `project.title`
  - User input (focused, editable): cursor starts here, user types the descriptive part
  - Extension (read-only, muted): `.png`, `.pdf`, etc.
- **Live preview** — below the input, shows the full resulting filename: `→ 2026_Acme_Rebrand_homepage_wireframe.png`
- **Folder chips** — row of buttons showing existing subfolders in the project root (`/`, `wireframes`, `photos`, `+ New`). Selecting one moves the file into that folder after rename. Default is current folder.
- **Navigation** — `←` `→` buttons (and arrow keys) to skip to previous/next file without renaming. "Skip" label next to arrows.
- **Actions** — "ESC to exit" label + "Rename ↵" primary button

**Behavior:**
- Enter renames the file on disk (via FileManager), moves it to selected folder if different, then auto-advances to next file
- Arrow keys skip without renaming
- ESC exits cleanup mode, returns to gallery
- Progress indicator: "File 3 of 14" in the popup header
- Auto-slugify user input as they type: spaces → underscores, lowercase, strip special characters
- If a file with the target name already exists, show inline error and don't rename

**Prefix derivation:**
- `String(project.year)` + `_` + `Slug.from(project.title)` with underscores instead of hyphens + `_`
- Example: project "Acme Rebrand", year 2026 → `2026_Acme_Rebrand_`

### 4. Teaser Image

One file per project can be marked as the teaser — the cover image shown in the project list.

**Setting the teaser:**
- In the gallery, right-click a file → "Set as Teaser" in context menu
- Or: select a file, click a ⭐ button in the detail area / toolbar

**Storage:**
- Stored as `teaser: relative/path/to/file.jpg` in the README.md frontmatter
- `FrontmatterParser` gains a new `teaser` field in `ParsedFrontmatter`
- `Project` model gains `var teaser: String` (relative path, empty string if not set)
- The frontmatter guard in the editor treats `teaser:` as a read-only key (same as other frontmatter keys)

**Display:**
- `ProjectCardView` in the project list shows the teaser image as a thumbnail/background if set
- The teaser file gets a small ⭐ badge overlay in the gallery grid view
- If the teaser file is deleted or moved, the field becomes stale — cleared on next scan (Project.loadReadme detects file doesn't exist, clears the field)

### 5. Updated FAB Buttons

Three floating capsule buttons in the bottom-right of the gallery:

- **URL** (link icon) — opens AddLinkSheet (existing)
- **File** (doc.badge.plus icon) — opens NSOpenPanel (existing)
- **Clean up** (sparkles or wand icon) — enters cleanup mode for all files in current folder

Same styling as current: `.ultraThinMaterial` capsule background, `.contentShape(Capsule())` for full hit area, subtle shadow.

---

## What Changes

### New files
- `PortyMcFolio/Views/CleanupPopup.swift` — the rename popup view
- `PortyMcFolio/Views/GalleryListView.swift` — list view variant of gallery items
- `PortyMcFolio/Views/BreadcrumbBar.swift` — folder navigation breadcrumb

### Modified files
- `PortyMcFolio/Views/GalleryView.swift` — add view toggle, breadcrumb, folder navigation state, cleanup mode trigger, updated FABs
- `PortyMcFolio/Views/GalleryItemView.swift` — add teaser badge overlay, folder item appearance
- `PortyMcFolio/Views/ProjectCardView.swift` — show teaser thumbnail
- `PortyMcFolio/Models/Project.swift` — add `teaser` field
- `PortyMcFolio/Services/FrontmatterParser.swift` — parse/serialize `teaser` field
- `PortyMcFolio/Services/Slug.swift` — may need underscore variant for filename prefix

### Not changed
- Editor (no changes)
- Link system (no changes)
- SearchIndex (no changes for now — folder structure is the organization)
- No new data files (.gallery.json, sidecar files, etc.)

---

## Out of Scope

- Per-file tags or metadata system
- AI-suggested filenames
- Batch rename patterns
- Spotlight/xattr integration
- File deduplication
- Image editing or cropping
