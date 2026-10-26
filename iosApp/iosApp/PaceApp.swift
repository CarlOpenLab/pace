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
    /// 唯一入口：主按钮永远打开同一页「记一笔」，页里再分一句话 / 手动。
    @Published var showAdd = false
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
        .sheet(isPresented: $state.showDrafts) {
            DraftReviewView(drafts: state.pendingDrafts) {
                state.pendingDrafts = []
            }
        }
        #if DEBUG
        // 上膛了就挂一条，免得拿正常路径当失败路径验。
        .safeAreaInset(edge: .top, spacing: 0) { DebugFaultBanner() }
        // 启动参数 `-uiFaultCard <名字>`：直接把「记一笔」连同一张失败卡摆出来。
        // 验收拍的是「标题 + 正文第一句 + 两颗按钮在同一张图里」，不该靠点一串坐标才拍得到。
        .task {
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-uiTab"), i + 1 < args.count {
                switch args[i + 1] {
                case "settings": state.tab = .settings
                case "bills": state.tab = .bills
                case "stats": state.tab = .stats
                default: state.tab = .home
                }
            }
            if args.contains("-uiFaultCard") || args.contains("-uiAmount") {
                state.showAdd = true
            }
            // 启动参数 `-uiDrafts`：草稿确认那页只能靠一次模型解析才到得了，
            // 验收不该依赖网络。三张：填好的、缺金额的、缺类型的。
            if args.contains("-uiDrafts") {
                state.openDrafts(Self.debugDrafts)
            }
            // 启动参数 `-uiNetProbe <地址>`：从 App 内部真发一次 GET，把结果打到控制台。
            // 「连不上」到底是服务器的错还是系统的 ATS 拦的，只有从 App 里发一次才分得清。
            if let i = args.firstIndex(of: "-uiNetProbe"), i + 1 < args.count {
                let probe = args[i + 1]
                Task {
                    guard let url = URL(string: probe) else {
                        print("NETPROBE bad-url \(probe)")
                        return
                    }
                    do {
                        let (data, response) = try await URLSession.shared.data(from: url)
                        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                        print("NETPROBE ok status=\(code) bytes=\(data.count)")
                    } catch {
                        print("NETPROBE fail \(error)")
                    }
                }
            }
        }
        #endif
    }

    #if DEBUG
    /// 草稿确认那页只能靠一次模型解析才到得了，验收不该依赖网络。
    private static var debugDrafts: [DraftItem] {
        let today = LedgerStore.shared.todayIso
        func draft(_ id: String, _ type: String, _ amountText: String, _ minor: Int64,
                   _ category: String, _ note: String,
                   _ missing: [String] = []) -> DraftItem {
            DraftItem(id: id, type: type, amountText: amountText, amountMinor: minor,
                      currency: "CNY", dateText: "", localDate: today,
                      category: category, note: note, account: "现金",
                      countInBudget: true, missingFields: missing)
        }
        return [
            draft("d1", TxnTypes.expense, "28.00", 2800, "餐饮", "午饭"),
            draft("d2", TxnTypes.expense, "", 0, "交通", "打车", [DraftMissing.amount]),
            draft("d3", "", "18.00", 1800, "餐饮", "咖啡", [DraftMissing.type]),
        ]
    }
    #endif
}
