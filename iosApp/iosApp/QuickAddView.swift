import SwiftUI
import shared

/// 一句话记账（输入页）：一句话进来，本机规则或用户自己填的服务拆成草稿。
struct QuickAddView: View {
    let initialText: String
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ai: AiSettings

    @State private var text: String
    @State private var busy = false
    @State private var failure: AiFailure?
    @State private var drafts: [DraftItem] = []
    @State private var showReview = false
    /// 失败是「本机规则」那一路时，文案和按钮都不一样。
    @State private var localFailure = false
    @EnvironmentObject private var state: AppState

    private var examples: [String] { Copy.Ai.Input.examples }

    init(initialText: String = "", onSaved: @escaping () -> Void) {
        self.initialText = initialText
        self.onSaved = onSaved
        _text = State(initialValue: initialText)
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool { !trimmed.isEmpty && !busy }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PaceSpace.cardGap) {
                    inputCard
                    exampleRow
                    hintLine
                    primaryButton
                    manualButton
                    if let failure {
                        failureCard(failure)
                    }
                }
                .padding(.horizontal, PaceSpace.screen)
                .padding(.vertical, PaceSpace.cardGap)
            }
            .background(PaceColor.canvas)
            .navigationTitle(Copy.Ai.Input.title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showReview) {
                DraftReviewView(drafts: drafts) {
                    onSaved()
                    dismiss()
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - 输入卡

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: PaceSpace.inner) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold))
                Text(Copy.Ai.Input.label).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(PaceColor.ai)

            TextField(Copy.Ai.Input.placeholder, text: $text, axis: .vertical)
                .font(.system(size: 17))
                .lineSpacing(4)
                .tint(PaceColor.ai)
                .lineLimit(3...6)
                .disabled(busy)
                .accessibilityLabel("一句话记账输入框")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .paceCardFill(20)
    }

    private var exampleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(examples, id: \.self) { example in
                    Button {
                        text = example
                    } label: {
                        Text(example).font(.system(size: 13))
                    }
                    .buttonStyle(PillChipStyle())
                }
            }
        }
    }

    private var hintLine: some View {
        Text(hintText)
            .font(.system(size: 12))
            .foregroundStyle(PaceColor.ink2)
    }

    /// 说明一行：没填三项、开关开着、开关关着，三种说法。
    private var hintText: String {
        if ai.config == nil { return Copy.Ai.Input.noteNoKey }
        return ai.usesRemoteModel ? Copy.Ai.Input.noteRemote : Copy.Ai.Input.noteLocalOff
    }

    private var primaryButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if busy {
                    ProgressView().tint(PaceColor.onAccent)
                    Text(Copy.Ai.Input.submitting)
                } else {
                    Text(Copy.Ai.Input.submit)
                }
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!canSubmit)
        .opacity(canSubmit ? 1 : 0.4)
    }

    private var manualButton: some View {
        Button(Copy.Ai.Input.manual) { goManual() }
        .buttonStyle(PlainButtonStylePace())
    }

    // MARK: - 失败

    private func failureCard(_ failure: AiFailure) -> some View {
        let copy = failureCopy(failure, isLocal: localFailure)
        return VStack(alignment: .leading, spacing: PaceSpace.inner) {
            Text(copy.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(PaceColor.ink)
            Text(copy.body).font(.system(size: 13)).foregroundStyle(PaceColor.ink2)
            HStack(spacing: 10) {
                Button(copy.primary) { primaryAction(failure) }
                    .buttonStyle(PillChipStyle(selected: true))
                if let secondary = copy.secondary {
                    Button(secondary) { secondaryAction(failure) }
                        .buttonStyle(PillChipStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .paceCardFill(18)
    }

    private struct FailureCopy {
        let title: String
        let body: String
        let primary: String
        let secondary: String?
    }

    private func failureCopy(_ failure: AiFailure, isLocal: Bool) -> FailureCopy {
        if isLocal {
            // 本机规则自己没拆开：只留「手动记这笔」。
            return FailureCopy(
                title: Copy.Ai.Fail.LocalRule.title,
                body: Copy.Ai.Fail.LocalRule.body,
                primary: Copy.Ai.Fail.LocalRule.primary,
                secondary: nil
            )
        }
        switch failure {
        case .offline:
            return FailureCopy(title: Copy.Ai.Fail.Offline.title, body: Copy.Ai.Fail.Offline.body,
                               primary: Copy.Ai.Fail.Offline.primary, secondary: Copy.Ai.Fail.Offline.secondary)
        case .timeout:
            return FailureCopy(title: Copy.Ai.Fail.Timeout.title, body: Copy.Ai.Fail.Timeout.body,
                               primary: Copy.Ai.Fail.Timeout.primary, secondary: Copy.Ai.Fail.Timeout.secondary)
        case .keyRejected:
            return FailureCopy(title: Copy.Ai.Fail.KeyRejected.title, body: Copy.Ai.Fail.KeyRejected.body,
                               primary: Copy.Ai.Fail.KeyRejected.primary, secondary: Copy.Ai.Fail.KeyRejected.secondary)
        case .quota:
            return FailureCopy(title: Copy.Ai.Fail.KeyRejected.title, body: Copy.Ai.Fail.Quota.body,
                               primary: Copy.Ai.Fail.KeyRejected.primary, secondary: Copy.Ai.Fail.KeyRejected.secondary)
        case .addressUnreachable, .notConfigured:
            return FailureCopy(title: Copy.Ai.Fail.Offline.title, body: Copy.Ai.Fail.Offline.body,
                               primary: Copy.Ai.Fail.Offline.primary, secondary: Copy.Ai.Fail.Offline.secondary)
        default:
            return FailureCopy(title: Copy.Ai.Fail.Model.title, body: Copy.Ai.Fail.Model.body,
                               primary: Copy.Ai.Fail.Model.primary, secondary: Copy.Ai.Fail.Model.secondary)
        }
    }

    private func primaryAction(_ failure: AiFailure) {
        let copy = failureCopy(failure, isLocal: localFailure)
        switch copy.primary {
        case Copy.Ai.Fail.KeyRejected.primary:
            dismiss()
        case Copy.Ai.Fail.Offline.primary:
            runLocal()
        case Copy.Ai.Fail.Timeout.primary, Copy.Ai.Fail.Model.primary, Copy.Ai.Fail.LocalRule.primary:
            goManual()
        default:
            goManual()
        }
    }

    private func secondaryAction(_ failure: AiFailure) {
        if localFailure {
            goManual()
        } else {
            runLocal()
        }
    }

    /// 手动记这笔：把用户原来那句话原样带进备注。
    private func goManual() {
        state.pendingNote = trimmed.isEmpty ? nil : trimmed
        state.showAdd = true
        dismiss()
    }

    // MARK: - 拆句

    private func submit() async {
        guard canSubmit else { return }
        failure = nil
        busy = true
        defer { busy = false }

        let sentence = trimmed
        let today = LedgerStore.shared.todayIso

        if ai.usesRemoteModel, let config = ai.config {
            do {
                let parsed = try await AiDraftClient.parse(text: sentence, todayIso: today, config: config)
                drafts = parsed
                showReview = true
                return
            } catch let error as AiFailure {
                failure = error
                return
            } catch {
                failure = .unreadable
                return
            }
        }
        runLocal(sentence: sentence, today: today)
    }

    private func runLocal() {
        failure = nil
        localFailure = false
        runLocal(sentence: trimmed, today: LedgerStore.shared.todayIso)
    }

    private func runLocal(sentence: String, today: String) {
        let parsed = LocalDrafts.parse(text: sentence, todayIso: today)
        if parsed.isEmpty {
            localFailure = true
            failure = .unreadable
            return
        }
        drafts = parsed
        showReview = true
    }
}
