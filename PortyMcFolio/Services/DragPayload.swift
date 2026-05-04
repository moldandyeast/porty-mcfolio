// PortyMcFolio/Services/DragPayload.swift
import Foundation
import UniformTypeIdentifiers

enum DragPayload {
    /// Custom pasteboard type used for internal multi-file drags. External
    /// consumers (Finder, other apps) ignore this and use the primary
    /// public.file-url entry instead.
    static let typeIdentifier = "com.portymcfolio.drag.urllist"

    enum Error: Swift.Error { case malformed }

    static func encode(urls: [URL]) throws -> Data {
        let strings = urls.map(\.absoluteString)
        return try JSONEncoder().encode(strings)
    }

    static func decode(data: Data) throws -> [URL] {
        let strings = try JSONDecoder().decode([String].self, from: data)
        let urls = strings.compactMap { URL(string: $0) }
        guard urls.count == strings.count else { throw Error.malformed }
        return urls
    }
}

/// In-process multi-drag handoff. SwiftUI's `.onDrag` returns a single
/// `NSItemProvider`, and custom-UTI data representations registered on it
/// don't reliably round-trip across the SwiftUI→AppKit drag pasteboard
/// when the UTI isn't declared in Info.plist. Since every multi-drag in
/// this app stays inside the app, we stash the full URL list here on drag
/// start and consume it on drop — pasteboard carries only the primary URL
/// for external receivers.
///
/// Set on drag start. Consumed once by the drop handler that matches,
/// then cleared. A subsequent drag always overwrites (so a cancelled drag
/// leaving stale state gets corrected by the next drag).
@MainActor
enum MultiDragSession {
    static var active: [URL]?
}
