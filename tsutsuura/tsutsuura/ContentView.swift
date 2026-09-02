import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

@MainActor
struct ContentView: View {
    @StateObject private var store: AppStore
    @StateObject private var speechTranscriber = SpeechTranscriber()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab: HomeTab = .family
    @State private var isVoiceAnswerPresented = false
    @State private var showAnswerSuccess = false
    @State private var localErrorMessage: String?
    @State private var pendingPushToken: String?
    @State private var settingsDisplayName = ""
    @State private var otpIssuedAt: Date?
    @State private var otpResendAvailableAt: Date?
    @State private var phoneEnrollmentIssuedAt: Date?
    @State private var phoneEnrollmentResendAvailableAt: Date?
    @State private var familyNameDraft = ""
    @State private var managedMemberNameDraft = ""
    @State private var answerEditorDraft = ""
    @State private var commentEditorDraft = ""
    @State private var notificationDraft = NotificationPreferences()
    @State private var pushAuthorizationState: PushAuthorizationState = .unavailable
    @State private var informationDocument: InformationDocument?

    init(store: AppStore? = nil) {
        if let store {
            _store = StateObject(wrappedValue: store)
        } else if ProcessInfo.processInfo.environment["UI_TESTING"] == "1" {
            let testURL = URL(
                string: "https://kttprojects.conohawing.com/tsutsuura-api/api"
            )!
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
            let fallbackURL = URL(
                string: "https://kttprojects.conohawing.com/tsutsuura-api/api"
            )!
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
                                insertion: .move(edge: .trailing)
                                    .combined(with: .opacity),
                                removal: .move(edge: .leading)
                                    .combined(with: .opacity)
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
            await consumePendingPushDestination()
        }
        .onOpenURL(perform: handleIncomingURL)
        .onReceive(
            NotificationCenter.default.publisher(for: .didReceivePushToken)
        ) { notification in
            guard let token = notification.object as? String else { return }
            pendingPushToken = token
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
            switch newSession {
            case .signedIn:
                refreshPushRegistrationIfAuthorized()
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
        }
    }

    private var keepsInputScreenFullScaleWithKeyboard: Bool {
        switch store.session {
        case .signedOut, .awaitingOTP:
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

        case .awaitingOTP(let phoneNumber):
            SMSVerificationScreen(
                phoneNumber: phoneNumber,
                code: Binding(
                    get: { store.auth.verificationCode },
                    set: { store.auth.verificationCode = $0 }
                ),
                isLoading: store.auth.isSubmitting,
                onBack: returnToLogin,
                onResend: requestOTP,
                onVerify: verifyOTP,
                expiresAt: otpExpirationDate,
                resendAvailableAt: otpResendAvailableAt,
                canReplayExpiredAttempt: store.auth.canReplayExpiredAttempt
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

        case .phoneEntry:
            LoginScreen(
                phoneNumber: Binding(
                    get: { store.auth.phoneNumber },
                    set: { store.auth.phoneNumber = $0 }
                ),
                isLoading: store.auth.isSubmitting,
                onBack: showFamilyWelcome,
                onPhoneAuthentication: requestOTP
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
                onReturningUserLogin: showPhoneLogin,
                onAccountRecovery: showAccountRecovery
            )
        }
    }

    @ViewBuilder
    private func signedInContent(profile: UserProfile) -> some View {
        if let informationDocument {
            InformationDocumentScreen(
                document: informationDocument,
                onBack: { self.informationDocument = nil }
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
                            store.path.append(.familyRename)
                        },
                        onEditMember: { member in
                            managedMemberNameDraft = member.displayName
                            store.path.append(
                                .managedMemberEdit(memberID: member.id)
                            )
                        },
                        onTransferOwnership: {
                            store.path.append(.ownershipTransfer)
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

            case .phoneEnrollment:
                PhoneEnrollmentScreen(
                    phoneNumber: $store.phoneEnrollment.phoneNumber,
                    isSubmitting: store.phoneEnrollment.isSubmitting,
                    onBack: {
                        store.cancelPhoneEnrollment()
                    },
                    onContinue: requestPhoneEnrollment
                )

            case .phoneEnrollmentVerification:
                SMSVerificationScreen(
                    phoneNumber: store.phoneEnrollment.phoneNumber,
                    code: $store.phoneEnrollment.verificationCode,
                    isLoading: store.phoneEnrollment.isSubmitting,
                    onBack: { store.cancelPhoneEnrollment() },
                    onResend: requestPhoneEnrollment,
                    onVerify: verifyPhoneEnrollment,
                    confirmationTitle: "電話番号を登録",
                    expiresAt: phoneEnrollmentExpirationDate,
                    resendAvailableAt: phoneEnrollmentResendAvailableAt,
                    canReplayExpiredAttempt:
                        store.phoneEnrollment.canReplayExpiredAttempt
                )

            case .accountPrivacy:
                AccountPrivacyScreen(
                    profile: settingsProfile(from: profile),
                    isWorking: store.account.isDeleting,
                    onBack: popRoute,
                    onPhoneEnrollment: {
                        store.path.append(.phoneEnrollment)
                    },
                    onRecoveryCode: {
                        store.path.append(.recoveryCode)
                    },
                    onExport: {
                        store.path.append(.accountExport)
                    },
                    onPrivacy: {
                        informationDocument = .privacy
                    },
                    onTerms: {
                        informationDocument = .terms
                    },
                    onHelp: {
                        store.path.append(.help)
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
                if let answer = answer(withID: answerID) {
                    AnswerEditorScreen(
                        answer: answer,
                        bodyText: $answerEditorDraft,
                        isSaving: store.answerOwnership.mutatingAnswerIDs
                            .contains(answerID),
                        onBack: popRoute,
                        onSave: {
                            Task {
                                if await store.updateAnswer(
                                    answerID: answerID,
                                    submission: AnswerSubmission(
                                        body: answerEditorDraft
                                    )
                                ) {
                                    popRoute()
                                }
                            }
                        },
                        onDeleteMedia: { media in
                            Task {
                                _ = await store.deleteAnswerMedia(
                                    answerID: answerID,
                                    mediaID: media.id
                                )
                            }
                        },
                        onDeleteAnswer: {
                            Task {
                                if await store.deleteAnswer(answerID: answerID) {
                                    popRoute()
                                }
                            }
                        }
                    )
                } else {
                    RestoringScreen(
                        message: "回答が見つかりません",
                        retryTitle: "戻る",
                        onRetry: popRoute
                    )
                }

            case .commentEditor(let commentID, let answerID):
                if let comment = store.commentThreads[answerID]?.comments
                    .first(where: { $0.id == commentID }) {
                    CommentEditorScreen(
                        comment: comment,
                        bodyText: $commentEditorDraft,
                        isSaving: store.commentThreads[answerID]?.isMutating
                            ?? false,
                        onBack: popRoute,
                        onSave: {
                            Task {
                                if await store.updateComment(
                                    commentID: commentID,
                                    answerID: answerID,
                                    body: commentEditorDraft
                                ) {
                                    popRoute()
                                }
                            }
                        }
                    )
                } else {
                    RestoringScreen(
                        message: "コメントが見つかりません",
                        retryTitle: "戻る",
                        onRetry: popRoute
                    )
                }

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
                    onReplayOnboarding: {}
                )

            case .todayQuestion:
                if let question = store.question.question {
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
                        onSubmit: submitAnswer
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
                        store.path.append(.notificationSettings)
                    },
                    onAccountPrivacy: {
                        store.path.append(.accountPrivacy)
                    },
                    onHelp: {
                        store.path.append(.help)
                    }
                )

            case .answerHistory:
                homeScreen(profile: profile, forcing: .profile)

            case .home:
                homeScreen(profile: profile)

            case .phoneEntry,
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
        let shouldLoadHistoryOnRefresh = selectedTab == .profile
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
            isRefreshing: store.home.isLoading
                || (selectedTab == .profile && store.history.isLoading),
            onRefresh: {
                await store.refreshHome()
                if shouldLoadHistoryOnRefresh {
                    await store.loadHistory()
                }
            },
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
            hasMoreHistory: store.history.nextCursor != nil,
            isLoadingMoreHistory: store.history.isLoadingMore,
            hasActiveHistoryFilters: store.history.query.hasActiveFilters
                || store.history.query.scope != .mine,
            currentHistorySearchText: store.history.query.searchText,
            onHistorySearch: { text in
                var query = store.history.query
                query.searchText = HistoryQuery.normalizedSearchText(text)
                store.setHistoryQuery(query)
                Task { await store.loadHistory() }
            },
            onHistoryFilters: {
                store.path.append(.historyFilters)
            },
            onHistoryJumpToToday: {
                var query = store.history.query
                let today = Self.historyDateFormatter.string(from: Date())
                query.startDate = today
                query.endDate = today
                store.setHistoryQuery(query)
                Task { await store.loadHistory() }
            },
            onLoadMoreHistory: {
                Task { await store.loadHistory(loadMore: true) }
            },
            onEditAnswer: { answer in
                answerEditorDraft = answer.body
                store.path.append(.answerEditor(answerID: answer.id))
            },
            hasMoreFamilyAnswers: store.home.feed?.nextCursor != nil,
            isLoadingMoreFamilyAnswers: store.home.isLoadingMore,
            onLoadMoreFamilyAnswers: {
                Task { await store.loadMoreHomeAnswers() }
            }
        )
        .task {
            if store.home.feed == nil {
                await store.refreshHome()
            }
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
                onDelete: { comment in
                    Task {
                        await store.deleteComment(
                            commentID: comment.id,
                            answerID: answerID
                        )
                    }
                },
                loadMedia: AnswerMediaLoader { media in
                    try await store.fetchAnswerMedia(media)
                },
                onEdit: { comment in
                    commentEditorDraft = comment.body
                    store.path.append(
                        .commentEditor(
                            commentID: comment.id,
                            answerID: answerID
                        )
                    )
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
            return "otp"
        case .signedIn:
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
            store.phoneEnrollment.errorMessage,
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
        if let expiresAt = store.auth.expiresAt {
            return expiresAt
        }
        guard let otpIssuedAt,
              let challenge = store.auth.challenge else { return nil }
        return otpIssuedAt.addingTimeInterval(
            TimeInterval(challenge.expiresIn)
        )
    }

    private var phoneEnrollmentExpirationDate: Date? {
        if let expiresAt = store.phoneEnrollment.expiresAt {
            return expiresAt
        }
        guard let phoneEnrollmentIssuedAt,
              let challenge = store.phoneEnrollment.challenge else {
            return nil
        }
        return phoneEnrollmentIssuedAt.addingTimeInterval(
            TimeInterval(challenge.expiresIn)
        )
    }

    private func requestOTP() {
        Task {
            if await store.requestOTP() {
                otpIssuedAt = Date()
                otpResendAvailableAt = Date().addingTimeInterval(30)
            }
        }
    }

    private func requestPhoneEnrollment() {
        Task {
            if await store.requestPhoneEnrollment() {
                phoneEnrollmentIssuedAt = Date()
                phoneEnrollmentResendAvailableAt = Date()
                    .addingTimeInterval(30)
            }
        }
    }

    private func verifyPhoneEnrollment() {
        Task {
            if await store.verifyPhoneEnrollment() {
                phoneEnrollmentIssuedAt = nil
                phoneEnrollmentResendAvailableAt = nil
            }
        }
    }

    private func showFamilyWelcome() {
        guard !store.familySetup.isSubmitting else { return }
        store.familySetup.pairingCode = ""
        store.familySetup.pairingToken = nil
        store.familySetup.pairingPreview = nil
        withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion)) {
            store.path = [.onboarding]
        }
    }

    private func showPhoneLogin() {
        guard !store.familySetup.isSubmitting else { return }
        withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion)) {
            store.path = [.onboarding, .phoneEntry]
        }
    }

    private func showAccountRecovery() {
        guard !store.familySetup.isSubmitting else { return }
        store.recovery.codeInput = ""
        withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion)) {
            store.path = [.onboarding, .accountRecovery]
        }
    }

    private func recoverAccount() {
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
        guard !store.familySetup.isSubmitting else { return }
        withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion)) {
            store.path = [.onboarding, .organizerSetup]
        }
    }

    private func showPairingEntry() {
        guard !store.familySetup.isSubmitting else { return }
        store.familySetup.pairingPreview = nil
        store.familySetup.pairingToken = nil
        withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion)) {
            store.path = [.onboarding, .pairingEntry]
        }
    }

    private func cancelPairingConfirmation() {
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
        Task {
            await store.createOrganizerFamily()
        }
    }

    private func createManagedMemberPairing() {
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
        Task {
            await store.previewFamilyPairing()
        }
    }

    private func activateFamilyPairing() {
        Task {
            await store.activateFamilyPairing()
            guard case .signedIn = store.session,
                  store.path.last == .pairingReady else {
                return
            }
        }
    }

    private func finishFamilySetup() {
        guard !store.familySetup.isSubmitting else { return }
        Task {
            await store.finishFamilySetup()
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

    private func verifyOTP() {
        Task {
            await store.verifyOTP()
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
        otpIssuedAt = nil
        otpResendAvailableAt = nil
        withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion)) {
            store.cancelOTP()
        }
    }

    private func openTodayQuestion() {
        Task {
            guard await store.loadTodayQuestion(),
                  store.question.question != nil else { return }
            withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion)) {
                store.path.append(.todayQuestion)
            }
        }
    }

    private func presentVoiceAnswer() {
        speechTranscriber.reset()
        withAnimation(
            TsutsuuraMotion.respectingReduceMotion(
                reduceMotion,
                TsutsuuraMotion.emphasizedSpring
            )
        ) {
            isVoiceAnswerPresented = true
        }
    }

    private func dismissVoiceAnswer() {
        speechTranscriber.reset()
        withAnimation(
            TsutsuuraMotion.respectingReduceMotion(
                reduceMotion,
                TsutsuuraMotion.quickSpring
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
            store.path.append(.settings)
        }
    }

    private func openFamilyManagement() {
        if store.familySetup.family == nil,
           let family = store.home.feed?.family {
            store.familySetup.family = family
        }
        withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion)) {
            store.path.append(.familyManagement)
        }
        Task {
            await store.loadFamilySetup()
        }
    }

    private func openComments(_ answer: Answer) {
        withAnimation(TsutsuuraMotion.respectingReduceMotion(reduceMotion)) {
            store.openComments(answerID: answer.id)
        }
    }

    private func popRoute() {
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
                pendingPushToken = nil
                AnswerMediaViewCache.clear()
                informationDocument = nil
                selectedTab = .family
            }
        }
    }

    private func prepareNotificationSettings() async {
        async let state = PushNotificationRegistration.registerIfAuthorized()
        await store.loadNotificationPreferences()
        pushAuthorizationState = await state
        store.setNotificationPermissionStatus(
            notificationPermissionStatus(from: pushAuthorizationState)
        )
        if let preferences = store.notificationPreferences.preferences {
            notificationDraft = preferences
        }
    }

    private func requestPushPermission() {
        Task {
            pushAuthorizationState = await PushNotificationRegistration
                .requestAuthorizationIfNeeded()
            store.setNotificationPermissionStatus(
                notificationPermissionStatus(from: pushAuthorizationState)
            )
        }
    }

    private func refreshPushRegistrationIfAuthorized() {
        Task {
            _ = await PushNotificationRegistration.registerIfAuthorized()
        }
    }

    private func saveNotificationPreferences() {
        Task {
            if await store.updateNotificationPreferences(notificationDraft) {
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
        Task {
            await store.signOut()
            guard case .signedOut = store.session else { return }
            PushNotificationRegistration.unregister()
            pendingPushToken = nil
            AnswerMediaViewCache.clear()
            selectedTab = .family
        }
    }

    private func registerPushTokenIfPossible() {
        guard let token = pendingPushToken,
              case .signedIn = store.session else {
            return
        }
        Task {
            #if DEBUG
            let environment = PushEnvironment.sandbox
            #else
            let environment = PushEnvironment.production
            #endif
            if await store.registerPushToken(token, environment: environment) {
                pendingPushToken = nil
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
        Task {
            await store.previewFamilyPairing()
        }
    }

    private func pairingToken(from url: URL) -> String? {
        PairingLinkParser.token(from: url)
    }

    private func consumePendingPushDestination() async {
        guard case .signedIn = store.session,
              let destination = await PendingPushDestinationStore.shared.peek()
        else {
            return
        }
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
                    store.path.append(.todayQuestion)
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
        if didOpen {
            await PendingPushDestinationStore.shared.acknowledge(destination)
        }
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
                Text("つつうら")
                    .font(TsutsuuraTheme.font(82))
                    .foregroundStyle(TsutsuuraTheme.cyan)
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
        .clipShape(RoundedRectangle(cornerRadius: 50, style: .continuous))
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
