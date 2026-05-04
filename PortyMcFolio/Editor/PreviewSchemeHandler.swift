import Foundation
import WebKit
import UniformTypeIdentifiers

final class PreviewSchemeHandler: NSObject, WKURLSchemeHandler {
    var projectFolderURL: URL?

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let projectFolder = projectFolderURL else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let filename = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // Reject encoded traversal patterns before decoding
        let lower = filename.lowercased()
        guard !lower.contains("%2e%2e"), !lower.contains("%00"), !lower.contains("..") else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let decodedFilename = filename.removingPercentEncoding ?? filename
        let fileURL = projectFolder.appendingPathComponent(decodedFilename)

        guard PathValidation.isContained(fileURL: fileURL, within: projectFolder),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let response = URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: nil)
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
