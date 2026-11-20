import Foundation

enum Debug { static func log(_ message: String) {} }
enum LLMError: Error { case noAPIKey, empty }
enum ReasoningEffort: String { case none, low, high, max }
final class Prefs {
    static let shared = Prefs()
    var apiKey = "test", baseURL = "local", model = "mock"
    var reasoningEffort: ReasoningEffort = .high
}
final class LLMClient {
    static var requests: [[[String: Any]]] = []
    func cancel() {}
    func stream(apiKey: String, baseURL: String, model: String, messages: [[String: Any]], temperature: Double = 0.2, reasoning: ReasoningEffort? = nil, maxTokens: Int? = nil, timeout: TimeInterval = 180, onDelta: @escaping (String) -> Void, onFinish: @escaping (Result<String, Error>) -> Void) {
        Self.requests.append(messages)
        onFinish(.success(maxTokens == 3500 ? "记住最早的问题、用户纠正和未解决疑问。" : "回答"))
    }
}
@main struct MemoryTests {
    static func main() throws {
        let history = (0..<100).map { AskThread(kind: .general, page: $0 % 10, question: "问题\($0)", answer: String(repeating: "长回答内容", count: 150)) }
        let start = ConversationContext.recentStart(history)
        assert(start > 6 && start < history.count)
        let doc = PaperDoc(path: "/tmp/sample.pdf", title: "Test", pages: [], language: .english, needsOCR: false, truncated: false, fullText: "Paper", charCount: 5, captions: [:])
        let engine = ChatEngine()
        var memory: ConversationMemory?
        engine.ask(doc: doc, history: history, memory: nil, onMemory: { memory = $0 }, question: "继续解释", context: AskContext(), onDelta: { _ in }, onFinish: { _ in })
        assert(memory?.coveredCount == start)
        assert(memory?.lastThreadID == history[start - 1].id)
        let last = LLMClient.requests.last!
        assert(last.contains { ($0["content"] as? String)?.contains("此前阅读交流摘要") == true })
        assert(last.contains { ($0["content"] as? String) == "问题99" })
        let count = LLMClient.requests.count
        engine.ask(doc: doc, history: history, memory: memory, question: "继续", context: AskContext(), onDelta: { _ in }, onFinish: { _ in })
        assert(LLMClient.requests.count == count + 1)
        var state = DocState(doc: doc)
        state.conversationMemory = memory
        let restored = try JSONDecoder().decode(DocState.self, from: JSONEncoder().encode(state))
        assert(restored.conversationMemory?.coveredCount == start)
        assert(ConversationContext.valid(memory, history: Array(history.dropFirst())) == nil)
        let concise = ChatEngine.systemPrompt(doc: doc, detail: .concise)
        let detailed = ChatEngine.systemPrompt(doc: doc, detail: .detailed)
        assert(concise.contains("不超过 400 字"))
        assert(detailed.contains("【回答篇幅】详细"))
        assert(!detailed.contains("不超过 400 字"))
        print("PASS: 100 exchanges, bounded recent context, batched summary, reuse, persistence, invalidation, answer length")
    }
}
