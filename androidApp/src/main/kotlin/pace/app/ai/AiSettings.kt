package pace.app.ai

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** BYOK 模型配置（设置 → 一句话记账）。 */
data class AiConfig(
    val endpoint: String,
    val model: String,
    val key: String
) {
    val isComplete: Boolean
        get() = endpoint.isNotBlank() && model.isNotBlank() && key.isNotEmpty()
}

/**
 * BYOK 模型配置（设置 → 一句话记账）。
 * 接口地址和模型名放 SharedPreferences；Key 用 AndroidKeyStore 的 AES-GCM
 * 密钥加密后落盘，密钥本体不出 Keystore、不写配置文件、不进导出、不进日志。
 * 写完读回来对一次：写失败不能让界面装作存上了（keyStoreFailed）。
 */
object AiSettings {

    private const val PREFS = "pace.ai"
    private const val KEY_ENABLED = "ai.enabled"
    private const val KEY_ENDPOINT = "ai.endpoint"
    private const val KEY_MODEL = "ai.model"
    private const val KEY_KEY_BLOB = "ai.key.blob"

    private const val KEYSTORE = "AndroidKeyStore"
    private const val MASTER_ALIAS = "pace.ai.master"
    private const val GCM_TAG_BITS = 128
    private const val GCM_IV_BYTES = 12

    private lateinit var prefs: SharedPreferences

    /** Compose 可观察状态；init 后由 UI 读写。 */
    var enabled by androidx.compose.runtime.mutableStateOf(false)
        private set
    var endpoint by androidx.compose.runtime.mutableStateOf("")
        private set
    var model by androidx.compose.runtime.mutableStateOf("")
        private set
    var key by androidx.compose.runtime.mutableStateOf("")
        private set

    /** 写加密存储失败时置位，设置页据此说一句，不让用户以为存上了。 */
    var keyStoreFailed by androidx.compose.runtime.mutableStateOf(false)
        private set

    fun init(context: Context) {
        // 可重入：重复调用等于按存储重载一遍（设置项都是即改即存的）
        prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        enabled = prefs.getBoolean(KEY_ENABLED, false)
        endpoint = prefs.getString(KEY_ENDPOINT, "").orEmpty()
        model = prefs.getString(KEY_MODEL, "").orEmpty()
        key = readStoredKey()
    }

    /** 三项都填全了才会真的走模型；缺任一项就用本机规则。 */
    fun config(): AiConfig? {
        val config = AiConfig(endpoint, model, key)
        return if (config.isComplete) config else null
    }

    /** 当前拆句子用的是哪条路：填了服务且开关打开 → 模型，否则本机规则。 */
    val usesRemoteModel: Boolean
        get() = enabled && config() != null

    fun updateEnabled(value: Boolean) {
        enabled = value
        prefs.edit().putBoolean(KEY_ENABLED, value).apply()
    }

    fun updateEndpoint(value: String) {
        endpoint = value
        prefs.edit().putString(KEY_ENDPOINT, value).apply()
    }

    fun updateModel(value: String) {
        model = value
        prefs.edit().putString(KEY_MODEL, value).apply()
    }

    fun updateKey(value: String) {
        key = value
        keyStoreFailed = !writeStoredKey(value)
        if (readStoredKey() != value) keyStoreFailed = true
    }

    fun clearKey() {
        key = ""
        try {
            prefs.edit().remove(KEY_KEY_BLOB).apply()
        } catch (_: Throwable) {
        }
    }

    // ---------- Key 的加密落盘（AndroidKeyStore AES/GCM） ----------

    private fun masterKey(): SecretKey {
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (store.getKey(MASTER_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(MASTER_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    private fun writeStoredKey(value: String): Boolean = try {
        if (value.isEmpty()) {
            prefs.edit().remove(KEY_KEY_BLOB).apply()
        } else {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, masterKey())
            val iv = cipher.iv
            val sealed = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
            val blob = Base64.encodeToString(iv, Base64.NO_WRAP) + ":" +
                Base64.encodeToString(sealed, Base64.NO_WRAP)
            prefs.edit().putString(KEY_KEY_BLOB, blob).apply()
        }
        true
    } catch (e: Throwable) {
        // 机器异常（厂商 ROM 砍掉 Keystore 之类）：只留内存，说一句实话
        Log.w("PaceAi", "key store failed: ${e.message}")
        false
    }

    private fun readStoredKey(): String {
        return try {
            val blob = prefs.getString(KEY_KEY_BLOB, null) ?: return ""
            val parts = blob.split(":", limit = 2)
            if (parts.size != 2) return ""
            val iv = Base64.decode(parts[0], Base64.NO_WRAP)
            if (iv.size != GCM_IV_BYTES) return ""
            val sealed = Base64.decode(parts[1], Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, masterKey(), GCMParameterSpec(GCM_TAG_BITS, iv))
            String(cipher.doFinal(sealed), Charsets.UTF_8)
        } catch (e: Throwable) {
            Log.w("PaceAi", "key read failed: ${e.message}")
            ""
        }
    }
}
