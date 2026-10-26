import SwiftUI

/// 右下角浮着的「记一笔」：全 App 唯一的主操作，只包住按钮本身。
/// 今天和账单两屏共用这一份，统计与设置不出现。
struct FloatingAddButton: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var ai: AiSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let collapsed = state.fabCollapsed
        Button {
            // 外观只有一个版本；开了 AI 时这颗按钮直达一句话输入，关着仍进表单。
            if ai.usesRemoteModel {
                state.showQuickAdd = true
            } else {
                state.showAdd = true
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                Text("记一笔")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(PaceColor.onAccent)
            .padding(.leading, 15)
            .padding(.trailing, 18)
            .frame(height: 44)
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
        .accessibilityLabel("记一笔")
        .accessibilityHint(ai.usesRemoteModel ? "打开一句话记账" : "打开新账单")
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
