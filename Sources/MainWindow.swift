import AppKit
import PDFKit
import UniformTypeIdentifiers

final class MainWindowController: NSWindowController, NSWindowDelegate, AssistantPaneDelegate {
    private lazy var reader = ReaderPane()
    private lazy var assistant = AssistantPane()

    private let header = NSView()
    private let titleLabel = NSTextField(labelWithString: "论文伴侣")
    private let subtitleLabel = NSTextField(labelWithString: "打开一篇 PDF 论文开始")
    private let openButton = NSButton()
    private let recentsButton = NSButton()
    private let compareButton = NSButton()
    private let regionButton = NSButton()
    private let sidebarButton = NSButton()
    private let settingsButton = NSButton()

    private let footer = NSView()
    private let pageLabel = NSTextField(labelWithString: "—")
    private let zoomLabel = NSTextField(labelWithString: "100%")
    private let statusLabel = NSTextField(labelWithString: "")
    private let prevButton = NSButton()
    private let nextButton = NSButton()
    private let zoomOutButton = NSButton()
    private let zoomInButton = NSButton()

    private let assistantHost = NSView()
    private var assistantWidth: NSLayoutConstraint!
    private var levelPicker: ReadingLevelWindow?
    private var sidebarVisible = true

    private var state: DocState?
    private var pdfDocument: PDFDocument?
    private let engine = ChatEngine()
    private let reportEngine = ChatEngine()
    private var reportRunning = false
    private let translator = TranslationService()

    private var anchor: AskContext?
    private var currentPage = 0
    private var isLoading = false
    private var studyBuffer = ""

    var onOpenSettings: (() -> Void)?
    private var startupDocument: URL? = nil

    // MARK: - Init

    convenience init(startupDocument: URL? = nil) {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(visible.width - 24, 1800)
        let height = min(visible.height - 32, 1200)
        let window = NSWindow(contentRect: NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        window.title = "论文伴侣"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 900, height: 600)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("PaperCompanion.Reader.v4")
        window.backgroundColor = Theme.paperBackground
        Debug.log("mw: init")
        self.init(window: window)
        Debug.log("mw: init returned")
        self.startupDocument = startupDocument
        Debug.log("mw: startup set")
        window.delegate = self
        Debug.log("mw: delegate set")
        buildUI()
        if let startup = startupDocument {
            open(url: startup)
        } else {
            reader.show(document: nil, empty: true)
            showSidebar(false, animated: false)
        }
    }

    // MARK: - Layout

    private func buildUI() {
        guard let window else { return }
        let root = DropRootView()
        root.onDropFile = { [weak self] url in self?.open(url: url) }
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.paperBackground.cgColor
        window.contentView = root

        Debug.log("ui: header")
        buildHeader()
        Debug.log("ui: footer")
        buildFooter()

        reader.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(header)
        root.addSubview(footer)
        root.addSubview(reader)
        assistantHost.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(assistantHost)
        assistantWidth = assistantHost.widthAnchor.constraint(equalToConstant: 410)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 72),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 36),
            reader.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            reader.trailingAnchor.constraint(equalTo: assistantHost.leadingAnchor, constant: -1),
            reader.topAnchor.constraint(equalTo: header.bottomAnchor),
            reader.bottomAnchor.constraint(equalTo: footer.topAnchor),
        ])
        assistant.translatesAutoresizingMaskIntoConstraints = false
        assistantHost.addSubview(assistant)
        NSLayoutConstraint.activate([
            assistantHost.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            assistantHost.topAnchor.constraint(equalTo: reader.topAnchor),
            assistantHost.bottomAnchor.constraint(equalTo: reader.bottomAnchor),
            assistantWidth,
            assistant.leadingAnchor.constraint(equalTo: assistantHost.leadingAnchor),
            assistant.trailingAnchor.constraint(equalTo: assistantHost.trailingAnchor),
            assistant.topAnchor.constraint(equalTo: assistantHost.topAnchor),
            assistant.bottomAnchor.constraint(equalTo: assistantHost.bottomAnchor),
        ])
        Debug.log("ui: assistant")
        Debug.log("ui: wire")
        assistant.delegate = self
        wireReader()
        NotificationCenter.default.addObserver(forName: .PDFViewScaleChanged, object: reader.pdfView, queue: .main) { [weak self] _ in self?.updateZoomLabel() }
        Store.onSaveError = { [weak self] message in self?.statusLabel.stringValue = message }
        Debug.log("ui: wired")
        Debug.log("ui: done")
    }

    private func buildHeader() {
        header.wantsLayer = true
        header.layer?.backgroundColor = Theme.paperHeader.cgColor
        header.translatesAutoresizingMaskIntoConstraints = false

        openButton.iconSetup("folder.badge.plus", tip: "打开论文 (⌘O)", target: self, action: #selector(pickFile), tint: .secondaryLabelColor, size: 28)
        recentsButton.iconSetup("clock.arrow.circlepath", tip: "最近打开", target: self, action: #selector(showRecents(_:)), tint: .secondaryLabelColor, size: 28)

        titleLabel.font = Theme.text(14.5, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        subtitleLabel.font = Theme.text(10.5)
        subtitleLabel.textColor = .tertiaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        configureCapsule(compareButton, title: "翻译 / 原文", symbol: "character.book.closed", action: #selector(toggleCompare))
        configureCapsule(regionButton, title: "框选", symbol: "rectangle.dashed", action: #selector(toggleRegion))
        sidebarButton.iconSetup("bubble.left.and.bubble.right", tip: "收起/展开助手 (⇧⌘S)", target: self, action: #selector(toggleSidebar), size: 28)
        settingsButton.iconSetup("slider.horizontal.3", tip: "设置 (⌘,)", target: self, action: #selector(openSettings), size: 28)

        for view in [openButton, recentsButton, titleLabel, subtitleLabel, compareButton, regionButton, sidebarButton, settingsButton] {
            header.addSubview(view)
        }

        NSLayoutConstraint.activate([
            openButton.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            openButton.topAnchor.constraint(equalTo: header.topAnchor, constant: 15),

            recentsButton.leadingAnchor.constraint(equalTo: openButton.trailingAnchor, constant: 4),
            recentsButton.centerYAnchor.constraint(equalTo: openButton.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: recentsButton.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: header.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: compareButton.leadingAnchor, constant: -18),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: compareButton.leadingAnchor, constant: -18),

            settingsButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -14),
            settingsButton.centerYAnchor.constraint(equalTo: openButton.centerYAnchor),

            sidebarButton.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -4),
            sidebarButton.centerYAnchor.constraint(equalTo: openButton.centerYAnchor),

            regionButton.trailingAnchor.constraint(equalTo: sidebarButton.leadingAnchor, constant: -10),
            regionButton.centerYAnchor.constraint(equalTo: openButton.centerYAnchor),
            regionButton.heightAnchor.constraint(equalToConstant: 26),

            compareButton.trailingAnchor.constraint(equalTo: regionButton.leadingAnchor, constant: -6),
            compareButton.centerYAnchor.constraint(equalTo: openButton.centerYAnchor),
            compareButton.heightAnchor.constraint(equalToConstant: 26),
        ])

        let line = SeparatorLine()
        line.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            line.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            line.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    private func configureCapsule(_ button: NSButton, title: String, symbol: String, action: Selector) {
        button.title = title
        button.isBordered = false
        button.bezelStyle = .inline
        button.font = Theme.text(11.5, weight: .medium)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .secondaryLabelColor
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 78).isActive = true
    }

    private func buildFooter() {
        footer.wantsLayer = true
        footer.layer?.backgroundColor = Theme.paperHeader.cgColor
        footer.translatesAutoresizingMaskIntoConstraints = false

        prevButton.iconSetup("chevron.left", tip: "上一页", target: self, action: #selector(prevPage), size: 22)
        nextButton.iconSetup("chevron.right", tip: "下一页", target: self, action: #selector(nextPage), size: 22)
        zoomOutButton.iconSetup("minus.magnifyingglass", tip: "缩小", target: self, action: #selector(zoomOut), size: 22)
        zoomInButton.iconSetup("plus.magnifyingglass", tip: "放大", target: self, action: #selector(zoomIn), size: 22)

        pageLabel.font = Theme.mono(11, weight: .medium)
        pageLabel.textColor = .secondaryLabelColor
        pageLabel.alignment = .center
        pageLabel.translatesAutoresizingMaskIntoConstraints = false

        zoomLabel.font = Theme.mono(10.5)
        zoomLabel.textColor = .tertiaryLabelColor
        zoomLabel.alignment = .center
        zoomLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = Theme.text(10.5)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.alignment = .right
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let fitButton = NSButton(title: "适宽", target: self, action: #selector(fitWidth))
        fitButton.bezelStyle = .inline
        fitButton.isBordered = false
        fitButton.font = Theme.text(10.5)
        fitButton.contentTintColor = .secondaryLabelColor
        fitButton.translatesAutoresizingMaskIntoConstraints = false

        for view in [prevButton, nextButton, pageLabel, zoomOutButton, zoomInButton, zoomLabel, fitButton, statusLabel] {
            footer.addSubview(view)
        }
        let topLine = SeparatorLine()
        topLine.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(topLine)

        NSLayoutConstraint.activate([
            topLine.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            topLine.topAnchor.constraint(equalTo: footer.topAnchor),
            topLine.heightAnchor.constraint(equalToConstant: 1),

            prevButton.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 14),
            prevButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),

            pageLabel.leadingAnchor.constraint(equalTo: prevButton.trailingAnchor, constant: 2),
            pageLabel.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            pageLabel.widthAnchor.constraint(equalToConstant: 160),

            nextButton.leadingAnchor.constraint(equalTo: pageLabel.trailingAnchor, constant: 2),
            nextButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),

            zoomOutButton.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 20),
            zoomOutButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),

            zoomLabel.leadingAnchor.constraint(equalTo: zoomOutButton.trailingAnchor, constant: 2),
            zoomLabel.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            zoomLabel.widthAnchor.constraint(equalToConstant: 44),

            zoomInButton.leadingAnchor.constraint(equalTo: zoomLabel.trailingAnchor, constant: 2),
            zoomInButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),

            fitButton.leadingAnchor.constraint(equalTo: zoomInButton.trailingAnchor, constant: 8),
            fitButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),

            statusLabel.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -14),
            statusLabel.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: fitButton.trailingAnchor, constant: 12),
        ])
    }

    private func wireReader() {
        reader.onSelectionAction = { [weak self] action, text, page in
            self?.handleSelection(action: action, text: text, page: page)
        }
        reader.onRegionSelected = { [weak self] page, rect in
            self?.handleRegion(page: page, rect: rect)
        }
        reader.onPageChanged = { [weak self] index in
            self?.currentPage = index
            self?.assistant.currentPage = index
            self?.updateFooter()
        }
        reader.onHighlightTapped = { [weak self] id in
            self?.handleHighlightTap(id)
        }
        reader.onDropFile = { [weak self] url in self?.open(url: url) }
        reader.onRequestOpen = { [weak self] in self?.pickFile() }
        reader.onRecentPicked = { [weak self] url in self?.open(url: url) }
        reader.onTranslationLanguageChanged = { [weak self] language in
            Prefs.shared.translationLanguage = language
            self?.settingsDidChange()
        }
        reader.onRetranslate = { [weak self] in
            guard let self else { return }
            if self.translator.isRunning {
                self.translator.cancel()
                self.reader.updateTranslations(self.state?.translations ?? [:])
                self.reader.updateTranslationProgress(nil)
                self.statusLabel.stringValue = "翻译已停止 · 点击译文栏继续"
            } else { self.startTranslation(force: NSEvent.modifierFlags.contains(.option)) }
        }
        reader.onTranslationVisibilityChanged = { [weak self] visible in
            self?.updateCompareButton(visible)
            Prefs.shared.sidebarVisible = self?.sidebarVisible ?? true
        }
    }

    // MARK: - Document lifecycle

    private func restoreLastDocument() {
        if let path = Prefs.shared.lastDocPath, FileManager.default.fileExists(atPath: path) {
            open(url: URL(fileURLWithPath: path))
        }
    }

    func open(url: URL) {
        guard !isLoading else { return }
        isLoading = true
        statusLabel.stringValue = "正在解析…"
        let target = url.standardizedFileURL

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let cached = Store.load(for: target)
            let doc: PaperDoc?
            if let cached, FileManager.default.fileExists(atPath: cached.doc.path) {
                doc = cached.doc
            } else {
                doc = Library.load(url: target)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                guard let doc else {
                    self.statusLabel.stringValue = "读不了这个文件"
                    let alert = NSAlert()
                    alert.messageText = "打不开这篇论文"
                    alert.informativeText = "可能是扫描版 PDF、加密文件，或者格式不受支持。"
                    alert.runModal()
                    return
                }
                self.apply(doc: doc, cached: cached)
            }
        }
    }

    private func apply(doc: PaperDoc, cached: DocState?) {
        translator.cancel()
        engine.cancel()
        pdfDocument = PDFDocument(url: doc.url)
        reader.show(document: pdfDocument, empty: false)

        var newState = cached ?? DocState(doc: doc)
        newState.doc = doc
        selectTranslationCache(&newState)
        state = newState

        window?.title = doc.title
        titleLabel.stringValue = doc.title
        var subtitle = "\(doc.pageCount) 页 · \(doc.charCount) 字 · \(doc.language.label)"
        if doc.needsOCR { subtitle += " · 扫描版" }
        if doc.truncated { subtitle += " · 正文有截断" }
        subtitleLabel.stringValue = subtitle
        Prefs.shared.lastDocPath = doc.path

        assistant.setDocument(doc)
        assistant.setThreads(newState.threads)
        assistant.setHighlights(newState.highlights)
        assistant.setStudyNotes(newState.studyNotes)
        reader.applyHighlights(newState.highlights)
        reader.configureTranslations(doc: doc, translations: newState.translations, currentPage: 0)

        showSidebar(true, animated: false)

        if let page = pdfDocument?.page(at: min(Prefs.shared.lastPage, max(0, doc.pageCount - 1))) {
            reader.pdfView.go(to: page)
        }
        currentPage = reader.currentPageIndex()
        assistant.currentPage = currentPage
        updateFooter()
        updateZoomLabel()

        compareButton.isHidden = doc.needsOCR
        if !doc.needsOCR {
            reader.showTranslationStrip(animated: false)
            updateCompareButton(false)
        } else {
            reader.setTranslationVisible(false, animated: false)
            updateCompareButton(false)
        }

        if doc.needsOCR {
            statusLabel.stringValue = "扫描版 PDF：没有文字层，可用框选提问"
        } else if !Prefs.shared.hasAPIKey {
            statusLabel.stringValue = "还没有 API Key：点右上角 ⚙︎ 填写"
        } else {
            statusLabel.stringValue = ""
        }

        updateHeaderAvailability()
        if !newState.translations.isEmpty {
            reader.updateTranslationProgress((newState.translations.count, newState.translations.count))
        }
        if newState.readingLevel == nil { assistantDidRequestReadingLevel() }
    }

    // MARK: - Sidebar

    private func showSidebar(_ visible: Bool, animated: Bool = true) {
        sidebarVisible = visible
        assistantHost.isHidden = !visible
        assistantWidth.constant = visible ? min(410, (window?.frame.width ?? 1200) * 0.35) : 0
        window?.contentView?.layoutSubtreeIfNeeded()
        reader.refitIfNeeded()
        sidebarButton.toolTip = visible ? "收起右侧助手 (⇧⌘S)" : "展开右侧助手 (⇧⌘S)"
    }

    @objc private func toggleSidebar() {
        showSidebar(!sidebarVisible)
    }

    @objc private func toggleCompare() {
        if reader.isShowingTranslation {
            reader.setTranslationVisible(false)
        } else if reader.hasTranslationDocument {
            reader.requestTranslationDisplay()
            updateCompareButton(true)
        } else {
            reader.setTranslationVisible(true)
            startTranslation(force: false)
        }
        reader.refitIfNeeded()
        updateCompareButton(reader.isTranslationVisible || reader.isShowingTranslation)
    }

    private func updateHeaderAvailability() {
        let hasDoc = state != nil
        compareButton.isEnabled = hasDoc && (state?.doc.needsOCR == false)
        regionButton.isEnabled = hasDoc
        compareButton.alphaValue = compareButton.isEnabled ? 1 : 0.45
        regionButton.alphaValue = regionButton.isEnabled ? 1 : 0.45
    }

    private func updateCompareButton(_ on: Bool) {
        compareButton.layer?.backgroundColor = on
            ? Theme.accent.withAlphaComponent(0.16).cgColor
            : NSColor.labelColor.withAlphaComponent(0.06).cgColor
        compareButton.contentTintColor = on ? Theme.accent : .secondaryLabelColor
    }

    // MARK: - Actions

    @objc func pickFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf]
        panel.message = "选择一篇论文 PDF"
        if panel.runModal() == .OK, let url = panel.url {
            open(url: url)
        }
    }

    @objc private func showRecents(_ sender: NSButton) {
        let menu = NSMenu()
        let entries = Recents.scan(limit: 8)
        if entries.isEmpty {
            menu.addItem(withTitle: "（没有找到最近的 PDF）", action: nil, keyEquivalent: "")
        }
        for entry in entries {
            let item = NSMenuItem(title: entry.url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.url
            item.toolTip = entry.url.path
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "在 Finder 里选…", action: #selector(pickFile), keyEquivalent: "").target = self
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 6), in: sender)
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        open(url: url)
    }

    @objc private func toggleRegion() {
        let on = !reader.isRegionMode
        reader.setRegionMode(on)
        regionButton.layer?.backgroundColor = on
            ? NSColor.systemOrange.withAlphaComponent(0.18).cgColor
            : NSColor.labelColor.withAlphaComponent(0.06).cgColor
        regionButton.contentTintColor = on ? .systemOrange : .secondaryLabelColor
        if on {
            statusLabel.stringValue = "在论文上拖出一个框，松手即可提问"
        } else {
            statusLabel.stringValue = ""
        }
    }

    @objc private func prevPage() { reader.previousPage(); updateFooter() }
    @objc private func nextPage() { reader.nextPage(); updateFooter() }
    @objc private func zoomIn() { reader.zoom(by: 0.15); updateZoomLabel() }
    @objc private func zoomOut() { reader.zoom(by: -0.15); updateZoomLabel() }
    @objc private func fitWidth() { reader.fitWidth(); updateZoomLabel() }
    @objc private func openSettings() { onOpenSettings?() }

    private func updateFooter() {
        guard let doc = state?.doc else {
            pageLabel.stringValue = "—"
            return
        }
        compareButton.title = reader.isShowingTranslation ? "返回原文" : "翻译 / 译文"
        pageLabel.stringValue = (reader.isShowingTranslation ? "译文 · 原文 " : "原文 ") + "\(currentPage + 1) / \(doc.pageCount)"
        Prefs.shared.lastPage = currentPage
    }

    private func updateZoomLabel() {
        zoomLabel.stringValue = "\(Int((reader.pdfView.scaleFactor * 100).rounded()))%"
    }

    // MARK: - Selection & region

    private func handleSelection(action: SelectionAction, text: String, page: Int) {
        let rects = currentSelectionRects(page: page)
        switch action {
        case .highlight:
            if reader.isShowingTranslation { statusLabel.stringValue = "已保存译文摘录至笔记" }
            addHighlight(page: page, rects: rects, quote: text, threadID: nil, color: .yellow, style: .text)
        case .ask:
            let id = addHighlight(page: page, rects: rects, quote: text, threadID: nil, color: .yellow, style: .text)
            anchor = AskContext(kind: .selection, page: page, quote: text, rects: rects, highlightID: id)
            assistant.focusComposer(with: text, page: page)
        case .explain:
            let id = addHighlight(page: page, rects: rects, quote: text, threadID: nil, color: .yellow, style: .text)
            anchor = AskContext(kind: .selection, page: page, quote: text, rects: rects, highlightID: id)
            submit(question: "解释这段话：它在论文里起什么作用，具体在说什么？", page: page)
        case .translate:
            let id = addHighlight(page: page, rects: rects, quote: text, threadID: nil, color: .green, style: .text)
            anchor = AskContext(kind: .selection, page: page, quote: text, rects: rects, highlightID: id)
            submit(question: "请仅翻译选中的文字。目标语言：" + Prefs.shared.translationLanguage + "。\n" + Prefs.shared.translationPrompt.replacingOccurrences(of: "【目标语言】", with: Prefs.shared.translationLanguage), page: page)
        }
    }

    private func currentSelectionRects(page: Int) -> [CGRect] {
        guard !reader.isShowingTranslation, let selection = reader.pdfView.currentSelection,
              let pdfPage = pdfDocument?.page(at: page) else { return [] }
        let lines = selection.selectionsByLine()
        if lines.isEmpty {
            let bounds = selection.bounds(for: pdfPage)
            return bounds.isEmpty ? [] : [bounds]
        }
        return lines.map { $0.bounds(for: pdfPage) }.filter { !$0.isEmpty }
    }

    private func handleRegion(page: PDFPage, rect: CGRect) {
        let pageIndex = reader.currentPageIndex()
        regionButton.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        regionButton.contentTintColor = .secondaryLabelColor
        statusLabel.stringValue = "正在识别框选内容…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let image = RegionCapture.crop(page: page, rectInPage: rect)
            let jpeg = image.flatMap { RegionCapture.jpegData(from: $0) }
            let ocr = image.map { RegionCapture.ocrText(in: $0) } ?? ""
            let caption = RegionCapture.caption(page: page, near: rect)
            DispatchQueue.main.async {
                self.statusLabel.stringValue = ""
                guard let jpeg else {
                    self.statusLabel.stringValue = "这块区域太小了，重新框一次"
                    return
                }
                let highlightID = self.addHighlight(page: pageIndex, rects: [rect],
                                                    quote: "[框选 p.\(pageIndex + 1)]", threadID: nil,
                                                    color: .blue, style: .region)
                self.anchor = AskContext(kind: .region, page: pageIndex, quote: "[框选 p.\(pageIndex + 1)]",
                                         caption: caption, ocr: ocr,
                                         imageJPEG: Prefs.shared.usesVision ? jpeg : nil, rects: [rect],
                                         highlightID: highlightID)
                self.assistant.focusComposer(with: "[框选 p.\(pageIndex + 1)] 图片已附上", page: pageIndex)
                self.submit(question: "解释我框选的这部分（可能是图、表或公式）：它在展示什么，关键信息是什么？", page: pageIndex)
            }
        }
    }

    // MARK: - Asking

    private func submit(question: String, page: Int?) {
        guard let state else { return }
        guard Prefs.shared.hasAPIKey else {
            assistant.failAnswer("还没有填 API Key：点右上角 ⚙︎ 设置，粘贴 DeepSeek 的 sk- key。")
            onOpenSettings?()
            return
        }

        guard !engine.isStreaming else { return }
        let context = anchor ?? AskContext(kind: .general, page: page)
        let history = state.threads

        assistant.beginAnswer(page: page, question: question)
        statusLabel.stringValue = ConversationContext.recentStart(history) > (state.conversationMemory?.coveredCount ?? 0) ? "正在整理早期交流，随后回答…" : "回答中…"

        engine.ask(doc: state.doc, history: history, level: state.readingLevel ?? .beginner,
                   memory: state.conversationMemory, onMemory: { [weak self] memory in
            guard let self, var current = self.state, current.doc.path == state.doc.path else { return }
            current.conversationMemory = memory
            self.state = current
            Store.save(current)
        }, question: question, context: context) { [weak self] delta in
            self?.assistant.appendAnswer(delta)
        } onFinish: { [weak self] result in
            guard let self else { return }
            self.statusLabel.stringValue = ""
            switch result {
            case let .success(answer):
                self.assistant.finishAnswer(markdown: answer)
                self.recordThread(question: question, answer: answer, context: context)
            case let .failure(error):
                let message = (error as? LLMError)?.localizedDescription ?? error.localizedDescription
                self.assistant.failAnswer(message)
            }
            self.anchor = nil
        }
    }

    private func recordThread(question: String, answer: String, context: AskContext) {
        guard var state else { return }
        var thread = AskThread(kind: context.kind,
                               page: context.page ?? currentPage,
                               quote: context.quote,
                               question: question,
                               answer: answer)
        if let image = context.imageJPEG, let name = Store.saveImage(image, for: state.doc.url, suffix: "jpg") {
            thread.imageFile = name
        }
        if let highlightID = context.highlightID {
            thread.highlightID = highlightID
            if let index = state.highlights.firstIndex(where: { $0.id == highlightID }) {
                state.highlights[index].threadID = thread.id
            }
        }
        state.threads.append(thread)
        Store.save(state)
        self.state = state
        assistant.setThreads(state.threads)
        assistant.setHighlights(state.highlights)
        reader.applyHighlights(state.highlights)
    }

    @discardableResult
    private func addHighlight(page: Int, rects: [CGRect], quote: String, threadID: UUID?,
                              color: HighlightColor = .yellow, style: HighlightStyle = .text) -> UUID? {
        guard var state, !rects.isEmpty || reader.isShowingTranslation else { return nil }
        let highlight = PaperHighlight(page: page, rects: reader.isShowingTranslation ? [] : rects, color: color, style: style, quote: quote, threadID: threadID)
        state.highlights.append(highlight)
        self.state = state
        Store.save(state)
        assistant.setHighlights(state.highlights)
        reader.applyHighlights(state.highlights)
        return highlight.id
    }

    private func handleHighlightTap(_ id: UUID) {
        guard let state, let highlight = state.highlights.first(where: { $0.id == id }) else { return }
        reader.goTo(page: highlight.page)
        assistant.selectTab(1)
        statusLabel.stringValue = "p.\(highlight.page + 1) 的标注"
    }

    // MARK: - Translation

    private func selectTranslationCache(_ value: inout DocState) {
        let key = Prefs.shared.translationCacheKey
        guard value.translationTarget != key else { return }
        var caches = value.translationCaches ?? [:]
        if !value.translations.isEmpty { caches[value.translationTarget.isEmpty ? "legacy-simplified-chinese" : value.translationTarget] = value.translations }
        value.translations = caches[key] ?? [:]
        value.translationCaches = caches
        value.translationTarget = key
    }

    private func startTranslation(force: Bool) {
        guard let state, !state.doc.needsOCR else { return }
        reader.requestTranslationDisplay()
        guard state.readingLevel != nil else { assistantDidRequestReadingLevel(); return }
        guard Prefs.shared.hasAPIKey else { reader.showTranslationError("请先在设置中填写 API Key"); return }
        translator.cancel()
        translator.onPageDelta = { [weak self] page, text in
            guard let self, let current = self.state else { return }
            var preview = current.translations
            preview[page] = text
            self.reader.updateTranslations(preview)
        }
        translator.onPageDone = { [weak self] page, text in
            guard let self, var current = self.state else { return }
            current.translations[page] = text
            self.state = current
            Store.save(current)
            self.reader.updateTranslations(current.translations)
            self.reader.renderTranslationPDF()
        }
        translator.onProgress = { [weak self] done, total in
            guard let self else { return }
            self.reader.updateTranslations(self.state?.translations ?? [:])
            let completed = self.state?.translations.count ?? done
            let all = self.state?.doc.pages.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count ?? total
            self.reader.updateTranslationProgress((completed, all))
            self.statusLabel.stringValue = done < total ? "翻译中 \(completed)/\(all) 页" : ""
        }
        translator.onError = { [weak self] message in
            self?.statusLabel.stringValue = "翻译失败：\(message.prefix(60))"
            self?.reader.showTranslationError(message)
        }
        reader.updateTranslationProgress((0, state.doc.pageCount))
        translator.start(doc: state.doc, existing: state.translations, force: force)
    }

    // MARK: - Study notes

    private func generateStudyNotes() {
        guard let state else { return }
        guard Prefs.shared.hasAPIKey else {
            statusLabel.stringValue = "先填 API Key 才能生成笔记"
            return
        }
        guard !assistant.isAnswering else { return }
        studyBuffer = ""
        assistant.setStudyGenerating(true)
        statusLabel.stringValue = "正在整理学习笔记…"

        engine.studyNotes(doc: state.doc, threads: state.threads, level: state.readingLevel ?? .beginner, highlights: state.highlights) { [weak self] delta in
            guard let self else { return }
            self.studyBuffer += delta
            self.assistant.setStudyDraft(self.studyBuffer)
        } onFinish: { [weak self] result in
            guard let self else { return }
            self.statusLabel.stringValue = ""
            switch result {
            case let .success(text):
                if var current = self.state {
                    current.studyNotes = text
                    self.state = current
                    Store.save(current)
                }
                self.assistant.setStudyNotes(text)
            case let .failure(error):
                self.assistant.setStudyGenerating(false)
                let message = (error as? LLMError)?.localizedDescription ?? error.localizedDescription
                self.assistant.setStudyDraft("生成失败：" + message)
            }
        }
    }

    func assistantDidRequestReadingLevel() {
        guard let current = state, let window, window.attachedSheet == nil else { return }
        let path = current.doc.path
        let picker = ReadingLevelWindow(title: current.doc.title, selected: current.readingLevel)
        levelPicker = picker
        picker.onSelect = { [weak self] level in
            guard let self, var value = self.state, value.doc.path == path else { return }
            value.readingLevel = level
            self.state = value
            Store.save(value)
            self.statusLabel.stringValue = "解释深度：" + level.title
            if let sheet = self.levelPicker?.window { window.endSheet(sheet) }
            self.levelPicker = nil
            self.showSidebar(true)

        }
        window.beginSheet(picker.window!)
    }

    func assistantDidRequestReport() {
        guard let snapshot = state, !reportRunning else { return }
        guard !snapshot.threads.isEmpty else {
            statusLabel.stringValue = "先与 AI 交流，再生成学习报告"
            return
        }
        guard !assistant.isAnswering else { statusLabel.stringValue = "请等当前回答完成后生成报告"; return }
        let panel = NSSavePanel()
        panel.title = "导出 LaTeX 学习报告"
        panel.nameFieldStringValue = "学习报告.tex"
        panel.allowedContentTypes = [UTType(filenameExtension: "tex") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        reportRunning = true
        statusLabel.stringValue = "正在总结交流并排版学习报告…"
        reportEngine.studyNotes(doc: snapshot.doc, threads: snapshot.threads,
                                level: snapshot.readingLevel ?? .beginner, report: true,
                                highlights: snapshot.highlights, onDelta: { _ in }) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.reportRunning = false
                self.statusLabel.stringValue = "报告生成失败：" + error.localizedDescription
            case .success(let summary):
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = LearningReport.export(state: snapshot, summary: summary, to: url)
                    DispatchQueue.main.async {
                        self.reportRunning = false
                        let alert = NSAlert()
                        alert.messageText = result.message.hasPrefix("导出失败") ? "报告导出失败" : (result.pdf == nil ? "LaTeX 源码已导出" : "学习报告已生成")
                        alert.informativeText = result.message
                        alert.runModal()
                        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.activateFileViewerSelecting([result.pdf ?? url]) }
                        self.statusLabel.stringValue = ""
                    }
                }
            }
        }
    }

    // MARK: - AssistantPaneDelegate

    func assistantDidSubmit(_ text: String) {
        let page = reader.currentPageIndex()
        currentPage = page
        submit(question: text, page: page)
    }

    func assistantDidTapQuickAsk(_ question: String) {
        let page = reader.currentPageIndex()
        anchor = AskContext(kind: .general, page: page)
        submit(question: question, page: page)
    }

    func assistantDidStop() {
        engine.cancel()
        assistant.finishAnswer(markdown: studyBuffer.isEmpty ? "（已停止）" : studyBuffer)
    }

    func assistantDidRequestSettings() { onOpenSettings?() }

    func assistantDidClearQuote() { anchor = nil }

    func assistantDidRequestStudyNotes() { generateStudyNotes() }

    func assistantDidDeleteHighlight(_ id: UUID) {
        guard var state else { return }
        state.highlights.removeAll { $0.id == id }
        self.state = state
        Store.save(state)
        assistant.setHighlights(state.highlights)
        reader.applyHighlights(state.highlights)
    }

    func assistantDidOpenHighlight(_ id: UUID) { handleHighlightTap(id) }

    func assistantDidJumpToPage(_ page: Int) {
        reader.goTo(page: page)
        currentPage = page
        updateFooter()
    }

    // MARK: - Automation & menu hooks

    func debugAsk(_ question: String) {
        let page = reader.currentPageIndex()
        currentPage = page
        anchor = AskContext(kind: .general, page: page)
        submit(question: question, page: page)
    }

    func debugSelection(_ text: String, page: Int) {
        handleSelection(action: .explain, text: text, page: page)
    }

    func debugRegion(page: Int, rect: CGRect) {
        guard let pdfPage = pdfDocument?.page(at: page) else { return }
        handleRegion(page: pdfPage, rect: rect)
    }

    func debugSelectTab(_ index: Int) { assistant.selectTab(index) }

    func debugGoToPage(_ page: Int) {
        reader.goTo(page: page)
        currentPage = page
        updateFooter()
    }

    func debugToggleCompare() { toggleCompare() }

    func debugToggleSidebar() { toggleSidebar() }

    func debugGenerateStudyNotes() { generateStudyNotes() }

    func keyDidLoad() {
        if !Prefs.shared.hasAPIKey {
            statusLabel.stringValue = "还没有 API Key：点右上角 ⚙︎ 填写"
        } else if statusLabel.stringValue.contains("API Key") {
            statusLabel.stringValue = ""
        }
        settingsDidChange()
    }

    func settingsDidChange() {
        if var current = state, current.translationTarget != Prefs.shared.translationCacheKey {
            translator.cancel()
            selectTranslationCache(&current)
            state = current
            Store.save(current)
            reader.configureTranslations(doc: current.doc, translations: current.translations, currentPage: currentPage)
            reader.updateTranslationProgress(nil)
        }

    }

    func toggleRegionFromMenu() { toggleRegion() }
    func showTranslationFromMenu() { toggleCompare() }
    func toggleSidebarFromMenu() { toggleSidebar() }
    func zoomInFromMenu() { zoomIn() }
    func zoomOutFromMenu() { zoomOut() }

    func debugChooseLevel(_ index: Int) {
        Debug.log("debugChooseLevel \(index) picker=\(levelPicker != nil)")
        guard let picker = levelPicker else { return }
        let levels = ReadingLevel.allCases
        guard index >= 0, index < levels.count else { return }
        picker.select(levels[index])
    }

    func snapshotChat(to path: String, completion: @escaping () -> Void) { assistant.snapshotChat(to: URL(fileURLWithPath: path), completion: completion) }

    func snapshot(to path: String) {
        let args = CommandLine.arguments
        let selectedWindow = args.contains("--snapshot-level") ? levelPicker?.window : window
        guard let view = selectedWindow?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
        Debug.log("snapshot written: \(path)")
    }

    // MARK: - Window delegate

    func windowDidResize(_ notification: Notification) {

        reader.refitIfNeeded()
    }

    func windowWillClose(_ notification: Notification) {
        engine.cancel()
        translator.cancel()
    }
}

// MARK: - Root drop target

final class DropRootView: NSView {
    var onDropFile: ((URL) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func url(from sender: NSDraggingInfo) -> URL? {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        return urls?.first { ["pdf"].contains($0.pathExtension.lowercased()) }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        url(from: sender) != nil ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = url(from: sender) else { return false }
        onDropFile?(url)
        return true
    }
}
