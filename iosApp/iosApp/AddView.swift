import SwiftUI
import shared

/// 记一笔 / 编辑账单（spec §7）。
/// 结构：一句话入口 → 金额 → 类型 → 分类 → 日期与账户 → 备注 → 计入预算 / 退款关联。
/// 从草稿带进手动记账页的东西：已经解析出来的金额、日期、备注跟着走，
/// 只有类型留空让用户挑——别把人送进一张白纸，那等于刚才那句白说了。
struct AddPrefill: Identifiable {
    let id = UUID()
    var amountText: String
    var localDate: String
    var note: String
}

struct AddView: View {
    let txnId: String?
    var prefill: AddPrefill? = nil
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState

    @State private var type: String
    @State private var amountText: String
    @State private var category: String
    @State private var localDate: String
    @State private var note: String
    @State private var account: String
    @State private var countInBudget: Bool
    @State private var refundOfId: String?

    @State private var errorText: String?
    @State private var confirmDuplicate = false
    @State private var showQuickAdd = false
    @State private var showCustomAccount = false
    @State private var customAccountDraft = ""

    @FocusState private var amountFocused: Bool

    private let categories: [LedgerCategory]
    private let refundCandidates: [LedgerTransaction]

    /// Copy 里没有账户预设的键（只有占位文案），按 spec 列在这里。
    private static let accountPresets = ["现金", "微信", "支付宝", "银行卡"]

    init(txnId: String?, prefill: AddPrefill? = nil) {
        self.txnId = txnId
        self.prefill = prefill
        self.onDone = {}

        let existing = txnId.flatMap { LedgerStore.shared.api.transaction(id: $0) }

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
                    if !isEditing {
                        quickAddRow
                    }
                    amountCard
                    typeCard
                    categoryCard
                    dateAccountCard
                    noteCard
                    if showsBudgetToggle {
                        budgetCard
                    }
                    if type == TxnTypes.refund {
                        refundCard
                    }
                }
                .padding(.horizontal, PaceSpace.screen)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(PaceColor.canvas.ignoresSafeArea())
            .navigationTitle(isEditing ? "编辑账单" : "记一笔")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // 一个安静的叉：不带玻璃气泡。iOS 26 的玻璃底画得比按钮框
                    // 大一圈，会压到旁边那颗保存胶囊上，两套长相不该并排。
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(PaceColor.ink2)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关掉")
                }
                // iOS 26 默认给每个工具栏项画一层共享的玻璃底，那层比按钮框大一圈，
                // 会压到旁边那颗保存胶囊上。这里只留自己画的东西。
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save(force: false)
                    } label: {
                        Text("保存")
                            .font(.system(size: 16, weight: .semibold))
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(ToolbarSaveStyle(enabled: isAmountValid))
                    .disabled(!isAmountValid)
                }
            }
            .alert(Copy.Confirm.Duplicate.title, isPresented: $confirmDuplicate) {
                Button(Copy.Confirm.Duplicate.primary) { save(force: true) }
                Button(Copy.Confirm.Duplicate.secondary, role: .cancel) {}
            } message: {
                Text(Copy.Confirm.Duplicate.body)
            }
            .sheet(isPresented: $showQuickAdd) {
                QuickAddView(initialText: "") { dismiss() }
            }
            .onChange(of: state.pendingNote) { _, pending in
                // 从「一句话记账」退回来时，把用户原来那句话放进备注。
                if let pending, !pending.isEmpty, note.isEmpty {
                    note = pending
                    state.pendingNote = nil
                }
            }
            .onAppear {
                // 从「一句话记账」失败退到这儿时，把用户原来那句话放进备注。
                if let pending = state.pendingNote, note.isEmpty {
                    note = pending
                    state.pendingNote = nil
                }
                // sheet 的入场动画结束后再聚焦，否则 keyboard 有可能不弹。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    amountFocused = true
                }
            }
        }
        .background(PaceColor.canvas)
        .presentationDetents([.large])
    }

    // MARK: - 1. 一句话入口（仅新建）

    private var quickAddRow: some View {
        Button {
            showQuickAdd = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                Text(Copy.Ai.Entry.title)
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 12)
                Text(Copy.Ai.Entry.placeholder)
                    .font(.system(size: 13))
                    .foregroundStyle(PaceColor.ink2)
            }
            .foregroundStyle(PaceColor.ai)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(PaceColor.aiSoft, in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. 金额

    private var amountCard: some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .paceCard()
    }

    // MARK: - 3. 类型

    private var typeCard: some View {
        Picker(Copy.Add.Section.type, selection: $type) {
            ForEach(TxnTypes.all, id: \.0) { value, label in
                Text(label).tag(value)
            }
        }
        .pickerStyle(.segmented)
        .paceCard()
    }

    // MARK: - 4. 分类

    private var categoryCard: some View {
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
        .paceCard()
    }

    // MARK: - 5. 日期与账户

    private var dateAccountCard: some View {
        VStack(spacing: 0) {
            dateRow
            Rectangle()
                .fill(PaceColor.line)
                .frame(height: 1)
                .padding(.leading, PaceSpace.cardPadding)
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

    // MARK: - 6. 备注

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

    // MARK: - 7. 计入预算 / 退款关联

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

    // MARK: - 保存

    private func save(force: Bool) {
        errorText = nil
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
            confirmDuplicate = true
        } else {
            errorText = describeError(result.errorCode)
        }
    }

    // MARK: - 派生状态

    private var isEditing: Bool { txnId != nil }

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
