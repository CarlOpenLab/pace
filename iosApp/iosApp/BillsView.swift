import SwiftUI
import shared

private enum RangeKind: String, CaseIterable, Identifiable {
    case week = "本周"
    case month = "本月"
    case all = "全部"
    var id: String { rawValue }
}

/// 账单页：按日期浏览、搜索、编辑、删除与撤销（PLAN §7 页面 3）
struct BillsView: View {
    @State private var keyword = ""
    @State private var range: RangeKind = .week
    @State private var refreshToken = 0
    @State private var editingTxnId: String?
    @State private var showAdd = false
    @State private var undoCandidate: LedgerTransaction?

    private var txns: [LedgerTransaction] { BillsView.loadTxns(keyword: keyword, range: range) }

    /// 拆成静态函数并显式标注类型，避免表达式过于复杂导致 type-check 超时
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

    private var grouped: [(String, [LedgerTransaction])] {
        Dictionary(grouping: txns, by: { $0.localDate })
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("范围", selection: $range) {
                        ForEach(RangeKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField("搜索备注/分类/账户", text: $keyword)
                }
                if grouped.isEmpty {
                    Text("该范围内没有账单。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(grouped, id: \.0) { date, dayTxns in
                    Section(date) {
                        ForEach(dayTxns, id: \.id) { txn in
                            Button {
                                editingTxnId = txn.id
                            } label: {
                                TxnRowView(txn: txn)
                            }
                            .tint(.primary)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(txn)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("账单")
            .listRowBackground(GlassRowBackground())
            .glassFormStyle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("记一笔") { showAdd = true }
                }
            }
            .sheet(isPresented: $showAdd, onDismiss: { refreshToken += 1 }) {
                AddView(txnId: nil)
            }
            .sheet(item: Binding(
                get: { editingTxnId.map { TxnIdBox(id: $0) } },
                set: { editingTxnId = $0?.id }
            ), onDismiss: { refreshToken += 1 }) { box in
                AddView(txnId: box.id)
            }
            .alert(
                "已删除",
                isPresented: Binding(
                    get: { undoCandidate != nil },
                    set: { if !$0 { undoCandidate = nil } }
                )
            ) {
                Button("撤销") { undo() }
                Button("好", role: .cancel) {}
            } message: {
                if let deleted = undoCandidate {
                    Text("「\(deleted.note.isEmpty ? deleted.category : deleted.note)」已删除")
                }
            }
            .id(refreshToken)
        }
    }

    private func delete(_ txn: LedgerTransaction) {
        if let deleted = LedgerStore.shared.api.deleteTransaction(id: txn.id) {
            undoCandidate = deleted
            refreshToken += 1
        }
    }

    /// 撤销 = 用原数据重新入账（U3）
    private func undo() {
        guard let deleted = undoCandidate else { return }
        _ = LedgerStore.shared.api.saveTransaction(
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
        undoCandidate = nil
        refreshToken += 1
    }
}
