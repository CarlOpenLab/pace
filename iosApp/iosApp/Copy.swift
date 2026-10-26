import Foundation

/// Pace 全量用户可见文案（中文）。
///
/// 唯一来源：`pace-copy-round2.md`（第二轮 v2，2026-10-26）。
/// 每个命名空间对应文案稿的一节；文字原样照抄，不改写、不缩写。
/// 带变量的句子一律用插值，不拼接中文片段。
enum Copy {

    /// 9. 名字：界面上唯一出现 App 名的地方是导航标题。
    static let appName = "Pace"

    // MARK: - 1. 一句话记账：入口和输入 / 3. 设置 / 5. 失败与回退

    enum Ai {

        /// 1.2 输入页（sheet）。
        enum Input {
            static let placeholder = "早饭 12，地铁 4"
            /// 例句胶囊（点一下填进去）。最多三个，第一个留「昨天午饭 28」：
            /// 本机规则失败卡里就引用了这一句。
            static let examples = ["昨天午饭 28", "超市 56 微信", "工资 8000"]
            /// 没填 Key 时的状态小字；填了则显示模型名（如 deepseek-chat）。
            static let localRuleStatus = "本机规则"
            static let cancel = "取消"
            static let submit = "整理成草稿"
            static let submitting = "正在整理…"
            /// 就地确认（docs/DESIGN-quickadd-primary.md §5）
            static let parsing = "正在拆这一句…"
            static let confirmInline = "记上"
            static let editInline = "改一下"
            static let confirmed = "记上了"
        }

        /// 3. 设置里的「AI 一句话记账」。
        enum Settings {
            static let sectionTitle = "一句话记账"
            static let toggleTitle = "用自己填的模型"
            static let subtitleOff = "关着。入口还在，用本机规则整理，不联网、不出手机。"
            static let subtitleOn = "开着。你打的那句话会发给你填的服务；账本其他内容不出设备。"
            static let disabledToast = "已关掉，改用本机规则，不出手机。"

            /// 3.2 服务商预置。名字用各家自己的写法，不翻译。
            enum Provider {
                static let label = "服务商"
                static let note = "换了服务商，Key 要换成那一家发的。"
                static let custom = "自定义"
            }

            /// 3.2 接口地址：选「自定义」时才露出来。
            enum Endpoint {
                static let label = "接口地址"
                static let placeholder = "https://api.deepseek.com/v1"
                static let note = "按 OpenAI 兼容格式填，地址一般写到 /v1 就行。"
            }

            /// 3.2 手填模型名。
            enum Model {
                static let label = "模型名"
                static let placeholder = "deepseek-chat"
                static let note = "填服务商文档里给的那个名字。"
            }

            /// 3.4 模型下拉：读取模型列表，以及手填兜底。
            enum ModelPick {
                static let label = "模型"
                static let loading = "正在读取模型列表…"
                static let ready = "这些是这个 Key 能用的模型。选一个就保存。"
                static let empty = "这个 Key 一个模型都没有。手填一个试试。"
                static let read = "读取模型列表"
                static let retry = "重新读取"
                static let manual = "手动填模型名"
                static let backToList = "回到列表"
                static let title = "选择模型"
                static let search = "搜模型名"
                static let close = "取消"
                static let choose = "选择一个"
                static let clearSearch = "清空搜索"
                static let noMatch = "没搜到。关掉这一页，用「手填模型名」直接填。"

                /// 手上这份名单是上次读回来的，这次没读上。
                static let staleList = "这是上次读回来的列表，可能不是最新的。"

                static func stale(_ model: String) -> String {
                    "「\(model)」这次没在列表里。可能换过服务商，或者它已经下线了。还用它也行。"
                }

                /// 四种失败态放各自站得住的话；「不列模型」是这家就这样，不当错误。
                enum Error {
                    static let keyRejected = "这个服务没认这把 Key。检查一下有没有粘全，或者去服务商后台看看它还能不能用、能不能读模型。"
                    static let noModelList = "这个服务不提供模型列表。手填一个模型名就行，服务商文档里有。"
                    static let unreachable = "连不上这个地址。检查一下地址有没有写错，或者是不是没网。"
                    static let server = "那边出了点问题，模型列表没取回来。过一会儿再读一次，或者先手填模型名。"
                    static let noKey = "先填 Key，这里会列出这个 Key 能用的模型。"
                    static let noAddress = "先填接口地址，再读模型列表。"
                    static let noAddressAndKey = "先填接口地址和 Key。"
                }

                static let a11yLoading = "正在读取模型列表"

                static func a11yLoaded(_ count: Int) -> String {
                    "模型列表回来了，\(count) 个模型"
                }
            }

            /// 3.2 三项设置：Key。
            enum Key {
                static let label = "Key"
                static let placeholder = "sk-…"
                static let note = "只存在这台手机的钥匙串里，不写进导出文件，不进日志。清空账本不会删它，要删就点「清空 Key」。"
                static let storeFailed = "这把 Key 没存进手机。这一页里还能用，但重开 app 就没了，得再粘一次。"
            }

            /// Key 下面那句：开关那两行说「现在走哪条路」，这句说「贴上这把 Key
            /// 等于同意什么」。Camo 定稿，顶掉原来那句「没配好服务，就用本机规则整理」。
            static let keyScope = "填了它，记账时打的那句话会发给你选的服务；账本其他内容不跟着发，没填就还是本机规则。"
            static let securityTitle = "Key 在你手机上"
            static let securityNote = "提醒一句：Key 存在你手机上，谁拿到你解锁的手机，就能用掉你的额度。建议单独申请一个 Key，方便随时去服务商后台吊销。"
        }

        /// 3.3 「测试连接」的三种结果与清空 Key 确认。
        enum Test {
            static let button = "测试连接"
            static let connecting = "正在连接…"
            static let ok = "连上了。"
            static let unreachable = "连不上这个地址。检查一下地址有没有写错，或者是不是没网。"
            static let keyRejected = "Key 没通过。这个服务没认这把 Key，去服务商后台确认一下。"
            static let incomplete = "先把地址和 Key 填上，再把模型选上。"
            static let clearKey = "清空 Key"
            static let clearConfirmTitle = "清空 Key？"
            static let clearConfirmBody = "清掉以后就用本机规则拆句子，账本不受影响。"
            static let clearConfirm = "清空"
            static let clearCancel = "取消"
        }

        /// 5. 失败与回退（五种）。正文末句「账本没有任何变化」是承诺，不可省略。
        enum Fail {

            /// 失败卡上那条出路。和类型菜单那行一个字不差：一个动作不许有两个名。
            static let toManual = "切到手动"

            /// 本机规则没读懂。
            enum LocalRule {
                static let title = "这句话没拆开"
                static let body = "本机规则只认常见的说法，比如「昨天午饭 28」。换个说法，或者切到手动。账本没有任何变化。"
                static let primary = toManual
            }

            /// 模型没读懂（返回的不是草稿、空结果）。
            enum Model {
                static let title = "这次没整理出来"
                static let body = "你填的服务没能把这句话拆成账单。换句话再说，或者切到手动。账本没有任何变化。"
                static let primary = toManual
                static let secondary = "用本机规则再试"
            }

            /// 没网。
            enum Offline {
                static let title = "连不上网"
                static let body = "你填的服务要联网才能用。先在这台手机上拆也行。账本没有任何变化。"
                static let primary = "用本机规则再试"
                static let secondary = toManual
            }

            /// 超时（20 秒）。
            enum Timeout {
                static let title = "那边没回话"
                static let body = "等太久了，这次不算。可以再试一次，或者切到手动。账本没有任何变化。"
                static let primary = toManual
                static let secondary = "用本机规则再试"
            }

            /// Key 被拒（401/403）。
            enum KeyRejected {
                static let title = "Key 没通过"
                static let body = "这个服务没认你填的 Key。去设置里确认一下，或者先用本机规则拆。账本没有任何变化。"
                static let primary = "去设置"
                static let secondary = "用本机规则再试"
            }

            /// 服务返回额度用完 / 限流（402、429）：沿用 KeyRejected 的标题与按钮，只换正文。
            enum Quota {
                static let body = "这个服务说额度用完了，去后台看看，或者先用本机规则拆。账本没有任何变化。"
            }
        }
    }

    // MARK: - 2. 开启前的隐私说明（BYOK 口径）

    enum PrivacySheet {
        static let title = "开启前，先说清楚一件事"
        static let line1 = "你在这里打的那句话，会发给你自己填的那个服务，用来整理成账单草稿。"
        static let line2 = "账本留在本机：以前的账单、统计、备注，都不会跟着发出去。"
        static let line3 = "它只出草稿。你逐笔确认，才保存进账本；它不会自己改你的账。"
        static let line4 = "关掉之后，记账、预算、统计、导出照常；没填服务就用本机规则整理，没网也能用。"
        static let footer = "你填的那个服务怎么处理这段文字，按它自己的规则。我们看不到，也存不下这句话。"
        static let primary = "同意并开启"
        static let secondary = "先不用"
        static let settingsHint = "以后可以在「设置 → 一句话记账」里关掉"
    }

    // MARK: - 4. 草稿确认页

    enum Draft {
        /// 数字只在大于零时出现：0 笔的时候别把 0 写进句子里。
        static func title(count: Int) -> String {
            count > 0 ? "草稿 \(count) 笔" : "没有草稿"
        }
        static let headerLeft = "确认后才进账本"
        static let headerRight = "逐笔可改"
        /// 顶部补的那行：缺哪样就报哪样；同时缺好几样时只说笔数。
        static func needsSupplementNote(count: Int, field: String?) -> String {
            guard let field else { return "还有 \(count) 笔要补。" }
            return "还有 \(count) 笔要补\(field)。"
        }
        static func saveButton(count: Int) -> String {
            count > 0 ? "保存 \(count) 笔" : "保存"
        }
        /// 缺的都一样就说那一样；说不到一起就只说还不能保存。
        static func fillRequiredButton(field: String?) -> String {
            guard let field else { return "补完再保存" }
            return "先补\(field)"
        }
        /// 草稿全删光以后这一页的样子。
        static let emptyTitle = "这一批草稿都删掉了。"
        static let emptySubtitle = "账本没有变化，回去就行"
        static let discardAll = "全部不要"
        static let deleteAction = "删除"
        static let statusNeedsSupplement = "需要补充"
        static let statusReady = "可以保存"
        static let footer = "草稿先给你看，你确认的才进账本。"

        /// 金额没解析出来时右边那个占位（按字画的破折号，不是 44pt 色块）。
        static let emptyAmount = "—"
        /// 金额为 0 那行说明。
        static let noAmountHint = "这句话里没有金额，不猜。"
        /// 卡片头部类型胶囊的去表单出口。
        static let toManual = "退款或转账，切到手动"

        /// 4.1 「需要补充」的标记措辞（标记 + 点开补的时候那行提示）。
        enum Missing {
            static let amount = "需要金额"
            /// 缺类型时胶囊里那两个字：说的是现在要做的事。
            static let typeCapsule = "选类型"
            /// 读屏：没选时的值。
            static let typeNotChosen = "没选"
            static let typeHintNotChosen = "点按选择支出或收入"
            static let typeHintChosen = "点按可以改成支出或收入"
            static let amountHint = "补一个金额就能保存"
            static let date = "需要日期"
            static let dateHint = "现在按今天算，可以改"
            static let type = "需要类型"
            static let typeHint = "这是支出还是收入？"
            static let category = "需要分类"
            static let categoryHint = "选一个分类"
        }

        /// 4.2 草稿卡片里的字段名（与手动记账表单同一套词）。
        enum Field {
            static let amount = "金额"
            static let category = "分类"
            static let date = "日期"
            static let note = "备注"
            static let account = "账户"
            static let countInBudget = "计入预算"
        }
    }

    // MARK: - 6. 保存和删除的确认语

    enum Save {
        static func saved(note: String, amount: String) -> String {
            "已保存「\(note)」¥\(amount)"
        }
        static func saved(count: Int) -> String {
            "已保存 \(count) 笔"
        }
        /// 全都重复：不搭「已保存」，直接说结果。
        static func allDuplicates(count: Int) -> String {
            "这 \(count) 笔账本里已经有了，没有重复记。"
        }
        /// 部分重复。
        static func savedSomeDuplicates(saved: Int, duplicated: Int) -> String {
            "已保存 \(saved) 笔，另外 \(duplicated) 笔账本里已经有了。"
        }
        static let edited = "已保存修改"
        static func savedWithoutNote(amount: String) -> String {
            "已保存 ¥\(amount)"
        }
    }

    enum Delete {
        static let action = "删除"
        static let confirmTitle = "删掉这笔？"
        static func confirmBody(note: String, amount: String) -> String {
            "「\(note) ¥\(amount)」会从账本里消失。删了还能撤销。"
        }
        static let confirmPrimary = "删除"
        static let confirmCancel = "取消"
        static func toast(note: String) -> String {
            "已删除「\(note)」"
        }
        static let undo = "撤销"
        static let restored = "已恢复"
        static func toastAccessibility(note: String) -> String {
            "已删除\(note)，可以撤销"
        }
    }

    /// 6.3 其他确认。
    enum Confirm {

        /// 重复账单。
        enum Duplicate {
            static let title = "这笔好像已经记过"
            static let body = "同一天、同金额、同备注的账单已经有了。还要再记一笔吗？"
            static let primary = "照样记"
            static let secondary = "取消"
        }

        /// 清空全部数据。
        enum ClearLedger {
            static let title = "清空整个账本？"
            static let body = "所有账单、预算设置和自定义分类都会删掉，删了找不回来。建议先导出一份备份。"
            static let primary = "确认清空"
            static let secondary = "取消"
        }

        /// 替换账本。
        enum ReplaceLedger {
            static let title = "用这个文件替换现在的账本？"
            static let body = "现在的账单、预算设置和分类会全部删掉，换成文件里的内容。删了找不回来。"
            static let primary = "确认替换"
            static let secondary = "取消"
        }
    }

    // MARK: - 7. 首页

    enum Home {
        static let statusWithinBudget = "在预算内"
        static let statusOverspent = "已超支"
        static let statusNoBudget = "还没设预算"
        static let noBudgetHint = "设一个每日预算，Pace 就开始算你还剩多少。"
        static let remainingLabel = "今天还剩"
        static let remainingOverspentLabel = "今天超支"
        static func budgetSpent(budget: String, spent: String) -> String {
            "预算 ¥\(budget) · 已花 ¥\(spent)"
        }
        static let budgetSpentHint = "不算进预算的那几笔，和退款，都不在这里扣。"
        static let todayBillsTitle = "今天"
        static let emptyTitle = "还没有账单"
        /// 两个填法共用同一句：不再按有没有 Key 分叉。
        static let emptySubtitle = "点「记一笔」，说一句话就行。"
        static let loading = "加载中…"
    }

    // MARK: - 7. 账单页

    enum Bills {
        static let title = "账单"
        static let rangeLabel = "范围"

        /// 范围分段：顺序固定，文案只此一份。
        enum Range {
            static let week = "本周"
            static let month = "本月"
            static let all = "全部"
        }

        static let emptyTitle = "这段时间还没有账单。"
        static let emptySubtitle = "换个范围看看，或者记一笔。"
        static let searchPlaceholder = "搜索备注、分类或账户"
        static let noResultsTitle = "没找到相关的账单。"
        static let noResultsSubtitle = "换个词试试。"

        /// 段头日期：`10月26日 · 周日`。
        static let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        static func sectionDate(month: Int, day: Int, weekday: String) -> String {
            "\(month)月\(day)日 · \(weekday)"
        }

        static let notInBudget = "不计入预算"
    }

    // MARK: - 8. 记一笔：两种填法（docs/add-mode-switch-copy.md）

    /// 页顶的切换器。两个都是 Button，不是 Picker。
    enum AddMode {
        static let sentence = "一句话"
        static let manual = "手动"
        static let switchHint = "切换后已经填的内容不会丢"
    }

    /// 一句话这一条路自己的字：键盘键和读屏提示按走不走模型分开。
    enum Sentence {
        static let fieldA11y = "一句话记账"
        static let parsing = "正在整理…"
    }

    // MARK: - 7. 记账页（AddView）

    enum Add {
        static let title = "记一笔"
        static let editTitle = "编辑账单"
        static let save = "保存"
        static let closeA11y = "关掉"
        /// 类型胶囊那一组的读屏名（docs/add-mode-switch-copy.md §3）。
        static let typeGroupA11y = "类型"
        static let sectionAccountBudget = "账户与预算"
        static let accountPlaceholder = "现金、微信、银行卡…"
        static let sectionRefundOriginal = "这笔退的是哪一笔"
        static let noRefundCandidates = "还没有可以关联的支出账单。"

        /// 7.16 保留的四个 Section 名。
        enum Section {
            static let type = "类型"
            static let amount = "金额"
            static let category = "分类"
            static let note = "备注"
        }
    }

    // MARK: - 7. 统计页

    enum Stats {
        static let title = "统计"
        static let week = "本周"
        static let month = "本月"
        static let expense = "支出"
        static let overspent = "超支"
        static let categoryRanking = "花在哪了"
        static let dailyBudget = "每天花了多少"
        static let refundOffset = "退款抵掉"
        static let empty = "这段时间没有支出。"
        static let loading = "加载中…"
        static let dailyFormula = "每天预算从生效日起算；今天还剩 = 预算 − 计入预算的支出 + 退款。"

        static func overspentDays(_ count: Int) -> String {
            "\(count) 天"
        }

        static func moreCategories(_ count: Int) -> String {
            "还有 \(count) 个分类"
        }

        static func ratioA11y(_ percent: Int) -> String {
            "占比 \(percent)%"
        }

        static func usedA11y(_ percent: Int) -> String {
            "已用 \(percent)%"
        }

        static func monthDay(month: Int, day: Int) -> String {
            "\(month)月\(day)日"
        }

        /// 规范第一批 §11 的读法：128 元 5 角。
        static func spokenAmount(_ minor: Int64) -> String {
            let value = abs(minor)
            let yuan = value / 100
            let cents = value % 100
            if cents == 0 { return "\(yuan) 元" }
            let jiao = cents / 10
            let fen = cents % 10
            if fen == 0 { return "\(yuan) 元 \(jiao) 角" }
            return "\(yuan) 元 \(jiao) 角 \(fen) 分"
        }

        /// 7.20 保留的筛选标签。
        enum Filter {
            static let countInBudget = "计入预算"
            static let income = "收入"
            static let transfer = "转账"
            static let transferExcluded = "转账 不计入支出"
        }
    }

    // MARK: - 7. 设置页

    enum Settings {
        /// 0. 词汇表 / 设置项名，保留不动。
        static let dailyBudget = "每日预算"
        static func currentBudget(amount: String, month: Int, day: Int) -> String {
            "现在是 ¥\(amount)，从 \(month) 月 \(day) 日开始"
        }
        static let effectiveDatePlaceholder = "从哪天开始"
        static let effectiveDateHint = "例如 2026-10-26"
        static let exportCSV = "导出表格（CSV）"
        static let exportJSON = "导出数据文件（JSON）"
        static let restoreFromFile = "从文件恢复…"
        static let clearLedger = "清空整个账本…"
        static let noBudget = "还没设预算"
        static let budgetPlaceholder = "200.00"
        static let effectiveDate = "生效日期"
        static let saveBudget = "保存预算"
        static let savedBadge = "已保存"
        static let budgetFooter = "改预算从生效日开始算，不改以前的天。"
        static let quickAddRow = "一句话记账"
        static let quickAddStatusRow = "现在用"
        static let statusLocal = "本机规则"
        static let statusRemote = "你的服务"
        static let clearConfirmTitle = "清空整个账本？"
        static let clearConfirmBody = "所有账单、预算设置和自定义分类都会删掉，删了找不回来。建议先导出一份备份。"
        static let clearConfirmKeyNote = "填过的 Key 不在这里删，要清掉请到「一句话记账」里点「清空 Key」。"
        static let clearConfirm = "确认清空"
        static let cancel = "取消"
        static func version(_ text: String) -> String {
            "Pace \(text)"
        }

        /// 7.27–7.30 恢复与导入。
        enum Import {
            static func previewDuplicates(count: Int) -> String {
                "其中 \(count) 笔现在账本里已经有了"
            }
            static let mergeOrReplaceNote = "合并：只补充新的，已有的不动。 替换：先清空，再写入文件里的内容。"
            static func merged(added: Int, skipped: Int) -> String {
                "已合并：新增 \(added) 笔，跳过 \(skipped) 笔"
            }

            /// 7.30 导入失败：错误码只进日志，界面统一冠以前缀。
            enum Issue {
                static let invalidAmount = "有一笔金额不对，要写成大于 0 的数，最多两位小数"
                static let invalidDate = "有一笔日期看不懂"
                static let invalidTypeOrCategory = "有一笔的类型或分类不认识"
                static let noteTooLong = "有一笔备注超过 500 字"
                static let unknown = "文件读不出来，可能不是 Pace 导出的"

                static func failed(reason: String) -> String {
                    "没有导入，现在的账本没变：\(reason)"
                }
            }
        }
    }

    /// 6.4 说出来的失败：哪件事没成 / 现在什么状态 / 能不能再试。
    enum Failed {

        /// 撤销删除：账本确实变了（这笔没了），所以不写「账本没有变化」。
        enum Undo {
            static let title = "没恢复上"
            static let body = "这笔还是删掉的，账本没有变化。再点一次「撤销」试试。"
        }

        /// 删除本身没成：账本没变，这笔还在。
        enum Delete {
            static let title = "没删掉"
            static let body = "这笔还在账本里，账本没有变化。再点一次「删除」试试。"
        }

        /// 草稿保存失败（不是重复）。
        enum DraftSave {
            static let title = "没保存上"
            static let bodyMany = "这几笔还在草稿页里，账本没有变化。再试一次。"
            static let bodyOne = "这笔还在草稿页里，账本没有变化。再试一次。"

            /// 部分成功：存进去的那几笔真的进了账本，别再说「没有变化」。
            static func partial(saved: Int, failed: Int) -> String {
                "存进去 \(saved) 笔，还有 \(failed) 笔没保存上，还在草稿页里。再试一次。"
            }
        }

        /// 就地确认那一路：不能复用「这次没整理出来」，那是解析失败的话。
        enum InlineSave {
            static let title = "没记上"
            static let body = "账本没有变化。再按一次「记上」。"
        }

        /// 导出：写文件失败时别弹分享面板。
        enum Export {
            static let title = "导出没成功"
            static let body = "文件没写成，账本没有变化。再试一次。"
        }

        /// 再说一次的那个动作（三条失败卡上都有）。
        static let retry = "再试一次"
    }

    // MARK: - 7.31 通用校验错误（TxnUI）

    enum Errors {
        static let amount = "金额要大于 0，最多两位小数。"
        static let date = "日期要填成这样：2026-10-26。"
        static let category = "选一个分类。"
        static let refundNeedsOriginal = "退款要说清楚退的是哪一笔支出。"
        static let originalMissing = "这笔原账单不存在，或者不是支出。"
        static let duplicate = "这笔已经记过了。"
        static let billGone = "这笔账单已经不在了，可能被删掉了。"
        static let saveFailed = "没保存上，再试一次。"
    }
}
