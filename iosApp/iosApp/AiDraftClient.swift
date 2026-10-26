import Foundation
import shared

/// 一条待确认草稿。本机规则和用户填的服务产出同一结构，界面不区分来源。
struct DraftItem: Identifiable {
    let id: String
    var type: String
    var amountText: String
    var amountMinor: Int64
    var currency: String
    var dateText: String
    var localDate: String
    var category: String
    var note: String
    var account: String
    var countInBudget: Bool
    var missingFields: [String]
}

/// 草稿缺什么（docs/AI_PRIVACY.md v1）
enum DraftMissing {
    static let amount = "AMOUNT"
    static let date = "DATE"
    static let type = "TYPE"
    static let category = "CATEGORY"
}

/// 一句话记账的失败情况（界面上各对应一句人话，见 Copy）
enum AiFailure: Error {
    case offline
    case timeout
    case keyRejected
    case quota
    case unreadable
    case empty
    case addressUnreachable
    case server(Int)
    case notConfigured
}

/// 本机规则：共享核心拆句，离线、不联网。
enum LocalDrafts {
    static func parse(text: String, todayIso: String) -> [DraftItem] {
        let result = SentenceDraftParser.shared.parse(input: text, todayIso: todayIso)
        return result.drafts.map { draft in
            DraftItem(
                id: draft.localId,
                type: draft.type,
                amountText: draft.amountText,
                amountMinor: draft.amountMinor,
                currency: draft.currency,
                dateText: draft.dateText,
                localDate: draft.localDate,
                category: draft.category,
                note: draft.note,
                account: draft.account ?? "",
                countInBudget: draft.countInBudget,
                missingFields: draft.missingFields
            )
        }
    }
}

/// 用户自己填的服务（OpenAI 兼容接口）。请求从手机直连，不经过任何中转。
struct AiDraftClient {

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: config)
    }()

    // MARK: - 拆句子

    static func parse(text: String, todayIso: String, config: AiConfig) async throws -> [DraftItem] {
        #if DEBUG
        // 示例和规则打架过一次，代价是一天的账落到另一天。改示例的人先在这里停下。
        assert(exampleIsCoherent(todayIso: todayIso), "提示词示例的 dateText 和 localDate 不是同一天")
        #endif
        let body: [String: Any] = [
            "model": config.model,
            "temperature": 0,
            "stream": false,
            "messages": [
                ["role": "system", "content": systemPrompt(todayIso: todayIso)],
                ["role": "user", "content": text]
            ]
        ]
        let data = try await send(body: body, config: config)
        let content = try contentText(from: data)
        guard let json = extractJSONObject(from: content) else {
            throw AiFailure.unreadable
        }
        let parsed: RemoteDraftResult
        do {
            parsed = try JSONDecoder().decode(RemoteDraftResult.self, from: json)
        } catch {
            throw AiFailure.unreadable
        }
        let drafts = parsed.drafts.map { map($0, todayIso: todayIso) }
        if drafts.isEmpty {
            throw AiFailure.empty
        }
        return drafts
    }

    // MARK: - 测试连接

    enum TestResult {
        case ok
        case unreachable
        case keyRejected
        case incomplete
    }

    static func testConnection(config: AiConfig) async -> TestResult {
        guard config.isComplete else { return .incomplete }
        let body: [String: Any] = [
            "model": config.model,
            "max_tokens": 1,
            "messages": [["role": "user", "content": "ping"]]
        ]
        do {
            _ = try await send(body: body, config: config)
            return .ok
        } catch AiFailure.keyRejected {
            return .keyRejected
        } catch {
            return .unreachable
        }
    }

    // MARK: - 网络

    private static func send(body: [String: Any], config: AiConfig) async throws -> Data {
        guard let url = AiProvider.chatURL(from: config.endpoint) else {
            throw AiFailure.addressUnreachable
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut: throw AiFailure.timeout
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed, .secureConnectionFailed:
                throw AiFailure.offline
            default:
                throw AiFailure.addressUnreachable
            }
        } catch {
            throw AiFailure.addressUnreachable
        }

        guard let http = response as? HTTPURLResponse else { throw AiFailure.addressUnreachable }
        switch http.statusCode {
        case 200...299: return data
        case 401, 403: throw AiFailure.keyRejected
        case 402, 429: throw AiFailure.quota
        default: throw AiFailure.server(http.statusCode)
        }
    }

    private static func contentText(from data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AiFailure.unreadable
        }
        if let choices = root["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        // 有的服务把内容给成 [{type:text,text:…}]
        if let choices = root["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let parts = message["content"] as? [[String: Any]] {
            let text = parts.compactMap { $0["text"] as? String }.joined()
            if !text.isEmpty { return text }
        }
        throw AiFailure.unreadable
    }

    /// 模型有时会包一层 ```json 或前后带说明，这里只取第一个完整的 JSON 对象。
    private static func extractJSONObject(from text: String) -> Data? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return nil }
        let slice = text[start...end]
        return String(slice).data(using: .utf8)
    }

    // MARK: - 映射与本地校验

    private struct RemoteDraftResult: Decodable {
        let draftVersion: Int?
        let drafts: [RemoteDraft]
        let parseErrors: [String]?
    }

    private struct RemoteDraft: Decodable {
        let localId: String?
        let type: String?
        let amountText: String?
        let currency: String?
        let dateText: String?
        let localDate: String?
        let category: String?
        let note: String?
        let account: String?
        let countInBudget: Bool?
        let missingFields: [String]?
    }

    static let knownCategories: Set<String> = [
        "餐饮", "交通", "购物", "住房", "娱乐", "医疗", "教育", "人情社交", "其他", "工资", "理财", "转账"
    ]

    /// 金额、日期、分类一律本地复算，不信任模型给的数值（docs/AI_PRIVACY.md 第 3 节）。
    private static func map(_ remote: RemoteDraft, todayIso: String) -> DraftItem {
        let dates = PaceDates.shared
        let money = Money.shared

        let rawType = remote.type ?? ""
        let type = TxnTypes.all.contains(where: { $0.0 == rawType }) ? rawType : TxnTypes.expense

        let amountText = (remote.amountText ?? "").trimmingCharacters(in: .whitespaces)
        var amountMinor: Int64 = 0
        if !amountText.isEmpty, let parsed = money.parseToMinor(text: amountText) {
            amountMinor = parsed.int64Value
        }

        var localDate = remote.localDate ?? ""
        if localDate.isEmpty || !dates.isValidLocalDate(iso: localDate) {
            localDate = todayIso
        }
        // 用户说的「昨天」比模型自己算出的绝对日期可靠：两者不一致时以词为准，
        // 免得一句话记的账落到今天（示例曾经就这么教过模型一次）。
        if let corrected = relativeDate(word: remote.dateText, todayIso: todayIso), corrected != localDate {
            localDate = corrected
        }

        var category = remote.category ?? ""
        if !knownCategories.contains(category) {
            category = KeywordClassifier.shared.suggestCategory(text: remote.note ?? "", type: type)
        }

        var missing = (remote.missingFields ?? []).filter {
            [DraftMissing.amount, DraftMissing.date, DraftMissing.type, DraftMissing.category].contains($0)
        }
        if amountMinor <= 0, !missing.contains(DraftMissing.amount) {
            missing.append(DraftMissing.amount)
        }
        if !dates.isValidLocalDate(iso: remote.localDate ?? "") || (remote.localDate ?? "").isEmpty {
            if !missing.contains(DraftMissing.date) && remote.localDate != nil {
                missing.append(DraftMissing.date)
            }
        }

        return DraftItem(
            id: remote.localId ?? UUID().uuidString,
            type: type,
            amountText: amountText,
            amountMinor: amountMinor,
            currency: (remote.currency ?? "CNY").uppercased(),
            dateText: remote.dateText ?? "",
            localDate: localDate,
            category: category,
            note: (remote.note ?? "").trimmingCharacters(in: .whitespaces),
            account: remote.account ?? "",
            countInBudget: (remote.countInBudget ?? (type == TxnTypes.expense)) && type == TxnTypes.expense,
            missingFields: missing
        )
    }

    /// 「今天」「昨天」「前天」「明天」换成的绝对日期；别的词不动。
    static func relativeDate(word: String?, todayIso: String) -> String? {
        let w = (word ?? "").trimmingCharacters(in: .whitespaces)
        let offset: Int
        switch w {
        case "今天": offset = 0
        case "昨天": offset = -1
        case "前天": offset = -2
        case "明天": offset = 1
        default: return nil
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: PaceDates.shared.currentTimeZoneId()) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        guard let today = formatter.date(from: todayIso),
              let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: offset, to: today) else {
            return nil
        }
        return formatter.string(from: date)
    }

    // MARK: - 提示词

    /// 只发送用户当次输入的那句话和今天日期；不带账本、不带分类表内容。
    static func systemPrompt(todayIso: String) -> String {
        """
        你是记账助手。把用户的一句话拆成若干笔待确认草稿，只输出 JSON，不要解释、不要 Markdown。
        今天是 \(todayIso)。
        JSON 结构：
        \(exampleJSON(todayIso: todayIso))
        规则：
        - type 只能是 EXPENSE、INCOME、TRANSFER 之一；默认 EXPENSE。
        - localDate 必须是 YYYY-MM-DD 的绝对日期，相对日期按今天换算；说不清日期就留空。
        - dateText 只在用户自己说了相对日期时填（今天、昨天、上周五），且必须和 localDate 是同一天；没提日期就留空，不要写「今天」。
        - amountText 只写数字（如 28、28.5），说不清金额就留空并在 missingFields 里写 AMOUNT。
        - missingFields 只能取 AMOUNT、DATE、TYPE、CATEGORY，不确定的字段绝不要猜。
        - category 从这些里选：餐饮、交通、购物、住房、娱乐、医疗、教育、人情社交、其他、工资、理财、转账。
        - note 是简短备注，最多 20 字，不要包含金额和日期。
        - 一句话里有多笔就拆多笔，按出现顺序编号 localId。
        """
    }

    /// 提示词里的示例，由这个字典生成，不再手写一段 JSON 字符串。
    ///
    /// 手写时它自相矛盾过一次：「dateText 昨天」配「localDate 今天」，规则里
    /// 又写着「相对日期按今天换算」——模型照抄示例，用户说「昨天记的」，账就
    /// 落到今天。日期错了在账本里很难一眼看出来，属于账本正确性问题。
    /// 现在示例不带相对日（dateText 留空、localDate 就是今天），加上
    /// exampleIsCoherent 这条断言，谁再改示例把两个字段写成打架的样子会当场停下。
    static func exampleJSON(todayIso: String) -> String {
        let example: [String: Any] = [
            "draftVersion": 1,
            "drafts": [[
                "localId": "d-001",
                "type": "EXPENSE",
                "amountText": "28",
                "currency": "CNY",
                "dateText": "",
                "localDate": todayIso,
                "category": "餐饮",
                "note": "午饭",
                "account": "",
                "countInBudget": true,
                "missingFields": [],
                "confidence": 0.8
            ]],
            "parseErrors": []
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: example, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return #"{"draftVersion":1,"drafts":[],"parseErrors":[]}"#
        }
        return text
    }

    /// 示例里的相对日和绝对日必须是同一天，否则示例就在教模型算错日期。
    static func exampleIsCoherent(todayIso: String) -> Bool {
        guard let data = exampleJSON(todayIso: todayIso).data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let drafts = root["drafts"] as? [[String: Any]] else { return false }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let today = formatter.date(from: todayIso) else { return false }
        for draft in drafts {
            guard let localDate = draft["localDate"] as? String,
                  let date = formatter.date(from: localDate) else { return false }
            let word = (draft["dateText"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let days = Calendar(identifier: .gregorian).dateComponents([.day], from: today, to: date).day ?? 0
            let expected: Int
            switch word {
            case "": expected = 0
            case "今天": expected = 0
            case "昨天": expected = -1
            case "前天": expected = -2
            case "明天": expected = 1
            default: continue // 一个说不清的词：规则里已经要求它别出现在示例里
            }
            if days != expected { return false }
        }
        return true
    }
}
