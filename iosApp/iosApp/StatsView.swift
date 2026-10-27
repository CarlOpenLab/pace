import SwiftUI
import shared

private enum StatsKind: String, CaseIterable, Identifiable {
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return Copy.Stats.week
        case .month: return Copy.Stats.month
        }
    }
}

/// 统计页：汇总卡 + 花在哪了 + 每天花了多少（墨黑规范第二批 §2）。
/// 实底卡片、无渐变；颜色只用于收入与超支。
struct StatsView: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var kind: StatsKind = .week
    @State private var stats: RangeStats?
    @State private var showSkeleton = false
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: PaceSpace.cardGap) {
                    picker
                    content
                }
                .padding(.horizontal, PaceSpace.screen)
                .padding(.top, 8)
                // 给底栏上方的系统「记一笔」附件留出滚动余量
                .padding(.bottom, 100)
            }
            .paceScreen()
            .navigationTitle(Copy.Stats.title)
        }
        .task { await load() }
        .onAppear {
            if hasLoaded { refresh() }
        }
        .onChange(of: kind) { _, _ in refresh() }
        .onChange(of: appState.showAdd) { _, showing in
            if !showing { refresh() }
        }
        .onChange(of: appState.showDrafts) { _, showing in
            if !showing { refresh() }
        }
    }

    // MARK: - 范围与内容

    private var picker: some View {
        // 同上：和记一笔、账单同一个组件，跟着字号长。
        PaceSegmented(
            options: StatsKind.allCases,
            title: { $0.title },
            selection: $kind,
            // 跟账单同一句组名：不然读屏只念「本周」，听不出这个本周管的是哪一段。
            groupLabel: Copy.Bills.rangeLabel
        )
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if let data = stats {
            summaryCard(data)
            categoryCard(data)
            dailyCard(data)
        } else if showSkeleton {
            skeleton
        }
    }

    // MARK: - 数据

    /// 保持现有计算口径：本周 / 本月都走 shared 的区间与统计接口。
    private func makeStats() -> RangeStats? {
        let api = LedgerStore.shared.api
        let today = LedgerStore.shared.todayIso
        switch kind {
        case .week:
            guard let range = api.weekRange(todayIso: today) else { return nil }
            return api.rangeStats(fromLocalDate: range.from, toLocalDate: range.to)
        case .month:
            guard let range = api.monthRange(todayIso: today) else { return nil }
            return api.rangeStats(fromLocalDate: range.from, toLocalDate: range.to)
        }
    }

    /// 本地读取通常很快；超过 300ms 仍没数据时才显示骨架，避免闪一下。
    @MainActor
    private func load() async {
        guard stats == nil else { return }

        let skeletonTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, stats == nil else { return }
            withAnimation(.easeOut(duration: 0.15)) { showSkeleton = true }
        }

        try? await Task.sleep(for: .milliseconds(80))
        guard !Task.isCancelled else {
            skeletonTask.cancel()
            return
        }

        let data = makeStats()
        skeletonTask.cancel()

        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.86)) {
            stats = data
            showSkeleton = false
            hasLoaded = true
        }
    }

    private func refresh() {
        let data = makeStats()
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.35)) {
            stats = data
            showSkeleton = false
            hasLoaded = true
        }
    }

    // MARK: - 加载骨架

    private var skeleton: some View {
        VStack(spacing: PaceSpace.cardGap) {
            VStack(alignment: .leading, spacing: 12) {
                skeletonBlock(width: 124, height: 11)
                skeletonBlock(width: 196, height: 38)

                HStack(spacing: 10) {
                    skeletonCell
                    skeletonCell
                }
                HStack(spacing: 10) {
                    skeletonCell
                    skeletonCell
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .paceCard(radius: PaceRadius.card, padding: PaceSpace.cardPadding)

            VStack(spacing: 12) {
                skeletonRow
                skeletonRow
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Copy.Stats.loading))
    }

    private func skeletonBlock(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(PaceColor.card2)
            .frame(width: width, height: height)
    }

    private var skeletonCell: some View {
        RoundedRectangle(cornerRadius: PaceRadius.block, style: .continuous)
            .fill(PaceColor.card2)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
    }

    private var skeletonRow: some View {
        HStack(spacing: 12) {
            skeletonBlock(width: 44, height: 12)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(PaceColor.card2)
                .frame(maxWidth: .infinity)
                .frame(height: 8)
            skeletonBlock(width: 112, height: 11)
        }
    }

    // MARK: - 汇总卡

    private func summaryCard(_ data: RangeStats) -> some View {
        VStack(alignment: .leading, spacing: PaceSpace.inner) {
            VStack(alignment: .leading, spacing: 4) {
                Text(dateRangeText(from: data.fromLocalDate, to: data.toLocalDate))
                    .paceFont(11)
                    .foregroundStyle(PaceColor.ink2)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Copy.Stats.expense)
                        .paceFont(15, .semibold)
                        .foregroundStyle(PaceColor.ink2)

                    FittedAmountText(text: LedgerStore.shared.format(data.totalExpenseAll), base: 38)
                        .foregroundStyle(PaceColor.ink)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(summaryAccessibilityLabel(data)))

            LazyVGrid(columns: gridColumns, spacing: 10) {
                statCell(
                    label: Copy.Stats.Filter.countInBudget,
                    value: LedgerStore.shared.format(data.totalExpenseInBudget),
                    valueColor: PaceColor.ink,
                    spokenValue: Copy.Stats.spokenAmount(data.totalExpenseInBudget)
                )
                statCell(
                    label: Copy.Stats.refundOffset,
                    value: LedgerStore.shared.format(data.refundTotal),
                    valueColor: PaceColor.ink,
                    spokenValue: Copy.Stats.spokenAmount(data.refundTotal)
                )
                statCell(
                    label: Copy.Stats.Filter.income,
                    value: LedgerStore.shared.format(data.incomeTotal),
                    valueColor: PaceColor.income,
                    spokenValue: Copy.Stats.spokenAmount(data.incomeTotal)
                )
                statCell(
                    label: Copy.Stats.overspent,
                    value: Copy.Stats.overspentDays(Int(data.overspentDays)),
                    valueColor: PaceColor.danger,
                    spokenValue: Copy.Stats.overspentDays(Int(data.overspentDays))
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paceCard(radius: PaceRadius.card, padding: PaceSpace.cardPadding)
        // 卡片分组朗读；内部四格仍是各自独立的无障碍元素。
        .accessibilityElement(children: .contain)
    }

    private var gridColumns: [GridItem] {
        // 大字号下两格并排会把数字挤成省略号，改成一列一格。
        if typeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: 10)]
        }
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
    }

    private func statCell(
        label: String,
        value: String,
        valueColor: Color,
        spokenValue: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .paceFont(11)
                .foregroundStyle(PaceColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .paceFont(15, .bold)
                .foregroundStyle(valueColor)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .paceCardFill(PaceRadius.block, color: PaceColor.card2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(spokenValue))
    }

    // MARK: - 花在哪了

    private func categoryCard(_ data: RangeStats) -> some View {
        let items = Array(data.byCategory)
        return VStack(alignment: .leading, spacing: PaceSpace.inner) {
            Text(Copy.Stats.categoryRanking)
                .font(.headline)
                .foregroundStyle(PaceColor.ink)

            if items.isEmpty {
                Text(Copy.Stats.empty)
                    .paceFont(13)
                    .foregroundStyle(PaceColor.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(items.prefix(6)), id: \.category) { item in
                        categoryRow(item)
                    }
                }

                if items.count > 6 {
                    Text(Copy.Stats.moreCategories(items.count - 6))
                        .paceFont(13)
                        .foregroundStyle(PaceColor.ink2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paceCard()
    }

    private func categoryRow(_ item: CategorySpend) -> some View {
        let percent = Int((item.ratio * 100).rounded())
        let ratio = min(max(item.ratio, 0), 1)

        return VStack(alignment: .leading, spacing: 8) {
            // 分类名和「金额 · 占比」一行放不下时上下两行——金额那一串不许截。
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    categoryName(item)
                    categoryAmount(item, percent)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    categoryName(item)
                    Spacer(minLength: 8)
                    categoryAmount(item, percent)
                }
            }

            PaceBar(ratio: ratio)
                .accessibilityLabel(Text(item.category))
                .accessibilityValue(Text(Copy.Stats.ratioA11y(percent)))
        }
    }

    // MARK: - 每天花了多少

    private func dailyCard(_ data: RangeStats) -> some View {
        let days = Array(data.daily)
        return VStack(alignment: .leading, spacing: PaceSpace.inner) {
            Text(Copy.Stats.dailyBudget)
                .font(.headline)
                .foregroundStyle(PaceColor.ink)

            if days.isEmpty {
                Text(Copy.Stats.empty)
                    .paceFont(13)
                    .foregroundStyle(PaceColor.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(days, id: \.localDate) { day in
                        dailyRow(day)
                    }
                }
            }

            Text(Copy.Stats.dailyFormula)
                .paceFont(11)
                .foregroundStyle(PaceColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paceCard()
    }

    private func dailyRow(_ day: DailyOverview) -> some View {
        // 默认字号：日期、进度条、金额一行（日期 44 点、金额 128 点，和以前一样）。
        // 大字号：那两条定宽会把金额挤成省略号，改成日期和金额一行、进度条另起一行。
        Group {
            if typeSize.isAccessibilitySize {
                // 大字号下「已花 / 预算」这一串自己占一行：和日期并排它会剩成「¥4.00 / ¥…」。
                VStack(alignment: .leading, spacing: 6) {
                    dailyDate(day)
                    dailyAmount(day, wraps: true)
                    dailyBar(day)
                }
            } else {
                HStack(spacing: 8) {
                    dailyDate(day)
                        .frame(width: 44, alignment: .leading)
                    dailyBar(day)
                    dailyAmount(day)
                        .frame(width: 128, alignment: .trailing)
                }
            }
        }
    }

    private func dailyDate(_ day: DailyOverview) -> some View {
        Text(shortDate(day.localDate))
            .paceFont(12)
            .foregroundStyle(day.overspent ? PaceColor.danger : PaceColor.ink)
            .lineLimit(1)
    }

    private func dailyAmount(_ day: DailyOverview, wraps: Bool = false) -> some View {
        Text(dailyAmountText(day))
            .paceFont(11, design: .monospaced)
            .foregroundStyle(PaceColor.ink2)
            .lineLimit(wraps ? nil : 1)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func dailyBar(_ day: DailyOverview) -> some View {
        PaceBar(ratio: dailyRatio(day), danger: day.overspent)
            .accessibilityLabel(Text(shortDate(day.localDate)))
            .accessibilityValue(Text(Copy.Stats.usedA11y(dailyPercent(day))))
    }

    private func categoryName(_ item: CategorySpend) -> some View {
        Text(item.category)
            .paceFont(15)
            .foregroundStyle(PaceColor.ink)
            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func categoryAmount(_ item: CategorySpend, _ percent: Int) -> some View {
        Text("\(LedgerStore.shared.format(item.amountMinor)) · \(percent)%")
            .paceFont(13, design: .monospaced)
            .foregroundStyle(PaceColor.ink2)
            .lineLimit(1)
    }

    private func dailyRatio(_ day: DailyOverview) -> Double {
        guard day.hasBudget, day.budgetMinor > 0 else { return 0 }
        let used = Double(max(day.netSpentMinor, 0)) / Double(day.budgetMinor)
        return min(max(used, 0), 1)
    }

    private func dailyPercent(_ day: DailyOverview) -> Int {
        guard day.hasBudget, day.budgetMinor > 0 else { return 0 }
        let used = Double(max(day.netSpentMinor, 0)) / Double(day.budgetMinor) * 100
        return max(0, Int(used.rounded()))
    }

    private func dailyAmountText(_ day: DailyOverview) -> String {
        let spent = LedgerStore.shared.format(day.netSpentMinor)
        guard day.hasBudget else { return spent }
        return "\(spent) / \(LedgerStore.shared.format(day.budgetMinor))"
    }

    // MARK: - 日期与无障碍文案

    private func dateRangeText(from: String, to: String) -> String {
        "\(monthDay(from)) – \(monthDay(to))"
    }

    private func monthDay(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return iso }
        return Copy.Stats.monthDay(month: month, day: day)
    }

    private func shortDate(_ iso: String) -> String {
        guard iso.count >= 10 else { return iso }
        return String(iso.dropFirst(5))
    }

    private func summaryAccessibilityLabel(_ data: RangeStats) -> String {
        "\(dateRangeText(from: data.fromLocalDate, to: data.toLocalDate))，\(Copy.Stats.expense) \(Copy.Stats.spokenAmount(data.totalExpenseAll))"
    }
}
