import Foundation

#if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
import ImageIO
import UniformTypeIdentifiers
#endif

// MARK: - Navigation and session

enum AppRoute: Hashable, Sendable {
    case emailEntry
    case emailVerification(email: String, requestID: String)
    case emailEnrollment
    case emailEnrollmentVerification(email: String, requestID: String)
    case phoneEntry
    case otpVerification(phoneNumber: String, requestID: String)
    case accountRecovery
    case phoneEnrollment
    case phoneEnrollmentVerification(phoneNumber: String, requestID: String)
    case onboarding
    case organizerSetup
    case pairingEntry
    case pairingConfirmation
    case familySetup
    case pairingShare
    case pairingReady
    case familyManagement
    case home
    case todayQuestion
    case answerHistory
    case historyFilters
    case answerEditor(answerID: String)
    case comments(answerID: String)
    case commentEditor(commentID: String, answerID: String)
    case familyRename
    case managedMemberEdit(memberID: String)
    case ownershipTransfer
    case settings
    case accountPrivacy
    case accountExport
    case recoveryCode
    case notificationSettings
    case help
    case essentials
    case personalMark
}

enum SessionState: Equatable, Sendable {
    case restoring
    case signedOut
    case awaitingOTP(phoneNumber: String)
    case awaitingEmailVerification(email: String)
    case signedIn(UserProfile)

    var isAwaitingVerification: Bool {
        if case .awaitingOTP = self { return true }
        if case .awaitingEmailVerification = self { return true }
        return false
    }
}

enum UnicodeTextValidation {
    /// PHP's `mb_strlen(..., "UTF-8")` and MySQL character limits count
    /// Unicode scalar values rather than Swift's extended grapheme clusters.
    /// Keep client counters and clamps on that same boundary so composed text
    /// cannot pass locally and then fail at the API.
    static func characterCount(_ value: String) -> Int {
        value.unicodeScalars.count
    }

    static func clamped(
        _ value: String,
        maximumLength: Int
    ) -> String {
        let scalars = value.unicodeScalars
        guard scalars.count > maximumLength else { return value }
        let endIndex = scalars.index(
            scalars.startIndex,
            offsetBy: maximumLength
        )
        return String(value[..<endIndex])
    }
}

enum NameValidation {
    /// Matches the server-side limit for organizer, family, member, and profile names.
    static let maximumLength = 80

    static func characterCount(_ value: String) -> Int {
        UnicodeTextValidation.characterCount(value)
    }

    static func clamped(
        _ value: String,
        maximumLength: Int = maximumLength
    ) -> String {
        UnicodeTextValidation.clamped(value, maximumLength: maximumLength)
    }

    static func isValid(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && characterCount(trimmed) <= maximumLength
    }
}

enum EmailAddressValidation {
    static let maximumLength = 254

    /// The server uses the same ASCII mailbox contract. Trim pasted whitespace,
    /// preserve plus addressing, and reject header injection before any request.
    static func normalized(_ value: String) -> String? {
        guard !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
            return nil
        }
        let email = (value.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? value)
            .trimmingCharacters(in: .whitespaces).lowercased()
        guard email.utf8.count <= maximumLength,
              email.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else {
            return nil
        }
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let local = String(parts[0])
        let domain = String(parts[1])
        guard !local.isEmpty, local.utf8.count <= 64,
              !local.hasPrefix("."), !local.hasSuffix("."), !local.contains(".."),
              local.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber
                  || "!#$%&'*+-/=?^_`{|}~.".contains($0)) }) else { return nil }
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2,
              labels.allSatisfy({ label in
                  !label.isEmpty && label.count <= 63
                      && !label.hasPrefix("-") && !label.hasSuffix("-")
                      && label.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
              }),
              labels.last!.contains(where: { $0.isLetter }) else { return nil }
        return email
    }

    static func isValid(_ value: String) -> Bool { normalized(value) != nil }
}

enum PhoneNumberValidation {
    /// Mirrors `PhoneNumber::normalize` on the server: remove Unicode spacing
    /// and common separators, translate `00` international prefixes and
    /// Japanese domestic leading zeroes, then require an E.164-shaped value.
    static func isPlausible(_ value: String) -> Bool {
        canonicalE164(value) != nil
    }

    static func normalizedForSubmission(_ value: String) -> String {
        canonicalE164(value) ?? normalizedWidthAndWhitespace(value)
    }

    static func canonicalE164(
        _ value: String,
        defaultCountryCode: String = "81"
    ) -> String? {
        let normalized = normalizedWidthAndWhitespace(value)
        let removable = CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: "-().")
        )
        var phone = String(
            normalized.unicodeScalars.filter { !removable.contains($0) }
        )
        guard !phone.isEmpty else { return nil }

        if phone.hasPrefix("00") {
            phone = "+" + phone.dropFirst(2)
        } else if phone.hasPrefix("0") {
            phone = "+" + defaultCountryCode + phone.dropFirst()
        }

        let scalars = Array(phone.unicodeScalars)
        guard scalars.first?.value == 43 else { return nil }
        let digits = scalars.dropFirst()
        guard (8...15).contains(digits.count),
              let firstDigit = digits.first,
              (49...57).contains(firstDigit.value),
              digits.allSatisfy({ (48...57).contains($0.value) }) else {
            return nil
        }
        return phone
    }

    private static func normalizedWidthAndWhitespace(_ value: String) -> String {
        (value.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? value)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum RecoveryCodeValidation {
    static let minimumLength = 40
    static let maximumLength = 128

    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValid(_ value: String) -> Bool {
        let scalars = normalized(value).unicodeScalars
        guard (minimumLength...maximumLength).contains(scalars.count) else {
            return false
        }
        return scalars.allSatisfy { scalar in
            switch scalar.value {
            case 45, 48...57, 65...90, 95, 97...122:
                return true
            default:
                return false
            }
        }
    }
}

enum TextInputValidationError: Error, Equatable, Sendable {
    case invalidEmailAddress
    case invalidPhoneNumber
    case invalidRecoveryCode
    case emptyComment
    case commentTooLong(maximum: Int)
    case reportDetailsTooLong(maximum: Int)
}

extension TextInputValidationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidEmailAddress:
            return "メールアドレスを確認してください。"
        case .invalidPhoneNumber:
            return "電話番号を確認してください。"
        case .invalidRecoveryCode:
            return "復旧コードは40〜128文字の英数字、ハイフン、またはアンダースコアで入力してください。"
        case .emptyComment:
            return "コメントを入力してください。"
        case .commentTooLong(let maximum):
            return "コメントは\(maximum)文字以内で入力してください。"
        case .reportDetailsTooLong(let maximum):
            return "通報の詳細は\(maximum)文字以内で入力してください。"
        }
    }
}

enum CommentTextValidation {
    static func body(_ value: String) throws -> String {
        let normalized = value
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw TextInputValidationError.emptyComment
        }
        guard UnicodeTextValidation.characterCount(normalized)
                <= Comment.maximumBodyCharacterCount else {
            throw TextInputValidationError.commentTooLong(
                maximum: Comment.maximumBodyCharacterCount
            )
        }
        return normalized
    }

    static func reportDetails(_ value: String?) throws -> String? {
        guard let value else { return nil }
        let normalized = value
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard UnicodeTextValidation.characterCount(normalized)
                <= CommentReport.maximumDetailsCharacterCount else {
            throw TextInputValidationError.reportDetailsTooLong(
                maximum: CommentReport.maximumDetailsCharacterCount
            )
        }
        return normalized.isEmpty ? nil : normalized
    }
}

enum NumericInputValidation {
    static func asciiDigits(in value: String, maximum: Int? = nil) -> String {
        let normalized = value.applyingTransform(
            .fullwidthToHalfwidth,
            reverse: false
        ) ?? value
        let digits = normalized.unicodeScalars.compactMap { scalar -> Character? in
            guard (48...57).contains(scalar.value) else { return nil }
            return Character(String(scalar))
        }
        if let maximum {
            return String(digits.prefix(maximum))
        }
        return String(digits)
    }
}

// MARK: - Authentication

enum FamilyRole: String, Codable, Equatable, Sendable {
    case owner
    case member
}

struct UserProfile: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var displayName: String
    var avatarURL: URL?
    var phoneNumber: String?
    var family: FamilySummary?
    var hasPhone: Bool? = nil
    var managed: Bool? = nil
    var familyRole: FamilyRole? = nil
    var joinedAt: Date? = nil
    var createdAt: Date? = nil
    var avatarMark: String? = nil
    var email: String? = nil
    var hasEmail: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case avatarURL = "avatarUrl"
        case phoneNumber
        case family
        case hasPhone
        case managed
        case familyRole = "role"
        case joinedAt
        case createdAt
        case avatarMark
        case email
        case hasEmail
    }
}

struct FamilySummary: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var memberCount: Int
    var inviteCode: String?
    var members: [UserProfile]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case memberCount
        case inviteCode
        case members
    }

    init(
        id: String,
        name: String,
        memberCount: Int,
        inviteCode: String? = nil,
        members: [UserProfile] = []
    ) {
        self.id = id
        self.name = name
        self.memberCount = memberCount
        self.inviteCode = inviteCode
        self.members = members
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        inviteCode = try container.decodeIfPresent(String.self, forKey: .inviteCode)
        members = try container.decodeIfPresent(
            [UserProfile].self,
            forKey: .members
        ) ?? []
        memberCount = try container.decodeIfPresent(
            Int.self,
            forKey: .memberCount
        ) ?? members.count
    }
}

struct AuthSession: Codable, Equatable, Sendable {
    let accessToken: String
    let tokenType: String
    let expiresAt: Date?
    let user: UserProfile

    enum CodingKeys: String, CodingKey {
        case accessToken = "token"
        case tokenType
        case expiresAt
        case user
    }

    init(
        accessToken: String,
        tokenType: String = "Bearer",
        expiresAt: Date? = nil,
        user: UserProfile
    ) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.expiresAt = expiresAt
        self.user = user
    }
}

struct RequestEmailCodeBody: Codable, Equatable, Sendable {
    let email: String
}

struct VerifyEmailCodeBody: Codable, Equatable, Sendable {
    let requestID: String
    let code: String

    enum CodingKeys: String, CodingKey {
        case requestID = "requestId"
        case code
    }
}

struct RequestOTPBody: Codable, Equatable, Sendable {
    let phone: String
}

struct VerifyOTPBody: Codable, Equatable, Sendable {
    let requestID: String
    let code: String

    enum CodingKeys: String, CodingKey {
        case requestID = "requestId"
        case code
    }
}

struct RequestPhoneEnrollmentBody: Codable, Equatable, Sendable {
    let phone: String
}

struct VerifyPhoneEnrollmentBody: Codable, Equatable, Sendable {
    let requestID: String
    let code: String

    enum CodingKeys: String, CodingKey {
        case requestID = "requestId"
        case code
    }
}

struct AccountRecoveryCode: Codable, Equatable, Sendable {
    let code: String
    let expiresAt: Date
}

struct VerifyAccountRecoveryBody: Codable, Equatable, Sendable {
    let code: String
}

struct OTPChallenge: Codable, Equatable, Sendable {
    let requestID: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case requestID = "requestId"
        case expiresIn
    }
}

struct UpdateProfileBody: Codable, Equatable, Sendable {
    let displayName: String
}

/// The server is authoritative about whether leaving removed the account.
/// In particular, a managed profile may have been promoted on another device,
/// so the client must not infer this result from a cached `managed` flag.
struct FamilyLeaveResult: Codable, Equatable, Sendable {
    let accountDeleted: Bool
}

// MARK: - Assisted family setup and device pairing

struct CreateOrganizerFamilyBody: Codable, Equatable, Sendable {
    let organizerName: String
    let familyName: String
}

struct AddManagedFamilyMemberBody: Codable, Equatable, Sendable {
    let displayName: String
}

struct RenameFamilyBody: Codable, Equatable, Sendable {
    let name: String
}

struct RenameManagedFamilyMemberBody: Codable, Equatable, Sendable {
    let displayName: String
}

struct TransferFamilyOwnershipBody: Codable, Equatable, Sendable {
    let memberID: String

    enum CodingKeys: String, CodingKey {
        case memberID = "memberId"
    }
}

enum FamilyPairingCredential: Equatable, Sendable {
    case code(String)
    case token(String)

    var requestBody: FamilyPairingSelectorBody {
        switch self {
        case .code(let code):
            FamilyPairingSelectorBody(code: code, token: nil)
        case .token(let token):
            FamilyPairingSelectorBody(code: nil, token: token)
        }
    }
}

struct FamilyPairingSelectorBody: Codable, Equatable, Sendable {
    let code: String?
    let token: String?
}

enum FamilyPairingStatus: String, Codable, Equatable, Sendable {
    case pending
    case consumed
    case revoked
    case expired
}

struct FamilyPairingMemberPreview: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var displayName: String
}

struct FamilyPairingFamilyPreview: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
}

struct FamilyPairingPreview: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let expiresAt: Date
    var status: FamilyPairingStatus
    var member: FamilyPairingMemberPreview
    var family: FamilyPairingFamilyPreview
    var createdAt: Date?
}

struct FamilyPairing: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let code: String
    let token: String
    let pairingURL: URL
    let expiresAt: Date
    let createdAt: Date
    var status: FamilyPairingStatus
    var member: FamilyPairingMemberPreview
    var family: FamilyPairingFamilyPreview

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case token
        case pairingURL = "pairingUrl"
        case expiresAt
        case createdAt
        case status
        case member
        case family
    }

    var preview: FamilyPairingPreview {
        FamilyPairingPreview(
            id: id,
            expiresAt: expiresAt,
            status: status,
            member: member,
            family: family,
            createdAt: createdAt
        )
    }
}

// MARK: - Questions, answers, and family feed

struct Question: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var prompt: String
    var publishedOn: String
    var answer: Answer?
    var availableAt: Date? = nil
    var isAvailable: Bool? = nil
    var timeZoneIdentifier: String? = nil

    var canAnswer: Bool { isAvailable != false && answer == nil }

    enum CodingKeys: String, CodingKey {
        case id
        case prompt
        case publishedOn = "date"
        case answer
        case availableAt
        case isAvailable
        case timeZoneIdentifier
    }
}

struct AnswerAuthor: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var displayName: String
    var avatarURL: URL?
    var avatarMark: String? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case avatarURL = "avatarUrl"
        case avatarMark
    }
}

enum AnswerMediaKind: String, Codable, Equatable, Sendable {
    case audio
    case photo
}

struct AnswerMedia: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: AnswerMediaKind
    let url: URL
    let mimeType: String
    let fileName: String?
    let byteCount: Int?
    let durationMilliseconds: Int?

    init(
        id: String,
        kind: AnswerMediaKind,
        url: URL,
        mimeType: String,
        fileName: String? = nil,
        byteCount: Int? = nil,
        durationMilliseconds: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.url = url
        self.mimeType = mimeType
        self.fileName = fileName
        self.byteCount = byteCount
        self.durationMilliseconds = durationMilliseconds
    }
}

/// Bytes selected or recorded locally before an answer is submitted.
///
/// Keeping the bytes in the value makes a draft independent from temporary
/// picker and recorder URLs, which iOS may invalidate at any time.
struct AnswerMediaUpload: Equatable, Identifiable, Sendable {
    static let maximumFileNameCharacterCount = 200

    let id: UUID
    let data: Data
    let fileName: String
    let mimeType: String
    let durationMilliseconds: Int?

    init(
        id: UUID = UUID(),
        data: Data,
        fileName: String,
        mimeType: String,
        durationMilliseconds: Int? = nil
    ) {
        self.id = id
        self.data = data
        self.fileName = fileName
        self.mimeType = mimeType
        self.durationMilliseconds = durationMilliseconds
    }

    /// Produces a single, header-safe path component on the same 200-scalar
    /// boundary used by the server's persisted media metadata.
    static func sanitizedFileName(_ value: String) -> String {
        let lastComponent = value
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .last
            .map(String.init) ?? "upload"
        let sanitizedScalars = lastComponent.unicodeScalars.map { scalar -> Character in
            switch scalar.value {
            case 0...31, 34, 127:
                return "_"
            default:
                return Character(String(scalar))
            }
        }
        let sanitized = String(sanitizedScalars).trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(
                CharacterSet(charactersIn: ".")
            )
        )
        guard !sanitized.isEmpty else { return "upload" }
        return UnicodeTextValidation.clamped(
            sanitized,
            maximumLength: maximumFileNameCharacterCount
        )
    }
}

#if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
extension AnswerMediaUpload {
    /// Decodes any ImageIO-supported picker asset (including HEIC), removes
    /// orientation ambiguity, and emits a server-supported, size-bounded JPEG.
    static func normalizedPhoto(
        from sourceData: Data,
        preferredFileName: String = "photo.jpg"
    ) throws -> AnswerMediaUpload {
        guard let source = CGImageSourceCreateWithData(
            sourceData as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            throw AnswerPhotoEncodingError.invalidImage
        }

        let dimensions = [4_096, 3_072, 2_048]
        let qualities = [0.84, 0.68, 0.52, 0.38]
        for maximumDimension in dimensions {
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                thumbnailOptions as CFDictionary
            ) else {
                continue
            }

            for quality in qualities {
                let encodedData = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(
                    encodedData,
                    UTType.jpeg.identifier as CFString,
                    1,
                    nil
                ) else {
                    throw AnswerPhotoEncodingError.couldNotEncode
                }
                CGImageDestinationAddImage(
                    destination,
                    image,
                    [kCGImageDestinationLossyCompressionQuality: quality]
                        as CFDictionary
                )
                guard CGImageDestinationFinalize(destination) else {
                    continue
                }
                let data = encodedData as Data
                if !data.isEmpty,
                   data.count <= AnswerDraft.maximumPhotoByteCount {
                    return AnswerMediaUpload(
                        data: data,
                        fileName: jpegFileName(from: preferredFileName),
                        mimeType: "image/jpeg"
                    )
                }
            }
        }
        throw AnswerMediaValidationError.photoTooLarge(
            maximumBytes: AnswerDraft.maximumPhotoByteCount
        )
    }

    private static func jpegFileName(from value: String) -> String {
        let component = value
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .last
            .map(String.init) ?? "photo"
        let stem = URL(fileURLWithPath: component)
            .deletingPathExtension()
            .lastPathComponent
        return "\(stem.isEmpty ? "photo" : stem).jpg"
    }
}

enum AnswerPhotoEncodingError: Error, Equatable, Sendable {
    case invalidImage
    case couldNotEncode
}

extension AnswerPhotoEncodingError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "選択した写真を読み取れませんでした。"
        case .couldNotEncode:
            return "写真をアップロード用に変換できませんでした。"
        }
    }
}
#endif

struct AnswerDraft: Equatable, Sendable {
    static let maximumBodyCharacterCount = 2_000
    static let maximumPhotoCount = 4
    static let maximumPhotoByteCount = 10 * 1_024 * 1_024
    static let maximumAudioByteCount = 20 * 1_024 * 1_024
    static let maximumAudioDurationMilliseconds = 86_400_000

    var body = ""
    private(set) var voiceRecording: AnswerMediaUpload?
    private(set) var photos: [AnswerMediaUpload] = []

    var isEmpty: Bool {
        body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && voiceRecording == nil
            && photos.isEmpty
    }

    mutating func setVoiceRecording(
        _ recording: AnswerMediaUpload?
    ) throws {
        if let recording {
            try Self.validateAudio(recording)
        }
        voiceRecording = recording
    }

    mutating func addPhotos(_ newPhotos: [AnswerMediaUpload]) throws {
        guard photos.count + newPhotos.count <= Self.maximumPhotoCount else {
            throw AnswerMediaValidationError.tooManyPhotos(
                maximum: Self.maximumPhotoCount
            )
        }
        try newPhotos.forEach(Self.validatePhoto)
        photos.append(contentsOf: newPhotos)
    }

    mutating func replacePhotos(
        with newPhotos: [AnswerMediaUpload]
    ) throws {
        guard newPhotos.count <= Self.maximumPhotoCount else {
            throw AnswerMediaValidationError.tooManyPhotos(
                maximum: Self.maximumPhotoCount
            )
        }
        try newPhotos.forEach(Self.validatePhoto)
        photos = newPhotos
    }

    mutating func removePhoto(id: UUID) {
        photos.removeAll(where: { $0.id == id })
    }

    mutating func removeAllMedia() {
        voiceRecording = nil
        photos = []
    }

    mutating func removeAll() {
        body = ""
        removeAllMedia()
    }

    func submission() throws -> AnswerSubmission {
        let submission = AnswerSubmission(
            body: body,
            voiceRecording: voiceRecording,
            photos: photos
        )
        try submission.validate()
        return submission
    }

    fileprivate static func validateAudio(
        _ recording: AnswerMediaUpload
    ) throws {
        guard !recording.data.isEmpty else {
            throw AnswerMediaValidationError.emptyAudio
        }
        let supportedTypes: Set<String> = [
            "audio/mp4",
            "audio/x-m4a",
            "audio/aac",
            "audio/x-hx-aac-adts",
            "audio/mpeg",
            "audio/mp3",
            "audio/wav",
            "audio/x-wav",
            "audio/vnd.wave",
            "audio/x-caf",
        ]
        guard supportedTypes.contains(recording.mimeType.lowercased()) else {
            throw AnswerMediaValidationError.invalidAudioType
        }
        guard recording.data.count <= maximumAudioByteCount else {
            throw AnswerMediaValidationError.audioTooLarge(
                maximumBytes: maximumAudioByteCount
            )
        }
        if let duration = recording.durationMilliseconds,
           !(1...maximumAudioDurationMilliseconds).contains(duration) {
            throw AnswerMediaValidationError.invalidAudioDuration(
                maximumMilliseconds: maximumAudioDurationMilliseconds
            )
        }
    }

    fileprivate static func validatePhoto(_ photo: AnswerMediaUpload) throws {
        guard !photo.data.isEmpty else {
            throw AnswerMediaValidationError.emptyPhoto
        }
        let supportedTypes: Set<String> = [
            "image/jpeg",
            "image/png",
            "image/webp",
        ]
        guard supportedTypes.contains(photo.mimeType.lowercased()) else {
            throw AnswerMediaValidationError.invalidPhotoType
        }
        guard photo.data.count <= maximumPhotoByteCount else {
            throw AnswerMediaValidationError.photoTooLarge(
                maximumBytes: maximumPhotoByteCount
            )
        }
    }
}

struct AnswerSubmission: Equatable, Sendable {
    let body: String
    let voiceRecording: AnswerMediaUpload?
    let photos: [AnswerMediaUpload]

    init(
        body: String,
        voiceRecording: AnswerMediaUpload? = nil,
        photos: [AnswerMediaUpload] = []
    ) {
        self.body = body
        self.voiceRecording = voiceRecording
        self.photos = photos
    }

    var hasMedia: Bool {
        voiceRecording != nil || !photos.isEmpty
    }

    func validate() throws {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || hasMedia else {
            throw AnswerMediaValidationError.emptyAnswer
        }
        guard UnicodeTextValidation.characterCount(
            body.trimmingCharacters(in: .whitespacesAndNewlines)
        ) <= AnswerDraft.maximumBodyCharacterCount else {
            throw AnswerMediaValidationError.answerTooLong(
                maximum: AnswerDraft.maximumBodyCharacterCount
            )
        }
        guard photos.count <= AnswerDraft.maximumPhotoCount else {
            throw AnswerMediaValidationError.tooManyPhotos(
                maximum: AnswerDraft.maximumPhotoCount
            )
        }
        if let voiceRecording {
            try AnswerDraft.validateAudio(voiceRecording)
        }
        try photos.forEach(AnswerDraft.validatePhoto)
    }
}

struct AnswerMediaContent: Equatable, Sendable {
    let data: Data
    let mimeType: String
}

enum AnswerMediaValidationError: Error, Equatable, Sendable {
    case emptyAnswer
    case answerTooLong(maximum: Int)
    case tooManyPhotos(maximum: Int)
    case photoTooLarge(maximumBytes: Int)
    case audioTooLarge(maximumBytes: Int)
    case emptyPhoto
    case emptyAudio
    case invalidAudioDuration(maximumMilliseconds: Int)
    case invalidPhotoType
    case invalidAudioType
}

extension AnswerMediaValidationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .emptyAnswer:
            return "文章、音声、または写真を追加してください。"
        case .answerTooLong(let maximum):
            return "回答は\(maximum)文字以内で入力してください。"
        case .tooManyPhotos(let maximum):
            return "写真は\(maximum)枚まで追加できます。"
        case .photoTooLarge:
            return "写真は1枚につき10 MB以下にしてください。"
        case .audioTooLarge:
            return "音声は20 MB以下にしてください。"
        case .emptyPhoto:
            return "空の写真ファイルは追加できません。"
        case .emptyAudio:
            return "空の音声ファイルは追加できません。"
        case .invalidAudioDuration:
            return "音声の長さを1ミリ秒以上24時間以内にしてください。"
        case .invalidPhotoType:
            return "写真をJPEG、PNG、またはWebP形式にしてください。"
        case .invalidAudioType:
            return "録音したファイルを音声として利用できません。"
        }
    }
}

struct Answer: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let questionID: String
    var questionPrompt: String?
    var author: AnswerAuthor
    var body: String
    let createdAt: Date
    var answerDate: String?
    var updatedAt: Date?
    var likeCount: Int
    var commentCount: Int
    var isLikedByMe: Bool
    var media: [AnswerMedia]

    private enum CodingKeys: String, CodingKey {
        case id
        case question
        case author
        case body
        case createdAt
        case answerDate
        case updatedAt
        case likeCount = "likesCount"
        case commentCount = "commentsCount"
        case isLikedByMe = "isLiked"
        case media
    }

    init(
        id: String,
        questionID: String,
        questionPrompt: String? = nil,
        author: AnswerAuthor,
        body: String,
        createdAt: Date,
        answerDate: String? = nil,
        updatedAt: Date? = nil,
        likeCount: Int = 0,
        commentCount: Int = 0,
        isLikedByMe: Bool = false,
        media: [AnswerMedia] = []
    ) {
        self.id = id
        self.questionID = questionID
        self.questionPrompt = questionPrompt
        self.author = author
        self.body = body
        self.createdAt = createdAt
        self.answerDate = answerDate
        self.updatedAt = updatedAt
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.isLikedByMe = isLikedByMe
        self.media = media
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let question = try container.decode(
            AnswerQuestionReference.self,
            forKey: .question
        )
        id = try container.decode(String.self, forKey: .id)
        questionID = question.id
        questionPrompt = question.prompt
        author = try container.decode(AnswerAuthor.self, forKey: .author)
        body = try container.decode(String.self, forKey: .body)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        answerDate = try container.decodeIfPresent(String.self, forKey: .answerDate)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        likeCount = try container.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
        commentCount = try container.decodeIfPresent(
            Int.self,
            forKey: .commentCount
        ) ?? 0
        isLikedByMe = try container.decodeIfPresent(
            Bool.self,
            forKey: .isLikedByMe
        ) ?? false
        media = try container.decodeIfPresent(
            [AnswerMedia].self,
            forKey: .media
        ) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(
            AnswerQuestionReference(
                id: questionID,
                prompt: questionPrompt,
                date: answerDate
            ),
            forKey: .question
        )
        try container.encode(author, forKey: .author)
        try container.encode(body, forKey: .body)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(answerDate, forKey: .answerDate)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encode(likeCount, forKey: .likeCount)
        try container.encode(commentCount, forKey: .commentCount)
        try container.encode(isLikedByMe, forKey: .isLikedByMe)
        try container.encode(media, forKey: .media)
    }
}

struct HomeFeed: Codable, Equatable, Sendable {
    var family: FamilySummary?
    var todayQuestion: Question?
    var myAnswer: Answer?
    var answers: [Answer]
    var nextCursor: String?
    var todayAnsweredUserIDs: [String]?

    enum CodingKeys: String, CodingKey {
        case family
        case todayQuestion
        case myAnswer
        case answers = "feed"
        case nextCursor
        case todayAnsweredUserIDs
    }

    init(
        family: FamilySummary? = nil,
        todayQuestion: Question? = nil,
        myAnswer: Answer? = nil,
        answers: [Answer] = [],
        nextCursor: String? = nil,
        todayAnsweredUserIDs: [String]? = nil
    ) {
        self.family = family
        self.todayQuestion = todayQuestion
        self.myAnswer = myAnswer
        self.answers = answers
        self.nextCursor = nextCursor
        self.todayAnsweredUserIDs = todayAnsweredUserIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        family = try container.decodeIfPresent(FamilySummary.self, forKey: .family)
        todayQuestion = try container.decodeIfPresent(
            Question.self,
            forKey: .todayQuestion
        )
        myAnswer = try container.decodeIfPresent(Answer.self, forKey: .myAnswer)
        answers = try container.decodeIfPresent([Answer].self, forKey: .answers) ?? []
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
        todayAnsweredUserIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .todayAnsweredUserIDs
        )
        if todayQuestion?.answer == nil {
            todayQuestion?.answer = myAnswer
        }
    }
}

/// Daily progress derived from the available feed and current family roster.
struct FamilyAnswerProgress: Equatable, Sendable {
    let members: [UserProfile]
    let answeredUserIDs: Set<String>
    let total: Int

    var answered: Int { min(total, answeredUserIDs.count) }
    var fraction: Double { total > 0 ? Double(answered) / Double(total) : 0 }
    var isComplete: Bool { total > 0 && answered == total }

    init(feed: HomeFeed) {
        var memberIDs = Set<String>()
        members = (feed.family?.members ?? []).filter {
            memberIDs.insert($0.id).inserted
        }
        let declaredTotal = max(0, feed.family?.memberCount ?? 0)
        total = max(declaredTotal, members.count)

        guard total > 0,
              let question = feed.todayQuestion,
              !question.publishedOn.isEmpty else {
            answeredUserIDs = []
            return
        }

        let todaysAuthors: Set<String>
        if let authoritativeIDs = feed.todayAnsweredUserIDs {
            todaysAuthors = Set(authoritativeIDs)
        } else {
            let candidates = feed.answers + [feed.myAnswer, question.answer].compactMap { $0 }
            todaysAuthors = Set(candidates.filter { answer in
                answer.answerDate == question.publishedOn
                    && (question.id.isEmpty || answer.questionID.isEmpty
                        || answer.questionID == question.id)
            }.map(\.author.id))
        }

        // Older responses can carry only a count or a partial member list.
        // Only a complete roster lets us identify and exclude former members.
        answeredUserIDs = members.count >= declaredTotal
            ? todaysAuthors.intersection(memberIDs)
            : todaysAuthors
    }
}

struct AnswerPage: Codable, Equatable, Sendable {
    var answers: [Answer]
    var nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case answers = "items"
        case nextCursor
    }
}

enum HistoryScope: String, Codable, Equatable, Hashable, Sendable {
    case mine
    case family
}

struct HistoryQuery: Codable, Equatable, Hashable, Sendable {
    static let maximumSearchCharacterCount = 100

    var scope: HistoryScope
    var authorID: String?
    var startDate: String?
    var endDate: String?
    var searchText: String
    var limit: Int

    init(
        scope: HistoryScope = .mine,
        authorID: String? = nil,
        startDate: String? = nil,
        endDate: String? = nil,
        searchText: String = "",
        limit: Int = 20
    ) {
        self.scope = scope
        self.authorID = authorID?.historyTrimmedNilIfEmpty
        self.startDate = startDate?.historyTrimmedNilIfEmpty
        self.endDate = endDate?.historyTrimmedNilIfEmpty
        self.searchText = Self.normalizedSearchText(searchText)
        self.limit = Self.normalizedLimit(limit)
    }

    static func normalizedSearchText(_ value: String) -> String {
        UnicodeTextValidation.clamped(
            value.trimmingCharacters(in: .whitespacesAndNewlines),
            maximumLength: maximumSearchCharacterCount
        )
    }

    static func normalizedLimit(_ value: Int) -> Int {
        min(max(value, 1), 50)
    }

    var hasActiveFilters: Bool {
        authorID != nil
            || startDate != nil
            || endDate != nil
            || !searchText.isEmpty
    }

    enum CodingKeys: String, CodingKey {
        case scope
        case authorID = "authorId"
        case startDate = "from"
        case endDate = "to"
        case searchText = "q"
        case limit
    }
}

struct SubmitAnswerBody: Codable, Equatable, Sendable {
    let body: String
    var questionId: String? = nil
    var questionDate: String? = nil
}

struct UpdateAnswerBody: Codable, Equatable, Sendable {
    let body: String
}

// MARK: - Likes and comments

struct LikeState: Codable, Equatable, Sendable {
    var isLikedByMe: Bool
    var likeCount: Int

    enum CodingKeys: String, CodingKey {
        case isLikedByMe = "isLiked"
        case likeCount = "likesCount"
    }
}

struct Comment: Codable, Equatable, Identifiable, Sendable {
    static let maximumBodyCharacterCount = 1_000

    let id: String
    let answerID: String
    var author: AnswerAuthor
    var body: String
    let createdAt: Date
    var updatedAt: Date?
    var parentCommentID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case answerID = "answerId"
        case author
        case body
        case createdAt
        case updatedAt
        case parentCommentID = "parentCommentId"
    }

    init(
        id: String,
        answerID: String,
        author: AnswerAuthor,
        body: String,
        createdAt: Date,
        updatedAt: Date? = nil,
        parentCommentID: String? = nil
    ) {
        self.id = id
        self.answerID = answerID
        self.author = author
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.parentCommentID = parentCommentID
    }
}

struct CommentPage: Codable, Equatable, Sendable {
    var comments: [Comment]
    var nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case comments = "items"
        case nextCursor
    }
}

struct CreateCommentBody: Codable, Equatable, Sendable {
    let body: String
    let parentCommentID: String?

    enum CodingKeys: String, CodingKey {
        case body
        case parentCommentID = "parentCommentId"
    }

    init(body: String, parentCommentID: String? = nil) {
        self.body = body
        self.parentCommentID = parentCommentID
    }
}

struct UpdateCommentBody: Codable, Equatable, Sendable {
    let body: String
}

enum CommentReportReason: String, Codable, CaseIterable, Equatable, Sendable {
    case spam
    case harassment
    case privacy
    case inappropriate
    case other
}

struct ReportCommentBody: Codable, Equatable, Sendable {
    let reason: CommentReportReason
    let details: String?
}

struct CommentReport: Codable, Equatable, Identifiable, Sendable {
    static let maximumDetailsCharacterCount = 500

    let id: String
    let commentID: String?
    let reason: CommentReportReason?
    let status: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case commentID = "commentId"
        case reason
        case status
        case createdAt
    }

    init(
        id: String,
        commentID: String? = nil,
        reason: CommentReportReason? = nil,
        status: String,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.commentID = commentID
        self.reason = reason
        self.status = status
        self.createdAt = createdAt
    }
}

// MARK: - Notifications and API metadata

enum PushEnvironment: String, Codable, Equatable, Sendable {
    case sandbox
    case production
}

struct RegisterPushTokenBody: Codable, Equatable, Sendable {
    let token: String
    let platform: String
    let environment: PushEnvironment

    init(token: String, environment: PushEnvironment) {
        self.token = token
        platform = "ios"
        self.environment = environment
    }
}

enum NotificationPermissionStatus: String, Codable, Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown
}

struct NotificationPreferences: Codable, Equatable, Sendable {
    var familyID: String?
    var enabled: Bool
    var dailyReminderEnabled: Bool
    var dailyReminderTime: String
    var timeZoneIdentifier: String
    var muteUntil: Date?
    var commentsEnabled: Bool
    var likesEnabled: Bool
    var quietStart: String?
    var quietEnd: String?
    var updatedAt: Date?

    init(
        familyID: String? = nil,
        enabled: Bool = true,
        dailyReminderEnabled: Bool = true,
        dailyReminderTime: String = "09:00",
        timeZoneIdentifier: String = TimeZone.current.identifier,
        muteUntil: Date? = nil,
        commentsEnabled: Bool = true,
        likesEnabled: Bool = true,
        quietStart: String? = nil,
        quietEnd: String? = nil,
        updatedAt: Date? = nil
    ) {
        self.familyID = familyID
        self.enabled = enabled
        self.dailyReminderEnabled = dailyReminderEnabled
        self.dailyReminderTime = dailyReminderTime
        self.timeZoneIdentifier = timeZoneIdentifier
        self.muteUntil = muteUntil
        self.commentsEnabled = commentsEnabled
        self.likesEnabled = likesEnabled
        self.quietStart = quietStart
        self.quietEnd = quietEnd
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case questionRemindersEnabled
        case questionReminderTime
        case commentsEnabled
        case likesEnabled
        case familyActivityEnabled
        case quietStart
        case quietEnd
        case muteUntil
        case timeZoneIdentifier = "timezone"
        case updatedAt

        // Compatibility with the first iOS-only preference draft. The live
        // API encoder intentionally emits only the canonical keys above.
        case legacyFamilyID = "familyId"
        case legacyEnabled = "enabled"
        case legacyDailyReminderEnabled = "dailyReminderEnabled"
        case legacyDailyReminderTime = "dailyReminderTime"
        case legacyTimeZoneIdentifier = "timeZone"
        case legacyQuestionsEnabled = "questionsEnabled"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let questionRemindersEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .questionRemindersEnabled
        )
        familyID = try container.decodeIfPresent(
            String.self,
            forKey: .legacyFamilyID
        )
        enabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .legacyEnabled
        ) ?? container.decodeIfPresent(
            Bool.self,
            forKey: .familyActivityEnabled
        ) ?? true
        dailyReminderEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .legacyDailyReminderEnabled
        ) ?? container.decodeIfPresent(
            Bool.self,
            forKey: .legacyQuestionsEnabled
        ) ?? questionRemindersEnabled ?? true
        dailyReminderTime = try container.decodeIfPresent(
            String.self,
            forKey: .questionReminderTime
        ) ?? container.decodeIfPresent(
            String.self,
            forKey: .legacyDailyReminderTime
        ) ?? "09:00"
        timeZoneIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .timeZoneIdentifier
        ) ?? container.decodeIfPresent(
            String.self,
            forKey: .legacyTimeZoneIdentifier
        ) ?? TimeZone.current.identifier
        muteUntil = try container.decodeIfPresent(
            Date.self,
            forKey: .muteUntil
        )
        commentsEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .commentsEnabled
        ) ?? true
        likesEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .likesEnabled
        ) ?? true
        quietStart = try container.decodeIfPresent(
            String.self,
            forKey: .quietStart
        )
        quietEnd = try container.decodeIfPresent(
            String.self,
            forKey: .quietEnd
        )
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            dailyReminderEnabled,
            forKey: .questionRemindersEnabled
        )
        try container.encode(
            dailyReminderTime,
            forKey: .questionReminderTime
        )
        try container.encode(commentsEnabled, forKey: .commentsEnabled)
        try container.encode(likesEnabled, forKey: .likesEnabled)
        try container.encode(enabled, forKey: .familyActivityEnabled)
        try container.encode(quietStart, forKey: .quietStart)
        try container.encode(quietEnd, forKey: .quietEnd)
        try container.encode(muteUntil, forKey: .muteUntil)
        try container.encode(timeZoneIdentifier, forKey: .timeZoneIdentifier)
    }
}

// MARK: - Account and privacy

struct AccountExportAnswer: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let date: String
    let prompt: String
    let body: String
    let media: [AnswerMedia]
    let createdAt: Date
    let updatedAt: Date

    init(
        id: String,
        date: String,
        prompt: String,
        body: String,
        media: [AnswerMedia] = [],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.date = date
        self.prompt = prompt
        self.body = body
        self.media = media
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(answer: Answer) {
        id = answer.id
        date = answer.answerDate ?? ""
        prompt = answer.questionPrompt ?? ""
        body = answer.body
        media = answer.media
        createdAt = answer.createdAt
        updatedAt = answer.updatedAt ?? answer.createdAt
    }
}

struct AccountExportComment: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let answerID: String
    let parentCommentID: String?
    let body: String
    let createdAt: Date
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case answerID = "answerId"
        case parentCommentID = "parentCommentId"
        case body
        case createdAt
        case updatedAt
    }

    init(comment: Comment) {
        id = comment.id
        answerID = comment.answerID
        parentCommentID = comment.parentCommentID
        body = comment.body
        createdAt = comment.createdAt
        updatedAt = comment.updatedAt
    }
}

indirect enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct AccountAuditEvent: Codable, Equatable, Sendable {
    let action: String
    let targetType: String
    let targetID: String?
    let metadata: [String: JSONValue]
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case action
        case targetType
        case targetID = "targetId"
        case metadata
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(String.self, forKey: .action)
        targetType = try container.decode(String.self, forKey: .targetType)
        targetID = try container.decodeIfPresent(String.self, forKey: .targetID)
        metadata = try container.decodeIfPresent(
            [String: JSONValue].self,
            forKey: .metadata
        ) ?? [:]
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

struct AccountExport: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let user: UserProfile
    let family: FamilySummary?
    let answers: [AccountExportAnswer]
    let comments: [AccountExportComment]
    let likedAnswerIDs: [String]
    let notificationPreferences: NotificationPreferences?
    let auditLog: [AccountAuditEvent]

    init(
        schemaVersion: Int = 1,
        generatedAt: Date,
        user: UserProfile,
        family: FamilySummary? = nil,
        answers: [AccountExportAnswer] = [],
        comments: [AccountExportComment] = [],
        likedAnswerIDs: [String] = [],
        notificationPreferences: NotificationPreferences? = nil,
        auditLog: [AccountAuditEvent] = []
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.user = user
        self.family = family
        self.answers = answers
        self.comments = comments
        self.likedAnswerIDs = likedAnswerIDs
        self.notificationPreferences = notificationPreferences
        self.auditLog = auditLog
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generatedAt = "exportedAt"
        case legacyGeneratedAt = "generatedAt"
        case user = "account"
        case legacyUser = "user"
        case family
        case answers
        case comments
        case likedAnswerIDs = "likedAnswerIds"
        case notificationPreferences
        case auditLog
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .schemaVersion
        ) ?? 1
        if let value = try container.decodeIfPresent(Date.self, forKey: .generatedAt) {
            generatedAt = value
        } else {
            generatedAt = try container.decode(Date.self, forKey: .legacyGeneratedAt)
        }
        if let value = try container.decodeIfPresent(UserProfile.self, forKey: .user) {
            user = value
        } else {
            user = try container.decode(UserProfile.self, forKey: .legacyUser)
        }
        family = try container.decodeIfPresent(FamilySummary.self, forKey: .family)
        answers = try container.decodeIfPresent(
            [AccountExportAnswer].self,
            forKey: .answers
        ) ?? []
        comments = try container.decodeIfPresent(
            [AccountExportComment].self,
            forKey: .comments
        ) ?? []
        likedAnswerIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .likedAnswerIDs
        ) ?? []
        notificationPreferences = try container.decodeIfPresent(
            NotificationPreferences.self,
            forKey: .notificationPreferences
        )
        auditLog = try container.decodeIfPresent(
            [AccountAuditEvent].self,
            forKey: .auditLog
        ) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(user, forKey: .user)
        try container.encodeIfPresent(family, forKey: .family)
        try container.encode(answers, forKey: .answers)
        try container.encode(comments, forKey: .comments)
        try container.encode(likedAnswerIDs, forKey: .likedAnswerIDs)
        try container.encodeIfPresent(
            notificationPreferences,
            forKey: .notificationPreferences
        )
        try container.encode(auditLog, forKey: .auditLog)
    }
}

struct EmptyResponse: Codable, Equatable, Sendable {
    init() {}
}

struct APIErrorPayload: Codable, Equatable, Sendable {
    var code: String?
    var message: String?
}

private struct AnswerQuestionReference: Codable, Sendable {
    let id: String
    let prompt: String?
    let date: String?
}

private extension String {
    var historyTrimmedNilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
