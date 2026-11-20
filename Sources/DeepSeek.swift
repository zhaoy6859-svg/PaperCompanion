import Foundation

enum LLMError: LocalizedError {
    case badURL
    case http(Int, String)
    case noAPIKey
    case empty

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "接口地址不对，检查一下设置里的 Base URL"
        case let .http(code, body):
            switch code {
            case 401:
                return "API Key 无效或已过期（401）。去 platform.deepseek.com 复制一个新的 sk- key。"
            case 402:
                return "账户余额不足（402）。"
            case 429:
                return "请求太频繁了（429），等几秒再问。"
            case 400:
                return "请求被拒绝（400）：\(body.prefix(200))"
            case -1:
                return "网络请求失败：\(body.prefix(160))"
            default:
                return "接口返回 \(code)：\(body.prefix(200))"
            }
        case .noAPIKey:
            return "还没有填 API Key"
        case .empty:
            return "模型没有返回内容"
        }
    }
}

final class LLMClient {
    private var requestID = UUID()
    private var task: Task<Void, Never>?

    var isRunning: Bool { task != nil }

    func cancel() {
        requestID = UUID()
        task?.cancel()
        task = nil
    }

    /// Streams a chat completion. Callbacks fire on the main thread.
    func stream(apiKey: String,
                baseURL: String,
                model: String,
                messages: [[String: Any]],
                temperature: Double = 0.25,
                reasoning: ReasoningEffort? = nil,
                maxTokens: Int? = nil,
                timeout: TimeInterval = 180,
                onDelta: @escaping (String) -> Void,
                onFinish: @escaping (Result<String, Error>) -> Void) {
        cancel()
        let token = requestID
        guard !apiKey.isEmpty else {
            DispatchQueue.main.async { onFinish(.failure(LLMError.noAPIKey)) }
            return
        }
        guard let url = Self.endpoint(baseURL) else {
            DispatchQueue.main.async { onFinish(.failure(LLMError.badURL)) }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": true,
            "temperature": temperature,
        ]
        if model.contains("reasoner") {
            body.removeValue(forKey: "temperature")
        }
        if let reasoning, let value = reasoning.wireValue(providerID: Prefs.shared.providerID) {
            body["reasoning_effort"] = value
            if Prefs.shared.providerID == "deepseek", reasoning == .none {
                body["thinking"] = ["type": "disabled"]
            }
            if Prefs.shared.providerID == "deepseek", reasoning != .none {
                body.removeValue(forKey: "temperature")
            }
        }
        if let maxTokens {
            body["max_tokens"] = maxTokens
        }
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else {
            DispatchQueue.main.async { onFinish(.failure(LLMError.badURL)) }
            return
        }
        request.httpBody = payload

        task = Task { [weak self] in
            var full = ""
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw LLMError.empty
                }
                Debug.log("http status=\(http.statusCode)")
                guard http.statusCode == 200 else {
                    var raw = ""
                    for try await line in bytes.lines {
                        raw += line
                        if raw.count > 4000 { break }
                    }
                    throw LLMError.http(http.statusCode, raw)
                }

                var seen = 0
                for try await line in bytes.lines {
                    if Task.isCancelled { break }
                    seen += 1
                    if seen == 1 { Debug.log("first line: \(line.prefix(80))") }
                    guard line.hasPrefix("data:") else { continue }
                    let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    if payload == "[DONE]" { Debug.log("saw DONE"); break }
                    guard let data = payload.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = obj["choices"] as? [[String: Any]],
                          let delta = choices.first?["delta"] as? [String: Any] else { continue }
                    if let piece = delta["content"] as? String, !piece.isEmpty {
                        full += piece
                        DispatchQueue.main.async { [weak self] in
                            guard self?.requestID == token else { return }; onDelta(piece)
                        }
                    }
                }
                Debug.log("stream loop ended, chars=\(full.count)")
                let answer = full
                await MainActor.run { [weak self] in
                    guard self?.requestID == token else { return }
                    if answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onFinish(.failure(LLMError.empty))
                    } else {
                        onFinish(.success(answer))
                    }
                }
            } catch is CancellationError {
                Debug.log("cancelled")
                // Cancellation never marks a partial answer as complete.
            } catch {
                let ns = error as NSError
                Debug.log("stream error domain=\(ns.domain) code=\(ns.code) url=\(request.url?.absoluteString ?? "-")")
                let message = error.localizedDescription
                await MainActor.run { [weak self] in
                    guard self?.requestID == token else { return }
                    onFinish(.failure(LLMError.http(-1, message)))
                }
            }
            await MainActor.run { [weak self] in
                if self?.requestID == token { self?.task = nil }
            }
        }
    }

    /// Quick connectivity check used by the settings window.
    func test(apiKey: String, baseURL: String, model: String, completion: @escaping (String) -> Void) {
        guard let url = Self.endpoint(baseURL) else {
            completion("地址无效")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": "只回复两个字：可用"]],
            "stream": false,
            "max_tokens": 8,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { data, response, error in
            var text = ""
            if let error {
                text = "连接失败：\(error.localizedDescription)"
            } else if let http = response as? HTTPURLResponse {
                if http.statusCode == 200, let data,
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = obj["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    text = "通了 ✓ 模型回复：\(content.prefix(20))"
                } else if http.statusCode == 401 {
                    text = "Key 无效（401）"
                } else {
                    let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    text = "接口 \(http.statusCode)：\(body.prefix(120))"
                }
            } else {
                text = "没有响应"
            }
            DispatchQueue.main.async { completion(text) }
        }.resume()
    }

    private static func endpoint(_ baseURL: String) -> URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/chat/completions") { return URL(string: base) }
        if !base.hasSuffix("/v1") && !base.contains("/v1/") { base += "/v1" }
        return URL(string: base + "/chat/completions")
    }
}
