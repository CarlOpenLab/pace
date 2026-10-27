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
/// 切边不能是硬的：卡片白底在屏中间被一条直线剁掉，字的上半截没了。所以切线上留 8 点，
/// 在里头做淡出，和记一笔页顶边接缝同一个值、同一套写法（`mask` + `LinearGradient`），
/// 不用系统的滚动边缘效果——它连模糊一起加，这底下没有东西可糊，糊出来是假的。
///
/// 淡出只在下面确实还有内容被裁的时候出现：装得下不淡、滚到底也不淡，
/// 不然最后一张卡会永远半透明。淡的是内容（挂在这层 mask 上），按钮在它外面，不受影响。
///
/// 数（iPhone 18 Pro，最大档，扫像素量）：滚动框底边 791；按钮可见框 683.7 … 741
/// （默认档和最大档一样高——按钮自己的字号封顶 1.5）；框底到按钮底 50。
/// 所以让开 = 50 + 58 + 8 = 116，切线落在 675，离按钮上沿 8.7。
struct FabClearance: ViewModifier {
    private let fabHeight: CGFloat = 58
    private let gapUnderFab: CGFloat = 50
    private let seam: CGFloat = 8

    /// 下面还有内容没露出来（滚动位置不在底）。
    @State private var moreBelow = false

    private var height: CGFloat { gapUnderFab + fabHeight + seam }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height > 0.5
            } action: { _, below in
                moreBelow = below
            }
            .mask {
                if moreBelow {
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(
                            colors: [.black, PaceColor.canvas.opacity(0)],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: seam)
                    }
                } else {
                    Color.black
                }
            }
            .padding(.bottom, height)
    }
}

/// 顶边 8 点渐隐：内容往上滚、第一行钻到导航栏底下才开始淡，滚回顶部就收掉。
///
/// 写法和记一笔页顶边、以及底边那条接缝同一套（`mask` + `LinearGradient`，8 点）。
/// 停在顶部时不能淡：第一张卡的顶边发灰是另一个毛病。
struct ScrollTopFade: ViewModifier {
    private let seam: CGFloat = 8
    @State private var scrolled = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 0.5
            } action: { _, up in
                scrolled = up
            }
            .mask {
                if scrolled {
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [PaceColor.canvas.opacity(0), .black],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: seam)
                        Color.black
                    }
                } else {
                    Color.black
                }
            }
    }
}

extension View {
    /// 这一页有浮动的「记一笔」时，用它把那条空间让出来。
    func clearsFab() -> some View {
        modifier(FabClearance())
    }
}

extension View {
    /// 带导航栏的滚动页用它：往上滚过之后顶边 8 点渐隐。
    func fadesScrollTop() -> some View {
        modifier(ScrollTopFade())
    }
}
