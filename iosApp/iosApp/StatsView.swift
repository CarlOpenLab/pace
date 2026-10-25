import SwiftUI
import shared

private enum StatsKind: String, CaseIterable, Identifiable {
    case week = "本周"
    case month = "本月"
    var id: String { rawValue }
}

/// 统计页：玻璃卡片式周/月汇总、分类排行、每日预算对比（PLAN §7 页面 4）
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
            ZStack {
                GlassBackground()
                if let data = stats {
                    ScrollView {
                        VStack(spacing: 16) {
                            picker
                            summaryCard(data)
                            categoryCard(data)
                            dailyCard(data)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .padding(.bottom, 100)
                    }
                } else {
                    ProgressView("加载中…")
                }
            }
            .navigationTitle("统计")
        }
    }

    private var picker: some View {
        HStack(spacing: 8) {
            ForEach(StatsKind.allCases) { k in
                Button(k.rawValue) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { kind = k }
                }
                .buttonStyle(GlassCapsuleButtonStyle(prominent: kind == k))
            }
            Spacer()
        }
    }

    // MARK: - 汇总卡

    private func summaryCard(_ data: RangeStats) -> some View {
        let store = LedgerStore.shared
        return VStack(alignment: .leading, spacing: 14) {
            Text("\(data.fromLocalDate) ~ \(data.toLocalDate)")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("支出")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(store.format(data.totalExpenseAll))
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(PaceGradients.accent)
            }

            HStack(spacing: 14) {
                statChip(label: "计入预算", value: store.format(data.totalExpenseInBudget))
                statChip(label: "退款冲减", value: store.format(data.refundTotal))
                statChip(label: "收入", value: store.format(data.incomeTotal))
            }
            HStack(spacing: 14) {
                statChip(label: "转账", value: store.format(data.transferTotal), note: "不计入支出")
                if data.overspentDays > 0 {
                    statChip(label: "超支", value: "\(data.overspentDays) 天", danger: true)
                } else {
                    statChip(label: "超支", value: "0 天")
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 28, padding: 20)
    }

    private func statChip(label: String, value: String, note: String? = nil, danger: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(danger ? Color(red: 0.85, green: 0.30, blue: 0.32) : .primary)
            if let note {
                Text(note)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.22)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.3), lineWidth: 1))
    }

    // MARK: - 分类排行卡

    private func categoryCard(_ data: RangeStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("分类排行", systemImage: "chart.pie.fill")
                .font(.system(.headline, design: .rounded))
            let items = Array(data.byCategory)
            if items.isEmpty {
                Text("暂无支出记录。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(items, id: \.category) { item in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(PaceGradients.accent.opacity(0.85))
                            .frame(width: 8, height: 8)
                        Text(item.category)
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                        Spacer()
                        Text("\(LedgerStore.shared.format(item.amountMinor)) · \(Int(item.ratio * 100))%")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    GlassProgress(ratio: item.ratio >= 1 ? 1 : item.ratio)
                }
            }
        }
        .glassCard(cornerRadius: 26, padding: 20)
    }

    // MARK: - 每日预算对比卡

    private func dailyCard(_ data: RangeStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("每日预算对比", systemImage: "chart.bar.doc.horizontal.fill")
                .font(.system(.headline, design: .rounded))
            ForEach(Array(data.daily), id: \.localDate) { day in
                let ratio: Double = day.hasBudget && day.budgetMinor > 0
                    ? min(Double(max(day.netSpentMinor, 0)) / Double(day.budgetMinor), 1.0)
                    : 0
                HStack(spacing: 10) {
                    Text(String(day.localDate.dropFirst(5)))
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .frame(width: 42, alignment: .leading)
                    GlassProgress(ratio: day.overspent ? 1 : ratio, danger: day.overspent)
                    Text(day.hasBudget
                         ? "\(LedgerStore.shared.format(day.netSpentMinor)) / \(LedgerStore.shared.format(day.budgetMinor))"
                         : LedgerStore.shared.format(day.netSpentMinor))
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 128, alignment: .trailing)
                }
            }
        }
        .glassCard(cornerRadius: 26, padding: 20)
    }
}
