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
