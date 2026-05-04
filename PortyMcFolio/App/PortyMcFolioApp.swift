import SwiftUI

@main
struct PortyMcFolioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environment(\.theme, appState.theme)
                .tint(appState.theme.colors.accent)
                // Manual light/dark override: follows system when
                // appearanceOverride == .system, otherwise forces the chosen
                // appearance across SwiftUI. AppKit side is kept in sync via
                // NSApp.appearance in AppState.appearanceOverride.didSet.
                .preferredColorScheme(appState.appearanceOverride.colorScheme)
                .onAppear {
                    NSApp.appearance = appState.appearanceOverride.nsAppearance
                    configureWindow()
                    addWindowGrain()
                    appState.startAppearanceObservers()
                }
                .onChange(of: appState.theme) { _, _ in
                    configureWindow()
                    updateGrainOpacity()
                }
                .onChange(of: appState.effectiveGrainOpacity) { _, _ in
                    updateGrainOpacity()
                }
                .onChange(of: appState.appearanceOverride) { _, _ in
                    configureWindow()
                }
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Project") { appState.isShowingNewProject = true }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(replacing: .sidebar) {
                // ⌘1 and ⌘2 are context-aware: on the project overview they
                // toggle the grid/table list mode; inside a project they
                // switch to editor/preview.
                let onOverview = appState.selectedProject == nil

                Button(onOverview ? "Grid" : "Editor") {
                    appState.handlePrimaryShortcut()
                }
                .keyboardShortcut("1", modifiers: .command)

                Button(onOverview ? "Table" : "Preview") {
                    appState.handleSecondaryShortcut()
                }
                .keyboardShortcut("2", modifiers: .command)

                // ⌘3–⌘6 and ⌘9 only make sense inside a project.
                Button("Editor + Gallery") { appState.viewMode = .splitGallery }
                    .keyboardShortcut("3", modifiers: .command)
                    .disabled(onOverview)

                Button("Gallery") { appState.viewMode = .gallery }
                    .keyboardShortcut("3", modifiers: [.command, .shift])
                    .disabled(onOverview)

                Button("Editor + List") { appState.viewMode = .splitList }
                    .keyboardShortcut("4", modifiers: .command)
                    .disabled(onOverview)

                Button("List") { appState.viewMode = .list }
                    .keyboardShortcut("4", modifiers: [.command, .shift])
                    .disabled(onOverview)

                Button("Editor + Links") { appState.viewMode = .splitLinks }
                    .keyboardShortcut("5", modifiers: .command)
                    .disabled(onOverview)

                Button("Links") { appState.viewMode = .links }
                    .keyboardShortcut("5", modifiers: [.command, .shift])
                    .disabled(onOverview)

                Button("Carousel") { appState.viewMode = .carousel }
                    .keyboardShortcut("6", modifiers: .command)
                    .disabled(onOverview)

                Divider()

                // ⌘9 works in both contexts: on detail it opens the active
                // project's settings; on overview it opens settings for the
                // project under the keyboard-selected or hovered card.
                Button("Project Settings") { appState.isShowingProjectSettings = true }
                    .keyboardShortcut("9", modifiers: .command)
            }
        }
    }

    private func configureWindow() {
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                window.titlebarAppearsTransparent = true
                window.backgroundColor = NSColor(appState.theme.colors.background)
                window.titlebarSeparatorStyle = .none
            }
            UserDefaults.standard.set("WhenScrolling", forKey: "AppleShowScrollBars")
        }
    }

    /// The grain is an AppKit layer on the window's contentView so it covers
    /// both the SwiftUI content AND the toolbar area.
    private func addWindowGrain() {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first,
                  let contentView = window.contentView else { return }

            contentView.subviews.compactMap { $0 as? GrainNSView }.forEach { $0.removeFromSuperview() }

            let grainView = GrainNSView(opacity: appState.effectiveGrainOpacity)
            grainView.frame = contentView.bounds
            grainView.autoresizingMask = [.width, .height]
            contentView.addSubview(grainView)
        }
    }

    private func updateGrainOpacity() {
        if let window = NSApplication.shared.windows.first,
           let grain = window.contentView?.subviews.compactMap({ $0 as? GrainNSView }).first {
            grain.updateOpacity(appState.effectiveGrainOpacity)
        }
    }
}

/// Disables macOS's automatic window tabbing completely. The class-level
/// flag has to be set in `applicationWillFinishLaunching` — before SwiftUI
/// creates any NSWindow — or the first window can still be added to a tab
/// group. We also scrub any persisted `NSWindowTabbingShoudShowTabBarKey-*`
/// pref written by a prior build, which is what revived the tab bar after
/// an earlier in-body fix attempt. An observer forces `.disallowed` on any
/// window that becomes key later.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        scrubPersistedTabBarKeys()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        for window in NSApp.windows {
            window.tabbingMode = .disallowed
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { note in
            (note.object as? NSWindow)?.tabbingMode = .disallowed
        }
    }

    private func scrubPersistedTabBarKeys() {
        let defaults = UserDefaults.standard
        let prefix = "NSWindowTabbingShoudShowTabBarKey-"
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
