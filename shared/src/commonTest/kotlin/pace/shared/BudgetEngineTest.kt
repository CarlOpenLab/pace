package pace.shared

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import pace.shared.budget.BudgetEngine
import pace.shared.model.TxnType
import pace.shared.statistics.StatsEngine

/** docs/BUDGET_RULES.md 第 7 节 B1–B10 验收案例。 */
class BudgetEngineTest {

    private val today = "2026-10-26"

    private fun engine(vararg txns: pace.shared.model.Transaction) = txns.toList()

    @Test
    fun b1_normal_day() {
        val txns = engine(txn("a", amountMinor = 1200, localDate = today))
        val overview = BudgetEngine.todayOverview(txns, listOf(rule(5000, "2026-10-01")), today)
        assertEquals(5000L, overview.budgetMinor)
        assertEquals(1200L, overview.netSpentMinor)
        assertEquals(3800L, overview.remainingMinor)
        assertFalse(overview.overspent)
    }

    @Test
    fun b2_refund_reduces_net_spend() {
        val txns = engine(
            txn("a", amountMinor = 1200, localDate = today),
            txn("r", type = TxnType.REFUND, amountMinor = 200, localDate = today)
        )
        val overview = BudgetEngine.todayOverview(txns, listOf(rule(5000, "2026-10-01")), today)
        assertEquals(1000L, overview.netSpentMinor)
        assertEquals(4000L, overview.remainingMinor)
    }

    @Test
    fun b3_exclude_from_budget_keeps_total_spend() {
        val txns = engine(
            txn("a", amountMinor = 1200, localDate = today, countInBudget = false),
            txn("b", amountMinor = 800, localDate = today, countInBudget = true)
        )
        val overview = BudgetEngine.todayOverview(txns, listOf(rule(5000, "2026-10-01")), today)
        assertEquals(800L, overview.netSpentMinor)
        assertEquals(4200L, overview.remainingMinor)
        assertEquals(2000L, overview.totalSpentMinor)
    }

    @Test
    fun b4_overspend() {
        val txns = engine(txn("a", amountMinor = 7000, localDate = today))
        val overview = BudgetEngine.todayOverview(txns, listOf(rule(5000, "2026-10-01")), today)
        assertTrue(overview.overspent)
        assertEquals(-2000L, overview.remainingMinor)
    }

    @Test
    fun b5_b6_no_carry_over() {
        val txns = engine(
            txn("d1a", amountMinor = 1000, localDate = "2026-10-24"),
            txn("d1b", amountMinor = 7000, localDate = "2026-10-25")
            // 10-26 无支出
        )
        val rules = listOf(rule(5000, "2026-10-01"))
        val day1 = BudgetEngine.todayOverview(txns, rules, "2026-10-24")
        val day2 = BudgetEngine.todayOverview(txns, rules, "2026-10-25")
        val day3 = BudgetEngine.todayOverview(txns, rules, "2026-10-26")
        assertEquals(4000L, day1.remainingMinor)   // 前一日结余
        assertTrue(day2.overspent)                  // 前一日超支
        assertEquals(5000L, day3.remainingMinor)   // 结余不结转、超支不传染
        assertFalse(day3.overspent)
    }

    @Test
    fun b7_effective_dates() {
        val rules = listOf(rule(5000, "2026-10-01"), rule(6000, "2026-10-10"))
        assertEquals(5000L, BudgetEngine.budgetFor(rules, "2026-10-05")!!.dailyAmountMinor)
        assertEquals(6000L, BudgetEngine.budgetFor(rules, "2026-10-10")!!.dailyAmountMinor)
        assertEquals(6000L, BudgetEngine.budgetFor(rules, "2026-10-12")!!.dailyAmountMinor)
        assertEquals(5000L, BudgetEngine.budgetFor(rules, "2026-10-01")!!.dailyAmountMinor)
    }

    @Test
    fun b8_no_budget_rules() {
        val overview = BudgetEngine.todayOverview(engine(txn("a", localDate = today)), emptyList(), today)
        assertFalse(overview.hasBudget)
        assertEquals(0L, overview.budgetMinor)
    }

    @Test
    fun b9_income_transfer_excluded() {
        val txns = engine(
            txn("inc", type = TxnType.INCOME, amountMinor = 100000, localDate = today),
            txn("tr", type = TxnType.TRANSFER, amountMinor = 3000, localDate = today),
            txn("exp", type = TxnType.EXPENSE, amountMinor = 1000, localDate = today)
        )
        val overview = BudgetEngine.todayOverview(txns, listOf(rule(5000, "2026-10-01")), today)
        assertEquals(1000L, overview.netSpentMinor)
    }

    @Test
    fun b10_refund_belongs_to_own_day() {
        val txns = engine(
            txn("exp", amountMinor = 1200, localDate = "2026-10-01"),
            txn("ref", type = TxnType.REFUND, amountMinor = 200, localDate = "2026-10-03")
        )
        val rules = listOf(rule(5000, "2026-10-01"))
        assertEquals(1200L, BudgetEngine.netSpend(txns, "2026-10-01"))
        assertEquals(-200L, BudgetEngine.netSpend(txns, "2026-10-03"))
        val day3 = BudgetEngine.dailyOverview(txns, rules, "2026-10-03")
        assertEquals(5200L, day3.remainingMinor)
    }

    @Test
    fun stats_range_weekly_and_category_ranking() {
        val txns = engine(
            txn("a", amountMinor = 1200, localDate = "2026-10-26", category = "餐饮"),
            txn("b", amountMinor = 800, localDate = "2026-10-27", category = "交通"),
            txn("c", amountMinor = 3000, localDate = "2026-10-27", category = "餐饮", countInBudget = false),
            txn("inc", type = TxnType.INCOME, amountMinor = 50000, localDate = "2026-10-26"),
            txn("tr", type = TxnType.TRANSFER, amountMinor = 2000, localDate = "2026-10-26")
        )
        val stats = StatsEngine.rangeStats(txns, listOf(rule(5000, "2026-10-01")), "2026-10-26", "2026-10-27")
        assertEquals(5000L, stats.totalExpenseAll)
        assertEquals(2000L, stats.totalExpenseInBudget)
        assertEquals(50000L, stats.incomeTotal)
        assertEquals(2000L, stats.transferTotal)
        assertEquals("餐饮", stats.byCategory.first().category)
        assertEquals(4200L, stats.byCategory.first().amountMinor)
        assertEquals(2, stats.daily.size) // 10-26..10-27 共两天
    }
}
