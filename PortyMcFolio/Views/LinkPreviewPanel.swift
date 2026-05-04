import AppKit
import WebKit

/// A Quick Look-style floating panel that previews a URL in a WebView.
/// Used from the gallery to preview links without opening Safari.
final class LinkPreviewPanel: NSObject {
    static let shared = LinkPreviewPanel()

    private var panel: NSPanel?
    private var webView: WKWebView?

    func preview(url: URL, title: String = "") {
        if let existing = panel, existing.isVisible {
            // Reuse existing panel — just load new URL
            webView?.load(URLRequest(url: url))
            existing.title = title.isEmpty ? url.host ?? url.absoluteString : title
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.load(URLRequest(url: url))

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.titlebarAppearsTransparent = false
        p.title = title.isEmpty ? url.host ?? url.absoluteString : title
        p.isMovableByWindowBackground = true
        p.contentView = wv
        p.center()
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.level = .floating
        p.makeKeyAndOrderFront(nil)

        self.panel = p
        self.webView = wv
    }

    func close() {
        panel?.close()
        panel = nil
        webView = nil
    }
}
