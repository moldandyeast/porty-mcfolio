import Foundation

/// Pure helpers used by `AppState.updateProjectMetadata` to keep the
/// frontmatter consistent on metadata changes.
enum ProjectMetadataMutation {

    /// Derives the canonical folder year from a `WhenValue`.
    ///
    /// - Year-only (`dateEnd == nil`): uses the user-picked `yearOnlyYear` if
    ///   present, otherwise falls back to the supplied `currentYear` (legacy
    ///   data without a year-only year set).
    /// - Range (`dateEnd != nil`): uses the year of `dateEnd`.
    static func resolveFolderYear(
        when: WhenValue,
        currentYear: Int,
        calendar: Calendar = utcGregorian()
    ) -> Int {
        if let end = when.dateEnd {
            return calendar.component(.year, from: end)
        }
        return when.yearOnlyYear ?? currentYear
    }

    private static func utcGregorian() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }
}
