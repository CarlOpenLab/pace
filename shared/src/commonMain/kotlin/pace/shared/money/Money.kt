package pace.shared.money

/**
 * 金额规则实现（docs/DATA_MODEL.md 第 1 节）。
 * 全程整数运算，禁止 Double 参与账本计算。
 */
object Money {

    const val MAX_AMOUNT_MINOR: Long = 10_000_000_000_000L // 10^13 分 ≈ 1 亿元

    private val AMOUNT_TEXT = Regex("""\+?(\d{1,11})(?:\.(\d{1,2}))?""")

    /** 严格解析用户输入的十进制金额文本为最小货币单位；非法输入返回 null（M2/M3）。 */
    fun parseToMinor(text: String): Long? {
        val trimmed = text.trim()
        val match = AMOUNT_TEXT.matchEntire(trimmed) ?: return null
        val whole = match.groupValues[1]
        val fraction = match.groupValues[2]
        if (whole.isEmpty()) return null
        val wholeMinor = whole.toLongOrNull()?.times(100L) ?: return null
        val fractionMinor = when {
            fraction.isEmpty() -> 0L
            else -> fraction.padEnd(2, '0').take(2).toLongOrNull() ?: return null
        }
        val total = wholeMinor + fractionMinor
        return if (total in 1..MAX_AMOUNT_MINOR) total else null
    }

    /** 最小货币单位 → 十进制展示字符串（两位小数），负数输出 `-12.34`。 */
    fun formatMinor(amountMinor: Long): String {
        val sign = if (amountMinor < 0) "-" else ""
        val abs = if (amountMinor < 0) -amountMinor else amountMinor
        val whole = abs / 100
        val cents = abs % 100
        return "$sign$whole.${cents.toString().padStart(2, '0')}"
    }

    /** 带货币符号展示；CNY 使用 ¥，其余使用 ISO 码前缀。 */
    fun display(amountMinor: Long, currency: String): String {
        val symbol = when (currency.uppercase()) {
            "CNY" -> "¥"
            "USD" -> "$"
            "EUR" -> "€"
            "JPY" -> "JPY¥" // 日元最小单位即为元，此处仍按两位展示，v1 不做多币种换算
            else -> currency.uppercase()
        }
        return "$symbol${formatMinor(amountMinor)}"
    }
}
