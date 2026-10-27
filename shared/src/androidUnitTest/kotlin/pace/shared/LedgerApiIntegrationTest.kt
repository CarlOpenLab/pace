package pace.shared

import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import pace.shared.db.PaceDatabase
import pace.shared.model.ErrorCodes
import pace.shared.model.SaveTxnInput
import pace.shared.model.TxnType

/**
 * LedgerApi 数据库集成测试（JVM 内存 SQLite，Android 单元测试运行时执行）。
 * 覆盖 docs/EDGE_CASES.md 中 U2/U3/R1-R3/E1/E2/I1/I2 与预算生效规则。
 */
class LedgerApiIntegrationTest {

    private lateinit var driver: SqlDriver
    private lateinit var api: LedgerApi
    private var now: Long = 1_792_000_000_000L

    @BeforeTest
    fun setUp() {
        driver = JdbcSqliteDriver("jdbc:sqlite::memory:")
        PaceDatabase.Schema.create(driver)
        api = LedgerApi(PaceDatabase(driver)) { now }
    }

    @AfterTest
    fun tearDown() {
        driver.close()
    }

    private fun saveInput(
        type: String = TxnType.EXPENSE,
        amountText: String = "12.00",
        category: String = "餐饮",
        note: String = "午饭",
        localDate: String = "2026-10-26",
        countInBudget: Boolean = true,
        refundOfId: String? = null,
        id: String? = null,
        forceSave: Boolean = false
    ) = SaveTxnInput(
        id = id,
        type = type,
        amountText = amountText,
        currency = "CNY",
        category = category,
        account = "现金",
        note = note,
        occurredAtEpochMillis = now,
        localDate = localDate,
        timezoneId = "Asia/Shanghai",
        countInBudget = countInBudget,
        refundOfId = refundOfId,
        source = "MANUAL",
        forceSave = forceSave
    )

    @Test
    fun save_and_today_overview() {
        api.setBudget("50", "CNY", "2026-10-01")
        val result = api.saveTransaction(saveInput(amountText = "12.00"))
        assertTrue(result.isSuccess)
        assertNull(result.errorCode)
        val overview = api.todayOverview("2026-10-26")
        assertEquals(5000L, overview.budgetMinor)
        assertEquals(1200L, overview.netSpentMinor)
        assertEquals(3800L, overview.remainingMinor)
        assertEquals(1, overview.transactions.size)
        assertTrue(api.categories().any { it.name == "餐饮" })
    }

    @Test
    fun u2_duplicate_fingerprint_requires_force() {
        val first = api.saveTransaction(saveInput(note = "咖啡"))
        assertTrue(first.isSuccess)
        val second = api.saveTransaction(saveInput(note = "咖啡"))
        assertFalse(second.isSuccess)
        assertEquals(ErrorCodes.DUPLICATE_FINGERPRINT, second.errorCode)
        val forced = api.saveTransaction(saveInput(note = "咖啡", forceSave = true))
        assertTrue(forced.isSuccess)
        assertEquals(2, api.todayOverview("2026-10-26").transactions.size)
    }

    @Test
    fun u3_delete_then_undo_restores() {
        val saved = api.saveTransaction(saveInput(note = "打车")).transaction!!
        val deleted = api.deleteTransaction(saved.id)
        assertEquals(saved.id, deleted?.id)
        assertNull(api.transaction(saved.id))
        // 撤销：用原数据重新保存
        val restored = api.saveTransaction(
            saveInput(note = "打车", id = deleted!!.id)
        )
        assertTrue(restored.isSuccess)
        assertEquals(saved.localDate, api.transaction(saved.id)?.localDate)
    }

    @Test
    fun r1_r2_refund_validation() {
        val missing = api.saveTransaction(saveInput(type = TxnType.REFUND, refundOfId = null))
        assertEquals(ErrorCodes.REFUND_MISSING_ORIGINAL, missing.errorCode)
        val notFound = api.saveTransaction(saveInput(type = TxnType.REFUND, refundOfId = "nope"))
        assertEquals(ErrorCodes.REFUND_ORIGINAL_NOT_FOUND, notFound.errorCode)
        val original = api.saveTransaction(saveInput(note = "网购")).transaction!!
        val income = api.saveTransaction(
            saveInput(type = TxnType.INCOME, amountText = "100", note = "工资", category = "工资")
        ).transaction!!
        val badOriginal = api.saveTransaction(saveInput(type = TxnType.REFUND, refundOfId = income.id))
        assertEquals(ErrorCodes.REFUND_ORIGINAL_NOT_FOUND, badOriginal.errorCode)
        val ok = api.saveTransaction(
            saveInput(type = TxnType.REFUND, amountText = "5", note = "退货运费", refundOfId = original.id)
        )
        assertTrue(ok.isSuccess)
    }

    @Test
    fun r4_income_transfer_never_count_in_budget() {
        api.saveTransaction(saveInput(type = TxnType.INCOME, amountText = "100", category = "工资", note = "工资", countInBudget = true))
        api.saveTransaction(saveInput(type = TxnType.TRANSFER, amountText = "30", category = "转账", note = "还款", countInBudget = true))
        val overview = api.todayOverview("2026-10-26")
        assertEquals(0L, overview.netSpentMinor)
        assertTrue(api.allTransactions().none { it.countInBudget })
    }

    @Test
    fun b7_budget_effective_dates() {
        api.setBudget("50", "CNY", "2026-10-01")
        api.setBudget("60", "CNY", "2026-10-10")
        assertEquals(5000L, api.budgetFor("2026-10-05")!!.dailyAmountMinor)
        assertEquals(6000L, api.budgetFor("2026-10-12")!!.dailyAmountMinor)
        assertEquals(2, api.budgetHistory().size)
    }

    @Test
    fun invalid_inputs() {
        assertEquals(ErrorCodes.INVALID_AMOUNT, api.saveTransaction(saveInput(amountText = "0")).errorCode)
        assertEquals(ErrorCodes.INVALID_AMOUNT, api.saveTransaction(saveInput(amountText = "10.005")).errorCode)
        assertEquals(ErrorCodes.INVALID_TYPE, api.saveTransaction(saveInput(type = "SPLITS")).errorCode)
        assertEquals(ErrorCodes.INVALID_CATEGORY, api.saveTransaction(saveInput(category = "不存在的分类")).errorCode)
        assertEquals(ErrorCodes.INVALID_DATE, api.saveTransaction(saveInput(localDate = "2026/10/26")).errorCode)
        assertEquals(
            ErrorCodes.NOTE_TOO_LONG,
            api.saveTransaction(saveInput(note = "长".repeat(501))).errorCode
        )
        // 用已不存在的 id 保存 = upsert 恢复（撤销语义），而不是报错
        val ghost = api.saveTransaction(saveInput(id = "ghost", note = "恢复的账单"))
        assertTrue(ghost.isSuccess)
        assertEquals("ghost", ghost.transaction?.id)
    }

    @Test
    fun export_json_roundtrip_fresh_install() {
        api.setBudget("50", "CNY", "2026-10-01")
        api.saveTransaction(saveInput(note = "午饭"))
        api.saveTransaction(saveInput(note = "晚饭", amountText = "20"))
        val json = api.exportJson("Asia/Shanghai")

        // 全新安装环境（E1）
        val driver2 = JdbcSqliteDriver("jdbc:sqlite::memory:")
        PaceDatabase.Schema.create(driver2)
        val api2 = LedgerApi(PaceDatabase(driver2)) { now }
        val applied = api2.applyImport(json, "REPLACE")
        assertTrue(applied.applied)
        assertEquals(2L, applied.insertedCount)
        assertEquals(5000L, api2.budgetFor("2026-10-26")!!.dailyAmountMinor)
        assertEquals(2, api2.todayOverview("2026-10-26").transactions.size)
        assertEquals(3200L, api2.todayOverview("2026-10-26").netSpentMinor)
        driver2.close()
    }

    @Test
    fun e2_i1_merge_import_skips_duplicates() {
        api.setBudget("50", "CNY", "2026-10-01")
        api.saveTransaction(saveInput(note = "午饭"))
        val json = api.exportJson("Asia/Shanghai")

        val preview = api.previewImport(json)
        assertTrue(preview.valid)
        assertEquals(1L, preview.transactionCount)
        assertEquals(1L, preview.duplicateCount)

        val applied = api.applyImport(json, "MERGE")
        assertTrue(applied.applied)
        assertEquals(0L, applied.insertedCount)
        assertEquals(1L, applied.skippedCount)
        assertEquals(1, api.allTransactions().size)
    }

    @Test
    fun i2_invalid_import_leaves_ledger_untouched() {
        api.saveTransaction(saveInput(note = "午饭"))
        val before = api.allTransactions()
        val result = api.applyImport("{ broken", "MERGE")
        assertFalse(result.applied)
        assertEquals(ErrorCodes.IMPORT_VALIDATION_FAILED, result.errorCode)
        assertEquals(before, api.allTransactions())
    }

    @Test
    fun invalid_amount_in_file_rejected() {
        api.saveTransaction(saveInput(note = "午饭"))
        val json = api.exportJson("Asia/Shanghai")
            .replace(Regex("\"amountMinor\":\\s*1200"), "\"amountMinor\": -1")
        val preview = api.previewImport(json)
        assertFalse(preview.valid)
        assertTrue(preview.errors.first().startsWith(ErrorCodes.INVALID_AMOUNT))
        assertFalse(api.applyImport(json, "MERGE").applied)
    }

    @Test
    fun u5_clear_all_data_resets() {
        api.saveTransaction(saveInput(note = "午饭"))
        assertTrue(api.clearAllData())
        assertEquals(0, api.allTransactions().size)
        assertEquals(0, api.budgetHistory().size)
        assertTrue(api.categories().isNotEmpty()) // 默认分类恢复
    }

    @Test
    fun suggest_category_local_offline() {
        assertEquals("餐饮", api.suggestCategory("午饭 28", TxnType.EXPENSE))
        assertEquals("其他", api.suggestCategory(" ", TxnType.EXPENSE))
    }

    @Test
    fun search_treats_like_wildcards_as_literals() {
        api.saveTransaction(saveInput(note = "满100减20"))
        api.saveTransaction(saveInput(note = "折扣100%"))
        api.saveTransaction(saveInput(note = "a_b"))
        api.saveTransaction(saveInput(note = "axb"))
        // % 与 _ 是通配符：字面搜索不该扩大命中范围
        assertEquals(1, api.searchTransactions("100%").size)
        assertEquals(1, api.searchTransactions("满100").size)
        assertEquals(1, api.searchTransactions("a_b").size)
        assertEquals(1, api.searchTransactions("axb").size)
        assertEquals(0, api.searchTransactions("").size)
    }
}
