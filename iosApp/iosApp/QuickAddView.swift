import SwiftUI
import shared

/// 一句话记账（输入页）：一句话进来，本机规则或用户自己填的服务拆成草稿。
/// 一笔且字段齐全时就地确认，不跳页（docs/DESIGN-quickadd-primary.md）。
struct QuickAddView: View {
    let initialText: String
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ai: AiSettings
    @EnvironmentObject private var state: AppState

    @State private var text: String
    @State private var busy = false
    @State private var failure: AiFailure?
    /// 失败是「本机规则」那一路时，文案和按钮都不一样。
    @State private var localFailure = false

    /// 多笔或缺字段：走确认页。
    @State private var drafts: [DraftItem] = []
    @State private var showReview = false

    /// 一笔且齐全：留在这一页，就地确认。
    @State private var inlineDraft: DraftItem?
    @State private var savingInline = false
    @State private var inlineSaved = false
    @State private var duplicateNotice = false
    /// 「记上」没成功：跟「这次没整理出来」是两件事，不能复用那张卡。
    @State private var inlineSaveFailed = false

    @FocusState private var inputFocused: Bool
    @AccessibilityFocusState private var draftFocused: Bool

    private var examples: [String] { Copy.Ai.Input.examples }

    init(initialText: String = "", onSaved: @escaping () -> Void) {
        self.initialText = initialText
        self.onSaved = onSaved
        _text = State(initialValue: initialText)
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool { !trimmed.isEmpty && !busy }

    /// 确认中或者已经记上了：例句、说明、手动入口都先让开。
    private var isConfirming: Bool { inlineDraft != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PaceSpace.cardGap) {
                    inputCard
                    if busy { parsingRow }
                    if let failure { failureCard(failure) }
                    if let draft = inlineDraft {
                        inlineBlock(draft)
                    } else {
                        exampleRow
                        hintLine
                        manualButton
                    }
                }
                .padding(.horizontal, PaceSpace.screen)
                .padding(.vertical, PaceSpace.cardGap)
            }
            .background(PaceColor.canvas)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(Copy.Ai.Input.title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showReview) {
                DraftReviewView(drafts: drafts) {
                    onSaved()
                    dismiss()
                }
            }
            .alert(Copy.Confirm.Duplicate.title, isPresented: $duplicateNotice) {
                Button(Copy.Confirm.Duplicate.primary) { saveDuplicateAnyway() }
                Button(Copy.Confirm.Duplicate.secondary, role: .cancel) {}
            } message: {
                Text(Copy.Confirm.Duplicate.body)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            // 让 sheet 动画先走完再起键盘，否则键盘和 sheet 抢动画。
            try? await Task.sleep(nanoseconds: 250_000_000)
            if !isConfirming && !busy { inputFocused = true }
        }
    }

    // MARK: - 输入卡

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: PaceSpace.inner) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold))
                Text(Copy.Ai.Input.label).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(PaceColor.ai)

            // 单行：一句话记账本来就说一句话，也保证下面的草稿卡不被输入框顶出屏幕。
            TextField(Copy.Ai.Input.placeholder, text: $text)
                .font(.system(size: 17))
                // 只在「正在整理」那一段掉成 ink2：草稿卡一出来，这句话就是
                // 正在确认的东西，得和卡片里的值一样深。
                .foregroundStyle(busy ? PaceColor.ink2 : PaceColor.ink)
                .tint(PaceColor.ai)
                .focused($inputFocused)
                .submitLabel(.send)
                .onSubmit { Task { await parse() } }
                .disabled(busy || isConfirming)
                .frame(height: 44)
                .accessibilityLabel("一句话记账输入框")
                .accessibilityHint("写一句话，按键盘上的发送")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .paceCardFill(20)
    }

    /// 解析中：原地一行，不跳页、不清空输入、不铺骨架屏。
    private var parsingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(Copy.Ai.Input.parsing)
                .font(.system(size: 13))
                .foregroundStyle(PaceColor.ink2)
        }
        .frame(height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在整理")
    }

    private var exampleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(examples, id: \.self) { example in
                    Button {
                        text = example
                        inputFocused = true
                    } label: {
                        Text(example).font(.system(size: 13))
                    }
                    .buttonStyle(PillChipStyle())
                }
            }
        }
    }

    private var hintLine: some View {
        Text(hintText)
            .font(.system(size: 12))
            .foregroundStyle(PaceColor.ink2)
    }

    /// 说明一行：没填三项、开关开着、开关关着，三种说法。
    private var hintText: String {
        if ai.config == nil { return Copy.Ai.Input.noteNoKey }
        return ai.usesRemoteModel ? Copy.Ai.Input.noteRemote : Copy.Ai.Input.noteLocalOff
    }

    private var manualButton: some View {
        Button(Copy.Ai.Input.manual) { goManual() }
        .buttonStyle(PlainButtonStylePace())
    }

    // MARK: - 就地确认

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
                draftCard(draft)

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

    private func draftCard(_ item: DraftItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(amountText(item))
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(item.type == TxnTypes.refund ? PaceColor.income : PaceColor.ink)
                Spacer(minLength: 8)
                Text(typeLabel(item.type))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PaceColor.ink2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(PaceColor.card2, in: Capsule(style: .continuous))
            }
            .padding(.bottom, 12)

            Rectangle()
                .fill(PaceColor.line)
                .frame(height: 0.5)

            fieldRow(Copy.Draft.Field.category, value: shortCategory(item.category))
            fieldRow(Copy.Draft.Field.date, value: dateText(item))
            fieldRow(Copy.Draft.Field.account, value: item.account.isEmpty ? "现金" : item.account)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .paceCardFill(18)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture { openReview(item) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("账单草稿")
        .accessibilityValue(accessibilityValue(item))
        .accessibilityFocused($draftFocused)
    }

    private func fieldRow(_ label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(PaceColor.ink2)
                .frame(width: 40, alignment: .leading)
            Text(value)
                .font(.system(size: 15))
                .foregroundStyle(PaceColor.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(height: 32)
    }

    private func amountText(_ item: DraftItem) -> String {
        let base = LedgerStore.shared.format(item.amountMinor, currency: item.currency)
        return item.type == TxnTypes.refund ? "-\(base)" : base
    }

    private func typeLabel(_ type: String) -> String {
        TxnTypes.all.first(where: { $0.0 == type })?.1 ?? type
    }

    private func shortCategory(_ category: String) -> String {
        category.count > 6 ? String(category.prefix(6)) + "…" : category
    }

    private func dateText(_ item: DraftItem) -> String {
        if !item.dateText.isEmpty { return item.dateText }
        return item.localDate.isEmpty ? "今天" : DraftDate.display(item.localDate)
    }

    private func accessibilityValue(_ item: DraftItem) -> String {
        var parts = [amountText(item), shortCategory(item.category), dateText(item)]
        parts.append(item.account.isEmpty ? "现金" : item.account)
        return parts.joined(separator: "，")
    }

    // MARK: - 入账（就地）

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
            duplicateNotice = true
        } else {
            // 账没记上，话也不能说成「那句话没读懂」。
            withAnimation { inlineSaveFailed = true }
        }
    }

    /// 用户说「照样记」。
    private func saveDuplicateAnyway() {
        guard let draft = inlineDraft else { return }
        savingInline = true
        let outcome = DraftSaver.save([draft], force: true)
        savingInline = false
        if outcome.saved > 0 {
            finishInline()
        } else {
            withAnimation { inlineSaveFailed = true }
        }
    }

    private func finishInline() {
        withAnimation(.easeOut(duration: 0.2)) { inlineSaved = true }
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            onSaved()
            dismiss()
        }
    }

    private func openReview(_ draft: DraftItem) {
        drafts = [draft]
        showReview = true
    }

    // MARK: - 失败

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
            goManual()
        default:
            goManual()
        }
    }

    private func secondaryAction(_ failure: AiFailure) {
        if localFailure {
            goManual()
        } else {
            runLocal()
        }
    }

    /// 手动记这笔：把用户原来那句话原样带进备注。
    private func goManual() {
        state.pendingNote = trimmed.isEmpty ? nil : trimmed
        state.showAdd = true
        dismiss()
    }

    // MARK: - 拆句

    private func parse() async {
        guard canSubmit else { return }
        failure = nil
        localFailure = false
        inlineDraft = nil
        inlineSaved = false
        inputFocused = false
        busy = true
        defer { busy = false }

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

    /// 一笔且齐全就地确认；多笔或缺字段才去确认页（§6）。
    private func present(_ parsed: [DraftItem]) {
        if parsed.count == 1, let only = parsed.first, only.missingFields.isEmpty {
            withAnimation(.easeOut(duration: 0.2)) { inlineDraft = only }
            draftFocused = true
            return
        }
        // 解析完把键盘收掉：多笔要一起看，键盘挡着就是白跳一页。
        inputFocused = false
        drafts = parsed
        showReview = true
    }

    private func runLocal() {
        failure = nil
        localFailure = false
        inlineDraft = nil
        inlineSaved = false
        let parsed = LocalDrafts.parse(text: trimmed, todayIso: LedgerStore.shared.todayIso)
        if parsed.isEmpty {
            localFailure = true
            failure = .unreadable
            return
        }
        present(parsed)
    }
}
