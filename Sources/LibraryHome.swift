import AppKit

func promptShelfText(title: String, confirm: String, value: String = "") -> String? {
    let alert = NSAlert()
    alert.messageText = title
    alert.addButton(withTitle: confirm)
    alert.addButton(withTitle: "取消")
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
    field.stringValue = value
    field.placeholderString = "书架名称"
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? nil : name
}

/// Home screen. An empty study keeps the welcome; once papers exist, this is the shelf.
final class LibraryHomeView: NSView, NSSearchFieldDelegate {
    var onOpen: (() -> Void)?
    var onResume: (() -> Void)?
    var onOpenPaper: ((URL) -> Void)?
    var onImportFolder: (() -> Void)?
    var onImportZotero: (() -> Void)?
    var onRelocate: ((URL) -> Void)?
    var onStatus: ((String, Bool) -> Void)?

    private let welcome = CompanionWelcomeView()
    private let study = NSView()
    private let rail = NSStackView()
    private let search = NSSearchField()
    private let zoteroButton = NSButton()
    private let scroll = NSScrollView()
    private let list = ShelfListView()
    private var index = ShelfIndex()
    private var filter: ShelfFilter = .all
    private var filterButtons: [ShelfFilterButton] = []
    private let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        welcome.onOpen = { [weak self] in self?.onOpen?() }
        welcome.onResume = { [weak self] in self?.onResume?() }

        study.translatesAutoresizingMaskIntoConstraints = false
        welcome.translatesAutoresizingMaskIntoConstraints = false
        addSubview(welcome)
        addSubview(study)
        NSLayoutConstraint.activate([
            welcome.leadingAnchor.constraint(equalTo: leadingAnchor),
            welcome.trailingAnchor.constraint(equalTo: trailingAnchor),
            welcome.topAnchor.constraint(equalTo: topAnchor),
            welcome.bottomAnchor.constraint(equalTo: bottomAnchor),
            study.leadingAnchor.constraint(equalTo: leadingAnchor),
            study.trailingAnchor.constraint(equalTo: trailingAnchor),
            study.topAnchor.constraint(equalTo: topAnchor),
            study.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        buildStudy()
        study.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func suspendShortcut() { welcome.setDefaultActionEnabled(false) }

    func focusSearch() {
        guard !study.isHidden else { return }
        window?.makeFirstResponder(search)
        search.selectText(nil)
    }

    func debugSetSearch(_ text: String) {
        search.stringValue = text
        reload()
    }

    func reload() {
        index = ShelfStore.loadMerged()
        if filterIDMissing() { filter = .all }
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let showWelcome = index.papers.isEmpty && query.isEmpty
        welcome.isHidden = !showWelcome
        welcome.setDefaultActionEnabled(showWelcome)
        study.isHidden = showWelcome
        if showWelcome {
            onStatus?("拖入一篇论文、一个文件夹，或按 ⌘O", true)
            return
        }
        rebuildRail()
        rebuildList()
        onStatus?("书房 · \(index.papers.count) 篇", false)
    }

    private func filterIDMissing() -> Bool {
        guard case .collection(let id) = filter else { return false }
        return !index.collections.contains { $0.id == id }
    }

    private func buildStudy() {
        study.wantsLayer = true
        study.layer?.backgroundColor = Theme.paperBackground.cgColor
        rail.orientation = .vertical
        rail.alignment = .leading
        rail.spacing = 4
        rail.translatesAutoresizingMaskIntoConstraints = false
        rail.edgeInsets = NSEdgeInsets(top: 18, left: 14, bottom: 16, right: 14)

        search.placeholderString = "搜索标题、笔记和提问"
        search.translatesAutoresizingMaskIntoConstraints = false
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.sendsWholeSearchString = true
        search.font = Theme.text(13)

        let open = NSButton.text("打开 PDF", target: self, action: #selector(openFile), symbol: "plus")
        let folder = NSButton.text("导入文件夹", target: self, action: #selector(importFolder), symbol: "folder")
        zoteroButton.title = "从 Zotero 导入"
        zoteroButton.bezelStyle = .rounded
        zoteroButton.controlSize = .regular
        zoteroButton.font = Theme.text(12, weight: .medium)
        zoteroButton.target = self
        zoteroButton.action = #selector(importZotero)
        zoteroButton.translatesAutoresizingMaskIntoConstraints = false
        zoteroButton.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let tools = NSStackView(views: [search, open, folder, zoteroButton])
        tools.orientation = .horizontal
        tools.alignment = .centerY
        tools.spacing = 8
        tools.translatesAutoresizingMaskIntoConstraints = false
        search.setContentHuggingPriority(.defaultLow, for: .horizontal)
        search.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = list

        let rule = SeparatorLine()
        rule.translatesAutoresizingMaskIntoConstraints = false
        study.addSubview(rail)
        study.addSubview(rule)
        study.addSubview(tools)
        study.addSubview(scroll)
        NSLayoutConstraint.activate([
            rail.leadingAnchor.constraint(equalTo: study.leadingAnchor),
            rail.topAnchor.constraint(equalTo: study.topAnchor),
            rail.bottomAnchor.constraint(equalTo: study.bottomAnchor),
            rail.widthAnchor.constraint(equalToConstant: 196),

            rule.leadingAnchor.constraint(equalTo: rail.trailingAnchor),
            rule.topAnchor.constraint(equalTo: study.topAnchor),
            rule.bottomAnchor.constraint(equalTo: study.bottomAnchor),
            rule.widthAnchor.constraint(equalToConstant: 1),

            tools.leadingAnchor.constraint(equalTo: rule.trailingAnchor, constant: 16),
            tools.trailingAnchor.constraint(equalTo: study.trailingAnchor, constant: -16),
            tools.topAnchor.constraint(equalTo: study.topAnchor, constant: 14),

            scroll.leadingAnchor.constraint(equalTo: rule.trailingAnchor),
            scroll.trailingAnchor.constraint(equalTo: study.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: tools.bottomAnchor, constant: 10),
            scroll.bottomAnchor.constraint(equalTo: study.bottomAnchor),
        ])
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        study.layer?.backgroundColor = Theme.paperBackground.cgColor
    }

    private func rebuildRail() {
        rail.arrangedSubviews.forEach {
            rail.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        filterButtons.removeAll()

        let title = NSTextField(labelWithString: "书房")
        title.font = Theme.display(22, weight: .bold)
        title.textColor = .labelColor
        let count = NSTextField(labelWithString: "\(index.papers.count) 篇论文留在原来的位置")
        count.font = Theme.text(11)
        count.textColor = .secondaryLabelColor
        count.lineBreakMode = .byWordWrapping
        count.maximumNumberOfLines = 2
        count.preferredMaxLayoutWidth = 164
        rail.addArrangedSubview(title)
        rail.addArrangedSubview(count)
        rail.setCustomSpacing(14, after: count)

        addFilter("全部", .all, symbol: "books.vertical")
        addFilter("有笔记", .noted, symbol: "pencil.and.outline")

        if !index.collections.isEmpty {
            let divider = SeparatorLine()
            divider.translatesAutoresizingMaskIntoConstraints = false
            divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
            divider.widthAnchor.constraint(equalToConstant: 168).isActive = true
            rail.addArrangedSubview(divider)
            rail.setCustomSpacing(8, after: divider)
        }
        for collection in index.collections {
            addFilter(collection.name, .collection(collection.id), symbol: "folder", collection: collection.id)
        }

        let create = NSButton(title: "新建书架", target: self, action: #selector(createShelf))
        create.bezelStyle = .inline
        create.isBordered = false
        create.font = Theme.text(12, weight: .medium)
        create.contentTintColor = Theme.accent
        create.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "新建书架")
        create.imagePosition = .imageLeading
        create.alignment = .left
        rail.addArrangedSubview(create)
        restyleRail()
        let zotero = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Zotero/storage")
        zoteroButton.isHidden = !FileManager.default.fileExists(atPath: zotero.path)
    }

    private func addFilter(_ title: String, _ filter: ShelfFilter, symbol: String, collection: UUID? = nil) {
        let button = ShelfFilterButton(title: title, symbol: symbol, filter: filter)
        button.target = self
        button.action = #selector(filterTapped(_:))
        button.widthAnchor.constraint(equalToConstant: 168).isActive = true
        if let collection {
            let menu = NSMenu()
            let rename = NSMenuItem(title: "重命名", action: #selector(renameShelf(_:)), keyEquivalent: "")
            rename.target = self
            rename.representedObject = collection
            let delete = NSMenuItem(title: "删除这层书架", action: #selector(deleteShelf(_:)), keyEquivalent: "")
            delete.target = self
            delete.representedObject = collection
            menu.addItem(rename)
            menu.addItem(delete)
            button.menu = menu
        }
        filterButtons.append(button)
        rail.addArrangedSubview(button)
    }

    private func restyleRail() {
        for button in filterButtons {
            button.chosen = button.filter == filter
        }
    }

    private func rebuildList() {
        let papers = ShelfStore.query(index.papers, text: search.stringValue, filter: filter)
        if papers.isEmpty {
            list.show([emptyNote()])
            return
        }
        list.show(papers.map { row(for: $0) })
    }

    private func emptyNote() -> NSView {
        let text: String
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            text = "没有找到「\(query)」"
        } else if case .noted = filter {
            text = "还没有划线或提问。打开一篇论文，选中一句就能记下来。"
        } else if case .collection = filter {
            text = "这层书架还空着。阅读时用菜单「文件 → 加入书架」放进来。"
        } else {
            text = "书房是空的。"
        }
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = Theme.text(13)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 420
        let wrap = NSView()
        label.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 18),
        ])
        return wrap
    }

    private func row(for paper: ShelfPaper) -> NSView {
        let row = ShelfRow(paper: paper, meta: meta(for: paper))
        row.toolTip = paper.path
        if paper.fileExists {
            row.onOpen = { [weak self] in self?.onOpenPaper?(URL(fileURLWithPath: paper.path)) }
        } else {
            row.onOpen = { [weak self] in self?.onRelocate?(URL(fileURLWithPath: paper.path)) }
        }
        row.onMenu = { [weak self] anchor in self?.popRowMenu(for: paper, anchor: anchor) }
        return row
    }

    private func meta(for paper: ShelfPaper) -> String {
        if !paper.fileExists { return "找不到文件 · 点这一行重新定位" }
        var bits: [String] = []
        bits.append(paper.pageCount > 0 ? "\(paper.pageCount) 页" : "未打开")
        if let raw = paper.readingLevel, let level = ReadingLevel(rawValue: raw) { bits.append(level.title) }
        if paper.highlightCount > 0 { bits.append("\(paper.highlightCount) 条划线") }
        if paper.threadCount > 0 { bits.append("\(paper.threadCount) 次提问") }
        let names = paper.collectionIDs.compactMap { id in index.collections.first { $0.id == id }?.name }
        if !names.isEmpty { bits.append(names.joined(separator: "、")) }
        if let opened = paper.lastOpenedAt {
            let delta = abs(opened.timeIntervalSinceNow)
            bits.append(delta < 45 ? "刚刚" : relative.localizedString(for: opened, relativeTo: Date()))
        } else {
            bits.append("还没读")
        }
        return bits.joined(separator: " · ")
    }

    private func popRowMenu(for paper: ShelfPaper, anchor: NSView) {
        let menu = NSMenu()
        if paper.fileExists {
            let open = item("打开", #selector(openPaperFromMenu(_:)), paper.path)
            menu.addItem(open)
            let reveal = item("在访达中显示", #selector(revealPaper(_:)), paper.path)
            menu.addItem(reveal)
        } else {
            menu.addItem(item("重新定位…", #selector(relocateFromMenu(_:)), paper.path))
        }
        menu.addItem(.separator())
        if index.collections.isEmpty {
            menu.addItem(withTitle: "还没有书架", action: nil, keyEquivalent: "")
        }
        for collection in index.collections {
            let entry = item(collection.name, #selector(toggleFromMenu(_:)), paper.path)
            entry.state = paper.collectionIDs.contains(collection.id) ? .on : .off
            entry.identifier = NSUserInterfaceItemIdentifier(collection.id.uuidString)
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(item("移出书房", #selector(removeFromMenu(_:)), paper.path))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.height), in: anchor)
    }

    private func item(_ title: String, _ action: Selector, _ path: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.representedObject = path
        return entry
    }

    func controlTextDidChange(_ obj: Notification) { rebuildList() }

    @objc private func filterTapped(_ sender: ShelfFilterButton) {
        filter = sender.filter
        restyleRail()
        rebuildList()
    }

    @objc private func openFile() { onOpen?() }
    @objc private func importFolder() { onImportFolder?() }
    @objc private func importZotero() { onImportZotero?() }

    @objc private func createShelf() {
        guard let name = promptShelfText(title: "新建书架", confirm: "创建") else { return }
        guard ShelfStore.createCollection(named: name) != nil else {
            onStatus?("已经有同名书架", false)
            return
        }
        reload()
    }

    @objc private func renameShelf(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let current = index.collections.first(where: { $0.id == id })?.name,
              let name = promptShelfText(title: "重命名书架", confirm: "保存", value: current) else { return }
        if !ShelfStore.renameCollection(id: id, to: name) {
            onStatus?("这个名字已经被用了", false)
            return
        }
        reload()
    }

    @objc private func deleteShelf(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let name = index.collections.first(where: { $0.id == id })?.name else { return }
        let alert = NSAlert()
        alert.messageText = "删除书架「\(name)」？"
        alert.informativeText = "论文会留在书房里，只是不再属于这层书架。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        ShelfStore.deleteCollection(id: id)
        reload()
    }

    @objc private func openPaperFromMenu(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        onOpenPaper?(URL(fileURLWithPath: path))
    }

    @objc private func revealPaper(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @objc private func relocateFromMenu(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        onRelocate?(URL(fileURLWithPath: path))
    }

    @objc private func toggleFromMenu(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String,
              let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        ShelfStore.toggle(path: path, collection: id)
        reload()
    }

    @objc private func removeFromMenu(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        ShelfStore.removePaper(path: path)
        reload()
    }
}

final class ShelfFilterButton: NSButton {
    let filter: ShelfFilter
    var chosen = false { didSet { refresh() } }

    init(title: String, symbol: String, filter: ShelfFilter) {
        self.filter = filter
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 8
        alignment = .left
        imagePosition = .imageLeading
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        font = Theme.text(13, weight: .medium)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 30).isActive = true
        lineBreakMode = .byTruncatingTail
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func refresh() {
        contentTintColor = chosen ? Theme.accent : .labelColor
        layer?.backgroundColor = (chosen ? Theme.accent.withAlphaComponent(0.14) : .clear).cgColor
        font = Theme.text(13, weight: chosen ? .semibold : .medium)
    }
}

final class ShelfRow: NSView {
    var onOpen: (() -> Void)?
    var onMenu: ((NSView) -> Void)?
    private let menuButton = NSButton()
    private var hover = false

    init(paper: ShelfPaper, meta: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        menuButton.iconSetup("ellipsis", tip: "更多", target: self, action: #selector(showMenu), size: 26)
        let title = NSTextField(labelWithString: paper.title)
        title.font = Theme.text(14, weight: .semibold)
        title.textColor = paper.fileExists ? .labelColor : .secondaryLabelColor
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 2
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let detail = NSTextField(labelWithString: meta)
        detail.font = Theme.text(11.5)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for view in [title, detail, menuButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            menuButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            menuButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            title.trailingAnchor.constraint(equalTo: menuButton.leadingAnchor, constant: -8),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            detail.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10),
        ])
        refreshFill()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hover = true; refreshFill() }
    override func mouseExited(with event: NSEvent) { hover = false; refreshFill() }

    override func mouseDown(with event: NSEvent) {
        onOpen?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func refreshFill() {
        let base = hover ? Theme.accent.withAlphaComponent(0.08) : Theme.cardBackground
        layer?.backgroundColor = base.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = Theme.hairline.cgColor
    }

    @objc private func showMenu() { onMenu?(menuButton) }
}

final class ShelfListView: NSView {
    override var isFlipped: Bool { true }
    private var rows: [NSView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizingMask = [.width]
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ views: [NSView]) {
        rows.forEach { $0.removeFromSuperview() }
        rows = views
        for row in rows {
            row.translatesAutoresizingMaskIntoConstraints = true
            addSubview(row)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = max(bounds.width, enclosingScrollView?.contentSize.width ?? 0)
        var y: CGFloat = 4
        for row in rows {
            row.frame = NSRect(x: 14, y: y, width: max(120, width - 28), height: 72)
            y += 80
        }
        let height = max(y + 12, enclosingScrollView?.contentView.bounds.height ?? 0)
        let size = NSSize(width: width, height: height)
        if frame.size != size { setFrameSize(size) }
    }
}
