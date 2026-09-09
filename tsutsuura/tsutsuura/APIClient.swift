import CryptoKit
import Foundation

protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        return (data, httpResponse)
    }
}

struct APIRequestRetryPolicy: Equatable, Sendable {
    let maximumAttempts: Int
    let initialDelay: TimeInterval
    let maximumDelay: TimeInterval

    init(
        maximumAttempts: Int = 3,
        initialDelay: TimeInterval = 0.25,
        maximumDelay: TimeInterval = 2
    ) {
        self.maximumAttempts = max(1, maximumAttempts)
        self.initialDelay = max(0, initialDelay)
        self.maximumDelay = max(0, maximumDelay)
    }

    static let standard = APIRequestRetryPolicy()
    static let disabled = APIRequestRetryPolicy(
        maximumAttempts: 1,
        initialDelay: 0,
        maximumDelay: 0
    )
}

protocol AppAPI: Sendable {
    func hasStoredSession() async throws -> Bool
    func requestEmailOTP(email: String) async throws -> OTPChallenge
    func verifyEmailOTP(requestID: String, code: String) async throws -> AuthSession
    func requestEmailEnrollment(email: String) async throws -> OTPChallenge
    func verifyEmailEnrollment(requestID: String, code: String) async throws -> UserProfile
    func requestOTP(phoneNumber: String) async throws -> OTPChallenge
    func verifyOTP(requestID: String, code: String) async throws -> AuthSession
    func requestPhoneEnrollment(phoneNumber: String) async throws -> OTPChallenge
    func verifyPhoneEnrollment(requestID: String, code: String) async throws -> UserProfile
    func createAccountRecoveryCode() async throws -> AccountRecoveryCode
    func recoverAccount(code: String) async throws -> AuthSession
    func fetchMe() async throws -> UserProfile
    func updateProfile(displayName: String) async throws -> UserProfile
    func updatePersonalMark(_ mark: String?) async throws -> UserProfile
    func fetchFamily() async throws -> FamilySummary
    func renameFamily(name: String) async throws -> FamilySummary
    func createOrganizerFamily(
        organizerName: String,
        familyName: String
    ) async throws -> AuthSession
    func addManagedFamilyMember(displayName: String) async throws -> UserProfile
    func renameManagedFamilyMember(
        memberID: String,
        displayName: String
    ) async throws -> UserProfile
    func removeManagedFamilyMember(memberID: String) async throws
    func transferFamilyOwnership(to memberID: String) async throws -> FamilySummary
    func leaveFamily() async throws -> FamilyLeaveResult
    func createFamilyPairing(memberID: String) async throws -> FamilyPairing
    func previewFamilyPairing(
        _ credential: FamilyPairingCredential
    ) async throws -> FamilyPairingPreview
    func activateFamilyPairing(
        _ credential: FamilyPairingCredential
    ) async throws -> AuthSession
    func fetchFamilyPairings() async throws -> [FamilyPairingPreview]
    func revokeFamilyPairing(pairingID: String) async throws
    func fetchHome(cursor: String?) async throws -> HomeFeed
    func fetchTodayQuestion() async throws -> Question
    func fetchAnswer(answerID: String) async throws -> Answer
    func submitAnswer(questionID: String, body: String) async throws -> Answer
    func submitAnswer(
        questionID: String,
        submission: AnswerSubmission
    ) async throws -> Answer
    func submitAnswer(
        questionID: String, questionDate: String?, submission: AnswerSubmission
    ) async throws -> Answer
    func updateAnswer(
        answerID: String,
        submission: AnswerSubmission
    ) async throws -> Answer
    func deleteAnswer(answerID: String) async throws
    func deleteAnswerMedia(answerID: String, mediaID: String) async throws -> Answer
    func fetchAnswerMedia(_ media: AnswerMedia) async throws -> AnswerMediaContent
    func fetchAnswerHistory(cursor: String?) async throws -> AnswerPage
    func fetchAnswerHistory(
        query: HistoryQuery,
        cursor: String?
    ) async throws -> AnswerPage
    func setLike(answerID: String, isLiked: Bool) async throws -> LikeState
    func fetchComments(answerID: String, cursor: String?) async throws -> CommentPage
    func createComment(answerID: String, body: String) async throws -> Comment
    func replyToComment(
        answerID: String,
        parentCommentID: String,
        body: String
    ) async throws -> Comment
    func updateComment(commentID: String, body: String) async throws -> Comment
    func deleteComment(commentID: String, answerID: String) async throws
    func reportComment(
        commentID: String,
        reason: CommentReportReason,
        details: String?
    ) async throws -> CommentReport
    func fetchContentSafety() async throws -> ContentSafetySnapshot
    func blockUser(userID: String) async throws
    func unblockUser(userID: String) async throws
    func reportAnswer(answerID: String, reason: CommentReportReason, details: String?) async throws -> AnswerReport
    func fetchNotificationPreferences() async throws -> NotificationPreferences
    func updateDeviceTimeZone(_ identifier: String) async throws
    func updateNotificationPreferences(
        _ preferences: NotificationPreferences
    ) async throws -> NotificationPreferences
    func exportAccount() async throws -> AccountExport
    func deleteAccount() async throws
    func registerPushToken(
        _ token: String,
        environment: PushEnvironment
    ) async throws
    func unregisterPushToken(tokenHash: String) async throws
    func signOut() async throws
}

extension AppAPI {
    func fetchContentSafety() async throws -> ContentSafetySnapshot { throw APIClientError.unsupportedOperation }
    func blockUser(userID: String) async throws { throw APIClientError.unsupportedOperation }
    func unblockUser(userID: String) async throws { throw APIClientError.unsupportedOperation }
    func reportAnswer(answerID: String, reason: CommentReportReason, details: String?) async throws -> AnswerReport { throw APIClientError.unsupportedOperation }

    func updateDeviceTimeZone(_ identifier: String) async throws {
        throw APIClientError.unsupportedOperation
    }

    func requestEmailOTP(email: String) async throws -> OTPChallenge {
        throw APIClientError.unsupportedOperation
    }
    func verifyEmailOTP(requestID: String, code: String) async throws -> AuthSession {
        throw APIClientError.unsupportedOperation
    }
    func requestEmailEnrollment(email: String) async throws -> OTPChallenge {
        throw APIClientError.unsupportedOperation
    }
    func verifyEmailEnrollment(requestID: String, code: String) async throws -> UserProfile {
        throw APIClientError.unsupportedOperation
    }

    func updatePersonalMark(_ mark: String?) async throws -> UserProfile {
        throw APIClientError.unsupportedOperation
    }
    func fetchAnswer(answerID: String) async throws -> Answer {
        throw APIClientError.unsupportedOperation
    }

    func requestPhoneEnrollment(
        phoneNumber: String
    ) async throws -> OTPChallenge {
        throw APIClientError.unsupportedOperation
    }

    func verifyPhoneEnrollment(
        requestID: String,
        code: String
    ) async throws -> UserProfile {
        throw APIClientError.unsupportedOperation
    }

    func createAccountRecoveryCode() async throws -> AccountRecoveryCode {
        throw APIClientError.unsupportedOperation
    }

    func recoverAccount(code: String) async throws -> AuthSession {
        throw APIClientError.unsupportedOperation
    }

    func renameFamily(name: String) async throws -> FamilySummary {
        throw APIClientError.unsupportedOperation
    }

    func renameManagedFamilyMember(
        memberID: String,
        displayName: String
    ) async throws -> UserProfile {
        throw APIClientError.unsupportedOperation
    }

    func removeManagedFamilyMember(memberID: String) async throws {
        throw APIClientError.unsupportedOperation
    }

    func transferFamilyOwnership(
        to memberID: String
    ) async throws -> FamilySummary {
        throw APIClientError.unsupportedOperation
    }

    func leaveFamily() async throws -> FamilyLeaveResult {
        throw APIClientError.unsupportedOperation
    }

    func submitAnswer(
        questionID: String,
        submission: AnswerSubmission
    ) async throws -> Answer {
        try submission.validate()
        guard !submission.hasMedia else {
            throw APIClientError.unsupportedOperation
        }
        return try await submitAnswer(
            questionID: questionID,
            body: submission.body
        )
    }

    func submitAnswer(
        questionID: String, questionDate: String?, submission: AnswerSubmission
    ) async throws -> Answer {
        try await submitAnswer(questionID: questionID, submission: submission)
    }

    func fetchAnswerMedia(
        _ media: AnswerMedia
    ) async throws -> AnswerMediaContent {
        throw APIClientError.unsupportedOperation
    }

    func updateAnswer(
        answerID: String,
        submission: AnswerSubmission
    ) async throws -> Answer {
        throw APIClientError.unsupportedOperation
    }

    func deleteAnswer(answerID: String) async throws {
        throw APIClientError.unsupportedOperation
    }

    func deleteAnswerMedia(
        answerID: String,
        mediaID: String
    ) async throws -> Answer {
        throw APIClientError.unsupportedOperation
    }

    func fetchAnswerHistory(
        query: HistoryQuery,
        cursor: String?
    ) async throws -> AnswerPage {
        try await fetchAnswerHistory(cursor: cursor)
    }

    func replyToComment(
        answerID: String,
        parentCommentID: String,
        body: String
    ) async throws -> Comment {
        throw APIClientError.unsupportedOperation
    }

    func updateComment(
        commentID: String,
        body: String
    ) async throws -> Comment {
        throw APIClientError.unsupportedOperation
    }

    func reportComment(
        commentID: String,
        reason: CommentReportReason,
        details: String?
    ) async throws -> CommentReport {
        throw APIClientError.unsupportedOperation
    }

    func fetchNotificationPreferences() async throws -> NotificationPreferences {
        throw APIClientError.unsupportedOperation
    }

    func updateNotificationPreferences(
        _ preferences: NotificationPreferences
    ) async throws -> NotificationPreferences {
        throw APIClientError.unsupportedOperation
    }

    func exportAccount() async throws -> AccountExport {
        throw APIClientError.unsupportedOperation
    }

    func deleteAccount() async throws {
        throw APIClientError.unsupportedOperation
    }

    func createOrganizerFamily(
        organizerName: String,
        familyName: String
    ) async throws -> AuthSession {
        throw APIClientError.unsupportedOperation
    }

    func addManagedFamilyMember(
        displayName: String
    ) async throws -> UserProfile {
        throw APIClientError.unsupportedOperation
    }

    func createFamilyPairing(
        memberID: String
    ) async throws -> FamilyPairing {
        throw APIClientError.unsupportedOperation
    }

    func previewFamilyPairing(
        _ credential: FamilyPairingCredential
    ) async throws -> FamilyPairingPreview {
        throw APIClientError.unsupportedOperation
    }

    func activateFamilyPairing(
        _ credential: FamilyPairingCredential
    ) async throws -> AuthSession {
        throw APIClientError.unsupportedOperation
    }

    func fetchFamilyPairings() async throws -> [FamilyPairingPreview] {
        throw APIClientError.unsupportedOperation
    }

    func revokeFamilyPairing(pairingID: String) async throws {
        throw APIClientError.unsupportedOperation
    }

    func previewFamilyPairing(code: String) async throws -> FamilyPairingPreview {
        try await previewFamilyPairing(.code(code))
    }

    func previewFamilyPairing(token: String) async throws -> FamilyPairingPreview {
        try await previewFamilyPairing(.token(token))
    }

    func activateFamilyPairing(code: String) async throws -> AuthSession {
        try await activateFamilyPairing(.code(code))
    }

    func activateFamilyPairing(token: String) async throws -> AuthSession {
        try await activateFamilyPairing(.token(token))
    }
}

enum APIClientError: Error {
    case missingConfiguration(String)
    case invalidBaseURL
    case invalidRequest
    case invalidResponse
    case unsupportedOperation
    case unauthorized
    case server(statusCode: Int, payload: APIErrorPayload?)
    case decoding(Error)
    case transport(Error)
}

extension APIClientError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingConfiguration(let key):
            return "アプリの設定（\(key)）を確認できませんでした。"
        case .invalidBaseURL:
            return "サーバーの接続先が正しくありません。"
        case .invalidRequest:
            return "通信を開始できませんでした。"
        case .invalidResponse:
            return "サーバーから正しい応答を受け取れませんでした。"
        case .unsupportedOperation:
            return "この操作は現在利用できません。"
        case .unauthorized:
            return "セッションの有効期限が切れました。もう一度ログインしてください。"
        case .server(_, let payload):
            switch payload?.code {
            case "auth_provider_unavailable":
                return "現在この認証方法は利用できません。しばらくしてからもう一度お試しください。"
            case "invalid_email":
                return "メールアドレスを確認してください。"
            case "email_already_in_use":
                return "このメールアドレスは別のアカウントで使われています。"
            case "email_already_enrolled":
                return "このメールアドレスは登録済みです。"
            case "email_delivery_failed":
                return "確認メールを送れませんでした。少し待ってから、もう一度お試しください。"
            case "invalid_phone":
                return "電話番号を確認してください。"
            case "invalid_otp":
                return "認証コードが正しくありません。"
            case "account_not_found":
                return "登録済みのアカウントが見つかりません。入力した情報を確認してください。"
            case "phone_already_in_use":
                return "この電話番号は別のアカウントで使われています。"
            case "phone_enrollment_required":
                return "先に電話番号を登録してください。"
            case "invalid_recovery_code", "recovery_state_changed":
                return "復旧コードが正しくないか、有効期限が切れています。"
            case "rate_limited":
                return "試行回数が多すぎます。時間をおいてからもう一度お試しください。"
            case "invalid_pairing",
                 "invalid_pairing_credential",
                 "invalid_pairing_code",
                 "invalid_pairing_token":
                return "招待番号または招待リンクを確認してください。"
            case "pairing_expired":
                return "この招待の有効期限が切れています。ご家族に新しい設定番号を送ってもらってください。"
            case "pairing_unavailable",
                 "pairing_not_found",
                 "pairing_revoked",
                 "pairing_consumed",
                 "pairing_already_used",
                 "pairing_state_changed":
                return "この招待は利用できません。ご家族に新しい設定番号を送ってもらってください。"
            case "family_owner_required", "family_manager_required":
                return "この操作は家族を設定した人だけが行えます。"
            case "managed_member_not_found":
                return "招待する家族を確認してください。"
            case "family_owner_transfer_required",
                 "ownership_transfer_required":
                return "先に家族を管理する方を変更してください。"
            case "last_owner_cannot_leave":
                return "最後の管理者は家族から退出できません。アカウント削除をご利用ください。"
            case "cannot_remove_family_owner",
                 "owner_cannot_be_removed",
                 "owner_cannot_remove_self":
                return "家族を管理する方は削除できません。"
            case "managed_member_required":
                return "名前を変更できるのは、この端末で管理している家族だけです。"
            case "managed_member_cannot_own_family":
                return "端末で管理している家族には管理者を引き継げません。"
            case "owner_device_setup_required",
                 "unauthenticated_member_cannot_own_family":
                return "新しい管理者のiPhone設定を先に完了してください。"
            case "owner_recovery_required":
                return "新しい管理者の端末で、電話番号を登録するか復旧コードを保存してから引き継いでください。"
            case "answer_not_found":
                return "回答が見つかりません。"
            case "answer_immutable":
                return "送った回答は変更できません。続きはコメントで伝えられます。"
            case "question_changed":
                return "質問が新しくなりました。ホームに戻って、今日の質問を確認してください。入力した内容は残っています。"
            case "question_not_published":
                return "今日の質問は、表示されている時刻に届きます。"
            case "not_found", "endpoint_not_found":
                return "この機能の準備がまだ完了していません。時間をおいてお試しください。"
            case "comment_not_found":
                return "コメントが見つかりません。"
            case "comment_already_reported":
                return "このコメントはすでに報告済みです。"
            case "self_report_not_allowed":
                return "自分のコメントは報告できません。"
            case "invalid_notification_preferences":
                return "通知設定の内容を確認してください。"
            case "self_like_not_allowed":
                return "自分の回答にはいいねできません。"
            default:
                return payload?.message ?? "サーバーで処理を完了できませんでした。"
            }
        case .decoding:
            return "サーバーからの応答を読み取れませんでした。"
        case .transport(let error):
            if (error as? URLError)?.code == .notConnectedToInternet {
                return "インターネットにつながっていません。接続を確認してください。"
            }
            return "通信できませんでした。もう一度お試しください。"
        }
    }
}

actor DefaultAppAPI: AppAPI {
    private static let mutationDefaultsPrefix = "tsutsuura.idempotency.v2."
    private static let legacyMutationDefaultsPrefix =
        "tsutsuura.idempotency.v1."
    private static let boundedMutationRetention: TimeInterval = 30 * 24 * 60 * 60
    // Lifecycle leave/delete tombstones are intentionally absent: they remain
    // durable until the client can reconcile the committed server receipt.
    private static let boundedMutationOperations: Set<String> = [
        "email.otp.verify",
        "email.enrollment.verify",
        "otp.verify",
        "phone.enrollment.verify",
        "family.create",
        "managed-member.create",
        "account.recovery",
        "pairing.activate",
        "comment.create",
        "comment.reply",
    ]

    private struct PersistedMutationRecord: Codable, Sendable {
        let value: String
        let authorizationFingerprint: String?
        let createdAt: Date?
    }

    private struct PersistentMutationKey: Sendable {
        let value: String
        let storageKey: String
        let authorizationFingerprint: String?
        let createdAt: Date?

        func matchesAuthorization(_ current: String?) -> Bool {
            guard let current else { return true }
            return authorizationFingerprint == current
        }
    }

    private enum MutationRecordProtectionError: Error, LocalizedError {
        case invalidRecord
        case encryptionFailed

        var errorDescription: String? {
            "再試行情報を安全に読み書きできませんでした。端末を再起動してもう一度お試しください。"
        }
    }

    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let tokenStore: any TokenStoring
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let retryPolicy: APIRequestRetryPolicy
    private let now: @Sendable () -> Date
    private let idempotencyDefaults: UserDefaults
    private let mutationProtectionKeyResult:
        Result<Data, MutationProtectionKeyError>

    init(
        configuration: APIConfiguration,
        transport: any HTTPTransport = URLSessionTransport(),
        tokenStore: any TokenStoring = KeychainTokenStore(),
        retryPolicy: APIRequestRetryPolicy = .standard,
        idempotencyDefaults: UserDefaults = .standard,
        mutationProtectionKey: Data? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.transport = transport
        self.tokenStore = tokenStore
        self.retryPolicy = retryPolicy
        self.idempotencyDefaults = idempotencyDefaults
        if let mutationProtectionKey {
            self.mutationProtectionKeyResult =
                mutationProtectionKey.count
                    == KeychainMutationProtectionKey.byteCount
                    ? .success(mutationProtectionKey)
                    : .failure(.invalidKeyData)
        } else {
            do {
                self.mutationProtectionKeyResult = .success(
                    try KeychainMutationProtectionKey.loadOrCreate()
                )
            } catch let error as MutationProtectionKeyError {
                self.mutationProtectionKeyResult = .failure(error)
            } catch {
                self.mutationProtectionKeyResult = .failure(
                    .invalidKeyData
                )
            }
        }
        self.now = now
        encoder = Self.makeEncoder()
        decoder = Self.makeDecoder()
    }

    func hasStoredSession() async throws -> Bool {
        try await reconcilePendingLifecycleMutations()
        return try await tokenStore.readToken()?.isEmpty == false
    }

    func requestEmailOTP(email: String) async throws -> OTPChallenge {
        guard let email = EmailAddressValidation.normalized(
            email
        ) else {
            throw TextInputValidationError.invalidEmailAddress
        }
        let endpoint = Endpoint<OTPChallenge>(
            method: .post,
            path: ["v1", "auth", "email", "request"],
            body: RequestEmailCodeBody(email: email),
            requiresAuthorization: false
        )
        return try await send(endpoint)
    }

    func verifyEmailOTP(requestID: String, code: String) async throws -> AuthSession {
        let mutation = try persistentMutationKey(
            operation: "email.otp.verify",
            fingerprint: requestID + "\u{0}" + code
        )
        do {
            let session: AuthSession = try await send(Endpoint(
                method: .post,
                path: ["v1", "auth", "email", "verify"],
                body: VerifyEmailCodeBody(requestID: requestID, code: code),
                requiresAuthorization: false,
                idempotencyKey: mutation.value,
                isSafelyRetryable: true
            ))
            try await tokenStore.writeToken(session.accessToken)
            clearPersistentMutationKey(mutation)
            return session
        } catch {
            clearPersistentMutationKeyIfDefinitive(mutation, after: error)
            throw error
        }
    }

    func requestEmailEnrollment(
        email: String
    ) async throws -> OTPChallenge {
        guard let email = EmailAddressValidation.normalized(
            email
        ) else {
            throw TextInputValidationError.invalidEmailAddress
        }
        return try await send(
            Endpoint<OTPChallenge>(
                method: .post,
                path: ["v1", "me", "email", "request"],
                body: RequestEmailCodeBody(email: email)
            )
        )
    }

    func verifyEmailEnrollment(
        requestID: String,
        code: String
    ) async throws -> UserProfile {
        let token = try await tokenStore.readToken()
        let actorFingerprint = token.map(Self.authorizationFingerprint) ?? ""
        let mutation = try persistentMutationKey(
            operation: "email.enrollment.verify",
            fingerprint: actorFingerprint + "\u{0}" + requestID + "\u{0}" + code,
            authorizationToken: token
        )
        do {
            let response: UserProfileResponse = try await send(Endpoint(
                method: .post,
                path: ["v1", "me", "email", "verify"],
                body: VerifyEmailCodeBody(
                    requestID: requestID,
                    code: code
                ),
                idempotencyKey: mutation.value,
                isSafelyRetryable: true
            ))
            clearPersistentMutationKey(mutation)
            return response.user
        } catch {
            clearPersistentMutationKeyIfDefinitive(mutation, after: error)
            throw error
        }
    }

    func requestOTP(phoneNumber: String) async throws -> OTPChallenge {
        guard let phoneNumber = PhoneNumberValidation.canonicalE164(
            phoneNumber
        ) else {
            throw TextInputValidationError.invalidPhoneNumber
        }
        let endpoint = Endpoint<OTPChallenge>(
            method: .post,
            path: ["v1", "auth", "phone", "request"],
            body: RequestOTPBody(phone: phoneNumber),
            requiresAuthorization: false
        )
        return try await send(endpoint)
    }

    func verifyOTP(requestID: String, code: String) async throws -> AuthSession {
        let mutation = try persistentMutationKey(
            operation: "otp.verify",
            fingerprint: requestID + "\u{0}" + code
        )
        do {
            let session: AuthSession = try await send(Endpoint(
                method: .post,
                path: ["v1", "auth", "phone", "verify"],
                body: VerifyOTPBody(requestID: requestID, code: code),
                requiresAuthorization: false,
                idempotencyKey: mutation.value,
                isSafelyRetryable: true
            ))
            try await tokenStore.writeToken(session.accessToken)
            clearPersistentMutationKey(mutation)
            return session
        } catch {
            clearPersistentMutationKeyIfDefinitive(mutation, after: error)
            throw error
        }
    }

    func requestPhoneEnrollment(
        phoneNumber: String
    ) async throws -> OTPChallenge {
        guard let phoneNumber = PhoneNumberValidation.canonicalE164(
            phoneNumber
        ) else {
            throw TextInputValidationError.invalidPhoneNumber
        }
        return try await send(
            Endpoint<OTPChallenge>(
                method: .post,
                path: ["v1", "me", "phone", "request"],
                body: RequestPhoneEnrollmentBody(phone: phoneNumber)
            )
        )
    }

    func verifyPhoneEnrollment(
        requestID: String,
        code: String
    ) async throws -> UserProfile {
        let token = try await tokenStore.readToken()
        let actorFingerprint = token.map(Self.authorizationFingerprint) ?? ""
        let mutation = try persistentMutationKey(
            operation: "phone.enrollment.verify",
            fingerprint: actorFingerprint + "\u{0}" + requestID + "\u{0}" + code,
            authorizationToken: token
        )
        do {
            let response: UserProfileResponse = try await send(Endpoint(
                method: .post,
                path: ["v1", "me", "phone", "verify"],
                body: VerifyPhoneEnrollmentBody(
                    requestID: requestID,
                    code: code
                ),
                idempotencyKey: mutation.value,
                isSafelyRetryable: true
            ))
            clearPersistentMutationKey(mutation)
            return response.user
        } catch {
            clearPersistentMutationKeyIfDefinitive(mutation, after: error)
            throw error
        }
    }

    func createAccountRecoveryCode() async throws -> AccountRecoveryCode {
        try await send(
            Endpoint(
                method: .post,
                path: ["v1", "me", "recovery-codes"]
            )
        )
    }

    func recoverAccount(code: String) async throws -> AuthSession {
        let code = RecoveryCodeValidation.normalized(code)
        guard RecoveryCodeValidation.isValid(code) else {
            throw TextInputValidationError.invalidRecoveryCode
        }
        let mutation = try persistentMutationKey(
            operation: "account.recovery",
            fingerprint: code
        )
        do {
            let session: AuthSession = try await send(Endpoint(
                method: .post,
                path: ["v1", "auth", "recovery", "verify"],
                body: VerifyAccountRecoveryBody(code: code),
                requiresAuthorization: false,
                idempotencyKey: mutation.value,
                isSafelyRetryable: true
            ))
            try await tokenStore.writeToken(session.accessToken)
            clearPersistentMutationKey(mutation)
            return session
        } catch {
            clearPersistentMutationKeyIfDefinitive(mutation, after: error)
            throw error
        }
    }

    func fetchMe() async throws -> UserProfile {
        let response: UserProfileResponse = try await send(
            Endpoint(method: .get, path: ["v1", "me"])
        )
        return response.user
    }

    func updateProfile(displayName: String) async throws -> UserProfile {
        let response: UserProfileResponse = try await send(
            Endpoint(
                method: .patch,
                path: ["v1", "me"],
                body: UpdateProfileBody(displayName: displayName)
            )
        )
        return response.user
    }

    func updatePersonalMark(_ mark: String?) async throws -> UserProfile {
        struct MarkBody: Encodable {
            let avatarMark: String?
            enum CodingKeys: String, CodingKey { case avatarMark }
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                if let avatarMark { try container.encode(avatarMark, forKey: .avatarMark) }
                else { try container.encodeNil(forKey: .avatarMark) }
            }
        }
        let response: UserProfileResponse = try await send(Endpoint(
            method: .patch, path: ["v1", "me"], body: MarkBody(avatarMark: mark)
        ))
        return response.user
    }

    func fetchFamily() async throws -> FamilySummary {
        let response: FamilyResponse = try await send(
            Endpoint(method: .get, path: ["v1", "family"])
        )
        return response.family
    }

    func renameFamily(name: String) async throws -> FamilySummary {
        let _: EmptyResponse = try await send(
            Endpoint(
                method: .patch,
                path: ["v1", "family"],
                body: RenameFamilyBody(name: name)
            )
        )
        return try await fetchFamily()
    }

    func createOrganizerFamily(
        organizerName: String,
        familyName: String
    ) async throws -> AuthSession {
        let mutation = try persistentMutationKey(
            operation: "family.create",
            fingerprint: organizerName + "\u{0}" + familyName
        )
        do {
            let session: AuthSession = try await send(Endpoint(
                method: .post,
                path: ["v1", "setup", "family"],
                body: CreateOrganizerFamilyBody(
                    organizerName: organizerName,
                    familyName: familyName
                ),
                requiresAuthorization: false,
                idempotencyKey: mutation.value,
                isSafelyRetryable: true
            ))
            try await tokenStore.writeToken(session.accessToken)
            clearPersistentMutationKey(mutation)
            return session
        } catch {
            clearPersistentMutationKeyIfDefinitive(mutation, after: error)
            throw error
        }
    }

    func addManagedFamilyMember(
        displayName: String
    ) async throws -> UserProfile {
        let token = try await tokenStore.readToken()
        let actorFingerprint = token.map(Self.authorizationFingerprint) ?? ""
        let mutation = try persistentMutationKey(
            operation: "managed-member.create",
            fingerprint: actorFingerprint + "\u{0}" + displayName,
            authorizationToken: token
        )
        do {
            let response: ManagedFamilyMemberResponse = try await send(Endpoint(
                method: .post,
                path: ["v1", "family", "managed-members"],
                body: AddManagedFamilyMemberBody(displayName: displayName),
                idempotencyKey: mutation.value,
                isSafelyRetryable: true
            ))
            clearPersistentMutationKey(mutation)
            return response.member
        } catch {
            clearPersistentMutationKeyIfDefinitive(mutation, after: error)
            throw error
        }
    }

    func renameManagedFamilyMember(
        memberID: String,
        displayName: String
    ) async throws -> UserProfile {
        let response: ManagedFamilyMemberResponse = try await send(
            Endpoint(
                method: .patch,
                path: ["v1", "family", "members", memberID],
                body: RenameManagedFamilyMemberBody(
                    displayName: displayName
                )
            )
        )
        return response.member
    }

    func removeManagedFamilyMember(memberID: String) async throws {
        // Establish that the target was visible before issuing the destructive
        // request. A DELETE whose committed response is lost is retried by the
        // transport and correctly receives 404; only an authoritative family
        // refresh proving that this previously-visible member is now absent
        // may reconcile that 404 as success.
        let memberWasPresent = try await fetchFamily().members.contains {
            $0.id == memberID
        }
        let endpoint = Endpoint<EmptyResponse>(
            method: .delete,
            path: ["v1", "family", "members", memberID]
        )
        do {
            _ = try await send(endpoint)
        } catch {
            let deletionError = error
            guard Self.isNotFound(deletionError), memberWasPresent else {
                throw deletionError
            }
            let memberIsAbsent: Bool
            do {
                let refreshedFamily = try await fetchFamily()
                memberIsAbsent = !refreshedFamily.members.contains {
                    $0.id == memberID
                }
            } catch {
                throw deletionError
            }
            guard memberIsAbsent else { throw deletionError }
        }
    }

    func transferFamilyOwnership(
        to memberID: String
    ) async throws -> FamilySummary {
        // Do not begin a consequential ownership mutation unless we have an
        // authoritative snapshot to reconcile against. If both this preflight
        // and the post-commit GET were allowed to fail, a committed handoff
        // could be reported as a failure with no safe local fallback.
        let previousFamily = try await fetchFamily()
        let _: EmptyResponse = try await send(
            Endpoint(
                method: .post,
                path: ["v1", "family", "ownership"],
                body: TransferFamilyOwnershipBody(memberID: memberID),
                isSafelyRetryable: true
            )
        )
        do {
            return try await fetchFamily()
        } catch {
            // The ownership endpoint returned 2xx, so a follow-up GET outage
            // must not turn a committed handoff into a reported failure. Use
            // the preflight family as a temporary authoritative-enough cache;
            // the next normal refresh will reconcile all server fields.
            guard previousFamily.members.contains(where: {
                $0.id == memberID
            }) else {
                throw error
            }
            var fallback = previousFamily
            for index in fallback.members.indices {
                fallback.members[index].familyRole =
                    fallback.members[index].id == memberID ? .owner : .member
                if fallback.members[index].id == memberID {
                    fallback.members[index].managed = false
                }
            }
            return fallback
        }
    }

    func leaveFamily() async throws -> FamilyLeaveResult {
        let token = try await tokenStore.readToken()
        let authorizationFingerprint = token.map(Self.authorizationFingerprint)
        if let pending = try pendingPersistentMutationKeys(
            operation: "family.leave"
        ).first(where: {
            $0.matchesAuthorization(authorizationFingerprint)
        }) {
            return try await performFamilyLeave(pending)
        }

        // Bind the durable key to the family visible when the user confirmed
        // this operation. The server retains the resulting receipt, allowing
        // the exact response to be recovered even after a process death or a
        // managed account's bearer has been deleted by the committed leave.
        let previousFamilyID = try await fetchFamily().id
        let mutation = try persistentMutationKey(
            operation: "family.leave",
            fingerprint: previousFamilyID,
            authorizationToken: token
        )
        return try await performFamilyLeave(mutation)
    }

    func createFamilyPairing(
        memberID: String
    ) async throws -> FamilyPairing {
        let response: FamilyPairingResponse = try await send(
            Endpoint(
                method: .post,
                path: [
                    "v1",
                    "family",
                    "managed-members",
                    memberID,
                    "pairings"
                ]
            )
        )
        return response.pairing
    }

    func previewFamilyPairing(
        _ credential: FamilyPairingCredential
    ) async throws -> FamilyPairingPreview {
        let fingerprint = Self.pairingCredentialFingerprint(credential)
        let exactActivation = try existingPersistentMutationKey(
            operation: "pairing.activate",
            fingerprint: fingerprint
        )
        let pendingActivation = try exactActivation
            ?? solePendingPairingActivationKey()
        let response: FamilyPairingPreviewResponse = try await send(
            Endpoint(
                method: .post,
                path: ["v1", "setup", "pairings", "preview"],
                body: credential.requestBody,
                requiresAuthorization: false,
                idempotencyKey: pendingActivation?.value
            )
        )
        switch response.pairing.status {
        case .pending:
            // A pending invite ignores an unrelated candidate key. Remember
            // that activation below always keys the exact representation;
            // abandoning the preview leaves no durable key behind.
            break
        case .consumed:
            // The server returns a consumed preview only when the supplied
            // key belongs to this exact pairing. Move the durable record to
            // the credential representation the user just entered so a
            // code↔token switch survives another process death.
            if exactActivation == nil, let pendingActivation {
                _ = try relocatePersistentMutationKey(
                    pendingActivation,
                    operation: "pairing.activate",
                    fingerprint: fingerprint
                )
            }
        case .revoked, .expired:
            break
        }
        return response.pairing
    }

    func activateFamilyPairing(
        _ credential: FamilyPairingCredential
    ) async throws -> AuthSession {
        let fingerprint = Self.pairingCredentialFingerprint(credential)
        let mutation = try persistentMutationKey(
            operation: "pairing.activate",
            fingerprint: fingerprint
        )
        do {
            let session: AuthSession = try await send(Endpoint(
                method: .post,
                path: ["v1", "setup", "pairings", "activate"],
                body: credential.requestBody,
                requiresAuthorization: false,
                idempotencyKey: mutation.value,
                isSafelyRetryable: true
            ))
            try await tokenStore.writeToken(session.accessToken)
            clearPersistentMutationKey(mutation)
            return session
        } catch {
            clearPersistentMutationKeyIfDefinitive(mutation, after: error)
            throw error
        }
    }

    func fetchFamilyPairings() async throws -> [FamilyPairingPreview] {
        let response: FamilyPairingListResponse = try await send(
            Endpoint(method: .get, path: ["v1", "family", "pairings"])
        )
        return response.items
    }

    func revokeFamilyPairing(pairingID: String) async throws {
        let endpoint = Endpoint<EmptyResponse>(
            method: .delete,
            path: ["v1", "family", "pairings", pairingID]
        )
        _ = try await send(endpoint)
    }

    func fetchHome(cursor: String? = nil) async throws -> HomeFeed {
        try await send(
            Endpoint(
                method: .get,
                path: ["v1", "home"],
                query: cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? []
            )
        )
    }

    func fetchTodayQuestion() async throws -> Question {
        let response: TodayQuestionResponse = try await send(
            Endpoint(method: .get, path: ["v1", "questions", "today"])
        )
        var question = response.question
        question.answer = response.answer
        return question
    }

    func fetchAnswer(answerID: String) async throws -> Answer {
        let response: SubmittedAnswerResponse = try await send(
            Endpoint(method: .get, path: ["v1", "answers", answerID])
        )
        return response.answer
    }

    func submitAnswer(questionID: String, body: String) async throws -> Answer {
        try await submitAnswer(
            questionID: questionID,
            submission: AnswerSubmission(body: body)
        )
    }

    func submitAnswer(
        questionID: String,
        submission: AnswerSubmission
    ) async throws -> Answer {
        try await submitAnswer(questionID: questionID, questionDate: nil, submission: submission)
    }

    func submitAnswer(
        questionID: String, questionDate: String?, submission: AnswerSubmission
    ) async throws -> Answer {
        try submission.validate()

        let endpoint: Endpoint<SubmittedAnswerResponse>
        if submission.hasMedia {
            endpoint = Endpoint(
                // PHP populates its native upload structures for multipart
                // POST requests, not multipart PUT requests.
                method: .post,
                path: ["v1", "questions", "today", "answer"],
                multipartBody: try MultipartFormData(submission: submission, questionID: questionID, questionDate: questionDate)
            )
        } else {
            endpoint = Endpoint(
                method: .put,
                path: ["v1", "questions", "today", "answer"],
                body: SubmitAnswerBody(body: submission.body, questionId: questionID, questionDate: questionDate)
            )
        }

        let response: SubmittedAnswerResponse = try await send(
            endpoint
        )
        return response.answer
    }

    func updateAnswer(
        answerID: String,
        submission: AnswerSubmission
    ) async throws -> Answer {
        guard !submission.hasMedia else {
            throw APIClientError.unsupportedOperation
        }
        guard UnicodeTextValidation.characterCount(
            submission.body.trimmingCharacters(in: .whitespacesAndNewlines)
        ) <= AnswerDraft.maximumBodyCharacterCount else {
            throw AnswerMediaValidationError.answerTooLong(
                maximum: AnswerDraft.maximumBodyCharacterCount
            )
        }
        let endpoint = Endpoint<SubmittedAnswerResponse>(
            method: .patch,
            path: ["v1", "answers", answerID],
            body: UpdateAnswerBody(body: submission.body)
        )
        let response: SubmittedAnswerResponse = try await send(endpoint)
        return response.answer
    }

    func deleteAnswer(answerID: String) async throws {
        // GET is family-visible, so this preflight proves the exact target
        // existed without assuming that the caller owns it. If ownership is
        // denied with the server's intentionally opaque 404, the postflight
        // still sees the answer and the original error is preserved.
        _ = try await fetchAnswer(answerID: answerID)
        let endpoint = Endpoint<EmptyResponse>(
            method: .delete,
            path: ["v1", "answers", answerID]
        )
        do {
            _ = try await send(endpoint)
        } catch {
            let deletionError = error
            guard Self.isNotFound(deletionError) else {
                throw deletionError
            }
            let answerIsAbsent: Bool
            do {
                answerIsAbsent = try await isAnswerAbsent(answerID: answerID)
            } catch {
                throw deletionError
            }
            guard answerIsAbsent else { throw deletionError }
        }
    }

    func deleteAnswerMedia(
        answerID: String,
        mediaID: String
    ) async throws -> Answer {
        let answerBeforeDelete = try await fetchAnswer(answerID: answerID)
        let mediaWasPresent = answerBeforeDelete.media.contains {
            $0.id == mediaID
        }
        do {
            let response: SubmittedAnswerResponse = try await send(
                Endpoint(
                    method: .delete,
                    path: ["v1", "answers", answerID, "media", mediaID]
                )
            )
            return response.answer
        } catch {
            let deletionError = error
            guard Self.isNotFound(deletionError), mediaWasPresent else {
                throw deletionError
            }
            // Unlike the void DELETE operations, media deletion must hand the
            // store an authoritative Answer. If the answer cannot be fetched,
            // or the media is still present, retain the original failure.
            let refreshedAnswer: Answer
            do {
                refreshedAnswer = try await fetchAnswer(answerID: answerID)
            } catch {
                throw deletionError
            }
            guard !refreshedAnswer.media.contains(where: {
                $0.id == mediaID
            }) else {
                throw deletionError
            }
            return refreshedAnswer
        }
    }

    func fetchAnswerMedia(
        _ media: AnswerMedia
    ) async throws -> AnswerMediaContent {
        guard isTrustedMediaURL(media.url) else {
            throw APIClientError.invalidRequest
        }
        guard let token = try await tokenStore.readToken(),
              !token.isEmpty else {
            throw APIClientError.unauthorized
        }

        var request = URLRequest(url: media.url)
        request.httpMethod = HTTPMethod.get.rawValue
        request.timeoutInterval = 60
        request.setValue(media.mimeType, forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performTransport(
            request,
            method: .get,
            isMultipart: false,
            isSafelyRetryable: false
        )

        guard (200..<300).contains(response.statusCode) else {
            let payload =
                (try? decoder.decode(APIErrorEnvelope.self, from: data).error)
                ?? (try? decoder.decode(APIErrorPayload.self, from: data))
            if response.statusCode == 401 {
                if let authorization = request.value(forHTTPHeaderField: "Authorization"),
                   authorization.hasPrefix("Bearer ") {
                    try? await tokenStore.clearToken(ifMatching: String(authorization.dropFirst(7)))
                }
                throw APIClientError.unauthorized
            }
            throw APIClientError.server(
                statusCode: response.statusCode,
                payload: payload
            )
        }

        let contentType = response.value(
            forHTTPHeaderField: "Content-Type"
        )?.split(separator: ";", maxSplits: 1).first.map(String.init)
        return AnswerMediaContent(
            data: data,
            mimeType: contentType ?? media.mimeType
        )
    }

    func fetchAnswerHistory(cursor: String? = nil) async throws -> AnswerPage {
        try await send(
            Endpoint(
                method: .get,
                path: ["v1", "history"],
                query: cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? []
            )
        )
    }

    func fetchAnswerHistory(
        query: HistoryQuery,
        cursor: String? = nil
    ) async throws -> AnswerPage {
        var queryItems = [
            URLQueryItem(name: "scope", value: query.scope.rawValue),
            URLQueryItem(
                name: "limit",
                value: String(HistoryQuery.normalizedLimit(query.limit))
            ),
        ]
        if let cursor, !cursor.isEmpty {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        if let authorID = query.authorID {
            queryItems.append(URLQueryItem(name: "authorId", value: authorID))
        }
        if let startDate = query.startDate {
            queryItems.append(URLQueryItem(name: "from", value: startDate))
        }
        if let endDate = query.endDate {
            queryItems.append(URLQueryItem(name: "to", value: endDate))
        }
        let searchText = HistoryQuery.normalizedSearchText(query.searchText)
        if !searchText.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: searchText))
        }
        return try await send(
            Endpoint(
                method: .get,
                path: ["v1", "history"],
                query: queryItems
            )
        )
    }

    func setLike(answerID: String, isLiked: Bool) async throws -> LikeState {
        try await send(Endpoint(
            method: isLiked ? .put : .delete,
            path: ["v1", "answers", answerID, "like"]
        ))
    }

    func fetchComments(
        answerID: String,
        cursor: String? = nil
    ) async throws -> CommentPage {
        try await send(
            Endpoint(
                method: .get,
                path: ["v1", "answers", answerID, "comments"],
                query: cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? []
            )
        )
    }

    func createComment(answerID: String, body: String) async throws -> Comment {
        let body = try CommentTextValidation.body(body)
        let token = try await tokenStore.readToken()
        let actorFingerprint = token.map(Self.authorizationFingerprint) ?? ""
        let mutation = try persistentMutationKey(
            operation: "comment.create",
            fingerprint: actorFingerprint + "\u{0}" + answerID + "\u{0}" + body,
            authorizationToken: token
        )
        do {
            let response: CreatedCommentResponse = try await send(Endpoint(
                method: .post,
                path: ["v1", "answers", answerID, "comments"],
                body: CreateCommentBody(body: body),
                idempotencyKey: mutation.value,
                isSafelyRetryable: true
            ))
            clearPersistentMutationKey(mutation)
            return response.comment
        } catch {
            clearPersistentMutationKeyIfDefinitive(mutation, after: error)
            throw error
        }
    }

    func replyToComment(
        answerID: String,
        parentCommentID: String,
        body: String
    ) async throws -> Comment {
        let body = try CommentTextValidation.body(body)
        let token = try await tokenStore.readToken()
        let actorFingerprint = token.map(Self.authorizationFingerprint) ?? ""
        let mutation = try persistentMutationKey(
            operation: "comment.reply",
            fingerprint: actorFingerprint + "\u{0}" + answerID + "\u{0}"
                + parentCommentID + "\u{0}" + body,
            authorizationToken: token
        )
        do {
            let response: CreatedCommentResponse = try await send(Endpoint(
                method: .post,
                path: ["v1", "answers", answerID, "comments"],
                body: CreateCommentBody(
                    body: body,
                    parentCommentID: parentCommentID
                ),
                idempotencyKey: mutation.value,
                isSafelyRetryable: true
            ))
            clearPersistentMutationKey(mutation)
            return response.comment
        } catch {
            clearPersistentMutationKeyIfDefinitive(mutation, after: error)
            throw error
        }
    }

    func updateComment(
        commentID: String,
        body: String
    ) async throws -> Comment {
        let body = try CommentTextValidation.body(body)
        let response: CreatedCommentResponse = try await send(
            Endpoint(
                method: .patch,
                path: ["v1", "comments", commentID],
                body: UpdateCommentBody(body: body)
            )
        )
        return response.comment
    }

    func deleteComment(commentID: String, answerID: String) async throws {
        // Comments have no standalone read endpoint. Walk the answer's cursor
        // pages before and after DELETE so an opaque 404 is reconciled only
        // for a comment that was visible and is now authoritatively absent.
        let commentWasPresent = try await containsComment(
            commentID: commentID,
            answerID: answerID
        )
        let endpoint = Endpoint<EmptyResponse>(
            method: .delete,
            path: ["v1", "comments", commentID]
        )
        do {
            _ = try await send(endpoint)
        } catch {
            let deletionError = error
            guard Self.isNotFound(deletionError), commentWasPresent else {
                throw deletionError
            }
            let commentIsAbsent: Bool
            do {
                let refreshedContainsComment = try await containsComment(
                    commentID: commentID,
                    answerID: answerID
                )
                commentIsAbsent = !refreshedContainsComment
            } catch {
                throw deletionError
            }
            guard commentIsAbsent else { throw deletionError }
        }
    }

    func reportComment(
        commentID: String,
        reason: CommentReportReason,
        details: String?
    ) async throws -> CommentReport {
        let details = try CommentTextValidation.reportDetails(details)
        let response: CommentReportResponse = try await send(
            Endpoint(
                method: .post,
                path: ["v1", "comments", commentID, "reports"],
                body: ReportCommentBody(reason: reason, details: details)
            )
        )
        return response.report
    }

    func fetchContentSafety() async throws -> ContentSafetySnapshot {
        try await send(Endpoint(method: .get, path: ["v1", "me", "blocks"]))
    }

    func blockUser(userID: String) async throws {
        let _: EmptyResponse = try await send(Endpoint(method: .put, path: ["v1", "me", "blocks", userID]))
    }

    func unblockUser(userID: String) async throws {
        let _: EmptyResponse = try await send(Endpoint(method: .delete, path: ["v1", "me", "blocks", userID]))
    }

    func reportAnswer(answerID: String, reason: CommentReportReason, details: String?) async throws -> AnswerReport {
        struct Response: Decodable, Sendable { let report: AnswerReport }
        let response: Response = try await send(Endpoint(method: .post, path: ["v1", "answers", answerID, "reports"], body: ReportCommentBody(reason: reason, details: try CommentTextValidation.reportDetails(details))))
        return response.report
    }

    func fetchNotificationPreferences() async throws -> NotificationPreferences {
        let response: NotificationPreferencesResponse = try await send(
            Endpoint(
                method: .get,
                path: ["v1", "me", "notification-preferences"]
            )
        )
        return response.preferences
    }

    func updateDeviceTimeZone(_ identifier: String) async throws {
        let _: NotificationPreferencesResponse = try await send(
            Endpoint(
                method: .patch,
                path: ["v1", "me", "timezone"],
                body: DeviceTimeZoneBody(timeZoneIdentifier: identifier)
            )
        )
    }

    func updateNotificationPreferences(
        _ preferences: NotificationPreferences
    ) async throws -> NotificationPreferences {
        let response: NotificationPreferencesResponse = try await send(
            Endpoint(
                method: .patch,
                path: ["v1", "me", "notification-preferences"],
                body: preferences
            )
        )
        return response.preferences
    }

    func exportAccount() async throws -> AccountExport {
        let response: AccountExportResponse = try await send(
            Endpoint(method: .get, path: ["v1", "me", "export"])
        )
        return response.export
    }

    func deleteAccount() async throws {
        let token = try await tokenStore.readToken()
        let authorizationFingerprint = token.map(Self.authorizationFingerprint)
        if let pending = try pendingPersistentMutationKeys(
            operation: "account.delete"
        ).first(where: {
            $0.matchesAuthorization(authorizationFingerprint)
        }) {
            try await performAccountDeletion(pending)
            return
        }

        let profile = try await fetchMe()
        let mutation = try persistentMutationKey(
            operation: "account.delete",
            fingerprint: profile.id,
            authorizationToken: token
        )
        try await performAccountDeletion(mutation)
    }

    func registerPushToken(
        _ token: String,
        environment: PushEnvironment
    ) async throws {
        let endpoint = Endpoint<EmptyResponse>(
            method: .put,
            path: ["v1", "push-tokens"],
            body: RegisterPushTokenBody(token: token, environment: environment)
        )
        _ = try await send(endpoint)
    }

    func unregisterPushToken(tokenHash: String) async throws {
        let endpoint = Endpoint<EmptyResponse>(
            method: .delete,
            path: ["v1", "push-tokens", tokenHash]
        )
        _ = try await send(endpoint)
    }

    func signOut() async throws {
        guard let token = try await tokenStore.readToken(),
              !token.isEmpty else {
            try await tokenStore.clearToken()
            return
        }
        do {
            let endpoint = Endpoint<EmptyResponse>(
                method: .post,
                path: ["v1", "auth", "logout"]
            )
            let _: EmptyResponse = try await send(endpoint)
        } catch APIClientError.unauthorized {
            // The server has already rejected this bearer, so there is no
            // live remote session left for the client to revoke.
            try await tokenStore.clearToken()
            return
        }
        try await tokenStore.clearToken()
    }

    private func isAnswerAbsent(answerID: String) async throws -> Bool {
        do {
            _ = try await fetchAnswer(answerID: answerID)
            return false
        } catch {
            guard Self.isNotFound(error) else { throw error }
            return true
        }
    }

    private func containsComment(
        commentID: String,
        answerID: String
    ) async throws -> Bool {
        var cursor: String?
        var seenCursors: Set<String> = []

        while true {
            let page = try await fetchComments(
                answerID: answerID,
                cursor: cursor
            )
            if page.comments.contains(where: { $0.id == commentID }) {
                return true
            }
            guard let nextCursor = page.nextCursor else { return false }
            guard seenCursors.insert(nextCursor).inserted else {
                throw APIClientError.invalidResponse
            }
            cursor = nextCursor
        }
    }

    private static func isNotFound(_ error: Error) -> Bool {
        guard let apiError = error as? APIClientError else { return false }
        if case .server(let statusCode, _) = apiError {
            return statusCode == 404
        }
        return false
    }

    /// Recovers a lifecycle response before normal session restoration can
    /// discard the bearer for an account that the server already deleted.
    /// The lifecycle routes consult their durable receipt before requiring a
    /// bearer, so a committed operation can also be acknowledged when secure
    /// storage no longer contains a token.
    private func reconcilePendingLifecycleMutations() async throws {
        let token = try await tokenStore.readToken()
        let authorizationFingerprint = token.map(Self.authorizationFingerprint)

        for mutation in try pendingPersistentMutationKeys(
            operation: "account.delete"
        ) where mutation.matchesAuthorization(authorizationFingerprint) {
            try await performAccountDeletion(mutation)
            return
        }

        for mutation in try pendingPersistentMutationKeys(
            operation: "family.leave"
        ) where mutation.matchesAuthorization(authorizationFingerprint) {
            _ = try await performFamilyLeave(mutation)
        }
    }

    private func performFamilyLeave(
        _ mutation: PersistentMutationKey
    ) async throws -> FamilyLeaveResult {
        do {
            let result: FamilyLeaveResult = try await send(Endpoint(
                method: .post,
                path: ["v1", "family", "leave"],
                idempotencyKey: mutation.value,
                isSafelyRetryable: true,
                allowsMissingAuthorization: true
            ))
            if result.accountDeleted {
                try await tokenStore.clearToken()
            }
            clearPersistentMutationKey(mutation)
            return result
        } catch {
            clearPersistentMutationKeyIfDefinitive(mutation, after: error)
            throw error
        }
    }

    private func performAccountDeletion(
        _ mutation: PersistentMutationKey
    ) async throws {
        do {
            let _: EmptyResponse = try await send(Endpoint(
                method: .delete,
                path: ["v1", "me"],
                idempotencyKey: mutation.value,
                isSafelyRetryable: true,
                allowsMissingAuthorization: true
            ))
            try await tokenStore.clearToken()
            clearPersistentMutationKey(mutation)
        } catch {
            clearPersistentMutationKeyIfDefinitive(mutation, after: error)
            throw error
        }
    }

    private func persistentMutationKey(
        operation: String,
        fingerprint: String,
        authorizationToken: String? = nil
    ) throws -> PersistentMutationKey {
        try pruneExpiredBoundedMutationKeys()
        let storageKey = try protectedMutationStorageKey(
            operation: operation,
            fingerprint: fingerprint
        )
        if let existing = try persistentMutationKey(
            at: storageKey,
            allowsLegacyPlaintext: false
        ) {
            return existing
        }

        // Records written by pre-protection builds used an unkeyed digest and
        // plaintext JSON. Migrate only after the caller supplies the exact
        // original input, then immediately remove the offline-verifiable key.
        let legacyStorageKey = Self.legacyMutationStorageKey(
            operation: operation,
            fingerprint: fingerprint
        )
        if let legacy = try persistentMutationKey(
            at: legacyStorageKey,
            allowsLegacyPlaintext: true
        ) {
            return try relocatePersistentMutationKey(
                legacy,
                operation: operation,
                fingerprint: fingerprint
            )
        }

        let record = PersistedMutationRecord(
            value: UUID().uuidString.lowercased(),
            authorizationFingerprint: authorizationToken.map(
                Self.authorizationFingerprint
            ),
            createdAt: now()
        )
        try persistProtectedMutationRecord(record, at: storageKey)
        return PersistentMutationKey(
            value: record.value,
            storageKey: storageKey,
            authorizationFingerprint: record.authorizationFingerprint,
            createdAt: record.createdAt
        )
    }

    private func existingPersistentMutationKey(
        operation: String,
        fingerprint: String
    ) throws -> PersistentMutationKey? {
        try pruneExpiredBoundedMutationKeys()
        let storageKey = try protectedMutationStorageKey(
            operation: operation,
            fingerprint: fingerprint
        )
        if let existing = try persistentMutationKey(
            at: storageKey,
            allowsLegacyPlaintext: false
        ) {
            return existing
        }
        let legacyStorageKey = Self.legacyMutationStorageKey(
            operation: operation,
            fingerprint: fingerprint
        )
        guard let legacy = try persistentMutationKey(
            at: legacyStorageKey,
            allowsLegacyPlaintext: true
        ) else {
            return nil
        }
        return try relocatePersistentMutationKey(
            legacy,
            operation: operation,
            fingerprint: fingerprint
        )
    }

    private func persistentMutationKey(
        at storageKey: String,
        allowsLegacyPlaintext: Bool
    ) throws -> PersistentMutationKey? {
        guard let data = idempotencyDefaults.data(forKey: storageKey) else {
            return nil
        }
        let record = try decodePersistedMutationRecord(
            data,
            allowsLegacyPlaintext: allowsLegacyPlaintext
        )
        return PersistentMutationKey(
            value: record.value,
            storageKey: storageKey,
            authorizationFingerprint: record.authorizationFingerprint,
            createdAt: record.createdAt
        )
    }

    private func pendingPersistentMutationKeys(
        operation: String
    ) throws -> [PersistentMutationKey] {
        try pruneExpiredBoundedMutationKeys()
        let protectedPrefix = Self.mutationDefaultsPrefix + operation + "."
        let legacyPrefix =
            Self.legacyMutationDefaultsPrefix + operation + "."
        var mutations: [PersistentMutationKey] = []
        for storageKey in idempotencyDefaults.dictionaryRepresentation().keys
            .filter({
                $0.hasPrefix(protectedPrefix) || $0.hasPrefix(legacyPrefix)
            })
            .sorted() {
            guard let mutation = try persistentMutationKey(
                at: storageKey,
                allowsLegacyPlaintext: storageKey.hasPrefix(legacyPrefix)
            ) else {
                continue
            }
            mutations.append(mutation)
        }
        return mutations
    }

    private func pruneExpiredBoundedMutationKeys() throws {
        let operationPrefixes = Self.boundedMutationOperations.flatMap {
            [
                Self.mutationDefaultsPrefix + $0 + ".",
                Self.legacyMutationDefaultsPrefix + $0 + "."
            ]
        }
        for storageKey in idempotencyDefaults.dictionaryRepresentation().keys
        where operationPrefixes.contains(where: { storageKey.hasPrefix($0) }) {
            guard let data = idempotencyDefaults.data(forKey: storageKey) else {
                continue
            }
            let record = try decodePersistedMutationRecord(
                data,
                allowsLegacyPlaintext: storageKey.hasPrefix(
                    Self.legacyMutationDefaultsPrefix
                )
            )
            guard let createdAt = record.createdAt,
                  now().timeIntervalSince(createdAt)
                    < Self.boundedMutationRetention else {
                idempotencyDefaults.removeObject(forKey: storageKey)
                continue
            }
        }
    }

    /// A consumed invite can be represented by either its six-digit code or
    /// its universal-link token. The server validates both against the same
    /// pairing row, so when exactly one activation is awaiting a response it
    /// is safe to offer that key during preview of either representation. A
    /// different pending invite may ignore the candidate and preview normally;
    /// only a consumed response proves the association and triggers relocation.
    private func solePendingPairingActivationKey() throws -> PersistentMutationKey? {
        let pending = try pendingPersistentMutationKeys(
            operation: "pairing.activate"
        )
        return pending.count == 1 ? pending[0] : nil
    }

    private func relocatePersistentMutationKey(
        _ mutation: PersistentMutationKey,
        operation: String,
        fingerprint: String
    ) throws -> PersistentMutationKey {
        let storageKey = try protectedMutationStorageKey(
            operation: operation,
            fingerprint: fingerprint
        )
        guard storageKey != mutation.storageKey else { return mutation }
        let record = PersistedMutationRecord(
            value: mutation.value,
            authorizationFingerprint: mutation.authorizationFingerprint,
            createdAt: mutation.createdAt
        )
        try persistProtectedMutationRecord(record, at: storageKey)
        idempotencyDefaults.removeObject(forKey: mutation.storageKey)
        return PersistentMutationKey(
            value: mutation.value,
            storageKey: storageKey,
            authorizationFingerprint: mutation.authorizationFingerprint,
            createdAt: mutation.createdAt
        )
    }

    private func protectedMutationStorageKey(
        operation: String,
        fingerprint: String
    ) throws -> String {
        let authenticationKey = try derivedMutationProtectionKey(
            context: "storage-fingerprint"
        )
        let message = Data((operation + "\u{0}" + fingerprint).utf8)
        let digest = HMAC<SHA256>.authenticationCode(
            for: message,
            using: authenticationKey
        )
        return Self.mutationDefaultsPrefix + operation + "."
            + Data(digest).map { String(format: "%02x", $0) }.joined()
    }

    private static func legacyMutationStorageKey(
        operation: String,
        fingerprint: String
    ) -> String {
        legacyMutationDefaultsPrefix + operation + "."
            + sha256Hex(operation + "\u{0}" + fingerprint)
    }

    private func persistProtectedMutationRecord(
        _ record: PersistedMutationRecord,
        at storageKey: String
    ) throws {
        let plaintext = try encoder.encode(record)
        let encryptionKey = try derivedMutationProtectionKey(
            context: "record-encryption"
        )
        let sealed = try AES.GCM.seal(plaintext, using: encryptionKey)
        guard let combined = sealed.combined else {
            throw MutationRecordProtectionError.encryptionFailed
        }
        idempotencyDefaults.set(combined, forKey: storageKey)
    }

    private func decodePersistedMutationRecord(
        _ data: Data,
        allowsLegacyPlaintext: Bool
    ) throws -> PersistedMutationRecord {
        let encryptionKey = try derivedMutationProtectionKey(
            context: "record-encryption"
        )
        if let sealed = try? AES.GCM.SealedBox(combined: data),
           let plaintext = try? AES.GCM.open(sealed, using: encryptionKey),
           let record = try? decoder.decode(
               PersistedMutationRecord.self,
               from: plaintext
           ) {
            return record
        }
        if allowsLegacyPlaintext,
           let record = try? decoder.decode(
               PersistedMutationRecord.self,
               from: data
           ) {
            return record
        }
        // Never replace unreadable protected state with a fresh receipt: the
        // prior request may already have committed, which could duplicate a
        // mutation. Surface the secure-storage failure and let the user retry.
        throw MutationRecordProtectionError.invalidRecord
    }

    private func derivedMutationProtectionKey(
        context: String
    ) throws -> SymmetricKey {
        let keyData = try mutationProtectionKeyResult.get()
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: keyData),
            salt: Data("tsutsuura-mutation-receipts-v2".utf8),
            info: Data(context.utf8),
            outputByteCount: 32
        )
    }

    private func clearPersistentMutationKey(_ mutation: PersistentMutationKey) {
        idempotencyDefaults.removeObject(forKey: mutation.storageKey)
    }

    private func clearPersistentMutationKeyIfDefinitive(
        _ mutation: PersistentMutationKey,
        after error: Error
    ) {
        guard Self.isDefinitiveMutationFailure(error) else { return }
        clearPersistentMutationKey(mutation)
    }

    private static func isDefinitiveMutationFailure(_ error: Error) -> Bool {
        guard let apiError = error as? APIClientError else { return false }
        switch apiError {
        case .missingConfiguration,
             .invalidBaseURL,
             .invalidRequest,
             .unsupportedOperation,
             .unauthorized:
            return true
        case .server(let statusCode, _):
            // A throttled request may be the retry of a mutation whose first
            // response was lost. Retain its key so the exact receipt can be
            // recovered after Retry-After instead of creating a duplicate.
            return statusCode < 500 && statusCode != 429
        case .invalidResponse, .decoding, .transport:
            return false
        }
    }

    private static func authorizationFingerprint(_ token: String) -> String {
        sha256Hex("authorization\u{0}" + token)
    }

    private static func pairingCredentialFingerprint(
        _ credential: FamilyPairingCredential
    ) -> String {
        switch credential {
        case .code(let code):
            let separators = CharacterSet.whitespacesAndNewlines.union(
                CharacterSet(charactersIn: "-")
            )
            return "code\u{0}" + code.components(
                separatedBy: separators
            ).joined()
        case .token(let token):
            return "token\u{0}" + token.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        }
    }

    private static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map {
            String(format: "%02x", $0)
        }.joined()
    }

    private func send<Response: Decodable & Sendable>(
        _ endpoint: Endpoint<Response>
    ) async throws -> Response {
        let request = try await makeRequest(for: endpoint)
        let (data, response) = try await performTransport(
            request,
            method: endpoint.method,
            isMultipart: endpoint.multipartBody != nil,
            isSafelyRetryable: endpoint.isSafelyRetryable
        )

        guard (200..<300).contains(response.statusCode) else {
            let payload =
                (try? decoder.decode(APIErrorEnvelope.self, from: data).error)
                ?? (try? decoder.decode(APIErrorPayload.self, from: data))
            if response.statusCode == 401 {
                if let authorization = request.value(forHTTPHeaderField: "Authorization"),
                   authorization.hasPrefix("Bearer ") {
                    try? await tokenStore.clearToken(ifMatching: String(authorization.dropFirst(7)))
                }
                throw APIClientError.unauthorized
            }
            throw APIClientError.server(
                statusCode: response.statusCode,
                payload: payload
            )
        }

        let responseData = data.isEmpty ? Data("{}".utf8) : data
        do {
            return try decoder.decode(
                APIEnvelope<Response>.self,
                from: responseData
            ).data
        } catch {
            do {
                return try decoder.decode(Response.self, from: responseData)
            } catch {
                throw APIClientError.decoding(error)
            }
        }
    }

    private func performTransport(
        _ request: URLRequest,
        method: HTTPMethod,
        isMultipart: Bool,
        isSafelyRetryable: Bool
    ) async throws -> (Data, HTTPURLResponse) {
        let allowsRetry = !isMultipart
            && (method.isIdempotentForAutomaticRetry || isSafelyRetryable)
            && retryPolicy.maximumAttempts > 1
        var attempt = 1

        while true {
            let result: (Data, HTTPURLResponse)
            do {
                result = try await transport.data(for: request)
            } catch {
                guard allowsRetry,
                      attempt < retryPolicy.maximumAttempts,
                      isRetryableTransportError(error) else {
                    if let apiError = error as? APIClientError {
                        throw apiError
                    }
                    throw APIClientError.transport(error)
                }
                try await waitBeforeRetry(failedAttempt: attempt)
                attempt += 1
                continue
            }

            guard (500..<600).contains(result.1.statusCode),
                  allowsRetry,
                  attempt < retryPolicy.maximumAttempts else {
                return result
            }
            try await waitBeforeRetry(
                failedAttempt: attempt,
                retryAfter: result.1.value(forHTTPHeaderField: "Retry-After")
            )
            attempt += 1
        }
    }

    private func isRetryableTransportError(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let apiError = error as? APIClientError {
            if case .transport(let underlyingError) = apiError {
                return isRetryableTransportError(underlyingError)
            }
            return false
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled,
                 .badURL,
                 .unsupportedURL,
                 .userAuthenticationRequired,
                 .userCancelledAuthentication,
                 .appTransportSecurityRequiresSecureConnection,
                 .serverCertificateHasBadDate,
                 .serverCertificateUntrusted,
                 .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid,
                 .clientCertificateRejected,
                 .clientCertificateRequired:
                return false
            default:
                return true
            }
        }
        // An error thrown by HTTPTransport represents a failure before an HTTP
        // response was received. Unknown transport implementations (including
        // deterministic test transports) are therefore treated as transient.
        return true
    }

    private func waitBeforeRetry(
        failedAttempt: Int,
        retryAfter: String? = nil
    ) async throws {
        let exponentialDelay = retryPolicy.initialDelay
            * pow(2, Double(max(0, failedAttempt - 1)))
        let requestedDelay = retryAfter.flatMap(retryAfterDelay)
            ?? exponentialDelay
        let boundedDelay = min(
            retryPolicy.maximumDelay,
            max(0, requestedDelay)
        )
        guard boundedDelay > 0 else { return }
        let nanoseconds = UInt64(
            min(boundedDelay * 1_000_000_000, Double(UInt64.max))
        )
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    private func retryAfterDelay(_ rawValue: String) -> TimeInterval? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = TimeInterval(value), seconds >= 0 {
            return seconds
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: value) else { return nil }
        return max(0, date.timeIntervalSince(now()))
    }

    private func makeRequest<Response>(
        for endpoint: Endpoint<Response>
    ) async throws -> URLRequest {
        var url = configuration.baseURL
        for component in endpoint.path {
            url.appendPathComponent(component)
        }

        if !endpoint.query.isEmpty {
            guard var components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            ) else {
                throw APIClientError.invalidRequest
            }
            components.queryItems = endpoint.query
            guard let queryURL = components.url else {
                throw APIClientError.invalidRequest
            }
            url = queryURL
        }

        var request = URLRequest(url: url)
        // The shared host's front-end firewall blocks native mutation verbs
        // before PHP runs. The API accepts these logical methods over POST.
        // Retry decisions still use endpoint.method, preserving their semantics.
        switch endpoint.method {
        case .patch, .put, .delete:
            request.httpMethod = HTTPMethod.post.rawValue
            request.setValue(endpoint.method.rawValue, forHTTPHeaderField: "X-HTTP-Method-Override")
        case .get, .post:
            request.httpMethod = endpoint.method.rawValue
        }
        request.timeoutInterval = endpoint.multipartBody == nil ? 30 : 120
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let idempotencyKey = endpoint.idempotencyKey {
            request.setValue(
                idempotencyKey,
                forHTTPHeaderField: "Idempotency-Key"
            )
        }

        if let multipartBody = endpoint.multipartBody {
            request.httpBody = multipartBody.data
            request.setValue(
                "multipart/form-data; boundary=\(multipartBody.boundary)",
                forHTTPHeaderField: "Content-Type"
            )
            request.setValue(
                String(multipartBody.data.count),
                forHTTPHeaderField: "Content-Length"
            )
        } else if let body = endpoint.body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }

        if endpoint.requiresAuthorization {
            let token = try await tokenStore.readToken()
            if let token, !token.isEmpty {
                request.setValue(
                    "Bearer \(token)",
                    forHTTPHeaderField: "Authorization"
                )
            } else if !endpoint.allowsMissingAuthorization {
                throw APIClientError.unauthorized
            }
        }

        return request
    }

    private func isTrustedMediaURL(_ url: URL) -> Bool {
        guard url.user == nil, url.password == nil else { return false }

        let baseURL = configuration.baseURL
        return url.scheme?.lowercased() == baseURL.scheme?.lowercased()
            && url.host?.lowercased() == baseURL.host?.lowercased()
            && effectivePort(for: url) == effectivePort(for: baseURL)
    }

    private func effectivePort(for url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Persisted idempotency keys may replay through a newly constructed
        // client. Stable key ordering keeps the retried wire body byte-for-byte
        // identical across encoder instances, not merely JSON-equivalent.
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO-8601 date."
            )
        }
        return decoder
    }
}

private enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"

    var isIdempotentForAutomaticRetry: Bool {
        switch self {
        case .get, .put, .delete:
            return true
        case .post, .patch:
            return false
        }
    }
}

private struct Endpoint<Response>: Sendable {
    let method: HTTPMethod
    let path: [String]
    let query: [URLQueryItem]
    let body: (any Encodable & Sendable)?
    let multipartBody: MultipartFormData?
    let requiresAuthorization: Bool
    let idempotencyKey: String?
    let isSafelyRetryable: Bool
    let allowsMissingAuthorization: Bool

    init(
        method: HTTPMethod,
        path: [String],
        query: [URLQueryItem] = [],
        body: (any Encodable & Sendable)? = nil,
        multipartBody: MultipartFormData? = nil,
        requiresAuthorization: Bool = true,
        idempotencyKey: String? = nil,
        isSafelyRetryable: Bool = false,
        allowsMissingAuthorization: Bool = false
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.multipartBody = multipartBody
        self.requiresAuthorization = requiresAuthorization
        self.idempotencyKey = idempotencyKey
        self.isSafelyRetryable = isSafelyRetryable
        self.allowsMissingAuthorization = allowsMissingAuthorization
    }
}

private struct MultipartFormData: Sendable {
    let boundary: String
    let data: Data

    init(submission: AnswerSubmission, questionID: String, questionDate: String?) throws {
        boundary = "tsutsuura-\(UUID().uuidString)"
        var encoded = Data()
        Self.appendTextPart(name: "questionId", value: questionID, boundary: boundary, to: &encoded)
        if let questionDate {
            Self.appendTextPart(name: "questionDate", value: questionDate, boundary: boundary, to: &encoded)
        }

        Self.appendTextPart(
            name: "body",
            value: submission.body,
            boundary: boundary,
            to: &encoded
        )

        if let audio = submission.voiceRecording {
            if let duration = audio.durationMilliseconds, duration > 0 {
                Self.appendTextPart(
                    name: "audioDurationMilliseconds",
                    value: String(duration),
                    boundary: boundary,
                    to: &encoded
                )
            }
            try Self.appendFilePart(
                name: "audio",
                upload: audio,
                boundary: boundary,
                to: &encoded
            )
        }

        for photo in submission.photos {
            try Self.appendFilePart(
                name: "photos[]",
                upload: photo,
                boundary: boundary,
                to: &encoded
            )
        }

        encoded.appendUTF8("--\(boundary)--\r\n")
        data = encoded
    }

    private static func appendTextPart(
        name: String,
        value: String,
        boundary: String,
        to data: inout Data
    ) {
        data.appendUTF8("--\(boundary)\r\n")
        data.appendUTF8(
            "Content-Disposition: form-data; name=\"\(name)\"\r\n"
        )
        data.appendUTF8("Content-Type: text/plain; charset=utf-8\r\n\r\n")
        data.append(Data(value.utf8))
        data.appendUTF8("\r\n")
    }

    private static func appendFilePart(
        name: String,
        upload: AnswerMediaUpload,
        boundary: String,
        to data: inout Data
    ) throws {
        guard isValidMIMEType(upload.mimeType) else {
            throw APIClientError.invalidRequest
        }
        let fileName = AnswerMediaUpload.sanitizedFileName(upload.fileName)
        data.appendUTF8("--\(boundary)\r\n")
        data.appendUTF8(
            "Content-Disposition: form-data; name=\"\(name)\"; "
                + "filename=\"\(fileName)\"\r\n"
        )
        data.appendUTF8("Content-Type: \(upload.mimeType.lowercased())\r\n\r\n")
        data.append(upload.data)
        data.appendUTF8("\r\n")
    }

    private static func isValidMIMEType(_ value: String) -> Bool {
        guard value.contains("/"), !value.isEmpty else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII
                && scalar.value > 32
                && scalar.value < 127
                && scalar != ";"
                && scalar != "\""
                && scalar != "\\"
        }
    }
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }
}

private struct APIEnvelope<Value: Decodable & Sendable>: Decodable, Sendable {
    let data: Value
}

private struct APIErrorEnvelope: Decodable, Sendable {
    let error: APIErrorPayload
}

private struct SubmittedAnswerResponse: Decodable, Sendable {
    let answer: Answer

    private enum CodingKeys: String, CodingKey {
        case answer
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let answer = try container.decodeIfPresent(Answer.self, forKey: .answer) {
            self.answer = answer
        } else {
            answer = try Answer(from: decoder)
        }
    }
}

private struct TodayQuestionResponse: Decodable, Sendable {
    let question: Question
    let answer: Answer?
}

private struct UserProfileResponse: Decodable, Sendable {
    let user: UserProfile

    private enum CodingKeys: String, CodingKey {
        case user
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let user = try container.decodeIfPresent(UserProfile.self, forKey: .user) {
            self.user = user
        } else {
            user = try UserProfile(from: decoder)
        }
    }
}

private struct FamilyResponse: Decodable, Sendable {
    let family: FamilySummary

    private enum CodingKeys: String, CodingKey {
        case family
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let family = try container.decodeIfPresent(
            FamilySummary.self,
            forKey: .family
           ) {
            self.family = family
        } else {
            family = try FamilySummary(from: decoder)
        }
    }
}

private struct ManagedFamilyMemberResponse: Decodable, Sendable {
    let member: UserProfile
}

private struct FamilyPairingResponse: Decodable, Sendable {
    let pairing: FamilyPairing
}

private struct FamilyPairingPreviewResponse: Decodable, Sendable {
    let pairing: FamilyPairingPreview
}

private struct FamilyPairingListResponse: Decodable, Sendable {
    let items: [FamilyPairingPreview]
}

private struct CreatedCommentResponse: Decodable, Sendable {
    let comment: Comment

    private enum CodingKeys: String, CodingKey {
        case comment
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let comment = try container.decodeIfPresent(Comment.self, forKey: .comment) {
            self.comment = comment
        } else {
            comment = try Comment(from: decoder)
        }
    }
}

private struct CommentReportResponse: Decodable, Sendable {
    let report: CommentReport

    private enum CodingKeys: String, CodingKey {
        case report
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let report = try container.decodeIfPresent(
            CommentReport.self,
            forKey: .report
           ) {
            self.report = report
        } else {
            report = try CommentReport(from: decoder)
        }
    }
}

private struct DeviceTimeZoneBody: Encodable, Sendable {
    let timeZoneIdentifier: String
}

private struct NotificationPreferencesResponse: Decodable, Sendable {
    let preferences: NotificationPreferences

    private enum CodingKeys: String, CodingKey {
        case preferences
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let preferences = try container.decodeIfPresent(
            NotificationPreferences.self,
            forKey: .preferences
           ) {
            self.preferences = preferences
        } else {
            preferences = try NotificationPreferences(from: decoder)
        }
    }
}

private struct AccountExportResponse: Decodable, Sendable {
    let export: AccountExport

    private enum CodingKeys: String, CodingKey {
        case export
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let export = try container.decodeIfPresent(
            AccountExport.self,
            forKey: .export
           ) {
            self.export = export
        } else {
            export = try AccountExport(from: decoder)
        }
    }
}
