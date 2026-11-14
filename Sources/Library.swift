import AppKit
import PDFKit

// MARK: - Extraction

enum Library {
    static let supportedExtensions: Set<String> = ["pdf", "docx", "doc", "txt", "md", "rtf"]

    /// Loads a paper: PDF pages get real per-page text, other formats become one page.
    static func load(url: URL) -> PaperDoc? {
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { return nil }

        var pages: [PaperPage] = []
        var needsOCR = false

        if ext == "pdf" {
            guard let pdf = PDFDocument(url: url) else { return nil }
            for index in 0..<pdf.pageCount {
                let raw = pdf.page(at: index)?.string ?? ""
                pages.append(PaperPage(index: index, text: normalize(raw)))
            }
            let total = pages.reduce(0) { $0 + $1.text.count }
            needsOCR = total < 240
        } else {
            let text = extractTextFile(url: url, ext: ext)
            let chunks = chunkParagraphs(text)
            pages = chunks.enumerated().map { PaperPage(index: $0.offset, text: $0.element) }
        }

        let fullRaw = pages.map(\.text).joined(separator: "\n")
        guard !fullRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if needsOCR {
                return PaperDoc(path: url.path,
                                title: displayTitle(for: url),
                                pages: pages,
                                language: .other,
                                needsOCR: true,
                                truncated: false,
                                fullText: "",
                                charCount: 0,
                                captions: [:])
            }
            return nil
        }

        let language = detectLanguage(fullRaw)
        let captions = indexCaptions(pages: pages)
        let (capped, truncated) = capText(pages: pages)

        return PaperDoc(path: url.path,
                        title: displayTitle(for: url),
                        pages: pages,
                        language: language,
                        needsOCR: needsOCR,
                        truncated: truncated,
                        fullText: capped,
                        charCount: capped.count,
                        captions: captions)
    }

    // MARK: Format helpers

    private static func extractTextFile(url: URL, ext: String) -> String {
        if ["txt", "md"].contains(ext) {
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        if ext == "docx", let xml = run("/usr/bin/unzip", ["-p", url.path, "word/document.xml"]) {
            var s = xml
            s = s.replacingOccurrences(of: "</w:p>", with: "\n")
            s = s.replacingOccurrences(of: "<w:tab/>", with: "\t")
            s = s.replacingOccurrences(of: "<w:br/>", with: "\n")
            s = s.replacingOccurrences(of: "</w:tc>", with: "\t")
            s = s.replacingOccurrences(of: "</w:tr>", with: "\n")
            s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            return decodeEntities(s)
        }
        return run("/usr/bin/textutil", ["-convert", "txt", "-stdout", url.path]) ?? ""
    }

    private static func run(_ path: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func decodeEntities(_ s: String) -> String {
        var out = s
        for (k, v) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'"] {
            out = out.replacingOccurrences(of: k, with: v)
        }
        return out
    }

    private static func normalize(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "\u{000C}", with: "\n")
        out = out.replacingOccurrences(of: "\r\n", with: "\n")
        out = out.replacingOccurrences(of: "\r", with: "\n")
        out = out.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
        out = out.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func chunkParagraphs(_ text: String, target: Int = 2600) -> [String] {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return [] }
        var chunks: [String] = []
        var buffer = ""
        for paragraph in normalized.components(separatedBy: "\n\n") {
            if buffer.count + paragraph.count > target, !buffer.isEmpty {
                chunks.append(buffer)
                buffer = ""
            }
            buffer += (buffer.isEmpty ? "" : "\n\n") + paragraph
        }
        if !buffer.isEmpty { chunks.append(buffer) }
        return chunks.isEmpty ? [normalized] : chunks
    }

    // MARK: Language & captions

    static func detectLanguage(_ text: String) -> DocLanguage {
        let sample = String(text.prefix(6000))
        var cjk = 0
        var latin = 0
        for scalar in sample.unicodeScalars {
            if (0x4E00...0x9FFF).contains(scalar.value) { cjk += 1 }
            else if (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value) { latin += 1 }
        }
        if cjk > 120 && cjk * 6 > latin { return .chinese }
        if latin > 220 { return .english }
        if cjk > 40 { return .chinese }
        return .other
    }

    private static let captionRegex = try! NSRegularExpression(
        pattern: "^(?:Figure|Fig\\.?|Table|图|表)\\s*[0-9]+[A-Za-z]?\\s*[.:：|]?",
        options: [.caseInsensitive]
    )

    private static func indexCaptions(pages: [PaperPage]) -> [Int: String] {
        var result: [Int: String] = [:]
        for page in pages {
            let lines = page.text.components(separatedBy: "\n")
            var found: [String] = []
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let range = NSRange(location: 0, length: (trimmed as NSString).length)
                guard captionRegex.firstMatch(in: trimmed, options: [], range: range) != nil else { continue }
                // caption may wrap onto the next line
                var caption = trimmed
                if index + 1 < lines.count {
                    let next = lines[index + 1].trimmingCharacters(in: .whitespaces)
                    if !next.isEmpty, next.count > 20, caption.count < 160 {
                        caption += " " + next
                    }
                }
                found.append(caption)
            }
            if !found.isEmpty {
                result[page.index] = found.prefix(4).joined(separator: "\n")
            }
        }
        return result
    }

    // MARK: Text budget

    static func capText(pages: [PaperPage]) -> (String, Bool) {
        var joined = ""
        for page in pages {
            if !page.text.isEmpty {
                joined += "\n[p.\(page.index + 1)]\n" + page.text
            }
        }
        let limit = 60_000
        guard joined.count > limit else { return (joined, false) }
        let head = String(joined.prefix(44_000))
        let tail = String(joined.suffix(13_000))
        return (head + "\n\n[…中间部分因篇幅省略…]\n\n" + tail, true)
    }

    // MARK: Titles

    private static func displayTitle(for url: URL) -> String {
        if url.pathExtension.lowercased() == "pdf",
           let pdf = PDFDocument(url: url),
           let raw = pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String {
            let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.count >= 12, !title.lowercased().hasPrefix("microsoft word"), !title.hasSuffix(".pdf") {
                return title
            }
        }
        return url.deletingPathExtension().lastPathComponent
    }
}

// MARK: - Recent papers

enum Recents {
    static var roots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["Downloads", "Documents", "Desktop", "Downloads/文献", "Downloads/论文", "Documents/论文"]
            .map { home.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static var cache: (date: Date, entries: [LibraryEntry])?

    static func scan(limit: Int = 8) -> [LibraryEntry] {
        if let cache, Date().timeIntervalSince(cache.date) < 90 {
            return Array(cache.entries.prefix(limit))
        }
        var found: [LibraryEntry] = []
        let fm = FileManager.default
        for root in roots {
            guard let enumerator = fm.enumerator(at: root,
                                                 includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                                                 options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                 errorHandler: { _, _ in true }) else { continue }
            var seen = 0
            for case let url as URL in enumerator {
                seen += 1
                if seen > 4000 { break }
                guard ["pdf"].contains(url.pathExtension.lowercased()) else { continue }
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
                      values.isRegularFile == true else { continue }
                let size = Int64(values.fileSize ?? 0)
                guard size > 12_000 else { continue }
                found.append(LibraryEntry(url: url,
                                          title: url.deletingPathExtension().lastPathComponent,
                                          modified: values.contentModificationDate ?? .distantPast,
                                          size: size,
                                          pageCount: 0))
            }
        }
        var seenPaths = Set<String>()
        let entries = found
            .sorted { $0.modified > $1.modified }
            .filter { seenPaths.insert($0.url.path).inserted }
        cache = (Date(), entries)
        return Array(entries.prefix(limit))
    }
}
