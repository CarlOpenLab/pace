import SwiftUI
import shared

/// 首页：今日预算卡 + 今日账单（规范第一批 §6 / §10 / §11）。
/// 靠排版撑层次：近黑与白；颜色只做三件事——黑＝选中与按钮，绿＝收入，红＝超支。
struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var ai: AiSettings

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 56

    @State private var overview: TodayOverview?
    @State private var showSkeleton = false
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: PaceSpace.cardGap) {
                    content
                }
                .padding(.horizontal, PaceSpace.screen)
                .padding(.top, 8)
                // 给右下角浮着的「记一笔」留出滚动余量（76）
                .padding(.bottom, 76)
            }
            .tracksFabScroll()
            .paceScreen()
            .navigationTitle(Copy.appName)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await load() }
        .onAppear {
            if hasLoaded { refresh() }
        }
        .onChange(of: state.showAdd) { _, showing in
            if !showing { refresh() }
        }
        .onChange(of: state.showDrafts) { _, showing in
            if !showing { refresh() }
        }
        .onChange(of: state.showQuickAdd) { _, showing in
            if !showing { refresh() }
        }
    }

    // MARK: - 内容与状态

    @ViewBuilder
    private var content: some View {
        if let data = overview {
            budgetCard(data)
                .transition(cardTransition)
            todayCard(data)
                .transition(cardTransition)
        } else if showSkeleton {
            VStack(spacing: PaceSpace.cardGap) {
                SkeletonCard(height: 216)
                SkeletonCard(height: 200)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(Copy.Home.loading))
        }
    }

    private var cardTransition: AnyTransition {
        reduceMotion ? .opacity : .offset(y: 8).combined(with: .opacity)
    }

    /// 先让第一帧画出来；本地读取通常很快，因此不会闪骨架。
    /// 只有超过 300ms 仍未拿到数据时才出现骨架（规范 §6「加载」）。
    @MainActor
    private func load() async {
        guard overview == nil else { return }

        let skeleton = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, overview == nil else { return }
            withAnimation(.easeOut(duration: 0.15)) { showSkeleton = true }
        }

        try? await Task.sleep(for: .milliseconds(80))
        guard !Task.isCancelled else {
            skeleton.cancel()
            return
        }

        let data = LedgerStore.shared.api.todayOverview(todayIso: LedgerStore.shared.todayIso)
        skeleton.cancel()

        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.86)) {
            overview = data
            showSkeleton = false
            hasLoaded = true
        }
    }

    private func refresh() {
        let data = LedgerStore.shared.api.todayOverview(todayIso: LedgerStore.shared.todayIso)
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.35)) {
            overview = data
            showSkeleton = false
            hasLoaded = true
        }
    }

    // MARK: - 预算卡

    @ViewBuilder
    private func budgetCard(_ data: TodayOverview) -> some View {
        if data.hasBudget {
            budgetContent(data)
                .paceCard(radius: PaceRadius.hero, padding: PaceSpace.heroPadding)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(budgetAccessibilityLabel(data)))
                .accessibilityValue(Text("已用 \(usedPercent(data))%"))
        } else {
            noBudgetContent(data)
                .paceCard(radius: PaceRadius.hero, padding: PaceSpace.heroPadding)
        }
    }

    private func budgetContent(_ data: TodayOverview) -> some View {
        VStack(alignment: .leading, spacing: PaceSpace.inner) {
            header(data)

            VStack(alignment: .leading, spacing: 4) {
                Text(data.overspent ? Copy.Home.remainingOverspentLabel : Copy.Home.remainingLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PaceColor.ink2)
                heroAmount(data)
            }

            PaceBar(ratio: barRatio(data), danger: data.overspent)
                .accessibilityValue(Text("已用 \(usedPercent(data))%"))

            Text(Copy.Home.budgetSpent(
                budget: plainAmount(data.budgetMinor),
                spent: plainAmount(max(data.netSpentMinor, 0))
            ))
            .font(.footnote)
            .foregroundStyle(PaceColor.ink2)
        }
    }

    private func noBudgetContent(_ data: TodayOverview) -> some View {
        VStack(alignment: .leading, spacing: PaceSpace.inner) {
            VStack(alignment: .leading, spacing: PaceSpace.inner) {
                header(data)

                VStack(alignment: .leading, spacing: 4) {
                    Text(Copy.Home.remainingLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PaceColor.ink2)
                    // 没设预算时不是「0」，也不是占位条：和金额同一档字体的 em dash，ink3。
                    // 用默认字面而不是 rounded——rounded 的破折号两端是圆头，44pt heavy 下整颗像一根灰胶囊，
                    // 会被读成「正在加载」的占位条。
                    Text("—")
                        .font(.system(size: 44, weight: .heavy))
                        .foregroundStyle(PaceColor.ink3)
                        .lineLimit(1)
                        .accessibilityHidden(true)
                }

                Text(Copy.Home.noBudgetHint)
                    .font(.footnote)
                    .foregroundStyle(PaceColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(Copy.Home.statusNoBudget)，\(Copy.Home.noBudgetHint)"))

            Button {
                state.tab = .settings
            } label: {
                Text("设置预算")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func header(_ data: TodayOverview) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(dateLine(data.localDate))
                .font(.footnote)
                .foregroundStyle(PaceColor.ink2)
            Spacer(minLength: 8)
            statusPill(data)
        }
    }

    @ViewBuilder
    private func statusPill(_ data: TodayOverview) -> some View {
        if !data.hasBudget {
            StatusPill(text: Copy.Home.statusNoBudget, kind: .noBudget)
        } else if data.overspent {
            StatusPill(text: Copy.Home.statusOverspent, kind: .overspent)
        } else {
            StatusPill(text: Copy.Home.statusWithinBudget, kind: .withinBudget)
        }
    }

    private func heroAmount(_ data: TodayOverview) -> some View {
        Text(LedgerStore.shared.format(abs(data.remainingMinor)))
            .font(.system(size: heroSize, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(PaceColor.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.35), value: data.remainingMinor)
    }

    private func barRatio(_ data: TodayOverview) -> Double {
        guard data.budgetMinor > 0 else { return 0 }
        let used = Double(max(data.netSpentMinor, 0)) / Double(data.budgetMinor)
        return min(max(used, 0), 1)
    }

    private func usedPercent(_ data: TodayOverview) -> Int {
        guard data.budgetMinor > 0 else { return 0 }
        let used = Double(max(data.netSpentMinor, 0)) / Double(data.budgetMinor) * 100
        return max(0, Int(used.rounded()))
    }

    // MARK: - 今日账单卡

    private func todayCard(_ data: TodayOverview) -> some View {
        VStack(alignment: .leading, spacing: PaceSpace.inner) {
            HStack(alignment: .firstTextBaseline) {
                Text(Copy.Home.todayBillsTitle)
                    .font(.headline)
                    .foregroundStyle(PaceColor.ink)
                Spacer(minLength: 8)
                // 空卡里已经有「还没有账单」，0 笔时不再挂一个 0：计数只在有数时出现。
                if !data.transactions.isEmpty {
                    Text("\(data.transactions.count) 笔")
                        .font(.footnote)
                        .foregroundStyle(PaceColor.ink2)
                        .monospacedDigit()
                }
            }

            if data.transactions.isEmpty {
                emptyToday
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(data.transactions), id: \.id) { txn in
                        txnRow(txn)
                        if txn.id != data.transactions.last?.id {
                            Rectangle()
                                .fill(PaceColor.line)
                                .frame(height: 1)
                                .padding(.leading, 46)
                        }
                    }
                }
            }
        }
        .paceCard(radius: PaceRadius.card)
    }

    private var emptyToday: some View {
        VStack(spacing: 8) {
            Text("还没有账单")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PaceColor.ink)
            // 和主按钮、键盘那颗键同一个判据：只有真走模型的人读到的才是「说一句话就行」。
            Text(ai.usesRemoteModel ? Copy.Home.emptySubtitleWithKey : Copy.Home.emptySubtitleNoKey)
                .font(.footnote)
                .foregroundStyle(PaceColor.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }

    private func txnRow(_ txn: LedgerTransaction) -> some View {
        HStack(spacing: PaceSpace.inner) {
            ZStack {
                Circle()
                    .fill(PaceColor.softFill)
                    .frame(width: 34, height: 34)
                Image(systemName: iconName(for: txn))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PaceColor.ink)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(rowTitle(txn))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PaceColor.ink)
                    .lineLimit(1)
                // 没备注时标题已经是分类名，副标题只写时间（带账户就加账户）。
                Text(homeSubtitle(txn))
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
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(rowAccessibilityLabel(txn)))
    }

    private func rowTitle(_ txn: LedgerTransaction) -> String {
        txn.note.isEmpty ? txn.category : txn.note
    }

    private func amountColor(_ txn: LedgerTransaction) -> Color {
        switch txn.type {
        case TxnTypes.income, TxnTypes.refund:
            return PaceColor.income
        default:
            return PaceColor.ink
        }
    }

    private func timeString(_ txn: LedgerTransaction) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: txn.timezoneId) ?? .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: Double(txn.occurredAtEpochMillis) / 1000))
    }

    private func iconName(for txn: LedgerTransaction) -> String {
        switch txn.type {
        case TxnTypes.income:
            return "arrow.down.left"
        case TxnTypes.refund:
            return "arrow.uturn.backward"
        case TxnTypes.transfer:
            return "arrow.left.arrow.right"
        default:
            return categoryIconName(txn.category)
        }
    }

    /// 标题是分类名时，副标题不再重复分类。
    private func homeSubtitle(_ txn: LedgerTransaction) -> String {
        var parts: [String] = []
        if !txn.note.isEmpty { parts.append(txn.category) }
        parts.append(timeString(txn))
        if txn.note.isEmpty, !txn.account.isEmpty { parts.append(txn.account) }
        return parts.joined(separator: " · ")
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
        default: return "circle.fill"
        }
    }

    // MARK: - 文案与无障碍

    private func dateLine(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return iso }
        return "今天 · \(month)月\(day)日"
    }

    /// 去掉 `format` 前缀的货币符号（Copy 的预算行自己带 ¥）。
    private func plainAmount(_ minor: Int64) -> String {
        let text = LedgerStore.shared.format(minor)
        if let start = text.firstIndex(where: { $0.isNumber || $0 == "-" }) {
            return String(text[start...])
        }
        return text
    }

    private func budgetAccessibilityLabel(_ data: TodayOverview) -> String {
        let remaining = data.overspent
            ? "\(Copy.Home.remainingOverspentLabel) \(spokenAmount(abs(data.remainingMinor)))"
            : "\(Copy.Home.remainingLabel) \(spokenAmount(max(data.remainingMinor, 0)))"
        return "\(remaining)，预算 \(spokenAmount(data.budgetMinor))，已花 \(spokenAmount(max(data.netSpentMinor, 0)))"
    }

    private func rowAccessibilityLabel(_ txn: LedgerTransaction) -> String {
        let title = rowTitle(txn)
        let kind = typeLabel(txn.type)
        let amount = spokenAmount(txn.amountMinor)
        if title == txn.category {
            return "\(title)，\(kind) \(amount)"
        }
        return "\(title)，\(txn.category)，\(kind) \(amount)"
    }

    private func typeLabel(_ type: String) -> String {
        TxnTypes.all.first(where: { $0.0 == type })?.1 ?? type
    }

    /// 规范 §11 的读法：128 元 5 角。
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
}
