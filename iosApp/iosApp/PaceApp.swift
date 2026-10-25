import SwiftUI
import shared

/// 全局账本入口：账本只保存在本地 SQLite（应用沙盒）。
final class LedgerStore: ObservableObject {
    static let shared = LedgerStore()

    let api: LedgerApi

    /// Kotlin object 单例桥接
    private let dates = PaceDates.shared
    private let money = Money.shared

    var timezoneId: String { dates.currentTimeZoneId() }

    var todayIso: String { dates.todayIso(timezoneId: timezoneId) ?? "1970-01-01" }

    private init() {
        let driver = IosDriverFactory.shared.create()
        api = PaceLibrary.shared.createLedger(driver: driver)
    }

    func format(_ minor: Int64, currency: String = "CNY") -> String {
        money.display(amountMinor: minor, currency: currency)
    }
}

/// Kotlin 侧字符串常量（docs/DATA_MODEL.md）
enum TxnTypes {
    static let expense = "EXPENSE"
    static let income = "INCOME"
    static let refund = "REFUND"
    static let transfer = "TRANSFER"

    static var all: [(String, String)] {
        [(expense, "支出"), (income, "收入"), (transfer, "转账"), (refund, "退款")]
    }
}

@main
struct PaceApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(Color(red: 0.06, green: 0.42, blue: 0.36))
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }
            BillsView()
                .tabItem { Label("账单", systemImage: "list.bullet") }
            StatsView()
                .tabItem { Label("统计", systemImage: "chart.bar") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}
