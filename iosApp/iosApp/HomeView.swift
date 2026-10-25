import SwiftUI
import shared

/// 首页：今日剩余/超支、预算、已花、今日账单（PLAN §7 页面 1）
struct HomeView: View {
    @State private var overview: TodayOverview?
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if let data = overview {
                    List {
                        Section {
                            budgetCard(data)
                                .listRowInsets(EdgeInsets())
                        }
                        Section {
                            ForEach(Array(data.transactions), id: \.id) { txn in
                                TxnRowView(txn: txn)
                            }
                            if data.transactions.isEmpty {
                                Text("今天还没有账单。飞行模式也能完整记账。")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } header: {
                            Text("今日账单")
                        }
                    }
                    .listStyle(.insetGrouped)
                } else {
                    ProgressView("加载中…")
                }
            }
            .navigationTitle("Pace")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("记一笔") { showAdd = true }
                }
            }
            .sheet(isPresented: $showAdd, onDismiss: reload) {
                AddView(txnId: nil)
            }
            .onAppear(perform: reload)
        }
    }

    private func reload() {
        overview = LedgerStore.shared.api.todayOverview(todayIso: LedgerStore.shared.todayIso)
    }

    @ViewBuilder
    private func budgetCard(_ data: TodayOverview) -> some View {
        let store = LedgerStore.shared
        VStack(alignment: .leading, spacing: 6) {
            if !data.hasBudget {
                Text("今日剩余").font(.caption)
                Text("未设置预算").font(.title2.weight(.semibold))
                Text("到「设置 → 每日预算」设置额度后开始追踪。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if data.overspent {
                Text("今日超支").font(.caption)
                Text(store.format(-data.remainingMinor))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
            } else {
                Text("今日剩余").font(.caption)
                Text(store.format(data.remainingMinor))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
            }
            Text("预算 \(store.format(data.budgetMinor)) · 已花 \(store.format(data.netSpentMinor))")
                .font(.subheadline)
            if data.hasBudget {
                Text("今日剩余 = 预算 − 已花（计入预算的支出 − 退款）")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}
