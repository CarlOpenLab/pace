import SwiftUI
import shared

private enum StatsKind: String, CaseIterable, Identifiable {
    case week = "本周"
    case month = "本月"
    var id: String { rawValue }
}

/// 统计页：周/月汇总、分类排行、每日预算对比（PLAN §7 页面 4）
struct StatsView: View {
    @State private var kind: StatsKind = .week

    private var stats: RangeStats? {
        let api = LedgerStore.shared.api
        let today = LedgerStore.shared.todayIso
        guard let range = kind == .week ? api.weekRange(todayIso: today) : api.monthRange(todayIso: today) else {
            return nil
        }
        return api.rangeStats(fromLocalDate: range.from, toLocalDate: range.to)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let data = stats {
                    List {
                        Picker("范围", selection: $kind) {
                            ForEach(StatsKind.allCases) { k in
                                Text(k.rawValue).tag(k)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)

                        Section {
                            row("支出（全部）", data.totalExpenseAll, bold: true)
                            row("计入预算", data.totalExpenseInBudget)
                            row("退款冲减", data.refundTotal)
                            row("收入", data.incomeTotal)
                            row("转账（不计入支出）", data.transferTotal)
                            if data.overspentDays > 0 {
                                Label("超支 \(data.overspentDays) 天", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.red)
                            }
                        } header: {
                            Text("\(data.fromLocalDate) ~ \(data.toLocalDate)")
                        }

                        Section("分类排行") {
                            let items = Array(data.byCategory)
                            if items.isEmpty {
                                Text("暂无支出记录。").font(.subheadline).foregroundStyle(.secondary)
                            }
                            ForEach(items, id: \.category) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(item.category)
                                        Spacer()
                                        Text("\(LedgerStore.shared.format(item.amountMinor)) · \(Int(item.ratio * 100))%")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    GeometryReader { proxy in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.secondary.opacity(0.15))
                                            Capsule()
                                                .fill(item.ratio >= 1 ? Color.red : Color.accentColor)
                                                .frame(width: proxy.size.width * min(item.ratio, 1))
                                        }
                                    }
                                    .frame(height: 6)
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        Section("每日预算对比") {
                            ForEach(Array(data.daily), id: \.localDate) { day in
                                dayRow(day)
                            }
                        }
                    }
                } else {
                    ProgressView("加载中…")
                }
            }
            .navigationTitle("统计")
        }
    }

    private func row(_ label: String, _ value: Int64, bold: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(LedgerStore.shared.format(value))
                .fontWeight(bold ? .semibold : .regular)
        }
    }

    private func dayRow(_ day: DailyOverview) -> some View {
        let ratio: Double = day.hasBudget && day.budgetMinor > 0
            ? min(Double(day.netSpentMinor) / Double(day.budgetMinor), 1.0)
            : 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String(day.localDate.dropFirst(5))).font(.caption)
                Spacer()
                Text(day.hasBudget
                     ? "\(LedgerStore.shared.format(day.netSpentMinor)) / \(LedgerStore.shared.format(day.budgetMinor))"
                     : LedgerStore.shared.format(day.netSpentMinor))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(day.overspent ? Color.red : Color.accentColor)
                        .frame(width: proxy.size.width * ratio)
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 2)
    }
}
