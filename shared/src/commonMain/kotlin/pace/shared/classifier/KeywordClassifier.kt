package pace.shared.classifier

import pace.shared.model.TxnType

/**
 * 本地关键词分类（从 Web 原型 src/lib/rules.ts + classifier.ts 提取的确定性规则）。
 * 完全离线，属于「本地隐私模式」允许的解析能力；不发送任何数据。
 */
object KeywordClassifier {

    private data class Rule(
        val name: String,
        val category: String,
        val type: String?,
        val keywords: List<String>
    )

    val FALLBACK_CATEGORY = "其他"

    private val RULES = listOf(
        Rule("工资收入", "工资", TxnType.INCOME, listOf("工资", "薪资", "奖金", "薪酬")),
        Rule("理财收入", "理财", TxnType.INCOME, listOf("利息", "收益", "分红", "理财")),
        Rule("餐饮关键词", "餐饮", TxnType.EXPENSE, listOf("美团", "饿了么", "肯德基", "麦当劳", "星巴克", "餐饮", "午饭", "晚饭", "早饭", "早餐", "午餐", "晚餐", "咖啡", "奶茶", "外卖", "餐厅", "食堂")),
        Rule("交通关键词", "交通", TxnType.EXPENSE, listOf("滴滴", "地铁", "公交", "火车", "机票", "加油", "打车", "出租车", "高铁", "共享单车", "停车")),
        Rule("购物关键词", "购物", TxnType.EXPENSE, listOf("淘宝", "京东", "拼多多", "天猫", "超市", "便利店", "网购")),
        Rule("住房关键词", "住房", TxnType.EXPENSE, listOf("房租", "物业", "水费", "电费", "燃气", "宽带", "房贷")),
        Rule("娱乐关键词", "娱乐", TxnType.EXPENSE, listOf("电影", "游戏", "视频会员", "音乐", "演出", "旅游")),
        Rule("医疗关键词", "医疗", TxnType.EXPENSE, listOf("医院", "药店", "挂号", "门诊", "体检")),
        Rule("教育关键词", "教育", TxnType.EXPENSE, listOf("学费", "培训", "课程", "书本", "考试")),
        Rule("人情社交", "人情社交", TxnType.EXPENSE, listOf("红包", "礼物", "聚餐", "随礼", "份子")),
        Rule("转账类", "转账", TxnType.TRANSFER, listOf("转账", "还款", "信用卡", "提现", "银行卡"))
    )

    /** 对记账文本（备注 + 分类输入等拼接）给出本地分类建议；无命中返回「其他」。 */
    fun suggestCategory(text: String, type: String): String {
        val normalized = text.lowercase()
        val typedRules = RULES.filter { it.type == type }
        for (rule in typedRules) {
            if (rule.keywords.any { normalized.contains(it.lowercase()) }) {
                return rule.category
            }
        }
        return FALLBACK_CATEGORY
    }
}
