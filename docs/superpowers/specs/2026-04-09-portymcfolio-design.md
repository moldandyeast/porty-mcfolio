# PortyMcFolio — Design Spec

**Date:** 2026-04-09
**Status:** Draft
**Platform:** macOS (Swift, SwiftUI)

---

## Overview

PortyMcFolio is a native macOS app for creatives to manage a local portfolio. It combines a project organizer, gallery-first file browser, and Obsidian-compatible WYSIWYG markdown editor into a single tool. The portfolio lives entirely on the local filesystem — no cloud, no proprietary formats, no lock-in.

**Target audience:** Multi-disciplinary creatives — designers, photographers, developers, 3D artists, writers, anyone whose work spans diverse file types.

---

## Data Model

### Portfolio Root

- User selects a single folder via `NSOpenPanel` on first launch
- Path persisted as a sandboxed security-scoped bookmark in `UserDefaults`
- All projects live as immediate child folders of this root

### Project Folders

Created by the app. Naming convention:

```
{Year}-{Name}-{UUID}/
```

- **Year:** 4-digit year (e.g., `2025`)
- **Name:** slugified project name (lowercase, hyphens, no spaces)
- **UUID:** short 8-char hex for uniqueness
- Example: `2025-brand-identity-acme-a3f1b2c4/`

Leading with year gives natural chronological sorting in Finder.

### Project README

Each project folder contains a `README.md` created at project creation:

```markdown
---
title: "Brand Identity — Acme"
date: 2025-03-15
tags: [branding, identity]
client: ""
status: draft
---

# Brand Identity — Acme

Project description here.
```

**Frontmatter fields (v1):**

| Field    | Type          | Required | Description                                      |
|----------|---------------|----------|--------------------------------------------------|
| `title`  | string        | yes      | Display name                                     |
| `date`   | date          | yes      | Project date                                     |
| `tags`   | list[string]  | no       | Freeform tags for filtering and search            |
| `client` | string        | no       | Client name                                      |
| `status` | enum          | yes      | `draft`, `active`, `complete`, or `archived`      |

### URL Link Items

Links are first-class gallery items stored as markdown files in the project folder:

```
link-{8-char-hex}.md
```

```markdown
---
type: link
url: "https://dribbble.com/shots/12345"
title: "Dribbble — Final Concepts"
annotation: "Client loved option B, see comments"
date: 2025-03-15
---
```

- Rendered as distinct cards in the gallery (favicon/og-image, title, URL, annotation)
- Click opens URL in default browser
- Indexed by search like any other markdown
- Portable and Obsidian-visible

### Files

Everything else in the project folder is unmanaged. The app displays files in the gallery but does not dictate internal folder structure.

---

## App Architecture

### Technology Stack

| Layer                  | Technology                  | Rationale                                                    |
|------------------------|-----------------------------|--------------------------------------------------------------|
| App chrome, navigation | SwiftUI                     | Native feel, vibrancy, system integration                    |
| Gallery / file browser | SwiftUI (`LazyVGrid`)       | Native grid, thumbnails, drag-and-drop                       |
| Markdown editor        | Tiptap v2 in `WKWebView`   | WYSIWYG editing, rich embeds, beautiful typography via CSS   |
| Search index           | SQLite with FTS5            | Fast full-text search, extensible                            |
| File watching          | FSEvents                    | Detect external changes to portfolio and project folders     |

### Why WKWebView for the Editor

The visual ceiling is highest with web-based rendering. CSS gives total control over typography, spacing, transitions, and embedded media. Tiptap (built on ProseMirror) provides structured WYSIWYG editing — the edit experience *is* the preview. No separate edit/preview toggle needed.

The app chrome and gallery remain native SwiftUI so it still feels like a Mac app.

---

## Navigation & Layout

### Two-Level Drill-Down

**Level 1 — Project List (full window)**
- Grid/list of all projects
- Each project shows: name, year, status badge, tag pills
- Search bar at top filters the list in real-time
- "New Project" button
- Click a project to drill in

**Level 2 — Project Detail**
- Back button to return to project list
- Two views within a project:
  - **Editor** — Tiptap WYSIWYG rendering of `README.md` (edit and preview are one)
  - **Gallery** — thumbnail grid of all files + link items in the folder

**Toolbar:** Minimal — search field, new project button. Within gallery view: grid size controls, add-link button.

---

## Markdown Editor (Tiptap)

### Implementation

- Tiptap v2 bundled as local HTML/CSS/JS assets in the app — no network dependency
- Runs inside a `WKWebView`
- Swift-to-JS bridge via `WKScriptMessageHandler` for:
  - Loading markdown content into the editor
  - Receiving content changes (for auto-save)
  - Triggering save

### Markdown Features

- **YAML frontmatter** — parsed and rendered as a styled metadata header (title, date, tags as pills, status badge)
- **Wiki-links** — `[[Project Name]]` rendered as clickable links that navigate to the referenced project
- **Embedded media** — `![[image.png]]` resolved relative to the project folder, rendered inline
- **Standard markdown** — headings, lists, code blocks, tables, links, images

### Output Format

Tiptap serializes to markdown (not HTML) so the `.md` file stays clean and Obsidian-compatible. The README.md on disk is always the source of truth.

### Saving

- Auto-save on debounce (1.5s after last keystroke)
- Writes directly to `README.md` on disk
- No separate database for content

---

## Gallery & File Handling

### Thumbnails

- Generated via `QLThumbnailGenerator` — works for images, PDFs, videos, 3D files, documents, anything macOS can preview
- File name label beneath each thumbnail
- Link items rendered as distinct cards with favicon/og-image, title, annotation

### Rich Inline Previews

For common creative formats, richer than a static thumbnail:

| File Type           | Preview Approach                                  |
|---------------------|---------------------------------------------------|
| Images              | Native `Image` view, full resolution on selection |
| Video               | `AVPlayerView` inline playback                    |
| Audio               | `AVPlayerView` with waveform/controls             |
| PDF                 | `PDFView` with page navigation                    |
| 3D (USDZ/OBJ)      | `SceneView` with orbit controls                   |
| Documents           | `QLPreviewView` embedded (system handles it)      |
| Everything else     | `QLPreviewView` fallback                          |

### Quick Look (Space Bar)

- `QLPreviewPanel` — the exact native Finder space-bar experience
- Select a file in the gallery, press space, get the system Quick Look panel

### File Operations

- **Drag-and-drop** from Finder into the gallery copies files into the project folder
- **Add Link** button opens a dialog for URL + title + annotation, creates the link `.md` file
- **Click** opens the file in the system default app via `NSWorkspace.shared.open`
- **File watching** via FSEvents so the gallery updates if files are added/removed externally

---

## Search

### Index

- SQLite database with FTS5 stored in the app's Application Support directory (not in the portfolio folder)
- Indexed on project creation and updated when `README.md` or link files are saved
- FSEvents watcher on the portfolio root detects external changes and re-indexes

### What's Indexed (v1)

- Frontmatter fields: title, date, tags, client, status
- Full markdown body text
- Project folder name
- Link item metadata (URL, title, annotation)

### Search UX

- Search bar at the top of the Project List view (`Cmd+F` to focus)
- Typing filters the project list in real-time
- Matches against tags, title, body text, link metadata
- Clicking a tag anywhere in the app filters the project list by that tag

### Out of Scope (v1)

- File name search within project folders
- Content search inside non-markdown files
- Fuzzy matching

The SQLite FTS5 foundation is designed to scale — adding file name search, fuzzy matching, or faceted filtering later extends the index and query layer without rearchitecture.

---

## Future Directions (Not in v1)

These are noted for architectural awareness — the v1 design should not block them.

- **Multiple gallery layouts:** list view, card view, freeform spatial canvas for organizing files visually
- **Sidecar markdown:** optional `{filename}.sidecar.md` companion files for any asset in the gallery, providing per-file notes, context, and annotations
- **Expanded search:** file name search, fuzzy matching, faceted filtering
- **Multiple portfolio roots:** registering several folders (e.g., "Client Work", "Personal", "Archive")

---

## Technical Constraints

- **macOS only** — no iOS/iPadOS target for v1
- **No network dependency** — all assets bundled, all data local
- **File-first** — the filesystem is the source of truth, the SQLite index is derived and rebuildable
- **Obsidian compatibility** — markdown files must remain valid and useful when opened in Obsidian
