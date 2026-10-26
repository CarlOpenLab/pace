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
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(PaceColor.ink)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(lines, id: \.self) { line in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(PaceColor.ink2)
                                .padding(.top, 4)
                            Text(line)
                                .font(.system(size: 15))
                                .foregroundStyle(PaceColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Text(Copy.PrivacySheet.footer)
                    .font(.system(size: 12))
                    .foregroundStyle(PaceColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    Button {
                        onAgree()
                        dismiss()
                    } label: {
                        Text(Copy.PrivacySheet.primary)
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button(Copy.PrivacySheet.secondary) {
                        onDecline()
                        dismiss()
                    }
                    .buttonStyle(PlainButtonStylePace())

                    Text(Copy.PrivacySheet.settingsHint)
                        .font(.system(size: 11))
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
