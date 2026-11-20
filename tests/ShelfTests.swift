import Foundation

@main struct ShelfTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pc-shelf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        setenv("PAPER_COMPANION_HOME", root.path, 1)
        defer { try? FileManager.default.removeItem(at: root) }

        let attention = sample(path: "/tmp/attention.pdf", title: "Attention Is All You Need", excerpt: "transformer self-attention\n划线里的句子", notes: 2, questions: 1)
        let climate = sample(path: "/tmp/climate.pdf", title: "Land use and climate", excerpt: "erosion by water", notes: 0, questions: 0)
        var unread = sample(path: "/tmp/draft.pdf", title: "未读草稿", excerpt: "草稿", notes: 0, questions: 0)
        unread.lastOpenedAt = nil

        var papers = [attention, climate]
        let shelf = UUID()
        papers[0].collectionIDs = [shelf]

        let byTitle = ShelfStore.query(papers, text: "attention transformer", filter: .all)
        assert(byTitle.map(\.id) == [attention.id], "all terms must match title and excerpt")
        assert(ShelfStore.query(papers, text: "attention climate", filter: .all).isEmpty, "terms are AND")
        assert(ShelfStore.query(papers, text: "划线里的句子", filter: .all).map(\.id) == [attention.id])
        assert(ShelfStore.query(papers, text: "", filter: .noted).map(\.id) == [attention.id])
        assert(ShelfStore.query(papers, text: "", filter: .collection(shelf)).map(\.id) == [attention.id])
        assert(ShelfStore.query(papers, text: "", filter: .collection(UUID())).isEmpty)

        let sorted = ShelfStore.query([unread, attention], text: "", filter: .all)
        assert(sorted.first?.id == attention.id, "unread papers sort after ones that were opened")

        let doc = PaperDoc(path: "/tmp/pc-shelf-remember.pdf", title: "记住我", pages: [PaperPage(index: 0, text: "第一页讲梯度")], language: .english, needsOCR: false, truncated: false, fullText: "第一页讲梯度", charCount: 6, captions: [:])
        var state = DocState(doc: doc)
        state.highlights = [PaperHighlight(page: 0, rects: [], color: .yellow, style: nil, quote: "梯度下降", threadID: nil)]
        state.threads = [AskThread(kind: .general, page: 0, quote: nil, question: "为什么要归一化", answer: "", imageFile: nil, highlightID: nil)]
        ShelfStore.remember(state)
        let stored = ShelfStore.read().papers.first { $0.path == doc.path }
        assert(stored?.title == "记住我")
        assert(stored?.highlightCount == 1 && stored?.threadCount == 1)
        assert(stored?.excerpt.contains("梯度下降") == true)
        assert(stored?.excerpt.contains("为什么要归一化") == true)
        ShelfStore.notePage(path: doc.path, page: 4)
        assert(ShelfStore.lastPage(for: doc.path) == 4)
        ShelfStore.notePage(path: doc.path, page: 4)
        assert(ShelfStore.lastPage(for: doc.path) == 4)

        let created = ShelfStore.createCollection(named: "  课程论文  ")
        assert(created?.name == "课程论文")
        assert(ShelfStore.createCollection(named: "课程论文") == nil, "duplicate names are refused")
        assert(ShelfStore.toggle(path: doc.path, collection: created!.id))
        assert(ShelfStore.membership(path: doc.path) == [created!.id])
        assert(ShelfStore.renameCollection(id: created!.id, to: "研讨班"))
        ShelfStore.deleteCollection(id: created!.id)
        assert(ShelfStore.read().collections.isEmpty)
        assert(ShelfStore.membership(path: doc.path).isEmpty)

        ShelfStore.removePaper(path: doc.path)
        let folder = root.appendingPathComponent("incoming", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let kept = folder.appendingPathComponent("kept.pdf")
        try Data("pdf".utf8).write(to: kept)
        let imported = ShelfStore.importFolder(folder)
        assert(imported.added == 1 && imported.skipped == 0, "import counts new pdfs")
        assert(ShelfStore.importFolder(folder).skipped == 1)
        assert(!ShelfStore.read().papers.contains { $0.path == doc.path }, "dismissed papers stay out until opened")

        let revived = DocState(doc: doc)
        ShelfStore.remember(revived)
        assert(ShelfStore.read().papers.contains { $0.path == doc.path }, "opening a paper puts it back on the shelf")
        assert(!ShelfStore.read().dismissedPaths.contains(doc.path))

        let mppi = sample(path: "/tmp/mppi.pdf", title: "Multi-Source Prediction-Powered Inference", excerpt: "ppi", notes: 0, questions: 0)
        let other = sample(path: "/tmp/other.pdf", title: "Land use and climate", excerpt: "erosion", notes: 0, questions: 0)
        let opened = ShelfStore.paperToOpen("帮我打开mppi哪篇文献", in: [mppi, other])
        assert(opened?.path == mppi.path, "mppi opens the prediction-powered paper")
        assert(ShelfStore.paperToOpen("这段在说什么", in: [mppi]) == nil)
        let parsed = ShelfStore.consumeOpens("已经找到。\n[[open:mppi]]")
        assert(parsed.queries == ["mppi"])
        assert(!parsed.text.contains("[[open:"))

        print("PASS: search, shelves, dismiss, import, page memory")
    }

    static func sample(path: String, title: String, excerpt: String, notes: Int, questions: Int) -> ShelfPaper {
        ShelfPaper(id: path, path: path, title: title, addedAt: Date(), lastOpenedAt: Date(), lastPage: 1,
                   pageCount: 8, readingLevel: nil, highlightCount: notes, threadCount: questions,
                   collectionIDs: [], excerpt: excerpt)
    }

}
