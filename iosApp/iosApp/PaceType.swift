import SwiftUI

/// 字号角色表（Colo：DESIGN-type-scale.md）。
///
/// 这个 App 之前 129 处字号写死 `.system(size:)`，用户在系统里把字调大，App 一个字都不变——
/// 无障碍设置变成了装饰。从这儿出字：给角色，不给数字，缩放交给系统。
///
/// 角色后面挂的是系统文字样式，所以默认字号下的 point 数和以前一样
/// （脚注 13、副标题 15、正文 17、标题 28…），字一放大整体跟着长。
enum PaceType {
    /// 页面大标题。默认 28。
    static let screenTitle = Font.title
    /// 区块标题、卡片标题、15 号重字。默认 15。
    static let sectionTitle = Font.subheadline.weight(.semibold)
    /// 16 号重字：卡片标题的另一档。
    static let sectionTitleLarge = Font.callout.weight(.semibold)
    /// 正文、说明的主体。默认 15。
    static let body = Font.subheadline
    /// 行标题：可截，无障碍读全。默认 15。
    static let rowTitle = Font.subheadline.weight(.medium)
    /// 16 号行标题。
    static let rowTitleLarge = Font.callout.weight(.semibold)
    /// 提示、脚注式说明。默认 13。
    static let secondary = Font.footnote
    /// 日期、计数、单位。默认 12。
    static let caption = Font.caption
    /// 胶囊、切换器两段的基准字号。系统 subheadline 是 15，原来是 14——
    /// 数字对不上档位的角色不许硬对（那会让平时样子长 1 点），改用基准缩放。
    static let labelBase: CGFloat = 14
    /// 极小辅助字的基准字号。系统 caption2 是 11，表上这一档按 10。
    static let microBase: CGFloat = 10
    /// 按钮字：不可截，放不下就换布局。默认 16。
    static let button = Font.callout.weight(.semibold)
}

/// 以原字号为基准的缩放：默认字号下就是那个点值，大字号跟着系统长。
///
/// 角色表里数字和系统档位不等的几档（label 14、micro 10）不能用系统样式的字体：
/// subheadline 是 15、caption2 是 11，硬换过去平时的样子就长了 1 点。
/// 这一轮的名义是「接系统字号」，不是「顺手调排版」，所以默认尺寸一个像素都不许动。
struct PaceScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let base: CGFloat
    private let cap: CGFloat?
    private let weight: Font.Weight
    private let design: Font.Design

    init(_ base: CGFloat, weight: Font.Weight = .regular,
         design: Font.Design = .default, relativeTo style: Font.TextStyle = .body,
         cap: CGFloat? = nil) {
        self.base = base
        self.cap = cap
        self.weight = weight
        self.design = design
        _size = ScaledMetric(wrappedValue: base, relativeTo: style)
    }

    func body(content: Content) -> some View {
        let value = cap.map { min(size, base * $0) } ?? size
        return content.font(.system(size: value, weight: weight, design: design))
    }
}

/// 会跟着系统字号长、但有上限的内距／间距。
///
/// 字放大之后内距不动，字就贴在边框上；内距无限长又会把内容挤出屏幕。
/// 上限 1.6 倍：20 → 32、16 → 26、12 → 19，再大交给滚动。
/// 0.5 的分隔线和 1 点以下的描边不缩放——它们是线，不是字。
struct PaceScaledLength: ViewModifier {
    @ScaledMetric private var length: CGFloat
    private let base: CGFloat
    private let cap: CGFloat
    private let edges: Edge.Set
    private let isPadding: Bool

    init(_ base: CGFloat, edges: Edge.Set = .all, isPadding: Bool) {
        self.base = base
        self.cap = base * 1.6
        self.edges = edges
        self.isPadding = isPadding
        _length = ScaledMetric(wrappedValue: base, relativeTo: .body)
    }

    func body(content: Content) -> some View {
        let value = min(length, cap)
        return Group {
            if isPadding {
                content.padding(edges, value)
            } else {
                content.lineSpacing(value)
            }
        }
    }
}

extension View {
    /// 基准缩放的字：默认字号下等于 base，大字号跟着系统长。
    /// 带封顶的版本：金额这类「必须被读准」的字，放大到一定倍数就不再长（Colo：1.6 倍）。
    func paceFont(_ base: CGFloat, _ weight: Font.Weight = .regular,
                  design: Font.Design = .default,
                  relativeTo style: Font.TextStyle = .body,
                  cap: CGFloat? = nil) -> some View {
        modifier(PaceScaledFont(base, weight: weight, design: design,
                                relativeTo: style, cap: cap))
    }

    /// 跟着字号长、封顶 1.6 倍的内距。
    func pacePadding(_ base: CGFloat, _ edges: Edge.Set = .all) -> some View {
        modifier(PaceScaledLength(base, edges: edges, isPadding: true))
    }

    /// 跟着字号长、封顶 1.6 倍的行距。
    func paceLineSpacing(_ base: CGFloat) -> some View {
        modifier(PaceScaledLength(base, isPadding: false))
    }
}

/// 量宽用的偏好键：卡片内容宽、金额并排所需的宽。
struct AmountCardWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct AmountRulerWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct AmountNumberWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// 记一笔页：可视高度、失败卡在滚动坐标系里的框。
struct AddViewportHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct FailureCardFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}
