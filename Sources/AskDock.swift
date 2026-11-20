import AppKit

/// The question box under the paper. Asking opens the chat sidebar.
final class AskDock: NSView {
    var onSubmit: ((String) -> Void)?
    var onQuickAsk: ((String) -> Void)?
    var onStop: (() -> Void)?
    var onClearQuote: (() -> Void)?
    var onOpenChat: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onAttach: (() -> Void)?
    var onClearAttachment: (() -> Void)?

    private let quoteBar = NSView()
    private let quoteLabel = NSTextField(labelWithString: "")
    private var quoteHeight: NSLayoutConstraint!
    private let chipsStack = NSStackView()
    private var chipsHeight: NSLayoutConstraint!
    private let detailControl = NSSegmentedControl(labels: ["精简", "详细"], trackingMode: .selectOne, target: nil, action: nil)
    private let composerBox = NSView()
    private let composer = NSTextField()
    private let modelButton = NSButton()
    private let sendButton = NSButton()
    private let attachButton = NSButton()
    private let attachmentBar = NSView()
    private let attachmentLabel = NSTextField(labelWithString: "")
    private var attachmentHeight: NSLayoutConstraint!
    private let popover = NSPopover()
    private let providerPopup = NSPopUpButton()
    private let modelPopup = NSPopUpButton()
    private let customModel = NSTextField()
    private let effortSlider = EffortSlider()
    private let effortTitle = NSTextField(labelWithString: "高")
    private let popoverModel = NSButton()
    private var pendingQuote: String?
    private var streaming = false
    private var paperMode = false
    private var dockHeight: NSLayoutConstraint!

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

    func focus(quote: String?) {
        pendingQuote = quote
        updateQuote()
        window?.makeFirstResponder(composer)
    }

    func clearQuote() {
        pendingQuote = nil
        updateQuote()
    }

    func setStreaming(_ streaming: Bool) {
        self.streaming = streaming
        applySendChrome()
        chipsStack.isHidden = streaming || !paperMode
    }

    private func applySendChrome() {
        let symbol = streaming ? "stop.fill" : "arrow.up"
        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        sendButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: streaming ? "停止" : "发送")?
            .withSymbolConfiguration(config)
        sendButton.contentTintColor = .white
        sendButton.layer?.backgroundColor = (streaming ? NSColor.systemRed : NSColor(calibratedRed: 0.23, green: 0.48, blue: 0.96, alpha: 1)).cgColor
    }

    func setConversationCount(_ count: Int) {}

    @discardableResult
    func focusComposer() -> Bool {
        guard let window else { return false }
        window.makeKeyAndOrderFront(nil)
        return window.makeFirstResponder(composer)
    }

    /// Paper mode shows the quick asks. The lounge is an open conversation with no paper open.
    func setMode(paper: Bool) {
        paperMode = paper
        composer.placeholderString = paper ? "问这篇论文…" : "跟伴侣聊聊…"
        chipsStack.isHidden = !paper || streaming
        detailControl.isHidden = !paper
        chipsHeight?.constant = paper ? 26 : 0
        fitHeight()
    }

    func setAttachment(_ name: String?) {
        if let name, !name.isEmpty {
            attachmentLabel.stringValue = "附件 · " + name
            attachmentBar.isHidden = false
            attachmentHeight?.constant = 22
        } else {
            attachmentBar.isHidden = true
            attachmentHeight?.constant = 0
        }
        fitHeight()
    }

    private func fitHeight() {
        var height: CGFloat = 72
        if paperMode { height += 34 }
        if (quoteHeight?.constant ?? 0) > 0 { height += 30 }
        if (attachmentHeight?.constant ?? 0) > 0 { height += 28 }
        dockHeight?.constant = height
    }

    func refreshModelChip() {
        let model = Prefs.shared.model
        let short = model.split(separator: "/").last.map(String.init) ?? model
        let visible = short.count > 22 ? String(short.prefix(22)) + "…" : short
        modelButton.title = "  \(Prefs.shared.reasoningEffort.title)  ▾  "
        effortTitle.stringValue = Prefs.shared.reasoningEffort.title
        popoverModel.title = visible + "  ›"
        if let index = ReasoningEffort.allCases.firstIndex(of: Prefs.shared.reasoningEffort) {
            effortSlider.setIndex(index)
        }
    }

    func debugSelectDetail(detailed: Bool) {
        detailControl.selectedSegment = detailed ? 1 : 0
        Prefs.shared.answerDetail = detailed ? .detailed : .concise
    }

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = Theme.paperBackground.cgColor

        let line = SeparatorLine()
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)

        quoteBar.wantsLayer = true
        quoteBar.layer?.masksToBounds = true
        quoteBar.layer?.cornerRadius = 8
        quoteBar.layer?.backgroundColor = Theme.accent.withAlphaComponent(0.12).cgColor
        quoteBar.translatesAutoresizingMaskIntoConstraints = false
        quoteLabel.font = Theme.text(11)
        quoteLabel.textColor = .secondaryLabelColor
        quoteLabel.lineBreakMode = .byTruncatingTail
        quoteLabel.translatesAutoresizingMaskIntoConstraints = false
        let clear = NSButton()
        clear.iconSetup("xmark.circle.fill", tip: "取消引用", target: self, action: #selector(clearQuoteTapped), size: 18)
        clear.contentTintColor = .tertiaryLabelColor
        quoteBar.addSubview(quoteLabel)
        quoteBar.addSubview(clear)
        quoteHeight = quoteBar.heightAnchor.constraint(equalToConstant: 0)
        quoteHeight.priority = .defaultHigh
        quoteHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            quoteHeight,
            quoteLabel.leadingAnchor.constraint(equalTo: quoteBar.leadingAnchor, constant: 10),
            quoteLabel.centerYAnchor.constraint(equalTo: quoteBar.centerYAnchor),
            quoteLabel.trailingAnchor.constraint(lessThanOrEqualTo: clear.leadingAnchor, constant: -4),
            clear.trailingAnchor.constraint(equalTo: quoteBar.trailingAnchor, constant: -5),
            clear.centerYAnchor.constraint(equalTo: quoteBar.centerYAnchor),
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

        detailControl.segmentStyle = .rounded
        detailControl.font = Theme.text(11, weight: .medium)
        detailControl.selectedSegment = Prefs.shared.answerDetail == .detailed ? 1 : 0
        detailControl.setToolTip("先给结论，大约 400 字", forSegment: 0)
        detailControl.setToolTip("把推理、符号和证据边界写完整", forSegment: 1)
        detailControl.target = self
        detailControl.action = #selector(detailChanged)
        detailControl.translatesAutoresizingMaskIntoConstraints = false

        attachmentBar.wantsLayer = true
        attachmentBar.layer?.masksToBounds = true
        attachmentBar.layer?.cornerRadius = 11
        attachmentBar.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        attachmentBar.translatesAutoresizingMaskIntoConstraints = false
        attachmentLabel.font = Theme.text(11, weight: .medium)
        attachmentLabel.textColor = .secondaryLabelColor
        attachmentLabel.lineBreakMode = .byTruncatingTail
        attachmentLabel.translatesAutoresizingMaskIntoConstraints = false
        let clearAttachment = NSButton()
        clearAttachment.iconSetup("xmark.circle.fill", tip: "移除附件", target: self, action: #selector(clearAttachmentTapped), size: 16)
        clearAttachment.contentTintColor = .tertiaryLabelColor
        attachmentBar.addSubview(attachmentLabel)
        attachmentBar.addSubview(clearAttachment)
        attachmentHeight = attachmentBar.heightAnchor.constraint(equalToConstant: 0)
        attachmentHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            attachmentHeight,
            attachmentLabel.leadingAnchor.constraint(equalTo: attachmentBar.leadingAnchor, constant: 10),
            attachmentLabel.centerYAnchor.constraint(equalTo: attachmentBar.centerYAnchor),
            attachmentLabel.trailingAnchor.constraint(lessThanOrEqualTo: clearAttachment.leadingAnchor, constant: -4),
            clearAttachment.trailingAnchor.constraint(equalTo: attachmentBar.trailingAnchor, constant: -4),
            clearAttachment.centerYAnchor.constraint(equalTo: attachmentBar.centerYAnchor),
        ])

        composerBox.wantsLayer = true
        composerBox.layer?.cornerRadius = 18
        composerBox.layer?.backgroundColor = Theme.cardBackground.cgColor
        composerBox.layer?.borderWidth = 1
        composerBox.layer?.borderColor = Theme.hairline.cgColor
        composerBox.translatesAutoresizingMaskIntoConstraints = false

        composer.font = Theme.text(13)
        composer.placeholderString = "跟伴侣聊聊…"
        composer.isBordered = false
        composer.isBezeled = false
        composer.drawsBackground = false
        composer.focusRingType = .none
        composer.textColor = .labelColor
        composer.alignment = .left
        composer.target = self
        composer.action = #selector(sendTapped)
        if let cell = composer.cell as? NSTextFieldCell {
            cell.font = Theme.text(13)
            cell.usesSingleLineMode = true
            cell.isScrollable = true
            cell.sendsActionOnEndEditing = false
            cell.lineBreakMode = .byClipping
        }
        composer.setContentHuggingPriority(.required, for: .vertical)
        composer.translatesAutoresizingMaskIntoConstraints = false

        modelButton.isBordered = false
        modelButton.font = Theme.text(11, weight: .medium)
        modelButton.contentTintColor = .secondaryLabelColor
        modelButton.wantsLayer = true
        modelButton.layer?.cornerRadius = 12
        modelButton.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        modelButton.toolTip = "推理强度和模型"
        modelButton.target = self
        modelButton.action = #selector(showModels)
        modelButton.translatesAutoresizingMaskIntoConstraints = false
        modelButton.setContentHuggingPriority(.required, for: .horizontal)
        refreshModelChip()

        sendButton.isBordered = false
        sendButton.imagePosition = .imageOnly
        sendButton.wantsLayer = true
        sendButton.layer?.masksToBounds = true
        sendButton.imageScaling = .scaleProportionallyDown
        applySendChrome()
        sendButton.target = self
        sendButton.action = #selector(sendTapped)
        sendButton.translatesAutoresizingMaskIntoConstraints = false

        attachButton.isBordered = false
        attachButton.image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: "添加附件")
        attachButton.contentTintColor = .secondaryLabelColor
        attachButton.imageScaling = .scaleProportionallyDown
        attachButton.toolTip = "添加图片，或打开一篇论文"
        attachButton.target = self
        attachButton.action = #selector(attachTapped)
        attachButton.translatesAutoresizingMaskIntoConstraints = false

        composerBox.addSubview(composer)
        composerBox.addSubview(modelButton)
        composerBox.addSubview(sendButton)
        addSubview(quoteBar)
        addSubview(chipsStack)
        addSubview(detailControl)
        addSubview(attachmentBar)
        composerBox.addSubview(attachButton)
        addSubview(composerBox)
        chipsHeight = chipsStack.heightAnchor.constraint(equalToConstant: 0)
        chipsHeight.priority = .defaultHigh
        dockHeight = heightAnchor.constraint(equalToConstant: 72)

        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.topAnchor.constraint(equalTo: topAnchor),
            line.heightAnchor.constraint(equalToConstant: 1).priority(.defaultHigh),

            quoteBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            quoteBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            quoteBar.topAnchor.constraint(equalTo: topAnchor, constant: 8).priority(.defaultHigh),

            chipsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            chipsStack.trailingAnchor.constraint(lessThanOrEqualTo: detailControl.leadingAnchor, constant: -8),
            chipsStack.topAnchor.constraint(equalTo: quoteBar.bottomAnchor, constant: 8).priority(.defaultHigh),

            detailControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            detailControl.centerYAnchor.constraint(equalTo: chipsStack.centerYAnchor),
            detailControl.widthAnchor.constraint(equalToConstant: 108),

            attachmentBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            attachmentBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            attachmentBar.topAnchor.constraint(equalTo: chipsStack.bottomAnchor, constant: 6).priority(.defaultHigh),

            composerBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            composerBox.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            composerBox.topAnchor.constraint(equalTo: attachmentBar.bottomAnchor, constant: 8).priority(.defaultHigh),
            composerBox.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            composerBox.heightAnchor.constraint(equalToConstant: 44),

            attachButton.leadingAnchor.constraint(equalTo: composerBox.leadingAnchor, constant: 8),
            attachButton.centerYAnchor.constraint(equalTo: composerBox.centerYAnchor),
            attachButton.widthAnchor.constraint(equalToConstant: 26),
            attachButton.heightAnchor.constraint(equalToConstant: 26),

            composer.leadingAnchor.constraint(equalTo: attachButton.trailingAnchor, constant: 2),
            composer.trailingAnchor.constraint(equalTo: modelButton.leadingAnchor, constant: -8),
            composer.centerYAnchor.constraint(equalTo: composerBox.centerYAnchor),
            composer.heightAnchor.constraint(equalToConstant: 22),

            modelButton.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            modelButton.centerYAnchor.constraint(equalTo: composerBox.centerYAnchor),
            modelButton.heightAnchor.constraint(equalToConstant: 24),

            sendButton.trailingAnchor.constraint(equalTo: composerBox.trailingAnchor, constant: -12),
            sendButton.centerYAnchor.constraint(equalTo: composerBox.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 20),
            sendButton.heightAnchor.constraint(equalToConstant: 20),
            chipsHeight,
            dockHeight,
        ])
        buildPopover()
        updateQuote()
        setAttachment(nil)
        setMode(paper: false)
    }

    private func buildPopover() {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 210))
        let bolt = NSImageView()
        bolt.image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)
        bolt.contentTintColor = .secondaryLabelColor
        bolt.translatesAutoresizingMaskIntoConstraints = false
        effortTitle.font = Theme.text(18, weight: .semibold)
        effortTitle.textColor = Theme.accent
        effortTitle.alignment = .center
        effortTitle.translatesAutoresizingMaskIntoConstraints = false
        let reset = NSButton()
        reset.iconSetup("arrow.clockwise", tip: "回到高", target: self, action: #selector(resetEffort), size: 22)
        reset.contentTintColor = .tertiaryLabelColor
        popoverModel.isBordered = false
        popoverModel.font = Theme.text(13)
        popoverModel.contentTintColor = .secondaryLabelColor
        popoverModel.target = self
        popoverModel.action = #selector(focusModelPopup)
        popoverModel.translatesAutoresizingMaskIntoConstraints = false
        effortSlider.onChange = { [weak self] index in self?.applyEffort(index) }
        effortSlider.translatesAutoresizingMaskIntoConstraints = false
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged)
        providerPopup.controlSize = .small
        providerPopup.font = Theme.text(11)
        modelPopup.target = self
        modelPopup.action = #selector(modelChanged)
        modelPopup.controlSize = .small
        modelPopup.font = Theme.text(11)
        customModel.placeholderString = "模型名"
        customModel.font = Theme.mono(11)
        customModel.target = self
        customModel.action = #selector(customModelChanged)
        let settings = NSButton(title: "API Key…", target: self, action: #selector(openSettings))
        settings.bezelStyle = .rounded
        settings.controlSize = .small
        settings.font = Theme.text(11)
        for view in [bolt, effortTitle, reset, popoverModel, effortSlider, providerPopup, modelPopup, customModel, settings] {
            view.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(view)
        }
        NSLayoutConstraint.activate([
            bolt.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 16),
            bolt.topAnchor.constraint(equalTo: host.topAnchor, constant: 16),
            bolt.widthAnchor.constraint(equalToConstant: 16),
            bolt.heightAnchor.constraint(equalToConstant: 16),
            effortTitle.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            effortTitle.centerYAnchor.constraint(equalTo: bolt.centerYAnchor),
            reset.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -12),
            reset.centerYAnchor.constraint(equalTo: bolt.centerYAnchor),

            popoverModel.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            popoverModel.topAnchor.constraint(equalTo: effortTitle.bottomAnchor, constant: 2),

            effortSlider.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 18),
            effortSlider.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -18),
            effortSlider.topAnchor.constraint(equalTo: popoverModel.bottomAnchor, constant: 10),
            effortSlider.heightAnchor.constraint(equalToConstant: 28),

            providerPopup.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 16),
            providerPopup.topAnchor.constraint(equalTo: effortSlider.bottomAnchor, constant: 12),
            providerPopup.widthAnchor.constraint(equalToConstant: 110),
            modelPopup.leadingAnchor.constraint(equalTo: providerPopup.trailingAnchor, constant: 8),
            modelPopup.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -16),
            modelPopup.centerYAnchor.constraint(equalTo: providerPopup.centerYAnchor),
            customModel.leadingAnchor.constraint(equalTo: modelPopup.leadingAnchor),
            customModel.trailingAnchor.constraint(equalTo: modelPopup.trailingAnchor),
            customModel.centerYAnchor.constraint(equalTo: modelPopup.centerYAnchor),

            settings.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 16),
            settings.topAnchor.constraint(equalTo: providerPopup.bottomAnchor, constant: 8),
            settings.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -10),
        ])
        popover.contentSize = NSSize(width: 320, height: 188)
        popover.behavior = .transient
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = host
    }

    private func reloadPopover() {
        providerPopup.removeAllItems()
        for provider in LLMProviders.all {
            providerPopup.addItem(withTitle: provider.name)
            providerPopup.lastItem?.representedObject = provider.id
        }
        let current = Prefs.shared.providerID
        if let index = LLMProviders.all.firstIndex(where: { $0.id == current }) {
            providerPopup.selectItem(at: index)
        }
        let provider = LLMProviders.provider(current)
        modelPopup.removeAllItems()
        var models = provider.models
        if !Prefs.shared.model.isEmpty, !models.contains(Prefs.shared.model) {
            models.insert(Prefs.shared.model, at: 0)
        }
        modelPopup.isHidden = models.isEmpty
        customModel.isHidden = !models.isEmpty
        if models.isEmpty {
            customModel.stringValue = Prefs.shared.model
        } else {
            modelPopup.addItems(withTitles: models)
            modelPopup.selectItem(withTitle: Prefs.shared.model)
        }
        if let index = ReasoningEffort.allCases.firstIndex(of: Prefs.shared.reasoningEffort) {
            effortSlider.setIndex(index)
        }
        refreshModelChip()
    }

    private func saveChoice(providerID: String, model: String) {
        let provider = LLMProviders.provider(providerID)
        let saved = Prefs.shared.savedConfig(providerID)
        let base = saved?.baseURL ?? (provider.baseURL.isEmpty ? Prefs.shared.baseURL : provider.baseURL)
        Prefs.shared.providerID = providerID
        if !base.isEmpty { Prefs.shared.baseURL = base }
        let chosen = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = chosen.isEmpty ? (provider.models.first ?? Prefs.shared.model) : chosen
        if !resolved.isEmpty { Prefs.shared.model = resolved }
        Prefs.shared.saveConfig(providerID, baseURL: Prefs.shared.baseURL, model: Prefs.shared.model)
        refreshModelChip()
    }

    private func updateQuote() {
        if let quote = pendingQuote, !quote.isEmpty {
            let flat = quote.replacingOccurrences(of: "\n", with: " ")
            quoteLabel.stringValue = "❝ " + (flat.count > 42 ? String(flat.prefix(42)) + "…" : flat)
            quoteBar.isHidden = false
            quoteHeight.constant = 26
        } else {
            quoteBar.isHidden = true
            quoteHeight.constant = 0
        }
        fitHeight()
    }

    private func submit() {
        guard !streaming else { return }
        let text = composer.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        composer.stringValue = ""
        onSubmit?(text)
    }

    @objc private func sendTapped() {
        if streaming { onStop?() } else { submit() }
    }

    @objc private func quickAskTapped(_ sender: PillButton) {
        guard !streaming, let question = sender.identifier?.rawValue else { return }
        onQuickAsk?(question)
    }

    @objc private func clearQuoteTapped() {
        clearQuote()
        onClearQuote?()
    }

    @objc private func attachTapped() { onAttach?() }

    @objc private func clearAttachmentTapped() {
        setAttachment(nil)
        onClearAttachment?()
    }

    @objc private func openChat() { onOpenChat?() }
    @objc private func openSettings() {
        popover.performClose(nil)
        onOpenSettings?()
    }

    @objc private func detailChanged() {
        Prefs.shared.answerDetail = detailControl.selectedSegment == 1 ? .detailed : .concise
    }

    @objc private func showModels() {
        reloadPopover()
        popover.show(relativeTo: modelButton.bounds, of: modelButton, preferredEdge: .maxY)
    }

    @objc private func providerChanged() {
        let id = providerPopup.selectedItem?.representedObject as? String ?? "deepseek"
        let provider = LLMProviders.provider(id)
        let model = Prefs.shared.savedConfig(id)?.model ?? provider.models.first ?? ""
        saveChoice(providerID: id, model: model)
        reloadPopover()
    }

    @objc private func modelChanged() {
        saveChoice(providerID: Prefs.shared.providerID, model: modelPopup.titleOfSelectedItem ?? "")
    }

    @objc private func customModelChanged() {
        saveChoice(providerID: Prefs.shared.providerID, model: customModel.stringValue)
    }

    @objc private func resetEffort() { applyEffort(ReasoningEffort.allCases.firstIndex(of: .high) ?? 2) }

    @objc private func focusModelPopup() {
        window?.makeFirstResponder(modelPopup.isHidden ? customModel : modelPopup)
    }

    private func applyEffort(_ index: Int) {
        guard index >= 0, index < ReasoningEffort.allCases.count else { return }
        Prefs.shared.reasoningEffort = ReasoningEffort.allCases[index]
        effortSlider.setIndex(index)
        refreshModelChip()
    }

    override func layout() {
        super.layout()
        composerBox.layer?.cornerRadius = composerBox.bounds.height / 2
        sendButton.layer?.cornerRadius = sendButton.bounds.height / 2
    }
}

/// Four-stop reasoning slider: blue track up to a white knob, gray after it.
final class EffortSlider: NSView {
    var onChange: ((Int) -> Void)?
    private var index = 2
    private let stops = 4

    func setIndex(_ value: Int) {
        index = min(stops - 1, max(0, value))
        needsDisplay = true
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = 11
        let track = NSRect(x: inset, y: bounds.midY - 3, width: bounds.width - inset * 2, height: 6)
        let knobX = inset + track.width * CGFloat(index) / CGFloat(stops - 1)
        NSColor(calibratedWhite: 0.86, alpha: 1).setFill()
        NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).fill()
        NSColor(calibratedRed: 0.23, green: 0.48, blue: 0.96, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: max(6, knobX - track.minX), height: track.height), xRadius: 3, yRadius: 3).fill()
        for step in 0..<stops {
            let x = inset + track.width * CGFloat(step) / CGFloat(stops - 1)
            let dot = NSRect(x: x - 3, y: bounds.midY - 3, width: 6, height: 6)
            (step <= index ? NSColor.white.withAlphaComponent(0.95) : NSColor(calibratedWhite: 0.72, alpha: 1)).setFill()
            NSBezierPath(ovalIn: dot).fill()
        }
        let knob = NSRect(x: knobX - 11, y: bounds.midY - 11, width: 22, height: 22)
        NSColor.black.withAlphaComponent(0.12).setFill()
        NSBezierPath(ovalIn: knob.offsetBy(dx: 0, dy: 1)).fill()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knob).fill()
        NSColor(calibratedWhite: 0.82, alpha: 1).setStroke()
        NSBezierPath(ovalIn: knob.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }

    override func mouseDown(with event: NSEvent) { move(event) }
    override func mouseDragged(with event: NSEvent) { move(event) }

    private func move(_ event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        let inset: CGFloat = 11
        let span = max(1, bounds.width - inset * 2)
        let t = min(1, max(0, (x - inset) / span))
        let next = Int((t * CGFloat(stops - 1)).rounded())
        guard next != index else { return }
        index = next
        needsDisplay = true
        onChange?(index)
    }
}

private extension NSLayoutConstraint {
    func priority(_ value: NSLayoutConstraint.Priority) -> NSLayoutConstraint {
        priority = value
        return self
    }
}
