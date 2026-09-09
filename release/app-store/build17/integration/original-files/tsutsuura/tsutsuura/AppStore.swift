import Combine
import Foundation

enum PushDestinationResolution: Equatable, Sendable {
    case ready
    case terminal
    case retryable
}

struct NavigationVisit: Equatable, Sendable {
    fileprivate let revision: UInt64
    fileprivate let path: [AppRoute]
}

struct AuthFeatureState: Equatable, Sendable {
    var phoneNumber = ""
    var verificationCode = ""
    var challenge: OTPChallenge?
    var expiresAt: Date? = nil
    var canReplayExpiredAttempt = false
    var isSubmitting = false
    var errorMessage: String?
}

struct EmailVerificationFeatureState: Equatable, Sendable {
    var email = ""
    var verificationCode = ""
    var challenge: OTPChallenge?
    var expiresAt: Date? = nil
    var canReplayExpiredAttempt = false
    var isSubmitting = false
    var errorMessage: String?
}

struct PhoneEnrollmentFeatureState: Equatable, Sendable {
    var phoneNumber = ""
    var verificationCode = ""
    var challenge: OTPChallenge?
    var expiresAt: Date? = nil
    var canReplayExpiredAttempt = false
    var isSubmitting = false
    var errorMessage: String?
}

struct RecoveryFeatureState: Equatable, Sendable {
    var codeInput = ""
    var issuedCode: AccountRecoveryCode?
    var isSubmitting = false
    var errorMessage: String?
}

struct HomeFeatureState: Equatable, Sendable {
    var feed: HomeFeed?
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
}

struct QuestionFeatureState: Equatable, Sendable {
    var question: Question?
    var pendingQuestion: Question?
    var answerDraft = AnswerDraft()
    var isLoading = false
    var isSubmitting = false
    var errorMessage: String?

    /// Compatibility access for the existing text editor while media lives in
    /// the same answer draft value.
    var draft: String {
        get { answerDraft.body }
        set {
            answerDraft.body = UnicodeTextValidation.clamped(
                newValue,
                maximumLength: AnswerDraft.maximumBodyCharacterCount
            )
        }
    }
}

struct HistoryFeatureState: Equatable, Sendable {
    var answers: [Answer] = []
    var nextCursor: String?
    var query = HistoryQuery()
    var isLoading = false
    var isLoadingMore = false
    var hasLoaded = false
    var errorMessage: String?
}

struct CommentThreadState: Equatable, Sendable {
    var comments: [Comment] = []
    var nextCursor: String?
    /// A notification may point to a comment beyond the first page. Keeping
    /// the target in thread state lets the comments view scroll to and
    /// visually identify it after every required page has loaded.
    var focusedCommentID: String?
    var draft = ""
    var isLoading = false
    var isPosting = false
    var isMutating = false
    var reportsByCommentID: [String: CommentReport] = [:]
    var errorMessage: String?
}

struct FamilySetupFeatureState: Equatable, Sendable {
    var organizerName = ""
    var familyName = ""
    var managedMemberName = ""
    var pairingCode = ""
    var pairingToken: String?
    var family: FamilySummary?
    var activePairing: FamilyPairing?
    var pairingPreview: FamilyPairingPreview?
    var pairings: [FamilyPairingPreview] = []
    var pendingManagedMember: UserProfile?
    var isSubmitting = false
    var isLoading = false
    var errorMessage: String?
}

struct FamilyLifecycleFeatureState: Equatable, Sendable {
    var isMutating = false
    var errorMessage: String?
}

struct AnswerOwnershipFeatureState: Equatable, Sendable {
    var mutatingAnswerIDs: Set<String> = []
    var errorMessage: String?
}

struct NotificationPreferencesFeatureState: Equatable, Sendable {
    var preferences: NotificationPreferences?
    var permissionStatus: NotificationPermissionStatus = .unknown
    var isLoading = false
    var isSaving = false
    var errorMessage: String?
}

struct AccountFeatureState: Equatable, Sendable {
    var export: AccountExport?
    var isExporting = false
    var isDeleting = false
    var errorMessage: String?
}

@MainActor
final class AppStore: ObservableObject {
    private struct PersistedEmailVerificationChallenge: Codable {
        let email: String
        let requestID: String
        let expiresAt: Date
        let actorUserID: String?
        /// Empty means the actor had no email when enrollment started; nil
        /// is reserved for login records and records written by older builds.
        let actorEmailAtRequest: String?
        let attemptStartedAt: Date?
        let replayUntil: Date?
    }

    private struct PersistedVerificationChallenge: Codable {
        let phoneNumber: String
        let requestID: String
        let expiresAt: Date
        let actorUserID: String?
        /// Empty means the actor had no phone when enrollment started; nil
        /// is reserved for login records and records written by older builds.
        let actorPhoneAtRequest: String?
        let attemptStartedAt: Date?
        let replayUntil: Date?
    }

    @Published private(set) var session: SessionState = .restoring
    @Published var path: [AppRoute] = [] {
        didSet {
            if path != oldValue { navigationRevision &+= 1 }
        }
    }
    @Published var emailAuth = EmailVerificationFeatureState()
    @Published var emailEnrollment = EmailVerificationFeatureState()
    @Published var auth = AuthFeatureState()
    @Published var phoneEnrollment = PhoneEnrollmentFeatureState()
    @Published var recovery = RecoveryFeatureState()
    @Published var home = HomeFeatureState()
    @Published var question = QuestionFeatureState()
    @Published var history = HistoryFeatureState()
    @Published var commentThreads: [String: CommentThreadState] = [:]
    @Published var familySetup = FamilySetupFeatureState()
    @Published var familyLifecycle = FamilyLifecycleFeatureState()
    @Published var answerOwnership = AnswerOwnershipFeatureState()
    @Published var notificationPreferences = NotificationPreferencesFeatureState()
    @Published var account = AccountFeatureState()
    @Published private(set) var globalErrorMessage: String?
    @Published private(set) var canRetrySessionRestore = false
    @Published private(set) var personalMarkRequirementIsConfirmed = false
    @Published private(set) var isCheckingPersonalMarkRequirement = false
    @Published private(set) var personalMarkRequirementError: String?

    private let api: any AppAPI
    private let haptics: any HapticProviding
    private let verificationDefaults: UserDefaults?
    private let now: @Sendable () -> Date
    private var historyGeneration = 0
    private var authenticationGeneration = 0
    private let deviceTimeZoneSynchronizer = DeviceTimeZoneSynchronizer()
    private var personalMarkVerificationGeneration: Int?
    private var navigationRevision: UInt64 = 0

    private static let emailLoginChallengeStorageKey =
        "jp.tsutsuura.pending-email-login-verification.v1"
    private static let emailEnrollmentChallengeStorageKey =
        "jp.tsutsuura.pending-email-enrollment-verification.v1"
    private static let loginChallengeStorageKey =
        "jp.tsutsuura.pending-login-verification.v1"
    private static let enrollmentChallengeStorageKey =
        "jp.tsutsuura.pending-phone-enrollment-verification.v1"
    private static let verificationReplayRetention: TimeInterval =
        30 * 24 * 60 * 60

    init(
        api: any AppAPI,
        haptics: (any HapticProviding)? = nil,
        verificationDefaults: UserDefaults? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.api = api
        self.haptics = haptics ?? LiveHaptics()
        self.verificationDefaults = verificationDefaults
        self.now = now
    }

    func navigationVisit() -> NavigationVisit {
        NavigationVisit(revision: navigationRevision, path: path)
    }

    /// Saving may continue after Back. Only the visit that started it may
    /// dismiss itself; reopening the same route creates a different visit.
    func finishSave(
        from visit: NavigationVisit,
        operation: () async -> Bool
    ) async -> Bool {
        let didSave = await operation()
        return didSave && navigationVisit() == visit
    }

    static func live(
        configuration: APIConfiguration? = nil
    ) throws -> AppStore {
        let resolvedConfiguration = try configuration ?? .fromInfoDictionary()
        return AppStore(
            api: DefaultAppAPI(configuration: resolvedConfiguration),
            verificationDefaults: UserDefaults(
                suiteName: resolvedConfiguration.verificationStorageSuiteName
            )
        )
    }

    func restoreSession() async {
        authenticationGeneration += 1
        resetPersonalMarkRequirement()
        session = .restoring
        globalErrorMessage = nil
        canRetrySessionRestore = false

        let hasStoredSession: Bool
        do {
            hasStoredSession = try await api.hasStoredSession()
        } catch {
            // A secure-storage read failure is not evidence that the account
            // has no session. Keep the restore screen and allow a retry so a
            // transient first-unlock/Keychain failure cannot send the user
            // into account creation or pairing by mistake.
            canRetrySessionRestore = true
            presentGlobalError(error)
            return
        }

        guard hasStoredSession else {
            transitionToSignedOut()
            return
        }

        do {
            let user = try await api.fetchMe()
            // A valid bearer is conclusive evidence that login completed,
            // including the narrow crash window after the API stored the
            // token but before finishAuthentication cleared UI bookkeeping.
            clearVerificationChallenge(
                storageKey: Self.loginChallengeStorageKey
            )
            clearVerificationChallenge(storageKey: Self.emailLoginChallengeStorageKey)
            personalMarkRequirementIsConfirmed = true
            session = .signedIn(user)
            path = [.home]
            await refreshHome()
            restorePendingEnrollmentChallenge(for: user)
            restorePendingEmailEnrollmentChallenge(for: user)
        } catch {
            if isUnauthorized(error) {
                transitionToSignedOut()
            } else {
                // A temporary transport or server failure does not invalidate
                // the token in secure storage. Keep the restore state so the
                // user can retry instead of being sent through sign-in again.
                canRetrySessionRestore = true
                presentGlobalError(error)
            }
        }
    }

    @discardableResult
    func requestEmailOTP() async -> Bool {
        guard let email = EmailAddressValidation.normalized(
            emailAuth.email
        ), !emailAuth.isSubmitting else { return false }

        emailAuth.isSubmitting = true
        emailAuth.errorMessage = nil
        defer { emailAuth.isSubmitting = false }

        do {
            let challenge = try await api.requestEmailOTP(email: email)
            emailAuth.email = email
            emailAuth.challenge = challenge
            emailAuth.verificationCode = ""
            emailAuth.expiresAt = now().addingTimeInterval(
                TimeInterval(challenge.expiresIn)
            )
            persistEmailVerificationChallenge(
                email: email,
                challenge: challenge,
                expiresAt: emailAuth.expiresAt,
                actorUserID: nil,
                actorEmailAtRequest: nil,
                storageKey: Self.emailLoginChallengeStorageKey
            )
            session = .awaitingEmailVerification(email: email)
            path = [
                .emailVerification(
                    email: email,
                    requestID: challenge.requestID
                )
            ]
            haptics.impact()
            return true
        } catch {
            emailAuth.errorMessage = userFacingMessage(for: error)
            haptics.error()
            return false
        }
    }

    func verifyEmailOTP() async {
        guard let requestID = emailAuth.challenge?.requestID,
              emailAuth.verificationCode.count == 6,
              NumericInputValidation.asciiDigits(in: emailAuth.verificationCode) == emailAuth.verificationCode,
              !emailAuth.isSubmitting else {
            return
        }

        emailAuth.isSubmitting = true
        emailAuth.errorMessage = nil
        emailAuth.canReplayExpiredAttempt = true
        markEmailVerificationAttemptStarted(
            storageKey: Self.emailLoginChallengeStorageKey
        )
        defer { emailAuth.isSubmitting = false }

        do {
            let authenticatedSession = try await api.verifyEmailOTP(
                requestID: requestID,
                code: emailAuth.verificationCode
            )
            await finishAuthentication(authenticatedSession)
        } catch {
            if isDefinitiveVerificationFailure(error) {
                emailAuth.canReplayExpiredAttempt = false
                markEmailVerificationAttemptDefinitivelyResolved(
                    storageKey: Self.emailLoginChallengeStorageKey
                )
            }
            emailAuth.errorMessage = userFacingMessage(for: error)
            haptics.error()
        }
    }

    func cancelEmailOTP() {
        guard !emailAuth.isSubmitting else { return }
        clearVerificationChallenge(storageKey: Self.emailLoginChallengeStorageKey)
        emailAuth.verificationCode = ""
        emailAuth.challenge = nil
        emailAuth.errorMessage = nil
        session = .signedOut
        path = [.onboarding, .emailEntry]
    }

    @discardableResult
    func requestEmailEnrollment() async -> Bool {
        guard case .signedIn(let requestingActor) = session,
              let email = EmailAddressValidation.normalized(
                emailEnrollment.email
              ),
              !emailEnrollment.isSubmitting else {
            return false
        }

        emailEnrollment.isSubmitting = true
        emailEnrollment.errorMessage = nil
        defer { emailEnrollment.isSubmitting = false }

        do {
            let challenge = try await api.requestEmailEnrollment(
                email: email
            )
            guard case .signedIn(let currentActor) = session,
                  currentActor.id == requestingActor.id else { return false }
            emailEnrollment.email = email
            emailEnrollment.challenge = challenge
            emailEnrollment.expiresAt = now().addingTimeInterval(
                TimeInterval(challenge.expiresIn)
            )
            emailEnrollment.verificationCode = ""
            let actorUserID = requestingActor.id
            let actorEmailAtRequest = requestingActor.email ?? ""
            persistEmailVerificationChallenge(
                email: email,
                challenge: challenge,
                expiresAt: emailEnrollment.expiresAt,
                actorUserID: actorUserID,
                actorEmailAtRequest: actorEmailAtRequest,
                storageKey: Self.emailEnrollmentChallengeStorageKey
            )
            let route = AppRoute.emailEnrollmentVerification(
                email: email,
                requestID: challenge.requestID
            )
            if case .emailEnrollmentVerification = path.last {
                path[path.count - 1] = route
            } else {
                path.append(route)
            }
            haptics.impact()
            return true
        } catch {
            handleAuthenticatedError(error)
            emailEnrollment.errorMessage = userFacingMessage(for: error)
            haptics.error()
            return false
        }
    }

    @discardableResult
    func verifyEmailEnrollment() async -> Bool {
        guard case .signedIn(let verifyingActor) = session,
              let requestID = emailEnrollment.challenge?.requestID,
              emailEnrollment.verificationCode.count == 6,
              NumericInputValidation.asciiDigits(in: emailEnrollment.verificationCode) == emailEnrollment.verificationCode,
              !emailEnrollment.isSubmitting else {
            return false
        }

        emailEnrollment.isSubmitting = true
        emailEnrollment.errorMessage = nil
        emailEnrollment.canReplayExpiredAttempt = true
        markEmailVerificationAttemptStarted(
            storageKey: Self.emailEnrollmentChallengeStorageKey
        )
        defer { emailEnrollment.isSubmitting = false }

        do {
            let profile = try await api.verifyEmailEnrollment(
                requestID: requestID,
                code: emailEnrollment.verificationCode
            )
            guard case .signedIn(let currentActor) = session,
                  currentActor.id == verifyingActor.id, profile.id == verifyingActor.id else {
                return false
            }
            applyCurrentUserProfile(profile)
            clearVerificationChallenge(
                storageKey: Self.emailEnrollmentChallengeStorageKey
            )
            emailEnrollment = EmailVerificationFeatureState()
            while let route = path.last, route.isEmailEnrollmentRoute {
                path.removeLast()
            }
            haptics.success()
            return true
        } catch {
            if isDefinitiveVerificationFailure(error) {
                emailEnrollment.canReplayExpiredAttempt = false
                markEmailVerificationAttemptDefinitivelyResolved(
                    storageKey: Self.emailEnrollmentChallengeStorageKey
                )
            }
            handleAuthenticatedError(error)
            emailEnrollment.errorMessage = userFacingMessage(for: error)
            haptics.error()
            return false
        }
    }

    func cancelEmailEnrollment() {
        guard !emailEnrollment.isSubmitting else { return }
        clearVerificationChallenge(
            storageKey: Self.emailEnrollmentChallengeStorageKey
        )
        emailEnrollment = EmailVerificationFeatureState()
        while let route = path.last, route.isEmailEnrollmentRoute {
            path.removeLast()
        }
    }

    @discardableResult
    func requestOTP() async -> Bool {
        guard let phoneNumber = PhoneNumberValidation.canonicalE164(
            auth.phoneNumber
        ), !auth.isSubmitting else { return false }

        auth.isSubmitting = true
        auth.errorMessage = nil
        defer { auth.isSubmitting = false }

        do {
            let challenge = try await api.requestOTP(phoneNumber: phoneNumber)
            auth.phoneNumber = phoneNumber
            auth.challenge = challenge
            auth.expiresAt = now().addingTimeInterval(
                TimeInterval(challenge.expiresIn)
            )
            persistVerificationChallenge(
                phoneNumber: phoneNumber,
                challenge: challenge,
                expiresAt: auth.expiresAt,
                actorUserID: nil,
                actorPhoneAtRequest: nil,
                storageKey: Self.loginChallengeStorageKey
            )
            session = .awaitingOTP(phoneNumber: phoneNumber)
            path = [
                .otpVerification(
                    phoneNumber: phoneNumber,
                    requestID: challenge.requestID
                )
            ]
            haptics.impact()
            return true
        } catch {
            auth.errorMessage = userFacingMessage(for: error)
            haptics.error()
            return false
        }
    }

    func verifyOTP() async {
        guard let requestID = auth.challenge?.requestID,
              !auth.verificationCode.isEmpty,
              !auth.isSubmitting else {
            return
        }

        auth.isSubmitting = true
        auth.errorMessage = nil
        auth.canReplayExpiredAttempt = true
        markVerificationAttemptStarted(
            storageKey: Self.loginChallengeStorageKey
        )
        defer { auth.isSubmitting = false }

        do {
            let authenticatedSession = try await api.verifyOTP(
                requestID: requestID,
                code: auth.verificationCode
            )
            await finishAuthentication(authenticatedSession)
        } catch {
            if isDefinitiveVerificationFailure(error) {
                auth.canReplayExpiredAttempt = false
                markVerificationAttemptDefinitivelyResolved(
                    storageKey: Self.loginChallengeStorageKey
                )
            }
            auth.errorMessage = userFacingMessage(for: error)
            haptics.error()
        }
    }

    func cancelOTP() {
        clearVerificationChallenge(storageKey: Self.loginChallengeStorageKey)
        auth.verificationCode = ""
        auth.challenge = nil
        auth.errorMessage = nil
        session = .signedOut
        path = [.onboarding, .phoneEntry]
    }

    @discardableResult
    func requestPhoneEnrollment() async -> Bool {
        guard case .signedIn = session,
              let phoneNumber = PhoneNumberValidation.canonicalE164(
                phoneEnrollment.phoneNumber
              ),
              !phoneEnrollment.isSubmitting else {
            return false
        }

        phoneEnrollment.isSubmitting = true
        phoneEnrollment.errorMessage = nil
        defer { phoneEnrollment.isSubmitting = false }

        do {
            let challenge = try await api.requestPhoneEnrollment(
                phoneNumber: phoneNumber
            )
            phoneEnrollment.phoneNumber = phoneNumber
            phoneEnrollment.challenge = challenge
            phoneEnrollment.expiresAt = now().addingTimeInterval(
                TimeInterval(challenge.expiresIn)
            )
            phoneEnrollment.verificationCode = ""
            let actorUserID: String?
            let actorPhoneAtRequest: String?
            if case .signedIn(let profile) = session {
                actorUserID = profile.id
                actorPhoneAtRequest = profile.phoneNumber ?? ""
            } else {
                actorUserID = nil
                actorPhoneAtRequest = nil
            }
            persistVerificationChallenge(
                phoneNumber: phoneNumber,
                challenge: challenge,
                expiresAt: phoneEnrollment.expiresAt,
                actorUserID: actorUserID,
                actorPhoneAtRequest: actorPhoneAtRequest,
                storageKey: Self.enrollmentChallengeStorageKey
            )
            let route = AppRoute.phoneEnrollmentVerification(
                phoneNumber: phoneNumber,
                requestID: challenge.requestID
            )
            if path.last != route {
                path.append(route)
            }
            haptics.impact()
            return true
        } catch {
            handleAuthenticatedError(error)
            phoneEnrollment.errorMessage = userFacingMessage(for: error)
            haptics.error()
            return false
        }
    }

    @discardableResult
    func verifyPhoneEnrollment() async -> Bool {
        guard let requestID = phoneEnrollment.challenge?.requestID,
              phoneEnrollment.verificationCode.count == 6,
              !phoneEnrollment.isSubmitting else {
            return false
        }

        phoneEnrollment.isSubmitting = true
        phoneEnrollment.errorMessage = nil
        phoneEnrollment.canReplayExpiredAttempt = true
        markVerificationAttemptStarted(
            storageKey: Self.enrollmentChallengeStorageKey
        )
        defer { phoneEnrollment.isSubmitting = false }

        do {
            let profile = try await api.verifyPhoneEnrollment(
                requestID: requestID,
                code: phoneEnrollment.verificationCode
            )
            applyCurrentUserProfile(profile)
            clearVerificationChallenge(
                storageKey: Self.enrollmentChallengeStorageKey
            )
            phoneEnrollment = PhoneEnrollmentFeatureState()
            while let route = path.last, route.isPhoneEnrollmentRoute {
                path.removeLast()
            }
            haptics.success()
            return true
        } catch {
            if isDefinitiveVerificationFailure(error) {
                phoneEnrollment.canReplayExpiredAttempt = false
                markVerificationAttemptDefinitivelyResolved(
                    storageKey: Self.enrollmentChallengeStorageKey
                )
            }
            handleAuthenticatedError(error)
            phoneEnrollment.errorMessage = userFacingMessage(for: error)
            haptics.error()
            return false
        }
    }

    func cancelPhoneEnrollment() {
        guard !phoneEnrollment.isSubmitting else { return }
        clearVerificationChallenge(
            storageKey: Self.enrollmentChallengeStorageKey
        )
        phoneEnrollment = PhoneEnrollmentFeatureState()
        while let route = path.last, route.isPhoneEnrollmentRoute {
            path.removeLast()
        }
    }

    @discardableResult
    func createAccountRecoveryCode() async -> Bool {
        guard case .signedIn = session, !recovery.isSubmitting else {
            return false
        }
        recovery.isSubmitting = true
        recovery.errorMessage = nil
        defer { recovery.isSubmitting = false }

        do {
            recovery.issuedCode = try await api.createAccountRecoveryCode()
            haptics.success()
            return true
        } catch {
            handleAuthenticatedError(error)
            recovery.errorMessage = userFacingMessage(for: error)
            haptics.error()
            return false
        }
    }

    @discardableResult
    func recoverAccount() async -> Bool {
        let code = RecoveryCodeValidation.normalized(recovery.codeInput)
        guard RecoveryCodeValidation.isValid(code),
              !recovery.isSubmitting else { return false }
        recovery.isSubmitting = true
        recovery.errorMessage = nil
        defer { recovery.isSubmitting = false }

        do {
            let authenticatedSession = try await api.recoverAccount(code: code)
            recovery = RecoveryFeatureState()
            await finishAuthentication(authenticatedSession)
            return true
        } catch {
            recovery.errorMessage = userFacingMessage(for: error)
            haptics.error()
            return false
        }
    }

    func createOrganizerFamily() async {
        let organizerName = familySetup.organizerName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let familyName = familySetup.familyName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard NameValidation.isValid(organizerName),
              NameValidation.isValid(familyName),
              !familySetup.isSubmitting else {
            return
        }

        familySetup.isSubmitting = true
        familySetup.errorMessage = nil
        defer { familySetup.isSubmitting = false }

        do {
            let authenticatedSession = try await api.createOrganizerFamily(
                organizerName: organizerName,
                familyName: familyName
            )
            canRetrySessionRestore = false
            authenticationGeneration += 1
            resetPersonalMarkRequirement()
            session = .signedIn(authenticatedSession.user)
            auth = AuthFeatureState()
            path = [.familySetup]
            haptics.success()
            await loadFamilySetup()
        } catch {
            familySetup.errorMessage = userFacingMessage(for: error)
            haptics.error()
        }
    }

    func loadFamilySetup() async {
        guard case .signedIn = session,
              !familySetup.isLoading else {
            return
        }

        familySetup.isLoading = true
        familySetup.errorMessage = nil
        defer { familySetup.isLoading = false }

        do {
            async let familyRequest = api.fetchFamily()
            async let pairingRequest = api.fetchFamilyPairings()
            let (family, pairings) = try await (
                familyRequest,
                pairingRequest
            )
            applyFamily(family)
            familySetup.pairings = pairings
        } catch {
            handleAuthenticatedError(error)
            familySetup.errorMessage = userFacingMessage(for: error)
        }
    }

    @discardableResult
    func renameFamily(_ name: String) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NameValidation.isValid(name),
              !familyLifecycle.isMutating else { return false }
        familyLifecycle.isMutating = true
        familyLifecycle.errorMessage = nil
        defer { familyLifecycle.isMutating = false }

        do {
            applyFamily(try await api.renameFamily(name: name))
            haptics.success()
            return true
        } catch {
            handleAuthenticatedError(error)
            familyLifecycle.errorMessage = userFacingMessage(for: error)
            haptics.error()
            return false
        }
    }

    @discardableResult
    func renameManagedFamilyMember(
        memberID: String,
        displayName: String
    ) async -> Bool {
        let displayName = displayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard NameValidation.isValid(displayName),
              !familyLifecycle.isMutating else {
            return false
        }
        familyLifecycle.isMutating = true
        familyLifecycle.errorMessage = nil
        defer { familyLifecycle.isMutating = false }

        do {
            let member = try await api.renameManagedFamilyMember(
                memberID: memberID,
                displayName: displayName
            )
            applyFamilyMember(member)
            applyDisplayName(member.displayName, toUserID: member.id)
            applyPairingMemberName(member.displayName, toUserID: member.id)
            haptics.success()
            return true
        } catch {
            handleAuthenticatedError(error)
            familyLifecycle.errorMessage = userFacingMessage(for: error)
            haptics.error()
            return false
        }
    }

    @discardableResult
    func removeManagedFamilyMember(memberID: String) async -> Bool {
        guard !familyLifecycle.isMutating else { return false }
        familyLifecycle.isMutating = true
        familyLifecycle.errorMessage = nil
        defer { familyLifecycle.isMutating = false }

        do {
            try await api.removeManagedFamilyMember(memberID: memberID)
            removeFamilyMemberFromCaches(memberID: memberID)
            haptics.success()
            return true
        } catch {
            handleAuthenticatedError(error)
            familyLifecycle.errorMessage = userFacingMessage(for: error)
            haptics.error()
            return false
        }
    }

    @discardableResult
    func transferFamilyOwnership(to memberID: String) async -> Bool {
        guard !familyLifecycle.isMutating else { return false }
        familyLifecycle.isMutating = true
        familyLifecycle.errorMessage = nil
        defer { familyLifecycle.isMutating = false }

        do {
            applyFamily(try await api.transferFamilyOwnership(to: memberID))
            synchronizeCurrentFamilyRole()
            haptics.success()
            return true
        } catch {
            handleAuthenticatedError(error)
            familyLifecycle.errorMessage = userFacingMessage(for: error)
            haptics.error()
            return false
        }
    }

    @discardableResult
    func leaveFamily() async -> Bool {
        guard !familyLifecycle.isMutating else { return false }
        familyLifecycle.isMutating = true
        familyLifecycle.errorMessage = nil
        defer { familyLifecycle.isMutating = false }

        do {
            let result = try await api.leaveFamily()
            if result.accountDeleted {
                transitionToSignedOut()
            } else {
                prepareForReplacementFamilyAfterLeaving()

                // A regular account immediately receives a new one-person
                // family on the server. Reload authoritative identity and
                // family data instead of routing through organizer setup,
                // which would create a second account/session.
                do {
                    let profile = try await api.fetchMe()
                    session = .signedIn(profile)
                } catch {
                    handleAuthenticatedError(error)
                    familyLifecycle.errorMessage = userFacingMessage(for: error)
                }
                await loadFamilySetup()
                await refreshHome()
                await loadHistory()
            }
            haptics.success()
            return true
        } catch {
            handleAuthenticatedError(error)
            familyLifecycle.errorMessage = userFacingMessage(for: error)
            haptics.error()
            return false
        }
    }

    func createManagedMemberPairing() async {
        let displayName = familySetup.managedMemberName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard NameValidation.isValid(displayName),
              !familySetup.isSubmitting else {
            return
        }

        familySetup.isSubmitting = true
        familySetup.errorMessage = nil
        defer { familySetup.isSubmitting = false }

        do {
            let member: UserProfile
            if let pending = familySetup.pendingManagedMember,
               pending.displayName == displayName {
                member = pending
            } else {
                member = try await api.addManagedFamilyMember(
                    displayName: displayName
                )
                familySetup.pendingManagedMember = member
                appendFamilyMemberIfNeeded(member)
            }

            let pairing = try await api.createFamilyPairing(
                memberID: member.id
            )
            applyCreatedPairing(pairing)
            familySetup.pendingManagedMember = nil
            familySetup.managedMemberName = ""
            haptics.success()
        } catch {
            handleAuthenticatedError(error)
            familySetup.errorMessage = userFacingMessage(for: error)
            haptics.error()
        }
    }

    func createPairing(for member: UserProfile) async {
        guard member.managed == true,
              !familySetup.isSubmitting else {
            return
        }

        familySetup.isSubmitting = true
        familySetup.errorMessage = nil
        defer { familySetup.isSubmitting = false }

        do {
            let pairing = try await api.createFamilyPairing(
                memberID: member.id
            )
            applyCreatedPairing(pairing)
            haptics.success()
        } catch {
            handleAuthenticatedError(error)
            familySetup.errorMessage = userFacingMessage(for: error)
            haptics.error()
        }
    }

    func previewFamilyPairing() async {
        guard let credential = currentPairingCredential,
              !familySetup.isSubmitting else {
            return
        }

        familySetup.isSubmitting = true
        familySetup.errorMessage = nil
        defer { familySetup.isSubmitting = false }

        do {
            familySetup.pairingPreview = try await api.previewFamilyPairing(
                credential
            )
            if path.last != .pairingConfirmation {
                path.append(.pairingConfirmation)
            }
            haptics.impact()
        } catch {
            familySetup.errorMessage = userFacingMessage(for: error)
            haptics.error()
        }
    }

    func activateFamilyPairing() async {
        guard let credential = currentPairingCredential,
              familySetup.pairingPreview != nil,
              !familySetup.isSubmitting else {
            return
        }

        familySetup.isSubmitting = true
        familySetup.errorMessage = nil
        defer { familySetup.isSubmitting = false }

        do {
            let authenticatedSession = try await api.activateFamilyPairing(
                credential
            )
            canRetrySessionRestore = false
            // Clear the one-time credential before publishing the signed-in
            // session. ContentView observes that transition and must not try
            // to preview the now-consumed invite a second time.
            familySetup.pairingCode = ""
            familySetup.pairingToken = nil
            authenticationGeneration += 1
            resetPersonalMarkRequirement()
            session = .signedIn(authenticatedSession.user)
            path = [.pairingReady]
            haptics.success()
        } catch {
            familySetup.errorMessage = userFacingMessage(for: error)
            haptics.error()
        }
    }

    func preparePairingToken(_ token: String) {
        let cleaned = token.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !cleaned.isEmpty else { return }
        familySetup.pairingToken = cleaned
        familySetup.pairingCode = ""
        familySetup.pairingPreview = nil
        if case .signedOut = session {
            path = [.pairingEntry]
        } else if case .signedIn = session,
                  path.last != .pairingConfirmation {
            path.append(.pairingConfirmation)
        }
    }

    func finishFamilySetup() async {
        familySetup.activePairing = nil
        familySetup.pairingPreview = nil
        familySetup.pairingCode = ""
        familySetup.pairingToken = nil
        path = [.home]
        await refreshHome()
    }

    func refreshHome(inBackground: Bool = false) async {
        guard !home.isLoading, !home.isLoadingMore else { return }
        let previousFeed = home.feed
        let previousSession = session
        let requestedGeneration = authenticationGeneration
        home.isLoading = true
        if !inBackground { home.errorMessage = nil }
        defer { home.isLoading = false }

        do {
            async let profileRequest = api.fetchMe()
            async let feedRequest = api.fetchHome(cursor: nil)
            let (profile, feed) = try await (profileRequest, feedRequest)
            try Task.checkCancellation()
            guard authenticationGeneration == requestedGeneration else { return }
            // A successful mark save must win over an older /me snapshot,
            // including the initial foreground refresh during first setup.
            if case .signedIn(let previousProfile) = previousSession,
               case .signedIn(let currentProfile) = session,
               previousProfile.id != currentProfile.id
                || previousProfile.avatarMark != currentProfile.avatarMark { return }
            // A local answer/reaction or another account change wins over a
            // background request that started before that change.
            if inBackground, home.feed != previousFeed || session != previousSession { return }
            var refreshedFeed = feed
            if inBackground, let previousFeed,
               previousFeed.family?.id == feed.family?.id,
               previousFeed.answers.count > feed.answers.count,
               feed.nextCursor != nil {
                let currentMembers = Set(feed.family?.members.map(\.id) ?? [])
                let refreshedIDs = Set(feed.answers.map(\.id))
                let hasCompleteRoster = currentMembers.count == feed.family?.memberCount
                let olderAnswers = previousFeed.answers.filter {
                    !refreshedIDs.contains($0.id)
                        && (!hasCompleteRoster || currentMembers.contains($0.author.id))
                }
                refreshedFeed.answers = mergedAnswers(feed.answers, appending: olderAnswers)
                refreshedFeed.nextCursor = previousFeed.nextCursor
            }
            home.feed = refreshedFeed
            home.errorMessage = nil
            if let family = feed.family {
                applyFamily(family)
            }
            // Refresh managed/independent state from /me, then derive the
            // authoritative family role from the newly loaded member list.
            // This makes an ownership transfer visible on the successor's
            // already-running device without requiring a relaunch.
            applyCurrentUserProfile(profile)
            synchronizeCurrentFamilyRole()
            if let todayQuestion = feed.todayQuestion {
                receiveTodayQuestion(todayQuestion)
            }
        } catch {
            guard !Task.isCancelled, !isCancelledRequest(error) else { return }
            guard authenticationGeneration == requestedGeneration else { return }
            if inBackground, session != previousSession { return }
            handleAuthenticatedError(error)
            if !inBackground { home.errorMessage = userFacingMessage(for: error) }
        }
    }

    /// Quiet updates preserve the current query, already loaded pages, drafts,
    /// and scroll positions. Foreground view tasks own the ten-second cadence.
    func refreshHomeInBackground(includingHistory: Bool) async {
        guard case .signedIn = session else { return }
        await refreshHome(inBackground: true)
        guard !Task.isCancelled, case .signedIn = session else { return }
        if includingHistory, history.hasLoaded {
            await loadHistory(inBackground: true)
        }
    }

    /// Refreshes every Settings-visible data source and reports whether the
    /// refresh fully succeeded. Individual loaders retain their last good
    /// cache on failure, while callers can avoid presenting false success.
    @discardableResult
    func refreshAllData() async -> Bool {
        await refreshHome()
        await loadHistory()
        guard case .signedIn = session else { return false }
        return home.errorMessage == nil && history.errorMessage == nil
    }

    func loadMoreHomeAnswers() async {
        guard let cursor = home.feed?.nextCursor,
              !home.isLoadingMore, !home.isLoading else {
            return
        }
        home.isLoadingMore = true
        home.errorMessage = nil
        defer { home.isLoadingMore = false }

        do {
            let nextPage = try await api.fetchHome(cursor: cursor)
            home.feed?.answers = mergedAnswers(
                home.feed?.answers ?? [],
                appending: nextPage.answers
            )
            home.feed?.nextCursor = nextPage.nextCursor
        } catch {
            guard !isCancelledRequest(error) else { return }
            handleAuthenticatedError(error)
            home.errorMessage = userFacingMessage(for: error)
        }
    }

    @discardableResult
    func loadTodayQuestion() async -> Bool {
        await performTodayQuestionLoad(treatMissingAsHandled: false)
    }

    /// A missing/withdrawn question is a terminal push destination, while a
    /// transport, authentication, or server failure must remain retryable.
    func loadTodayQuestionForPush(
        expectedQuestionID: String?
    ) async -> PushDestinationResolution {
        guard await performTodayQuestionLoad(treatMissingAsHandled: true) else {
            return .retryable
        }
        guard let loadedQuestion = question.question else {
            return .terminal
        }
        if let expectedQuestionID,
           loadedQuestion.id != expectedQuestionID {
            let message = "この通知の質問は終了しました。今日の質問はホームから確認できます。"
            question.errorMessage = message
            globalErrorMessage = message
            return .terminal
        }
        return .ready
    }

    private func performTodayQuestionLoad(
        treatMissingAsHandled: Bool
    ) async -> Bool {
        guard !question.isLoading else { return false }
        let requestedGeneration = authenticationGeneration
        question.isLoading = true
        question.errorMessage = nil
        defer {
            if authenticationGeneration == requestedGeneration { question.isLoading = false }
        }

        do {
            let loadedQuestion = try await api.fetchTodayQuestion()
            guard authenticationGeneration == requestedGeneration, !Task.isCancelled else { return false }
            receiveTodayQuestion(loadedQuestion)
            return question.pendingQuestion == nil
        } catch {
            guard authenticationGeneration == requestedGeneration,
                  !Task.isCancelled, !isCancelledRequest(error) else { return false }
            if treatMissingAsHandled,
               isTerminalPushDestinationError(error) {
                let message = "この質問は終了したか、現在は表示できません。"
                question.question = nil
                question.errorMessage = message
                globalErrorMessage = message
                return true
            }
            handleAuthenticatedError(error)
            question.errorMessage = userFacingMessage(for: error)
            return false
        }
    }

    func submitAnswer() async {
        guard question.pendingQuestion == nil else {
            question.errorMessage = "新しい質問が届きました。前の下書きは残っています。「新しい質問を確認」を押してください。"
            return
        }
        guard let questionID = question.question?.id,
              question.question?.isAvailable != false,
              !question.answerDraft.isEmpty,
              !question.isSubmitting else {
            return
        }

        question.isSubmitting = true
        question.errorMessage = nil
        defer { question.isSubmitting = false }

        do {
            let submission = try question.answerDraft.submission()
            let answer = try await api.submitAnswer(
                questionID: questionID,
                questionDate: question.question?.publishedOn,
                submission: submission
            )
            question.question?.answer = answer
            question.answerDraft.removeAll()
            updateHomeAnswerProgress(for: answer, isAnswered: true)
            if home.feed?.todayQuestion?.id == questionID {
                home.feed?.todayQuestion?.answer = answer
                home.feed?.myAnswer = answer
                if let index = home.feed?.answers.firstIndex(where: {
                    $0.id == answer.id
                }) {
                    home.feed?.answers[index] = answer
                } else {
                    home.feed?.answers.insert(answer, at: 0)
                }
            }
            if history.hasLoaded, answerMatchesHistoryQuery(answer) {
                if let index = history.answers.firstIndex(where: {
                    $0.id == answer.id
                }) {
                    history.answers[index] = answer
                } else {
                    history.answers.insert(answer, at: 0)
                }
            }
            haptics.success()
        } catch {
            handleAuthenticatedError(error)
            question.errorMessage = userFacingMessage(for: error)
            haptics.error()
        }
    }

    private func receiveTodayQuestion(_ incoming: Question) {
        if let current = question.question, !question.answerDraft.isEmpty,
           current.id != incoming.id || current.publishedOn != incoming.publishedOn {
            question.pendingQuestion = incoming
            return
        }
        question.question = incoming
        question.pendingQuestion = nil
    }

    func acceptNewQuestionDiscardingDraft() {
        guard let pending = question.pendingQuestion else { return }
        question.answerDraft = AnswerDraft()
        question.question = pending
        question.pendingQuestion = nil
        question.errorMessage = nil
    }

    @discardableResult
    func updateAnswer(
        answerID: String,
        submission: AnswerSubmission
    ) async -> Bool {
        guard !answerOwnership.mutatingAnswerIDs.contains(answerID) else {
            return false
        }
        answerOwnership.mutatingAnswerIDs.insert(answerID)
        answerOwnership.errorMessage = nil
        defer { answerOwnership.mutatingAnswerIDs.remove(answerID) }

        do {
            let answer = try await api.updateAnswer(
                answerID: answerID,
                submission: submission
            )
            replaceCachedAnswer(answer)
            haptics.success()
            return true
        } catch {
            handleAuthenticatedError(error)
            answerOwnership.errorMessage = userFacingMessage(for: error)
            haptics.error()
            return false
        }
    }

    @discardableResult
    func deleteAnswer(answerID: String) async -> Bool {
        guard !answerOwnership.mutatingAnswerIDs.contains(answerID) else {
            return false
        }
        answerOwnership.mutatingAnswerIDs.insert(answerID)
        answerOwnership.errorMessage = nil
        defer { answerOwnership.mutatingAnswerIDs.remove(answerID) }

        do {
            try await api.deleteAnswer(answerID: answerID)
            removeCachedAnswer(answerID: answerID)
            haptics.selection()
            return true
        } catch {
            handleAuthenticatedError(error)
            answerOwnership.errorMessage = userFacingMessage(for: error)
            haptics.error()
            return false
        }
    }

    @discardableResult
    func deleteAnswerMedia(
        answerID: String,
        mediaID: String
    ) async -> Bool {
        guard !answerOwnership.mutatingAnswerIDs.contains(answerID) else {
            return false
        }
        answerOwnership.mutatingAnswerIDs.insert(answerID)
        answerOwnership.errorMessage = nil
        defer { answerOwnership.mutatingAnswerIDs.remove(answerID) }

        do {
            let answer = try await api.deleteAnswerMedia(
                answerID: answerID,
                mediaID: mediaID
            )
            replaceCachedAnswer(answer)
            haptics.selection()
            return true
        } catch {
            handleAuthenticatedError(error)
            answerOwnership.errorMessage = userFacingMessage(for: error)
            haptics.error()
            return false
        }
    }

    @discardableResult
    func setAnswerVoiceRecording(
        _ recording: AnswerMediaUpload?
    ) -> Bool {
        do {
            try question.answerDraft.setVoiceRecording(recording)
            question.errorMessage = nil
            return true
        } catch {
            question.errorMessage = userFacingMessage(for: error)
            haptics.error()
            return false
        }
    }

    @discardableResult
    func addAnswerPhotos(_ photos: [AnswerMediaUpload]) -> Bool {
        do {
            try question.answerDraft.addPhotos(photos)
            question.errorMessage = nil
            return true
        } catch {
            question.errorMessage = userFacingMessage(for: error)
            haptics.error()
            return false
        }
    }

    @discardableResult
    func replaceAnswerPhotos(with photos: [AnswerMediaUpload]) -> Bool {
        do {
            try question.answerDraft.replacePhotos(with: photos)
            question.errorMessage = nil
            return true
        } catch {
            question.errorMessage = userFacingMessage(for: error)
            haptics.error()
            return false
        }
    }

    func removeAnswerPhoto(id: UUID) {
        question.answerDraft.removePhoto(id: id)
    }

    func removeAnswerMedia() {
        question.answerDraft.removeAllMedia()
    }

    func fetchAnswerMedia(
        _ media: AnswerMedia
    ) async throws -> AnswerMediaContent {
        do {
            return try await api.fetchAnswerMedia(media)
        } catch {
            handleAuthenticatedError(error)
            throw error
        }
    }

    func loadHistory(loadMore: Bool = false, inBackground: Bool = false) async {
        guard !history.isLoading, !history.isLoadingMore else { return }
        if loadMore, history.nextCursor == nil { return }

        let requestedQuery = history.query
        let requestedGeneration = historyGeneration
        let previousAnswers = history.answers
        let previousCursor = history.nextCursor
        if loadMore {
            history.isLoadingMore = true
        } else {
            history.isLoading = true
        }
        if !inBackground { history.errorMessage = nil }
        defer {
            if requestedGeneration == historyGeneration {
                if loadMore {
                    history.isLoadingMore = false
                } else {
                    history.isLoading = false
                }
            }
        }

        do {
            let page = try await api.fetchAnswerHistory(
                query: requestedQuery,
                cursor: loadMore ? history.nextCursor : nil
            )
            guard requestedGeneration == historyGeneration,
                  history.query == requestedQuery, !Task.isCancelled else {
                return
            }
            if inBackground, history.answers != previousAnswers { return }
            let preservesOlderPages = inBackground
                && previousAnswers.count > page.answers.count && page.nextCursor != nil
            if loadMore {
                history.answers = mergedAnswers(
                    history.answers,
                    appending: page.answers
                )
            } else if preservesOlderPages {
                let refreshedIDs = Set(page.answers.map(\.id))
                history.answers = mergedAnswers(page.answers, appending: previousAnswers.filter { !refreshedIDs.contains($0.id) })
            } else {
                history.answers = uniqueAnswers(page.answers)
            }
            history.nextCursor = preservesOlderPages ? previousCursor : page.nextCursor
            history.hasLoaded = true
            history.errorMessage = nil
        } catch {
            guard requestedGeneration == historyGeneration,
                  !Task.isCancelled, !isCancelledRequest(error) else { return }
            handleAuthenticatedError(error)
            if !inBackground { history.errorMessage = userFacingMessage(for: error) }
        }
    }

    func loadHistory(
        query: HistoryQuery,
        loadMore: Bool = false
    ) async {
        if history.query != query {
            setHistoryQuery(query)
        }
        await loadHistory(loadMore: loadMore)
    }

    func setHistoryQuery(_ query: HistoryQuery) {
        var query = query
        query.searchText = HistoryQuery.normalizedSearchText(query.searchText)
        query.limit = HistoryQuery.normalizedLimit(query.limit)
        guard history.query != query else { return }
        historyGeneration += 1
        // A result belongs to its query. Showing an old page under a new
        // search term makes a failed or pending request look like a match.
        history.query = query
        history.answers = []
        history.hasLoaded = false
        history.nextCursor = nil
        history.isLoading = false
        history.isLoadingMore = false
        history.errorMessage = nil
    }

    func toggleLike(answerID: String) async {
        guard let original = answer(withID: answerID),
              case .signedIn(let profile) = session,
              original.author.id != profile.id else {
            return
        }
        let intendedValue = !original.isLikedByMe

        applyLike(
            LikeState(
                isLikedByMe: intendedValue,
                likeCount: max(0, original.likeCount + (intendedValue ? 1 : -1))
            ),
            to: answerID
        )
        haptics.selection()

        do {
            let state = try await api.setLike(
                answerID: answerID,
                isLiked: intendedValue
            )
            applyLike(state, to: answerID)
        } catch {
            applyLike(
                LikeState(
                    isLikedByMe: original.isLikedByMe,
                    likeCount: original.likeCount
                ),
                to: answerID
            )
            handleAuthenticatedError(error)
            presentGlobalError(error)
            haptics.error()
        }
    }

    @discardableResult
    func loadComments(answerID: String, loadMore: Bool = false) async -> Bool {
        await performCommentLoad(
            answerID: answerID,
            loadMore: loadMore
        ) == .ready
    }

    private func performCommentLoad(
        answerID: String,
        loadMore: Bool = false
    ) async -> PushDestinationResolution {
        let requestedGeneration = authenticationGeneration
        var thread = commentThreads[answerID] ?? CommentThreadState()
        guard !thread.isLoading else { return .retryable }
        if loadMore, thread.nextCursor == nil { return .ready }

        thread.isLoading = true
        thread.errorMessage = nil
        commentThreads[answerID] = thread

        do {
            let page = try await api.fetchComments(
                answerID: answerID,
                cursor: loadMore ? thread.nextCursor : nil
            )
            guard authenticationGeneration == requestedGeneration else { return .retryable }
            thread = commentThreads[answerID] ?? thread
            if Task.isCancelled {
                thread.isLoading = false
                commentThreads[answerID] = thread
                return .retryable
            }
            if loadMore {
                thread.comments = mergedComments(
                    thread.comments,
                    appending: page.comments
                )
            } else {
                thread.comments = mergedComments([], appending: page.comments)
            }
            thread.nextCursor = page.nextCursor
            thread.isLoading = false
            commentThreads[answerID] = thread
            return .ready
        } catch {
            guard authenticationGeneration == requestedGeneration else { return .retryable }
            thread = commentThreads[answerID] ?? thread
            thread.isLoading = false
            if Task.isCancelled || isCancelledRequest(error) {
                commentThreads[answerID] = thread
                return .retryable
            }
            thread.errorMessage = userFacingMessage(for: error)
            commentThreads[answerID] = thread
            handleAuthenticatedError(error)
            return isTerminalPushDestinationError(error)
                ? .terminal
                : .retryable
        }
    }

    func setCommentDraft(_ draft: String, answerID: String) {
        var thread = commentThreads[answerID] ?? CommentThreadState()
        thread.draft = UnicodeTextValidation.clamped(
            draft,
            maximumLength: Comment.maximumBodyCharacterCount
        )
        commentThreads[answerID] = thread
    }

    func postComment(answerID: String) async {
        var thread = commentThreads[answerID] ?? CommentThreadState()
        let body = thread.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty,
              UnicodeTextValidation.characterCount(body)
                <= Comment.maximumBodyCharacterCount,
              !thread.isPosting else { return }

        thread.isPosting = true
        thread.errorMessage = nil
        commentThreads[answerID] = thread

        do {
            let comment = try await api.createComment(
                answerID: answerID,
                body: body
            )
            thread = commentThreads[answerID] ?? thread
            thread.comments = mergedComments(
                thread.comments,
                appending: [comment]
            )
            thread.draft = ""
            thread.isPosting = false
            commentThreads[answerID] = thread
            incrementCommentCount(answerID: answerID)
            haptics.success()
        } catch {
            thread = commentThreads[answerID] ?? thread
            thread.isPosting = false
            thread.errorMessage = userFacingMessage(for: error)
            commentThreads[answerID] = thread
            handleAuthenticatedError(error)
            haptics.error()
        }
    }

    @discardableResult
    func replyToComment(
        answerID: String,
        parentCommentID: String,
        body: String
    ) async -> Bool {
        var thread = commentThreads[answerID] ?? CommentThreadState()
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty,
              UnicodeTextValidation.characterCount(body)
                <= Comment.maximumBodyCharacterCount,
              !thread.isPosting,
              !thread.isMutating else {
            return false
        }
        thread.isPosting = true
        thread.errorMessage = nil
        commentThreads[answerID] = thread

        do {
            let reply = try await api.replyToComment(
                answerID: answerID,
                parentCommentID: parentCommentID,
                body: body
            )
            thread = commentThreads[answerID] ?? thread
            thread.comments = mergedComments(
                thread.comments,
                appending: [reply]
            )
            thread.isPosting = false
            commentThreads[answerID] = thread
            incrementCommentCount(answerID: answerID)
            haptics.success()
            return true
        } catch {
            thread = commentThreads[answerID] ?? thread
            thread.isPosting = false
            thread.errorMessage = userFacingMessage(for: error)
            commentThreads[answerID] = thread
            handleAuthenticatedError(error)
            haptics.error()
            return false
        }
    }

    @discardableResult
    func updateComment(
        commentID: String,
        answerID: String,
        body: String
    ) async -> Bool {
        var thread = commentThreads[answerID] ?? CommentThreadState()
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty,
              UnicodeTextValidation.characterCount(body)
                <= Comment.maximumBodyCharacterCount,
              !thread.isMutating else { return false }
        thread.isMutating = true
        thread.errorMessage = nil
        commentThreads[answerID] = thread

        do {
            let updated = try await api.updateComment(
                commentID: commentID,
                body: body
            )
            thread = commentThreads[answerID] ?? thread
            if let index = thread.comments.firstIndex(where: {
                $0.id == commentID
            }) {
                thread.comments[index] = updated
            }
            thread.isMutating = false
            commentThreads[answerID] = thread
            haptics.success()
            return true
        } catch {
            thread = commentThreads[answerID] ?? thread
            thread.isMutating = false
            thread.errorMessage = userFacingMessage(for: error)
            commentThreads[answerID] = thread
            handleAuthenticatedError(error)
            haptics.error()
            return false
        }
    }

    @discardableResult
    func reportComment(
        commentID: String,
        answerID: String,
        reason: CommentReportReason,
        details: String? = nil
    ) async -> Bool {
        var thread = commentThreads[answerID] ?? CommentThreadState()
        let normalizedDetails = details?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard normalizedDetails.map({
            UnicodeTextValidation.characterCount($0)
                <= CommentReport.maximumDetailsCharacterCount
        }) ?? true,
        !thread.isMutating else { return false }
        thread.isMutating = true
        thread.errorMessage = nil
        commentThreads[answerID] = thread

        do {
            let report = try await api.reportComment(
                commentID: commentID,
                reason: reason,
                details: normalizedDetails
            )
            thread = commentThreads[answerID] ?? thread
            thread.reportsByCommentID[commentID] = report
            thread.isMutating = false
            commentThreads[answerID] = thread
            haptics.success()
            return true
        } catch {
            thread = commentThreads[answerID] ?? thread
            thread.isMutating = false
            thread.errorMessage = userFacingMessage(for: error)
            commentThreads[answerID] = thread
            handleAuthenticatedError(error)
            haptics.error()
            return false
        }
    }

    func deleteComment(commentID: String, answerID: String) async {
        var thread = commentThreads[answerID] ?? CommentThreadState()
        guard !thread.isMutating else { return }
        thread.isMutating = true
        thread.errorMessage = nil
        commentThreads[answerID] = thread

        do {
            try await api.deleteComment(
                commentID: commentID,
                answerID: answerID
            )
            thread = commentThreads[answerID] ?? thread
            thread.comments.removeAll(where: { $0.id == commentID })
            thread.reportsByCommentID[commentID] = nil
            thread.isMutating = false
            commentThreads[answerID] = thread
            decrementCommentCount(answerID: answerID)
            haptics.selection()
        } catch {
            handleAuthenticatedError(error)
            thread = commentThreads[answerID] ?? thread
            thread.isMutating = false
            thread.errorMessage = userFacingMessage(for: error)
            commentThreads[answerID] = thread
            haptics.error()
        }
    }

    @discardableResult
    func updateDisplayName(_ displayName: String) async -> Bool {
        let trimmedName = displayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard NameValidation.isValid(trimmedName) else { return false }

        do {
            let profile = try await api.updateProfile(displayName: trimmedName)
            if let family = profile.family { applyFamily(family) }
            applyCurrentUserProfile(profile)
            applyDisplayName(profile.displayName, toUserID: profile.id)
            haptics.success()
            return true
        } catch {
            handleAuthenticatedError(error)
            presentGlobalError(error)
            haptics.error()
            return false
        }
    }

    var requiresPersonalMarkSetup: Bool {
        guard case .signedIn(let profile) = session else { return false }
        return !personalMarkRequirementIsConfirmed
            || PersonalMarkRequirement.requiresSetup(for: profile)
    }

    /// Authentication receipts can replay an older profile snapshot. Resolve
    /// the current server profile before asking an existing member to redraw.
    func confirmPersonalMarkRequirement() async {
        guard case .signedIn(let actor) = session,
              !personalMarkRequirementIsConfirmed,
              personalMarkVerificationGeneration != authenticationGeneration else { return }
        let generation = authenticationGeneration
        personalMarkVerificationGeneration = generation
        isCheckingPersonalMarkRequirement = true
        personalMarkRequirementError = nil
        defer {
            if personalMarkVerificationGeneration == generation {
                personalMarkVerificationGeneration = nil
                isCheckingPersonalMarkRequirement = false
            }
        }
        do {
            let profile = try await api.fetchMe()
            guard case .signedIn(let current) = session,
                  current.id == actor.id, profile.id == actor.id,
                  generation == authenticationGeneration else { return }
            personalMarkRequirementIsConfirmed = true
            applyCurrentUserProfile(profile)
        } catch {
            guard !Task.isCancelled, !isCancelledRequest(error),
                  case .signedIn(let current) = session,
                  current.id == actor.id, generation == authenticationGeneration else { return }
            handleAuthenticatedError(error)
            personalMarkRequirementError = userFacingMessage(for: error)
        }
    }

    private func resetPersonalMarkRequirement() {
        personalMarkRequirementIsConfirmed = false
        isCheckingPersonalMarkRequirement = false
        personalMarkRequirementError = nil
        personalMarkVerificationGeneration = nil
    }

    @discardableResult
    func updatePersonalMark(_ mark: String?) async -> Bool {
        guard case .signedIn(let actor) = session,
              PersonalMarkRequirement.hasDrawing(mark) else { return false }
        let generation = authenticationGeneration
        let previousErrorMessage = globalErrorMessage
        do {
            let profile = try await api.updatePersonalMark(mark)
            guard case .signedIn(let current) = session,
                  current.id == actor.id, profile.id == actor.id,
                  generation == authenticationGeneration,
                  profile.avatarMark == mark,
                  PersonalMarkRequirement.hasDrawing(profile.avatarMark) else { return false }
            if globalErrorMessage == previousErrorMessage {
                globalErrorMessage = nil
            }
            if let family = profile.family { applyFamily(family) }
            personalMarkRequirementIsConfirmed = true
            applyCurrentUserProfile(profile)
            applyPersonalMark(profile.avatarMark, toUserID: profile.id)
            haptics.success()
            return true
        } catch {
            guard !Task.isCancelled, !isCancelledRequest(error),
                  case .signedIn(let current) = session,
                  current.id == actor.id, generation == authenticationGeneration else { return false }
            handleAuthenticatedError(error)
            presentGlobalError(error)
            return false
        }
    }

    func setNotificationPermissionStatus(
        _ status: NotificationPermissionStatus
    ) {
        notificationPreferences.permissionStatus = status
    }

    func loadNotificationPreferences() async {
        guard !notificationPreferences.isLoading else { return }
        let generation = authenticationGeneration
        notificationPreferences.isLoading = true
        notificationPreferences.errorMessage = nil
        defer {
            if generation == authenticationGeneration { notificationPreferences.isLoading = false }
        }

        do {
            let preferences = try await api.fetchNotificationPreferences()
            guard generation == authenticationGeneration, !Task.isCancelled else { return }
            notificationPreferences.preferences = preferences
        } catch {
            guard generation == authenticationGeneration,
                  !Task.isCancelled, !isCancelledRequest(error) else { return }
            handleAuthenticatedError(error)
            notificationPreferences.errorMessage = userFacingMessage(for: error)
        }
    }

    @discardableResult
    func updateNotificationPreferences(
        _ preferences: NotificationPreferences
    ) async -> Bool {
        guard !notificationPreferences.isSaving else { return false }
        let generation = authenticationGeneration
        notificationPreferences.isSaving = true
        notificationPreferences.errorMessage = nil
        defer {
            if generation == authenticationGeneration { notificationPreferences.isSaving = false }
        }

        do {
            let saved = try await api.updateNotificationPreferences(preferences)
            guard generation == authenticationGeneration, !Task.isCancelled else { return false }
            notificationPreferences.preferences = saved
            haptics.success()
            return true
        } catch {
            guard generation == authenticationGeneration,
                  !Task.isCancelled, !isCancelledRequest(error) else { return false }
            handleAuthenticatedError(error)
            notificationPreferences.errorMessage = userFacingMessage(for: error)
            haptics.error()
            return false
        }
    }

    func exportAccount() async -> AccountExport? {
        guard !account.isExporting else { return nil }
        account.isExporting = true
        account.errorMessage = nil
        defer { account.isExporting = false }

        do {
            let export = try await api.exportAccount()
            account.export = export
            haptics.success()
            return export
        } catch {
            handleAuthenticatedError(error)
            account.errorMessage = userFacingMessage(for: error)
            haptics.error()
            return nil
        }
    }

    @discardableResult
    func deleteAccount() async -> Bool {
        guard !account.isDeleting else { return false }
        account.isDeleting = true
        account.errorMessage = nil

        do {
            try await api.deleteAccount()
            transitionToSignedOut()
            haptics.success()
            return true
        } catch {
            account.isDeleting = false
            handleAuthenticatedError(error)
            account.errorMessage = userFacingMessage(for: error)
            haptics.error()
            return false
        }
    }

    /// This background update never changes notification switches or presents
    /// an error banner. A later foreground event retries a failed sync.
    func synchronizeDeviceTimeZone(
        _ identifier: String = TimeZone.autoupdatingCurrent.identifier
    ) async {
        guard case .signedIn(let profile) = session else {
            deviceTimeZoneSynchronizer.reset()
            return
        }
        let identity = DeviceTimeZoneSynchronizer.Identity(
            userID: profile.id,
            sessionGeneration: authenticationGeneration,
            timeZoneIdentifier: identifier
        )
        await deviceTimeZoneSynchronizer.synchronize(identity: identity) { [weak self] request in
            guard let self,
                  case .signedIn(let currentProfile) = session,
                  currentProfile.id == request.userID,
                  authenticationGeneration == request.sessionGeneration else { return false }
            do {
                try await api.updateDeviceTimeZone(request.timeZoneIdentifier)
                guard case .signedIn(let currentProfile) = session,
                      currentProfile.id == request.userID,
                      authenticationGeneration == request.sessionGeneration else { return false }
                notificationPreferences.preferences?.timeZoneIdentifier = request.timeZoneIdentifier
                return true
            } catch {
                guard !Task.isCancelled, !isCancelledRequest(error),
                      case .signedIn(let currentProfile) = session,
                      currentProfile.id == request.userID,
                      authenticationGeneration == request.sessionGeneration else { return false }
                handleAuthenticatedError(error)
                return false
            }
        }
    }

    @discardableResult
    func registerPushToken(
        _ token: String,
        environment: PushEnvironment
    ) async -> Bool {
        guard case .signedIn(let requestedProfile) = session else { return false }
        let requestedGeneration = authenticationGeneration
        do {
            try await api.registerPushToken(token, environment: environment)
            guard case .signedIn(let currentProfile) = session,
                  currentProfile.id == requestedProfile.id,
                  authenticationGeneration == requestedGeneration else { return false }
            return true
        } catch {
            guard !Task.isCancelled, !isCancelledRequest(error),
                  case .signedIn(let currentProfile) = session,
                  currentProfile.id == requestedProfile.id,
                  authenticationGeneration == requestedGeneration else { return false }
            handleAuthenticatedError(error)
            presentGlobalError(error)
            return false
        }
    }

    func unregisterPushToken(tokenHash: String) async {
        do {
            try await api.unregisterPushToken(tokenHash: tokenHash)
        } catch {
            handleAuthenticatedError(error)
            presentGlobalError(error)
        }
    }

    func openComments(answerID: String) {
        var thread = commentThreads[answerID] ?? CommentThreadState()
        thread.focusedCommentID = nil
        commentThreads[answerID] = thread
        path.append(.comments(answerID: answerID))
    }

    /// Resolves a notification deep link even when its answer is outside the
    /// currently cached feed page, then opens the answer's conversation.
    @discardableResult
    func openPushAnswer(
        answerID: String,
        targetCommentID: String? = nil
    ) async -> Bool {
        let requestedGeneration = authenticationGeneration
        do {
            let answer = try await api.fetchAnswer(answerID: answerID)
            guard authenticationGeneration == requestedGeneration, !Task.isCancelled else { return false }
            if home.feed == nil {
                home.feed = HomeFeed(answers: [answer])
            } else if let index = home.feed?.answers.firstIndex(where: {
                $0.id == answer.id
            }) {
                home.feed?.answers[index] = answer
            } else {
                home.feed?.answers.insert(answer, at: 0)
            }
            var thread = commentThreads[answer.id] ?? CommentThreadState()
            thread.focusedCommentID = nil
            commentThreads[answer.id] = thread
            let commentResolution = await performCommentLoad(answerID: answer.id)
            guard authenticationGeneration == requestedGeneration, !Task.isCancelled else { return false }
            switch commentResolution {
            case .ready:
                break
            case .terminal:
                globalErrorMessage = "この回答は削除されたか、現在は表示できません。"
                return true
            case .retryable:
                return false
            }

            if let targetCommentID {
                // Comments are cursor-paged. Continue until the notification's
                // exact comment is present, pagination ends, or a server makes
                // no cursor progress (which prevents an accidental loop).
                var previousCursor: String?
                while commentThreads[answer.id]?.comments.contains(where: {
                    $0.id == targetCommentID
                }) != true,
                let nextCursor = commentThreads[answer.id]?.nextCursor,
                nextCursor != previousCursor {
                    previousCursor = nextCursor
                    let pageResolution = await performCommentLoad(
                        answerID: answer.id,
                        loadMore: true
                    )
                    guard authenticationGeneration == requestedGeneration, !Task.isCancelled else { return false }
                    switch pageResolution {
                    case .ready:
                        break
                    case .terminal:
                        globalErrorMessage = "この回答は削除されたか、現在は表示できません。"
                        return true
                    case .retryable:
                        return false
                    }
                }

                if commentThreads[answer.id]?.comments.contains(where: {
                    $0.id == targetCommentID
                }) == true {
                    var thread = commentThreads[answer.id] ?? CommentThreadState()
                    thread.focusedCommentID = targetCommentID
                    commentThreads[answer.id] = thread
                }
                // Reaching the end without the target is terminal (for
                // example, the comment was deleted). Opening the surviving
                // conversation is still a successful handling and prevents
                // an unresolvable push from retrying forever.
            }

            path = [.home, .comments(answerID: answer.id)]
            return true
        } catch {
            guard authenticationGeneration == requestedGeneration,
                  !Task.isCancelled, !isCancelledRequest(error) else { return false }
            if isTerminalPushDestinationError(error) {
                globalErrorMessage = "この回答は削除されたか、現在は表示できません。"
                return true
            }
            handleAuthenticatedError(error)
            presentGlobalError(error)
            return false
        }
    }

    func dismissPresentedErrors(commentAnswerID: String? = nil) {
        globalErrorMessage = nil
        emailAuth.errorMessage = nil
        emailEnrollment.errorMessage = nil
        auth.errorMessage = nil
        phoneEnrollment.errorMessage = nil
        recovery.errorMessage = nil
        home.errorMessage = nil
        question.errorMessage = nil
        history.errorMessage = nil
        familySetup.errorMessage = nil
        familyLifecycle.errorMessage = nil
        answerOwnership.errorMessage = nil
        notificationPreferences.errorMessage = nil
        account.errorMessage = nil

        if let commentAnswerID,
           var thread = commentThreads[commentAnswerID] {
            thread.errorMessage = nil
            commentThreads[commentAnswerID] = thread
        }
    }

    func signOut() async {
        do {
            try await api.signOut()
            transitionToSignedOut()
        } catch {
            // Do not claim logout succeeded when the local token could not be
            // cleared; otherwise the next launch may sign the user back in.
            presentGlobalError(error)
            haptics.error()
        }
    }

    private func finishAuthentication(_ authenticatedSession: AuthSession) async {
        authenticationGeneration += 1
        resetPersonalMarkRequirement()
        canRetrySessionRestore = false
        clearVerificationChallenge(storageKey: Self.loginChallengeStorageKey)
        clearVerificationChallenge(storageKey: Self.emailLoginChallengeStorageKey)
        session = .signedIn(authenticatedSession.user)
        emailAuth = EmailVerificationFeatureState()
        auth = AuthFeatureState()
        path = [.home]
        haptics.success()
        await refreshHome()
    }

    private func transitionToSignedOut() {
        authenticationGeneration += 1
        resetPersonalMarkRequirement()
        deviceTimeZoneSynchronizer.reset()
        let pendingPairingToken = familySetup.pairingToken
        canRetrySessionRestore = false
        session = .signedOut
        clearVerificationChallenge(
            storageKey: Self.enrollmentChallengeStorageKey
        )
        clearVerificationChallenge(storageKey: Self.emailEnrollmentChallengeStorageKey)
        emailAuth = EmailVerificationFeatureState()
        emailEnrollment = EmailVerificationFeatureState()
        auth = AuthFeatureState()
        phoneEnrollment = PhoneEnrollmentFeatureState()
        recovery = RecoveryFeatureState()
        home = HomeFeatureState()
        question = QuestionFeatureState()
        history = HistoryFeatureState()
        commentThreads = [:]
        familySetup = FamilySetupFeatureState()
        familyLifecycle = FamilyLifecycleFeatureState()
        answerOwnership = AnswerOwnershipFeatureState()
        notificationPreferences = NotificationPreferencesFeatureState()
        account = AccountFeatureState()
        historyGeneration += 1
        familySetup.pairingToken = pendingPairingToken
        if pendingPairingToken == nil, restorePendingEmailLoginChallenge() {
            return
        }
        if pendingPairingToken == nil, restorePendingLoginChallenge() {
            return
        }
        path = pendingPairingToken == nil ? [.onboarding] : [.pairingEntry]
    }

    private func persistEmailVerificationChallenge(
        email: String,
        challenge: OTPChallenge,
        expiresAt: Date?,
        actorUserID: String?,
        actorEmailAtRequest: String?,
        storageKey: String
    ) {
        guard let verificationDefaults, let expiresAt else { return }
        let record = PersistedEmailVerificationChallenge(
            email: email,
            requestID: challenge.requestID,
            expiresAt: expiresAt,
            actorUserID: actorUserID,
            actorEmailAtRequest: actorEmailAtRequest,
            attemptStartedAt: nil,
            replayUntil: nil
        )
        guard let data = try? JSONEncoder().encode(record) else { return }
        verificationDefaults.set(data, forKey: storageKey)
    }

    private func persistedEmailVerificationChallenge(
        storageKey: String
    ) -> PersistedEmailVerificationChallenge? {
        guard let verificationDefaults,
              let data = verificationDefaults.data(forKey: storageKey),
              let record = try? JSONDecoder().decode(
                  PersistedEmailVerificationChallenge.self,
                  from: data
              ),
              !record.email.isEmpty,
              !record.requestID.isEmpty else {
            verificationDefaults?.removeObject(forKey: storageKey)
            return nil
        }
        let isChallengeLive = record.expiresAt > now()
        let isInterruptedAttemptRecoverable = record.attemptStartedAt != nil
            && (record.replayUntil ?? .distantPast) > now()
        guard isChallengeLive || isInterruptedAttemptRecoverable else {
            verificationDefaults.removeObject(forKey: storageKey)
            return nil
        }
        return record
    }

    private func markEmailVerificationAttemptStarted(storageKey: String) {
        guard let verificationDefaults,
              let data = verificationDefaults.data(forKey: storageKey),
              let record = try? JSONDecoder().decode(
                  PersistedEmailVerificationChallenge.self,
                  from: data
              ) else {
            return
        }
        let updated = PersistedEmailVerificationChallenge(
            email: record.email,
            requestID: record.requestID,
            expiresAt: record.expiresAt,
            actorUserID: record.actorUserID,
            actorEmailAtRequest: record.actorEmailAtRequest,
            attemptStartedAt: now(),
            replayUntil: now().addingTimeInterval(
                Self.verificationReplayRetention
            )
        )
        guard let encoded = try? JSONEncoder().encode(updated) else { return }
        verificationDefaults.set(encoded, forKey: storageKey)
    }

    private func markEmailVerificationAttemptDefinitivelyResolved(
        storageKey: String
    ) {
        guard let verificationDefaults,
              let data = verificationDefaults.data(forKey: storageKey),
              let record = try? JSONDecoder().decode(
                  PersistedEmailVerificationChallenge.self,
                  from: data
              ) else {
            return
        }
        guard record.expiresAt > now() else {
            verificationDefaults.removeObject(forKey: storageKey)
            return
        }
        let updated = PersistedEmailVerificationChallenge(
            email: record.email,
            requestID: record.requestID,
            expiresAt: record.expiresAt,
            actorUserID: record.actorUserID,
            actorEmailAtRequest: record.actorEmailAtRequest,
            attemptStartedAt: nil,
            replayUntil: nil
        )
        guard let encoded = try? JSONEncoder().encode(updated) else { return }
        verificationDefaults.set(encoded, forKey: storageKey)
    }

    @discardableResult
    private func restorePendingEmailLoginChallenge() -> Bool {
        guard let record = persistedEmailVerificationChallenge(
            storageKey: Self.emailLoginChallengeStorageKey
        ), record.actorUserID == nil else {
            return false
        }
        let remaining = max(
            1,
            Int(ceil(record.expiresAt.timeIntervalSince(now())))
        )
        emailAuth = EmailVerificationFeatureState(
            email: record.email,
            verificationCode: "",
            challenge: OTPChallenge(
                requestID: record.requestID,
                expiresIn: remaining
            ),
            expiresAt: record.expiresAt,
            canReplayExpiredAttempt: record.attemptStartedAt != nil
        )
        session = .awaitingEmailVerification(email: record.email)
        path = [
            .emailVerification(
                email: record.email,
                requestID: record.requestID
            )
        ]
        return true
    }

    private func restorePendingEmailEnrollmentChallenge(for user: UserProfile) {
        guard let record = persistedEmailVerificationChallenge(
            storageKey: Self.emailEnrollmentChallengeStorageKey
        ) else {
            return
        }
        guard record.actorUserID == user.id else {
            clearVerificationChallenge(
                storageKey: Self.emailEnrollmentChallengeStorageKey
            )
            return
        }
        // A fetched profile with an email means enrollment committed even if
        // the process died before the verification screen cleared its record.
        let fetchedEmail = Self.canonicalEmail(user.email ?? "")
        let enrollmentHasCompleted: Bool
        if let actorEmailAtRequest = record.actorEmailAtRequest {
            let previousEmail = Self.canonicalEmail(actorEmailAtRequest)
            enrollmentHasCompleted = fetchedEmail != previousEmail
                || (previousEmail.isEmpty && user.hasEmail == true)
        } else {
            // Backward-compatible self-heal for a record written before the
            // previous-email snapshot existed.
            enrollmentHasCompleted = !fetchedEmail.isEmpty
                && fetchedEmail == Self.canonicalEmail(record.email)
        }
        if enrollmentHasCompleted {
            clearVerificationChallenge(
                storageKey: Self.emailEnrollmentChallengeStorageKey
            )
            return
        }
        let remaining = max(
            1,
            Int(ceil(record.expiresAt.timeIntervalSince(now())))
        )
        emailEnrollment = EmailVerificationFeatureState(
            email: record.email,
            verificationCode: "",
            challenge: OTPChallenge(
                requestID: record.requestID,
                expiresIn: remaining
            ),
            expiresAt: record.expiresAt,
            canReplayExpiredAttempt: record.attemptStartedAt != nil
        )
        path.append(
            .emailEnrollmentVerification(
                email: record.email,
                requestID: record.requestID
            )
        )
    }

    private func persistVerificationChallenge(
        phoneNumber: String,
        challenge: OTPChallenge,
        expiresAt: Date?,
        actorUserID: String?,
        actorPhoneAtRequest: String?,
        storageKey: String
    ) {
        guard let verificationDefaults, let expiresAt else { return }
        let record = PersistedVerificationChallenge(
            phoneNumber: phoneNumber,
            requestID: challenge.requestID,
            expiresAt: expiresAt,
            actorUserID: actorUserID,
            actorPhoneAtRequest: actorPhoneAtRequest,
            attemptStartedAt: nil,
            replayUntil: nil
        )
        guard let data = try? JSONEncoder().encode(record) else { return }
        verificationDefaults.set(data, forKey: storageKey)
    }

    private func persistedVerificationChallenge(
        storageKey: String
    ) -> PersistedVerificationChallenge? {
        guard let verificationDefaults,
              let data = verificationDefaults.data(forKey: storageKey),
              let record = try? JSONDecoder().decode(
                  PersistedVerificationChallenge.self,
                  from: data
              ),
              !record.phoneNumber.isEmpty,
              !record.requestID.isEmpty else {
            verificationDefaults?.removeObject(forKey: storageKey)
            return nil
        }
        let isChallengeLive = record.expiresAt > now()
        let isInterruptedAttemptRecoverable = record.attemptStartedAt != nil
            && (record.replayUntil ?? .distantPast) > now()
        guard isChallengeLive || isInterruptedAttemptRecoverable else {
            verificationDefaults.removeObject(forKey: storageKey)
            return nil
        }
        return record
    }

    private func markVerificationAttemptStarted(storageKey: String) {
        guard let verificationDefaults,
              let data = verificationDefaults.data(forKey: storageKey),
              let record = try? JSONDecoder().decode(
                  PersistedVerificationChallenge.self,
                  from: data
              ) else {
            return
        }
        let updated = PersistedVerificationChallenge(
            phoneNumber: record.phoneNumber,
            requestID: record.requestID,
            expiresAt: record.expiresAt,
            actorUserID: record.actorUserID,
            actorPhoneAtRequest: record.actorPhoneAtRequest,
            attemptStartedAt: now(),
            replayUntil: now().addingTimeInterval(
                Self.verificationReplayRetention
            )
        )
        guard let encoded = try? JSONEncoder().encode(updated) else { return }
        verificationDefaults.set(encoded, forKey: storageKey)
    }

    private func markVerificationAttemptDefinitivelyResolved(
        storageKey: String
    ) {
        guard let verificationDefaults,
              let data = verificationDefaults.data(forKey: storageKey),
              let record = try? JSONDecoder().decode(
                  PersistedVerificationChallenge.self,
                  from: data
              ) else {
            return
        }
        guard record.expiresAt > now() else {
            verificationDefaults.removeObject(forKey: storageKey)
            return
        }
        let updated = PersistedVerificationChallenge(
            phoneNumber: record.phoneNumber,
            requestID: record.requestID,
            expiresAt: record.expiresAt,
            actorUserID: record.actorUserID,
            actorPhoneAtRequest: record.actorPhoneAtRequest,
            attemptStartedAt: nil,
            replayUntil: nil
        )
        guard let encoded = try? JSONEncoder().encode(updated) else { return }
        verificationDefaults.set(encoded, forKey: storageKey)
    }

    private func clearVerificationChallenge(storageKey: String) {
        verificationDefaults?.removeObject(forKey: storageKey)
    }

    @discardableResult
    private func restorePendingLoginChallenge() -> Bool {
        guard let record = persistedVerificationChallenge(
            storageKey: Self.loginChallengeStorageKey
        ), record.actorUserID == nil else {
            return false
        }
        let remaining = max(
            1,
            Int(ceil(record.expiresAt.timeIntervalSince(now())))
        )
        auth = AuthFeatureState(
            phoneNumber: record.phoneNumber,
            verificationCode: "",
            challenge: OTPChallenge(
                requestID: record.requestID,
                expiresIn: remaining
            ),
            expiresAt: record.expiresAt,
            canReplayExpiredAttempt: record.attemptStartedAt != nil
        )
        session = .awaitingOTP(phoneNumber: record.phoneNumber)
        path = [
            .otpVerification(
                phoneNumber: record.phoneNumber,
                requestID: record.requestID
            )
        ]
        return true
    }

    private func restorePendingEnrollmentChallenge(for user: UserProfile) {
        guard let record = persistedVerificationChallenge(
            storageKey: Self.enrollmentChallengeStorageKey
        ) else {
            return
        }
        guard record.actorUserID == user.id else {
            clearVerificationChallenge(
                storageKey: Self.enrollmentChallengeStorageKey
            )
            return
        }
        // A fetched profile with a phone means enrollment committed even if
        // the process died before the verification screen cleared its record.
        let fetchedPhone = Self.canonicalPhone(user.phoneNumber ?? "")
        let enrollmentHasCompleted: Bool
        if let actorPhoneAtRequest = record.actorPhoneAtRequest {
            let previousPhone = Self.canonicalPhone(actorPhoneAtRequest)
            enrollmentHasCompleted = fetchedPhone != previousPhone
                || (previousPhone.isEmpty && user.hasPhone == true)
        } else {
            // Backward-compatible self-heal for a record written before the
            // previous-phone snapshot existed.
            enrollmentHasCompleted = !fetchedPhone.isEmpty
                && fetchedPhone == Self.canonicalPhone(record.phoneNumber)
        }
        if enrollmentHasCompleted {
            clearVerificationChallenge(
                storageKey: Self.enrollmentChallengeStorageKey
            )
            return
        }
        let remaining = max(
            1,
            Int(ceil(record.expiresAt.timeIntervalSince(now())))
        )
        phoneEnrollment = PhoneEnrollmentFeatureState(
            phoneNumber: record.phoneNumber,
            verificationCode: "",
            challenge: OTPChallenge(
                requestID: record.requestID,
                expiresIn: remaining
            ),
            expiresAt: record.expiresAt,
            canReplayExpiredAttempt: record.attemptStartedAt != nil
        )
        path.append(
            .phoneEnrollmentVerification(
                phoneNumber: record.phoneNumber,
                requestID: record.requestID
            )
        )
    }

    private func handleAuthenticatedError(_ error: Error) {
        if isUnauthorized(error) {
            transitionToSignedOut()
        }
    }

    private func isUnauthorized(_ error: Error) -> Bool {
        guard let apiError = error as? APIClientError else { return false }
        if case .unauthorized = apiError {
            return true
        }
        return false
    }

    private func userFacingMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
    }

    private func isCancelledRequest(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if (error as? URLError)?.code == .cancelled { return true }
        if case .transport(let underlying) = error as? APIClientError {
            return isCancelledRequest(underlying)
        }
        return false
    }

    private func isTerminalPushDestinationError(_ error: Error) -> Bool {
        guard case .server(let statusCode, _) = error as? APIClientError else {
            return false
        }
        return statusCode == 404 || statusCode == 410
    }

    private func presentGlobalError(_ error: Error) {
        guard !isCancelledRequest(error) else { return }
        globalErrorMessage = userFacingMessage(for: error)
    }

    private func applyPersonalMark(_ mark: String?, toUserID userID: String) {
        for index in home.feed?.answers.indices ?? 0..<0
        where home.feed?.answers[index].author.id == userID {
            home.feed?.answers[index].author.avatarMark = mark
        }
        for index in history.answers.indices where history.answers[index].author.id == userID {
            history.answers[index].author.avatarMark = mark
        }
        if home.feed?.myAnswer?.author.id == userID { home.feed?.myAnswer?.author.avatarMark = mark }
        if home.feed?.todayQuestion?.answer?.author.id == userID { home.feed?.todayQuestion?.answer?.author.avatarMark = mark }
        if question.question?.answer?.author.id == userID { question.question?.answer?.author.avatarMark = mark }
        for key in Array(commentThreads.keys) {
            guard var thread = commentThreads[key] else { continue }
            for index in thread.comments.indices where thread.comments[index].author.id == userID {
                thread.comments[index].author.avatarMark = mark
            }
            commentThreads[key] = thread
        }
    }

    private var currentPairingCredential: FamilyPairingCredential? {
        if let token = familySetup.pairingToken,
           !token.isEmpty {
            return .token(token)
        }
        let code = NumericInputValidation.asciiDigits(
            in: familySetup.pairingCode,
            maximum: 6
        )
        return code.count == 6 ? .code(code) : nil
    }

    private func applyFamily(_ family: FamilySummary) {
        familySetup.family = family
        home.feed?.family = family
        if familySetup.activePairing?.family.id == family.id {
            familySetup.activePairing?.family.name = family.name
        }
        if familySetup.pairingPreview?.family.id == family.id {
            familySetup.pairingPreview?.family.name = family.name
        }
        for index in familySetup.pairings.indices
        where familySetup.pairings[index].family.id == family.id {
            familySetup.pairings[index].family.name = family.name
        }
        if notificationPreferences.preferences?.familyID != nil {
            notificationPreferences.preferences?.familyID = family.id
        }

        if case .signedIn(var profile) = session {
            profile.family = family
            session = .signedIn(profile)
        }
    }

    private func applyCurrentUserProfile(_ incomingProfile: UserProfile) {
        guard case .signedIn(let currentProfile) = session else { return }
        var profile = incomingProfile
        if profile.family == nil {
            profile.family = currentProfile.family
                ?? familySetup.family
                ?? home.feed?.family
        }
        let authoritativeFamilyMember = profile.family?.members.first(where: {
            $0.id == profile.id
        })
        if profile.familyRole == nil {
            profile.familyRole = authoritativeFamilyMember?.familyRole
                ?? currentProfile.familyRole
        }
        if profile.joinedAt == nil {
            profile.joinedAt = authoritativeFamilyMember?.joinedAt
                ?? currentProfile.joinedAt
        }
        session = .signedIn(profile)
        applyFamilyMember(profile)
        applyDisplayName(profile.displayName, toUserID: profile.id)
    }

    private func applyFamilyMember(_ member: UserProfile) {
        var cachedMember = member
        // Family members are summaries. Avoid nesting a full family inside
        // itself when a profile mutation response includes its family object.
        cachedMember.family = nil
        cachedMember.email = nil
        if var family = familySetup.family,
           let index = family.members.firstIndex(where: { $0.id == member.id }) {
            family.members[index] = cachedMember
            family.memberCount = family.members.count
            familySetup.family = family
        }
        if var family = home.feed?.family,
           let index = family.members.firstIndex(where: { $0.id == member.id }) {
            family.members[index] = cachedMember
            family.memberCount = family.members.count
            home.feed?.family = family
        }
    }

    private func applyPairingMemberName(
        _ displayName: String,
        toUserID userID: String
    ) {
        if familySetup.activePairing?.member.id == userID {
            familySetup.activePairing?.member.displayName = displayName
        }
        if familySetup.pairingPreview?.member.id == userID {
            familySetup.pairingPreview?.member.displayName = displayName
        }
        for index in familySetup.pairings.indices
        where familySetup.pairings[index].member.id == userID {
            familySetup.pairings[index].member.displayName = displayName
        }
    }

    private func removeFamilyMemberFromCaches(memberID: String) {
        var cachedAnswers = (home.feed?.answers ?? []) + history.answers
        if let answer = home.feed?.myAnswer { cachedAnswers.append(answer) }
        if let answer = home.feed?.todayQuestion?.answer {
            cachedAnswers.append(answer)
        }
        if let answer = question.question?.answer { cachedAnswers.append(answer) }
        let answerIDs = Set(cachedAnswers.compactMap { answer in
            answer.author.id == memberID ? answer.id : nil
        })
        for answerID in answerIDs {
            removeCachedAnswer(answerID: answerID)
        }

        for answerID in Array(commentThreads.keys) {
            guard var thread = commentThreads[answerID] else { continue }
            let oldCount = thread.comments.count
            let removedCommentIDs = Set(thread.comments.compactMap { comment in
                comment.author.id == memberID ? comment.id : nil
            })
            thread.comments.removeAll(where: { $0.author.id == memberID })
            for commentID in removedCommentIDs {
                thread.reportsByCommentID[commentID] = nil
            }
            let removedCount = oldCount - thread.comments.count
            if removedCount > 0 {
                adjustCommentCount(answerID: answerID, by: -removedCount)
            }
            commentThreads[answerID] = thread
        }

        if var family = familySetup.family {
            family.members.removeAll(where: { $0.id == memberID })
            family.memberCount = family.members.count
            applyFamily(family)
        } else if var family = home.feed?.family {
            family.members.removeAll(where: { $0.id == memberID })
            family.memberCount = family.members.count
            applyFamily(family)
        }
        familySetup.pairings.removeAll(where: { $0.member.id == memberID })
        if familySetup.activePairing?.member.id == memberID {
            familySetup.activePairing = nil
        }
        if familySetup.pairingPreview?.member.id == memberID {
            familySetup.pairingPreview = nil
        }
        if familySetup.pendingManagedMember?.id == memberID {
            familySetup.pendingManagedMember = nil
        }
    }

    private func synchronizeCurrentFamilyRole() {
        guard case .signedIn(var profile) = session,
              let family = familySetup.family ?? home.feed?.family else {
            return
        }
        profile.family = family
        if let member = family.members.first(where: { $0.id == profile.id }) {
            profile.familyRole = member.familyRole
            profile.joinedAt = member.joinedAt
        }
        session = .signedIn(profile)
    }

    private func prepareForReplacementFamilyAfterLeaving() {
        if case .signedIn(var profile) = session {
            profile.family = nil
            profile.familyRole = nil
            profile.joinedAt = nil
            session = .signedIn(profile)
        }
        familySetup = FamilySetupFeatureState()
        home = HomeFeatureState()
        question = QuestionFeatureState()
        historyGeneration += 1
        history = HistoryFeatureState()
        commentThreads = [:]
        notificationPreferences.preferences = nil
        path = [.home]
    }

    private func appendFamilyMemberIfNeeded(_ member: UserProfile) {
        guard var family = familySetup.family,
              !family.members.contains(where: { $0.id == member.id }) else {
            return
        }
        family.members.append(member)
        family.memberCount = family.members.count
        applyFamily(family)
    }

    private func applyCreatedPairing(_ pairing: FamilyPairing) {
        familySetup.activePairing = pairing
        familySetup.pairings.removeAll {
            $0.member.id == pairing.member.id
        }
        familySetup.pairings.insert(pairing.preview, at: 0)
        if path.last != .pairingShare {
            path.append(.pairingShare)
        }
    }

    private func applyDisplayName(_ displayName: String, toUserID userID: String) {
        if case .signedIn(var profile) = session,
           profile.id == userID {
            profile.displayName = displayName
            session = .signedIn(profile)
        }
        if var family = familySetup.family,
           let memberIndex = family.members.firstIndex(where: {
               $0.id == userID
           }) {
            family.members[memberIndex].displayName = displayName
            familySetup.family = family
        }
        if var family = home.feed?.family,
           let memberIndex = family.members.firstIndex(where: {
               $0.id == userID
           }) {
            family.members[memberIndex].displayName = displayName
            home.feed?.family = family
        }

        if var answers = home.feed?.answers {
            for index in answers.indices
            where answers[index].author.id == userID {
                answers[index].author.displayName = displayName
            }
            home.feed?.answers = answers
        }
        if home.feed?.myAnswer?.author.id == userID {
            home.feed?.myAnswer?.author.displayName = displayName
        }
        if home.feed?.todayQuestion?.answer?.author.id == userID {
            home.feed?.todayQuestion?.answer?.author.displayName = displayName
        }
        if question.question?.answer?.author.id == userID {
            question.question?.answer?.author.displayName = displayName
        }

        for index in history.answers.indices
        where history.answers[index].author.id == userID {
            history.answers[index].author.displayName = displayName
        }

        for answerID in Array(commentThreads.keys) {
            guard var thread = commentThreads[answerID] else { continue }
            for index in thread.comments.indices
            where thread.comments[index].author.id == userID {
                thread.comments[index].author.displayName = displayName
            }
            commentThreads[answerID] = thread
        }
    }

    private func replaceCachedAnswer(_ answer: Answer) {
        updateHomeAnswerProgress(for: answer, isAnswered: true)
        if let index = home.feed?.answers.firstIndex(where: {
            $0.id == answer.id
        }) {
            home.feed?.answers[index] = answer
        }
        if home.feed?.myAnswer?.id == answer.id {
            home.feed?.myAnswer = answer
        }
        if home.feed?.todayQuestion?.answer?.id == answer.id {
            home.feed?.todayQuestion?.answer = answer
        }
        if question.question?.answer?.id == answer.id {
            question.question?.answer = answer
        }
        if let index = history.answers.firstIndex(where: {
            $0.id == answer.id
        }) {
            if answerMatchesHistoryQuery(answer) {
                history.answers[index] = answer
            } else {
                history.answers.remove(at: index)
            }
        }
    }

    private func removeCachedAnswer(answerID: String) {
        if let cachedAnswer = answer(withID: answerID) {
            updateHomeAnswerProgress(for: cachedAnswer, isAnswered: false)
        }
        home.feed?.answers.removeAll(where: { $0.id == answerID })
        if home.feed?.myAnswer?.id == answerID {
            home.feed?.myAnswer = nil
        }
        if home.feed?.todayQuestion?.answer?.id == answerID {
            home.feed?.todayQuestion?.answer = nil
        }
        if question.question?.answer?.id == answerID {
            question.question?.answer = nil
        }
        history.answers.removeAll(where: { $0.id == answerID })
        commentThreads[answerID] = nil
    }

    private func updateHomeAnswerProgress(for answer: Answer, isAnswered: Bool) {
        guard let today = home.feed?.todayQuestion,
              answer.answerDate == today.publishedOn,
              answer.questionID == today.id,
              var answeredIDs = home.feed?.todayAnsweredUserIDs else { return }

        if isAnswered {
            if !answeredIDs.contains(answer.author.id) {
                answeredIDs.append(answer.author.id)
            }
        } else {
            answeredIDs.removeAll(where: { $0 == answer.author.id })
        }
        home.feed?.todayAnsweredUserIDs = answeredIDs
    }

    private func answerMatchesHistoryQuery(_ answer: Answer) -> Bool {
        let query = history.query
        if query.scope == .mine,
           case .signedIn(let profile) = session,
           answer.author.id != profile.id {
            return false
        }
        if let authorID = query.authorID,
           answer.author.id != authorID {
            return false
        }
        if let startDate = query.startDate,
           (answer.answerDate ?? "") < startDate {
            return false
        }
        if let endDate = query.endDate,
           (answer.answerDate ?? "") > endDate {
            return false
        }
        if !query.searchText.isEmpty {
            let search = query.searchText.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            let content = [
                answer.body,
                answer.questionPrompt ?? "",
                answer.author.displayName,
            ]
                .joined(separator: "\n")
                .folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                )
            if !content.contains(search) { return false }
        }
        return true
    }

    private func uniqueAnswers(_ answers: [Answer]) -> [Answer] {
        var seen = Set<String>()
        return answers.filter { seen.insert($0.id).inserted }
    }

    private func mergedAnswers(
        _ current: [Answer],
        appending newAnswers: [Answer]
    ) -> [Answer] {
        var byID: [String: Answer] = [:]
        var order: [String] = []
        for answer in current {
            if byID[answer.id] == nil { order.append(answer.id) }
            byID[answer.id] = answer
        }
        for answer in newAnswers {
            if byID[answer.id] == nil {
                order.append(answer.id)
            }
            byID[answer.id] = answer
        }
        return order.compactMap { byID[$0] }
    }

    private func mergedComments(
        _ current: [Comment],
        appending newComments: [Comment]
    ) -> [Comment] {
        var byID: [String: Comment] = [:]
        var order: [String] = []
        for comment in current {
            if byID[comment.id] == nil { order.append(comment.id) }
            byID[comment.id] = comment
        }
        for comment in newComments {
            if byID[comment.id] == nil {
                order.append(comment.id)
            }
            byID[comment.id] = comment
        }
        return order.compactMap { byID[$0] }
    }

    private func answer(withID id: String) -> Answer? {
        if let answer = home.feed?.answers.first(where: { $0.id == id }) {
            return answer
        }
        if let answer = history.answers.first(where: { $0.id == id }) {
            return answer
        }
        if question.question?.answer?.id == id {
            return question.question?.answer
        }
        if home.feed?.myAnswer?.id == id {
            return home.feed?.myAnswer
        }
        return nil
    }

    private func applyLike(_ state: LikeState, to answerID: String) {
        if let index = home.feed?.answers.firstIndex(where: { $0.id == answerID }) {
            home.feed?.answers[index].isLikedByMe = state.isLikedByMe
            home.feed?.answers[index].likeCount = state.likeCount
        }
        if let index = history.answers.firstIndex(where: { $0.id == answerID }) {
            history.answers[index].isLikedByMe = state.isLikedByMe
            history.answers[index].likeCount = state.likeCount
        }
        if question.question?.answer?.id == answerID {
            question.question?.answer?.isLikedByMe = state.isLikedByMe
            question.question?.answer?.likeCount = state.likeCount
        }
        if home.feed?.myAnswer?.id == answerID {
            home.feed?.myAnswer?.isLikedByMe = state.isLikedByMe
            home.feed?.myAnswer?.likeCount = state.likeCount
        }
        if home.feed?.todayQuestion?.answer?.id == answerID {
            home.feed?.todayQuestion?.answer?.isLikedByMe = state.isLikedByMe
            home.feed?.todayQuestion?.answer?.likeCount = state.likeCount
        }
    }

    private func incrementCommentCount(answerID: String) {
        adjustCommentCount(answerID: answerID, by: 1)
    }

    private func decrementCommentCount(answerID: String) {
        adjustCommentCount(answerID: answerID, by: -1)
    }

    private func adjustCommentCount(answerID: String, by delta: Int) {
        if let index = home.feed?.answers.firstIndex(where: { $0.id == answerID }) {
            let currentCount = home.feed?.answers[index].commentCount ?? 0
            home.feed?.answers[index].commentCount = max(
                0,
                currentCount + delta
            )
        }
        if let index = history.answers.firstIndex(where: { $0.id == answerID }) {
            history.answers[index].commentCount = max(
                0,
                history.answers[index].commentCount + delta
            )
        }
        if question.question?.answer?.id == answerID {
            let currentCount = question.question?.answer?.commentCount ?? 0
            question.question?.answer?.commentCount = max(
                0,
                currentCount + delta
            )
        }
        if home.feed?.myAnswer?.id == answerID {
            let count = home.feed?.myAnswer?.commentCount ?? 0
            home.feed?.myAnswer?.commentCount = max(0, count + delta)
        }
        if home.feed?.todayQuestion?.answer?.id == answerID {
            let count = home.feed?.todayQuestion?.answer?.commentCount ?? 0
            home.feed?.todayQuestion?.answer?.commentCount = max(
                0,
                count + delta
            )
        }
    }

    private func isDefinitiveVerificationFailure(_ error: Error) -> Bool {
        guard let apiError = error as? APIClientError else { return false }
        switch apiError {
        case .missingConfiguration,
             .invalidBaseURL,
             .invalidRequest,
             .unsupportedOperation,
             .unauthorized:
            return true
        case .server(let statusCode, _):
            return statusCode < 500 && statusCode != 429
        case .invalidResponse, .decoding, .transport:
            return false
        }
    }

    private static func canonicalEmail(_ value: String) -> String {
        EmailAddressValidation.normalized(value) ?? ""
    }

    private static func canonicalPhone(_ value: String) -> String {
        PhoneNumberValidation.canonicalE164(value) ?? ""
    }
}

private extension AppRoute {
    var isEmailEnrollmentRoute: Bool {
        switch self {
        case .emailEnrollment, .emailEnrollmentVerification: return true
        default: return false
        }
    }

    var isPhoneEnrollmentRoute: Bool {
        switch self {
        case .phoneEnrollment, .phoneEnrollmentVerification:
            return true
        default:
            return false
        }
    }
}
