import AppKit
import PDFKit

enum Debug {
    static let enabled = ProcessInfo.processInfo.environment["PAPER_COMPANION_DEBUG"] == "1"
    static func log(_ message: String) {
        guard enabled else { return }
        let line = "[paper-companion] " + message + "\n"
        FileHandle.standardError.write(line.data(using: .utf8)!)
        if let path = ProcessInfo.processInfo.environment["PAPER_COMPANION_LOG"] {
            let url = URL(fileURLWithPath: path)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
                try? handle.close()
            } else {
                try? line.data(using: .utf8)?.write(to: url)
            }
        }
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: MainWindowController!
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Store.prepare()
        buildMenu()
        var startup: URL?
        if let index = CommandLine.arguments.firstIndex(of: "--doc"), index + 1 < CommandLine.arguments.count {
            startup = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        }
        mainWindow = MainWindowController(startupDocument: startup)
        mainWindow.onOpenSettings = { [weak self] in self?.showSettings() }
        mainWindow.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        Prefs.shared.warmUpKey { [weak self] in
            guard let self else { return }
            self.mainWindow.keyDidLoad()
            self.settingsWindow?.window.map { _ in }
        }



        handleAutomationFlags()
    }

    private func handleAutomationFlags() {
        let arguments = CommandLine.arguments
        guard let snapshotIndex = arguments.firstIndex(of: "--snapshot"), snapshotIndex + 1 < arguments.count else {
            return
        }
        let path = arguments[snapshotIndex + 1]

        let tabValue: Int? = {
            guard let tabIndex = arguments.firstIndex(of: "--tab"), tabIndex + 1 < arguments.count else { return nil }
            return Int(arguments[tabIndex + 1])
        }()
        if let selectionIndex = arguments.firstIndex(of: "--selection"), selectionIndex + 1 < arguments.count {
            let text = arguments[selectionIndex + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [self] in
                mainWindow.debugSelection(text, page: 0)
            }
        }
        if let regionIndex = arguments.firstIndex(of: "--region"), regionIndex + 1 < arguments.count {
            let spec = arguments[regionIndex + 1]
            let parts = spec.split(separator: ",").compactMap { Double($0) }
            if parts.count == 5 {
                let rect = CGRect(x: parts[1], y: parts[2], width: parts[3], height: parts[4])
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [self] in
                    mainWindow.debugRegion(page: Int(parts[0]), rect: rect)
                }
            }
        }

        if let pageIndex = arguments.firstIndex(of: "--page"), pageIndex + 1 < arguments.count,
           let page = Int(arguments[pageIndex + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [self] in
                mainWindow.debugGoToPage(page)
            }
        }

        if let levelIndex = arguments.firstIndex(of: "--level"), levelIndex + 1 < arguments.count,
           let level = Int(arguments[levelIndex + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
                mainWindow.debugChooseLevel(level)
            }
        }
        if arguments.contains("--compare") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [self] in
                mainWindow.debugToggleCompare()
            }
        }
        if arguments.contains("--study") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [self] in
                mainWindow.debugGenerateStudyNotes()
            }
        }
        if arguments.contains("--collapse") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [self] in
                mainWindow.debugToggleSidebar()
            }
        }
        if let askIndex = arguments.firstIndex(of: "--ask"), askIndex + 1 < arguments.count {
            let question = arguments[askIndex + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + (arguments.contains("--level") ? 2.4 : 1.2)) { [self] in
                mainWindow.debugAsk(question)
            }
        }
        var delay: Double = 2.0
        if arguments.contains("--ask") || arguments.contains("--selection") { delay = 9.0 }
        if arguments.contains("--region") { delay = 16.0 }
        if let delayIndex = arguments.firstIndex(of: "--delay"), delayIndex + 1 < arguments.count,
           let custom = Double(arguments[delayIndex + 1]) {
            delay = custom
        }
        Debug.log("snapshot scheduled in \(delay)s -> \(path)")
        if arguments.contains("--settings") {
            showSettings()
        }
        let snapshotTimer = Timer(timeInterval: delay, repeats: false) { [self] _ in
            Debug.log("snapshot timer fired")
            if arguments.contains("--settings") {
                if let view = settingsWindow?.window?.contentView,
                   let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    if let data = rep.representation(using: .png, properties: [:]) {
                        try? data.write(to: URL(fileURLWithPath: path))
                    }
                }
                exit(0)
            }
            if let tabValue { mainWindow.debugSelectTab(tabValue) }
            if let pageIndex = arguments.firstIndex(of: "--page"), pageIndex + 1 < arguments.count,
               let page = Int(arguments[pageIndex + 1]) { mainWindow.debugGoToPage(page) }
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            if arguments.contains("--snapshot-chat") { mainWindow.snapshotChat(to: path) { exit(0) }; return }
            mainWindow.snapshot(to: path)
            exit(0)
        }
        RunLoop.main.add(snapshotTimer, forMode: .common)
    }

    // MARK: Menu

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于论文伴侣", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(showSettingsMenu), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏论文伴侣", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出论文伴侣", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "文件")
        let open = NSMenuItem(title: "打开论文…", action: #selector(openDocument), keyEquivalent: "o")
        open.target = self
        fileMenu.addItem(open)
        fileMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "视图")
        let region = NSMenuItem(title: "框选提问", action: #selector(toggleRegionMenu), keyEquivalent: "r")
        region.keyEquivalentModifierMask = [.command, .shift]
        region.target = self
        viewMenu.addItem(region)
        let translation = NSMenuItem(title: "对照译文", action: #selector(showTranslationMenu), keyEquivalent: "t")
        translation.keyEquivalentModifierMask = [.command, .shift]
        translation.target = self
        viewMenu.addItem(translation)
        let sidebar = NSMenuItem(title: "收起 / 展开助手", action: #selector(toggleSidebarMenu), keyEquivalent: "s")
        sidebar.keyEquivalentModifierMask = [.command, .shift]
        sidebar.target = self
        viewMenu.addItem(sidebar)
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "放大", action: #selector(zoomInMenu), keyEquivalent: "+")
        viewMenu.addItem(withTitle: "缩小", action: #selector(zoomOutMenu), keyEquivalent: "-")
        viewItem.submenu = viewMenu

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func openDocument() {
        mainWindow.pickFile()
    }

    @objc private func showSettingsMenu() {
        showSettings()
    }

    @objc private func toggleRegionMenu() {
        mainWindow.toggleRegionFromMenu()
    }

    @objc private func showTranslationMenu() {
        mainWindow.showTranslationFromMenu()
    }

    @objc private func toggleSidebarMenu() { mainWindow.toggleSidebarFromMenu() }
    @objc private func zoomInMenu() { mainWindow.zoomInFromMenu() }
    @objc private func zoomOutMenu() { mainWindow.zoomOutFromMenu() }

    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController()
            settingsWindow?.onSave = { [weak self] in
                self?.mainWindow.settingsDidChange()
            }
        }
        settingsWindow?.showWindow(nil)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) else { return }
        mainWindow?.open(url: url)
    }
}

// MARK: - LaTeX sample (verification)

if let index = CommandLine.arguments.firstIndex(of: "--texsample"), index + 1 < CommandLine.arguments.count {
    let out = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    let sampleFile = CommandLine.arguments.count > index + 2 ? CommandLine.arguments[index + 2] : ""
    let sample: String
    if !sampleFile.isEmpty, let loaded = try? String(contentsOf: URL(fileURLWithPath: sampleFile), encoding: .utf8) {
        sample = loaded
    } else {
    sample = """
    ## 3.1 模型平均估计量

    令 $\\hat{\\theta}_k$ 为第 $k$ 个候选模型的估计量，权重 $w \\in \\mathcal{W}$ 满足 $\\sum_{k=1}^{K} w_k = 1$。模型平均估计量定义为

    $$\\hat{\\theta}(w) = \\sum_{k=1}^{K} w_k \\hat{\\theta}_k, \\qquad \\mathcal{W} = \\left\\{ w \\in [0,1]^K : \\sum_{k=1}^{K} w_k = 1 \\right\\}.$$

    在假设 (A1)–(A3) 下，当 $n \\to \\infty$ 时

    $$\\sqrt{n}\\,(\\hat{\\theta}(w) - \\theta_0) \\xrightarrow{d} N(0, \\Sigma(w)).$$

    其中 $\\Sigma(w)$ 是渐近协方差矩阵，$\\alpha \\le \\beta$ 且 $\\lambda_{\\min} > 0$。

    | 方法 | 权重 | 风险 |
    | --- | --- | --- |
    | 模型平均 | $w_k$ | $R(w)$ |
    | 模型选择 | $1\\{k=\\hat{k}\\}$ | $R(\\hat{k})$ |

    - **一致性**：$\\hat{\\theta}(w)$ 依概率收敛到 $\\theta_0$；
    - 当 $\\Sigma(w)$ 可逆时，$\\hat{\\theta}(w)$ 渐近正态。
    """
    }
    let layoutSource = CommandLine.arguments.count > index + 3 ? CommandLine.arguments[index + 3] : "/tmp/sample.pdf"
    var doc = PaperDoc(path: layoutSource, title: "Frequentist Model Averaging", pages: [], language: .english,
                       needsOCR: false, truncated: false, fullText: "", charCount: 0, captions: [:])
    doc.pages = [PaperPage(index: 0, text: sample)]
    let tex = TranslationTeX.document(doc: doc, pages: [0: sample], language: "简体中文")
    let result = LearningReport.exportSource(tex, to: out)
    print("pdf: " + (result.pdf?.path ?? "nil"))
    print("message: " + result.message)
    exit(result.pdf == nil ? 1 : 0)
}

if let index = CommandLine.arguments.firstIndex(of: "--halves"), index + 2 < CommandLine.arguments.count {
    let pdf = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[index + 1]))!
    let prefix = CommandLine.arguments[index + 2]
    let halves = RegionCapture.pageHalves(page: pdf.page(at: 0)!)
    for (i, data) in halves.enumerated() {
        try? data.write(to: URL(fileURLWithPath: prefix + "\(i).jpg"))
        print("half \(i): \(data.count) bytes")
    }
    exit(0)
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
