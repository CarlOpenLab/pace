package pace.shared.importer

import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import pace.shared.export.Exporters
import pace.shared.model.ErrorCodes
import pace.shared.model.LedgerEnvelope
import pace.shared.model.Transaction
import pace.shared.model.TxnType
import pace.shared.validation.Validators

/**
 * JSON 导入（恢复）：整体校验 → 预览 → 事务性写入（docs/EXPORT_FORMAT.md 第 4 节）。
 * 本文件只做无副作用的解析与校验；写入由 LedgerApi 在数据库事务内执行。
 */
object Importer {

    private val decodeJson = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    const val MAX_ERRORS = 20

    sealed class ParseOutcome {
        data class Ok(val envelope: LedgerEnvelope) : ParseOutcome()
        data class Invalid(val errors: List<String>) : ParseOutcome()
    }

    /** 整体解析 + 逐条校验；任何一条非法即整体 invalid（E3/E4/E6）。 */
    fun parseAndValidate(jsonText: String): ParseOutcome {
        val envelope = try {
            decodeJson.decodeFromString(LedgerEnvelope.serializer(), jsonText)
        } catch (_: SerializationException) {
            return ParseOutcome.Invalid(listOf(ErrorCodes.IMPORT_MALFORMED_JSON))
        } catch (_: IllegalArgumentException) {
            return ParseOutcome.Invalid(listOf(ErrorCodes.IMPORT_MALFORMED_JSON))
        }
        val errors = mutableListOf<String>()
        if (envelope.app != Exporters.APP_ID) {
            errors += ErrorCodes.IMPORT_MALFORMED_JSON
        }
        if (envelope.formatVersion > Exporters.FORMAT_VERSION) {
            errors += ErrorCodes.IMPORT_FORMAT_VERSION
        }
        val categoryNames = envelope.categories.map { it.name }.toSet()
        val seenIds = mutableSetOf<String>()
        for (txn in envelope.transactions) {
            if (seenIds.contains(txn.id)) {
                errors += "${ErrorCodes.DUPLICATE_ID}:${txn.id}"
                if (errors.size >= MAX_ERRORS) break
            }
            seenIds += txn.id
            val error = validateRecord(txn, categoryNames)
            if (error != null) {
                errors += "${error}:${txn.id}"
                if (errors.size >= MAX_ERRORS) break
            }
        }
        if (envelope.transactions.isEmpty() && envelope.categories.isEmpty() && envelope.budgetRules.isEmpty()) {
            // 允许空文件（I3），不视为错误
        }
        return if (errors.isEmpty()) ParseOutcome.Ok(envelope) else ParseOutcome.Invalid(errors.take(MAX_ERRORS))
    }

    /** 单条账单记录校验（错误码见 docs/DATA_MODEL.md 第 7 节）。 */
    fun validateRecord(txn: Transaction, knownCategoryNames: Set<String>): String? {
        Validators.validateType(txn.type)?.let { return it }
        Validators.validateAmountMinor(txn.amountMinor)?.let { return it }
        if (txn.currency.isBlank()) return ErrorCodes.INVALID_AMOUNT
        val categoryOk = txn.category.isNotBlank() &&
            (txn.category in knownCategoryNames || txn.category == "其他")
        if (!categoryOk) return ErrorCodes.INVALID_CATEGORY
        Validators.validateLocalDate(txn.localDate)?.let { return it }
        Validators.validateNote(txn.note)?.let { return it }
        if (txn.occurredAtEpochMillis < 0 || txn.occurredAtEpochMillis > 4_102_444_800_000L) {
            return ErrorCodes.INVALID_DATE
        }
        if (txn.createdAtEpochMillis < 0 || txn.updatedAtEpochMillis < txn.createdAtEpochMillis) {
            return ErrorCodes.INVALID_DATE
        }
        if (txn.type == TxnType.REFUND && txn.refundOfId.isNullOrBlank()) {
            return ErrorCodes.REFUND_MISSING_ORIGINAL
        }
        return null
    }

    /**
     * 与现有账本的重复检测（4.3 节）：id 相同或指纹相同均视为重复。
     */
    fun duplicateCount(envelope: LedgerEnvelope, existingIds: Set<String>, existingFingerprints: Set<String>): Long {
        var count = 0L
        for (txn in envelope.transactions) {
            if (txn.id in existingIds || txn.fingerprint in existingFingerprints) count += 1
        }
        return count
    }
}
