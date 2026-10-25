package pace.shared.datetime

import kotlinx.datetime.Clock
import kotlinx.datetime.DateTimeUnit
import kotlinx.datetime.Instant
import kotlinx.datetime.LocalDate
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.daysUntil
import kotlinx.datetime.isoDayNumber
import kotlinx.datetime.minus
import kotlinx.datetime.plus
import kotlinx.datetime.toLocalDateTime

/**
 * 时区、归属日和午夜边界规则（docs/DATA_MODEL.md 第 6 节、docs/EDGE_CASES.md 第 2 节）。
 * 业务逻辑不直接读取系统时间做判断；「今天」由调用方传入。
 */
object PaceDates {

    const val MIN_LOCAL_DATE = "1970-01-01"
    const val MAX_LOCAL_DATE = "2100-12-31"

    private val LOCAL_DATE = Regex("""\d{4}-\d{2}-\d{2}""")

    fun nowEpochMillis(): Long = Clock.System.now().toEpochMilliseconds()

    fun currentTimeZoneId(): String = TimeZone.currentSystemDefault().id

    fun isValidTimeZoneId(timezoneId: String): Boolean = try {
        TimeZone.of(timezoneId)
        true
    } catch (_: Throwable) {
        false
    }

    /** 校验 localDate：ISO 格式 + 真实存在的日期 + 1970-01-01..2100-12-31 范围。 */
    fun isValidLocalDate(iso: String): Boolean {
        if (!LOCAL_DATE.matchEntire(iso).let { it != null }) return false
        val date = try {
            LocalDate.parse(iso)
        } catch (_: Throwable) {
            return false
        }
        return date.toString() == iso && iso in MIN_LOCAL_DATE..MAX_LOCAL_DATE
    }

    /** Instant + 时区 → 归属日（D1/D2）。时区非法返回 null。 */
    fun localDateFor(epochMillis: Long, timezoneId: String): String? = try {
        Instant.fromEpochMilliseconds(epochMillis).toLocalDateTime(TimeZone.of(timezoneId)).date.toString()
    } catch (_: Throwable) {
        null
    }

    /** 归属日 + 时区 → 该日 HH:mm 展示（用于账单列表），失败返回空串。 */
    fun timeOfDay(epochMillis: Long, timezoneId: String): String {
        val time = try {
            Instant.fromEpochMilliseconds(epochMillis).toLocalDateTime(TimeZone.of(timezoneId)).time
        } catch (_: Throwable) {
            return ""
        }
        return "${time.hour.toString().padStart(2, '0')}:${time.minute.toString().padStart(2, '0')}"
    }

    /** CSV time 列：按账单保存的时区还原 HHmmss。 */
    fun timeCompact(epochMillis: Long, timezoneId: String): String {
        val time = try {
            Instant.fromEpochMilliseconds(epochMillis).toLocalDateTime(TimeZone.of(timezoneId)).time
        } catch (_: Throwable) {
            return ""
        }
        return time.hour.toString().padStart(2, '0') +
            time.minute.toString().padStart(2, '0') +
            time.second.toString().padStart(2, '0')
    }

    fun todayIso(timezoneId: String): String? = localDateFor(nowEpochMillis(), timezoneId)

    /** 周一为一周开始；返回包含 [iso] 的那周的周一。 */
    fun weekStartIso(iso: String): String? {
        val date = try {
            LocalDate.parse(iso)
        } catch (_: Throwable) {
            return null
        }
        val monday = date.minus(date.dayOfWeek.isoDayNumber - 1, DateTimeUnit.DAY)
        return monday.toString()
    }

    fun monthStartIso(iso: String): String? = try {
        LocalDate.parse(iso).let { LocalDate(it.year, it.monthNumber, 1).toString() }
    } catch (_: Throwable) {
        null
    }

    fun nextMonthStartIso(iso: String): String? = try {
        LocalDate.parse(iso).let {
            it.plus(1, DateTimeUnit.MONTH).let { firstOfNext ->
                LocalDate(firstOfNext.year, firstOfNext.monthNumber, 1).toString()
            }
        }
    } catch (_: Throwable) {
        null
    }

    fun nextDayIso(iso: String): String? = try {
        LocalDate.parse(iso).plus(1, DateTimeUnit.DAY).toString()
    } catch (_: Throwable) {
        null
    }

    /** 排序用的日期差：[from, to] 闭区间天数；非法返回 -1。 */
    fun daysBetweenInclusive(from: String, to: String): Int = try {
        LocalDate.parse(from).daysUntil(LocalDate.parse(to)) + 1
    } catch (_: Throwable) {
        -1
    }
}
