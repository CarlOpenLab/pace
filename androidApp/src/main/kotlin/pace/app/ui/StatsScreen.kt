package pace.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import pace.app.AppContainer
import pace.shared.model.RangeStats
import pace.shared.money.Money

private enum class StatsKind(val label: String) { WEEK("本周"), MONTH("本月") }

/** 统计页：玻璃卡片式周/月汇总、分类排行、每日预算对比（PLAN §7 页面 4）。 */
@Composable
fun StatsScreen() {
    var kind by remember { mutableStateOf(StatsKind.WEEK) }

    val stats by produceState<RangeStats?>(initialValue = null, kind) {
        val today = AppContainer.todayIso()
        val range = when (kind) {
            StatsKind.WEEK -> AppContainer.ledger.weekRange(today)
            StatsKind.MONTH -> AppContainer.ledger.monthRange(today)
        }
        value = range?.let { AppContainer.ledger.rangeStats(it.from, it.to) }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 18.dp)
    ) {
        Spacer(Modifier.height(8.dp))
        Row {
            StatsKind.entries.forEach { k ->
                FilterChip(
                    selected = kind == k,
                    onClick = { kind = k },
                    label = { Text(k.label) },
                    modifier = Modifier.padding(end = 8.dp)
                )
            }
        }
        Spacer(Modifier.height(14.dp))
        val data = stats
        if (data == null) {
            Text("加载中…")
            return@Column
        }

        SummaryCard(data)
        Spacer(Modifier.height(16.dp))
        CategoryCard(data)
        Spacer(Modifier.height(16.dp))
        DailyCard(data)
        Spacer(Modifier.height(120.dp))
    }
}

@Composable
private fun SummaryCard(data: RangeStats) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .glassCard(RoundedCornerShape(28.dp))
            .padding(20.dp)
    ) {
        Text(
            "${data.fromLocalDate} ~ ${data.toLocalDate}",
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(6.dp))
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                "支出 ",
                style = MaterialTheme.typography.headlineSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            GradientText(
                text = Money.display(data.totalExpenseAll, "CNY"),
                brush = PaceGradients.accent(),
                style = MaterialTheme.typography.displaySmall.copy(
                    fontWeight = FontWeight.Black,
                    fontSize = 34.sp,
                    lineHeight = 40.sp
                )
            )
        }
        Spacer(Modifier.height(14.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StatChip("计入预算", Money.display(data.totalExpenseInBudget, "CNY"))
            StatChip("退款冲减", Money.display(data.refundTotal, "CNY"))
            StatChip("收入", Money.display(data.incomeTotal, "CNY"))
        }
        Spacer(Modifier.height(10.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StatChip("转账", Money.display(data.transferTotal, "CNY"), note = "不计入支出")
            StatChip(
                "超支",
                "${data.overspentDays} 天",
                danger = data.overspentDays > 0
            )
        }
    }
}

@Composable
private fun StatChip(label: String, value: String, note: String? = null, danger: Boolean = false) {
    Column(
        modifier = Modifier
            .glassCard(RoundedCornerShape(14.dp))
            .padding(horizontal = 10.dp, vertical = 8.dp)
    ) {
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            value,
            style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Bold),
            color = if (danger) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface
        )
        if (note != null) {
            Text(
                note,
                style = MaterialTheme.typography.labelSmall.copy(fontSize = 9.sp),
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
            )
        }
    }
}

@Composable
private fun CategoryCard(data: RangeStats) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .glassCard(RoundedCornerShape(26.dp))
            .padding(20.dp)
    ) {
        Text("分类排行", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(12.dp))
        if (data.byCategory.isEmpty()) {
            Text(
                "暂无支出记录。",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            data.byCategory.forEach { item ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 5.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier
                            .padding(end = 8.dp)
                            .size(8.dp)
                            .background(PaceGradients.accent(), CircleShape)
                    ) {}
                    Text(
                        item.category,
                        style = MaterialTheme.typography.titleSmall,
                        modifier = Modifier.weight(1f)
                    )
                    Text(
                        "${Money.display(item.amountMinor, "CNY")} · ${(item.ratio * 100).toInt()}%",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                GlassProgress(
                    ratio = item.ratio.toFloat(),
                    danger = item.ratio >= 1.0,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(start = 16.dp, bottom = 6.dp)
                )
            }
        }
    }
}

@Composable
private fun DailyCard(data: RangeStats) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .glassCard(RoundedCornerShape(26.dp))
            .padding(20.dp)
    ) {
        Text("每日预算对比", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(10.dp))
        data.daily.forEach { day ->
            val ratio = if (day.hasBudget && day.budgetMinor > 0) {
                day.netSpentMinor.coerceAtLeast(0L).toFloat() / day.budgetMinor.toFloat()
            } else 0f
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    day.localDate.drop(5),
                    style = MaterialTheme.typography.labelSmall,
                    modifier = Modifier.padding(end = 8.dp)
                )
                GlassProgress(
                    ratio = if (day.overspent) 1f else ratio,
                    danger = day.overspent,
                    modifier = Modifier
                        .weight(1f)
                        .padding(horizontal = 6.dp)
                )
                Text(
                    if (day.hasBudget) {
                        "${Money.display(day.netSpentMinor, "CNY")} / ${Money.display(day.budgetMinor, "CNY")}"
                    } else {
                        Money.display(day.netSpentMinor, "CNY")
                    },
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}
