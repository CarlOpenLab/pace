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
            .scrollDismissesKeyboard(.interactively)
            .background(PaceColor.canvas.ignoresSafeArea())
            // 切换器钉在导航栏下面，不跟内容滚。视觉上距导航栏 8、距卡片 12；
            // 多出来的 5+5 是把 34 高的胶囊撑成 44 的点击区，见 AddModeSwitcher。
            .safeAreaInset(edge: .top, spacing: 0) {
                if !isEditing {
                    AddModeSwitcher(mode: modeBinding)
                        .padding(.horizontal, PaceSpace.screen)
                        .padding(.top, 3)
                        .padding(.bottom, 7)
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
                                .font(.system(size: 16, weight: .semibold))
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
            .sheet(item: $reviewPayload) { payload in
                DraftReviewView(drafts: payload.drafts) {
                    onDone()
                    dismiss()
                }
                .presentationDetents([.large])
            }
            .onAppear {
                // sheet 的入场动画结束后再聚焦，否则 keyboard 有可能不弹。
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
        }
        if let draft = sentenceDraft {
            inlineBlock(draft)
        } else if trimmed.isEmpty && !busy {
            exampleRow
        }
    }

    /// 只有输入框：没有小标题、没有 sparkles、没有说明行（spec §2）。
    private var inputCard: some View {
        TextField("", text: $sentenceText)
            .font(.system(size: 17))
            // 占位自己画：系统那层灰在亮色卡片上只有 3.0:1，用户读的第一行字
            // 不该比说明文字还弱。空着的时候才出现，和输入框同一套字号与缩进。
            .overlay(alignment: .leading) {
                if sentenceText.isEmpty {
                    Text(Copy.Ai.Input.placeholder)
                        .font(.system(size: 17))
                        .foregroundStyle(PaceColor.ink2)
                        .allowsHitTesting(false)
                }
            }
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
            .frame(height: 44)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .paceCardFill(20)
            .accessibilityLabel(Text(Copy.Sentence.fieldA11y))
    }

    /// 例句只在输入框空着、还没有草稿时出现。
    private var exampleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(Copy.Ai.Input.examples.prefix(4)), id: \.self) { example in
                    Button {
                        sentenceText = example
                        inputFocused = true
                    } label: {
                        Text(example).font(.system(size: 13))
                    }
                    .buttonStyle(PillChipStyle())
                }
            }
        }
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
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PaceColor.ink)
                    Text(Copy.Ai.Input.confirmed)
                        .font(.system(size: 15))
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
                        .font(.system(size: 13, weight: .medium))
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
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PaceColor.ink)
            Text(Copy.Failed.InlineSave.body)
                .font(.system(size: 13))
                .foregroundStyle(PaceColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .paceCardFill(18)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 一句话：失败

    private func failureCard(_ failure: AiFailure) -> some View {
        let copy = failureCopy(failure, isLocal: localFailure)
        return VStack(alignment: .leading, spacing: PaceSpace.inner) {
            Text(copy.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(PaceColor.ink)
            Text(copy.body).font(.system(size: 13)).foregroundStyle(PaceColor.ink2)
            HStack(spacing: 10) {
                Button(copy.primary) { primaryAction(failure) }
                    .buttonStyle(PillChipStyle(selected: true))
                if let secondary = copy.secondary {
                    Button(secondary) { secondaryAction(failure) }
                        .buttonStyle(PillChipStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .paceCardFill(18)
    }

    private struct FailureCopy {
        let title: String
        let body: String
        let primary: String
        let secondary: String?
    }

    private func failureCopy(_ failure: AiFailure, isLocal: Bool) -> FailureCopy {
        if isLocal {
            // 本机规则自己没拆开：只留「手动记这笔」。
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
        case .addressUnreachable, .notConfigured:
            return FailureCopy(title: Copy.Ai.Fail.Offline.title, body: Copy.Ai.Fail.Offline.body,
                               primary: Copy.Ai.Fail.Offline.primary, secondary: Copy.Ai.Fail.Offline.secondary)
        default:
            return FailureCopy(title: Copy.Ai.Fail.Model.title, body: Copy.Ai.Fail.Model.body,
                               primary: Copy.Ai.Fail.Model.primary, secondary: Copy.Ai.Fail.Model.secondary)
        }
    }

    private func primaryAction(_ failure: AiFailure) {
        let copy = failureCopy(failure, isLocal: localFailure)
        switch copy.primary {
        case Copy.Ai.Fail.KeyRejected.primary:
            dismiss()
        case Copy.Ai.Fail.Offline.primary:
            runLocal()
        case Copy.Ai.Fail.Timeout.primary, Copy.Ai.Fail.Model.primary, Copy.Ai.Fail.LocalRule.primary:
            goManualFromFailure()
        default:
            goManualFromFailure()
        }
    }

    private func secondaryAction(_ failure: AiFailure) {
        if localFailure {
            goManualFromFailure()
        } else {
            runLocal()
        }
    }

    /// 手动记这笔：把用户原来那句话原样带进备注（备注已经写了就不动它）。
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
        if DebugFaults.take(.keyRejected) { failure = .keyRejected; return }
        if DebugFaults.take(.offline) { failure = .offline; return }
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

        let parsed = LocalDrafts.parse(text: sentence, todayIso: today)
        if parsed.isEmpty {
            localFailure = true
            failure = .unreadable
            return
        }
        present(parsed)
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
        if DebugFaults.take(.localRule) {
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

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("¥")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(PaceColor.ink2)

                    TextField("", text: $amountText)
                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(PaceColor.ink)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.plain)
                        .focused($amountFocused)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .accessibilityLabel(Text(Copy.Add.Section.amount))
                        .onChange(of: amountText) { _, _ in
                            errorText = nil
                        }
                }

                if let amountMessage {
                    Text(amountMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(PaceColor.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            typeChips
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paceCard()
    }

    /// 四个类型胶囊：大字号或窄屏时横向滚动，不换行。
    private var typeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(Copy.Add.typeGroupA11y))
    }

    /// 卡 2：分类、日期、账户。分类最高频，放最上面；卡里只这一条分隔线。
    private var attributionCard: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                fieldLabel(Copy.Add.Section.category)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
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
                }
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
        HStack(spacing: 12) {
            Text(Copy.Draft.Field.date)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(PaceColor.ink)

            Spacer(minLength: 12)

            Text(dateDisplay)
                .font(.system(size: 15))
                .foregroundStyle(PaceColor.ink2)
                .lineLimit(1)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PaceColor.ink3)
        }
        .frame(minHeight: 52)
        // .compact 的 DatePicker 只负责交互，显示用上面那行「今天 · 10月26日」。
        .overlay(alignment: .trailing) {
            DatePicker("", selection: dateBinding, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .opacity(0.02)
                .frame(width: 170, height: 44)
                .accessibilityLabel(Text(Copy.Draft.Field.date))
        }
        .padding(.horizontal, PaceSpace.cardPadding)
        .contentShape(Rectangle())
    }

    private var accountRow: some View {
        HStack(spacing: 12) {
            Text(Copy.Draft.Field.account)
                .font(.system(size: 15, weight: .medium))
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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PaceColor.ink3)
                }
                .font(.system(size: 15))
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
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(PaceColor.ink)

            TextField("例如：午饭", text: $note)
                .font(.system(size: 15))
                .foregroundStyle(PaceColor.ink)
                .submitLabel(.done)
        }
        .frame(minHeight: 24)
        .paceCard()
    }

    /// 卡 4：计入预算 / 退款关联。
    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $countInBudget) {
                Text("计入每日预算")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(PaceColor.ink)
            }
            .tint(PaceColor.accent)

            Text("关闭后仍计入总支出统计")
                .font(.system(size: 13))
                .foregroundStyle(PaceColor.ink2)
        }
        .paceCard()
    }

    private var refundCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            fieldLabel(Copy.Add.sectionRefundOriginal)

            if refundCandidates.isEmpty {
                Text(Copy.Add.noRefundCandidates)
                    .font(.system(size: 13))
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
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PaceColor.ink3)
                    }
                    .font(.system(size: 15))
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
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(PaceColor.ink2)
    }
}
