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

final class AccentButton: NSButton {
    private var hover = false

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.masksToBounds = false
        setButtonType(.momentaryChange)
        font = Theme.text(14, weight: .semibold)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 44).isActive = true
        widthAnchor.constraint(greaterThanOrEqualToConstant: 236).isActive = true
        applyTitle()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let fill = (hover || isHighlighted) ? Theme.cta.blended(withFraction: 0.14, of: .white) ?? Theme.cta : Theme.cta
        layer?.backgroundColor = fill.cgColor
        layer?.shadowColor = Theme.cta.cgColor
        layer?.shadowOpacity = hover ? 0.42 : 0.28
        layer?.shadowRadius = hover ? 18 : 14
        layer?.shadowOffset = CGSize(width: 0, height: -5)
    }

    private func applyTitle() {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        attributedTitle = NSAttributedString(string: "   \(title)   ", attributes: [
            .font: Theme.text(14, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: style,
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        hover = true
        animateLift(true)
    }

    override func mouseExited(with event: NSEvent) {
        hover = false
        animateLift(false)
    }

    private func animateLift(_ lifted: Bool) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            needsDisplay = true
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().layer?.transform = lifted ? CATransform3DMakeTranslation(0, 1, 0) : CATransform3DIdentity
        }
        needsDisplay = true
    }
}

final class WelcomeAtmosphere: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        Theme.paperBackground.setFill()
        bounds.fill()

        let indigo = NSColor(calibratedRed: 0.46, green: 0.50, blue: 0.95, alpha: dark ? 0.38 : 0.24)
        if let glow = NSGradient(colors: [indigo, indigo.withAlphaComponent(0)]) {
            let center = NSPoint(x: bounds.midX - bounds.width * 0.16, y: bounds.midY + 24)
            let radius = min(bounds.width, bounds.height) * 0.46
            glow.draw(fromCenter: center, radius: 8, toCenter: center, radius: radius, options: [])
        }
        let warm = NSColor(calibratedRed: 0.95, green: 0.62, blue: 0.48, alpha: dark ? 0.14 : 0.16)
        if let glow = NSGradient(colors: [warm, warm.withAlphaComponent(0)]) {
            let center = NSPoint(x: bounds.maxX - bounds.width * 0.08, y: bounds.minY + bounds.height * 0.12)
            glow.draw(fromCenter: center, radius: 4, toCenter: center, radius: 280, options: [])
        }
    }
}

final class PoseChip: NSView {
    init(image: NSImage, caption: String) {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 76).isActive = true
        heightAnchor.constraint(equalToConstant: 92).isActive = true

        let face = NSImageView()
        face.image = image
        face.imageScaling = .scaleProportionallyUpOrDown
        face.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: caption)
        label.font = Theme.text(10, weight: .medium)
        label.textColor = .tertiaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(face)
        addSubview(label)
        NSLayoutConstraint.activate([
            face.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            face.centerXAnchor.constraint(equalTo: centerXAnchor),
            face.widthAnchor.constraint(equalToConstant: 58),
            face.heightAnchor.constraint(equalToConstant: 58),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.cornerRadius = 16
        layer?.backgroundColor = (dark ? NSColor.white.withAlphaComponent(0.06) : NSColor.white.withAlphaComponent(0.72)).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = Theme.hairline.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = dark ? 0.28 : 0.08
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        layer?.masksToBounds = false
    }
}

final class CompanionWelcomeView: NSView {
    var onOpen: (() -> Void)?
    var onResume: (() -> Void)?
    private let atmosphere = WelcomeAtmosphere()
    private let portrait = CompanionArt.portrait(CompanionArt.welcome)
    private var openButton: NSButton?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        atmosphere.translatesAutoresizingMaskIntoConstraints = false
        addSubview(atmosphere)

        let text = NSStackView()
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 14
        text.translatesAutoresizingMaskIntoConstraints = false

        text.addArrangedSubview(tracked("PAPER COMPANION", size: 11, color: Theme.accent, kern: 1.8))
        let headline = NSTextField(wrappingLabelWithString: "今天，也一起\n读懂一篇论文吧。")
        headline.font = Theme.display(32, weight: .bold)
        headline.textColor = .labelColor
        headline.maximumNumberOfLines = 2
        text.addArrangedSubview(headline)
        let body = NSTextField(wrappingLabelWithString: "我是你的论文伴侣。\n从第一个不懂的概念，到终于想通的瞬间，\n我都会陪你一起读下去。")
        body.font = Theme.text(14)
        body.textColor = .secondaryLabelColor
        body.maximumNumberOfLines = 4
        text.addArrangedSubview(body)
        text.setCustomSpacing(20, after: body)

        let open = AccentButton(title: "选择论文，开始学习  →")
        open.target = self
        open.action = #selector(openPaper)
        open.keyEquivalent = "\r"
        openButton = open
        text.addArrangedSubview(open)

        if let path = Prefs.shared.lastDocPath, FileManager.default.fileExists(atPath: path) {
            let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            let resume = NSButton(title: "继续上次 · \(name)", target: self, action: #selector(resumePaper))
            resume.bezelStyle = .inline
            resume.isBordered = false
            resume.font = Theme.text(13, weight: .medium)
            resume.contentTintColor = Theme.accent
            resume.alignment = .left
            resume.lineBreakMode = .byTruncatingTail
            resume.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            resume.translatesAutoresizingMaskIntoConstraints = false
            resume.widthAnchor.constraint(lessThanOrEqualToConstant: 380).isActive = true
            text.addArrangedSubview(resume)
        }

        text.addArrangedSubview(plain("拖入 PDF 也可以  ·  ⌘O 打开文献", size: 11, color: .tertiaryLabelColor))

        let captions = ["图表", "笔记", "划线"]
        let castStack = NSStackView()
        castStack.orientation = .horizontal
        castStack.spacing = 10
        castStack.alignment = .centerY
        castStack.translatesAutoresizingMaskIntoConstraints = false
        for (index, member) in CompanionArt.strip.enumerated() {
            let caption = index < captions.count ? captions[index] : member.name
            castStack.addArrangedSubview(PoseChip(image: member.image, caption: caption))
        }
        text.addArrangedSubview(plain("陪你读、陪你算、陪你记", size: 10, color: .tertiaryLabelColor))
        text.addArrangedSubview(castStack)

        portrait.wantsLayer = true
        portrait.shadow = NSShadow()
        applyPortraitShadow()

        let group = NSView()
        group.translatesAutoresizingMaskIntoConstraints = false
        addSubview(group)
        group.addSubview(portrait)
        group.addSubview(text)
        NSLayoutConstraint.activate([
            atmosphere.leadingAnchor.constraint(equalTo: leadingAnchor),
            atmosphere.trailingAnchor.constraint(equalTo: trailingAnchor),
            atmosphere.topAnchor.constraint(equalTo: topAnchor),
            atmosphere.bottomAnchor.constraint(equalTo: bottomAnchor),

            group.centerXAnchor.constraint(equalTo: centerXAnchor),
            group.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -4),
            group.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            group.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),

            portrait.leadingAnchor.constraint(equalTo: group.leadingAnchor),
            portrait.centerYAnchor.constraint(equalTo: group.centerYAnchor),
            portrait.widthAnchor.constraint(equalToConstant: 340),
            portrait.heightAnchor.constraint(equalToConstant: 340),
            portrait.topAnchor.constraint(greaterThanOrEqualTo: group.topAnchor),
            portrait.bottomAnchor.constraint(lessThanOrEqualTo: group.bottomAnchor),

            text.leadingAnchor.constraint(equalTo: portrait.trailingAnchor, constant: 28),
            text.trailingAnchor.constraint(equalTo: group.trailingAnchor),
            text.centerYAnchor.constraint(equalTo: group.centerYAnchor),
            text.widthAnchor.constraint(equalToConstant: 380),
            text.topAnchor.constraint(greaterThanOrEqualTo: group.topAnchor),
            text.bottomAnchor.constraint(lessThanOrEqualTo: group.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        startFloat()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        atmosphere.needsDisplay = true
        applyPortraitShadow()
    }

    private func applyPortraitShadow() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.45 : 0.16)
        shadow.shadowBlurRadius = 28
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        portrait.shadow = shadow
    }

    private func startFloat() {
        portrait.layer?.removeAnimation(forKey: "float")
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let float = CABasicAnimation(keyPath: "transform.translation.y")
        float.fromValue = -7
        float.toValue = 7
        float.duration = 3.6
        float.autoreverses = true
        float.repeatCount = .infinity
        float.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        portrait.layer?.add(float, forKey: "float")
    }

    private func tracked(_ string: String, size: CGFloat, color: NSColor, kern: CGFloat) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.attributedStringValue = NSAttributedString(string: string, attributes: [
            .font: Theme.text(size, weight: .semibold),
            .foregroundColor: color,
            .kern: kern,
        ])
        return field
    }

    private func plain(_ string: String, size: CGFloat, color: NSColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: string)
        field.font = Theme.text(size, weight: size > 20 ? .semibold : .regular)
        field.textColor = color
        return field
    }

    /// Return opens a paper only while this welcome is the screen in front.
    func setDefaultActionEnabled(_ enabled: Bool) {
        openButton?.keyEquivalent = enabled ? "\r" : ""
    }

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
