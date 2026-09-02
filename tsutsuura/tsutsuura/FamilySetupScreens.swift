import CoreImage.CIFilterBuiltins
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Family setup entry

struct FamilyWelcomeScreen: View {
    let isWorking: Bool
    let onCreateFamily: () -> Void
    let onSetUpThisIPhone: () -> Void
    let onReturningUserLogin: () -> Void
    let onAccountRecovery: () -> Void

    init(
        isWorking: Bool = false,
        onCreateFamily: @escaping () -> Void,
        onSetUpThisIPhone: @escaping () -> Void,
        onReturningUserLogin: @escaping () -> Void,
        onAccountRecovery: @escaping () -> Void
    ) {
        self.isWorking = isWorking
        self.onCreateFamily = onCreateFamily
        self.onSetUpThisIPhone = onSetUpThisIPhone
        self.onReturningUserLogin = onReturningUserLogin
        self.onAccountRecovery = onAccountRecovery
    }

    var body: some View {
        FamilySetupPage(title: "家族の準備") {
            VStack(spacing: 28) {
                Image(systemName: "figure.2.and.child.holdinghands")
                    .font(.system(size: 78, weight: .bold))
                    .foregroundStyle(TsutsuuraTheme.cyan)
                    .accessibilityHidden(true)

                PaperPanel {
                    VStack(spacing: 14) {
                        Text("どちらから始めますか？")
                            .font(TsutsuuraTheme.font(31))
                            .foregroundStyle(TsutsuuraTheme.ink)

                        Text("離れて暮らしていても、ご家族の方が\nほとんどの準備をできます。")
                            .font(TsutsuuraTheme.font(24))
                            .foregroundStyle(TsutsuuraTheme.skyInk)
                            .multilineTextAlignment(.center)
                            .lineSpacing(8)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity)
                }
                .frame(minHeight: 170)

                VStack(spacing: 12) {
                    TextRaisedButton(
                        title: "家族をつくる",
                        icon: "person.3.fill",
                        height: 76,
                        fontSize: 31,
                        action: onCreateFamily
                    )
                    .disabled(isWorking)
                    .accessibilityIdentifier("create-family-button")

                    Text("ご家族の準備をする方はこちら")
                        .font(TsutsuuraTheme.font(21))
                        .foregroundStyle(.white.opacity(0.82))
                        .multilineTextAlignment(.center)
                }

                FamilySetupDivider()

                VStack(spacing: 14) {
                    Text("ご家族から届いたリンクを開くか、\n電話で聞いた番号を入力します")
                        .font(TsutsuuraTheme.font(23))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(7)

                    TextRaisedButton(
                        title: "このiPhoneを設定",
                        icon: "iphone",
                        fill: TsutsuuraTheme.orange,
                        shadow: TsutsuuraTheme.orangeDark,
                        height: 76,
                        fontSize: 28,
                        action: onSetUpThisIPhone
                    )
                    .disabled(isWorking)
                    .accessibilityIdentifier("setup-this-iphone-button")
                }

                VStack(spacing: 10) {
                    Text("以前のアカウントを使う方")
                        .font(TsutsuuraTheme.font(20))
                        .foregroundStyle(.white.opacity(0.82))

                    TextRaisedButton(
                        title: "電話番号でログイン",
                        icon: "phone.fill",
                        fill: TsutsuuraTheme.cyanMuted,
                        shadow: TsutsuuraTheme.cyanDark,
                        height: 64,
                        fontSize: 24,
                        action: onReturningUserLogin
                    )
                    .disabled(isWorking)
                    .accessibilityIdentifier("returning-user-login-button")

                    Button(action: onAccountRecovery) {
                        Label(
                            "復旧コードを使う",
                            systemImage: "key.horizontal.fill"
                        )
                        .font(TsutsuuraTheme.bodyFont(size: 21, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .overlay(Rectangle().stroke(.white, lineWidth: 2))
                    }
                    .disabled(isWorking)
                    .accessibilityIdentifier("account-recovery-button")
                }
            }
            .padding(.top, 22)
        }
    }
}

// MARK: - Organizer setup

struct OrganizerSetupScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var organizerName: String
    @Binding var familyName: String

    let isSaving: Bool
    let onBack: (() -> Void)?
    let onContinue: () -> Void

    @FocusState private var isOrganizerNameFocused: Bool
    @FocusState private var isFamilyNameFocused: Bool
    @State private var previousSuggestedFamilyName = ""

    private var isAnyFieldFocused: Bool {
        isOrganizerNameFocused || isFamilyNameFocused
    }

    init(
        organizerName: Binding<String>,
        familyName: Binding<String>,
        isSaving: Bool = false,
        onBack: (() -> Void)? = nil,
        onContinue: @escaping () -> Void
    ) {
        _organizerName = organizerName
        _familyName = familyName
        self.isSaving = isSaving
        self.onBack = onBack
        self.onContinue = onContinue
    }

    private var canContinue: Bool {
        !organizerName.familyTrimmed.isEmpty
            && !familyName.familyTrimmed.isEmpty
            && !isSaving
    }

    var body: some View {
        FamilySetupPage(
            title: "家族をつくる",
            onBack: onBack,
            isBackDisabled: isSaving
        ) {
            VStack(spacing: 28) {
                // Keep the introduction in the layout while a field gains
                // focus. Removing it moved the text field underneath an
                // in-flight tap at Accessibility text sizes, which could make
                // the field fail to become first responder.
                VStack(spacing: 28) {
                    FamilyStepLabel(current: 1, total: 2)

                    VStack(spacing: 10) {
                        Text("まず、あなたのお名前")
                            .font(TsutsuuraTheme.font(32))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)

                        Text("家族に表示する、呼びやすい名前を\n入れてください。")
                            .font(TsutsuuraTheme.font(22))
                            .foregroundStyle(.white.opacity(0.82))
                            .multilineTextAlignment(.center)
                            .lineSpacing(6)
                    }
                }

                FamilyInputPanel(
                    title: "あなたのお名前",
                    prompt: "例：たかみ",
                    text: $organizerName,
                    isFocused: isOrganizerNameFocused,
                    focus: $isOrganizerNameFocused,
                    submitLabel: .next,
                    accessibilityIdentifier: "organizer-name-input"
                ) {
                    isFamilyNameFocused = true
                }

                VStack(spacing: 12) {
                    FamilyInputPanel(
                        title: "家族の呼び名",
                        prompt: "例：たかみの家族",
                        text: $familyName,
                        isFocused: isFamilyNameFocused,
                        focus: $isFamilyNameFocused,
                        submitLabel: .done,
                        accessibilityIdentifier: "family-name-input",
                        onSubmit: continueSetup
                    )

                    Text("自動で入ります。変えたいときだけ\n書き直してください。")
                        .font(TsutsuuraTheme.font(20))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                }

                TextRaisedButton(
                    title: isSaving ? "保存しています…" : "この名前で次へ",
                    icon: "arrow.right",
                    height: 72,
                    fontSize: 27,
                    haptic: .success,
                    action: continueSetup
                )
                .disabled(!canContinue)
                .accessibilityIdentifier("organizer-continue-button")

                FamilyKeyboardClearance(isVisible: isAnyFieldFocused)
            }
            .padding(.top, 14)
        }
        .onAppear(perform: applyInitialFamilyName)
        .onChange(of: organizerName) { oldValue, newValue in
            updateSuggestedFamilyName(from: oldValue, to: newValue)
        }
        .animation(
            TsutsuuraMotion.respectingReduceMotion(
                reduceMotion,
                TsutsuuraMotion.quickSpring
            ),
            value: isAnyFieldFocused
        )
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("閉じる") {
                    isOrganizerNameFocused = false
                    isFamilyNameFocused = false
                }
                .accessibilityIdentifier("dismiss-organizer-keyboard")
            }
        }
    }

    private func applyInitialFamilyName() {
        let suggestion = Self.suggestedFamilyName(for: organizerName)
        if familyName.familyTrimmed.isEmpty {
            familyName = suggestion
        }
        previousSuggestedFamilyName = suggestion
    }

    private func updateSuggestedFamilyName(
        from oldOrganizerName: String,
        to newOrganizerName: String
    ) {
        let oldSuggestion = Self.suggestedFamilyName(for: oldOrganizerName)
        let newSuggestion = Self.suggestedFamilyName(for: newOrganizerName)
        let currentName = familyName.familyTrimmed

        if currentName.isEmpty
            || currentName == oldSuggestion
            || currentName == previousSuggestedFamilyName {
            familyName = newSuggestion
        }
        previousSuggestedFamilyName = newSuggestion
    }

    private static func suggestedFamilyName(for organizerName: String) -> String {
        let trimmedName = organizerName.familyTrimmed
        let suggestion = trimmedName.isEmpty
            ? "わたしたちの家族"
            : "\(trimmedName)の家族"
        return NameValidation.clamped(suggestion)
    }

    private func continueSetup() {
        guard canContinue else { return }
        isOrganizerNameFocused = false
        isFamilyNameFocused = false
        onContinue()
    }
}

// MARK: - Family members

struct FamilySetupScreen: View {
    let familyName: String
    let members: [UserProfile]
    let pairings: [FamilyPairingPreview]
    @Binding var managedMemberName: String
    let isCreatingPairing: Bool
    let onCreatePairing: () -> Void
    let onCreatePairingForMember: (UserProfile) -> Void
    let onRefresh: () async -> Void
    let onFinish: () -> Void

    init(
        familyName: String,
        members: [UserProfile],
        pairings: [FamilyPairingPreview],
        managedMemberName: Binding<String>,
        isCreatingPairing: Bool = false,
        onCreatePairing: @escaping () -> Void,
        onCreatePairingForMember: @escaping (UserProfile) -> Void,
        onRefresh: @escaping () async -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.familyName = familyName
        self.members = members
        self.pairings = pairings
        _managedMemberName = managedMemberName
        self.isCreatingPairing = isCreatingPairing
        self.onCreatePairing = onCreatePairing
        self.onCreatePairingForMember = onCreatePairingForMember
        self.onRefresh = onRefresh
        self.onFinish = onFinish
    }

    private var pendingPairingIDs: [String] {
        pairings
            .filter { $0.status == .pending }
            .map(\.id)
            .sorted()
    }

    var body: some View {
        FamilySetupPage(title: "家族の準備") {
            VStack(spacing: 28) {
                FamilyStepLabel(current: 2, total: 2)

                FamilyManagementContent(
                    familyName: familyName,
                    members: members,
                    pairings: pairings,
                    managedMemberName: $managedMemberName,
                    isCreatingPairing: isCreatingPairing,
                    onCreatePairing: onCreatePairing,
                    onCreatePairingForMember: onCreatePairingForMember,
                    currentUserID: nil,
                    isOwner: false,
                    onRenameFamily: nil,
                    onEditMember: nil,
                    onTransferOwnership: nil,
                    onLeaveFamily: nil
                )

                TextRaisedButton(
                    title: "家族の画面へ進む",
                    icon: "arrow.right",
                    fill: TsutsuuraTheme.green,
                    shadow: TsutsuuraTheme.greenDark,
                    height: 72,
                    fontSize: 28,
                    haptic: .success,
                    action: onFinish
                )
                .disabled(isCreatingPairing)
                .accessibilityIdentifier("family-setup-finished-button")
            }
            .padding(.top, 14)
        }
        .refreshable {
            await onRefresh()
        }
        .task(id: pendingPairingIDs) {
            await onRefresh()

            guard !pendingPairingIDs.isEmpty else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(4))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await onRefresh()
            }
        }
    }
}

struct FamilyManagementScreen: View {
    let familyName: String
    let members: [UserProfile]
    let pairings: [FamilyPairingPreview]
    @Binding var managedMemberName: String
    let isCreatingPairing: Bool
    let onBack: () -> Void
    let onCreatePairing: () -> Void
    let onCreatePairingForMember: (UserProfile) -> Void
    let currentUserID: String?
    let isOwner: Bool
    let onRenameFamily: (() -> Void)?
    let onEditMember: ((UserProfile) -> Void)?
    let onTransferOwnership: (() -> Void)?
    let onLeaveFamily: (() -> Void)?

    init(
        familyName: String,
        members: [UserProfile],
        pairings: [FamilyPairingPreview],
        managedMemberName: Binding<String>,
        isCreatingPairing: Bool = false,
        onBack: @escaping () -> Void,
        onCreatePairing: @escaping () -> Void,
        onCreatePairingForMember: @escaping (UserProfile) -> Void,
        currentUserID: String? = nil,
        isOwner: Bool = false,
        onRenameFamily: (() -> Void)? = nil,
        onEditMember: ((UserProfile) -> Void)? = nil,
        onTransferOwnership: (() -> Void)? = nil,
        onLeaveFamily: (() -> Void)? = nil
    ) {
        self.familyName = familyName
        self.members = members
        self.pairings = pairings
        _managedMemberName = managedMemberName
        self.isCreatingPairing = isCreatingPairing
        self.onBack = onBack
        self.onCreatePairing = onCreatePairing
        self.onCreatePairingForMember = onCreatePairingForMember
        self.currentUserID = currentUserID
        self.isOwner = isOwner
        self.onRenameFamily = onRenameFamily
        self.onEditMember = onEditMember
        self.onTransferOwnership = onTransferOwnership
        self.onLeaveFamily = onLeaveFamily
    }

    var body: some View {
        FamilySetupPage(
            title: "家族の設定",
            onBack: onBack,
            isBackDisabled: isCreatingPairing
        ) {
            FamilyManagementContent(
                familyName: familyName,
                members: members,
                pairings: pairings,
                managedMemberName: $managedMemberName,
                isCreatingPairing: isCreatingPairing,
                onCreatePairing: onCreatePairing,
                onCreatePairingForMember: onCreatePairingForMember,
                currentUserID: currentUserID,
                isOwner: isOwner,
                onRenameFamily: onRenameFamily,
                onEditMember: onEditMember,
                onTransferOwnership: onTransferOwnership,
                onLeaveFamily: onLeaveFamily
            )
            .padding(.top, 18)
        }
    }
}

private struct FamilyManagementContent: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let familyName: String
    let members: [UserProfile]
    let pairings: [FamilyPairingPreview]
    @Binding var managedMemberName: String
    let isCreatingPairing: Bool
    let onCreatePairing: () -> Void
    let onCreatePairingForMember: (UserProfile) -> Void
    let currentUserID: String?
    let isOwner: Bool
    let onRenameFamily: (() -> Void)?
    let onEditMember: ((UserProfile) -> Void)?
    let onTransferOwnership: (() -> Void)?
    let onLeaveFamily: (() -> Void)?

    @FocusState private var isNameFocused: Bool
    @State private var isAddingMember = false
    @State private var confirmsLeavingFamily = false

    private var canCreatePairing: Bool {
        !managedMemberName.familyTrimmed.isEmpty && !isCreatingPairing
    }

    var body: some View {
        VStack(spacing: 26) {
            VStack(spacing: 8) {
                Text(familyName)
                    .font(TsutsuuraTheme.font(35))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(members.count)人の家族")
                    .font(TsutsuuraTheme.font(22))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .accessibilityElement(children: .combine)

            PaperPanel {
                VStack(spacing: 0) {
                    if members.isEmpty {
                        Text("まだ家族がいません")
                            .font(TsutsuuraTheme.font(24))
                            .foregroundStyle(TsutsuuraTheme.skyMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    } else {
                        ForEach(
                            Array(members.enumerated()),
                            id: \.element.id
                        ) { index, member in
                            FamilyMemberRow(
                                member: member,
                                pairingStatus: latestPairingStatus(for: member),
                                isBusy: isCreatingPairing,
                                onCreatePairing: {
                                    onCreatePairingForMember(member)
                                },
                                onEdit: member.id == currentUserID
                                    || member.managed != true
                                    ? nil
                                    : onEditMember.map { callback in
                                        { callback(member) }
                                    }
                            )

                            if index < members.count - 1 {
                                Rectangle()
                                    .fill(TsutsuuraTheme.skyInk.opacity(0.24))
                                    .frame(height: 2)
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
            }

            if isAddingMember {
                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        Text("つつうらを使う方")
                            .font(TsutsuuraTheme.font(29))
                            .foregroundStyle(.white)

                        Text("お名前は、あなたが先に\n入力しておけます。")
                            .font(TsutsuuraTheme.font(21))
                            .foregroundStyle(.white.opacity(0.78))
                            .multilineTextAlignment(.center)
                            .lineSpacing(5)
                    }

                    FamilyInputPanel(
                        title: "お名前",
                        prompt: "例：おばあちゃん",
                        text: $managedMemberName,
                        isFocused: isNameFocused,
                        focus: $isNameFocused,
                        submitLabel: .done,
                        accessibilityIdentifier: "managed-member-name-input",
                        onSubmit: createPairing
                    )

                    TextRaisedButton(
                        title: isCreatingPairing
                            ? "案内をつくっています…"
                            : "設定の案内をつくる",
                        icon: "paperplane.fill",
                        height: 72,
                        fontSize: 27,
                        haptic: .success,
                        action: createPairing
                    )
                    .disabled(!canCreatePairing)
                    .accessibilityIdentifier("create-pairing-button")

                    Text("案内は10分間使えます。離れているときは、\n先に電話をつないでおくと安心です。")
                        .font(TsutsuuraTheme.font(19))
                        .foregroundStyle(.white.opacity(0.76))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)

                    Button {
                        HapticPlayer.play(.selection)
                        isNameFocused = false
                        withAnimation(
                            TsutsuuraMotion.respectingReduceMotion(
                                reduceMotion,
                                TsutsuuraMotion.quickSpring
                            )
                        ) {
                            isAddingMember = false
                        }
                    } label: {
                        Text("やめる")
                            .font(TsutsuuraTheme.font(23))
                            .foregroundStyle(.white)
                            .frame(minWidth: 120, minHeight: 64)
                    }
                    .buttonStyle(.plain)
                    .disabled(isCreatingPairing)
                }
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                )
            } else {
                VStack(spacing: 10) {
                    TextRaisedButton(
                        title: "つつうらを使う方を追加",
                        icon: "person.badge.plus",
                        height: 76,
                        fontSize: 24,
                        action: beginAddingMember
                    )
                    .disabled(isCreatingPairing)
                    .accessibilityIdentifier("add-managed-member-button")

                    Text("離れて暮らしていても、ここから\n設定の案内を送れます。")
                        .font(TsutsuuraTheme.font(20))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                }
            }

            if isOwner {
                VStack(spacing: 12) {
                    if let onRenameFamily {
                        LifecycleNavigationButton(
                            title: "家族名を変更",
                            subtitle: "家族全員に表示される名前です",
                            icon: "pencil",
                            action: onRenameFamily
                        )
                    }
                    if let onTransferOwnership {
                        LifecycleNavigationButton(
                            title: "管理者を引き継ぐ",
                            subtitle: "退会する前に別の家族へ引き継げます",
                            icon: "person.2.arrowtriangles.swap",
                            action: onTransferOwnership
                        )
                    }
                }
            } else if onLeaveFamily != nil {
                Button("この家族から退会", role: .destructive) {
                    confirmsLeavingFamily = true
                }
                    .font(TsutsuuraTheme.bodyFont(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .background(TsutsuuraTheme.coral)
            }

            FamilyKeyboardClearance(isVisible: isNameFocused)
        }
        .animation(
            TsutsuuraMotion.respectingReduceMotion(
                reduceMotion,
                TsutsuuraMotion.quickSpring
            ),
            value: isAddingMember
        )
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("閉じる") {
                    isNameFocused = false
                }
                .accessibilityIdentifier("dismiss-managed-member-keyboard")
            }
        }
        .confirmationDialog(
            "この家族から退会しますか？",
            isPresented: $confirmsLeavingFamily,
            titleVisibility: .visible
        ) {
            if let onLeaveFamily {
                Button("退会", role: .destructive, action: onLeaveFamily)
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("この家族での自分の回答・写真・コメントは削除され、ほかの家族の投稿も見られなくなります。自分のアカウントには引き続きログインできます。")
        }
    }

    private func beginAddingMember() {
        withAnimation(
            TsutsuuraMotion.respectingReduceMotion(
                reduceMotion,
                TsutsuuraMotion.quickSpring
            )
        ) {
            isAddingMember = true
        }
    }

    private func createPairing() {
        guard canCreatePairing else { return }
        isNameFocused = false
        onCreatePairing()
    }

    private func latestPairingStatus(
        for member: UserProfile
    ) -> FamilyPairingStatus? {
        pairings.first(where: { $0.member.id == member.id })?.status
    }
}

// MARK: - Pairing invitation

struct PairingShareScreen: View {
    let familyName: String
    let memberName: String
    let pairingURL: URL
    let pairingCode: String
    let expiresAt: Date
    let onFinished: () -> Void
    let onReissue: (() -> Void)?

    @State private var copyFeedback: String?

    init(
        familyName: String,
        memberName: String,
        pairingURL: URL,
        pairingCode: String,
        expiresAt: Date,
        onFinished: @escaping () -> Void,
        onReissue: (() -> Void)? = nil
    ) {
        self.familyName = familyName
        self.memberName = memberName
        self.pairingURL = pairingURL
        self.pairingCode = pairingCode
        self.expiresAt = expiresAt
        self.onFinished = onFinished
        self.onReissue = onReissue
    }

    private var sixDigitCode: String {
        NumericInputValidation.asciiDigits(in: pairingCode, maximum: 6)
    }

    private var displayedCode: String {
        sixDigitCode.map(String.init).joined(separator: "  ")
    }

    private var shareMessage: String {
        """
        \(familyName)の「\(memberName)」用の、つつうらの設定です。
        このリンクを「\(memberName)」が使うiPhoneで開いてください。
        リンクが開かないときは、つつうらで「このiPhoneを設定」を押し、設定番号「\(sixDigitCode)」を入力してください。
        この案内は\(Self.expirationFormatter.string(from: expiresAt))まで使えます。
        """
    }

    var body: some View {
        TimelineView(.periodic(from: Date.now, by: 1)) { timeline in
            sharePage(at: timeline.date)
        }
    }

    private func sharePage(at now: Date) -> some View {
        FamilySetupPage(title: "設定を送る") {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("「\(memberName)」の\n設定ができました")
                        .font(TsutsuuraTheme.font(32))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(7)

                    Text("離れているときは、リンクを送るか\n電話で6桁の番号を伝えてください。")
                        .font(TsutsuuraTheme.font(21))
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                }

                ActivityShareButton(items: [shareMessage, pairingURL]) {
                    Label(
                        now >= expiresAt
                            ? "この設定案内は期限切れです"
                            : "設定リンクを送る",
                        systemImage: "square.and.arrow.up"
                    )
                    .font(TsutsuuraTheme.font(29))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 14)
                }
                .buttonStyle(
                    FamilyShareButtonStyle(
                        fill: TsutsuuraTheme.cyan,
                        shadow: TsutsuuraTheme.cyanDark,
                        height: 72
                    )
                )
                .accessibilityLabel(
                    "\(memberName)へ設定リンクを送る"
                )
                .accessibilityIdentifier("pairing-share-button")
                .disabled(now >= expiresAt)

                HStack(spacing: 12) {
                    PairingCopyButton(
                        title: "リンクをコピー",
                        icon: "link",
                        isDisabled: now >= expiresAt
                    ) {
                        copy(pairingURL.absoluteString, message: "リンクをコピーしました")
                    }
                    .accessibilityIdentifier("pairing-copy-link-button")

                    PairingCopyButton(
                        title: "番号をコピー",
                        icon: "number",
                        isDisabled: now >= expiresAt
                    ) {
                        copy(sixDigitCode, message: "6桁の番号をコピーしました")
                    }
                    .accessibilityIdentifier("pairing-copy-code-button")
                }

                if let copyFeedback {
                    Label(copyFeedback, systemImage: "checkmark.circle.fill")
                        .font(TsutsuuraTheme.bodyFont(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("pairing-copy-feedback")
                }

                PaperPanel {
                    VStack(spacing: 18) {
                        PairingQRCode(value: pairingURL.absoluteString)
                            .frame(width: 210, height: 210)

                        Text("近くにいるときは、相手のiPhoneで\n四角い印を読み取ります")
                            .font(TsutsuuraTheme.font(19))
                            .foregroundStyle(TsutsuuraTheme.skyInk)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                }

                VStack(spacing: 12) {
                    Text("電話で伝えるときは、6桁の番号")
                        .font(TsutsuuraTheme.font(22))
                        .foregroundStyle(.white)

                    PaperPanel {
                        Text(displayedCode)
                            .font(TsutsuuraTheme.codeFont())
                            .foregroundStyle(TsutsuuraTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(minHeight: 94)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "設定番号、"
                            + sixDigitCode.map(String.init)
                                .joined(separator: "、")
                    )
                    .accessibilityIdentifier("pairing-share-code")

                    Text(expirationMessage(at: now))
                        .font(TsutsuuraTheme.font(18))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("pairing-expiration-status")
                }

                if now >= expiresAt,
                   let onReissue {
                    TextRaisedButton(
                        title: "新しい設定案内を作る",
                        icon: "arrow.clockwise",
                        fill: TsutsuuraTheme.orange,
                        shadow: TsutsuuraTheme.orangeDark,
                        height: 68,
                        fontSize: 23,
                        haptic: .warning,
                        action: onReissue
                    )
                    .accessibilityIdentifier("pairing-reissue-expired-button")
                }

                TextRaisedButton(
                    title: "家族の一覧に戻る",
                    icon: "arrow.left",
                    fill: TsutsuuraTheme.green,
                    shadow: TsutsuuraTheme.greenDark,
                    height: 72,
                    fontSize: 28,
                    haptic: .success,
                    action: onFinished
                )
                .accessibilityIdentifier("pairing-share-finished-button")
            }
            .padding(.top, 16)
        }
    }

    private func copy(_ value: String, message: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = value
        #endif
        HapticPlayer.play(.success)
        copyFeedback = message
    }

    private func expirationMessage(at now: Date) -> String {
        let seconds = Int(expiresAt.timeIntervalSince(now).rounded(.down))
        guard seconds > 0 else {
            return "期限が切れました。新しい設定案内を作ってください。"
        }
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return "あと\(minutes)分\(remainingSeconds)秒（\(Self.expirationFormatter.string(from: expiresAt))まで）"
    }

    private static let expirationFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.timeZone = .current
        formatter.dateFormat = "M月d日 H時mm分"
        return formatter
    }()
}

private struct PairingCopyButton: View {
    let title: String
    let icon: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(TsutsuuraTheme.bodyFont(size: 18, weight: .bold))
                .foregroundStyle(isDisabled ? TsutsuuraTheme.skyMuted : TsutsuuraTheme.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(isDisabled ? Color(hex: 0xD6E1E3) : TsutsuuraTheme.sky)
                .overlay(
                    Rectangle().stroke(
                        isDisabled ? TsutsuuraTheme.skyMuted : TsutsuuraTheme.skyInk,
                        lineWidth: 2
                    )
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

struct PairingEntryScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var code: String
    let isChecking: Bool
    let onBack: (() -> Void)?
    let onContinue: () -> Void

    @FocusState private var isCodeFocused: Bool

    init(
        code: Binding<String>,
        isChecking: Bool = false,
        onBack: (() -> Void)? = nil,
        onContinue: @escaping () -> Void
    ) {
        _code = code
        self.isChecking = isChecking
        self.onBack = onBack
        self.onContinue = onContinue
    }

    private var digits: String {
        NumericInputValidation.asciiDigits(in: code, maximum: 6)
    }

    private var canContinue: Bool {
        digits.count == 6 && !isChecking
    }

    var body: some View {
        FamilySetupPage(
            title: "このiPhoneを設定",
            onBack: onBack,
            isBackDisabled: isChecking,
            backAccessibilityIdentifier: "pairing-entry-back-button"
        ) {
            VStack(spacing: 30) {
                Image(systemName: "iphone.gen3")
                    .font(.system(size: 76, weight: .bold))
                    .foregroundStyle(TsutsuuraTheme.orange)
                    .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text("6桁の設定番号を入力")
                        .font(TsutsuuraTheme.font(32))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("ご家族から電話やメッセージで\n聞いた番号を入れてください。")
                        .font(TsutsuuraTheme.font(23))
                        .foregroundStyle(.white.opacity(0.82))
                        .multilineTextAlignment(.center)
                        .lineSpacing(7)
                }

                PaperPanel {
                    TextField(
                        "",
                        text: $code,
                        prompt: Text("6桁")
                            .foregroundStyle(TsutsuuraTheme.skyMuted)
                    )
                    .font(TsutsuuraTheme.codeFont())
                    .foregroundStyle(TsutsuuraTheme.ink)
                    .multilineTextAlignment(.center)
                    .familyNumericInputTraits()
                    .focused($isCodeFocused)
                    .onChange(of: code) { _, newValue in
                        let cleaned = NumericInputValidation.asciiDigits(
                            in: newValue,
                            maximum: 6
                        )
                        if cleaned != newValue {
                            code = cleaned
                        }
                    }
                    .accessibilityLabel("6桁の設定番号")
                    .accessibilityIdentifier("pairing-code-input")
                    .padding(.horizontal, 20)
                }
                .frame(minHeight: 108)

                TextRaisedButton(
                    title: isChecking ? "確認しています…" : "内容を確認する",
                    icon: "arrow.right",
                    height: 76,
                    fontSize: 28,
                    haptic: .success,
                    action: continuePairing
                )
                .disabled(!canContinue)
                .accessibilityIdentifier("pairing-activate-button")

                FamilyKeyboardClearance(isVisible: isCodeFocused)
            }
            .padding(.top, 34)
        }
        .onAppear {
            isCodeFocused = true
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
                .accessibilityIdentifier("dismiss-pairing-keyboard")
            }
        }
    }

    private func continuePairing() {
        guard canContinue else { return }
        isCodeFocused = false
        onContinue()
    }
}

struct PairingConfirmationScreen: View {
    let familyName: String
    let memberName: String
    let isConfirming: Bool
    let onBack: (() -> Void)?
    let onConfirm: () -> Void
    let currentAccountName: String?

    @State private var confirmsAccountSwitch = false

    init(
        familyName: String,
        memberName: String,
        isConfirming: Bool = false,
        onBack: (() -> Void)? = nil,
        currentAccountName: String? = nil,
        onConfirm: @escaping () -> Void
    ) {
        self.familyName = familyName
        self.memberName = memberName
        self.isConfirming = isConfirming
        self.onBack = onBack
        self.currentAccountName = currentAccountName
        self.onConfirm = onConfirm
    }

    var body: some View {
        FamilySetupPage(
            title: "内容を確認",
            onBack: onBack,
            isBackDisabled: isConfirming,
            backAccessibilityIdentifier: "pairing-confirmation-back-button"
        ) {
            VStack(spacing: 30) {
                VStack(spacing: 12) {
                    Text("この内容で合っていますか？")
                        .font(TsutsuuraTheme.font(32))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text("入力はもうありません。")
                        .font(TsutsuuraTheme.font(23))
                        .foregroundStyle(.white.opacity(0.78))
                }

                PaperPanel {
                    VStack(spacing: 0) {
                        PairingConfirmationRow(
                            title: "ご家族",
                            value: familyName,
                            icon: "person.3.fill"
                        )

                        Rectangle()
                            .fill(TsutsuuraTheme.skyInk.opacity(0.28))
                            .frame(height: 2)

                        PairingConfirmationRow(
                            title: "このiPhoneを使う方",
                            value: memberName,
                            icon: "person.crop.circle.fill"
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
                .frame(minHeight: 230)

                Text("このiPhoneでは「\(memberName)」の\n画面だけが開きます。")
                    .font(TsutsuuraTheme.font(22))
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)

                if let currentAccountName {
                    Label(
                        "現在の「\(currentAccountName)」から「\(memberName)」へ切り替わります。未送信の内容がないか確認してください。",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(TsutsuuraTheme.bodyFont(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .overlay(Rectangle().stroke(.white, lineWidth: 2))
                }

                TextRaisedButton(
                    title: "このiPhoneを設定する",
                    icon: "iphone",
                    fill: TsutsuuraTheme.orange,
                    shadow: TsutsuuraTheme.orangeDark,
                    height: 82,
                    fontSize: 25,
                    haptic: .success,
                    action: {
                        if currentAccountName == nil {
                            onConfirm()
                        } else {
                            confirmsAccountSwitch = true
                        }
                    }
                )
                .disabled(isConfirming)
                .accessibilityIdentifier("pairing-confirm-button")

                if isConfirming {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.large)
                        .accessibilityLabel("設定しています")
                }
            }
            .padding(.top, 36)
        }
        .confirmationDialog(
            "このiPhoneのアカウントを切り替えますか？",
            isPresented: $confirmsAccountSwitch,
            titleVisibility: .visible
        ) {
            Button("「\(memberName)」へ切り替える", role: .destructive) {
                onConfirm()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("現在のアカウントへ戻るには、登録済みの電話番号または家族からの復旧用設定案内が必要です。")
        }
    }
}

struct PairingReadyScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let memberName: String?
    let onStart: () -> Void

    @State private var isVisible = false

    init(
        memberName: String? = nil,
        onStart: @escaping () -> Void
    ) {
        self.memberName = memberName
        self.onStart = onStart
    }

    var body: some View {
        FamilySetupPage(title: "") {
            VStack(spacing: 34) {
                ZStack {
                    Rectangle()
                        .fill(TsutsuuraTheme.greenDark)
                        .offset(y: 6)

                    Rectangle()
                        .fill(TsutsuuraTheme.green)

                    Image(systemName: "checkmark")
                        .font(.system(size: 64, weight: .black))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }
                .frame(width: 132, height: 132)
                .scaleEffect(
                    reduceMotion ? 1 : (isVisible ? 1 : 0.72)
                )
                .accessibilityHidden(true)

                VStack(spacing: 18) {
                    Text("準備できました")
                        .font(TsutsuuraTheme.font(45))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("pairing-ready-title")

                    if let memberName,
                       !memberName.familyTrimmed.isEmpty {
                        Text("「\(memberName)」が使うiPhoneです")
                            .font(TsutsuuraTheme.font(25))
                            .foregroundStyle(.white.opacity(0.82))
                            .multilineTextAlignment(.center)
                    }

                    PaperPanel {
                        Text("設定はすべて終わりました\nこのまま使えます")
                            .font(TsutsuuraTheme.font(31))
                            .foregroundStyle(TsutsuuraTheme.ink)
                            .multilineTextAlignment(.center)
                            .lineSpacing(10)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 30)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(minHeight: 156)
                }

                TextRaisedButton(
                    title: "はじめる",
                    icon: "arrow.right",
                    fill: TsutsuuraTheme.green,
                    shadow: TsutsuuraTheme.greenDark,
                    height: 82,
                    fontSize: 34,
                    haptic: .success,
                    action: onStart
                )
                .accessibilityIdentifier("pairing-start-button")
            }
            .padding(.top, 126)
        }
        .onAppear {
            HapticPlayer.play(.success)
            withAnimation(
                TsutsuuraMotion.respectingReduceMotion(
                    reduceMotion,
                    TsutsuuraMotion.emphasizedSpring
                )
            ) {
                isVisible = true
            }
        }
    }
}

// MARK: - Shared family setup pieces

private struct FamilySetupPage<Content: View>: View {
    let title: String
    let onBack: (() -> Void)?
    let isBackDisabled: Bool
    let backAccessibilityIdentifier: String
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        onBack: (() -> Void)? = nil,
        isBackDisabled: Bool = false,
        backAccessibilityIdentifier: String = "family-setup-back-button",
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.onBack = onBack
        self.isBackDisabled = isBackDisabled
        self.backAccessibilityIdentifier = backAccessibilityIdentifier
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .top) {
            DottedBackdrop()

            VStack(spacing: 0) {
                FamilySetupHeader(
                    title: title,
                    onBack: onBack,
                    isBackDisabled: isBackDisabled,
                    backAccessibilityIdentifier: backAccessibilityIdentifier
                )

                ScrollView(showsIndicators: false) {
                    content()
                        .padding(.horizontal, 34)
                        .padding(.bottom, 58)
                        .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 50, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

private struct FamilySetupHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let onBack: (() -> Void)?
    let isBackDisabled: Bool
    let backAccessibilityIdentifier: String

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    if onBack != nil {
                        backButton
                    }
                    headerTitle
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                ZStack {
                    headerTitle
                        .padding(.horizontal, 112)

                    if onBack != nil {
                        HStack(spacing: 0) {
                            backButton
                            Spacer(minLength: 0)
                        }
                        .zIndex(2)
                    }
                }
            }
        }
        .frame(minHeight: 66)
        .padding(.horizontal, 24)
        .padding(.top, 50)
        .padding(.bottom, 8)
    }

    private var headerTitle: some View {
        Text(title)
            .font(TsutsuuraTheme.font(34))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .allowsHitTesting(false)
    }

    private var backButton: some View {
        Button {
            HapticPlayer.play(.selection)
            onBack?()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .bold))
                    .accessibilityHidden(true)
                Text("戻る")
                    .font(TsutsuuraTheme.font(25))
            }
            .foregroundStyle(
                isBackDisabled
                    ? Color(hex: 0xAEBFC3)
                    : .white
            )
            .frame(minWidth: 112, minHeight: 66, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBackDisabled)
        .contentShape(Rectangle())
        .accessibilityIdentifier(backAccessibilityIdentifier)
    }
}

private struct FamilyStepLabel: View {
    let current: Int
    let total: Int

    var body: some View {
        Text("\(current) / \(total)")
            .font(TsutsuuraTheme.font(20))
            .foregroundStyle(.white.opacity(0.76))
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(TsutsuuraTheme.cyanDark)
            .overlay(Rectangle().stroke(.white.opacity(0.22), lineWidth: 2))
            .accessibilityLabel("\(total)つのうち\(current)つ目")
    }
}

private struct FamilySetupDivider: View {
    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(.white.opacity(0.26))
                .frame(height: 2)
            Text("または")
                .font(TsutsuuraTheme.font(20))
                .foregroundStyle(.white.opacity(0.72))
            Rectangle()
                .fill(.white.opacity(0.26))
                .frame(height: 2)
        }
        .accessibilityHidden(true)
    }
}

private struct FamilyInputPanel: View {
    let title: String
    let prompt: String
    @Binding var text: String
    let isFocused: Bool
    let focus: FocusState<Bool>.Binding
    let submitLabel: SubmitLabel
    let accessibilityIdentifier: String
    let onSubmit: () -> Void

    init(
        title: String,
        prompt: String,
        text: Binding<String>,
        isFocused: Bool,
        focus: FocusState<Bool>.Binding,
        submitLabel: SubmitLabel,
        accessibilityIdentifier: String,
        onSubmit: @escaping () -> Void
    ) {
        self.title = title
        self.prompt = prompt
        _text = text
        self.isFocused = isFocused
        self.focus = focus
        self.submitLabel = submitLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onSubmit = onSubmit
    }

    var body: some View {
        PaperPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                    Spacer()
                    Text("\(NameValidation.characterCount(text)) / \(NameValidation.maximumLength)")
                        .monospacedDigit()
                        .accessibilityLabel(
                            "\(NameValidation.characterCount(text))文字、上限\(NameValidation.maximumLength)文字"
                        )
                        .accessibilityIdentifier(
                            "\(accessibilityIdentifier)-character-count"
                        )
                }
                .font(TsutsuuraTheme.font(21))
                .foregroundStyle(TsutsuuraTheme.skyInk)

                TextField(
                    "",
                    text: $text,
                    prompt: Text(prompt)
                        .foregroundStyle(TsutsuuraTheme.skyMuted)
                )
                .font(TsutsuuraTheme.font(31))
                .foregroundStyle(TsutsuuraTheme.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(false)
                .focused(focus)
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
                .padding(.horizontal, 14)
                .frame(minHeight: 64)
                .background(.white.opacity(isFocused ? 0.78 : 0.58))
                .overlay(
                    Rectangle()
                        .stroke(
                            TsutsuuraTheme.skyInk,
                            lineWidth: isFocused ? 3 : 2
                        )
                )
                .accessibilityLabel(title)
                .accessibilityIdentifier(accessibilityIdentifier)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
        .frame(minHeight: 132)
        .onAppear(perform: enforceCharacterLimit)
        .onChange(of: text) { _, _ in
            enforceCharacterLimit()
        }
    }

    private func enforceCharacterLimit() {
        guard NameValidation.characterCount(text) > NameValidation.maximumLength else {
            return
        }
        text = NameValidation.clamped(text)
    }
}

private struct FamilyMemberRow: View {
    let member: UserProfile
    let pairingStatus: FamilyPairingStatus?
    let isBusy: Bool
    let onCreatePairing: () -> Void
    let onEdit: (() -> Void)?

    private var status: (
        title: String,
        icon: String,
        color: Color,
        actionTitle: String?
    ) {
        guard member.managed == true else {
            return (
                "家族を準備する方",
                "person.crop.circle.badge.checkmark",
                TsutsuuraTheme.cyanDark,
                nil
            )
        }

        switch pairingStatus {
        case .some(.pending):
            return (
                "ご本人の設定待ち",
                "clock.fill",
                TsutsuuraTheme.orangeDark,
                "案内を送り直す"
            )
        case .some(.consumed):
            return (
                "設定済み",
                "checkmark.circle.fill",
                TsutsuuraTheme.greenDark,
                "別のiPhoneを設定"
            )
        case .some(.revoked), .some(.expired), .none:
            return (
                "設定の案内が必要",
                "exclamationmark.circle.fill",
                TsutsuuraTheme.orangeDark,
                "設定の案内をつくる"
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                ZStack {
                    Rectangle()
                        .fill(TsutsuuraTheme.blueAvatar)

                    Image(systemName: "person.fill")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(member.displayName)
                        .font(TsutsuuraTheme.font(27))
                        .foregroundStyle(TsutsuuraTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(status.title, systemImage: status.icon)
                        .font(TsutsuuraTheme.font(18))
                        .foregroundStyle(status.color)
                }

                Spacer()
            }

            if let actionTitle = status.actionTitle {
                TextRaisedButton(
                    title: isBusy ? "準備しています…" : actionTitle,
                    icon: "arrow.clockwise",
                    fill: TsutsuuraTheme.cyan,
                    shadow: TsutsuuraTheme.cyanDark,
                    height: 56,
                    fontSize: 20,
                    action: onCreatePairing
                )
                .disabled(isBusy)
                .accessibilityIdentifier("reissue-pairing-\(member.id)")
            }

            if let onEdit {
                Button(action: onEdit) {
                    Label("名前・端末・家族所属を編集", systemImage: "ellipsis.circle")
                        .font(TsutsuuraTheme.bodyFont(size: 18, weight: .semibold))
                        .foregroundStyle(TsutsuuraTheme.cyanDark)
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .accessibilityIdentifier("edit-family-member-\(member.id)")
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }
}

private struct PairingConfirmationRow: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 31, weight: .bold))
                .foregroundStyle(TsutsuuraTheme.cyanDark)
                .frame(width: 42)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(TsutsuuraTheme.font(20))
                    .foregroundStyle(TsutsuuraTheme.skyMuted)

                Text(value)
                    .font(TsutsuuraTheme.font(29))
                    .foregroundStyle(TsutsuuraTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .frame(minHeight: 96)
        .accessibilityElement(children: .combine)
    }
}

private struct PairingQRCode: View {
    let value: String

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let image = Self.makeImage(from: value) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                unavailableMark
            }
            #else
            unavailableMark
            #endif
        }
        .padding(12)
        .background(.white)
        .overlay(Rectangle().stroke(TsutsuuraTheme.skyInk, lineWidth: 3))
        .accessibilityHidden(true)
    }

    private var unavailableMark: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 64, weight: .bold))
            .foregroundStyle(TsutsuuraTheme.orangeDark)
            .accessibilityHidden(true)
    }

    #if canImport(UIKit)
    private static func makeImage(from value: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let transformedImage = outputImage.transformed(
            by: CGAffineTransform(scaleX: 12, y: 12)
        )
        let context = CIContext()
        guard let cgImage = context.createCGImage(
            transformedImage,
            from: transformedImage.extent
        ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
    #endif
}

private struct FamilyShareButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let fill: Color
    let shadow: Color
    let height: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed && !reduceMotion
        let depth: CGFloat = 5

        ZStack {
            Rectangle()
                .fill(shadow)
                .offset(y: depth)

            ZStack {
                Rectangle()
                    .fill(fill)

                VStack(spacing: 0) {
                    Rectangle()
                        .fill(.white.opacity(0.20))
                        .frame(height: 8)
                    Spacer()
                }

                configuration.label
            }
            .offset(y: isPressed ? depth : 0)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: height)
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .animation(
            TsutsuuraMotion.buttonSpring(
                isPressed: isPressed,
                reduceMotion: reduceMotion
            ),
            value: isPressed
        )
    }
}

private struct FamilyKeyboardClearance: View {
    let isVisible: Bool

    var body: some View {
        Color.clear
            .frame(height: isVisible ? 280 : 0)
            .accessibilityHidden(true)
    }
}

private extension String {
    var familyTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension View {
    @ViewBuilder
    func familyNumericInputTraits() -> some View {
        #if os(iOS)
        self
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
        #else
        self
        #endif
    }
}

#if DEBUG
#Preview("Family welcome") {
    TsutsuuraCanvas {
        FamilyWelcomeScreen(
            onCreateFamily: {},
            onSetUpThisIPhone: {},
            onReturningUserLogin: {},
            onAccountRecovery: {}
        )
    }
}

#Preview("Pairing ready") {
    TsutsuuraCanvas {
        PairingReadyScreen(memberName: "おばあちゃん") {}
    }
}
#endif
