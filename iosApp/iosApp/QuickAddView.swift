import SwiftUI
import shared

/// 「记一笔」页里一句话这条路的零件。
/// 页面本身和两边共用的状态都在 AddView：切换填法不能把已经写好的东西丢掉，
/// 所以这些视图只负责画，不自己留 @State。
enum AddFillMode: Hashable {
    case sentence
    case manual
}

/// 页顶切换器（docs/DESIGN-add-mode-switch.md §1）。
///
/// 外观是 34 高的胶囊，但每个按钮的点击区撑到 44：34 只够看，不够手指点。
/// 外面的 AddView 用 3 + 7 的上下留白把视觉位置补回设计稿的 8 / 12。
struct AddModeSwitcher: View {
    @Binding var mode: AddFillMode

    // 三个高度跟着 label 的字长走，封顶 1.6 倍（和 Colo 的间距规则同一条）。
    // 默认字号下就是原来的 44 / 34 / 28——接字号不是顺手调版式。
    @ScaledMetric(relativeTo: .subheadline) private var tapHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .subheadline) private var trackHeight: CGFloat = 34
    @ScaledMetric(relativeTo: .subheadline) private var pillHeight: CGFloat = 28

    private var tap: CGFloat { min(tapHeight, 44 * 1.6) }
    private var track: CGFloat { min(trackHeight, 34 * 1.6) }
    private var pill: CGFloat { min(pillHeight, 28 * 1.6) }

    var body: some View {
        HStack(spacing: 0) {
            segment(.sentence, title: Copy.AddMode.sentence)
            segment(.manual, title: Copy.AddMode.manual)
        }
        .padding(.horizontal, 3)
        .frame(height: tap)
        // 胶囊高度跟着字长：写死 34 之后，字一放大两段就挤成一团。
        .background(alignment: .center) {
            Capsule(style: .continuous)
                .fill(PaceColor.card2)
                .frame(height: track)
        }
    }

    private func segment(_ value: AddFillMode, title: String) -> some View {
        Button {
            mode = value
        } label: {
            Text(title)
                .paceFont(PaceType.labelBase, .medium)
                .foregroundStyle(mode == value ? PaceColor.onAccent : PaceColor.ink2)
                .lineLimit(1)
                // 不再压字号：minimumScaleFactor(0.85) 就是把用户选的字按回去。
                .frame(maxWidth: .infinity)
                .frame(height: tap)
                .background(alignment: .center) {
                    if mode == value {
                        Capsule(style: .continuous)
                            .fill(PaceColor.accent)
                            .frame(height: pill)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        // 承诺要在按之前就听到：两边都带，不只在当前那一边。
        .accessibilityHint(Text(Copy.AddMode.switchHint))
        .accessibilityAddTraits(mode == value ? .isSelected : [])
    }
}

/// 解析中：原地占住草稿卡的位置，44 高，不跳页、不铺骨架屏。
struct SentenceParsingRow: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
            Text(Copy.Sentence.parsing)
                .font(PaceType.secondary)
                .foregroundStyle(PaceColor.ink2)
            Spacer(minLength: 0)
        }
        .frame(height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Copy.Sentence.parsing))
    }
}

/// 一笔且字段齐全时就地确认的那张卡。点卡片等于「改一下」。
struct SentenceDraftCard: View {
    let item: DraftItem
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(amountText)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(item.type == TxnTypes.refund ? PaceColor.income : PaceColor.ink)
                Spacer(minLength: 8)
                // 类型胶囊只报数、不改成菜单：要选转账或退款，出口在草稿确认页的菜单里。
                Text(typeLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PaceColor.ink2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(PaceColor.card2, in: Capsule(style: .continuous))
            }
            .padding(.bottom, 12)

            Rectangle()
                .fill(PaceColor.line)
                .frame(height: 0.5)

            fieldRow(Copy.Draft.Field.category, value: shortCategory)
            fieldRow(Copy.Draft.Field.date, value: dateText)
            fieldRow(Copy.Draft.Field.account, value: item.account.isEmpty ? "现金" : item.account)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .paceCardFill(18)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("账单草稿"))
        .accessibilityValue(Text(accessibilityValue))
    }

    private func fieldRow(_ label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(PaceColor.ink2)
                .frame(width: 40, alignment: .leading)
            Text(value)
                .font(.system(size: 15))
                .foregroundStyle(PaceColor.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(height: 32)
    }

    private var amountText: String {
        let base = LedgerStore.shared.format(item.amountMinor, currency: item.currency)
        return item.type == TxnTypes.refund ? "-\(base)" : base
    }

    private var typeLabel: String {
        TxnTypes.all.first(where: { $0.0 == item.type })?.1 ?? item.type
    }

    private var shortCategory: String {
        item.category.count > 6 ? String(item.category.prefix(6)) + "…" : item.category
    }

    private var dateText: String {
        if !item.dateText.isEmpty { return item.dateText }
        return item.localDate.isEmpty ? "今天" : DraftDate.display(item.localDate)
    }

    private var accessibilityValue: String {
        [amountText, shortCategory, dateText, item.account.isEmpty ? "现金" : item.account]
            .joined(separator: "，")
    }
}
