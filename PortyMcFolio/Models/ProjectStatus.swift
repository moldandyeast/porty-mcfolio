import Foundation

enum ProjectStatus: String, Codable, CaseIterable, Identifiable, Comparable {
    case empty
    case inProgress
    case archived

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .empty: "Empty"
        case .inProgress: "In Progress"
        case .archived: "Archived"
        }
    }

    private var sortIndex: Int {
        switch self {
        case .empty: 0
        case .inProgress: 1
        case .archived: 2
        }
    }

    static func < (lhs: ProjectStatus, rhs: ProjectStatus) -> Bool {
        lhs.sortIndex < rhs.sortIndex
    }

    /// Map legacy status strings from existing frontmatter
    static func from(_ raw: String) -> ProjectStatus {
        switch raw.lowercased() {
        case "empty": .empty
        case "inprogress", "in progress", "active": .inProgress
        case "archived", "complete": .archived
        case "draft": .empty
        default: .empty
        }
    }
}
