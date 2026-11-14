import AppKit

final class SettingsWindowController: NSWindowController {
    private let prefs = Prefs.shared
    private let providerPopup = NSPopUpButton()
    private let baseURLField = NSTextField()
    private let modelCombo = NSComboBox()
    private let apiKeyField = NSSecureTextField()
    private let keyHintLabel = NSTextField(labelWithString: "")
    private let visionSwitch = NSButton(checkboxWithTitle: "把框选的图表/公式图片发给模型（需模型支持视觉）", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let client = LLMClient()
    private var currentProviderID = "deepseek"

    var onSave: (() -> Void)?

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 590),
                              styleMask: [.titled, .closable],
                              backing: .buffered,
                              defer: false)
        window.title = "论文伴侣 · 模型设置"
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        build()
        load()
    }

    private func build() {
        guard let window else { return }
        let content = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "模型服务")
        title.font = Theme.text(17, weight: .semibold)

        let hint = NSTextField(labelWithString: "所有服务都走 OpenAI 兼容协议；DeepSeek 是默认。Key 只存本机（0600 文件）。")
        hint.font = Theme.text(11.5)
        hint.textColor = .secondaryLabelColor
        hint.maximumNumberOfLines = 2

        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.alignment = .top
        headerRow.spacing = 16
        let headerText = NSStackView(views: [title, hint])
        headerText.orientation = .vertical
        headerText.alignment = .leading
        headerText.spacing = 6
        headerRow.addArrangedSubview(headerText)
        if let image = CompanionArt.settings {
            let mascot = NSImageView()
            mascot.image = image
            mascot.imageScaling = .scaleProportionallyUpOrDown
            mascot.translatesAutoresizingMaskIntoConstraints = false
            mascot.widthAnchor.constraint(equalToConstant: 62).isActive = true
            mascot.heightAnchor.constraint(equalToConstant: 62).isActive = true
            headerRow.addArrangedSubview(mascot)
        }

        for provider in LLMProviders.all {
            providerPopup.addItem(withTitle: provider.name)
            providerPopup.lastItem?.representedObject = provider.id
        }
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged)

        baseURLField.placeholderString = "https://api.deepseek.com"
        baseURLField.font = Theme.mono(11.5)
        modelCombo.font = Theme.mono(11.5)
        modelCombo.isEditable = true
        modelCombo.completes = true
        modelCombo.numberOfVisibleItems = 6
        apiKeyField.font = Theme.mono(11.5)

        for control in [providerPopup, baseURLField, modelCombo, apiKeyField] as [NSView] {
            control.translatesAutoresizingMaskIntoConstraints = false
            control.widthAnchor.constraint(equalToConstant: 468).isActive = true
            control.heightAnchor.constraint(equalToConstant: 28).isActive = true
        }

        keyHintLabel.font = Theme.text(10.5)
        keyHintLabel.textColor = .tertiaryLabelColor

        visionSwitch.font = Theme.text(12)

        statusLabel.font = Theme.text(11.5)
        statusLabel.textColor = .secondaryLabelColor

        let testButton = NSButton(title: "测试连接", target: self, action: #selector(test))
        testButton.bezelStyle = .rounded
        let saveButton = NSButton(title: "保存", target: self, action: #selector(save))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        let closeButton = NSButton(title: "关闭", target: self, action: #selector(closeWindow))
        closeButton.bezelStyle = .rounded
        let buttons = NSStackView(views: [testButton, saveButton, closeButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        stack.addArrangedSubview(headerRow)
        stack.addArrangedSubview(spacer(8))
        stack.addArrangedSubview(fieldLabel("模型服务"))
        stack.addArrangedSubview(providerPopup)
        stack.addArrangedSubview(fieldLabel("Base URL（OpenAI 兼容接口）"))
        stack.addArrangedSubview(baseURLField)
        stack.addArrangedSubview(fieldLabel("模型（可直接输入任意模型名）"))
        stack.addArrangedSubview(modelCombo)
        stack.addArrangedSubview(fieldLabel("API Key"))
        stack.addArrangedSubview(apiKeyField)
        stack.addArrangedSubview(keyHintLabel)
        stack.addArrangedSubview(spacer(4))
        stack.addArrangedSubview(visionSwitch)
        stack.addArrangedSubview(spacer(6))
        stack.addArrangedSubview(statusLabel)
        stack.addArrangedSubview(buttons)

        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
        ])
        window.contentView = content
    }

    private func fieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = Theme.text(11.5, weight: .medium)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func spacer(_ height: CGFloat) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    private func load() {
        currentProviderID = prefs.providerID
        selectProvider(currentProviderID, fillFields: true)
        if let saved = prefs.savedConfig(currentProviderID) {
            baseURLField.stringValue = saved.baseURL
            modelCombo.stringValue = saved.model
        } else if currentProviderID == "deepseek" {
            // Existing installs kept the DeepSeek endpoint and model here.
            baseURLField.stringValue = prefs.baseURL
            modelCombo.stringValue = prefs.model
        }
        apiKeyField.stringValue = prefs.key(for: currentProviderID)
        visionSwitch.state = prefs.visionEnabled ? .on : .off
        applyProviderTraits()
        statusLabel.stringValue = prefs.apiKey.isEmpty ? "还没填 Key，问答与翻译还不能用。" : ""
    }

    private func selectProvider(_ id: String, fillFields: Bool) {
        guard let index = LLMProviders.all.firstIndex(where: { $0.id == id }) else { return }
        providerPopup.selectItem(at: index)
        currentProviderID = id
        let provider = LLMProviders.all[index]
        keyHintLabel.stringValue = "· " + provider.keyHint
        modelCombo.removeAllItems()
        modelCombo.addItems(withObjectValues: provider.models)
        if fillFields {
            if let saved = prefs.savedConfig(id) {
                baseURLField.stringValue = saved.baseURL
                modelCombo.stringValue = saved.model
            } else {
                if !provider.baseURL.isEmpty { baseURLField.stringValue = provider.baseURL }
                if let first = provider.models.first { modelCombo.stringValue = first }
            }
            apiKeyField.stringValue = prefs.key(for: id)
        }
        applyProviderTraits()
    }

    private func applyProviderTraits() {
        let provider = LLMProviders.provider(currentProviderID)
        visionSwitch.isEnabled = provider.supportsVision
        if !provider.supportsVision { visionSwitch.state = .off }
        apiKeyField.isEnabled = true
    }

    @objc private func providerChanged() {
        currentProviderID = providerPopup.selectedItem?.representedObject as? String ?? "deepseek"
        selectProvider(currentProviderID, fillFields: true)
        statusLabel.stringValue = ""
    }

    @objc private func save() {
        let provider = LLMProviders.provider(currentProviderID)
        prefs.providerID = provider.id
        let base = baseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        prefs.baseURL = base.isEmpty ? provider.baseURL : base
        prefs.model = modelCombo.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (provider.models.first ?? "deepseek-chat")
            : modelCombo.stringValue
        prefs.saveConfig(provider.id, baseURL: prefs.baseURL, model: prefs.model)
        prefs.setKey(apiKeyField.stringValue, for: provider.id)
        prefs.visionEnabled = provider.supportsVision && visionSwitch.state == .on
        statusLabel.stringValue = "已保存 ✓"
        statusLabel.textColor = .systemGreen
        onSave?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.statusLabel.stringValue = ""
            self?.statusLabel.textColor = .secondaryLabelColor
        }
    }

    @objc private func test() {
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "测试中…"
        let base = baseURLField.stringValue.isEmpty ? LLMProviders.provider(currentProviderID).baseURL : baseURLField.stringValue
        let model = modelCombo.stringValue.isEmpty ? (LLMProviders.provider(currentProviderID).models.first ?? "") : modelCombo.stringValue
        client.test(apiKey: apiKeyField.stringValue, baseURL: base, model: model) { [weak self] result in
            self?.statusLabel.stringValue = result
            self?.statusLabel.textColor = result.contains("✓") ? .systemGreen : .systemOrange
        }
    }

    @objc private func closeWindow() {
        window?.orderOut(nil)
    }
}
