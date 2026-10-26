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
        enum Kind {
            /// 删掉了，可以撤销。
            case deleted
            /// 撤销成功，恢复回来了。
            case restored
            /// 删除本身没成：这笔还在账本里。
            case deleteFailed
            /// 撤销没成：这笔还是删掉的，还能再点一次。
            case undoFailed
        }

        let txn: LedgerTransaction
        let note: String
        let kind: Kind
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
                        message: undoBarMessage(undoItem),
                        accessibilityMessage: undoBarAccessibility(undoItem),
                        canUndo: undoItem.kind == .deleted || undoItem.kind == .undoFailed,
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
                            .fill(PaceColor.divider)
                            .frame(height: 1)
                            .padding(.leading, PaceSpace.cardPadding + 46)
                    }
                }
            }
            .paceCardFill(PaceRadius.list)
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
        .contentMargins(.bottom, PaceSpace.fabClearance, for: .scrollContent)
        .tracksFabScroll()
    }

    private func dayHeader(_ group: BillDayGroup) -> some View {
        // 日期和当天净额都是 caption（12 点，默认字号下和以前一个像素都不差）。
        // 大字号下一排放不下就上下两行：这两个数都短，谁也不该被截。
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                dayTitleText(group)
                Spacer(minLength: 8)
                netLabelText(group)
            }
            VStack(alignment: .leading, spacing: 2) {
                dayTitleText(group)
                netLabelText(group)
            }
        }
        .padding(.top, PaceSpace.cardGap)
        .padding(.bottom, 6)
        .listRowInsets(EdgeInsets(top: 0, leading: PaceSpace.screen, bottom: 0, trailing: PaceSpace.screen))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    private func dayTitleText(_ group: BillDayGroup) -> some View {
        Text(dayTitle(group.date))
            .font(PaceType.caption.weight(.semibold))
            .foregroundStyle(PaceColor.ink2)
            .accessibilityAddTraits(.isHeader)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func netLabelText(_ group: BillDayGroup) -> some View {
        Text(netLabel(group.netMinor))
            .font(PaceType.caption)
            .monospacedDigit()
            .foregroundStyle(PaceColor.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 大字号下：金额自己占一整行，时间换行让位。和首页同一条规则（Colo 写进表的）：
    /// 金额是这一行唯一必须读准的东西，不退让。
    private func stackedRowContent(_ txn: LedgerTransaction) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: PaceSpace.inner) {
                rowIcon(txn)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rowTitle(txn))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(PaceColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(rowSubtitle(txn))
                        .font(.footnote)
                        .foregroundStyle(PaceColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(amountLabel(txn))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(amountColor(txn))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func rowIcon(_ txn: LedgerTransaction) -> some View {
        ZStack {
            Circle()
                .fill(PaceColor.card2)
                .frame(width: 34, height: 34)
            Image(systemName: categoryIconName(txn.category))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PaceColor.ink)
        }
        .accessibilityHidden(true)
    }

    private func compactRowContent(_ txn: LedgerTransaction) -> some View {
        HStack(spacing: PaceSpace.inner) {
            rowIcon(txn)

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
        }
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
                Group {
                    if typeSize.isAccessibilitySize {
                        stackedRowContent(txn)
                    } else {
                        compactRowContent(txn)
                    }
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
                    .fill(PaceColor.divider)
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
            // 全局 tint 是 ink（暗色下近白），滑动动作的底会跟着变成白的 ——
            // 白底白字。凡是 destructive 控件都显式给红，不许吃全局 tint。
            .tint(PaceColor.dangerFill)
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
        guard let deleted else {
            // 没删掉就得说：用户以为这笔已经没了，比什么都不说更糟。
            presentFailure(txn: txn)
            return
        }
        presentUndo(for: deleted)
    }

    /// 删除没成功：账本没变，浮条上不挂「撤销」——没有可撤销的事。
    private func presentFailure(txn: LedgerTransaction) {
        undoDismissTask?.cancel()
        let note = txn.note.isEmpty ? txn.category : txn.note
        withAnimation(undoAnimation) {
            undoItem = UndoItem(txn: txn, note: note, kind: .deleteFailed)
        }
        scheduleUndoDismiss(after: 6)
    }

    private func undoBarMessage(_ item: UndoItem) -> String {
        switch item.kind {
        case .deleted: return Copy.Delete.toast(note: item.note)
        case .restored: return Copy.Delete.restored
        case .deleteFailed: return Copy.Failed.Delete.body
        case .undoFailed: return Copy.Failed.Undo.body
        }
    }

    private func undoBarAccessibility(_ item: UndoItem) -> String {
        switch item.kind {
        case .deleted: return Copy.Delete.toastAccessibility(note: item.note)
        case .restored: return Copy.Delete.restored
        case .deleteFailed: return Copy.Failed.Delete.title + "，" + Copy.Failed.Delete.body
        case .undoFailed: return Copy.Failed.Undo.title + "，" + Copy.Failed.Undo.body
        }
    }

    private func presentUndo(for txn: LedgerTransaction) {
        undoDismissTask?.cancel()
        let note = txn.note.isEmpty ? txn.category : txn.note
        withAnimation(undoAnimation) {
            undoItem = UndoItem(txn: txn, note: note, kind: .deleted)
        }
        scheduleUndoDismiss(after: 8)
    }

    /// 撤销 = 用原数据重新入账（U3）。
    private func undoDelete() {
        guard let item = undoItem, item.kind == .deleted || item.kind == .undoFailed else { return }
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

        guard result.transaction != nil else {
            // 撤销失败：账本确实变了（这笔没了），口径不能写「没有变化」。
            withAnimation(undoAnimation) {
                undoItem = UndoItem(txn: deleted, note: item.note, kind: .undoFailed)
            }
            scheduleUndoDismiss(after: 8)
            return
        }

        reload()
        withAnimation(undoAnimation) {
            undoItem = UndoItem(txn: deleted, note: item.note, kind: .restored)
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
                .paceFont(14, .semibold)
                .foregroundStyle(PaceColor.ink)
                .lineLimit(1)
                .accessibilityLabel(Text(accessibilityMessage))

            Spacer(minLength: 8)

            if canUndo {
                Button(Copy.Delete.undo) {
                    onUndo()
                }
                .paceFont(14, .semibold)
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
