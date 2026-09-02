import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Shared lifecycle page

struct LifecyclePage<Content: View>: View {
    let title: String
    let onBack: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            DottedBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    HStack(alignment: .center) {
                        Button(action: onBack) {
                            Label("戻る", systemImage: "chevron.left")
                                .font(TsutsuuraTheme.bodyFont(size: 24))
                                .foregroundStyle(.white)
                                .frame(minHeight: 52)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("lifecycle-back-button")

                        Spacer(minLength: 12)

                        Text(title)
                            .font(TsutsuuraTheme.font(34))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    content()
                }
                .padding(.horizontal, 28)
                .padding(.top, 44)
                .padding(.bottom, 64)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 50, style: .continuous))
    }
}

struct LifecycleField: View {
    let title: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var maximumLength: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(TsutsuuraTheme.bodyFont(size: 20))
                .foregroundStyle(TsutsuuraTheme.ink)

            TextField(title, text: $text)
                .font(TsutsuuraTheme.bodyFont(size: 25))
                .foregroundStyle(TsutsuuraTheme.ink)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 14)
                .frame(minHeight: 58)
                .background(.white.opacity(0.70))
                .overlay(Rectangle().stroke(TsutsuuraTheme.skyInk, lineWidth: 2))
                .onChange(of: text) { _, value in
                    guard let maximumLength,
                          NameValidation.characterCount(value) > maximumLength else {
                        return
                    }
                    text = NameValidation.clamped(
                        value,
                        maximumLength: maximumLength
                    )
                }

            if let maximumLength {
                Text("\(NameValidation.characterCount(text)) / \(maximumLength)文字")
                    .font(TsutsuuraTheme.bodyFont(size: 16))
                    .foregroundStyle(TsutsuuraTheme.skyInk)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

// MARK: - Account recovery and enrollment

struct PhoneEnrollmentScreen: View {
    @Binding var phoneNumber: String
    let isSubmitting: Bool
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        LifecyclePage(title: "電話番号を登録", onBack: onBack) {
            PaperPanel {
                VStack(alignment: .leading, spacing: 18) {
                    Text("機種変更や紛失のときに、同じアカウントへ戻れるようにします。確認番号をSMSで送ります。")
                        .font(TsutsuuraTheme.bodyFont(size: 21))
                        .foregroundStyle(TsutsuuraTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    LifecycleField(
                        title: "電話番号",
                        text: $phoneNumber,
                        keyboardType: .phonePad,
                        maximumLength: 32
                    )

                    Text("登録済みの番号を別のアカウントには使えません。番号は家族には表示されません。")
                        .font(TsutsuuraTheme.bodyFont(size: 17))
                        .foregroundStyle(TsutsuuraTheme.skyInk)
                }
                .padding(24)
            }

            TextRaisedButton(
                title: isSubmitting ? "送信中…" : "確認番号を送る",
                icon: "message.fill",
                height: 68,
                fontSize: 25,
                action: onContinue
            )
            .disabled(
                !PhoneNumberValidation.isPlausible(phoneNumber)
                    || isSubmitting
            )
            .accessibilityIdentifier("phone-enrollment-submit")
        }
    }
}

// MARK: - Family lifecycle

struct FamilyRenameScreen: View {
    @Binding var familyName: String
    let isSaving: Bool
    let onBack: () -> Void
    let onSave: () -> Void

    var body: some View {
        LifecyclePage(title: "家族名を変更", onBack: onBack) {
            PaperPanel {
                LifecycleField(
                    title: "家族の名前",
                    text: $familyName,
                    maximumLength: NameValidation.maximumLength
                )
                .padding(24)
            }

            TextRaisedButton(
                title: isSaving ? "保存中…" : "家族名を保存",
                icon: "checkmark",
                height: 68,
                fontSize: 25,
                haptic: .success,
                action: onSave
            )
            .disabled(
                familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || isSaving
            )
        }
    }
}

struct ManagedMemberEditScreen: View {
    let member: UserProfile
    @Binding var displayName: String
    let isWorking: Bool
    let onBack: () -> Void
    let onSave: () -> Void
    let onIssueRecovery: () -> Void
    let onRemove: () -> Void

    @State private var confirmsRemoval = false

    var body: some View {
        LifecyclePage(title: "家族を編集", onBack: onBack) {
            PaperPanel {
                VStack(alignment: .leading, spacing: 18) {
                    LifecycleField(
                        title: "表示名",
                        text: $displayName,
                        maximumLength: NameValidation.maximumLength
                    )

                    TextRaisedButton(
                        title: isWorking ? "保存中…" : "名前を保存",
                        height: 60,
                        fontSize: 23,
                        action: onSave
                    )
                    .disabled(
                        displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || displayName == member.displayName
                            || isWorking
                    )
                }
                .padding(24)
            }

            if member.managed == true {
                PaperPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("端末の復旧")
                            .font(TsutsuuraTheme.bodyFont(size: 24, weight: .bold))
                            .foregroundStyle(TsutsuuraTheme.ink)
                        Text("紛失・機種変更・誤ってログアウトしたときは、新しい一回限りの設定案内を発行します。以前の未使用案内は無効になります。")
                            .font(TsutsuuraTheme.bodyFont(size: 18))
                            .foregroundStyle(TsutsuuraTheme.skyInk)
                        TextRaisedButton(
                            title: "復旧用の設定案内を作る",
                            icon: "iphone.gen3.radiowaves.left.and.right",
                            height: 62,
                            fontSize: 21,
                            action: onIssueRecovery
                        )
                        .disabled(isWorking)
                    }
                    .padding(24)
                }
            }

            Button(role: .destructive) {
                confirmsRemoval = true
            } label: {
                Label("この家族を削除", systemImage: "person.crop.circle.badge.minus")
                    .font(TsutsuuraTheme.bodyFont(size: 23, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .background(TsutsuuraTheme.coral)
                    .overlay(Rectangle().stroke(Color(hex: 0x7A3038), lineWidth: 3))
            }
            .disabled(isWorking)
            .confirmationDialog(
                "\(member.displayName)を家族から削除しますか？",
                isPresented: $confirmsRemoval,
                titleVisibility: .visible
            ) {
                Button("削除", role: .destructive, action: onRemove)
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この端末のセッションと未使用の設定案内も無効になります。この操作は元に戻せません。")
            }
        }
    }
}

struct OwnershipTransferScreen: View {
    let currentUserID: String
    let members: [UserProfile]
    let isWorking: Bool
    let onBack: () -> Void
    let onTransfer: (UserProfile) -> Void

    @State private var selectedMember: UserProfile?

    private var candidates: [UserProfile] {
        members.filter { $0.id != currentUserID }
    }

    var body: some View {
        LifecyclePage(title: "管理者を引き継ぐ", onBack: onBack) {
            Text("引き継ぎ後は、選んだ方が家族名の変更や家族の削除を管理します。相手のiPhone設定を完了し、その端末で電話番号を登録するか復旧コードを保存しておいてください。管理対象の方は、引き継ぎと同時に独立したアカウントになります。")
                .font(TsutsuuraTheme.bodyFont(size: 20))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            if candidates.isEmpty {
                PaperPanel {
                    Text("引き継げる家族がまだいません。")
                        .font(TsutsuuraTheme.bodyFont(size: 22))
                        .foregroundStyle(TsutsuuraTheme.ink)
                        .padding(24)
                }
            } else {
                ForEach(candidates) { member in
                    Button {
                        selectedMember = member
                    } label: {
                        PaperPanel {
                            HStack(spacing: 14) {
                                PersonBadge(name: member.displayName)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(TsutsuuraTheme.skyInk)
                                    .accessibilityHidden(true)
                            }
                            .padding(18)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                    .accessibilityLabel("\(member.displayName)を管理者に選ぶ")
                }
            }
        }
        .confirmationDialog(
            "管理者を引き継ぎますか？",
            isPresented: Binding(
                get: { selectedMember != nil },
                set: { if !$0 { selectedMember = nil } }
            ),
            titleVisibility: .visible,
            presenting: selectedMember
        ) { member in
            Button("\(member.displayName)に引き継ぐ") {
                selectedMember = nil
                onTransfer(member)
            }
            Button("キャンセル", role: .cancel) { selectedMember = nil }
        } message: { member in
            Text(member.managed == true
                ? "\(member.displayName)が新しい管理者になり、管理対象ではなくなります。相手の端末に復旧方法が用意されていない場合、引き継ぎは行われません。"
                : "\(member.displayName)が新しい管理者になります。")
        }
    }
}

// MARK: - Account, privacy, legal, and support

struct AccountPrivacyScreen: View {
    let profile: UserProfile
    let isWorking: Bool
    let onBack: () -> Void
    let onPhoneEnrollment: () -> Void
    let onRecoveryCode: () -> Void
    let onExport: () -> Void
    let onPrivacy: () -> Void
    let onTerms: () -> Void
    let onHelp: () -> Void
    let onDelete: () -> Void

    @State private var confirmsDeletion = false

    var body: some View {
        LifecyclePage(title: "アカウントとプライバシー", onBack: onBack) {
            VStack(spacing: 12) {
                LifecycleNavigationButton(
                    title: profile.hasPhone == true
                        ? "復旧用の電話番号を変更"
                        : "復旧用の電話番号を登録",
                    subtitle: "機種変更やログアウトに備えます",
                    icon: "phone.badge.checkmark",
                    action: onPhoneEnrollment
                )
                .accessibilityIdentifier("phone-enrollment-navigation-button")
                LifecycleNavigationButton(
                    title: "復旧コードを作る",
                    subtitle: "電話が使えないときの一回限りの予備キー",
                    icon: "key.horizontal.fill",
                    action: onRecoveryCode
                )
                .accessibilityIdentifier("recovery-code-navigation-button")
                LifecycleNavigationButton(
                    title: "自分のデータを書き出す",
                    subtitle: "プロフィール・回答・コメントを確認できます",
                    icon: "square.and.arrow.up",
                    action: onExport
                )
                .accessibilityIdentifier("account-export-navigation-button")
                LifecycleNavigationButton(
                    title: "プライバシー",
                    subtitle: "収集する情報と使い方",
                    icon: "hand.raised.fill",
                    action: onPrivacy
                )
                LifecycleNavigationButton(
                    title: "利用規約",
                    subtitle: "サービス利用時のお約束",
                    icon: "doc.text.fill",
                    action: onTerms
                )
                LifecycleNavigationButton(
                    title: "使い方・お問い合わせ",
                    subtitle: "設定をもう一度確認できます",
                    icon: "questionmark.circle.fill",
                    action: onHelp
                )
            }

            Button(role: .destructive) {
                confirmsDeletion = true
            } label: {
                Label("アカウントを削除", systemImage: "trash.fill")
                    .font(TsutsuuraTheme.bodyFont(size: 23, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(TsutsuuraTheme.coral)
                    .overlay(Rectangle().stroke(Color(hex: 0x7A3038), lineWidth: 3))
            }
            .disabled(isWorking)
            .accessibilityIdentifier("delete-account-button")
        }
        .confirmationDialog(
            "アカウントを完全に削除しますか？",
            isPresented: $confirmsDeletion,
            titleVisibility: .visible
        ) {
            Button("完全に削除", role: .destructive, action: onDelete)
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text(profile.familyRole == .owner
                ? "ほかの家族がいる場合は、先に管理者を引き継ぐ必要があります。削除した回答やコメントは元に戻せません。"
                : "自分の回答とコメント、すべてのログイン情報が削除されます。この操作は元に戻せません。")
        }
    }
}

struct AccountRecoveryScreen: View {
    @Binding var code: String
    let isSubmitting: Bool
    let onBack: () -> Void
    let onRecover: () -> Void

    @FocusState private var isCodeFocused: Bool

    private var normalizedCode: String {
        RecoveryCodeValidation.normalized(code)
    }

    var body: some View {
        LifecyclePage(title: "アカウントを復旧", onBack: onBack) {
            PaperPanel {
                VStack(alignment: .leading, spacing: 14) {
                    Label(
                        "保存しておいた復旧コードを入力",
                        systemImage: "key.horizontal.fill"
                    )
                    .font(TsutsuuraTheme.bodyFont(size: 23, weight: .bold))
                    .foregroundStyle(TsutsuuraTheme.ink)

                    Text("復旧コードは一回だけ使えます。復旧すると、紛失した端末を含む以前のログインはすべて無効になります。")
                        .font(TsutsuuraTheme.bodyFont(size: 18))
                        .foregroundStyle(TsutsuuraTheme.skyInk)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("復旧コード", text: $code, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.oneTimeCode)
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .foregroundStyle(TsutsuuraTheme.ink)
                        .padding(16)
                        .frame(minHeight: 58)
                        .background(Color.white)
                        .overlay(Rectangle().stroke(TsutsuuraTheme.cyanDark, lineWidth: 3))
                        .focused($isCodeFocused)
                        .accessibilityIdentifier("recovery-code-input")
                        .onChange(of: code) { _, value in
                            let clamped = UnicodeTextValidation.clamped(
                                value,
                                maximumLength: RecoveryCodeValidation.maximumLength
                            )
                            if clamped != value {
                                code = clamped
                            }
                        }

                    Text("40〜128文字の英数字・ハイフン・アンダースコア")
                        .font(TsutsuuraTheme.bodyFont(size: 16, weight: .semibold))
                        .foregroundStyle(TsutsuuraTheme.skyInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
            }

            TextRaisedButton(
                title: isSubmitting ? "復旧中…" : "このアカウントを復旧",
                icon: "arrow.clockwise.circle.fill",
                height: 68,
                fontSize: 24,
                action: onRecover
            )
            .disabled(
                !RecoveryCodeValidation.isValid(normalizedCode)
                    || isSubmitting
            )
            .accessibilityIdentifier("recover-account-submit-button")

            Text("コードがない場合は、電話番号でログインするか、家族の管理者にこのiPhone用の新しい設定案内を頼んでください。")
                .font(TsutsuuraTheme.bodyFont(size: 17))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { isCodeFocused = true }
    }
}

struct RecoveryCodeScreen: View {
    let issuedCode: AccountRecoveryCode?
    let isSubmitting: Bool
    let onBack: () -> Void
    let onCreate: () -> Void

    @State private var copyFeedback: String?

    var body: some View {
        LifecyclePage(title: "復旧コード", onBack: onBack) {
            PaperPanel {
                VStack(alignment: .leading, spacing: 12) {
                    Label("電話が使えないときの予備キー", systemImage: "lock.shield.fill")
                        .font(TsutsuuraTheme.bodyFont(size: 23, weight: .bold))
                        .foregroundStyle(TsutsuuraTheme.ink)
                    Text("安全な場所へ保存してください。一回使うか新しいコードを作ると無効になり、有効期限は30日です。コードを知る人はアカウントを復旧できます。")
                        .font(TsutsuuraTheme.bodyFont(size: 18))
                        .foregroundStyle(TsutsuuraTheme.skyInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
            }

            if let issuedCode {
                PaperPanel {
                    VStack(spacing: 16) {
                        Text(issuedCode.code)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(TsutsuuraTheme.ink)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("復旧コード")
                            .accessibilityValue(issuedCode.code)

                        Text("期限: \(Self.expiryFormatter.string(from: issuedCode.expiresAt))")
                            .font(TsutsuuraTheme.bodyFont(size: 17))
                            .foregroundStyle(TsutsuuraTheme.skyInk)

                        Button {
                            #if canImport(UIKit)
                            UIPasteboard.general.string = issuedCode.code
                            #endif
                            copyFeedback = "復旧コードをコピーしました"
                        } label: {
                            Label("コードをコピー", systemImage: "doc.on.doc.fill")
                                .font(TsutsuuraTheme.bodyFont(size: 21, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 58)
                                .background(TsutsuuraTheme.cyanDark)
                        }
                        .accessibilityIdentifier("copy-recovery-code-button")

                        if let copyFeedback {
                            Text(copyFeedback)
                                .font(TsutsuuraTheme.bodyFont(size: 17, weight: .bold))
                                .foregroundStyle(TsutsuuraTheme.greenDark)
                                .accessibilityAddTraits(.isStaticText)
                        }
                    }
                    .padding(24)
                }
            }

            TextRaisedButton(
                title: isSubmitting
                    ? "作成中…"
                    : (issuedCode == nil ? "復旧コードを作る" : "新しいコードに置き換える"),
                icon: "key.fill",
                height: 68,
                fontSize: 23,
                action: onCreate
            )
            .disabled(isSubmitting)
            .accessibilityIdentifier("create-recovery-code-button")
        }
        .onChange(of: issuedCode?.code) { _, _ in
            copyFeedback = nil
        }
    }

    private static let expiryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()
}

struct LifecycleNavigationButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PaperPanel {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(TsutsuuraTheme.cyanDark)
                        .frame(width: 38)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(TsutsuuraTheme.bodyFont(size: 22, weight: .bold))
                            .foregroundStyle(TsutsuuraTheme.ink)
                        Text(subtitle)
                            .font(TsutsuuraTheme.bodyFont(size: 16))
                            .foregroundStyle(TsutsuuraTheme.skyInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(TsutsuuraTheme.skyInk)
                        .accessibilityHidden(true)
                }
                .padding(18)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

struct AccountExportScreen: View {
    let export: AccountExport?
    let isLoading: Bool
    let onBack: () -> Void
    let onLoad: () -> Void

    private var exportText: String? {
        guard let export else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(export) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    var body: some View {
        LifecyclePage(title: "データを書き出す", onBack: onBack) {
            if let export, let exportText {
                PaperPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("書き出しの準備ができました", systemImage: "checkmark.circle.fill")
                            .font(TsutsuuraTheme.bodyFont(size: 22, weight: .bold))
                            .foregroundStyle(TsutsuuraTheme.greenDark)
                        Text("回答 \(export.answers.count)件・コメント \(export.comments.count)件")
                            .font(TsutsuuraTheme.bodyFont(size: 19))
                            .foregroundStyle(TsutsuuraTheme.ink)
                        Text("写真・音声は安全な取得先とファイル情報を含みます。共有先を選ぶ前に内容を確認してください。")
                            .font(TsutsuuraTheme.bodyFont(size: 17))
                            .foregroundStyle(TsutsuuraTheme.skyInk)
                    }
                    .padding(24)
                }

                ShareLink(
                    item: exportText,
                    subject: Text("つつうら 個人データ"),
                    message: Text("つつうらから書き出した個人データ（JSON）です。")
                ) {
                    Label("JSONを共有・保存", systemImage: "square.and.arrow.up")
                        .font(TsutsuuraTheme.bodyFont(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 68)
                        .background(TsutsuuraTheme.cyan)
                        .overlay(Rectangle().stroke(TsutsuuraTheme.cyanDark, lineWidth: 3))
                }
            } else {
                ProgressView(isLoading ? "データを準備しています…" : "")
                    .font(TsutsuuraTheme.bodyFont(size: 20))
                    .foregroundStyle(.white)
                    .tint(.white)

                if !isLoading {
                    TextRaisedButton(
                        title: "書き出しを準備",
                        icon: "arrow.clockwise",
                        action: onLoad
                    )
                }
            }
        }
        .task {
            guard export == nil, !isLoading else { return }
            onLoad()
        }
    }
}

enum InformationDocument: String, CaseIterable, Identifiable {
    case privacy
    case terms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacy: "プライバシー"
        case .terms: "利用規約"
        }
    }

    var sections: [(String, String)] {
        switch self {
        case .privacy:
            [
                ("取り扱う情報", "アカウント情報、家族構成、回答、コメント、選んだ写真・音声、通知用端末情報を、機能提供に必要な範囲で取り扱います。"),
                ("家族への公開", "回答・写真・音声・コメントは、参加している同じ家族のメンバーに表示されます。電話番号とログイン情報は家族には表示しません。"),
                ("安全と選択", "通信は暗号化し、端末用の認証情報は安全な保存領域を使います。設定からデータの書き出しとアカウント削除を依頼できます。"),
            ]
        case .terms:
            [
                ("大切に使う", "家族の同意とプライバシーを尊重し、本人の許可なく写真・音声・個人情報を投稿しないでください。"),
                ("禁止事項", "他者への嫌がらせ、なりすまし、不正アクセス、違法な内容、サービス運営を妨げる利用は禁止します。"),
                ("データと終了", "利用者は自分の投稿を編集・削除できます。家族の管理者は、管理者を引き継いだ後に退会できます。"),
            ]
        }
    }
}

struct InformationDocumentScreen: View {
    let document: InformationDocument
    let onBack: () -> Void

    var body: some View {
        LifecyclePage(title: document.title, onBack: onBack) {
            ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                PaperPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(section.0)
                            .font(TsutsuuraTheme.bodyFont(size: 23, weight: .bold))
                            .foregroundStyle(TsutsuuraTheme.ink)
                        Text(section.1)
                            .font(TsutsuuraTheme.bodyFont(size: 19))
                            .foregroundStyle(TsutsuuraTheme.skyInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(24)
                }
            }

            Text("最終更新: 2026年9月1日")
                .font(TsutsuuraTheme.bodyFont(size: 16))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Notification preferences

struct NotificationSettingsScreen: View {
    @Binding var preferences: NotificationPreferences
    let permissionState: PushAuthorizationState
    let isSaving: Bool
    let onBack: () -> Void
    let onRequestPermission: () -> Void
    let onOpenSystemSettings: () -> Void
    let onSave: () -> Void

    @State private var reminderDate = Date()

    var body: some View {
        LifecyclePage(title: "通知", onBack: onBack) {
            PaperPanel {
                VStack(alignment: .leading, spacing: 16) {
                    Text("端末の通知")
                        .font(TsutsuuraTheme.bodyFont(size: 23, weight: .bold))
                        .foregroundStyle(TsutsuuraTheme.ink)
                    Label(permissionDescription, systemImage: permissionIcon)
                        .font(TsutsuuraTheme.bodyFont(size: 19))
                        .foregroundStyle(TsutsuuraTheme.skyInk)

                    if permissionState == .notDetermined {
                        Text("許可すると、今日の質問や家族からの反応を見逃しにくくなります。通知は下で細かく選べます。")
                            .font(TsutsuuraTheme.bodyFont(size: 17))
                            .foregroundStyle(TsutsuuraTheme.skyInk)
                        TextRaisedButton(
                            title: "通知を許可する",
                            icon: "bell.badge.fill",
                            height: 58,
                            fontSize: 21,
                            action: onRequestPermission
                        )
                    } else if permissionState == .denied {
                        TextRaisedButton(
                            title: "iPhoneの設定を開く",
                            icon: "gearshape.fill",
                            height: 58,
                            fontSize: 21,
                            action: onOpenSystemSettings
                        )
                    }
                }
                .padding(24)
            }

            PaperPanel {
                VStack(spacing: 4) {
                    notificationToggle("家族の活動", isOn: $preferences.enabled)
                    notificationToggle("コメント", isOn: $preferences.commentsEnabled)
                    notificationToggle("いいね", isOn: $preferences.likesEnabled)
                    Divider()
                    notificationToggle("毎日の質問リマインダー", isOn: $preferences.dailyReminderEnabled)

                    if preferences.dailyReminderEnabled {
                        DatePicker(
                            "通知する時刻",
                            selection: $reminderDate,
                            displayedComponents: .hourAndMinute
                        )
                        .font(TsutsuuraTheme.bodyFont(size: 19))
                        .foregroundStyle(TsutsuuraTheme.ink)
                        .padding(.vertical, 10)
                        .onChange(of: reminderDate) { _, newValue in
                            preferences.dailyReminderTime = Self.timeFormatter
                                .string(from: newValue)
                        }
                    }

                    Divider()
                    Menu {
                        Button("ミュートしない") { preferences.muteUntil = nil }
                        Button("1時間") { preferences.muteUntil = Date().addingTimeInterval(3_600) }
                        Button("明日まで") { preferences.muteUntil = Date().addingTimeInterval(86_400) }
                        Button("1週間") { preferences.muteUntil = Date().addingTimeInterval(604_800) }
                    } label: {
                        HStack {
                            Text("一時的にミュート")
                            Spacer()
                            Text(muteDescription)
                                .foregroundStyle(TsutsuuraTheme.skyInk)
                            Image(systemName: "chevron.up.chevron.down")
                                .accessibilityHidden(true)
                        }
                        .font(TsutsuuraTheme.bodyFont(size: 19))
                        .foregroundStyle(TsutsuuraTheme.ink)
                        .frame(minHeight: 52)
                    }
                }
                .padding(22)
            }

            TextRaisedButton(
                title: isSaving ? "保存中…" : "通知設定を保存",
                icon: "checkmark",
                height: 66,
                fontSize: 24,
                action: onSave
            )
            .disabled(isSaving)
        }
        .onAppear {
            if let date = Self.timeFormatter.date(
                from: preferences.dailyReminderTime
            ) {
                reminderDate = date
            }
        }
    }

    @ViewBuilder
    private func notificationToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .font(TsutsuuraTheme.bodyFont(size: 19))
            .foregroundStyle(TsutsuuraTheme.ink)
            .tint(TsutsuuraTheme.greenDark)
            .frame(minHeight: 50)
    }

    private var permissionDescription: String {
        switch permissionState {
        case .notDetermined: "まだ許可を選んでいません"
        case .denied: "iPhoneの設定で通知がオフです"
        case .authorized: "iPhoneの通知が許可されています"
        case .provisional: "通知センターへ静かに届きます"
        case .ephemeral: "通知が一時的に許可されています"
        case .unavailable: "この端末では通知状態を確認できません"
        }
    }

    private var permissionIcon: String {
        permissionState == .denied ? "bell.slash.fill" : "bell.fill"
    }

    private var muteDescription: String {
        guard let muteUntil = preferences.muteUntil,
              muteUntil > Date() else { return "オフ" }
        return Self.muteFormatter.string(from: muteUntil) + "まで"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let muteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d H:mm"
        return formatter
    }()
}

// MARK: - Answer ownership

struct AnswerEditorScreen: View {
    let answer: Answer
    @Binding var bodyText: String
    let isSaving: Bool
    let onBack: () -> Void
    let onSave: () -> Void
    let onDeleteMedia: (AnswerMedia) -> Void
    let onDeleteAnswer: () -> Void

    @State private var confirmsAnswerDeletion = false
    @State private var pendingMediaDeletion: AnswerMedia?

    var body: some View {
        LifecyclePage(title: "回答を編集", onBack: onBack) {
            PaperPanel {
                VStack(alignment: .leading, spacing: 14) {
                    Text(answer.questionPrompt ?? "この日の回答")
                        .font(TsutsuuraTheme.bodyFont(size: 19, weight: .bold))
                        .foregroundStyle(TsutsuuraTheme.skyInk)

                    TextEditor(text: $bodyText)
                        .font(TsutsuuraTheme.bodyFont(size: 23))
                        .foregroundStyle(TsutsuuraTheme.ink)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 180)
                        .padding(10)
                        .background(.white.opacity(0.70))
                        .overlay(Rectangle().stroke(TsutsuuraTheme.skyInk, lineWidth: 2))
                        .onChange(of: bodyText) { _, value in
                            if UnicodeTextValidation.characterCount(value)
                                > AnswerDraft.maximumBodyCharacterCount {
                                bodyText = UnicodeTextValidation.clamped(
                                    value,
                                    maximumLength: AnswerDraft.maximumBodyCharacterCount
                                )
                            }
                        }

                    Text("\(UnicodeTextValidation.characterCount(bodyText)) / \(AnswerDraft.maximumBodyCharacterCount)文字")
                        .font(TsutsuuraTheme.bodyFont(size: 16))
                        .foregroundStyle(TsutsuuraTheme.skyInk)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(24)
            }

            if !answer.media.isEmpty {
                PaperPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("写真・音声")
                            .font(TsutsuuraTheme.bodyFont(size: 22, weight: .bold))
                            .foregroundStyle(TsutsuuraTheme.ink)
                        ForEach(Array(answer.media.enumerated()), id: \.element.id) { index, media in
                            HStack {
                                Label(
                                    media.kind == .photo
                                        ? "写真 \(index + 1)"
                                        : "音声の回答",
                                    systemImage: media.kind == .photo ? "photo" : "waveform"
                                )
                                .font(TsutsuuraTheme.bodyFont(size: 19))
                                .foregroundStyle(TsutsuuraTheme.ink)
                                Spacer()
                                Button("削除", role: .destructive) {
                                    pendingMediaDeletion = media
                                }
                                .font(TsutsuuraTheme.bodyFont(size: 18, weight: .bold))
                                .frame(minWidth: 60, minHeight: 44)
                            }
                        }
                    }
                    .padding(24)
                }
            }

            TextRaisedButton(
                title: isSaving ? "保存中…" : "変更を保存",
                icon: "checkmark",
                height: 66,
                fontSize: 24,
                action: onSave
            )
            .disabled(
                bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && answer.media.isEmpty
                || isSaving
            )

            Button("回答を削除", role: .destructive) {
                confirmsAnswerDeletion = true
            }
            .font(TsutsuuraTheme.bodyFont(size: 22, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(TsutsuuraTheme.coral)
            .disabled(isSaving)
        }
        .confirmationDialog(
            "この回答を削除しますか？",
            isPresented: $confirmsAnswerDeletion,
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive, action: onDeleteAnswer)
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("文章・写真・音声・いいね・コメントが削除されます。元に戻せません。")
        }
        .confirmationDialog(
            "この添付を削除しますか？",
            isPresented: Binding(
                get: { pendingMediaDeletion != nil },
                set: { if !$0 { pendingMediaDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingMediaDeletion
        ) { media in
            Button("削除", role: .destructive) {
                pendingMediaDeletion = nil
                onDeleteMedia(media)
            }
            Button("キャンセル", role: .cancel) { pendingMediaDeletion = nil }
        }
    }
}

struct CommentEditorScreen: View {
    let comment: Comment
    @Binding var bodyText: String
    let isSaving: Bool
    let onBack: () -> Void
    let onSave: () -> Void

    var body: some View {
        LifecyclePage(title: "コメントを編集", onBack: onBack) {
            PaperPanel {
                VStack(alignment: .leading, spacing: 12) {
                    Text("コメント")
                        .font(TsutsuuraTheme.bodyFont(size: 21, weight: .bold))
                        .foregroundStyle(TsutsuuraTheme.ink)
                    TextEditor(text: $bodyText)
                        .font(TsutsuuraTheme.bodyFont(size: 23))
                        .foregroundStyle(TsutsuuraTheme.ink)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 180)
                        .padding(10)
                        .background(.white.opacity(0.70))
                        .overlay(Rectangle().stroke(TsutsuuraTheme.skyInk, lineWidth: 2))
                        .onChange(of: bodyText) { _, value in
                            if UnicodeTextValidation.characterCount(value)
                                > Comment.maximumBodyCharacterCount {
                                bodyText = UnicodeTextValidation.clamped(
                                    value,
                                    maximumLength: Comment.maximumBodyCharacterCount
                                )
                            }
                        }
                    Text("\(UnicodeTextValidation.characterCount(bodyText)) / \(Comment.maximumBodyCharacterCount)文字")
                        .font(TsutsuuraTheme.bodyFont(size: 16))
                        .foregroundStyle(TsutsuuraTheme.skyInk)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(24)
            }

            TextRaisedButton(
                title: isSaving ? "保存中…" : "変更を保存",
                icon: "checkmark",
                height: 66,
                fontSize: 24,
                action: onSave
            )
            .disabled(
                bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || bodyText == comment.body
                    || isSaving
            )
        }
    }
}

// MARK: - History controls

struct HistoryFilterScreen: View {
    @Binding var query: HistoryQuery
    let members: [UserProfile]
    let onBack: () -> Void
    let onApply: () -> Void

    @State private var usesStartDate = false
    @State private var usesEndDate = false
    @State private var startDate = Date()
    @State private var endDate = Date()

    private var hasInvalidDateRange: Bool {
        usesStartDate && usesEndDate && startDate > endDate
    }

    var body: some View {
        LifecyclePage(title: "履歴を絞り込む", onBack: onBack) {
            PaperPanel {
                VStack(alignment: .leading, spacing: 14) {
                    Text("表示する回答")
                        .font(TsutsuuraTheme.bodyFont(size: 22, weight: .bold))
                        .foregroundStyle(TsutsuuraTheme.ink)
                    Picker("範囲", selection: $query.scope) {
                        Text("自分の回答").tag(HistoryScope.mine)
                        Text("家族全員").tag(HistoryScope.family)
                    }
                    .pickerStyle(.segmented)

                    if query.scope == .family {
                        Picker("家族", selection: $query.authorID) {
                            Text("全員").tag(String?.none)
                            ForEach(members) { member in
                                Text(member.displayName).tag(String?.some(member.id))
                            }
                        }
                        .font(TsutsuuraTheme.bodyFont(size: 19))
                    }
                }
                .padding(24)
            }

            PaperPanel {
                VStack(spacing: 10) {
                    Toggle("開始日を指定", isOn: $usesStartDate)
                    if usesStartDate {
                        DatePicker("開始日", selection: $startDate, displayedComponents: .date)
                    }
                    Toggle("終了日を指定", isOn: $usesEndDate)
                    if usesEndDate {
                        DatePicker("終了日", selection: $endDate, displayedComponents: .date)
                    }
                    if hasInvalidDateRange {
                        Text("開始日は終了日以前にしてください。")
                            .font(TsutsuuraTheme.bodyFont(size: 17, weight: .bold))
                            .foregroundStyle(TsutsuuraTheme.coral)
                            .accessibilityIdentifier("history-date-range-error")
                    }
                }
                .font(TsutsuuraTheme.bodyFont(size: 19))
                .foregroundStyle(TsutsuuraTheme.ink)
                .tint(TsutsuuraTheme.greenDark)
                .padding(24)
            }

            Button("条件をすべて解除") {
                query = HistoryQuery(scope: query.scope)
                usesStartDate = false
                usesEndDate = false
            }
            .font(TsutsuuraTheme.bodyFont(size: 20, weight: .bold))
            .foregroundStyle(.white)
            .frame(minHeight: 50)

            TextRaisedButton(
                title: "この条件で表示",
                icon: "line.3.horizontal.decrease.circle",
                height: 66,
                fontSize: 24
            ) {
                query.startDate = usesStartDate
                    ? Self.dateFormatter.string(from: startDate)
                    : nil
                query.endDate = usesEndDate
                    ? Self.dateFormatter.string(from: endDate)
                    : nil
                onApply()
            }
            .disabled(hasInvalidDateRange)
        }
        .onChange(of: query.scope) { _, scope in
            if scope == .mine {
                query.authorID = nil
            }
        }
        .onAppear {
            if let value = query.startDate,
               let date = Self.dateFormatter.date(from: value) {
                usesStartDate = true
                startDate = date
            }
            if let value = query.endDate,
               let date = Self.dateFormatter.date(from: value) {
                usesEndDate = true
                endDate = date
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

// MARK: - Help and onboarding replay

struct HelpScreen: View {
    let isManagedUser: Bool
    let onBack: () -> Void
    let onReplayOnboarding: () -> Void
    @State private var showsWalkthrough = false

    private var topics: [(String, String, String)] {
        var result = [
            ("回答する", "text.bubble.fill", "家族タブの「回答する」から、文章・声・写真で今日の出来事を残せます。送信後も自分の回答から編集・削除できます。"),
            ("声で回答する", "waveform", "音声認識とマイクの許可が必要です。許可しない場合も、いつでも文章で回答できます。"),
            ("写真を追加する", "photo.on.rectangle", "1回の回答に4枚まで。写真は同じ家族だけに表示されます。"),
            ("いいね・コメント", "heart.bubble.fill", "家族の回答に反応できます。自分のコメントは編集・削除できます。困った内容は報告できます。"),
            ("通知", "bell.fill", "質問、コメント、いいねを個別に選べます。通知を一時的に止めることもできます。"),
        ]
        if isManagedUser {
            result.append(("端末を復旧する", "iphone.gen3", "先に設定で復旧コードを作って安全な場所に保存します。コードがない場合は、ご家族の管理者に新しい一回限りの設定案内を送ってもらってください。"))
        } else {
            result.append(("家族の端末を復旧する", "person.badge.key.fill", "家族の設定で対象の方を選び、「復旧用の設定案内を作る」を使います。古い未使用案内は無効になります。"))
        }
        return result
    }

    var body: some View {
        LifecyclePage(title: "使い方・ヘルプ", onBack: onBack) {
            ForEach(Array(topics.enumerated()), id: \.offset) { _, topic in
                PaperPanel {
                    HStack(alignment: .top, spacing: 15) {
                        Image(systemName: topic.1)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(TsutsuuraTheme.cyanDark)
                            .frame(width: 38)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(topic.0)
                                .font(TsutsuuraTheme.bodyFont(size: 22, weight: .bold))
                                .foregroundStyle(TsutsuuraTheme.ink)
                            Text(topic.2)
                                .font(TsutsuuraTheme.bodyFont(size: 18))
                                .foregroundStyle(TsutsuuraTheme.skyInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(22)
                }
            }

            TextRaisedButton(
                title: "最初の案内をもう一度見る",
                icon: "play.circle.fill",
                height: 64,
                fontSize: 22,
                action: {
                    onReplayOnboarding()
                    showsWalkthrough = true
                }
            )

            Link(destination: URL(string: "mailto:support@toshizo.link?subject=Tsutsuura%20Support")!) {
                Label("メールで問い合わせる", systemImage: "envelope.fill")
                    .font(TsutsuuraTheme.bodyFont(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .overlay(Rectangle().stroke(.white, lineWidth: 2))
            }
        }
        .sheet(isPresented: $showsWalkthrough) {
            OnboardingReplaySheet {
                showsWalkthrough = false
            }
        }
    }
}

private struct OnboardingReplaySheet: View {
    let onFinished: () -> Void
    @State private var page = 0

    private let pages: [(String, String, String)] = [
        ("家族で一日ひとつ", "sun.max.fill", "毎日の質問に答えると、離れていても小さな出来事を分かち合えます。"),
        ("好きな方法で回答", "text.bubble.fill", "文章・声・写真から、その日に合う方法を選べます。"),
        ("家族だけで会話", "person.3.fill", "回答へのいいねやコメントは、同じ家族の中だけに表示されます。"),
        ("困ったときも安心", "lifepreserver.fill", "設定のヘルプ、通知、復旧、データ管理はいつでも設定から開けます。"),
    ]

    var body: some View {
        ZStack {
            DottedBackdrop()
            VStack(spacing: 24) {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        VStack(spacing: 24) {
                            Image(systemName: item.1)
                                .font(.system(size: 58, weight: .semibold))
                                .foregroundStyle(TsutsuuraTheme.cyan)
                                .accessibilityHidden(true)
                            Text(item.0)
                                .font(TsutsuuraTheme.font(38))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                            Text(item.2)
                                .font(TsutsuuraTheme.bodyFont(size: 22))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(36)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                TextRaisedButton(
                    title: page == pages.count - 1 ? "案内を閉じる" : "次へ",
                    icon: page == pages.count - 1 ? "checkmark" : "arrow.right",
                    height: 64,
                    fontSize: 23
                ) {
                    if page == pages.count - 1 {
                        onFinished()
                    } else {
                        page += 1
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 30)
            }
        }
        .presentationDragIndicator(.visible)
    }
}
