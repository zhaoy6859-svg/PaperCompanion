import AppKit

protocol AssistantPaneDelegate: AnyObject {
    func assistantDidSubmit(_ text: String)
    func assistantDidTapQuickAsk(_ question: String)
    func assistantDidStop()
    func assistantDidRequestSettings()
    func assistantDidClearQuote()
    func assistantDidRequestReport()
    func assistantDidRequestReadingLevel()
    func assistantDidRequestStudyNotes()
    func assistantDidDeleteHighlight(_ id: UUID)
    func assistantDidJumpToPage(_ page: Int)
}

final class ComposerTextView: NSTextView {
    var onSubmit: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn, !event.modifierFlags.contains(.shift), !hasMarkedText() {
            onSubmit?()
            return
        }
        super.keyDown(with: event)
    }
}

final class AssistantPane: NSView, NSTextViewDelegate {
    weak var delegate: AssistantPaneDelegate?
    var currentPage: Int = 0

    private let header = NSView()
    private let chatTab = NSButton()
    private let notesTab = NSButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private let settingsButton = NSButton()
    private let content = NSView()

    // Chat
    private let chatContainer = NSView()
    private let transcript = RichTranscript()
    private var pendingQuestion = ""
    private var pendingPage = 0
    private var failedStream = false
    private let anchorBar = NSView()
    private let anchorLabel = NSTextField(labelWithString: "")
    private let chipsStack = NSStackView()
    private let composerBox = NSView()
    private let composer = ComposerTextView()
    private let composerScroll = NSScrollView()
    private let placeholder = NSTextField(labelWithString: "问关于这篇论文的任何问题…")
    private let sendButton = NSButton()

    // Notes
    private let notesContainer = NSView()
    private let notesText = TextPane()
    private let notesBar = NSView()
    private let studyButton = NSButton()

    private var doc: PaperDoc?
    private var threads: [AskThread] = []
    private var highlights: [PaperHighlight] = []
    private var studyNotes: String?
    private var studyRunning = false

    private var pendingQuote: String?
    private var isStreaming = false
    private var streamStart = -1
    private var streamBuffer = ""
    private var streamTimer: Timer?
    private var selectedTab = 0

    private static let quickAsks: [(String, String)] = [
        ("全文摘要", "用 5 句话概括这篇论文：研究问题、方法、主要结果、贡献、局限。"),
        ("创新点", "这篇论文相对已有工作最实质的新意是什么？具体到机制或假设，不要泛泛而谈。"),
        ("方法可信吗", "这个方法的假设和实验设计有哪些可被质疑的地方？按重要性排序。"),
        ("结论", "作者最终能站得住的结论是什么？哪些只是推测？"),
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Build

    private func build() {
        Debug.log("pane: build start")
        wantsLayer = true
        layer?.backgroundColor = Theme.sidebarBackground.cgColor

        buildHeader()
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)

        Debug.log("pane: chat")
        buildChat()
        Debug.log("pane: notes")
        buildNotes()
        Debug.log("pane: build end")

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.topAnchor.constraint(equalTo: topAnchor),
            header.heightAnchor.constraint(equalToConstant: 46),

            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: header.bottomAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        for view in [chatContainer, notesContainer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                view.topAnchor.constraint(equalTo: content.topAnchor),
                view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            ])
        }
        notesContainer.isHidden = true
        updateTabAppearance()
    }

    private func buildHeader() {
        header.wantsLayer = true
        header.layer?.backgroundColor = Theme.sidebarBackground.cgColor

        configureTab(chatTab, title: "对话", tag: 0)
        configureTab(notesTab, title: "笔记", tag: 1)

        statusLabel.font = Theme.text(10)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.alignment = .right
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        settingsButton.iconSetup("slider.horizontal.3", tip: "设置", target: self, action: #selector(settingsTapped), size: 24)

        for view in [chatTab, notesTab, statusLabel, settingsButton] { header.addSubview(view) }

        NSLayoutConstraint.activate([
            chatTab.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            chatTab.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            chatTab.heightAnchor.constraint(equalToConstant: 26),
            chatTab.widthAnchor.constraint(equalToConstant: 58),

            notesTab.leadingAnchor.constraint(equalTo: chatTab.trailingAnchor, constant: 4),
            notesTab.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            notesTab.heightAnchor.constraint(equalToConstant: 26),
            notesTab.widthAnchor.constraint(equalToConstant: 58),

            settingsButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10),
            settingsButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            statusLabel.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -6),
            statusLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: notesTab.trailingAnchor, constant: 8),
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

    private func configureTab(_ button: NSButton, title: String, tag: Int) {
        button.title = title
        button.tag = tag
        button.isBordered = false
        button.bezelStyle = .inline
        button.setButtonType(.momentaryChange)
        button.font = Theme.text(12, weight: .medium)
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.target = self
        button.action = #selector(tabTapped(_:))
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func updateTabAppearance() {
        for (index, button) in [chatTab, notesTab].enumerated() {
            let selected = index == selectedTab
            button.layer?.backgroundColor = selected ? NSColor.labelColor.withAlphaComponent(0.10).cgColor : NSColor.clear.cgColor
            button.contentTintColor = selected ? .labelColor : .secondaryLabelColor
        }
    }

    private func buildChat() {
        transcript.translatesAutoresizingMaskIntoConstraints = false
        chatContainer.addSubview(transcript)
        transcript.onPage = { [weak self] page in self?.delegate?.assistantDidJumpToPage(page) }

        anchorBar.wantsLayer = true
        anchorBar.layer?.cornerRadius = 8
        anchorBar.layer?.backgroundColor = Theme.accent.withAlphaComponent(0.12).cgColor
        anchorBar.translatesAutoresizingMaskIntoConstraints = false
        anchorBar.isHidden = true
        anchorLabel.font = Theme.text(11)
        anchorLabel.textColor = .secondaryLabelColor
        anchorLabel.lineBreakMode = .byTruncatingTail
        anchorLabel.translatesAutoresizingMaskIntoConstraints = false
        let clearQuote = NSButton()
        clearQuote.iconSetup("xmark.circle.fill", tip: "取消引用", target: self, action: #selector(clearQuoteTapped), size: 18)
        clearQuote.contentTintColor = .tertiaryLabelColor
        anchorBar.addSubview(anchorLabel)
        anchorBar.addSubview(clearQuote)
        NSLayoutConstraint.activate([
            anchorBar.heightAnchor.constraint(equalToConstant: 28),
            anchorLabel.leadingAnchor.constraint(equalTo: anchorBar.leadingAnchor, constant: 10),
            anchorLabel.centerYAnchor.constraint(equalTo: anchorBar.centerYAnchor),
            anchorLabel.trailingAnchor.constraint(lessThanOrEqualTo: clearQuote.leadingAnchor, constant: -4),
            clearQuote.trailingAnchor.constraint(equalTo: anchorBar.trailingAnchor, constant: -5),
            clearQuote.centerYAnchor.constraint(equalTo: anchorBar.centerYAnchor),
        ])

        chipsStack.orientation = .horizontal
        chipsStack.spacing = 6
        chipsStack.translatesAutoresizingMaskIntoConstraints = false
        for (title, question) in Self.quickAsks {
            let pill = PillButton(title: title)
            pill.target = self
            pill.action = #selector(quickAskTapped(_:))
            pill.identifier = NSUserInterfaceItemIdentifier(question)
            chipsStack.addArrangedSubview(pill)
        }

        composerBox.wantsLayer = true
        composerBox.layer?.cornerRadius = 12
        composerBox.layer?.backgroundColor = Theme.cardBackground.cgColor
        composerBox.layer?.borderWidth = 1
        composerBox.layer?.borderColor = Theme.hairline.cgColor
        composerBox.translatesAutoresizingMaskIntoConstraints = false

        composer.font = Theme.text(13)
        composer.isRichText = false
        composer.allowsUndo = true
        composer.drawsBackground = false
        composer.textContainerInset = NSSize(width: 4, height: 6)
        composer.isVerticallyResizable = true
        composer.isHorizontallyResizable = false
        composer.autoresizingMask = [.width]
        composer.textContainer?.widthTracksTextView = true
        composer.delegate = self
        composer.onSubmit = { [weak self] in self?.submit() }

        composerScroll.documentView = composer
        composerScroll.hasVerticalScroller = true
        composerScroll.drawsBackground = false
        composerScroll.autohidesScrollers = true
        composerScroll.scrollerStyle = .overlay
        composerScroll.borderType = .noBorder
        composerScroll.translatesAutoresizingMaskIntoConstraints = false

        placeholder.font = Theme.text(13)
        placeholder.textColor = .tertiaryLabelColor
        placeholder.translatesAutoresizingMaskIntoConstraints = false

        sendButton.isBordered = false
        sendButton.bezelStyle = .inline
        sendButton.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: "发送")
        sendButton.contentTintColor = Theme.accent
        sendButton.imageScaling = .scaleProportionallyDown
        sendButton.target = self
        sendButton.action = #selector(sendTapped)
        sendButton.translatesAutoresizingMaskIntoConstraints = false

        composerBox.addSubview(placeholder)
        composerBox.addSubview(composerScroll)
        composerBox.addSubview(sendButton)

        chatContainer.addSubview(anchorBar)
        chatContainer.addSubview(chipsStack)
        chatContainer.addSubview(composerBox)

        NSLayoutConstraint.activate([
            transcript.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor),
            transcript.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor),
            transcript.topAnchor.constraint(equalTo: chatContainer.topAnchor),
            transcript.bottomAnchor.constraint(equalTo: anchorBar.topAnchor, constant: -8),

            anchorBar.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor, constant: 12),
            anchorBar.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor, constant: -12),
            anchorBar.bottomAnchor.constraint(equalTo: chipsStack.topAnchor, constant: -8),

            chipsStack.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor, constant: 12),
            chipsStack.trailingAnchor.constraint(lessThanOrEqualTo: chatContainer.trailingAnchor, constant: -12),
            chipsStack.bottomAnchor.constraint(equalTo: composerBox.topAnchor, constant: -8),
            chipsStack.heightAnchor.constraint(equalToConstant: 26),

            composerBox.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor, constant: 12),
            composerBox.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor, constant: -12),
            composerBox.bottomAnchor.constraint(equalTo: chatContainer.bottomAnchor, constant: -12),
            composerBox.heightAnchor.constraint(equalToConstant: 84),

            placeholder.leadingAnchor.constraint(equalTo: composerBox.leadingAnchor, constant: 12),
            placeholder.topAnchor.constraint(equalTo: composerBox.topAnchor, constant: 9),

            composerScroll.leadingAnchor.constraint(equalTo: composerBox.leadingAnchor, constant: 8),
            composerScroll.trailingAnchor.constraint(equalTo: composerBox.trailingAnchor, constant: -40),
            composerScroll.topAnchor.constraint(equalTo: composerBox.topAnchor, constant: 4),
            composerScroll.bottomAnchor.constraint(equalTo: composerBox.bottomAnchor, constant: -4),

            sendButton.trailingAnchor.constraint(equalTo: composerBox.trailingAnchor, constant: -8),
            sendButton.bottomAnchor.constraint(equalTo: composerBox.bottomAnchor, constant: -8),
            sendButton.widthAnchor.constraint(equalToConstant: 26),
            sendButton.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    private func buildNotes() {
        notesText.translatesAutoresizingMaskIntoConstraints = false
        notesContainer.addSubview(notesText)

        notesBar.wantsLayer = true
        notesBar.layer?.backgroundColor = Theme.sidebarBackground.cgColor
        notesBar.translatesAutoresizingMaskIntoConstraints = false

        studyButton.title = "生成学习笔记"
        studyButton.bezelStyle = .rounded
        studyButton.controlSize = .small
        studyButton.font = Theme.text(11, weight: .medium)
        studyButton.target = self
        studyButton.action = #selector(studyTapped)
        studyButton.translatesAutoresizingMaskIntoConstraints = false
        let reportButton = NSButton(title: "学习报告", target: self, action: #selector(reportTapped))
        reportButton.bezelStyle = .rounded
        reportButton.translatesAutoresizingMaskIntoConstraints = false
        notesBar.addSubview(reportButton)
        let levelButton = NSButton(title: "熟悉程度", target: self, action: #selector(levelTapped))
        levelButton.bezelStyle = .rounded
        levelButton.translatesAutoresizingMaskIntoConstraints = false
        notesBar.addSubview(levelButton)
        notesBar.addSubview(studyButton)
        NSLayoutConstraint.activate([
            reportButton.leadingAnchor.constraint(equalTo: notesBar.leadingAnchor),
            reportButton.centerYAnchor.constraint(equalTo: notesBar.centerYAnchor),
            levelButton.leadingAnchor.constraint(equalTo: reportButton.trailingAnchor, constant: 4),
            levelButton.centerYAnchor.constraint(equalTo: notesBar.centerYAnchor),
            levelButton.trailingAnchor.constraint(lessThanOrEqualTo: studyButton.leadingAnchor, constant: -4),
        ])
        notesContainer.addSubview(notesBar)

        NSLayoutConstraint.activate([
            notesText.leadingAnchor.constraint(equalTo: notesContainer.leadingAnchor),
            notesText.trailingAnchor.constraint(equalTo: notesContainer.trailingAnchor),
            notesText.topAnchor.constraint(equalTo: notesContainer.topAnchor),
            notesText.bottomAnchor.constraint(equalTo: notesBar.topAnchor, constant: -6),

            notesBar.leadingAnchor.constraint(equalTo: notesContainer.leadingAnchor, constant: 12),
            notesBar.trailingAnchor.constraint(equalTo: notesContainer.trailingAnchor, constant: -12),
            notesBar.bottomAnchor.constraint(equalTo: notesContainer.bottomAnchor, constant: -10),
            notesBar.heightAnchor.constraint(equalToConstant: 28),
            studyButton.trailingAnchor.constraint(equalTo: notesBar.trailingAnchor),
            studyButton.centerYAnchor.constraint(equalTo: notesBar.centerYAnchor),
        ])
    }

    // MARK: - Public API

    func setDocument(_ doc: PaperDoc?) {
        streamTimer?.invalidate(); streamTimer = nil
        isStreaming = false
        streamStart = -1
        streamBuffer = ""
        self.doc = doc
        threads = []
        highlights = []
        studyNotes = nil
        pendingQuote = nil
        updateAnchorBar()
        renderChat()
        renderNotes()
        statusLabel.stringValue = ""
        updatePlaceholder()
    }

    func setThreads(_ threads: [AskThread]) {
        self.threads = threads
        streamStart = -1
        renderChat()
        renderNotes()
    }

    func setHighlights(_ highlights: [PaperHighlight]) {
        self.highlights = highlights
        renderNotes()
    }

    func setStudyNotes(_ text: String?) {
        studyNotes = text
        studyRunning = false
        studyButton.isEnabled = true
        renderNotes()
    }

    func setStudyGenerating(_ generating: Bool) {
        studyRunning = generating
        studyButton.isEnabled = !generating
        studyButton.title = generating ? "生成中…" : (studyNotes == nil ? "生成学习笔记" : "重新生成")
        renderNotes()
    }

    func setStudyDraft(_ markdown: String) {
        studyNotes = markdown
        studyRunning = true
        renderNotes()
    }

    func setStatus(_ text: String) { statusLabel.stringValue = text }

    func focusComposer(with quote: String?, page: Int?) {
        pendingQuote = quote
        updateAnchorBar()
        selectTab(0)
        window?.makeFirstResponder(composer)
        _ = page
    }

    func selectTab(_ index: Int) {
        selectedTab = index
        updateTabAppearance()
        chatContainer.isHidden = index != 0
        notesContainer.isHidden = index != 1
        if index == 1 { renderNotes() }
    }

    var isAnswering: Bool { isStreaming }

    // MARK: - Chat rendering

    private func renderChat() {
        transcript.render(threads: threads, draft: streamBuffer, question: pendingQuestion,
                          pending: streamStart >= 0, streaming: isStreaming, page: pendingPage, error: failedStream)
    }

    func beginAnswer(page: Int?, question: String = "") {
        pendingQuestion = question
        pendingPage = page ?? currentPage
        streamStart = 0
        streamBuffer = ""
        failedStream = false
        isStreaming = true
        updateSendState()
        renderChat()
    }
    func appendAnswer(_ delta: String) {
        streamBuffer += delta
        if streamTimer == nil {
            streamTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in self?.renderChat() }
        }
    }
    func finishAnswer(markdown: String) {
        streamTimer?.invalidate(); streamTimer = nil
        isStreaming = false
        streamBuffer = markdown
        updateSendState()
        renderChat()
    }
    func failAnswer(_ message: String) {
        streamTimer?.invalidate(); streamTimer = nil
        isStreaming = false
        streamStart = 0
        streamBuffer = message
        failedStream = true
        updateSendState()
        renderChat()
    }
    func snapshotChat(to url: URL, completion: @escaping () -> Void) { transcript.snapshot(to: url, completion: completion) }

    // MARK: - Notes rendering

    private func renderNotes() {
        guard let storage = notesText.storage else { return }
        let out = NSMutableAttributedString()

        out.append(NSAttributedString(string: "学习笔记", attributes: [
            .font: Theme.text(14, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: Theme.paragraph(spacing: 4),
        ]))
        out.append(NSAttributedString(string: studyRunning ? "整理中…\n\n" : "\n", attributes: [
            .font: Theme.text(11),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .paragraphStyle: Theme.paragraph(spacing: 6),
        ]))
        if let studyNotes, !studyNotes.isEmpty {
            out.append(Markdown.render(studyNotes, baseSize: 12.4))
            out.append(NSAttributedString(string: "\n", attributes: [.font: Theme.text(6)]))
        } else if !studyRunning {
            out.append(NSAttributedString(string: "读完这篇后点下面的「生成学习笔记」，我会把划过的重点和问过的问题整理成可复习的结构。\n", attributes: [
                .font: Theme.text(12),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .paragraphStyle: Theme.paragraph(spacing: 12, lineSpacing: 4.5),
            ]))
        }

        out.append(NSAttributedString(string: "标注与提问（\(highlights.count)）\n", attributes: [
            .font: Theme.text(12, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: Theme.paragraph(spacing: 6, before: 12),
        ]))

        if highlights.isEmpty {
            out.append(NSAttributedString(string: "还没有标注。选中文字点「划线」或「提问」，会出现在这里。\n", attributes: [
                .font: Theme.text(11.5),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .paragraphStyle: Theme.paragraph(spacing: 8, lineSpacing: 4),
            ]))
        }

        for (index, highlight) in highlights.sorted(by: { ($0.page, $0.createdAt) < ($1.page, $1.createdAt) }).enumerated() {
            let thread = highlight.threadID.flatMap { id in threads.first { $0.id == id } }
            let kind = highlight.style == .region ? "框选" : "划线"
            out.append(NSAttributedString(string: "\(index + 1). \(kind) · p.\(highlight.page + 1)  ", attributes: [
                .font: Theme.text(10.5, weight: .semibold),
                .foregroundColor: highlight.style == .region ? NSColor.systemBlue : NSColor.secondaryLabelColor,
                .paragraphStyle: Theme.paragraph(spacing: 2, lineSpacing: 3),
            ]))
            out.append(NSAttributedString(string: "跳转\n", attributes: [
                .font: Theme.text(10.5, weight: .medium),
                .foregroundColor: Theme.accent,
                .link: "page://\(highlight.page)",
                .paragraphStyle: Theme.paragraph(spacing: 4, lineSpacing: 3),
            ]))
            let quote = highlight.quote.isEmpty ? "（框选区域）" : highlight.quote
            out.append(NSAttributedString(string: "❝ " + String(quote.prefix(140)) + "\n", attributes: [
                .font: Theme.text(11.2),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: Theme.paragraph(spacing: 4, lineSpacing: 3.5),
            ]))
            if let thread {
                out.append(NSAttributedString(string: "Q：" + thread.question + "\n", attributes: [
                    .font: Theme.text(11.5, weight: .medium),
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: Theme.paragraph(spacing: 3, lineSpacing: 3.5),
                ]))
            }
            out.append(NSAttributedString(string: "\n", attributes: [.font: Theme.text(6)]))
        }

        storage.setAttributedString(out)
        notesText.textView.linkTextAttributes = [.foregroundColor: Theme.accent]
    }

    // MARK: - Actions

    @objc private func tabTapped(_ sender: NSButton) { selectTab(sender.tag) }

    @objc private func sendTapped() {
        if isStreaming { delegate?.assistantDidStop() } else { submit() }
    }

    private func submit() {
        let text = composer.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        composer.string = ""
        updatePlaceholder()
        delegate?.assistantDidSubmit(text)
    }

    @objc private func quickAskTapped(_ sender: PillButton) {
        guard !isStreaming, let question = sender.identifier?.rawValue else { return }
        delegate?.assistantDidTapQuickAsk(question)
    }

    @objc private func reportTapped() { delegate?.assistantDidRequestReport() }
    @objc private func levelTapped() { delegate?.assistantDidRequestReadingLevel() }
    @objc private func studyTapped() { delegate?.assistantDidRequestStudyNotes() }

    @objc private func clearQuoteTapped() {
        pendingQuote = nil
        updateAnchorBar()
        delegate?.assistantDidClearQuote()
    }

    @objc private func settingsTapped() { delegate?.assistantDidRequestSettings() }

    // MARK: - Helpers

    private func updateAnchorBar() {
        if let quote = pendingQuote, !quote.isEmpty {
            let flat = quote.replacingOccurrences(of: "\n", with: " ")
            let prefix = flat.count > 30 ? String(flat.prefix(30)) + "…" : flat
            anchorLabel.stringValue = "❝ 引用 · \(prefix)"
            anchorBar.isHidden = false
        } else {
            anchorBar.isHidden = true
        }
    }

    private func updatePlaceholder() {
        placeholder.isHidden = !composer.string.isEmpty
    }

    private func updateSendState() {
        sendButton.image = NSImage(systemSymbolName: isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill",
                                   accessibilityDescription: isStreaming ? "停止" : "发送")
        sendButton.contentTintColor = isStreaming ? .systemRed : Theme.accent
        chipsStack.isHidden = isStreaming
    }

    func textDidChange(_ notification: Notification) {
        if let view = notification.object as? NSTextView, view === composer {
            updatePlaceholder()
        }
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let string = link as? String, string.hasPrefix("page://"),
              let page = Int(string.replacingOccurrences(of: "page://", with: "")) else { return false }
        delegate?.assistantDidJumpToPage(page)
        return true
    }

    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    var pendingQuoteValue: String? { pendingQuote }
}
