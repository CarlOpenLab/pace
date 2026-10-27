package pace.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import pace.app.AppContainer
import pace.shared.datetime.PaceDates
import pace.shared.model.ErrorCodes
import pace.shared.model.SaveTxnInput
import pace.shared.model.SaveResult
import pace.shared.model.Transaction
import pace.shared.model.TxnType

private val typeOptions = listOf(
    TxnType.EXPENSE to "支出",
    TxnType.INCOME to "收入",
    TxnType.TRANSFER to "转账",
    TxnType.REFUND to "退款"
)

/** 记账页：金额、类型、分类、日期、备注、预算归属（PLAN §7 页面 2）。txnId 非空为编辑。 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AddScreen(txnId: String?, onDone: () -> Unit) {
    // remember(txnId)：编辑态只在打开时查一次库，不跟着每次重组（每个按键）重查
    val editing: Transaction? = remember(txnId) { txnId?.let { AppContainer.ledger.transaction(it) } }
    var type by remember { mutableStateOf(editing?.type ?: TxnType.EXPENSE) }
    var amountText by remember { mutableStateOf(editing?.let { pace.shared.money.Money.formatMinor(it.amountMinor) } ?: "") }
    var category by remember { mutableStateOf(editing?.category ?: "餐饮") }
    var localDate by remember { mutableStateOf(editing?.localDate ?: AppContainer.todayIso()) }
    var note by remember { mutableStateOf(editing?.note ?: "") }
    var account by remember { mutableStateOf(editing?.account ?: "现金") }
    var countInBudget by remember { mutableStateOf(editing?.countInBudget ?: true) }
    var refundOfId by remember { mutableStateOf<String?>(editing?.refundOfId) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirmDuplicate by remember { mutableStateOf(false) }

    val categories = remember { AppContainer.ledger.categories() }
    val expensesForRefund = remember {
        AppContainer.ledger.allTransactions().filter { it.type == TxnType.EXPENSE }
    }

    // 手动保存与「仍然保存」共用同一份输入构造，forceSave 是唯一差别
    fun buildSaveInput(forceSave: Boolean = false) = SaveTxnInput(
        id = editing?.id,
        type = type,
        amountText = amountText,
        currency = "CNY",
        category = category,
        account = account,
        note = note,
        occurredAtEpochMillis = editing?.occurredAtEpochMillis ?: 0L,
        localDate = localDate,
        timezoneId = AppContainer.timezoneId,
        countInBudget = countInBudget,
        refundOfId = refundOfId,
        forceSave = forceSave
    )

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp)
    ) {
        Text(
            if (editing == null) "记一笔" else "编辑账单",
            style = MaterialTheme.typography.headlineSmall
        )
        Spacer(Modifier.height(16.dp))

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            typeOptions.forEach { (value, label) ->
                FilterChip(
                    selected = type == value,
                    onClick = {
                        type = value
                        if (value == TxnType.INCOME) category = "工资"
                        if (value == TxnType.TRANSFER) category = "转账"
                    },
                    label = { Text(label) }
                )
            }
        }
        Spacer(Modifier.height(12.dp))

        OutlinedTextField(
            value = amountText,
            onValueChange = { amountText = it },
            label = { Text("金额（元）") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(Modifier.height(12.dp))

        Text("分类", style = MaterialTheme.typography.labelLarge)
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.padding(vertical = 8.dp)
        ) {
            categories
                .sortedWith(compareByDescending<pace.shared.model.Category> { it.usageCount }.thenBy { it.sortOrder })
                .forEach { c ->
                    FilterChip(
                        selected = category == c.name,
                        onClick = { category = c.name },
                        label = { Text(c.name) }
                    )
                }
        }

        OutlinedTextField(
            value = localDate,
            onValueChange = { localDate = it },
            label = { Text("归属日期（yyyy-MM-dd）") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(Modifier.height(12.dp))

        OutlinedTextField(
            value = account,
            onValueChange = { account = it },
            label = { Text("账户/支付方式") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(Modifier.height(12.dp))

        OutlinedTextField(
            value = note,
            onValueChange = { text ->
                note = text
                if (type == TxnType.EXPENSE) {
                    category = AppContainer.ledger.suggestCategory(text.ifBlank { amountText }, type)
                }
            },
            label = { Text("备注（输入内容会实时给出本地分类建议）") },
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(Modifier.height(12.dp))

        if (type == TxnType.EXPENSE || type == TxnType.REFUND) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text("计入每日预算")
                    Text(
                        "关闭后仍计入总支出统计",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Switch(checked = countInBudget, onCheckedChange = { countInBudget = it })
            }
            Spacer(Modifier.height(12.dp))
        }

        if (type == TxnType.REFUND) {
            Text("退款关联原账单", style = MaterialTheme.typography.labelLarge)
            if (expensesForRefund.isEmpty()) {
                Text(
                    "还没有可关联的支出账单",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error
                )
            } else {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.padding(vertical = 8.dp)
                ) {
                    expensesForRefund.take(10).forEach { candidate ->
                        FilterChip(
                            selected = refundOfId == candidate.id,
                            onClick = { refundOfId = candidate.id },
                            label = {
                                Text(
                                    "${candidate.localDate} ${pace.shared.money.Money.display(candidate.amountMinor, candidate.currency)} ${candidate.note.ifBlank { candidate.category }}"
                                )
                            }
                        )
                    }
                }
            }
        }

        error?.let {
            Spacer(Modifier.height(8.dp))
            Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
        }

        Spacer(Modifier.height(16.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Button(
                onClick = {
                    val result: SaveResult = AppContainer.ledger.saveTransaction(buildSaveInput())
                    if (result.isSuccess) {
                        onDone()
                    } else if (result.errorCode == ErrorCodes.DUPLICATE_FINGERPRINT) {
                        confirmDuplicate = true
                    } else {
                        error = describeError(result.errorCode)
                    }
                },
                modifier = Modifier.weight(1f)
            ) { Text("保存") }
            TextButton(onClick = onDone, modifier = Modifier.weight(1f)) { Text("取消") }
        }
        Spacer(Modifier.height(32.dp))
    }

    if (confirmDuplicate) {
        AlertDialog(
            onDismissRequest = { confirmDuplicate = false },
            title = { Text("已存在相同账单") },
            text = { Text("同一天、同金额、同备注的账单已存在。仍然保存这一笔吗？") },
            confirmButton = {
                TextButton(onClick = {
                    confirmDuplicate = false
                    val retry = AppContainer.ledger.saveTransaction(buildSaveInput(forceSave = true))
                    if (retry.isSuccess) onDone() else error = describeError(retry.errorCode)
                }) { Text("仍然保存") }
            },
            dismissButton = {
                TextButton(onClick = { confirmDuplicate = false }) { Text("取消") }
            }
        )
    }
}

fun describeError(code: String?): String = when (code) {
    ErrorCodes.INVALID_AMOUNT -> "金额无效：需为大于 0 的数，最多两位小数"
    ErrorCodes.INVALID_TYPE -> "账单类型无效"
    ErrorCodes.INVALID_CATEGORY -> "请选择有效分类"
    ErrorCodes.INVALID_DATE -> "日期无效（yyyy-MM-dd，1970-2100）"
    ErrorCodes.INVALID_TIMEZONE -> "时区信息无效"
    ErrorCodes.REFUND_MISSING_ORIGINAL -> "退款必须关联一笔原支出"
    ErrorCodes.REFUND_ORIGINAL_NOT_FOUND -> "关联的原账单不存在或不是支出"
    ErrorCodes.NOTE_TOO_LONG -> "备注最长 500 字"
    ErrorCodes.DUPLICATE_FINGERPRINT -> "存在相同账单"
    ErrorCodes.NOT_FOUND -> "账单不存在，可能已被删除"
    else -> "保存失败（$code）"
}
