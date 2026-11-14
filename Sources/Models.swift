import AppKit

// MARK: - Document

enum DocLanguage: String, Codable {
    case english
    case chinese
    case other

    var label: String {
        switch self {
        case .english: return "英文"
        case .chinese: return "中文"
        case .other: return "未知语言"
        }
    }

    var needsTranslation: Bool { self == .english }
}

struct PaperPage: Codable, Equatable {
    var index: Int
    var text: String
}

struct PaperDoc: Codable, Equatable {
    var path: String
    var title: String
    var pages: [PaperPage]
    var language: DocLanguage
    var needsOCR: Bool
    var truncated: Bool
    var fullText: String
    var charCount: Int
    var captions: [Int: String]

    var url: URL { URL(fileURLWithPath: path) }
    var pageCount: Int { pages.count }

    func text(at page: Int) -> String {
        guard page >= 0, page < pages.count else { return "" }
        return pages[page].text
    }

    func caption(at page: Int) -> String? { captions[page] }
}

// MARK: - Conversations

enum AnchorKind: String, Codable {
    case selection
    case region
    case page
    case general

    var symbol: String {
        switch self {
        case .selection: return "text.cursor"
        case .region: return "rectangle.dashed"
        case .page: return "doc.text"
        case .general: return "bubble.left"
        }
    }
}

struct AskThread: Codable, Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var kind: AnchorKind
    var page: Int
    var quote: String?
    var question: String
    var answer: String
    var imageFile: String?
    var highlightID: UUID?

    var shortQuote: String {
        guard let quote, !quote.isEmpty else { return "" }
        let flat = quote.replacingOccurrences(of: "\n", with: " ")
        return flat.count > 90 ? String(flat.prefix(90)) + "…" : flat
    }
}

// MARK: - Highlights

enum HighlightColor: String, Codable, CaseIterable {
    case yellow
    case green
    case blue
    case pink

    var nsColor: NSColor {
        switch self {
        case .yellow: return NSColor.systemYellow.withAlphaComponent(0.35)
        case .green: return NSColor.systemGreen.withAlphaComponent(0.30)
        case .blue: return NSColor.systemBlue.withAlphaComponent(0.26)
        case .pink: return NSColor.systemPink.withAlphaComponent(0.28)
        }
    }

    var label: String {
        switch self {
        case .yellow: return "黄"
        case .green: return "绿"
        case .blue: return "蓝"
        case .pink: return "粉"
        }
    }
}

enum HighlightStyle: String, Codable {
    case text
    case region
}

struct PaperHighlight: Codable, Identifiable {
    var id: UUID = UUID()
    var page: Int
    var rects: [CGRect]
    var color: HighlightColor
    var style: HighlightStyle?
    var quote: String
    var threadID: UUID?
    var createdAt: Date = Date()
}

// MARK: - Persisted per-document state

struct DocState: Codable {
    var doc: PaperDoc
    var threads: [AskThread] = []
    var highlights: [PaperHighlight] = []
    /// page index -> translated text
    var translations: [Int: String] = [:]
    /// AI-generated study notes for this paper
    var conversationMemory: ConversationMemory?
    var readingLevel: ReadingLevel?
    var studyNotes: String?
    var translationCaches: [String: [Int: String]]?
    var translationTarget: String = ""
    var updatedAt: Date = Date()
}

// MARK: - Library entry

struct LibraryEntry {
    let url: URL
    let title: String
    let modified: Date
    let size: Int64
    let pageCount: Int
}

// Reading depth is stored per paper; old documents decode with a nil selection.
enum ReadingLevel: String, Codable, CaseIterable {
    case beginner, intermediate, advanced
    var title: String {
        switch self {
        case .beginner: return "完全陌生"
        case .intermediate: return "了解基础"
        case .advanced: return "比较熟悉"
        }
    }
    var instruction: String {
        switch self {
        case .beginner: return "用户完全不熟悉本文。先用日常语言说明问题和意义，再逐步解释；术语首次出现必须解释，公式逐个说明符号，适当用生活类比并说明类比局限。不假设用户掌握背景知识。必要时可超过默认字数以讲清楚。"
        case .intermediate: return "用户了解基础。简要补充本文特有的概念，重点解释方法步骤、推理链和证据，避免重复基础常识。"
        case .advanced: return "用户比较熟悉。重点讨论创新、假设、推导、证据强度、局限与可复现性，可以使用专业术语。"
        }
    }
}
