import AppKit
import WebKit

let gameTitle = "BREaK!BRaKE!BREaK!"

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate,
                         WKNavigationDelegate, WKScriptMessageHandlerWithReply {
    private var window: NSWindow!
    private var webView: ForceWebView!
    private let pressure = PressureInput()
    private var store: LocalStore!
    private var gameActive = false
    private var inputMode = "pressure"
    private var ready = false
    private var quitting = false
    private var startupError: String?
    private let smokeTest = CommandLine.arguments.contains("--smoke-test")
    private var smokeFinished = false
    private var smokeTimeout: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let base = try FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
            let directory = base.appendingPathComponent("BREaK-BRaKE-BREaK", isDirectory: true)
            store = try LocalStore(directory: smokeTest
                ? directory.appendingPathComponent("SmokeTest-\(UUID().uuidString)") : directory)
        } catch { startupError = "无法读取本地设置或成绩：\(error.localizedDescription)" }
        installMenu()
        let configuration = WKWebViewConfiguration()
        // Browser persistence and networking are unnecessary; native code owns data.
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        guard let resources = Bundle.main.resourceURL else { fatalError("Missing app resources") }
        configuration.setURLSchemeHandler(BundleContent(root: resources.appendingPathComponent("Web")),
                                           forURLScheme: BundleContent.scheme)
        configuration.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "native")
        webView = ForceWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 780), configuration: configuration)
        webView.navigationDelegate = self
        webView.pressureConfiguration = NSPressureConfiguration(pressureBehavior: .primaryGeneric)
        window = NSWindow(contentRect: webView.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = gameTitle
        window.minSize = NSSize(width: 800, height: 650)
        window.contentView = webView
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.center()
        pressure.window = window
        pressure.onSample = { [weak self] sample in
            guard let self, self.ready else { return }
            self.evaluate("BreakPressure.receive(\(self.json(sample))); BreakDesktop.rawPressure(\(sample["value"] ?? 0));")
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        webView.load(URLRequest(url: URL(string: "breakgame://bundle/index.html")!))
        if smokeTest {
            smokeTimeout = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
                self?.finishSmoke(["success": false, "error": "Native WebKit smoke test timed out"])
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame,
              message.frameInfo.request.url?.scheme == BundleContent.scheme,
              message.frameInfo.request.url?.host == BundleContent.host,
              let body = message.body as? [String: Any], let action = body["action"] as? String else {
            replyHandler(nil, "无法识别请求。"); return
        }
        if let startupError { replyHandler(nil, startupError); return }
        do {
            switch action {
            case "bootstrap": replyHandler(store.bootstrap, nil)
            case "hardware": replyHandler(["verified": pressure.verified], nil)
            case "mode":
                guard !gameActive, let mode = body["mode"] as? String,
                      ["pressure", "keyboard"].contains(mode),
                      mode != "keyboard" || (body["acknowledged"] as? Bool) == true else {
                    replyHandler(nil, "请先确认键盘/鼠标模式无法提供完整力度体验。"); return
                }
                inputMode = mode
                pressure.setSession(false)
                replyHandler(["mode": mode], nil)
            case "probe":
                guard !gameActive else { replyHandler(nil, "请先返回游戏菜单再检测设备。"); return }
                pressure.beginProbe()
                replyHandler(["ok": true], nil)
            case "settings":
                guard !gameActive, let number = body["threshold"] as? NSNumber,
                      number.doubleValue == Double(number.intValue) else { throw StoreError.invalidSettings }
                replyHandler(try store.setThreshold(number.intValue), nil)
            case "leaderboard":
                replyHandler(["entries": store.leaderboard(limit: (body["limit"] as? Int) ?? 50)], nil)
            case "score":
                guard let name = body["nickname"] as? String, let v0 = body["v0"] as? Double,
                      let time = body["stopTime"] as? Double else { throw StoreError.invalidScore }
                replyHandler(try store.save(nickname: name, v0: v0, stopTime: time), nil)
            case "session":
                let enabled = (body["active"] as? Bool) ?? false
                guard !enabled || inputMode == "keyboard" || pressure.verified else {
                    replyHandler(nil, "未检测到兼容的力度触控板。"); return
                }
                gameActive = enabled
                pressure.setSession(enabled && inputMode == "pressure")
                replyHandler(["ok": true], nil)
            default: replyHandler(nil, "不支持这个操作。")
            }
        } catch { replyHandler(nil, error.localizedDescription) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        decisionHandler(url?.scheme == BundleContent.scheme && url?.host == BundleContent.host ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        configurePressure(in: webView)
        setPaused(!NSApp.isActive || !window.isKeyWindow || window.isMiniaturized)
        if smokeTest {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.runSmoke() }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadingFailed(error)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadingFailed(error)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        ready = false
        gameActive = false
        inputMode = "pressure"
        pressure.deactivate()
        if smokeTest { finishSmoke(["success": false, "error": "WebKit content process terminated"]); return }
        let alert = NSAlert()
        alert.messageText = "游戏渲染进程已退出"
        alert.informativeText = "本地成绩已保留。重新加载后请再次确认触控板。"
        alert.addButton(withTitle: "重新加载")
        alert.addButton(withTitle: "退出")
        if alert.runModal() == .alertFirstButtonReturn {
            webView.load(URLRequest(url: URL(string: "breakgame://bundle/index.html")!))
        } else { NSApp.terminate(nil) }
    }

    private func configurePressure(in view: NSView) {
        view.pressureConfiguration = NSPressureConfiguration(pressureBehavior: .primaryGeneric)
        for child in view.subviews { configurePressure(in: child) }
    }
    private func setPaused(_ paused: Bool) {
        if paused { pressure.deactivate() }
        if ready { evaluate("BreakPressure.setPaused(\(paused ? "true" : "false"));") }
    }
    func applicationDidResignActive(_ notification: Notification) { setPaused(true) }
    func applicationDidBecomeActive(_ notification: Notification) {
        if window != nil { setPaused(!window.isKeyWindow || window.isMiniaturized) }
    }
    func windowDidResignKey(_ notification: Notification) { setPaused(true) }
    func windowDidBecomeKey(_ notification: Notification) { setPaused(false) }
    func windowWillMiniaturize(_ notification: Notification) { setPaused(true) }
    func windowDidDeminiaturize(_ notification: Notification) { setPaused(!NSApp.isActive) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        quitting = true
        pressure.deactivate()
    }

    private func json(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
    private func evaluate(_ script: String) {
        if !quitting { webView.evaluateJavaScript(script, completionHandler: nil) }
    }
    private func loadingFailed(_ error: Error) {
        if smokeTest { finishSmoke(["success": false, "error": error.localizedDescription]); return }
        let alert = NSAlert()
        alert.messageText = "无法加载内置游戏"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private func installMenu() {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        menu.addItem(applicationItem)
        let application = NSMenu()
        application.addItem(withTitle: "关于 \(gameTitle)", action: #selector(showAbout), keyEquivalent: "")
        application.addItem(.separator())
        application.addItem(withTitle: "力度设置…", action: #selector(showSettings), keyEquivalent: ",")
        application.addItem(withTitle: "查看本地成绩文件", action: #selector(revealScores), keyEquivalent: "")
        application.addItem(.separator())
        application.addItem(withTitle: "隐藏 \(gameTitle)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        application.addItem(withTitle: "退出 \(gameTitle)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = application
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        for (title, action, key) in [("撤销", Selector(("undo:")), "z"),
            ("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"),
            ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        editItem.submenu = edit
        menu.addItem(editItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        let fullscreen = windowMenu.addItem(withTitle: "进入全屏", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullscreen.keyEquivalentModifierMask = [.control, .command]
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = menu
        for item in application.items where item.action == #selector(showSettings) || item.action == #selector(showAbout) || item.action == #selector(revealScores) { item.target = self }
    }
    @objc private func showSettings() { if ready { evaluate("BreakDesktop.showSettings();") } }
    @objc private func revealScores() {
        guard let store else { return }
        NSWorkspace.shared.activateFileViewerSelecting([store.url])
    }
    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = gameTitle
        alert.informativeText = "所有代码为生成式人工智能生成。\n\n游戏包含 Three.js 等第三方库；本移植与修改代码由生成式人工智能生成。\n\nApple Silicon / Intel · 离线版 · 1.1.1\n推荐力度触控板，也支持键盘/鼠标备用模式。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func runSmoke() {
        webView.takeSnapshot(with: nil) { [weak self] image, _ in
            guard let self else { return }
            let preview = self.saveSmokeImage(image, name: "startup.png")
            self.exerciseSmoke(startupPreview: preview)
        }
    }
    private func exerciseSmoke(startupPreview: String?) {
        let script = """
        (async () => {
          const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
          const waitUntil = async fn => {
            const end = performance.now() + 5000;
            while (!fn()) {
              if (performance.now() > end) throw new Error('UI checkpoint timed out');
              await sleep(20);
            }
          };
          const bootstrap = await BreakNative.call('bootstrap');
          const initialGate = BreakPressure.verified || document.getElementById('continueBtn').disabled;
          const defaultUI = document.getElementById('thresholdSlider').value === '100';
          // Exercise the real WebKit button with simulated native samples. A
          // trackpad click has pressure before its DOM click reaches the page.
          BreakPressure.beginProbe();
          BreakPressure.receive({value: .4, peak: .4, verified: true, gesture: 10001});
          const calibrationReleaseGate = document.getElementById('continueBtn').disabled;
          BreakPressure.receive({value: 0, peak: 0, verified: true, gesture: 10001});
          const calibrationReady = !document.getElementById('continueBtn').disabled;
          BreakPressure.receive({value: .3, peak: .3, verified: true, gesture: 10002});
          const entryButtonEnabled = !document.getElementById('continueBtn').disabled;
          document.getElementById('continueBtn').click();
          const pressureEntryClick = document.getElementById('startup').classList.contains('hidden');
          const entryPressureCleared = BreakPressure.sample() === 0;
          BreakDesktop.showSettings();
          BreakPressure.beginProbe();
          const calibrationReset = document.getElementById('continueBtn').disabled;
          await BreakNative.call('settings', {threshold: 73});
          const updated = await BreakNative.call('bootstrap');
          const score = await BreakNative.call('score', {nickname: '本机自检', v0: 150, stopTime: 8});
          const board = await BreakNative.call('leaderboard', {limit: 50});
          let requiresAcknowledgment = false;
          try { await BreakNative.call('mode', {mode: 'keyboard'}); }
          catch { requiresAcknowledgment = true; }
          document.getElementById('fallbackBtn').click();
          const warningShown = !document.getElementById('fallbackWarning').classList.contains('hidden');
          document.getElementById('fallbackConfirm').click();
          await waitUntil(() => BreakControl.mode === 'keyboard' && document.getElementById('fallbackWarning').classList.contains('hidden'));
          const fallbackAllowed = !document.getElementById('continueBtn').disabled;
          document.getElementById('continueBtn').click();
          BreakPressure.setPaused(false);
          document.getElementById('startBtn').click();
          await waitUntil(() => BreakGame.diagnostics().phase === 'accelerating');
          const button = document.getElementById('brakeBtn').getBoundingClientRect();
          const labels = [...document.querySelectorAll('#brakeText .brake-caption, #brakeText .brake-speed')].map(x => x.getBoundingClientRect());
          const layoutFits = labels.length === 2 && labels.every(x => x.left >= button.left + 10 && x.right <= button.right - 10 && x.top >= button.top + 10 && x.bottom <= button.bottom - 10);
          window.dispatchEvent(new KeyboardEvent('keydown', {code: 'Space'}));
          const spaceDown = BreakControl.sample() === 1;
          window.dispatchEvent(new KeyboardEvent('keyup', {code: 'Space'}));
          const spaceUp = BreakControl.sample() === 0;
          document.getElementById('app').dispatchEvent(new PointerEvent('pointerdown', {pointerType: 'mouse', button: 0}));
          const mouseDown = BreakControl.sample() === 1;
          window.dispatchEvent(new PointerEvent('pointerup', {pointerType: 'mouse', button: 0}));
          const mouseUp = BreakControl.sample() === 0;
          const diagnostics = BreakGame.diagnostics();
          return {success: bootstrap.threshold === 100 && defaultUI && updated.threshold === 73 &&
              board.entries.length === 1 && board.entries[0].score === 2813 &&
              diagnostics.webgl && diagnostics.frames > 0 && initialGate && requiresAcknowledgment &&
              warningShown && fallbackAllowed && layoutFits && spaceDown && spaceUp && mouseDown && mouseUp &&
              calibrationReleaseGate && calibrationReady && entryButtonEnabled && pressureEntryClick &&
              entryPressureCleared && calibrationReset,
              bootstrap, updated, score, diagnostics, initialGate, requiresAcknowledgment, warningShown,
              fallbackAllowed, layoutFits, spaceDown, spaceUp, mouseDown, mouseUp,
              calibrationReleaseGate, calibrationReady, entryButtonEnabled, pressureEntryClick,
              entryPressureCleared, calibrationReset};
        })()
        """
        webView.callAsyncJavaScript("return await " + script, arguments: [:], in: nil, in: .page, completionHandler: { [weak self] result in
            switch result {
            case .success(let value):
                var report = value as? [String: Any] ?? ["success": false]
                report["preview"] = startupPreview
                self?.snapshotSmoke(report)
            case .failure(let error): self?.finishSmoke(["success": false, "error": error.localizedDescription])
            }
        })
    }
    private func snapshotSmoke(_ result: [String: Any]) {
        webView.takeSnapshot(with: nil) { [weak self] image, error in
            guard let self else { return }
            var report = result
            if let preview = self.saveSmokeImage(image, name: "brake-hud.png") { report["hudPreview"] = preview }
            else if let error { report["snapshotError"] = error.localizedDescription }
            self.finishSmoke(report)
        }
    }
    private func saveSmokeImage(_ image: NSImage?, name: String) -> String? {
        guard let image, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]), let store else { return nil }
        let directory = store.url.deletingLastPathComponent()
        let file = directory.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file)
            return file.path
        } catch { return nil }
    }
    private func finishSmoke(_ result: [String: Any]) {
        guard !smokeFinished else { return }
        smokeFinished = true
        smokeTimeout?.invalidate()
        print("BREAK_SMOKE " + json(result))
        fflush(stdout)
        if let store {
            if result["preview"] == nil { try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent()) }
            else { try? FileManager.default.removeItem(at: store.url) }
        }
        NSApp.terminate(nil)
    }
}
