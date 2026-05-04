import Foundation

enum CSVExporter {

    /// RFC 4180 escape: wrap in `"…"` only if the field contains `,`, `"`,
    /// CR, or LF. Internal `"` is doubled. Empty input stays empty (not `""`).
    static func escape(_ field: String) -> String {
        if field.isEmpty { return "" }
        let needsQuoting = field.contains(",")
            || field.contains("\"")
            || field.contains("\n")
            || field.contains("\r")
        guard needsQuoting else { return field }
        let doubled = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(doubled)\""
    }

    /// Build the full CSV document for the given projects, in the order provided.
    /// Output is UTF-8 with a BOM prefix, CRLF line endings, and a trailing CRLF
    /// after the last row (header-only when `projects` is empty).
    static func csv(for projects: [Project]) -> String {
        let bom = "\u{FEFF}"
        let header = "Year,Title,Client,Status,Tags"

        var out = bom + header + "\r\n"
        for project in projects {
            let cells = [
                String(project.year),
                escape(project.title),
                escape(project.client),
                escape(project.status.displayName),
                escape(project.tags.joined(separator: "; ")),
            ]
            out += cells.joined(separator: ",") + "\r\n"
        }
        return out
    }
}
