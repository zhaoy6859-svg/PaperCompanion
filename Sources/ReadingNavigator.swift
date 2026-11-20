import AppKit
import PDFKit

struct ReadingOutlineItem {
    var title: String
    var depth: Int
    var destination: PDFDestination?
    var pageIndex: Int
}

enum ReadingOutline {
    /// Published bookmarks win. Translation anchors become “原文第 n 页”.
    /// When a PDF has neither, headings are inferred from type size and labeled as such.
    static func build(_ document: PDFDocument) -> (items: [ReadingOutlineItem], note: String) {
        if let root = document.outlineRoot, root.numberOfChildren > 0 {
            var published: [ReadingOutlineItem] = []
            var sources: [ReadingOutlineItem] = []
            func visit(_ node: PDFOutline, depth: Int) {
                for index in 0..<node.numberOfChildren {
                    guard let child = node.child(at: index) else { continue }
                    let label = (child.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if label.hasPrefix("pc-source-") {
                        if let source = Int(label.dropFirst("pc-source-".count)), let destination = child.destination {
                            let page = destination.page.map { document.index(for: $0) } ?? 0
                            sources.append(ReadingOutlineItem(title: "原文第 \(source + 1) 页", depth: 0, destination: destination, pageIndex: page))
                        }
                        continue
                    }
                    if !label.isEmpty {
                        let destination = child.destination
                        let page = destination?.page.map { document.index(for: $0) } ?? 0
                        published.append(ReadingOutlineItem(title: label, depth: depth, destination: destination, pageIndex: page))
                    }
                    visit(child, depth: min(depth + 1, 4))
                }
            }
            visit(root, depth: 0)
            if !published.isEmpty { return (published, "") }
            if !sources.isEmpty { return (sources, "译文对应的原文页") }
        }
        return ([], "正在按字号整理标题…")
    }

    static func infer(_ document: PDFDocument) -> [ReadingOutlineItem] {
        var items: [ReadingOutlineItem] = []
        let pageLimit = min(document.pageCount, 30)
        for index in 0..<pageLimit {
            guard items.count < 60, let page = document.page(at: index) else { continue }
            guard let text = page.attributedString, text.length > 40 else { continue }
            let range = NSRange(location: 0, length: min(text.length, 6000))
            guard let selection = page.selection(for: range) else { continue }
            for line in selection.selectionsByLine() {
                guard items.count < 60 else { break }
                let title = (line.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard (4...70).contains(title.count) else { continue }
                guard let styled = line.attributedString, styled.length > 0 else { continue }
                var size: CGFloat = 0
                styled.enumerateAttribute(.font, in: NSRange(location: 0, length: styled.length)) { value, _, _ in
                    if let font = value as? NSFont { size = max(size, font.pointSize) }
                }
                guard size >= 13.5 else { continue }
                if title.allSatisfy({ $0.isNumber || $0 == "." || $0.isWhitespace }) { continue }
                if items.last?.title == title, items.last?.pageIndex == index { continue }
                let bounds = line.bounds(for: page)
                let destination = PDFDestination(page: page, at: NSPoint(x: bounds.minX, y: bounds.maxY))
                items.append(ReadingOutlineItem(title: title, depth: size >= 16 ? 0 : 1, destination: destination, pageIndex: index))
            }
        }
        return items
    }
}

final class OutlineDocument: NSView {
    override var isFlipped: Bool { true }
    private var rows: [NSView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizingMask = [.width]
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ views: [NSView]) {
        rows.forEach { $0.removeFromSuperview() }
        rows = views
        for row in rows {
            row.translatesAutoresizingMaskIntoConstraints = true
            addSubview(row)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = max(bounds.width, enclosingScrollView?.contentSize.width ?? 0)
        var y: CGFloat = 4
        for row in rows {
            let indent = CGFloat(min(row.tag, 4)) * 12
            row.frame = NSRect(x: 8 + indent, y: y, width: max(40, width - indent - 16), height: 26)
            y += 28
        }
        let height = max(y + 8, enclosingScrollView?.contentView.bounds.height ?? 0)
        let size = NSSize(width: width, height: height)
        if frame.size != size { setFrameSize(size) }
    }
}

final class ReadingNavigator: NSView {
    var onJump: ((PDFDestination) -> Void)?
    var onCollapse: (() -> Void)?

    private let segmented = NSSegmentedControl(labels: ["目录", "缩略图"], trackingMode: .selectOne, target: nil, action: nil)
    private let collapseButton = NSButton()
    private let note = NSTextField(wrappingLabelWithString: "")
    private let outlineScroll = NSScrollView()
    private let outlineDocument = OutlineDocument()
    let thumbnails = PDFThumbnailView()
    private var items: [ReadingOutlineItem] = []
    private var rowButtons: [NSButton] = []
    private weak var pdfView: PDFView?
    private var inferToken = UUID()
    private var noteHeight: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = Theme.paperHeader.cgColor

        segmented.target = self
        segmented.action = #selector(switchPane)
        segmented.selectedSegment = 0
        segmented.segmentStyle = .rounded
        segmented.font = Theme.text(12, weight: .medium)
        segmented.translatesAutoresizingMaskIntoConstraints = false
        collapseButton.iconSetup("chevron.left", tip: "收起目录", target: self, action: #selector(collapse), size: 22)

        note.font = Theme.text(11)
        note.textColor = .secondaryLabelColor
        note.maximumNumberOfLines = 2
        note.translatesAutoresizingMaskIntoConstraints = false
        note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        outlineScroll.drawsBackground = false
        outlineScroll.hasVerticalScroller = true
        outlineScroll.autohidesScrollers = true
        outlineScroll.borderType = .noBorder
        outlineScroll.translatesAutoresizingMaskIntoConstraints = false
        outlineScroll.documentView = outlineDocument

        thumbnails.translatesAutoresizingMaskIntoConstraints = false
        thumbnails.maximumNumberOfColumns = 1
        thumbnails.thumbnailSize = NSSize(width: 132, height: 168)
        thumbnails.backgroundColor = .clear
        thumbnails.labelFont = Theme.text(10)
        thumbnails.allowsDragging = false
        thumbnails.isHidden = true

        for view in [segmented, collapseButton, note, outlineScroll, thumbnails] { addSubview(view) }
        noteHeight = note.heightAnchor.constraint(equalToConstant: 0)
        let pins = [
            segmented.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            segmented.trailingAnchor.constraint(equalTo: collapseButton.leadingAnchor, constant: -6),
            collapseButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            note.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            note.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            outlineScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            outlineScroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            thumbnails.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            thumbnails.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        ]
        for pin in pins { pin.priority = NSLayoutConstraint.Priority(rawValue: 900) }
        NSLayoutConstraint.activate(pins + [
            segmented.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            segmented.heightAnchor.constraint(equalToConstant: 24),
            collapseButton.centerYAnchor.constraint(equalTo: segmented.centerYAnchor),
            note.topAnchor.constraint(equalTo: segmented.bottomAnchor, constant: 8),
            noteHeight,
            outlineScroll.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 4),
            outlineScroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            thumbnails.topAnchor.constraint(equalTo: note.bottomAnchor, constant: 4),
            thumbnails.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.paperHeader.cgColor
        highlight(page: currentPDFPage())
    }

    func attach(_ pdfView: PDFView) {
        self.pdfView = pdfView
        thumbnails.pdfView = pdfView
    }

    func selectThumbnails() {
        segmented.selectedSegment = 1
        switchPane()
    }

    func reload() {
        inferToken = UUID()
        guard let document = pdfView?.document else {
            show(items: [], note: "")
            return
        }
        let built = ReadingOutline.build(document)
        if built.note == "正在按字号整理标题…" {
            show(items: [], note: built.note)
            let token = inferToken
            DispatchQueue.main.async { [weak self] in
                guard let self, self.inferToken == token, self.pdfView?.document === document else { return }
                let inferred = ReadingOutline.infer(document)
                if inferred.isEmpty {
                    self.show(items: [], note: "这篇 PDF 没有目录，可以改用缩略图翻页。")
                } else {
                    self.show(items: inferred, note: "按字号整理，不是出版目录")
                }
            }
            return
        }
        show(items: built.items, note: built.note)
    }

    func highlight(page: Int) {
        let selected = items.firstIndex(where: { $0.pageIndex == page })
        for (index, button) in rowButtons.enumerated() {
            let on = index == selected
            button.wantsLayer = true
            button.layer?.cornerRadius = 6
            button.layer?.backgroundColor = (on ? Theme.accent.withAlphaComponent(0.16) : NSColor.clear).cgColor
            button.contentTintColor = on ? Theme.accent : .labelColor
            if on, let scroll = button.enclosingScrollView {
                let visible = scroll.contentView.documentVisibleRect
                if !visible.intersects(button.frame) { button.scrollToVisible(button.bounds) }
            }
        }
    }

    private func show(items: [ReadingOutlineItem], note text: String) {
        self.items = items
        note.stringValue = text
        noteHeight.constant = text.isEmpty ? 0 : 32
        var buttons: [NSButton] = []
        for (index, item) in items.enumerated() {
            let button = NSButton(title: item.title, target: self, action: #selector(jump(_:)))
            button.tag = min(item.depth, 4)
            button.identifier = NSUserInterfaceItemIdentifier("outline-\(index)")
            button.isBordered = false
            button.alignment = .left
            button.font = Theme.text(12, weight: item.depth == 0 ? .medium : .regular)
            button.lineBreakMode = .byTruncatingTail
            button.contentTintColor = .labelColor
            button.wantsLayer = true
            buttons.append(button)
        }
        rowButtons = buttons
        outlineDocument.show(buttons)
        highlight(page: currentPDFPage())
    }

    private func currentPDFPage() -> Int {
        guard let page = pdfView?.currentPage, let document = pdfView?.document else { return -1 }
        return document.index(for: page)
    }

    @objc private func jump(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let index = Int(raw.dropFirst("outline-".count)),
              items.indices.contains(index), let destination = items[index].destination else { return }
        onJump?(destination)
        highlight(page: items[index].pageIndex)
    }

    @objc private func collapse() { onCollapse?() }

    @objc private func switchPane() {
        let thumbs = segmented.selectedSegment == 1
        thumbnails.isHidden = !thumbs
        outlineScroll.isHidden = thumbs
        note.isHidden = thumbs && note.stringValue.isEmpty
    }
}

final class PaperSearchField: NSSearchField {
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

final class PaperFindBar: NSView, NSSearchFieldDelegate {
    var onQuery: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onClose: (() -> Void)?

    let field = PaperSearchField()
    private let countLabel = NSTextField(labelWithString: "")
    var query: String { field.stringValue }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.97).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = Theme.subtleBorder.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -2)

        field.placeholderString = "在正文中查找"
        field.font = Theme.text(13)
        field.delegate = self
        field.target = self
        field.action = #selector(commit)
        field.sendsSearchStringImmediately = false
        field.sendsWholeSearchString = true
        field.onCancel = { [weak self] in self?.onClose?() }
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)

        countLabel.font = Theme.text(11, weight: .medium)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let previous = icon("chevron.up", action: #selector(previousTapped), tip: "上一个 (⇧⌘G)")
        let next = icon("chevron.down", action: #selector(nextTapped), tip: "下一个 (⌘G)")
        let close = icon("xmark", action: #selector(closeTapped), tip: "关闭")

        for view in [field, countLabel, previous, next, close] { addSubview(view) }
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            field.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.trailingAnchor.constraint(equalTo: countLabel.leadingAnchor, constant: -6),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            countLabel.widthAnchor.constraint(equalToConstant: 72),
            previous.leadingAnchor.constraint(equalTo: countLabel.trailingAnchor, constant: 2),
            previous.centerYAnchor.constraint(equalTo: centerYAnchor),
            next.leadingAnchor.constraint(equalTo: previous.trailingAnchor, constant: 0),
            next.centerYAnchor.constraint(equalTo: centerYAnchor),
            close.leadingAnchor.constraint(equalTo: next.trailingAnchor, constant: 0),
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            close.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func setQuery(_ text: String) { field.stringValue = text }
    func setStatus(_ text: String) { countLabel.stringValue = text }
    func selectAll() { field.selectText(nil) }

    func controlTextDidChange(_ obj: Notification) { onQuery?(field.stringValue) }

    @objc private func commit() { onNext?() }
    @objc private func previousTapped() { onPrevious?() }
    @objc private func nextTapped() { onNext?() }
    @objc private func closeTapped() { onClose?() }

    private func icon(_ symbol: String, action: Selector, tip: String) -> NSButton {
        let button = NSButton()
        button.iconSetup(symbol, tip: tip, target: self, action: action, size: 24)
        return button
    }
}
