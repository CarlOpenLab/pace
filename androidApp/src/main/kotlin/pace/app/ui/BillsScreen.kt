package pace.app.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import pace.app.AppContainer
import pace.shared.model.Transaction
import pace.shared.statistics.StatsEngine

private enum class RangeKind(val label: String) {
    WEEK("本周"), MONTH("本月"), ALL("全部")
}

/** 账单页：按日期浏览、搜索、编辑、删除与撤销（PLAN §7 页面 3）。 */
@Composable
fun BillsScreen(onOpenTxn: (String) -> Unit, onAdd: () -> Unit) {
    var keyword by remember { mutableStateOf("") }
    var range by remember { mutableStateOf(RangeKind.WEEK) }
    var refresh by remember { mutableStateOf(0) }
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    val txns by produceState<List<Transaction>>(initialValue = emptyList(), keyword, range, refresh) {
        val today = AppContainer.todayIso()
        value = AppContainer.withLedger { ledger ->
            when (range) {
                RangeKind.WEEK -> {
                    val week = ledger.weekRange(today)
                    if (week != null) {
                        if (keyword.isBlank()) ledger.transactions(week.from, week.to)
                        else ledger.searchTransactions(keyword)
                    } else emptyList()
                }
                RangeKind.MONTH -> {
                    val month = ledger.monthRange(today)
                    if (month != null) {
                        if (keyword.isBlank()) ledger.transactions(month.from, month.to)
                        else ledger.searchTransactions(keyword)
                    } else emptyList()
                }
                RangeKind.ALL -> if (keyword.isBlank()) {
                    ledger.allTransactions()
                } else {
                    ledger.searchTransactions(keyword)
                }
            }
        }
    }

    // Box 包一层把 Snackbar 钉在底部：直接放在 NavHost 的容器里会顶到左上角
    androidx.compose.foundation.layout.Box(modifier = Modifier.fillMaxSize()) {
        Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        OutlinedTextField(
            value = keyword,
            onValueChange = { keyword = it },
            label = { Text("搜索备注/分类/账户") },
            leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(Modifier.height(8.dp))
        Row {
            RangeKind.entries.forEach { kind ->
                FilterChip(
                    selected = range == kind,
                    onClick = { range = kind },
                    label = { Text(kind.label) },
                    modifier = Modifier.padding(end = 8.dp)
                )
            }
        }
        Spacer(Modifier.height(8.dp))
        if (txns.isEmpty()) {
            Text(
                "该范围内没有账单。",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            TextButton(onClick = onAdd) { Text("记一笔") }
        } else {
            LazyColumn {
                val grouped = txns.groupBy { it.localDate }.toSortedMap(compareByDescending { it })
                grouped.forEach { (date, dayTxns) ->
                    item(key = "header-$date") {
                        Text(
                            date,
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.padding(top = 12.dp, bottom = 4.dp)
                        )
                    }
                    items(dayTxns, key = { it.id }) { txn ->
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Column(
                                modifier = Modifier
                                    .weight(1f)
                                    .padding(vertical = 4.dp)
                            ) { TxnRow(txn, onOpenTxn) }
                            IconButton(onClick = {
                                scope.launch {
                                    val deleted = AppContainer.withLedger { it.deleteTransaction(txn.id) }
                                    if (deleted != null) {
                                        refresh += 1
                                        val result = snackbarHostState.showSnackbar(
                                            message = "已删除「${deleted.note.ifBlank { deleted.category }}」",
                                            actionLabel = "撤销",
                                            withDismissAction = true
                                        )
                                        if (result == androidx.compose.material3.SnackbarResult.ActionPerformed) {
                                            // 撤销 = 用原数据重新入账（U3）
                                            AppContainer.withLedger {
                                                it.saveTransaction(
                                                    pace.shared.model.SaveTxnInput(
                                                        id = deleted.id,
                                                        type = deleted.type,
                                                        amountText = pace.shared.money.Money.formatMinor(deleted.amountMinor),
                                                        currency = deleted.currency,
                                                        category = deleted.category,
                                                        account = deleted.account,
                                                        note = deleted.note,
                                                        occurredAtEpochMillis = deleted.occurredAtEpochMillis,
                                                        localDate = deleted.localDate,
                                                        timezoneId = deleted.timezoneId,
                                                        countInBudget = deleted.countInBudget,
                                                        refundOfId = deleted.refundOfId,
                                                        forceSave = true
                                                    )
                                                )
                                            }
                                            refresh += 1
                                        }
                                    }
                                }
                            }) {
                                Icon(
                                    Icons.Filled.Delete,
                                    contentDescription = "删除",
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }
                }
            }
        }
        }
        SnackbarHost(
            hostState = snackbarHostState,
            modifier = Modifier
                .align(androidx.compose.ui.Alignment.BottomCenter)
                .padding(16.dp)
        )
    }
}
