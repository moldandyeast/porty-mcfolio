import SwiftUI
import WebKit

struct MarkdownPreviewView: NSViewRepresentable {
    let markdown: String
    let projectFolderURL: URL
    var onExportRequest: (() -> Void)?
    var theme: Theme = .porty
    var appearanceSignal: Int = 0

    /// Compiled once — matches `![[filename]]` embed tokens.
    private static let embedRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"!\[\[([^\]]+)\]\]"#)
    }()

    /// Cache of parsed link metadata, keyed by the link file's absolute path.
    /// Invalidated via file mtime to pick up user edits through EditLinkSheet
    /// or external edits. Avoids synchronous disk reads on every render of a
    /// preview that contains `![[link-{uid}.md]]` embeds.
    private static let linkCardCache = NSCache<NSString, LinkCardCacheEntry>()

    private final class LinkCardCacheEntry {
        let link: LinkItem
        let mtime: Date
        init(link: LinkItem, mtime: Date) {
            self.link = link
            self.mtime = mtime
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let handler = PreviewSchemeHandler()
        handler.projectFolderURL = projectFolderURL
        config.setURLSchemeHandler(handler, forURLScheme: "portymcfolio")
        config.userContentController.add(context.coordinator, name: "openFile")
        context.coordinator.schemeHandler = handler
        context.coordinator.projectFolderURL = projectFolderURL

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        // Inject theme CSS variables once the document has loaded, replacing
        // the fallback :root block in preview.html with the active theme's
        // resolved hex values for the current appearance.
        let css = theme.cssVariables(appearance: NSApp.effectiveAppearance)
        let escapedCSS = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        let themeScript = WKUserScript(
            source: """
            (function() {
              const style = document.getElementById('porty-theme-vars');
              if (style) { style.textContent = `\(escapedCSS)`; }
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(themeScript)

        if let htmlURL = Bundle.main.url(forResource: "preview", withExtension: "html") {
            // Grant read access ONLY to the directory containing preview.html,
            // not the whole app bundle. Prevents a DOMPurify-bypass from
            // fetching arbitrary bundle resources.
            let readScope = htmlURL.deletingLastPathComponent()
            webView.loadFileURL(htmlURL, allowingReadAccessTo: readScope)
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.schemeHandler?.projectFolderURL = projectFolderURL
        context.coordinator.projectFolderURL = projectFolderURL
        context.coordinator.pendingMarkdown = preprocessEmbeds(markdown)

        // Re-inject CSS variables whenever the theme or appearance changes.
        let newThemeKey = "\(theme.id.rawValue)-\(appearanceSignal)"
        if context.coordinator.lastThemeKey != newThemeKey {
            context.coordinator.lastThemeKey = newThemeKey
            reapplyTheme(webView: webView)
        }

        if context.coordinator.isReady {
            context.coordinator.render()
        }
    }

    private func reapplyTheme(webView: WKWebView) {
        let css = theme.cssVariables(appearance: NSApp.effectiveAppearance)
        let escaped = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        webView.evaluateJavaScript("""
        (function(){
          const s = document.getElementById('porty-theme-vars');
          if (s) { s.textContent = `\(escaped)`; }
        })();
        """)
    }

    private func preprocessEmbeds(_ md: String) -> String {
        let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "svg", "webp", "avif", "heic", "tiff"]
        let videoExts: Set<String> = ["mp4", "webm", "ogg", "mov", "m4v"]
        let audioExts: Set<String> = ["mp3", "wav", "aac", "m4a", "flac"]

        var result = md
        let embedRE = Self.embedRegex
        let matches = embedRE.matches(in: result, range: NSRange(location: 0, length: (result as NSString).length))

        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let filenameRange = Range(match.range(at: 1), in: result) else { continue }
            let filename = String(result[filenameRange]).trimmingCharacters(in: .whitespaces)
            let ext = (filename as NSString).pathExtension.lowercased()

            let replacement: String
            // Defense-in-depth: even though .urlPathAllowed percent-encodes `"`,
            // the `??` fallback would previously pass the raw filename into the
            // attribute if encoding returned nil. Fall back to "" and HTML-escape
            // the encoded value before it enters the attribute.
            let safeEncodedSrc: String = {
                let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
                return Self.escapeHTML(encoded)
            }()

            if imageExts.contains(ext) {
                replacement = "<img src=\"portymcfolio://media/\(safeEncodedSrc)\" alt=\"\(Self.escapeHTML(filename))\">"
            } else if videoExts.contains(ext) {
                replacement = "<video src=\"portymcfolio://media/\(safeEncodedSrc)\" controls preload=\"metadata\"></video>"
            } else if audioExts.contains(ext) {
                replacement = "<audio src=\"portymcfolio://media/\(safeEncodedSrc)\" controls preload=\"metadata\"></audio>"
            } else if LinkItem.isLinkFile(name: filename) {
                replacement = buildLinkCard(filename: filename)
            } else {
                replacement = "<span class=\"file-badge\" data-file=\"\(Self.escapeHTML(filename))\">\(Self.escapeHTML(filename))</span>"
            }

            result.replaceSubrange(fullRange, with: replacement)
        }

        return result
    }

    private func buildLinkCard(filename: String) -> String {
        let fileURL = projectFolderURL.appendingPathComponent(filename)
        let cacheKey = fileURL.path as NSString
        let mtime = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date

        let link: LinkItem
        if let cached = Self.linkCardCache.object(forKey: cacheKey),
           let mtime, cached.mtime == mtime {
            link = cached.link
        } else {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
                  let parsed = try? LinkItem.parse(markdown: content) else {
                return "<span class=\"file-badge\">\(Self.escapeHTML(filename))</span>"
            }
            link = parsed
            if let mtime {
                Self.linkCardCache.setObject(LinkCardCacheEntry(link: link, mtime: mtime), forKey: cacheKey)
            }
        }

        let title = link.title.isEmpty ? (link.url.host ?? link.url.absoluteString) : link.title
        let domain = link.url.host?.replacingOccurrences(of: "www.", with: "") ?? ""
        return """
        <a class="link-card" href="\(Self.escapeHTML(link.url.absoluteString))" target="_blank">
          <span class="link-card-icon">\u{1F517}</span>
          <span class="link-card-body">
            <span class="link-card-title">\(Self.escapeHTML(title))</span>
            <span class="link-card-domain">\(Self.escapeHTML(domain))</span>
          </span>
        </a>
        """
    }

    // MARK: - Export

    /// Exports the rendered HTML + all referenced files to a user-chosen folder.
    static func export(markdown: String, projectFolderURL: URL, projectTitle: String, projectYear: Int, theme: Theme) {
        let panel = NSSavePanel()
        panel.title = "Export Project"
        let name = projectTitle.isEmpty ? "export" : "\(projectYear)_\(projectTitle)"
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        // We're saving a folder, so use a directory approach
        panel.allowedContentTypes = [.folder]

        guard panel.runModal() == .OK, let destFolder = panel.url else { return }

        do {
            try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)

            // Collect referenced files from ![[]] embeds
            let embedRE = Self.embedRegex
            let matches = embedRE.matches(in: markdown, range: NSRange(location: 0, length: (markdown as NSString).length))
            var referencedFiles: [String] = []

            for match in matches {
                if let range = Range(match.range(at: 1), in: markdown) {
                    referencedFiles.append(String(markdown[range]).trimmingCharacters(in: .whitespaces))
                }
            }

            // Copy referenced files to an "assets" subfolder
            let assetsFolder = destFolder.appendingPathComponent("assets")
            if !referencedFiles.isEmpty {
                try FileManager.default.createDirectory(at: assetsFolder, withIntermediateDirectories: true)
            }

            for filename in referencedFiles {
                let src = projectFolderURL.appendingPathComponent(filename)
                guard FileManager.default.fileExists(atPath: src.path) else { continue }
                let destFile = assetsFolder.appendingPathComponent((filename as NSString).lastPathComponent)
                try? FileManager.default.copyItem(at: src, to: destFile)
            }

            // Build export HTML with relative paths to assets/
            let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "svg", "webp", "avif", "heic", "tiff"]
            let videoExts: Set<String> = ["mp4", "webm", "ogg", "mov", "m4v"]
            let audioExts: Set<String> = ["mp3", "wav", "aac", "m4a", "flac"]

            var processedMd = markdown
            let exportMatches = embedRE.matches(in: processedMd, range: NSRange(location: 0, length: (processedMd as NSString).length))

            for match in exportMatches.reversed() {
                guard let fullRange = Range(match.range, in: processedMd),
                      let fnRange = Range(match.range(at: 1), in: processedMd) else { continue }
                let filename = String(processedMd[fnRange]).trimmingCharacters(in: .whitespaces)
                let basename = (filename as NSString).lastPathComponent
                let ext = (filename as NSString).pathExtension.lowercased()

                let esc = Self.escapeHTML
                let html: String
                if imageExts.contains(ext) {
                    html = "<img src=\"assets/\(esc(basename))\" alt=\"\(esc(basename))\">"
                } else if videoExts.contains(ext) {
                    html = "<video src=\"assets/\(esc(basename))\" controls></video>"
                } else if audioExts.contains(ext) {
                    html = "<audio src=\"assets/\(esc(basename))\" controls></audio>"
                } else if LinkItem.isLinkFile(name: filename) {
                    let fileURL = projectFolderURL.appendingPathComponent(filename)
                    if let content = try? String(contentsOf: fileURL, encoding: .utf8),
                       let link = try? LinkItem.parse(markdown: content) {
                        let title = link.title.isEmpty ? (link.url.host ?? link.url.absoluteString) : link.title
                        let domain = link.url.host?.replacingOccurrences(of: "www.", with: "") ?? ""
                        html = """
                        <a class="link-card" href="\(esc(link.url.absoluteString))" target="_blank" rel="noopener noreferrer">\
                        <span class="link-card-icon">\u{1F517}</span>\
                        <span class="link-card-body">\
                        <span class="link-card-title">\(esc(title))</span>\
                        <span class="link-card-domain">\(esc(domain))</span>\
                        </span></a>
                        """
                    } else {
                        html = esc(basename)
                    }
                } else {
                    html = "<span class=\"file-badge\">\(esc(basename))</span>"
                }
                processedMd.replaceSubrange(fullRange, with: html)
            }

            // Build full HTML document.
            // `preview.html` has TWO <style> blocks: one tagged
            // `<style id="porty-theme-vars">` for the live-inject theme :root
            // variables, and a second static `<style>` with the actual CSS
            // rules. For the exported HTML we extract the range from the first
            // `<style` through the LAST `</style>` so both blocks are
            // included, then append the active theme's CSS variables (so they
            // override the placeholder :root) and drop the id attribute since
            // the exported file doesn't need the runtime JS hook.
            let cssURL = Bundle.main.url(forResource: "preview", withExtension: "html")
            var css = ""
            if let htmlURL = cssURL, let htmlContent = try? String(contentsOf: htmlURL, encoding: .utf8),
               let styleStart = htmlContent.range(of: "<style"),
               let styleEnd = htmlContent.range(of: "</style>", options: .backwards) {
                css = String(htmlContent[styleStart.lowerBound...styleEnd.upperBound])
            }

            let themeCSS = theme.cssVariables(appearance: NSApp.effectiveAppearance)
            // Insert theme CSS right after the theme-vars </style> closer so it
            // overrides the placeholder :root without polluting the body CSS block.
            css = css.replacingOccurrences(
                of: "</style>\n<style>",
                with: "\n\(themeCSS)\n</style>\n<style>"
            )
            css = css.replacingOccurrences(of: "<style id=\"porty-theme-vars\">", with: "<style>")

            let markedJS = Self.loadBundledJS(named: "marked.min")
            let purifyJS = Self.loadBundledJS(named: "purify.min")

            let exportHTML = Self.buildExportHTML(
                title: projectTitle,
                processedMd: processedMd,
                css: css,
                markedJS: markedJS,
                purifyJS: purifyJS
            )

            let htmlFile = destFolder.appendingPathComponent("index.html")
            try exportHTML.write(to: htmlFile, atomically: true, encoding: .utf8)

            // Open the export folder in Finder
            NSWorkspace.shared.open(destFolder)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Export failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private static func jsonEncode(_ str: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [str]),
              let array = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(array.dropFirst().dropLast())
    }

    /// Build the final HTML document shipped to the user's export folder.
    /// Sanitizes via DOMPurify because the markdown body may contain raw HTML
    /// (marked.js passes `<script>` and other dangerous tags straight through).
    /// Exposed for testing.
    static func buildExportHTML(
        title: String,
        processedMd: String,
        css: String,
        markedJS: String,
        purifyJS: String
    ) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>\(escapeHTML(title))</title>
        \(css)
        </head>
        <body>
        <div id="content"></div>
        <script>\(markedJS)</script>
        <script>\(purifyJS)</script>
        <script>
        document.getElementById('content').innerHTML = DOMPurify.sanitize(marked.parse(\(jsonEncode(processedMd)), { gfm: true, breaks: true }));
        </script>
        </body>
        </html>
        """
    }

    private static func loadBundledJS(named name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return contents
    }

    static func escapeHTML(_ str: String) -> String {
        str.replacingOccurrences(of: "&", with: "&amp;")
           .replacingOccurrences(of: "<", with: "&lt;")
           .replacingOccurrences(of: ">", with: "&gt;")
           .replacingOccurrences(of: "\"", with: "&quot;")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var schemeHandler: PreviewSchemeHandler?
        var projectFolderURL: URL?
        var pendingMarkdown: String?
        var isReady = false
        /// Tracks the last injected theme+appearance combination so updateNSView
        /// only re-evaluates the CSS when something actually changed.
        var lastThemeKey: String = ""

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            render()
        }

        // Intercept link clicks — open in default browser instead of navigating the WKWebView
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url, url.isSafeExternalScheme {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        // Handle "openFile" messages from file badge clicks
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "openFile",
                  let filename = message.body as? String,
                  let projectFolder = projectFolderURL else { return }
            let fileURL = projectFolder.appendingPathComponent(filename)
            guard PathValidation.isContained(fileURL: fileURL, within: projectFolder) else { return }
            NSWorkspace.shared.open(fileURL)
        }

        func render() {
            guard let webView, let md = pendingMarkdown else { return }
            guard let data = try? JSONSerialization.data(withJSONObject: [md]),
                  let jsonArray = String(data: data, encoding: .utf8) else { return }
            let jsonString = String(jsonArray.dropFirst().dropLast())
            webView.evaluateJavaScript("renderMarkdown(\(jsonString))")
        }

        deinit {
            webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        }
    }
}
