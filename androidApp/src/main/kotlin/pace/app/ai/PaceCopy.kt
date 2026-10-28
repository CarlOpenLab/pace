package pace.app.ai

/**
 * 一句话记账 surfaces 的用户可见文案（中文）。
 * 唯一来源：docs/COPY.md（第二轮 v2）；与 iOS `Copy.swift` 逐字一致，不本地化改写。
 * 只收录 Android 用到的键；两边的同一句话必须一字不差。
 */
object PaceCopy {

    object AddMode {
        const val sentence = "一句话"
        const val manual = "手动"
        const val switchHint = "切换后已经填的内容不会丢"
    }

    /** 记一笔手动表单的散字（docs/add-mode-switch-copy.md §3，与 iOS Copy.Add 同源）。 */
    object Add {
        const val sectionAmount = "金额"
        const val sectionCategory = "分类"
        const val sectionNote = "备注"
        const val notePlaceholder = "例如：午饭"
        const val accountPlaceholder = "现金、微信、银行卡…"
        const val sectionRefundOriginal = "这笔退的是哪一笔"
        const val noRefundCandidates = "还没有可以关联的支出账单。"
        const val customAccount = "自定义…"
        const val customAccountTitle = "自定义账户"
    }

    object Ai {
        object Input {
            const val placeholder = "早饭 12，地铁 4"
            val examples = listOf("昨天午饭 28", "超市 56 微信", "工资 8000")
            const val parsing = "正在拆这一句…"
            const val confirmInline = "记上"
            const val editInline = "改一下"
            const val confirmed = "记上了"
        }

        object Net {
            const val checkAddress = "看看有没有打错，或者地址结尾是不是少了 /v1。"
            const val fixHTTP = "换成 http 开头的地址先顶着（明文，同一网络里可能看到 Key），或者把它的证书装到手机上。"
        }

        /** 5. 失败与回退（五种）。正文末句「账本没有任何变化」是承诺，不可省略。 */
        object Fail {
            const val toManual = "切到手动"
            const val retryLocal = "用本机规则再试"
            const val toSettings = "去设置"

            object LocalRule {
                const val title = "这句话没拆开"
                const val body = "本机规则只认常见的说法，比如「昨天午饭 28」。换个说法，或者切到手动。账本没有任何变化。"
                const val primary = toManual
            }

            object Model {
                const val title = "这次没整理出来"
                const val body = "你填的服务没能把这句话拆成账单。换句话再说，或者切到手动。账本没有任何变化。"
                const val primary = toManual
                const val secondary = retryLocal
            }

            object Offline {
                const val title = "连不上网"
                const val body = "你填的服务要联网才能用。先在这台手机上拆也行。账本没有任何变化。"
                const val primary = retryLocal
                const val secondary = toManual
            }

            object Timeout {
                const val title = "那边没回话"
                const val body = "等太久了，这次不算。可以再试一次，或者切到手动。账本没有任何变化。"
                const val primary = toManual
                const val secondary = retryLocal
            }

            object BadAddress {
                const val title = "这个地址打不开"
                const val body = "这个地址打不开。" + Net.checkAddress + "回设置里对着服务商给的那一栏核一遍。账本没有任何变化。"
                const val primary = toSettings
                const val secondary = toManual
            }

            object Certificate {
                const val title = "这台服务器的证书手机不认"
                const val body = "这台服务器的证书手机不认，连接被系统拦下了。" + Net.fixHTTP + "账本没有任何变化。"
                const val primary = toManual
                const val secondary = retryLocal
            }

            object Server {
                const val title = "服务器那边出问题了"
                const val body = "地址和 Key 都没问题，是它那边没接住这次请求。待会儿再试一次，或者切到手动。账本没有任何变化。"
                const val primary = toManual
                const val secondary = retryLocal
            }

            object ModelRejected {
                const val title = "这个模型现在用不了"
                const val body = "地址和 Key 都通了，你填的服务说这次请求给不出这个模型。回设置里从列表里挑一个，或者问给你这个地址的人要准确的模型名。账本没有任何变化。"
                const val primary = toSettings
                const val secondary = toManual
            }

            object Unreachable {
                const val title = "连不上这个地址"
                const val body = "试了也没连上，分不出卡在哪一环。先看手机有没有网、地址有没有写错；都对着，就换个网络再试。账本没有任何变化。"
                const val primary = toManual
                const val secondary = retryLocal
            }

            object KeyRejected {
                const val title = "Key 没通过"
                const val body = "这个服务没认你填的 Key。去设置里确认一下，或者先用本机规则拆。账本没有任何变化。"
                const val primary = toSettings
                const val secondary = retryLocal
            }

            object Quota {
                const val body = "这个服务说额度用完了，去后台看看，或者先用本机规则拆。账本没有任何变化。"
            }
        }

        object Settings {
            const val sectionTitle = "一句话记账"
            const val toggleTitle = "用自己填的模型"
            const val subtitleOff = "关着。入口还在，用本机规则整理，不联网、不出手机。"
            const val subtitleOn = "开着。你打的那句话会发给你填的服务；账本其他内容不出设备。"
            const val keyScope = "填了它，记账时打的那句话会发给你选的服务；账本其他内容不跟着发，没填就还是本机规则。"
            const val securityNote = "提醒一句：Key 存在你手机上，谁拿到你解锁的手机，就能用掉你的额度。建议单独申请一个 Key，方便随时去服务商后台吊销。"

            object Provider {
                const val label = "服务商"
                const val note = "换了服务商，Key 要换成那一家发的。"
                const val custom = "自定义"
            }

            object Endpoint {
                const val label = "接口地址"
                const val placeholder = "https://api.deepseek.com/v1"
                const val note = "按 OpenAI 兼容格式填，地址一般写到 /v1 就行。"
                const val plainHTTP = "这是 http 明文地址，同一网络里的人可能看到你的 Key；能换成 https 就换。"
            }

            object Model {
                const val label = "模型名"
                const val placeholder = "deepseek-chat"
                const val note = "填服务商文档里给的那个名字。"
            }

            object ModelPick {
                const val read = "读取模型列表"
                const val retry = "重新读取"
                const val loading = "正在读取模型列表…"
                const val ready = "这些是这个 Key 能用的模型。选一个就保存。"
                const val empty = "这个 Key 一个模型都没有。手填一个试试。"
                const val keyRejected = "这个服务没认这把 Key。检查一下有没有粘全，或者去服务商后台看看它还能不能用、能不能读模型。"
                const val noModelList = "这个服务不提供模型列表。手填一个模型名就行，服务商文档里有。"
                const val unreachable = "连不上这个地址。先看手机有没有网、地址有没有写错。"
                const val offline = "手机没联网，读不了模型列表。连上网络再试，或者先手填模型名。"
                const val badAddress = "这个地址打不开，读不了模型列表。" + Net.checkAddress
                const val certificate = "这台服务器的证书手机不认，读不了模型列表。" + Net.fixHTTP
                const val server = "那边出了点问题，模型列表没取回来。过一会儿再读一次，或者先手填模型名。"
                const val noKey = "先填 Key，这里会列出这个 Key 能用的模型。"
                const val noAddress = "先填接口地址，再读模型列表。"
            }

            object Key {
                const val label = "Key"
                const val placeholder = "sk-…"
                const val note = "只存在这台手机的加密存储里，不写进导出文件，不进日志。清空账本不会删它，要删就点「清空 Key」。"
                const val storeFailed = "这把 Key 没存进手机。这一页里还能用，但重开 app 就没了，得再粘一次。"
                const val clear = "清空 Key"
                const val clearConfirmTitle = "清空 Key？"
                const val clearConfirmBody = "清掉以后就用本机规则拆句子，账本不受影响。"
                const val clearConfirm = "清空"
            }

            object Test {
                const val button = "测试连接"
                const val connecting = "正在连接…"
                const val ok = "连上了。"
                const val unreachable = "连不上这个地址。检查一下地址有没有写错，或者是不是没网。"
                const val keyRejected = "Key 没通过。这个服务没认这把 Key，去服务商后台确认一下。"
                const val offline = "手机没联网。连上网络再试。"
                const val badAddress = "这个地址打不开。" + Net.checkAddress
                const val certificate = "这台服务器的证书手机不认。" + Net.fixHTTP
                const val server = "地址通了，服务器那边出错了。待会儿再试。"
                const val modelRejected = "地址和 Key 都通了，你填的服务说这个模型用不了。换一个模型再试。"
                const val incomplete = "先把地址和 Key 填上，再把模型选上。"
            }
        }
    }

    object Draft {
        fun title(count: Int) = if (count > 0) "草稿 $count 笔" else "没有草稿"
        const val headerLeft = "确认后才进账本"
        const val headerRight = "逐笔可改"
        fun needsSupplementNote(count: Int, field: String?) =
            if (field == null) "还有 $count 笔要补。" else "还有 $count 笔要补$field。"
        fun saveButton(count: Int) = if (count > 0) "保存 $count 笔" else "保存"
        fun fillRequiredButton(field: String?) = if (field == null) "补完再保存" else "先补$field"
        const val emptyTitle = "这一批草稿都删掉了。"
        const val emptySubtitle = "账本没有变化，回去就行"
        const val discardAll = "全部不要"
        const val deleteAction = "删除"
        const val statusNeedsSupplement = "需要补充"
        const val footer = "草稿先给你看，你确认的才进账本。"
        const val emptyAmount = "还没填"
        const val noAmountHint = "这句话里没有金额，不猜。"
        const val toManual = "退款或转账，切到手动"
        const val editorDone = "改好了"

        object Missing {
            const val amount = "需要金额"
            const val typeCapsule = "选类型"
            const val date = "需要日期"
            const val type = "需要类型"
            const val category = "需要分类"
        }

        object Field {
            const val amount = "金额"
            const val category = "分类"
            const val date = "日期"
            const val note = "备注"
            const val account = "账户"
        }
    }

    object Save {
        fun saved(count: Int) = "已保存 $count 笔"
        fun allDuplicates(count: Int) = "这 $count 笔账本里已经有了，没有重复记。"
        fun savedSomeDuplicates(saved: Int, duplicated: Int) = "已保存 $saved 笔，另外 $duplicated 笔账本里已经有了。"
        const val duplicateTitle = "这笔好像已经记过"
        const val duplicateBody = "同一天、同金额、同备注的账单已经有了。还要再记一笔吗？"
        const val duplicatePrimary = "照样记"
        const val duplicateCancel = "取消"
    }

    object Failed {
        const val retry = "再试一次"
        object DraftSave {
            const val title = "没保存上"
            const val bodyMany = "这几笔还在草稿页里，账本没有变化。再试一次。"
            const val bodyOne = "这笔还在草稿页里，账本没有变化。再试一次。"
            fun partial(saved: Int, failed: Int) = "存进去 $saved 笔，还有 $failed 笔没保存上，还在草稿页里。再试一次。"
        }

        object InlineSave {
            const val title = "没记上"
            const val body = "账本没有变化。再按一次「记上」。"
        }
    }

    object Home {
        const val emptySubtitle = "点「记一笔」，说一句话就行。"
    }

    object Errors {
        const val amount = "金额要大于 0，最多两位小数。"
    }
}
