package pace.shared

import app.cash.sqldelight.db.SqlDriver
import pace.shared.budget.BudgetEngine
import pace.shared.classifier.KeywordClassifier
import pace.shared.datetime.PaceDates
import pace.shared.db.Budget_rules as DbBudgetRule
import pace.shared.db.Categories as DbCategory
import pace.shared.db.PaceDatabase
import pace.shared.db.Transactions as DbTransaction
import pace.shared.export.Exporters
import pace.shared.importer.Importer
import pace.shared.model.ApplyImportResult
import pace.shared.model.BudgetRule
import pace.shared.model.Category
import pace.shared.model.DateRange
import pace.shared.model.ErrorCodes
import pace.shared.model.ImportPreview
import pace.shared.model.RangeStats
import pace.shared.model.SaveResult
import pace.shared.model.SaveTxnInput
import pace.shared.model.TodayOverview
import pace.shared.model.Transaction
import pace.shared.model.TxnSource
import pace.shared.model.TxnType
import pace.shared.money.Money
import pace.shared.statistics.StatsEngine
import pace.shared.util.Ids
import pace.shared.validation.Validators

/**
 * 共享账本门面 API。Android 与 iOS 通过该类完成全部账本操作；
 * 公开方法只使用 String/Long/Boolean/List 等易桥接类型，全部同步、离线可用。
 */
class LedgerApi internal constructor(
    private val database: PaceDatabase,
    private val clock: () -> Long
) {

    constructor(driver: SqlDriver) : this(PaceDatabase(driver), { PaceDates.nowEpochMillis() })

    private val defaultCategories = listOf(
        "餐饮" to TxnType.EXPENSE, "交通" to TxnType.EXPENSE, "购物" to TxnType.EXPENSE,
        "住房" to TxnType.EXPENSE, "娱乐" to TxnType.EXPENSE, "医疗" to TxnType.EXPENSE,
        "教育" to TxnType.EXPENSE, "人情社交" to TxnType.EXPENSE, "其他" to TxnType.EXPENSE,
        "工资" to TxnType.INCOME, "理财" to TxnType.INCOME, "转账" to TxnType.TRANSFER
    )

    init {
        if (categoryCount() == 0L) {
            seedDefaultCategories()
        }
    }

    // ---------- 分类 ----------

    private fun seedDefaultCategories() {
        defaultCategories.forEachIndexed { index, (name, kind) ->
            insertCategoryRow(Ids.newUuid(), name, kind, index, 0L)
        }
    }

    private fun insertCategoryRow(id: String, name: String, kind: String, sortOrder: Int, usageCount: Long) {
        database.categoriesQueries.insertOrReplaceCategory(id, name, kind, sortOrder.toLong(), usageCount)
    }

    fun categories(): List<Category> =
        database.categoriesQueries.selectAllCategories().executeAsList().map { it.toModel() }

    fun addCategory(name: String, kind: String): Category? {
        val trimmed = name.trim()
        if (trimmed.isEmpty() || trimmed.length > 20) return null
        if (trimmed == KeywordClassifier.FALLBACK_CATEGORY) return null
        if (database.categoriesQueries.selectCategoryByName(trimmed).executeAsList().isNotEmpty()) return null
        val safeKind = if (TxnType.isValid(kind)) kind else TxnType.EXPENSE
        val sortOrder = (categories().maxOfOrNull { it.sortOrder } ?: -1) + 1
        val category = Category(Ids.newUuid(), trimmed, safeKind, sortOrder, 0L)
        insertCategoryRow(category.id, category.name, category.kind, category.sortOrder, category.usageCount)
        return category
    }

    private fun categoryCount(): Long =
        database.categoriesQueries.countAllCategories().executeAsList().first()

    private fun knownCategoryNames(): Set<String> = categories().map { it.name }.toSet()

    // ---------- 账单 ----------

    fun transaction(id: String): Transaction? =
        database.transactionsQueries.selectById(id).executeAsList().firstOrNull()?.toModel()

    fun transactions(fromLocalDate: String, toLocalDate: String): List<Transaction> =
        database.transactionsQueries.selectByLocalDateRange(fromLocalDate, toLocalDate)
            .executeAsList().map { it.toModel() }

    fun allTransactions(): List<Transaction> =
        database.transactionsQueries.selectAll().executeAsList().map { it.toModel() }

    /** 关键字里转义 LIKE 通配符（% _ \），让「100%」搜的是字面量而不是任意串。 */
    private fun escapeLike(keyword: String): String =
        keyword.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")

    fun searchTransactions(keyword: String): List<Transaction> {
        val trimmed = keyword.trim()
        if (trimmed.isEmpty()) return emptyList()
        val pattern = "%${escapeLike(trimmed)}%"
        return database.transactionsQueries.searchByKeyword(pattern, pattern, pattern)
            .executeAsList().map { it.toModel() }
    }

    /**
     * 新增或编辑账单。校验失败返回 errorCode；同指纹重复返回 DUPLICATE_FINGERPRINT，
     * 用户明确继续时以 input.forceSave = true 重试（U2：防双击，同时不阻止真实重复）。
     */
    fun saveTransaction(input: SaveTxnInput): SaveResult {
        // 1. 基础校验
        Validators.validateType(input.type)?.let { return SaveResult(null, it) }
        val amountMinor = Money.parseToMinor(input.amountText)
            ?: return SaveResult(null, ErrorCodes.INVALID_AMOUNT)
        Validators.validateNote(input.note)?.let { return SaveResult(null, it) }
        Validators.validateTimezone(input.timezoneId)?.let { return SaveResult(null, it) }

        // 2. 时间与归属日
        val now = clock()
        val occurredAt = if (input.occurredAtEpochMillis > 0) input.occurredAtEpochMillis else now
        val localDate = input.localDate.ifBlank {
            PaceDates.localDateFor(occurredAt, input.timezoneId) ?: return SaveResult(null, ErrorCodes.INVALID_DATE)
        }
        Validators.validateLocalDate(localDate)?.let { return SaveResult(null, it) }

        // 3. 分类
        val category = input.category.ifBlank { KeywordClassifier.FALLBACK_CATEGORY }
        Validators.validateCategoryName(category, knownCategoryNames())?.let { return SaveResult(null, it) }

        // 4. 退款关联（R1/R2）
        var refundOfId: String? = null
        if (input.type == TxnType.REFUND) {
            refundOfId = input.refundOfId?.takeIf { it.isNotBlank() }
                ?: return SaveResult(null, ErrorCodes.REFUND_MISSING_ORIGINAL)
            val original = transaction(refundOfId)
                ?: return SaveResult(null, ErrorCodes.REFUND_ORIGINAL_NOT_FOUND)
            if (original.type != TxnType.EXPENSE) {
                return SaveResult(null, ErrorCodes.REFUND_ORIGINAL_NOT_FOUND)
            }
        }

        // 5. 归一化：收入/转账永不计入预算
        val countInBudget = input.countInBudget &&
            (input.type == TxnType.EXPENSE || input.type == TxnType.REFUND)

        // 6. 指纹与重复检测
        val fingerprint = Ids.fingerprint(
            input.type, amountMinor, input.currency.uppercase(), localDate, category, input.account, input.note
        )
        if (!input.forceSave) {
            val sameFingerprint = database.transactionsQueries
                .selectByFingerprint(fingerprint).executeAsList().firstOrNull()
            if (sameFingerprint != null && sameFingerprint.id != input.id) {
                return SaveResult(null, ErrorCodes.DUPLICATE_FINGERPRINT)
            }
        }

        // 7. 写入（新增或编辑；id 指向已删除账单时按 upsert 恢复，支撑「撤销」流程）
        val existing = input.id?.let { transaction(it) }
        val id = existing?.id ?: input.id ?: Ids.newUuid()
        val createdAt = existing?.createdAtEpochMillis ?: now
        val txn = Transaction(
            id = id,
            type = input.type,
            amountMinor = amountMinor,
            currency = input.currency.uppercase().ifBlank { "CNY" },
            category = category,
            account = input.account,
            note = input.note,
            occurredAtEpochMillis = occurredAt,
            localDate = localDate,
            timezoneId = input.timezoneId,
            countInBudget = countInBudget,
            refundOfId = refundOfId,
            source = TxnSource.normalize(input.source),
            fingerprint = fingerprint,
            createdAtEpochMillis = createdAt,
            updatedAtEpochMillis = now
        )
        insertTransactionRow(txn)
        database.categoriesQueries.incrementCategoryUsage(category)
        return SaveResult(txn, null)
    }

    private fun insertTransactionRow(txn: Transaction) {
        database.transactionsQueries.insertOrReplace(
            txn.id, txn.type, txn.amountMinor, txn.currency, txn.category, txn.account, txn.note,
            txn.occurredAtEpochMillis, txn.localDate, txn.timezoneId, if (txn.countInBudget) 1L else 0L,
            txn.refundOfId, txn.source, txn.fingerprint, txn.createdAtEpochMillis, txn.updatedAtEpochMillis
        )
    }

    /** 删除并返回被删账单（供 UI 撤销：重新 save 即可恢复，U3）。 */
    fun deleteTransaction(id: String): Transaction? {
        val existing = transaction(id) ?: return null
        database.transactionsQueries.deleteById(id)
        return existing
    }

    // ---------- 预算 ----------

    fun budgetFor(localDate: String): BudgetRule? =
        BudgetEngine.budgetFor(budgetHistory(), localDate)

    fun budgetHistory(): List<BudgetRule> =
        database.budgetRulesQueries.selectAllBudgetRules().executeAsList().map { it.toModel() }

    /**
     * 设置每日预算：追加生效规则，不重写历史（BUDGET_RULES 第 4 节）。
     * 返回错误码；成功返回 null。
     */
    fun setBudget(dailyAmountText: String, currency: String, effectiveFromIso: String): String? {
        val amount = Money.parseToMinor(dailyAmountText)
            ?: return ErrorCodes.INVALID_AMOUNT
        Validators.validateLocalDate(effectiveFromIso)?.let { return it }
        val rule = BudgetRule(
            id = Ids.newUuid(),
            dailyAmountMinor = amount,
            currency = currency.uppercase().ifBlank { "CNY" },
            effectiveFromLocalDate = effectiveFromIso,
            createdAtEpochMillis = clock()
        )
        insertBudgetRuleRow(rule)
        return null
    }

    private fun insertBudgetRuleRow(rule: BudgetRule) {
        database.budgetRulesQueries.insertOrReplaceBudgetRule(
            rule.id, rule.dailyAmountMinor, rule.currency, rule.effectiveFromLocalDate, rule.createdAtEpochMillis
        )
    }

    // ---------- 预算视图与统计 ----------

    fun todayOverview(todayIso: String): TodayOverview =
        BudgetEngine.todayOverview(allTransactions(), budgetHistory(), todayIso)

    fun weekRange(todayIso: String): DateRange? = StatsEngine.weekRange(todayIso)

    fun monthRange(todayIso: String): DateRange? = StatsEngine.monthRange(todayIso)

    fun rangeStats(fromLocalDate: String, toLocalDate: String): RangeStats =
        StatsEngine.rangeStats(allTransactions(), budgetHistory(), fromLocalDate, toLocalDate, StatsEngine::nextDay)

    // ---------- 导出 ----------

    fun exportJson(timezoneId: String): String {
        val envelope = Exporters.buildEnvelope(
            transactions = allTransactions(),
            categories = categories(),
            budgetRules = budgetHistory(),
            timezoneId = timezoneId,
            defaultCurrency = "CNY",
            exportedAtEpochMillis = clock()
        )
        return Exporters.exportJson(envelope)
    }

    fun exportCsv(): String = Exporters.exportCsv(allTransactions())

    // ---------- 导入 ----------

    /** 预览：整体校验 + 重复统计，不写库。 */
    fun previewImport(jsonText: String): ImportPreview {
        val outcome = Importer.parseAndValidate(jsonText)
        return when (outcome) {
            is Importer.ParseOutcome.Invalid -> ImportPreview(
                transactionCount = 0, categoryCount = 0, budgetRuleCount = 0,
                firstLocalDate = null, lastLocalDate = null, duplicateCount = 0,
                valid = false, errors = outcome.errors
            )
            is Importer.ParseOutcome.Ok -> {
                val existingIds = allTransactions().map { it.id }.toSet()
                val existingFingerprints = allTransactions().map { it.fingerprint }.toSet()
                val dates = outcome.envelope.transactions.map { it.localDate }.sorted()
                ImportPreview(
                    transactionCount = outcome.envelope.transactions.size.toLong(),
                    categoryCount = outcome.envelope.categories.size.toLong(),
                    budgetRuleCount = outcome.envelope.budgetRules.size.toLong(),
                    firstLocalDate = dates.firstOrNull(),
                    lastLocalDate = dates.lastOrNull(),
                    duplicateCount = Importer.duplicateCount(outcome.envelope, existingIds, existingFingerprints),
                    valid = true,
                    errors = emptyList()
                )
            }
        }
    }

    /**
     * 事务性导入：MERGE 按 id/指纹去重跳过；REPLACE 清空后整体写入。
     * 任何异常整体回滚，现有账本不变（I2）。
     */
    fun applyImport(jsonText: String, mode: String): ApplyImportResult {
        val outcome = Importer.parseAndValidate(jsonText)
        val envelope = when (outcome) {
            is Importer.ParseOutcome.Invalid ->
                return ApplyImportResult(false, 0, 0, ErrorCodes.IMPORT_VALIDATION_FAILED, outcome.errors)
            is Importer.ParseOutcome.Ok -> outcome.envelope
        }
        val existingIds = allTransactions().map { it.id }.toSet()
        val existingFingerprints = allTransactions().map { it.fingerprint }.toSet()
        val replace = mode == "REPLACE"
        var inserted = 0L
        var skipped = 0L
        try {
            database.transaction {
                if (replace) {
                    database.transactionsQueries.deleteAll()
                    database.budgetRulesQueries.deleteAllBudgetRules()
                    database.categoriesQueries.deleteAllCategories()
                }
                for (category in envelope.categories) {
                    if (!replace) {
                        val exists = database.categoriesQueries
                            .selectCategoryByName(category.name).executeAsList().isNotEmpty()
                        if (exists) {
                            continue
                        }
                    }
                    insertCategoryRow(category.id, category.name, category.kind, category.sortOrder, category.usageCount)
                }
                if (replace && envelope.categories.isEmpty()) {
                    seedDefaultCategories()
                }
                for (rule in envelope.budgetRules) {
                    if (!replace) {
                        val exists = database.budgetRulesQueries
                            .selectBudgetRuleById(rule.id).executeAsList().isNotEmpty()
                        if (exists) {
                            continue
                        }
                    }
                    insertBudgetRuleRow(rule)
                }
                // inserted/skipped 只统计账单（与 ImportPreview 口径一致）
                for (txn in envelope.transactions) {
                    if (!replace) {
                        if (txn.id in existingIds || txn.fingerprint in existingFingerprints) {
                            skipped += 1
                            continue
                        }
                    }
                    insertTransactionRow(txn)
                    inserted += 1
                }
            }
        } catch (e: Throwable) {
            return ApplyImportResult(false, 0, 0, ErrorCodes.IMPORT_VALIDATION_FAILED, listOf(e.message ?: "ROLLBACK"))
        }
        return ApplyImportResult(true, inserted, skipped, null, emptyList())
    }

    // ---------- 其他 ----------

    fun suggestCategory(text: String, type: String): String =
        KeywordClassifier.suggestCategory(text, type)

    /** 清空全部数据并恢复默认分类（U5：调用方必须先完成二次确认）。 */
    fun clearAllData(): Boolean = try {
        database.transaction {
            database.transactionsQueries.deleteAll()
            database.budgetRulesQueries.deleteAllBudgetRules()
            database.categoriesQueries.deleteAllCategories()
        }
        seedDefaultCategories()
        true
    } catch (_: Throwable) {
        false
    }

    // ---------- 行映射 ----------

    private fun DbTransaction.toModel(): Transaction = Transaction(
        id = id,
        type = type,
        amountMinor = amountMinor,
        currency = currency,
        category = category,
        account = account,
        note = note,
        occurredAtEpochMillis = occurredAtEpochMillis,
        localDate = localDate,
        timezoneId = timezoneId,
        countInBudget = countInBudget != 0L,
        refundOfId = refundOfId,
        source = source,
        fingerprint = fingerprint,
        createdAtEpochMillis = createdAtEpochMillis,
        updatedAtEpochMillis = updatedAtEpochMillis
    )

    private fun DbCategory.toModel(): Category = Category(
        id = id,
        name = name,
        kind = kind,
        sortOrder = sortOrder.toInt(),
        usageCount = usageCount
    )

    private fun DbBudgetRule.toModel(): BudgetRule = BudgetRule(
        id = id,
        dailyAmountMinor = dailyAmountMinor,
        currency = currency,
        effectiveFromLocalDate = effectiveFromLocalDate,
        createdAtEpochMillis = createdAtEpochMillis
    )
}
