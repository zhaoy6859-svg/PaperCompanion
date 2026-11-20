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
