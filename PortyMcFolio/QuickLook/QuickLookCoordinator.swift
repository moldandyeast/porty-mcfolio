import AppKit
import Quartz

/// Minimal QuickLook coordinator kept for potential future use.
/// The gallery now uses SwiftUI's .quickLookPreview() modifier directly.
final class QuickLookCoordinator: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLookCoordinator()
    private var previewURL: URL?

    func preview(url: URL) {
        previewURL = url
        if let panel = QLPreviewPanel.shared() {
            panel.dataSource = self
            if panel.isVisible { panel.reloadData() }
            else { panel.makeKeyAndOrderFront(nil) }
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL != nil ? 1 : 0
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewURL as? NSURL
    }
}
