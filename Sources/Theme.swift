import AppKit

// MARK: - Palette

enum Theme {
    static let sidebarBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.13, alpha: 1)
            : NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.93, alpha: 1)
    }

    static let cardBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.19, alpha: 1)
            : NSColor.white
    }

    static let accent = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.62, green: 0.65, blue: 0.94, alpha: 1)
            : NSColor(calibratedRed: 0.34, green: 0.38, blue: 0.65, alpha: 1)
    }

    /// Signature fill for the one primary action. Dark enough for white type in both appearances.
    static let cta = NSColor(calibratedRed: 0.28, green: 0.31, blue: 0.66, alpha: 1)
    static let subtleBorder = NSColor.separatorColor.withAlphaComponent(0.55)

    static let paperBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.115, alpha: 1)
            : NSColor(calibratedRed: 0.99, green: 0.98, blue: 0.96, alpha: 1)
    }

    static let paperHeader = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 0.16, alpha: 1)
            : NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.93, alpha: 1)
    }

    static let hairline = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedWhite: 1, alpha: 0.08)
            : NSColor(calibratedWhite: 0, alpha: 0.08)
    }

    static func mono(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    static func text(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }

    /// Serif display face. Chinese falls through to the system Songti cascade, which suits a reading app.
    static func display(_ size: CGFloat, weight: NSFont.Weight = .semibold) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    static func paragraph(spacing: CGFloat = 5, lineSpacing: CGFloat = 4.5, before: CGFloat = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = spacing
        style.paragraphSpacingBefore = before
        return style
    }
}

// MARK: - Small views

final class CardView: NSView {
    var fill: NSColor = Theme.cardBackground { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = fill.cgColor
        layer?.borderColor = Theme.subtleBorder.cgColor
    }
}

final class SeparatorLine: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.subtleBorder.cgColor
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Capsule button used for quick asks and small inline actions.
final class PillButton: NSButton {
    var fillColor: NSColor = NSColor.labelColor.withAlphaComponent(0.06) {
        didSet { updateAppearance() }
    }
    var textColor: NSColor = .secondaryLabelColor {
        didSet { updateAppearance() }
    }

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        bezelStyle = .inline
        font = Theme.text(11.5, weight: .medium)
        wantsLayer = true
        layer?.cornerRadius = 7
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 26).isActive = true
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateAppearance() {
        layer?.backgroundColor = fillColor.cgColor
        contentTintColor = textColor
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: Theme.text(11.5, weight: .medium),
            .foregroundColor: textColor,
            .paragraphStyle: style,
        ])
    }

    func setTitle(_ text: String) {
        title = text
        updateAppearance()
    }
}

extension NSTextView {
    func pcSetAttributed(_ attributed: NSAttributedString) {
        textStorage?.setAttributedString(attributed)
    }
}

extension NSButton {
    static func icon(_ symbol: String, tip: String, target: AnyObject?, action: Selector, size: CGFloat = 26) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.bezelStyle = .inline
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tip
        button.target = target
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: size).isActive = true
        button.heightAnchor.constraint(equalToConstant: size).isActive = true
        return button
    }

    static func text(_ title: String, target: AnyObject?, action: Selector, symbol: String? = nil) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = Theme.text(12, weight: .medium)
        if let symbol {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            button.imagePosition = .imageLeading
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }
}

extension NSButton {
    func iconSetup(_ symbol: String, tip: String, target: AnyObject?, action: Selector,
                   tint: NSColor = .secondaryLabelColor, size: CGFloat = 26) {
        isBordered = false
        bezelStyle = .inline
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        imageScaling = .scaleProportionallyDown
        contentTintColor = tint
        toolTip = tip
        self.target = target
        self.action = action
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
    }
}

/// Minimal vertical stack that avoids NSStackView layout pitfalls with scroll views.
final class VStack: NSView {
    private(set) var items: [NSView] = []
    var spacing: CGFloat = 8
    private var bottomConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError() }

    func removeAll() {
        for item in items { item.removeFromSuperview() }
        items.removeAll()
        bottomConstraint?.isActive = false
        bottomConstraint = nil
    }

    func add(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        if let last = items.last {
            view.topAnchor.constraint(equalTo: last.bottomAnchor, constant: spacing).isActive = true
        } else {
            view.topAnchor.constraint(equalTo: topAnchor).isActive = true
        }
        bottomConstraint?.isActive = false
        bottomConstraint = view.bottomAnchor.constraint(equalTo: bottomAnchor)
        bottomConstraint?.isActive = true
        items.append(view)
    }
}

// MARK: - Text helpers

enum RichText {
    static func line(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
                     color: NSColor = .labelColor, spacing: CGFloat = 6) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: Theme.text(size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: Theme.paragraph(spacing: spacing),
        ])
    }

    static func small(_ text: String, color: NSColor = .tertiaryLabelColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: Theme.text(10.5, weight: .semibold),
            .foregroundColor: color,
            .paragraphStyle: Theme.paragraph(spacing: 3, lineSpacing: 3),
        ])
    }

    static func timeStamp(_ date: Date) -> NSAttributedString {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return NSAttributedString(string: formatter.string(from: date) + "\n", attributes: [
            .font: Theme.text(10),
            .foregroundColor: NSColor.quaternaryLabelColor,
            .paragraphStyle: Theme.paragraph(spacing: 3, lineSpacing: 3),
        ])
    }
}

// MARK: - Scrollable text view

final class TextPane: NSView {
    let scrollView = NSScrollView()
    let textView = NSTextView()

    init(editable: Bool = false, inset: NSSize = NSSize(width: 18, height: 16)) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = editable
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.textContainerInset = inset
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 2
        textView.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .underlineStyle: 0]
        textView.frame = NSRect(x: 0, y: 0, width: 320, height: 400)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    var storage: NSTextStorage? { textView.textStorage }

    func scrollToBottom() {
        guard bounds.width > 10, bounds.height > 10 else { return }
        guard let storage, storage.length > 0 else { return }
        if let container = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: container)
        }
        textView.scrollRangeToVisible(NSRange(location: storage.length, length: 0))
        if let clip = scrollView.contentView as NSClipView? {
            scrollView.reflectScrolledClipView(clip)
        }
    }
}
