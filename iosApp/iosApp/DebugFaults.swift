#if DEBUG
import Foundation

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
    case exportWrite
    case partialSave

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "不制造"
        case .localRule: return "本机规则拆不开"
        case .keyRejected: return "Key 被拒"
        case .offline: return "连不上"
        case .exportWrite: return "导出写不进去"
        case .partialSave: return "保存只成一半"
        }
    }
}

enum DebugFaults {
    /// 已上膛的那一个，只在内存里，进程一退就没了。
    static var armed: DebugFault = .none

    /// 取走一次：命中就清空，所以下一次操作又是正常的。
    static func take(_ fault: DebugFault) -> Bool {
        guard armed == fault else { return false }
        armed = .none
        return true
    }
}
#endif
