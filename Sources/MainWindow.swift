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
    private let navigatorButton = NSButton()
    private var navigatorOn = false
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
    private var lounge = LoungeRecord()
    private var attachedJPEG: Data?
    private var carryQuestion: String?
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
    private var launchSplash: LaunchSplashView?
    private var readingChrome: [NSView] = []

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
            presentLounge()
            showSidebar(true, animated: false)
            setReadingChrome(visible: false)
            updateHeaderAvailability()
        }
    }

    // MARK: - Layout

    private func buildUI() {
        guard let window else { return }
        let root = DropRootView()
        root.onDropFile = { [weak self] url in self?.openOrImport(url) }
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
        assistantHost.wantsLayer = true
        assistantHost.layer?.backgroundColor = Theme.paperBackground.cgColor
        assistantHost.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(assistantHost)
        assistantWidth = assistantHost.widthAnchor.constraint(equalToConstant: 468)
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
        ])
        for inset in [
            assistant.leadingAnchor.constraint(equalTo: assistantHost.leadingAnchor, constant: 8),
            assistant.trailingAnchor.constraint(equalTo: assistantHost.trailingAnchor, constant: -10),
            assistant.topAnchor.constraint(equalTo: assistantHost.topAnchor, constant: 8),
            assistant.bottomAnchor.constraint(equalTo: assistantHost.bottomAnchor, constant: -10),
        ] {
            inset.priority = .defaultHigh
            inset.isActive = true
        }
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
        recentsButton.iconSetup("books.vertical", tip: "书房 (⇧⌘L)", target: self, action: #selector(showLibrary), tint: .secondaryLabelColor, size: 28)
        navigatorButton.iconSetup("sidebar.left", tip: "显示或收起目录 (⇧⌘D)", target: self, action: #selector(toggleNavigator), tint: .secondaryLabelColor, size: 28)

        titleLabel.font = Theme.display(16, weight: .semibold)
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

        let brandMark = NSImageView()
        brandMark.image = CompanionArt.avatar
        brandMark.imageScaling = .scaleProportionallyUpOrDown
        brandMark.wantsLayer = true
        brandMark.layer?.cornerRadius = 9
        brandMark.layer?.masksToBounds = true
        brandMark.setAccessibilityLabel("论文伴侣")
        brandMark.translatesAutoresizingMaskIntoConstraints = false

        for view in [openButton, recentsButton, navigatorButton, brandMark, titleLabel, subtitleLabel, compareButton, regionButton, sidebarButton, settingsButton] {
            header.addSubview(view)
        }

        NSLayoutConstraint.activate([
            openButton.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            openButton.topAnchor.constraint(equalTo: header.topAnchor, constant: 15),

            recentsButton.leadingAnchor.constraint(equalTo: openButton.trailingAnchor, constant: 4),
            recentsButton.centerYAnchor.constraint(equalTo: openButton.centerYAnchor),

            navigatorButton.leadingAnchor.constraint(equalTo: recentsButton.trailingAnchor, constant: 4),
            navigatorButton.centerYAnchor.constraint(equalTo: openButton.centerYAnchor),

            brandMark.leadingAnchor.constraint(equalTo: navigatorButton.trailingAnchor, constant: 12),
            brandMark.centerYAnchor.constraint(equalTo: openButton.centerYAnchor),
            brandMark.widthAnchor.constraint(equalToConstant: 32),
            brandMark.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.leadingAnchor.constraint(equalTo: brandMark.trailingAnchor, constant: 10),
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
        readingChrome = [prevButton, nextButton, pageLabel, zoomOutButton, zoomInButton, zoomLabel, fitButton]
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

    private func setReadingChrome(visible: Bool) {
        for view in readingChrome { view.isHidden = !visible }
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
        reader.onDropFile = { [weak self] url in self?.openOrImport(url) }
        reader.onRequestOpen = { [weak self] in self?.pickFile() }
        reader.onRecentPicked = { [weak self] url in self?.open(url: url) }
        reader.onImportFolder = { [weak self] in self?.importFolderPanel() }
        reader.onImportZotero = { [weak self] in self?.importZotero() }
        reader.onRelocatePaper = { [weak self] url in self?.relocatePaper(url) }
        reader.askDock.onSubmit = { [weak self] text in self?.assistantDidSubmit(text) }
        reader.askDock.onQuickAsk = { [weak self] question in self?.assistantDidTapQuickAsk(question) }
        reader.askDock.onStop = { [weak self] in self?.assistantDidStop() }
        reader.askDock.onClearQuote = { [weak self] in self?.anchor = nil }
        reader.askDock.onOpenSettings = { [weak self] in self?.onOpenSettings?() }
        reader.askDock.onAttach = { [weak self] in self?.attachFromComposer() }
        reader.askDock.onClearAttachment = { [weak self] in self?.attachedJPEG = nil }
        assistant.onPickPaper = { [weak self] url in self?.open(url: url) }
        assistant.onLounge = { [weak self] in self?.showLibrary() }
        reader.onNavigatorChanged = { [weak self] on in
            self?.navigatorOn = on
            self?.refreshNavigatorButton()
        }
        reader.onLibraryStatus = { [weak self] text, emptyLibrary in
            guard let self else { return }
            self.statusLabel.stringValue = text
            if self.state == nil {
                self.titleLabel.stringValue = "论文伴侣"
                self.subtitleLabel.stringValue = emptyLibrary ? "打开一篇 PDF 论文开始" : "书房"
                self.window?.title = "论文伴侣"
            }
        }
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
        launchSplash?.finish(immediate: true)
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
                    self.carryQuestion = nil
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
        setReadingChrome(visible: true)

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
        ShelfStore.remember(newState)

        assistant.setDocument(doc)
        assistant.setThreads(newState.threads)
        assistant.setHighlights(newState.highlights)
        assistant.setStudyNotes(newState.studyNotes)
        reader.applyHighlights(newState.highlights)
        reader.configureTranslations(doc: doc, translations: newState.translations, currentPage: 0)

        showSidebar(true, animated: false)
        reader.askDock.clearQuote()
        reader.askDock.setAttachment(nil)
        attachedJPEG = nil
        reader.askDock.setStreaming(false)
        reader.askDock.setConversationCount(newState.threads.count)
        reader.askDock.refreshModelChip()

        var pageIndex = ShelfStore.lastPage(for: doc.path)
        if pageIndex == 0, Prefs.shared.lastDocPath == doc.path, Prefs.shared.lastPage > 0 {
            pageIndex = Prefs.shared.lastPage
        }
        if let page = pdfDocument?.page(at: min(pageIndex, max(0, doc.pageCount - 1))) {
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
        if let question = carryQuestion {
            carryQuestion = nil
            submit(question: question, page: 0, carried: true)
        }
    }

    // MARK: - Sidebar

    private func showSidebar(_ visible: Bool, animated: Bool = true) {
        sidebarVisible = visible
        assistantHost.isHidden = !visible
        assistantWidth.constant = visible ? min(468, (window?.frame.width ?? 1200) * 0.38) : 0
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
        navigatorButton.isEnabled = hasDoc
        compareButton.alphaValue = compareButton.isEnabled ? 1 : 0.45
        regionButton.alphaValue = regionButton.isEnabled ? 1 : 0.45
        navigatorButton.alphaValue = hasDoc ? 1 : 0.45
        refreshNavigatorButton()
    }

    private func refreshNavigatorButton() {
        navigatorButton.contentTintColor = (navigatorOn && state != nil) ? Theme.accent : .secondaryLabelColor
    }

    @objc private func toggleNavigator() { reader.toggleNavigator() }

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

    func currentPaperPath() -> String? { state?.doc.path }

    @objc func showLibrary() {
        if let current = state {
            Store.save(current)
        }
        translator.cancel()
        engine.cancel()
        reportEngine.cancel()
        reportRunning = false
        state = nil
        pdfDocument = nil
        reader.show(document: nil, empty: true)
        setReadingChrome(visible: false)
        presentLounge()
        showSidebar(true, animated: false)
        updateHeaderAvailability()
        updateCompareButton(false)
        compareButton.isHidden = false
    }

    func openOrImport(_ url: URL) {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            importFolder(url)
        } else {
            open(url: url)
        }
    }

    @objc func importFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "导入"
        panel.message = "选择存放论文 PDF 的文件夹，文件仍留在原处"
        if panel.runModal() == .OK, let url = panel.url { importFolder(url) }
    }

    @objc func importZotero() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Zotero/storage")
        guard FileManager.default.fileExists(atPath: url.path) else {
            statusLabel.stringValue = "没有找到 ~/Zotero/storage"
            return
        }
        importFolder(url)
    }

    func importFolder(_ url: URL) {
        let result = ShelfStore.importFolder(url)
        reader.reloadLibrary()
        if result.added == 0 && result.skipped == 0 {
            statusLabel.stringValue = "这个文件夹里没有 PDF"
        } else if result.added == 0 {
            statusLabel.stringValue = "没有新论文 · \(result.skipped) 篇已经在书房"
        } else {
            statusLabel.stringValue = "已放入书房 · 新增 \(result.added) 篇" + (result.skipped > 0 ? " · \(result.skipped) 篇已在" : "")
        }
    }

    func relocatePaper(_ url: URL) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.canChooseDirectories = false
        panel.message = "找到这篇论文现在的位置。笔记会跟着走。"
        panel.prompt = "定位"
        guard panel.runModal() == .OK, let picked = panel.url else { return }
        ShelfStore.relocate(from: url, to: picked)
        reader.reloadLibrary()
        statusLabel.stringValue = "已改到新的位置"
    }

    func promptNewShelf(assignCurrent: Bool) {
        guard let name = promptShelfText(title: "新建书架", confirm: "创建") else { return }
        guard let collection = ShelfStore.createCollection(named: name) else {
            statusLabel.stringValue = "已经有同名书架"
            return
        }
        if assignCurrent, let path = state?.doc.path {
            ShelfStore.toggle(path: path, collection: collection.id)
            statusLabel.stringValue = "已放入「\(collection.name)」"
        }
        reader.reloadLibrary()
    }

    func toggleShelf(path: String, collection: UUID) {
        ShelfStore.toggle(path: path, collection: collection)
        reader.reloadLibrary()
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
        ShelfStore.notePage(path: doc.path, page: currentPage)
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
            showSidebar(true)
            assistant.selectTab(0)
            reader.askDock.focus(quote: text)
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
                self.showSidebar(true)
                self.assistant.selectTab(0)
                self.reader.askDock.focus(quote: "[框选 p.\(pageIndex + 1)] 图片已附上")
                self.submit(question: "解释我框选的这部分（可能是图、表或公式）：它在展示什么，关键信息是什么？", page: pageIndex)
            }
        }
    }

    // MARK: - Asking

    private func presentLounge() {
        lounge = LoungeStore.load()
        assistant.setDocument(nil)
        assistant.setThreads(lounge.threads)
        reader.askDock.setStreaming(false)
        reader.askDock.clearQuote()
        reader.askDock.setAttachment(nil)
        reader.askDock.refreshModelChip()
        attachedJPEG = nil
        anchor = nil
    }

    private func attachFromComposer() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .pdf]
        panel.message = "图片会附在下一条消息上。选 PDF 则会打开那篇论文。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if url.pathExtension.lowercased() == "pdf" {
            open(url: url)
            return
        }
        guard let image = NSImage(contentsOf: url), let jpeg = RegionCapture.jpegData(from: image) else {
            statusLabel.stringValue = "这张图片读不了"
            return
        }
        attachedJPEG = jpeg
        reader.askDock.setAttachment(url.deletingPathExtension().lastPathComponent)
        showSidebar(true)
        assistant.selectTab(0)
        reader.askDock.focusComposer()
    }

    private func submit(question: String, page: Int?, carried: Bool = false) {
        if !carried, let paper = ShelfStore.paperToOpen(question, in: ShelfStore.loadMerged().papers) {
            if state?.doc.path == paper.path {
                submit(question: question, page: page, carried: true)
            } else {
                carryQuestion = question
                statusLabel.stringValue = "正在打开 " + paper.title
                open(url: URL(fileURLWithPath: paper.path))
            }
            return
        }
        let loungeMode = state == nil
        let boundPath = state?.doc.path
        showSidebar(true)
        assistant.selectTab(0)
        guard Prefs.shared.hasAPIKey else {
            assistant.failAnswer("还没有填 API Key：点右上角 ⚙︎ 设置，粘贴 DeepSeek 的 sk- key。")
            onOpenSettings?()
            return
        }

        guard !engine.isStreaming else { return }
        var context = anchor ?? AskContext(kind: .general, page: loungeMode ? nil : page)
        if let jpeg = attachedJPEG {
            context.imageJPEG = jpeg
            if context.quote == nil { context.quote = "附件图片" }
        }
        let doc = state?.doc ?? ChatEngine.loungeDocument()
        let history = loungeMode ? lounge.threads : (state?.threads ?? [])
        let level = state?.readingLevel ?? .intermediate
        let memory = loungeMode ? lounge.conversationMemory : state?.conversationMemory

        let catalog = ShelfStore.catalog(of: ShelfStore.loadMerged().papers)
        var modelQuestion = question
        if carried {
            modelQuestion = "【应用已经打开左侧这篇论文。先用一句话确认已经打开，再回答用户。不要说无法打开本地文件。】\n" + question
        }
        modelQuestion += "\n\n【书库标题，仅供决定要不要打开】\n" + catalog
        assistant.beginAnswer(page: loungeMode ? nil : page, question: question)
        reader.askDock.setStreaming(true)
        statusLabel.stringValue = ConversationContext.recentStart(history) > (memory?.coveredCount ?? 0) ? "正在整理早期交流，随后回答…" : "回答中…"

        engine.ask(doc: doc, history: history, level: level,
                   detail: Prefs.shared.answerDetail,
                   memory: memory, onMemory: { [weak self] memory in
            guard let self else { return }
            if loungeMode {
                guard self.state == nil else { return }
                self.lounge.conversationMemory = memory
                LoungeStore.save(self.lounge)
            } else if var current = self.state, current.doc.path == boundPath {
                current.conversationMemory = memory
                self.state = current
                Store.save(current)
            }
        }, question: modelQuestion, context: context) { [weak self] delta in
            self?.assistant.appendAnswer(delta)
        } onFinish: { [weak self] result in
            guard let self else { return }
            let stillHere = loungeMode ? self.state == nil : self.state?.doc.path == boundPath
            self.statusLabel.stringValue = ""
            self.reader.askDock.setStreaming(false)
            self.reader.askDock.clearQuote()
            self.reader.askDock.setAttachment(nil)
            self.attachedJPEG = nil
            guard stillHere else { return }
            switch result {
            case let .success(answer):
                let parsed = ShelfStore.consumeOpens(answer)
                let shown = parsed.text.isEmpty ? "已经按你的要求处理。" : parsed.text
                self.assistant.finishAnswer(markdown: shown)
                if loungeMode {
                    self.recordLounge(question: question, answer: shown, context: context)
                } else {
                    self.recordThread(question: question, answer: shown, context: context)
                }
                if let query = parsed.queries.first,
                   let paper = ShelfStore.best(query, in: ShelfStore.loadMerged().papers),
                   paper.path != self.state?.doc.path {
                    self.open(url: URL(fileURLWithPath: paper.path))
                }
            case let .failure(error):
                let message = (error as? LLMError)?.localizedDescription ?? error.localizedDescription
                self.assistant.failAnswer(message)
            }
            self.anchor = nil
        }
    }

    private func recordLounge(question: String, answer: String, context: AskContext) {
        var thread = AskThread(kind: context.kind, page: -1, quote: context.quote, question: question, answer: answer)
        if let image = context.imageJPEG,
           let name = Store.saveImage(image, for: URL(fileURLWithPath: ChatEngine.loungePath), suffix: "jpg") {
            thread.imageFile = name
        }
        lounge.threads.append(thread)
        LoungeStore.save(lounge)
        assistant.setThreads(lounge.threads)
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
        reader.askDock.setConversationCount(state.threads.count)
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
        reader.askDock.setStreaming(false)
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
        reader.askDock.refreshModelChip()
        if var current = state, current.translationTarget != Prefs.shared.translationCacheKey {
            translator.cancel()
            selectTranslationCache(&current)
            state = current
            Store.save(current)
            reader.configureTranslations(doc: current.doc, translations: current.translations, currentPage: currentPage)
            reader.updateTranslationProgress(nil)
        }

    }

    func findInDocument() { reader.beginFind() }
    func findNextInDocument() { reader.findNext() }
    func findPreviousInDocument() { reader.findPrevious() }
    func toggleNavigatorFromMenu() { reader.toggleNavigator() }
    func debugFind(_ query: String) { reader.beginFind(query) }
    func debugEndFind() { reader.endFind() }
    func debugShowThumbnails() { reader.showThumbnailNavigator() }
    func debugSetLibrarySearch(_ text: String) { reader.debugSetLibrarySearch(text) }
    func debugSelectDetail(detailed: Bool) { reader.askDock.debugSelectDetail(detailed: detailed) }
    func debugSetSidebar(visible: Bool) { showSidebar(visible, animated: false) }
    func debugFocusComposer() {
        window?.makeKeyAndOrderFront(nil)
        reader.askDock.focusComposer()
    }

    /// Fixed frame for README recordings. Drops the user's saved window frame first.
    func prepareShowcaseFrame() {
        window?.setFrameAutosaveName("PaperCompanion.Showcase")
        window?.setFrame(NSRect(x: 48, y: 64, width: 1120, height: 720), display: true, animate: false)
        window?.layoutIfNeeded()
        reader.refitIfNeeded()
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

    /// Full-window title card. Skipped for snapshots, file opens, and `PAPER_COMPANION_NO_SPLASH=1`.
    func presentLaunchSplash() {
        guard LaunchSplashView.shouldPlay, launchSplash == nil, let root = window?.contentView else { return }
        let splash = LaunchSplashView(frame: root.bounds)
        splash.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(splash)
        NSLayoutConstraint.activate([
            splash.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            splash.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            splash.topAnchor.constraint(equalTo: root.topAnchor),
            splash.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        launchSplash = splash
        splash.onFinished = { [weak self] in self?.launchSplash = nil }
        root.layoutSubtreeIfNeeded()
        splash.play()
    }

    func snapshotChat(to path: String, completion: @escaping () -> Void) { assistant.snapshotChat(to: URL(fileURLWithPath: path), completion: completion) }

    func snapshot(to path: String) {
        let args = CommandLine.arguments
        if args.contains("--focus-composer") {
            prepareShowcaseFrame()
            NSApp.activate(ignoringOtherApps: true)
            window?.displayIfNeeded()
            let focused = reader.askDock.focusComposer()
            Debug.log("composer focused=\(focused) responder=\(String(describing: type(of: window?.firstResponder)))")
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            window?.display()
        }
        if (args.contains("--frames") || args.contains("--focus-composer")), let window, window.windowNumber > 0 {
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
            try? capture.run()
            capture.waitUntilExit()
            if capture.terminationStatus == 0,
               let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               (attrs[.size] as? Int ?? 0) > 5000 {
                return
            }
        }
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
        return urls?.first { url in
            if url.pathExtension.lowercased() == "pdf" { return true }
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
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
