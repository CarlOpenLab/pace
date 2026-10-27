package pace.app.ai

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 远端草稿的本地复算规则（docs/AI_PRIVACY.md §3）：
 * 金额、日期、分类一律本地复算，不信任模型给的数值。
 */
class RemoteDraftMapperTest {

    private val today = "2026-10-28"

    private fun map(
        type: String? = "EXPENSE",
        amountText: String? = "28",
        dateText: String? = null,
        localDate: String? = today,
        category: String? = "餐饮",
        note: String? = "午饭",
        countInBudget: Boolean? = true,
        missingFields: List<String>? = emptyList()
    ) = RemoteDraftMapper.map(
        localId = "d-001",
        type = type,
        amountText = amountText,
        currency = "CNY",
        dateText = dateText,
        localDate = localDate,
        category = category,
        note = note,
        account = null,
        countInBudget = countInBudget,
        missingFields = missingFields,
        todayIso = today
    )

    @Test
    fun clean_draft_passes_through() {
        val draft = map()
        assertEquals(2800L, draft.amountMinor)
        assertEquals(today, draft.localDate)
        assertEquals("餐饮", draft.category)
        assertTrue(draft.missingFields.isEmpty())
        assertTrue(draft.countInBudget)
    }

    @Test
    fun amount_recomputed_locally() {
        // 模型给的 amountText 才算数；解析不出就标缺金额
        assertEquals(2850L, map(amountText = "28.5").amountMinor)
        val missing = map(amountText = "abc")
        assertEquals(0L, missing.amountMinor)
        assertTrue(DraftMissing.AMOUNT in missing.missingFields)
        assertEquals("", map(amountText = null).let { it.amountText })
    }

    @Test
    fun invalid_date_falls_back_to_today() {
        assertEquals(today, map(localDate = "2026-13-99").localDate)
        assertEquals(today, map(localDate = "").localDate)
        val noDateAtAll = map(localDate = null)
        assertEquals(today, noDateAtAll.localDate)
        // 模型压根没提日期不算「需要日期」；给了但非法才算
        assertFalse(DraftMissing.DATE in noDateAtAll.missingFields)
        assertTrue(DraftMissing.DATE in map(localDate = "").missingFields)
    }

    @Test
    fun relative_word_wins_over_model_date() {
        // 用户说的「昨天」比模型算的绝对日期可靠
        assertEquals("2026-10-27", map(dateText = "昨天", localDate = today).localDate)
        assertEquals("2026-10-26", map(dateText = "前天", localDate = today).localDate)
        assertEquals(today, map(dateText = "今天", localDate = "2026-01-01").localDate)
        assertNull(DraftWhitelist.relativeDate("上周五", today))
    }

    @Test
    fun unknown_category_falls_back_to_classifier() {
        // 备注没有关键词 → 兜底「其他」
        assertEquals("其他", map(category = "不认识的分类", note = "随便什么").category)
        // 备注里有交通词就落到交通
        assertEquals("交通", map(category = "??", note = "打车回家").category)
        // 备注有餐饮词也照落：分类器说了算
        assertEquals("餐饮", map(category = "不认识的分类").category)
    }

    @Test
    fun bad_type_defaults_to_expense() {
        assertEquals("EXPENSE", map(type = "GUESS").type)
        assertEquals("INCOME", map(type = "INCOME").type)
        // 非支出不算入预算，模型给的 true 也被压掉
        assertFalse(map(type = "INCOME", countInBudget = true).countInBudget)
    }

    @Test
    fun missing_fields_normalized() {
        // 白名单外的标记被丢弃
        val draft = map(missingFields = listOf("HALLUCINATION"))
        assertTrue(draft.missingFields.isEmpty())
        val withAmount = map(amountText = "0", missingFields = emptyList())
        assertTrue(DraftMissing.AMOUNT in withAmount.missingFields)
    }

    @Test
    fun example_prompt_is_coherent() {
        assertTrue(AiDraftClient.exampleIsCoherent(today))
        // 示例里的 localDate 跟 todayIso 走，谁改坏了当场炸
        assertFalse(AiDraftClient.exampleIsCoherent("not-a-date"))
    }

    @Test
    fun content_and_json_extraction() {
        val chat = """
            {"choices":[{"message":{"content":"{\"draftVersion\":1,\"drafts\":[],\"parseErrors\":[]}"}}]}
        """.trimIndent()
        assertEquals(
            "{\"draftVersion\":1,\"drafts\":[],\"parseErrors\":[]}",
            AiDraftClient.contentText(chat)
        )
        assertEquals(
            "{\"a\":1}",
            AiDraftClient.extractJSONObject("前置说明 {\"a\":1} 后置说明")
        )
        assertNull(AiDraftClient.extractJSONObject("没有花括号"))
        assertTrue(AiDraftClient.parseDraftsJson("{\"drafts\":[]}", today).isEmpty())
    }
}
