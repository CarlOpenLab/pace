package pace.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import pace.shared.datetime.PaceDates
import pace.shared.model.Transaction
import pace.shared.model.TxnType
import pace.shared.money.Money

fun amountLabel(txn: Transaction): String = when (txn.type) {
    TxnType.EXPENSE -> "-" + Money.display(txn.amountMinor, txn.currency)
    TxnType.INCOME -> "+" + Money.display(txn.amountMinor, txn.currency)
    TxnType.REFUND -> "退 " + Money.display(txn.amountMinor, txn.currency)
    TxnType.TRANSFER -> Money.display(txn.amountMinor, txn.currency)
    else -> Money.display(txn.amountMinor, txn.currency)
}

/** 小玻璃徽章 */
@Composable
fun GlassPill(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Bold),
        color = Color(0xFF0D8570),
        modifier = Modifier
            .background(Color.White.copy(alpha = 0.38f), RoundedCornerShape(50))
            .border(1.dp, Color.White.copy(alpha = 0.5f), RoundedCornerShape(50))
            .padding(horizontal = 10.dp, vertical = 4.dp)
    )
}

/** 账单行（账单页使用） */
@Composable
fun TxnRow(txn: Transaction, onOpenTxn: (String) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onOpenTxn(txn.id) }
            .padding(vertical = 12.dp),
        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically
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
                TxnType.REFUND -> Color(0xFF0D8570)
                else -> MaterialTheme.colorScheme.onSurface
            }
        )
    }
}
