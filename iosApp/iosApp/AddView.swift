import SwiftUI
import shared

/// 记一笔 / 编辑账单（docs/DESIGN-add-mode-switch.md）。
///
/// 原来按 AI 设置分叉成两个入口，现在只有这一页：页顶切换「一句话 / 手动」，
/// 两种填法写的是同一笔账，共用下面这份 @State。切换只换显示，不动值；
/// 唯一会覆盖表单的是一次新的解析——那是用户按了发送的显式动作。
struct AddPrefill: Identifiable {
    let id = UUID()
    var amountText: String
    var localDate: String
    var note: String
}

/// 草稿确认页的入参。包一层只为了拿到稳定的 id，让 .sheet(item:) 每次都建新内容。
private struct ReviewPayload: Identifiable {
    let id = UUID()
    let drafts: [DraftItem]
}

struct AddView: View {
    let txnId: String?
    var prefill: AddPrefill? = nil
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ai: AiSettings

    // 手动表单
    @State private var type: String
    @State private var amountText: String
    @State private var category: String
    @State private var localDate: String
    @State private var note: String
    @State private var account: String
    @State private var countInBudget: Bool
    @State private var refundOfId: String?

    @State private var errorText: String?
    @State private var showCustomAccount = false
    @State private var customAccountDraft = ""

    // 一句话
    @State private var mode: AddFillMode
    @State private var sentenceText = ""
    @State private var busy = false
    @State private var failure: AiFailure?
    /// 失败是「本机规则」那一路时，文案和按钮都不一样。
    @State private var localFailure = false
    @State private var sentenceDraft: DraftItem?
    /// 草稿确认页要整批拿走；用 item 而不是 isPresented + 数组，
    /// 否则 sheet 会在数组写进去之前就建好内容，出现一张「没有草稿」的空页。
    @State private var reviewPayload: ReviewPayload?
    @State private var savingInline = false
    @State private var inlineSaved = false
    @State private var inlineSaveFailed = false
    /// 这张草稿已经灌进手动表单一次；再切回来不重复灌，免得覆盖用户改过的值。
    @State private var pumpedDraftId: String?

    /// 失败卡在滚动坐标系里的框、可视高度、用户有没有自己拖过。
    @State private var failureCardFrame: CGRect = .zero
    @State private var viewportHeight: CGFloat = 0
    @State private var userScrolled = false
    /// 滚过顶了没有：顶边那 8 点渐隐只在滚起来之后出现。
    @State private var scrolledFromTop = false

    /// 金额那一行：卡片内容宽、并排所需的宽。
    @State private var cardContentWidth: CGFloat = 0
    @State private var amountRowRulerWidth: CGFloat = 0

    // 保存确认（手动和就确认共用一张）
    @State private var duplicateNotice = false
    /// 非空表示这次重复来自一句话的「记上」。
    @State private var duplicateDraft: DraftItem?

    @FocusState private var inputFocused: Bool
    @FocusState private var amountFocused: Bool
    @AccessibilityFocusState private var draftFocused: Bool

    private let categories: [LedgerCategory]
    private let refundCandidates: [LedgerTransaction]

    /// Copy 里没有账户预设的键（只有占位文案），按 spec 列在这里。
    private static let accountPresets = ["现金", "微信", "支付宝", "银行卡"]

    init(txnId: String?, prefill: AddPrefill? = nil, startInManual: Bool = false) {
        self.txnId = txnId
        self.prefill = prefill
        self.onDone = {}

        let existing = txnId.flatMap { LedgerStore.shared.api.transaction(id: $0) }

        // 编辑账单没有切换器，也不进一句话：只给手动表单。
        _mode = State(initialValue: (txnId != nil || startInManual || prefill != nil) ? .manual : .sentence)
        _type = State(initialValue: existing?.type ?? TxnTypes.expense)
        _amountText = State(initialValue: existing.map { Money.shared.formatMinor(amountMinor: $0.amountMinor) } ?? prefill?.amountText ?? "")
        _category = State(initialValue: existing?.category ?? "餐饮")
        _localDate = State(initialValue: existing?.localDate ?? prefill?.localDate ?? LedgerStore.shared.todayIso)
        _note = State(initialValue: existing?.note ?? prefill?.note ?? "")
        _account = State(initialValue: existing?.account ?? "现金")
        _countInBudget = State(initialValue: existing?.countInBudget ?? true)
        _refundOfId = State(initialValue: existing?.refundOfId)

        #if DEBUG
        // `-uiAmount 1280.50`：直接进手动页并填好金额，验收「金额整串可见」不用手打。
        if txnId == nil, prefill == nil, let amount = Self.debugAmountArg {
            _mode = State(initialValue: .manual)
            _amountText = State(initialValue: amount)
        }
        #endif

        self.categories = LedgerStore.shared.api.categories().sorted { a, b in
            if a.usageCount != b.usageCount { return a.usageCount > b.usageCount }
            return a.sortOrder < b.sortOrder
        }
        self.refundCandidates = Array(
            LedgerStore.shared.api.allTransactions()
                .filter { $0.type == TxnTypes.expense }
                .sorted { $0.occurredAtEpochMillis > $1.occurredAtEpochMillis }
                .prefix(10)
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: PaceSpace.cardGap) {
                        if showsSentence {
                            sentenceContent
                        } else {
                            manualContent
                        }
                    }
                    .padding(.horizontal, PaceSpace.screen)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                // 失败卡一出来，就把卡的顶滚进视野。
                // 以前不滚：键盘弹起来把输入框顶到可见处，偏移留在那儿；卡比输入框高得多，
                // 长出来的部分往上顶，标题和正文第一句就钻进切换器底下那条不透明底色里。
                // 用户看到的第一眼是一张没有标题、正文从半句开始的卡——而这张卡的全部作用
                // 就是让他看懂出了什么事。字没有上限，所以不能靠在卡片高度上找数字解决，
                // 只能让整页把它带进视野。
                .onChange(of: failure != nil) { _, hasFailure in
                    guard hasFailure else { return }
                    // 让这一帧先量出卡在自己坐标系里的位置，再决定滚不滚。
                    DispatchQueue.main.async { scrollToFailureIfNeeded(proxy) }
                }
                .coordinateSpace(name: Self.scrollSpace)
                .background(
                    GeometryReader { g in
                        Color.clear.preference(key: AddViewportHeightKey.self, value: g.size.height)
                    }
                )
                // 用户自己一拖，就不再补第二下：自动滚是为了把卡带进视野，
                // 不是为了把人从他滚到的位置拽回来。
                // 用滚动阶段而不是拖拽手势判：ScrollView 的拖拽被它自己的 pan 吃掉，
                // 手势挂在外面收不全；阶段里的 tracking/interacting 就是手指在动。
                .onScrollPhaseChange { _, phase in
                    guard phase == .tracking || phase == .interacting else { return }
                    userScrolled = true
                    #if DEBUG
                    print("SCROLLDBG user drag \(phase)")
                    #endif
                }
            }
            .onPreferenceChange(AddViewportHeightKey.self) { viewportHeight = $0 }
            .onPreferenceChange(FailureCardFrameKey.self) { failureCardFrame = $0 }
            .scrollDismissesKeyboard(.interactively)
            // 顶边 8 点渐隐，**只在滚过顶之后出现**：停在顶部时第一张卡的顶边不能发灰，
            // 那是另一个毛病。滚起来之后卡片从切换器底下淡出去，不出现半截字。
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y > 0.5
            } action: { _, scrolled in
                scrolledFromTop = scrolled
            }
            .mask {
                if scrolledFromTop {
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [PaceColor.canvas.opacity(0), .black],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 8)
                        Color.black
                    }
                } else {
                    Color.black
                }
            }
            .background(PaceColor.canvas.ignoresSafeArea())
            // 切换器钉在导航栏下面，不跟内容滚。视觉上距导航栏 8、距卡片 12；
            // 多出来的 5+5 是把 34 高的胶囊撑成 44 的点击区，见 AddModeSwitcher。
            .safeAreaInset(edge: .top, spacing: 0) {
                if !isEditing {
                    AddModeSwitcher(mode: modeBinding)
                        .padding(.horizontal, PaceSpace.screen)
                        .padding(.top, 3)
                        // 下内距 7 → 2：切线和胶囊下沿的差要 ≤2 点。差得多了，中间那截画布
                        // 会让字看起来是「凭空从一条线下面开始」，而不是从玻璃底下滑过去。
                        .padding(.bottom, 2)
                        // 铺画布底色这件事试过去掉：结果一样。safeAreaInset 里的内容不会盖在
                        // 滚动内容上面——内容到「切线」就被裁了，玻璃底下永远是纯色。
                        .background(PaceColor.canvas)
                }
            }
            .navigationTitle(isEditing ? Copy.Add.editTitle : Copy.Add.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 工具栏两颗都交给系统画玻璃（2026-10-26 改回）：之前把系统底关掉、
                // 自己画胶囊，结果是玻璃挨着自画胶囊打架。现在两颗同一套材质，
                // 保存那颗就是一颗写着「保存」的玻璃按钮，系统会自己排开它们。
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.Add.closeA11y, systemImage: "xmark") { dismiss() }
                }
                // 一句话模式不放保存：值在草稿卡上，动作就在草稿卡上。
                if !showsSentence {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            save(force: false)
                        } label: {
                            // 玻璃上的字系统会自己调暗：暗色下不可用时只有 2.18:1。
                            // 可读性不交给系统猜，不可用时显式给 ink2（5.84:1）。
                            Text(Copy.Add.save)
                                .font(PaceType.button)
                                .foregroundStyle(isAmountValid ? PaceColor.ink : PaceColor.ink2)
                        }
                        .disabled(!isAmountValid)
                    }
                }
            }
            .alert(Copy.Confirm.Duplicate.title, isPresented: $duplicateNotice) {
                Button(Copy.Confirm.Duplicate.primary) { saveDuplicateAnyway() }
                Button(Copy.Confirm.Duplicate.secondary, role: .cancel) { duplicateDraft = nil }
            } message: {
                Text(Copy.Confirm.Duplicate.body)
            }
            #if DEBUG
            .safeAreaInset(edge: .top, spacing: 0) { DebugFaultBanner() }
            #endif
            .sheet(item: $reviewPayload) { payload in
                DraftReviewView(drafts: payload.drafts) {
                    onDone()
                    dismiss()
                }
                .presentationDetents([.large])
            }
            .onAppear {
                #if DEBUG
                // 只在调试包里：用启动参数把某张失败卡直接摆出来，不用点进设置造故障。
                // 验收要的是「标题、正文第一句、两颗按钮在同一张图里」，这个入口让那张图
                // 在任何字号下都能一次拍到，也顺便复现「键盘滚过之后卡长出来」那条路径。
                if let preview = Self.debugPreviewFailure {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        localFailure = preview.isLocalRule
                        inputFocused = false   // 真实路径里拆句时键盘也会退下去
                        failure = preview.failure
                    }
                }
                #endif
                // sheet 的入场动画结束后再聚焦，否则 keyboard 有可能不弹。
                // 调试入口摆卡时先不聚焦：键盘会把两颗按钮挤出画面，而这一屏的验收
                // 要的是标题、正文第一句、两颗按钮同时在一张图里。
                #if DEBUG
                if Self.debugPreviewFailure != nil { return }
                #endif
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    if showsSentence {
                        inputFocused = true
                    } else if isEditing {
                        amountFocused = true
                    }
                }
            }
        }
        .background(PaceColor.canvas)
        .presentationDetents([.large])
    }

    // MARK: - 一句话

    @ViewBuilder
    private var sentenceContent: some View {
        inputCard
        if busy {
            // 原地占住草稿卡的位置：解析完直接换卡，不让页面跳一下。
            SentenceParsingRow()
        }
        if let failure {
            failureCard(failure)
                .id(Self.failureAnchor)
                .background(
                    GeometryReader { g in
                        Color.clear.preference(
                            key: FailureCardFrameKey.self,
                            value: g.frame(in: .named(Self.scrollSpace))
                        )
                    }
                )
        }
        if let draft = sentenceDraft {
            inlineBlock(draft)
        } else if trimmed.isEmpty && !busy {
            exampleRow
        }
    }

    /// 只有输入框：没有小标题、没有 sparkles、没有说明行（spec §2）。
    private var inputCard: some View {
        // 占位和输入框并排放在一层里，而不是压在输入框上。
        // 压在框上时它是被框的高度裁的，最大字号下系统给的是「早饭 12，地…」——
        // 省略号就是把用户要读的话切掉（Camo 的规矩：不许加省略号）。
        // 并排之后它自己换行、把卡片撑高，默认字号下两者都是一行，一个像素都不动。
        ZStack(alignment: .topLeading) {
            // 占位自己画：系统那层灰在亮色卡片上只有 3.0:1，用户读的第一行字
            // 不该比说明文字还弱。空着的时候才出现，和输入框同一套字号与缩进。
            if sentenceText.isEmpty {
                Text(Copy.Ai.Input.placeholder)
                    .font(.body)
                    .foregroundStyle(PaceColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    // 和输入框同一个最小高度，单行时两者都在 44 里居中——
                    // 默认字号下占位的位置和改之前一像素不差。
                    .frame(minHeight: 44)
                    .allowsHitTesting(false)
            }

            TextField("", text: $sentenceText)
            .font(.body)
            // 只在「正在整理」那一段掉成 ink2：草稿卡一出来，这句话就是
            // 正在确认的东西，得和卡片里的值一样深。
            .foregroundStyle(busy ? PaceColor.ink2 : PaceColor.ink)
            .tint(PaceColor.ai)
            .focused($inputFocused)
            // 键名跟着「按下去会发生什么」走：没字的时候没有东西可发，键就是
            // 「完成」，写「发送」等于承诺一件不会发生的事；有字且走模型才是
            // 「发送」，走本机规则仍是「完成」。
            .submitLabel(submitKey)
            .onSubmit { Task { await parse() } }
            .disabled(busy || sentenceDraft != nil)
            .frame(minHeight: 44)
        }
        // 卡高 = 字高 + 上下内距，不写死：写死 44 之后字一放大就切在框里。
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 44)
        .padding(.horizontal, 18)
        .pacePadding(10, .vertical)
        .paceCardFill(20)
        .accessibilityLabel(Text(Copy.Sentence.fieldA11y))
    }

    /// 例句只在输入框空着、还没有草稿时出现。
    /// 三颗固定：放得下就一行，放不下换行——它在输入卡下面，长高只往下长，输入框不动。
    private var exampleRow: some View {
        PaceWrap(spacing: 8, lineSpacing: 8) {
            ForEach(Array(Copy.Ai.Input.examples.prefix(4)), id: \.self) { example in
                Button {
                    sentenceText = example
                    inputFocused = true
                } label: {
                    // 这三颗历史上是 13（自己盖掉了胶囊的 14）。零变化就是零变化，不借接字号顺手对齐。
                    Text(example).paceFont(13, .medium)
                }
                .buttonStyle(PillChipStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 一句话：就地确认

    @ViewBuilder
    private func inlineBlock(_ draft: DraftItem) -> some View {
        VStack(spacing: 12) {
            if inlineSaved {
                HStack(spacing: 6) {
                    // 勾说的是「账已经记上了」，不是「AI 干了点什么」：不上色，
                    // 只有失败才该是这个页面上有颜色的东西。
                    Image(systemName: "checkmark")
                        .font(PaceType.sectionTitle)
                        .foregroundStyle(PaceColor.ink)
                    Text(Copy.Ai.Input.confirmed)
                        .font(PaceType.body)
                        .foregroundStyle(PaceColor.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .paceCardFill(18)
                .accessibilityElement(children: .combine)
            } else {
                SentenceDraftCard(item: draft) { openReview(draft) }
                    .accessibilityFocused($draftFocused)

                if inlineSaveFailed { inlineFailureCard }

                Button { saveInline(draft) } label: {
                    HStack(spacing: 8) {
                        if savingInline {
                            ProgressView().tint(PaceColor.onAccent)
                        }
                        Text(Copy.Ai.Input.confirmInline)
                    }
                }
                .buttonStyle(PrimaryButtonStyle(height: 52))
                .disabled(savingInline)
                .accessibilityLabel("记上这笔账")

                Button {
                    openReview(draft)
                } label: {
                    Text(Copy.Ai.Input.editInline)
                        .font(PaceType.secondary)
                        .foregroundStyle(PaceColor.ink2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .transition(.opacity)
    }

    /// 没记上的那句话：停在这儿，按「记上」就是再试一次。
    private var inlineFailureCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Copy.Failed.InlineSave.title)
                .font(PaceType.sectionTitle)
                .foregroundStyle(PaceColor.ink)
            Text(Copy.Failed.InlineSave.body)
                .font(PaceType.secondary)
                .foregroundStyle(PaceColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .paceCardFill(18)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 一句话：失败

    #if DEBUG
    /// `-uiFaultCard offline|timeout|keyRejected|model|localRule`
    fileprivate static var debugPreviewFailure: DebugPreviewFailure? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiFaultCard"), i + 1 < args.count else { return nil }
        switch args[i + 1] {
        case "offline": return DebugPreviewFailure(failure: .offline, isLocalRule: false)
        case "timeout": return DebugPreviewFailure(failure: .timeout, isLocalRule: false)
        case "keyRejected": return DebugPreviewFailure(failure: .keyRejected, isLocalRule: false)
        case "model": return DebugPreviewFailure(failure: .unreadable, isLocalRule: false)
        case "localRule": return .localRule
        default: return nil
        }
    }

    /// 本机规则那一路没有自己的 AiFailure：它用 `localFailure` 这个开关换文案。
    fileprivate struct DebugPreviewFailure {
        let failure: AiFailure
        let isLocalRule: Bool
        static let localRule = DebugPreviewFailure(failure: .unreadable, isLocalRule: true)
    }
    #endif

    #if DEBUG
    fileprivate static var debugAmountArg: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiAmount"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    #endif

    /// 并排要的宽超过卡片内容宽，就把「¥」让到数字上面去。
    private var stacksCurrencyAboveAmount: Bool {
        guard cardContentWidth > 0, amountRowRulerWidth > 0 else { return false }
        return amountRowRulerWidth > cardContentWidth
    }

    private static let failureAnchor = "add.failure"
    private static let scrollSpace = "add.scroll"

    /// 第二拍的间隔。调试时可以用 `-uiSecondScroll 3` 把它拉长，
    /// 好在中间插一次拖拽，验「用户拖过就不再补第二下」。
    private static var secondScrollDelay: Double {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-uiSecondScroll"), i + 1 < args.count,
           let value = Double(args[i + 1]) { return value }
        #endif
        return 0.35
    }

    /// 卡已经整张看得见就不滚——默认字号下这张卡本来就在画面里，
    /// 让人一失败页面就跳一下，比不滚更糟（Ato 加的第一条）。
    /// 看得见的时候不滚，只在它被挡住时才滚，于是「跳不跳」只取决于它有没有被挡。
    private func isFailureCardFullyVisible() -> Bool {
        guard failureCardFrame != .zero, viewportHeight > 0 else { return false }
        return failureCardFrame.minY >= 0 && failureCardFrame.maxY <= viewportHeight
    }

    /// 滚两次：第一次在状态刚变、键盘还在往下退的时候，第二次等布局落定。
    /// 只滚一次会算在键盘的临时高度上，落下来的位置差一截。
    /// 第二下在用户已经自己拖过的情况下取消（Ato 加的第二条）。
    private func scrollToFailureIfNeeded(_ proxy: ScrollViewProxy) {
        #if DEBUG
        print("SCROLLDBG first scroll needed: visible=\(isFailureCardFullyVisible()) frame=\(failureCardFrame) viewport=\(viewportHeight)")
        #endif
        guard !isFailureCardFullyVisible() else { return }
        userScrolled = false
        proxy.scrollTo(Self.failureAnchor, anchor: .top)
        #if DEBUG
        // 验「用户拖过就不再补第二下」用：在第二拍之前把标记按下去，模拟一次真实拖拽。
        if ProcessInfo.processInfo.arguments.contains("-uiSimulateDrag") {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.secondScrollDelay * 0.5) {
                userScrolled = true
                print("SCROLLDBG simulated drag")
            }
        }
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.secondScrollDelay) {
            #if DEBUG
            print("SCROLLDBG second scroll: userScrolled=\(userScrolled) visible=\(isFailureCardFullyVisible())")
            #endif
            guard !userScrolled, !isFailureCardFullyVisible() else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(Self.failureAnchor, anchor: .top)
            }
        }
    }

    private func failureCard(_ failure: AiFailure) -> some View {
        let copy = failureCopy(failure, isLocal: localFailure)
        return VStack(alignment: .leading, spacing: 0) {
            Text(copy.title)
                .font(PaceType.sectionTitle)
                .foregroundStyle(PaceColor.ink)
            Text(copy.body)
                .font(PaceType.secondary)
                .paceLineSpacing(3)
                .foregroundStyle(PaceColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            // 两颗按钮：放得下就并排，放不下就上下两行各自占满。
            // 不缩字——字号是用户选的，为了塞进一行把字变小就是在他最需要看清的时候变小。
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { failureButtons(copy, failure, fill: false) }
                VStack(spacing: 8) { failureButtons(copy, failure, fill: true) }
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pacePadding(20)
        .paceCardFill(18)
    }

    @ViewBuilder
    private func failureButtons(_ copy: FailureCopy, _ failure: AiFailure, fill: Bool) -> some View {
        Button { primaryAction(failure) } label: {
            Text(copy.primary).frame(maxWidth: fill ? .infinity : nil)
        }
        .buttonStyle(GlassSecondaryStyle())
        if let secondary = copy.secondary {
            Button { secondaryAction(failure) } label: {
                Text(secondary).frame(maxWidth: fill ? .infinity : nil)
            }
            .buttonStyle(GlassSecondaryStyle())
        }
    }

    private struct FailureCopy {
        let title: String
        let body: String
        let primary: String
        let secondary: String?
    }

    private func failureCopy(_ failure: AiFailure, isLocal: Bool) -> FailureCopy {
        if isLocal {
            // 本机规则自己没拆开：只留「切到手动」。
            return FailureCopy(
                title: Copy.Ai.Fail.LocalRule.title,
                body: Copy.Ai.Fail.LocalRule.body,
                primary: Copy.Ai.Fail.LocalRule.primary,
                secondary: nil
            )
        }
        switch failure {
        case .offline:
            return FailureCopy(title: Copy.Ai.Fail.Offline.title, body: Copy.Ai.Fail.Offline.body,
                               primary: Copy.Ai.Fail.Offline.primary, secondary: Copy.Ai.Fail.Offline.secondary)
        case .timeout:
            return FailureCopy(title: Copy.Ai.Fail.Timeout.title, body: Copy.Ai.Fail.Timeout.body,
                               primary: Copy.Ai.Fail.Timeout.primary, secondary: Copy.Ai.Fail.Timeout.secondary)
        case .keyRejected:
            return FailureCopy(title: Copy.Ai.Fail.KeyRejected.title, body: Copy.Ai.Fail.KeyRejected.body,
                               primary: Copy.Ai.Fail.KeyRejected.primary, secondary: Copy.Ai.Fail.KeyRejected.secondary)
        case .quota:
            return FailureCopy(title: Copy.Ai.Fail.KeyRejected.title, body: Copy.Ai.Fail.Quota.body,
                               primary: Copy.Ai.Fail.KeyRejected.primary, secondary: Copy.Ai.Fail.KeyRejected.secondary)
        case .badAddress:
            return FailureCopy(title: Copy.Ai.Fail.BadAddress.title, body: Copy.Ai.Fail.BadAddress.body,
                               primary: Copy.Ai.Fail.BadAddress.primary, secondary: Copy.Ai.Fail.BadAddress.secondary)
        case .certificate:
            return FailureCopy(title: Copy.Ai.Fail.Certificate.title, body: Copy.Ai.Fail.Certificate.body,
                               primary: Copy.Ai.Fail.Certificate.primary, secondary: Copy.Ai.Fail.Certificate.secondary)
        case .server(let code) where (400...499).contains(code):
            // 4xx 是「它收到了、但这次请求它不收」，多半是模型名不对——让人去改模型，
            // 不是让他等一等再试。实测那台服务器 400 的原话是 Model is unavailable。
            return FailureCopy(title: Copy.Ai.Fail.ModelRejected.title, body: Copy.Ai.Fail.ModelRejected.body,
                               primary: Copy.Ai.Fail.ModelRejected.primary, secondary: Copy.Ai.Fail.ModelRejected.secondary)
        case .server:
            return FailureCopy(title: Copy.Ai.Fail.Server.title, body: Copy.Ai.Fail.Server.body,
                               primary: Copy.Ai.Fail.Server.primary, secondary: Copy.Ai.Fail.Server.secondary)
        case .addressUnreachable, .notConfigured:
            return FailureCopy(title: Copy.Ai.Fail.Unreachable.title, body: Copy.Ai.Fail.Unreachable.body,
                               primary: Copy.Ai.Fail.Unreachable.primary, secondary: Copy.Ai.Fail.Unreachable.secondary)
        default:
            return FailureCopy(title: Copy.Ai.Fail.Model.title, body: Copy.Ai.Fail.Model.body,
                               primary: Copy.Ai.Fail.Model.primary, secondary: Copy.Ai.Fail.Model.secondary)
        }
    }

    private func primaryAction(_ failure: AiFailure) {
        let copy = failureCopy(failure, isLocal: localFailure)
        if copy.primary == Copy.Ai.Fail.KeyRejected.primary {
            dismiss()
        } else if copy.primary == Copy.Ai.Fail.Offline.primary {
            runLocal()
        } else {
            goManualFromFailure()
        }
    }

    /// 副按钮按它写的那句话办事，不按失败类型猜：
    /// 「切到手动」就去手动，「用本机规则再试」才重拆。先前这里只看是不是本机失败，
    /// 结果断网那张卡的「切到手动」按下去又去联网拆了一遍。
    private func secondaryAction(_ failure: AiFailure) {
        let copy = failureCopy(failure, isLocal: localFailure)
        if copy.secondary == Copy.Ai.Fail.toManual {
            goManualFromFailure()
        } else {
            runLocal()
        }
    }

    /// 切到手动：把用户原来那句话原样带进备注（备注已经写了就不动它）。
    /// 输入框里那句不清，切回一句话还在。
    private func goManualFromFailure() {
        if note.isEmpty, !trimmed.isEmpty {
            note = trimmed
        }
        selectMode(.manual)
    }

    // MARK: - 一句话：拆句

    private func parse() async {
        guard canSubmit else { return }
        failure = nil
        localFailure = false
        sentenceDraft = nil
        inlineSaved = false
        inlineSaveFailed = false
        pumpedDraftId = nil
        inputFocused = false
        busy = true
        defer { busy = false }

        #if DEBUG
        // 调试构建里造出来的失败，只为把那几张卡看一眼；正式包里没有这段。
        if DebugFaults.shared.take(.keyRejected) { failure = .keyRejected; return }
        if DebugFaults.shared.take(.offline) { failure = .offline; return }
        // 模型没整理出来那张是五张里最长、唯一带两颗按钮的，没人见过就先把它造出来。
        if DebugFaults.shared.take(.model) { failure = .unreadable; return }
        #endif

        let sentence = trimmed
        let today = LedgerStore.shared.todayIso

        if ai.usesRemoteModel, let config = ai.config {
            do {
                let parsed = try await AiDraftClient.parse(text: sentence, todayIso: today, config: config)
                present(parsed)
            } catch let error as AiFailure {
                failure = error
            } catch {
                failure = .unreadable
            }
            return
        }

        // 本机规则这条路只有 runLocal 一处：先前这里另写了一遍解析，
        // 结果「本机规则拆不开」那个调试故障永远不触发——开关是开的，卡永远不出来。
        runLocal()
    }

    /// 一笔且齐全就地确认；多笔或缺字段才去确认页。
    private func present(_ parsed: [DraftItem]) {
        if parsed.count == 1, let only = parsed.first, only.missingFields.isEmpty {
            withAnimation(.easeOut(duration: 0.2)) { sentenceDraft = only }
            draftFocused = true
            return
        }
        // 解析完把键盘收掉：多笔要一起看，键盘挡着就是白跳一页。
        inputFocused = false
        reviewPayload = ReviewPayload(drafts: parsed)
    }

    private func runLocal() {
        failure = nil
        localFailure = false
        sentenceDraft = nil
        inlineSaved = false
        inlineSaveFailed = false
        pumpedDraftId = nil
        #if DEBUG
        if DebugFaults.shared.take(.localRule) {
            localFailure = true
            failure = .unreadable
            return
        }
        #endif
        let parsed = LocalDrafts.parse(text: trimmed, todayIso: LedgerStore.shared.todayIso)
        if parsed.isEmpty {
            localFailure = true
            failure = .unreadable
            return
        }
        present(parsed)
    }

    // MARK: - 切换填法

    private var modeBinding: Binding<AddFillMode> {
        Binding(
            get: { mode },
            set: { selectMode($0) }
        )
    }

    private func selectMode(_ newMode: AddFillMode) {
        guard newMode != mode else { return }
        if newMode == .manual {
            pumpDraftIntoForm()
            inputFocused = false
        } else {
            amountFocused = false
        }
        withAnimation(.easeOut(duration: 0.18)) { mode = newMode }
    }

    /// 一句话刚解析出的那张草稿，切到手动时把值带进表单。
    /// 只带一次：用户改了表单再切回来，不能被同一张草稿再盖一遍。
    private func pumpDraftIntoForm() {
        guard let draft = sentenceDraft, pumpedDraftId != draft.id else { return }
        pumpedDraftId = draft.id
        amountText = draft.amountText.isEmpty
            ? (draft.amountMinor > 0 ? Money.shared.formatMinor(amountMinor: draft.amountMinor) : "")
            : draft.amountText
        type = draft.type
        if !draft.category.isEmpty { category = draft.category }
        if !draft.localDate.isEmpty { localDate = draft.localDate }
        note = draft.note
        errorText = nil
    }

    // MARK: - 手动：四张卡

    @ViewBuilder
    private var manualContent: some View {
        amountTypeCard
        attributionCard
        noteCard
        if showsBudgetToggle {
            budgetCard
        }
        if type == TxnTypes.refund {
            refundCard
        }
    }

    /// 卡 1：金额和类型。这笔多少、是进是出，是同一个判断的两半，不拆成两张卡。
    private var amountTypeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel(Copy.Add.Section.amount)

                // 并排放不下的时候，「¥」让到数字上面去，数字自己占一整行。
                // 最大档实测：卡片内容宽 322，并排时「¥」加间距吃掉 40，留给数字的只有 282；
                // 「1280.50」在这个字号下要 312，于是框里显示成「1280…」——省略号，
                // 正好切在用户要核对的那个数上。缩字不行（字是用户选的），
                // 那就换布局：Camo 的规矩是宁可换行，不许缩字也不许省略。
                Group {
                    if stacksCurrencyAboveAmount {
                        VStack(alignment: .leading, spacing: 0) {
                            currencyGlyph
                            // 系统输入框自己左右各留约 8 点内距。金额要占满整行时把它收回来，
                            // 否则字往右缩 8 点，宽出来的那点正好又不够七位数字用。
                            amountField
                                .padding(.horizontal, -Self.textFieldInset)
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            currencyGlyph
                            amountField
                        }
                    }
                }

                if let amountMessage {
                    Text(amountMessage)
                        .font(PaceType.secondary)
                        .foregroundStyle(PaceColor.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: AmountCardWidthKey.self, value: g.size.width)
                }
            )

            typeChips
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paceCard()
        // 量两样东西：卡片内容有多宽、并排那一行需要多宽。都在背景里量，不占版面。
        .background(alignment: .topLeading) { amountRuler }
        .onPreferenceChange(AmountCardWidthKey.self) { cardContentWidth = $0 }
        .onPreferenceChange(AmountRulerWidthKey.self) { amountRowRulerWidth = $0 }
    }

    /// 系统 TextField 的内距，收回来时用。
    private static let textFieldInset: CGFloat = 8

    private var currencyGlyph: some View {
        Text("¥")
            .font(PaceType.screenTitle)
            .foregroundStyle(PaceColor.ink2)
    }

    private var amountField: some View {
        TextField("", text: $amountText)
            // 金额跟着字长，封顶 1.5 倍（48 → 72）。上限不是拍的：并排的宽度放不下时
            // 「¥」已经让到数字上面，数字能用的宽度约 307 点；「1280.50」在这个字体下
            // 一点字号约 4.1 点宽，307 ÷ 4.1 ≈ 75——1.6 倍（77）差 8 点，1.5 倍（72）
            // 还余 12 点。再大的话七位数字又会变成「1280…」，省略号正好切在要核对的地方。
            .paceFont(48, .heavy, design: .rounded, relativeTo: .largeTitle, cap: 1.5)
            .monospacedDigit()
            .foregroundStyle(PaceColor.ink)
            .keyboardType(.decimalPad)
            .textFieldStyle(.plain)
            .focused($amountFocused)
            // 不缩字：放不下就换行，字是用户选的。
            // （这里原来挂着 minimumScaleFactor(1)，是不缩字的写法——但这条规则只认「0 处」，
            //   一个数字从 0.6 一路改到 1，说明下一个人还会再改它一次。整条删掉。）
            .accessibilityLabel(Text(Copy.Add.Section.amount))
            .onChange(of: amountText) { _, _ in
                errorText = nil
            }
    }

    /// 尺子：拿「¥ + 0000.00」量并排要多少宽。
    /// 用固定的六位小数，不用当前输入——不然用户刚打到第四位，版式就翻一次。
    private var amountRuler: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("¥").font(PaceType.screenTitle)
            Text("0000.00")
                .paceFont(48, .heavy, design: .rounded, relativeTo: .largeTitle, cap: 1.5)
                .monospacedDigit()
                .background(
                    GeometryReader { g in
                        Color.clear.preference(key: AmountNumberWidthKey.self, value: g.size.width)
                    }
                )
        }
        .hidden()
        .fixedSize()
        .background(
            GeometryReader { g in
                Color.clear.preference(key: AmountRulerWidthKey.self, value: g.size.width)
            }
        )
    }

    /// 四个类型胶囊：固定四颗，放不下就换行，不横着滚。
    /// 横着滚在大字号下把「退款」切成一个「退」——切在半颗胶囊上，读到的是坏掉的词。
    private var typeChips: some View {
        PaceWrap(spacing: 8, lineSpacing: 8) {
            ForEach(TxnTypes.all, id: \.0) { value, label in
                Button {
                    type = value
                } label: {
                    Text(label)
                }
                .buttonStyle(PillChipStyle(selected: type == value))
                .accessibilityLabel(Text(label))
                .accessibilityAddTraits(type == value ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(Copy.Add.typeGroupA11y))
    }

    /// 卡 2：分类、日期、账户。分类最高频，放最上面；卡里只这一条分隔线。
    private var attributionCard: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                fieldLabel(Copy.Add.Section.category)

                PaceWrap(spacing: 8, lineSpacing: 8) {
                    ForEach(categoryNames, id: \.self) { name in
                        Button {
                            category = name
                        } label: {
                            Text(name)
                        }
                        .buttonStyle(PillChipStyle(selected: category == name))
                        .accessibilityAddTraits(category == name ? .isSelected : [])
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PaceSpace.cardPadding)
            .padding(.top, PaceSpace.cardPadding)
            .padding(.bottom, 16)

            Rectangle()
                .fill(PaceColor.divider)
                .frame(height: 0.5)
                .padding(.leading, PaceSpace.cardPadding)

            dateRow
            accountRow
        }
        .paceCard(radius: PaceRadius.list, padding: 0)
    }

    private var dateRow: some View {
        // 放得下就一行，放不下就上下两行：字是用户选的，不缩也不截。
        // 写死 lineLimit(1) 之后，大字号下日期会变成「今天 · 10月2…」——那是把日期截掉了。
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                dateRowLabel
                Spacer(minLength: 12)
                dateRowValue
            }
            VStack(alignment: .leading, spacing: 4) {
                dateRowLabel
                dateRowValue
            }
        }
        .frame(minHeight: 52)
        // .compact 的 DatePicker 只负责交互，显示用上面那行「今天 · 10月26日」。
        .overlay(alignment: .trailing) {
            DatePicker("", selection: dateBinding, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                // 0.02 在大字号下仍看得见一层影子；0.001 看不见，但点击照收。
                .opacity(0.001)
                .frame(width: 170, height: 44)
                // 裁掉：大字号下那颗紧凑选择器会画得比 170 宽，0.02 的透明度也看得出影子。
                .clipped()
                .accessibilityLabel(Text(Copy.Draft.Field.date))
        }
        .padding(.horizontal, PaceSpace.cardPadding)
        .contentShape(Rectangle())
    }

    private var dateRowLabel: some View {
        Text(Copy.Draft.Field.date)
            .font(PaceType.rowTitle)
            .foregroundStyle(PaceColor.ink)
    }

    private var dateRowValue: some View {
        HStack(spacing: 6) {
            Text(dateDisplay)
                .font(PaceType.body)
                .foregroundStyle(PaceColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "chevron.up.chevron.down")
                .paceFont(11, .semibold)
                .foregroundStyle(PaceColor.ink3)
        }
    }

    private var accountRow: some View {
        HStack(spacing: 12) {
            Text(Copy.Draft.Field.account)
                .font(PaceType.rowTitle)
                .foregroundStyle(PaceColor.ink)

            Spacer(minLength: 12)

            Menu {
                ForEach(Self.accountPresets, id: \.self) { preset in
                    Button {
                        account = preset
                    } label: {
                        if account == preset {
                            Label(preset, systemImage: "checkmark")
                        } else {
                            Text(preset)
                        }
                    }
                }
                Divider()
                Button {
                    customAccountDraft = account
                    showCustomAccount = true
                } label: {
                    Text("自定义…")
                }
            } label: {
                HStack(spacing: 4) {
                    Text(account.isEmpty ? Copy.Add.accountPlaceholder : account)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .paceFont(11, .semibold)
                        .foregroundStyle(PaceColor.ink3)
                }
                .font(PaceType.body)
                .foregroundStyle(PaceColor.ink2)
            }
        }
        .frame(minHeight: 52)
        .padding(.horizontal, PaceSpace.cardPadding)
        .contentShape(Rectangle())
        .alert("自定义账户", isPresented: $showCustomAccount) {
            TextField("账户名称", text: $customAccountDraft)
            Button("取消", role: .cancel) {}
            Button("好") { applyCustomAccount() }
        }
    }

    /// 卡 3：备注。
    private var noteCard: some View {
        HStack(spacing: 12) {
            Text(Copy.Add.Section.note)
                .font(PaceType.rowTitle)
                .foregroundStyle(PaceColor.ink)

            TextField(
                "",
                text: $note,
                prompt: Text(Copy.Add.notePlaceholder).foregroundColor(PaceColor.ink2)
            )
            .font(PaceType.body)
            .foregroundStyle(PaceColor.ink)
                .submitLabel(.done)
        }
        .frame(minHeight: 24)
        .paceCard()
    }

    /// 卡 4：计入预算 / 退款关联。
    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 自画勾选块：系统开关在暗色下圆点和轨道都是白的，开和关分不出来。
            Toggle(isOn: $countInBudget) {
                Text("计入每日预算")
                    .font(PaceType.rowTitle)
                    .foregroundStyle(PaceColor.ink)
            }
            .toggleStyle(CheckBlockToggleStyle())
            .accessibilityRepresentation {
                Toggle(isOn: $countInBudget) {
                    Text("计入每日预算")
                }
            }

            Text("关闭后仍计入总支出统计")
                .font(PaceType.secondary)
                .foregroundStyle(PaceColor.ink2)
        }
        .paceCard()
    }

    private var refundCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldLabel(Copy.Add.sectionRefundOriginal)

            if refundCandidates.isEmpty {
                Text(Copy.Add.noRefundCandidates)
                    .font(PaceType.secondary)
                    .foregroundStyle(PaceColor.ink2)
            } else {
                Menu {
                    ForEach(refundCandidates, id: \.id) { candidate in
                        Button {
                            refundOfId = candidate.id
                        } label: {
                            if refundOfId == candidate.id {
                                Label(refundCandidateLabel(candidate), systemImage: "checkmark")
                            } else {
                                Text(refundCandidateLabel(candidate))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(refundSelectionLabel)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.up.chevron.down")
                            .paceFont(11, .semibold)
                            .foregroundStyle(PaceColor.ink3)
                    }
                    .font(PaceType.body)
                    .foregroundStyle(PaceColor.ink2)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paceCard()
    }

    // MARK: - 入账（就确认）

    private func saveInline(_ draft: DraftItem) {
        guard !savingInline else { return }
        savingInline = true
        let outcome = DraftSaver.save([draft])
        if outcome.saved > 0 {
            finishInline()
            return
        }
        savingInline = false
        if !outcome.duplicated.isEmpty {
            duplicateDraft = draft
            duplicateNotice = true
        } else {
            // 账没记上，话也不能说成「那句话没读懂」。
            withAnimation { inlineSaveFailed = true }
        }
    }

    private func finishInline() {
        withAnimation(.easeOut(duration: 0.2)) { inlineSaved = true }
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            onDone()
            dismiss()
        }
    }

    private func openReview(_ draft: DraftItem) {
        reviewPayload = ReviewPayload(drafts: [draft])
    }

    // MARK: - 保存（手动）

    private func save(force: Bool) {
        errorText = nil
        duplicateDraft = nil
        let input = makeSaveInput(
            id: txnId,
            type: type,
            amountText: amountText,
            category: category,
            note: note,
            localDate: localDate,
            account: account,
            countInBudget: countInBudget,
            refundOfId: refundOfId,
            forceSave: force
        )
        let result = LedgerStore.shared.api.saveTransaction(input: input)
        if result.isSuccess {
            onDone()
            dismiss()
        } else if result.errorCode == "DUPLICATE_FINGERPRINT" {
            duplicateNotice = true
        } else {
            errorText = describeError(result.errorCode)
        }
    }

    /// 用户说「照样记」：看这次重复是从手动保存来的，还是从一句话的「记上」来的。
    private func saveDuplicateAnyway() {
        if let draft = duplicateDraft {
            duplicateDraft = nil
            guard !savingInline else { return }
            savingInline = true
            let outcome = DraftSaver.save([draft], force: true)
            savingInline = false
            if outcome.saved > 0 {
                finishInline()
            } else {
                withAnimation { inlineSaveFailed = true }
            }
            return
        }
        save(force: true)
    }

    // MARK: - 派生状态

    private var isEditing: Bool { txnId != nil }

    /// 编辑账单永远走手动；一句话只在新建时出现。
    private var showsSentence: Bool { !isEditing && mode == .sentence }

    private var trimmed: String {
        sentenceText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool { !trimmed.isEmpty && !busy }

    /// 键盘上那颗键的名字：没字 → 完成，有字且走模型 → 发送，有字走本机 → 完成。
    private var submitKey: SubmitLabel {
        trimmed.isEmpty || !ai.usesRemoteModel ? .done : .send
    }

    private var showsBudgetToggle: Bool {
        type == TxnTypes.expense || type == TxnTypes.refund
    }

    private var isAmountValid: Bool {
        Money.shared.parseToMinor(text: amountText) != nil
    }

    private var amountMessage: String? {
        if let errorText { return errorText }
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAmountValid else { return nil }
        return Copy.Errors.amount
    }

    private var categoryNames: [String] {
        var names = categories.map(\.name)
        if !category.isEmpty && !names.contains(category) {
            names.append(category)
        }
        return names
    }

    private var refundSelection: LedgerTransaction? {
        guard let refundOfId else { return nil }
        if let candidate = refundCandidates.first(where: { $0.id == refundOfId }) {
            return candidate
        }
        return LedgerStore.shared.api.transaction(id: refundOfId)
    }

    private var refundSelectionLabel: String {
        guard let txn = refundSelection else { return "选择原账单" }
        return refundCandidateLabel(txn)
    }

    private func refundCandidateLabel(_ txn: LedgerTransaction) -> String {
        let title = txn.note.isEmpty ? txn.category : txn.note
        let amount = LedgerStore.shared.format(txn.amountMinor, currency: txn.currency)
        return "\(shortDateLabel(txn.localDate)) · \(title) · \(amount)"
    }

    private func applyCustomAccount() {
        let trimmed = customAccountDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            account = trimmed
        }
    }

    // MARK: - 日期换算（localDate ISO ⇄ Date，固定格式 + 账本时区）

    private var ledgerTimeZone: TimeZone {
        TimeZone(identifier: LedgerStore.shared.timezoneId) ?? .current
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { isoDate(from: localDate) ?? Date() },
            set: { localDate = isoText(from: $0) }
        )
    }

    private func isoDate(from iso: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = ledgerTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)
    }

    private func isoText(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = ledgerTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func localizedDay(_ date: Date, includeYear: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = ledgerTimeZone
        formatter.setLocalizedDateFormatFromTemplate(includeYear ? "yMMMd" : "MMMd")
        return formatter.string(from: date)
    }

    private var dateDisplay: String {
        guard let date = isoDate(from: localDate) else { return localDate }
        let today = LedgerStore.shared.todayIso
        if localDate == today {
            return "今天 · " + localizedDay(date, includeYear: false)
        }
        let yesterday = PaceDates.shared.localDateFor(
            epochMillis: PaceDates.shared.nowEpochMillis() - 86_400_000,
            timezoneId: LedgerStore.shared.timezoneId
        )
        if localDate == yesterday {
            return "昨天 · " + localizedDay(date, includeYear: false)
        }
        let sameYear = localDate.prefix(4) == today.prefix(4)
        return localizedDay(date, includeYear: !sameYear)
    }

    private func shortDateLabel(_ iso: String) -> String {
        guard let date = isoDate(from: iso) else { return iso }
        return localizedDay(date, includeYear: iso.prefix(4) != localDate.prefix(4))
    }

    // MARK: - 小标题

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(PaceType.caption.weight(.semibold))
            .foregroundStyle(PaceColor.ink2)
    }
}
