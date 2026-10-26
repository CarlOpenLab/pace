import SwiftUI
import shared

/// 设置 → 一句话记账：开关、三项配置、测试连接、清空 Key。
struct QuickAddSettingsView: View {
    @EnvironmentObject private var ai: AiSettings
    @Environment(\.dismiss) private var dismiss

    @State private var showPrivacyNote = false
    @State private var pendingEnable = false
    @State private var testing = false
    @State private var testResult: AiDraftClient.TestResult?
    @State private var confirmClearKey = false
    @State private var toast: String?

    /// 用 Key 从服务商读回来的模型列表；空着就回到手填模型名。
    @State private var models: [String] = []
    @State private var manualEntry = false
    @State private var fetchingModels = false
    @State private var modelsNotice: ModelNotice?
    /// 手上这份名单是上一次成功读回来的，这次没刷新成功。
    @State private var listStale = false
    @State private var pickingModel = false
    @FocusState private var focusedField: EditField?
    private enum EditField: Hashable { case endpoint, key }

    var body: some View {
        ScrollView {
            VStack(spacing: PaceSpace.cardGap) {
                toggleCard
                fieldsCard
                testButton
                if let testResult {
                    resultLine(testResult)
                }
                securityCard
            }
            .padding(.horizontal, PaceSpace.screen)
            .padding(.vertical, PaceSpace.cardGap)
        }
        .background(PaceColor.canvas)
        .task {
            if models.isEmpty, modelsNotice == nil, !manualEntry,
               !ai.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !ai.key.isEmpty {
                await loadModels()
            }
        }
        .sheet(isPresented: $pickingModel) {
            AiModelPickerView(models: models, selected: $ai.model, isPresented: $pickingModel)
        }
        // 设置里 push 出来的二级页，不留标签栏：底栏会把「清空 Key」挤上去。
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(Copy.Ai.Settings.sectionTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: ai.key) { _, newValue in
            // Key 清掉之后，上一次的失败说明就不算数了。
            if newValue.isEmpty { modelsNotice = nil }
        }
        .onChange(of: focusedField) { old, new in
            // 地址或 Key 改完、光标离开那一栏，就再拉一次列表。
            if old != nil, new == nil { reloadAfterEdit() }
        }
        .onChange(of: ai.endpoint) { _, _ in
            // 换了地址，之前拉下来的列表就不算数了。
            models = []
            modelsNotice = nil
        }
        .onChange(of: pendingEnable) { _, wantsOn in
            guard wantsOn else { return }
            // 第一次打开开关：先看一遍隐私说明，点「同意并开启」才真的打开。
            if !PrivacySeen.value {
                showPrivacyNote = true
            }
        }
        .sheet(isPresented: $showPrivacyNote) {
            PrivacyNoteView {
                PrivacySeen.value = true
                ai.enabled = true
                pendingEnable = false
            } onDecline: {
                ai.enabled = false
                pendingEnable = false
            }
        }
        .alert(Copy.Ai.Test.clearConfirmTitle, isPresented: $confirmClearKey) {
            Button(Copy.Ai.Test.clearCancel, role: .cancel) {}
            Button(Copy.Ai.Test.clearConfirm, role: .destructive) {
                ai.clearKey()
                testResult = nil
            }
        } message: {
            Text(Copy.Ai.Test.clearConfirmBody)
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PaceColor.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(PaceColor.card, in: Capsule(style: .continuous))
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - 开关

    private var toggleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(Copy.Ai.Settings.toggleTitle, isOn: Binding(
                get: { ai.enabled },
                set: { newValue in
                    if newValue, !PrivacySeen.value {
                        pendingEnable = true
                        return
                    }
                    ai.enabled = newValue
                    if !newValue {
                        showToast(Copy.Ai.Settings.disabledToast)
                    }
                }
            ))
            .font(.system(size: 15, weight: .semibold))
            .tint(PaceColor.accent)

            Text(ai.enabled ? Copy.Ai.Settings.subtitleOn : Copy.Ai.Settings.subtitleOff)
                .font(.system(size: 12))
                .foregroundStyle(PaceColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .paceCardFill(PaceRadius.card)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Copy.Ai.Settings.toggleTitle)，\(ai.enabled ? Copy.Ai.Settings.subtitleOn : Copy.Ai.Settings.subtitleOff)")
    }

    // MARK: - 服务商、地址、模型、Key

    private var fieldsCard: some View {
        VStack(alignment: .leading, spacing: PaceSpace.inner) {
            field(
                label: Copy.Ai.Settings.Provider.label,
                note: Copy.Ai.Settings.Provider.note
            ) {
                Menu {
                    ForEach(AiProvider.presets) { provider in
                        Button(provider.name) { apply(provider) }
                    }
                    Divider()
                    Button(AiProvider.custom.name) { apply(AiProvider.custom) }
                } label: {
                    HStack(spacing: 4) {
                        Text(currentProvider.name)
                            .font(.system(size: 15))
                            .foregroundStyle(PaceColor.ink)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(PaceColor.ink2)
                    }
                }
                .accessibilityLabel("\(Copy.Ai.Settings.Provider.label)，\(currentProvider.name)")
            }

            if currentProvider == AiProvider.custom {
                Divider().background(PaceColor.divider)

                field(
                    label: Copy.Ai.Settings.Endpoint.label,
                    note: Copy.Ai.Settings.Endpoint.note,
                    stacked: true
                ) {
                    TextField(Copy.Ai.Settings.Endpoint.placeholder, text: $ai.endpoint)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .endpoint)
                        .onSubmit { reloadAfterEdit() }
                }
            }

            Divider().background(PaceColor.divider)

            field(
                label: manualEntry || models.isEmpty ? Copy.Ai.Settings.Model.label : Copy.Ai.Settings.ModelPick.label,
                note: manualEntry || models.isEmpty
                    ? Copy.Ai.Settings.Model.note
                    : (listStale ? Copy.Ai.Settings.ModelPick.staleList : Copy.Ai.Settings.ModelPick.ready)
            ) {
                if manualEntry || models.isEmpty {
                    TextField(Copy.Ai.Settings.Model.placeholder, text: $ai.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                } else if models.count <= 15 {
                    Menu {
                        ForEach(models, id: \.self) { name in
                            Button(name) { ai.model = name }
                        }
                    } label: {
                        modelLabel
                    }
                    .accessibilityLabel("\(Copy.Ai.Settings.ModelPick.label)，\(ai.model.isEmpty ? Copy.Ai.Settings.ModelPick.choose : ai.model)")
                } else {
                    Button {
                        pickingModel = true
                    } label: {
                        modelLabel
                    }
                    .accessibilityLabel("\(Copy.Ai.Settings.ModelPick.label)，\(ai.model.isEmpty ? Copy.Ai.Settings.ModelPick.choose : ai.model)")
                    .buttonStyle(.plain)
                }
            }

            if !models.isEmpty {
                Button(manualEntry ? Copy.Ai.Settings.ModelPick.backToList : Copy.Ai.Settings.ModelPick.manual) {
                    manualEntry.toggle()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PaceColor.ink)
            }

            if !models.isEmpty, !ai.model.isEmpty, !models.contains(ai.model) {
                Text(Copy.Ai.Settings.ModelPick.stale(ai.model))
                    .font(.system(size: 11))
                    .foregroundStyle(PaceColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            fetchModelsRow

            Divider().background(PaceColor.divider)

            field(
                label: Copy.Ai.Settings.Key.label,
                note: Copy.Ai.Settings.Key.note
            ) {
                HStack(spacing: 8) {
                    SecureField(Copy.Ai.Settings.Key.placeholder, text: $ai.key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .key)
                        .onSubmit { reloadAfterEdit() }
                    if !ai.key.isEmpty {
                        Button(Copy.Ai.Test.clearKey) { confirmClearKey = true }
                            .font(.system(size: 12))
                            .foregroundStyle(PaceColor.danger)
                    }
                }
            }

            // 从一句话那页挪过来的隐私说明：它是这条路的边界，不是装饰。
            // 就贴在 Key 输入框下面，一行 12 ink2。
            Text(Copy.Ai.Settings.keyScope)
                .font(.system(size: 12))
                .foregroundStyle(PaceColor.ink2)
                .fixedSize(horizontal: false, vertical: true)

            if ai.keyStoreFailed, !ai.key.isEmpty {
                Text(Copy.Ai.Settings.Key.storeFailed)
                    .font(.system(size: 11))
                    .foregroundStyle(PaceColor.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .paceCardFill(PaceRadius.card)
    }

    /// stacked：标签一行、输入框另起一行占满宽（长地址要能看全）；否则标签和值左右对齐。
    private func field<Content: View>(
        label: String,
        note: String,
        stacked: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if stacked {
                Text(label)
                    .font(.system(size: 15))
                    .foregroundStyle(PaceColor.ink)
                content()
                    .font(.system(size: 15))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(label)
                        .font(.system(size: 15))
                        .foregroundStyle(PaceColor.ink)
                        .layoutPriority(1)
                    content()
                        .font(.system(size: 15))
                }
            }
            Text(note)
                .font(.system(size: 11))
                .foregroundStyle(PaceColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 读取模型列表：拿现在填的 Key 去服务商读 /models，读回来就变成上面那个下拉。
    private var fetchModelsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let hint = modelListHint {
                // 缺哪样说哪样；两样都缺就说两样。不放在这儿按了没用的按钮。
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(PaceColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                fetchModelsButton
            }

            if let modelsNotice {
                Text(modelsNotice.text)
                    .font(.system(size: 11))
                    .foregroundStyle(modelsNotice.isWarning ? PaceColor.danger : PaceColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    /// 列表还读不成时，直接说现在缺哪一样。
    private var modelListHint: String? {
        let hasAddress = !ai.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasKey = !ai.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch (hasAddress, hasKey) {
        case (false, false): return Copy.Ai.Settings.ModelPick.Error.noAddressAndKey
        case (false, true): return Copy.Ai.Settings.ModelPick.Error.noAddress
        case (true, false): return Copy.Ai.Settings.ModelPick.Error.noKey
        case (true, true): return nil
        }
    }

    private var fetchModelsButton: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Task { await loadModels() }
            } label: {
                HStack(spacing: 6) {
                    if fetchingModels {
                        ProgressView()
                            .controlSize(.small)
                            .tint(PaceColor.ink2)
                    }
                    Text(fetchLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PaceColor.ink)
                }
            }
            .disabled(fetchingModels)
            .accessibilityLabel(fetchingModels ? Copy.Ai.Settings.ModelPick.a11yLoading : fetchLabel)
        }
    }

    private var modelLabel: some View {
        HStack(spacing: 4) {
            Text(ai.model.isEmpty ? Copy.Ai.Settings.ModelPick.choose : ai.model)
                .font(.system(size: 15))
                .foregroundStyle(ai.model.isEmpty ? PaceColor.ink2 : PaceColor.ink)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(PaceColor.ink2)
        }
    }

    private var fetchLabel: String {
        if fetchingModels { return Copy.Ai.Settings.ModelPick.loading }
        return modelsNotice == nil && models.isEmpty
            ? Copy.Ai.Settings.ModelPick.read
            : Copy.Ai.Settings.ModelPick.retry
    }

    private var currentProvider: AiProvider {
        AiProvider.matching(endpoint: ai.endpoint)
    }

    private func apply(_ provider: AiProvider) {
        if !provider.endpoint.isEmpty {
            ai.endpoint = provider.endpoint
        }
        models = []
        manualEntry = false
        modelsNotice = nil
        listStale = false
    }

    private func reloadAfterEdit() {
        guard !fetchingModels,
              !ai.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !ai.key.isEmpty else { return }
        modelsNotice = nil
        Task { await loadModels() }
    }

    private func loadModels() async {
        guard !fetchingModels else { return }
        fetchingModels = true
        modelsNotice = nil
        let result = await AiModelList.fetch(endpoint: ai.endpoint, key: ai.key)
        switch result {
        case .success(let list):
            models = list
            manualEntry = false
            listStale = false
            AccessibilityNotification.Announcement(Copy.Ai.Settings.ModelPick.a11yLoaded(list.count)).post()
        case .failure(.noKey):
           listStale = !models.isEmpty
            listStale = !models.isEmpty
            modelsNotice = .init(Copy.Ai.Settings.ModelPick.Error.noKey, isWarning: false)
        case .failure(.noAddress):
            listStale = !models.isEmpty
            modelsNotice = .init(Copy.Ai.Settings.ModelPick.Error.noAddress, isWarning: false)
        case .failure(.keyRejected):
            listStale = !models.isEmpty
            modelsNotice = .init(Copy.Ai.Settings.ModelPick.Error.keyRejected, isWarning: true)
        case .failure(.noModelList):
            listStale = !models.isEmpty
            modelsNotice = .init(Copy.Ai.Settings.ModelPick.Error.noModelList, isWarning: false)
        case .failure(.unreachable):
            listStale = !models.isEmpty
            modelsNotice = .init(Copy.Ai.Settings.ModelPick.Error.unreachable, isWarning: true)
        case .failure(.server):
            listStale = !models.isEmpty
            modelsNotice = .init(Copy.Ai.Settings.ModelPick.Error.server, isWarning: true)
        case .failure(.empty):
            listStale = !models.isEmpty
            modelsNotice = .init(Copy.Ai.Settings.ModelPick.empty, isWarning: false)
        }
        fetchingModels = false
    }

    // MARK: - 测试连接

    private var testButton: some View {
        Button {
            Task { await runTest() }
        } label: {
            HStack(spacing: 8) {
                if testing {
                    ProgressView().tint(PaceColor.onAccent)
                }
                Text(testing ? Copy.Ai.Test.connecting : Copy.Ai.Test.button)
                    .font(.system(size: 15, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(testing)
    }

    private func runTest() async {
        guard !testing else { return }
        testing = true
        testResult = nil
        let config = AiConfig(endpoint: ai.endpoint, model: ai.model, key: ai.key)
        let result = await AiDraftClient.testConnection(config: config)
        testResult = result
        testing = false
    }

    private func resultLine(_ result: AiDraftClient.TestResult) -> some View {
        let shape: (String, String, Color) = {
            switch result {
            case .ok:
                return (Copy.Ai.Test.ok, "checkmark.circle.fill", PaceColor.income)
            case .unreachable:
                return (Copy.Ai.Test.unreachable, "exclamationmark.triangle.fill", PaceColor.danger)
            case .keyRejected:
                return (Copy.Ai.Test.keyRejected, "exclamationmark.triangle.fill", PaceColor.danger)
            case .incomplete:
                return (Copy.Ai.Test.incomplete, "info.circle", PaceColor.ink2)
            }
        }()
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: shape.1).font(.system(size: 13, weight: .semibold))
            Text(shape.0)
                .font(.system(size: 14, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(shape.2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - 安全提示与清空 Key

    private var securityCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Copy.Ai.Settings.securityTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PaceColor.ink)
            Text(Copy.Ai.Settings.securityNote)
                .font(.system(size: 12))
                .foregroundStyle(PaceColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .paceCardFill(14, color: PaceColor.card2)
    }


    private func showToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.easeIn(duration: 0.2)) { toast = nil }
        }
    }
}

/// 读取模型列表后那一行提示。红的才是要用户处理的；
/// 「这家不列模型」属于正常情况，用灰的。
struct ModelNotice: Equatable {
    let text: String
    let isWarning: Bool

    init(_ text: String, isWarning: Bool) {
        self.text = text
        self.isWarning = isWarning
    }
}

/// 隐私说明只弹一次：记在 UserDefaults 里，重装才会再出现。
enum PrivacySeen {
    private static let key = "ai.privacySeen"

    static var value: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// 模型太多的服务商（OpenRouter 一拉几百个）用这一页：搜索常驻并自动聚焦，行高 44，选中的打勾加粗。
struct AiModelPickerView: View {
    let models: [String]
    @Binding var selected: String
    @Binding var isPresented: Bool

    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var filtered: [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return models }
        return models.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                Divider().background(PaceColor.divider)
                if filtered.isEmpty {
                    Text(Copy.Ai.Settings.ModelPick.noMatch)
                        .font(.system(size: 13))
                        .foregroundStyle(PaceColor.ink2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 28)
                        .padding(.top, 32)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered, id: \.self) { name in
                                row(name)
                                Divider().background(PaceColor.divider).padding(.leading, 16)
                            }
                        }
                    }
                }
            }
            .background(PaceColor.canvas)
            .navigationTitle(Copy.Ai.Settings.ModelPick.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Copy.Ai.Settings.ModelPick.close) { isPresented = false }
                }
            }
            .task {
                // 弹出动画期间系统会丢掉一次聚焦，落定后再点一次。
                try? await Task.sleep(for: .milliseconds(500))
                searchFocused = true
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PaceColor.ink2)
            TextField(Copy.Ai.Settings.ModelPick.search, text: $query)
                .font(.system(size: 15))
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(PaceColor.ink3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Copy.Ai.Settings.ModelPick.clearSearch)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    private func row(_ name: String) -> some View {
        Button {
            selected = name
            isPresented = false
        } label: {
            HStack(spacing: 8) {
                Text(name)
                    .font(.system(size: 15, weight: name == selected ? .semibold : .regular))
                    .foregroundStyle(PaceColor.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if name == selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PaceColor.ink)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
