import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Shared lifecycle page

struct LifecyclePage<Content: View>: View {
    let title: String
    let onBack: () -> Void
    var showsBackButton = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            DottedBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) {
                            if showsBackButton {
                                backButton
                                Spacer(minLength: 12)
                            }
                            pageTitle
                                .fixedSize(horizontal: true, vertical: true)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            if showsBackButton { backButton }
                            pageTitle
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
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
    }

    private var backButton: some View {
        Button(action: onBack) {
            Label {
                Text("戻る")
                    .font(TsutsuuraTheme.displayFont(24))
            } icon: {
                Image(systemName: "chevron.left")
            }
                .font(TsutsuuraTheme.bodyFont(size: 24))
                .foregroundStyle(.white)
                .fixedSize(horizontal: true, vertical: true)
                .frame(minWidth: 64, minHeight: 52, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("lifecycle-back-button")
    }

    private var pageTitle: some View {
        Text(title)
            .font(TsutsuuraTheme.displayFont(34))
            .foregroundStyle(.white)
            .accessibilityAddTraits(.isHeader)
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
                .font(TsutsuuraTheme.displayFont(20))
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
                            .font(TsutsuuraTheme.displayFont(24))
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
                Label {
                    Text("この家族を削除")
                        .font(TsutsuuraTheme.displayFont(23))
                } icon: {
                    Image(systemName: "person.crop.circle.badge.minus")
                }
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
            Text("引き継ぎ後は、選んだ方が家族名の変更や家族の削除を管理します。相手のiPhone設定を完了し、その端末でメールを登録するか復旧コードを保存しておいてください。管理対象の方は、引き継ぎと同時に独立したアカウントになります。")
                .font(TsutsuuraTheme.bodyFont(size: 20))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            if candidates.isEmpty {
                PaperPanel {
                    Text("引き継げる家族がまだいません。")
                        .font(TsutsuuraTheme.displayFont(22))
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
    let onEmailEnrollment: () -> Void
    let onRecoveryCode: () -> Void
    let onExport: () -> Void
    let onPrivacy: () -> Void
    let onTerms: () -> Void
    let onHelp: () -> Void
    let onDelete: () -> Void

    @State private var confirmsDeletion = false

    var body: some View {
        LifecyclePage(title: "機種変更・データ", onBack: onBack) {
            Text("必要なときだけ開く設定です。毎日の回答は「戻る」から続けられます。")
                .font(TsutsuuraTheme.bodyFont(size: 20))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                settingsGroupTitle("新しいiPhoneに備える")
                LifecycleNavigationButton(
                    title: profile.hasEmail == true
                        ? "登録したメールを変える"
                        : "メールを登録する",
                    subtitle: profile.email.map { "登録済み：\($0)" }
                        ?? "メールの確認番号で、同じアカウントに戻れます",
                    icon: "envelope.fill",
                    action: onEmailEnrollment
                )
                .accessibilityIdentifier("email-enrollment-navigation-button")
                LifecycleNavigationButton(
                    title: "予備の復旧コードを作る",
                    subtitle: "メールが使えないときに戻るための番号",
                    icon: "key.horizontal.fill",
                    action: onRecoveryCode
                )
                .accessibilityIdentifier("recovery-code-navigation-button")
                LifecycleNavigationButton(
                    title: "自分の記録を保存する",
                    subtitle: "これまでの回答やコメントをファイルに保存",
                    icon: "square.and.arrow.up",
                    action: onExport
                )
                .accessibilityIdentifier("account-export-navigation-button")
            }

            DisclosureGroup {
                VStack(spacing: 12) {
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
                .padding(.top, 12)
            } label: {
                Text("利用規約・お問い合わせ")
                    .font(TsutsuuraTheme.bodyFont(size: 22, weight: .semibold))
                    .frame(minHeight: 56)
            }
            .tint(.white)
            .foregroundStyle(.white)

            DisclosureGroup {
            Text("使うのをやめて、記録もすべて消したい場合だけ選んでください。")
                .font(TsutsuuraTheme.bodyFont(size: 19))
                .foregroundStyle(.white)
                .padding(.vertical, 12)
            Button(role: .destructive) {
                confirmsDeletion = true
            } label: {
                Label {
                    Text("アカウントを削除")
                        .font(TsutsuuraTheme.displayFont(23))
                } icon: {
                    Image(systemName: "trash.fill")
                }
                    .font(TsutsuuraTheme.bodyFont(size: 23, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(TsutsuuraTheme.coral)
                    .overlay(Rectangle().stroke(Color(hex: 0x7A3038), lineWidth: 3))
            }
            .disabled(isWorking)
            .accessibilityIdentifier("delete-account-button")
            } label: {
                Text("アカウントの削除")
                    .font(TsutsuuraTheme.bodyFont(size: 22))
                    .frame(minHeight: 56)
            }
            .tint(.white)
            .foregroundStyle(.white)
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

    private func settingsGroupTitle(_ title: String) -> some View {
        Text(title)
            .font(TsutsuuraTheme.bodyFont(size: 24, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
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
                    Label {
                        Text("保存しておいた復旧コードを入力")
                            .font(TsutsuuraTheme.displayFont(23))
                    } icon: {
                        Image(systemName: "key.horizontal.fill")
                    }
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

            Text("コードがない場合は、登録したメールでログインするか、家族の管理者にこのiPhone用の新しい設定案内を頼んでください。")
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
                    Label {
                        Text("メールが使えないときの予備キー")
                            .font(TsutsuuraTheme.displayFont(23))
                    } icon: {
                        Image(systemName: "lock.shield.fill")
                    }
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
                            Label {
                                Text("コードをコピー")
                                    .font(TsutsuuraTheme.displayFont(21))
                            } icon: {
                                Image(systemName: "doc.on.doc.fill")
                            }
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
                            .font(TsutsuuraTheme.bodyFont(size: 22, weight: .semibold))
                            .foregroundStyle(TsutsuuraTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(subtitle)
                            .font(TsutsuuraTheme.bodyFont(size: 18))
                            .foregroundStyle(TsutsuuraTheme.skyInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(TsutsuuraTheme.skyInk)
                        .accessibilityHidden(true)
                }
                .padding(20)
                .frame(minHeight: 88)
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
    @Environment(\.colorSchemeContrast) private var contrast
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
                        Label {
                            Text("書き出しの準備ができました")
                                .font(TsutsuuraTheme.displayFont(22))
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                        }
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
                    Label {
                        Text("JSONを共有・保存")
                            .font(TsutsuuraTheme.displayFont(24))
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                        .font(TsutsuuraTheme.bodyFont(24))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 68)
                        .background(TsutsuuraTheme.actionFill(TsutsuuraTheme.cyan, contrast: contrast))
                        .overlay(Rectangle().stroke(TsutsuuraTheme.cyanDark, lineWidth: 3))
                }
            } else if isLoading {
                ProgressView("データを準備しています…")
                    .font(TsutsuuraTheme.bodyFont(size: 20))
                    .foregroundStyle(.white)
                    .tint(.white)
            } else {
                TextRaisedButton(
                    title: "書き出しを準備",
                    icon: "arrow.clockwise",
                    action: onLoad
                )
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
    case licenses

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacy: "プライバシー"
        case .terms: "利用規約"
        case .licenses: "ライセンス"
        }
    }

    var sections: [(String, String)] {
        switch self {
        case .licenses:
            ["ThirdPartyNotices", "KaisotaiNotice", "MaterialDesignIconsLicense"].map { name in
                let url = Bundle.main.url(forResource: name, withExtension: "txt")
                    ?? Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "ThirdPartyNotices")
                return (name == "MaterialDesignIconsLicense" ? "Apache License 2.0" : name == "KaisotaiNotice" ? "廻想体 ネクスト UP" : "使用している素材", url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "廻想体の利用条件: https://moji-waku.com/mj_work_license/\nMaterial Design Icons: https://www.apache.org/licenses/LICENSE-2.0")
            }

        case .privacy:
            [
                ("取り扱う情報", "アカウント情報、家族構成、回答、コメント、選んだ写真・音声、通知用端末情報を、機能提供に必要な範囲で取り扱います。"),
                ("家族への公開", "回答・写真・音声・コメントは、参加している同じ家族のメンバーに表示されます。メールアドレスとログイン情報は家族には表示しません。"),
                ("安全と選択", "通信は暗号化し、端末用の認証情報は安全な保存領域を使います。設定からデータの書き出しとアカウント削除を依頼できます。"),
            ]
        case .terms:
            [
                ("大切に使う", "家族の同意とプライバシーを尊重し、本人の許可なく写真・音声・個人情報を投稿しないでください。"),
                ("禁止事項", "他者への嫌がらせ、なりすまし、不正アクセス、違法な内容、サービス運営を妨げる利用は禁止します。"),
                ("データと終了", "回答やコメントは、送る前に内容を確認してください。アカウントは設定から削除できます。ほかの家族がいる場合、管理者は先に管理を引き継いでください。"),
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
                            .font(TsutsuuraTheme.displayFont(23))
                            .foregroundStyle(TsutsuuraTheme.ink)
                        Text(section.1)
                            .font(TsutsuuraTheme.bodyFont(size: 19))
                            .foregroundStyle(TsutsuuraTheme.skyInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(24)
                }
            }

            if document == .privacy {
                Link(destination: URL(string: "https://toshizo.link/tsutsuura-privacy.html")!) {
                    Label("プライバシーポリシーを読む", systemImage: "safari")
                        .font(TsutsuuraTheme.bodyFont(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .overlay(Rectangle().stroke(.white, lineWidth: 2))
                }
                .accessibilityHint("ブラウザで全文を開きます")
                .accessibilityIdentifier("privacy-policy-link")
            }

            Text(document == .privacy ? "最終更新: 2026年9月5日" : "最終更新: 2026年9月1日")
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

    private var familyNotices: Binding<Bool> {
        Binding(
            get: { preferences.enabled || preferences.commentsEnabled || preferences.likesEnabled },
            set: { receivesNotices in
                preferences.enabled = receivesNotices
                preferences.commentsEnabled = receivesNotices
                preferences.likesEnabled = receivesNotices
            }
        )
    }

    private var pausesUntilTomorrow: Binding<Bool> {
        Binding(
            get: { (preferences.muteUntil ?? .distantPast) > Date() },
            set: { pauses in
                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(86_400)
                preferences.muteUntil = pauses
                    ? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
                    : nil
            }
        )
    }

    var body: some View {
        LifecyclePage(title: "お知らせを選ぶ", onBack: onBack) {
            PaperPanel {
                VStack(alignment: .leading, spacing: 16) {
                    Text("iPhoneのお知らせ")
                        .font(TsutsuuraTheme.bodyFont(size: 23, weight: .semibold))
                        .foregroundStyle(TsutsuuraTheme.ink)
                    Label(permissionDescription, systemImage: permissionIcon)
                        .font(TsutsuuraTheme.bodyFont(size: 21))
                        .foregroundStyle(TsutsuuraTheme.skyInk)
                        .fixedSize(horizontal: false, vertical: true)

                    if permissionState == .notDetermined {
                        Text("許可すると、アプリを閉じていてもお知らせが届きます。許可しなくても使えます。")
                            .font(TsutsuuraTheme.bodyFont(size: 20))
                            .foregroundStyle(TsutsuuraTheme.skyInk)
                        TextRaisedButton(
                            title: "お知らせを受け取る",
                            icon: "bell.fill",
                            height: 60,
                            fontSize: 22,
                            action: onRequestPermission
                        )
                    } else if permissionState == .denied {
                        TextRaisedButton(
                            title: "iPhoneの設定を開く",
                            icon: "gearshape.fill",
                            height: 60,
                            fontSize: 22,
                            action: onOpenSystemSettings
                        )
                    }
                }
                .padding(24)
            }

            PaperPanel {
                VStack(alignment: .leading, spacing: 16) {
                    notificationToggle("今日の質問", isOn: $preferences.dailyReminderEnabled)
                        .accessibilityIdentifier("notification-daily-toggle")
                    Text("質問は日本時間の朝9時〜夜7時に公開します。質問のお知らせは、この端末の地域の日中に届きます。海外では時差があるため、ホームで時刻を確認できます。")
                        .font(TsutsuuraTheme.bodyFont(size: 20))
                        .foregroundStyle(TsutsuuraTheme.skyInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    notificationToggle("家族からのお知らせ", isOn: familyNotices)
                        .accessibilityIdentifier("notification-family-toggle")
                    Text("家族の回答、いいね、コメントが届いたときにお知らせします。")
                        .font(TsutsuuraTheme.bodyFont(size: 20))
                        .foregroundStyle(TsutsuuraTheme.skyInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(24)
            }

            DisclosureGroup {
                PaperPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        notificationToggle("家族が回答したとき", isOn: $preferences.enabled)
                        notificationToggle("コメントが届いたとき", isOn: $preferences.commentsEnabled)
                        notificationToggle("いいねが届いたとき", isOn: $preferences.likesEnabled)
                        Divider()
                        notificationToggle("明日の朝9時まで休む", isOn: pausesUntilTomorrow)
                        if let muteUntil = preferences.muteUntil, muteUntil > Date() {
                            Text("\(Self.muteFormatter.string(from: muteUntil))まで、お知らせを止めています。")
                                .font(TsutsuuraTheme.bodyFont(size: 19))
                                .foregroundStyle(TsutsuuraTheme.skyInk)
                        }
                    }
                    .padding(22)
                }
                .padding(.top, 12)
            } label: {
                Text("お知らせを細かく選ぶ")
                    .font(TsutsuuraTheme.bodyFont(size: 22, weight: .semibold))
                    .frame(minHeight: 56)
            }
            .tint(.white)
            .foregroundStyle(.white)
            .accessibilityIdentifier("notification-details")

            TextRaisedButton(
                title: isSaving ? "保存中…" : "この設定を保存",
                icon: "checkmark",
                height: 68,
                fontSize: 25,
                action: onSave
            )
            .disabled(isSaving)
            .accessibilityIdentifier("notification-save-button")
        }
    }

    private func notificationToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .font(TsutsuuraTheme.bodyFont(size: 22, weight: .semibold))
            .foregroundStyle(TsutsuuraTheme.ink)
            .tint(TsutsuuraTheme.greenDark)
            .frame(minHeight: 58)
    }

    private var permissionDescription: String {
        switch permissionState {
        case .notDetermined: "お知らせを受け取るか選べます"
        case .denied: "iPhoneでお知らせがオフになっています"
        case .authorized: "お知らせを受け取れます"
        case .provisional: "音を鳴らさずに届きます"
        case .ephemeral: "一時的にお知らせを受け取れます"
        case .unavailable: "この端末では設定を確認できません"
        }
    }

    private var permissionIcon: String {
        permissionState == .denied ? "bell.slash.fill" : "bell.fill"
    }

    private static let muteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日 H:mm"
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
                            .font(TsutsuuraTheme.displayFont(22))
                            .foregroundStyle(TsutsuuraTheme.ink)
                        ForEach(Array(answer.media.enumerated()), id: \.element.id) { index, media in
                            HStack {
                                Label {
                                    Text(media.kind == .photo
                                        ? "写真 \(index + 1)"
                                        : "音声の回答")
                                        .font(TsutsuuraTheme.displayFont(19))
                                } icon: {
                                    Image(systemName: media.kind == .photo ? "photo" : "waveform")
                                }
                                .font(TsutsuuraTheme.bodyFont(size: 19))
                                .foregroundStyle(TsutsuuraTheme.ink)
                                Spacer()
                                Button("削除", role: .destructive) {
                                    pendingMediaDeletion = media
                                }
                                .font(TsutsuuraTheme.displayFont(18))
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
            .font(TsutsuuraTheme.displayFont(22))
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

struct HistoryFilterScreen: View {
    @Binding var query: HistoryQuery
    let members: [UserProfile]
    let onBack: () -> Void
    let onApply: () -> Void

    @State private var draftQuery: HistoryQuery
    @State private var usesStartDate = false
    @State private var usesEndDate = false
    @State private var startDate = Date()
    @State private var endDate = Date()

    init(
        query: Binding<HistoryQuery>,
        members: [UserProfile],
        onBack: @escaping () -> Void,
        onApply: @escaping () -> Void
    ) {
        _query = query
        _draftQuery = State(initialValue: query.wrappedValue)
        self.members = members
        self.onBack = onBack
        self.onApply = onApply
    }

    private var hasInvalidDateRange: Bool {
        usesStartDate && usesEndDate
            && Calendar.current.compare(startDate, to: endDate, toGranularity: .day)
                == .orderedDescending
    }

    var body: some View {
        LifecyclePage(title: "履歴を絞り込む", onBack: onBack) {
            PaperPanel {
                VStack(alignment: .leading, spacing: 14) {
                    Text("表示する回答")
                        .font(TsutsuuraTheme.displayFont(22))
                        .foregroundStyle(TsutsuuraTheme.ink)
                    Picker("範囲", selection: $draftQuery.scope) {
                        Text("自分の回答").tag(HistoryScope.mine)
                        Text("家族全員").tag(HistoryScope.family)
                    }
                    .pickerStyle(.segmented)

                    if draftQuery.scope == .family {
                        Picker("家族", selection: $draftQuery.authorID) {
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
                        .font(TsutsuuraTheme.displayFont(19))
                    if usesStartDate {
                        DatePicker("開始日", selection: $startDate, displayedComponents: .date)
                    }
                    Toggle("終了日を指定", isOn: $usesEndDate)
                        .font(TsutsuuraTheme.displayFont(19))
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
                draftQuery = HistoryQuery(scope: draftQuery.scope)
                usesStartDate = false
                usesEndDate = false
            }
            .font(TsutsuuraTheme.displayFont(20))
            .foregroundStyle(.white)
            .frame(minHeight: 50)

            TextRaisedButton(
                title: "この条件で表示",
                icon: "line.3.horizontal.decrease.circle",
                height: 66,
                fontSize: 24
            ) {
                draftQuery.startDate = usesStartDate
                    ? Self.dateFormatter.string(from: startDate)
                    : nil
                draftQuery.endDate = usesEndDate
                    ? Self.dateFormatter.string(from: endDate)
                    : nil
                query = draftQuery
                onApply()
            }
            .disabled(hasInvalidDateRange)
        }
        .onChange(of: draftQuery.scope) { _, scope in
            if scope == .mine {
                draftQuery.authorID = nil
            }
        }
        .onAppear {
            if let value = draftQuery.startDate,
               let date = Self.dateFormatter.date(from: value) {
                usesStartDate = true
                startDate = date
            }
            if let value = draftQuery.endDate,
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
    var onLicenses: (() -> Void)? = nil

    private let essentials: [(String, String, String)] = [
        ("1. 今日の質問を見る", "sun.max.fill", "家族みんなで、日本の日付の質問に答えます。日本時間の朝9時〜夜7時に公開し、その日の出来事を聞く質問は日本時間の夕方5時以降です。ホームには海外の端末の時刻も表示します。"),
        ("2. 回答を送る", "text.bubble.fill", "「回答する」を押し、ひとこと書くか、声で話します。送る前に内容を確認しましょう。送った回答は編集・削除できません。"),
        ("3. 家族の回答を読む", "person.3.fill", "「家族」でみんなの回答を、「あなた」で自分の回答を読めます。上の四角は、家族ひとりにつきひとつ。日本の日付で同じ質問に答えた人の分に色がつきます。"),
    ]

    private var moreTopics: [(String, String, String)] {
        var topics = [
            ("報告・ブロック", "hand.raised.fill", "回答やコメントの「報告・ブロック」から、困った投稿を運営者に報告し、非表示にできます。写真・音声もまとめて対象になります。ブロックした人は「設定」で確認・解除できます。"),
            ("いいね・コメント", "heart.fill", "家族の回答に「いいね」を押したり、「コメント」から返事を書いたりできます。同じ家族の中だけに表示されます。"),
            ("声で回答する", "waveform", "「声で回答」を押し、マイクと音声認識を許可します。話した言葉が文字になるので、送る前に確認できます。文字で入力することもできます。"),
            ("写真を追加する", "photo.on.rectangle", "回答には写真を4枚まで添えられます。写真も同じ家族だけに見えます。"),
            ("あなたのしるし", "pencil.tip.crop.circle", "はじめに全員が、自分のしるしを指でかきます。丸や線だけでも大丈夫です。かいたしるしは名前の横に表示され、「設定」の「あなたのしるし」でかき直せます。"),
            ("前の回答を探す", "magnifyingglass", "「あなた」の検索欄に、質問や回答に入っている言葉を入れます。検索をやめるときは、入力した言葉を消します。"),
            ("お知らせを選ぶ", "bell.fill", "「設定」から「お知らせを選ぶ」を開きます。今日の質問や、家族からの反応を受け取るか選べます。通知を許可しなくてもアプリは使えます。"),
            ("前の画面に戻る", "chevron.left", "「戻る」を押します。画面の左端から右へ指を動かして戻ることもできます。"),
        ]
        topics.append(isManagedUser
            ? ("iPhoneを変えるとき", "iphone", "「設定」の「機種変更・データの保存」でメールを登録するか、復旧コードを作って保存します。難しいときは、ご家族に新しい設定番号を送ってもらってください。")
            : ("家族のiPhoneを準備する", "iphone", "「設定」の「家族を追加・確認する」で、ご家族を選びます。機種変更のときは「復旧用の設定案内を作る」から、新しい設定番号を送れます。"))
        return topics
    }

    var body: some View {
        LifecyclePage(title: "使い方", onBack: onBack) {
            TextRaisedButton(
                title: "ひとつずつ案内を見る",
                icon: "play.circle.fill",
                height: 68,
                fontSize: 24,
                action: onReplayOnboarding
            )
            .accessibilityIdentifier("replay-essentials-button")

            ForEach(Array(essentials.enumerated()), id: \.offset) { _, topic in
                topicCard(topic)
            }

            DisclosureGroup {
                VStack(spacing: 18) {
                    ForEach(Array(moreTopics.enumerated()), id: \.offset) { _, topic in
                        topicCard(topic)
                    }
                }
                .padding(.top, 16)
            } label: {
                Text("写真・声・設定など")
                    .font(TsutsuuraTheme.bodyFont(size: 24, weight: .semibold))
                    .frame(minHeight: 58)
            }
            .tint(.white)
            .foregroundStyle(.white)

            if let onLicenses {
                LifecycleNavigationButton(title: "ライセンス", subtitle: "文字やアイコンなどの権利表示", icon: "doc.text", action: onLicenses)
                    .accessibilityIdentifier("licenses-button")
            }
            Link(destination: URL(string: "mailto:general@toshizo.link?subject=Tsutsuura%20Support")!) {
                Label("メールで問い合わせる", systemImage: "envelope.fill")
                    .font(TsutsuuraTheme.bodyFont(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .overlay(Rectangle().stroke(.white, lineWidth: 2))
            }
        }

    }

    private func topicCard(_ topic: (String, String, String)) -> some View {
        PaperPanel {
            HStack(alignment: .top, spacing: 15) {
                Image(systemName: topic.1)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(TsutsuuraTheme.cyanDark)
                    .frame(width: 38)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 10) {
                    Text(topic.0)
                        .font(TsutsuuraTheme.bodyFont(size: 24, weight: .semibold))
                        .foregroundStyle(TsutsuuraTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(topic.2)
                        .font(TsutsuuraTheme.bodyFont(size: 21))
                        .foregroundStyle(TsutsuuraTheme.skyInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(22)
        }
    }
}

/// Shared by first setup and Help after the required personal mark is saved.
struct EssentialsWalkthroughScreen: View {
    let onBack: () -> Void
    let onFinished: () -> Void
    var onPersonalize: (() -> Void)? = nil
    let permissionState: PushAuthorizationState
    let isRequestingPermission: Bool
    let onRequestPermission: () -> Void
    let onOpenSystemSettings: () -> Void
    var completionTitle = "つつうらをはじめる"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding private var page: Int
    @AccessibilityFocusState private var focusedPage: Int?

    init(
        page: Binding<Int>,
        onBack: @escaping () -> Void,
        onFinished: @escaping () -> Void,
        onPersonalize: (() -> Void)? = nil,
        permissionState: PushAuthorizationState,
        isRequestingPermission: Bool,
        onRequestPermission: @escaping () -> Void,
        onOpenSystemSettings: @escaping () -> Void,
        completionTitle: String = "つつうらをはじめる"
    ) {
        _page = page
        self.onBack = onBack
        self.onFinished = onFinished
        self.onPersonalize = onPersonalize
        self.permissionState = permissionState
        self.isRequestingPermission = isRequestingPermission
        self.onRequestPermission = onRequestPermission
        self.onOpenSystemSettings = onOpenSystemSettings
        self.completionTitle = completionTitle
    }

    private let pages: [(title: String, icon: String, body: String, example: String, note: String)] = [
        ("一日ひとつ、家族に近況を", "sun.max.fill", "日本時間の朝9時〜夜7時に、家族みんなへ同じ質問を公開します。海外では、ホームにこの端末の時刻も表示します。", "最近、おいしかったものは？", "その日の出来事を聞く質問は、日本時間の夕方5時以降です。質問のお知らせは、この端末の地域の日中に届きます。"),
        ("ひとことから、答えてみる", "text.bubble.fill", "「回答する」を押して、文字を入力するか、声で話します。写真も添えられます。", "家族と食べたおにぎりです。", "送る前に確認しましょう。送った回答は編集・削除できません。"),
        ("「家族」と「あなた」を選ぶ", "person.3.fill", "「家族」はみんなの回答。「あなた」は自分の回答です。家族に、いいねやコメントで返事をしましょう。", "四角ひとつが、家族ひとり", "上の四角は、日本の日付で同じ質問に答えた人の分に色がつきます。回答は同じ家族だけに見えます。"),
        ("準備ができました", "checkmark.circle.fill", "わからなくなったら、「設定」の「使い方を見る」で、いつでもこの案内を読めます。", "あなたがかいた「しるし」が目印です", "名前の横のしるしは、あなたがかいた絵です。「設定」から、いつでもかき直せます。"),
    ]

    var body: some View {
        ZStack {
            DottedBackdrop()
            VStack(spacing: 16) {
                HStack {
                    if page > 0 {
                        Button(action: onBack) {
                            Label("前へ", systemImage: "chevron.left")
                                .frame(minHeight: 52)
                        }
                        .accessibilityIdentifier("essentials-previous-button")
                    }
                    Spacer()
                    Text("\(page + 1) / \(pages.count)")
                        .accessibilityLabel("案内、\(pages.count)つのうち\(page + 1)つ目")
                    Spacer()
                    Button("あとで見る", action: onFinished)
                        .frame(minHeight: 52)
                        .accessibilityIdentifier("onboarding-replay-close-button")
                }
                .font(TsutsuuraTheme.bodyFont(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)

                GeometryReader { viewport in
                    ZStack(alignment: .topLeading) {
                        ForEach(pages.indices, id: \.self) { index in
                            guidePage(at: index)
                                .frame(width: viewport.size.width, height: viewport.size.height)
                                .offset(x: CGFloat(index - page) * viewport.size.width)
                                .allowsHitTesting(page == index)
                                .accessibilityHidden(page != index)
                        }
                    }
                    .clipped()
                    .animation(
                        TsutsuuraMotion.respectingReduceMotion(reduceMotion, TsutsuuraMotion.navigation),
                        value: page
                    )
                }

                TextRaisedButton(
                    title: page == pages.count - 1 ? completionTitle : "次へ",
                    icon: page == pages.count - 1 ? "checkmark" : "arrow.right",
                    height: 68,
                    fontSize: 25
                ) {
                    if page == pages.count - 1 { onFinished() }
                    else { changePage(to: page + 1) }
                }
                .accessibilityIdentifier("essentials-next-button")
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: page) { _, newPage in
            focusedPage = newPage
        }
    }

    private func guidePage(at index: Int) -> some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: pages[index].icon)
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(TsutsuuraTheme.cyan)
                    .accessibilityHidden(true)
                Text(pages[index].title)
                    .font(TsutsuuraTheme.bodyFont(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($focusedPage, equals: index)
                    .accessibilityIdentifier("essentials-title")
                Text(pages[index].body)
                    .font(TsutsuuraTheme.bodyFont(size: 24))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(5)

                if index == pages.count - 1 {
                    notificationOptIn
                }

                PaperPanel {
                    VStack(alignment: .leading, spacing: 18) {
                        if index < 2 {
                            Text(index == 0 ? "質問の例" : "回答の例")
                                .font(TsutsuuraTheme.bodyFont(size: 19, weight: .semibold))
                                .foregroundStyle(TsutsuuraTheme.cyanDark)
                        }
                        Text(pages[index].example)
                            .font(TsutsuuraTheme.bodyFont(size: 25, weight: .semibold))
                            .foregroundStyle(TsutsuuraTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if index == 2 {
                            HStack(spacing: 10) {
                                ForEach(0..<3) { memberIndex in
                                    Rectangle()
                                        .fill(memberIndex < 2 ? TsutsuuraTheme.greenDark : TsutsuuraTheme.skyMuted.opacity(0.25))
                                        .frame(height: 40)
                                        .overlay {
                                            if memberIndex < 2 {
                                                Image(systemName: "checkmark")
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                }
                            }
                            .accessibilityLabel("3人家族の例。2人が回答しました")
                        }
                        Text(pages[index].note)
                            .font(TsutsuuraTheme.bodyFont(size: 21))
                            .foregroundStyle(TsutsuuraTheme.skyInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if index == pages.count - 1, let onPersonalize {
                    TextRaisedButton(
                        title: "しるしをかき直す",
                        icon: "pencil.tip.crop.circle",
                        height: 64,
                        fontSize: 22,
                        action: onPersonalize
                    )
                    .accessibilityIdentifier("essentials-personalize-button")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    private var notificationOptIn: some View {
        PaperPanel {
            VStack(alignment: .leading, spacing: 18) {
                Label("家族からのお知らせ", systemImage: "bell.fill")
                    .font(TsutsuuraTheme.bodyFont(size: 25, weight: .semibold))
                    .foregroundStyle(TsutsuuraTheme.ink)
                Text("新しい質問や、家族の回答・返事に気づけます。お知らせを受け取らなくても、アプリを使えます。")
                    .font(TsutsuuraTheme.bodyFont(size: 21))
                    .foregroundStyle(TsutsuuraTheme.skyInk)
                    .fixedSize(horizontal: false, vertical: true)

                switch permissionState {
                case .notDetermined:
                    TextRaisedButton(
                        title: isRequestingPermission ? "確認しています" : "お知らせを受け取る",
                        icon: "bell.fill",
                        height: 64,
                        fontSize: 22,
                        action: onRequestPermission
                    )
                    .disabled(isRequestingPermission)
                    .accessibilityIdentifier("essentials-notification-opt-in")
                case .denied:
                    Text("受け取るには、iPhoneの設定で通知を許可してください。あとからでも変更できます。")
                        .font(TsutsuuraTheme.bodyFont(size: 21))
                        .foregroundStyle(TsutsuuraTheme.skyInk)
                        .fixedSize(horizontal: false, vertical: true)
                    TextRaisedButton(
                        title: "iPhoneの設定を開く",
                        icon: "gearshape.fill",
                        height: 64,
                        fontSize: 22,
                        action: onOpenSystemSettings
                    )
                    .accessibilityIdentifier("essentials-notification-settings")
                case .authorized, .provisional, .ephemeral:
                    Label("お知らせは許可されています", systemImage: "checkmark.circle.fill")
                        .font(TsutsuuraTheme.bodyFont(size: 22, weight: .semibold))
                        .foregroundStyle(TsutsuuraTheme.greenDark)
                        .accessibilityIdentifier("essentials-notification-authorized")
                    Text("受け取る種類は「設定」で選べます。")
                        .font(TsutsuuraTheme.bodyFont(size: 21))
                        .foregroundStyle(TsutsuuraTheme.skyInk)
                case .unavailable:
                    Text("お知らせは、あとから「設定」で選べます。")
                        .font(TsutsuuraTheme.bodyFont(size: 21))
                        .foregroundStyle(TsutsuuraTheme.skyInk)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func changePage(to nextPage: Int) {
        guard pages.indices.contains(nextPage) else { return }
        page = nextPage
    }
}
