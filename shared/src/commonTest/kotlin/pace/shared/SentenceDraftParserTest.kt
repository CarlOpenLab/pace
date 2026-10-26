package pace.shared

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import pace.shared.ai.DraftErrors
import pace.shared.ai.DraftMissing
import pace.shared.ai.DRAFT_VERSION
import pace.shared.ai.SentenceDraftParser
import pace.shared.model.TxnType

/**
 * 一句话记账：本机拆句规则的固定验收案例（brief 第 5 节 + docs/AI_PRIVACY.md v1）。
 */
class SentenceDraftParserTest {

    private val today = "2026-10-26" // 周日
    private val yesterday = "2026-10-25"

    @Test
    fun splitsTwoSegmentsAndCarriesTheDate() {
        val result = SentenceDraftParser.parse("昨天午饭 28，晚上打车 16", today)
        assertTrue(result.parseErrors.isEmpty())
        assertEquals(DRAFT_VERSION, result.draftVersion)
        assertEquals(2, result.drafts.size)

        val first = result.drafts[0]
        assertEquals(TxnType.EXPENSE, first.type)
        assertEquals(2800L, first.amountMinor)
        assertEquals(yesterday, first.localDate)
        assertEquals("餐饮", first.category)
        assertTrue(first.missingFields.isEmpty())
        assertTrue(first.note.contains("午饭"))

        val second = result.drafts[1]
        assertEquals(1600L, second.amountMinor)
        // 同一句话里日期延续：第二笔也是昨天
        assertEquals(yesterday, second.localDate)
        assertEquals("交通", second.category)
        assertTrue(second.missingFields.isEmpty())
    }

    @Test
    fun missingAmountIsFlaggedAndNeverGuessed() {
        val result = SentenceDraftParser.parse("昨天和朋友吃饭", today)
        assertEquals(1, result.drafts.size)
        val draft = result.drafts.single()
        assertEquals(0L, draft.amountMinor)
        assertEquals("", draft.amountText)
        assertTrue(draft.missingFields.contains(DraftMissing.AMOUNT))
        assertTrue(draft.needsAttention)
        assertEquals(yesterday, draft.localDate)
        assertTrue(draft.note.contains("和朋友吃饭"))
    }

    @Test
    fun amountWithUnitAndToday() {
        val result = SentenceDraftParser.parse("今天咖啡 25 元", today)
        val draft = result.drafts.single()
        assertEquals(2500L, draft.amountMinor)
        assertEquals(today, draft.localDate)
        assertEquals("餐饮", draft.category)
        assertEquals(TxnType.EXPENSE, draft.type)
        assertFalse(draft.needsAttention)
    }

    @Test
    fun incomeIsNotCountedInBudget() {
        val result = SentenceDraftParser.parse("发工资 12000", today)
        val draft = result.drafts.single()
        assertEquals(TxnType.INCOME, draft.type)
        assertEquals(1200000L, draft.amountMinor)
        assertFalse(draft.countInBudget)
        assertEquals(today, draft.localDate)
    }

    @Test
    fun explicitMonthDayIsResolved() {
        val result = SentenceDraftParser.parse("10月20日 房租 3000 元", today)
        val draft = result.drafts.single()
        assertEquals("2026-10-20", draft.localDate)
        assertEquals(300000L, draft.amountMinor)
        assertEquals("住房", draft.category)
    }

    @Test
    fun emptyInputIsRejected() {
        val result = SentenceDraftParser.parse("   ", today)
        assertTrue(result.drafts.isEmpty())
        assertEquals(listOf(DraftErrors.AI_REJECTED), result.parseErrors)
    }

    @Test
    fun multipleExpensesWithoutDateDefaultToToday() {
        val result = SentenceDraftParser.parse("打车 16，地铁 3", today)
        assertEquals(2, result.drafts.size)
        assertTrue(result.drafts.all { it.localDate == today })
        assertEquals(listOf(1600L, 300L), result.drafts.map { it.amountMinor })
        assertTrue(result.drafts.all { it.category == "交通" })
    }

    @Test
    fun amountsAreParsedByTheLocalMoneyRule() {
        val result = SentenceDraftParser.parse("超市 12.5 块", today)
        val draft = result.drafts.single()
        assertEquals(1250L, draft.amountMinor)
        assertEquals("购物", draft.category)
    }

    @Test
    fun clockNumbersAreNotAmounts() {
        // 「下午 3 点」里的 3 不是金额；后面没有金额时标需要金额
        val result = SentenceDraftParser.parse("下午 3 点买咖啡", today)
        val draft = result.drafts.single()
        assertEquals(0L, draft.amountMinor)
        assertTrue(draft.missingFields.contains(DraftMissing.AMOUNT))
    }

    @Test
    fun draftsCarryStableIdsAndOrder() {
        val result = SentenceDraftParser.parse("早饭 8，午饭 28，晚饭 40", today)
        assertEquals(listOf("d-001", "d-002", "d-003"), result.drafts.map { it.localId })
        assertEquals(listOf(800L, 2800L, 4000L), result.drafts.map { it.amountMinor })
    }
}
