#if DEBUG
import Foundation
import SwiftUI

/// 只在调试构建里存在的故障注入：失败卡是用户最需要看懂的一屏，可它偏偏
/// 在正常情况下造不出来——本机规则几乎不会失败，磁盘也不会坏。这个开关让
/// 那几张卡真的渲染出来，量一遍字会不会截、按钮会不会看不见。
///
/// 三条规矩，都是 Ato 定的：
/// 一，整个文件包在 `#if DEBUG` 里，正式包连编都不编进去；
/// 二，不写盘，用一次就清空——装回正式版本不会带着一个「一直是坏的」；
/// 三，正式路径上没有任何入口，只有设置最底下这一节，而这一节只在调试构建里有。
enum DebugFault: String, CaseIterable, Identifiable {
    case none
    case localRule
    case keyRejected
    case offline
    case model
    case exportWrite
    case partialSave

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "不制造"
        case .localRule: return "本机规则拆不开"
        case .keyRejected: return "Key 被拒"
        case .offline: return "连不上"
        case .model: return "服务没整理出来"
        case .exportWrite: return "导出写不进去"
        case .partialSave: return "保存只成一半"
        }
    }
}

@Observable
final class DebugFaults {
    static let shared = DebugFaults()

    /// 已上膛的那一个，只在内存里，进程一退就没了。
    var armed: DebugFault = .none

    /// 刚打过的那一发。取走之后 armed 清空、这条留着，
    /// 所以失败卡还在屏幕上时，顶上那条字也还在——不然最该说明的那一屏反倒没标记。
    var fired: DebugFault?

    /// 取走一次：命中就清空，所以下一次操作又是正常的。
    func take(_ fault: DebugFault) -> Bool {
        guard armed == fault else { return false }
        armed = .none
        fired = fault
        return true
    }

    func arm(_ fault: DebugFault) {
        armed = fault
        fired = nil
    }
}

/// 上膛之后屏幕上必须有痕迹。
///
/// 一个开了却不生效的调试件比没有更坏：我们会以为验过了，其实什么都没看到。
/// 长相照 Colo 的规矩来：一行 13 的小字，用 danger——它是个警告状态，不是装饰，
/// 别自己发明一种新长相。
struct DebugFaultBanner: View {
    @State private var faults = DebugFaults.shared

    var body: some View {
        Group {
            if faults.armed != .none || faults.fired != nil {
                // 字是 Camo 定的，别改。后半句必须在：假失败最容易被读成真事故。
                Text("调试中：失败是故意造的，账本没坏。")
                    .font(PaceType.secondary.weight(.medium))
                    .foregroundStyle(PaceColor.danger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(PaceColor.canvas)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(PaceColor.divider)
                            .frame(height: 0.5)
                    }
                    .accessibilityIdentifier("debug-fault-banner")
            }
        }
        .animation(.easeOut(duration: 0.15), value: faults.armed)
    }
}
#endif
