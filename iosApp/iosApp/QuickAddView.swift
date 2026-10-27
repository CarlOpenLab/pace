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
/// 2026-10-27：换回系统 `.segmented`（Carl 定，和账单、统计一致）——要的是那颗真液态玻璃槽。
/// 自绘的 PaceSegmented 玻璃被一层实色墨压住，画布是纯色时没有玻璃感。
/// 代价：最大档下这一行不跟 Dynamic Type 长（量到字高 35，旁边正文 120）。
/// 切换仍然只改 mode：输入框、草稿、解析结果都不重建。
struct AddModeSwitcher: View {
    @Binding var mode: AddFillMode

    var body: some View {
        Picker(selection: $mode) {
            Text(Copy.AddMode.sentence).tag(AddFillMode.sentence)
            Text(Copy.AddMode.manual).tag(AddFillMode.manual)
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        // 承诺要在按之前就听到：已经填的东西不会因为换填法丢掉。
        .accessibilityHint(Copy.AddMode.switchHint)
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

    /// 草稿卡金额：display 那一套——跟着系统字号长、封顶 1.5 倍（34→51）、不低于 34。
    /// 原来这里带着 minimumScaleFactor(0.6)，等于字一大就把用户选的字号压回去；
    /// 现在放不下就换行，不许缩。
    @ScaledMetric(relativeTo: .largeTitle) private var draftAmountScaled: CGFloat = 34
    /// 字段名的列宽跟着字号长（封顶 1.6 倍），否则大字号下「分类」两个字会被挤成两行。
    @ScaledMetric(relativeTo: .body) private var fieldLabelWidth: CGFloat = 40

    private var draftAmountSize: CGFloat {
        min(max(34, draftAmountScaled), 34 * 1.5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 金额和类型胶囊：并排放不下时，胶囊整颗落到金额下面，金额自己不被挤窄。
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    amountLabel
                    Spacer(minLength: 8)
                    typePill
                }
                VStack(alignment: .leading, spacing: 6) {
                    amountLabel
                    typePill
                }
            }
            .padding(.bottom, 12)

            Rectangle()
                .fill(PaceColor.divider)
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

    private var amountLabel: some View {
        Text(amountText)
            .font(.system(size: draftAmountSize, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(item.type == TxnTypes.refund ? PaceColor.income : PaceColor.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    // 类型胶囊只报数、不改成菜单：要选转账或退款，出口在草稿确认页的菜单里。
    private var typePill: some View {
        Text(typeLabel)
            .paceFont(11, .medium, relativeTo: .caption2)
            .foregroundStyle(PaceColor.ink2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(PaceColor.card2, in: Capsule(style: .continuous))
    }

    private func fieldRow(_ label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .paceFont(11, .regular, relativeTo: .caption2)
                .foregroundStyle(PaceColor.ink2)
                .frame(width: min(fieldLabelWidth, 40 * 1.6), alignment: .leading)
            Text(value)
                .paceFont(15, .regular, relativeTo: .subheadline)
                .foregroundStyle(PaceColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 32)
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
