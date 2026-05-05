import SwiftUI

struct AppSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var updateController: UpdateController
    @Environment(\.theme) var theme
    @Environment(\.colorScheme) private var colorScheme
    @State private var logo: NSImage?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header

                zoneHeader("PREFERENCES")
                appearanceSection
                divider
                workspaceSection
                divider
                portfolioSection

                zoneHeader("MANUAL")
                gettingStartedSection
                divider
                importingContentSection
                divider
                projectMetadataSection
                divider
                viewModesSection
                divider
                editorSection
                divider
                gallerySection
                divider
                carouselSection
                divider
                searchSection
                divider
                themesSection
                divider
                shortcutsSection
                divider
                updatesSection

                HStack {
                    Spacer()
                    Text("Minimal Lovable Software by Mold&Yeast")
                        .font(DT.Typography.caption)
                        .foregroundStyle(theme.colors.textTertiary)
                    Spacer()
                }
                .padding(.top, 48)
            }
            .padding(DT.Spacing.xl)
            .padding(.bottom, 64)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.background)
        .background {
            Button("") { appState.isShowingSettings = false }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
                .allowsHitTesting(false)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    appState.isShowingSettings = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.colors.textSecondary)
                }
                .iconButton()
                .help("Back to projects")
            }
            ToolbarItem(placement: .principal) {
                Text("Settings")
                    .font(DT.Typography.headline)
                    .foregroundStyle(theme.colors.textPrimary)
            }
        }
        .onAppear { logo = loadLogo() }
        .onChange(of: colorScheme) { _, _ in logo = loadLogo() }
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(theme.colors.border)
            .frame(height: 0.5)
            .padding(.vertical, 32)
    }

    /// Top-level zone marker separating SETTINGS from REFERENCE.
    /// Uppercase, tracked, centered above a hairline rule.
    private func zoneHeader(_ label: String) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme.colors.border)
                .frame(height: 0.5)
                .padding(.bottom, DT.Spacing.lg)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.colors.textTertiary)
                .tracking(2)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, DT.Spacing.xl)
        }
        .padding(.top, 48)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.md) {
            if let image = logo {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 160, height: 160)
                    .padding(.bottom, DT.Spacing.sm)
            }

            Text("Porty McFolio")
                .font(DT.Typography.largeTitle)
                .foregroundStyle(theme.colors.textPrimary)

            Text("A minimal portfolio manager for creatives. Organize projects in folders, write markdown documentation, manage files and links, and export when ready.")
                .font(DT.Typography.body)
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        section("Appearance") {
            VStack(alignment: .leading, spacing: DT.Spacing.md) {
                HStack(spacing: DT.Spacing.md) {
                    ForEach(Theme.all, id: \.id) { t in
                        themeCard(t)
                    }
                }

                // Light / Dark / System override. Follows the OS by default;
                // explicit picks force the chosen appearance app-wide.
                VStack(alignment: .leading, spacing: DT.Spacing.xs) {
                    Text("MODE")
                        .font(DT.Typography.micro)
                        .foregroundStyle(theme.colors.textTertiary)
                        .tracking(1)
                    HStack(spacing: DT.Spacing.xs) {
                        ForEach(AppState.AppearanceOverride.allCases, id: \.self) { mode in
                            pillOption(label(for: mode), mode, selection: $appState.appearanceOverride)
                        }
                    }
                }
            }
        }
    }

    private func label(for mode: AppState.AppearanceOverride) -> String {
        switch mode {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    private func themeCard(_ t: Theme) -> some View {
        let isSelected = t.id == appState.themeID
        return VStack(alignment: .leading, spacing: DT.Spacing.sm) {
            HStack(spacing: 2) {
                swatch(t.colors.background)
                swatch(t.colors.surface)
                swatch(t.colors.textPrimary)
                swatch(t.colors.accent)
            }
            Text(t.name)
                .font(DT.Typography.headline)
                .foregroundStyle(theme.colors.textPrimary)
            Text(description(for: t.id))
                .font(DT.Typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .padding(DT.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected ? theme.colors.accent.opacity(DT.Opacity.selection) : theme.colors.surface,
            in: RoundedRectangle(cornerRadius: DT.Radius.medium)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.medium)
                .stroke(
                    isSelected ? theme.colors.accent : theme.colors.border,
                    lineWidth: isSelected ? 2 : 0.5
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            appState.themeID = t.id
        }
    }

    private func swatch(_ c: Color) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(c)
            .frame(width: 20, height: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(theme.colors.border, lineWidth: 0.5)
            )
    }

    private func description(for id: Theme.ID) -> String {
        switch id {
        case .porty: return "Warm, branded"
        case .osx:   return "Native Apple"
        case .bw:    return "Monochrome"
        }
    }

    // MARK: - Workspace

    private var workspaceSection: some View {
        section("Workspace") {
            VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                Text("Default view mode")
                    .font(DT.Typography.body)
                    .foregroundStyle(theme.colors.textPrimary)
                // Row 1: primary modes mapped to ⌘1..⌘6 + "Last used".
                HStack(spacing: DT.Spacing.xs) {
                    pillOption("Last used", AppState.DefaultViewMode.lastUsed, selection: $appState.defaultViewMode)
                    pillOption("Editor", .editor, selection: $appState.defaultViewMode)
                    pillOption("Preview", .preview, selection: $appState.defaultViewMode)
                    pillOption("Carousel", .carousel, selection: $appState.defaultViewMode)
                }
                // Row 2: split modes (first press of ⌘3/4/5).
                HStack(spacing: DT.Spacing.xs) {
                    pillOption("Editor + Gallery", .splitGallery, selection: $appState.defaultViewMode)
                    pillOption("Editor + List", .splitList, selection: $appState.defaultViewMode)
                    pillOption("Editor + Links", .splitLinks, selection: $appState.defaultViewMode)
                }
                // Row 3: full-width variants (second press of ⌘3/4/5 toggles to these).
                HStack(spacing: DT.Spacing.xs) {
                    pillOption("Gallery", .gallery, selection: $appState.defaultViewMode)
                    pillOption("List", .list, selection: $appState.defaultViewMode)
                    pillOption("Links", .links, selection: $appState.defaultViewMode)
                }
                Text("Which mode opens first when you enter a project.")
                    .font(DT.Typography.caption)
                    .foregroundStyle(theme.colors.textTertiary)
                    .padding(.top, DT.Spacing.xs)
            }
            .padding(.bottom, DT.Spacing.md)

            VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                Text("Project image format")
                    .font(DT.Typography.body)
                    .foregroundStyle(theme.colors.textPrimary)
                HStack(spacing: DT.Spacing.xs) {
                    ForEach(GridAspectRatio.allCases, id: \.self) { ratio in
                        pillOption(ratio.rawValue, ratio, selection: $appState.gridAspectRatio)
                    }
                }
                Text("Aspect ratio used for project images on the overview grid.")
                    .font(DT.Typography.caption)
                    .foregroundStyle(theme.colors.textTertiary)
                    .padding(.top, DT.Spacing.xs)
            }
            .padding(.bottom, DT.Spacing.md)

            VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                HStack {
                    Text("Auto-save delay")
                        .font(DT.Typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                    Spacer()
                    Text(String(format: "%.1fs", appState.autoSaveDelay))
                        .font(DT.Typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .monospacedDigit()
                }
                Slider(value: $appState.autoSaveDelay, in: 0.5...5.0, step: 0.5)
                    .tint(theme.colors.accent)
                Text("How long the editor waits after your last keystroke before saving.")
                    .font(DT.Typography.caption)
                    .foregroundStyle(theme.colors.textTertiary)
                    .padding(.top, DT.Spacing.xs)
            }
            .padding(.bottom, DT.Spacing.md)

            VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                HStack {
                    Text("Grain overlay")
                        .font(DT.Typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                    Spacer()
                    HStack(spacing: DT.Spacing.xs) {
                        pillOption("Off", false, selection: $appState.grainEnabled)
                        pillOption("On", true, selection: $appState.grainEnabled)
                    }
                }
                if appState.grainEnabled {
                    HStack(spacing: DT.Spacing.sm) {
                        Slider(
                            value: Binding(
                                get: { appState.grainOpacityOverride ?? theme.grainOpacity },
                                set: { appState.grainOpacityOverride = $0 }
                            ),
                            in: 0.0...0.10,
                            step: 0.01
                        )
                        .tint(theme.colors.accent)
                        pillButton("Reset") {
                            appState.grainOpacityOverride = nil
                        }
                    }
                }
                Text("Subtle film-grain texture over the window.")
                    .font(DT.Typography.caption)
                    .foregroundStyle(theme.colors.textTertiary)
                    .padding(.top, DT.Spacing.xs)
            }

            VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                Text("New project template")
                    .font(DT.Typography.body)
                    .foregroundStyle(theme.colors.textPrimary)

                TextEditor(text: $appState.newProjectTemplate)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.colors.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(DT.Spacing.sm)
                    .background(theme.colors.surface)
                    .frame(minHeight: 220)
                    .overlay(
                        RoundedRectangle(cornerRadius: DT.Radius.small)
                            .stroke(theme.colors.border, lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DT.Radius.small))

                Text("Available: {{title}} {{year}} {{client}} {{tags}} {{date}}")
                    .font(DT.Typography.monoSmall)
                    .foregroundStyle(theme.colors.textTertiary)

                HStack(alignment: .top) {
                    Text("Used as the body of every new project. Frontmatter is set in the New Project sheet.")
                        .font(DT.Typography.caption)
                        .foregroundStyle(theme.colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    pillButton("Reset default") {
                        appState.newProjectTemplate = AppState.defaultNewProjectTemplate
                    }
                }
                .padding(.top, DT.Spacing.xs)
            }
        }
    }

    // MARK: - Settings controls (custom pill-style language)

    /// Selection pill used in segmented-style pickers. Selected = accent-tinted
    /// bg + accent border + accent text; idle = surface + soft border + secondary text.
    private func pillOption<T: Equatable>(_ label: String, _ value: T, selection: Binding<T>) -> some View {
        let isSelected = selection.wrappedValue == value
        return Button {
            selection.wrappedValue = value
        } label: {
            Text(label)
                .font(DT.Typography.caption)
                .foregroundStyle(isSelected ? theme.colors.accent : theme.colors.textSecondary)
                .padding(.horizontal, DT.Spacing.md)
                .padding(.vertical, DT.Spacing.xs)
                .background(
                    isSelected ? theme.colors.accent.opacity(DT.Opacity.selection) : theme.colors.surface,
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(
                        isSelected ? theme.colors.accent : theme.colors.border.opacity(DT.Opacity.muted),
                        lineWidth: isSelected ? 1 : 0.5
                    )
                )
        }
        .buttonStyle(.plain)
    }

    /// Secondary action pill (like "Reset", "Change…"). Plain, muted — no selection state.
    private func pillButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(DT.Typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .padding(.horizontal, DT.Spacing.md)
                .padding(.vertical, DT.Spacing.xs)
                .background(theme.colors.surface, in: Capsule())
                .overlay(Capsule().stroke(theme.colors.border.opacity(DT.Opacity.muted), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Portfolio

    private var portfolioSection: some View {
        section("Portfolio") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Portfolio folder")
                        .font(DT.Typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(appState.portfolioRootURL?.path ?? "—")
                        .font(DT.Typography.monoSmall)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                pillButton("Change…") {
                    pickPortfolioFolder()
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hide projects marked hidden")
                        .font(DT.Typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text("Persists across launches. Same toggle as the eye icon on the overview.")
                        .font(DT.Typography.caption)
                        .foregroundStyle(theme.colors.textTertiary)
                }
                Spacer()
                HStack(spacing: DT.Spacing.xs) {
                    pillOption("Off", false, selection: $appState.hideHiddenProjects)
                    pillOption("On", true, selection: $appState.hideHiddenProjects)
                }
            }
        }
    }

    private func pickPortfolioFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select your portfolio folder"
        panel.prompt = "Use This Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        appState.setRoot(url)
    }

    // MARK: - Getting started (manual)

    private var gettingStartedSection: some View {
        section("Getting Started") {
            featureRow(
                icon: "folder",
                title: "Each project is a folder with a markdown file",
                description: "Folders are named year_slug_uid. The markdown file inside (same name as the folder, .md) holds your project body plus YAML frontmatter for title, year, client, status, tags, teaser, favorites, and hidden."
            )
            featureRow(
                icon: "photo.on.rectangle",
                title: "Drop in files",
                description: "Images, video, audio, PDFs — anything. They live next to the markdown inside the project folder."
            )
            featureRow(
                icon: "link",
                title: "Add links with previews",
                description: "Each link becomes a small markdown file in the project folder. Switch to the Links pane to browse them."
            )
            featureRow(
                icon: "square.and.pencil",
                title: "Edit the markdown",
                description: "Use the Editor to describe the work. Auto-saves after 1.5 seconds of inactivity by default."
            )
            featureRow(
                icon: "star.fill",
                title: "Mark favorites",
                description: "Press L on a media file to favorite it. Favorites populate the Carousel and the project teaser."
            )
            featureRow(
                icon: "doc.text.magnifyingglass",
                title: "Filesystem is canonical",
                description: "PortyMcFolio reads and writes plain folders and files; the database is just a search and metadata cache. Move or back up your portfolio with anything that handles folders."
            )
        }
    }

    // MARK: - Importing content (manual)

    private var importingContentSection: some View {
        section("Importing Content") {
            featureRow(
                icon: "arrow.down.doc",
                title: "Drag from Finder",
                description: "Drop files onto the editor, gallery, or the project folder itself. Files are copied into the project folder and (when dropped on the editor) auto-embedded with ![[filename]]."
            )
            featureRow(
                icon: "doc.on.clipboard",
                title: "Paste from clipboard",
                description: "Files paste in as files. Images paste in as pasted-{timestamp}.png. Plain-text URLs paste as link cards on the gallery / links pane."
            )
            featureRow(
                icon: "chevron.left.forwardslash.chevron.right",
                title: "Embed syntax",
                description: "![[filename]] embeds an image, video, audio file, or link card. Works for files in the project folder or any subfolder (use the relative path: ![[subfolder/image.jpg]])."
            )
            featureRow(
                icon: "arrow.triangle.2.circlepath",
                title: "Renames stay in sync",
                description: "Rename a file inside the app and any ![[…]] embeds in the body, the teaser, and the favorites list update automatically."
            )
        }
    }

    // MARK: - View Modes (existing help content)

    private var viewModesSection: some View {
        section("View Modes") {
            featureRow(
                icon: "doc.text",
                title: "Editor",
                description: "Write and edit your project markdown file. Auto-saves after 1.5 seconds of inactivity."
            )
            featureRow(
                icon: "eye",
                title: "Preview",
                description: "Rendered markdown with embedded media, link cards, and file badges. Export to HTML from here."
            )
            featureRow(
                icon: "rectangle.split.2x1",
                title: "Split (Editor + Gallery / List / Links)",
                description: "Editor on the left, chosen secondary pane on the right. Drag the divider to resize, double-click to reset. Press \u{2318}3 / \u{2318}4 / \u{2318}5 again to toggle to the full-width variant of the same pane."
            )
            featureRow(
                icon: "square.grid.2x2",
                title: "Gallery / List / Links",
                description: "Grid of media files, table with file metadata, or saved-URL cards. Each is the full-width variant of the matching split mode \u{2014} press \u{2318}3 / \u{2318}4 / \u{2318}5 once for split, again for full."
            )
            featureRow(
                icon: "rectangle.stack.badge.play",
                title: "Carousel",
                description: "Full-screen slideshow of hearted media. Press \u{2190} / \u{2192} to navigate."
            )
        }
    }

    // MARK: - Editor (existing help content)

    private var editorSection: some View {
        section("Editor") {
            featureRow(
                icon: "photo",
                title: "Embeds",
                description: "Type ![[filename]] to embed images, videos, audio, or link cards. Drag files from Finder or the gallery to auto-insert."
            )
            featureRow(
                icon: "list.bullet",
                title: "Smart Lists",
                description: "Press Enter to continue bullet or numbered lists. Empty items exit the list. Numbering auto-increments."
            )
            featureRow(
                icon: "doc.on.clipboard",
                title: "Paste",
                description: "Paste files or images from the clipboard to embed them. Screenshots become pasted-{timestamp}.png in the project folder."
            )
            featureRow(
                icon: "link",
                title: "URL Paste",
                description: "Paste a URL into the editor or the Links pane to save it as a link card automatically."
            )
        }
    }

    // MARK: - Gallery (existing help content)

    private var gallerySection: some View {
        section("Gallery & Files") {
            featureRow(
                icon: "folder.badge.plus",
                title: "File Management",
                description: "Add files, create folders, drag to rearrange. Cut and paste files between folders. Right-click for more actions."
            )
            featureRow(
                icon: "checklist",
                title: "Multi-Select",
                description: "\u{2318}-click to toggle, \u{21E7}-click for a range, \u{2318}A for all visible. Drag any selected item to move the whole set into a folder or into the editor (one embed per file)."
            )
            featureRow(
                icon: "trash",
                title: "Batch Delete",
                description: "Select files and/or folders, press \u{2318}\u{232B} to move them to the Trash after a single confirmation."
            )
            featureRow(
                icon: "heart",
                title: "Bulk Favorite",
                description: "Select media files and press L to toggle them into (or out of) the Carousel. Uses a majority rule: if all are already favorited, it unfavorites them all."
            )
            featureRow(
                icon: "link",
                title: "Links",
                description: "Save URLs with titles and notes. Stored as markdown files in your project folder. Switch to the Links view to browse."
            )
            featureRow(
                icon: "sparkles",
                title: "Cleanup",
                description: "Step through files one by one. Rename them with the project naming convention (year_slug_description.ext), move to folders, or delete. Navigate with \u{2318}\u{2190}/\u{2192}."
            )
        }
    }

    // MARK: - Carousel (help content)

    private var carouselSection: some View {
        section("Carousel") {
            featureRow(
                icon: "heart.fill",
                title: "Hearted Media",
                description: "Files you heart (click the heart on a grid or list row, or press L on a selection) appear in the Carousel. Great for an ordered, distraction-free slideshow."
            )
            featureRow(
                icon: "arrow.up.arrow.down",
                title: "Reorder",
                description: "Open the reorder sheet from the bar icon to drag favorites into the order you want them to play."
            )
            featureRow(
                icon: "doc.on.doc",
                title: "Copy File",
                description: "Click the copy icon in the bottom bar to put the current file on the clipboard. Paste in Finder to duplicate the file elsewhere."
            )
            featureRow(
                icon: "pencil",
                title: "Rename",
                description: "Double-click the filename in the bottom bar to rename it. Enforces the project's year_slug_description.ext convention, and rewrites README embeds, teaser, and favorites automatically."
            )
        }
    }

    // MARK: - Search (existing help content)

    private var searchSection: some View {
        section("Search & Commands") {
            featureRow(
                icon: "magnifyingglass",
                title: "Search",
                description: "Press \u{2318}K to open the palette. Searches projects, files, links, and tags. Project metadata (title, client, tags, status, folder name) is always matched in full; full-text matches across body + file + link content are unioned on top."
            )
            featureRow(
                icon: "command",
                title: "Commands",
                description: "The same palette runs commands: New Project, Guide, and Re-index portfolio. Re-index rebuilds the search database from disk \u{2014} the only way to recover from a corrupted FTS index."
            )
            featureRow(
                icon: "arrow.up.arrow.down",
                title: "Keyboard",
                description: "Arrow keys navigate results, Enter opens, Esc closes. Type partial words; matches are prefix-aware."
            )
        }
    }

    // MARK: - Project metadata (manual)

    private var projectMetadataSection: some View {
        section("Project Metadata") {
            featureRow(
                icon: "textformat",
                title: "Title",
                description: "The display name of the project. Editable from the project settings popover (\u{2318}9)."
            )
            featureRow(
                icon: "calendar",
                title: "When",
                description: "A year, or a date range. The folder year is derived from this — moving a project's When across years renames its folder automatically."
            )
            featureRow(
                icon: "person.2",
                title: "Client",
                description: "One name, or a comma-separated list. Used as a clickable filter on the overview and shown beneath each project's title."
            )
            featureRow(
                icon: "circle.dashed",
                title: "Status",
                description: "One of three states — empty, in-progress, or archived — shown as a small badge on the table view. See Status Types below."
            )
            featureRow(
                icon: "tag",
                title: "Tags",
                description: "Free-form. Searchable from \u{2318}K. The overview's editorial hover overlay surfaces them as clickable pills."
            )
            featureRow(
                icon: "heart",
                title: "Favorites",
                description: "Per-project list of media filenames. Drives the Carousel order. Press L on a gallery item to toggle."
            )
            featureRow(
                icon: "photo",
                title: "Teaser",
                description: "One image filename used as the project card thumbnail on the overview grid. Set from the project settings popover or via the gallery's right-click menu."
            )
            featureRow(
                icon: "eye.slash",
                title: "Hidden",
                description: "Marks a project hidden. The overview's eye-icon toggle (or the Portfolio preference) filters all hidden projects out — useful for presenting your portfolio without works-in-progress."
            )

            VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                Text("STATUS TYPES")
                    .font(DT.Typography.micro)
                    .foregroundStyle(theme.colors.textTertiary)
                    .tracking(1)

                HStack(spacing: DT.Spacing.md) {
                    ForEach([ProjectStatus.empty, .inProgress, .archived], id: \.self) { s in
                        StatusBadgeView(status: s)
                    }
                }
            }
            .padding(.top, DT.Spacing.xs)
        }
    }

    // MARK: - Themes (manual)

    private var themesSection: some View {
        section("Themes") {
            featureRow(
                icon: "paintpalette",
                title: "Porty",
                description: "Warm, branded palette with the mauve accent. The default."
            )
            featureRow(
                icon: "macwindow",
                title: "OSX",
                description: "Warm Apple greys with the same mauve accent. Calmer, more familiar neutrals."
            )
            featureRow(
                icon: "circle.lefthalf.filled",
                title: "BW",
                description: "Monochrome — pure black, white, and grey. Lets the work do the talking."
            )
            featureRow(
                icon: "sun.max",
                title: "Light / Dark / System",
                description: "Independent of theme. System follows your OS appearance; Light or Dark force the chosen mode app-wide."
            )
        }
    }

    // MARK: - Shortcuts (existing help content)

    private var shortcutsSection: some View {
        section("Keyboard Shortcuts") {
            subsection("Global") {
                shortcutRow("Search & Commands", "\u{2318}K")
                shortcutRow("New Project", "\u{2318}N")
                shortcutRow("Back to Projects", "\u{238B}")
            }

            subsection("Project Overview") {
                shortcutRow("Navigate Cards / Rows", "\u{2190}\u{2191}\u{2193}\u{2192}")
                shortcutRow("Open Selected", "\u{21A9}")
                shortcutRow("Project Settings (hovered/selected)", "\u{2318}9")
                shortcutRow("Toggle Grid / Table", "\u{2318}1 / \u{2318}2")
            }

            subsection("View Modes (in a project)") {
                shortcutRow("Editor", "\u{2318}1")
                shortcutRow("Preview", "\u{2318}2")
                shortcutRow("Gallery (toggles split / full)", "\u{2318}3")
                shortcutRow("List (toggles split / full)", "\u{2318}4")
                shortcutRow("Links (toggles split / full)", "\u{2318}5")
                shortcutRow("Carousel", "\u{2318}6")
                shortcutRow("Project Settings", "\u{2318}9")
            }

            subsection("Editor") {
                shortcutRow("Bold", "\u{2318}B")
                shortcutRow("Italic", "\u{2318}I")
                shortcutRow("Strikethrough", "\u{2318}\u{21E7}S")
                shortcutRow("Inline Code", "\u{2318}E")
                shortcutRow("Heading 1 / 2 / 3", "\u{2318}\u{2325}1\u{2013}3")
                shortcutRow("Insert Link", "\u{2318}\u{21E7}K")
                shortcutRow("Find", "\u{2318}F")
            }

            subsection("Gallery") {
                shortcutRow("Quick Look", "\u{2423}")
                shortcutRow("Navigate Files", "\u{2190}\u{2191}\u{2193}\u{2192}")
                shortcutRow("First / Last", "\u{2318}\u{2191} / \u{2318}\u{2193}")
                shortcutRow("Select All Visible", "\u{2318}A")
                shortcutRow("Toggle Selection", "\u{2318}-click")
                shortcutRow("Range Select", "\u{21E7}-click  /  \u{21E7}\u{2190}\u{2191}\u{2193}\u{2192}")
                shortcutRow("Move to Trash", "\u{2318}\u{232B}")
                shortcutRow("Toggle Favorite", "L")
                shortcutRow("Cut File", "\u{2318}X")
                shortcutRow("Paste File", "\u{2318}V")
                shortcutRow("Go Up a Folder", "\u{2318}[")
            }

            subsection("Carousel") {
                shortcutRow("Previous / Next Slide", "\u{2190} / \u{2192}")
                shortcutRow("Rename Current File", "double-click filename")
                shortcutRow("Copy File to Clipboard", "click copy icon")
            }
        }
    }

    // MARK: - Updates

    private var updatesSection: some View {
        section("Updates") {
            VStack(alignment: .leading, spacing: DT.Spacing.md) {
                Text("Porty McFolio checks for updates daily by default. Updates are downloaded only after you confirm. No usage data, system information, or telemetry is sent during update checks — only a request to fetch the public release feed.")
                    .font(DT.Typography.body)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(isOn: Binding(
                    get: { updateController.automaticallyChecksForUpdates },
                    set: { updateController.automaticallyChecksForUpdates = $0 }
                )) {
                    Text("Automatically check for updates")
                        .font(DT.Typography.body)
                }
                .toggleStyle(.switch)

                HStack(spacing: DT.Spacing.lg) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current version")
                            .font(DT.Typography.caption)
                            .foregroundStyle(theme.colors.textTertiary)
                        Text(updateController.currentVersion)
                            .font(DT.Typography.body.monospacedDigit())
                            .foregroundStyle(theme.colors.textPrimary)
                    }
                    if let last = updateController.lastCheckedAt {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Last checked")
                                .font(DT.Typography.caption)
                                .foregroundStyle(theme.colors.textTertiary)
                            Text(last, format: .relative(presentation: .named))
                                .font(DT.Typography.body)
                                .foregroundStyle(theme.colors.textPrimary)
                        }
                    }
                }

                pillButton("Check for Updates Now") {
                    updateController.checkNow()
                }
                .disabled(!updateController.canCheckForUpdates)
            }
        }
    }

    // MARK: - Helpers

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DT.Spacing.lg) {
            Text(title)
                .font(DT.Typography.title)
                .foregroundStyle(theme.colors.textPrimary)

            content()
        }
    }

    private func subsection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DT.Spacing.xs) {
            Text(title.uppercased())
                .font(DT.Typography.micro)
                .foregroundStyle(theme.colors.textTertiary)
                .tracking(1)
                .padding(.bottom, DT.Spacing.xs)

            content()
        }
        .padding(.bottom, DT.Spacing.sm)
    }

    private func shortcutRow(_ label: String, _ keys: String) -> some View {
        HStack {
            Text(label)
                .font(DT.Typography.body)
                .foregroundStyle(theme.colors.textSecondary)
            Spacer()
            Text(keys)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.horizontal, DT.Spacing.sm)
                .padding(.vertical, 3)
                .background(theme.colors.backgroundAlt, in: RoundedRectangle(cornerRadius: DT.Radius.small))
        }
        .padding(.vertical, 2)
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: DT.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.textTertiary)
                .frame(width: 24, height: 20, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DT.Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(description)
                    .font(DT.Typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loadLogo() -> NSImage? {
        let name = colorScheme == .dark ? "logo-dark" : "logo-light"
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg") else { return nil }
        return NSImage(contentsOf: url)
    }
}
