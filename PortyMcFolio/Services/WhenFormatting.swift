import Foundation

/// Pure formatting for the project When summary used by the editorial card
/// hover overlay. Output is locale-aware (defaults to en_US_POSIX), uppercase,
/// and uses em-dashes for ranges to match the editorial typographic voice.
enum WhenFormatting {

    /// Produce the human-readable summary string for a project's When.
    /// Year is the canonical (folder) year — only used when `dateEnd == nil`.
    static func summaryString(
        date: Date,
        dateEnd: Date?,
        year: Int,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> String {
        guard dateEnd != nil else {
            return String(year)
        }
        return monthSummary(date: date, dateEnd: dateEnd, locale: locale)
    }

    private static func monthSummary(date: Date, dateEnd: Date?, locale: Locale) -> String {
        let cal = utcGregorian(locale: locale)
        let startMonth = cal.component(.month, from: date)
        let startYear = cal.component(.year, from: date)
        let startStr = monthAbbrev(month: startMonth, locale: locale).uppercased()

        guard let end = dateEnd else {
            return "\(startStr) \(startYear)"
        }

        let endMonth = cal.component(.month, from: end)
        let endYear = cal.component(.year, from: end)
        let endStr = monthAbbrev(month: endMonth, locale: locale).uppercased()

        if startYear == endYear {
            if startMonth == endMonth {
                return "\(startStr) \(startYear)"
            }
            return "\(startStr) — \(endStr) \(startYear)"
        }
        return "\(startStr) \(startYear) — \(endStr) \(endYear)"
    }

    // MARK: - Helpers

    private static func utcGregorian(locale: Locale) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.locale = locale
        return cal
    }

    private static func monthAbbrev(month: Int, locale: Locale) -> String {
        let df = DateFormatter()
        df.locale = locale
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "MMM"
        var comps = DateComponents()
        comps.year = 2000
        comps.month = month
        comps.day = 1
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: comps)!
        return df.string(from: date)
    }
}
