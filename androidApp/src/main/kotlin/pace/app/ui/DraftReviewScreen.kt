package pace.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import pace.app.AppContainer
import pace.app.ai.DraftItem
import pace.app.ai.DraftMissing
import pace.app.ai.DraftSaver
import pace.app.ai.PaceCopy
import pace.app.ai.updateAmount
import pace.shared.money.Money
import java.time.LocalDate

/** 「切到手动」带回记一笔页的预填值（退款/转账要指定账户或原账单，盲选就是错账）。 */
data class ManualPrefill(
    val amountText: String,
    val localDate: String,
    val note: String
) : java.io.Serializable

/**
 * 草稿确认页：拆出来的每一笔都要用户看过、补齐、确认，才写进账本
 * （docs/DESIGN-quickadd-primary.md §6，iOS DraftReviewView 同一套语义）。
 * DraftItem 字段可变但不可观察：每次改动后 bump revision 触发重画。
 */
@Composable
fun DraftReviewScreen(
    initialDrafts: List<DraftItem>,
    onDone: () -> Unit,
    onBack: () -> Unit,
    onSwitchManual: (ManualPrefill) -> Unit
) {
    var drafts by remember { mutableStateOf(initialDrafts) }
    val categories = remember { AppContainer.ledger.categories().map { it.name } }
    var editingId by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }
    var toast by remember { mutableStateOf<String?>(null) }
    var duplicateNotice by remember { mutableStateOf(false) }
    var failureBody by remember { mutableStateOf<String?>(null) }
    /** 保存后要留在这页上的重复笔；null = 没有这步。1.4 秒后要么走人、要么留重复问用户。 */
    var pendingDuplicates by remember { mutableStateOf<List<DraftItem>?>(null) }

    // DraftItem 字段可变但不可观察：改动后换一份列表触发重画
    fun mutate() {
        drafts = drafts.toList()
    }

    val missingCount = drafts.count { it.missingFields.isNotEmpty() }
    val readyCount = drafts.size - missingCount

    fun supplementField(): String? {
        val kinds = drafts.flatMap { it.missingFields }.toSet()
        if (kinds.size != 1) return null
        return when (kinds.first()) {
            DraftMissing.AMOUNT -> PaceCopy.Draft.Field.amount
            DraftMissing.DATE -> PaceCopy.Draft.Field.date
            DraftMissing.CATEGORY -> PaceCopy.Draft.Field.category
            else -> null
        }
    }

    fun saveAll() {
        if (saving || missingCount > 0 || drafts.isEmpty()) return
        saving = true
        failureBody = null
        val outcome = DraftSaver.save(drafts)

        if (outcome.failed.isNotEmpty()) {
            saving = false
            val kept = outcome.failed + outcome.duplicated
            drafts = kept
            failureBody = if (outcome.saved > 0) {
                PaceCopy.Failed.DraftSave.partial(outcome.saved, outcome.failed.size)
            } else if (kept.size == 1) PaceCopy.Failed.DraftSave.bodyOne else PaceCopy.Failed.DraftSave.bodyMany
            if (outcome.duplicated.isNotEmpty()) duplicateNotice = true
            return
        }

        if (outcome.saved == 0 && outcome.duplicated.isNotEmpty()) {
            saving = false
            toast = PaceCopy.Save.allDuplicates(outcome.duplicated.size)
            duplicateNotice = true
            return
        }

        toast = if (outcome.duplicated.isEmpty()) {
            PaceCopy.Save.saved(outcome.saved)
        } else {
            PaceCopy.Save.savedSomeDuplicates(outcome.saved, outcome.duplicated.size)
        }
        pendingDuplicates = outcome.duplicated
    }

    // 保存结果收尾：有重复的留在页上问，没有的 1.4 秒后关页（iOS 同节奏）
    LaunchedEffect(pendingDuplicates) {
        val duplicates = pendingDuplicates ?: return@LaunchedEffect
        delay(1400)
        pendingDuplicates = null
        if (duplicates.isEmpty()) {
            onDone()
        } else {
            drafts = duplicates
            saving = false
            toast = null
            duplicateNotice = true
        }
    }

    fun saveDuplicatesAnyway() {
        val outcome = DraftSaver.save(drafts, force = true)
        if (outcome.failed.isNotEmpty()) {
            drafts = outcome.failed
            mutate()
            failureBody = if (outcome.saved > 0) {
                PaceCopy.Failed.DraftSave.partial(outcome.saved, outcome.failed.size)
            } else if (outcome.failed.size == 1) PaceCopy.Failed.DraftSave.bodyOne else PaceCopy.Failed.DraftSave.bodyMany
            return
        }
        failureBody = null
        toast = PaceCopy.Save.saved(outcome.saved)
        pendingDuplicates = emptyList()
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 18.dp)
                .padding(top = 4.dp, bottom = 120.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onBack) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                }
                Text(
                    PaceCopy.Draft.title(drafts.size),
                    style = MaterialTheme.typography.titleMedium
                )
            }
            if (drafts.isNotEmpty()) {
                Row(modifier = Modifier.fillMaxWidth()) {
                    Text(
                        PaceCopy.Draft.headerLeft,
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.SemiBold
                    )
                    Spacer(Modifier.weight(1f))
                    Text(
                        PaceCopy.Draft.headerRight,
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                if (missingCount > 0) {
                    Spacer(Modifier.height(4.dp))
                    Text(
                        PaceCopy.Draft.needsSupplementNote(missingCount, supplementField()),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Spacer(Modifier.height(12.dp))
            }

            if (drafts.isEmpty()) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .glassCard(RoundedCornerShape(18.dp))
                        .padding(16.dp)
                ) {
                    Text(PaceCopy.Draft.emptyTitle, style = MaterialTheme.typography.titleSmall)
                    Text(
                        PaceCopy.Draft.emptySubtitle,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            } else {
                drafts.forEach { draft ->
                    DraftCard(
                        draft = draft,
                        editing = editingId == draft.id,
                        categories = categories,
                        onEdit = { editingId = draft.id; mutate() },
                        onEditDone = { editingId = null; mutate() },
                        onDelete = {
                            drafts = drafts.filterNot { it.id == draft.id }
                        },
                        onMutate = { mutate() },
                        onSwitchManual = {
                            onSwitchManual(
                                ManualPrefill(
                                    amountText = if (draft.amountMinor > 0) Money.formatMinor(draft.amountMinor) else "",
                                    localDate = draft.localDate,
                                    note = draft.note
                                )
                            )
                        }
                    )
                    Spacer(Modifier.height(12.dp))
                }
            }

            failureBody?.let { body ->
                Spacer(Modifier.height(4.dp))
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .glassCard(RoundedCornerShape(18.dp))
                        .padding(16.dp)
                ) {
                    Text(PaceCopy.Failed.DraftSave.title, style = MaterialTheme.typography.titleSmall)
                    Text(
                        body,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(Modifier.height(8.dp))
                    TextButton(onClick = { saveAll() }) { Text(PaceCopy.Failed.retry) }
                }
            }

            if (drafts.isNotEmpty()) {
                Spacer(Modifier.height(4.dp))
                Text(
                    PaceCopy.Draft.footer,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        // 底部保存胶囊：一句话模式下保存的唯一入口在草稿卡上；这一页的保存就是这颗
        if (drafts.isNotEmpty()) {
            val enabled = missingCount == 0 && !saving
            Surface(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(16.dp),
                shape = RoundedCornerShape(50),
                color = Color.Transparent,
                shadowElevation = 10.dp
            ) {
                Button(
                    onClick = { saveAll() },
                    enabled = enabled,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = Color.Transparent,
                        contentColor = Color.White,
                        disabledContainerColor = Color.Transparent,
                        disabledContentColor = MaterialTheme.colorScheme.onSurfaceVariant
                    ),
                    modifier = Modifier.background(
                        if (enabled) PaceGradients.accent()
                        else androidx.compose.ui.graphics.Brush.linearGradient(
                            listOf(
                                if (isSystemInDarkTheme()) Color(0xFF223330) else Color(0xFFD8DDD9),
                                if (isSystemInDarkTheme()) Color(0xFF223330) else Color(0xFFD8DDD9)
                            )
                        ),
                        RoundedCornerShape(50)
                    )
                ) {
                    if (saving) {
                        CircularProgressIndicator(
                            modifier = Modifier.height(18.dp),
                            strokeWidth = 2.dp,
                            color = Color.White
                        )
                        Spacer(Modifier.padding(4.dp))
                    }
                    Text(
                        if (missingCount > 0) {
                            PaceCopy.Draft.fillRequiredButton(supplementField())
                        } else {
                            PaceCopy.Draft.saveButton(readyCount)
                        },
                        fontWeight = FontWeight.Bold
                    )
                }
            }
        }

        toast?.let { message ->
            Surface(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 8.dp),
                shape = RoundedCornerShape(50),
                color = MaterialTheme.colorScheme.surfaceVariant,
                shadowElevation = 6.dp
            ) {
                Text(
                    message,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
                    style = MaterialTheme.typography.labelLarge
                )
            }
        }
    }

    if (duplicateNotice) {
        AlertDialog(
            onDismissRequest = { duplicateNotice = false },
            title = { Text(PaceCopy.Save.duplicateTitle) },
            text = { Text(PaceCopy.Save.duplicateBody) },
            confirmButton = {
                TextButton(onClick = {
                    duplicateNotice = false
                    saveDuplicatesAnyway()
                }) { Text(PaceCopy.Save.duplicatePrimary) }
            },
            dismissButton = {
                TextButton(onClick = { duplicateNotice = false }) { Text(PaceCopy.Save.duplicateCancel) }
            }
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DraftCard(
    draft: DraftItem,
    editing: Boolean,
    categories: List<String>,
    onEdit: () -> Unit,
    onEditDone: () -> Unit,
    onDelete: () -> Unit,
    onMutate: () -> Unit,
    onSwitchManual: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .glassCard(RoundedCornerShape(18.dp))
            .padding(16.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    draft.note.ifBlank { draft.category },
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    metaLine(draft),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Spacer(Modifier.padding(4.dp))
            Text(
                if (draft.amountMinor > 0) Money.display(draft.amountMinor, draft.currency)
                else PaceCopy.Draft.emptyAmount,
                style = MaterialTheme.typography.titleSmall.copy(fontSize = 16.sp),
                fontWeight = FontWeight.SemiBold,
                color = if (draft.amountMinor > 0) MaterialTheme.colorScheme.onSurface
                else MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // 类型胶囊：菜单里只有支出、收入——转账和退款要指定账户或原账单，
            // 盲选出来就是一笔没关联的错账。想记这两种的人从最后一行出口走。
            TypeCapsule(draft, onTypeChange = { onTypeChanged(draft, it, onMutate) }, onSwitchManual = onSwitchManual)
            Spacer(Modifier.weight(1f))
            val marker = missingMarker(draft.missingFields)
            if (marker != null) {
                Text(
                    marker,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier
                        .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(50))
                        .padding(horizontal = 8.dp, vertical = 3.dp)
                )
            }
        }

        if (draft.amountMinor <= 0) {
            Spacer(Modifier.height(4.dp))
            Text(
                PaceCopy.Draft.noAmountHint,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        Spacer(Modifier.height(10.dp))
        if (editing) {
            DraftEditor(draft, categories, onMutate, onEditDone)
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = onEdit) { Text(PaceCopy.Ai.Input.editInline) }
                TextButton(onClick = onDelete) {
                    Text(PaceCopy.Draft.deleteAction, color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }
}

private fun onTypeChanged(draft: DraftItem, value: String, mutate: () -> Unit) {
    draft.type = value
    draft.missingFields = draft.missingFields - DraftMissing.TYPE
    draft.countInBudget = value == pace.shared.model.TxnType.EXPENSE
    mutate()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TypeCapsule(draft: DraftItem, onTypeChange: (String) -> Unit, onSwitchManual: () -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    val missingType = DraftMissing.TYPE in draft.missingFields
    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it }
    ) {
        Text(
            if (missingType) PaceCopy.Draft.Missing.typeCapsule else typeLabel(draft.type),
            style = MaterialTheme.typography.labelSmall,
            color = if (missingType) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier
                .menuAnchor()
                .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(50))
                .padding(horizontal = 8.dp, vertical = 3.dp)
        )
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false }
        ) {
            DropdownMenuItem(
                text = { Text(typeLabel(pace.shared.model.TxnType.EXPENSE)) },
                onClick = { expanded = false; onTypeChange(pace.shared.model.TxnType.EXPENSE) }
            )
            DropdownMenuItem(
                text = { Text(typeLabel(pace.shared.model.TxnType.INCOME)) },
                onClick = { expanded = false; onTypeChange(pace.shared.model.TxnType.INCOME) }
            )
            DropdownMenuItem(
                text = { Text(PaceCopy.Draft.toManual) },
                onClick = { expanded = false; onSwitchManual() }
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DraftEditor(
    draft: DraftItem,
    categories: List<String>,
    onMutate: () -> Unit,
    onDone: () -> Unit
) {
    var amount by remember { mutableStateOf(draft.amountText) }
    var categoryExpanded by remember { mutableStateOf(false) }
    Column {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                PaceCopy.Draft.Field.amount,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(Modifier.padding(4.dp))
            OutlinedTextField(
                value = amount,
                onValueChange = {
                    amount = it
                    draft.updateAmount(it)
                    onMutate()
                },
                placeholder = { Text("0.00") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                singleLine = true,
                modifier = Modifier.weight(1f)
            )
        }
        Spacer(Modifier.height(6.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                PaceCopy.Draft.Field.category,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(Modifier.padding(4.dp))
            ExposedDropdownMenuBox(
                expanded = categoryExpanded,
                onExpandedChange = { categoryExpanded = it }
            ) {
                Text(
                    draft.category,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier
                        .menuAnchor()
                        .background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(50))
                        .padding(horizontal = 10.dp, vertical = 4.dp)
                )
                ExposedDropdownMenu(
                    expanded = categoryExpanded,
                    onDismissRequest = { categoryExpanded = false }
                ) {
                    categories.forEach { name ->
                        DropdownMenuItem(
                            text = { Text(name) },
                            onClick = {
                                draft.category = name
                                draft.missingFields = draft.missingFields - DraftMissing.CATEGORY
                                onMutate()
                                categoryExpanded = false
                            }
                        )
                    }
                }
            }
        }
        Spacer(Modifier.height(6.dp))
        OutlinedTextField(
            value = draft.note,
            onValueChange = {
                draft.note = it
                onMutate()
            },
            placeholder = { Text(PaceCopy.Draft.Field.note) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )
        Spacer(Modifier.height(8.dp))
        FilterChip(
            selected = true,
            onClick = onDone,
            label = { Text(PaceCopy.Draft.editorDone) }
        )
    }
}

private fun metaLine(draft: DraftItem): String {
    val parts = mutableListOf(draft.category)
    if (draft.localDate.isNotEmpty()) {
        val dateDisplay = if (draft.dateText.isEmpty()) displayDate(draft.localDate)
        else "${draft.dateText} ${displayDate(draft.localDate)}"
        parts += dateDisplay
    }
    if (draft.account.isNotEmpty()) parts += draft.account
    return parts.joinToString(" · ")
}

/** 卡片上的日期：10月20日，机器格式不进界面。 */
fun displayDate(iso: String): String {
    val date = runCatching { LocalDate.parse(iso) }.getOrNull() ?: return iso
    return "${date.monthValue}月${date.dayOfMonth}日"
}

private fun typeLabel(type: String): String = when (type) {
    pace.shared.model.TxnType.EXPENSE -> "支出"
    pace.shared.model.TxnType.INCOME -> "收入"
    pace.shared.model.TxnType.TRANSFER -> "转账"
    pace.shared.model.TxnType.REFUND -> "退款"
    else -> type
}

private fun missingMarker(fields: List<String>): String? {
    if (fields.isEmpty()) return null
    // 缺的只有类型/金额时不挂状态标：胶囊和「还没填」已经在说同一件事
    if (fields.size == 1 && fields.first() == DraftMissing.TYPE) return null
    if (fields.size == 1 && fields.first() == DraftMissing.AMOUNT) return null
    if (fields.size > 1) return PaceCopy.Draft.statusNeedsSupplement
    return when (fields.first()) {
        DraftMissing.AMOUNT -> PaceCopy.Draft.Missing.amount
        DraftMissing.DATE -> PaceCopy.Draft.Missing.date
        DraftMissing.TYPE -> PaceCopy.Draft.Missing.type
        DraftMissing.CATEGORY -> PaceCopy.Draft.Missing.category
        else -> PaceCopy.Draft.statusNeedsSupplement
    }
}
