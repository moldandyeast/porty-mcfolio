import Foundation

enum SearchResultType: String, CaseIterable {
    case command
    case project
    case file
    case link
    case tag

    var sectionTitle: String {
        switch self {
        case .command: "COMMANDS"
        case .project: "PROJECTS"
        case .file: "FILES"
        case .link: "LINKS"
        case .tag: "TAGS"
        }
    }
}

struct SearchResult: Identifiable, Equatable {
    let id: String
    let type: SearchResultType
    let entityID: String
    let parentUID: String
    let primaryText: String
    let secondaryText: String
}

struct SearchCommand: Identifiable {
    let id: String
    let name: String
    let icon: String
    let shortcut: String?
    let action: @MainActor (AppState) -> Void

    static let allCommands: [SearchCommand] = [
        SearchCommand(
            id: "cmd-new-project",
            name: "New Project",
            icon: "plus.rectangle",
            shortcut: "Cmd+N"
        ) { state in
            state.isShowingNewProject = true
        },
        SearchCommand(
            id: "cmd-guide",
            name: "Guide",
            icon: "questionmark.circle",
            shortcut: nil
        ) { state in
            state.isShowingSettings = true
        },
        SearchCommand(
            id: "cmd-reindex",
            name: "Re-index portfolio",
            icon: "arrow.clockwise",
            shortcut: nil
        ) { state in
            state.reindexEverything()
        }
    ]

    static func matching(_ query: String) -> [SearchCommand] {
        guard !query.isEmpty else { return allCommands }
        let q = query.lowercased()
        return allCommands.filter { $0.name.lowercased().contains(q) }
    }
}
