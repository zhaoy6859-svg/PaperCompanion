import AppKit

final class ReadingLevelWindow: NSWindowController {
    var onSelect: ((ReadingLevel) -> Void)?
    private var selected: ReadingLevel
    private var choices: [NSButton] = []

    init(title: String, selected: ReadingLevel?) {
        self.selected = selected ?? .beginner
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 510), styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "开始你的阅读"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let root = CardView()
        root.fill = Theme.paperBackground
        window.contentView = root
        let portrait = CompanionArt.portrait(CompanionArt.level)
        root.addSubview(portrait)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        func label(_ text: String, _ size: CGFloat, _ color: NSColor) -> NSTextField {
            let view = NSTextField(wrappingLabelWithString: text)
            view.font = Theme.text(size, weight: size > 20 ? .semibold : .regular)
            view.textColor = color
            return view
        }
        stack.addArrangedSubview(label("论文伴侣 · 想先了解你", 11, Theme.accent))
        stack.addArrangedSubview(label("这篇论文，你熟悉多少？", 25, .labelColor))
        let paper = label(title, 12, .secondaryLabelColor)
        paper.maximumNumberOfLines = 2
        stack.addArrangedSubview(paper)
        let details = ["补充背景 · 通俗类比 · 一步步解释术语", "梳理方法 · 串联推理 · 解释关键证据", "深入推导 · 检查假设 · 讨论创新与局限"]
        for (index, level) in ReadingLevel.allCases.enumerated() {
            let button = NSButton(title: "", target: self, action: #selector(choose(_:)))
            button.tag = index
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = 12
            let text = NSMutableAttributedString(string: level.title + "\n", attributes: [.font: Theme.text(15, weight: .semibold), .foregroundColor: NSColor.labelColor])
            text.append(NSAttributedString(string: details[index], attributes: [.font: Theme.text(12), .foregroundColor: NSColor.secondaryLabelColor]))
            let paragraph = NSMutableParagraphStyle()
            paragraph.firstLineHeadIndent = 18
            paragraph.headIndent = 18
            paragraph.paragraphSpacing = 5
            text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
            button.attributedTitle = text
            button.alignment = .left
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 66).isActive = true
            button.widthAnchor.constraint(equalToConstant: 452).isActive = true
            choices.append(button)
            stack.addArrangedSubview(button)
        }
        stack.addArrangedSubview(label("不用担心，我会按照你的起点来解释。随时可以调整。", 11, .secondaryLabelColor))
        let start = NSButton(title: "开始阅读 →", target: self, action: #selector(confirm))
        start.bezelStyle = .rounded
        start.keyEquivalent = "\r"
        start.contentTintColor = Theme.accent
        stack.addArrangedSubview(start)
        NSLayoutConstraint.activate([
            portrait.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            portrait.widthAnchor.constraint(equalToConstant: 300),
            portrait.heightAnchor.constraint(equalToConstant: 400),
            portrait.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: 15),
            stack.leadingAnchor.constraint(equalTo: portrait.trailingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -36),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
        ])
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    private func refresh() {
        for button in choices {
            let active = ReadingLevel.allCases[button.tag] == selected
            button.layer?.backgroundColor = (active ? Theme.accent.withAlphaComponent(0.12) : Theme.cardBackground).cgColor
            button.layer?.borderWidth = active ? 1.5 : 0.5
            button.layer?.borderColor = (active ? Theme.accent : Theme.hairline).cgColor
            button.setAccessibilityValue(active ? "已选择" : "未选择")
        }
    }
    /// Used by debug automation to drive the sheet without a mouse.
    func select(_ level: ReadingLevel) {
        selected = level
        refresh()
        onSelect?(level)
    }

    @objc private func choose(_ button: NSButton) { selected = ReadingLevel.allCases[button.tag]; refresh() }
    @objc private func confirm() { onSelect?(selected) }
}
