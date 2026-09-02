import Foundation

enum DemoLaunchMode: String, Sendable {
    case authenticated
    case signedOut

    static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> DemoLaunchMode? {
        #if DEBUG
        if let value = environment["TSUTSUURA_DEMO_MODE"] {
            return DemoLaunchMode(rawValue: value)
        }
        if arguments.contains("-tsutsuura-demo-authenticated") {
            return .authenticated
        }
        if arguments.contains("-tsutsuura-demo-signed-out") {
            return .signedOut
        }
        #endif
        return nil
    }
}

@MainActor
enum AppStoreLaunchFactory {
    static func make() -> AppStore {
        #if DEBUG
        if let mode = DemoLaunchMode.current() {
            return demoStore(mode: mode)
        }

        // Existing UI tests should never require a network or provider credential.
        if ProcessInfo.processInfo.environment["UI_TESTING"] == "1" {
            return demoStore(mode: .signedOut)
        }
        #endif

        if let liveStore = try? AppStore.live() {
            return liveStore
        }

        // This remains a safe fallback for malformed local build configuration.
        let baseURL = URL(
            string: "https://kttprojects.conohawing.com/tsutsuura-api/api"
        )!
        let configuration = try! APIConfiguration(baseURL: baseURL)
        return AppStore(
            api: DefaultAppAPI(configuration: configuration)
        )
    }

    #if DEBUG
    private static func demoStore(mode: DemoLaunchMode) -> AppStore {
        let store = AppStore(
            api: DemoAppAPI(startsAuthenticated: mode == .authenticated),
            haptics: NoopHaptics()
        )
        if ProcessInfo.processInfo.arguments.contains(
            "-tsutsuura-demo-draft-photos"
        ), let photoData = Data(
            base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ) {
            _ = store.addAnswerPhotos(
                (1...2).map { index in
                    AnswerMediaUpload(
                        data: photoData,
                        fileName: "draft-\(index).png",
                        mimeType: "image/png"
                    )
                }
            )
        }
        return store
    }
    #endif
}

#if DEBUG
actor DemoAppAPI: AppAPI {
    private var isAuthenticated: Bool
    private var profile: UserProfile
    private var family: FamilySummary
    private var todayQuestion: Question
    private var feedAnswers: [Answer]
    private var historyAnswers: [Answer]
    private var commentsByAnswerID: [String: [Comment]]
    private var nextCommentID = 100
    private var nextManagedMemberID = 1
    private var nextPairingID = 1
    private var pairingsByID: [String: FamilyPairing] = [:]
    private var mediaContentByURL: [URL: AnswerMediaContent] = [:]
    private var notificationPreferences = NotificationPreferences()
    private var reportsByCommentID: [String: CommentReport] = [:]
    private var nextReportID = 1
    private var pendingLoginPhone: String?
    private var pendingPhoneEnrollment: (requestID: String, phone: String)?
    private var activeRecoveryCode: AccountRecoveryCode?
    private var activeRecoveryMemberID: String?
    private var hasFamily = true
    /// Activation and durable recovery are separate live-server invariants.
    /// The seeded sibling represents a device that has completed both; a newly
    /// paired managed profile is activated but remains ineligible for ownership
    /// until it enrolls a phone or creates a recovery code.
    private var activatedMemberIDs: Set<String> = ["demo-user", "demo-family-1"]
    private var recoverableMemberIDs: Set<String> = ["demo-user", "demo-family-1"]

    init(startsAuthenticated: Bool) {
        isAuthenticated = startsAuthenticated

        let includesGalleryFixture = ProcessInfo.processInfo.arguments
            .contains("-tsutsuura-demo-gallery")
        let galleryPhotoData = Data(
            base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )!
        let galleryMedia: [AnswerMedia] = includesGalleryFixture
            ? (1...3).map { index in
                AnswerMedia(
                    id: "demo-gallery-photo-\(index)",
                    kind: .photo,
                    url: URL(
                        string: "https://demo.tsutsuura.invalid/media/demo-gallery-photo-\(index)"
                    )!,
                    mimeType: "image/png",
                    fileName: "demo-gallery-\(index).png",
                    byteCount: galleryPhotoData.count
                )
            }
            : []

        let currentUser = UserProfile(
            id: "demo-user",
            displayName: "つつうら",
            avatarURL: nil,
            phoneNumber: "090-1234-5678",
            family: nil,
            hasPhone: true,
            managed: false,
            familyRole: .owner,
            joinedAt: Date(timeIntervalSince1970: 1_722_124_800),
            createdAt: Date(timeIntervalSince1970: 1_722_124_800)
        )
        let sibling = UserProfile(
            id: "demo-family-1",
            displayName: "あおい",
            avatarURL: nil,
            phoneNumber: nil,
            family: nil,
            hasPhone: false,
            managed: true,
            familyRole: .member,
            joinedAt: Date(timeIntervalSince1970: 1_722_211_200),
            createdAt: Date(timeIntervalSince1970: 1_722_211_200)
        )
        let demoFamily = FamilySummary(
            id: "demo-family",
            name: "わたしたちの家族",
            memberCount: 2,
            inviteCode: "TUTUURA",
            members: [currentUser, sibling]
        )
        var userWithFamily = currentUser
        userWithFamily.family = demoFamily
        profile = userWithFamily
        family = demoFamily
        notificationPreferences.familyID = demoFamily.id

        todayQuestion = Question(
            id: "demo-question-today",
            prompt: "今日、家族に伝えたい小さな出来事は？",
            publishedOn: "2026-07-28",
            answer: nil
        )

        let siblingAuthor = AnswerAuthor(
            id: sibling.id,
            displayName: sibling.displayName,
            avatarURL: sibling.avatarURL
        )
        let currentAuthor = AnswerAuthor(
            id: currentUser.id,
            displayName: currentUser.displayName,
            avatarURL: currentUser.avatarURL
        )
        let familyAnswer = Answer(
            id: "demo-answer-family",
            questionID: "demo-question-yesterday",
            questionPrompt: "昨日いちばん笑ったことは？",
            author: siblingAuthor,
            body: "夕飯のときに昔の写真を見つけて、みんなで笑ったこと。",
            createdAt: Date(timeIntervalSince1970: 1_722_816_000),
            answerDate: "2026-07-27",
            updatedAt: Date(timeIntervalSince1970: 1_722_816_000),
            likeCount: 2,
            commentCount: 2,
            isLikedByMe: false,
            media: galleryMedia
        )
        let ownHistoryAnswer = Answer(
            id: "demo-answer-history",
            questionID: "demo-question-history",
            questionPrompt: "最近、ありがとうと思ったことは？",
            author: currentAuthor,
            body: "忙しい朝に、そっとお茶を入れてくれたこと。",
            createdAt: Date(timeIntervalSince1970: 1_722_729_600),
            answerDate: "2026-07-26",
            updatedAt: Date(timeIntervalSince1970: 1_722_729_600),
            likeCount: 4,
            commentCount: 1,
            isLikedByMe: false
        )
        feedAnswers = [familyAnswer, ownHistoryAnswer]
        historyAnswers = [ownHistoryAnswer]

        commentsByAnswerID = [
            familyAnswer.id: [
                Comment(
                    id: "demo-comment-1",
                    answerID: familyAnswer.id,
                    author: currentAuthor,
                    body: "その写真、今度わたしにも見せて！",
                    createdAt: Date(timeIntervalSince1970: 1_722_819_600)
                ),
                Comment(
                    id: "demo-comment-2",
                    answerID: familyAnswer.id,
                    author: siblingAuthor,
                    body: "もちろん。アルバムにしておくね。",
                    createdAt: Date(timeIntervalSince1970: 1_722_823_200)
                )
            ],
            ownHistoryAnswer.id: [
                Comment(
                    id: "demo-comment-3",
                    answerID: ownHistoryAnswer.id,
                    author: siblingAuthor,
                    body: "こちらこそ、いつもありがとう。",
                    createdAt: Date(timeIntervalSince1970: 1_722_733_200)
                )
            ]
        ]
        for media in galleryMedia {
            mediaContentByURL[media.url] = AnswerMediaContent(
                data: galleryPhotoData,
                mimeType: media.mimeType
            )
        }
    }

    func hasStoredSession() -> Bool {
        isAuthenticated
    }

    func requestOTP(phoneNumber: String) throws -> OTPChallenge {
        guard let phone = PhoneNumberValidation.canonicalE164(phoneNumber) else {
            throw DemoAPIError.invalidInput
        }
        pendingLoginPhone = phone
        return OTPChallenge(requestID: "demo-otp-request", expiresIn: 300)
    }

    func verifyOTP(requestID: String, code: String) throws -> AuthSession {
        guard requestID == "demo-otp-request",
              NumericInputValidation.asciiDigits(in: code) == code,
              code.count == 6 else {
            throw DemoAPIError.invalidCode
        }
        guard let pendingLoginPhone,
              var returningProfile = family.members.first(where: { member in
                  member.phoneNumber.flatMap {
                      PhoneNumberValidation.canonicalE164($0)
                  } == pendingLoginPhone
              }) else {
            throw DemoAPIError.accountNotFound
        }
        self.pendingLoginPhone = nil
        returningProfile.family = family
        profile = returningProfile
        isAuthenticated = true
        return demoSession
    }

    func requestPhoneEnrollment(
        phoneNumber: String
    ) async throws -> OTPChallenge {
        try requireAuthentication()
        guard let phone = PhoneNumberValidation.canonicalE164(phoneNumber) else {
            throw DemoAPIError.invalidInput
        }
        let requestID = "demo-phone-enrollment"
        pendingPhoneEnrollment = (requestID, phone)
        return OTPChallenge(requestID: requestID, expiresIn: 300)
    }

    func verifyPhoneEnrollment(
        requestID: String,
        code: String
    ) async throws -> UserProfile {
        try requireAuthentication()
        guard let pendingPhoneEnrollment,
              pendingPhoneEnrollment.requestID == requestID,
              NumericInputValidation.asciiDigits(in: code) == code,
              code.count == 6 else {
            throw DemoAPIError.invalidCode
        }
        profile.phoneNumber = pendingPhoneEnrollment.phone
        profile.hasPhone = true
        recoverableMemberIDs.insert(profile.id)
        self.pendingPhoneEnrollment = nil
        if let index = family.members.firstIndex(where: { $0.id == profile.id }) {
            family.members[index].phoneNumber = profile.phoneNumber
            family.members[index].hasPhone = true
        }
        profile.family = hasFamily ? family : nil
        return profile
    }

    func createAccountRecoveryCode() async throws -> AccountRecoveryCode {
        try requireAuthentication()
        let rawCode = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let recoveryCode = AccountRecoveryCode(
            code: rawCode,
            expiresAt: Date().addingTimeInterval(30 * 24 * 60 * 60)
        )
        activeRecoveryCode = recoveryCode
        activeRecoveryMemberID = profile.id
        recoverableMemberIDs.insert(profile.id)
        return recoveryCode
    }

    func recoverAccount(code: String) async throws -> AuthSession {
        let normalizedCode = RecoveryCodeValidation.normalized(code)
        guard RecoveryCodeValidation.isValid(normalizedCode),
              let activeRecoveryCode,
              activeRecoveryCode.expiresAt > Date(),
              activeRecoveryCode.code == normalizedCode,
              let activeRecoveryMemberID,
              var recoveredProfile = family.members.first(where: {
                  $0.id == activeRecoveryMemberID
              }) else {
            throw DemoAPIError.invalidRecoveryCode
        }
        self.activeRecoveryCode = nil
        self.activeRecoveryMemberID = nil
        recoveredProfile.family = family
        profile = recoveredProfile
        if recoveredProfile.hasPhone != true {
            // A one-time recovery code stops being an available recovery path
            // once consumed. Phone enrollment remains durable.
            recoverableMemberIDs.remove(recoveredProfile.id)
        }
        isAuthenticated = true
        return demoSession
    }

    func fetchMe() throws -> UserProfile {
        try requireAuthentication()
        return profile
    }

    func updateProfile(displayName: String) throws -> UserProfile {
        try requireAuthentication()
        let displayName = try validatedName(displayName)
        profile.displayName = displayName
        if let memberIndex = family.members.firstIndex(where: {
            $0.id == profile.id
        }) {
            family.members[memberIndex].displayName = displayName
        }
        profile.family = hasFamily ? family : nil
        updateAuthorName(displayName)
        return profile
    }

    func fetchFamily() throws -> FamilySummary {
        try requireAuthentication()
        guard hasFamily else { throw DemoAPIError.notFound }
        return family
    }

    func renameFamily(name: String) async throws -> FamilySummary {
        try requireOwner()
        let name = try validatedName(name)
        family.name = name
        profile.family = family
        for pairingID in Array(pairingsByID.keys) {
            pairingsByID[pairingID]?.family.name = name
        }
        return family
    }

    func createOrganizerFamily(
        organizerName: String,
        familyName: String
    ) async throws -> AuthSession {
        let organizerName = try validatedName(organizerName)
        let familyName = try validatedName(familyName)

        profile.displayName = organizerName
        profile.phoneNumber = nil
        profile.hasPhone = false
        profile.managed = false
        profile.familyRole = .owner
        profile.joinedAt = Date()
        profile.family = nil
        family = FamilySummary(
            id: "demo-organizer-family",
            name: familyName,
            memberCount: 1,
            inviteCode: nil,
            members: [profile]
        )
        profile.family = family
        pairingsByID = [:]
        activeRecoveryCode = nil
        activeRecoveryMemberID = nil
        activatedMemberIDs = [profile.id]
        recoverableMemberIDs = []
        hasFamily = true
        notificationPreferences.familyID = family.id
        feedAnswers = []
        historyAnswers = []
        commentsByAnswerID = [:]
        todayQuestion.answer = nil
        isAuthenticated = true
        return demoSession
    }

    func addManagedFamilyMember(
        displayName: String
    ) async throws -> UserProfile {
        try requireOwner()
        let displayName = try validatedName(displayName)

        let member = UserProfile(
            id: "demo-managed-member-\(nextManagedMemberID)",
            displayName: displayName,
            avatarURL: nil,
            phoneNumber: nil,
            family: nil,
            hasPhone: false,
            managed: true,
            familyRole: .member,
            joinedAt: Date(),
            createdAt: Date()
        )
        nextManagedMemberID += 1
        family.members.append(member)
        family.memberCount = family.members.count
        profile.family = family
        return member
    }

    func renameManagedFamilyMember(
        memberID: String,
        displayName: String
    ) async throws -> UserProfile {
        try requireOwner()
        let displayName = try validatedName(displayName)
        guard let index = family.members.firstIndex(where: {
                  $0.id == memberID && $0.managed == true
              }) else {
            throw DemoAPIError.invalidInput
        }
        family.members[index].displayName = displayName
        if profile.id == memberID {
            profile.displayName = displayName
        }
        updateAuthorName(displayName, userID: memberID)
        for pairingID in Array(pairingsByID.keys)
        where pairingsByID[pairingID]?.member.id == memberID {
            pairingsByID[pairingID]?.member.displayName = displayName
        }
        profile.family = family
        return family.members[index]
    }

    func removeManagedFamilyMember(memberID: String) async throws {
        try requireOwner()
        guard let member = family.members.first(where: {
            $0.id == memberID && $0.managed == true
        }) else {
            throw DemoAPIError.notFound
        }
        family.members.removeAll(where: { $0.id == member.id })
        activatedMemberIDs.remove(member.id)
        recoverableMemberIDs.remove(member.id)
        family.memberCount = family.members.count
        pairingsByID = pairingsByID.filter { $0.value.member.id != member.id }

        let removedAnswerIDs = Set(
            (feedAnswers + historyAnswers)
                .filter { $0.author.id == member.id }
                .map(\.id)
        )
        feedAnswers.removeAll(where: { removedAnswerIDs.contains($0.id) })
        historyAnswers.removeAll(where: { removedAnswerIDs.contains($0.id) })
        for answerID in removedAnswerIDs {
            commentsByAnswerID[answerID] = nil
        }
        for answerID in Array(commentsByAnswerID.keys) {
            let oldCount = commentsByAnswerID[answerID]?.count ?? 0
            commentsByAnswerID[answerID]?.removeAll(where: {
                $0.author.id == member.id
            })
            let removedCount = oldCount - (commentsByAnswerID[answerID]?.count ?? 0)
            if removedCount > 0 {
                updateCommentCount(for: answerID, by: -removedCount)
            }
        }
        reportsByCommentID = reportsByCommentID.filter { report in
            commentsByAnswerID.values.joined().contains(where: {
                $0.id == report.key
            })
        }
        profile.family = family
    }

    func transferFamilyOwnership(
        to memberID: String
    ) async throws -> FamilySummary {
        try requireOwner()
        guard let newOwnerIndex = family.members.firstIndex(where: {
            $0.id == memberID
        }), activatedMemberIDs.contains(memberID),
              isMemberRecoverable(memberID) else {
            throw DemoAPIError.invalidInput
        }
        family.members[newOwnerIndex].managed = false
        for index in family.members.indices {
            family.members[index].familyRole = index == newOwnerIndex
                ? .owner
                : .member
        }
        profile.familyRole = profile.id == memberID ? .owner : .member
        profile.family = family
        return family
    }

    func leaveFamily() async throws -> FamilyLeaveResult {
        try requireAuthentication()
        guard hasFamily, profile.familyRole != .owner else {
            throw DemoAPIError.ownerCannotLeave
        }

        if profile.managed == true {
            family.members.removeAll(where: { $0.id == profile.id })
            family.memberCount = family.members.count
            isAuthenticated = false
            hasFamily = false
            pairingsByID = [:]
            pendingPhoneEnrollment = nil
            activeRecoveryCode = nil
            activeRecoveryMemberID = nil
            notificationPreferences.familyID = nil
            return FamilyLeaveResult(accountDeleted: true)
        }

        let leavingUserID = profile.id
        let removedAnswerIDs = Set(
            (feedAnswers + historyAnswers)
                .filter { $0.author.id == leavingUserID }
                .map(\.id)
        )
        feedAnswers.removeAll(where: { removedAnswerIDs.contains($0.id) })
        historyAnswers.removeAll(where: { removedAnswerIDs.contains($0.id) })
        if let answer = todayQuestion.answer,
           removedAnswerIDs.contains(answer.id) {
            todayQuestion.answer = nil
        }
        for answerID in removedAnswerIDs {
            commentsByAnswerID[answerID] = nil
        }
        for answerID in Array(commentsByAnswerID.keys) {
            let oldCount = commentsByAnswerID[answerID]?.count ?? 0
            commentsByAnswerID[answerID]?.removeAll(where: {
                $0.author.id == leavingUserID
            })
            let removedCount = oldCount - (commentsByAnswerID[answerID]?.count ?? 0)
            if removedCount > 0 {
                updateCommentCount(for: answerID, by: -removedCount)
            }
        }
        reportsByCommentID = reportsByCommentID.filter { report in
            commentsByAnswerID.values.joined().contains(where: {
                $0.id == report.key
            })
        }

        // The replacement family must never inherit content from the family
        // that was just left, including answers authored by other members.
        feedAnswers = []
        historyAnswers = []
        commentsByAnswerID = [:]
        reportsByCommentID = [:]
        mediaContentByURL = [:]
        todayQuestion.answer = nil

        profile.managed = false
        profile.familyRole = .owner
        profile.joinedAt = Date()
        var replacementMember = profile
        replacementMember.family = nil
        family = FamilySummary(
            id: "demo-personal-family",
            name: "わたしの家族",
            memberCount: 1,
            inviteCode: "PERSONAL",
            members: [replacementMember]
        )
        profile.family = family
        hasFamily = true
        pairingsByID = [:]
        notificationPreferences = NotificationPreferences(familyID: family.id)
        return FamilyLeaveResult(accountDeleted: false)
    }

    func createFamilyPairing(
        memberID: String
    ) async throws -> FamilyPairing {
        try requireOwner()
        guard let member = family.members.first(where: {
            $0.id == memberID && $0.managed == true
        }) else {
            throw DemoAPIError.notFound
        }
        expireStalePairings()
        for pairingID in Array(pairingsByID.keys) {
            guard var existingPairing = pairingsByID[pairingID],
                  existingPairing.member.id == memberID,
                  existingPairing.status == .pending else {
                continue
            }
            existingPairing.status = .revoked
            pairingsByID[pairingID] = existingPairing
        }

        let pairingID = "demo-pairing-\(nextPairingID)"
        let code = String(format: "%06d", nextPairingID % 1_000_000)
        let token = (
            UUID().uuidString.replacingOccurrences(of: "-", with: "")
                + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        )
        let pairingURL = URL(
            string: "https://kttprojects.conohawing.com/tsutsuura-api/api/invite/\(token)"
        )!
        let now = Date()
        let expiresAt = ProcessInfo.processInfo.arguments.contains(
            "-tsutsuura-demo-expired-pairing"
        )
            ? now.addingTimeInterval(-1)
            : now.addingTimeInterval(10 * 60)
        let pairing = FamilyPairing(
            id: pairingID,
            code: code,
            token: token,
            pairingURL: pairingURL,
            expiresAt: expiresAt,
            createdAt: now,
            status: .pending,
            member: FamilyPairingMemberPreview(
                id: member.id,
                displayName: member.displayName
            ),
            family: FamilyPairingFamilyPreview(
                id: family.id,
                name: family.name
            )
        )
        nextPairingID += 1
        pairingsByID[pairing.id] = pairing
        return pairing
    }

    func previewFamilyPairing(
        _ credential: FamilyPairingCredential
    ) async throws -> FamilyPairingPreview {
        expireStalePairings()
        guard let pairing = pairing(matching: credential),
              pairing.status == .pending else {
            throw DemoAPIError.pairingUnavailable
        }
        var preview = pairing.preview
        preview.createdAt = nil
        return preview
    }

    func activateFamilyPairing(
        _ credential: FamilyPairingCredential
    ) async throws -> AuthSession {
        expireStalePairings()
        guard var pairing = pairing(matching: credential),
              pairing.status == .pending,
              let memberIndex = family.members.firstIndex(where: {
                  $0.id == pairing.member.id
              }) else {
            throw DemoAPIError.pairingUnavailable
        }

        pairing.status = .consumed
        pairingsByID[pairing.id] = pairing
        profile = family.members[memberIndex]
        profile.family = family
        activatedMemberIDs.insert(profile.id)
        hasFamily = true
        notificationPreferences.familyID = family.id
        isAuthenticated = true
        return demoSession
    }

    func fetchFamilyPairings() async throws -> [FamilyPairingPreview] {
        try requireAuthentication()
        expireStalePairings()
        return pairingsByID.values
            .map(\.preview)
            .sorted {
                ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
    }

    func revokeFamilyPairing(pairingID: String) async throws {
        try requireAuthentication()
        guard var pairing = pairingsByID[pairingID] else {
            throw DemoAPIError.notFound
        }
        if pairing.status == .revoked {
            return
        }
        guard pairing.status != .consumed else {
            throw DemoAPIError.pairingUnavailable
        }
        pairing.status = .revoked
        pairingsByID[pairingID] = pairing
    }

    func fetchHome(cursor: String?) throws -> HomeFeed {
        try requireAuthentication()
        return HomeFeed(
            family: hasFamily ? family : nil,
            todayQuestion: todayQuestion,
            myAnswer: todayQuestion.answer,
            answers: hasFamily ? feedAnswers : [],
            nextCursor: nil
        )
    }

    func fetchTodayQuestion() throws -> Question {
        try requireAuthentication()
        return todayQuestion
    }

    func fetchAnswer(answerID: String) async throws -> Answer {
        try requireAuthentication()
        guard let answer = answer(withID: answerID) else {
            throw DemoAPIError.notFound
        }
        return answer
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
        try requireAuthentication()
        guard questionID == todayQuestion.id else {
            throw DemoAPIError.invalidInput
        }
        try submission.validate()

        mediaContentByURL.removeAll()
        var answerMedia: [AnswerMedia] = []
        if let audio = submission.voiceRecording {
            let media = demoMedia(
                id: "demo-media-audio",
                kind: .audio,
                upload: audio
            )
            answerMedia.append(media)
            mediaContentByURL[media.url] = AnswerMediaContent(
                data: audio.data,
                mimeType: audio.mimeType
            )
        }
        for (index, photo) in submission.photos.enumerated() {
            let media = demoMedia(
                id: "demo-media-photo-\(index + 1)",
                kind: .photo,
                upload: photo
            )
            answerMedia.append(media)
            mediaContentByURL[media.url] = AnswerMediaContent(
                data: photo.data,
                mimeType: photo.mimeType
            )
        }

        let answer = Answer(
            id: "demo-answer-today",
            questionID: todayQuestion.id,
            questionPrompt: todayQuestion.prompt,
            author: AnswerAuthor(
                id: profile.id,
                displayName: profile.displayName,
                avatarURL: profile.avatarURL
            ),
            body: submission.body,
            createdAt: Date(),
            answerDate: todayQuestion.publishedOn,
            updatedAt: Date(),
            likeCount: 0,
            commentCount: 0,
            isLikedByMe: false,
            media: answerMedia
        )
        todayQuestion.answer = answer
        feedAnswers.removeAll(where: { $0.id == answer.id })
        feedAnswers.insert(answer, at: 0)
        historyAnswers.removeAll(where: { $0.id == answer.id })
        historyAnswers.insert(answer, at: 0)
        return answer
    }

    func updateAnswer(
        answerID: String,
        submission: AnswerSubmission
    ) async throws -> Answer {
        try requireAuthentication()
        guard var answer = answer(withID: answerID),
              answer.author.id == profile.id else {
            throw DemoAPIError.notFound
        }
        guard !submission.hasMedia else {
            throw APIClientError.unsupportedOperation
        }
        guard UnicodeTextValidation.characterCount(
            submission.body.trimmingCharacters(in: .whitespacesAndNewlines)
        ) <= AnswerDraft.maximumBodyCharacterCount else {
            throw DemoAPIError.invalidInput
        }
        if submission.body.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty && answer.media.isEmpty {
            throw DemoAPIError.invalidInput
        }
        answer.body = submission.body
        answer.updatedAt = Date()
        replaceAnswer(answer)
        return answer
    }

    func deleteAnswer(answerID: String) async throws {
        try requireAuthentication()
        guard let answer = answer(withID: answerID),
              answer.author.id == profile.id else {
            throw DemoAPIError.notFound
        }
        for media in answer.media {
            mediaContentByURL[media.url] = nil
        }
        if todayQuestion.answer?.id == answerID {
            todayQuestion.answer = nil
        }
        feedAnswers.removeAll(where: { $0.id == answerID })
        historyAnswers.removeAll(where: { $0.id == answerID })
        commentsByAnswerID[answerID] = nil
    }

    func deleteAnswerMedia(
        answerID: String,
        mediaID: String
    ) async throws -> Answer {
        try requireAuthentication()
        guard var answer = answer(withID: answerID),
              answer.author.id == profile.id,
              let media = answer.media.first(where: { $0.id == mediaID }) else {
            throw DemoAPIError.notFound
        }
        guard !answer.body.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty || answer.media.count > 1 else {
            throw DemoAPIError.invalidInput
        }
        answer.media.removeAll(where: { $0.id == mediaID })
        answer.updatedAt = Date()
        mediaContentByURL[media.url] = nil
        replaceAnswer(answer)
        return answer
    }

    func fetchAnswerMedia(
        _ media: AnswerMedia
    ) async throws -> AnswerMediaContent {
        try requireAuthentication()
        guard let content = mediaContentByURL[media.url] else {
            throw DemoAPIError.notFound
        }
        return content
    }

    func fetchAnswerHistory(cursor: String?) throws -> AnswerPage {
        try requireAuthentication()
        return AnswerPage(answers: historyAnswers, nextCursor: nil)
    }

    func fetchAnswerHistory(
        query: HistoryQuery,
        cursor: String?
    ) async throws -> AnswerPage {
        try requireAuthentication()
        let searchText = HistoryQuery.normalizedSearchText(query.searchText)
        var answers = uniqueAnswers(feedAnswers + historyAnswers)
        if query.scope == .mine {
            answers.removeAll(where: { $0.author.id != profile.id })
        }
        if let authorID = query.authorID {
            answers.removeAll(where: { $0.author.id != authorID })
        }
        if let startDate = query.startDate {
            answers.removeAll(where: { ($0.answerDate ?? "") < startDate })
        }
        if let endDate = query.endDate {
            answers.removeAll(where: { ($0.answerDate ?? "") > endDate })
        }
        if !searchText.isEmpty {
            let search = searchText.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            answers.removeAll { answer in
                let haystack = [
                    answer.body,
                    answer.questionPrompt ?? "",
                    answer.author.displayName,
                ]
                    .joined(separator: "\n")
                    .folding(
                        options: [.caseInsensitive, .diacriticInsensitive],
                        locale: .current
                    )
                return !haystack.contains(search)
            }
        }
        answers.sort {
            if $0.createdAt == $1.createdAt { return $0.id > $1.id }
            return $0.createdAt > $1.createdAt
        }

        let startIndex: Int
        if let cursor,
           let cursorIndex = answers.firstIndex(where: { $0.id == cursor }) {
            startIndex = answers.index(after: cursorIndex)
        } else {
            startIndex = 0
        }
        guard startIndex < answers.count else {
            return AnswerPage(answers: [], nextCursor: nil)
        }
        let endIndex = min(
            startIndex + HistoryQuery.normalizedLimit(query.limit),
            answers.count
        )
        let page = Array(answers[startIndex..<endIndex])
        let nextCursor = endIndex < answers.count ? page.last?.id : nil
        return AnswerPage(answers: page, nextCursor: nextCursor)
    }

    func setLike(answerID: String, isLiked: Bool) throws -> LikeState {
        try requireAuthentication()
        guard var answer = answer(withID: answerID) else {
            throw DemoAPIError.notFound
        }
        guard !isLiked || answer.author.id != profile.id else {
            throw DemoAPIError.selfLikeNotAllowed
        }
        if answer.isLikedByMe != isLiked {
            answer.likeCount = max(0, answer.likeCount + (isLiked ? 1 : -1))
            answer.isLikedByMe = isLiked
            replaceAnswer(answer)
        }
        return LikeState(
            isLikedByMe: answer.isLikedByMe,
            likeCount: answer.likeCount
        )
    }

    func fetchComments(
        answerID: String,
        cursor: String?
    ) throws -> CommentPage {
        try requireAuthentication()
        guard answer(withID: answerID) != nil else {
            throw DemoAPIError.notFound
        }
        return CommentPage(
            comments: commentsByAnswerID[answerID] ?? [],
            nextCursor: nil
        )
    }

    func createComment(answerID: String, body: String) throws -> Comment {
        try requireAuthentication()
        guard answer(withID: answerID) != nil else {
            throw DemoAPIError.invalidInput
        }
        let body = try CommentTextValidation.body(body)
        nextCommentID += 1
        let comment = Comment(
            id: "demo-comment-\(nextCommentID)",
            answerID: answerID,
            author: AnswerAuthor(
                id: profile.id,
                displayName: profile.displayName,
                avatarURL: profile.avatarURL
            ),
            body: body,
            createdAt: Date()
        )
        commentsByAnswerID[answerID, default: []].append(comment)
        updateCommentCount(for: answerID, by: 1)
        return comment
    }

    func replyToComment(
        answerID: String,
        parentCommentID: String,
        body: String
    ) async throws -> Comment {
        try requireAuthentication()
        guard commentsByAnswerID[answerID]?.contains(where: {
            $0.id == parentCommentID
        }) == true else {
            throw DemoAPIError.notFound
        }
        let comment = try createComment(answerID: answerID, body: body)
        var reply = comment
        reply.parentCommentID = parentCommentID
        if let index = commentsByAnswerID[answerID]?.firstIndex(where: {
            $0.id == reply.id
        }) {
            commentsByAnswerID[answerID]?[index] = reply
        }
        return reply
    }

    func updateComment(
        commentID: String,
        body: String
    ) async throws -> Comment {
        try requireAuthentication()
        let body = try CommentTextValidation.body(body)
        for answerID in Array(commentsByAnswerID.keys) {
            guard let index = commentsByAnswerID[answerID]?.firstIndex(where: {
                $0.id == commentID && $0.author.id == profile.id
            }), var comment = commentsByAnswerID[answerID]?[index] else {
                continue
            }
            comment.body = body
            comment.updatedAt = Date()
            commentsByAnswerID[answerID]?[index] = comment
            return comment
        }
        throw DemoAPIError.notFound
    }

    func deleteComment(commentID: String, answerID: String) throws {
        try requireAuthentication()
        guard let index = commentsByAnswerID[answerID]?.firstIndex(
            where: { $0.id == commentID }
        ) else {
            throw DemoAPIError.notFound
        }
        guard commentsByAnswerID[answerID]?[index].author.id == profile.id else {
            throw DemoAPIError.notFound
        }
        commentsByAnswerID[answerID]?.remove(at: index)
        updateCommentCount(for: answerID, by: -1)
    }

    func reportComment(
        commentID: String,
        reason: CommentReportReason,
        details: String?
    ) async throws -> CommentReport {
        try requireAuthentication()
        _ = try CommentTextValidation.reportDetails(details)
        guard commentsByAnswerID.values.joined().contains(where: {
            $0.id == commentID && $0.author.id != profile.id
        }) else {
            throw DemoAPIError.notFound
        }
        if let report = reportsByCommentID[commentID] {
            return report
        }
        let report = CommentReport(
            id: "demo-report-\(nextReportID)",
            commentID: commentID,
            reason: reason,
            status: "pending",
            createdAt: Date()
        )
        nextReportID += 1
        reportsByCommentID[commentID] = report
        return report
    }

    func fetchNotificationPreferences() async throws -> NotificationPreferences {
        try requireAuthentication()
        return notificationPreferences
    }

    func updateNotificationPreferences(
        _ preferences: NotificationPreferences
    ) async throws -> NotificationPreferences {
        try requireAuthentication()
        notificationPreferences = preferences
        return notificationPreferences
    }

    func exportAccount() async throws -> AccountExport {
        try requireAuthentication()
        return AccountExport(
            generatedAt: Date(),
            user: profile,
            family: hasFamily ? family : nil,
            answers: uniqueAnswers(feedAnswers + historyAnswers).filter {
                $0.author.id == profile.id
            }.map(AccountExportAnswer.init(answer:)),
            comments: commentsByAnswerID.values
                .flatMap { $0 }
                .filter { $0.author.id == profile.id }
                .sorted { $0.createdAt < $1.createdAt }
                .map(AccountExportComment.init(comment:)),
            likedAnswerIDs: uniqueAnswers(feedAnswers + historyAnswers)
                .filter(\.isLikedByMe)
                .map(\.id),
            notificationPreferences: notificationPreferences
        )
    }

    func deleteAccount() async throws {
        try requireAuthentication()
        isAuthenticated = false
        hasFamily = false
        feedAnswers.removeAll(where: { $0.author.id == profile.id })
        historyAnswers.removeAll(where: { $0.author.id == profile.id })
        for answerID in Array(commentsByAnswerID.keys) {
            commentsByAnswerID[answerID]?.removeAll(where: {
                $0.author.id == profile.id
            })
        }
        reportsByCommentID = [:]
        pairingsByID = [:]
        pendingPhoneEnrollment = nil
        activeRecoveryCode = nil
        activeRecoveryMemberID = nil
    }

    func registerPushToken(
        _ token: String,
        environment: PushEnvironment
    ) throws {
        try requireAuthentication()
    }

    func unregisterPushToken(tokenHash: String) throws {
        try requireAuthentication()
    }

    func signOut() {
        isAuthenticated = false
    }

    private var demoSession: AuthSession {
        AuthSession(
            accessToken: "demo-access-token",
            expiresAt: Date().addingTimeInterval(86_400),
            user: profile
        )
    }

    private func requireAuthentication() throws {
        guard isAuthenticated else {
            throw APIClientError.unauthorized
        }
    }

    private func requireOwner() throws {
        try requireAuthentication()
        guard hasFamily, profile.familyRole == .owner else {
            throw DemoAPIError.ownerRequired
        }
    }

    private func validatedName(_ value: String) throws -> String {
        let withoutNulls = value.replacingOccurrences(of: "\0", with: "")
        let normalized = withoutNulls
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !normalized.isEmpty,
              NameValidation.characterCount(normalized)
                <= NameValidation.maximumLength else {
            throw DemoAPIError.invalidInput
        }
        return normalized
    }

    private func isMemberRecoverable(_ memberID: String) -> Bool {
        guard recoverableMemberIDs.contains(memberID) else { return false }
        if family.members.first(where: { $0.id == memberID })?.hasPhone == true {
            return true
        }
        if activeRecoveryMemberID == memberID {
            return (activeRecoveryCode?.expiresAt ?? .distantPast) > Date()
        }
        // The seeded fixture represents a member with a previously configured
        // durable recovery path; generated demo codes are tracked explicitly.
        return memberID == "demo-family-1"
    }

    private func pairing(
        matching credential: FamilyPairingCredential
    ) -> FamilyPairing? {
        pairingsByID.values.first { pairing in
            switch credential {
            case .code(let code):
                let normalizedCode = code
                    .filter { !$0.isWhitespace && $0 != "-" }
                return pairing.code == normalizedCode
            case .token(let token):
                return pairing.token == token.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            }
        }
    }

    private func expireStalePairings() {
        let now = Date()
        for pairingID in Array(pairingsByID.keys) {
            guard var pairing = pairingsByID[pairingID],
                  pairing.status == .pending,
                  pairing.expiresAt <= now else {
                continue
            }
            pairing.status = .expired
            pairingsByID[pairingID] = pairing
        }
    }

    private func answer(withID id: String) -> Answer? {
        if todayQuestion.answer?.id == id {
            return todayQuestion.answer
        }
        return feedAnswers.first(where: { $0.id == id })
            ?? historyAnswers.first(where: { $0.id == id })
    }

    private func demoMedia(
        id: String,
        kind: AnswerMediaKind,
        upload: AnswerMediaUpload
    ) -> AnswerMedia {
        AnswerMedia(
            id: id,
            kind: kind,
            url: URL(string: "https://demo.tsutsuura.invalid/media/\(id)")!,
            mimeType: upload.mimeType,
            fileName: AnswerMediaUpload.sanitizedFileName(upload.fileName),
            byteCount: upload.data.count,
            durationMilliseconds: upload.durationMilliseconds
        )
    }

    private func makeDemoMedia(
        from submission: AnswerSubmission,
        answerID: String
    ) -> [AnswerMedia] {
        var result: [AnswerMedia] = []
        let safeAnswerID = answerID.replacingOccurrences(of: "/", with: "-")
        if let audio = submission.voiceRecording {
            let media = demoMedia(
                id: "\(safeAnswerID)-audio-\(UUID().uuidString)",
                kind: .audio,
                upload: audio
            )
            result.append(media)
            mediaContentByURL[media.url] = AnswerMediaContent(
                data: audio.data,
                mimeType: audio.mimeType
            )
        }
        for photo in submission.photos {
            let media = demoMedia(
                id: "\(safeAnswerID)-photo-\(UUID().uuidString)",
                kind: .photo,
                upload: photo
            )
            result.append(media)
            mediaContentByURL[media.url] = AnswerMediaContent(
                data: photo.data,
                mimeType: photo.mimeType
            )
        }
        return result
    }

    private func uniqueAnswers(_ answers: [Answer]) -> [Answer] {
        var seen = Set<String>()
        return answers.filter { seen.insert($0.id).inserted }
    }

    private func replaceAnswer(_ answer: Answer) {
        if todayQuestion.answer?.id == answer.id {
            todayQuestion.answer = answer
        }
        if let index = feedAnswers.firstIndex(where: { $0.id == answer.id }) {
            feedAnswers[index] = answer
        }
        if let index = historyAnswers.firstIndex(where: { $0.id == answer.id }) {
            historyAnswers[index] = answer
        }
    }

    private func updateCommentCount(for answerID: String, by delta: Int) {
        guard var answer = answer(withID: answerID) else { return }
        answer.commentCount = max(0, answer.commentCount + delta)
        replaceAnswer(answer)
    }

    private func updateAuthorName(
        _ displayName: String,
        userID: String? = nil
    ) {
        let targetUserID = userID ?? profile.id
        for index in feedAnswers.indices
        where feedAnswers[index].author.id == targetUserID {
            feedAnswers[index].author.displayName = displayName
        }
        for index in historyAnswers.indices
        where historyAnswers[index].author.id == targetUserID {
            historyAnswers[index].author.displayName = displayName
        }
        for answerID in Array(commentsByAnswerID.keys) {
            var comments = commentsByAnswerID[answerID] ?? []
            for index in comments.indices
            where comments[index].author.id == targetUserID {
                comments[index].author.displayName = displayName
            }
            commentsByAnswerID[answerID] = comments
        }
    }
}

private enum DemoAPIError: LocalizedError {
    case invalidCode
    case invalidInput
    case notFound
    case pairingUnavailable
    case selfLikeNotAllowed
    case ownerRequired
    case ownerCannotLeave
    case invalidRecoveryCode
    case accountNotFound

    var errorDescription: String? {
        switch self {
        case .invalidCode:
            return "デモ用の6桁の認証コードを入力してください。"
        case .invalidInput:
            return "入力内容を確認してください。"
        case .notFound:
            return "デモデータが見つかりません。"
        case .pairingUnavailable:
            return "この招待は利用できません。ご家族に新しい設定番号を送ってもらってください。"
        case .selfLikeNotAllowed:
            return "自分の回答にはいいねできません。"
        case .ownerRequired:
            return "この操作は家族を設定した人だけが行えます。"
        case .ownerCannotLeave:
            return "家族を管理する方を変更してから退出してください。"
        case .invalidRecoveryCode:
            return "復旧コードが正しくないか、有効期限が切れています。"
        case .accountNotFound:
            return "この電話番号に登録されたアカウントが見つかりません。"
        }
    }
}
#endif
