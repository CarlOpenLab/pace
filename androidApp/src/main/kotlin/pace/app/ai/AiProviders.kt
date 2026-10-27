package pace.app.ai

/**
 * 一句话记账能直接用的服务商（都是 OpenAI 兼容接口）。
 * 地址存的是 base（一般写到 /v1）；用户也可以粘完整的 /chat/completions，
 * 两种都认，对话和模型列表都从同一个地址推出来。
 */
data class AiProvider(
    val id: String,
    val name: String,
    val endpoint: String
) {
    companion object {
        val custom = AiProvider("custom", "自定义", "")

        /** 顺序与 PaceCopy 对齐。 */
        val presets = listOf(
            AiProvider("deepseek", "DeepSeek", "https://api.deepseek.com/v1"),
            AiProvider("moonshot", "Kimi", "https://api.moonshot.cn/v1"),
            AiProvider("openai", "OpenAI", "https://api.openai.com/v1"),
            AiProvider("zhipu", "智谱", "https://open.bigmodel.cn/api/paas/v4"),
            AiProvider("openrouter", "OpenRouter", "https://openrouter.ai/api/v1"),
            AiProvider("dashscope", "通义千问", "https://dashscope.aliyuncs.com/compatible-mode/v1")
        )

        /** 地址和某个预置一致才认成那个服务商，用户手改过就算自定义。 */
        fun matching(endpoint: String): AiProvider {
            val normalized = normalize(endpoint)
            if (normalized.isEmpty()) return custom
            return presets.firstOrNull { normalize(it.endpoint) == normalized } ?: custom
        }

        /** 比较时抹掉结尾的 /chat/completions 和斜杠，这样完整路径也能对上预置。 */
        fun normalize(endpoint: String): String {
            var text = endpoint.trim().lowercase()
            while (text.endsWith("/")) text = text.dropLast(1)
            if (text.endsWith(CHAT_PATH)) text = text.dropLast(CHAT_PATH.length)
            return text
        }

        private const val CHAT_PATH = "/chat/completions"

        private fun base(endpoint: String): String? {
            val text = endpoint.trim()
            if (text.isEmpty()) return null
            val scheme = runCatching { java.net.URI(text).scheme }.getOrNull()
            if (scheme != "https" && scheme != "http") return null
            var stripped = text
            while (stripped.endsWith("/")) stripped = stripped.dropLast(1)
            if (stripped.endsWith(CHAT_PATH)) stripped = stripped.dropLast(CHAT_PATH.length)
            return stripped.ifEmpty { null }
        }

        /** 对话接口：…/chat/completions；用户只写了 base 就补上。 */
        fun chatUrl(endpoint: String): String? = base(endpoint)?.let { it + CHAT_PATH }

        /** 模型列表接口：…/models。 */
        fun modelsUrl(endpoint: String): String? = base(endpoint)?.let { "$it/models" }
    }
}

/** 用用户自己的 Key 去服务商读模型列表。读不到时调用方回退到手填模型名。 */
object AiModelList {

    sealed class Failure {
        data object NoAddress : Failure()
        data object NoKey : Failure()
        data object Offline : Failure()
        data object BadAddress : Failure()
        data object Certificate : Failure()
        data object Unreachable : Failure()
        data object KeyRejected : Failure()
        data object NoModelList : Failure()
        data object Server : Failure()
        data object Empty : Failure()
    }

    sealed class Outcome {
        data class Success(val models: List<String>) : Outcome()
        data class Failed(val reason: Failure) : Outcome()
    }

    /** 拉模型列表。网络在调用方线程执行（Dispatchers.IO）。 */
    fun fetch(endpoint: String, key: String): Outcome {
        val url = AiProvider.modelsUrl(endpoint) ?: return Outcome.Failed(Failure.NoAddress)
        val trimmedKey = key.trim()
        if (trimmedKey.isEmpty()) return Outcome.Failed(Failure.NoKey)

        val outcome = AiHttp.get(url, "Bearer $trimmedKey", connectTimeoutMs = 15_000, readTimeoutMs = 20_000)
        return when (outcome) {
            is AiHttp.Outcome.Network -> when (outcome.kind) {
                AiHttp.NetworkKind.OFFLINE -> Outcome.Failed(Failure.Offline)
                AiHttp.NetworkKind.BAD_ADDRESS -> Outcome.Failed(Failure.BadAddress)
                AiHttp.NetworkKind.CERTIFICATE -> Outcome.Failed(Failure.Certificate)
                AiHttp.NetworkKind.TIMEOUT, AiHttp.NetworkKind.UNREACHABLE -> Outcome.Failed(Failure.Unreachable)
            }
            is AiHttp.Outcome.Status -> when (outcome.code) {
                in 200..299 -> {
                    val ids = parseIds(outcome.body)
                    if (ids.isEmpty()) Outcome.Failed(Failure.Empty) else Outcome.Success(ids)
                }
                401, 403 -> Outcome.Failed(Failure.KeyRejected)
                404, 405 -> Outcome.Failed(Failure.NoModelList)
                else -> Outcome.Failed(Failure.Server)
            }
        }
    }

    /**
     * 主流的写法是 {"data":[{"id":"…"}]}，也有 {"models":[…]} 或直接给 ["…"] 的，三种都认。
     */
    fun parseIds(body: String): List<String> {
        val root = runCatching { org.json.JSONTokener(body).nextValue() }.getOrNull() ?: return emptyList()
        val raw: List<String> = when (root) {
            is org.json.JSONArray -> (0 until root.length()).mapNotNull { root.optString(it) }
            is org.json.JSONObject -> {
                val dataArray = root.optJSONArray("data")
                if (dataArray != null) {
                    (0 until dataArray.length()).mapNotNull { index ->
                        dataArray.optJSONObject(index)?.optString("id")
                    }
                } else {
                    val modelsArray = root.optJSONArray("models")
                    if (modelsArray != null) {
                        (0 until modelsArray.length()).mapNotNull { index ->
                            modelsArray.optJSONObject(index)?.let { item ->
                                item.optString("id").ifEmpty { item.optString("name") }
                            }
                        }
                    } else emptyList()
                }
            }
            else -> emptyList()
        }
        return sortedUnique(raw)
    }

    private fun sortedUnique(ids: List<String>): List<String> = ids
        .map { it.trim() }
        .filter { it.isNotEmpty() }
        .distinct()
        .sortedWith(compareBy<String> { it.length }.thenBy { it })
}
