import SwiftUI
import shared

// MARK: - 范围

private enum RangeKind: CaseIterable, Identifiable, Hashable {
    case week
    case month
    case all

    var id: Self { self }

    var title: String {
        switch self {
        case .week: return Copy.Bills.Range.week
        case .month: return Copy.Bills.Range.month
        case .all: return Copy.Bills.Range.all
        }
    }
}

// MARK: - 分组

private struct BillDayGroup: Identifiable {
    let date: String
    let txns: [LedgerTransaction]

    var id: String { date }

    /// 当天净额：支出记负，收入与退款记正；转账不计入。
    var netMinor: Int64 {
        txns.reduce(into: Int64(0)) { sum, txn in
            switch txn.type {
            case TxnTypes.expense:
                sum -= txn.amountMinor
            case TxnTypes.income, TxnTypes.refund:
                sum += txn.amountMinor
            default:
                break
            }
        }
    }
}

/// 账单页：按日期浏览、搜索、编辑、删除与撤销（规范第二批 §1）。
/// 内容卡片实底，玻璃只用于删除后的撤销浮条。
struct BillsView: View {
    @EnvironmentObject private var state: AppState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var keyword = ""
    @State private var range: RangeKind = .week
    @State private var items: [LedgerTransaction]?
    @State private var showSkeleton = false
    @State private var hasLoaded = false
    @State private var editingTxnId: String?

    @State private var undoItem: UndoItem?
    @State private var undoDismissTask: Task<Void, Never>?

    private struct UndoItem {
        let txn: LedgerTransaction
        let note: String
        let restored: Bool
    }

    var body: some View {
        GeometryReader { proxy in
            NavigationStack {
                VStack(spacing: 0) {
                    rangePicker
                    content
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PaceColor.canvas)
                .navigationTitle(Copy.Bills.title)
                .navigationBarTitleDisplayMode(.large)
                .searchable(text: $keyword, prompt: Text(Copy.Bills.searchPlaceholder))
                .task { await initialLoad() }
                .onAppear {
                    if hasLoaded { reload() }
                }
                .onChange(of: keyword) { _, _ in
                    reload()
                }
                .onChange(of: range) { _, _ in
                    reload()
                }
                .onChange(of: state.showAdd) { _, showing in
                    if !showing { reload() }
                }
                .onChange(of: state.showDrafts) { _, showing in
                    if !showing { reload() }
                }
                .sheet(item: editingBinding, onDismiss: { reload() }) { box in
                    AddView(txnId: box.id)
                }
                .onDisappear {
                    undoDismissTask?.cancel()
                    undoItem = nil
                }
            }
            .overlay(alignment: .bottom) {
                if let undoItem {
                    BillsUndoBar(
                        message: undoItem.restored
                            ? Copy.Delete.restored
                            : Copy.Delete.toast(note: undoItem.note),
                        accessibilityMessage: undoItem.restored
                            ? Copy.Delete.restored
                            : Copy.Delete.toastAccessibility(note: undoItem.note),
                        canUndo: !undoItem.restored,
                        onUndo: undoDelete
                    )
                    .padding(.horizontal, PaceSpace.screen)
                    .padding(.bottom, proxy.safeAreaInsets.bottom + 8)
                    .transition(undoTransition)
                }
            }
        }
    }

    // MARK: - 范围

    private var rangePicker: some View {
        Picker(selection: $range) {
            ForEach(RangeKind.allCases) { kind in
                Text(kind.title).tag(kind)
            }
        } label: {
            Text(Copy.Bills.rangeLabel)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, PaceSpace.screen)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .accessibilityLabel(Text(Copy.Bills.rangeLabel))
    }

    // MARK: - 内容与状态

    @ViewBuilder
    private var content: some View {
        if let items {
            if items.isEmpty {
                emptyState
            } else {
                transactionList(items)
            }
        } else if showSkeleton {
            skeletonRows
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var isSearching: Bool {
        !keyword.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(isSearching ? Copy.Bills.noResultsTitle : Copy.Bills.emptyTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PaceColor.ink)
            Text(isSearching ? Copy.Bills.noResultsSubtitle : Copy.Bills.emptySubtitle)
                .font(.footnote)
                .foregroundStyle(PaceColor.ink2)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, PaceSpace.screen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var skeletonRows: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { index in
                    HStack(spacing: PaceSpace.inner) {
                        Circle()
                            .fill(PaceColor.card2)
                            .frame(width: 34, height: 34)

                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(PaceColor.card2)
                                .frame(width: 120, height: 12)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(PaceColor.card2)
                                .frame(width: 86, height: 10)
                        }

                        Spacer(minLength: 8)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(PaceColor.card2)
                            .frame(width: 60, height: 14)
                    }
                    .padding(.horizontal, PaceSpace.cardPadding)
                    .padding(.vertical, 10)
                    .frame(minHeight: 54)

                    if index < 2 {
                        Rectangle()
                            .fill(PaceColor.line)
                            .frame(height: 1)
                            .padding(.leading, PaceSpace.cardPadding + 46)
                    }
                }
            }
            .background(
                PaceColor.card,
                in: RoundedRectangle(cornerRadius: PaceRadius.list, style: .continuous)
            )
            .redacted(reason: .placeholder)
            .padding(.horizontal, PaceSpace.screen)
            .padding(.top, PaceSpace.cardGap)
        }
        .scrollDisabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Copy.Home.loading))
    }

    // MARK: - 列表

    private func transactionList(_ txns: [LedgerTransaction]) -> some View {
        let groups = Self.groupedByDay(txns)
        return List {
            ForEach(groups) { group in
                dayHeader(group)

                ForEach(Array(group.txns.enumerated()), id: \.element.id) { index, txn in
                    txnRow(
                        txn,
                        isFirst: index == 0,
                        isLast: index == group.txns.count - 1
                    )
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(PaceColor.canvas)
        .contentMargins(.bottom, 76, for: .scrollContent)
        .tracksFabScroll()
    }

    private func dayHeader(_ group: BillDayGroup) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(dayTitle(group.date))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PaceColor.ink2)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            Text(netLabel(group.netMinor))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(PaceColor.ink2)
        }
        .padding(.top, PaceSpace.cardGap)
        .padding(.bottom, 6)
        .listRowInsets(EdgeInsets(top: 0, leading: PaceSpace.screen, bottom: 0, trailing: PaceSpace.screen))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func txnRow(
        _ txn: LedgerTransaction,
        isFirst: Bool,
        isLast: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                editingTxnId = txn.id
            } label: {
                HStack(spacing: PaceSpace.inner) {
                    ZStack {
                        Circle()
                            .fill(PaceColor.card2)
                            .frame(width: 34, height: 34)
                        Image(systemName: categoryIconName(txn.category))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(PaceColor.ink)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(rowTitle(txn))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(PaceColor.ink)
                            .lineLimit(1)
                        Text(rowSubtitle(txn))
                            .font(.footnote)
                            .foregroundStyle(PaceColor.ink2)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Text(amountLabel(txn))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(amountColor(txn))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, PaceSpace.cardPadding)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(rowAccessibilityLabel(txn)))

            if !isLast {
                Rectangle()
                    .fill(PaceColor.line)
                    .frame(height: 1)
                    .padding(.leading, PaceSpace.cardPadding + 46)
            }
        }
        .background(dayCardBackground(first: isFirst, last: isLast))
        .listRowInsets(EdgeInsets(top: 0, leading: PaceSpace.screen, bottom: 0, trailing: PaceSpace.screen))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                delete(txn)
            } label: {
                Label(Copy.Delete.action, systemImage: "trash")
            }
        }
    }

    private func dayCardBackground(first: Bool, last: Bool) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: first ? PaceRadius.list : 0,
            bottomLeadingRadius: last ? PaceRadius.list : 0,
            bottomTrailingRadius: last ? PaceRadius.list : 0,
            topTrailingRadius: first ? PaceRadius.list : 0,
            style: .continuous
        )
        .fill(PaceColor.card)
    }

    // MARK: - 数据

    /// 拆成静态函数并显式标注类型，避免表达式过于复杂导致 type-check 超时。
    private static func loadTxns(keyword: String, range: RangeKind) -> [LedgerTransaction] {
        let api = LedgerStore.shared.api
        let today = LedgerStore.shared.todayIso
        let searching = !keyword.trimmingCharacters(in: .whitespaces).isEmpty
        if searching {
            return Array(api.searchTransactions(keyword: keyword))
        }
        switch range {
        case .week:
            guard let week = api.weekRange(todayIso: today) else { return [] }
            return Array(api.transactions(fromLocalDate: week.from, toLocalDate: week.to))
        case .month:
            guard let month = api.monthRange(todayIso: today) else { return [] }
            return Array(api.transactions(fromLocalDate: month.from, toLocalDate: month.to))
        case .all:
            return Array(api.allTransactions())
        }
    }

    private static func groupedByDay(_ txns: [LedgerTransaction]) -> [BillDayGroup] {
        Dictionary(grouping: txns, by: { $0.localDate })
            .map { date, dayTxns in
                let sorted = dayTxns.sorted { lhs, rhs in
                    if lhs.occurredAtEpochMillis != rhs.occurredAtEpochMillis {
                        return lhs.occurredAtEpochMillis > rhs.occurredAtEpochMillis
                    }
                    return lhs.id > rhs.id
                }
                return BillDayGroup(date: date, txns: sorted)
            }
            .sorted { $0.date > $1.date }
    }

    /// 先让第一帧画出来；本地读取通常很快，超过 300ms 才出现骨架。
    @MainActor
    private func initialLoad() async {
        guard items == nil else { return }

        let skeleton = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, items == nil else { return }
            withAnimation(.easeOut(duration: 0.15)) { showSkeleton = true }
        }

        try? await Task.sleep(for: .milliseconds(80))
        guard !Task.isCancelled else {
            skeleton.cancel()
            return
        }

        let loaded = Self.loadTxns(keyword: keyword, range: range)
        skeleton.cancel()

        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.86)) {
            items = loaded
            showSkeleton = false
            hasLoaded = true
        }
    }

    private func reload() {
        let loaded = Self.loadTxns(keyword: keyword, range: range)
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.3)) {
            items = loaded
            showSkeleton = false
            hasLoaded = true
        }
    }

    // MARK: - 删除与撤销

    private func delete(_ txn: LedgerTransaction) {
        let deleted = LedgerStore.shared.api.deleteTransaction(id: txn.id)
        reload()
        guard let deleted else { return }
        presentUndo(for: deleted)
    }

    private func presentUndo(for txn: LedgerTransaction) {
        undoDismissTask?.cancel()
        let note = txn.note.isEmpty ? txn.category : txn.note
        withAnimation(undoAnimation) {
            undoItem = UndoItem(txn: txn, note: note, restored: false)
        }
        scheduleUndoDismiss(after: 8)
    }

    /// 撤销 = 用原数据重新入账（U3）。
    private func undoDelete() {
        guard let item = undoItem, !item.restored else { return }
        let deleted = item.txn

        let result = LedgerStore.shared.api.saveTransaction(
            input: makeSaveInput(
                id: deleted.id,
                type: deleted.type,
                amountText: Money.shared.formatMinor(amountMinor: deleted.amountMinor),
                category: deleted.category,
                note: deleted.note,
                localDate: deleted.localDate,
                account: deleted.account,
                countInBudget: deleted.countInBudget,
                refundOfId: deleted.refundOfId,
                occurredAtEpochMillis: deleted.occurredAtEpochMillis,
                forceSave: true
            )
        )

        guard result.transaction != nil else { return }

        reload()
        withAnimation(undoAnimation) {
            undoItem = UndoItem(txn: deleted, note: item.note, restored: true)
        }
        scheduleUndoDismiss(after: 2)
    }

    private func scheduleUndoDismiss(after seconds: Double) {
        undoDismissTask?.cancel()
        undoDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(undoAnimation) { undoItem = nil }
        }
    }

    // MARK: - 文案与格式化

    private func dayTitle(_ iso: String) -> String {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return iso }

        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12

        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components) else { return iso }

        let weekdayIndex = calendar.component(.weekday, from: date) - 1
        guard Copy.Bills.weekdays.indices.contains(weekdayIndex) else { return iso }
        return Copy.Bills.sectionDate(
            month: parts[1],
            day: parts[2],
            weekday: Copy.Bills.weekdays[weekdayIndex]
        )
    }

    private func netLabel(_ minor: Int64) -> String {
        guard minor != 0 else { return LedgerStore.shared.format(0) }
        let sign = minor < 0 ? "-" : "+"
        return sign + LedgerStore.shared.format(abs(minor))
    }

    private func rowTitle(_ txn: LedgerTransaction) -> String {
        txn.note.isEmpty ? txn.category : txn.note
    }

    private func rowSubtitle(_ txn: LedgerTransaction) -> String {
        let time = PaceDates.shared.timeOfDay(
            epochMillis: txn.occurredAtEpochMillis,
            timezoneId: txn.timezoneId
        )
        // 没备注时标题已经是分类名，副标题不再重复一遍：只留时间和账户。
        var parts: [String] = []
        if !txn.note.isEmpty { parts.append(txn.category) }
        parts.append(time)
        if txn.note.isEmpty, !txn.account.isEmpty { parts.append(txn.account) }
        if !txn.countInBudget { parts.append(Copy.Bills.notInBudget) }
        return parts.joined(separator: " · ")
    }

    private func amountColor(_ txn: LedgerTransaction) -> Color {
        switch txn.type {
        case TxnTypes.income, TxnTypes.refund:
            return PaceColor.income
        default:
            return PaceColor.ink
        }
    }

    private func categoryIconName(_ category: String) -> String {
        switch category {
        case "餐饮": return "fork.knife"
        case "交通": return "car.fill"
        case "购物": return "bag.fill"
        case "住房": return "house.fill"
        case "娱乐": return "party.popper.fill"
        case "医疗": return "cross.case.fill"
        case "教育": return "book.fill"
        case "人情社交": return "gift.fill"
        case "工资": return "banknote.fill"
        case "理财": return "chart.line.uptrend.xyaxis"
        case "转账": return "arrow.left.arrow.right"
        case "退款": return "arrow.uturn.backward"
        default: return "circle.fill"
        }
    }

    private func rowAccessibilityLabel(_ txn: LedgerTransaction) -> String {
        let title = rowTitle(txn)
        let kind = TxnTypes.all.first(where: { $0.0 == txn.type })?.1 ?? txn.type
        let amount = spokenAmount(txn.amountMinor)
        if title == txn.category {
            return "\(title)，\(kind) \(amount)"
        }
        return "\(title)，\(txn.category)，\(kind) \(amount)"
    }

    /// 规范 §11 的读法：32 元 / 12 元 5 角。
    private func spokenAmount(_ minor: Int64) -> String {
        let value = abs(minor)
        let yuan = value / 100
        let cents = value % 100
        if cents == 0 { return "\(yuan) 元" }
        let jiao = cents / 10
        let fen = cents % 10
        if fen == 0 { return "\(yuan) 元 \(jiao) 角" }
        return "\(yuan) 元 \(jiao) 角 \(fen) 分"
    }

    // MARK: - 动效与绑定

    private var undoAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.9)
    }

    private var undoTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    private var editingBinding: Binding<TxnIdBox?> {
        Binding(
            get: { editingTxnId.map { TxnIdBox(id: $0) } },
            set: { editingTxnId = $0?.id }
        )
    }
}

// MARK: - 撤销浮条

/// 底栏上方 8pt 的玻璃浮条；降低透明度时退回实底卡片。
private struct BillsUndoBar: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let message: String
    let accessibilityMessage: String
    let canUndo: Bool
    let onUndo: () -> Void

    var body: some View {
        Group {
            if reduceTransparency {
                bar
                    .background(
                        PaceColor.card,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )
            } else {
                bar
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var bar: some View {
        HStack(spacing: PaceSpace.inner) {
            Text(message)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PaceColor.ink)
                .lineLimit(1)
                .accessibilityLabel(Text(accessibilityMessage))

            Spacer(minLength: 8)

            if canUndo {
                Button(Copy.Delete.undo) {
                    onUndo()
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PaceColor.ink)
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 48)
    }
}
