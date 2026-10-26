import SwiftUI
import shared

/// 草稿确认页：拆出来的每一笔都要用户看过、补齐、确认，才写进账本。
struct DraftReviewView: View {
    @State private var drafts: [DraftItem]
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var editingId: String?
    @State private var saving = false
    @State private var toast: String?
    @State private var duplicateNotice = false
    /// 没保存上的那几笔：停在这一页说清楚，不用会消失的提示。
    @State private var failureBody: String?
    /// 从类型菜单走「改成手动记账」的那一笔。
    @State private var manualPrefill: AddPrefill?

    init(drafts: [DraftItem], onDone: @escaping () -> Void) {
        _drafts = State(initialValue: drafts)
        self.onDone = onDone
    }

    private var categories: [String] {
        LedgerStore.shared.api.categories().map { $0.name }
    }

    private var missingCount: Int {
        drafts.filter { !$0.missingFields.isEmpty }.count
    }

    private var readyCount: Int {
        drafts.filter { $0.missingFields.isEmpty }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: PaceSpace.inner) {
                    header
                    if drafts.isEmpty {
                        emptyState
                    } else {
                        ForEach($drafts) { $draft in
                            draftCard(draft: $draft)
                        }
                    }
                    if let failureBody {
                        failureCard(failureBody)
                    }
                }
                .padding(.horizontal, PaceSpace.screen)
                .padding(.vertical, PaceSpace.cardGap)
            }
            .background(PaceColor.canvas)
            .navigationTitle(Copy.Draft.title(count: drafts.count))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle) { saveAll() }
                        .buttonStyle(ToolbarSaveStyle(enabled: canSave))
                        .disabled(!canSave)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(Copy.Draft.footer)
                    .font(.system(size: 12))
                    .foregroundStyle(PaceColor.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, PaceSpace.screen)
                    .padding(.vertical, 10)
                    .background(PaceColor.canvas)
            }
            .overlay(alignment: .top) {
                if let toast {
                    Text(toast)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PaceColor.ink)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(PaceColor.card, in: Capsule(style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .sheet(item: $manualPrefill) { prefill in
                AddView(txnId: nil, prefill: prefill)
            }
            .alert(Copy.Confirm.Duplicate.title, isPresented: $duplicateNotice) {
                Button(Copy.Confirm.Duplicate.primary) { saveDuplicatesAnyway() }
                Button(Copy.Confirm.Duplicate.secondary, role: .cancel) {}
            } message: {
                Text(Copy.Confirm.Duplicate.body)
            }
        }
    }

    /// 顶部那行补什么：缺的都一样才报具体字段，混着缺就只说笔数。
    private var supplementField: String? {
        let kinds = Set(drafts.flatMap { $0.missingFields })
        guard kinds.count == 1, let kind = kinds.first else { return nil }
        switch kind {
        case DraftMissing.amount: return Copy.Draft.Field.amount
        case DraftMissing.date: return Copy.Draft.Field.date
        case DraftMissing.category: return Copy.Draft.Field.category
        default: return nil
        }
    }

    /// 一笔都没有的时候别让人按一个空操作。
    private var canSave: Bool {
        !drafts.isEmpty && missingCount == 0 && !saving
    }

    private var saveTitle: String {
        if missingCount > 0 { return Copy.Draft.fillRequiredButton(field: supplementField) }
        return Copy.Draft.saveButton(count: readyCount)
    }

    /// 草稿全删光以后这一页的样子：说清楚账本没变，门在哪儿。
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Copy.Draft.emptyTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PaceColor.ink)
            Text(Copy.Draft.emptySubtitle)
                .font(.system(size: 13))
                .foregroundStyle(PaceColor.ink2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .paceCardFill(18)
        .accessibilityElement(children: .combine)
    }

    /// 失败卡：停着不走，带一个能按的「再试一次」。
    private func failureCard(_ body: String) -> some View {
        VStack(alignment: .leading, spacing: PaceSpace.inner) {
            Text(Copy.Failed.DraftSave.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PaceColor.ink)
            Text(body)
                .font(.system(size: 13))
                .foregroundStyle(PaceColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Button(Copy.Failed.retry) { saveAll() }
                .buttonStyle(PillChipStyle(selected: true))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .paceCardFill(18)
        .accessibilityElement(children: .contain)
    }

    // MARK: - 顶部与底部

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(Copy.Draft.headerLeft)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PaceColor.ink)
                Spacer()
                Text(Copy.Draft.headerRight)
                    .font(.system(size: 13))
                    .foregroundStyle(PaceColor.ink2)
            }
            if missingCount > 0 {
                Text(Copy.Draft.needsSupplementNote(count: missingCount, field: supplementField))
                    .font(.system(size: 13))
                    .foregroundStyle(PaceColor.ink2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    // MARK: - 单张草稿

    @ViewBuilder
    private func draftCard(draft: Binding<DraftItem>) -> some View {
        let item = draft.wrappedValue
        let missing = item.missingFields

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.note.isEmpty ? item.category : item.note)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PaceColor.ink)
                Spacer(minLength: 8)
                typeCapsule(draft: draft)
                if item.amountMinor > 0 {
                    Text(LedgerStore.shared.format(item.amountMinor, currency: item.currency))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(PaceColor.ink)
                } else {
                    Text(Copy.Draft.emptyAmount)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(PaceColor.ink3)
                }
            }

            Text(metaLine(item))
                .font(.system(size: 13))
                .foregroundStyle(PaceColor.ink2)

            if item.amountMinor <= 0 {
                Text(Copy.Draft.noAmountHint)
                    .font(.system(size: 12))
                    .foregroundStyle(PaceColor.ink2)
            }

            if editingId == item.id {
                editor(draft: draft)
            } else {
                HStack(spacing: 8) {
                    Button("改") { editingId = item.id }
                        .buttonStyle(PillChipStyle())
                    Button(Copy.Draft.deleteAction) { remove(item.id) }
                        .buttonStyle(PillChipStyle())
                    Spacer()
                    if let marker = missingMarker(missing) {
                        StatusPill(text: marker, kind: .neutral)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .paceCardFill(18)
    }

    /// 类型做成卡片头部那颗小胶囊：跟 QuickAddView 右上角那颗一套值，只是它能点。
    /// 菜单里只有支出、收入——转账和退款要指定账户或原账单，盲选出来就是错账。
    @ViewBuilder
    private func typeCapsule(draft: Binding<DraftItem>) -> some View {
        let item = draft.wrappedValue
        let missingType = item.missingFields.contains(DraftMissing.type)

        Menu {
            // 转账和退款不能从两项里盲选：那两样要指定账户或原账单，
            // 选出来就是一笔没关联的错账。想记这两种的人从最后一行出口走。
            ForEach([TxnTypes.expense, TxnTypes.income], id: \.self) { value in
                Button {
                    draft.wrappedValue.type = value
                    draft.wrappedValue.missingFields.removeAll { $0 == DraftMissing.type }
                } label: {
                    if item.type == value {
                        Label(typeLabel(value), systemImage: "checkmark")
                    } else {
                        Text(typeLabel(value))
                    }
                }
            }
            Divider()
            // 跟当前有没有类型无关：想把这笔记成退款，跟它原来是支出没关系。
            Button(Copy.Draft.toManual) {
                manualPrefill = AddPrefill(
                    amountText: item.amountMinor > 0
                        ? Money.shared.formatMinor(amountMinor: item.amountMinor)
                        : "",
                    localDate: item.localDate,
                    note: item.note
                )
            }
        } label: {
            Text(missingType ? Copy.Draft.Missing.typeCapsule : typeLabel(item.type))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(missingType ? PaceColor.accent : PaceColor.ink2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(missingType ? PaceColor.card : PaceColor.card2)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(missingType ? PaceColor.accent : .clear, lineWidth: 0.5)
                )
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(Copy.Draft.Missing.type)
        .accessibilityValue(missingType ? Copy.Draft.Missing.typeNotChosen : typeLabel(item.type))
        .accessibilityHint(missingType ? Copy.Draft.Missing.typeHintNotChosen : Copy.Draft.Missing.typeHintChosen)
    }

    private func typeLabel(_ type: String) -> String {
        TxnTypes.all.first(where: { $0.0 == type })?.1 ?? type
    }

    private func metaLine(_ item: DraftItem) -> String {
        var parts = [item.category]
        if !item.localDate.isEmpty {
            parts.append(item.dateText.isEmpty ? DraftDate.display(item.localDate) : "\(item.dateText) \(DraftDate.display(item.localDate))")
        }
        if !item.account.isEmpty { parts.append(item.account) }
        return parts.joined(separator: " · ")
    }

    private func missingMarker(_ fields: [String]) -> String? {
        guard !fields.isEmpty else { return nil }
        // 缺的只有类型时不再让状态标说第二遍：胶囊已经在说「选类型」了。
        if fields.count == 1, fields.first == DraftMissing.type { return nil }
        if fields.count > 1 { return Copy.Draft.statusNeedsSupplement }
        switch fields.first {
        case DraftMissing.amount: return Copy.Draft.Missing.amount
        case DraftMissing.date: return Copy.Draft.Missing.date
        case DraftMissing.type: return Copy.Draft.Missing.type
        case DraftMissing.category: return Copy.Draft.Missing.category
        default: return Copy.Draft.statusNeedsSupplement
        }
    }

    @ViewBuilder
    private func editor(draft: Binding<DraftItem>) -> some View {
        let item = draft.wrappedValue
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(Copy.Draft.Field.amount).font(.system(size: 12)).foregroundStyle(PaceColor.ink2)
                TextField("0.00", text: draft.amountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 15, design: .rounded))
                    .onChange(of: draft.wrappedValue.amountText) { _, newValue in
                        draft.wrappedValue.updateAmount(newValue, todayIso: LedgerStore.shared.todayIso)
                    }
            }
            HStack(spacing: 8) {
                Text(Copy.Draft.Field.date).font(.system(size: 12)).foregroundStyle(PaceColor.ink2)
                DatePicker("", selection: dateBinding(draft), displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                Spacer()
            }
            HStack(spacing: 8) {
                Text(Copy.Draft.Field.category).font(.system(size: 12)).foregroundStyle(PaceColor.ink2)
                Menu(item.category) {
                    ForEach(categories, id: \.self) { name in
                        Button(name) {
                            draft.wrappedValue.category = name
                            draft.wrappedValue.missingFields.removeAll { $0 == DraftMissing.category }
                        }
                    }
                }
                .font(.system(size: 15))
                Spacer()
            }
            TextField(Copy.Draft.Field.note, text: draft.note)
                .font(.system(size: 15))
            Button("改好了") { editingId = nil }
                .buttonStyle(PillChipStyle(selected: true))
        }
        .padding(.top, 4)
    }

    private func dateBinding(_ draft: Binding<DraftItem>) -> Binding<Date> {
        Binding(
            get: { DraftDate.date(from: draft.wrappedValue.localDate) ?? Date() },
            set: { newValue in
                draft.wrappedValue.localDate = DraftDate.iso(from: newValue)
                draft.wrappedValue.missingFields.removeAll { $0 == DraftMissing.date }
            }
        )
    }

    private func remove(_ id: String) {
        drafts.removeAll { $0.id == id }
    }

    // MARK: - 入账

    private func saveAll() {
        // 空数组不再往下走：否则「已保存 0 笔」哪天又从别处冒回来。
        guard !saving, missingCount == 0, !drafts.isEmpty else { return }
        saving = true
        failureBody = nil
        let outcome = DraftSaver.save(drafts)

        // 有真没写进去的：先把话说出来，再说重复的。
        if !outcome.failed.isEmpty {
            saving = false
            let kept = outcome.failed + outcome.duplicated
            withAnimation { drafts = kept }
            failureBody = outcome.saved > 0
                ? Copy.Failed.DraftSave.partial(saved: outcome.saved, failed: outcome.failed.count)
                : (kept.count == 1 ? Copy.Failed.DraftSave.bodyOne : Copy.Failed.DraftSave.bodyMany)
            if !outcome.duplicated.isEmpty { duplicateNotice = true }
            return
        }

        // 全都撞上重复，就直接问要不要照样记，不先报一个「已保存 0 笔」。
        if outcome.saved == 0, !outcome.duplicated.isEmpty {
            saving = false
            withAnimation { toast = Copy.Save.allDuplicates(count: outcome.duplicated.count) }
            duplicateNotice = true
            return
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            toast = outcome.duplicated.isEmpty
                ? Copy.Save.saved(count: outcome.saved)
                : Copy.Save.savedSomeDuplicates(saved: outcome.saved, duplicated: outcome.duplicated.count)
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if outcome.duplicated.isEmpty {
                onDone()
                dismiss()
            } else {
                // 存进去的不再留着，只把重复的这几笔留在页面上问用户。
                drafts = outcome.duplicated
                saving = false
                withAnimation { toast = nil }
                duplicateNotice = true
            }
        }
    }

    /// 用户说「照样记」：把剩下这几笔强制写进去。
    private func saveDuplicatesAnyway() {
        let outcome = DraftSaver.save(drafts, force: true)
        if !outcome.failed.isEmpty {
            withAnimation {
                drafts = outcome.failed
                failureBody = outcome.saved > 0
                    ? Copy.Failed.DraftSave.partial(saved: outcome.saved, failed: outcome.failed.count)
                    : (outcome.failed.count == 1 ? Copy.Failed.DraftSave.bodyOne : Copy.Failed.DraftSave.bodyMany)
            }
            return
        }
        withAnimation { toast = Copy.Save.saved(count: outcome.saved) }
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            onDone()
            dismiss()
        }
    }
}

/// 草稿日期与 Date 的互转（固定格式，避免时区把日期挪一天）。
enum DraftDate {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: LedgerStore.shared.timezoneId) ?? .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func date(from iso: String) -> Date? {
        formatter.date(from: iso)
    }

    static func iso(from date: Date) -> String {
        formatter.string(from: date)
    }

    /// 卡片上显示的日期：10月20日，机器格式不进界面。
    static func display(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else { return iso }
        return "\(month)月\(day)日"
    }
}

extension DraftItem {
    /// 金额改动后本地复算最小单位，顺带清掉「需要金额」。
    mutating func updateAmount(_ text: String, todayIso: String) {
        amountText = text.trimmingCharacters(in: .whitespaces)
        if let minor = Money.shared.parseToMinor(text: amountText) {
            amountMinor = minor.int64Value
            missingFields.removeAll { $0 == DraftMissing.amount }
        } else {
            amountMinor = 0
            if !missingFields.contains(DraftMissing.amount) {
                missingFields.append(DraftMissing.amount)
            }
        }
    }
}
