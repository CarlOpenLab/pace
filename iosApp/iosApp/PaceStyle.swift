import SwiftUI
import UIKit

// MARK: - 墨黑设计系统（Colo 规范第一批）
// 靠排版撑层次：近黑与白；颜色只做三件事——黑＝选中与按钮，绿＝收入，红＝超支；紫只标一句话记账入口。

extension Color {
    init(light: UInt32, lightAlpha: Double = 1, dark: UInt32, darkAlpha: Double = 1) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            let alpha = traits.userInterfaceStyle == .dark ? darkAlpha : lightAlpha
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: CGFloat(alpha)
            )
        })
    }
}

enum PaceColor {
    static let canvas = Color(light: 0xF7F7F7, dark: 0x0C0C0D)
    static let card = Color(light: 0xFFFFFF, dark: 0x1A1A1C)
    static let card2 = Color(light: 0xF2F2F4, dark: 0x26262A)
    static let ink = Color(light: 0x0E0E0F, dark: 0xF5F5F7)
    static let ink2 = Color(light: 0x6E6E73, dark: 0xA6A6AD)
    static let ink3 = Color(light: 0x8E8E93, dark: 0x7A7A80)
    static let line = Color(light: 0x000000, lightAlpha: 0.10, dark: 0xFFFFFF, darkAlpha: 0.10)
    /// 卡片里面的分隔线：暗色下白 10% 压在 card 上只有 1.53:1，几乎看不见，抬到 12%。
    static let divider = Color(light: 0x000000, lightAlpha: 0.10, dark: 0xFFFFFF, darkAlpha: 0.12)
    static let accent = Color(light: 0x1C1C1E, dark: 0xF2F2F4)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x0C0C0D)
    static let income = Color(light: 0x107050, dark: 0x4ED4A0)
    /// 红是含义不是明暗倾向：dangerFill 两个主题都是同一个红，只给「实底红」用
    /// （滑动删除、危险确认）。danger 是它的浅色版本，只给文字和图标。
    static let dangerFill = Color(light: 0xC0392B, dark: 0xC0392B)
    static let danger = Color(light: 0xC0392B, dark: 0xFF8578)
    static let ai = Color(light: 0x5B3FD9, dark: 0xB9A6FF)

    /// 中性底上的浅色块（状态胶囊、缺口标记）
    static var softFill: Color { Color(light: 0x000000, lightAlpha: 0.06, dark: 0xFFFFFF, darkAlpha: 0.10) }
    /// 一句话记账入口的浅紫底
    static var aiSoft: Color { ai.opacity(0.12) }
    /// 超支胶囊底
    static var dangerSoft: Color { danger.opacity(0.14) }
}

// MARK: - 布局常量

enum PaceSpace {
    static let screen: CGFloat = 20
    static let cardPadding: CGFloat = 20
    static let heroPadding: CGFloat = 22
    static let cardGap: CGFloat = 16
    static let inner: CGFloat = 12
}

enum PaceRadius {
    static let hero: CGFloat = 30
    static let card: CGFloat = 26
    static let list: CGFloat = 22
    static let block: CGFloat = 14
}

// MARK: - 卡片与块

struct PaceCardModifier: ViewModifier {
    var radius: CGFloat = PaceRadius.card
    var padding: CGFloat = PaceSpace.cardPadding

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .paceCardFill(radius)
    }
}

extension View {
    /// 实底卡片的底 + 0.5pt 描边。深色下卡片 #1A1A1C 压在底色 #0C0C0D 上只有 1.12:1，
    /// 光靠明度分不出边界，靠 PaceColor.line（浅色黑 10% / 深色白 10%）把边缘画出来；阴影在深色底上没用。
    func paceCardFill(_ radius: CGFloat, color: Color = PaceColor.card) -> some View {
        self
            .background(color, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(PaceColor.line, lineWidth: 0.5)
            )
    }

    /// 实底内容卡（不做玻璃叠玻璃）
    func paceCard(radius: CGFloat = PaceRadius.card, padding: CGFloat = PaceSpace.cardPadding) -> some View {
        modifier(PaceCardModifier(radius: radius, padding: padding))
    }

    /// 屏幕底色 + 左右边距
    func paceScreen() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(PaceColor.canvas)
    }
}

// MARK: - 状态胶囊

struct StatusPill: View {
    enum Kind {
        case withinBudget
        case overspent
        case noBudget
        case neutral
    }

    let text: String
    var kind: Kind = .neutral

    private var icon: String? {
        switch kind {
        case .withinBudget: return "checkmark.seal.fill"
        case .overspent: return "exclamationmark.triangle.fill"
        case .noBudget: return "gearshape"
        case .neutral: return nil
        }
    }

    private var foreground: Color {
        switch kind {
        case .overspent: return PaceColor.danger
        default: return PaceColor.ink
        }
    }

    private var background: Color {
        switch kind {
        case .overspent: return PaceColor.dangerSoft
        default: return PaceColor.softFill
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            }
            Text(text).font(.caption.weight(.semibold))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(background, in: Capsule(style: .continuous))
    }
}

// MARK: - 进度条

struct PaceBar: View {
    let ratio: Double
    var danger = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(PaceColor.line)
                Capsule()
                    .fill(danger ? PaceColor.danger : PaceColor.accent)
                    .frame(width: max(0, min(proxy.size.width, proxy.size.width * ratio)))
            }
        }
        .frame(height: 8)
    }
}

// MARK: - 按钮

/// 内容区主按钮：实底 accent + onAccent，圆角 14，高 48/50。
struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 50

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(PaceColor.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(PaceColor.accent, in: RoundedRectangle(cornerRadius: PaceRadius.block, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// 次要按钮：纯文字
/// 实底主按钮：能用时 accent 底 + onAccent 字，不能用时 card2 底 + ink2 字
/// （ink3 在亮色 card2 上只有 2.92:1，低于 3；ink2 是 4.54 / 6.23）。
/// 记一笔和草稿确认页共用这一套——一屏里两种保存长相，用户会以为是两件事。
struct ToolbarSaveStyle: ButtonStyle {
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(enabled ? PaceColor.onAccent : PaceColor.ink2)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(
                Capsule(style: .continuous)
                    .fill(enabled ? PaceColor.accent : PaceColor.card2)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct PlainButtonStylePace: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(PaceColor.ink2)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// 分类/操作胶囊
struct PillChipStyle: ButtonStyle {
    var selected = false
    var tint: Color = PaceColor.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(selected ? PaceColor.onAccent : PaceColor.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(selected ? AnyShapeStyle(PaceColor.accent) : AnyShapeStyle(PaceColor.card2), in: Capsule(style: .continuous))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: - 骨架

struct SkeletonCard: View {
    var height: CGFloat = 180

    var body: some View {
        RoundedRectangle(cornerRadius: PaceRadius.card, style: .continuous)
            .fill(PaceColor.card)
            .frame(height: height)
            .redacted(reason: .placeholder)
    }
}

// MARK: - 数字格式

extension LedgerStore {
    /// 金额展示用，去掉货币符号前缀（卡片上金额自己画 ¥）
    func amount(_ minor: Int64, currency: String = "CNY") -> String {
        format(minor, currency: currency)
    }
}
