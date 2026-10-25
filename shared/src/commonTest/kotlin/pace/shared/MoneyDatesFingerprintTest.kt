package pace.shared

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import pace.shared.datetime.PaceDates
import pace.shared.model.BudgetRule
import pace.shared.model.Transaction
import pace.shared.model.TxnType
import pace.shared.money.Money
import pace.shared.util.Ids

fun txn(
    id: String,
    type: String = TxnType.EXPENSE,
    amountMinor: Long = 1000L,
    localDate: String = "2026-10-26",
    countInBudget: Boolean = true,
    category: String = "餐饮",
    note: String = "",
    occurredAtEpochMillis: Long = 1_792_000_000_000L
): Transaction = Transaction(
    id = id,
    type = type,
    amountMinor = amountMinor,
    currency = "CNY",
    category = category,
    account = "现金",
    note = note,
    occurredAtEpochMillis = occurredAtEpochMillis,
    localDate = localDate,
    timezoneId = "Asia/Shanghai",
    countInBudget = countInBudget,
    refundOfId = if (type == TxnType.REFUND) "original" else null,
    source = "MANUAL",
    fingerprint = "fp1_test_$id",
    createdAtEpochMillis = occurredAtEpochMillis,
    updatedAtEpochMillis = occurredAtEpochMillis
)

fun rule(dailyAmountMinor: Long, from: String, createdAt: Long = 0L): BudgetRule =
    BudgetRule("rule-$from-$dailyAmountMinor-$createdAt", dailyAmountMinor, "CNY", from, createdAt)

class MoneyTest {

    @Test
    fun m1_integer_sum_no_float_error() {
        // 0.1 元 + 0.2 元 = 30 分，不允许出现浮点误差
        val a = Money.parseToMinor("0.1")!!
        val b = Money.parseToMinor("0.2")!!
        assertEquals(10L, a)
        assertEquals(20L, b)
        assertEquals(30L, a + b)
        assertEquals("0.30", Money.formatMinor(a + b))
    }

    @Test
    fun m2_reject_three_decimals() {
        assertNull(Money.parseToMinor("10.005"))
    }

    @Test
    fun m3_reject_zero_and_negative() {
        assertNull(Money.parseToMinor("0"))
        assertNull(Money.parseToMinor("0.00"))
        assertNull(Money.parseToMinor("-5"))
        assertNull(Money.parseToMinor(""))
        assertNull(Money.parseToMinor("abc"))
        assertNull(Money.parseToMinor("1,000"))
    }

    @Test
    fun m4_max_allowed() {
        assertEquals(9999999999999L, Money.parseToMinor("99999999999.99"))
    }

    @Test
    fun m5_over_max_rejected() {
        assertNull(Money.parseToMinor("100000000000"))
    }

    @Test
    fun m6_negative_display_keeps_sign() {
        assertEquals("-38.00", Money.formatMinor(-3800))
        assertEquals("¥38.00", Money.display(3800, "CNY"))
    }

    @Test
    fun accept_single_decimal_and_integers() {
        assertEquals(2800L, Money.parseToMinor("28"))
        assertEquals(2850L, Money.parseToMinor("28.5"))
        assertEquals(2850L, Money.parseToMinor("28.50"))
        assertEquals(2800L, Money.parseToMinor(" 28 "))
    }
}

class DatesTest {

    @Test
    fun d1_d2_local_date_follows_timezone() {
        // 2026-10-25 00:00 UTC = 上海 08:00（同日）；纽约 2026-10-24 20:00（前一天）
        val epoch = 1_792_886_400_000L
        val shanghai = PaceDates.localDateFor(epoch, "Asia/Shanghai")!!
        val utc = PaceDates.localDateFor(epoch, "UTC")!!
        val newYork = PaceDates.localDateFor(epoch, "America/New_York")!!
        assertEquals("2026-10-25", utc)
        assertEquals("2026-10-25", shanghai)
        assertEquals("2026-10-24", newYork)
    }

    @Test
    fun d5_invalid_local_dates_rejected() {
        assertFalse(PaceDates.isValidLocalDate("1969-12-31"))
        assertFalse(PaceDates.isValidLocalDate("2101-01-01"))
        assertFalse(PaceDates.isValidLocalDate("2026-13-01"))
        assertFalse(PaceDates.isValidLocalDate("2026-02-30"))
        assertFalse(PaceDates.isValidLocalDate("2026/10/26"))
        assertTrue(PaceDates.isValidLocalDate("2024-02-29"))
        assertFalse(PaceDates.isValidLocalDate("2026-02-29"))
    }

    @Test
    fun week_range_starts_monday() {
        // 2026-10-28 是周三；本周 = 2026-10-26（周一）.. 2026-11-01（周日）
        val week = pace.shared.statistics.StatsEngine.weekRange("2026-10-28")!!
        assertEquals("2026-10-26", week.from)
        assertEquals("2026-11-01", week.to)
    }

    @Test
    fun month_range() {
        val month = pace.shared.statistics.StatsEngine.monthRange("2026-02-10")!!
        assertEquals("2026-02-01", month.from)
        assertEquals("2026-02-28", month.to)
        val month2 = pace.shared.statistics.StatsEngine.monthRange("2024-02-10")!!
        assertEquals("2024-02-29", month2.to)
    }

    @Test
    fun next_day_crosses_month_and_year() {
        assertEquals("2026-11-01", pace.shared.statistics.StatsEngine.nextDay("2026-10-31"))
        assertEquals("2027-01-01", pace.shared.statistics.StatsEngine.nextDay("2026-12-31"))
    }
}

class FingerprintTest {

    @Test
    fun stable_and_input_sensitive() {
        val a = Ids.fingerprint("EXPENSE", 2800, "CNY", "2026-10-25", "餐饮", "微信支付", "午饭")
        val b = Ids.fingerprint("EXPENSE", 2800, "CNY", "2026-10-25", "餐饮", "微信支付", "午饭")
        assertEquals(a, b)
        assertTrue(a.startsWith("fp1_"))
        val c = Ids.fingerprint("EXPENSE", 2801, "CNY", "2026-10-25", "餐饮", "微信支付", "午饭")
        assertTrue(a != c)
    }

    @Test
    fun uuid_v4_shape() {
        val id = Ids.newUuid()
        assertTrue(Regex("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$").matches(id))
    }
}
