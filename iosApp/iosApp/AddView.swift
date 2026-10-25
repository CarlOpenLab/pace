import SwiftUI
import shared

/// 记账页：金额、类型、分类、日期、备注、预算归属（PLAN §7 页面 2）
struct AddView: View {
    let txnId: String?
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss

    init(txnId: String?) {
        self.txnId = txnId
        self.onDone = {}
        if let id = txnId, let existing = LedgerStore.shared.api.transaction(id: id) {
            _type = State(initialValue: existing.type)
            _amountText = State(initialValue: Money.shared.formatMinor(amountMinor: existing.amountMinor))
            _category = State(initialValue: existing.category)
            _localDate = State(initialValue: existing.localDate)
            _note = State(initialValue: existing.note)
            _account = State(initialValue: existing.account)
            _countInBudget = State(initialValue: existing.countInBudget)
            _refundOfId = State(initialValue: existing.refundOfId)
        } else {
            _type = State(initialValue: TxnTypes.expense)
            _amountText = State(initialValue: "")
            _category = State(initialValue: "餐饮")
            _localDate = State(initialValue: LedgerStore.shared.todayIso)
            _note = State(initialValue: "")
            _account = State(initialValue: "现金")
            _countInBudget = State(initialValue: true)
            _refundOfId = State(initialValue: nil)
        }
    }

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

    private var categories: [LedgerCategory] {
        LedgerStore.shared.api.categories().sorted { a, b in
            if a.usageCount != b.usageCount { return a.usageCount > b.usageCount }
            return a.sortOrder < b.sortOrder
        }
    }

    private var refundCandidates: [LedgerTransaction] {
        LedgerStore.shared.api.allTransactions().filter { $0.type == TxnTypes.expense }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("类型") {
                    Picker("类型", selection: $type) {
                        ForEach(TxnTypes.all, id: \.0) { value, label in
                            Text(label).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("金额") {
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                }

                Section("分类") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(categories, id: \.id) { c in
                                Button(c.name) { category = c.name }
                                    .buttonStyle(.bordered)
                                    .tint(category == c.name ? Color.accentColor : .secondary)
                            }
                        }
                    }
                }

                Section("归属与账户") {
                    TextField("yyyy-MM-dd", text: $localDate)
                    TextField("账户/支付方式", text: $account)
                }

                Section("备注") {
                    TextField("例如：午饭", text: $note)
                }

                if type == TxnTypes.expense || type == TxnTypes.refund {
                    Section {
                        Toggle("计入每日预算", isOn: $countInBudget)
                    } footer: {
                        Text("关闭后仍计入总支出统计")
                    }
                }

                if type == TxnTypes.refund {
                    Section("退款关联原账单") {
                        if refundCandidates.isEmpty {
                            Text("还没有可关联的支出账单").font(.footnote).foregroundStyle(.red)
                        } else {
                            ForEach(refundCandidates.prefix(10), id: \.id) { candidate in
                                Button {
                                    refundOfId = candidate.id
                                } label: {
                                    HStack {
                                        Image(systemName: refundOfId == candidate.id ? "checkmark.circle.fill" : "circle")
                                        Text("\(candidate.localDate) \(LedgerStore.shared.format(candidate.amountMinor)) \(candidate.note.isEmpty ? candidate.category : candidate.note)")
                                    }
                                }
                                .tint(.primary)
                            }
                        }
                    }
                }

                if let errorText {
                    Section {
                        Text(errorText).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .listRowBackground(GlassRowBackground())
            .glassFormStyle()
            .navigationTitle(txnId == nil ? "记一笔" : "编辑账单")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save(force: false) }
                }
            }
            .alert("已存在相同账单", isPresented: $confirmDuplicate) {
                Button("仍然保存") { save(force: true) }
                Button("取消", role: .cancel) {}
            } message: {
                Text("同一天、同金额、同备注的账单已存在。仍然保存这一笔吗？")
            }
        }
    }

    private func save(force: Bool) {
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
            dismiss()
        } else if result.errorCode == "DUPLICATE_FINGERPRINT" {
            confirmDuplicate = true
        } else {
            errorText = describeError(result.errorCode)
        }
    }
}
