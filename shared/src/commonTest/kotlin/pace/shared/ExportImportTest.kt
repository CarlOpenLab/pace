package pace.shared

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import pace.shared.classifier.KeywordClassifier
import pace.shared.export.Exporters
import pace.shared.importer.Importer
import pace.shared.model.ErrorCodes
import pace.shared.model.TxnType

class ClassifierTest {

    @Test
    fun keyword_rules_offline() {
        assertEquals("餐饮", KeywordClassifier.suggestCategory("昨天午饭 28 元", TxnType.EXPENSE))
        assertEquals("交通", KeywordClassifier.suggestCategory("打车回家", TxnType.EXPENSE))
        assertEquals("工资", KeywordClassifier.suggestCategory("10月工资", TxnType.INCOME))
        assertEquals("转账", KeywordClassifier.suggestCategory("信用卡还款", TxnType.TRANSFER))
        assertEquals("其他", KeywordClassifier.suggestCategory("随便什么", TxnType.EXPENSE))
    }
}

class ExportImportTest {

    private fun envelopeJson(count: Int = 1, mutate: (pace.shared.model.Transaction) -> pace.shared.model.Transaction = { it }): String {
        val txns = (1..count).map { i -> mutate(txn("t$i", amountMinor = 1000L + i, localDate = "2026-10-2$i")) }
        val envelope = Exporters.buildEnvelope(
            transactions = txns,
            categories = listOf(pace.shared.model.Category("c1", "餐饮", TxnType.EXPENSE, 0)),
            budgetRules = listOf(rule(5000, "2026-10-01")),
            timezoneId = "Asia/Shanghai",
            defaultCurrency = "CNY",
            exportedAtEpochMillis = 1_792_000_000_000L
        )
        return Exporters.exportJson(envelope)
    }

    @Test
    fun e1_json_roundtrip_validates() {
        val json = envelopeJson(3)
        val outcome = Importer.parseAndValidate(json)
        assertTrue(outcome is Importer.ParseOutcome.Ok)
        assertEquals(3, outcome.envelope.transactions.size)
        assertEquals(1, outcome.envelope.budgetRules.size)
    }

    @Test
    fun e2_duplicate_detection() {
        val json = envelopeJson(2)
        val outcome = Importer.parseAndValidate(json)
        assertTrue(outcome is Importer.ParseOutcome.Ok)
        val env = outcome.envelope
        val dup = Importer.duplicateCount(env, existingIds = env.transactions.map { it.id }.toSet(), existingFingerprints = emptySet())
        assertEquals(2L, dup)
    }

    @Test
    fun e3_negative_amount_rejected() {
        val json = envelopeJson(1) { it.copy(amountMinor = -100) }
        val outcome = Importer.parseAndValidate(json)
        assertTrue(outcome is Importer.ParseOutcome.Invalid)
        assertTrue(outcome.errors.first().startsWith(ErrorCodes.INVALID_AMOUNT))
    }

    @Test
    fun e4_future_format_version_rejected() {
        val json = envelopeJson(1).replace("\"formatVersion\": 1", "\"formatVersion\": 99")
        val outcome = Importer.parseAndValidate(json)
        assertTrue(outcome is Importer.ParseOutcome.Invalid)
        assertTrue(ErrorCodes.IMPORT_FORMAT_VERSION in outcome.errors)
    }

    @Test
    fun e6_malformed_json_rejected() {
        val outcome = Importer.parseAndValidate("{ not valid json")
        assertTrue(outcome is Importer.ParseOutcome.Invalid)
        assertTrue(ErrorCodes.IMPORT_MALFORMED_JSON in outcome.errors)
    }

    @Test
    fun i3_empty_ledger_allowed() {
        val envelope = pace.shared.model.LedgerEnvelope(
            formatVersion = 1, app = "pace", exportedAtEpochMillis = 0,
            timezone = "Asia/Shanghai", defaultCurrency = "CNY"
        )
        val outcome = Importer.parseAndValidate(Exporters.exportJson(envelope))
        assertTrue(outcome is Importer.ParseOutcome.Ok)
    }

    @Test
    fun i4_csv_escaping() {
        assertEquals("plain", Exporters.csvEscape("plain"))
        assertEquals("\"a,b\"", Exporters.csvEscape("a,b"))
        assertEquals("\"say \"\"hi\"\"\"", Exporters.csvEscape("say \"hi\""))
        assertEquals("\"line1\nline2\"", Exporters.csvEscape("line1\nline2"))
    }

    @Test
    fun i4_csv_formula_injection_neutralized() {
        // 导出的 CSV 会被 Excel 打开：以 = + @ Tab CR 开头的文本不能原样出去
        assertEquals("'=cmd", Exporters.csvEscape("=cmd"))
        assertEquals("'+SUM(A1)", Exporters.csvEscape("+SUM(A1)"))
        assertEquals("'@x", Exporters.csvEscape("@x"))
        assertEquals("'\tx", Exporters.csvEscape("\tx"))
        // \r 本身触发 RFC 4180 加引号
        assertEquals("\"'\rx\"", Exporters.csvEscape("\rx"))
        // 负数金额是合法数字字面量，不处理
        assertEquals("-12.34", Exporters.csvEscape("-12.34"))
        // 普通文本和数字不受影响
        assertEquals("满100减20", Exporters.csvEscape("满100减20"))
        assertEquals("28.50", Exporters.csvEscape("28.50"))
    }

    @Test
    fun csv_output_shape() {
        val csv = Exporters.exportCsv(
            listOf(txn("a", amountMinor = 2850, localDate = "2026-10-25", note = "午饭,团建"))
        )
        val lines = csv.trim().lines()
        assertTrue(lines.first().startsWith("id,date,time,type,amount,currency,category,account,note"))
        assertTrue(lines[1].contains("2026-10-25"))
        assertTrue(lines[1].contains("EXPENSE,28.50,CNY,餐饮,现金,\"午饭,团建\",true"))
    }

    @Test
    fun refund_without_original_rejected() {
        val json = envelopeJson(1) { it.copy(type = TxnType.REFUND, refundOfId = null) }
        val outcome = Importer.parseAndValidate(json)
        assertTrue(outcome is Importer.ParseOutcome.Invalid)
        assertTrue(outcome.errors.first().startsWith(ErrorCodes.REFUND_MISSING_ORIGINAL))
    }

    @Test
    fun duplicate_ids_inside_file_rejected() {
        val json = envelopeJson(2) { it.copy(id = "same-id") }
        val outcome = Importer.parseAndValidate(json)
        assertTrue(outcome is Importer.ParseOutcome.Invalid)
        assertTrue(outcome.errors.any { it.startsWith(ErrorCodes.DUPLICATE_ID) })
    }
}
