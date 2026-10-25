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
    @State private var showImporter = false

    private var currentBudget: BudgetRule? {
        LedgerStore.shared.api.budgetFor(localDate: LedgerStore.shared.todayIso)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("每日预算") {
                    if let rule = currentBudget {
                        Text("当前 \(LedgerStore.shared.format(rule.dailyAmountMinor))（自 \(rule.effectiveFromLocalDate) 生效）")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("尚未设置预算")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    TextField("每日预算（元）", text: $budgetText)
                        .keyboardType(.decimalPad)
                    TextField("生效日期（yyyy-MM-dd）", text: $effectiveFrom)
                    Button("保存预算") { saveBudget() }
                    Text("修改预算从指定生效日开始，不重写历史。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("导出 CSV") { exportCsv() }
                    Button("导出 JSON") { exportJson() }
                    Button("从 JSON 恢复…") { showImporter = true }
                    if let importMessage {
                        Text(importMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("导出与恢复")
                } footer: {
                    Text("导出文件通过系统分享面板交给你保存；保存到 iCloud/Drive/微信等外部服务后，由对应服务管理。账本数据只保存在本机，删除 App 且未导出时数据将丢失。")
                }

                Section("隐私与 AI") {
                    Text("""
                    · 当前为本地隐私模式：账本内容不离开设备。
                    · AI 功能默认关闭，记账与统计完全不依赖 AI。
                    · AI 仅用于把你的输入整理成待确认草稿，永不直接修改账本。
                    """)
                    .font(.footnote)
                }

                Section("数据") {
                    Button("清空全部数据…", role: .destructive) { confirmClear = true }
                }
            }
            .navigationTitle("设置")
            .listRowBackground(GlassRowBackground())
            .glassFormStyle()
            .id(refreshToken)
            .onAppear {
                if budgetText.isEmpty, let rule = currentBudget {
                    budgetText = Money.shared.formatMinor(amountMinor: rule.dailyAmountMinor)
                }
            }
            .sheet(item: $exportShareItem) { item in
                ShareSheet(items: [item.url])
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json, .data]) { result in
                switch result {
                case .success(let url):
                    guard url.startAccessingSecurityScopedResource(),
                          let data = try? Data(contentsOf: url),
                          let text = String(data: data, encoding: .utf8) else {
                        url.stopAccessingSecurityScopedResource()
                        importMessage = "无法读取文件"
                        return
                    }
                    url.stopAccessingSecurityScopedResource()
                    importJsonText = text
                    importPreview = LedgerStore.shared.api.previewImport(jsonText: text)
                case .failure:
                    importMessage = "无法读取文件"
                }
            }
            .sheet(isPresented: Binding(
                get: { importPreview != nil && importJsonText != nil },
                set: { if !$0 { importPreview = nil; importJsonText = nil } }
            )) {
                importPreviewSheet
            }
            .alert("替换当前账本？", isPresented: $confirmReplace) {
                Button("确认替换", role: .destructive) { applyImport(mode: "REPLACE") }
                Button("取消", role: .cancel) {}
            } message: {
                Text("当前全部账单、预算和分类将被删除，并以导入文件替换。此操作无法撤销。")
            }
            .alert("清空全部数据？", isPresented: $confirmClear) {
                Button("确认清空", role: .destructive) {
                    if LedgerStore.shared.api.clearAllData() {
                        importMessage = "已清空全部数据"
                    }
                    refreshToken += 1
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将删除所有账单、预算规则和自定义分类。此操作无法撤销，请先导出备份。")
            }
        }
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
        }
    }

    // MARK: 导出

    private struct ShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    private func exportCsv() { share(text: LedgerStore.shared.api.exportCsv(), ext: "csv") }

    private func exportJson() {
        share(text: LedgerStore.shared.api.exportJson(timezoneId: LedgerStore.shared.timezoneId), ext: "json")
    }

    private func share(text: String, ext: String) {
        let stamp = DateFormatter(format: "yyyyMMdd-HHmmss").string(from: Date())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pace-ledger-\(stamp).\(ext)")
        try? text.data(using: .utf8)?.write(to: url)
        exportShareItem = ShareItem(url: url)
    }

    // MARK: 导入

    private func pickJson() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .data, .item])
        picker.delegate = DocumentPickerDelegate { url in
            guard let url, let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else {
                importMessage = "无法读取文件"
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
                            Text("与现有账本重复 \(preview.duplicateCount) 笔")
                            Section {
                                Button("合并到现有账本") { applyImport(mode: "MERGE") }
                                Button("替换当前账本…", role: .destructive) { confirmReplace = true }
                            } footer: {
                                Text("合并：跳过重复，保留现有账本。\n替换：清空当前账本后写入。")
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
                    Button("取消") {
                        importPreview = nil
                        importJsonText = nil
                    }
                }
            }
        }
    }

    private func applyImport(mode: String) {
        guard let json = importJsonText else { return }
        let result = LedgerStore.shared.api.applyImport(jsonText: json, mode: mode)
        if result.applied {
            importMessage = mode == "REPLACE"
                ? "已替换：写入 \(result.insertedCount) 笔"
                : "已合并：新入 \(result.insertedCount) 笔，跳过 \(result.skippedCount) 条"
        } else {
            importMessage = "导入失败，原账本未变更：\(result.errors.prefix(3).joined(separator: ", "))"
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
