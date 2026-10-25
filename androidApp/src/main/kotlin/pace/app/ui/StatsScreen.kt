package pace.app.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.LinearProgressIndicator
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
import androidx.compose.ui.unit.dp
import pace.app.AppContainer
import pace.shared.model.RangeStats
import pace.shared.money.Money

private enum class StatsKind(val label: String) { WEEK("本周"), MONTH("本月") }

/** 统计页：周/月汇总、分类排行、每日预算对比（PLAN §7 页面 4）。 */
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

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
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
        Spacer(Modifier.height(12.dp))
        val data = stats
        if (data == null) {
            Text("加载中…")
            return@Column
        }

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(
                    "${data.fromLocalDate} ~ ${data.toLocalDate}",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(4.dp))
                Text(
                    "支出 ${Money.display(data.totalExpenseAll, "CNY")}",
                    style = MaterialTheme.typography.headlineSmall
                )
                Text(
                    "计入预算 ${Money.display(data.totalExpenseInBudget, "CNY")} · 退款冲减 ${Money.display(data.refundTotal, "CNY")}",
                    style = MaterialTheme.typography.bodySmall
                )
                Text(
                    "收入 ${Money.display(data.incomeTotal, "CNY")} · 转账 ${Money.display(data.transferTotal, "CNY")}（不计入支出）",
                    style = MaterialTheme.typography.bodySmall
                )
                if (data.overspentDays > 0) {
                    Text(
                        "超支 ${data.overspentDays} 天",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.error
                    )
                }
            }
        }
        Spacer(Modifier.height(16.dp))

        Text("分类排行", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(8.dp))
        if (data.byCategory.isEmpty()) {
            Text(
                "暂无支出记录。",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            LazyColumn {
                items(data.byCategory, key = { it.category }) { item ->
                    Column(modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(item.category, modifier = Modifier.weight(1f))
                            Text(
                                "${Money.display(item.amountMinor, "CNY")} · ${(item.ratio * 100).toInt()}%",
                                style = MaterialTheme.typography.bodySmall
                            )
                        }
                        LinearProgressIndicator(
                            progress = { item.ratio.toFloat() },
                            modifier = Modifier.fillMaxWidth().padding(top = 4.dp)
                        )
                    }
                }
                item {
                    Spacer(Modifier.height(16.dp))
                    Text("每日预算对比", style = MaterialTheme.typography.titleMedium)
                    Spacer(Modifier.height(8.dp))
                }
                items(data.daily, key = { it.localDate }) { day ->
                    val budgetRatio = if (day.hasBudget && day.budgetMinor > 0) {
                        (day.netSpentMinor.toFloat() / day.budgetMinor.toFloat()).coerceIn(0f, 1f)
                    } else 0f
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(day.localDate.substring(5), style = MaterialTheme.typography.bodySmall)
                        Box(modifier = Modifier.weight(1f).padding(horizontal = 8.dp)) {
                            LinearProgressIndicator(
                                progress = { budgetRatio },
                                modifier = Modifier.fillMaxWidth(),
                                color = if (day.overspent) MaterialTheme.colorScheme.error
                                else MaterialTheme.colorScheme.primary
                            )
                        }
                        Text(
                            if (day.hasBudget) {
                                "${Money.display(day.netSpentMinor, "CNY")} / ${Money.display(day.budgetMinor, "CNY")}"
                            } else {
                                Money.display(day.netSpentMinor, "CNY")
                            },
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                }
            }
        }
    }
}
