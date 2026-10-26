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
                    ForEach($drafts) { $draft in
                        draftCard(draft: $draft)
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
                        .buttonStyle(.glassProminent)
                        .disabled(missingCount > 0 || saving)
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

    private var saveTitle: String {
        missingCount > 0 ? Copy.Draft.fillRequiredButton : Copy.Draft.saveButton(count: readyCount)
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
                Spacer()
                if item.amountMinor > 0 {
                    Text(LedgerStore.shared.format(item.amountMinor, currency: item.currency))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(PaceColor.ink)
                } else {
                    Text("—")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(PaceColor.ink3)
                }
            }

            Text(metaLine(item))
                .font(.system(size: 13))
                .foregroundStyle(PaceColor.ink2)

            if item.amountMinor <= 0 {
                Text("这句话里没有金额，不猜。")
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
        guard !saving, missingCount == 0 else { return }
        saving = true
        let api = LedgerStore.shared.api
        let input = drafts.map { draft in
            makeSaveInput(
                type: draft.type,
                amountText: draft.amountText,
                category: draft.category,
                note: draft.note,
                localDate: draft.localDate,
                account: draft.account.isEmpty ? "现金" : draft.account,
                countInBudget: draft.countInBudget,
                forceSave: false
            )
        }

        // 先存一遍：全都撞上重复，就直接问要不要照样记，不先报一个「已保存 0 笔」。
        var saved = 0
        var duplicated: [DraftItem] = []
        for (index, draft) in drafts.enumerated() {
            let result = api.saveTransaction(input: input[index])
            if result.isSuccess {
                saved += 1
            } else if result.errorCode == "DUPLICATE_FINGERPRINT" {
                duplicated.append(draft)
            }
        }

        if saved == 0, !duplicated.isEmpty {
            saving = false
            withAnimation { toast = Copy.Save.allDuplicates(count: duplicated.count) }
            duplicateNotice = true
            return
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            toast = duplicated.isEmpty
                ? Copy.Save.saved(count: saved)
                : Copy.Save.savedSomeDuplicates(saved: saved, duplicated: duplicated.count)
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if duplicated.isEmpty {
                onDone()
                dismiss()
            } else {
                // 存进去的不再留着，只把重复的这几笔留在页面上问用户。
                drafts = duplicated
                saving = false
                withAnimation { toast = nil }
                duplicateNotice = true
            }
        }
    }

    /// 用户说「照样记」：把剩下这几笔强制写进去。
    private func saveDuplicatesAnyway() {
        let api = LedgerStore.shared.api
        var saved = 0
        for draft in drafts {
            let result = api.saveTransaction(input: makeSaveInput(
                type: draft.type,
                amountText: draft.amountText,
                category: draft.category,
                note: draft.note,
                localDate: draft.localDate,
                account: draft.account.isEmpty ? "现金" : draft.account,
                countInBudget: draft.countInBudget,
                forceSave: true
            ))
            if result.isSuccess { saved += 1 }
        }
        withAnimation { toast = Copy.Save.saved(count: saved) }
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
