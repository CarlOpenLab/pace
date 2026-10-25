import SwiftUI
import shared

// MARK: - 共享输入构造（Kotlin 默认参数不会桥接，这里集中处理）

func makeSaveInput(
    id: String? = nil,
    type: String,
    amountText: String,
    category: String,
    note: String,
    localDate: String,
    account: String,
    countInBudget: Bool,
    refundOfId: String? = nil,
    occurredAtEpochMillis: Int64 = 0,
    forceSave: Bool = false
) -> SaveTxnInput {
    SaveTxnInput(
        id: id,
        type: type,
        amountText: amountText,
        currency: "CNY",
        category: category,
        account: account,
        note: note,
        occurredAtEpochMillis: occurredAtEpochMillis,
        localDate: localDate,
        timezoneId: LedgerStore.shared.timezoneId,
        countInBudget: countInBudget,
        refundOfId: refundOfId,
        source: "MANUAL",
        forceSave: forceSave
    )
}

func describeError(_ code: String?) -> String {
    switch code {
    case "INVALID_AMOUNT": return "金额无效：需为大于 0 的数，最多两位小数"
    case "INVALID_TYPE": return "账单类型无效"
    case "INVALID_CATEGORY": return "请选择有效分类"
    case "INVALID_DATE": return "日期无效（yyyy-MM-dd，1970-2100）"
    case "INVALID_TIMEZONE": return "时区信息无效"
    case "REFUND_MISSING_ORIGINAL": return "退款必须关联一笔原支出"
    case "REFUND_ORIGINAL_NOT_FOUND": return "关联的原账单不存在或不是支出"
    case "NOTE_TOO_LONG": return "备注最长 500 字"
    case "DUPLICATE_FINGERPRINT": return "存在相同账单"
    case "NOT_FOUND": return "账单不存在，可能已被删除"
    default: return "保存失败（\(code ?? "unknown")）"
    }
}

func amountLabel(_ txn: Transaction) -> String {
    let store = LedgerStore.shared
    switch txn.type {
    case TxnTypes.expense: return "-" + store.format(txn.amountMinor, currency: txn.currency)
    case TxnTypes.income: return "+" + store.format(txn.amountMinor, currency: txn.currency)
    case TxnTypes.refund: return "退 " + store.format(txn.amountMinor, currency: txn.currency)
    default: return store.format(txn.amountMinor, currency: txn.currency)
    }
}

// MARK: - 账单行

struct TxnRowView: View {
    let txn: Transaction

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(txn.note.isEmpty ? txn.category : txn.note)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(amountLabel(txn))
                .font(.body)
                .foregroundStyle(txn.type == TxnTypes.refund ? Color.accentColor : .primary)
        }
        .padding(.vertical, 6)
    }

    private var subtitle: String {
        let time = PaceDates.shared.timeOfDay(
            epochMillis: txn.occurredAtEpochMillis,
            timezoneId: txn.timezoneId
        )
        var text = "\(txn.category) · \(time)"
        if txn.type == TxnTypes.expense && !txn.countInBudget {
            text += " · 不计入预算"
        }
        return text
    }
}
