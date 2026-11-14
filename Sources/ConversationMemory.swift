import Foundation

struct ConversationMemory: Codable {
    var summary: String
    var coveredCount: Int
    var lastThreadID: UUID?
}

enum ConversationContext {
    // Character budgets are deliberately conservative across Chinese and English.
    static func recentStart(_ history: [AskThread], budget: Int = 24000) -> Int {
        var count = 0
        var start = history.count
        for index in history.indices.reversed() {
            let size = history[index].question.count + history[index].answer.count + (history[index].quote?.count ?? 0)
            if start < history.count && (count + size > budget || history.count - index > 24) { break }
            start = index
            count += size
        }
        return start
    }
    static func valid(_ memory: ConversationMemory?, history: [AskThread]) -> ConversationMemory? {
        guard let memory, memory.coveredCount > 0, memory.coveredCount <= history.count,
              history[memory.coveredCount - 1].id == memory.lastThreadID else { return nil }
        return memory
    }
    static func batchEnd(_ history: [AskThread], from: Int, to: Int) -> Int {
        var end = from
        var size = 0
        while end < to {
            let next = history[end].question.count + history[end].answer.count + (history[end].quote?.count ?? 0)
            if end > from && size + next > 20000 { break }
            size += next
            end += 1
        }
        return end
    }
}
