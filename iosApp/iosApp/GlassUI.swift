import SwiftUI

// MARK: - 玻璃质感设计系统
// 基于 Material 毛玻璃 + 多层柔和渐变 + 大圆角，兼容 iOS 16（编译期不依赖 iOS 26 glassEffect API）。

/// 品牌渐变
enum PaceGradients {
    /// 主色渐变：青绿 → 薄荷
    static let accent = LinearGradient(
        colors: [Color(red: 0.05, green: 0.52, blue: 0.44), Color(red: 0.30, green: 0.78, blue: 0.62)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// 超支红渐变
    static let danger = LinearGradient(
        colors: [Color(red: 0.90, green: 0.30, blue: 0.32), Color(red: 0.98, green: 0.50, blue: 0.44)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// 玻璃卡顶部高光
    static let sheen = LinearGradient(
        stops: [
            .init(color: .white.opacity(0.35), location: 0),
            .init(color: .white.opacity(0.06), location: 0.35),
            .init(color: .clear, location: 1)
        ],
        startPoint: .top, endPoint: .bottom
    )

    /// 品牌单色（tab tint 等）
    static let tint = Color(red: 0.07, green: 0.50, blue: 0.42)
}

/// 全局环境背景：多层柔和渐变，给玻璃材质提供折射内容
struct GlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [Color(red: 0.03, green: 0.10, blue: 0.11), Color(red: 0.05, green: 0.07, blue: 0.14)],
                    startPoint: .top, endPoint: .bottom
                )
                LinearGradient(
                    colors: [Color(red: 0.10, green: 0.45, blue: 0.38).opacity(0.35), .clear],
                    startPoint: .topLeading, endPoint: .center
                )
                LinearGradient(
                    colors: [Color(red: 0.30, green: 0.25, blue: 0.60).opacity(0.25), .clear],
                    startPoint: .bottomTrailing, endPoint: .center
                )
            } else {
                LinearGradient(
                    colors: [Color(red: 0.91, green: 0.97, blue: 0.95), Color(red: 0.94, green: 0.94, blue: 0.99)],
                    startPoint: .top, endPoint: .bottom
                )
                LinearGradient(
                    colors: [Color(red: 0.62, green: 0.92, blue: 0.82).opacity(0.55), .clear],
                    startPoint: .topLeading, endPoint: .center
                )
                LinearGradient(
                    colors: [Color(red: 0.78, green: 0.82, blue: 1.0).opacity(0.5), .clear],
                    startPoint: .bottomTrailing, endPoint: .center
                )
            }
        }
        .ignoresSafeArea()
    }
}

/// 玻璃卡片修饰：毛玻璃 + 细描边 + 顶部高光 + 柔和投影
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 26
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(PaceGradients.sheen)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.45), .white.opacity(0.08)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.10), radius: 22, x: 0, y: 10)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 26, padding: CGFloat = 18) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
}

/// 玻璃胶囊按钮样式
struct GlassCapsuleButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(PaceGradients.accent))
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    Capsule(style: .continuous)
                        .fill(prominent ? AnyShapeStyle(PaceGradients.accent) : AnyShapeStyle(.thickMaterial))
                    if !prominent {
                        Capsule(style: .continuous)
                            .fill(PaceGradients.sheen)
                    }
                }
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(prominent ? 0.35 : 0.5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(prominent ? 0.22 : 0.10), radius: prominent ? 14 : 8, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Form/List 露出玻璃背景并让行变为玻璃行
struct GlassFormBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(GlassBackground())
    }
}

extension View {
    func glassFormStyle() -> some View {
        modifier(GlassFormBackground())
    }
}

/// 玻璃行背景（用于 listRowBackground）
struct GlassRowBackground: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(PaceGradients.sheen.opacity(0.5))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.28), lineWidth: 1)
        )
    }
}

/// 玻璃进度条
struct GlassProgress: View {
    @Environment(\.colorScheme) private var colorScheme
    let ratio: CGFloat
    var danger = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.5))
                Capsule()
                    .fill(danger ? AnyShapeStyle(PaceGradients.danger) : AnyShapeStyle(PaceGradients.accent))
                    .frame(width: proxy.size.width * min(max(ratio, 0), 1))
            }
        }
        .frame(height: 8)
    }
}
