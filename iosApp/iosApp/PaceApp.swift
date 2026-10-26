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

// MARK: - 全局导航状态

enum AppTab: Hashable {
    case home, bills, stats, settings
}

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var tab: AppTab = .home
    @Published var showAdd = false
    @Published var showQuickAdd = false
    /// 从「一句话记账」失败退到手动记账时，把用户原来那句话带进备注。
    @Published var pendingNote: String?
    @Published var pendingDrafts: [DraftItem] = []
    @Published var showDrafts = false
    /// 右下那颗「记一笔」是否收起（滚动收起，滞回 24pt）。
    @Published var fabCollapsed = false

    private var fabAnchor: CGFloat = 0
    private var fabIdle: Task<Void, Never>?

    private init() {}

    /// 只在今天和账单两屏、且没有弹层时出现。
    var showsFab: Bool {
        (tab == .home || tab == .bills) && !showAdd && !showDrafts
    }

    func updateFabScroll(_ offset: CGFloat) {
        if fabCollapsed {
            if offset < fabAnchor - 24 {
                setFabCollapsed(false)
            }
        } else if offset > fabAnchor + 24 {
            fabAnchor = offset
            setFabCollapsed(true)
        }
        fabIdle?.cancel()
        fabIdle = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.setFabCollapsed(false) }
        }
    }

    private func setFabCollapsed(_ value: Bool) {
        guard fabCollapsed != value else { return }
        withAnimation(.easeOut(duration: 0.22)) { fabCollapsed = value }
    }

    func openDrafts(_ drafts: [DraftItem]) {
        pendingDrafts = drafts
        showDrafts = true
    }
}

@main
struct PaceApp: App {
    @StateObject private var state = AppState.shared
    @StateObject private var ai = AiSettings.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .environmentObject(ai)
                .tint(PaceColor.ink)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        TabView(selection: $state.tab) {
            Tab("今天", systemImage: "house.fill", value: AppTab.home) {
                HomeView()
            }
            Tab("账单", systemImage: "list.bullet", value: AppTab.bills) {
                BillsView()
            }
            Tab("统计", systemImage: "chart.bar.fill", value: AppTab.stats) {
                StatsView()
            }
            Tab("设置", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // 「记一笔」只包住按钮本身：一颗浮在底栏右上方的玻璃胶囊，不再用系统那条占满宽度的附件条。
        .overlay(alignment: .bottomTrailing) {
            if state.showsFab {
                FloatingAddButton()
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $state.showAdd) {
            AddView(txnId: nil)
        }
        .sheet(isPresented: $state.showQuickAdd) {
            QuickAddView { }
        }
        .sheet(isPresented: $state.showDrafts) {
            DraftReviewView(drafts: state.pendingDrafts) {
                state.pendingDrafts = []
            }
        }
    }
}
