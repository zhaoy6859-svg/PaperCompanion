import AppKit
import PDFKit
import UniformTypeIdentifiers

/// Completed translation pages are typeset with XeLaTeX, then displayed by PDFKit.
final class TranslationColumn: NSView {
    var onTypesetting: (() -> Void)?
    var onTypesettingFailure: (() -> Void)?
    var onDocumentReady: ((PDFDocument) -> Void)?
    var onFinished: (() -> Void)?
    var onJumpToPage: ((Int) -> Void)?
    var onClose: (() -> Void)?
    var onFontSizeChanged: ((CGFloat) -> Void)?
    var onRetranslate: (() -> Void)?
    var onLanguageChanged: ((String) -> Void)?
    private let language = NSComboBox()
    private let status = NSTextField(labelWithString: "选择语言，开始精翻")
    private let action = NSButton()
    private let export = NSButton()
    private let pdfView = PDFView()
    private let hint = NSTextField(wrappingLabelWithString: "译文将在这里排版为 PDF。\n选择目标语言，点击「应用语言」开始。")
    private var doc: PaperDoc?
    private var translations: [Int: String] = [:]
    private var completed: [Int: String] = [:]
    private var pdfURL: URL?
    private var texURL: URL?
    private var generation = UUID()
    private var pending: DispatchWorkItem?
    private let queue = DispatchQueue(label: "PaperCompanion.Typesetting", qos: .userInitiated)
    private var currentLanguage = ""
    private var cacheKey = ""
    private var rendering = false
    private var lastCompile = Date.distantPast
    private var renderedCount = 0
    private var requested: [Int: String] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = Theme.paperBackground.cgColor
        language.addItems(withObjectValues: ["简体中文", "繁體中文", "English", "日本語", "한국어", "Français", "Deutsch", "Español", "Português", "Русский", "العربية"])
        language.stringValue = Prefs.shared.translationLanguage
        language.toolTip = "选择或输入任意目标语言，然后应用"
        language.translatesAutoresizingMaskIntoConstraints = false
        language.widthAnchor.constraint(equalToConstant: 165).isActive = true
        let apply = NSButton(title: "应用语言", target: self, action: #selector(applyLanguage))
        apply.bezelStyle = .rounded
        action.title = "开始翻译"
        action.target = self
        action.action = #selector(toggle)
        action.bezelStyle = .rounded
        action.toolTip = "停止或继续；按住 Option 点击重新翻译"
        export.title = "导出 PDF"
        export.target = self
        export.action = #selector(exportPDF)
        export.bezelStyle = .rounded
        export.isEnabled = false
        let close = NSButton.icon("xmark", tip: "返回原文", target: self, action: #selector(closeColumn))
        let row = NSStackView(views: [language, apply, action, export, close])
        row.spacing = 6
        status.font = Theme.text(11)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        let header = NSStackView(views: [row, status])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 7
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.backgroundColor = Theme.sidebarBackground
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        // PDF is displayed in the main reader, not a second column.
        pdfView.isHidden = true
        addSubview(pdfView)
        hint.font = Theme.text(14)
        hint.textColor = .secondaryLabelColor
        hint.alignment = .center
        hint.translatesAutoresizingMaskIntoConstraints = false
        hint.isHidden = true
        addSubview(hint)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            row.widthAnchor.constraint(lessThanOrEqualTo: header.widthAnchor),
            status.widthAnchor.constraint(equalTo: header.widthAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(doc: PaperDoc?, translations: [Int: String], currentPage: Int, fontSize: CGFloat) {
        generation = UUID()
        pending?.cancel()
        self.doc = doc
        self.translations = translations
        self.completed = translations
        currentLanguage = Prefs.shared.translationLanguage
        cacheKey = Prefs.shared.translationCacheKey
        language.stringValue = currentLanguage
        pdfView.document = nil
        pdfURL = nil
        texURL = nil
        requested = [:]
        rendering = false
        renderedCount = 0
        export.isEnabled = false
        hint.isHidden = true
        hint.stringValue = "点击「开始翻译」后，译文会排版成 PDF 并替换正文。"
        renderPDF()
    }
    func update(translations: [Int: String]) { self.translations = translations }
    func update(currentPage: Int) { /* Original and translated text have independent pagination. */ }
    func setFontSize(_ size: CGFloat) { pdfView.scaleFactor *= size > 13.5 ? 1.1 : 0.9 }
    func showError(_ message: String) {
        status.stringValue = "翻译失败 · 点击继续重试"
        status.toolTip = message
        action.title = "重试翻译"
        if pdfView.document == nil { hint.stringValue = message; hint.isHidden = false }
    }
    func update(progress: (Int, Int)?) {
        let running = progress.map { $0.0 < $0.1 } ?? false
        let total = doc?.pages.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count ?? 0
        let done = completed.count
        if running {
            action.title = "停止翻译"
        } else if done == 0 {
            action.title = "开始翻译"
        } else if done < total {
            action.title = "继续翻译"
        } else {
            action.title = "重新翻译"
        }
        if let progress { status.stringValue = "\(currentLanguage) · \(progress.0)/\(progress.1) 页 · LaTeX 排版" }
        else { status.stringValue = done == 0 ? "\(currentLanguage) · 尚未翻译" : "\(currentLanguage) · 已停止" }
        if !running { renderPDF() }
    }
    func renderPDF() {
        completed = translations
        schedulePDF()
    }
    private func schedulePDF() {
        guard !rendering, !completed.isEmpty, let doc else { return }
        if completed == requested { return }
        pending?.cancel()
        let token = generation
        let pages = completed
        let target = currentLanguage
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == token else { return }
            self.rendering = true
            self.requested = pages
            self.status.stringValue = "正在排版 \(pages.count) 页译文…"
            if pages.count == doc.pages.filter({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).count { self.onTypesetting?() }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PaperCompanion-Translation-" + UUID().uuidString)
            self.queue.async {
                let source = TranslationPDF.source(doc: doc, pages: pages, language: target)
                do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
                catch { DispatchQueue.main.async { if self.generation == token { self.rendering = false; self.onTypesettingFailure?(); self.showError(error.localizedDescription) } }; return }
                let tex = folder.appendingPathComponent("translation.tex")
                let result = LearningReport.exportSource(source, to: tex)
                DispatchQueue.main.async {
                    guard self.generation == token else { try? FileManager.default.removeItem(at: folder); return }
                    self.rendering = false
                    self.lastCompile = Date()
                    let oldFolder = self.texURL?.deletingLastPathComponent()
                    self.texURL = tex
                    self.renderedCount = pages.count
                    self.pdfURL = result.pdf
                    self.export.isEnabled = true
                    let complete = pages.count == doc.pages.filter({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).count
                    if let url = result.pdf, let document = PDFDocument(url: url) {
                        self.onDocumentReady?(document)
                        if complete { self.onFinished?() }
                        self.hint.isHidden = true
                        self.status.stringValue = "\(target) · 已排版 \(pages.count)/\(doc.pageCount) 页"
                    } else {
                        self.onTypesettingFailure?()
                        Debug.log("typeset failed: " + result.message)
                        self.hint.stringValue = result.message
                        self.hint.isHidden = true
                        self.status.stringValue = "PDF 排版失败 · 可导出 LaTeX 源码"
                    }
                    if let oldFolder { try? FileManager.default.removeItem(at: oldFolder) }
                    if self.completed != pages { self.schedulePDF() }
                }
            }
        }
        pending = work
        // Do not rebuild the PDF on every single page: LaTeX compiles the whole document,
        // so coalesce bursts and keep at least 4s between compiles.
        let wait = max(1.2, 4.0 - Date().timeIntervalSince(lastCompile))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }
    @objc private func applyLanguage() {
        let target = language.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { status.stringValue = "请输入目标语言"; return }
        onLanguageChanged?(target)
    }
    @objc private func toggle() { onRetranslate?() }
    @objc private func closeColumn() { onClose?() }
    @objc private func exportPDF() {
        guard let texURL else { return }
        let source = pdfURL ?? texURL
        let panel = NSSavePanel()
        panel.title = pdfURL == nil ? "导出 LaTeX 译文源码" : "导出排版译文 PDF"
        panel.nameFieldStringValue = "译文-\(currentLanguage)." + (pdfURL == nil ? "tex" : "pdf")
        panel.allowedContentTypes = pdfURL == nil ? [UTType(filenameExtension: "tex") ?? .plainText] : [.pdf]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try Data(contentsOf: source).write(to: destination, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
            status.stringValue = "已导出 · \(renderedCount) 页译文"
        } catch { status.stringValue = "导出失败：" + error.localizedDescription }
    }
    static func stripPageEcho(_ text: String) -> String { text }
}
