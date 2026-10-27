import SwiftUI

/// 三处共用的分段切换器：记一笔（一句话／手动）、账单（本周／本月／全部）、统计（本周／本月）。
///
/// 规范正本：`docs/DESIGN-switcher.md`（Colo）。这里只写实现，数值都从那份文档来。
///
/// 为什么不用系统的 `.pickerStyle(.segmented)`：它不跟 Dynamic Type 长。
/// 2026-10-27 最大档实测，系统那一行的字高 35，同屏「餐饮」120——差 3.4 倍。
/// App 里别的字都跟着系统走，只剩这一行停在默认字号，就是最后漏掉的一处。
///
/// 长相照系统那颗学：玻璃槽 + 一块抬起来的胶囊。区别只有一条——选中不靠换字色，
/// 字一律 `ink`，选中由胶囊比槽亮一档、再加一道投影来说；读屏由 `.isSelected` 说。
struct PaceSegmented<Value: Hashable>: View {
    let options: [Value]
    let title: (Value) -> String
    @Binding var selection: Value
    /// 整组的读屏名字（账单那组要念「范围」）；每段自己的名字由 title 给。
    var groupLabel: String? = nil
    /// 换段之前就听到的承诺：已经填的东西不会丢。账单、统计不带——数字变化立刻看得见。
    var hint: String? = nil

    /// 槽高 44、内距 3、段高 38。跟着字号长，封顶 1.6 倍（最大档 70／64）。
    @ScaledMetric(relativeTo: .subheadline) private var slotHeight: CGFloat = 44

    private var slot: CGFloat { min(slotHeight, 44 * 1.6) }
    private var track: CGFloat { slot - 6 }

    /// 降低透明度：glassEffect 会退回实底，那时槽没有「板」了——白胶囊会浮在半空。
    /// 这一档显式给实色槽（亮 #E8E8E8、暗 #1B1B1C），描边、胶囊、投影照旧。
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @Namespace private var selectionNS

    private var capsule: Capsule { Capsule(style: .continuous) }

    var body: some View {
        ZStack {
            if reduceTransparency {
                // 没有玻璃可糊，就退成实色槽。6% 的墨这时也不需要了：实色就是那个色。
                capsule.fill(PaceColor.segSlotSolid)
            } else {
                // 槽：玻璃在最底下。内容滚到它底下时照旧模糊。
                capsule
                    .fill(.clear)
                    .glassEffect(.regular, in: .capsule)
                // 压一层墨：纯玻璃压在 #F7F7F7 上 ≈ #F5F5F5，白胶囊压上去只有 1.02:1，
                // 选中块会化掉。压完 ≈ #E8E8E8，和系统那颗的槽 #E7E7E8 一个量级。
                // 暗色压得多（40%），但玻璃还在：滚动时仍然看得见底下糊过去。
                capsule.fill(PaceColor.segSlotTint)
            }
            // 描边是「这是一块玻璃」的唯一静态线索：白底上玻璃本身没有形。
            capsule.strokeBorder(PaceColor.segSlotEdge, lineWidth: 0.5)

            HStack(spacing: 0) {
                ForEach(options, id: \.self) { value in
                    segment(value)
                }
            }
            .padding(3)
        }
        .frame(height: slot)
        .animation(.easeOut(duration: 0.18), value: selection)
        // 容器是一组、每段是独立可点元素：不加 .contain，整组的 accessibilityLabel
        // 会盖到每一段上——三个段全念「范围」，念不出「本周」。
        .accessibilityElement(children: .contain)
        .modifier(GroupLabel(text: groupLabel))
    }

    private func segment(_ value: Value) -> some View {
        Button {
            selection = value
        } label: {
            Text(title(value))
                .paceFont(15, .semibold)
                // 字一律 ink：ink2 压在槽 #E8E8E8 上只有 4.08:1，15 点不算大字，过不了 4.5。
                .foregroundStyle(PaceColor.ink)
                // 单行：段高是固定的，真折两行会被裁。装不下走横向滚动，不缩字、不省略。
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: track)
                .background(alignment: .center) {
                    if selection == value {
                        capsule
                            .fill(PaceColor.segThumb)
                            // 「抬起」：块比槽亮一档 + 这道投影，灰度下也分得出边界。
                            .shadow(color: PaceColor.segThumbShadow, radius: 3, x: 0, y: 1)
                            .matchedGeometryEffect(id: "selected", in: selectionNS)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title(value)))
        .modifier(OptionalHint(text: hint))
        .accessibilityAddTraits(selection == value ? .isSelected : [])
    }
}

/// 没给的时候什么都不加：空的 accessibilityLabel / hint 会让读屏念出一串空白。
private struct OptionalHint: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text {
            content.accessibilityHint(Text(text))
        } else {
            content
        }
    }
}

private struct GroupLabel: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text {
            content.accessibilityLabel(Text(text))
        } else {
            content
        }
    }
}
