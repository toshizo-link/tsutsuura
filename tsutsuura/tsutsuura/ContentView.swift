import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@MainActor
struct ContentView: View {
    @StateObject private var store: AppStore
    @StateObject private var speechTranscriber = SpeechTranscriber()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isNavigatingBack = false
    @State private var isSavingPersonalMark = false
    @State private var essentialsPage = 0
    @State private var confirmsQuestionChange = false
    @State private var selectedTab: HomeTab = .family
    @State private var isVoiceAnswerPresented = false
    @State private var showAnswerSuccess = false
    @State private var localErrorMessage: String?
    @State private var pushRegistration = PushRegistrationCoordinator()
    @State private var pushDestinations = PushDestinationCoordinator()
    @State private var settingsDisplayName = ""
    @State private var otpIssuedAt: Date?
    @State private var otpResendAvailableAt: Date?
    @State private var emailEnrollmentIssuedAt: Date?
    @State private var emailEnrollmentResendAvailableAt: Date?
    @State private var familyNameDraft = ""
    @State private var managedMemberNameDraft = ""
    @State private var answerEditorDraft = ""
    @State private var notificationDraft = NotificationPreferences()
    @State private var pushAuthorizationState: PushAuthorizationState = .unavailable
    @State private var isRequestingPushPermission = false
    @State private var informationDocument: InformationDocument?

    init(store: AppStore? = nil) {
        if let store {
            _store = StateObject(wrappedValue: store)
        } else if ProcessInfo.processInfo.environment["UI_TESTING"] == "1" {
            let testURL = APIConfiguration.productionBaseURL
            let configuration = try! APIConfiguration(baseURL: testURL)
            _store = StateObject(
                wrappedValue: AppStore(
                    api: DefaultAppAPI(
                        configuration: configuration,
                        tokenStore: InMemoryTokenStore()
                    ),
                    haptics: NoopHaptics()
                )
            )
        } else if let liveStore = try? AppStore.live() {
            _store = StateObject(wrappedValue: liveStore)
        } else {
            let fallbackURL = APIConfiguration.productionBaseURL
            let configuration = try! APIConfiguration(baseURL: fallbackURL)
            _store = StateObject(
                wrappedValue: AppStore(
                    api: DefaultAppAPI(configuration: configuration)
                )
            )
        }
    }

    var body: some View {
        TsutsuuraCanvas(
            keepsFullScaleWithKeyboard: keepsInputScreenFullScaleWithKeyboard
        ) {
            ZStack(alignment: .top) {
                routedContent
                    .id(routeIdentity)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .move(edge: isNavigatingBack ? .leading : .trailing),
                                removal: .move(edge: isNavigatingBack ? .trailing : .leading)
                            )
                    )

                if showAnswerSuccess {
                    SuccessBurst()
                        .transition(.opacity)
                        .zIndex(5)
                }

                if let errorMessage = displayedErrorMessage {
                    ErrorToast(
                        message: errorMessage,
                        onDismiss: dismissPresentedErrors
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 54)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity)
                    )
                    .zIndex(10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(
                TsutsuuraMotion.respectingReduceMotion(
                    reduceMotion,
                    TsutsuuraMotion.spring
                ),
                value: routeIdentity
            )
            .animation(
                TsutsuuraMotion.respectingReduceMotion(
                    reduceMotion,
                    TsutsuuraMotion.quickSpring
                ),
                value: displayedErrorMessage
            )
        }
        .task {
            if store.session == .restoring {
                await store.restoreSession()
            }
            await store.synchronizeDeviceTimeZone()
            await consumePendingPushDestination()
        }
        .alert("新しい質問が届きました", isPresented: $confirmsQuestionChange) {
            Button("下書きを消して新しい質問へ", role: .destructive) {
                store.acceptNewQuestionDiscardingDraft()
                if store.path.last != .todayQuestion { pushRoute(.todayQuestion) }
            }
            Button("下書きを残す", role: .cancel) {}
        } message: {
            Text("前の質問の下書きは、まだ送られていません。新しい質問へ進むと、この下書きは消えます。\n\n\(store.question.draft)")
        }
        .overlay(alignment: .leading) {
            BackSwipeNavigation(enabled: canSwipeBack, onBack: performBackNavigation)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, case .signedIn = store.session {
                refreshPushRegistrationIfAuthorized()
                Task { await store.synchronizeDeviceTimeZone() }
                Task {
                    await store.refreshHomeInBackground(includingHistory: selectedTab == .profile)
                    await consumePendingPushDestination()
                }
            }
        }
        .onOpenURL(perform: handleIncomingURL)
        .onReceive(
            NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)
        ) { _ in
            Task { await store.synchronizeDeviceTimeZone() }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didReceivePushToken)
        ) { notification in
            guard let token = notification.object as? String else { return }
            pushRegistration.receiveToken(token)
            registerPushTokenIfPossible()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didOpenPushDestination)
        ) { _ in
            Task {
                await consumePendingPushDestination()
            }
        }
        .onChange(of: store.session) { _, newSession in
            if case .signedIn(let profile) = newSession {
                pushRegistration.setUserID(profile.id)
            } else {
                pushRegistration.setUserID(nil)
            }
            switch newSession {
            case .signedIn:
                refreshPushRegistrationIfAuthorized()
                Task { await store.synchronizeDeviceTimeZone() }
                if let pairingToken = store.familySetup.pairingToken {
                    store.preparePairingToken(pairingToken)
                    previewIncomingPairing()
                } else {
                    registerPushTokenIfPossible()
                    Task {
                        await consumePendingPushDestination()
                    }
                }
            case .signedOut where store.familySetup.pairingToken != nil:
                Task {
                    await store.previewFamilyPairing()
                }
            default:
                break
            }
        }
        .onChange(of: store.path) { _, newPath in
            guard case .signedIn = store.session,
                  newPath.last == .home,
                  store.familySetup.pairingToken == nil else {
                return
            }
            registerPushTokenIfPossible()
            Task { await consumePendingPushDestination() }
        }
    }

    private var canSwipeBack: Bool {
        if store.requiresPersonalMarkSetup || store.auth.isSubmitting || store.familySetup.isSubmitting || store.question.isSubmitting
            || store.emailAuth.isSubmitting || store.emailEnrollment.isSubmitting
            || isSavingPersonalMark || store.familyLifecycle.isMutating
            || store.account.isDeleting {
            return false
        }
        return informationDocument != nil || isVoiceAnswerPresented
            || store.path.count > 1 || store.session.isAwaitingVerification
            || (store.path.last == .essentials && essentialsPage > 0)
    }

    private func performBackNavigation() {
        guard canSwipeBack else { return }
        isNavigatingBack = true
        if informationDocument != nil { informationDocument = nil }
        else if isVoiceAnswerPresented { dismissVoiceAnswer() }
        else if store.session.isAwaitingVerification { returnToLogin() }
        else if store.path.last == .pairingConfirmation { cancelPairingConfirmation() }
        else if store.path.last == .emailEnrollment { store.cancelEmailEnrollment() }
        else if case .emailEnrollmentVerification = store.path.last { store.cancelEmailEnrollment() }
        else if store.path.last == .recoveryCode { closeRecoveryCode() }
        else if store.path.last == .essentials { goBackInEssentials() }
        else { popRoute() }
    }

    private var keepsInputScreenFullScaleWithKeyboard: Bool {
        switch store.session {
        case .signedOut, .awaitingOTP, .awaitingEmailVerification:
            return false
        case .signedIn:
            guard !isVoiceAnswerPresented else { return false }
            return false
        case .restoring:
            return false
        }
    }

    @ViewBuilder
    private var routedContent: some View {
        switch store.session {
        case .restoring:
            if store.canRetrySessionRestore {
                RestoringScreen(
                    message: "ログイン状態を確認できませんでした",
                    onRetry: retrySessionRestore
                )
            } else {
                RestoringScreen()
            }

        case .signedOut:
            signedOutContent

        case .awaitingEmailVerification(let email):
            EmailVerificationScreen(
                email: email,
                code: Binding(
                    get: { store.emailAuth.verificationCode },
                    set: { store.emailAuth.verificationCode = $0 }
                ),
                isSubmitting: store.emailAuth.isSubmitting,
                onBack: returnToLogin,
                onResend: requestEmailOTP,
                onVerify: verifyEmailOTP,
                expiresAt: otpExpirationDate,
                resendAvailableAt: otpResendAvailableAt,
                canReplayExpiredAttempt: store.emailAuth.canReplayExpiredAttempt
            )

        case .awaitingOTP:
            // Old, interrupted SMS challenges return to email entry. Existing
            // sessions and recovery codes remain usable after the upgrade.
            EmailEntryScreen(
                email: $store.emailAuth.email,
                isSubmitting: store.emailAuth.isSubmitting,
                onBack: showFamilyWelcome,
                onContinue: requestEmailOTP
            )

        case .signedIn(let profile):
            signedInContent(profile: profile)
        }
    }

    @ViewBuilder
    private var signedOutContent: some View {
        switch store.path.last ?? .onboarding {
        case .accountRecovery:
            AccountRecoveryScreen(
                code: $store.recovery.codeInput,
                isSubmitting: store.recovery.isSubmitting,
                onBack: showFamilyWelcome,
                onRecover: recoverAccount
            )

        case .emailEntry, .emailVerification, .phoneEntry:
            EmailEntryScreen(
                email: $store.emailAuth.email,
                isSubmitting: store.emailAuth.isSubmitting,
                onBack: showFamilyWelcome,
                onContinue: requestEmailOTP
            )

        case .organizerSetup:
            OrganizerSetupScreen(
                organizerName: $store.familySetup.organizerName,
                familyName: $store.familySetup.familyName,
                isSaving: store.familySetup.isSubmitting,
                onBack: showFamilyWelcome,
                onContinue: createOrganizerFamily
            )

        case .pairingEntry:
            if store.familySetup.pairingToken != nil {
                RestoringScreen(
                    message: "家族の設定を確認しています…",
                    onRetry: previewFamilyPairing,
                    secondaryTitle: "6桁の番号を入力",
                    onSecondary: showPairingEntry,
                    isWorking: store.familySetup.isSubmitting
                )
                .task(id: store.familySetup.pairingToken) {
                    guard store.familySetup.pairingPreview == nil,
                          !store.familySetup.isSubmitting else {
                        return
                    }
                    await store.previewFamilyPairing()
                }
            } else {
                PairingEntryScreen(
                    code: Binding(
                        get: { store.familySetup.pairingCode },
                        set: { newCode in
                            store.familySetup.pairingCode = newCode
                        }
                    ),
                    isChecking: store.familySetup.isSubmitting,
                    onBack: showFamilyWelcome,
                    onContinue: previewFamilyPairing
                )
            }

        case .pairingConfirmation:
            if let preview = store.familySetup.pairingPreview {
                PairingConfirmationScreen(
                    familyName: preview.family.name,
                    memberName: preview.member.displayName,
                    isConfirming: store.familySetup.isSubmitting,
                    onBack: cancelPairingConfirmation,
                    onConfirm: activateFamilyPairing
                )
            } else {
                RestoringScreen(message: "家族を確認しています…")
                    .task(id: store.familySetup.pairingToken) {
                        // A missing code preview during Back navigation is a
                        // transient teardown state, not a reason to submit the
                        // same six-digit credential again. Token deep links do
                        // need automatic restoration here.
                        guard store.familySetup.pairingToken != nil else {
                            return
                        }
                        await store.previewFamilyPairing()
                    }
            }

        default:
            FamilyWelcomeScreen(
                isWorking: store.familySetup.isSubmitting,
                onCreateFamily: showOrganizerSetup,
                onSetUpThisIPhone: showPairingEntry,
                onReturningUserLogin: showEmailLogin,
                onAccountRecovery: showAccountRecovery
            )
        }
    }

    @ViewBuilder
    private func signedInContent(profile: UserProfile) -> some View {
        if store.requiresPersonalMarkSetup {
            if !store.personalMarkRequirementIsConfirmed {
                RestoringScreen(
                    message: store.personalMarkRequirementError == nil
                        ? "あなたのしるしを確認しています…"
                        : "しるしを確認できませんでした",
                    onRetry: { Task { await store.confirmPersonalMarkRequirement() } },
                    isWorking: store.isCheckingPersonalMarkRequirement
                )
                .task { await store.confirmPersonalMarkRequirement() }
            } else {
                PersonalMarkEditor(
                    displayName: profile.displayName,
                    mark: nil,
                    onBack: {},
                    onSave: { mark in await store.updatePersonalMark(mark) },
                    isRequiredSetup: true,
                    onSavingChanged: {
                        isSavingPersonalMark = $0
                        if $0 { isNavigatingBack = false }
                    }
                )
            }
        } else if let informationDocument {
            InformationDocumentScreen(
                document: informationDocument,
                onBack: { isNavigatingBack = true; self.informationDocument = nil }
            )
        } else if isVoiceAnswerPresented,
           let question = store.question.question {
            VoiceAnswerScreen(
                prompt: question.prompt,
                transcript: Binding(
                    get: { speechTranscriber.transcript },
                    set: { _ in }
                ),
                level: speechTranscriber.level,
                isRecording: speechTranscriber.isRecording,
                hasRecording: speechTranscriber.recording != nil,
                errorMessage: speechTranscriber.errorMessage,
                captureState: speechTranscriber.captureState,
                onStartRecording: {
                    await speechTranscriber.start()
                },
                onStopRecording: {
                    speechTranscriber.stop()
                },
                onCancel: dismissVoiceAnswer,
                onUseTranscript: useVoiceTranscript,
                onOpenSettings: openAppSettings,
                onUseTextAnswer: dismissVoiceAnswer
            )
            .onDisappear {
                speechTranscriber.stop()
            }
        } else {
            switch store.path.last ?? .home {
            case .pairingConfirmation:
                if let preview = store.familySetup.pairingPreview {
                    PairingConfirmationScreen(
                        familyName: preview.family.name,
                        memberName: preview.member.displayName,
                        isConfirming: store.familySetup.isSubmitting,
                        onBack: cancelPairingConfirmation,
                        currentAccountName: preview.member.id == profile.id
                            ? nil
                            : profile.displayName,
                        onConfirm: activateFamilyPairing
                    )
                } else {
                    RestoringScreen(
                        message: store.familySetup.errorMessage == nil
                            ? "家族を確認しています…"
                            : "招待を確認できませんでした",
                        onRetry: previewFamilyPairing,
                        secondaryTitle: "戻る",
                        onSecondary: cancelPairingConfirmation,
                        isWorking: store.familySetup.isSubmitting
                    )
                        .task(id: store.familySetup.pairingToken) {
                            guard store.familySetup.pairingPreview == nil,
                                  !store.familySetup.isSubmitting else {
                                return
                            }
                            await store.previewFamilyPairing()
                        }
                }

            case .familySetup:
                if let family = store.familySetup.family ?? profile.family {
                    FamilySetupScreen(
                        familyName: family.name,
                        members: family.members,
                        pairings: store.familySetup.pairings,
                        managedMemberName: $store.familySetup.managedMemberName,
                        isCreatingPairing: store.familySetup.isSubmitting,
                        onCreatePairing: createManagedMemberPairing,
                        onCreatePairingForMember: createPairingForMember,
                        onRefresh: {
                            await store.loadFamilySetup()
                        },
                        onFinish: finishFamilySetup
                    )
                } else {
                    RestoringScreen(
                        message: "家族を準備しています…",
                        onRetry: loadFamilySetup
                    )
                        .task {
                            await store.loadFamilySetup()
                        }
                }

            case .pairingShare:
                if let pairing = store.familySetup.activePairing {
                    PairingShareScreen(
                        familyName: pairing.family.name,
                        memberName: pairing.member.displayName,
                        pairingURL: pairing.pairingURL,
                        pairingCode: pairing.code,
                        expiresAt: pairing.expiresAt,
                        onFinished: finishSharingPairing,
                        onReissue: {
                            guard let member = currentFamily(profile: profile)?
                                .members.first(where: {
                                    $0.id == pairing.member.id
                                }) else {
                                return
                            }
                            createPairingForMember(member)
                        }
                    )
                } else {
                    RestoringScreen(
                        message: "設定番号が見つかりません",
                        retryTitle: "戻る",
                        onRetry: popRoute
                    )
                }

            case .pairingReady:
                PairingReadyScreen(
                    memberName: store.familySetup.pairingPreview?
                        .member.displayName ?? profile.displayName,
                    onStart: finishFamilySetup
                )

            case .familyManagement:
                if let family = store.familySetup.family
                    ?? store.home.feed?.family
                    ?? profile.family {
                    FamilyManagementScreen(
                        familyName: family.name,
                        members: family.members,
                        pairings: store.familySetup.pairings,
                        managedMemberName: $store.familySetup.managedMemberName,
                        isCreatingPairing: store.familySetup.isSubmitting,
                        onBack: popRoute,
                        onCreatePairing: createManagedMemberPairing,
                        onCreatePairingForMember: createPairingForMember,
                        currentUserID: profile.id,
                        isOwner: profile.familyRole == .owner,
                        onRenameFamily: {
                            familyNameDraft = family.name
                            pushRoute(.familyRename)
                        },
                        onEditMember: { member in
                            managedMemberNameDraft = member.displayName
                            pushRoute(
                                .managedMemberEdit(memberID: member.id)
                            )
                        },
                        onTransferOwnership: {
                            pushRoute(.ownershipTransfer)
                        },
                        onLeaveFamily: {
                            Task {
                                _ = await store.leaveFamily()
                            }
                        }
                    )
                    .task {
                        await store.loadFamilySetup()
                    }
                } else {
                    RestoringScreen(
                        message: "家族を読み込んでいます…",
                        onRetry: loadFamilySetup
                    )
                        .task {
                            await store.loadFamilySetup()
                        }
                }

            case .familyRename:
                FamilyRenameScreen(
                    familyName: $familyNameDraft,
                    isSaving: store.familyLifecycle.isMutating,
                    onBack: popRoute,
                    onSave: {
                        Task {
                            if await store.renameFamily(familyNameDraft) {
                                popRoute()
                            }
                        }
                    }
                )

            case .managedMemberEdit(let memberID):
                if let member = currentFamily(profile: profile)?.members
                    .first(where: { $0.id == memberID }) {
                    ManagedMemberEditScreen(
                        member: member,
                        displayName: $managedMemberNameDraft,
                        isWorking: store.familyLifecycle.isMutating
                            || store.familySetup.isSubmitting,
                        onBack: popRoute,
                        onSave: {
                            Task {
                                if await store.renameManagedFamilyMember(
                                    memberID: memberID,
                                    displayName: managedMemberNameDraft
                                ) {
                                    popRoute()
                                }
                            }
                        },
                        onIssueRecovery: {
                            createPairingForMember(member)
                        },
                        onRemove: {
                            Task {
                                if await store.removeManagedFamilyMember(
                                    memberID: memberID
                                ) {
                                    popRoute()
                                }
                            }
                        }
                    )
                } else {
                    RestoringScreen(
                        message: "家族が見つかりません",
                        retryTitle: "戻る",
                        onRetry: popRoute
                    )
                }

            case .ownershipTransfer:
                OwnershipTransferScreen(
                    currentUserID: profile.id,
                    members: currentFamily(profile: profile)?.members ?? [],
                    isWorking: store.familyLifecycle.isMutating,
                    onBack: popRoute,
                    onTransfer: { member in
                        Task {
                            if await store.transferFamilyOwnership(
                                to: member.id
                            ) {
                                popRoute()
                            }
                        }
                    }
                )

            case .emailEnrollment, .phoneEnrollment, .phoneEnrollmentVerification:
                EmailEnrollmentScreen(
                    email: $store.emailEnrollment.email,
                    isSubmitting: store.emailEnrollment.isSubmitting,
                    onBack: {
                        isNavigatingBack = true
                        store.cancelEmailEnrollment()
                    },
                    onContinue: requestEmailEnrollment
                )

            case .emailEnrollmentVerification:
                EmailVerificationScreen(
                    email: store.emailEnrollment.email,
                    code: $store.emailEnrollment.verificationCode,
                    isSubmitting: store.emailEnrollment.isSubmitting,
                    onBack: { isNavigatingBack = true; store.cancelEmailEnrollment() },
                    onResend: requestEmailEnrollment,
                    onVerify: verifyEmailEnrollment,
                    confirmationTitle: "メールアドレスを登録",
                    expiresAt: emailEnrollmentExpirationDate,
                    resendAvailableAt: emailEnrollmentResendAvailableAt,
                    canReplayExpiredAttempt:
                        store.emailEnrollment.canReplayExpiredAttempt
                )

            case .accountPrivacy:
                AccountPrivacyScreen(
                    profile: settingsProfile(from: profile),
                    isWorking: store.account.isDeleting,
                    onBack: popRoute,
                    onEmailEnrollment: {
                        store.emailEnrollment.email = profile.email ?? ""
                        pushRoute(.emailEnrollment)
                    },
                    onRecoveryCode: {
                        pushRoute(.recoveryCode)
                    },
                    onExport: {
                        pushRoute(.accountExport)
                    },
                    onPrivacy: {
                        isNavigatingBack = false
                        informationDocument = .privacy
                    },
                    onTerms: {
                        isNavigatingBack = false
                        informationDocument = .terms
                    },
                    onHelp: {
                        pushRoute(.help)
                    },
                    onDelete: deleteAccount
                )

            case .accountExport:
                AccountExportScreen(
                    export: store.account.export,
                    isLoading: store.account.isExporting,
                    onBack: popRoute,
                    onLoad: exportAccount
                )

            case .recoveryCode:
                RecoveryCodeScreen(
                    issuedCode: store.recovery.issuedCode,
                    isSubmitting: store.recovery.isSubmitting,
                    onBack: closeRecoveryCode,
                    onCreate: createRecoveryCode
                )

            case .notificationSettings:
                NotificationSettingsScreen(
                    preferences: $notificationDraft,
                    permissionState: pushAuthorizationState,
                    isSaving: store.notificationPreferences.isSaving,
                    onBack: popRoute,
                    onRequestPermission: requestPushPermission,
                    onOpenSystemSettings: openAppSettings,
                    onSave: saveNotificationPreferences
                )
                .task {
                    await prepareNotificationSettings()
                }

            case .answerEditor(let answerID):
                LifecyclePage(title: "送った回答", onBack: popRoute) {
                    Text("送った回答は変更・削除できません。続きはコメントで伝えられます。")
                        .font(TsutsuuraTheme.bodyFont(22))
                        .foregroundStyle(.white)
                    if let answer = answer(withID: answerID) {
                        AnswerCard(
                            answer: answer, actionMode: .profile, canLike: false,
                            onLike: {}, onComments: { openComments(answer) },
                            loadMedia: AnswerMediaLoader { media in try await store.fetchAnswerMedia(media) }
                        )
                    }
                }

            case .commentEditor(_, let answerID):
                commentsScreen(answerID: answerID, currentUserID: profile.id)

            case .historyFilters:
                HistoryFilterScreen(
                    query: Binding(
                        get: { store.history.query },
                        set: { store.setHistoryQuery($0) }
                    ),
                    members: currentFamily(profile: profile)?.members ?? [],
                    onBack: popRoute,
                    onApply: {
                        popRoute()
                        Task { await store.loadHistory() }
                    }
                )

            case .help:
                HelpScreen(
                    isManagedUser: profile.managed == true,
                    onBack: popRoute,
                    onReplayOnboarding: {
                        essentialsPage = 0
                        pushRoute(.essentials)
                    }
                )

            case .todayQuestion:
                if let question = store.question.question, question.isAvailable == false {
                    let schedule = QuestionSchedulePresentation(question: question)
                    LifecyclePage(title: "次の質問", onBack: popRoute) {
                        PaperPanel {
                            VStack(spacing: 18) {
                                Text(schedule.title)
                                    .font(TsutsuuraTheme.displayFont(28))
                                if let release = schedule.releaseInScheduleTimeZone {
                                    Text(release)
                                        .font(TsutsuuraTheme.bodyFont(24))
                                }
                                if let localRelease = schedule.releaseInLocalTimeZone {
                                    Text(localRelease)
                                        .font(TsutsuuraTheme.bodyFont(21))
                                }
                                Text("ホームで、家族の回答を読んでみましょう。")
                                    .font(TsutsuuraTheme.bodyFont(21))
                            }
                            .foregroundStyle(TsutsuuraTheme.ink)
                            .padding(24)
                        }
                    }
                    .task(id: question.availableAt) {
                        guard let release = question.availableAt else { return }
                        do { try await Task.sleep(for: .seconds(max(0, release.timeIntervalSinceNow))) }
                        catch { return }
                        _ = await store.loadTodayQuestion()
                    }
                } else if let question = store.question.question {
                    QuestionScreen(
                        question: question,
                        answerText: Binding(
                            get: { store.question.draft },
                            set: { store.question.draft = $0 }
                        ),
                        voiceRecording: store.question.answerDraft.voiceRecording,
                        photos: store.question.answerDraft.photos,
                        isSubmitting: store.question.isSubmitting,
                        onBack: popRoute,
                        onVoice: presentVoiceAnswer,
                        onAddPhotos: { photos in
                            store.addAnswerPhotos(photos)
                        },
                        onRemoveVoice: {
                            store.setAnswerVoiceRecording(nil)
                        },
                        onRemovePhoto: { photoID in
                            store.removeAnswerPhoto(id: photoID)
                        },
                        onMediaError: { message in
                            localErrorMessage = message
                        },
                        onSubmit: submitAnswer,
                        hasNewQuestion: store.question.pendingQuestion != nil,
                        onNewQuestion: { confirmsQuestionChange = true }
                    )
                } else {
                    RestoringScreen(message: "質問を読み込み中…")
                        .task {
                            await store.loadTodayQuestion()
                        }
                }

            case .comments(let answerID):
                commentsScreen(
                    answerID: answerID,
                    currentUserID: profile.id
                )

            case .settings:
                SettingsScreen(
                    profile: settingsProfile(from: profile),
                    displayName: $settingsDisplayName,
                    onBack: popRoute,
                    onSaveName: saveDisplayName,
                    onFamilySettings: openFamilyManagement,
                    onRefresh: refreshAll,
                    onSignOut: signOut,
                    onNotificationSettings: {
                        pushRoute(.notificationSettings)
                    },
                    onAccountPrivacy: {
                        pushRoute(.accountPrivacy)
                    },
                    onHelp: {
                        pushRoute(.help)
                    },
                    onPersonalMark: { pushRoute(.personalMark) }
                )

            case .essentials:
                EssentialsWalkthroughScreen(
                    page: $essentialsPage,
                    onBack: goBackInEssentials,
                    onFinished: { finishEssentials() },
                    onPersonalize: {
                        pushRoute(.personalMark)
                    },
                    permissionState: pushAuthorizationState,
                    isRequestingPermission: isRequestingPushPermission,
                    onRequestPermission: requestPushPermission,
                    onOpenSystemSettings: openAppSettings,
                    completionTitle: store.path.contains(.help) ? "案内を閉じる" : "つつうらをはじめる"
                )

            case .personalMark:
                PersonalMarkEditor(
                    displayName: profile.displayName,
                    mark: profile.avatarMark,
                    onBack: {
                        guard store.path.last == .personalMark, !isSavingPersonalMark else { return }
                        popRoute()
                    },
                    onSave: { mark in await store.updatePersonalMark(mark) },
                    onSavingChanged: { isSavingPersonalMark = $0 }
                )

            case .answerHistory:
                homeScreen(profile: profile, forcing: .profile)

            case .home:
                homeScreen(profile: profile)

            case .emailEntry,
                 .emailVerification,
                 .phoneEntry,
                 .otpVerification,
                 .accountRecovery,
                 .onboarding,
                 .organizerSetup,
                 .pairingEntry:
                homeScreen(profile: profile)
            }
        }
    }

    private func homeScreen(
        profile: UserProfile,
        forcing tab: HomeTab? = nil
    ) -> some View {
        let feed = store.home.feed ?? HomeFeed(
            family: profile.family,
            todayQuestion: store.question.question,
            answers: [],
            nextCursor: nil
        )

        return HomeScreen(
            feed: feed,
            history: store.history.answers,
            currentUserID: profile.id,
            selectedTab: Binding(
                get: { tab ?? selectedTab },
                set: { newTab in
                    selectedTab = newTab
                    if newTab == .profile {
                        Task {
                            await store.loadHistory()
                        }
                    }
                }
            ),
            onQuestion: openTodayQuestion,
            onSettings: openSettings,
            onLike: { answer in
                Task {
                    await store.toggleLike(answerID: answer.id)
                }
            },
            onComments: openComments,
            loadMedia: AnswerMediaLoader { media in
                try await store.fetchAnswerMedia(media)
            },
            isLoadingFamily: store.home.feed == nil && store.home.isLoading,
            isLoadingHistory: !store.history.hasLoaded && store.history.isLoading,
            hasMoreHistory: store.history.nextCursor != nil,
            isLoadingMoreHistory: store.history.isLoadingMore,
            hasActiveHistoryFilters: store.history.query.hasActiveFilters
                || store.history.query.scope != .mine,
            currentHistorySearchText: store.history.query.searchText,
            onHistorySearch: { text in
                var query = HistoryQuery()
                query.searchText = HistoryQuery.normalizedSearchText(text)
                store.setHistoryQuery(query)
                Task { await store.loadHistory() }
            },
            onLoadMoreHistory: {
                Task { await store.loadHistory(loadMore: true) }
            },
            hasMoreFamilyAnswers: store.home.feed?.nextCursor != nil,
            isLoadingMoreFamilyAnswers: store.home.isLoadingMore,
            onLoadMoreFamilyAnswers: {
                Task { await store.loadMoreHomeAnswers() }
            }
        )
        .task {
            if store.home.feed == nil { await store.refreshHome() }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await HomeAutoRefresh.run {
                await store.refreshHomeInBackground(includingHistory: (tab ?? selectedTab) == .profile)
            }
        }
        .task(id: feed.todayQuestion?.availableAt) {
            guard let question = feed.todayQuestion, question.isAvailable == false,
                  let release = question.availableAt else { return }
            let seconds = release.timeIntervalSinceNow
            if seconds > 0 {
                do { try await Task.sleep(for: .seconds(seconds)) }
                catch { return }
            }
            while store.home.isLoading {
                do { try await Task.sleep(for: .milliseconds(100)) }
                catch { return }
            }
            await store.refreshHome()
        }
    }

    @ViewBuilder
    private func commentsScreen(
        answerID: String,
        currentUserID: String
    ) -> some View {
        if let answer = answer(withID: answerID) {
            let thread = store.commentThreads[answerID] ?? CommentThreadState()

            CommentsScreen(
                answer: answer,
                comments: thread.comments,
                currentUserID: currentUserID,
                focusedCommentID: thread.focusedCommentID,
                hasMoreComments: thread.nextCursor != nil,
                draft: Binding(
                    get: {
                        store.commentThreads[answerID]?.draft ?? ""
                    },
                    set: {
                        store.setCommentDraft($0, answerID: answerID)
                    }
                ),
                isLoading: thread.isLoading || thread.isPosting,
                onBack: popRoute,
                onSend: {
                    Task {
                        await store.postComment(answerID: answerID)
                    }
                },
                onLoadMore: {
                    Task {
                        await store.loadComments(
                            answerID: answerID,
                            loadMore: true
                        )
                    }
                },
                loadMedia: AnswerMediaLoader { media in
                    try await store.fetchAnswerMedia(media)
                },
                onReply: { comment in
                    let body = store.commentThreads[answerID]?.draft ?? ""
                    Task {
                        if await store.replyToComment(
                            answerID: answerID,
                            parentCommentID: comment.id,
                            body: body
                        ) {
                            store.setCommentDraft("", answerID: answerID)
                        }
                    }
                },
                onReport: { comment in
                    Task {
                        _ = await store.reportComment(
                            commentID: comment.id,
                            answerID: answerID,
                            reason: .inappropriate
                        )
                    }
                }
            )
            .task {
                if store.commentThreads[answerID]?.comments.isEmpty != false {
                    await store.loadComments(answerID: answerID)
                }
            }
        } else {
            RestoringScreen(message: "回答を読み込み中…")
        }
    }

    private var routeIdentity: String {
        switch store.session {
        case .restoring:
            return "restoring"
        case .signedOut:
            return "signedOut-\(String(describing: store.path.last ?? .onboarding))"
        case .awaitingOTP:
            return "legacy-recovery"
        case .awaitingEmailVerification:
            return "email-verification"
        case .signedIn(let profile):
            if store.requiresPersonalMarkSetup {
                return "required-personal-mark-\(profile.id)-\(store.personalMarkRequirementIsConfirmed)"
            }
            if let informationDocument {
                return "information-\(informationDocument.rawValue)"
            }
            if isVoiceAnswerPresented {
                return "voice"
            }
            return String(describing: store.path.last ?? .home)
        }
    }

    private var displayedErrorMessage: String? {
        [
            localErrorMessage,
            store.globalErrorMessage,
            store.familySetup.errorMessage,
            store.familyLifecycle.errorMessage,
            store.emailAuth.errorMessage,
            store.emailEnrollment.errorMessage,
            store.answerOwnership.errorMessage,
            store.notificationPreferences.errorMessage,
            store.account.errorMessage,
            store.recovery.errorMessage,
            activeCommentErrorMessage,
            store.auth.errorMessage,
            store.question.errorMessage,
            store.home.errorMessage,
            store.history.errorMessage,
        ].compactMap { $0 }.first
    }

    private var activeCommentAnswerID: String? {
        guard let route = store.path.last,
              case .comments(let answerID) = route else {
            return nil
        }
        return answerID
    }

    private var activeCommentErrorMessage: String? {
        guard let activeCommentAnswerID else { return nil }
        return store.commentThreads[activeCommentAnswerID]?.errorMessage
    }

    private func dismissPresentedErrors() {
        localErrorMessage = nil
        store.dismissPresentedErrors(
            commentAnswerID: activeCommentAnswerID
        )
    }

    private func answer(withID answerID: String) -> Answer? {
        if let answer = store.home.feed?.answers.first(where: { $0.id == answerID }) {
            return answer
        }
        if let answer = store.history.answers.first(where: { $0.id == answerID }) {
            return answer
        }
        if store.question.question?.answer?.id == answerID {
            return store.question.question?.answer
        }
        return nil
    }

    private func settingsProfile(from profile: UserProfile) -> UserProfile {
        var updatedProfile = profile
        updatedProfile.family = store.familySetup.family
            ?? store.home.feed?.family
            ?? profile.family
        return updatedProfile
    }

    private func currentFamily(profile: UserProfile) -> FamilySummary? {
        store.familySetup.family
            ?? store.home.feed?.family
            ?? profile.family
    }

    private var otpExpirationDate: Date? {
        if let expiresAt = store.emailAuth.expiresAt {
            return expiresAt
        }
        guard let otpIssuedAt,
              let challenge = store.emailAuth.challenge else { return nil }
        return otpIssuedAt.addingTimeInterval(
            TimeInterval(challenge.expiresIn)
        )
    }

    private var emailEnrollmentExpirationDate: Date? {
        if let expiresAt = store.emailEnrollment.expiresAt {
            return expiresAt
        }
        guard let emailEnrollmentIssuedAt,
              let challenge = store.emailEnrollment.challenge else {
            return nil
        }
        return emailEnrollmentIssuedAt.addingTimeInterval(
            TimeInterval(challenge.expiresIn)
        )
    }

    private func requestEmailOTP() {
        isNavigatingBack = false
        Task {
            if await store.requestEmailOTP() {
                otpIssuedAt = Date()
                otpResendAvailableAt = Date().addingTimeInterval(30)
            }
        }
    }

    private func requestEmailEnrollment() {
        isNavigatingBack = false
        Task {
            if await store.requestEmailEnrollment() {
                emailEnrollmentIssuedAt = Date()
                emailEnrollmentResendAvailableAt = Date()
                    .addingTimeInterval(30)
            }
        }
    }

    private func verifyEmailEnrollment() {
        isNavigatingBack = true
        Task {
            if await store.verifyEmailEnrollment() {
                emailEnrollmentIssuedAt = nil
                emailEnrollmentResendAvailableAt = nil
            }
        }
    }

    private func showFamilyWelcome() {
        isNavigatingBack = true
        guard !store.familySetup.isSubmitting else { return }
        store.familySetup.pairingCode = ""
        store.familySetup.pairingToken = nil
        store.familySetup.pairingPreview = nil
        withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion)) {
            store.path = [.onboarding]
        }
    }

    private func showEmailLogin() {
        isNavigatingBack = false
        guard !store.familySetup.isSubmitting else { return }
        withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion)) {
            store.path = [.onboarding, .emailEntry]
        }
    }

    private func showAccountRecovery() {
        isNavigatingBack = false
        guard !store.familySetup.isSubmitting else { return }
        store.recovery.codeInput = ""
        withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion)) {
            store.path = [.onboarding, .accountRecovery]
        }
    }

    private func recoverAccount() {
        isNavigatingBack = false
        Task {
            _ = await store.recoverAccount()
        }
    }

    private func createRecoveryCode() {
        Task {
            _ = await store.createAccountRecoveryCode()
        }
    }

    private func closeRecoveryCode() {
        store.recovery.issuedCode = nil
        popRoute()
    }

    private func showOrganizerSetup() {
        isNavigatingBack = false
        guard !store.familySetup.isSubmitting else { return }
        withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion)) {
            store.path = [.onboarding, .organizerSetup]
        }
    }

    private func showPairingEntry() {
        isNavigatingBack = false
        guard !store.familySetup.isSubmitting else { return }
        store.familySetup.pairingPreview = nil
        store.familySetup.pairingToken = nil
        withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion)) {
            store.path = [.onboarding, .pairingEntry]
        }
    }

    private func cancelPairingConfirmation() {
        isNavigatingBack = true
        guard !store.familySetup.isSubmitting else { return }

        if case .signedOut = store.session {
            // Leave the confirmation route before clearing its preview. If the
            // preview disappears first, that route's restoration task can
            // resubmit the still-valid code and bounce straight back here.
            withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion)) {
                store.path = [.onboarding, .pairingEntry]
                store.familySetup.pairingPreview = nil
                store.familySetup.pairingToken = nil
            }
        } else {
            store.familySetup.pairingPreview = nil
            store.familySetup.pairingToken = nil
            store.familySetup.pairingCode = ""
            popRoute()
        }
    }

    private func createOrganizerFamily() {
        isNavigatingBack = false
        Task {
            await store.createOrganizerFamily()
        }
    }

    private func createManagedMemberPairing() {
        isNavigatingBack = false
        Task {
            await store.createManagedMemberPairing()
        }
    }

    private func createPairingForMember(_ member: UserProfile) {
        Task {
            await store.createPairing(for: member)
        }
    }

    private func previewFamilyPairing() {
        isNavigatingBack = false
        Task {
            await store.previewFamilyPairing()
        }
    }

    private func activateFamilyPairing() {
        isNavigatingBack = false
        Task {
            await store.activateFamilyPairing()
            guard case .signedIn = store.session,
                  store.path.last == .pairingReady else {
                return
            }
        }
    }

    private func goBackInEssentials() {
        guard store.path.last == .essentials else { return }
        isNavigatingBack = true
        if essentialsPage > 0 {
            essentialsPage -= 1
        } else {
            finishEssentials(isGoingBack: true)
        }
    }

    private func finishEssentials(isGoingBack: Bool = false) {
        guard store.path.last == .essentials,
              case .signedIn(let profile) = store.session else { return }
        UserDefaults.standard.set(true, forKey: "essentials-v2-\(profile.id)")
        if store.path.contains(.help) {
            popRoute()
        } else {
            isNavigatingBack = isGoingBack
            store.path = [.home]
        }
    }

    private func finishFamilySetup() {
        isNavigatingBack = false
        guard !store.familySetup.isSubmitting else { return }
        Task {
            await store.finishFamilySetup()
            if case .signedIn(let profile) = store.session,
               !UserDefaults.standard.bool(forKey: "essentials-v2-\(profile.id)") {
                essentialsPage = 0
                pushRoute(.essentials)
            }
        }
    }

    private func finishSharingPairing() {
        guard !store.familySetup.isSubmitting else { return }
        store.familySetup.activePairing = nil
        popRoute()
        Task {
            await store.loadFamilySetup()
        }
    }

    private func loadFamilySetup() {
        Task {
            await store.loadFamilySetup()
        }
    }

    private func verifyEmailOTP() {
        isNavigatingBack = false
        Task {
            await store.verifyEmailOTP()
            if case .signedIn = store.session {
                otpIssuedAt = nil
                otpResendAvailableAt = nil
            }
        }
    }

    private func retrySessionRestore() {
        Task {
            await store.restoreSession()
        }
    }

    private func returnToLogin() {
        isNavigatingBack = true
        otpIssuedAt = nil
        otpResendAvailableAt = nil
        withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion)) {
            if case .awaitingOTP = store.session { store.cancelOTP() }
            else { store.cancelEmailOTP() }
        }
    }

    private func openTodayQuestion() {
        Task {
            let loaded = await store.loadTodayQuestion()
            if store.question.pendingQuestion != nil {
                confirmsQuestionChange = true
                return
            }
            guard loaded, store.question.question != nil else { return }
            withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion)) {
                pushRoute(.todayQuestion)
            }
        }
    }

    private func presentVoiceAnswer() {
        speechTranscriber.reset()
        withAnimation(
            TsutsuuraMotion.respectingReduceMotion(
                reduceMotion,
                TsutsuuraMotion.navigation
            )
        ) {
            isNavigatingBack = false
            isVoiceAnswerPresented = true
        }
    }

    private func dismissVoiceAnswer() {
        isNavigatingBack = true
        speechTranscriber.reset()
        withAnimation(
            TsutsuuraMotion.respectingReduceMotion(
                reduceMotion,
                TsutsuuraMotion.navigation
            )
        ) {
            isVoiceAnswerPresented = false
        }
    }

    private func openAppSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
        #endif
    }

    private func useVoiceTranscript() {
        isNavigatingBack = true
        speechTranscriber.stop()
        guard let recording = speechTranscriber.takeRecording() else {
            localErrorMessage = speechTranscriber.errorMessage
                ?? "音声の録音を保存できませんでした。"
            return
        }
        guard store.setAnswerVoiceRecording(recording) else { return }

        let transcript = speechTranscriber.transcript.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !transcript.isEmpty {
            store.question.draft = transcript
        }
        // Accepting a recording is a state commit, so return to the editor
        // immediately. A long route transition can otherwise leave the user
        // looking at a completed recording with no apparent response.
        isVoiceAnswerPresented = false
    }

    private func submitAnswer() {
        Task {
            let answerBeforeSubmission = store.question.question?.answer
            await store.submitAnswer()
            guard answerBeforeSubmission == nil,
                  store.question.question?.answer != nil else {
                return
            }

            withAnimation(
                TsutsuuraMotion.respectingReduceMotion(
                    reduceMotion,
                    TsutsuuraMotion.emphasizedSpring
                )
            ) {
                showAnswerSuccess = true
            }
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion)) {
                showAnswerSuccess = false
                popRoute()
            }
            await store.refreshHome()
            await store.loadHistory()
        }
    }

    private func openSettings() {
        if case .signedIn(let profile) = store.session {
            settingsDisplayName = profile.displayName
        }
        withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion)) {
            pushRoute(.settings)
        }
    }

    private func openFamilyManagement() {
        if store.familySetup.family == nil,
           let family = store.home.feed?.family {
            store.familySetup.family = family
        }
        withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion)) {
            pushRoute(.familyManagement)
        }
        Task {
            await store.loadFamilySetup()
        }
    }

    private func openComments(_ answer: Answer) {
        isNavigatingBack = false
        withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion)) {
            store.openComments(answerID: answer.id)
        }
    }

    private func pushRoute(_ route: AppRoute) {
        guard !store.requiresPersonalMarkSetup else { return }
        isNavigatingBack = false
        withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion, TsutsuuraMotion.navigation)) {
            store.path.append(route)
        }
    }

    private func popRoute() {
        guard !store.requiresPersonalMarkSetup else { return }
        isNavigatingBack = true
        guard !store.path.isEmpty else { return }
        withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion)) {
            if store.path.count > 1 {
                store.path.removeLast()
            } else {
                store.path = [.home]
            }
        }
    }

    private func refreshAll() async -> Bool {
        await store.refreshAllData()
    }

    private func saveDisplayName() async -> Bool {
        await store.updateDisplayName(settingsDisplayName)
    }

    private func exportAccount() {
        Task {
            _ = await store.exportAccount()
        }
    }

    private func deleteAccount() {
        Task {
            if await store.deleteAccount() {
                PushNotificationRegistration.unregister()
                pushRegistration.setUserID(nil)
                AnswerMediaViewCache.clear()
                informationDocument = nil
                selectedTab = .family
            }
        }
    }

    private func prepareNotificationSettings() async {
        async let permission: Void = refreshPushAuthorization()
        await store.loadNotificationPreferences()
        await permission
        if let preferences = store.notificationPreferences.preferences {
            notificationDraft = preferences
        }
    }

    private func requestPushPermission() {
        guard !isRequestingPushPermission else { return }
        isRequestingPushPermission = true
        Task {
            defer { isRequestingPushPermission = false }
            await refreshPushAuthorization(requestPermission: true)
        }
    }

    private func refreshPushRegistrationIfAuthorized() {
        Task { await refreshPushAuthorization() }
    }

    private func refreshPushAuthorization(requestPermission: Bool = false) async {
        guard case .signedIn(let profile) = store.session else { return }
        pushRegistration.setUserID(profile.id)
        let state = await pushRegistration.refreshAuthorization(requestsPermission: requestPermission) {
            if requestPermission {
                return await PushNotificationRegistration.requestAuthorizationIfNeeded()
            }
            return await PushNotificationRegistration.registerIfAuthorized()
        }
        guard case .signedIn = store.session else { return }
        if let state {
            pushAuthorizationState = state
            store.setNotificationPermissionStatus(notificationPermissionStatus(from: state))
        }
        registerPushTokenIfPossible()
    }

    private func saveNotificationPreferences() {
        let visit = store.navigationVisit()
        var preferences = notificationDraft
        // The timezone can change while this form is open. Saving switches
        // must not restore an older timezone copied when the page opened.
        preferences.timeZoneIdentifier = TimeZone.autoupdatingCurrent.identifier
        Task {
            let mayDismiss = await store.finishSave(from: visit) {
                await store.updateNotificationPreferences(preferences)
            }
            if mayDismiss {
                popRoute()
            }
        }
    }

    private func notificationPermissionStatus(
        from state: PushAuthorizationState
    ) -> NotificationPermissionStatus {
        switch state {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        case .provisional: .provisional
        case .ephemeral: .ephemeral
        case .unavailable: .unknown
        }
    }

    private func signOut() {
        isNavigatingBack = true
        Task {
            await store.signOut()
            guard case .signedOut = store.session else { return }
            PushNotificationRegistration.unregister()
            pushRegistration.setUserID(nil)
            AnswerMediaViewCache.clear()
            selectedTab = .family
        }
    }

    private func registerPushTokenIfPossible() {
        guard case .signedIn(let profile) = store.session else { return }
        pushRegistration.setUserID(profile.id)
        Task {
            await pushRegistration.synchronize { token, expectedUserID in
                guard case .signedIn(let currentProfile) = store.session,
                      currentProfile.id == expectedUserID else { return false }
                #if DEBUG
                let environment = PushEnvironment.sandbox
                #else
                let environment = PushEnvironment.production
                #endif
                return await store.registerPushToken(token, environment: environment)
            }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard let token = pairingToken(from: url) else { return }
        store.preparePairingToken(token)

        guard store.session != .restoring else { return }
        previewIncomingPairing()
    }

    private func previewIncomingPairing() {
        guard !store.requiresPersonalMarkSetup else { return }
        isNavigatingBack = false
        Task {
            await store.previewFamilyPairing()
        }
    }

    private func pairingToken(from url: URL) -> String? {
        PairingLinkParser.token(from: url)
    }

    private func consumePendingPushDestination() async {
        await pushDestinations.consume(
            from: PendingPushDestinationStore.shared,
            isAvailable: {
                guard case .signedIn = store.session else { return false }
                return !store.requiresPersonalMarkSetup
            },
            open: openPushDestination
        )
    }

    private func openPushDestination(_ destination: AppPushDestination) async -> Bool {
        let didOpen: Bool
        switch destination {
        case .todayQuestion(let expectedQuestionID):
            let resolution = await store.loadTodayQuestionForPush(
                expectedQuestionID: expectedQuestionID
            )
            didOpen = resolution != .retryable
            if resolution == .ready {
                withAnimation(
                    TsutsuuraMotion.respectingReduceMotion(reduceMotion)
                ) {
                    pushRoute(.todayQuestion)
                }
            }
        case .familyAnswer(let answerID):
            didOpen = await store.openPushAnswer(answerID: answerID)
        case .comments(let answerID, let commentID):
            didOpen = await store.openPushAnswer(
                answerID: answerID,
                targetCommentID: commentID
            )
        }
        return didOpen
    }

    private static let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct RestoringScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var message = "読み込み中…"
    var retryTitle = "再試行"
    var onRetry: (() -> Void)?
    var secondaryTitle: String?
    var onSecondary: (() -> Void)?
    var isWorking = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            DottedBackdrop()

            VStack(spacing: 26) {
                TsutsuuraWordmark(size: 82)
                    .scaleEffect(pulse && !reduceMotion ? 1.04 : 0.97)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 0.82)
                                .repeatForever(autoreverses: true),
                        value: pulse
                    )

                Text(message)
                    .font(TsutsuuraTheme.font(25))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                if let onRetry {
                    TextRaisedButton(
                        title: retryTitle,
                        icon: "arrow.clockwise",
                        height: 62,
                        fontSize: 27,
                        action: onRetry
                    )
                    .frame(width: 180)
                    .disabled(isWorking)
                }

                if let secondaryTitle,
                   let onSecondary {
                    Button(secondaryTitle, action: onSecondary)
                        .font(TsutsuuraTheme.font(23))
                        .foregroundStyle(.white)
                        .frame(minWidth: 220, minHeight: 58)
                        .disabled(isWorking)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            pulse = true
        }
    }
}

#if DEBUG
#Preview {
    ContentView()
}
#endif
