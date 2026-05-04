import Foundation

enum ProjectTemplate {

    static func render(
        _ template: String,
        title: String,
        year: Int,
        client: String,
        tags: [String],
        date: Date
    ) -> String {
        var out = template
        out = out.replacingOccurrences(of: "{{title}}",  with: title)
        out = out.replacingOccurrences(of: "{{year}}",   with: String(year))
        out = out.replacingOccurrences(of: "{{client}}", with: client)
        out = out.replacingOccurrences(of: "{{tags}}",   with: tags.joined(separator: ", "))
        out = out.replacingOccurrences(of: "{{date}}",   with: Self.isoDate(date))
        return out
    }

    private static func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
