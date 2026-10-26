import SwiftUI

/// 胶囊排：放得下就一行，放不下就自己换行、往下长高。
///
/// 原来这三排（类型、分类、例句）是横着滚的。大字号下滚层把字切在屏幕边上——
/// 「退款」只剩一个「退」、「住宿」只剩一个「住」，那不是滚动，那是把词切了一半，
/// 人读到的是一个坏掉的词。颗数少而固定、或者长高只往下长的排，就该换行。
///
/// 放得进一行时，交给它摆的结果和 `HStack(spacing: 8)` 一个像素都不差：
/// 默认字号下版面不动，这是接系统字号的底线。
struct PaceWrap: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let rows = layoutRows(maxWidth: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height }
            + lineSpacing * CGFloat(max(rows.count - 1, 0))
        // 报「父视图给的那条宽度」，不报自己内容的宽度。
        // 先前报的是内容宽：排一次只剩两颗的一行（232.67），父视图就把 232.67 当我的宽度
        // 再摆一遍，我用 232.67 重新分行，于是永远换行——自己把自己挤换行的。
        let widest = rows.map(\.width).max() ?? 0
        #if DEBUG
        if ProcessInfo.processInfo.environment["PACEWRAP_DEBUG"] != nil {
            print("PaceWrap sizeThatFits proposal=\(String(describing: proposal.width)) rows=\(rows.count) widest=\(widest) rowWidths=\(rows.map(\.width))")
        }
        #endif
        let width = proposal.width ?? widest
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PACEWRAP_DEBUG"] != nil {
            print("PaceWrap place bounds=\(bounds.width) subviewWidths=\(subviews.indices.map { subviews[$0].sizeThatFits(.unspecified).width })")
        }
        #endif
        var y = bounds.minY
        for row in layoutRows(maxWidth: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layoutRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width = needed
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
