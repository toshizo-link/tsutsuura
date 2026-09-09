import Foundation
import XCTest
@testable import tsutsuura

@MainActor
final class PersonalMarkRequirementTests: XCTestCase {
    private let drawing = "1" + String(repeating: "0", count: 255)

    func testOnlyACompleteBinaryMarkWithAtLeastOneDrawnCellCompletesSetup() {
        let invalidMarks: [String?] = [
            nil, "", String(repeating: "0", count: 256),
            String(repeating: "1", count: 255), String(repeating: "1", count: 257),
            "x" + String(repeating: "0", count: 255),
            "１" + String(repeating: "0", count: 255),
            "1" + String(repeating: "0", count: 254) + "\n"
        ]
        for mark in invalidMarks {
            XCTAssertFalse(PersonalMarkRequirement.hasDrawing(mark))
            XCTAssertTrue(PersonalMarkRequirement.requiresSetup(for: profile(mark: mark)))
        }
        for mark in [drawing, String(repeating: "1", count: 256)] {
            XCTAssertTrue(PersonalMarkRequirement.hasDrawing(mark))
            XCTAssertFalse(PersonalMarkRequirement.requiresSetup(for: profile(mark: mark)))
        }
    }

    func testRestoredAccountsUseTheServerMarkWithoutAskingExistingMembersToRedraw() async {
        for mark in [nil, String(repeating: "0", count: 256), drawing] {
            let api = PersonalMarkTestAPI(profile: profile(mark: mark))
            let store = makeStore(api)
            await store.restoreSession()
            XCTAssertTrue(store.personalMarkRequirementIsConfirmed)
            XCTAssertEqual(store.requiresPersonalMarkSetup, mark != drawing)
            let readsBeforeConfirmation = await api.profileReadCount
            await store.confirmPersonalMarkRequirement()
            let readsAfterConfirmation = await api.profileReadCount
            XCTAssertEqual(readsAfterConfirmation, readsBeforeConfirmation)
        }
    }

    func testSignedOutAccountDoesNotShowDrawingSetup() async {
        let store = makeStore(PersonalMarkTestAPI(profile: profile()))
        await store.restoreSession()
        XCTAssertTrue(store.requiresPersonalMarkSetup)
        await store.signOut()
        XCTAssertFalse(store.requiresPersonalMarkSetup)
        XCTAssertFalse(store.personalMarkRequirementIsConfirmed)
    }

    func testBlankAndInvalidSavesNeverReachTheServerOrReleaseTheGate() async {
        let api = PersonalMarkTestAPI(profile: profile())
        let store = makeStore(api)
        await store.restoreSession()
        for mark in [nil, "", String(repeating: "0", count: 256), "1"] {
            let saved = await store.updatePersonalMark(mark)
            XCTAssertFalse(saved)
            XCTAssertTrue(store.requiresPersonalMarkSetup)
        }
        let saveCount = await api.markSaveCount
        XCTAssertEqual(saveCount, 0)
    }

    func testFailedSaveKeepsSetupRequiredAndAValidRetryCompletesIt() async {
        let api = PersonalMarkTestAPI(profile: profile())
        let store = makeStore(api)
        await store.restoreSession()
        await api.failNextMarkSave()
        let failed = await store.updatePersonalMark(drawing)
        XCTAssertFalse(failed)
        XCTAssertTrue(store.requiresPersonalMarkSetup)
        XCTAssertNil(signedInProfile(store)?.avatarMark)
        XCTAssertNotNil(store.globalErrorMessage)

        let saved = await store.updatePersonalMark(drawing)
        XCTAssertTrue(saved)
        XCTAssertTrue(store.personalMarkRequirementIsConfirmed)
        XCTAssertFalse(store.requiresPersonalMarkSetup)
        XCTAssertEqual(signedInProfile(store)?.avatarMark, drawing)
        XCTAssertNil(store.globalErrorMessage, "A successful retry must remove its earlier error toast.")
    }

    func testSuccessfulSavePreservesANewerErrorShownWhileSaving() async {
        let api = PersonalMarkTestAPI(profile: profile())
        let store = makeStore(api)
        await store.restoreSession()
        let entered = expectation(description: "mark save started before newer error")
        await api.deferNextMarkSave { entered.fulfill() }
        let saving = Task { await store.updatePersonalMark(drawing) }
        await fulfillment(of: [entered], timeout: 2)

        let renamed = await store.updateDisplayName("新しい名前")
        XCTAssertFalse(renamed)
        let newerError = store.globalErrorMessage
        XCTAssertNotNil(newerError)
        await api.finishMarkSave()
        let saved = await saving.value
        XCTAssertTrue(saved)
        XCTAssertEqual(store.globalErrorMessage, newerError)
    }

    func testSuccessfulResponseMustConfirmTheExactDrawingAndAccount() async {
        for response in [profile(mark: nil), profile(mark: String(repeating: "1", count: 256)),
                         profile(id: "another-member", mark: drawing)] {
            let api = PersonalMarkTestAPI(profile: profile())
            let store = makeStore(api)
            await store.restoreSession()
            await api.setMarkSaveResponse(response)
            let saved = await store.updatePersonalMark(drawing)
            XCTAssertFalse(saved)
            XCTAssertTrue(store.requiresPersonalMarkSetup)
            XCTAssertEqual(signedInProfile(store)?.id, "member")
            XCTAssertNil(signedInProfile(store)?.avatarMark)
        }
    }

    func testReplayedBlankAuthenticationReceiptUsesFreshProfileBeforeRequestingDrawing() async {
        let api = PersonalMarkTestAPI(profile: profile(mark: drawing), receipt: profile())
        let store = makeStore(api)
        await createOrganizer(store)
        XCTAssertTrue(store.requiresPersonalMarkSetup)
        XCTAssertFalse(store.personalMarkRequirementIsConfirmed)
        XCTAssertNil(signedInProfile(store)?.avatarMark)

        await store.confirmPersonalMarkRequirement()
        XCTAssertTrue(store.personalMarkRequirementIsConfirmed)
        XCTAssertFalse(store.requiresPersonalMarkSetup)
        XCTAssertEqual(signedInProfile(store)?.avatarMark, drawing)
    }

    func testDrawingInAuthenticationReceiptCannotBypassFreshProfileConfirmation() async {
        let api = PersonalMarkTestAPI(profile: profile(), receipt: profile(mark: drawing))
        let store = makeStore(api)
        await createOrganizer(store)
        XCTAssertTrue(store.requiresPersonalMarkSetup)
        XCTAssertFalse(store.personalMarkRequirementIsConfirmed)
        await store.confirmPersonalMarkRequirement()
        XCTAssertTrue(store.personalMarkRequirementIsConfirmed)
        XCTAssertTrue(store.requiresPersonalMarkSetup)
        XCTAssertNil(signedInProfile(store)?.avatarMark)
    }

    func testFailedProfileConfirmationKeepsGateClosedAndCanBeRetried() async {
        let api = PersonalMarkTestAPI(profile: profile(mark: drawing), receipt: profile())
        let store = makeStore(api)
        await createOrganizer(store)
        await api.failNextProfileRead()
        await store.confirmPersonalMarkRequirement()
        XCTAssertTrue(store.requiresPersonalMarkSetup)
        XCTAssertFalse(store.personalMarkRequirementIsConfirmed)
        XCTAssertNotNil(store.personalMarkRequirementError)
        XCTAssertFalse(store.isCheckingPersonalMarkRequirement)

        await store.confirmPersonalMarkRequirement()
        XCTAssertFalse(store.requiresPersonalMarkSetup)
        XCTAssertNil(store.personalMarkRequirementError)
    }

    func testDelayedForegroundRefreshCannotRestoreTheBlankMarkAfterSave() async {
        let api = PersonalMarkTestAPI(profile: profile())
        let store = makeStore(api)
        await store.restoreSession()
        let entered = expectation(description: "foreground refresh captured old profile")
        await api.deferNextProfileRead { entered.fulfill() }
        let refresh = Task { await store.refreshHome() }
        await fulfillment(of: [entered], timeout: 2)

        let saved = await store.updatePersonalMark(drawing)
        XCTAssertTrue(saved)
        await api.finishProfileRead()
        await refresh.value
        XCTAssertEqual(signedInProfile(store)?.avatarMark, drawing)
        XCTAssertFalse(store.requiresPersonalMarkSetup)
        XCTAssertFalse(store.home.isLoading)
    }

    func testLateSaveCannotReleaseSetupForAnotherAccountOrANewSessionOfTheSameAccount() async {
        for nextActorID in ["member", "another-member"] {
            let api = PersonalMarkTestAPI(profile: profile())
            let store = makeStore(api)
            await store.restoreSession()
            let entered = expectation(description: "old session mark save started")
            await api.deferNextMarkSave { entered.fulfill() }
            let saving = Task { await store.updatePersonalMark(drawing) }
            await fulfillment(of: [entered], timeout: 2)

            await store.signOut()
            await api.setProfile(profile(id: nextActorID))
            await store.restoreSession()
            XCTAssertTrue(store.requiresPersonalMarkSetup)
            await api.finishMarkSave()
            let saved = await saving.value
            XCTAssertFalse(saved)
            XCTAssertEqual(signedInProfile(store)?.id, nextActorID)
            XCTAssertNil(signedInProfile(store)?.avatarMark)
            XCTAssertTrue(store.requiresPersonalMarkSetup)
        }
    }

    func testLateProfileConfirmationCannotChangeTheNewAccount() async {
        let api = PersonalMarkTestAPI(profile: profile(mark: drawing), receipt: profile())
        let store = makeStore(api)
        await createOrganizer(store)
        let entered = expectation(description: "old account profile confirmation started")
        await api.deferNextProfileRead { entered.fulfill() }
        let confirmation = Task { await store.confirmPersonalMarkRequirement() }
        await fulfillment(of: [entered], timeout: 2)
        await store.signOut()
        await api.setProfile(profile(id: "another-member"))
        await store.restoreSession()
        await api.finishProfileRead()
        await confirmation.value
        XCTAssertEqual(signedInProfile(store)?.id, "another-member")
        XCTAssertNil(signedInProfile(store)?.avatarMark)
        XCTAssertTrue(store.requiresPersonalMarkSetup)
        XCTAssertFalse(store.isCheckingPersonalMarkRequirement)
    }

    private func profile(id: String = "member", mark: String? = nil) -> UserProfile {
        UserProfile(id: id, displayName: "家族", avatarURL: nil,
                    phoneNumber: nil, family: nil, avatarMark: mark)
    }

    private func makeStore(_ api: PersonalMarkTestAPI) -> AppStore {
        AppStore(api: api, haptics: NoopHaptics())
    }

    private func signedInProfile(_ store: AppStore) -> UserProfile? {
        guard case .signedIn(let profile) = store.session else { return nil }
        return profile
    }

    private func createOrganizer(_ store: AppStore) async {
        store.familySetup.organizerName = "家族"
        store.familySetup.familyName = "家族の部屋"
        await store.createOrganizerFamily()
        XCTAssertNotNil(signedInProfile(store))
    }
}

/// Captures response snapshots before suspending, like a real request that
/// finishes after another save, sign-out, or account restore has completed.
private actor PersonalMarkTestAPI: AppAPI {
    private var profile: UserProfile
    private let receipt: UserProfile?
    private var markSaveResponse: UserProfile?
    private var markSaveFails = false
    private var profileReadFails = false
    private var onProfileRead: (@Sendable () -> Void)?
    private var onMarkSave: (@Sendable () -> Void)?
    private var pendingProfileRead: CheckedContinuation<UserProfile, Never>?
    private var pendingMarkSave: CheckedContinuation<UserProfile, Never>?
    private var profileReadSnapshot: UserProfile?
    private var markSaveSnapshot: UserProfile?
    private(set) var profileReadCount = 0
    private(set) var markSaveCount = 0

    init(profile: UserProfile, receipt: UserProfile? = nil) {
        self.profile = profile
        self.receipt = receipt
    }

    func setProfile(_ value: UserProfile) { profile = value }
    func setMarkSaveResponse(_ value: UserProfile) { markSaveResponse = value }
    func failNextMarkSave() { markSaveFails = true }
    func failNextProfileRead() { profileReadFails = true }
    func deferNextProfileRead(_ onStart: @escaping @Sendable () -> Void) { onProfileRead = onStart }
    func deferNextMarkSave(_ onStart: @escaping @Sendable () -> Void) { onMarkSave = onStart }
    func finishProfileRead() {
        if let profileReadSnapshot { pendingProfileRead?.resume(returning: profileReadSnapshot) }
        pendingProfileRead = nil
        profileReadSnapshot = nil
    }
    func finishMarkSave() {
        if let markSaveSnapshot { pendingMarkSave?.resume(returning: markSaveSnapshot) }
        pendingMarkSave = nil
        markSaveSnapshot = nil
    }

    func hasStoredSession() -> Bool { true }
    func fetchMe() async throws -> UserProfile {
        profileReadCount += 1
        if profileReadFails {
            profileReadFails = false
            throw APIClientError.transport(URLError(.notConnectedToInternet))
        }
        if let onStart = onProfileRead {
            onProfileRead = nil
            profileReadSnapshot = profile
            return await withCheckedContinuation {
                pendingProfileRead = $0
                onStart()
            }
        }
        return profile
    }
    func updatePersonalMark(_ mark: String?) async throws -> UserProfile {
        markSaveCount += 1
        if markSaveFails {
            markSaveFails = false
            throw APIClientError.transport(URLError(.notConnectedToInternet))
        }
        var response = profile
        response.avatarMark = mark
        if let markSaveResponse { response = markSaveResponse }
        if let onStart = onMarkSave {
            onMarkSave = nil
            markSaveSnapshot = response
            return await withCheckedContinuation {
                pendingMarkSave = $0
                onStart()
            }
        }
        profile = response
        return response
    }
    func createOrganizerFamily(organizerName: String, familyName: String) -> AuthSession {
        AuthSession(accessToken: "test-only", user: receipt ?? profile)
    }
    func fetchFamily() -> FamilySummary {
        FamilySummary(id: "family", name: "家族の部屋", memberCount: 1, members: [receipt ?? profile])
    }
    func fetchFamilyPairings() -> [FamilyPairingPreview] { [] }
    func fetchHome(cursor: String?) -> HomeFeed { HomeFeed() }
    func signOut() {}

    func requestOTP(phoneNumber: String) throws -> OTPChallenge { throw APIClientError.unsupportedOperation }
    func verifyOTP(requestID: String, code: String) throws -> AuthSession { throw APIClientError.unsupportedOperation }
    func updateProfile(displayName: String) throws -> UserProfile { throw APIClientError.unsupportedOperation }
    func fetchTodayQuestion() throws -> Question { throw APIClientError.unsupportedOperation }
    func submitAnswer(questionID: String, body: String) throws -> Answer { throw APIClientError.unsupportedOperation }
    func fetchAnswerHistory(cursor: String?) throws -> AnswerPage { throw APIClientError.unsupportedOperation }
    func setLike(answerID: String, isLiked: Bool) throws -> LikeState { throw APIClientError.unsupportedOperation }
    func fetchComments(answerID: String, cursor: String?) throws -> CommentPage { throw APIClientError.unsupportedOperation }
    func createComment(answerID: String, body: String) throws -> Comment { throw APIClientError.unsupportedOperation }
    func deleteComment(commentID: String, answerID: String) throws { throw APIClientError.unsupportedOperation }
    func registerPushToken(_ token: String, environment: PushEnvironment) throws { throw APIClientError.unsupportedOperation }
    func unregisterPushToken(tokenHash: String) throws { throw APIClientError.unsupportedOperation }
}
