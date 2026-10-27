package pace.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import pace.app.ai.AiDraftClient
import pace.app.ai.AiModelList
import pace.app.ai.AiProvider
import pace.app.ai.AiSettings
import pace.app.ai.PaceCopy

/**
 * 设置 → 一句话记账（docs/AI_PRIVACY.md §1、Copy 3 节）。
 * Key 只进 AndroidKeyStore 加密存储，不写导出、不进日志。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsAiSection(modifier: Modifier = Modifier) {
    val enabled = AiSettings.enabled
    val endpoint = AiSettings.endpoint
    val model = AiSettings.model
    val key = AiSettings.key

    var modelMenuExpanded by remember { mutableStateOf(false) }
    var providerMenuExpanded by remember { mutableStateOf(false) }
    var fetchedModels by remember { mutableStateOf<List<String>?>(null) }
    var modelMessage by remember { mutableStateOf<String?>(null) }
    var loadingModels by remember { mutableStateOf(false) }
    var testMessage by remember { mutableStateOf<String?>(null) }
    var testing by remember { mutableStateOf(false) }
    var confirmClearKey by remember { mutableStateOf(false) }

    val provider = AiProvider.matching(endpoint)
    val isCustom = provider.id == "custom"
    val plainHttp = endpoint.trim().startsWith("http://")
    val scope = rememberCoroutineScope()

    fun fetchModels() {
        if (loadingModels) return
        if (endpoint.trim().isEmpty()) {
            modelMessage = PaceCopy.Ai.Settings.ModelPick.noAddress
            return
        }
        if (key.isEmpty()) {
            modelMessage = PaceCopy.Ai.Settings.ModelPick.noKey
            return
        }
        loadingModels = true
        modelMessage = PaceCopy.Ai.Settings.ModelPick.loading
        scope.launch {
            val outcome = withContext(Dispatchers.IO) {
                AiModelList.fetch(endpoint, key)
            }
            loadingModels = false
            when (outcome) {
                is AiModelList.Outcome.Success -> {
                    fetchedModels = outcome.models
                    modelMessage = if (outcome.models.isEmpty()) {
                        PaceCopy.Ai.Settings.ModelPick.empty
                    } else {
                        PaceCopy.Ai.Settings.ModelPick.ready
                    }
                }
                is AiModelList.Outcome.Failed -> {
                    modelMessage = when (outcome.reason) {
                        AiModelList.Failure.KeyRejected -> PaceCopy.Ai.Settings.ModelPick.keyRejected
                        AiModelList.Failure.NoModelList -> PaceCopy.Ai.Settings.ModelPick.noModelList
                        AiModelList.Failure.Offline -> PaceCopy.Ai.Settings.ModelPick.offline
                        AiModelList.Failure.BadAddress -> PaceCopy.Ai.Settings.ModelPick.badAddress
                        AiModelList.Failure.Certificate -> PaceCopy.Ai.Settings.ModelPick.certificate
                        AiModelList.Failure.NoAddress -> PaceCopy.Ai.Settings.ModelPick.noAddress
                        AiModelList.Failure.NoKey -> PaceCopy.Ai.Settings.ModelPick.noKey
                        AiModelList.Failure.Empty -> PaceCopy.Ai.Settings.ModelPick.empty
                        AiModelList.Failure.Unreachable, AiModelList.Failure.Server ->
                            PaceCopy.Ai.Settings.ModelPick.unreachable
                    }
                }
            }
        }
    }

    fun testConnection() {
        if (testing) return
        val config = AiSettings.config()
        if (config == null) {
            testMessage = PaceCopy.Ai.Settings.Test.incomplete
            return
        }
        testing = true
        testMessage = PaceCopy.Ai.Settings.Test.connecting
        scope.launch {
            val result = withContext(Dispatchers.IO) {
                AiDraftClient.testConnection(config)
            }
            testing = false
            testMessage = when (result) {
                AiDraftClient.TestResult.Ok -> PaceCopy.Ai.Settings.Test.ok
                AiDraftClient.TestResult.Offline -> PaceCopy.Ai.Settings.Test.offline
                AiDraftClient.TestResult.BadAddress -> PaceCopy.Ai.Settings.Test.badAddress
                AiDraftClient.TestResult.Certificate -> PaceCopy.Ai.Settings.Test.certificate
                AiDraftClient.TestResult.Timeout, AiDraftClient.TestResult.Unreachable ->
                    PaceCopy.Ai.Settings.Test.unreachable
                AiDraftClient.TestResult.KeyRejected -> PaceCopy.Ai.Settings.Test.keyRejected
                is AiDraftClient.TestResult.Server ->
                    if (result.code in 400..499) PaceCopy.Ai.Settings.Test.modelRejected
                    else PaceCopy.Ai.Settings.Test.server
                AiDraftClient.TestResult.Incomplete -> PaceCopy.Ai.Settings.Test.incomplete
            }
        }
    }

    Card(modifier = modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(PaceCopy.Ai.Settings.sectionTitle, style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(8.dp))
            Row(modifier = Modifier.fillMaxWidth()) {
                Text(PaceCopy.Ai.Settings.toggleTitle, modifier = Modifier.weight(1f))
                Switch(
                    checked = enabled,
                    onCheckedChange = { AiSettings.updateEnabled(it) }
                )
            }
            Text(
                if (AiSettings.usesRemoteModel) PaceCopy.Ai.Settings.subtitleOn
                else PaceCopy.Ai.Settings.subtitleOff,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            if (enabled) {
                Spacer(Modifier.height(12.dp))
                // 服务商：地址和某个预置一致才认成那个服务商，用户手改过就算自定义
                Text(PaceCopy.Ai.Settings.Provider.label, style = MaterialTheme.typography.labelLarge)
                ExposedDropdownMenuBox(
                    expanded = providerMenuExpanded,
                    onExpandedChange = { providerMenuExpanded = it }
                ) {
                    Text(
                        provider.name,
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier
                            .menuAnchor()
                            .padding(vertical = 10.dp)
                    )
                    ExposedDropdownMenu(
                        expanded = providerMenuExpanded,
                        onDismissRequest = { providerMenuExpanded = false }
                    ) {
                        AiProvider.presets.forEach { preset ->
                            DropdownMenuItem(
                                text = { Text(preset.name) },
                                onClick = {
                                    AiSettings.updateEndpoint(preset.endpoint)
                                    fetchedModels = null
                                    providerMenuExpanded = false
                                }
                            )
                        }
                        DropdownMenuItem(
                            text = { Text(PaceCopy.Ai.Settings.Provider.custom) },
                            onClick = {
                                AiSettings.updateEndpoint("")
                                fetchedModels = null
                                providerMenuExpanded = false
                            }
                        )
                    }
                }
                Text(
                    PaceCopy.Ai.Settings.Provider.note,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )

                if (isCustom) {
                    Spacer(Modifier.height(10.dp))
                    OutlinedTextField(
                        value = endpoint,
                        onValueChange = {
                            AiSettings.updateEndpoint(it)
                            fetchedModels = null
                        },
                        label = { Text(PaceCopy.Ai.Settings.Endpoint.label) },
                        placeholder = { Text(PaceCopy.Ai.Settings.Endpoint.placeholder) },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Text(
                        PaceCopy.Ai.Settings.Endpoint.note,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    if (plainHttp) {
                        Text(
                            PaceCopy.Ai.Settings.Endpoint.plainHTTP,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error
                        )
                    }
                }

                Spacer(Modifier.height(10.dp))
                OutlinedTextField(
                    value = model,
                    onValueChange = { AiSettings.updateModel(it) },
                    label = { Text(PaceCopy.Ai.Settings.Model.label) },
                    placeholder = { Text(PaceCopy.Ai.Settings.Model.placeholder) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                Text(
                    PaceCopy.Ai.Settings.Model.note,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Spacer(Modifier.height(8.dp))
                Row {
                    Button(onClick = { fetchModels() }, enabled = !loadingModels) {
                        Text(
                            if (fetchedModels == null) PaceCopy.Ai.Settings.ModelPick.read
                            else PaceCopy.Ai.Settings.ModelPick.retry
                        )
                    }
                    if (fetchedModels != null && fetchedModels!!.isNotEmpty()) {
                        Spacer(Modifier.padding(4.dp))
                        ExposedDropdownMenuBox(
                            expanded = modelMenuExpanded,
                            onExpandedChange = { modelMenuExpanded = it }
                        ) {
                            Text(
                                model.ifEmpty { PaceCopy.Ai.Settings.ModelPick.read },
                                style = MaterialTheme.typography.bodyMedium,
                                modifier = Modifier
                                    .menuAnchor()
                                    .padding(vertical = 12.dp)
                            )
                            ExposedDropdownMenu(
                                expanded = modelMenuExpanded,
                                onDismissRequest = { modelMenuExpanded = false }
                            ) {
                                fetchedModels!!.forEach { id ->
                                    DropdownMenuItem(
                                        text = { Text(id) },
                                        onClick = {
                                            AiSettings.updateModel(id)
                                            modelMenuExpanded = false
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
                modelMessage?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                Spacer(Modifier.height(10.dp))
                OutlinedTextField(
                    value = key,
                    onValueChange = { AiSettings.updateKey(it) },
                    label = { Text(PaceCopy.Ai.Settings.Key.label) },
                    placeholder = { Text(PaceCopy.Ai.Settings.Key.placeholder) },
                    visualTransformation = PasswordVisualTransformation(),
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
                Text(
                    PaceCopy.Ai.Settings.keyScope,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                if (AiSettings.keyStoreFailed) {
                    Text(
                        PaceCopy.Ai.Settings.Key.storeFailed,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error
                    )
                }
                Text(
                    PaceCopy.Ai.Settings.Key.note,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )

                Spacer(Modifier.height(10.dp))
                Row {
                    Button(
                        onClick = { testConnection() },
                        enabled = !testing,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = Color.Transparent,
                            contentColor = MaterialTheme.colorScheme.primary
                        ),
                        modifier = Modifier.background(
                            MaterialTheme.colorScheme.surfaceVariant,
                            RoundedCornerShape(50)
                        )
                    ) { Text(PaceCopy.Ai.Settings.Test.button, fontWeight = FontWeight.SemiBold) }
                    Spacer(Modifier.padding(4.dp))
                    TextButton(onClick = { confirmClearKey = true }) {
                        Text(PaceCopy.Ai.Settings.Key.clear)
                    }
                }
                testMessage?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                Spacer(Modifier.height(10.dp))
                Text(
                    PaceCopy.Ai.Settings.securityNote,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }

    if (confirmClearKey) {
        AlertDialog(
            onDismissRequest = { confirmClearKey = false },
            title = { Text(PaceCopy.Ai.Settings.Key.clearConfirmTitle) },
            text = { Text(PaceCopy.Ai.Settings.Key.clearConfirmBody) },
            confirmButton = {
                TextButton(onClick = {
                    AiSettings.clearKey()
                    fetchedModels = null
                    modelMessage = null
                    testMessage = null
                    confirmClearKey = false
                }) { Text(PaceCopy.Ai.Settings.Key.clearConfirm) }
            },
            dismissButton = {
                TextButton(onClick = { confirmClearKey = false }) { Text(PaceCopy.Save.duplicateCancel) }
            }
        )
    }
}
