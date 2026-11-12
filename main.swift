// MDView：輕量 Markdown 閱讀器。外部連結交給系統預設瀏覽器（Chrome），.md 連結在本程式內開啟，檔案變更自動重新整理。
import AppKit
import WebKit
import UniformTypeIdentifiers

final class ViewerWindow: NSWindowController, WKNavigationDelegate, NSWindowDelegate, NSToolbarDelegate, WKScriptMessageHandler {
    let fileURL: URL
    let web: WKWebView
    var lastModified: Date?
    var timer: Timer?
    var ready = false
    var onClose: ((ViewerWindow) -> Void)?

    init(fileURL: URL) {
        self.fileURL = fileURL
        let cfg = WKWebViewConfiguration()
        cfg.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let ucc = WKUserContentController()
        cfg.userContentController = ucc
        web = WKWebView(frame: .zero, configuration: cfg)
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 820),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        win.title = fileURL.lastPathComponent
        win.representedURL = fileURL
        win.contentView = web
        win.setFrameAutosaveName("MDViewWindow")
        super.init(window: win)
        win.delegate = self
        web.navigationDelegate = self
        ucc.add(WeakHandler(self), name: "mdview")
        web.allowsMagnification = true
        let tb = NSToolbar(identifier: "MDViewToolbar")
        tb.delegate = self
        tb.displayMode = .iconAndLabel
        win.toolbar = tb
        win.toolbarStyle = .unified
        let viewer = Bundle.main.url(forResource: "viewer", withExtension: "html")!
        web.loadFileURL(viewer, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.reloadIfChanged() }
    }
    required init?(coder: NSCoder) { fatalError() }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        render(keepScroll: false)
        setSidebar(UserDefaults.standard.bool(forKey: "sidebar"))
    }

    // MARK: 工具列
    static let ids: [NSToolbarItem.Identifier] = [.init("open"), .init("sidebar"), .flexibleSpace, .init("pdf"), .init("export"), .init("theme"), .init("help")]
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { Self.ids }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { Self.ids }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let d = AppDelegate.shared
        func button(_ label: String, _ symbol: String, _ action: Selector, _ target: AnyObject) -> NSToolbarItem {
            let i = NSToolbarItem(itemIdentifier: id)
            i.label = label; i.toolTip = label
            i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            i.target = target; i.action = action; i.isBordered = true
            return i
        }
        switch id.rawValue {
        case "open": return button("開啟", "doc", #selector(AppDelegate.openDocument(_:)), d)
        case "sidebar": return button("目錄", "sidebar.left", #selector(toggleSidebar(_:)), self)
        case "help": return button("說明", "info.circle", #selector(showHelp(_:)), self)
        case "pdf": return button("PDF", "doc.richtext", #selector(exportPDF(_:)), self)
        case "theme":
            let i = button("主題", d.theme.symbol, #selector(AppDelegate.cycleTheme(_:)), d)
            i.toolTip = "切換主題（目前：\(d.theme.label)）"
            return i
        case "export":
            let i = NSMenuToolbarItem(itemIdentifier: id)
            i.label = "匯出"; i.toolTip = "匯出 HTML / Word"
            i.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "匯出")
            i.showsIndicator = true
            let m = NSMenu()
            for (t, sel) in [("匯出 PDF…", #selector(exportPDF(_:))), ("匯出 HTML…", #selector(exportHTML(_:))), ("匯出 Word（DOCX）…", #selector(exportDOCX(_:)))] {
                let it = NSMenuItem(title: t, action: sel, keyEquivalent: ""); it.target = self; m.addItem(it)
            }
            i.menu = m
            return i
        default: return nil
        }
    }

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.body as? String == "closeSidebar" { setSidebar(false); UserDefaults.standard.set(false, forKey: "sidebar") }
    }
    @objc func showHelp(_ sender: Any?) { web.evaluateJavaScript("toggleHelp()") }
    @objc func showFind(_ sender: Any?) { web.evaluateJavaScript("showFind()") }
    @objc func findNext(_ sender: Any?) { web.evaluateJavaScript("step(1)") }
    @objc func findPrev(_ sender: Any?) { web.evaluateJavaScript("step(-1)") }

    // MARK: 目錄側欄
    var sidebarOn = false
    func setSidebar(_ on: Bool) {
        sidebarOn = on
        web.evaluateJavaScript("toggleSidebar(\(on))")
    }
    @objc func toggleSidebar(_ sender: Any?) {
        setSidebar(!sidebarOn)
        UserDefaults.standard.set(sidebarOn, forKey: "sidebar")
    }

    // MARK: 匯出
    func askSaveURL(_ ext: String, _ title: String) -> URL? {
        let p = NSSavePanel()
        p.title = title
        p.directoryURL = fileURL.deletingLastPathComponent()
        p.nameFieldStringValue = fileURL.deletingPathExtension().lastPathComponent + "." + ext
        p.allowedContentTypes = [.init(filenameExtension: ext)!]
        return p.runModal() == .OK ? p.url : nil
    }

    func renderedHTML(_ done: @escaping (String?) -> Void) {
        web.evaluateJavaScript("exportHTML()") { r, _ in done(r as? String) }
    }

    @objc func exportPDF(_ sender: Any?) {
        guard let url = askSaveURL("pdf", "匯出 PDF") else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize = NSSize(width: 595.28, height: 841.89)
        info.topMargin = 36; info.bottomMargin = 36; info.leftMargin = 36; info.rightMargin = 36
        info.horizontalPagination = .fit; info.verticalPagination = .automatic
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let wasSide = sidebarOn
        if wasSide { setSidebar(false) }
        let op = web.printOperation(with: info)
        op.showsPrintPanel = false; op.showsProgressPanel = true
        op.view?.frame = web.bounds
        op.runModal(for: window!, delegate: self, didRun: #selector(printDone(_:success:context:)), contextInfo: nil)
        pendingOpen = url
        if wasSide { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.setSidebar(true) } }
    }
    var pendingOpen: URL?
    @objc func printDone(_ op: NSPrintOperation, success: Bool, context: UnsafeMutableRawPointer?) {
        if success, let u = pendingOpen { NSWorkspace.shared.activateFileViewerSelecting([u]) }
        pendingOpen = nil
    }

    @objc func exportHTML(_ sender: Any?) {
        guard let url = askSaveURL("html", "匯出 HTML") else { return }
        renderedHTML { html in
            guard let html else { return }
            try? html.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    @objc func exportDOCX(_ sender: Any?) {
        guard let url = askSaveURL("docx", "匯出 Word") else { return }
        renderedHTML { html in
            guard let html else { return }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".html")
            // Word 不吃 CSS 變數與深色，改用淺色固定樣式
            let plain = html.replacingOccurrences(of: "@media (prefers-color-scheme:dark)", with: "@media (max-width:0px)")
            try? plain.write(to: tmp, atomically: true, encoding: .utf8)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
            p.arguments = ["-convert", "docx", "-inputencoding", "UTF-8", tmp.path, "-output", url.path]
            try? p.run(); p.waitUntilExit()
            try? FileManager.default.removeItem(at: tmp)
            if p.terminationStatus == 0 { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            else { NSAlert(error: NSError(domain: "MDView", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "DOCX 轉檔失敗"])).runModal() }
        }
    }

    func modDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }

    func reloadIfChanged() {
        guard ready, let m = modDate(), m != lastModified else { return }
        render(keepScroll: true)
    }

    func render(keepScroll: Bool) {
        lastModified = modDate()
        let text: String
        if let data = try? Data(contentsOf: fileURL) {
            text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        } else {
            text = "# 無法讀取檔案\n\n`\(fileURL.path)`"
        }
        let base = fileURL.deletingLastPathComponent().absoluteString
        guard let payload = try? JSONSerialization.data(withJSONObject: [text, base]),
              let json = String(data: payload, encoding: .utf8) else { return }
        web.evaluateJavaScript("(function(a){render(a[0], \(keepScroll), a[1]);})(\(json))")
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard action.navigationType == .linkActivated, let url = action.request.url else {
            decisionHandler(.allow); return
        }
        decisionHandler(.cancel)
        if url.isFileURL {
            let path = url.path
            if path == fileURL.path, let frag = url.fragment {
                web.evaluateJavaScript("location.hash = \(String(reflecting: frag))")
            } else if ["md", "markdown", "mdown"].contains(url.pathExtension.lowercased()) {
                AppDelegate.shared.open(URL(fileURLWithPath: path))
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            }
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        onClose?(self)
    }
}

final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) { target?.userContentController(c, didReceive: m) }
}

enum Theme: String, CaseIterable {
    case auto, light, dark
    var label: String { ["auto": "跟隨系統", "light": "淺色", "dark": "深色"][rawValue]! }
    var symbol: String { ["auto": "circle.lefthalf.filled", "light": "sun.max", "dark": "moon"][rawValue]! }
    var appearance: NSAppearance? { self == .auto ? nil : NSAppearance(named: self == .light ? .aqua : .darkAqua) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()
    var theme = Theme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .auto {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme"); applyTheme() }
    }
    func applyTheme() {
        NSApp.appearance = theme.appearance
        for w in windows {
            for i in w.window?.toolbar?.items ?? [] where i.itemIdentifier.rawValue == "theme" {
                i.image = NSImage(systemSymbolName: theme.symbol, accessibilityDescription: "主題")
                i.toolTip = "切換主題（目前：\(theme.label)）"
            }
        }
    }
    @objc func cycleTheme(_ sender: Any?) {
        let all = Theme.allCases
        theme = all[(all.firstIndex(of: theme)! + 1) % all.count]
    }
    var windows: [ViewerWindow] = []
    var pending: [URL] = []
    var launched = false

    func open(_ url: URL) {
        let url = url.standardizedFileURL
        if let w = windows.first(where: { $0.fileURL == url }) {
            w.showWindow(nil); w.window?.makeKeyAndOrderFront(nil); return
        }
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        let w = ViewerWindow(fileURL: url)
        w.onClose = { [weak self] closed in self?.windows.removeAll { $0 === closed } }
        windows.append(w)
        if let front = NSApp.keyWindow, front.isVisible {
            w.window?.setFrameTopLeftPoint(NSPoint(x: front.frame.minX + 24, y: front.frame.maxY - 24))
        } else {
            w.window?.center()
        }
        w.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if launched { urls.forEach(open); openPanel?.cancel(nil) } else { pending += urls }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        applyTheme()
        ensureHelperInstalled()
        launched = true
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }.map { URL(fileURLWithPath: $0) }
        (pending + args).forEach(open)
        pending = []
        // 用 `open 檔案.md` 啟動時，開檔事件常在 didFinishLaunching 之後才到；
        // 若此時立刻跳出模態開檔視窗，會擋住事件迴圈，檔案永遠開不出來。延後再判斷。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, self.windows.isEmpty, self.openPanel == nil else { return }
            self.openDocument(nil)
        }
    }

    /// 拖曳安裝（DMG）也能用：首次啟動或 App 搬家後，自動建立連結中繼 LaunchAgent 並啟用 Quick Look 外掛
    func ensureHelperInstalled() {
        let exe = Bundle.main.executablePath!
        let plist = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/com.butyshop.mdview.linkhelper.plist")
        let want: [String: Any] = [
            "Label": "com.butyshop.mdview.linkhelper",
            "ProgramArguments": [exe, "--link-helper"],
            "MachServices": ["com.butyshop.mdview.linkhelper": true],
            "ProcessType": "Background",
        ]
        let current = (NSDictionary(contentsOf: plist) as? [String: Any])?["ProgramArguments"] as? [String]
        guard current?.first != exe else { return }
        try? FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        (want as NSDictionary).write(to: plist, atomically: true)
        func run(_ path: String, _ args: [String]) {
            let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
            try? p.run(); p.waitUntilExit()
        }
        let domain = "gui/\(getuid())"
        DispatchQueue.global().async {
            run("/bin/launchctl", ["bootout", domain + "/com.butyshop.mdview.linkhelper"])
            run("/bin/launchctl", ["bootstrap", domain, plist.path])
            let ext = Bundle.main.builtInPlugInsURL!.appendingPathComponent("MDViewQuickLook.appex").path
            run("/usr/bin/pluginkit", ["-a", ext])
            run("/usr/bin/pluginkit", ["-e", "use", "-i", "com.butyshop.mdview.quicklook"])
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openDocument(nil) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    var openPanel: NSOpenPanel?
    @objc func openDocument(_ sender: Any?) {
        if let p = openPanel { p.makeKeyAndOrderFront(nil); return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.init(filenameExtension: "md")!, .init(filenameExtension: "markdown")!, .plainText]
        openPanel = panel
        NSApp.activate(ignoringOtherApps: true)
        // 非模態：開檔視窗開著時，外部送來的檔案仍能照常開啟
        panel.begin { [weak self] resp in
            guard let self = self else { return }
            self.openPanel = nil
            if resp == .OK { panel.urls.forEach(self.open) }
            else if self.windows.isEmpty { NSApp.terminate(nil) }
        }
    }

    var current: ViewerWindow? { windows.first { $0.window == NSApp.keyWindow } }
    @objc func reload(_ sender: Any?) { current?.render(keepScroll: true) }
    @objc func zoomIn(_ sender: Any?) { if let w = current { w.web.pageZoom = min(w.web.pageZoom + 0.1, 3) } }
    @objc func zoomOut(_ sender: Any?) { if let w = current { w.web.pageZoom = max(w.web.pageZoom - 0.1, 0.5) } }
    @objc func zoomReset(_ sender: Any?) { current?.web.pageZoom = 1 }
    @objc func helpMenu(_ sender: Any?) { current?.showHelp(sender) }
    @objc func findMenu(_ sender: Any?) { current?.showFind(sender) }
    @objc func findNextMenu(_ sender: Any?) { current?.findNext(sender) }
    @objc func findPrevMenu(_ sender: Any?) { current?.findPrev(sender) }
    @objc func toggleSidebarMenu(_ sender: Any?) { current?.toggleSidebar(sender) }
    @objc func exportPDFMenu(_ sender: Any?) { current?.exportPDF(sender) }
    @objc func exportHTMLMenu(_ sender: Any?) { current?.exportHTML(sender) }
    @objc func exportDOCXMenu(_ sender: Any?) { current?.exportDOCX(sender) }
    @objc func revealInFinder(_ sender: Any?) { if let w = current { NSWorkspace.shared.activateFileViewerSelecting([w.fileURL]) } }
    @objc func editInTextEdit(_ sender: Any?) {
        guard let w = current else { return }
        NSWorkspace.shared.open([w.fileURL], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }
    @objc func printDoc(_ sender: Any?) {
        guard let w = current else { return }
        let op = w.web.printOperation(with: NSPrintInfo.shared)
        op.view?.frame = w.web.bounds
        op.runModal(for: w.window!, delegate: nil, didRun: nil, contextInfo: nil)
    }

    func buildMenu() {
        let main = NSMenu()
        func add(_ title: String, _ items: [NSMenuItem]) {
            let top = NSMenuItem(); let m = NSMenu(title: title)
            items.forEach(m.addItem); top.submenu = m; main.addItem(top)
        }
        func item(_ t: String, _ a: Selector?, _ k: String, _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: t, action: a, keyEquivalent: k); i.keyEquivalentModifierMask = mods; return i
        }
        add("MDView", [item("關於 MDView", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), ""), .separator(),
                       item("隱藏 MDView", #selector(NSApplication.hide(_:)), "h"),
                       item("結束 MDView", #selector(NSApplication.terminate(_:)), "q")])
        let recent = NSMenuItem(title: "最近開啟", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        recentMenu.addItem(item("清除選單", #selector(NSDocumentController.clearRecentDocuments(_:)), ""))
        recent.submenu = recentMenu
        add("檔案", [item("開啟…", #selector(openDocument(_:)), "o"), recent, .separator(),
                    item("在 Finder 中顯示", #selector(revealInFinder(_:)), "r", [.command, .shift]),
                    item("用文字編輯開啟", #selector(editInTextEdit(_:)), "e"), .separator(),
                    item("匯出 PDF…", #selector(exportPDFMenu(_:)), "e", [.command, .shift]),
                    item("匯出 HTML…", #selector(exportHTMLMenu(_:)), ""),
                    item("匯出 Word（DOCX）…", #selector(exportDOCXMenu(_:)), ""),
                    item("列印…", #selector(printDoc(_:)), "p"),
                    item("關閉視窗", #selector(NSWindow.performClose(_:)), "w")])
        add("編輯", [item("復原", Selector(("undo:")), "z"), item("重做", Selector(("redo:")), "z", [.command, .shift]), .separator(),
                    item("剪下", #selector(NSText.cut(_:)), "x"), item("拷貝", #selector(NSText.copy(_:)), "c"),
                    item("貼上", #selector(NSText.paste(_:)), "v"), item("全選", #selector(NSText.selectAll(_:)), "a"), .separator(),
                    item("尋找…", #selector(findMenu(_:)), "f"), item("找下一個", #selector(findNextMenu(_:)), "g"),
                    item("找上一個", #selector(findPrevMenu(_:)), "g", [.command, .shift])])
        add("顯示方式", [item("重新載入", #selector(reload(_:)), "r"),
                      item("顯示／隱藏目錄", #selector(toggleSidebarMenu(_:)), "s", [.command, .control]),
                      item("切換主題", #selector(cycleTheme(_:)), "t", [.command, .shift]), .separator(),
                      item("放大", #selector(zoomIn(_:)), "+"), item("縮小", #selector(zoomOut(_:)), "-"),
                      item("實際大小", #selector(zoomReset(_:)), "0")])
        add("視窗", [item("縮到最小", #selector(NSWindow.performMiniaturize(_:)), "m")])
        add("說明", [item("快捷鍵說明", #selector(helpMenu(_:)), "/")])
        NSApp.mainMenu = main
    }
}

// MARK: 連結中繼（--link-helper）：Quick Look 外掛在沙盒裡不能開程式也不能連網，改用 XPC mach 服務請這裡代開
@objc(MDViewLinkOpener) protocol MDViewLinkOpener {
    func open(_ url: String, reply: @escaping (Bool) -> Void)
}
final class LinkOpenerService: NSObject, MDViewLinkOpener, NSXPCListenerDelegate {
    func open(_ s: String, reply: @escaping (Bool) -> Void) {
        guard let url = URL(string: s), ["http", "https", "mailto", "file"].contains(url.scheme?.lowercased() ?? "") else { reply(false); return }
        DispatchQueue.main.async {
            if url.isFileURL, ["md", "markdown", "mdown"].contains(url.pathExtension.lowercased()) {
                NSWorkspace.shared.open([url], withApplicationAt: Bundle.main.bundleURL, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(url)
            }
            reply(true)
        }
    }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection c: NSXPCConnection) -> Bool {
        c.exportedInterface = NSXPCInterface(with: MDViewLinkOpener.self)
        c.exportedObject = self
        c.resume()
        return true
    }
}
func runLinkHelper() -> Never {
    let service = LinkOpenerService()
    let listener = NSXPCListener(machServiceName: "com.butyshop.mdview.linkhelper")
    listener.delegate = service
    listener.resume()
    withExtendedLifetime(service) { RunLoop.main.run() }
    exit(0)
}

if CommandLine.arguments.contains("--link-helper") { runLinkHelper() }

// 安裝用：把 .md 預設開啟程式設為 MDView（deploy 腳本遠端呼叫）。各機器 .md 的 UTI 不一定相同（有的被別的 App 宣告成 com.unknown.md），全部設
if CommandLine.arguments.contains("--set-default") {
    var types = ["net.daringfireball.markdown", "public.markdown"]
    for ext in ["md", "markdown"] { if let t = UTType(filenameExtension: ext)?.identifier, !types.contains(t) { types.append(t) } }
    for t in types {
        let r = LSSetDefaultRoleHandlerForContentType(t as NSString, .all, "com.butyshop.mdview" as NSString)
        print("set-default \(t) \(r == 0 ? "ok" : "err \(r)")")
    }
    exit(0)
}

let app = NSApplication.shared
app.delegate = AppDelegate.shared
app.setActivationPolicy(.regular)
app.run()
