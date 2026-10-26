import SwiftUI

/// 开启前的隐私说明：只在第一次打开开关时出现一次。
struct PrivacyNoteView: View {
    let onAgree: () -> Void
    let onDecline: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var lines: [String] {
        [Copy.PrivacySheet.line1, Copy.PrivacySheet.line2, Copy.PrivacySheet.line3, Copy.PrivacySheet.line4]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaceSpace.cardGap) {
                Text(Copy.PrivacySheet.title)
                    // 原 26 号页面标题：保住基准，只跟系统缩放。
                    .paceFont(26, .bold, relativeTo: .title)
                    .foregroundStyle(PaceColor.ink)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(lines, id: \.self) { line in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark")
                                .paceFont(12, .bold, relativeTo: .caption)
                                .foregroundStyle(PaceColor.ink2)
                                .padding(.top, 4)
                            Text(line)
                                .paceFont(15, .regular, relativeTo: .subheadline)
                                .foregroundStyle(PaceColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Text(Copy.PrivacySheet.footer)
                    .paceFont(12, .regular, relativeTo: .caption)
                    .foregroundStyle(PaceColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    Button {
                        onAgree()
                        dismiss()
                    } label: {
                        Text(Copy.PrivacySheet.primary)
                            .paceFont(16, .semibold, relativeTo: .callout)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 50)
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button(Copy.PrivacySheet.secondary) {
                        onDecline()
                        dismiss()
                    }
                    .buttonStyle(PlainButtonStylePace())

                    Text(Copy.PrivacySheet.settingsHint)
                        .paceFont(11, .regular, relativeTo: .caption2)
                        .foregroundStyle(PaceColor.ink2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, PaceSpace.screen)
            .padding(.vertical, PaceSpace.cardGap)
        }
        .background(PaceColor.canvas)
        .presentationDetents([.large])
    }
}
