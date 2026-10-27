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
/// 在里头做淡出，和记一笔页顶边接缝同一个 8 点、同一条 canvas 渐变，不用系统的滚动边缘效果
/// ——它连模糊一起加，这底下没有东西可糊，糊出来是假的。
///
/// 画在**画布色的 overlay** 里，不是 `mask`：给滚动视图套 mask 会多出一层合成层，
/// 统计页那种「滚动视图就是导航栏大标题的跟随对象」的页面会被打断——大标题在无障碍树里还在
/// （y=120），屏幕上却什么都没画，内容也整体上移。见 ScrollTopFade 的注释。
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
            .overlay(alignment: .bottom) {
                if moreBelow {
                    LinearGradient(
                        colors: [PaceColor.canvas.opacity(0), PaceColor.canvas],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: seam)
                    .allowsHitTesting(false)
                }
            }
            .padding(.bottom, height)
    }
}

/// 顶边 8 点渐隐：内容往上滚、第一行钻到导航栏底下才开始淡，滚回顶部就收掉。
///
/// 和底边那条接缝同一个 8 点、同一条 canvas 渐变；停在顶部时不能淡（第一张卡顶边发灰是另一个毛病）。
///
/// 用 overlay 画画布色渐变，**不能用 mask**：mask 会给滚动视图套一层合成层，
/// 统计页那种把 ScrollView 直接交给 NavigationStack、由它驱动大标题收放的页面会被打断
/// （实测：大标题在无障碍树里 y=120 还在，屏幕上一个字都不画，内容整体上移，偶尔整页白）。
/// 渐变顶层是画布色、底层全透明，视觉上和 mask 一样，但不改滚动视图本身的结构。
/// 渐变挂 `allowsHitTesting(false)`，不吃点击。
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
            .overlay(alignment: .top) {
                if scrolled {
                    LinearGradient(
                        colors: [PaceColor.canvas, PaceColor.canvas.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: seam)
                    .allowsHitTesting(false)
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
