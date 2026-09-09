import Foundation
import XCTest
@testable import tsutsuura

@MainActor
final class PushRegistrationRecoveryTests: XCTestCase {
    func testFailedDestinationRetriesOnNextForegroundAttempt() async throws {
        let suite = "push-destination-retry-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let pending = PendingPushDestinationStore(defaults: defaults, storageKey: "destination")
        let destination = AppPushDestination.todayQuestion(questionID: "today")
        await pending.save(destination)
        let coordinator = PushDestinationCoordinator()
        var attempts = 0

        await coordinator.consume(from: pending, isAvailable: { true }) { _ in
            attempts += 1
            return false
        }
        let retained = await pending.peek()
        XCTAssertEqual(retained, destination)
        XCTAssertEqual(attempts, 1, "An offline destination must not spin in a retry loop")

        await coordinator.consume(from: pending, isAvailable: { true }) { _ in
            attempts += 1
            return true
        }
        let completed = await pending.peek()
        XCTAssertNil(completed)
        XCTAssertEqual(attempts, 2)
    }

    func testNewNotificationWaitsForInFlightDestinationThenOpensLast() async throws {
        for firstSucceeds in [true, false] {
            let suite = "push-destination-order-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let pending = PendingPushDestinationStore(defaults: defaults, storageKey: "destination")
            let first = AppPushDestination.familyAnswer(answerID: "first")
            let latest = AppPushDestination.comments(answerID: "latest", commentID: "comment")
            let coordinator = PushDestinationCoordinator()
            let entered = expectation(description: "older destination starts")
            let gate = PushUploadGate()
            var opened: [AppPushDestination] = []
            await pending.save(first)

            let task = Task {
                await coordinator.consume(from: pending, isAvailable: { true }) { destination in
                    opened.append(destination)
                    if destination == first { entered.fulfill(); return await gate.wait() }
                    return true
                }
            }
            await fulfillment(of: [entered], timeout: 2)
            await pending.save(latest)
            await coordinator.consume(from: pending, isAvailable: { true }) { _ in
                XCTFail("Concurrent notification callback must share the existing drain")
                return true
            }
            XCTAssertEqual(opened, [first])
            gate.finish(firstSucceeds)
            await task.value

            XCTAssertEqual(opened, [first, latest])
            let remaining = await pending.peek()
            XCTAssertNil(remaining)
        }
    }

    func testLosingSignedInAvailabilityKeepsDestinationPending() async throws {
        let suite = "push-destination-signout-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let pending = PendingPushDestinationStore(defaults: defaults, storageKey: "destination")
        let destination = AppPushDestination.familyAnswer(answerID: "answer")
        await pending.save(destination)
        let coordinator = PushDestinationCoordinator()
        var isSignedIn = true
        await coordinator.consume(from: pending, isAvailable: { isSignedIn }) { _ in
            isSignedIn = false
            return true
        }
        let retained = await pending.peek()
        XCTAssertEqual(retained, destination)
    }

    func testLatePushAnswerAfterSignOutCannotRepopulateFeedOrNavigate() async throws {
        let entered = expectation(description: "answer destination request started")
        let transport = DeferredPushDestinationTransport(delayedEndpoint: "answer", onStart: { entered.fulfill() })
        let store = try destinationStore(transport: transport)
        await store.restoreSession()
        let task = Task { await store.openPushAnswer(answerID: "answer") }
        await fulfillment(of: [entered], timeout: 2)
        await store.signOut()
        await transport.finish()
        let didOpen = await task.value
        XCTAssertFalse(didOpen)
        XCTAssertEqual(store.session, .signedOut)
        XCTAssertEqual(store.path, [.onboarding])
        XCTAssertNil(store.home.feed)
        XCTAssertTrue(store.commentThreads.isEmpty)
        XCTAssertNil(store.globalErrorMessage)
    }

    func testLatePushCommentAfterSignOutCannotRestoreOldThread() async throws {
        let entered = expectation(description: "comment destination request started")
        let transport = DeferredPushDestinationTransport(delayedEndpoint: "comments", onStart: { entered.fulfill() })
        let store = try destinationStore(transport: transport)
        await store.restoreSession()
        let task = Task { await store.openPushAnswer(answerID: "answer", targetCommentID: "comment") }
        await fulfillment(of: [entered], timeout: 2)
        await store.signOut()
        await transport.finish()
        let didOpen = await task.value
        XCTAssertFalse(didOpen)
        XCTAssertEqual(store.path, [.onboarding])
        XCTAssertTrue(store.commentThreads.isEmpty)
        XCTAssertNil(store.globalErrorMessage)
    }

    func testLateQuestionPushAfterSignOutCannotRestorePreviousQuestion() async throws {
        let entered = expectation(description: "question destination request started")
        let transport = DeferredPushDestinationTransport(delayedEndpoint: "today", onStart: { entered.fulfill() })
        let store = try destinationStore(transport: transport)
        await store.restoreSession()
        let task = Task { await store.loadTodayQuestionForPush(expectedQuestionID: "question") }
        await fulfillment(of: [entered], timeout: 2)
        await store.signOut()
        await transport.finish()
        let resolution = await task.value
        XCTAssertEqual(resolution, .retryable)
        XCTAssertNil(store.question.question)
        XCTAssertFalse(store.question.isLoading)
        XCTAssertEqual(store.path, [.onboarding])
        XCTAssertNil(store.globalErrorMessage)
    }

    private func destinationStore(transport: DeferredPushDestinationTransport) throws -> AppStore {
        AppStore(
            api: DefaultAppAPI(
                configuration: try APIConfiguration(baseURL: APIConfiguration.productionBaseURL),
                transport: transport,
                tokenStore: InMemoryTokenStore(token: "account-bearer"),
                retryPolicy: .disabled,
                mutationProtectionKey: Data(repeating: 1, count: 32)
            ),
            haptics: NoopHaptics()
        )
    }

    func testLateNotificationPreferencesCannotRestoreSignedOutAccountState() async throws {
        for saves in [false, true] {
            let entered = expectation(description: "notification preferences request started")
            let transport = DeferredPushDestinationTransport(delayedEndpoint: "notification-preferences", onStart: { entered.fulfill() })
            let store = try destinationStore(transport: transport)
            await store.restoreSession()
            let task = Task {
                if saves { return await store.updateNotificationPreferences(NotificationPreferences()) }
                await store.loadNotificationPreferences()
                return false
            }
            await fulfillment(of: [entered], timeout: 2)
            await store.signOut()
            await transport.finish()
            let didSave = await task.value
            XCTAssertFalse(didSave)
            XCTAssertEqual(store.notificationPreferences, NotificationPreferencesFeatureState())
            XCTAssertEqual(store.session, .signedOut)
        }
    }

    func testReturningFromSettingsAfterDenialRegistersWithoutReopeningPage() async {
        let coordinator = PushRegistrationCoordinator()
        coordinator.setUserID("user")
        _ = await coordinator.refreshAuthorization { .denied }
        var uploaded: [String] = []
        await coordinator.synchronize { token, _ in uploaded.append(token); return true }
        XCTAssertTrue(uploaded.isEmpty)

        // Foreground authorization refresh receives the system token callback
        // before registerForRemoteNotifications returns to its caller.
        let state = await coordinator.refreshAuthorization {
            coordinator.receiveToken("device-token")
            return .authorized
        }
        XCTAssertEqual(state, .authorized)
        await coordinator.synchronize { token, _ in uploaded.append(token); return true }
        XCTAssertEqual(uploaded, ["device-token"])
    }

    func testConcurrentPermissionRefreshSharesOneSystemRequest() async {
        let coordinator = PushRegistrationCoordinator()
        let entered = expectation(description: "permission query started")
        let gate = PushPermissionGate()
        var queryCount = 0
        let first = Task {
            await coordinator.refreshAuthorization {
                queryCount += 1
                entered.fulfill()
                return await gate.wait()
            }
        }
        await fulfillment(of: [entered], timeout: 2)
        let second = await coordinator.refreshAuthorization {
            queryCount += 1
            return .denied
        }
        XCTAssertNil(second)
        gate.finish(.authorized)
        let result = await first.value
        XCTAssertEqual(result, .authorized)
        XCTAssertEqual(queryCount, 1)
    }

    func testExplicitPermissionRequestWaitsForPassiveQueryInsteadOfBeingDropped() async {
        let coordinator = PushRegistrationCoordinator()
        let entered = expectation(description: "passive query started")
        let gate = PushPermissionGate()
        let passive = Task {
            await coordinator.refreshAuthorization {
                entered.fulfill()
                return await gate.wait()
            }
        }
        await fulfillment(of: [entered], timeout: 2)
        var permissionRequests = 0
        let explicit = Task {
            await coordinator.refreshAuthorization(requestsPermission: true) {
                permissionRequests += 1
                return .authorized
            }
        }
        await Task.yield()
        XCTAssertEqual(permissionRequests, 0)
        gate.finish(.notDetermined)
        _ = await passive.value
        let result = await explicit.value
        XCTAssertEqual(result, .authorized)
        XCTAssertEqual(permissionRequests, 1)
    }

    func testDuplicateTokenCallbacksDoNotUploadTwiceAndNewTokenIsNotLost() async {
        let coordinator = PushRegistrationCoordinator()
        coordinator.setUserID("user")
        _ = await coordinator.refreshAuthorization { .authorized }
        coordinator.receiveToken("first-token")
        let entered = expectation(description: "first token upload started")
        let gate = PushUploadGate()
        var uploaded: [String] = []
        let first = Task {
            await coordinator.synchronize { token, _ in
                uploaded.append(token)
                if token == "first-token" {
                    entered.fulfill()
                    return await gate.wait()
                }
                return true
            }
        }
        await fulfillment(of: [entered], timeout: 2)
        coordinator.receiveToken("first-token")
        await coordinator.synchronize { token, _ in uploaded.append(token); return true }
        coordinator.receiveToken("new-token")
        await coordinator.synchronize { token, _ in uploaded.append(token); return true }
        gate.finish(true)
        await first.value
        await coordinator.synchronize { token, _ in uploaded.append(token); return true }
        XCTAssertEqual(uploaded, ["first-token", "new-token"])
    }

    func testAccountChangeDuringUploadCannotAcknowledgePreviousAccount() async {
        let coordinator = PushRegistrationCoordinator()
        coordinator.setUserID("first-user")
        _ = await coordinator.refreshAuthorization { .authorized }
        coordinator.receiveToken("device-token")
        let entered = expectation(description: "old account upload started")
        let gate = PushUploadGate()
        var uploadedUsers: [String] = []
        let first = Task {
            await coordinator.synchronize { _, user in
                uploadedUsers.append(user)
                if user == "first-user" {
                    entered.fulfill()
                    return await gate.wait()
                }
                return true
            }
        }
        await fulfillment(of: [entered], timeout: 2)
        coordinator.setUserID("new-user")
        await coordinator.synchronize { _, user in uploadedUsers.append(user); return true }
        gate.finish(true)
        await first.value
        XCTAssertEqual(uploadedUsers, ["first-user", "new-user"])
    }

    func testSigningOutAndBackIntoSameAccountNeedsFreshAcknowledgment() async {
        let coordinator = PushRegistrationCoordinator()
        coordinator.setUserID("same-user")
        _ = await coordinator.refreshAuthorization { .authorized }
        coordinator.receiveToken("device-token")
        let entered = expectation(description: "old session upload started")
        let gate = PushUploadGate()
        var count = 0
        let first = Task {
            await coordinator.synchronize { _, _ in
                count += 1
                if count == 1 { entered.fulfill(); return await gate.wait() }
                return true
            }
        }
        await fulfillment(of: [entered], timeout: 2)
        coordinator.setUserID(nil)
        coordinator.setUserID("same-user")
        coordinator.receiveToken("device-token")
        gate.finish(true)
        await first.value
        XCTAssertEqual(count, 2)
    }

    func testFailedUploadRetriesOnNextRefreshAndRevokedPermissionPreventsUploads() async {
        let coordinator = PushRegistrationCoordinator()
        coordinator.setUserID("user")
        coordinator.receiveToken("device-token")
        _ = await coordinator.refreshAuthorization { .authorized }
        var attempts = 0
        await coordinator.synchronize { _, _ in attempts += 1; return false }
        XCTAssertEqual(attempts, 1)
        await coordinator.synchronize { _, _ in attempts += 1; return true }
        XCTAssertEqual(attempts, 2)
        _ = await coordinator.refreshAuthorization { .denied }
        await coordinator.synchronize { _, _ in attempts += 1; return true }
        XCTAssertEqual(attempts, 2)
        _ = await coordinator.refreshAuthorization { .authorized }
        await coordinator.synchronize { _, _ in attempts += 1; return true }
        XCTAssertEqual(attempts, 3)
    }

    func testSigningOutDuringUploadDoesNotScheduleAnotherAccountRequest() async {
        let coordinator = PushRegistrationCoordinator()
        coordinator.setUserID("user")
        _ = await coordinator.refreshAuthorization { .authorized }
        coordinator.receiveToken("device-token")
        let entered = expectation(description: "upload started")
        let gate = PushUploadGate()
        var count = 0
        let first = Task {
            await coordinator.synchronize { _, _ in
                count += 1
                entered.fulfill()
                return await gate.wait()
            }
        }
        await fulfillment(of: [entered], timeout: 2)
        coordinator.setUserID(nil)
        gate.finish(true)
        await first.value
        await coordinator.synchronize { _, _ in count += 1; return true }
        XCTAssertEqual(count, 1)
    }

    func testLatePushUnauthorizedCannotSignOutFreshSessionOfSameUser() async throws {
        let started = expectation(description: "previous session push request started")
        let transport = DeferredPushUnauthorizedTransport { started.fulfill() }
        let tokens = InMemoryTokenStore(token: "old-account-bearer")
        let api = DefaultAppAPI(
            configuration: try APIConfiguration(baseURL: APIConfiguration.productionBaseURL),
            transport: transport,
            tokenStore: tokens,
            retryPolicy: .disabled,
            mutationProtectionKey: Data(repeating: 1, count: 32)
        )
        let store = AppStore(api: api, haptics: NoopHaptics())
        await store.restoreSession()
        let previousSession = store.session
        let upload = Task {
            await store.registerPushToken(String(repeating: "a", count: 64), environment: .production)
        }
        await fulfillment(of: [started], timeout: 2)
        await store.signOut()
        store.emailAuth.email = "family@example.com"
        let requested = await store.requestEmailOTP()
        XCTAssertTrue(requested)
        store.emailAuth.verificationCode = "123456"
        await store.verifyEmailOTP()
        // Profile equality cannot distinguish the new bearer from the old one.
        XCTAssertEqual(store.session, previousSession)
        await transport.reject()
        let registered = await upload.value
        XCTAssertFalse(registered)
        XCTAssertEqual(store.session, previousSession)
        XCTAssertNil(store.globalErrorMessage)
        let remainingToken = await tokens.readToken()
        XCTAssertEqual(remainingToken, "new-account-bearer")
    }

    func testLatePushUnauthorizedResponsePreservesNewAccountBearer() async throws {
        let started = expectation(description: "push request started")
        let transport = DeferredPushUnauthorizedTransport { started.fulfill() }
        let tokens = InMemoryTokenStore(token: "old-account-bearer")
        let api = DefaultAppAPI(
            configuration: try APIConfiguration(baseURL: APIConfiguration.productionBaseURL),
            transport: transport,
            tokenStore: tokens,
            retryPolicy: .disabled,
            mutationProtectionKey: Data(repeating: 1, count: 32)
        )
        let upload = Task {
            do {
                try await api.registerPushToken(String(repeating: "a", count: 64), environment: .production)
                XCTFail("Expected rejected old bearer")
            } catch APIClientError.unauthorized {} catch { XCTFail("Unexpected error: \(error)") }
        }
        await fulfillment(of: [started], timeout: 2)
        await tokens.writeToken("new-account-bearer")
        await transport.reject()
        await upload.value
        let remainingToken = await tokens.readToken()
        XCTAssertEqual(remainingToken, "new-account-bearer")
        let request = await transport.request
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer old-account-bearer")
        let body = try XCTUnwrap(request?.httpBody)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(fields["platform"], "ios")
        XCTAssertEqual(fields["environment"], "production")
    }
}

@MainActor
private final class PushPermissionGate {
    private var continuation: CheckedContinuation<PushAuthorizationState, Never>?
    func wait() async -> PushAuthorizationState {
        await withCheckedContinuation { continuation = $0 }
    }
    func finish(_ value: PushAuthorizationState) { continuation?.resume(returning: value); continuation = nil }
}

@MainActor
private final class PushUploadGate {
    private var continuation: CheckedContinuation<Bool, Never>?
    func wait() async -> Bool { await withCheckedContinuation { continuation = $0 } }
    func finish(_ value: Bool) { continuation?.resume(returning: value); continuation = nil }
}

private actor DeferredPushUnauthorizedTransport: HTTPTransport {
    private let onStart: @Sendable () -> Void
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var request: URLRequest?
    init(onStart: @escaping @Sendable () -> Void) { self.onStart = onStart }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if request.url?.path.hasSuffix("/push-tokens") != true {
            let user = #"{"id":"same-user","displayName":"家族","email":"family@example.com","hasEmail":true}"#
            let body: String
            switch request.url!.lastPathComponent {
            case "me": body = "{\"data\":{\"user\":\(user)}}"
            case "home": body = #"{"data":{"answers":[]}}"#
            case "request": body = #"{"data":{"requestId":"push-relogin","expiresIn":600}}"#
            case "verify": body = "{\"data\":{\"token\":\"new-account-bearer\",\"tokenType\":\"Bearer\",\"user\":\(user)}}"
            default: body = #"{"data":{}}"#
            }
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!)
        }
        self.request = request
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            onStart()
        }
        return (Data(#"{"error":{"code":"unauthorized"}}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
    func reject() { continuation?.resume(); continuation = nil }
}

private actor DeferredPushDestinationTransport: HTTPTransport {
    private let delayedEndpoint: String
    private let onStart: @Sendable () -> Void
    private var continuation: CheckedContinuation<Void, Never>?

    init(delayedEndpoint: String, onStart: @escaping @Sendable () -> Void) {
        self.delayedEndpoint = delayedEndpoint
        self.onStart = onStart
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let endpoint = request.url!.lastPathComponent
        if endpoint == delayedEndpoint {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                onStart()
            }
        }
        let body: String
        switch endpoint {
        case "me": body = #"{"data":{"user":{"id":"user","displayName":"家族","hasEmail":true}}}"#
        case "home": body = #"{"data":{"answers":[]}}"#
        case "answer": body = #"{"data":{"answer":{"id":"answer","question":{"id":"question"},"author":{"id":"relative","displayName":"家族"},"body":"家族の回答","createdAt":"2026-09-05T12:00:00Z"}}}"#
        case "comments": body = #"{"data":{"items":[{"id":"comment","answerId":"answer","author":{"id":"relative","displayName":"家族"},"body":"家族のコメント","createdAt":"2026-09-05T12:00:00Z"}],"nextCursor":null}}"#
        case "today": body = #"{"data":{"question":{"id":"question","prompt":"今日の質問","date":"2026-09-05"},"answer":null}}"#
        case "notification-preferences": body = #"{"data":{"preferences":{"familyActivityEnabled":false,"commentsEnabled":false,"likesEnabled":false,"questionRemindersEnabled":false,"questionReminderTime":"09:00","timezone":"Asia/Tokyo"}}}"#
        default: body = #"{"data":{}}"#
        }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }

    func finish() { continuation?.resume(); continuation = nil }
}
