import Foundation
import shared

/// 把草稿写进账本的那一步——确认页和一句话记账的就地确认共用同一份，
/// 防重（DUPLICATE_FINGERPRINT）不能因为少跳一页就少一道（docs/DESIGN-quickadd-primary.md §7）。
enum DraftSaver {
    struct Outcome {
        var saved = 0
        var duplicated: [DraftItem] = []
    }

    /// - Parameter force: 用户已经说过「照样记」，跳过重复拦截。
    static func save(_ drafts: [DraftItem], force: Bool = false) -> Outcome {
        let api = LedgerStore.shared.api
        var outcome = Outcome()
        for draft in drafts {
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
            }
        }
        return outcome
    }
}
