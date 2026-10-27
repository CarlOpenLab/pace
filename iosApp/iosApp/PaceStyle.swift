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
    /// 卡片的边。暗色下卡片 #1A1A1C 对画布 #0C0C0D 只有 1.13:1，用 white 10% 只有 1.67；
    /// 这条是容器的边，抬到 16% = #3F3F40、对画布 1.86——看得见但不抢，比玻璃那圈 1.35 重一点。
    static let cardEdge = Color(light: 0x000000, lightAlpha: 0.10, dark: 0xFFFFFF, darkAlpha: 0.16)
    /// 卡片里面的分隔线。文档写的是白 12%，但白 12% 压在 card #1A1A1C 上量出来是 #353537，
    /// 不是文档同时给出的目标色 #3D3D40（那条要 15%）。按目标色取，别按百分比猜。
    static let divider = Color(light: 0x000000, lightAlpha: 0.10, dark: 0x3D3D40, darkAlpha: 1.0)
    static let accent = Color(light: 0x1C1C1E, dark: 0xF2F2F4)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x0C0C0D)
    static let income = Color(light: 0x107050, dark: 0x4ED4A0)
    /// 红是含义不是明暗倾向：dangerFill 两个主题都是同一个红，只给「实底红」用
    /// （滑动删除、危险确认）。danger 是它的浅色版本，只给文字和图标。
    static let dangerFill = Color(light: 0xC0392B, dark: 0xC0392B)
    static let danger = Color(light: 0xC0392B, dark: 0xFF8578)
    static let ai = Color(light: 0x5B3FD9, dark: 0xB9A6FF)

    // 分段切换器（docs/DESIGN-switcher.md）：槽里压的墨、槽的描边、抬起来的选中块。
    /// 亮色 7.5% 不是文档的 6%：玻璃本身会把底提亮约 3 个色阶，6% 压出来是 #EBEAEA，
    /// 目标是 #E8E8E8。按目标色反推，别按百分比猜（同 divider 那条）。
    /// 暗色不是压白 6%：玻璃在深底上会把槽提亮到 #39393A，目标是 #1B1B1C，只能往回收。
    /// 实测 #39393A 压黑 53% 落到 ≈#1B1B1C。还是那句话：按目标色反推，别按百分比猜。
    static let segSlotTint = Color(light: 0x000000, lightAlpha: 0.075, dark: 0x000000, darkAlpha: 0.40)
    static let segSlotEdge = Color(light: 0x000000, lightAlpha: 0.12, dark: 0xFFFFFF, darkAlpha: 0.12)
    /// 选中块：亮色是卡白；暗色比卡片 #1A1A1C 抬到 #2C2C2E，不然在槽里浮不起来。
    /// 降低透明度时的实色槽：跟玻璃槽的目标色同一个值，换过去看不出跳。
    static let segSlotSolid = Color(light: 0xE8E8E8, dark: 0x1B1B1C)
    /// 暗色选中块取 #4D4D4E（Colo 定：白 22% 叠在槽上，对槽 2.04:1）。
    /// 原来 #2C2C2E 只有 1.27:1——暗色下投影是黑的、压在黑底上等于没有，选中的唯一线索
    /// 就剩那点亮度差，1.27 太薄。不取系统那颗的 #636366（2.87）：暗色卡面才 #1A1A1C，
    /// 那么亮会像「另一个按钮」把白字抢走。按目标色取，不按百分比算。
    static let segThumb = Color(light: 0xFFFFFF, dark: 0x4D4D4E)
    /// 选中块的投影。暗色要重得多（45%）：浅投影在深底上等于没有。
    static let segThumbShadow = Color(light: 0x000000, lightAlpha: 0.14, dark: 0x000000, darkAlpha: 0.50)
    /// 暗色选中块的边（white 12%，对块面 1.3:1）：投影在暗色失效，靠这根边说明「那块是个东西」。
    static let segThumbEdge = Color(light: 0x000000, lightAlpha: 0, dark: 0xFFFFFF, darkAlpha: 0.12)

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
                    .strokeBorder(PaceColor.cardEdge, lineWidth: 0.5)
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
                Image(systemName: icon).paceFont(11, .semibold, relativeTo: .caption2)
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
            .font(PaceType.button)
            .foregroundStyle(PaceColor.onAccent)
            .frame(maxWidth: .infinity)
            // 最小高度不是固定高度：字一放大按钮得跟着长，不然字被切在框里。
            .frame(minHeight: height)
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
            .font(PaceType.button)
            .foregroundStyle(enabled ? PaceColor.onAccent : PaceColor.ink2)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
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
            .font(PaceType.rowTitle)
            .foregroundStyle(PaceColor.ink2)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// 分类/操作胶囊
struct PillChipStyle: ButtonStyle {
    var selected = false
    var tint: Color = PaceColor.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .paceFont(PaceType.labelBase, .medium)
            .foregroundStyle(selected ? PaceColor.onAccent : PaceColor.ink)
            .padding(.horizontal, 14)
            .pacePadding(7, .vertical)
            .background(selected ? AnyShapeStyle(PaceColor.accent) : AnyShapeStyle(PaceColor.card2), in: Capsule(style: .continuous))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// 勾选块：系统开关的圆点是白的，我们给暗色轨道的是近白 accent，圆点对轨道只有
/// 1.12:1——圆的等于没了，开关打开就是把一个白胶囊点亮，开和关看起来一模一样。
/// 做成 ToggleStyle 而不是「长得像勾选的按钮」：无障碍身份还是开关，读屏会说
/// 「开关，已关闭」，双击能切；换成按钮，读屏说「按钮」，按了没反应又回到死胡同。
struct CheckBlockToggleStyle: ToggleStyle {
    /// 块是记号不是字，不跟系统字号长（Ato 定），所以这一个是固定值——
    /// CI 那条「不许写死字号」盯的是文字，记号走变量名。
    private let blockSize: CGFloat = 22
    private let blockCorner: CGFloat = 7
    private let checkGlyphSize: CGFloat = 13
    /// 块顶相对行框顶的下沉量。行框比字腔高，字号越大差得越多，
    /// 所以这个值跟着字号长：默认 3 点，最大字号约 9 点，块顶才落在字形顶上（误差 ≤3）。
    @ScaledMetric(relativeTo: .body) private var blockTopInset: CGFloat = 3

    func makeBody(configuration: Configuration) -> some View {
        // 块和第一行字对齐，不是整行居中：标题两行时居中的块会挂在两行之间，
        // 看着像掉进缝里。块顶比字顶低 3 点，正好落在字腔里。
        HStack(alignment: .top, spacing: PaceSpace.inner) {
            configuration.label
            Spacer(minLength: 8)
            block(on: configuration.isOn)
                .padding(.top, blockTopInset)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
        // 自定义样式会把这颗控件的身份换成复选框（读屏说「复选框」），所以在调用处
        // 用 accessibilityRepresentation 交回一个真 Toggle：外观是我们的勾选块，
        // 读屏听到的还是「开关，已打开／已关闭」，双击也能切。
        .animation(.easeOut(duration: 0.16), value: configuration.isOn)
    }

    private func block(on: Bool) -> some View {
        RoundedRectangle(cornerRadius: blockCorner, style: .continuous)
            .fill(on ? PaceColor.accent : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: blockCorner, style: .continuous)
                    .strokeBorder(on ? Color.clear : PaceColor.ink3, lineWidth: 1.5)
            }
            .overlay {
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: checkGlyphSize, weight: .semibold))
                        .foregroundStyle(PaceColor.onAccent)
                }
            }
            .frame(width: blockSize, height: blockSize)
            .accessibilityHidden(true)
    }
}

/// 次级按钮：系统玻璃胶囊，字自己给。
///
/// 玻璃一旦交回系统，字色也跟着交出去了，禁用时系统会把它压到几乎和玻璃同色
/// （暗色下量到 1.38:1）。可读性不交给系统猜，所以 label 里的 Text 显式给色。
struct GlassSecondaryStyle: ButtonStyle {
    var tint: Color = PaceColor.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PaceType.button)
            .foregroundStyle(tint)
            .padding(.horizontal, 16)
            .pacePadding(9, .vertical)
            .frame(minHeight: 44)
            .glassEffect(.regular.interactive(), in: .capsule)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Capsule())
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

// MARK: - 放得下的金额

/// 一个必须整串读准的数字：跟着系统字号长、封顶 1.5 倍，并且不超过这一行放得下的宽度；
/// 但也不低于它本来那个字号（Colo/Ato：往下降是为了整串可见，降太狠等于把用户选的字号压回去）。
///
/// 和首页那个 hero 量的是同三样：基准宽度、可用宽度、封顶值。
struct FittedAmountText: View {
    let text: String
    var base: CGFloat
    var weight: Font.Weight = .heavy
    var design: Font.Design = .rounded
    var cap: CGFloat = 1.5

    @ScaledMetric private var scaled: CGFloat = 38
    @State private var available: CGFloat = 0
    @State private var baseWidth: CGFloat = 0

    init(text: String, base: CGFloat, weight: Font.Weight = .heavy,
         design: Font.Design = .rounded, cap: CGFloat = 1.5) {
        self.text = text
        self.base = base
        self.weight = weight
        self.design = design
        self.cap = cap
        _scaled = ScaledMetric(wrappedValue: base, relativeTo: .body)
    }

    private var pointSize: CGFloat {
        let wanted = min(scaled, base * cap)
        guard available > 0, baseWidth > 0 else { return wanted }
        return min(wanted, max(base, base * (available / baseWidth)))
    }

    var body: some View {
        Text(text)
            .font(.system(size: pointSize, weight: weight, design: design))
            .monospacedDigit()
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .leading) {
                Text(text)
                    .font(.system(size: base, weight: weight, design: design))
                    .monospacedDigit()
                    .hidden()
                    .fixedSize()
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(key: FittedBaseWidthKey.self, value: g.size.width)
                        }
                    )
            }
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: FittedAvailableWidthKey.self, value: g.size.width)
                }
            )
            .onPreferenceChange(FittedBaseWidthKey.self) { baseWidth = $0 }
            .onPreferenceChange(FittedAvailableWidthKey.self) { available = $0 }
    }
}

private struct FittedBaseWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct FittedAvailableWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
