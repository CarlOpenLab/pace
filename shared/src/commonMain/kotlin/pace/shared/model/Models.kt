package pace.shared.model

import kotlinx.serialization.Serializable

/** 账单类型枚举（docs/DATA_MODEL.md 第 2.1 节）。用字符串常量避免跨端枚举桥接歧义。 */
object TxnType {
    const val EXPENSE = "EXPENSE"
    const val INCOME = "INCOME"
    const val REFUND = "REFUND"
    const val TRANSFER = "TRANSFER"

    val ALL = listOf(EXPENSE, INCOME, REFUND, TRANSFER)

    fun isValid(value: String): Boolean = value in ALL
}

object TxnSource {
    const val MANUAL = "MANUAL"
    const val IMPORT = "IMPORT"
    const val AI_DRAFT = "AI_DRAFT"

    fun normalize(value: String): String = if (value in listOf(MANUAL, IMPORT, AI_DRAFT)) value else MANUAL
}

/** 共享业务错误码（docs/DATA_MODEL.md 第 7 节），两端按码展示文案。 */
object ErrorCodes {
    const val INVALID_AMOUNT = "INVALID_AMOUNT"
    const val INVALID_TYPE = "INVALID_TYPE"
    const val INVALID_CATEGORY = "INVALID_CATEGORY"
    const val INVALID_DATE = "INVALID_DATE"
    const val REFUND_MISSING_ORIGINAL = "REFUND_MISSING_ORIGINAL"
    const val REFUND_ORIGINAL_NOT_FOUND = "REFUND_ORIGINAL_NOT_FOUND"
    const val NOTE_TOO_LONG = "NOTE_TOO_LONG"
    const val DUPLICATE_FINGERPRINT = "DUPLICATE_FINGERPRINT"
    const val DUPLICATE_ID = "DUPLICATE_ID"
    const val IMPORT_FORMAT_VERSION = "IMPORT_FORMAT_VERSION"
    const val IMPORT_VALIDATION_FAILED = "IMPORT_VALIDATION_FAILED"
    const val IMPORT_MALFORMED_JSON = "IMPORT_MALFORMED_JSON"
    const val NOT_FOUND = "NOT_FOUND"
    const val INVALID_TIMEZONE = "INVALID_TIMEZONE"
}

@Serializable
data class Transaction(
    val id: String,
    val type: String,
    val amountMinor: Long,
    val currency: String,
    val category: String,
    val account: String,
    val note: String,
    val occurredAtEpochMillis: Long,
    val localDate: String,
    val timezoneId: String,
    val countInBudget: Boolean,
    val refundOfId: String? = null,
    val source: String,
    val fingerprint: String,
    val createdAtEpochMillis: Long,
    val updatedAtEpochMillis: Long
)

@Serializable
data class Category(
    val id: String,
    val name: String,
    val kind: String,
    val sortOrder: Int,
    val usageCount: Long = 0
)

@Serializable
data class BudgetRule(
    val id: String,
    val dailyAmountMinor: Long,
    val currency: String,
    val effectiveFromLocalDate: String,
    val createdAtEpochMillis: Long
)

/** JSON 导出信封（docs/EXPORT_FORMAT.md 第 2 节）。 */
@Serializable
data class LedgerEnvelope(
    val formatVersion: Int,
    val app: String,
    val exportedAtEpochMillis: Long,
    val timezone: String,
    val defaultCurrency: String,
    val transactions: List<Transaction> = emptyList(),
    val categories: List<Category> = emptyList(),
    val budgetRules: List<BudgetRule> = emptyList()
)

/** 新增/编辑账单的输入。id 为空表示新增；occurredAt 为 0 表示取当前时间。 */
data class SaveTxnInput(
    val id: String? = null,
    val type: String,
    val amountText: String,
    val currency: String,
    val category: String,
    val account: String,
    val note: String,
    val occurredAtEpochMillis: Long,
    val localDate: String,
    val timezoneId: String,
    val countInBudget: Boolean,
    val refundOfId: String? = null,
    val source: String = TxnSource.MANUAL,
    val forceSave: Boolean = false
)

data class SaveResult(val transaction: Transaction?, val errorCode: String?) {
    val isSuccess: Boolean get() = transaction != null
}

data class DateRange(val from: String, val to: String)

/** 单日预算视图（预算引擎输出）。 */
data class DailyOverview(
    val localDate: String,
    val hasBudget: Boolean,
    val budgetMinor: Long,
    val netSpentMinor: Long,
    val totalSpentMinor: Long,
    val remainingMinor: Long,
    val overspent: Boolean
)

data class TodayOverview(
    val localDate: String,
    val hasBudget: Boolean,
    val budgetMinor: Long,
    val netSpentMinor: Long,
    val totalSpentMinor: Long,
    val remainingMinor: Long,
    val overspent: Boolean,
    val transactions: List<Transaction>
)

data class CategorySpend(val category: String, val amountMinor: Long, val ratio: Double)

data class RangeStats(
    val fromLocalDate: String,
    val toLocalDate: String,
    val totalExpenseAll: Long,
    val totalExpenseInBudget: Long,
    val refundTotal: Long,
    val incomeTotal: Long,
    val transferTotal: Long,
    val netSpentMinor: Long,
    val byCategory: List<CategorySpend>,
    val daily: List<DailyOverview>,
    val overspentDays: Int
)

data class ImportPreview(
    val transactionCount: Long,
    val categoryCount: Long,
    val budgetRuleCount: Long,
    val firstLocalDate: String?,
    val lastLocalDate: String?,
    val duplicateCount: Long,
    val valid: Boolean,
    val errors: List<String>
)

data class ApplyImportResult(
    val applied: Boolean,
    val insertedCount: Long,
    val skippedCount: Long,
    val errorCode: String?,
    val errors: List<String> = emptyList()
)
