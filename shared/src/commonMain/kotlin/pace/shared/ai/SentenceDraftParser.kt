package pace.shared.ai

import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.LocalDate
import kotlinx.datetime.minus
import pace.shared.classifier.KeywordClassifier
import pace.shared.model.TxnType
import pace.shared.money.Money

/** 草稿版本号（docs/AI_PRIVACY.md 第 3 节，v1）。 */
const val DRAFT_VERSION: Int = 1

/** 草稿缺字段标记（docs/AI_PRIVACY.md 第 3 节）。 */
object DraftMissing {
    const val AMOUNT = "AMOUNT"
    const val DATE = "DATE"
    const val TYPE = "TYPE"
    const val CATEGORY = "CATEGORY"
}

/** 草稿错误码（docs/AI_PRIVACY.md 第 5 节）。 */
object DraftErrors {
    const val AI_DISABLED = "AI_DISABLED"
    const val AI_TIMEOUT = "AI_TIMEOUT"
    const val AI_PARSE_FAILED = "AI_PARSE_FAILED"
    const val AI_REJECTED = "AI_REJECTED"
    const val DRAFT_VALIDATION_FAILED = "DRAFT_VALIDATION_FAILED"
}

/**
 * 待确认草稿（docs/AI_PRIVACY.md 第 3 节 v1）。
 * 只描述「用户可能记的一笔」，永不直接入库；确认后仍走 LedgerApi.saveTransaction 的完整校验。
 */
data class Draft(
    val localId: String,
    val type: String,
    val amountText: String,
    val amountMinor: Long,
    val currency: String,
    val dateText: String,
    val localDate: String,
    val category: String,
    val note: String,
    val account: String?,
    val countInBudget: Boolean,
    val missingFields: List<String>,
    val confidence: Double
) {
    /** 是否停留在「需要补充」状态（缺金额/日期等，用户补齐前不得确认）。 */
    val needsAttention: Boolean get() = missingFields.isNotEmpty()
}

data class DraftResult(
    val draftVersion: Int,
    val drafts: List<Draft>,
    val parseErrors: List<String>
) {
    val isEmpty: Boolean get() = drafts.isEmpty()
}

/**
 * 本机规则拆句（一句自然语言 → 多笔待确认草稿）。
 *
 * 完全离线，不联网、不发送任何文本。规则只认三类信号：金额、相对日期词（今天/昨天/前天…）、
 * 关键词分类（复用 [KeywordClassifier]）。认不出的句子不猜：金额缺失即标「需要金额」。
 * 与 BYOK 模型共用同一份草稿结构，确认入账流程一致。
 */
object SentenceDraftParser {

    private const val MAX_DRAFTS = 20

    private val SEGMENT_SPLIT = Regex("[，,。；;、\n!！?？]+")
    private val EXPLICIT_DATE = Regex("""(\d{4})-(\d{1,2})-(\d{1,2})|(\d{1,2})月(\d{1,2})[日号]""")
    private val RELATIVE_DATE = Regex("""大前天|前天|昨天|昨日|今天|今日""")
    // 金额：可选货币符号 + 数字 + 可选单位；单位出现时优先
    private val MONEY = Regex("""([¥￥$]\s*)?(\d{1,9}(?:\.\d{1,2})?)\s*(元|块钱|块|圆)?""")
    // 数字后跟这些量词时不是金额
    private val NOT_MONEY_SUFFIX = Regex("""^\s*(点|时|分|秒|号|个|人|次|天|周|月|年|折|%|％)""")

    private val INCOME_WORDS = listOf("工资", "收入", "奖金", "报销", "红包收", "收到", "利息", "分红", "中奖", "进账")
    private val TRANSFER_WORDS = listOf("转账", "转给", "转到")
    private val NOISE_PREFIX = listOf("花了", "付了", "用了", "买了", "花", "消费", "支付", "记一笔", "记")

    /**
     * @param input 用户当次输入的一整句话
     * @param todayIso 用户所在时区的今天（YYYY-MM-DD），相对日期以它为基准
     */
    fun parse(input: String, todayIso: String): DraftResult {
        val text = input.trim()
        if (text.isEmpty()) {
            return DraftResult(DRAFT_VERSION, emptyList(), listOf(DraftErrors.AI_REJECTED))
        }
        if (!isValidDate(todayIso)) {
            return DraftResult(DRAFT_VERSION, emptyList(), listOf(DraftErrors.AI_PARSE_FAILED))
        }

        val segments = text.split(SEGMENT_SPLIT).map { it.trim() }.filter { it.isNotEmpty() }
        if (segments.isEmpty()) {
            return DraftResult(DRAFT_VERSION, emptyList(), listOf(DraftErrors.AI_REJECTED))
        }

        // 句子里的日期会延续到下一个小句：「昨天午饭 28，晚上打车 16」两笔都算昨天
        var carriedDate: String? = null
        var carriedDateText: String = ""
        val drafts = mutableListOf<Draft>()

        for (segment in segments.take(MAX_DRAFTS)) {
            val explicit = resolveExplicitDate(segment, todayIso)
            val relative = RELATIVE_DATE.find(segment)?.value
            val relativeDate = relative?.let { resolveRelativeDate(it, todayIso) }

            val localDate: String
            val dateText: String
            when {
                explicit != null -> {
                    localDate = explicit.first
                    dateText = explicit.second
                }
                relativeDate != null -> {
                    localDate = relativeDate
                    dateText = relative
                }
                else -> {
                    localDate = carriedDate ?: todayIso
                    dateText = if (carriedDate != null) carriedDateText else ""
                }
            }
            if (explicit != null || relativeDate != null) {
                carriedDate = localDate
                carriedDateText = dateText
            }

            drafts += buildDraft(segment, localDate, dateText, drafts.size)
        }

        // 一整句都没有金额：不拆成一堆空草稿，合成一条「需要金额」，原话进备注（回退手动记账）
        if (drafts.isNotEmpty() && drafts.all { it.amountText.isBlank() }) {
            val first = drafts.first()
            val collapsed = first.copy(
                localId = "d-001",
                note = text.take(80),
                category = KeywordClassifier.suggestCategory(text, first.type),
                dateText = if (first.dateText.isNotBlank()) first.dateText else "",
                missingFields = listOf(DraftMissing.AMOUNT),
                confidence = 0.2
            )
            return DraftResult(DRAFT_VERSION, listOf(collapsed), emptyList())
        }

        return DraftResult(DRAFT_VERSION, drafts, emptyList())
    }

    private fun buildDraft(segment: String, localDate: String, dateText: String, index: Int): Draft {
        val type = detectType(segment)
        val amountToken = findAmount(segment)

        var note = segment
        dateText.takeIf { it.isNotBlank() }?.let { note = note.replace(it, " ") }
        amountToken?.let { note = note.replace(it.first, " ") }
        note = cleanNote(note)

        val category = KeywordClassifier.suggestCategory(if (note.isBlank()) segment else note, type)
        val amountText = amountToken?.second ?: ""
        val amountMinor = if (amountText.isBlank()) 0L else (Money.parseToMinor(amountText) ?: 0L)
        val missing = mutableListOf<String>()
        if (amountMinor <= 0L) missing += DraftMissing.AMOUNT
        if (!isValidDate(localDate)) missing += DraftMissing.DATE

        val confidence = when {
            amountText.isNotBlank() && dateText.isNotBlank() && category != KeywordClassifier.FALLBACK_CATEGORY -> 0.9
            amountText.isNotBlank() && category != KeywordClassifier.FALLBACK_CATEGORY -> 0.8
            amountText.isNotBlank() -> 0.6
            else -> 0.3
        }

        return Draft(
            localId = "d-" + (index + 1).toString().padStart(3, '0'),
            type = type,
            amountText = amountText,
            amountMinor = amountMinor,
            currency = "CNY",
            dateText = dateText,
            localDate = localDate,
            category = category,
            note = note,
            account = null,
            countInBudget = type == TxnType.EXPENSE,
            missingFields = missing,
            confidence = confidence
        )
    }

    /** 找到本小句里的金额：带单位/货币符号的优先，否则取最靠后一个（「打车 16」）。 */
    private fun findAmount(segment: String): Pair<String, String>? {
        var withUnit: Pair<String, String>? = null
        var lastPlain: Pair<String, String>? = null
        for (match in MONEY.findAll(segment)) {
            val start = match.range.first
            val end = match.range.last + 1
            val after = segment.substring(end)
            if (NOT_MONEY_SUFFIX.containsMatchIn(after)) continue
            // 日期/时间里的数字已经在上一步从 note 里剥离，这里再挡一次「10 月」这类
            val before = segment.substring(0, start)
            if (before.isNotEmpty() && (before.last().isDigit() || before.last() == '-')) continue
            val digits = match.groupValues[2]
            if (digits.isBlank()) continue
            val hasMarker = match.groupValues[1].isNotBlank() || match.groupValues[3].isNotBlank()
            val token = segment.substring(start, end)
            if (hasMarker && withUnit == null) withUnit = token to digits
            lastPlain = token to digits
        }
        return withUnit ?: lastPlain
    }

    private fun detectType(segment: String): String {
        val text = segment.lowercase()
        if (TRANSFER_WORDS.any { text.contains(it) }) return TxnType.TRANSFER
        if (INCOME_WORDS.any { text.contains(it) }) return TxnType.INCOME
        return TxnType.EXPENSE
    }

    private fun cleanNote(raw: String): String {
        var note = raw.replace(Regex("\\s+"), " ").trim()
        note = note.trim('，', ',', '。', '；', ';', '、', ':', '：', '-', '—', '·', ' ')
        var changed = true
        while (changed) {
            changed = false
            for (prefix in NOISE_PREFIX) {
                if (note.startsWith(prefix) && note.length > prefix.length) {
                    note = note.removePrefix(prefix).trim()
                    changed = true
                }
            }
        }
        return note.take(80)
    }

    private fun resolveExplicitDate(segment: String, todayIso: String): Pair<String, String>? {
        val match = EXPLICIT_DATE.find(segment) ?: return null
        val groups = match.groupValues
        val date: LocalDate? = if (groups[1].isNotEmpty()) {
            try {
                LocalDate(groups[1].toInt(), groups[2].toInt(), groups[3].toInt())
            } catch (_: Throwable) {
                null
            }
        } else {
            try {
                val today = LocalDate.parse(todayIso)
                var candidate = LocalDate(today.year, groups[4].toInt(), groups[5].toInt())
                // 没写年份的日期若在未来，按去年理解（「12月31日」说在 1 月）
                if (candidate > today) {
                    candidate = LocalDate(today.year - 1, candidate.monthNumber, candidate.dayOfMonth)
                }
                candidate
            } catch (_: Throwable) {
                null
            }
        }
        if (date == null) return null
        return date.toString() to match.value
    }

    private fun resolveRelativeDate(word: String, todayIso: String): String? = try {
        val today = LocalDate.parse(todayIso)
        val days = when (word) {
            "今天", "今日" -> 0
            "昨天", "昨日" -> 1
            "前天" -> 2
            "大前天" -> 3
            else -> 0
        }
        if (days == 0) today.toString() else today.minus(days, DateTimeUnit.DAY).toString()
    } catch (_: Throwable) {
        null
    }

    private fun isValidDate(iso: String): Boolean = try {
        LocalDate.parse(iso).toString() == iso
    } catch (_: Throwable) {
        false
    }
}
