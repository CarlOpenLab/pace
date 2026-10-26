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
    /// 校验没通过那张卡里的「换一份文件再试」：直接从卡上开文件选择。
    @State private var retryImporter = false
    /// 重选之后读不出来的原因；nil 表示用 preview 自己带的原因。
    @State private var overriddenReasons: [String]?
    @State private var showSavedBadge = false
    @State private var showDatePicker = false

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
                        .paceFont(11)
                        .foregroundStyle(PaceColor.ink2)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PaceColor.canvas)
            // 底栏和「记一笔」都是浮在上面的：内容滚到底也要停在它们上面。
            .contentMargins(.bottom, 16, for: .scrollContent)
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
            .sheet(isPresented: $showDatePicker) {
                NavigationStack {
                    DatePicker(Copy.Settings.effectiveDate, selection: dateBinding, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                        .padding()
                        .navigationTitle(Copy.Settings.effectiveDate)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("完成") { showDatePicker = false }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
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
                    guard let text = readImportedText(url) else {
                        importMessage = Copy.Settings.Import.Issue.unknown
                        return
                    }
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

    @Environment(\.dynamicTypeSize) private var typeSize

    /// 区块标题按角色表走 sectionTitle（15 点重字），最多两行。
    ///
    /// 原来吃系统列表头的样式，最大档会自己长成 83 点高的一行——那不是「放大」，是路标变成了标题。
    /// 这一处默认字号是有意改的（13 点系统灰 → 15 点重字），不是顺手改。
    private func headerText(_ text: String) -> some View {
        Text(text)
            .paceFont(15, .semibold)
            .foregroundStyle(PaceColor.ink2)
    }

    private var dateButton: some View {
        Button {
            showDatePicker = true
        } label: {
            Text(displayDate)
                .paceFont(15)
                .foregroundStyle(PaceColor.ink)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(Copy.Settings.effectiveDate)，\(displayDate)"))
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
                .paceFont(11)
                .foregroundStyle(PaceColor.ink2)
            } else {
                Text(Copy.Settings.noBudget)
                    .paceFont(11)
                    .foregroundStyle(PaceColor.ink2)
            }

            // 大字号下标签和值并排会把「每日预算」压成两行、值挤到右边剩一半；
            // 改成标签一行、值一行（值仍然靠左，因为它要能被读准）。
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Copy.Settings.dailyBudget)
                    TextField(Copy.Settings.budgetPlaceholder, text: $budgetText)
                        .keyboardType(.decimalPad)
                }
            } else {
                HStack {
                    Text(Copy.Settings.dailyBudget)
                    Spacer()
                    TextField(Copy.Settings.budgetPlaceholder, text: $budgetText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }

            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(Copy.Settings.effectiveDate)
                    dateButton
                }
                // 这一行是卡片的最后一行：原来「保存预算」还在这张卡里，它下面这条线是
                // 「卡片内部再分区」用的。按钮搬出卡片之后没人用得上它了，留着就是在卡片
                // 底边上划一道缝（默认字号量到 362.0–363.0，另外两张卡都没有）。
                .listRowSeparator(.hidden)
            } else {
            HStack {
                Text(Copy.Settings.effectiveDate)
                Spacer()
                // 界面上写「10月26日」。以前是让一个透明的系统选择器垫在字后面接点击——
                // 字一大，它自己那串「2026 年 10 月 26 日」就撑出这一格的框，
                // 卡片底下多出一条空白（就是那条「透出来」的影子）。现在按一下开面板，
                // 面板里是图形选择器：里面没有一行字要跟外面这格的宽度对齐。
                Button {
                    showDatePicker = true
                } label: {
                    Text(displayDate)
                        .paceFont(15)
                        .foregroundStyle(PaceColor.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(Copy.Settings.effectiveDate)，\(displayDate)"))
            }
            .listRowSeparator(.hidden)
            }

            // 真按钮，不是一行说明：可用时实底 accent，不可用时灰底点不动。
            // 「已保存」直接换按钮上的字，不挂在行右边——那看起来像一条状态说明。
            Button {
                saveBudget()
            } label: {
                Text(showSavedBadge ? Copy.Settings.savedBadge : Copy.Settings.saveBudget)
                    .paceFont(16, .semibold)
                    .foregroundStyle(canSaveBudget ? PaceColor.onAccent : PaceColor.ink2)
            }
            .buttonStyle(BudgetSaveButtonStyle(enabled: canSaveBudget))
            .disabled(!canSaveBudget)
            .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)

            if let budgetError {
                Text(budgetError)
                    .paceFont(12)
                    .foregroundStyle(PaceColor.danger)
            }
        } header: {
            headerText(Copy.Settings.dailyBudget)
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
                        .paceFont(13)
                        .foregroundStyle(PaceColor.ink2)
                }
            }
        } header: {
            headerText(Copy.Settings.quickAddRow)
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
                Text(importMessage).paceFont(12).foregroundStyle(PaceColor.ink2)
            }
        } header: {
            headerText("导出与恢复")
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
            headerText("调试")
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
                            Text(Copy.Settings.Import.Preview.bills(
                                count: Int(preview.transactionCount),
                                first: preview.firstLocalDate,
                                last: preview.lastLocalDate
                            ))
                            Text(Copy.Settings.Import.Preview.groups(
                                categories: Int(preview.categoryCount),
                                budgets: Int(preview.budgetRuleCount)
                            ))
                            // 零不出现：一句里没有「0 笔」的位置它就整行不在。
                            if let duplicates = Copy.Settings.Import.previewDuplicates(count: Int(preview.duplicateCount)) {
                                Text(duplicates)
                            }
                            Section {
                                Button(Copy.Settings.Import.Preview.merge) { applyImport(mode: "MERGE") }
                                Button(Copy.Settings.Import.Preview.replace, role: .destructive) { confirmReplace = true }
                            } footer: {
                                Text(Copy.Settings.Import.mergeOrReplaceNote)
                            }
                        }
                    } else {
                        // 校验没通过：和别处的失败卡同一个结构——标题说哪件事没成、
                        // 正文说现在什么状态、下面是全部原因、最后一颗「换一份文件再试」。
                        // 一次只报第一个原因等于让人按次数把错走完，所以全列出来（最多五行）。
                        ScrollView {
                            VStack(alignment: .leading, spacing: PaceSpace.inner) {
                                Text(Copy.Settings.Import.Preview.invalidTitle)
                                    .paceFont(15, .semibold)
                                    .foregroundStyle(PaceColor.ink)
                                Text(Copy.Settings.Import.Preview.invalidBody)
                                    .paceFont(13)
                                    .foregroundStyle(PaceColor.ink2)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button(Copy.Settings.Import.Preview.retry) { retryImporter = true }
                                    .buttonStyle(GlassSecondaryStyle())
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(importProblems(overriddenReasons ?? preview.errors), id: \.self) { line in
                                        Text(line)
                                            .paceFont(13)
                                            .foregroundStyle(PaceColor.ink2)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .paceCardFill(18)
                            .padding(20)
                        }
                    }
                }
            }
            .fileImporter(isPresented: $retryImporter, allowedContentTypes: [.json, .data]) { result in
                switch result {
                case .success(let url):
                    if let text = readImportedText(url) {
                        importJsonText = text
                        importPreview = LedgerStore.shared.api.previewImport(jsonText: text)
                        overriddenReasons = nil
                    } else {
                        // 读不出来：不关这张卡，只把原因换成这一条。
                        overriddenReasons = []
                    }
                case .failure:
                    // 取消：人只是去找另一份文件，回来还要看原来那份卡在哪儿。
                    break
                }
            }
            .navigationTitle(Copy.Settings.Import.Preview.title)
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

    /// 导入失败：错误码只写日志，界面上说人话，而且一次说完。
    /// 只报第一个的话，人得改一笔、再恢复、再撞下一个，来回好几趟才走完。
    /// 最多五行——原因一共五种，再多就是撑满一屏而不是说人话。
    private func importProblems(_ errors: [String]) -> [String] {
        NSLog("[Pace] 导入问题：\(errors.joined(separator: " | "))")
        var lines: [String] = []
        for raw in errors {
            let code = raw.split(separator: ":").first.map(String.init) ?? raw
            let line: String
            switch code.trimmingCharacters(in: .whitespaces) {
            case "INVALID_AMOUNT": line = Copy.Settings.Import.Issue.invalidAmount
            case "INVALID_DATE": line = Copy.Settings.Import.Issue.invalidDate
            case "INVALID_TYPE", "INVALID_CATEGORY": line = Copy.Settings.Import.Issue.invalidTypeOrCategory
            case "NOTE_TOO_LONG": line = Copy.Settings.Import.Issue.noteTooLong
            default: continue
            }
            if !lines.contains(line) { lines.append(line) }
            if lines.count == 5 { break }
        }
        return lines.isEmpty ? [Copy.Settings.Import.Issue.unknown] : lines
    }

    /// 选中的文件读成文本；读不出来返回 nil。
    private func readImportedText(_ url: URL) -> String? {
        guard url.startAccessingSecurityScopedResource() else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    private func applyImport(mode: String) {
        guard let json = importJsonText else { return }
        let result = LedgerStore.shared.api.applyImport(jsonText: json, mode: mode)
        if result.applied {
            importMessage = mode == "REPLACE"
                ? Copy.Settings.Import.Result.replaced(count: Int(result.insertedCount))
                : Copy.Settings.Import.merged(added: Int(result.insertedCount), skipped: Int(result.skippedCount))
        } else {
            let reasons = importProblems(result.errors).joined(separator: "；")
            importMessage = Copy.Settings.Import.Issue.failed(reason: reasons)
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
            .frame(minHeight: 50)
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
