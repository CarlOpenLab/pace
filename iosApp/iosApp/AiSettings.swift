import Foundation
import Security

/// BYOK 模型配置（设置 → AI 一句话记账）。
/// 接口地址和模型名放 UserDefaults；Key 只进钥匙串，不写配置文件、不进导出、不进日志。
struct AiConfig {
    var endpoint: String
    var model: String
    var key: String

    var isComplete: Bool {
        !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !key.isEmpty
    }
}

@MainActor
final class AiSettings: ObservableObject {
    static let shared = AiSettings()

    private enum Key {
        static let enabled = "ai.enabled"
        static let endpoint = "ai.endpoint"
        static let model = "ai.model"
    }

    private let defaults = UserDefaults.standard

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Key.enabled) }
    }

    @Published var endpoint: String {
        didSet { defaults.set(endpoint, forKey: Key.endpoint) }
    }

    @Published var model: String {
        didSet { defaults.set(model, forKey: Key.model) }
    }

    @Published var key: String {
        didSet {
            // 存完读回来对一次：写失败不能让界面装作存上了。
            AiKeychain.save(key)
            keyStoreFailed = AiKeychain.read() != key
        }
    }

    /// 写钥匙串失败时置位，设置页据此说一句，不让用户以为存上了。
    @Published private(set) var keyStoreFailed = false

    private init() {
        enabled = defaults.bool(forKey: Key.enabled)
        endpoint = defaults.string(forKey: Key.endpoint) ?? ""
        model = defaults.string(forKey: Key.model) ?? ""
        key = AiKeychain.read()
    }

    /// 三项都填全了才会真的走模型；缺任一项就用本机规则。
    var config: AiConfig? {
        let config = AiConfig(endpoint: endpoint, model: model, key: key)
        return config.isComplete ? config : nil
    }

    /// 当前拆句子用的是哪条路：填了服务且开关打开 → 模型，否则本机规则。
    var usesRemoteModel: Bool { enabled && config != nil }

    func clearKey() {
        key = ""
    }
}

/// 钥匙串里那一个 API Key。
enum AiKeychain {
    private static let service = "com.pace.app.ai"
    private static let account = "api-key"

    static func read() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    static func save(_ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var insert = base
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(insert as CFDictionary, nil)
    }
}
