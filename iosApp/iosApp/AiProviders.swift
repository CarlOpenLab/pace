import Foundation

/// 一句话记账能直接用的服务商（都是 OpenAI 兼容接口）。
/// 地址存的是 base（一般写到 /v1）；用户也可以粘完整的 /chat/completions，
/// 两种都认，对话和模型列表都从同一个地址推出来。
struct AiProvider: Identifiable, Hashable {
    let id: String
    let name: String
    let endpoint: String

    static let custom = AiProvider(id: "custom", name: "自定义", endpoint: "")

    /// 顺序与 Copy.Ai.Settings.Provider.options 对齐。
    static let presets: [AiProvider] = [
        AiProvider(id: "deepseek", name: "DeepSeek", endpoint: "https://api.deepseek.com/v1"),
        AiProvider(id: "moonshot", name: "Kimi", endpoint: "https://api.moonshot.cn/v1"),
        AiProvider(id: "openai", name: "OpenAI", endpoint: "https://api.openai.com/v1"),
        AiProvider(id: "zhipu", name: "智谱", endpoint: "https://open.bigmodel.cn/api/paas/v4"),
        AiProvider(id: "openrouter", name: "OpenRouter", endpoint: "https://openrouter.ai/api/v1"),
        AiProvider(id: "dashscope", name: "通义千问", endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1")
    ]

    /// 地址和某个预置一致才认成那个服务商，用户手改过就算自定义。
    static func matching(endpoint: String) -> AiProvider {
        let normalized = normalize(endpoint)
        guard !normalized.isEmpty else { return custom }
        return presets.first { normalize($0.endpoint) == normalized } ?? custom
    }

    /// 比较时抹掉结尾的 /chat/completions 和斜杠，这样完整路径也能对上预置。
    static func normalize(_ endpoint: String) -> String {
        var text = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while text.hasSuffix("/") { text.removeLast() }
        let suffix = "/chat/completions"
        if text.hasSuffix(suffix) { text.removeLast(suffix.count) }
        return text
    }

    private static func base(from endpoint: String) -> String? {
        var text = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let url = URL(string: text),
              url.scheme == "https" || url.scheme == "http" else { return nil }
        while text.hasSuffix("/") { text.removeLast() }
        let suffix = "/chat/completions"
        if text.hasSuffix(suffix) { text.removeLast(suffix.count) }
        return text.isEmpty ? nil : text
    }

    /// 对话接口：…/chat/completions；用户只写了 base 就补上。
    static func chatURL(from endpoint: String) -> URL? {
        guard let base = base(from: endpoint) else { return nil }
        return URL(string: base + "/chat/completions")
    }

    /// 模型列表接口：…/models。
    static func modelsURL(from endpoint: String) -> URL? {
        guard let base = base(from: endpoint) else { return nil }
        return URL(string: base + "/models")
    }
}

/// 用用户自己的 Key 去服务商读模型列表。读不到时调用方回退到手填模型名。
enum AiModelList {
    enum Failure: Error {
        case noAddress
        case noKey
        case unreachable
        case keyRejected
        case noModelList
        case server
        case empty
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: config)
    }()

    static func fetch(endpoint: String, key: String) async -> Result<[String], Failure> {
        guard let url = AiProvider.modelsURL(from: endpoint) else { return .failure(.noAddress) }
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return .failure(.noKey) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .failure(.unreachable)
        }

        guard let http = response as? HTTPURLResponse else { return .failure(.unreachable) }
        switch http.statusCode {
        case 200...299:
            let ids = parseIDs(from: data)
            return ids.isEmpty ? .failure(.empty) : .success(ids)
        case 401, 403:
            return .failure(.keyRejected)
        case 404, 405:
            return .failure(.noModelList)
        default:
            return .failure(.server)
        }
    }

    /// 主流的写法是 {"data":[{"id":"…"}]}，也有直接给 ["…","…"] 的，两种都认。
    private static func parseIDs(from data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let object = root as? [String: Any], let items = object["data"] as? [[String: Any]] {
            return sorted(items.compactMap { $0["id"] as? String })
        }
        if let object = root as? [String: Any], let items = object["models"] as? [[String: Any]] {
            return sorted(items.compactMap { $0["id"] as? String ?? $0["name"] as? String })
        }
        if let array = root as? [String] {
            return sorted(array)
        }
        return []
    }

    private static func sorted(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        let unique = ids
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        return unique.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
