package pace.app.ui

import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import pace.app.AppContainer
import pace.app.ai.AiDraftClient
import pace.app.ai.AiFailure
import pace.app.ai.AiSettings
import pace.app.ai.DraftItem
import pace.app.ai.DraftMissing
import pace.app.ai.DraftSaver
import pace.app.ai.LocalDrafts
import pace.app.ai.PaceCopy
import pace.app.ai.updateAmount
import pace.shared.model.ErrorCodes
import pace.shared.model.SaveResult
import pace.shared.model.SaveTxnInput
import pace.shared.model.Transaction
import pace.shared.model.TxnType
import pace.shared.money.Money

private val typeOptions = listOf(
    TxnType.EXPENSE to "支出",
    TxnType.INCOME to "收入",
    TxnType.TRANSFER to "转账",
    TxnType.REFUND to "退款"
)

private enum class AddFillMode { SENTENCE, MANUAL }

/**
 * 记一笔（docs/DESIGN-add-mode-switch.md）：页顶切换「一句话 / 手动」，两种填法
 * 写的是同一笔账，共用下面这份状态。切换只换显示，不动值；唯一会覆盖表单的
 * 是一次新的解析——那是用户按了发送的显式动作。编辑已有账单没有切换器。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AddScreen(
    txnId: String?,
    onDone: () -> Unit,
    onOpenReview: (List<DraftItem>) -> Unit,
    reviewResult: ManualPrefill?,
    onConsumeReviewResult: () -> Unit
) {
    // remember(txnId)：编辑态只在打开时查一次库，不跟着每次重组（每个按键）重查
    val editing: Transaction? = remember(txnId) { txnId?.let { AppContainer.ledger.transaction(it) } }
    val isEditing = txnId != null

    // 共享状态：两种填法各取所需，切换不丢（spec §4）
    var type by remember { mutableStateOf(editing?.type ?: TxnType.EXPENSE) }
    var amountText by remember {
        mutableStateOf(editing?.let { Money.formatMinor(it.amountMinor) } ?: "")
    }
    var category by remember { mutableStateOf(editing?.category ?: "餐饮") }
    var localDate by remember { mutableStateOf(editing?.localDate ?: AppContainer.todayIso()) }
    var note by remember { mutableStateOf(editing?.note ?: "") }
    var account by remember { mutableStateOf(editing?.account ?: "现金") }
    var countInBudget by remember { mutableStateOf(editing?.countInBudget ?: true) }
    var refundOfId by remember { mutableStateOf<String?>(editing?.refundOfId) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirmDuplicate by remember { mutableStateOf(false) }

    // 一句话模式自己的状态
    var mode by remember { mutableStateOf(if (isEditing) AddFillMode.MANUAL else AddFillMode.SENTENCE) }
    var sentenceText by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<AiFailure?>(null) }
    var localFailure by remember { mutableStateOf(false) }
    var sentenceDraft by remember { mutableStateOf<DraftItem?>(null) }
    var pumpedDraftId by remember { mutableStateOf<String?>(null) }
    var inlineSaved by remember { mutableStateOf(false) }
    var inlineSaveFailed by remember { mutableStateOf(false) }
    var savingInline by remember { mutableStateOf(false) }
    /** 就地草稿卡的字段是可变对象上的改动；bump 它让卡片重读金额。 */
    var inlineRevision by remember { mutableStateOf(0) }
    /** 非空表示这次重复来自一句话的「记上」。 */
    var duplicateDraft by remember { mutableStateOf<DraftItem?>(null) }

    val categories = remember { AppContainer.ledger.categories() }
    val expensesForRefund = remember {
        AppContainer.ledger.allTransactions().filter { it.type == TxnType.EXPENSE }
    }
    val scope = rememberCoroutineScope()

    // 草稿确认页「退款或转账，切到手动」：把那句带回表单（只带一次）
    LaunchedEffect(reviewResult) {
        val prefill = reviewResult ?: return@LaunchedEffect
        onConsumeReviewResult()
        if (prefill.amountText.isNotEmpty()) amountText = prefill.amountText
        if (prefill.localDate.isNotEmpty()) localDate = prefill.localDate
        if (prefill.note.isNotEmpty()) note = prefill.note
        mode = AddFillMode.MANUAL
    }

    val trimmed = sentenceText.trim()
    val canSubmit = trimmed.isNotEmpty() && !busy

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

    fun saveManual(force: Boolean) {
        error = null
        val result: SaveResult = AppContainer.ledger.saveTransaction(buildSaveInput(force))
        if (result.isSuccess) {
            onDone()
        } else if (result.errorCode == ErrorCodes.DUPLICATE_FINGERPRINT) {
            duplicateDraft = null
            confirmDuplicate = true
        } else {
            error = describeError(result.errorCode)
        }
    }

    // 一笔且齐全就地确认；多笔或缺字段才去确认页
    fun present(parsed: List<DraftItem>) {
        if (parsed.size == 1 && parsed.first().missingFields.isEmpty()) {
            sentenceDraft = parsed.first()
            return
        }
        onOpenReview(parsed)
    }

    fun runLocal() {
        failure = null
        localFailure = false
        sentenceDraft = null
        inlineSaved = false
        inlineSaveFailed = false
        pumpedDraftId = null
        val parsed = LocalDrafts.parse(trimmed, AppContainer.todayIso())
        if (parsed.isEmpty()) {
            localFailure = true
            failure = AiFailure.Unreadable
            return
        }
        present(parsed)
    }

    fun parseSentence() {
        if (!canSubmit) return
        failure = null
        localFailure = false
        sentenceDraft = null
        inlineSaved = false
        inlineSaveFailed = false
        pumpedDraftId = null
        busy = true
        val sentence = trimmed
        val today = AppContainer.todayIso()
        scope.launch {
            try {
                if (AiSettings.usesRemoteModel) {
                    val config = AiSettings.config() ?: throw AiFailure.NotConfigured
                    val parsed = withContext(Dispatchers.IO) {
                        AiDraftClient.parse(sentence, today, config)
                    }
                    present(parsed)
                } else {
                    runLocal()
                }
            } catch (e: AiFailure) {
                failure = e
            } catch (e: Throwable) {
                failure = AiFailure.Unreadable
            } finally {
                busy = false
            }
        }
    }

    fun selectMode(newMode: AddFillMode) {
        if (newMode == mode) return
        // 一句话刚解析出的那张草稿，切到手动时把值带进表单；只带一次，
        // 用户改了表单再切回来，不能被同一张草稿再盖一遍
        if (newMode == AddFillMode.MANUAL) {
            val draft = sentenceDraft
            if (draft != null && pumpedDraftId != draft.id) {
                pumpedDraftId = draft.id
                if (draft.amountText.isNotEmpty()) amountText = draft.amountText
                type = draft.type
                if (draft.category.isNotEmpty()) category = draft.category
                if (draft.localDate.isNotEmpty()) localDate = draft.localDate
                note = draft.note
                error = null
            }
        }
        mode = newMode
    }

    fun saveInline(draft: DraftItem) {
        if (savingInline) return
        savingInline = true
        val outcome = DraftSaver.save(listOf(draft))
        if (outcome.saved > 0) {
            inlineSaved = true
            savingInline = false
            scope.launch {
                kotlinx.coroutines.delay(800)
                onDone()
            }
            return
        }
        savingInline = false
        if (outcome.duplicated.isNotEmpty()) {
            duplicateDraft = draft
            confirmDuplicate = true
        } else {
            // 账没记上，话也不能说成「那句话没读懂」
            inlineSaveFailed = true
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 18.dp)
    ) {
        Spacer(Modifier.height(8.dp))
        Text(
            if (isEditing) "编辑账单" else "记一笔",
            style = MaterialTheme.typography.headlineSmall
        )

        // 切换器：编辑账单没有它（spec §8.6）
        if (!isEditing) {
            Spacer(Modifier.height(10.dp))
            SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                SegmentedButton(
                    selected = mode == AddFillMode.SENTENCE,
                    onClick = { selectMode(AddFillMode.SENTENCE) },
                    shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2)
                ) { Text(PaceCopy.AddMode.sentence) }
                SegmentedButton(
                    selected = mode == AddFillMode.MANUAL,
                    onClick = { selectMode(AddFillMode.MANUAL) },
                    shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2)
                ) { Text(PaceCopy.AddMode.manual) }
            }
        }
        Spacer(Modifier.height(14.dp))

        if (!isEditing && mode == AddFillMode.SENTENCE) {
            // ---------- 一句话 ----------
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .glassCard(RoundedCornerShape(20.dp))
                    .padding(horizontal = 18.dp, vertical = 10.dp)
            ) {
                OutlinedTextField(
                    value = sentenceText,
                    onValueChange = { sentenceText = it },
                    placeholder = { Text(PaceCopy.Ai.Input.placeholder) },
                    singleLine = true,
                    enabled = !busy && sentenceDraft == null,
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Text,
                        imeAction = if (trimmed.isEmpty() || !AiSettings.usesRemoteModel) ImeAction.Done else ImeAction.Send
                    ),
                    keyboardActions = KeyboardActions(onSend = { parseSentence() }, onDone = { parseSentence() }),
                    colors = androidx.compose.material3.OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = Color.Transparent,
                        unfocusedBorderColor = Color.Transparent,
                        disabledBorderColor = Color.Transparent
                    ),
                    modifier = Modifier.fillMaxWidth()
                )
            }

            if (busy) {
                // 原地占住草稿卡的位置：解析完直接换卡，不让页面跳一下
                Spacer(Modifier.height(12.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                    Spacer(Modifier.padding(4.dp))
                    Text(
                        PaceCopy.Ai.Input.parsing,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            failure?.let { failureValue ->
                Spacer(Modifier.height(12.dp))
                FailureCard(
                    failure = failureValue,
                    isLocal = localFailure,
                    onPrimary = {
                        val copy = failureCopy(failureValue, localFailure)
                        when {
                            // Key 被拒：去设置（关掉本页，让用户去弄 Key）
                            copy.primary == PaceCopy.Ai.Fail.toSettings -> onDone()
                            // 没网：本机规则也是一条出路
                            copy.primary == PaceCopy.Ai.Fail.retryLocal -> runLocal()
                            else -> {
                                if (note.isEmpty() && trimmed.isNotEmpty()) note = trimmed
                                selectMode(AddFillMode.MANUAL)
                            }
                        }
                    },
                    onSecondary = { secondary ->
                        if (secondary == PaceCopy.Ai.Fail.toManual) {
                            if (note.isEmpty() && trimmed.isNotEmpty()) note = trimmed
                            selectMode(AddFillMode.MANUAL)
                        } else {
                            runLocal()
                        }
                    }
                )
            }

            val draft = sentenceDraft
            if (draft != null) {
                Spacer(Modifier.height(12.dp))
                if (inlineSaved) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .glassCard(RoundedCornerShape(18.dp))
                            .padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("✓", style = MaterialTheme.typography.titleMedium)
                        Spacer(Modifier.padding(4.dp))
                        Text(PaceCopy.Ai.Input.confirmed, style = MaterialTheme.typography.bodyLarge)
                    }
                } else {
                    InlineDraftCard(draft, inlineRevision) { inlineRevision += 1 }
                    if (inlineSaveFailed) {
                        Spacer(Modifier.height(8.dp))
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .glassCard(RoundedCornerShape(18.dp))
                                .padding(16.dp)
                        ) {
                            Text(PaceCopy.Failed.InlineSave.title, style = MaterialTheme.typography.titleSmall)
                            Text(
                                PaceCopy.Failed.InlineSave.body,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                    Spacer(Modifier.height(12.dp))
                    Button(
                        onClick = { saveInline(draft) },
                        enabled = !savingInline,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = Color.Transparent,
                            contentColor = Color.White
                        ),
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(52.dp)
                            .background(PaceGradients.accent(), RoundedCornerShape(50))
                    ) {
                        if (savingInline) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(18.dp),
                                strokeWidth = 2.dp,
                                color = Color.White
                            )
                            Spacer(Modifier.padding(4.dp))
                        }
                        Text(PaceCopy.Ai.Input.confirmInline, fontWeight = FontWeight.Bold)
                    }
                    Spacer(Modifier.height(4.dp))
                    TextButton(
                        onClick = { onOpenReview(listOf(draft)) },
                        modifier = Modifier.fillMaxWidth()
                    ) { Text(PaceCopy.Ai.Input.editInline) }
                }
            } else if (trimmed.isEmpty() && !busy) {
                // 例句只在输入框空着、还没有草稿时出现
                Spacer(Modifier.height(12.dp))
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    PaceCopy.Ai.Input.examples.take(4).forEach { example ->
                        FilterChip(
                            selected = false,
                            onClick = { sentenceText = example },
                            label = { Text(example) }
                        )
                    }
                }
            }
        } else {
            // ---------- 手动（原有表单） ----------
            Spacer(Modifier.height(4.dp))
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
                                        "${candidate.localDate} ${Money.display(candidate.amountMinor, candidate.currency)} ${candidate.note.ifBlank { candidate.category }}"
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
                    onClick = { saveManual(force = false) },
                    modifier = Modifier.weight(1f)
                ) { Text("保存") }
                TextButton(onClick = onDone, modifier = Modifier.weight(1f)) { Text("取消") }
            }
            Spacer(Modifier.height(8.dp))
        }

        Spacer(Modifier.height(120.dp))
    }

    if (confirmDuplicate) {
        AlertDialog(
            onDismissRequest = { confirmDuplicate = false },
            title = { Text(PaceCopy.Save.duplicateTitle) },
            text = { Text(PaceCopy.Save.duplicateBody) },
            confirmButton = {
                TextButton(onClick = {
                    confirmDuplicate = false
                    val forcedDraft = duplicateDraft
                    if (forcedDraft != null) {
                        // 这笔重复来自一句话的「记上」
                        duplicateDraft = null
                        savingInline = true
                        val outcome = DraftSaver.save(listOf(forcedDraft), force = true)
                        savingInline = false
                        if (outcome.saved > 0) {
                            inlineSaved = true
                            scope.launch {
                                kotlinx.coroutines.delay(800)
                                onDone()
                            }
                        } else {
                            inlineSaveFailed = true
                        }
                    } else {
                        saveManual(force = true)
                    }
                }) { Text(PaceCopy.Save.duplicatePrimary) }
            },
            dismissButton = {
                TextButton(onClick = { confirmDuplicate = false; duplicateDraft = null }) {
                    Text(PaceCopy.Save.duplicateCancel)
                }
            }
        )
    }
}

/** 就地确认的草稿卡：金额、类型、分类、日期都在卡上，可直接改。 */
@Composable
private fun InlineDraftCard(draft: DraftItem, revision: Int, onMutated: () -> Unit) {
    @Suppress("UNUSED_EXPRESSION") revision
    var editing by remember { mutableStateOf(false) }
    var amount by remember { mutableStateOf(draft.amountText) }
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
                    listOfNotNull(
                        draft.category,
                        draft.localDate.takeIf { it.isNotEmpty() }?.let { displayDate(it) }
                    ).joinToString(" · "),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            Text(
                if (draft.amountMinor > 0) Money.display(draft.amountMinor, draft.currency)
                else PaceCopy.Draft.emptyAmount,
                style = MaterialTheme.typography.titleSmall.copy(fontSize = 16.sp),
                fontWeight = FontWeight.SemiBold,
                color = if (draft.amountMinor > 0) MaterialTheme.colorScheme.onSurface
                else MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        val marker = draft.missingFields
            .filterNot { it == DraftMissing.AMOUNT || it == DraftMissing.TYPE }
            .firstOrNull()
        if (marker != null) {
            Spacer(Modifier.height(8.dp))
            Text(
                PaceCopy.Draft.statusNeedsSupplement,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.primary
            )
        }

        if (editing) {
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    PaceCopy.Draft.Field.amount,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.padding(4.dp))
                androidx.compose.material3.OutlinedTextField(
                    value = amount,
                    onValueChange = {
                        amount = it
                        draft.updateAmount(it)
                        onMutated()
                    },
                    placeholder = { Text("0.00") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                    singleLine = true,
                    modifier = Modifier.weight(1f)
                )
            }
            Spacer(Modifier.height(6.dp))
            OutlinedTextField(
                value = draft.note,
                onValueChange = {
                    draft.note = it
                    onMutated()
                },
                placeholder = { Text(PaceCopy.Draft.Field.note) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(Modifier.height(8.dp))
            TextButton(onClick = { editing = false }) { Text(PaceCopy.Draft.editorDone) }
        }
    }
}

private class FailureCopy(
    val title: String,
    val body: String,
    val primary: String,
    val secondary: String?
)

/** 失败卡文案矩阵（docs/AI_PRIVACY.md §5；与 iOS AddView.failureCopy 一字不差）。 */
private fun failureCopy(failure: AiFailure, isLocal: Boolean): FailureCopy {
    // K2 不允许经实例访问嵌套对象：一律用 PaceCopy.Ai.Fail.X 类名路径
    if (isLocal) {
        return FailureCopy(
            PaceCopy.Ai.Fail.LocalRule.title,
            PaceCopy.Ai.Fail.LocalRule.body,
            PaceCopy.Ai.Fail.LocalRule.primary,
            null
        )
    }
    return when (failure) {
        AiFailure.Offline -> FailureCopy(
            PaceCopy.Ai.Fail.Offline.title,
            PaceCopy.Ai.Fail.Offline.body,
            PaceCopy.Ai.Fail.Offline.primary,
            PaceCopy.Ai.Fail.Offline.secondary
        )
        AiFailure.Timeout -> FailureCopy(
            PaceCopy.Ai.Fail.Timeout.title,
            PaceCopy.Ai.Fail.Timeout.body,
            PaceCopy.Ai.Fail.Timeout.primary,
            PaceCopy.Ai.Fail.Timeout.secondary
        )
        AiFailure.KeyRejected -> FailureCopy(
            PaceCopy.Ai.Fail.KeyRejected.title,
            PaceCopy.Ai.Fail.KeyRejected.body,
            PaceCopy.Ai.Fail.KeyRejected.primary,
            PaceCopy.Ai.Fail.KeyRejected.secondary
        )
        AiFailure.Quota -> FailureCopy(
            PaceCopy.Ai.Fail.KeyRejected.title,
            PaceCopy.Ai.Fail.Quota.body,
            PaceCopy.Ai.Fail.KeyRejected.primary,
            PaceCopy.Ai.Fail.KeyRejected.secondary
        )
        AiFailure.BadAddress -> FailureCopy(
            PaceCopy.Ai.Fail.BadAddress.title,
            PaceCopy.Ai.Fail.BadAddress.body,
            PaceCopy.Ai.Fail.BadAddress.primary,
            PaceCopy.Ai.Fail.BadAddress.secondary
        )
        AiFailure.Certificate -> FailureCopy(
            PaceCopy.Ai.Fail.Certificate.title,
            PaceCopy.Ai.Fail.Certificate.body,
            PaceCopy.Ai.Fail.Certificate.primary,
            PaceCopy.Ai.Fail.Certificate.secondary
        )
        is AiFailure.Server -> if (failure.code in 400..499) {
            // 4xx 是「它收到了、但这次请求它不收」，多半是模型名不对
            FailureCopy(
                PaceCopy.Ai.Fail.ModelRejected.title,
                PaceCopy.Ai.Fail.ModelRejected.body,
                PaceCopy.Ai.Fail.ModelRejected.primary,
                PaceCopy.Ai.Fail.ModelRejected.secondary
            )
        } else {
            FailureCopy(
                PaceCopy.Ai.Fail.Server.title,
                PaceCopy.Ai.Fail.Server.body,
                PaceCopy.Ai.Fail.Server.primary,
                PaceCopy.Ai.Fail.Server.secondary
            )
        }
        AiFailure.AddressUnreachable, AiFailure.NotConfigured -> FailureCopy(
            PaceCopy.Ai.Fail.Unreachable.title,
            PaceCopy.Ai.Fail.Unreachable.body,
            PaceCopy.Ai.Fail.Unreachable.primary,
            PaceCopy.Ai.Fail.Unreachable.secondary
        )
        else -> FailureCopy(
            PaceCopy.Ai.Fail.Model.title,
            PaceCopy.Ai.Fail.Model.body,
            PaceCopy.Ai.Fail.Model.primary,
            PaceCopy.Ai.Fail.Model.secondary
        )
    }
}

/** 失败卡：标题 + 正文 + 两颗按钮（并排放不下就换行——字号是用户选的，不缩字）。 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FailureCard(
    failure: AiFailure,
    isLocal: Boolean,
    onPrimary: () -> Unit,
    onSecondary: (String) -> Unit
) {
    val copy = failureCopy(failure, isLocal)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .glassCard(RoundedCornerShape(18.dp))
            .padding(20.dp)
    ) {
        Text(copy.title, style = MaterialTheme.typography.titleSmall)
        Spacer(Modifier.height(8.dp))
        Text(
            copy.body,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Spacer(Modifier.height(16.dp))
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            TextButton(onClick = onPrimary) { Text(copy.primary) }
            copy.secondary?.let { secondary ->
                TextButton(onClick = { onSecondary(secondary) }) { Text(secondary) }
            }
        }
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
