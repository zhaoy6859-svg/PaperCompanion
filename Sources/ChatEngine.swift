import Foundation

struct AskContext {
    var kind: AnchorKind = .general
    var page: Int?
    var quote: String?
    var caption: String?
    var ocr: String?
    var imageJPEG: Data?
    var rects: [CGRect] = []
    var highlightID: UUID?
}

final class ChatEngine {
    private let client = LLMClient()
    private var generation = UUID()
    private(set) var isStreaming = false

    var hasKey: Bool { !Prefs.shared.apiKey.isEmpty }

    func cancel() {
        generation = UUID()
        client.cancel()
        isStreaming = false
    }

    func ask(doc: PaperDoc,
             history: [AskThread],
             level: ReadingLevel = .beginner,
             memory: ConversationMemory? = nil,
             onMemory: @escaping (ConversationMemory) -> Void = { _ in },
             question: String,
             context: AskContext,
             onDelta: @escaping (String) -> Void,
             onFinish: @escaping (Result<String, Error>) -> Void) {
        guard !isStreaming else { return }
        guard hasKey else {
            onFinish(.failure(LLMError.noAPIKey))
            return
        }
        isStreaming = true

        let token = generation
        let start = ConversationContext.recentStart(history)
        let saved = ConversationContext.valid(memory, history: history)
        prepareMemory(history: history, target: start, memory: saved, token: token, onMemory: onMemory) { [weak self] result in
            guard let self, self.generation == token else { return }
            switch result {
            case .failure(let error): self.isStreaming = false; onFinish(.failure(error))
            case .success(let memory):
                self.sendAnswer(doc: doc, history: history, start: min(start, memory?.coveredCount ?? 0), level: level,
                                memory: memory, question: question, context: context, onDelta: onDelta, onFinish: onFinish)
            }
        }
    }

    private func sendAnswer(doc: PaperDoc, history: [AskThread], start: Int, level: ReadingLevel,
                            memory: ConversationMemory?, question: String, context: AskContext,
                            onDelta: @escaping (String) -> Void,
                            onFinish: @escaping (Result<String, Error>) -> Void) {
        var messages: [[String: Any]] = [["role": "system", "content": ChatEngine.systemPrompt(doc: doc) + "\n【解释深度】\n" + level.instruction]]

        if let memory {
            messages.append(["role": "system", "content": "【此前阅读交流摘要，仅作对话背景，不代表论文事实】\n" + memory.summary])
        }
        for thread in history.dropFirst(start) {
            messages.append(["role": "user", "content": ChatEngine.historyUserText(thread)])
            messages.append(["role": "assistant", "content": thread.answer])
        }

        let userText = ChatEngine.userText(question: question, context: context, doc: doc)
        if let image = context.imageJPEG {
            messages.append(["role": "user", "content": [
                ["type": "text", "text": userText],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(image.base64EncodedString())", "detail": "high"]],
            ]])
        } else {
            messages.append(["role": "user", "content": userText])
        }

        client.stream(apiKey: Prefs.shared.apiKey,
                      baseURL: Prefs.shared.baseURL,
                      model: Prefs.shared.model,
                      messages: messages,
                      onDelta: onDelta,
                      onFinish: { [weak self] result in
                          Debug.log("engine onFinish main=\(Thread.isMainThread)")
                          self?.isStreaming = false
                          onFinish(result)
                      })
    }

    private func prepareMemory(history: [AskThread], target: Int, memory: ConversationMemory?, token: UUID,
                               onMemory: @escaping (ConversationMemory) -> Void,
                               completion: @escaping (Result<ConversationMemory?, Error>) -> Void) {
        let covered = memory?.coveredCount ?? 0
        guard covered < target else { completion(.success(memory)); return }
        let end = ConversationContext.batchEnd(history, from: covered, to: target)
        let exchanges = history[covered..<end].map {
            "[p.\($0.page + 1)]\n选文：\($0.quote ?? "")\n问题：\($0.question)\n回答：\($0.answer)"
        }.joined(separator: "\n\n")
        let messages: [[String: Any]] = [
            ["role": "system", "content": "维护同一篇论文的长期阅读记忆。将已有记忆和新增交流合并成简洁中文摘要（不超过 2500 字）。保留用户困惑、已解释概念、符号定义、关键推理、纠正、尚未解决的问题和原文页码。区分用户观点、助手解释和已核实原文事实，不添加新结论。优先保留用户明确纠正和未解决的问题。只输出更新后的摘要。"],
            ["role": "user", "content": "已有记忆：\n" + (memory?.summary ?? "无") + "\n新增交流：\n" + exchanges]
        ]
        client.stream(apiKey: Prefs.shared.apiKey, baseURL: Prefs.shared.baseURL, model: Prefs.shared.model,
                      messages: messages, temperature: 0.1, maxTokens: 3500, timeout: 240, onDelta: { _ in }) { [weak self] result in
            guard let self, self.generation == token else { return }
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let summary):
                let updated = ConversationMemory(summary: summary, coveredCount: end, lastThreadID: history[end - 1].id)
                onMemory(updated)
                self.prepareMemory(history: history, target: target, memory: updated, token: token, onMemory: onMemory, completion: completion)
            }
        }
    }

    func studyNotes(doc: PaperDoc,
                    threads: [AskThread],
                    level: ReadingLevel = .beginner,
                    report: Bool = false,
                    highlights: [PaperHighlight],
                    onDelta: @escaping (String) -> Void,
                    onFinish: @escaping (Result<String, Error>) -> Void) {
        guard !isStreaming else { return }
        guard hasKey else {
            onFinish(.failure(LLMError.noAPIKey))
            return
        }
        isStreaming = true

        var material = "论文标题：\(doc.title)\n"
        if !highlights.isEmpty {
            material += "\n【我标注过的位置】\n"
            for highlight in highlights.sorted(by: { $0.page < $1.page }) {
                let quote = String(highlight.quote.replacingOccurrences(of: "\n", with: " ").prefix(160))
                material += "- p.\(highlight.page + 1)：\(quote)\n"
            }
        }
        if !threads.isEmpty {
            material += "\n【我问过的问题与得到的回答（节选）】\n"
            for thread in (report ? threads : Array(threads.suffix(10))) {
                material += "Q（p.\(thread.page + 1)）：\(thread.question)\nA：\(report ? thread.answer : String(thread.answer.prefix(400)))\n\n"
            }
        }
        if material.count < 60 {
            material += "\n（用户还没有标注，请基于论文整体写一份阅读笔记。）"
        }

        var system = """
        你是用户的学习教练。根据这篇论文以及用户标注、提问的内容，整理一份**可复习的中文学习笔记**。

        要求：
        1. 用 Markdown，分四节：`## 核心概念`、`## 方法与证据`、`## 我标注过的要点`、`## 还没弄懂 / 值得追问`。
        2. 每节 3–6 条短句。术语首次出现括注英文。
        3. 优先覆盖用户标注和提问涉及的内容，其余只补必要的背景。
        4. 关键结论后用 [p.x] 标页码。论文没写的不许编。
        5. 总长不超过 700 字。
        6. 只输出笔记本身，不要前言。
        """

        system += "\n" + level.instruction
        if report {
            system = "根据以下阅读交流整理精致、严谨的中文学习报告，用 Markdown 标题和段落，包含：学习概览、核心概念、关键问答与理解进展、方法与证据、尚存疑惑、复习与行动建议。覆盖所有交流主题，不虚构已经掌握的知识，不把助手旧回答当作核实过的事实。没有原文依据的结论标注待核实。只引用材料中存在的页码。约 1500–2500 字。输出正文，不要 LaTeX 代码。\n" + level.instruction
        }
        let messages: [[String: Any]] = [
            ["role": "system", "content": system],
            ["role": "user", "content": material],
        ]

        client.stream(apiKey: Prefs.shared.apiKey,
                      baseURL: Prefs.shared.baseURL,
                      model: Prefs.shared.model,
                      messages: messages,
                      temperature: 0.2,
                      timeout: 240,
                      onDelta: onDelta,
                      onFinish: { [weak self] result in
                          self?.isStreaming = false
                          onFinish(result)
                      })
    }

    // MARK: - Prompt construction

    static func systemPrompt(doc: PaperDoc) -> String {
        var prompt = """
        你是「论文伴侣」，一位严谨、直接的科研阅读助手，正陪用户精读一篇论文。

        行为准则：
        1. 只依据下面这篇论文回答。原文没写的数字、结论、引用，明确说"论文里没有"，绝不编造。
        2. 默认用简体中文回答；如果用户要求翻译或指定语言，必须使用用户指定的目标语言。先给结论，再给 2–5 句依据；不复述问题，不写空话。
        3. 指位置时用 [p.x]（页码）或章节名。原文已带 [p.x] 标记。
        4. 解释公式：说清每个符号在本文语境里指什么、为什么这样设。
        5. 解释图表：先说它展示了什么变量/对比，再给关键数值，最后说它能支持与不能支持的结论。
        6. 区分"论文声称的"和"证据支持的"；可疑处直说。
        7. 默认不超过 400 字，除非用户要求展开。
        8. 用户若附了图片（框选的图/表/公式区域），以图片为主要依据，OCR 文本可能有误。
        """

        prompt += "\n\n【论文】\n标题：\(doc.title)\n页数：\(doc.pageCount)\n语言：\(doc.language.label)\n"
        if doc.truncated { prompt += "注意：正文过长，中段已省略。\n" }
        if doc.needsOCR { prompt += "注意：这篇 PDF 没有文字层（扫描版），正文可能为空。\n" }
        prompt += "【正文开始】\n\(doc.fullText)\n【正文结束】"
        return prompt
    }

    static func historyUserText(_ thread: AskThread) -> String {
        var text = ""
        if let quote = thread.quote, !quote.isEmpty {
            text += "【当时选中的内容】\n\"\"\"\n\(String(quote.prefix(1200)))\n\"\"\"\n\n"
        }
        text += thread.question
        return text
    }

    static func userText(question: String, context: AskContext, doc: PaperDoc) -> String {
        var blocks: [String] = []

        switch context.kind {
        case .selection:
            if let page = context.page { blocks.append("【我在第 \(page + 1) 页选中了】") }
            if let quote = context.quote {
                blocks.append("\"\"\"\n\(quote)\n\"\"\"")
            }
        case .region:
            if let page = context.page { blocks.append("【我在第 \(page + 1) 页框选了图/表/公式区域】") }
            if let caption = context.caption, !caption.isEmpty {
                blocks.append("该区域附近的图注：\n\(caption)")
            }
            if let ocr = context.ocr, !ocr.isEmpty {
                blocks.append("区域 OCR 文本（可能不准确）：\n\(String(ocr.prefix(1500)))")
            }
            blocks.append("（该区域的截图已随本条消息附上）")
        case .page:
            if let page = context.page {
                blocks.append("【当前在第 \(page + 1) 页】")
                blocks.append("该页原文：\n\(String(doc.text(at: page).prefix(3000)))")
            }
        case .general:
            break
        }

        blocks.append("问题：" + question)
        return blocks.joined(separator: "\n\n")
    }
}
