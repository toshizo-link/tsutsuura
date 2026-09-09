import SwiftUI

struct EmailEntryScreen: View {
    @Binding var email: String
    let isSubmitting: Bool
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        EmailAddressPage(
            email: $email,
            isEnrolling: false,
            isSubmitting: isSubmitting,
            onBack: onBack,
            onContinue: onContinue
        )
    }
}

struct EmailEnrollmentScreen: View {
    @Binding var email: String
    let isSubmitting: Bool
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        EmailAddressPage(
            email: $email,
            isEnrolling: true,
            isSubmitting: isSubmitting,
            onBack: onBack,
            onContinue: onContinue
        )
    }
}

private struct EmailAddressPage: View {
    @Binding var email: String
    let isEnrolling: Bool
    let isSubmitting: Bool
    let onBack: () -> Void
    let onContinue: () -> Void
    @FocusState private var isEmailFocused: Bool

    var body: some View {
        LifecyclePage(
            title: isEnrolling ? "メールを登録" : "メールでログイン",
            onBack: {
                isEmailFocused = false
                onBack()
            }
        ) {
            PaperPanel {
                VStack(alignment: .leading, spacing: 20) {
                    Label("1. メールアドレスを入力", systemImage: "envelope.fill")
                        .font(TsutsuuraTheme.bodyFont(size: 23, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(isEnrolling
                        ? "機種変更をしたときに、同じアカウントへ戻るためのメールを登録します。"
                        : "このアカウントに登録したメールアドレスを入力してください。")
                        .font(TsutsuuraTheme.bodyFont(size: 21))
                        .fixedSize(horizontal: false, vertical: true)
                    TextField("name@example.com", text: $email)
                        .font(TsutsuuraTheme.bodyFont(size: 23))
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isEmailFocused)
                        .submitLabel(.next)
                        .onSubmit(continueIfValid)
                        .onChange(of: email) { _, value in
                            email = UnicodeTextValidation.clamped(
                                value, maximumLength: EmailAddressValidation.maximumLength
                            )
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 62)
                        .background(.white.opacity(0.72))
                        .overlay(Rectangle().stroke(TsutsuuraTheme.skyInk, lineWidth: 2))
                        .accessibilityLabel("メールアドレス")
                        .accessibilityIdentifier("email-address-input")
                    Text("次の画面で、メールに届く6桁の確認番号を入力します。")
                        .font(TsutsuuraTheme.bodyFont(size: 19))
                        .fixedSize(horizontal: false, vertical: true)
                    if isEnrolling {
                        Text("メールアドレスは家族に表示されません。ご本人が受け取れるメールを使ってください。")
                            .font(TsutsuuraTheme.bodyFont(size: 17))
                            .foregroundStyle(TsutsuuraTheme.skyInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .foregroundStyle(TsutsuuraTheme.ink)
                .padding(24)
            }

            TextRaisedButton(
                title: isSubmitting ? "送信中…" : "確認メールを送る",
                icon: "envelope.fill",
                height: 68,
                fontSize: 25,
                action: continueIfValid
            )
            .disabled(!EmailAddressValidation.isValid(email) || isSubmitting)
            .accessibilityIdentifier(isEnrolling ? "email-enrollment-submit" : "email-login-submit")

            if !isEnrolling {
                Text("まだメールを登録していない方は、「戻る」から復旧コードや家族の設定番号を使ってください。")
                    .font(TsutsuuraTheme.bodyFont(size: 19))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func continueIfValid() {
        guard !isSubmitting, EmailAddressValidation.isValid(email) else { return }
        isEmailFocused = false
        onContinue()
    }
}

struct EmailVerificationScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let email: String
    @Binding var code: String
    let isSubmitting: Bool
    let onBack: () -> Void
    let onResend: () -> Void
    let onVerify: () -> Void
    var confirmationTitle = "ログイン"
    var expiresAt: Date? = nil
    var resendAvailableAt: Date? = nil
    var canReplayExpiredAttempt = false

    @FocusState private var isCodeFocused: Bool

    private var isVerificationDisabled: Bool {
        code.count != 6 || isSubmitting
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            LifecyclePage(title: "2. メールの確認番号", onBack: goBack) {
                Text("\(email)\nメールに届いた6桁の番号を入力してください。")
                    .font(TsutsuuraTheme.bodyFont(size: 21))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                PaperPanel {
                    VStack(spacing: 12) {
                        TextField("6桁の確認番号", text: $code)
                            .font(TsutsuuraTheme.bodyFont(size: 32))
                            .foregroundStyle(TsutsuuraTheme.ink)
                            .tsutsuuraOTPInputTraits()
                            .multilineTextAlignment(.center)
                            .focused($isCodeFocused)
                            .onChange(of: code) { _, newValue in
                                code = NumericInputValidation.asciiDigits(
                                    in: newValue,
                                    maximum: 6
                                )
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 72)
                            .background(.white.opacity(0.72))
                            .overlay(Rectangle().stroke(TsutsuuraTheme.skyInk, lineWidth: 2))
                            .accessibilityLabel("確認番号")
                            .accessibilityIdentifier("email-verification-code-input")

                        if let expiresAt {
                            Text(expiryText(now: timeline.date, expiresAt: expiresAt))
                                .font(TsutsuuraTheme.bodyFont(size: 17))
                                .foregroundStyle(
                                    timeline.date >= expiresAt
                                        ? TsutsuuraTheme.coral
                                        : TsutsuuraTheme.skyInk
                                )
                                .accessibilityIdentifier("email-otp-expiry-countdown")

                            if canReplayExpiredAttempt,
                               timeline.date >= expiresAt {
                                Text("前回「確認する」を押したあとに通信が途切れた場合は、同じ6桁の番号を入力すると結果を復旧できます。それ以外は確認番号を再送してください。")
                                    .font(TsutsuuraTheme.bodyFont(size: 16))
                                    .foregroundStyle(TsutsuuraTheme.skyInk)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier(
                                        "email-otp-interrupted-recovery-hint"
                                    )
                            }
                        }
                    }
                    .padding(24)
                }

                TextRaisedButton(
                    title: isSubmitting ? "確認中…" : confirmationTitle,
                    icon: "checkmark",
                    height: 68,
                    fontSize: 26,
                    haptic: .success,
                    action: verify
                )
                .disabled(
                    isVerificationDisabled
                        || (
                            !canReplayExpiredAttempt
                                && expiresAt.map { timeline.date >= $0 } == true
                        )
                )
                .accessibilityIdentifier("verify-email-code-button")

                VStack(spacing: 8) {
                    Text("メールが届かない場合は、迷惑メールも確認してください。")
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .font(TsutsuuraTheme.bodyFont(size: 18))
                        .foregroundStyle(.white)
                    Button(resendTitle(now: timeline.date)) {
                        code = ""
                        onResend()
                    }
                    .font(TsutsuuraTheme.bodyFont(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .overlay(Rectangle().stroke(.white, lineWidth: 2))
                    .disabled(
                        isSubmitting
                            || resendAvailableAt.map { timeline.date < $0 } == true
                    )
                    .accessibilityIdentifier("resend-email-code-button")
                }
            }
        }
        .animation(
            TsutsuuraMotion.respectingReduceMotion(
                reduceMotion,
                TsutsuuraMotion.quickSpring
            ),
            value: isCodeFocused
        )
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button("閉じる") {
                    isCodeFocused = false
                }
                .accessibilityIdentifier("dismiss-code-keyboard")
            }
        }
    }

    private func expiryText(now: Date, expiresAt: Date) -> String {
        let seconds = max(0, Int(expiresAt.timeIntervalSince(now)))
        guard seconds > 0 else { return "確認番号の期限が切れました。再送してください。" }
        return "有効期限 あと\(seconds / 60)分\(seconds % 60)秒"
    }

    private func resendTitle(now: Date) -> String {
        guard let resendAvailableAt,
              resendAvailableAt > now else { return "確認番号を再送" }
        return "あと\(Int(resendAvailableAt.timeIntervalSince(now).rounded(.up)))秒で再送できます"
    }

    private func goBack() {
        isCodeFocused = false
        onBack()
    }

    private func verify() {
        guard !isVerificationDisabled else { return }
        isCodeFocused = false
        onVerify()
    }
}

