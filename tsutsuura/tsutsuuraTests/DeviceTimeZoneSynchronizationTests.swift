import Foundation
import XCTest
@testable import tsutsuura

@MainActor
final class DeviceTimeZoneSynchronizationTests: XCTestCase {
    func testDuplicateCallbacksAreCoalescedAndChangedZoneDrainsAfterInFlightRequest() async {
        let synchronizer = DeviceTimeZoneSynchronizer()
        let entered = expectation(description: "first sync started")
        let gate = TimeZoneUpdateGate()
        var requested: [String] = []
        let toronto = identity("America/Toronto")
        let tokyo = identity("Asia/Tokyo")
        let first = Task {
            await synchronizer.synchronize(identity: toronto) { value in
                requested.append(value.timeZoneIdentifier)
                if requested.count == 1 { entered.fulfill(); return await gate.wait() }
                return true
            }
        }
        await fulfillment(of: [entered], timeout: 2)
        await synchronizer.synchronize(identity: toronto) { _ in XCTFail("Duplicate upload"); return true }
        await synchronizer.synchronize(identity: tokyo) { _ in XCTFail("Concurrent upload"); return true }
        gate.finish(true)
        await first.value
        await synchronizer.synchronize(identity: tokyo) { _ in XCTFail("Already acknowledged"); return true }
        XCTAssertEqual(requested, ["America/Toronto", "Asia/Tokyo"])
    }

    func testFailureRetriesOnNextActivationAndNewSessionRequiresItsOwnAcknowledgment() async {
        let synchronizer = DeviceTimeZoneSynchronizer()
        var attempts = 0
        await synchronizer.synchronize(identity: identity("Asia/Tokyo")) { _ in attempts += 1; return false }
        XCTAssertEqual(attempts, 1)
        await synchronizer.synchronize(identity: identity("Asia/Tokyo")) { _ in attempts += 1; return true }
        await synchronizer.synchronize(identity: identity("Asia/Tokyo")) { _ in attempts += 1; return true }
        XCTAssertEqual(attempts, 2)
        synchronizer.reset()
        await synchronizer.synchronize(identity: identity("Asia/Tokyo", generation: 2)) { _ in attempts += 1; return true }
        XCTAssertEqual(attempts, 3)
    }

    func testTimezoneRequestSendsOnlyZoneAndWorksWithNotificationPermissionDenied() async throws {
        let transport = TimeZoneRecordingTransport()
        let api = try makeAPI(transport: transport)
        let store = AppStore(api: api, haptics: NoopHaptics())
        await store.restoreSession()
        store.setNotificationPermissionStatus(.denied)
        await store.synchronizeDeviceTimeZone("America/Toronto")
        await store.synchronizeDeviceTimeZone("America/Toronto")
        let requests = await transport.timeZoneRequests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-HTTP-Method-Override"), "PATCH")
        XCTAssertEqual(request.url?.path, "/tsutsuura-api/api/v1/me/timezone")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer original-bearer")
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String]
        XCTAssertEqual(body, ["timeZoneIdentifier": "America/Toronto"], "Timezone sync must never upload default notification toggles.")
        XCTAssertEqual(store.notificationPreferences.permissionStatus, .denied)
        XCTAssertNil(store.globalErrorMessage)
    }

    func testLateUnauthorizedTimezoneResponseCannotSignOutSameUserWithNewSession() async throws {
        let entered = expectation(description: "old session sync started")
        let transport = TimeZoneRecordingTransport(onFirstTimeZoneRequest: { entered.fulfill() })
        let tokens = InMemoryTokenStore(token: "original-bearer")
        let store = AppStore(api: try makeAPI(transport: transport, tokens: tokens), haptics: NoopHaptics())
        await store.restoreSession()
        let originalSession = store.session
        let first = Task { await store.synchronizeDeviceTimeZone("America/Toronto") }
        await fulfillment(of: [entered], timeout: 2)
        await store.signOut()
        store.emailAuth.email = "family@example.com"
        let requested = await store.requestEmailOTP()
        XCTAssertTrue(requested)
        store.emailAuth.verificationCode = "123456"
        await store.verifyEmailOTP()
        XCTAssertEqual(store.session, originalSession)
        await store.synchronizeDeviceTimeZone("America/Toronto")
        await transport.finishFirstTimeZoneRequest(status: 401)
        await first.value
        XCTAssertEqual(store.session, originalSession)
        let remainingToken = await tokens.readToken()
        XCTAssertEqual(remainingToken, "new-bearer")
        XCTAssertNil(store.globalErrorMessage)
        let requests = await transport.timeZoneRequests
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer original-bearer", "Bearer new-bearer"])
    }

    private func identity(_ zone: String, generation: Int = 1) -> DeviceTimeZoneSynchronizer.Identity {
        .init(userID: "same-user", sessionGeneration: generation, timeZoneIdentifier: zone)
    }

    private func makeAPI(
        transport: TimeZoneRecordingTransport,
        tokens: InMemoryTokenStore = InMemoryTokenStore(token: "original-bearer")
    ) throws -> DefaultAppAPI {
        DefaultAppAPI(
            configuration: try APIConfiguration(baseURL: APIConfiguration.productionBaseURL),
            transport: transport,
            tokenStore: tokens,
            retryPolicy: .disabled,
            mutationProtectionKey: Data(repeating: 1, count: 32)
        )
    }
}

@MainActor
private final class TimeZoneUpdateGate {
    private var continuation: CheckedContinuation<Bool, Never>?
    func wait() async -> Bool { await withCheckedContinuation { continuation = $0 } }
    func finish(_ value: Bool) { continuation?.resume(returning: value); continuation = nil }
}

private actor TimeZoneRecordingTransport: HTTPTransport {
    private let onFirstTimeZoneRequest: (@Sendable () -> Void)?
    private var continuation: CheckedContinuation<Int, Never>?
    private(set) var timeZoneRequests: [URLRequest] = []
    init(onFirstTimeZoneRequest: (@Sendable () -> Void)? = nil) {
        self.onFirstTimeZoneRequest = onFirstTimeZoneRequest
    }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let user = #"{"id":"same-user","displayName":"家族","email":"family@example.com","hasEmail":true}"#
        let body: String
        var status = 200
        switch request.url!.lastPathComponent {
        case "timezone":
            timeZoneRequests.append(request)
            if timeZoneRequests.count == 1, let onFirstTimeZoneRequest {
                status = await withCheckedContinuation { continuation in
                    self.continuation = continuation
                    onFirstTimeZoneRequest()
                }
            }
            body = status == 401 ? #"{"error":{"code":"unauthorized"}}"# : #"{"data":{"timezone":"America/Toronto"}}"#
        case "me": body = "{\"data\":{\"user\":\(user)}}"
        case "home": body = #"{"data":{"answers":[]}}"#
        case "request": body = #"{"data":{"requestId":"timezone-relogin","expiresIn":600}}"#
        case "verify": body = "{\"data\":{\"token\":\"new-bearer\",\"tokenType\":\"Bearer\",\"user\":\(user)}}"
        default: body = #"{"data":{}}"#
        }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
    func finishFirstTimeZoneRequest(status: Int) { continuation?.resume(returning: status); continuation = nil }
}
