import Foundation
import XCTest
@testable import tsutsuura

@MainActor
final class PushRegistrationRecoveryTests: XCTestCase {
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
