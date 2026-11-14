import AppKit

enum CompanionArt {
    static func asset(_ relative: String) -> NSImage? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent(relative)
        let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources").appendingPathComponent(relative)
        return [bundled, development].compactMap { $0 }.compactMap { NSImage(contentsOf: $0) }.first
    }

    static func pose(_ name: String) -> NSImage? { asset("Companion/poses/\(name).png") }

    /// The companion, in the pose that fits the context.
    static var welcome: NSImage? { pose("pdf") }
    static var level: NSImage? { pose("stars") }
    static var chatWelcome: NSImage? { pose("sparkle") }
    static var notes: NSImage? { pose("book") }
    static var progress: NSImage? { pose("bar") }
    static var settings: NSImage? { pose("key") }
    static var avatar: NSImage? { asset("Companion/companion-avatar.png") }

    /// Three poses shown as a small "reading crew" on the welcome screen.
    static var strip: [(name: String, image: NSImage)] {
        var items: [(String, NSImage)] = []
        for name in ["chart", "notebook", "marker"] {
            if let image = pose(name) { items.append((name, image)) }
        }
        return items
    }

    static func portrait(_ image: NSImage? = CompanionArt.welcome) -> NSImageView {
        let view = NSImageView()
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setAccessibilityLabel("论文伴侣，蓝色头发的鲸鱼少女")
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }
}

final class CompanionWelcomeView: NSView {
    var onOpen: (() -> Void)?
    var onResume: (() -> Void)?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.paperBackground.cgColor
        let portrait = CompanionArt.portrait(CompanionArt.welcome)
        let text = NSStackView()
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 18
        text.translatesAutoresizingMaskIntoConstraints = false
        func label(_ title: String, size: CGFloat, color: NSColor) -> NSTextField {
            let label = NSTextField(wrappingLabelWithString: title)
            label.font = Theme.text(size, weight: size > 22 ? .semibold : .regular)
            label.textColor = color
            return label
        }
        text.addArrangedSubview(label("PAPER COMPANION", size: 11, color: Theme.accent))
        text.addArrangedSubview(label("今天，也一起\n读懂一篇论文吧。", size: 32, color: .labelColor))
        text.addArrangedSubview(label("我是你的论文伴侣。\n从第一个不懂的概念，到终于想通的瞬间，\n我都会陪你一起读下去。", size: 14, color: .secondaryLabelColor))
        let open = NSButton(title: "选择论文，开始学习  →", target: self, action: #selector(openPaper))
        open.bezelStyle = .rounded
        open.controlSize = .large
        open.keyEquivalent = "\r"
        text.addArrangedSubview(open)
        if let path = Prefs.shared.lastDocPath, FileManager.default.fileExists(atPath: path) {
            let resume = NSButton(title: "继续上次阅读", target: self, action: #selector(resumePaper))
            resume.bezelStyle = .inline
            resume.isBordered = false
            resume.contentTintColor = Theme.accent
            text.addArrangedSubview(resume)
        }
        text.addArrangedSubview(label("拖入 PDF 也可以  ·  ⌘O 打开文献", size: 11, color: .tertiaryLabelColor))

        // A few more poses of the same companion, as a small reading crew.
        let castStack = NSStackView()
        castStack.orientation = .horizontal
        castStack.spacing = 8
        castStack.alignment = .bottom
        castStack.translatesAutoresizingMaskIntoConstraints = false
        for member in CompanionArt.strip {
            let face = NSImageView()
            face.image = member.image
            face.imageScaling = .scaleProportionallyUpOrDown
            face.toolTip = member.name
            face.translatesAutoresizingMaskIntoConstraints = false
            face.widthAnchor.constraint(equalToConstant: 54).isActive = true
            face.heightAnchor.constraint(equalToConstant: 54).isActive = true
            castStack.addArrangedSubview(face)
        }
        text.addArrangedSubview(label("陪你读、陪你算、陪你记", size: 10, color: .tertiaryLabelColor))
        text.addArrangedSubview(castStack)
        let group = NSView()
        group.translatesAutoresizingMaskIntoConstraints = false
        addSubview(group)
        group.addSubview(portrait)
        group.addSubview(text)
        NSLayoutConstraint.activate([
            group.widthAnchor.constraint(equalToConstant: 820),
            group.heightAnchor.constraint(equalToConstant: 480),
            group.centerXAnchor.constraint(equalTo: centerXAnchor),
            group.centerYAnchor.constraint(equalTo: centerYAnchor),
            portrait.leadingAnchor.constraint(equalTo: group.leadingAnchor),
            portrait.widthAnchor.constraint(equalToConstant: 390),
            portrait.heightAnchor.constraint(equalTo: group.heightAnchor),
            portrait.centerYAnchor.constraint(equalTo: group.centerYAnchor),
            text.leadingAnchor.constraint(equalTo: portrait.trailingAnchor, constant: 30),
            text.trailingAnchor.constraint(equalTo: group.trailingAnchor),
            text.centerYAnchor.constraint(equalTo: group.centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func openPaper() { onOpen?() }
    @objc private func resumePaper() { onResume?() }
}

final class CompanionProgressBar: NSView {
    private let track = CALayer()
    private let fill = CAGradientLayer()
    private var progress: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        track.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        track.cornerRadius = 2.5
        layer?.addSublayer(track)
        fill.colors = [Theme.accent.cgColor, NSColor.systemTeal.cgColor]
        fill.startPoint = CGPoint(x: 0, y: 0.5)
        fill.endPoint = CGPoint(x: 1, y: 0.5)
        fill.cornerRadius = 2.5
        layer?.addSublayer(fill)
        translatesAutoresizingMaskIntoConstraints = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.frame = bounds
        let width = bounds.width * max(0, min(1, progress))
        fill.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        CATransaction.commit()
    }

    func setProgress(_ value: CGFloat, animated: Bool = true) {
        progress = value
        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.35)
            fill.frame = CGRect(x: 0, y: 0, width: bounds.width * max(0, min(1, value)), height: bounds.height)
            CATransaction.commit()
        } else {
            needsLayout = true
        }
    }

    func setIndeterminate(_ on: Bool) {
        if on {
            progress = 1
            needsLayout = true
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.45
            pulse.toValue = 1.0
            pulse.duration = 0.9
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            fill.add(pulse, forKey: "pulse")
        } else {
            fill.removeAnimation(forKey: "pulse")
        }
    }
}

/// Intentionally passes ALL mouse events through, including scrolling and selection.
final class ReadingProgressView: NSVisualEffectView {
    private let title = NSTextField(labelWithString: "正在准备译文")
    private let detail = NSTextField(labelWithString: "可继续阅读和提问，译完后自动切换")
    private let bar = CompanionProgressBar()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        alphaValue = 0.97
        title.font = Theme.text(12, weight: .semibold)
        detail.font = Theme.text(10.5)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 2
        for view in [title, bar, detail] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 13),

            bar.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            bar.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 9),
            bar.heightAnchor.constraint(equalToConstant: 5),

            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            detail.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 8),
            detail.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -13),
        ])
        setAccessibilityLabel("翻译进度，不会阻挡阅读操作")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
func translating(done: Int, total: Int) {
        isHidden = false
        bar.setIndeterminate(false)
        bar.setProgress(total > 0 ? CGFloat(done) / CGFloat(total) : 0)
        title.stringValue = "正在精翻 · \(done) / \(total) 页"
        detail.stringValue = "可继续阅读和提问，译完后自动切换"
    }
    func typesetting() {
        isHidden = false
        bar.setIndeterminate(true)
        title.stringValue = "译文已就绪 · 正在排版公式与正文"
        detail.stringValue = "只需几秒，不影响当前操作"
    }
    func finish() {
        bar.setIndeterminate(false)
        isHidden = true
    }
}
