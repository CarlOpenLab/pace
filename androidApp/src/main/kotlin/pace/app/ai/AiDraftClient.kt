package pace.app.ai

import org.json.JSONArray
import org.json.JSONObject

/** 一句话记账的失败情况（界面上各对应一句人话，见 PaceCopy.Ai.Fail）。 */
sealed class AiFailure : Throwable() {
    data object Offline : AiFailure()
    data object BadAddress : AiFailure()
    data object Certificate : AiFailure()
    data object Timeout : AiFailure()
    data object KeyRejected : AiFailure()
    data object Quota : AiFailure()
    data object Unreadable : AiFailure()
    data object Empty : AiFailure()

    /** 兜底：发不出去，也分不出是哪一环。 */
    data object AddressUnreachable : AiFailure()

    /** 服务器自己回了个非 2xx（状态码进日志，不上屏）。 */
    data class Server(val code: Int) : AiFailure()

    data object NotConfigured : AiFailure()
}

/**
 * 用户自己填的服务（OpenAI 兼容接口）。请求从手机直连，不经过任何中转。
 * 解析/映射是纯函数（JVM 可测）；send 在 Dispatchers.IO 上由调用方驱动。
 */
object AiDraftClient {

    private const val CONNECT_TIMEOUT_MS = 15_000
    private const val READ_TIMEOUT_MS = 20_000

    // MARK: - 拆句子

    /** 网络与编排（调用方包 withContext(Dispatchers.IO)）。 */
    fun parse(text: String, todayIso: String, config: AiConfig): List<DraftItem> {
        if (pace.app.BuildConfig.DEBUG) {
            check(exampleIsCoherent(todayIso)) { "提示词示例的 dateText 和 localDate 不是同一天" }
        }
        val body = JSONObject().apply {
            put("model", config.model)
            put("temperature", 0)
            put("stream", false)
            put(
                "messages",
                JSONArray().put(message("system", systemPrompt(todayIso))).put(message("user", text))
            )
        }.toString()

        val url = AiProvider.chatUrl(config.endpoint) ?: throw AiFailure.AddressUnreachable
        val outcome = AiHttp.postJson(
            url, "Bearer ${config.key}", body,
            connectTimeoutMs = CONNECT_TIMEOUT_MS, readTimeoutMs = READ_TIMEOUT_MS
        )
        val data = when (outcome) {
            is AiHttp.Outcome.Network -> throw when (outcome.kind) {
                AiHttp.NetworkKind.OFFLINE -> AiFailure.Offline
                AiHttp.NetworkKind.BAD_ADDRESS -> AiFailure.BadAddress
                AiHttp.NetworkKind.CERTIFICATE -> AiFailure.Certificate
                AiHttp.NetworkKind.TIMEOUT -> AiFailure.Timeout
                AiHttp.NetworkKind.UNREACHABLE -> AiFailure.AddressUnreachable
            }
            is AiHttp.Outcome.Status -> when (outcome.code) {
                in 200..299 -> outcome.body
                401, 403 -> throw AiFailure.KeyRejected
                402, 429 -> throw AiFailure.Quota
                else -> {
                    // 状态码只进日志，不上屏；正文留一截：400 这种「地址和 Key 都对、
                    // 它就是不收」的，只有它自己的话能说明为什么。
                    android.util.Log.w(
                        "PaceAi",
                        "chat endpoint answered ${outcome.code} ${outcome.body.take(400)}"
                    )
                    throw AiFailure.Server(outcome.code)
                }
            }
        }

        val content = contentText(data)
        val json = extractJSONObject(content) ?: throw AiFailure.Unreadable
        val drafts = parseDraftsJson(json, todayIso)
        if (drafts.isEmpty()) throw AiFailure.Empty
        return drafts
    }

    // MARK: - 测试连接

    sealed class TestResult {
        data object Ok : TestResult()
        data object Offline : TestResult()
        data object BadAddress : TestResult()
        data object Certificate : TestResult()
        data object Timeout : TestResult()
        data object Unreachable : TestResult()
        data object KeyRejected : TestResult()
        data class Server(val code: Int) : TestResult()
        data object Incomplete : TestResult()
    }

    fun testConnection(config: AiConfig): TestResult {
        if (!config.isComplete) return TestResult.Incomplete
        // 16 不是随手写：有的服务不收 max_tokens=1（会回 400），把「地址和 Key 都对、
        // 只是这个数太小」报成「服务器出问题了」。一次 ping 花不了几分钱，别在这上面省。
        val body = JSONObject().apply {
            put("model", config.model)
            put("max_tokens", 16)
            put("messages", JSONArray().put(message("user", "ping")))
        }.toString()
        val url = AiProvider.chatUrl(config.endpoint) ?: return TestResult.Unreachable
        return when (val outcome = AiHttp.postJson(
            url, "Bearer ${config.key}", body,
            connectTimeoutMs = CONNECT_TIMEOUT_MS, readTimeoutMs = READ_TIMEOUT_MS
        )) {
            is AiHttp.Outcome.Network -> when (outcome.kind) {
                AiHttp.NetworkKind.OFFLINE -> TestResult.Offline
                AiHttp.NetworkKind.BAD_ADDRESS -> TestResult.BadAddress
                AiHttp.NetworkKind.CERTIFICATE -> TestResult.Certificate
                AiHttp.NetworkKind.TIMEOUT -> TestResult.Timeout
                AiHttp.NetworkKind.UNREACHABLE -> TestResult.Unreachable
            }
            is AiHttp.Outcome.Status -> when (outcome.code) {
                in 200..299 -> TestResult.Ok
                401, 403 -> TestResult.KeyRejected
                else -> TestResult.Server(outcome.code)
            }
        }
    }

    // MARK: - 响应解析（纯函数，JVM 可测）

    private fun message(role: String, content: String): JSONObject =
        JSONObject().put("role", role).put("content", content)

    /** 有的服务把内容给成 [{type:text,text:…}]，两种都认。 */
    fun contentText(data: String): String {
        val root = runCatching { JSONObject(data) }.getOrNull() ?: throw AiFailure.Unreadable
        val choices = root.optJSONArray("choices") ?: throw AiFailure.Unreadable
        val message = choices.optJSONObject(0)?.optJSONObject("message") ?: throw AiFailure.Unreadable
        val content = message.opt("content")
        if (content is String && content.isNotEmpty()) return content
        if (content is JSONArray) {
            val text = (0 until content.length())
                .mapNotNull { content.optJSONObject(it)?.optString("text") }
                .joinToString("")
            if (text.isNotEmpty()) return text
        }
        throw AiFailure.Unreadable
    }

    /** 模型有时会包一层 ```json 或前后带说明，这里只取第一个 { 到最后一个 } 之间的内容。 */
    fun extractJSONObject(text: String): String? {
        val start = text.indexOf('{')
        val end = text.lastIndexOf('}')
        if (start < 0 || end <= start) return null
        return text.substring(start, end + 1)
    }

    fun parseDraftsJson(json: String, todayIso: String): List<DraftItem> {
        val root = runCatching { JSONObject(json) }.getOrNull() ?: return emptyList()
        val drafts = root.optJSONArray("drafts") ?: return emptyList()
        return (0 until drafts.length()).mapNotNull { index ->
            val item = drafts.optJSONObject(index) ?: return@mapNotNull null
            RemoteDraftMapper.map(
                localId = item.optStringOrNull("localId"),
                type = item.optStringOrNull("type"),
                amountText = item.optStringOrNull("amountText"),
                currency = item.optStringOrNull("currency"),
                dateText = item.optStringOrNull("dateText"),
                localDate = item.optStringOrNull("localDate"),
                category = item.optStringOrNull("category"),
                note = item.optStringOrNull("note"),
                account = item.optStringOrNull("account"),
                countInBudget = if (item.has("countInBudget")) item.optBoolean("countInBudget") else null,
                missingFields = item.optJSONArray("missingFields")?.let { array ->
                    (0 until array.length()).mapNotNull { array.optStringOrNull(it) }
                },
                todayIso = todayIso
            )
        }
    }

    private fun JSONObject.optStringOrNull(key: String): String? =
        if (has(key) && !isNull(key)) optString(key) else null

    private fun JSONArray.optStringOrNull(index: Int): String? {
        val value = optString(index)
        return value.ifEmpty { null }
    }

    // MARK: - 提示词

    /** 只发送用户当次输入的那句话和今天日期；不带账本、不带分类表内容。 */
    fun systemPrompt(todayIso: String): String {
        return """
            你是记账助手。把用户的一句话拆成若干笔待确认草稿，只输出 JSON，不要解释、不要 Markdown。
            今天是 $todayIso。
            JSON 结构：
            ${exampleJSON(todayIso)}
            规则：
            - type 只能是 EXPENSE、INCOME、TRANSFER 之一；默认 EXPENSE。
            - localDate 必须是 YYYY-MM-DD 的绝对日期，相对日期按今天换算；说不清日期就留空。
            - dateText 只在用户自己说了相对日期时填（今天、昨天、上周五），且必须和 localDate 是同一天；没提日期就留空，不要写「今天」。
            - amountText 只写数字（如 28、28.5），说不清金额就留空并在 missingFields 里写 AMOUNT。
            - missingFields 只能取 AMOUNT、DATE、TYPE、CATEGORY，不确定的字段绝不要猜。
            - category 从这些里选：餐饮、交通、购物、住房、娱乐、医疗、教育、人情社交、其他、工资、理财、转账。
            - note 是简短备注，最多 20 字，不要包含金额和日期。
            - 一句话里有多笔就拆多笔，按出现顺序编号 localId。
        """.trimIndent()
    }

    /**
     * 提示词里的示例。手写示例自相矛盾过一次（「dateText 昨天」配「localDate 今天」），
     * 模型照抄示例，用户说「昨天记的」，账就落到今天。所以示例由字典生成，
     * 不带相对日，配上 exampleIsCoherent 断言（docs/AI_PRIVACY.md；iOS 同一套）。
     */
    fun exampleJSON(todayIso: String): String {
        val example = JSONObject().apply {
            put("draftVersion", 1)
            put(
                "drafts",
                JSONArray().put(
                    JSONObject().apply {
                        put("localId", "d-001")
                        put("type", "EXPENSE")
                        put("amountText", "28")
                        put("currency", "CNY")
                        put("dateText", "")
                        put("localDate", todayIso)
                        put("category", "餐饮")
                        put("note", "午饭")
                        put("account", "")
                        put("countInBudget", true)
                        put("missingFields", JSONArray())
                        put("confidence", 0.8)
                    }
                )
            )
            put("parseErrors", JSONArray())
        }
        return example.toString()
    }

    /** 示例里的相对日和绝对日必须是同一天，否则示例就在教模型算错日期。 */
    fun exampleIsCoherent(todayIso: String): Boolean {
        val root = runCatching { JSONObject(exampleJSON(todayIso)) }.getOrNull() ?: return false
        val drafts = root.optJSONArray("drafts") ?: return false
        val today = runCatching { java.time.LocalDate.parse(todayIso) }.getOrNull() ?: return false
        for (index in 0 until drafts.length()) {
            val draft = drafts.optJSONObject(index) ?: return false
            val localDate = runCatching { java.time.LocalDate.parse(draft.optString("localDate")) }.getOrNull()
                ?: return false
            val word = draft.optString("dateText").trim()
            val expected = when (word) {
                "", "今天" -> 0L
                "昨天" -> -1L
                "前天" -> -2L
                "明天" -> 1L
                else -> continue // 一个说不清的词：规则里已经要求它别出现在示例里
            }
            if (java.time.temporal.ChronoUnit.DAYS.between(today, localDate) != expected) return false
        }
        return true
    }
}
