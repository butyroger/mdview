// MDView Quick Look 預覽：Finder 按空白鍵時用與 MDView 相同的樣式顯示，連結可點（交給預設瀏覽器）。
import Cocoa
import Quartz
import WebKit
import os

let qlLog = Logger(subsystem: "com.butyshop.mdview.quicklook", category: "preview")

@objc(MDViewLinkOpener) protocol MDViewLinkOpener {
    func open(_ url: String, reply: @escaping (Bool) -> Void)
}

@objc(PreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {
    var web: WKWebView!
    var pending: (text: String, base: String)?
    var loaded = false

    override func loadView() {
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        web.navigationDelegate = self
        view = web
        // 主題跟 MDView 一致：讀 MDView 的偏好設定（auto / light / dark）
        let theme = UserDefaults(suiteName: "com.butyshop.mdview")?.string(forKey: "theme") ?? "auto"
        qlLog.log("theme=\(theme, privacy: .public)")
        if theme == "light" { view.appearance = NSAppearance(named: .aqua) }
        if theme == "dark" { view.appearance = NSAppearance(named: .darkAqua) }
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do {
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            pending = (text, url.deletingLastPathComponent().absoluteString)
            let viewer = Bundle(for: Self.self).url(forResource: "viewer", withExtension: "html")!
            web.loadFileURL(viewer, allowingReadAccessTo: viewer.deletingLastPathComponent())
            handler(nil)
        } catch { handler(error) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !loaded, let p = pending,
              let d = try? JSONSerialization.data(withJSONObject: [p.text, p.base]),
              let json = String(data: d, encoding: .utf8) else { return }
        loaded = true
        web.evaluateJavaScript("(function(a){render(a[0], false, a[1]);})(\(json))")
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard action.navigationType == .linkActivated, let url = action.request.url else { decisionHandler(.allow); return }
        if url.isFileURL, url.fragment != nil, url.path == action.sourceFrame.request.url?.path { decisionHandler(.allow); return }
        decisionHandler(.cancel)
        qlLog.log("link click \(url.absoluteString, privacy: .public)")
        // 外掛無權直接開程式也不能連網，交給 MDView 的 XPC 連結中繼代開
        let c = NSXPCConnection(machServiceName: "com.butyshop.mdview.linkhelper", options: [])
        c.remoteObjectInterface = NSXPCInterface(with: MDViewLinkOpener.self)
        c.resume()
        let proxy = c.remoteObjectProxyWithErrorHandler { err in
            qlLog.log("relay error \(String(describing: err), privacy: .public)"); c.invalidate()
        } as? MDViewLinkOpener
        proxy?.open(url.absoluteString) { ok in qlLog.log("relay ok=\(ok)"); c.invalidate() }
    }
}
