import Foundation

/// Chat providers that speak the OpenAI-compatible `/chat/completions` protocol.
/// Every preset is only a starting point: base URL and model stay editable.
struct LLMProvider: Identifiable, Equatable {
    let id: String
    let name: String
    let baseURL: String
    let models: [String]
    let keyHint: String
    let supportsVision: Bool
    let isLocal: Bool
}

/// How hard the model should think before answering. DeepSeek accepts
/// none / low / high / max. Other OpenAI-compatible services get the closest
/// value they usually accept; max is sent as high.
enum ReasoningEffort: String, CaseIterable {
    case none, low, high, max

    var title: String {
        switch self {
        case .none: return "关闭"
        case .low: return "低"
        case .high: return "高"
        case .max: return "最强"
        }
    }

    func wireValue(providerID: String) -> String? {
        if providerID == "deepseek" { return rawValue }
        switch self {
        case .none: return nil
        case .low: return "low"
        case .high, .max: return "high"
        }
    }
}

enum LLMProviders {
    static let all: [LLMProvider] = [
        LLMProvider(id: "deepseek",
                    name: "DeepSeek（推荐）",
                    baseURL: "https://api.deepseek.com",
                    models: ["deepseek-flash", "deepseek-v4-pro", "deepseek-chat", "deepseek-reasoner"],
                    keyHint: "platform.deepseek.com 的 sk- key",
                    supportsVision: true,
                    isLocal: false),
        LLMProvider(id: "openai",
                    name: "OpenAI",
                    baseURL: "https://api.openai.com/v1",
                    models: ["gpt-5", "gpt-5-mini", "gpt-4.1", "o4-mini"],
                    keyHint: "platform.openai.com 的 sk- key",
                    supportsVision: true,
                    isLocal: false),
        LLMProvider(id: "anthropic",
                    name: "Anthropic Claude",
                    baseURL: "https://api.anthropic.com/v1",
                    models: ["claude-sonnet-4-5", "claude-opus-4-1", "claude-haiku-4-5"],
                    keyHint: "console.anthropic.com 的 sk-ant- key",
                    supportsVision: true,
                    isLocal: false),
        LLMProvider(id: "gemini",
                    name: "Google Gemini",
                    baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
                    models: ["gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.0-flash"],
                    keyHint: "aistudio.google.com 的 API key",
                    supportsVision: true,
                    isLocal: false),
        LLMProvider(id: "qwen",
                    name: "通义千问（百炼）",
                    baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                    models: ["qwen3-max", "qwen-plus", "qwen-vl-max"],
                    keyHint: "阿里云百炼的 sk- key",
                    supportsVision: true,
                    isLocal: false),
        LLMProvider(id: "moonshot",
                    name: "Moonshot Kimi",
                    baseURL: "https://api.moonshot.cn/v1",
                    models: ["kimi-k2-0905-preview", "moonshot-v1-32k"],
                    keyHint: "platform.moonshot.cn 的 sk- key",
                    supportsVision: true,
                    isLocal: false),
        LLMProvider(id: "zhipu",
                    name: "智谱 GLM",
                    baseURL: "https://open.bigmodel.cn/api/paas/v4",
                    models: ["glm-4.6", "glm-4.5-air", "glm-4v-plus"],
                    keyHint: "bigmodel.cn 的 API key",
                    supportsVision: true,
                    isLocal: false),
        LLMProvider(id: "openrouter",
                    name: "OpenRouter（聚合）",
                    baseURL: "https://openrouter.ai/api/v1",
                    models: ["deepseek/deepseek-chat", "anthropic/claude-sonnet-4.5", "openai/gpt-5"],
                    keyHint: "openrouter.ai 的 sk-or- key",
                    supportsVision: true,
                    isLocal: false),
        LLMProvider(id: "siliconflow",
                    name: "硅基流动",
                    baseURL: "https://api.siliconflow.cn/v1",
                    models: ["deepseek-ai/DeepSeek-V3.2", "Qwen/Qwen3-235B-A22B"],
                    keyHint: "siliconflow.cn 的 sk- key",
                    supportsVision: true,
                    isLocal: false),
        LLMProvider(id: "ollama",
                    name: "本地 Ollama",
                    baseURL: "http://localhost:11434/v1",
                    models: ["qwen3:8b", "llama3.2", "deepseek-r1:7b"],
                    keyHint: "本地模型无需 key，留空即可",
                    supportsVision: false,
                    isLocal: true),
        LLMProvider(id: "custom",
                    name: "自定义（OpenAI 兼容）",
                    baseURL: "",
                    models: [],
                    keyHint: "任意 OpenAI 兼容服务的 key",
                    supportsVision: true,
                    isLocal: false),
    ]

    static func provider(_ id: String) -> LLMProvider {
        all.first(where: { $0.id == id }) ?? all[0]
    }
}
