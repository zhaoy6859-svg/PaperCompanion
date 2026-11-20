import Foundation

// The study: every paper the user opens or imports, grouped into shelves
// and searchable across titles, highlights and questions. PDFs stay where
// they are; this file only remembers them.

struct ShelfPaper: Codable, Equatable, Identifiable {
    var id: String
    var path: String
    var title: String
    var addedAt: Date
    var lastOpenedAt: Date?
    var lastPage: Int
    var pageCount: Int
    var readingLevel: String?
    var highlightCount: Int
    var threadCount: Int
    var collectionIDs: [UUID]
    var excerpt: String

    var filename: String { URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }
    var fileExists: Bool { FileManager.default.fileExists(atPath: path) }
}

struct ShelfCollection: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var createdAt: Date
}

struct ShelfIndex: Codable, Equatable {
    var papers: [ShelfPaper] = []
    var collections: [ShelfCollection] = []
    /// Paths the user removed from the study. Opening or importing them brings them back.
    var dismissedPaths: [String] = []
}

enum ShelfFilter: Equatable {
    case all
    case noted
    case collection(UUID)
}

struct ShelfImportResult: Equatable {
    var added: Int
    var skipped: Int
}

enum ShelfStore {
    private static var fileURL: URL { Store.root.appendingPathComponent("shelf.json") }

    static func read() -> ShelfIndex {
        guard let data = try? Data(contentsOf: fileURL) else { return ShelfIndex() }
        return (try? JSONDecoder().decode(ShelfIndex.self, from: data)) ?? ShelfIndex()
    }

    static func write(_ index: ShelfIndex) {
        Store.prepare()
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Saved papers plus any reading record that is not in the catalog yet.
    static func loadMerged() -> ShelfIndex {
        var index = read()
        let files = (try? FileManager.default.contentsOfDirectory(at: Store.docsDir, includingPropertiesForKeys: nil)) ?? []
        var changed = false
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let state = try? JSONDecoder().decode(DocState.self, from: data) else { continue }
            let path = standardized(state.doc.path)
            if index.dismissedPaths.contains(path) { continue }
            if index.papers.contains(where: { $0.path == path || $0.id == Store.key(for: URL(fileURLWithPath: path)) }) { continue }
            index.papers.append(paper(from: state))
            changed = true
        }
        if changed { write(index) }
        return index
    }

    static func remember(_ state: DocState) {
        var index = read()
        let path = standardized(state.doc.path)
        index.dismissedPaths.removeAll { $0 == path }
        let id = Store.key(for: URL(fileURLWithPath: path))
        if let existing = index.papers.firstIndex(where: { $0.path == path || $0.id == id }) {
            var paper = index.papers[existing]
            paper.id = id
            paper.path = path
            paper.title = state.doc.title
            paper.pageCount = state.doc.pageCount
            paper.readingLevel = state.readingLevel?.rawValue
            paper.highlightCount = state.highlights.count
            paper.threadCount = state.threads.count
            paper.excerpt = excerpt(from: state)
            paper.lastOpenedAt = Date()
            index.papers[existing] = paper
        } else {
            var paper = paper(from: state)
            paper.lastOpenedAt = Date()
            index.papers.append(paper)
        }
        write(index)
    }

    static func notePage(path: String, page: Int) {
        var index = read()
        let path = standardized(path)
        guard let existing = index.papers.firstIndex(where: { $0.path == path }) else { return }
        if index.papers[existing].lastPage == page, index.papers[existing].lastOpenedAt != nil { return }
        index.papers[existing].lastPage = page
        index.papers[existing].lastOpenedAt = Date()
        write(index)
    }

    static func lastPage(for path: String) -> Int {
        read().papers.first { $0.path == standardized(path) }?.lastPage ?? 0
    }

    static func membership(path: String) -> [UUID] {
        read().papers.first { $0.path == standardized(path) }?.collectionIDs ?? []
    }

    @discardableResult
    static func toggle(path: String, collection id: UUID) -> Bool {
        var index = read()
        let path = standardized(path)
        guard let existing = index.papers.firstIndex(where: { $0.path == path }) else { return false }
        if index.papers[existing].collectionIDs.contains(id) {
            index.papers[existing].collectionIDs.removeAll { $0 == id }
        } else {
            index.papers[existing].collectionIDs.append(id)
        }
        write(index)
        return true
    }

    static func createCollection(named raw: String) -> ShelfCollection? {
        let name = normalizeName(raw)
        guard !name.isEmpty else { return nil }
        var index = read()
        if index.collections.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return nil }
        let collection = ShelfCollection(id: UUID(), name: name, createdAt: Date())
        index.collections.append(collection)
        write(index)
        return collection
    }

    static func renameCollection(id: UUID, to raw: String) -> Bool {
        let name = normalizeName(raw)
        guard !name.isEmpty else { return false }
        var index = read()
        guard let existing = index.collections.firstIndex(where: { $0.id == id }) else { return false }
        if index.collections.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return false }
        index.collections[existing].name = name
        write(index)
        return true
    }

    static func deleteCollection(id: UUID) {
        var index = read()
        index.collections.removeAll { $0.id == id }
        for i in index.papers.indices {
            index.papers[i].collectionIDs.removeAll { $0 == id }
        }
        write(index)
    }

    static func removePaper(path: String) {
        var index = read()
        let path = standardized(path)
        index.papers.removeAll { $0.path == path }
        if !index.dismissedPaths.contains(path) { index.dismissedPaths.append(path) }
        write(index)
    }

    /// Point a shelf entry at a moved file and bring its notes along.
    static func relocate(from old: URL, to new: URL) {
        let oldPath = standardized(old.path)
        let newPath = standardized(new.path)
        Store.relocateState(from: URL(fileURLWithPath: oldPath), to: URL(fileURLWithPath: newPath))
        var index = read()
        index.dismissedPaths.removeAll { $0 == oldPath || $0 == newPath }
        let newID = Store.key(for: URL(fileURLWithPath: newPath))
        if let existing = index.papers.firstIndex(where: { $0.path == oldPath || $0.path == newPath }) {
            index.papers[existing].path = newPath
            index.papers[existing].id = newID
            if index.papers[existing].title == URL(fileURLWithPath: oldPath).deletingPathExtension().lastPathComponent {
                index.papers[existing].title = URL(fileURLWithPath: newPath).deletingPathExtension().lastPathComponent
            }
        } else {
            index.papers.append(ShelfPaper(id: newID, path: newPath, title: URL(fileURLWithPath: newPath).deletingPathExtension().lastPathComponent,
                                            addedAt: Date(), lastOpenedAt: nil, lastPage: 0, pageCount: 0, readingLevel: nil,
                                            highlightCount: 0, threadCount: 0, collectionIDs: [], excerpt: ""))
        }
        index.papers = dedupe(index.papers)
        write(index)
    }

    static func importFolder(_ folder: URL) -> ShelfImportResult {
        var index = read()
        var added = 0
        var skipped = 0
        let root = folder.standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(at: root,
                                                              includingPropertiesForKeys: [.isRegularFileKey],
                                                              options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                              errorHandler: { _, _ in true }) else {
            return ShelfImportResult(added: 0, skipped: 0)
        }
        var seen = 0
        for case let url as URL in enumerator {
            seen += 1
            if seen > 8000 { break }
            guard url.pathExtension.lowercased() == "pdf" else { continue }
            let path = standardized(url.path)
            index.dismissedPaths.removeAll { $0 == path }
            if index.papers.contains(where: { $0.path == path }) {
                skipped += 1
                continue
            }
            let title = url.deletingPathExtension().lastPathComponent
            index.papers.append(ShelfPaper(id: Store.key(for: URL(fileURLWithPath: path)), path: path, title: title,
                                            addedAt: Date(), lastOpenedAt: nil, lastPage: 0, pageCount: 0, readingLevel: nil,
                                            highlightCount: 0, threadCount: 0, collectionIDs: [], excerpt: title))
            added += 1
        }
        if added > 0 || skipped > 0 { write(index) }
        return ShelfImportResult(added: added, skipped: skipped)
    }

    static func query(_ papers: [ShelfPaper], text: String, filter: ShelfFilter) -> [ShelfPaper] {
        let terms = text.localizedLowercase.split { $0.isWhitespace }.map(String.init).filter { !$0.isEmpty }
        let filtered = papers.filter { paper in
            switch filter {
            case .all: break
            case .noted: if paper.highlightCount == 0 && paper.threadCount == 0 { return false }
            case .collection(let id): if !paper.collectionIDs.contains(id) { return false }
            }
            if terms.isEmpty { return true }
            let haystack = (paper.title + "\n" + paper.excerpt + "\n" + paper.filename).localizedLowercase
            return terms.allSatisfy { haystack.contains($0) }
        }
        return filtered.sorted { lhs, rhs in
            let left = lhs.lastOpenedAt ?? .distantPast
            let right = rhs.lastOpenedAt ?? .distantPast
            if left != right { return left > right }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    /// Pick a shelf paper the user asked to open. Nil when the request is not an open, or the match is ambiguous.
    static func paperToOpen(_ question: String, in papers: [ShelfPaper]) -> ShelfPaper? {
        let lowered = question.localizedLowercase
        guard ["打开", "开一下", "开启", "open"].contains(where: { lowered.contains($0) }) else { return nil }
        var query = lowered
        for word in ["请你", "请", "帮我", "帮忙", "一下", "哪篇", "那篇", "这篇", "文献", "论文", "文件", "打开", "开启", "看看", "找到", "open"] {
            query = query.replacingOccurrences(of: word, with: " ")
        }
        let terms = query.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 2 }
        guard !terms.isEmpty else { return nil }
        return best(terms.joined(separator: " "), in: papers)
    }

    static func best(_ query: String, in papers: [ShelfPaper]) -> ShelfPaper? {
        let q = query.localizedLowercase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return nil }
        let ranked = papers.compactMap { paper -> (ShelfPaper, Int)? in
            let score = matchScore(q, paper)
            return score > 0 ? (paper, score) : nil
        }.sorted { $0.1 > $1.1 }
        guard let top = ranked.first, top.1 >= 60 else { return nil }
        if ranked.count > 1, ranked[1].1 >= top.1 - 5 { return nil }
        return top.0
    }

    static func catalog(of papers: [ShelfPaper], limit: Int = 40) -> String {
        let ordered = papers.sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
        if ordered.isEmpty { return "（书库是空的）" }
        return ordered.prefix(limit).map { "· \($0.title)" }.joined(separator: "\n")
    }

    /// Pull `[[open:关键词]]` out of a model reply so the app can open the paper and the chat stays clean.
    static func consumeOpens(_ text: String) -> (text: String, queries: [String]) {
        let pattern = #"\[\[open:([^\]]{1,80})\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return (text, []) }
        let range = NSRange(text.startIndex..., in: text)
        var queries: [String] = []
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, match.numberOfRanges > 1, let span = Range(match.range(at: 1), in: text) else { return }
            queries.append(String(text[span]))
        }
        let clean = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        return (clean.replacingOccurrences(of: "\n\n\n", with: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines), queries)
    }

    private static func matchScore(_ query: String, _ paper: ShelfPaper) -> Int {
        let title = paper.title.localizedLowercase
        let file = paper.filename.localizedLowercase
        let excerpt = paper.excerpt.localizedLowercase
        if title.contains(query) || file.contains(query) { return 100 }
        let acronym = initials(of: paper.title)
        if acronym == query || acronym.contains(query) { return 90 }
        if query.count >= 3, acronym.count - query.count <= 2, isSubsequence(query, of: acronym) { return 70 }
        if excerpt.contains(query) { return 60 }
        let tokens = query.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 2 }
        if tokens.count > 1 {
            let hay = title + "\n" + file + "\n" + excerpt
            let hits = tokens.filter { hay.contains($0) }.count
            if hits == tokens.count { return 80 }
        }
        return 0
    }

    private static func initials(of title: String) -> String {
        let skip: Set<String> = ["a", "an", "the", "of", "for", "and", "with", "on", "in", "to", "from", "by"]
        return title.split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !skip.contains($0.localizedLowercase) && $0.count > 1 }
            .compactMap { $0.first.map { String($0).localizedLowercase } }
            .joined()
    }

    private static func isSubsequence(_ needle: String, of hay: String) -> Bool {
        var index = hay.startIndex
        for character in needle {
            guard let found = hay[index...].firstIndex(of: character) else { return false }
            index = hay.index(after: found)
        }
        return !needle.isEmpty
    }

    static func excerpt(from state: DocState) -> String {
        var parts: [String] = [state.doc.title]
        if let first = state.doc.pages.first?.text, !first.isEmpty {
            parts.append(String(first.prefix(1600)))
        }
        for highlight in state.highlights.prefix(30) where !highlight.quote.isEmpty {
            parts.append(highlight.quote)
        }
        for thread in state.threads.prefix(30) {
            parts.append(thread.question)
        }
        let joined = parts.joined(separator: "\n")
        return joined.count > 6000 ? String(joined.prefix(6000)) : joined
    }

    private static func paper(from state: DocState) -> ShelfPaper {
        let path = standardized(state.doc.path)
        return ShelfPaper(id: Store.key(for: URL(fileURLWithPath: path)), path: path, title: state.doc.title,
                          addedAt: state.updatedAt, lastOpenedAt: state.updatedAt, lastPage: 0,
                          pageCount: state.doc.pageCount, readingLevel: state.readingLevel?.rawValue,
                          highlightCount: state.highlights.count, threadCount: state.threads.count,
                          collectionIDs: [], excerpt: excerpt(from: state))
    }

    private static func normalizeName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 40 ? String(trimmed.prefix(40)) : trimmed
    }

    private static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func dedupe(_ papers: [ShelfPaper]) -> [ShelfPaper] {
        var seen = Set<String>()
        return papers.filter { seen.insert($0.path).inserted }
    }
}
