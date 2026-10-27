import SwiftUI
import shared

/// 首页：今日预算卡 + 今日账单（规范第一批 §6 / §10 / §11）。
/// 靠排版撑层次：近黑与白；颜色只做三件事——黑＝选中与按钮，绿＝收入，红＝超支。
struct HomeView: View {
    @EnvironmentObject private var state: AppState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 56
    /// hero 的基准字号。量宽度那一份必须钉在基准上，否则「按比例算放得下多大」的两边都在长。
    static let heroBasePointSize: CGFloat = 56
    /// 分类行左端那个圆跟着字号长（封顶 1.3 倍）。
    @ScaledMetric(relativeTo: .body) private var iconCircle: CGFloat = 34
    @Environment(\.dynamicTypeSize) private var typeSize
    /// 金额这一行能用的宽、以及同一串字在 56 点时有多宽（量出来，不是估）。
    @State private var heroAvailableWidth: CGFloat = 0
    @State private var heroBaseWidth: CGFloat = 0

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
                .padding(.bottom, PaceSpace.cardGap)
            }
            .clearsFab()
            .fadesScrollTop()
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
            // 撑满卡片再加量：量的是「这一行能用多宽」，不是「这串字本身多宽」。
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: HomeHeroAvailableWidthKey.self, value: g.size.width)
                }
            )

            PaceBar(ratio: barRatio(data), danger: data.overspent)
                .accessibilityValue(Text("已用 \(usedPercent(data))%"))

            // 判据是「整行放得下」，不是「是不是辅助功能档」：xxxLarge 这种还没进辅助功能
            // 的档位也可能放不下，那时折行，点照样会甩到行尾（Ato）。
            // 放得下就是一整行带点（默认字号照旧），放不下就拆两行、不带点。
            ViewThatFits(in: .horizontal) {
                Text(Copy.Home.budgetSpent(
                    budget: plainAmount(data.budgetMinor),
                    spent: plainAmount(max(data.netSpentMinor, 0))
                ))
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.Home.budgetPart(budget: plainAmount(data.budgetMinor)))
                    Text(Copy.Home.spentPart(spent: plainAmount(max(data.netSpentMinor, 0))))
                }
            }
            .font(.footnote)
            .foregroundStyle(PaceColor.ink2)
        }
        .onPreferenceChange(HomeHeroAvailableWidthKey.self) {
            heroAvailableWidth = $0
            #if DEBUG
            print("HERODBG avail=\($0) base=\(heroBaseWidth) size=\(heroPointSize)")
            #endif
        }
        .onPreferenceChange(HomeHeroBaseWidthKey.self) {
            heroBaseWidth = $0
            #if DEBUG
            print("HERODBG avail=\(heroAvailableWidth) base=\($0) size=\(heroPointSize)")
            #endif
        }
    }

    /// 没设预算的卡：日期加「还没设预算」胶囊、一句提示、设置预算——就这三段。
    /// 原来这里还有「今天还剩」和一根 44pt 破折号，屏幕上看着就是一根加载条，
    /// 用户以为 app 卡住了。没数字可报就别摆一个位置出来。
    private func noBudgetContent(_ data: TodayOverview) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(data)

            Text(Copy.Home.noBudgetHint)
                .font(.footnote)
                .foregroundStyle(PaceColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            Button {
                state.tab = .settings
            } label: {
                Text("设置预算")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Copy.Home.statusNoBudget)，\(Copy.Home.noBudgetHint)"))
    }

    /// 日期和状态并排，放不下就上下两行。
    /// 大字号下日期原来会从「10月」后面断行、「26日」掉到第二行；不靠缩小字号
    /// 或截断来救，字号是用户自己选的，他要大字就该拿到大字。状态不能被挤掉，
    /// 它是这张卡的主结论；所以两样都不缩，换的是排法。
    private func header(_ data: TodayOverview) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                dateLabel(data)
                Spacer(minLength: 8)
                statusPill(data).fixedSize()
            }
            VStack(alignment: .leading, spacing: 6) {
                dateLabel(data)
                statusPill(data).fixedSize()
            }
            // 两行也放不下时只剩短写法兜底：「今天」在这一句里是有意思的，
            // 只有实在没有位置时才让位。
            VStack(alignment: .leading, spacing: 6) {
                dateLabel(data, short: true)
                statusPill(data).fixedSize()
            }
        }
    }

    private func dateLabel(_ data: TodayOverview, short: Bool = false) -> some View {
        Text(short ? shortDateLine(data.localDate) : dateLine(data.localDate))
            .font(.footnote)
            .foregroundStyle(PaceColor.ink2)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
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

    /// 首页金额长到多大：跟着系统字号，封顶 1.5 倍，但**不超过这一行放得下的大小**。
    /// 整串可见是硬的（Camo、Ato、Colo 都定过），封顶是软的：放不下就停在放得下的大小，
    /// 不出省略号、不换行。默认字号下这条完全不生效——量出来比 56 大，取的是 56。
    private var heroPointSize: CGFloat {
        let wanted = min(heroSize, 56 * 1.5)
        guard heroAvailableWidth > 0, heroBaseWidth > 0 else { return wanted }
        let fitted = 56 * (heroAvailableWidth / heroBaseWidth)
        return min(wanted, max(56, fitted))
    }

    private func heroAmount(_ data: TodayOverview) -> some View {
        let text = LedgerStore.shared.format(abs(data.remainingMinor))
        return Text(text)
            .font(.system(size: heroPointSize, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(PaceColor.ink)
            .lineLimit(1)
            // 量这串字在 56 点下多宽：拿去按比例算「放到多大才放得下」。
            .background(alignment: .leading) {
                Text(text)
                    .font(.system(size: HomeView.heroBasePointSize, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .hidden()
                    .fixedSize()
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(key: HomeHeroBaseWidthKey.self, value: g.size.width)
                        }
                    )
            }
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
                                .fill(PaceColor.divider)
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
            // 不再按有没有 Key 分叉：两种填法都从同一页进，说的也是同一句话。
            Text(Copy.Home.emptySubtitle)
                .font(.footnote)
                .foregroundStyle(PaceColor.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }

    /// 大字号下：金额自己占一整行。同一行里时间和金额抢地方时，金额不退让
    /// （Colo 在表里定的：金额是这一行唯一必须读准的东西），所以让金额离开那一行。
    /// 默认字号下这一段不走，页面一个像素都不动。
    private func stackedTxnRow(_ txn: LedgerTransaction) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: PaceSpace.inner) {
                rowIcon(txn)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rowTitle(txn))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(PaceColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    // 时间可以换行、可以长，金额不行。
                    Text(homeSubtitle(txn))
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
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(rowAccessibilityLabel(txn)))
    }

    @ViewBuilder
    private func txnRow(_ txn: LedgerTransaction) -> some View {
        if typeSize.isAccessibilitySize {
            stackedTxnRow(txn)
        } else {
            compactTxnRow(txn)
        }
    }

    private func rowIcon(_ txn: LedgerTransaction) -> some View {
        ZStack {
            Circle()
                .fill(PaceColor.softFill)
                .frame(width: min(iconCircle, 34 * 1.3), height: min(iconCircle, 34 * 1.3))
            Image(systemName: iconName(for: txn))
                .paceFont(15, .semibold, relativeTo: .body, cap: 1.3)
                .foregroundStyle(PaceColor.ink)
        }
    }

    private func compactTxnRow(_ txn: LedgerTransaction) -> some View {
        HStack(spacing: PaceSpace.inner) {
            ZStack {
                Circle()
                    .fill(PaceColor.softFill)
                    .frame(width: min(iconCircle, 34 * 1.3), height: min(iconCircle, 34 * 1.3))
                Image(systemName: iconName(for: txn))
                    .paceFont(15, .semibold, relativeTo: .body, cap: 1.3)
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

    /// 短写法，只在日期连一整行都放不下时用。
    private func shortDateLine(_ iso: String) -> String {
        let parts = iso.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return iso }
        return "\(month)/\(day)"
    }

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
