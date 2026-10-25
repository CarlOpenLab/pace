package pace.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import pace.app.AppContainer
import pace.shared.datetime.PaceDates
import pace.shared.model.TodayOverview
import pace.shared.model.Transaction
import pace.shared.model.TxnType
import pace.shared.money.Money

/** 首页：玻璃质感今日预算卡 + 今日账单（PLAN §7 页面 1）。 */
@Composable
fun HomeScreen(onAdd: () -> Unit, onOpenTxn: (String) -> Unit) {
    val overview by produceState<TodayOverview?>(initialValue = null, key1 = "home") {
        value = AppContainer.ledger.todayOverview(AppContainer.todayIso())
    }
    val data = overview ?: return

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 18.dp)
    ) {
        Spacer(Modifier.height(8.dp))
        BudgetCard(data)
        Spacer(Modifier.height(16.dp))
        TodayCard(data, onOpenTxn)
        Spacer(Modifier.height(120.dp))
    }
}

@Composable
private fun BudgetCard(data: TodayOverview) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .glassCard(RoundedCornerShape(30.dp))
            .padding(22.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                "今天 · ${data.localDate.drop(5)}",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            GlassPill(
                text = if (!data.hasBudget) "未设预算" else if (data.overspent) "已超支" else "预算中"
            )
        }
        Spacer(Modifier.height(14.dp))

        if (!data.hasBudget) {
            Text("未设置预算", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(4.dp))
            Text(
                "到「设置 → 每日预算」设置额度后开始追踪。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        } else {
            Text(
                if (data.overspent) "今日超支" else "今日剩余",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(Modifier.height(4.dp))
            GradientText(
                text = Money.display(
                    if (data.overspent) -data.remainingMinor else data.remainingMinor,
                    "CNY"
                ).let { if (data.overspent) it.removePrefix("-") else it },
                brush = if (data.overspent) PaceGradients.dangerBrush() else PaceGradients.accent(),
                style = MaterialTheme.typography.displayLarge.copy(
                    fontWeight = FontWeight.Black,
                    fontSize = 52.sp,
                    lineHeight = 58.sp
                )
            )
            if (data.overspent) {
                Text(
                    "超支金额",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.error
                )
            }
            if (data.budgetMinor > 0) {
                Spacer(Modifier.height(14.dp))
                val used = if (data.budgetMinor == 0L) 0f else
                    (data.netSpentMinor.coerceAtLeast(0L).toFloat() / data.budgetMinor.toFloat())
                GlassProgress(
                    ratio = if (data.overspent) 1f else used,
                    danger = data.overspent,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(8.dp))
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(
                        "预算 ${Money.display(data.budgetMinor, "CNY")}",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        "已花 ${Money.display(data.netSpentMinor, "CNY")}",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            Spacer(Modifier.height(8.dp))
            Text(
                "今日剩余 = 预算 − 已花（计入预算的支出 − 退款）",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f)
            )
        }
    }
}

@Composable
private fun TodayCard(data: TodayOverview, onOpenTxn: (String) -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .glassCard(RoundedCornerShape(26.dp))
            .padding(18.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("今日账单", style = MaterialTheme.typography.titleMedium)
            Text(
                "${data.transactions.size} 笔",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Spacer(Modifier.height(6.dp))

        if (data.transactions.isEmpty()) {
            Row(
                modifier = Modifier.padding(vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    modifier = Modifier
                        .size(38.dp)
                        .glassCard(CircleShape),
                    contentAlignment = Alignment.Center
                ) {
                    Text("🌿")
                }
                Spacer(Modifier.padding(4.dp))
                Column {
                    Text("今天还没有账单", style = MaterialTheme.typography.titleSmall)
                    Text(
                        "飞行模式也能完整记账",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        } else {
            data.transactions.forEachIndexed { index, txn ->
                GlassTxnRow(txn, onOpenTxn)
                if (index != data.transactions.lastIndex) {
                    HorizontalDivider(
                        color = Color.White.copy(alpha = if (androidx.compose.foundation.isSystemInDarkTheme()) 0.10f else 0.55f),
                        modifier = Modifier.padding(start = 44.dp)
                    )
                }
            }
        }
    }
}

@Composable
private fun GlassTxnRow(txn: Transaction, onOpenTxn: (String) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onOpenTxn(txn.id) }
            .padding(vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(34.dp)
                .background(
                    Color.White.copy(alpha = 0.32f),
                    CircleShape
                ),
            contentAlignment = Alignment.Center
        ) {
            Text(categoryEmoji(txn.category), style = MaterialTheme.typography.bodySmall)
        }
        Spacer(Modifier.padding(6.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                txn.note.ifBlank { txn.category },
                style = MaterialTheme.typography.titleSmall
            )
            Text(
                buildString {
                    append(txn.category)
                    if (txn.type == TxnType.EXPENSE && !txn.countInBudget) append(" · 不计入预算")
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
        Text(
            amountLabel(txn),
            style = MaterialTheme.typography.titleSmall,
            color = if (txn.type == TxnType.REFUND) Color(0xFF0D8570) else MaterialTheme.colorScheme.onSurface
        )
    }
}

private fun categoryEmoji(category: String): String = when (category) {
    "餐饮" -> "🍜"
    "交通" -> "🚗"
    "购物" -> "🛍"
    "住房" -> "🏠"
    "娱乐" -> "🎬"
    "医疗" -> "💊"
    "教育" -> "📚"
    "人情社交" -> "🎁"
    "工资" -> "💰"
    "理财" -> "📈"
    "转账" -> "🔁"
    else -> "💠"
}
