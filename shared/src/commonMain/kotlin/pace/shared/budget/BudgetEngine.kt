package pace.shared.budget

import pace.shared.model.BudgetRule
import pace.shared.model.DailyOverview
import pace.shared.model.TodayOverview
import pace.shared.model.Transaction
import pace.shared.model.TxnType

/**
 * 固定每日预算引擎（docs/BUDGET_RULES.md）。
 * 纯函数实现：同一输入在任何平台输出一致。
 */
object BudgetEngine {

    /** 某日生效的预算规则：effectiveFrom <= date 的最新一条；同日取 createdAt 最新（B7）。 */
    fun budgetFor(rules: List<BudgetRule>, localDate: String): BudgetRule? =
        rules
            .filter { it.effectiveFromLocalDate <= localDate }
            .sortedWith(
                compareByDescending<BudgetRule> { it.effectiveFromLocalDate }
                    .thenByDescending { it.createdAtEpochMillis }
            )
            .firstOrNull()

    /** 当日计入预算的净支出 = Σ计入支出 − Σ计入退款（B2/B9/B10）。 */
    fun netSpend(transactions: List<Transaction>, localDate: String): Long {
        var net = 0L
        for (txn in transactions) {
            if (txn.localDate != localDate || !txn.countInBudget) continue
            when (txn.type) {
                TxnType.EXPENSE -> net += txn.amountMinor
                TxnType.REFUND -> net -= txn.amountMinor
                else -> Unit
            }
        }
        return net
    }

    /** 当日全部支出：所有 EXPENSE，不论 countInBudget，不减退款（B3）。 */
    fun totalSpend(transactions: List<Transaction>, localDate: String): Long =
        transactions.filter { it.localDate == localDate && it.type == TxnType.EXPENSE }
            .sumOf { it.amountMinor }

    fun isOverspent(budgetMinor: Long, netSpentMinor: Long): Boolean =
        budgetMinor > 0 && netSpentMinor > budgetMinor

    fun dailyOverview(
        transactions: List<Transaction>,
        rules: List<BudgetRule>,
        localDate: String
    ): DailyOverview {
        val rule = budgetFor(rules, localDate)
        val budget = rule?.dailyAmountMinor ?: 0L
        val net = netSpend(transactions, localDate)
        val total = totalSpend(transactions, localDate)
        return DailyOverview(
            localDate = localDate,
            hasBudget = rule != null,
            budgetMinor = budget,
            netSpentMinor = net,
            totalSpentMinor = total,
            remainingMinor = budget - net,
            overspent = isOverspent(budget, net)
        )
    }

    fun todayOverview(
        transactions: List<Transaction>,
        rules: List<BudgetRule>,
        todayIso: String
    ): TodayOverview {
        val overview = dailyOverview(transactions, rules, todayIso)
        return TodayOverview(
            localDate = overview.localDate,
            hasBudget = overview.hasBudget,
            budgetMinor = overview.budgetMinor,
            netSpentMinor = overview.netSpentMinor,
            totalSpentMinor = overview.totalSpentMinor,
            remainingMinor = overview.remainingMinor,
            overspent = overview.overspent,
            transactions = transactions.filter { it.localDate == todayIso }
                .sortedWith(compareByDescending<Transaction> { it.occurredAtEpochMillis }.thenByDescending { it.id })
        )
    }

    /**
     * 区间逐日预算对比。区间天数超过 400 时拒绝（防止误传超大范围）。
     */
    fun dailyOverviews(
        transactions: List<Transaction>,
        rules: List<BudgetRule>,
        fromLocalDate: String,
        toLocalDate: String,
        dayIterator: (String) -> String?
    ): List<DailyOverview> {
        if (fromLocalDate > toLocalDate) return emptyList()
        val result = mutableListOf<DailyOverview>()
        var cursor = fromLocalDate
        var guard = 0
        while (cursor <= toLocalDate && guard < 400) {
            result += dailyOverview(transactions, rules, cursor)
            cursor = dayIterator(cursor) ?: break
            guard += 1
        }
        return result
    }
}
