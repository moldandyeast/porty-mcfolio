import Foundation
import LinkPresentation

/// Fetches a web page's title for use as a link's display name.
/// Wraps `LPMetadataProvider` with a hard timeout so a hanging site doesn't
/// block the calling task indefinitely.
enum LinkTitleFetcher {
    /// Fetches the page title for `url`. Returns `nil` if the fetch fails,
    /// times out, or the fetched metadata has no usable title.
    static func fetch(url: URL, timeout: TimeInterval = 5) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                await fetchWithProvider(url: url)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }

            // Return the first result — fetch success, fetch failure, or timeout.
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func fetchWithProvider(url: URL) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let provider = LPMetadataProvider()
            provider.startFetchingMetadata(for: url) { metadata, _ in
                let title = metadata?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let title, !title.isEmpty {
                    continuation.resume(returning: title)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
