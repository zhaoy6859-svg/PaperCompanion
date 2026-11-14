import AppKit
import Security

// MARK: - Keychain

enum Keychain {
    private static let service = "com.papercompanion.app"

    static func set(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Preferences

final class Prefs {
    static let shared = Prefs()
    private let defaults = ProcessInfo.processInfo.environment["PAPER_COMPANION_PREFS_SUITE"].flatMap { UserDefaults(suiteName: $0) } ?? UserDefaults.standard

    private enum Key {
        static let model = "model"
        static let baseURL = "baseURL"
        static let vision = "visionEnabled"
        static let sidebarWidth = "sidebarWidth"
        static let lastDocPath = "lastDocPath"
        static let lastPage = "lastPage"
        static let translationFraction = "translationFraction"
        static let translationFontSize = "translationFontSize"
        static let sidebarVisible = "sidebarVisible"
    }

    var model: String {
        get { defaults.string(forKey: Key.model) ?? "deepseek-chat" }
        set { defaults.set(newValue, forKey: Key.model) }
    }

    var baseURL: String {
        get {
            if let env = ProcessInfo.processInfo.environment["PAPER_COMPANION_BASE_URL"], !env.isEmpty { return env }
            return defaults.string(forKey: Key.baseURL) ?? "https://api.deepseek.com"
        }
        set { defaults.set(newValue, forKey: Key.baseURL) }
    }

    static let defaultTranslationPrompt = #"""
    精翻，不能机翻。请将原文翻译为【目标语言】，达到专业学术译者的质量：准确传达原意，表达自然，避免生硬直译；统一专业术语，保留原文的限定条件与不确定性；不遗漏、不增补、不擅自概括；保留段落结构、引用编号与图表编号。

    数学与排版要求：
    1. 所有公式、变量、符号都用 LaTeX 数学语法输出：行内用 $...$，独立公式用 $$...$$。
    2. 下标用 _、上标用 ^、分式用 \frac{}{}、希腊字母用 \alpha \beta 等命令，不要输出 Unicode 数学符号。
    3. PDF 提取的原文中公式常常是乱码字符，请以随附的页面图片为准还原公式的真实结构，不要照抄乱码。
    4. 表格用 Markdown 表格输出（| 列 | 列 |）。
    5. 随附两张图片分别是该页的上半页与下半页；抄写公式时请逐字核对上下标与运算符（尤其除号、负号、下标数字），不确定时保留原式结构，禁止臆造符号。
    6. 仅输出译文，不要解释、不要加标题。
    """#
    var translationLanguage: String {
        get { defaults.string(forKey: "translationLanguage") ?? "简体中文" }
        set { defaults.set(newValue, forKey: "translationLanguage") }
    }
    var translationPrompt: String {
        get { defaults.string(forKey: "translationPrompt") ?? Self.defaultTranslationPrompt }
        set { defaults.set(newValue, forKey: "translationPrompt") }
    }
    var translationCacheKey: String {
        // JSON preserves unambiguous boundaries between language and instructions.
        let data = try! JSONEncoder().encode([translationLanguage, translationPrompt, "continuous-layout-v5"])
        return String(decoding: data, as: UTF8.self)
    }

    /// Send cropped figure/table images to the model (requires a vision-capable model).
    var visionEnabled: Bool {
        get { defaults.object(forKey: Key.vision) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.vision) }
    }

    var sidebarWidth: CGFloat {
        get { let v = defaults.double(forKey: Key.sidebarWidth); return v > 0 ? CGFloat(v) : 420 }
        set { defaults.set(Double(newValue), forKey: Key.sidebarWidth) }
    }

    var translationFraction: CGFloat {
        get { let v = defaults.double(forKey: Key.translationFraction); return v > 0 ? CGFloat(v) : 0.48 }
        set { defaults.set(Double(newValue), forKey: Key.translationFraction) }
    }

    var translationFontSize: CGFloat {
        get { let v = defaults.double(forKey: Key.translationFontSize); return v > 0 ? CGFloat(v) : 13.5 }
        set { defaults.set(Double(newValue), forKey: Key.translationFontSize) }
    }

    var sidebarVisible: Bool {
        get { defaults.object(forKey: Key.sidebarVisible) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.sidebarVisible) }
    }

    var lastDocPath: String? {
        get { defaults.string(forKey: Key.lastDocPath) }
        set { defaults.set(newValue, forKey: Key.lastDocPath) }
    }

    var lastPage: Int {
        get { defaults.integer(forKey: Key.lastPage) }
        set { defaults.set(newValue, forKey: Key.lastPage) }
    }

    /// The key lives in a 0600 file inside the app's data directory, so no
    /// keychain ACL prompt can ever block the UI. A keychain entry written by
    /// older builds is imported once in the background.
    private var warmUpStarted = false

    private var keyFileURL: URL { Store.root.appendingPathComponent("credentials.json") }
    private var providerKeys: [String: String] = [:]

    private func readCredentials() -> [String: String] {
        guard let data = try? Data(contentsOf: keyFileURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        if let keys = obj["keys"] as? [String: String] {
            return keys.filter { !$0.value.isEmpty }
        }
        // v1 files had a single DeepSeek key.
        if let legacy = obj["apiKey"] as? String, !legacy.isEmpty {
            return ["deepseek": legacy]
        }
        return [:]
    }

    private func writeCredentials() {
        Store.prepare()
        let payload: [String: Any] = ["version": 2, "keys": providerKeys]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) else { return }
        try? data.write(to: keyFileURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFileURL.path)
    }

    init() {
        providerKeys = readCredentials()
    }

    // MARK: Providers

    var providerID: String {
        get { defaults.string(forKey: "providerID") ?? "deepseek" }
        set { defaults.set(newValue, forKey: "providerID") }
    }

    var provider: LLMProvider { LLMProviders.provider(providerID) }

    func key(for providerID: String) -> String {
        providerKeys[providerID] ?? ""
    }

    func setKey(_ key: String, for providerID: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { providerKeys.removeValue(forKey: providerID) }
        else { providerKeys[providerID] = trimmed }
        writeCredentials()
    }

    var apiKey: String {
        if let env = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !env.isEmpty { return env }
        return providerKeys[providerID] ?? ""
    }

    func setAPIKey(_ key: String) { setKey(key, for: providerID) }

    /// Base URL and model remembered per provider, so switching back keeps settings.
    func savedConfig(_ id: String) -> (baseURL: String, model: String)? {
        guard let data = defaults.data(forKey: "providerConfigs"),
              let dict = try? JSONDecoder().decode([String: [String: String]].self, from: data),
              let entry = dict[id],
              let base = entry["baseURL"], let model = entry["model"], !base.isEmpty, !model.isEmpty
        else { return nil }
        return (base, model)
    }

    func saveConfig(_ id: String, baseURL: String, model: String) {
        var dict: [String: [String: String]] = [:]
        if let data = defaults.data(forKey: "providerConfigs"),
           let stored = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
            dict = stored
        }
        dict[id] = ["baseURL": baseURL, "model": model]
        if let data = try? JSONEncoder().encode(dict) { defaults.set(data, forKey: "providerConfigs") }
    }

    /// Vision is only offered for providers known to accept image blocks.
    var usesVision: Bool { visionEnabled && provider.supportsVision }

    var hasAPIKey: Bool { !apiKey.isEmpty }

    /// One-time import of a keychain entry written by an older build.
    func warmUpKey(completion: (() -> Void)? = nil) {
        if ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"] != nil { completion?(); return }
        guard !warmUpStarted else { return }
        warmUpStarted = true
        guard providerKeys["deepseek"] == nil else {
            completion?()
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let stored = Keychain.get("deepseek-api-key") ?? ""
            DispatchQueue.main.async {
                if self.providerKeys["deepseek"] == nil, !stored.isEmpty {
                    self.providerKeys["deepseek"] = stored
                    self.writeCredentials()
                }
                completion?()
            }
        }
    }
}
