import Foundation
import WebKit

/// Serves only the six packaged files. There is no HTTP listener or remote host.
final class BundleContent: NSObject, WKURLSchemeHandler {
    static let scheme = "breakgame"
    static let host = "bundle"
    private let root: URL
    private let mime = ["index.html": "text/html", "game.js": "application/javascript",
                        "native.js": "application/javascript", "desktop.js": "application/javascript",
                        "original.css": "text/css", "desktop.css": "text/css"]

    init(root: URL) { self.root = root }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, url.scheme == Self.scheme, url.host == Self.host,
              task.request.httpMethod == "GET", url.query == nil,
              let type = mime[String(url.path.dropFirst())] else {
            task.didFailWithError(NSError(domain: "BreakContent", code: 403,
                userInfo: [NSLocalizedDescriptionKey: "游戏仅允许读取内置离线资源。 "]))
            return
        }
        do {
            let data = try Data(contentsOf: root.appendingPathComponent(String(url.path.dropFirst())))
            task.didReceive(URLResponse(url: url, mimeType: type, expectedContentLength: data.count,
                                        textEncodingName: "utf-8"))
            task.didReceive(data)
            task.didFinish()
        } catch { task.didFailWithError(error) }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
