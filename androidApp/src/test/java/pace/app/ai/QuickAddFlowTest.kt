package pace.app.ai

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import pace.app.AppContainer
import pace.shared.model.ErrorCodes
import pace.shared.model.TxnType

/**
 * 一句话记账 → 入账 的端到端回归（Robolectric，真 SQLite，无模拟器）。
 * 覆盖本机拆句、草稿映射、DraftSaver 防重、BYOK 设置存取与 Key 加密失败兜底。
 * AppContainer 是进程级单例：每个测试用 clearAllData 清场，设置项由各测试自带。
 */
@RunWith(AndroidJUnit4::class)
@Config(sdk = [34])
class QuickAddFlowTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val today get() = AppContainer.todayIso()

    @Before
    fun setUp() {
        // Robolectric 每个测试重置 SQLite 连接池：单例必须换新 driver 再清场
        AppContainer.resetForTest(context as android.app.Application)
        AppContainer.ledger.clearAllData()
        AiSettings.init(context)
        // 清掉上一个测试留下的设置状态
        AiSettings.updateEnabled(false)
        AiSettings.updateKey("")
    }

    @Test
    fun local_parse_and_inline_save_lands_in_ledger() {
        // 本机规则拆「午饭 28」：一笔、齐全，走就地确认路径
        val drafts = LocalDrafts.parse("午饭 28", today)
        assertEquals(1, drafts.size)
        val draft = drafts.first()
        assertEquals(TxnType.EXPENSE, draft.type)
        assertEquals("28", draft.amountText)
        assertEquals(2800L, draft.amountMinor)
        assertEquals(today, draft.localDate)
        assertTrue(draft.missingFields.isEmpty())

        // 「记上」= DraftSaver.save → 走 saveTransaction 完整校验入账
        val outcome = DraftSaver.save(listOf(draft))
        assertEquals(1, outcome.saved)
        assertTrue(outcome.duplicated.isEmpty())
        assertTrue(outcome.failed.isEmpty())

        val saved = AppContainer.ledger.todayOverview(today)
        assertEquals(1, saved.transactions.size)
        assertEquals(2800L, saved.netSpentMinor)
    }

    @Test
    fun duplicate_draft_is_caught_by_fingerprint_guard() {
        val drafts = LocalDrafts.parse("午饭 28", today)
        val first = DraftSaver.save(drafts)
        assertEquals(1, first.saved)
        val second = DraftSaver.save(drafts)
        assertEquals(0, second.saved)
        assertEquals(1, second.duplicated.size)
        assertTrue(second.failed.isEmpty())

        // 用户说「照样记」：force 落库，不阻塞真实重复
        val forced = DraftSaver.save(drafts, force = true)
        assertEquals(1, forced.saved)
        assertEquals(2, AppContainer.ledger.todayOverview(today).transactions.size)
    }

    @Test
    fun multi_segment_sentence_goes_to_review_page() {
        // 两笔：超过一笔 → 走草稿确认页而不是就地确认
        val drafts = LocalDrafts.parse("午饭 28，地铁 4", today)
        assertEquals(2, drafts.size)
        val outcome = DraftSaver.save(drafts)
        assertEquals(2, outcome.saved)
        val overview = AppContainer.ledger.todayOverview(today)
        assertEquals(2, overview.transactions.size)
        assertEquals(3200L, overview.netSpentMinor)
    }

    @Test
    fun relative_date_draft_lands_on_yesterday() {
        val drafts = LocalDrafts.parse("昨天午饭 28", today)
        val draft = drafts.first()
        val yesterday = java.time.LocalDate.parse(today).minusDays(1).toString()
        assertEquals(yesterday, draft.localDate)
        val outcome = DraftSaver.save(listOf(draft))
        assertEquals(1, outcome.saved)
        // 不在今天的账单里
        assertEquals(0, AppContainer.ledger.todayOverview(today).transactions.size)
    }

    @Test
    fun draft_without_amount_is_blocked_before_save() {
        // 没有金额：collapsed 成一条「需要金额」，不得入账
        val drafts = LocalDrafts.parse("打车回家", today)
        assertTrue(drafts.all { DraftMissing.AMOUNT in it.missingFields })
        val outcome = DraftSaver.save(drafts)
        assertEquals(0, outcome.saved)
        assertEquals(0, AppContainer.ledger.todayOverview(today).transactions.size)
    }

    @Test
    fun update_amount_clears_missing_marker() {
        val draft = LocalDrafts.parse("打车回家", today).first()
        assertTrue(DraftMissing.AMOUNT in draft.missingFields)
        draft.updateAmount("12.5")
        assertEquals(1250L, draft.amountMinor)
        assertFalse(DraftMissing.AMOUNT in draft.missingFields)
        val outcome = DraftSaver.save(listOf(draft))
        assertEquals(1, outcome.saved)
    }

    @Test
    fun ai_settings_persist_and_gate_remote_path() {
        // 三项填全 + 开关打开 → 走模型；缺任一项 → 本机规则
        AiSettings.updateEnabled(true)
        AiSettings.updateEndpoint("https://api.deepseek.com/v1")
        AiSettings.updateModel("deepseek-chat")
        assertEquals(null, AiSettings.config())
        assertFalse(AiSettings.usesRemoteModel)

        AiSettings.updateKey("sk-test")
        assertEquals("sk-test", AiSettings.config()!!.key)
        assertTrue(AiSettings.usesRemoteModel)

        AiSettings.updateEnabled(false)
        assertFalse(AiSettings.usesRemoteModel)
        AiSettings.updateEnabled(true)

        // SharedPreferences 里有真值（进程重启后 init 会读回这些键）
        val prefs = context.getSharedPreferences("pace.ai", Context.MODE_PRIVATE)
        assertTrue(prefs.getBoolean("ai.enabled", false))
        assertEquals("https://api.deepseek.com/v1", prefs.getString("ai.endpoint", null))
        assertEquals("deepseek-chat", prefs.getString("ai.model", null))
    }

    @Test
    fun ai_key_store_failure_falls_back_to_memory_only() {
        // Robolectric 里 AndroidKeyStore 通常不可用：writeStoredKey 应失败并置位
        // keyStoreFailed，而不是崩溃或假装存上了——本页里 Key 仍可用（内存）。
        // 若运行环境真的支持 Keystore，则必须存得进、读得回。
        val prefs = context.getSharedPreferences("pace.ai", Context.MODE_PRIVATE)
        AiSettings.updateKey("sk-secret")
        assertEquals("sk-secret", AiSettings.key)
        if (AiSettings.keyStoreFailed) {
            assertNull(prefs.getString("ai.key.blob", null))
        } else {
            assertTrue(prefs.contains("ai.key.blob"))
        }

        AiSettings.clearKey()
        assertEquals("", AiSettings.key)
        assertFalse(AiSettings.usesRemoteModel)
    }

    @Test
    fun save_result_errors_surface_through_validation() {
        val bad = AppContainer.ledger.saveTransaction(
            draftSaveInput(LocalDrafts.parse("午饭 28", today).first().copy(amountText = ""), forceSave = false)
        )
        assertEquals(ErrorCodes.INVALID_AMOUNT, bad.errorCode)
    }
}
