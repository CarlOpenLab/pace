import SwiftUI
import UniformTypeIdentifiers
import shared

/// 设置页：预算、导出/恢复、隐私说明、数据删除（PLAN §7 页面 5/7/8）
struct SettingsView: View {
    @State private var budgetText = ""
    @State private var effectiveFrom = LedgerStore.shared.todayIso
    @State private var budgetError: String?
    @State private var refreshToken = 0

    @State private var importPreview: ImportPreview?
    @State private var importJsonText: String?
    @State private var confirmReplace = false
    @State private var confirmClear = false
    @State private var importMessage: String?
    @State private var exportShareItem: ShareItem?
    /// 写文件失败时留着的那次导出，供「再试一次」重跑。
    @State private var failedExport: (() -> Void)?
    @State private var exportFailed = false
    @State private var showImporter = false
    @State private var showSavedBadge = false

    @EnvironmentObject private var ai: AiSettings

    private var currentBudget: BudgetRule? {
        LedgerStore.shared.api.budgetFor(localDate: LedgerStore.shared.todayIso)
    }

    var body: some View {
        NavigationStack {
            Form {
                budgetSection
                quickAddSection
                transferSection
                dataSection
                debugSection

                Section {
                    EmptyView()
                } footer: {
                    Text(Copy.Settings.version(versionText))
                        .font(.system(size: 11))
                        .foregroundStyle(PaceColor.ink2)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PaceColor.canvas)
            .navigationTitle("设置")
            .id(refreshToken)
            .onAppear {
                if budgetText.isEmpty, let rule = currentBudget {
                    budgetText = Money.shared.formatMinor(amountMinor: rule.dailyAmountMinor)
                }
            }
            .sheet(item: $exportShareItem) { item in
                ShareSheet(items: [item.url])
            }
            .alert(Copy.Failed.Export.title, isPresented: $exportFailed) {
                Button(Copy.Failed.retry) {
                    let again = failedExport
                    failedExport = nil
                    again?()
                }
                Button(Copy.Confirm.Duplicate.secondary, role: .cancel) { failedExport = nil }
            } message: {
                Text(Copy.Failed.Export.body)
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .data]) { result in
                switch result {
                case .success(let url):
                    guard url.startAccessingSecurityScopedResource(),
                          let data = try? Data(contentsOf: url),
                          let text = String(data: data, encoding: .utf8) else {
                        url.stopAccessingSecurityScopedResource()
                        importMessage = Copy.Settings.Import.Issue.unknown
                        return
                    }
                    url.stopAccessingSecurityScopedResource()
                    importJsonText = text
                    importPreview = LedgerStore.shared.api.previewImport(jsonText: text)
                case .failure:
                    importMessage = Copy.Settings.Import.Issue.unknown
                }
            }
            .sheet(isPresented: Binding(
                get: { importPreview != nil && importJsonText != nil },
                set: { if !$0 { importPreview = nil; importJsonText = nil } }
            )) {
                importPreviewSheet
            }
            .alert(Copy.Confirm.ReplaceLedger.title, isPresented: $confirmReplace) {
                Button(Copy.Confirm.ReplaceLedger.primary, role: .destructive) { applyImport(mode: "REPLACE") }
                Button(Copy.Settings.cancel, role: .cancel) {}
            } message: {
                Text(Copy.Confirm.ReplaceLedger.body)
            }
            .alert(Copy.Settings.clearConfirmTitle, isPresented: $confirmClear) {
                Button(Copy.Settings.clearConfirm, role: .destructive) {
                    if LedgerStore.shared.api.clearAllData() {
                        importMessage = nil
                    }
                    refreshToken += 1
                }
                Button(Copy.Settings.cancel, role: .cancel) {}
            } message: {
                Text("\(Copy.Settings.clearConfirmBody)\n\(Copy.Settings.clearConfirmKeyNote)")
            }
        }
    }

    // MARK: - 每日预算

    private var budgetSection: some View {
        Section {
            if let rule = currentBudget {
                let parts = rule.effectiveFromLocalDate.split(separator: "-")
                let month = Int(parts.count > 1 ? String(parts[1]) : "") ?? 1
                let day = Int(parts.count > 2 ? String(parts[2]) : "") ?? 1
                Text(Copy.Settings.currentBudget(
                    amount: Money.shared.formatMinor(amountMinor: rule.dailyAmountMinor),
                    month: month,
                    day: day
                ))
                .font(.system(size: 11))
                .foregroundStyle(PaceColor.ink2)
            } else {
                Text(Copy.Settings.noBudget)
                    .font(.system(size: 11))
                    .foregroundStyle(PaceColor.ink2)
            }

            HStack {
                Text(Copy.Settings.dailyBudget)
                Spacer()
                TextField(Copy.Settings.budgetPlaceholder, text: $budgetText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }

            HStack {
                Text(Copy.Settings.effectiveDate)
                Spacer()
                // 界面上写「10月26日」；系统紧凑选择器只做背后的交互。
                Text(displayDate)
                    .font(.system(size: 15))
                    .foregroundStyle(PaceColor.ink)
                    .overlay {
                        // 背后的日期选择器只用来接住点击，不能自己露字。
                        // 以前给它 0.02 透明度：字一大，选择器自己那串「2026 年 10 月 26 日」
                        // 就超出这一行的框，带着那点透明度浮在界面上。现在两件事都做：
                        // 完全透明，并且锁在这行的框里不外溢。
                        DatePicker("", selection: dateBinding, displayedComponents: .date)
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "zh_CN"))
                            .opacity(0)
                            .accessibilityHidden(true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .contentShape(Rectangle())
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("\(Copy.Settings.effectiveDate)，\(displayDate)"))
            }

            // 真按钮，不是一行说明：可用时实底 accent，不可用时灰底点不动。
            // 「已保存」直接换按钮上的字，不挂在行右边——那看起来像一条状态说明。
            Button {
                saveBudget()
            } label: {
                Text(showSavedBadge ? Copy.Settings.savedBadge : Copy.Settings.saveBudget)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(canSaveBudget ? PaceColor.onAccent : PaceColor.ink2)
            }
            .buttonStyle(BudgetSaveButtonStyle(enabled: canSaveBudget))
            .disabled(!canSaveBudget)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)

            if let budgetError {
                Text(budgetError)
                    .font(.system(size: 12))
                    .foregroundStyle(PaceColor.danger)
            }
        } header: {
            Text(Copy.Settings.dailyBudget)
        } footer: {
            Text(Copy.Settings.budgetFooter)
        }
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { Self.isoFormatter.date(from: effectiveFrom) ?? Date() },
            set: { effectiveFrom = Self.isoFormatter.string(from: $0) }
        )
    }

    /// 「10月26日」——界面上的日期不用机器格式。
    private var displayDate: String {
        let parts = effectiveFrom.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else { return effectiveFrom }
        return "\(month)月\(day)日"
    }

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: LedgerStore.shared.timezoneId) ?? .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - 记账

    private var quickAddSection: some View {
        Section {
            NavigationLink {
                QuickAddSettingsView()
            } label: {
                HStack {
                    Text(Copy.Settings.quickAddStatusRow)
                    Spacer()
                    Text(ai.usesRemoteModel ? Copy.Settings.statusRemote : Copy.Settings.statusLocal)
                        .font(.system(size: 13))
                        .foregroundStyle(PaceColor.ink2)
                }
            }
        } header: {
            Text(Copy.Settings.quickAddRow)
        }
    }

    /// 能不能按：金额和手动记账同一条校验（大于 0、最多两位小数）。
    private var canSaveBudget: Bool {
        Money.shared.parseToMinor(text: budgetText) != nil
    }

    // MARK: - 导出与恢复

    private var transferSection: some View {
        Section {
            Button(Copy.Settings.exportCSV) { exportCsv() }
            Button(Copy.Settings.exportJSON) { exportJson() }
            Button(Copy.Settings.restoreFromFile) { showImporter = true }
            if let importMessage {
                Text(importMessage).font(.system(size: 12)).foregroundStyle(PaceColor.ink2)
            }
        } header: {
            Text("导出与恢复")
        } footer: {
            Text("导出文件通过系统分享面板交给你保存；保存到 iCloud、Drive、微信等外部服务后，由对应服务管理。账本数据只保存在本机，删除 App 且未导出时数据会丢失。")
        }
    }

    // MARK: - 数据

    private var dataSection: some View {
        Section("数据") {
            Button(Copy.Settings.clearLedger, role: .destructive) { confirmClear = true }
        }
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }

    // MARK: 预算

    private func saveBudget() {
        let error = LedgerStore.shared.api.setBudget(
            dailyAmountText: budgetText,
            currency: "CNY",
            effectiveFromIso: effectiveFrom
        )
        if let error {
            budgetError = describeError(error)
        } else {
            budgetError = nil
            refreshToken += 1
            withAnimation { showSavedBadge = true }
            Task {
                // spec §9：1.6 秒后回到「保存预算」；按钮宽度是整行，字换了也不跳。
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                withAnimation { showSavedBadge = false }
            }
        }
    }

    /// 只在调试构建里出现，正式包里这一节整块不存在。
    #if DEBUG
    private var debugFaultBinding: Binding<DebugFault> {
        Binding(get: { DebugFaults.shared.armed }, set: { DebugFaults.shared.arm($0) })
    }
    #endif

    @ViewBuilder
    private var debugSection: some View {
        #if DEBUG
        Section {
            Picker("制造一次失败", selection: debugFaultBinding) {
                ForEach(DebugFault.allCases) { fault in
                    Text(fault.label).tag(fault)
                }
            }
        } header: {
            Text("调试")
        } footer: {
            Text("只为把失败卡渲染出来看一眼。选完做一次对应的操作，用完自己回到「不制造」，不写盘，正式包里没有这一节。")
        }
        #endif
    }

    // MARK: 导出

    private struct ShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    private func exportCsv() { share(text: LedgerStore.shared.api.exportCsv(), ext: "csv", retry: exportCsv) }

    private func exportJson() {
        share(
            text: LedgerStore.shared.api.exportJson(timezoneId: LedgerStore.shared.timezoneId),
            ext: "json",
            retry: exportJson
        )
    }

    /// 文件没写成就不弹分享面板：面板一出来就是「导出好了」，跟「没写成」同屏，
    /// 用户只会信面板。
    private func share(text: String, ext: String, retry: @escaping () -> Void) {
        let stamp = DateFormatter(format: "yyyyMMdd-HHmmss").string(from: Date())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pace-ledger-\(stamp).\(ext)")
        #if DEBUG
        // 磁盘不坏就没有写失败，只能造一个，看那两句字会不会截。
        if DebugFaults.shared.take(.exportWrite) {
            failedExport = retry
            exportFailed = true
            return
        }
        #endif
        do {
            guard let data = text.data(using: .utf8) else { throw ExportError.encoding }
            try data.write(to: url)
        } catch {
            failedExport = retry
            exportFailed = true
            return
        }
        exportShareItem = ShareItem(url: url)
    }

    private enum ExportError: Error { case encoding }

    // MARK: 导入

    private func pickJson() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .data, .item])
        picker.delegate = DocumentPickerDelegate { url in
            guard let url, let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else {
                importMessage = Copy.Settings.Import.Issue.unknown
                return
            }
            importJsonText = text
            importPreview = LedgerStore.shared.api.previewImport(jsonText: text)
        }
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first?.present(picker, animated: true)
    }

    @ViewBuilder
    private var importPreviewSheet: some View {
        NavigationStack {
            Group {
                if let preview = importPreview {
                    if preview.valid {
                        List {
                            Text("账单 \(preview.transactionCount) 笔（\(preview.firstLocalDate ?? "无") ~ \(preview.lastLocalDate ?? "无")）")
                            Text("分类 \(preview.categoryCount) · 预算规则 \(preview.budgetRuleCount)")
                            Text(Copy.Settings.Import.previewDuplicates(count: Int(preview.duplicateCount)))
                            Section {
                                Button("合并到现有账本") { applyImport(mode: "MERGE") }
                                Button("替换当前账本…", role: .destructive) { confirmReplace = true }
                            } footer: {
                                Text(Copy.Settings.Import.mergeOrReplaceNote)
                            }
                        }
                    } else {
                        List {
                            Section("文件校验未通过，不会写入任何数据") {
                                ForEach(Array(preview.errors), id: \.self) { error in
                                    Text(error).font(.footnote)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("恢复预览")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.Settings.cancel) {
                        importPreview = nil
                        importJsonText = nil
                    }
                }
            }
        }
    }

    /// 导入失败：错误码只写日志，界面上说人话。
    private func importProblem(_ errors: [String]) -> String {
        for raw in errors {
            let code = raw.split(separator: ":").first.map(String.init) ?? raw
            switch code.trimmingCharacters(in: .whitespaces) {
            case "INVALID_AMOUNT": return Copy.Settings.Import.Issue.invalidAmount
            case "INVALID_DATE": return Copy.Settings.Import.Issue.invalidDate
            case "INVALID_TYPE", "INVALID_CATEGORY": return Copy.Settings.Import.Issue.invalidTypeOrCategory
            case "NOTE_TOO_LONG": return Copy.Settings.Import.Issue.noteTooLong
            default: continue
            }
        }
        return Copy.Settings.Import.Issue.unknown
    }

    private func applyImport(mode: String) {
        guard let json = importJsonText else { return }
        let result = LedgerStore.shared.api.applyImport(jsonText: json, mode: mode)
        if result.applied {
            importMessage = mode == "REPLACE"
                ? "已替换：写入 \(result.insertedCount) 笔"
                : Copy.Settings.Import.merged(added: Int(result.insertedCount), skipped: Int(result.skippedCount))
        } else {
            importMessage = Copy.Settings.Import.Issue.failed(reason: importProblem(result.errors))
        }
        importPreview = nil
        importJsonText = nil
        confirmReplace = false
        refreshToken += 1
    }
}

extension DateFormatter {
    convenience init(format: String) {
        self.init()
        dateFormat = format
    }
}

/// 设置里的「保存预算」：占满整行的胶囊，高 50，按下和主按钮同一套反馈。
private struct BudgetSaveButtonStyle: ButtonStyle {
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                enabled ? PaceColor.accent : PaceColor.card2,
                in: RoundedRectangle(cornerRadius: PaceRadius.block, style: .continuous)
            )
            .opacity(configuration.isPressed && enabled ? 0.85 : 1)
            .scaleEffect(configuration.isPressed && enabled ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// UIKit 分享面板（导出文件交给用户自行保存）
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private final class DocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    private let handler: (URL?) -> Void

    init(handler: @escaping (URL?) -> Void) {
        self.handler = handler
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        handler(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        handler(nil)
    }
}
