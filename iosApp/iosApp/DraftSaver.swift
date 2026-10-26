import Foundation
import shared

/// 把草稿写进账本的那一步——确认页和一句话记账的就地确认共用同一份，
/// 防重（DUPLICATE_FINGERPRINT）不能因为少跳一页就少一道（docs/DESIGN-quickadd-primary.md §7）。
enum DraftSaver {
    struct Outcome {
        var saved = 0
        /// 账本里已经有了的这几笔，问用户要不要照样记。
        var duplicated: [DraftItem] = []
        /// 真没写进去的（不是重复）：必须说出来，否则存一半会报「已保存 2 笔」。
        var failed: [DraftItem] = []
    }

    /// - Parameter force: 用户已经说过「照样记」，跳过重复拦截。
    static func save(_ drafts: [DraftItem], force: Bool = false) -> Outcome {
        let api = LedgerStore.shared.api
        var outcome = Outcome()
        for (index, draft) in drafts.enumerated() {
            #if DEBUG
            // 保存只成一半：第二笔故意写不进去，看确认页会不会把话说出来。
            if index == 1, DebugFaults.shared.take(.partialSave) {
                outcome.failed.append(draft)
                continue
            }
            #endif
            let result = api.saveTransaction(input: makeSaveInput(
                type: draft.type,
                amountText: draft.amountText,
                category: draft.category,
                note: draft.note,
                localDate: draft.localDate,
                account: draft.account.isEmpty ? "现金" : draft.account,
                countInBudget: draft.countInBudget,
                forceSave: force
            ))
            if result.isSuccess {
                outcome.saved += 1
            } else if result.errorCode == "DUPLICATE_FINGERPRINT" {
                outcome.duplicated.append(draft)
            } else {
                outcome.failed.append(draft)
            }
        }
        return outcome
    }
}
