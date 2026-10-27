package pace.app.ai

import pace.shared.classifier.KeywordClassifier
import pace.shared.datetime.PaceDates
import pace.shared.model.SaveTxnInput
import pace.shared.model.TxnType
import pace.shared.money.Money

/**
 * 一条待确认草稿。本机规则和用户填的服务产出同一结构，界面不区分来源。
 * Serializable：通过导航 savedStateHandle 在记一笔页与草稿确认页之间传递。
 */
data class DraftItem(
    val id: String,
    var type: String,
    var amountText: String,
    var amountMinor: Long,
    var currency: String,
    var dateText: String,
    var localDate: String,
    var category: String,
    var note: String,
    var account: String,
    var countInBudget: Boolean,
    var missingFields: List<String>
) : java.io.Serializable

/** 草稿缺什么（docs/AI_PRIVACY.md v1）——与 shared 的 DraftMissing 同值。 */
object DraftMissing {
    const val AMOUNT = "AMOUNT"
    const val DATE = "DATE"
    const val TYPE = "TYPE"
    const val CATEGORY = "CATEGORY"
}

/** 本机规则：共享核心拆句，离线、不联网。 */
object LocalDrafts {
    fun parse(text: String, todayIso: String): List<DraftItem> {
        val result = pace.shared.ai.SentenceDraftParser.parse(input = text, todayIso = todayIso)
        return result.drafts.map { draft ->
            DraftItem(
                id = draft.localId,
                type = draft.type,
                amountText = draft.amountText,
                amountMinor = draft.amountMinor,
                currency = draft.currency,
                dateText = draft.dateText,
                localDate = draft.localDate,
                category = draft.category,
                note = draft.note,
                account = draft.account ?: "",
                countInBudget = draft.countInBudget,
                missingFields = draft.missingFields
            )
        }
    }
}

/** 金额改动后本地复算最小单位，顺带清掉「需要金额」。 */
fun DraftItem.updateAmount(text: String) {
    amountText = text.trim()
    val minor = Money.parseToMinor(amountText)
    if (minor != null) {
        amountMinor = minor
        missingFields = missingFields - DraftMissing.AMOUNT
    } else {
        amountMinor = 0
        if (DraftMissing.AMOUNT !in missingFields) {
            missingFields = missingFields + DraftMissing.AMOUNT
        }
    }
}

/** 草稿 → 入账输入；防重（DUPLICATE_FINGERPRINT）不因为入口不同就少一道。 */
fun draftSaveInput(draft: DraftItem, forceSave: Boolean): SaveTxnInput = SaveTxnInput(
    id = null,
    type = draft.type,
    amountText = draft.amountText,
    currency = draft.currency,
    category = draft.category,
    account = draft.account.ifBlank { "现金" },
    note = draft.note,
    occurredAtEpochMillis = 0L,
    localDate = draft.localDate,
    timezoneId = pace.app.AppContainer.timezoneId,
    countInBudget = draft.countInBudget,
    refundOfId = null,
    source = pace.shared.model.TxnSource.AI_DRAFT,
    forceSave = forceSave
)

/** 把草稿写进账本的那一步——确认页与就地确认共用（docs/DESIGN-quickadd-primary.md §7）。 */
object DraftSaver {
    class Outcome {
        var saved = 0
        /** 账本里已经有了的这几笔，问用户要不要照样记。 */
        val duplicated = mutableListOf<DraftItem>()
        /** 真没写进去的（不是重复）：必须说出来，否则存一半会报「已保存 2 笔」。 */
        val failed = mutableListOf<DraftItem>()
    }

    /** [force] 用户已经说过「照样记」，跳过重复拦截。 */
    fun save(drafts: List<DraftItem>, force: Boolean = false): Outcome {
        val api = pace.app.AppContainer.ledger
        val outcome = Outcome()
        for (draft in drafts) {
            val result = api.saveTransaction(draftSaveInput(draft, forceSave = force))
            if (result.isSuccess) {
                outcome.saved += 1
            } else if (result.errorCode == pace.shared.model.ErrorCodes.DUPLICATE_FINGERPRINT) {
                outcome.duplicated += draft
            } else {
                outcome.failed += draft
            }
        }
        return outcome
    }
}

/** 远端草稿落本地校验时要用的分类白名单（与 iOS AiDraftClient.knownCategories 同表）。 */
object DraftWhitelist {
    val knownCategories: Set<String> = setOf(
        "餐饮", "交通", "购物", "住房", "娱乐", "医疗", "教育", "人情社交", "其他", "工资", "理财", "转账"
    )

    /** 「今天」「昨天」「前天」「明天」换算成绝对日期；别的词不动。 */
    fun relativeDate(word: String?, todayIso: String): String? {
        val w = word?.trim().orEmpty()
        val days = when (w) {
            "今天" -> 0
            "昨天" -> -1
            "前天" -> -2
            "明天" -> 1
            else -> return null
        }
        return try {
            val today = java.time.LocalDate.parse(todayIso)
            today.plusDays(days.toLong()).toString()
        } catch (_: Throwable) {
            null
        }
    }
}

/**
 * 远端返回的草稿必须过本地校验才能进确认页：
 * 金额、日期、分类一律本地复算，不信任模型给的数值（docs/AI_PRIVACY.md 第 3 节）。
 * 纯函数，JVM 可测。
 */
object RemoteDraftMapper {

    fun map(
        localId: String?,
        type: String?,
        amountText: String?,
        currency: String?,
        dateText: String?,
        localDate: String?,
        category: String?,
        note: String?,
        account: String?,
        countInBudget: Boolean?,
        missingFields: List<String>?,
        todayIso: String
    ): DraftItem {
        val rawType = type.orEmpty()
        val safeType = if (TxnType.isValid(rawType)) rawType else TxnType.EXPENSE

        val safeAmountText = amountText.orEmpty().trim()
        var amountMinor = 0L
        if (safeAmountText.isNotEmpty()) {
            Money.parseToMinor(safeAmountText)?.let { amountMinor = it }
        }

        val rawDate = localDate.orEmpty()
        var safeDate = rawDate
        if (rawDate.isEmpty() || !PaceDates.isValidLocalDate(rawDate)) {
            safeDate = todayIso
        }
        // 用户说的「昨天」比模型自己算出的绝对日期可靠：两者不一致时以词为准
        DraftWhitelist.relativeDate(dateText, todayIso)?.let { corrected ->
            if (corrected != safeDate) safeDate = corrected
        }

        var safeCategory = category.orEmpty()
        if (safeCategory !in DraftWhitelist.knownCategories) {
            safeCategory = KeywordClassifier.suggestCategory(note.orEmpty(), safeType)
        }

        val known = listOf(DraftMissing.AMOUNT, DraftMissing.DATE, DraftMissing.TYPE, DraftMissing.CATEGORY)
        val missing = (missingFields.orEmpty()).filter { it in known }.toMutableList()
        if (amountMinor <= 0 && DraftMissing.AMOUNT !in missing) missing += DraftMissing.AMOUNT
        // 模型压根没提 localDate（null）不算「需要日期」；给了但空串/非法才算——与 iOS 同口径
        val dateAttempted = localDate != null
        if (dateAttempted && (rawDate.isEmpty() || !PaceDates.isValidLocalDate(rawDate))) {
            if (DraftMissing.DATE !in missing) missing += DraftMissing.DATE
        }

        return DraftItem(
            id = localId ?: pace.shared.util.Ids.newUuid(),
            type = safeType,
            amountText = safeAmountText,
            amountMinor = amountMinor,
            currency = (currency ?: "CNY").uppercase(),
            dateText = dateText.orEmpty(),
            localDate = safeDate,
            category = safeCategory,
            note = note.orEmpty().trim(),
            account = account.orEmpty(),
            countInBudget = (countInBudget ?: (safeType == TxnType.EXPENSE)) && safeType == TxnType.EXPENSE,
            missingFields = missing
        )
    }
}
