package pace.shared.statistics

import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.LocalDate
import kotlinx.datetime.isoDayNumber
import kotlinx.datetime.minus
import kotlinx.datetime.plus
import pace.shared.budget.BudgetEngine
import pace.shared.model.BudgetRule
import pace.shared.model.CategorySpend
import pace.shared.model.DailyOverview
import pace.shared.model.DateRange
import pace.shared.model.RangeStats
import pace.shared.model.Transaction
import pace.shared.model.TxnType

/**
 * 本地确定性统计（docs/BUDGET_RULES.md 第 5 节）。全部基于纯函数。
 */
object StatsEngine {

    /** 本周：周一到周日（按 localDate 字符串）。 */
    fun weekRange(todayIso: String): DateRange? = runCatching {
        val date = LocalDate.parse(todayIso)
        val monday = date.minus(date.dayOfWeek.isoDayNumber - 1, DateTimeUnit.DAY)
        DateRange(monday.toString(), monday.plus(6, DateTimeUnit.DAY).toString())
    }.getOrNull()

    /** 本月：自然月。 */
    fun monthRange(todayIso: String): DateRange? = runCatching {
        val date = LocalDate.parse(todayIso)
        val first = LocalDate(date.year, date.monthNumber, 1)
        val last = first.plus(1, DateTimeUnit.MONTH).minus(1, DateTimeUnit.DAY)
        DateRange(first.toString(), last.toString())
    }.getOrNull()

    /** 逐日迭代辅助：返回 iso 的下一天字符串，解析失败返回 null。 */
    fun nextDay(iso: String): String? = runCatching {
        LocalDate.parse(iso).plus(1, DateTimeUnit.DAY).toString()
    }.getOrNull()

    /**
     * 区间统计。daily 为逐日预算对比（B5/B6：结余不结转、超支不传染）。
     */
    fun rangeStats(
        transactions: List<Transaction>,
        rules: List<BudgetRule>,
        fromLocalDate: String,
        toLocalDate: String,
        dayIterator: (String) -> String? = ::nextDay
    ): RangeStats {
        val inRange = transactions.filter { it.localDate in fromLocalDate..toLocalDate }
        var expenseAll = 0L
        var expenseInBudget = 0L
        var refund = 0L
        var income = 0L
        var transfer = 0L
        val byCategory = linkedMapOf<String, Long>()
        for (txn in inRange) {
            when (txn.type) {
                TxnType.EXPENSE -> {
                    expenseAll += txn.amountMinor
                    if (txn.countInBudget) expenseInBudget += txn.amountMinor
                    byCategory[txn.category] = (byCategory[txn.category] ?: 0L) + txn.amountMinor
                }
                TxnType.REFUND -> if (txn.countInBudget) refund += txn.amountMinor
                TxnType.INCOME -> income += txn.amountMinor
                TxnType.TRANSFER -> transfer += txn.amountMinor
                else -> Unit
            }
        }
        val netSpent = expenseInBudget - refund
        val categoryList = byCategory.entries
            .map { CategorySpend(it.key, it.value, if (expenseAll > 0) it.value.toDouble() / expenseAll else 0.0) }
            .sortedByDescending { it.amountMinor }
        val daily: List<DailyOverview> =
            BudgetEngine.dailyOverviews(transactions, rules, fromLocalDate, toLocalDate, dayIterator)
        return RangeStats(
            fromLocalDate = fromLocalDate,
            toLocalDate = toLocalDate,
            totalExpenseAll = expenseAll,
            totalExpenseInBudget = expenseInBudget,
            refundTotal = refund,
            incomeTotal = income,
            transferTotal = transfer,
            netSpentMinor = netSpent,
            byCategory = categoryList,
            daily = daily,
            overspentDays = daily.count { it.overspent }
        )
    }
}
