package pace.shared.validation

import pace.shared.datetime.PaceDates
import pace.shared.money.Money
import pace.shared.model.ErrorCodes
import pace.shared.model.TxnType

/**
 * 账单与预算输入校验（docs/DATA_MODEL.md 第 7 节）。
 * 返回 null 表示通过；否则返回错误码。
 */
object Validators {

    fun validateAmountText(amountText: String): String? =
        if (Money.parseToMinor(amountText) == null) ErrorCodes.INVALID_AMOUNT else null

    fun validateAmountMinor(amountMinor: Long): String? =
        if (amountMinor !in 1..Money.MAX_AMOUNT_MINOR) ErrorCodes.INVALID_AMOUNT else null

    fun validateType(type: String): String? =
        if (!TxnType.isValid(type)) ErrorCodes.INVALID_TYPE else null

    fun validateNote(note: String): String? =
        if (note.length > 500) ErrorCodes.NOTE_TOO_LONG else null

    fun validateLocalDate(iso: String): String? =
        if (!PaceDates.isValidLocalDate(iso)) ErrorCodes.INVALID_DATE else null

    fun validateTimezone(timezoneId: String): String? =
        if (!PaceDates.isValidTimeZoneId(timezoneId)) ErrorCodes.INVALID_TIMEZONE else null

    fun validateCategoryName(category: String, knownCategoryNames: Set<String>): String? =
        if (category.isBlank() || category !in knownCategoryNames) ErrorCodes.INVALID_CATEGORY else null

    /** 退款必须关联一笔存在的 EXPENSE（R1/R2）。existence 与 typeOfOriginal 由调用方查询。 */
    fun validateRefund(
        type: String,
        refundOfId: String?,
        originalExists: Boolean,
        originalIsExpense: Boolean
    ): String? {
        if (type != TxnType.REFUND) return null
        if (refundOfId.isNullOrBlank()) return ErrorCodes.REFUND_MISSING_ORIGINAL
        if (!originalExists || !originalIsExpense) return ErrorCodes.REFUND_ORIGINAL_NOT_FOUND
        return null
    }
}
