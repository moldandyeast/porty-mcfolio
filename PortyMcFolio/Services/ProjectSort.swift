import Foundation

/// Pure helpers that order projects within a single year band.
///
/// The grid groups projects by `Project.year` (folder year). Within each band,
/// we sort by an "effective sort date" so projects with explicit Whens land
/// in chronological order (newest first) and year-only projects collapse to
/// Jan 1 — pushing them past everything dated, where they tie-break on title.
enum ProjectSort {

    /// Returns the date used to order a project within its band.
    /// Year-only projects collapse to Jan 1 of the folder year so legacy
    /// `date:` noise (e.g. an old project with `date: 2026-...` due to
    /// the parser default) cannot influence ordering.
    static func effectiveSortDate(for project: Project) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        if let end = project.dateEnd {
            return end
        }
        return calendar.date(from: DateComponents(year: project.year, month: 1, day: 1))
            ?? project.date
    }

    /// Orders projects within a year band.
    /// Explicit Whens descend (most recent start first); year-only projects
    /// land at the end and tie-break alphabetically by title.
    static func sortedWithinYear(_ projects: [Project]) -> [Project] {
        projects.sorted { a, b in
            let aDate = effectiveSortDate(for: a)
            let bDate = effectiveSortDate(for: b)
            if aDate != bDate {
                return aDate > bDate
            }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }
}
