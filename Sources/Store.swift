import Foundation

enum Store {
    static var onSaveError: ((String) -> Void)?
    static var root: URL {
        if let custom = ProcessInfo.processInfo.environment["PAPER_COMPANION_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("PaperCompanion", isDirectory: true)
    }

    static var docsDir: URL { root.appendingPathComponent("docs", isDirectory: true) }
    static var imagesDir: URL { root.appendingPathComponent("images", isDirectory: true) }

    static func prepare() {
        for dir in [root, docsDir, imagesDir] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    static func key(for url: URL) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in url.standardizedFileURL.path.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    private static func stateURL(for url: URL) -> URL {
        docsDir.appendingPathComponent(key(for: url) + ".json")
    }

    static func load(for url: URL) -> DocState? {
        guard let data = try? Data(contentsOf: stateURL(for: url)),
              let state = try? JSONDecoder().decode(DocState.self, from: data),
              state.doc.path == url.standardizedFileURL.path else { return nil }
        return state
    }

    static func save(_ state: DocState) {
        prepare()
        var copy = state
        copy.updatedAt = Date()
        do {
            let data = try JSONEncoder().encode(copy)
            try data.write(to: stateURL(for: state.doc.url), options: .atomic)
            ShelfStore.remember(copy)
        } catch { onSaveError?("保存失败：" + error.localizedDescription) }
    }

    /// Move a paper's notes when the file itself moves.
    static func relocateState(from old: URL, to new: URL) {
        let source = stateURL(for: old)
        guard FileManager.default.fileExists(atPath: source.path),
              let data = try? Data(contentsOf: source),
              var state = try? JSONDecoder().decode(DocState.self, from: data) else { return }
        state.doc.path = new.standardizedFileURL.path
        let destination = stateURL(for: new)
        guard let encoded = try? JSONEncoder().encode(state) else { return }
        try? encoded.write(to: destination, options: .atomic)
        if source.path != destination.path {
            try? FileManager.default.removeItem(at: source)
        }
    }

    static func remove(for url: URL) {
        try? FileManager.default.removeItem(at: stateURL(for: url))
    }

    // MARK: Region images

    static func saveImage(_ data: Data, for docURL: URL, suffix: String = "png") -> String? {
        prepare()
        let name = key(for: docURL) + "-" + UUID().uuidString.prefix(8) + "." + suffix
        let url = imagesDir.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func imageURL(named name: String) -> URL {
        imagesDir.appendingPathComponent(name)
    }
}

/// Conversation that is not tied to a paper, used before and after reading.
struct LoungeRecord: Codable {
    var threads: [AskThread] = []
    var conversationMemory: ConversationMemory?
}

enum LoungeStore {
    private static var fileURL: URL { Store.root.appendingPathComponent("lounge.json") }

    static func load() -> LoungeRecord {
        guard let data = try? Data(contentsOf: fileURL),
              let record = try? JSONDecoder().decode(LoungeRecord.self, from: data) else { return LoungeRecord() }
        return record
    }

    static func save(_ record: LoungeRecord) {
        Store.prepare()
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
