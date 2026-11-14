import AppKit
import PDFKit

enum SelectionAction {
    case explain
    case translate
    case ask
    case highlight
}

// MARK: - Floating action bar for a text selection

final class SelectionToolbar: NSView {
    var onAction: ((SelectionAction) -> Void)?

    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.97).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = Theme.subtleBorder.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.22
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -3)

        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 32),
        ])

        add("解释", symbol: "sparkle", action: .explain)
        add("翻译", symbol: "character.book.closed", action: .translate)
        add("提问", symbol: "questionmark.bubble", action: .ask)
        add("划线", symbol: "highlighter", action: .highlight)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func add(_ title: String, symbol: String, action: SelectionAction) {
        let button = NSButton(title: title, target: self, action: #selector(tapped(_:)))
        button.isBordered = false
        button.bezelStyle = .inline
        button.font = Theme.text(11.5, weight: .medium)
        button.contentTintColor = .labelColor
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.identifier = NSUserInterfaceItemIdentifier(String(describing: action))
        button.tag = ["explain": 0, "translate": 1, "ask": 2, "highlight": 3][String(describing: action)] ?? 0
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        stack.addArrangedSubview(button)
    }

    @objc private func tapped(_ sender: NSButton) {
        let action: SelectionAction
        switch sender.tag {
        case 0: action = .explain
        case 1: action = .translate
        case 2: action = .ask
        default: action = .highlight
        }
        onAction?(action)
    }
}

// MARK: - Drag-a-box overlay

final class RegionOverlay: NSView {
    var isActive = false { didSet { updateCursor(); needsDisplay = true } }
    var onFinish: ((NSRect) -> Void)?

    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero

    override var isFlipped: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isActive else { return nil }
        return super.hitTest(point)
    }

    private func updateCursor() {
        window?.invalidateCursorRects(for: self)
        if isActive {
            NSCursor.crosshair.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func resetCursorRects() {
        if isActive {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isActive else { return }
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isActive, let startPoint else { return }
        let point = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(x: min(startPoint.x, point.x),
                             y: min(startPoint.y, point.y),
                             width: abs(point.x - startPoint.x),
                             height: abs(point.y - startPoint.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isActive else { return }
        defer {
            startPoint = nil
            currentRect = .zero
            needsDisplay = true
            isActive = false
        }
        guard currentRect.width > 12, currentRect.height > 12 else { return }
        onFinish?(currentRect)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isActive else { return }
        if currentRect.width > 0 {
            let path = NSBezierPath(roundedRect: currentRect, xRadius: 4, yRadius: 4)
            Theme.accent.withAlphaComponent(0.14).setFill()
            path.fill()
            Theme.accent.setStroke()
            path.lineWidth = 1.5
            let dash: [CGFloat] = [5, 3]
            path.setLineDash(dash, count: 2, phase: 0)
            path.stroke()
        }
    }
}

// MARK: - Highlight overlay (drawn above the PDF, click-through)

final class HighlightOverlay: NSView {
    weak var pdfView: PDFView?
    var highlights: [PaperHighlight] = [] { didSet { needsDisplay = true } }
    var showMarks = true { didSet { needsDisplay = true } }

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func refresh() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let pdfView, let document = pdfView.document else { return }
        guard showMarks else { return }
        for (index, highlight) in highlights.enumerated() {
            guard highlight.page >= 0, highlight.page < document.pageCount,
                  let page = document.page(at: highlight.page) else { continue }
            var drawn = false
            for pageRect in highlight.rects {
                var rect = pdfView.convert(pageRect, from: page)
                rect = convert(rect, from: pdfView)
                guard rect.width > 0.5, rect.height > 0.5 else { continue }
                if !rect.intersects(dirtyRect) { continue }
                drawn = true
                let path = NSBezierPath(roundedRect: rect.insetBy(dx: -1, dy: -0.5), xRadius: 2.5, yRadius: 2.5)
                if highlight.style == .region {
                    NSColor.systemBlue.withAlphaComponent(0.32).setStroke()
                    path.lineWidth = 1
                    let dash: [CGFloat] = [3, 3]
                    path.setLineDash(dash, count: 2, phase: 0)
                    path.stroke()
                } else {
                    highlight.color.nsColor.setFill()
                    path.fill()
                }
            }
            if highlight.style == .region, let first = highlight.rects.first {
                var badgeRect = pdfView.convert(first, from: page)
                badgeRect = convert(badgeRect, from: pdfView)
                let badge = NSRect(x: badgeRect.maxX - 9, y: badgeRect.maxY - 9, width: 18, height: 18)
                let circle = NSBezierPath(ovalIn: badge)
                Theme.accent.withAlphaComponent(0.92).setFill()
                circle.fill()
                let label = "\(index + 1)" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                    .foregroundColor: NSColor.white,
                ]
                let size = label.size(withAttributes: attrs)
                label.draw(at: NSPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2), withAttributes: attrs)
            }
            _ = drawn
        }
    }
}

// MARK: - Reader

final class ReaderPane: NSView {
    let pdfView = PDFView()
    private let toolbar = SelectionToolbar()
    private let overlay = RegionOverlay()
    private let highlightOverlay = HighlightOverlay()
    private let translationColumn = TranslationColumn()
    private let translationDivider = NSView()
    private var translationWidth: NSLayoutConstraint!
    private var translationVisible = false
    private var wantsTranslationDisplay = false
    private var originalDocument: PDFDocument?
    private var translatedDocument: PDFDocument?
    private var originalDestination: PDFDestination?
    private var translatedDestination: PDFDestination?
    private(set) var isShowingTranslation = false
    private var translationPageMap: [Int] = []
    private let emptyView = CompanionWelcomeView()
    private let readingProgress = ReadingProgressView()
    private let hintBar = NSView()
    private let hintLabel = NSTextField(labelWithString: "拖动框选论文里的图、表或公式，松手后提问")

    var onSelectionAction: ((SelectionAction, String, Int) -> Void)?
    var onRegionSelected: ((PDFPage, NSRect) -> Void)?
    var onPageChanged: ((Int) -> Void)?
    var onHighlightTapped: ((UUID) -> Void)?
    var onTranslationVisibilityChanged: ((Bool) -> Void)?
    var onTranslationLanguageChanged: ((String) -> Void)?
    var onRetranslate: (() -> Void)?
    var onDropFile: ((URL) -> Void)?
    var onRequestOpen: (() -> Void)?
    var onRecentPicked: ((URL) -> Void)?

    private var pendingSelection: (text: String, page: Int)?
    private var toolbarWorkItem: DispatchWorkItem?
    private var highlightOwner = "papercompanion:"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        Debug.log("reader: init")
        build()
        Debug.log("reader: built")
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Setup

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        Debug.log("reader: build start")

        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.pageBreakMargins = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        pdfView.backgroundColor = NSColor.underPageBackgroundColor
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pdfView)

        highlightOverlay.pdfView = pdfView
        highlightOverlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(highlightOverlay)

        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.onFinish = { [weak self] rect in
            guard let self else { return }
            self.handleRegion(rect)
        }
        addSubview(overlay)

        toolbar.isHidden = true
        toolbar.onAction = { [weak self] action in self?.runSelectionAction(action) }
        addSubview(toolbar)

        hintBar.wantsLayer = true
        hintBar.layer?.cornerRadius = 8
        hintBar.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.95).cgColor
        hintBar.translatesAutoresizingMaskIntoConstraints = false
        hintBar.isHidden = true
        hintLabel.font = Theme.text(11.5, weight: .medium)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintBar.addSubview(hintLabel)
        addSubview(hintBar)

        translationDivider.wantsLayer = true
        translationDivider.layer?.backgroundColor = Theme.hairline.cgColor
        translationDivider.translatesAutoresizingMaskIntoConstraints = false
        translationDivider.isHidden = true
        addSubview(translationDivider)

        translationColumn.isHidden = true
        translationColumn.onLanguageChanged = { [weak self] in self?.onTranslationLanguageChanged?($0) }
        translationColumn.onTypesetting = { [weak self] in self?.readingProgress.typesetting() }
        translationColumn.onTypesettingFailure = { [weak self] in self?.readingProgress.finish() }
        translationColumn.onFinished = { [weak self] in
            self?.readingProgress.finish()
        }
        translationColumn.onDocumentReady = { [weak self] document in
            guard let self else { return }
            self.translatedDocument = document
            self.translationPageMap = Self.pageMap(document)
            if self.translationVisible, self.wantsTranslationDisplay { self.displayTranslation(true) }
        }
        translationColumn.onClose = { [weak self] in self?.setTranslationVisible(false) }
        translationColumn.onRetranslate = { [weak self] in self?.onRetranslate?() }
        translationColumn.onJumpToPage = { [weak self] page in self?.goTo(page: page) }
        translationColumn.onFontSizeChanged = { [weak self] size in
            Prefs.shared.translationFontSize = size
            self?.translationColumn.setFontSize(size)
        }
        addSubview(translationColumn)

        let dividerDrag = NSPanGestureRecognizer(target: self, action: #selector(handleTranslationDivider(_:)))
        translationDivider.addGestureRecognizer(dividerDrag)

        buildEmptyState()

        translationWidth = translationColumn.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            pdfView.leadingAnchor.constraint(equalTo: leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: translationColumn.bottomAnchor),
            pdfView.bottomAnchor.constraint(equalTo: bottomAnchor),

            translationDivider.widthAnchor.constraint(equalToConstant: 1),
            translationDivider.topAnchor.constraint(equalTo: topAnchor),
            translationDivider.bottomAnchor.constraint(equalTo: bottomAnchor),

            translationColumn.leadingAnchor.constraint(equalTo: leadingAnchor),
            translationColumn.trailingAnchor.constraint(equalTo: trailingAnchor),
            translationColumn.topAnchor.constraint(equalTo: topAnchor),
            translationWidth,

            highlightOverlay.leadingAnchor.constraint(equalTo: pdfView.leadingAnchor),
            highlightOverlay.trailingAnchor.constraint(equalTo: pdfView.trailingAnchor),
            highlightOverlay.topAnchor.constraint(equalTo: pdfView.topAnchor),
            highlightOverlay.bottomAnchor.constraint(equalTo: pdfView.bottomAnchor),

            overlay.leadingAnchor.constraint(equalTo: pdfView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: pdfView.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: pdfView.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: pdfView.bottomAnchor),

            hintBar.centerXAnchor.constraint(equalTo: centerXAnchor),
            hintBar.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            hintLabel.leadingAnchor.constraint(equalTo: hintBar.leadingAnchor, constant: 12),
            hintLabel.trailingAnchor.constraint(equalTo: hintBar.trailingAnchor, constant: -12),
            hintLabel.centerYAnchor.constraint(equalTo: hintBar.centerYAnchor),
            hintBar.heightAnchor.constraint(equalToConstant: 30),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(selectionChanged),
                                               name: .PDFViewSelectionChanged, object: pdfView)
        NotificationCenter.default.addObserver(self, selector: #selector(pageChanged),
                                               name: .PDFViewPageChanged, object: pdfView)
        NotificationCenter.default.addObserver(self, selector: #selector(viewGeometryChanged),
                                               name: NSView.boundsDidChangeNotification,
                                               object: pdfView.enclosingScrollView?.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(viewGeometryChanged),
                                               name: .PDFViewScaleChanged, object: pdfView)

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        click.delaysPrimaryMouseButtonEvents = false
        pdfView.addGestureRecognizer(click)

        registerForDraggedTypes([.fileURL])
    }

    private func buildEmptyState() {
        emptyView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyView)

        emptyView.onOpen = { [weak self] in self?.onRequestOpen?() }
        emptyView.onResume = { [weak self] in
            if let path = Prefs.shared.lastDocPath { self?.onRecentPicked?(URL(fileURLWithPath: path)) }
        }
        NSLayoutConstraint.activate([
            emptyView.leadingAnchor.constraint(equalTo: leadingAnchor),
            emptyView.trailingAnchor.constraint(equalTo: trailingAnchor),
            emptyView.topAnchor.constraint(equalTo: topAnchor),
            emptyView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        readingProgress.translatesAutoresizingMaskIntoConstraints = false
        readingProgress.isHidden = true
        addSubview(readingProgress)
        NSLayoutConstraint.activate([
            readingProgress.widthAnchor.constraint(equalToConstant: 366),
            readingProgress.heightAnchor.constraint(equalToConstant: 104),
            readingProgress.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            readingProgress.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
        ])
    }

    // MARK: Public API

    func show(document: PDFDocument?, empty: Bool) {
        readingProgress.finish()
        originalDocument = document
        translatedDocument = nil
        originalDestination = nil
        translatedDestination = nil
        isShowingTranslation = false
        pdfView.document = document
        emptyView.isHidden = !empty
        pdfView.isHidden = empty
        toolbar.isHidden = true
    }

    // MARK: Translation column

    var isTranslationVisible: Bool { translationVisible }
    var hasTranslationDocument: Bool { translatedDocument != nil }

    func setTranslationVisible(_ visible: Bool, animated: Bool = true) {
        wantsTranslationDisplay = visible
        layoutTranslation(visible: visible, animated: animated)
        displayTranslation(visible && translatedDocument != nil)
        onTranslationVisibilityChanged?(visible)
    }

    /// Shows the translation toolbar without switching the reader to the translation.
    /// Translation only starts (and only replaces the page) after the user asks for it.
    func showTranslationStrip(animated: Bool = false) {
        wantsTranslationDisplay = false
        guard !translationVisible else { return }
        layoutTranslation(visible: true, animated: animated)
        onTranslationVisibilityChanged?(true)
    }

    func requestTranslationDisplay() {
        wantsTranslationDisplay = true
        if translatedDocument != nil { displayTranslation(true) }
    }

    private func layoutTranslation(visible: Bool, animated: Bool) {
        translationVisible = visible
        translationDivider.isHidden = true
        translationColumn.isHidden = !visible
        translationWidth.constant = visible ? 72 : 0
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.allowsImplicitAnimation = true
                window?.contentView?.layoutSubtreeIfNeeded()
            }
        } else {
            window?.contentView?.layoutSubtreeIfNeeded()
        }
        refitNow()
    }

    func configureTranslations(doc: PaperDoc?, translations: [Int: String], currentPage: Int) {
        translatedDocument = nil
        wantsTranslationDisplay = false
        displayTranslation(false)
        translationColumn.configure(doc: doc,
                                    translations: translations,
                                    currentPage: currentPage,
                                    fontSize: Prefs.shared.translationFontSize)
    }

    func renderTranslationPDF() { translationColumn.renderPDF() }

    func updateTranslations(_ translations: [Int: String]) {
        translationColumn.update(translations: translations)
    }

    func showTranslationError(_ message: String) {
        readingProgress.finish()
        translationColumn.showError(message)
    }

    func updateTranslationProgress(_ progress: (Int, Int)?) {
        if let progress, progress.0 < progress.1 { readingProgress.translating(done: progress.0, total: progress.1) }
        else { readingProgress.finish() }
        translationColumn.update(progress: progress)
    }

    func setTranslationFontSize(_ size: CGFloat) {
        translationColumn.setFontSize(size)
    }

    @objc private func handleTranslationDivider(_ gesture: NSPanGestureRecognizer) {}

    override func layout() {
        super.layout()
        if followsWidth, abs(pdfView.bounds.width - fittedWidth) > 1 { fitWidth() }
    }

    private func displayTranslation(_ translated: Bool) {
        let target = translated ? translatedDocument : originalDocument
        guard let target, pdfView.document !== target else { return }
        let previousPage = currentPageIndex()
        if isShowingTranslation { translatedDestination = pdfView.currentDestination }
        else { originalDestination = pdfView.currentDestination }
        isShowingTranslation = translated
        pdfView.document = target
        pdfView.layoutDocumentView()
        if let first = target.page(at: 0) { pdfView.go(to: first) }
        let destination = translated ? translatedDestination : originalDestination
        if let destination, destination.page?.document === target {
            pdfView.go(to: destination)
        } else if previousPage > 0, previousPage < target.pageCount, let page = target.page(at: previousPage) {
            pdfView.go(to: page)
        }
        highlightOverlay.isHidden = translated
        toolbar.isHidden = true
        fitWidth()
        onPageChanged?(currentPageIndex())
    }

    static func sourceDestinations(_ document: PDFDocument) -> [(Int, PDFDestination)] {
        var result: [(Int, PDFDestination)] = []
        func visit(_ node: PDFOutline) {
            if let label = node.label, label.hasPrefix("pc-source-"),
               let source = Int(label.dropFirst("pc-source-".count)), let destination = node.destination {
                result.append((source, destination))
            }
            for index in 0..<node.numberOfChildren { if let child = node.child(at: index) { visit(child) } }
        }
        if let root = document.outlineRoot { visit(root) }
        return result.sorted { $0.0 < $1.0 }
    }

    static func pageMap(_ document: PDFDocument) -> [Int] {
        let destinations = sourceDestinations(document)
        var previous = 0
        return (0..<document.pageCount).map { index in
            if let entry = destinations.first(where: { $0.1.page.map { document.index(for: $0) } == index }) { previous = entry.0 }
            return previous
        }
    }

    func setRegionMode(_ on: Bool) {
        overlay.isActive = on
        hintBar.isHidden = !on
        if on { toolbar.isHidden = true }
    }

    var isRegionMode: Bool { overlay.isActive }

    func goTo(page index: Int) {
        if isShowingTranslation, let document = pdfView.document, let destination = Self.sourceDestinations(document).first(where: { $0.0 == index })?.1 { pdfView.go(to: destination); return }
        let target = isShowingTranslation ? (translationPageMap.firstIndex(of: index) ?? 0) : index
        guard let document = pdfView.document, target >= 0, target < document.pageCount,
              let page = document.page(at: target) else { return }
        pdfView.go(to: page)
    }

    func currentPageIndex() -> Int {
        guard let page = pdfView.currentPage, let document = pdfView.document else { return 0 }
        let index = document.index(for: page)
        return isShowingTranslation && translationPageMap.indices.contains(index) ? translationPageMap[index] : index
    }

    func setZoom(_ factor: CGFloat) {
        followsWidth = false
        pdfView.autoScales = false
        pdfView.scaleFactor = max(0.35, min(3.5, factor))
    }

    func zoom(by delta: CGFloat) {
        setZoom(pdfView.scaleFactor + delta)
    }

    private var followsWidth = true
    private var fittedWidth: CGFloat = 0
    func fitWidth() {
        followsWidth = true
        guard let page = pdfView.currentPage else { return }
        let width = page.bounds(for: pdfView.displayBox).width
        guard width > 0, pdfView.bounds.width > 20 else { return }
        pdfView.autoScales = false
        pdfView.scaleFactor = (pdfView.bounds.width - 20) / width
        fittedWidth = pdfView.bounds.width
    }

    func refitIfNeeded() { refitNow() }

    private func refitNow() {
        if followsWidth { fitWidth(); return }
        guard pdfView.autoScales else { return }
        pdfView.autoScales = false
        pdfView.autoScales = true
        pdfView.layoutSubtreeIfNeeded()
    }

    func nextPage() { pdfView.goToNextPage(nil) }
    func previousPage() { pdfView.goToPreviousPage(nil) }

    func applyHighlights(_ highlights: [PaperHighlight]) {
        highlightOverlay.highlights = highlights
        highlightOverlay.refresh()
    }

    // MARK: Selection

    @objc private func selectionChanged() {
        toolbarWorkItem?.cancel()
        guard !isRegionMode else { return }
        guard let selection = pdfView.currentSelection,
              let page = selection.pages.first,
              let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            toolbar.isHidden = true
            pendingSelection = nil
            return
        }
        let displayedIndex = pdfView.document?.index(for: page) ?? 0
        let pageIndex = isShowingTranslation && translationPageMap.indices.contains(displayedIndex) ? translationPageMap[displayedIndex] : displayedIndex
        pendingSelection = (text, pageIndex)
        toolbar.isHidden = true

        let work = DispatchWorkItem { [weak self] in
            guard let self, let selection = self.pdfView.currentSelection else { return }
            self.positionToolbar(for: selection, page: page)
        }
        toolbarWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
    }

    private func positionToolbar(for selection: PDFSelection, page: PDFPage) {
        guard !selection.pages.isEmpty else { return }
        let pageBounds = selection.bounds(for: page)
        var rect = pdfView.convert(pageBounds, from: page)
        rect = convert(rect, from: pdfView)

        let size = toolbar.fittingSize
        var origin = NSPoint(x: rect.midX - size.width / 2, y: rect.maxY + 8)
        if origin.y + size.height > bounds.maxY - 8 {
            origin.y = rect.minY - size.height - 8
        }
        origin.x = max(8, min(origin.x, bounds.maxX - size.width - 8))
        origin.y = max(8, min(origin.y, bounds.maxY - size.height - 8))
        toolbar.frame = NSRect(origin: origin, size: size)
        toolbar.isHidden = false
    }

    private func runSelectionAction(_ action: SelectionAction) {
        guard let selection = pendingSelection else { return }
        toolbar.isHidden = true
        onSelectionAction?(action, selection.text, selection.page)
    }

    // MARK: Region

    private func handleRegion(_ rectInPane: NSRect) {
        let point = NSPoint(x: rectInPane.midX, y: rectInPane.midY)
        guard let page = pdfView.page(for: convert(point, to: pdfView), nearest: true) else {
            setRegionMode(false)
            return
        }
        let rectInPDFView = convert(rectInPane, to: pdfView)
        let pageRect = pdfView.convert(rectInPDFView, to: page)
        setRegionMode(false)
        onRegionSelected?(page, pageRect)
    }

    // MARK: Clicks on highlights

    @objc private func handleClick(_ gesture: NSClickGestureRecognizer) {
        guard !isShowingTranslation else { return }
        let point = gesture.location(in: pdfView)
        guard let page = pdfView.page(for: point, nearest: true),
              let document = pdfView.document else { return }
        let pageIndex = document.index(for: page)
        let pagePoint = pdfView.convert(point, to: page)
        for highlight in highlightOverlay.highlights where highlight.page == pageIndex {
            for rect in highlight.rects where rect.insetBy(dx: -2, dy: -2).contains(pagePoint) {
                onHighlightTapped?(highlight.id)
                return
            }
        }
    }

    // MARK: Page tracking

    @objc private func viewGeometryChanged() {
        highlightOverlay.refresh()
    }

    @objc private func pageChanged() {
        let index = currentPageIndex()
        translationColumn.update(currentPage: index)
        onPageChanged?(index)
    }

    @objc private func openTapped() {
        onRequestOpen?()
    }

    @objc private func recentTapped(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        onRecentPicked?(URL(fileURLWithPath: path))
    }

    // MARK: Drag & drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let url = droppedURL(sender), ["pdf"].contains(url.pathExtension.lowercased()) else { return [] }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = droppedURL(sender) else { return false }
        onDropFile?(url)
        return true
    }

    private func droppedURL(_ sender: NSDraggingInfo) -> URL? {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.first
    }
}
