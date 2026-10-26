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
                if !ai.key.isEmpty {
                    clearKeyButton
                }
            }
            .padding(.horizontal, PaceSpace.screen)
            .padding(.vertical, PaceSpace.cardGap)
        }
        .background(PaceColor.canvas)
        // 设置里 push 出来的二级页，不留标签栏：底栏会把「清空 Key」挤上去。
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle(Copy.Ai.Settings.sectionTitle)
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - 三项

    private var fieldsCard: some View {
        VStack(alignment: .leading, spacing: PaceSpace.inner) {
            field(
                label: Copy.Ai.Settings.Endpoint.label,
                note: Copy.Ai.Settings.Endpoint.note,
                stacked: true
            ) {
                TextField(Copy.Ai.Settings.Endpoint.placeholder, text: $ai.endpoint)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Divider().background(PaceColor.line)

            field(
                label: Copy.Ai.Settings.Model.label,
                note: Copy.Ai.Settings.Model.note
            ) {
                TextField(Copy.Ai.Settings.Model.placeholder, text: $ai.model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }

            Divider().background(PaceColor.line)

            field(
                label: Copy.Ai.Settings.Key.label,
                note: Copy.Ai.Settings.Key.note
            ) {
                HStack(spacing: 8) {
                    SecureField(Copy.Ai.Settings.Key.placeholder, text: $ai.key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                    if !ai.key.isEmpty {
                        Button(Copy.Ai.Test.clearKey) { confirmClearKey = true }
                            .font(.system(size: 12))
                            .foregroundStyle(PaceColor.danger)
                    }
                }
            }

            Text(Copy.Ai.Settings.fallbackNote)
                .font(.system(size: 11))
                .foregroundStyle(PaceColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
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

    private var clearKeyButton: some View {
        Button(role: .destructive) {
            confirmClearKey = true
        } label: {
            Text(Copy.Ai.Test.clearKey)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PaceColor.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func showToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.easeIn(duration: 0.2)) { toast = nil }
        }
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
