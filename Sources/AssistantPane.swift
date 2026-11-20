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
    var onPickPaper: ((URL) -> Void)?
    var onLounge: (() -> Void)?

    private let header = NSView()
    private let avatarView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "论文伴侣")
    private let contextLabel = NSTextField(labelWithString: "还没打开论文，先随便聊聊")
    private let libraryButton = NSButton()
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

    private var isStreaming = false
    private var streamStart = -1
    private var streamBuffer = ""
    private var streamTimer: Timer?
    private var selectedTab = 0

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
        layer?.cornerRadius = 18
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = Theme.hairline.cgColor
        layer?.backgroundColor = Theme.cardBackground.cgColor

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
            header.heightAnchor.constraint(equalToConstant: 68),

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
        header.layer?.backgroundColor = Theme.cardBackground.cgColor

        avatarView.image = CompanionArt.avatar
        avatarView.imageScaling = .scaleProportionallyUpOrDown
        avatarView.wantsLayer = true
        avatarView.layer?.cornerRadius = 16
        avatarView.layer?.masksToBounds = true
        avatarView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = Theme.text(14, weight: .semibold)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contextLabel.font = Theme.text(11)
        contextLabel.textColor = .secondaryLabelColor
        contextLabel.lineBreakMode = .byTruncatingTail
        contextLabel.translatesAutoresizingMaskIntoConstraints = false

        libraryButton.title = "书库"
        libraryButton.isBordered = false
        libraryButton.font = Theme.text(11, weight: .medium)
        libraryButton.contentTintColor = Theme.accent
        libraryButton.image = NSImage(systemSymbolName: "books.vertical", accessibilityDescription: "书库")
        libraryButton.imagePosition = .imageLeading
        libraryButton.imageScaling = .scaleProportionallyDown
        libraryButton.toolTip = "换成另一篇论文的对话，或先随便聊聊"
        libraryButton.target = self
        libraryButton.action = #selector(showRoster)
        libraryButton.translatesAutoresizingMaskIntoConstraints = false

        configureTab(chatTab, title: "对话", tag: 0)
        configureTab(notesTab, title: "笔记", tag: 1)

        statusLabel.font = Theme.text(10)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.alignment = .right
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        settingsButton.iconSetup("slider.horizontal.3", tip: "设置", target: self, action: #selector(settingsTapped), size: 24)

        for view in [avatarView, nameLabel, contextLabel, libraryButton, chatTab, notesTab, statusLabel, settingsButton] { header.addSubview(view) }

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            avatarView.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 32),
            avatarView.heightAnchor.constraint(equalToConstant: 32),

            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 8),
            nameLabel.topAnchor.constraint(equalTo: header.topAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: chatTab.leadingAnchor, constant: -8),

            contextLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            contextLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            contextLabel.trailingAnchor.constraint(lessThanOrEqualTo: libraryButton.leadingAnchor, constant: -8),

            libraryButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            libraryButton.centerYAnchor.constraint(equalTo: contextLabel.centerYAnchor),

            settingsButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -8),
            settingsButton.topAnchor.constraint(equalTo: header.topAnchor, constant: 8),

            notesTab.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -2),
            notesTab.centerYAnchor.constraint(equalTo: settingsButton.centerYAnchor),
            notesTab.heightAnchor.constraint(equalToConstant: 24),
            notesTab.widthAnchor.constraint(equalToConstant: 46),

            chatTab.trailingAnchor.constraint(equalTo: notesTab.leadingAnchor, constant: -2),
            chatTab.centerYAnchor.constraint(equalTo: settingsButton.centerYAnchor),
            chatTab.heightAnchor.constraint(equalToConstant: 24),
            chatTab.widthAnchor.constraint(equalToConstant: 46),

            statusLabel.trailingAnchor.constraint(equalTo: chatTab.leadingAnchor, constant: -4),
            statusLabel.centerYAnchor.constraint(equalTo: settingsButton.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 4),
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

        NSLayoutConstraint.activate([
            transcript.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor),
            transcript.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor),
            transcript.topAnchor.constraint(equalTo: chatContainer.topAnchor),
            transcript.bottomAnchor.constraint(equalTo: chatContainer.bottomAnchor),
        ])
    }

    func setChatHeading(paper: String?) {
        contextLabel.stringValue = (paper?.isEmpty == false) ? paper! : "还没打开论文，先随便聊聊"
    }

    @objc private func showRoster() {
        let menu = NSMenu()
        let lounge = NSMenuItem(title: "随便聊聊", action: #selector(pickLounge), keyEquivalent: "")
        lounge.target = self
        menu.addItem(lounge)
        menu.addItem(.separator())
        let papers = ShelfStore.loadMerged().papers.sorted {
            ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast)
        }
        if papers.isEmpty {
            let empty = NSMenuItem(title: "书库还是空的", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for paper in papers.prefix(16) {
            let item = NSMenuItem(title: paper.title, action: #selector(pickPaper(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = paper.path
            item.toolTip = paper.path
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: libraryButton.bounds.height), in: libraryButton)
    }

    @objc private func pickLounge() { onLounge?() }

    @objc private func pickPaper(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        onPickPaper?(URL(fileURLWithPath: path))
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
        setChatHeading(paper: doc?.title)
        threads = []
        highlights = []
        studyNotes = nil
        renderChat()
        renderNotes()
        statusLabel.stringValue = ""
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
        pendingPage = page ?? -1
        streamStart = 0
        streamBuffer = ""
        failedStream = false
        isStreaming = true
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
        renderChat()
    }
    func failAnswer(_ message: String) {
        streamTimer?.invalidate(); streamTimer = nil
        isStreaming = false
        streamStart = 0
        streamBuffer = message
        failedStream = true
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

    @objc private func reportTapped() { delegate?.assistantDidRequestReport() }
    @objc private func levelTapped() { delegate?.assistantDidRequestReadingLevel() }
    @objc private func studyTapped() { delegate?.assistantDidRequestStudyNotes() }

    @objc private func settingsTapped() { delegate?.assistantDidRequestSettings() }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let string = link as? String, string.hasPrefix("page://"),
              let page = Int(string.replacingOccurrences(of: "page://", with: "")) else { return false }
        delegate?.assistantDidJumpToPage(page)
        return true
    }

}
