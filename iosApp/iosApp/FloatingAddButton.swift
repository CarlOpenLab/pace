import SwiftUI

/// 右下角浮着的「记一笔」：全 App 唯一的主操作，只包住按钮本身。
/// 今天和账单两屏共用这一份，统计与设置不出现。
struct FloatingAddButton: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let collapsed = state.fabCollapsed
        Button {
            // 只有一个去处：记一笔页默认停在「一句话」，切到手动由页里的切换器负责。
            state.showAdd = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .paceFont(15, .semibold, relativeTo: .callout, cap: 1.5)
                Text("记一笔")
                    .paceFont(15, .semibold, relativeTo: .callout, cap: 1.5)
            }
            .foregroundStyle(PaceColor.onAccent)
            // 内距和高度跟着字长（Colo 第十五版：胶囊最小高 44，左右内距跟着长）。
            // 封顶 1.5 的理由和别处不同：它是浮在账上的东西，再大就开始挡住下面。
            .pacePadding(15, .leading)
            .pacePadding(18, .trailing)
            .frame(minHeight: 44)
        }
        .buttonStyle(.glassProminent)
        .tint(PaceColor.accent)
        .clipShape(Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(PaceColor.line, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 13, x: 0, y: 12)
        .padding(.trailing, 20)
        .padding(.bottom, 99)
        .opacity(collapsed ? 0 : 1)
        .scaleEffect(collapsed && !reduceMotion ? 0.92 : 1)
        .offset(y: collapsed && !reduceMotion ? 8 : 0)
        .animation(.easeOut(duration: 0.22), value: collapsed)
        .allowsHitTesting(!collapsed)
        .accessibilityLabel(Text("记一笔，打开记账页"))
        .accessibilityHidden(collapsed)
    }
}

/// 接滚动位置：向下滚过 24pt 淡出，反向滚回 24pt 或停手 0.4 秒回原位。
struct FabScrollTracking: ViewModifier {
    @EnvironmentObject private var state: AppState

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                state.updateFabScroll(offset)
            }
        } else {
            content
        }
    }
}

extension View {
    /// 挂在滚动容器上，让浮动的「记一笔」跟着滚动收起。
    func tracksFabScroll() -> some View {
        modifier(FabScrollTracking())
    }
}

/// 「记一笔」压在内容上的那条空间，各页自己让开。
///
/// 为什么不在 TabView 上包 safeAreaInset：那样浮条会落到标签栏上，压住标签本身。
/// 所以留给每一页：滚动内容的可视区到按钮上沿为止，停在顶上时正文不会被压；
/// 多出来的内容滚一下看全（按钮在滚动时本来就会淡出）。
///
/// 缩的是滚动容器的**框**，不是内容的内距。内距只加滚动余量，内容照样画到按钮底下
/// ——首页实测：预算卡的白底一直伸到按钮后面，停在顶上时字被压住。
///
/// 高度跟按钮一起长（同样的 15 点、1.5 倍封顶），不然最大档让得不够。
/// 量的是卡片可见底边离按钮可见顶边的距离，不是行的框：行的框在卡片里还差 23 点，
/// 压住眼睛的是卡片那条边。最大字号实测：不缩时卡片白底伸到按钮顶边下方 30 点；
/// 缩 136 点后内容在最下面一行下面 28 点就停，按钮和它的阴影都不压东西。
struct FabClearance: ViewModifier {
    @ScaledMetric(relativeTo: .callout) private var scaled: CGFloat = 44

    /// 玻璃按钮的可见高：常量写的 44，最大字号实测 58，多出来的 14 是玻璃那层。
    private var fabHeight: CGFloat { min(scaled, 44 * 1.5) + 14 }

    /// 滚动框底边到按钮底边之间那段固定的空（标签页栏让出来的），实测 50。
    private let gapUnderFab: CGFloat = 50

    /// 再留 6 点，卡片底边不贴着按钮的描边。
    private var height: CGFloat { gapUnderFab + fabHeight + 6 }

    func body(content: Content) -> some View {
        content.padding(.bottom, height)
    }
}

extension View {
    /// 这一页有浮动的「记一笔」时，用它把那条空间让出来。
    func clearsFab() -> some View {
        modifier(FabClearance())
    }
}
