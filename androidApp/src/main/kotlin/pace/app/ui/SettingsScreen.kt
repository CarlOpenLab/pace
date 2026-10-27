package pace.app.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import pace.app.AppContainer
import pace.shared.datetime.PaceDates
import pace.shared.model.ImportPreview
import java.io.File
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

/** 设置页：预算、导出/恢复、隐私说明、数据删除（PLAN §7 页面 5/7/8）。 */
@Composable
fun SettingsScreen() {
    val context = LocalContext.current
    val ledger = AppContainer.ledger
    var refresh by remember { mutableStateOf(0) }

    // ---- 预算 ----
    val currentBudget = remember(refresh) { ledger.budgetFor(AppContainer.todayIso()) }
    var budgetText by remember {
        mutableStateOf(currentBudget?.let { pace.shared.money.Money.formatMinor(it.dailyAmountMinor) } ?: "")
    }
    var budgetEffectiveFrom by remember { mutableStateOf(AppContainer.todayIso()) }
    var budgetError by remember { mutableStateOf<String?>(null) }

    // ---- 导入 ----
    var pendingImport by remember { mutableStateOf<String?>(null) }
    var importPreview by remember { mutableStateOf<ImportPreview?>(null) }
    var confirmReplace by remember { mutableStateOf(false) }
    var importMessage by remember { mutableStateOf<String?>(null) }
    val openJsonLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        if (uri != null) {
            val text = context.contentResolver.openInputStream(uri)?.bufferedReader()?.readText()
            if (text != null) {
                pendingImport = text
                importPreview = ledger.previewImport(text)
            } else {
                importMessage = "无法读取文件"
            }
        }
    }

    var confirmClear by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp)
    ) {
        Text("设置", style = MaterialTheme.typography.headlineSmall)

        Spacer(Modifier.height(16.dp))
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text("每日预算", style = MaterialTheme.typography.titleMedium)
                if (currentBudget != null) {
                    Text(
                        "当前 ${pace.shared.money.Money.display(currentBudget.dailyAmountMinor, currentBudget.currency)}" +
                            "（自 ${currentBudget.effectiveFromLocalDate} 生效）",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                } else {
                    Text(
                        "尚未设置预算",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = budgetText,
                    onValueChange = { budgetText = it },
                    label = { Text("每日预算（元）") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.height(8.dp))
                OutlinedTextField(
                    value = budgetEffectiveFrom,
                    onValueChange = { budgetEffectiveFrom = it },
                    label = { Text("生效日期（yyyy-MM-dd）") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                budgetError?.let {
                    Spacer(Modifier.height(4.dp))
                    Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                }
                Spacer(Modifier.height(8.dp))
                Button(onClick = {
                    val error = ledger.setBudget(budgetText, "CNY", budgetEffectiveFrom)
                    if (error == null) {
                        budgetError = null
                        refresh += 1
                    } else {
                        budgetError = describeError(error)
                    }
                }) { Text("保存预算") }
                Text(
                    "修改预算从指定生效日开始，不重写历史。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        Spacer(Modifier.height(16.dp))
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text("导出与恢复", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(8.dp))
                Row {
                    OutlinedButton(onClick = { shareExport(context, "csv", ledger.exportCsv()) }) {
                        Text("导出 CSV")
                    }
                    Spacer(Modifier.padding(4.dp))
                    OutlinedButton(onClick = { shareExport(context, "json", ledger.exportJson(AppContainer.timezoneId)) }) {
                        Text("导出 JSON")
                    }
                }
                Spacer(Modifier.height(8.dp))
                OutlinedButton(onClick = { openJsonLauncher.launch(arrayOf("application/json")) }) {
                    Text("从 JSON 恢复…")
                }
                importMessage?.let {
                    Spacer(Modifier.height(8.dp))
                    Text(it, style = MaterialTheme.typography.bodySmall)
                }
                Text(
                    "导出文件通过系统分享面板交给你保存；保存到 iCloud/Drive/微信等外部服务后，由对应服务管理。" +
                        "账本数据只保存在本机，删除 App 且未导出时数据将丢失。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        Spacer(Modifier.height(16.dp))
        SettingsAiSection()

        Spacer(Modifier.height(16.dp))
        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text("数据", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(8.dp))
                OutlinedButton(onClick = { confirmClear = true }) { Text("清空全部数据…") }
            }
        }
        Spacer(Modifier.height(32.dp))
    }

    // 导入预览（先整体校验，确认后事务性写入）
    val preview = importPreview
    if (pendingImport != null && preview != null) {
        AlertDialog(
            onDismissRequest = { pendingImport = null; importPreview = null },
            title = { Text("恢复预览") },
            text = {
                if (preview.valid) {
                    Text(
                        "账单 ${preview.transactionCount} 笔（${preview.firstLocalDate ?: "无"} ~ ${preview.lastLocalDate ?: "无"}）\n" +
                            "分类 ${preview.categoryCount} · 预算规则 ${preview.budgetRuleCount}\n" +
                            "与现有账本重复 ${preview.duplicateCount} 笔\n\n" +
                            "合并：跳过重复，保留现有账本。\n替换：清空当前账本后写入。"
                    )
                } else {
                    Text("文件校验未通过，不会写入任何数据：\n${preview.errors.joinToString("\n")}")
                }
            },
            confirmButton = {
                if (preview.valid) {
                    TextButton(onClick = {
                        val result = ledger.applyImport(pendingImport!!, "MERGE")
                        importMessage = if (result.applied) {
                            "已合并：新入 ${result.insertedCount} 笔，跳过 ${result.skippedCount} 条"
                        } else {
                            "合并失败：${result.errors.joinToString().take(200)}"
                        }
                        pendingImport = null
                        importPreview = null
                        refresh += 1
                    }) { Text("合并") }
                }
            },
            dismissButton = {
                if (preview.valid) {
                    TextButton(onClick = { confirmReplace = true }) { Text("替换…") }
                }
                TextButton(onClick = { pendingImport = null; importPreview = null }) { Text("取消") }
            }
        )
    }

    if (confirmReplace) {
        AlertDialog(
            onDismissRequest = { confirmReplace = false },
            title = { Text("替换当前账本？") },
            text = { Text("当前全部账单、预算和分类将被删除，并以导入文件替换。此操作无法撤销。") },
            confirmButton = {
                TextButton(onClick = {
                    confirmReplace = false
                    val result = ledger.applyImport(pendingImport!!, "REPLACE")
                    importMessage = if (result.applied) {
                        "已替换：写入 ${result.insertedCount} 笔"
                    } else {
                        "替换失败，原账本未变更：${result.errors.joinToString().take(200)}"
                    }
                    pendingImport = null
                    importPreview = null
                    refresh += 1
                }) { Text("确认替换") }
            },
            dismissButton = {
                TextButton(onClick = { confirmReplace = false }) { Text("取消") }
            }
        )
    }

    if (confirmClear) {
        AlertDialog(
            onDismissRequest = { confirmClear = false },
            title = { Text("清空全部数据？") },
            text = { Text("将删除所有账单、预算规则和自定义分类。此操作无法撤销，请先导出备份。") },
            confirmButton = {
                TextButton(onClick = {
                    confirmClear = false
                    val ok = ledger.clearAllData()
                    importMessage = if (ok) "已清空全部数据" else "清空失败"
                    refresh += 1
                }) { Text("确认清空") }
            },
            dismissButton = {
                TextButton(onClick = { confirmClear = false }) { Text("取消") }
            }
        )
    }
}

private fun shareExport(context: Context, ext: String, content: String) {
    val stamp = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss"))
    val dir = File(context.cacheDir, "exports").apply { mkdirs() }
    val file = File(dir, "pace-ledger-$stamp.$ext")
    file.writeText(content, Charsets.UTF_8)
    val uri = androidx.core.content.FileProvider.getUriForFile(
        context, context.packageName + ".fileprovider", file
    )
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = if (ext == "csv") "text/csv" else "application/json"
        putExtra(Intent.EXTRA_STREAM, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(intent, "保存导出文件"))
}
