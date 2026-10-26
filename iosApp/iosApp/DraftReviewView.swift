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
    /// 从类型菜单走「切到手动」的那一笔。
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
                    // 草稿都删光了就别再留着列表的表头：它注解的是一张不存在的列表。
                    if !drafts.isEmpty {
                        header
                    }
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
            // 工具栏交给系统：左上返回、右上保存都是系统玻璃。这一页唯一的实底
            // 强调留给草稿卡上的「记上」。
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveAll()
                    } label: {
                        Text(saveTitle)
                            .paceFont(16, .semibold)
                            .foregroundStyle(canSave ? PaceColor.ink : PaceColor.ink2)
                    }
                    .disabled(!canSave)
                }
            }
            .safeAreaInset(edge: .bottom) {
                // 没有草稿时页脚也一样让开：空卡自己已经说了账本没变。
                if !drafts.isEmpty {
                    Text(Copy.Draft.footer)
                        .paceFont(12)
                        .foregroundStyle(PaceColor.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, PaceSpace.screen)
                        .padding(.vertical, 10)
                        .background(PaceColor.canvas)
                }
            }
            .overlay(alignment: .top) {
                if let toast {
                    Text(toast)
                        .paceFont(14, .semibold)
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
                // 这一行是「切到手动」：打开记一笔页时直接落在手动那边。
                AddView(txnId: nil, prefill: prefill, startInManual: true)
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

    @Environment(\.dynamicTypeSize) private var typeSize
    /// 状态位里两样之间的间隔：跟着字号长（Colo 第十一版：4 点起）。
    @ScaledMetric private var statusSlotGap: CGFloat = 4

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
                .paceFont(15, .semibold)
                .foregroundStyle(PaceColor.ink)
            Text(Copy.Draft.emptySubtitle)
                .paceFont(13)
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
                .paceFont(15, .semibold)
                .foregroundStyle(PaceColor.ink)
            Text(body)
                .paceFont(13)
                .foregroundStyle(PaceColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Button(Copy.Failed.retry) { saveAll() }
                .buttonStyle(GlassSecondaryStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .paceCardFill(18)
        .accessibilityElement(children: .contain)
    }

    // MARK: - 顶部与底部

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 两句说明：默认字号并排（和以前一个像素都不差）；大字号下上下两行，
            // 不挤成「确认后才／进账本」那种一页里最难看的样子。
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    headerLeftText
                    headerRightText
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    headerLeftText
                    Spacer()
                    headerRightText
                }
            }
            if missingCount > 0 {
                Text(Copy.Draft.needsSupplementNote(count: missingCount, field: supplementField))
                    .paceFont(13)
                    .fixedSize(horizontal: false, vertical: true)
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
            // 卡片头一行三样东西抢地方。默认字号下并排（一个像素都不差）；
            // 大字号下金额单独下一行——它是这一格必须被读准的东西。
            // 状态和动作都住右上角那个位子（Colo 第十一版）：状态在上、动作在下，
            // 这样一张卡「怎么了、该按哪儿」扫一遍就够了，不用两个角来回看。
            // 默认字号并排一行；大字号下状态位掉到标题下面、仍然右对齐，金额再下一行。
            if typeSize.isAccessibilitySize {
                // 钱的那一格不动（Colo 第十二版）：金额永远在标题行右侧那一格，
                // 三张卡扫一眼能对齐。胶囊放不下就整组换到下面一行，不拆开、不把金额挤下去。
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        cardTitle(item)
                        Spacer(minLength: 8)
                        cardAmount(item)
                    }
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        statusSlot(item: item, draft: draft)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    cardTitle(item)
                    Spacer(minLength: 8)
                    statusSlot(item: item, draft: draft)
                    cardAmount(item)
                }
            }

            // 分类、日期、账户三样用「 · 」连起来。默认字号并成一串（和以前一样）；
            // 大字号下一行一样、不带间隔点——换行时把「·」甩到行首是最难看的。
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(metaParts(item), id: \.self) { part in
                        Text(part)
                            .paceFont(13)
                            .foregroundStyle(PaceColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text(metaLine(item))
                    .paceFont(13)
                    .foregroundStyle(PaceColor.ink2)
            }

            if item.amountMinor <= 0 {
                Text(Copy.Draft.noAmountHint)
                    .paceFont(12)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(PaceColor.ink2)
            }

            if editingId == item.id {
                editor(draft: draft)
            } else {
                HStack(spacing: 8) {
                    editButton(item)
                    deleteButton(item)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .paceCardFill(18)
    }

    @ViewBuilder
    private var headerLeftText: some View {
        Text(Copy.Draft.headerLeft)
            .paceFont(13, .semibold)
            .foregroundStyle(PaceColor.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var headerRightText: some View {
        Text(Copy.Draft.headerRight)
            .paceFont(13)
            .foregroundStyle(PaceColor.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func statusSlot(item: DraftItem, draft: Binding<DraftItem>) -> some View {
        VStack(alignment: .trailing, spacing: statusSlotGap) {
            statusPill(item.missingFields)
            typeCapsule(draft: draft)
        }
    }

    @ViewBuilder
    private func editButton(_ item: DraftItem) -> some View {
        Button(Copy.Ai.Input.editInline) { editingId = item.id }
            .buttonStyle(GlassSecondaryStyle())
    }

    @ViewBuilder
    private func deleteButton(_ item: DraftItem) -> some View {
        Button(Copy.Draft.deleteAction) { remove(item.id) }
            .buttonStyle(GlassSecondaryStyle(tint: PaceColor.danger))
    }

    @ViewBuilder
    private func statusPill(_ missing: [String]) -> some View {
        if let marker = missingMarker(missing) {
            StatusPill(text: marker, kind: .neutral)
        }
    }

    @ViewBuilder
    private func cardTitle(_ item: DraftItem) -> some View {
        Text(item.note.isEmpty ? item.category : item.note)
            .paceFont(16, .semibold)
            .foregroundStyle(PaceColor.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func cardAmount(_ item: DraftItem) -> some View {
        if item.amountMinor > 0 {
            Text(LedgerStore.shared.format(item.amountMinor, currency: item.currency))
                .paceFont(16, .semibold, design: .rounded)
                .monospacedDigit()
                .foregroundStyle(PaceColor.ink)
                .lineLimit(1)
        } else {
            // 缺金额写一个词，不套任何胶囊容器（Camo：套上就是按钮，人会去点）。
            // 右边缘和金额同一条线（Colo：锚点是右边，齐尾不齐头）。
            Text(Copy.Draft.emptyAmount)
                .paceFont(16, .semibold, design: .rounded)
                .foregroundStyle(PaceColor.ink2)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                // 并进金额那一格读「金额，还没填」，不单独成元素。
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(Copy.Draft.Field.amount)，\(Copy.Draft.emptyAmount)"))
        }
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
                .paceFont(11, .medium)
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

    private func metaParts(_ item: DraftItem) -> [String] {
        var parts = [item.category]
        if !item.localDate.isEmpty {
            parts.append(item.dateText.isEmpty ? DraftDate.display(item.localDate) : "\(item.dateText) \(DraftDate.display(item.localDate))")
        }
        if !item.account.isEmpty { parts.append(item.account) }
        return parts
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
        // 缺的只有金额也不再挂状态标：金额那一格现在写的是「还没填」，
        // 同一个事实只留一个信号（Colo 第十二版）。
        if fields.count == 1, fields.first == DraftMissing.amount { return nil }
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
                Text(Copy.Draft.Field.amount).paceFont(12).foregroundStyle(PaceColor.ink2)
                TextField("0.00", text: draft.amountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .paceFont(15, design: .rounded, relativeTo: .subheadline)
                    .onChange(of: draft.wrappedValue.amountText) { _, newValue in
                        draft.wrappedValue.updateAmount(newValue, todayIso: LedgerStore.shared.todayIso)
                    }
            }
            HStack(spacing: 8) {
                Text(Copy.Draft.Field.date).paceFont(12).foregroundStyle(PaceColor.ink2)
                DatePicker("", selection: dateBinding(draft), displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                Spacer()
            }
            HStack(spacing: 8) {
                Text(Copy.Draft.Field.category).paceFont(12).foregroundStyle(PaceColor.ink2)
                Menu(item.category) {
                    ForEach(categories, id: \.self) { name in
                        Button(name) {
                            draft.wrappedValue.category = name
                            draft.wrappedValue.missingFields.removeAll { $0 == DraftMissing.category }
                        }
                    }
                }
                .paceFont(15)
                Spacer()
            }
            TextField(Copy.Draft.Field.note, text: draft.note)
                .paceFont(15)
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
