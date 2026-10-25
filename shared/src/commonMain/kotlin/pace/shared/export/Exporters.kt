package pace.shared.export

import kotlinx.serialization.json.Json
import pace.shared.datetime.PaceDates
import pace.shared.money.Money
import pace.shared.model.BudgetRule
import pace.shared.model.Category
import pace.shared.model.LedgerEnvelope
import pace.shared.model.Transaction

/**
 * CSV / JSON 导出（docs/EXPORT_FORMAT.md）。
 * 完全在本地生成字符串，文件落盘与分享由各平台完成。
 */
object Exporters {

    const val FORMAT_VERSION = 1
    const val APP_ID = "pace"

    val CSV_HEADER = listOf(
        "id", "date", "time", "type", "amount", "currency", "category", "account", "note", "count_in_budget", "refund_of_id"
    )

    private val exportJson = Json {
        encodeDefaults = true
        ignoreUnknownKeys = true
        prettyPrint = true
    }

    fun buildEnvelope(
        transactions: List<Transaction>,
        categories: List<Category>,
        budgetRules: List<BudgetRule>,
        timezoneId: String,
        defaultCurrency: String,
        exportedAtEpochMillis: Long
    ): LedgerEnvelope = LedgerEnvelope(
        formatVersion = FORMAT_VERSION,
        app = APP_ID,
        exportedAtEpochMillis = exportedAtEpochMillis,
        timezone = timezoneId,
        defaultCurrency = defaultCurrency,
        transactions = transactions.sortedWith(
            compareBy<Transaction> { it.localDate }.thenBy { it.occurredAtEpochMillis }
        ),
        categories = categories.sortedBy { it.sortOrder },
        budgetRules = budgetRules.sortedBy { it.effectiveFromLocalDate }
    )

    fun exportJson(envelope: LedgerEnvelope): String = exportJson.encodeToString(LedgerEnvelope.serializer(), envelope)

    /** RFC 4180 转义（I4）：含逗号/引号/换行时用双引号包裹，内部引号翻倍。 */
    fun csvEscape(field: String): String {
        val needsQuote = field.any { it == ',' || it == '"' || it == '\n' || it == '\r' }
        val escaped = field.replace("\"", "\"\"")
        return if (needsQuote) "\"$escaped\"" else escaped
    }

    fun exportCsv(transactions: List<Transaction>): String {
        val lines = mutableListOf(CSV_HEADER.joinToString(","))
        val ordered = transactions.sortedWith(
            compareBy<Transaction> { it.localDate }.thenBy { it.occurredAtEpochMillis }
        )
        for (txn in ordered) {
            val cells = listOf(
                txn.id,
                txn.localDate,
                PaceDates.timeCompact(txn.occurredAtEpochMillis, txn.timezoneId),
                txn.type,
                Money.formatMinor(txn.amountMinor),
                txn.currency,
                txn.category,
                txn.account,
                txn.note,
                if (txn.countInBudget) "true" else "false",
                txn.refundOfId ?: ""
            )
            lines += cells.joinToString(",") { csvEscape(it) }
        }
        return lines.joinToString("\n", postfix = "\n")
    }
}
