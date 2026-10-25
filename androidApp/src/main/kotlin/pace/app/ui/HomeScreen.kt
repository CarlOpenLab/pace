package pace.app.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import pace.app.AppContainer
import pace.shared.datetime.PaceDates
import pace.shared.model.TodayOverview
import pace.shared.model.Transaction
import pace.shared.model.TxnType
import pace.shared.money.Money

/** 首页：今日剩余/超支、预算、已花、今日账单（PLAN §7 页面 1）。 */
@Composable
fun HomeScreen(onAdd: () -> Unit, onOpenTxn: (String) -> Unit) {
    val overview by produceState<TodayOverview?>(initialValue = null, key1 = "home") {
        value = AppContainer.ledger.todayOverview(AppContainer.todayIso())
    }

    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        val data = overview
        if (data == null) {
            Text("加载中…")
            return@Column
        }
        BudgetCard(data)
        Spacer(Modifier.height(16.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("今日账单", style = MaterialTheme.typography.titleMedium)
            Button(onClick = onAdd) { Text("记一笔") }
        }
        Spacer(Modifier.height(8.dp))
        if (data.transactions.isEmpty()) {
            Text(
                "今天还没有账单。飞行模式也能完整记账。",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            LazyColumn {
                items(data.transactions, key = { it.id }) { txn ->
                    TxnRow(txn, onOpenTxn)
                    HorizontalDivider()
                }
            }
        }
    }
}

@Composable
private fun BudgetCard(data: TodayOverview) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(20.dp)) {
            if (!data.hasBudget) {
                Text("今日剩余", style = MaterialTheme.typography.labelLarge)
                Spacer(Modifier.height(4.dp))
                Text("未设置预算", style = MaterialTheme.typography.headlineMedium)
                Spacer(Modifier.height(4.dp))
                Text(
                    "到「设置 → 每日预算」设置额度后开始追踪。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else if (data.overspent) {
                Text("今日超支", style = MaterialTheme.typography.labelLarge)
                Spacer(Modifier.height(4.dp))
                Text(
                    Money.display(-data.remainingMinor, "CNY"),
                    style = MaterialTheme.typography.headlineLarge,
                    color = MaterialTheme.colorScheme.error
                )
            } else {
                Text("今日剩余", style = MaterialTheme.typography.labelLarge)
                Spacer(Modifier.height(4.dp))
                Text(
                    Money.display(data.remainingMinor, "CNY"),
                    style = MaterialTheme.typography.headlineLarge,
                    color = MaterialTheme.colorScheme.primary
                )
            }
            Spacer(Modifier.height(8.dp))
            Text(
                "预算 ${Money.display(data.budgetMinor, "CNY")} · 已花 ${Money.display(data.netSpentMinor, "CNY")}",
                style = MaterialTheme.typography.bodyMedium
            )
            if (data.hasBudget) {
                Text(
                    "今日剩余 = 预算 − 已花（计入预算的支出 − 退款）",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
fun TxnRow(txn: Transaction, onOpenTxn: (String) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onOpenTxn(txn.id) }
            .padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                txn.note.ifBlank { txn.category },
                style = MaterialTheme.typography.bodyLarge
            )
            Text(
                "${txn.category} · ${PaceDates.timeOfDay(txn.occurredAtEpochMillis, txn.timezoneId)}" +
                    if (!txn.countInBudget && txn.type == TxnType.EXPENSE) " · 不计入预算" else "",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Text(
            amountLabel(txn),
            style = MaterialTheme.typography.bodyLarge,
            color = when (txn.type) {
                TxnType.EXPENSE -> MaterialTheme.colorScheme.onSurface
                TxnType.REFUND -> MaterialTheme.colorScheme.primary
                else -> MaterialTheme.colorScheme.onSurfaceVariant
            }
        )
    }
}

fun amountLabel(txn: Transaction): String = when (txn.type) {
    TxnType.EXPENSE -> "-" + Money.display(txn.amountMinor, txn.currency)
    TxnType.INCOME -> "+" + Money.display(txn.amountMinor, txn.currency)
    TxnType.REFUND -> "退 " + Money.display(txn.amountMinor, txn.currency)
    TxnType.TRANSFER -> Money.display(txn.amountMinor, txn.currency)
    else -> Money.display(txn.amountMinor, txn.currency)
}
