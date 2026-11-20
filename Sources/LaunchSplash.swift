import AppKit

/// Title card played once when the window appears.
/// Click or any key skips it. Reduced motion uses a short fade.
final class LaunchSplashView: NSView {
    var onFinished: (() -> Void)?

    static var shouldPlay: Bool {
        if ProcessInfo.processInfo.environment["PAPER_COMPANION_NO_SPLASH"] == "1" { return false }
        let args = CommandLine.arguments
        if args.contains("--doc") || args.contains("--texsample") { return false }
        if args.contains("--snapshot"), !args.contains("--with-splash") { return false }
        return true
    }

    private let glow = CAGradientLayer()
    private var rings: [CAShapeLayer] = []
    private let portrait = CompanionArt.portrait(CompanionArt.welcome)
    private let rule = NSView()
    private var ruleWidth: NSLayoutConstraint!
    private let titleField = NSTextField(labelWithString: "论文伴侣")
    private let subtitleField = NSTextField(labelWithString: "读懂一篇论文")
    private let hintField = NSTextField(labelWithString: "轻点或按任意键进入")
    private var monitor: Any?
    private var played = false
    private var finishing = false
    private var exitWork: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 0.62)
        glow.endPoint = CGPoint(x: 1.15, y: 1.15)
        glow.locations = [0, 1]
        layer?.addSublayer(glow)

        for _ in 0..<3 {
            let ring = CAShapeLayer()
            ring.fillColor = NSColor.clear.cgColor
            ring.lineWidth = 1.25
            ring.opacity = 0
            layer?.addSublayer(ring)
            rings.append(ring)
        }

        portrait.translatesAutoresizingMaskIntoConstraints = false
        portrait.wantsLayer = true
        portrait.setAccessibilityLabel("论文伴侣")

        rule.wantsLayer = true
        rule.translatesAutoresizingMaskIntoConstraints = false
        ruleWidth = rule.widthAnchor.constraint(equalToConstant: 0)

        titleField.font = Theme.display(46, weight: .bold)
        titleField.textColor = .labelColor
        titleField.alignment = .center
        titleField.translatesAutoresizingMaskIntoConstraints = false

        subtitleField.font = Theme.text(14, weight: .medium)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.alignment = .center
        subtitleField.translatesAutoresizingMaskIntoConstraints = false
        subtitleField.attributedStringValue = NSAttributedString(string: "读懂一篇论文", attributes: [
            .font: Theme.text(14, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
            .kern: 3.2,
        ])

        hintField.font = Theme.text(11, weight: .medium)
        hintField.textColor = .tertiaryLabelColor
        hintField.alignment = .center
        hintField.translatesAutoresizingMaskIntoConstraints = false

        let cluster = NSStackView()
        cluster.orientation = .vertical
        cluster.alignment = .centerX
        cluster.spacing = 14
        cluster.translatesAutoresizingMaskIntoConstraints = false
        cluster.addArrangedSubview(portrait)
        cluster.addArrangedSubview(rule)
        cluster.setCustomSpacing(18, after: rule)
        cluster.addArrangedSubview(titleField)
        cluster.setCustomSpacing(8, after: titleField)
        cluster.addArrangedSubview(subtitleField)

        addSubview(cluster)
        addSubview(hintField)
        NSLayoutConstraint.activate([
            portrait.widthAnchor.constraint(equalToConstant: 248),
            portrait.heightAnchor.constraint(equalToConstant: 248),
            ruleWidth,
            rule.heightAnchor.constraint(equalToConstant: 1),
            cluster.centerXAnchor.constraint(equalTo: centerXAnchor),
            cluster.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -8),
            hintField.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -32),
        ])
        applyPalette()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        placeGlowAndRings()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyPalette()
    }

    func play() {
        guard !played else { return }
        played = true
        layoutSubtreeIfNeeded()
        placeGlowAndRings()
        applyPalette()

        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduced {
            ruleWidth.constant = 64
            scheduleExit(after: 0.7, immediate: false)
            installSkipMonitor()
            return
        }

        titleField.alphaValue = 1
        subtitleField.alphaValue = 1
        hintField.alphaValue = 1
        titleField.layer?.opacity = 0
        subtitleField.layer?.opacity = 0
        hintField.layer?.opacity = 0

        portrait.layer?.transform = CATransform3DIdentity
        var entered = CATransform3DIdentity
        entered = CATransform3DTranslate(entered, 0, -22, 0)
        entered = CATransform3DScale(entered, 0.9, 0.9, 1)
        let enter = CABasicAnimation(keyPath: "transform")
        enter.fromValue = entered
        enter.toValue = CATransform3DIdentity
        enter.duration = 0.95
        enter.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        portrait.layer?.add(enter, forKey: "enter")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.7
        portrait.layer?.add(fade, forKey: "in")
        portrait.layer?.opacity = 1

        for (index, ring) in rings.enumerated() {
            let group = CAAnimationGroup()
            group.beginTime = CACurrentMediaTime() + 0.12 + Double(index) * 0.14
            group.duration = 1.7
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.7
            grow.toValue = 1.08
            grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0, 0.5, 0]
            opacity.keyTimes = [0, 0.28, 1]
            group.animations = [grow, opacity]
            ring.add(group, forKey: "pulse")
        }

        fadeIn(titleField, delay: 0.38, distance: 12)
        fadeIn(subtitleField, delay: 0.58, distance: 10)
        fadeIn(hintField, delay: 1.05, distance: 6)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) { [weak self] in
            guard let self, !self.finishing else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.55
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
                context.allowsImplicitAnimation = true
                self.ruleWidth.animator().constant = 64
            }
        }

        scheduleExit(after: 2.35, immediate: false)
        installSkipMonitor()
    }

    func finish(immediate: Bool) {
        guard !finishing else { return }
        finishing = true
        exitWork?.cancel()
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        let duration = immediate ? 0.2 : 0.62
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.removeFromSuperview()
            self.onFinished?()
        })
    }

    override func mouseDown(with event: NSEvent) {
        finish(immediate: true)
    }

    private func scheduleExit(after delay: Double, immediate: Bool) {
        let work = DispatchWorkItem { [weak self] in self?.finish(immediate: immediate) }
        exitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func installSkipMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.modifierFlags.contains(.command) { return event }
            self?.finish(immediate: true)
            return nil
        }
    }

    private func fadeIn(_ view: NSView, delay: Double, distance: CGFloat) {
        view.wantsLayer = true
        view.alphaValue = 1
        var from = CATransform3DIdentity
        from = CATransform3DTranslate(from, 0, -distance, 0)
        let move = CABasicAnimation(keyPath: "transform")
        move.fromValue = from
        move.toValue = CATransform3DIdentity
        move.duration = 0.7
        move.beginTime = CACurrentMediaTime() + delay
        move.fillMode = .backwards
        move.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        view.layer?.add(move, forKey: "rise")
        view.layer?.transform = CATransform3DIdentity

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.7
        fade.beginTime = CACurrentMediaTime() + delay
        fade.fillMode = .backwards
        view.layer?.add(fade, forKey: "in")
        view.layer?.opacity = 1
    }

    private func placeGlowAndRings() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glow.frame = bounds
        let center = CGPoint(x: bounds.midX, y: bounds.midY + 78)
        for (index, ring) in rings.enumerated() {
            let radius: CGFloat = 86 + CGFloat(index) * 34
            ring.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
            ring.position = center
            ring.path = CGPath(ellipseIn: ring.bounds.insetBy(dx: 1, dy: 1), transform: nil)
        }
        CATransaction.commit()
    }

    private func applyPalette() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let paper = dark
            ? NSColor(calibratedRed: 0.07, green: 0.075, blue: 0.11, alpha: 1)
            : NSColor(calibratedRed: 0.975, green: 0.965, blue: 0.945, alpha: 1)
        layer?.backgroundColor = paper.cgColor
        let core = dark
            ? NSColor(calibratedRed: 0.42, green: 0.48, blue: 0.95, alpha: 0.5)
            : NSColor(calibratedRed: 0.55, green: 0.58, blue: 0.98, alpha: 0.45)
        glow.colors = [core.cgColor, core.withAlphaComponent(0).cgColor]
        let stroke = (dark
            ? NSColor(calibratedRed: 0.74, green: 0.78, blue: 1, alpha: 0.75)
            : NSColor(calibratedRed: 0.38, green: 0.42, blue: 0.75, alpha: 0.6)).cgColor
        for ring in rings { ring.strokeColor = stroke }
        rule.layer?.backgroundColor = Theme.accent.cgColor
    }
}
