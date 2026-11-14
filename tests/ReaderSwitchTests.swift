import AppKit
import PDFKit

enum Debug { static func log(_ message: String) {} }
@main struct ReaderSwitchTests {
    static func main() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        let reader = ReaderPane()
        window.contentView = reader
        window.makeKeyAndOrderFront(nil)
        let original = PDFDocument(url: URL(fileURLWithPath: "/tmp/pc-v4-source.pdf"))!
        reader.show(document: original, empty: false)
        reader.goTo(page: 1)
        let doc = PaperDoc(path: "/tmp/pc-v4-source.pdf", title: "测试", pages: [PaperPage(index: 0, text: "One"), PaperPage(index: 1, text: "Two")], language: .english, needsOCR: false, truncated: false, fullText: "", charCount: 6, captions: [:])
        let translations = try JSONDecoder().decode([Int: String].self, from: Data(contentsOf: URL(fileURLWithPath: "/tmp/pc-v4-translations.json")))
        reader.configureTranslations(doc: doc, translations: translations, currentPage: 1)
        reader.setTranslationVisible(true, animated: false)
        let deadline = Date().addingTimeInterval(25)
        while !reader.isShowingTranslation && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        assert(reader.isShowingTranslation, "Translation must replace original after successful compile")
        assert(reader.pdfView.document !== original)
        reader.goTo(page: 1)
        assert(reader.pdfView.document?.outlineRoot?.numberOfChildren == 2)
        reader.setTranslationVisible(false, animated: false)
        assert(reader.pdfView.document === original)
        assert(reader.currentPageIndex() == 1)
        reader.setTranslationVisible(true, animated: false)
        assert(reader.isShowingTranslation)
        let overlay = ReadingProgressView()
        overlay.translating(done: 1, total: 3)
        assert(overlay.hitTest(.zero) == nil)
        overlay.finish()
        assert(overlay.isHidden)
        print("PASS: translated PDF replacement, source page mapping, original/translation position restoration")
    }
}
