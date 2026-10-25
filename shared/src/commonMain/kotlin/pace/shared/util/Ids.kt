package pace.shared.util

import kotlin.random.Random

/** 稳定 ID 与指纹（docs/DATA_MODEL.md 第 5 节）。 */
object Ids {

    /** UUID v4，纯 kotlin.random 实现，跨平台一致格式。 */
    fun newUuid(): String {
        val bytes = Random.Default.nextBytes(16)
        bytes[6] = ((bytes[6].toInt() and 0x0F) or 0x40).toByte() // version 4
        bytes[8] = ((bytes[8].toInt() and 0x3F) or 0x80).toByte() // variant 10xx
        val hex = bytes.joinToString("") { (it.toInt() and 0xFF).toString(16).padStart(2, '0') }
        return "${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}"
    }

    /**
     * 指纹 = FNV-1a 64 对规范化串哈希（fp1_ 前缀）。
     * 规范化串使用纯整数/字符串，任何平台实现结果一致。
     */
    fun fingerprint(
        type: String,
        amountMinor: Long,
        currency: String,
        localDate: String,
        category: String,
        account: String,
        note: String
    ): String {
        val canonical = "v1|$type|$amountMinor|$currency|$localDate|$category|$account|$note"
        var hash = 0xCBF29CE484222325UL
        for (char in canonical) {
            hash = hash xor char.code.toULong()
            hash *= 0x100000001B3UL
        }
        return "fp1_" + hash.toString(16).padStart(16, '0')
    }
}
