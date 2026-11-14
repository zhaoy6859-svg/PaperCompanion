import AppKit
import PDFKit

/// Translates an English paper page by page, streaming each page as it lands.
final class TranslationService {
    var onPageDelta: ((Int, String) -> Void)?
    var onPageDone: ((Int, String) -> Void)?
    var onProgress: ((Int, Int) -> Void)?
    var onError: ((String) -> Void)?

    private let client = LLMClient()
    private(set) var isRunning = false
    private var generation = UUID()
    private var instructions = ""
    private var cancelled = false
    private var queue: [Int] = []
    private var total = 0
    private var doc: PaperDoc?

    func cancel() {
        generation = UUID()
        cancelled = true
        client.cancel()
        isRunning = false
    }

    /// Translates pages that do not have a cached translation yet.
    func start(doc: PaperDoc, existing: [Int: String], force: Bool = false) {
        guard !isRunning else { return }
        guard !Prefs.shared.apiKey.isEmpty else { return }
        instructions = Prefs.shared.translationPrompt.replacingOccurrences(of: "【目标语言】", with: Prefs.shared.translationLanguage) + "\n目标语言：" + Prefs.shared.translationLanguage + "\n保留原文的文章标题、作者、章节编号、标题级别（用 Markdown # / ## / ###）、段落、列表、表格和公式编号，依照原文顺序。不要添加页标题、不要重复页眉页脚；跨页段落自然衔接。必须使用 $...$ 和 $$...$$ 表达全部数学公式；若图片和文字均无法可靠识别，写【公式识别待核对，参见原文该页】，不得猜测符号或输出乱码方框。"

        self.doc = doc
        let pending = doc.pages
            .filter { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            .map(\.index)
            .filter { force || existing[$0] == nil }

        guard !pending.isEmpty else {
            onProgress?(existing.count, existing.count)
            return
        }
        queue = pending
        total = pending.count
        cancelled = false
        isRunning = true
        onProgress?(0, total)
        next()
    }

    private func next() {
        guard !cancelled, isRunning, !queue.isEmpty, let doc else {
            isRunning = false
            return
        }
        let page = queue.removeFirst()
        let text = doc.text(at: page)
        let docURL = doc.url
        let useVision = Prefs.shared.usesVision
        let token = generation

        // The page image lets the model reconstruct formulas instead of copying the
        // garbled glyph soup that PDF text extraction produces.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var images: [Data] = []
            if useVision, let pdf = PDFDocument(url: docURL), let pageObject = pdf.page(at: page) {
                images = RegionCapture.pageHalves(page: pageObject)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.generation == token, self.isRunning, !self.cancelled else { return }
                self.send(page: page, text: text, images: images, token: token)
            }
        }
    }

    private func send(page: Int, text: String, images: [Data], token: UUID) {
        Debug.log("translate page \(page + 1): images=\(images.count) bytes=\(images.reduce(0) { $0 + $1.count }) text=\(text.count)")
        let header = images.isEmpty
            ? "【原文文本（PDF 提取，公式可能乱码）】\n"
            : "【原文文本（PDF 提取，公式可能乱码）】\n"
        let body = header + text + (images.isEmpty ? "" : "\n\n【页面图片】依次为该页上半页、下半页。")
        var content: [[String: Any]] = [["type": "text", "text": body]]
        for image in images {
            content.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64," + image.base64EncodedString(),
                    "detail": "high",
                ],
            ])
        }

        var buffer = ""
        client.stream(apiKey: Prefs.shared.apiKey,
                      baseURL: Prefs.shared.baseURL,
                      model: Prefs.shared.model,
                      messages: [["role": "system", "content": instructions],
                                 ["role": "user", "content": content]],
                      temperature: 0.1,
                      maxTokens: 6000,
                      timeout: 300,
                      onDelta: { [weak self] delta in
                          guard let self, self.generation == token, !self.cancelled else { return }
                          buffer += delta
                          self.onPageDelta?(page, buffer)
                      },
                      onFinish: { [weak self] result in
                          guard let self, self.generation == token, !self.cancelled else { return }
                          switch result {
                          case let .success(text):
                              let cleaned = Self.stripPageEcho(text)
                              if !cleaned.isEmpty {
                                  self.onPageDone?(page, cleaned)
                              }
                              self.onProgress?(self.total - self.queue.count, self.total)
                              self.next()
                          case let .failure(error):
                              self.isRunning = false
                              let message = (error as? LLMError)?.localizedDescription ?? error.localizedDescription
                              self.onError?(message)
                          }
                      })
    }

    private static func stripPageEcho(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        while let first = lines.first {
            let trimmed = first.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("【第") && trimmed.hasSuffix("页】") {
                lines.removeFirst()
            } else {
                break
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
