import SwiftUI
import shared

/// 首页：玻璃质感今日预算卡 + 今日账单（PLAN §7 页面 1）
struct HomeView: View {
    @State private var overview: TodayOverview?
    @State private var showAdd = false
    @State private var editingTxnId: String?

    var body: some View {
        NavigationStack {
            ZStack {
                GlassBackground()
                if let data = overview {
                    ScrollView {
                        VStack(spacing: 18) {
                            budgetCard(data)
                            todayCard(data)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .padding(.bottom, 110)
                    }
                } else {
                    ProgressView("加载中…")
                }
            }
            .navigationTitle("Pace")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // 悬浮玻璃胶囊「记一笔」
                Button {
                    showAdd = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .bold))
                        Text("记一笔")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassCapsuleButtonStyle(prominent: true))
                .padding(.horizontal, 24)
                .padding(.bottom, 72)
                .frame(maxWidth: 340)
                .frame(maxWidth: .infinity)
            }
            .sheet(isPresented: $showAdd, onDismiss: reload) {
                AddView(txnId: nil)
            }
            .sheet(item: Binding(
                get: { editingTxnId.map { TxnIdBox(id: $0) } },
                set: { editingTxnId = $0?.id }
            ), onDismiss: reload) { box in
                AddView(txnId: box.id)
            }
            .onAppear(perform: reload)
        }
    }

    private func reload() {
        overview = LedgerStore.shared.api.todayOverview(todayIso: LedgerStore.shared.todayIso)
    }

    // MARK: - 玻璃预算大卡

    @ViewBuilder
    private func budgetCard(_ data: TodayOverview) -> some View {
        let store = LedgerStore.shared
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("今天 · \(String(data.localDate.dropFirst(5)))", systemImage: "sparkles")
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                GlassPill(text: data.hasBudget ? (data.overspent ? "已超支" : "预算中") : "未设预算",
                          systemImage: data.hasBudget ? (data.overspent ? "exclamationmark.triangle.fill" : "checkmark.seal.fill") : "gearshape.fill",
                          danger: data.overspent)
            }

            if !data.hasBudget {
                Text("未设置预算")
                    .font(.system(.title, design: .rounded).weight(.bold))
                Text("到「设置 → 每日预算」设置额度后开始追踪。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                (data.overspent ? Text("今日超支").font(.system(.headline, design: .rounded)) : Text("今日剩余").font(.system(.headline, design: .rounded)))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(data.overspent ? "超支 " : "")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(data.overspent ? PaceGradients.danger : PaceGradients.accent)
                    Text(store.format(abs(data.remainingMinor)))
                        .font(.system(size: 54, weight: .heavy, design: .rounded))
                        .foregroundStyle(data.overspent ? AnyShapeStyle(PaceGradients.danger) : AnyShapeStyle(PaceGradients.accent))
                }
                // 预算用量
                if data.budgetMinor > 0 {
                    let used = min(Double(max(data.netSpentMinor, 0)) / Double(data.budgetMinor), 1.0)
                    GlassProgress(ratio: data.overspent ? 1 : used, danger: data.overspent)
                    HStack {
                        Text("预算 \(store.format(data.budgetMinor))")
                        Spacer()
                        Text("已花 \(store.format(data.netSpentMinor))")
                    }
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
                }
                Text("今日剩余 = 预算 − 已花（计入预算的支出 − 退款）")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 30, padding: 22)
    }

    // MARK: - 今日账单玻璃卡

    private func todayCard(_ data: TodayOverview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("今日账单", systemImage: "list.bullet.rectangle")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Text("\(data.transactions.count) 笔")
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)

            if data.transactions.isEmpty {
                HStack {
                    Image(systemName: "leaf")
                        .font(.system(size: 30))
                        .foregroundStyle(PaceGradients.accent.opacity(0.6))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("今天还没有账单")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        Text("飞行模式也能完整记账")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
            } else {
                ForEach(Array(data.transactions), id: \.id) { txn in
                    glassTxnRow(txn)
                    if txn.id != data.transactions.last?.id {
                        Rectangle()
                            .fill(.white.opacity(0.18))
                            .frame(height: 1)
                            .padding(.leading, 44)
                    }
                }
            }
        }
        .glassCard(cornerRadius: 26, padding: 18)
    }

    private func glassTxnRow(_ txn: Transaction) -> some View {
        Button {
            editingTxnId = txn.id
        } label: {
            HStack(spacing: 12) {
                categoryIcon(txn)
                VStack(alignment: .leading, spacing: 2) {
                    Text(txn.note.isEmpty ? txn.category : txn.note)
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                    Text(rowSubtitle(txn))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(amountLabel(txn))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(txn.type == TxnTypes.refund ? AnyShapeStyle(PaceGradients.accent) : AnyShapeStyle(.primary))
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func rowSubtitle(_ txn: Transaction) -> String {
        var parts = [txn.category]
        if txn.type == TxnTypes.expense && !txn.countInBudget {
            parts.append("不计入预算")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func categoryIcon(_ txn: Transaction) -> some View {
        let symbol = symbolFor(txn)
        ZStack {
            Circle()
                .fill(.white.opacity(0.35))
                .frame(width: 34, height: 34)
            Image(systemName: symbol.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(symbol.danger ? PaceGradients.danger : PaceGradients.accent)
        }
    }

    private func symbolFor(_ txn: Transaction) -> (name: String, danger: Bool) {
        switch txn.type {
        case TxnTypes.income: return ("arrow.down.circle.fill", false)
        case TxnTypes.refund: return ("arrow.uturn.left.circle.fill", false)
        case TxnTypes.transfer: return ("arrow.left.arrow.right.circle.fill", false)
        default: return (categorySymbol(txn.category), false)
        }
    }

    private func categorySymbol(_ category: String) -> String {
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
        default: return "circle.fill"
        }
    }
}

/// 小玻璃徽章
struct GlassPill: View {
    let text: String
    let systemImage: String
    var danger = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(.caption2, design: .rounded).weight(.bold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
        .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.4), lineWidth: 1))
        .foregroundStyle(danger ? Color(red: 0.85, green: 0.30, blue: 0.32) : PaceGradients.tint)
    }
}
