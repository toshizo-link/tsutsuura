import Foundation
import XCTest
@testable import tsutsuura

final class EmailAddressValidationTests: XCTestCase {
    func testNormalizesAddressAndPreservesPlusTag() {
        XCTAssertEqual(EmailAddressValidation.normalized("  Takami+Family@Example.COM  "), "takami+family@example.com")
        XCTAssertTrue(EmailAddressValidation.isValid("family@sub.example.co.jp"))
        XCTAssertEqual(EmailAddressValidation.normalized("Ｆａｍｉｌｙ＠Ｅｘａｍｐｌｅ．ｃｏｍ"), "family@example.com")
    }

    func testRejectsHeaderInjectionAndMalformedAddresses() {
        for address in ["", "name", "name@localhost", "a b@example.com", "a..b@example.com",
                        ".a@example.com", "a.@example.com", "a@-example.com", "a@example..com",
                        "a@example.com\r\nBcc:other@example.com", "a@@example.com", "あ@example.com",
                        String(repeating: "a", count: 65) + "@example.com"] {
            XCTAssertFalse(EmailAddressValidation.isValid(address), address)
        }
    }

    func testOldProfileStillDecodesWithoutEmailFields() throws {
        let data = Data(#"{"id":"legacy","displayName":"家族"}"#.utf8)
        let profile = try JSONDecoder().decode(UserProfile.self, from: data)
        XCTAssertNil(profile.email)
        XCTAssertNil(profile.hasEmail)
    }
}

@MainActor
final class EmailVerificationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let startedAt = Date(timeIntervalSince1970: 1_788_192_000)

    override func setUpWithError() throws {
        suiteName = "tsutsuura.tests.email.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeAPI(
        transport: EmailTestTransport,
        tokenStore: InMemoryTokenStore = InMemoryTokenStore(),
        date: Date? = nil
    ) throws -> DefaultAppAPI {
        let clock = date ?? startedAt
        return DefaultAppAPI(
            configuration: try APIConfiguration(baseURL: URL(string: "https://api.example.com")!),
            transport: transport,
            tokenStore: tokenStore,
            retryPolicy: .disabled,
            idempotencyDefaults: defaults,
            mutationProtectionKey: Data(repeating: 7, count: 32),
            now: { clock }
        )
    }

    private func makeStore(
        transport: EmailTestTransport,
        signedIn: Bool = false,
        date: Date? = nil
    ) throws -> AppStore {
        let clock = date ?? startedAt
        return AppStore(
            api: try makeAPI(transport: transport, tokenStore: InMemoryTokenStore(token: signedIn ? "actor-token" : nil), date: clock),
            haptics: NoopHaptics(),
            verificationDefaults: defaults,
            now: { clock }
        )
    }

    func testEmailAPIUsesExpectedWireContractAndRetainsRetryReceipt() async throws {
        let transport = EmailTestTransport()
        let tokens = InMemoryTokenStore()
        let api = try makeAPI(transport: transport, tokenStore: tokens)
        let challenge = try await api.requestEmailOTP(email: " Family+One@Example.COM ")
        await transport.setVerificationOutcome(.timeout)
        do {
            _ = try await api.verifyEmailOTP(requestID: challenge.requestID, code: "654321")
            XCTFail("Expected interrupted response")
        } catch {}
        let relaunchedAPI = try makeAPI(transport: transport, tokenStore: tokens, date: startedAt.addingTimeInterval(601))
        await transport.setVerificationOutcome(.success)
        let session = try await relaunchedAPI.verifyEmailOTP(requestID: challenge.requestID, code: "654321")
        XCTAssertEqual(session.user.id, "email-user")
        let token = await tokens.readToken()
        XCTAssertEqual(token, "email-session-token")
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url!.path }, ["/v1/auth/email/request", "/v1/auth/email/verify", "/v1/auth/email/verify"])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[0].httpBody!) as? [String: String])
        XCTAssertEqual(body, ["email": "family+one@example.com"])
        let verifyBody = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[1].httpBody!) as? [String: String])
        XCTAssertEqual(verifyBody, ["requestId": challenge.requestID, "code": "654321"])
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "Authorization"))
        let key = try XCTUnwrap(requests[1].value(forHTTPHeaderField: "Idempotency-Key"))
        XCTAssertEqual(key, requests[2].value(forHTTPHeaderField: "Idempotency-Key"))
    }

    func testEnrollmentRetryKeyIsBoundToCurrentBearer() async throws {
        let transport = EmailTestTransport()
        await transport.setVerificationOutcome(.timeout)
        let tokens = InMemoryTokenStore(token: "first-actor")
        let api = try makeAPI(transport: transport, tokenStore: tokens)
        do { _ = try await api.verifyEmailEnrollment(requestID: "same-challenge", code: "654321") } catch {}
        await tokens.writeToken("different-actor")
        do { _ = try await api.verifyEmailEnrollment(requestID: "same-challenge", code: "654321") } catch {}
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer first-actor")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer different-actor")
        XCTAssertNotEqual(requests[0].value(forHTTPHeaderField: "Idempotency-Key"), requests[1].value(forHTTPHeaderField: "Idempotency-Key"))
    }

    func testMalformedEmailNeverReachesNetwork() async throws {
        let transport = EmailTestTransport()
        let api = try makeAPI(transport: transport)
        do {
            _ = try await api.requestEmailOTP(email: "a@example.com\nBcc:b@example.com")
            XCTFail("Expected local validation")
        } catch let error as TextInputValidationError {
            XCTAssertEqual(error, .invalidEmailAddress)
        }
        let count = await transport.requests.count
        XCTAssertEqual(count, 0)
    }

    func testUnfinishedLoginRestoresWithoutPersistingTheCode() async throws {
        let transport = EmailTestTransport()
        let first = try makeStore(transport: transport)
        first.emailAuth.email = "Family@Example.com"
        let requested = await first.requestEmailOTP()
        XCTAssertTrue(requested)
        first.emailAuth.verificationCode = "654321"
        let relaunched = try makeStore(transport: transport, date: startedAt.addingTimeInterval(30))
        await relaunched.restoreSession()
        XCTAssertEqual(relaunched.session, .awaitingEmailVerification(email: "family@example.com"))
        XCTAssertEqual(relaunched.emailAuth.challenge?.requestID, "email-request-1")
        XCTAssertEqual(relaunched.emailAuth.verificationCode, "")
        XCTAssertEqual(relaunched.path, [.emailVerification(email: "family@example.com", requestID: "email-request-1")])
        let record = try XCTUnwrap(defaults.data(forKey: "jp.tsutsuura.pending-email-login-verification.v1"))
        XCTAssertFalse(String(decoding: record, as: UTF8.self).contains("654321"))
    }

    func testExpiredUnsubmittedLoginDoesNotRestore() async throws {
        let transport = EmailTestTransport()
        let first = try makeStore(transport: transport)
        first.emailAuth.email = "family@example.com"
        _ = await first.requestEmailOTP()
        let relaunched = try makeStore(transport: transport, date: startedAt.addingTimeInterval(601))
        await relaunched.restoreSession()
        XCTAssertEqual(relaunched.session, .signedOut)
        XCTAssertNil(relaunched.emailAuth.challenge)
    }

    func testInterruptedLoginRemainsReplayableAfterChallengeExpiry() async throws {
        let transport = EmailTestTransport()
        await transport.setVerificationOutcome(.timeout)
        let first = try makeStore(transport: transport)
        first.emailAuth.email = "family@example.com"
        _ = await first.requestEmailOTP()
        first.emailAuth.verificationCode = "654321"
        await first.verifyEmailOTP()
        let relaunched = try makeStore(transport: transport, date: startedAt.addingTimeInterval(601))
        await relaunched.restoreSession()
        XCTAssertTrue(relaunched.emailAuth.canReplayExpiredAttempt)
        XCTAssertEqual(relaunched.emailAuth.expiresAt, startedAt.addingTimeInterval(600))
        XCTAssertEqual(relaunched.emailAuth.verificationCode, "")
        await transport.setVerificationOutcome(.success)
        relaunched.emailAuth.verificationCode = "654321"
        await relaunched.verifyEmailOTP()
        guard case .signedIn = relaunched.session else { return XCTFail("Replay should finish login") }
        XCTAssertEqual(relaunched.path, [.home])
        XCTAssertNil(defaults.data(forKey: "jp.tsutsuura.pending-email-login-verification.v1"))
    }

    func testRejectedCodeDoesNotKeepExpiredReplayAlive() async throws {
        let transport = EmailTestTransport()
        await transport.setVerificationOutcome(.invalidCode)
        let first = try makeStore(transport: transport)
        first.emailAuth.email = "family@example.com"
        _ = await first.requestEmailOTP()
        first.emailAuth.verificationCode = "654321"
        await first.verifyEmailOTP()
        XCTAssertFalse(first.emailAuth.canReplayExpiredAttempt)
        let relaunched = try makeStore(transport: transport, date: startedAt.addingTimeInterval(601))
        await relaunched.restoreSession()
        XCTAssertEqual(relaunched.session, .signedOut)
    }

    func testEnrollmentRestoreIsActorBoundAndResendReplacesOnePage() async throws {
        let transport = EmailTestTransport()
        let first = try makeStore(transport: transport, signedIn: true)
        await first.restoreSession()
        first.path = [.home, .settings, .accountPrivacy, .emailEnrollment]
        first.emailEnrollment.email = "family@example.com"
        _ = await first.requestEmailEnrollment()
        _ = await first.requestEmailEnrollment()
        XCTAssertEqual(first.path.count, 5)
        XCTAssertEqual(first.path.last, .emailEnrollmentVerification(email: "family@example.com", requestID: "email-request-2"))
        let relaunched = try makeStore(transport: transport, signedIn: true, date: startedAt.addingTimeInterval(30))
        await relaunched.restoreSession()
        XCTAssertEqual(relaunched.emailEnrollment.challenge?.requestID, "email-request-2")
        await transport.setProfileID("another-user")
        let differentActor = try makeStore(transport: transport, signedIn: true, date: startedAt.addingTimeInterval(30))
        await differentActor.restoreSession()
        XCTAssertNil(differentActor.emailEnrollment.challenge)
        XCTAssertEqual(differentActor.path, [.home])
    }

    func testEnrollmentCompletionAfterLostResponseSelfHealsOnRestore() async throws {
        let transport = EmailTestTransport()
        await transport.setVerificationOutcome(.timeout)
        let first = try makeStore(transport: transport, signedIn: true)
        await first.restoreSession()
        first.emailEnrollment.email = "family@example.com"
        _ = await first.requestEmailEnrollment()
        first.emailEnrollment.verificationCode = "654321"
        let verified = await first.verifyEmailEnrollment()
        XCTAssertFalse(verified)
        await transport.setEmail("family@example.com")
        let relaunched = try makeStore(transport: transport, signedIn: true, date: startedAt.addingTimeInterval(601))
        await relaunched.restoreSession()
        XCTAssertNil(relaunched.emailEnrollment.challenge)
        XCTAssertEqual(relaunched.path, [.home])
        guard case .signedIn(let user) = relaunched.session else { return XCTFail("Expected restored user") }
        XCTAssertEqual(user.email, "family@example.com")
    }

    func testInterruptedEnrollmentCanReplayAndSuccessfulProfileUpdatesImmediately() async throws {
        let transport = EmailTestTransport()
        await transport.setVerificationOutcome(.timeout)
        let first = try makeStore(transport: transport, signedIn: true)
        await first.restoreSession()
        first.emailEnrollment.email = "family@example.com"
        _ = await first.requestEmailEnrollment()
        first.emailEnrollment.verificationCode = "654321"
        _ = await first.verifyEmailEnrollment()
        let relaunched = try makeStore(transport: transport, signedIn: true, date: startedAt.addingTimeInterval(601))
        await relaunched.restoreSession()
        XCTAssertTrue(relaunched.emailEnrollment.canReplayExpiredAttempt)
        XCTAssertEqual(relaunched.emailEnrollment.verificationCode, "")
        await transport.setVerificationOutcome(.success)
        relaunched.emailEnrollment.verificationCode = "654321"
        let verified = await relaunched.verifyEmailEnrollment()
        XCTAssertTrue(verified)
        guard case .signedIn(let user) = relaunched.session else { return XCTFail("Expected user") }
        XCTAssertEqual(user.email, "family@example.com")
        XCTAssertEqual(user.hasEmail, true)
        XCTAssertNil(relaunched.emailEnrollment.challenge)
    }

    func testDemoEnrollmentAndRecoveryDoNotPublishEmailToFamily() async throws {
        let api = DemoAppAPI(startsAuthenticated: true)
        let challenge = try await api.requestEmailEnrollment(email: "private@example.com")
        let user = try await api.verifyEmailEnrollment(requestID: challenge.requestID, code: "654321")
        XCTAssertEqual(user.email, "private@example.com")
        let family = try await api.fetchFamily()
        XCTAssertTrue(family.members.allSatisfy { $0.email == nil })
        await api.signOut()
        let login = try await api.requestEmailOTP(email: "PRIVATE@example.com")
        let session = try await api.verifyEmailOTP(requestID: login.requestID, code: "654321")
        XCTAssertEqual(session.user.id, user.id)
        XCTAssertEqual(session.user.email, "private@example.com")
    }
}

private actor EmailTestTransport: HTTPTransport {
    enum VerificationOutcome: Sendable { case success, timeout, invalidCode }
    private(set) var requests: [URLRequest] = []
    private var outcome = VerificationOutcome.success
    private var requestCount = 0
    private var requestedEmail = "family@example.com"
    private var profileID = "email-user"
    private var email: String?

    func setVerificationOutcome(_ value: VerificationOutcome) { outcome = value }
    func setProfileID(_ value: String) { profileID = value }
    func setEmail(_ value: String) { email = value }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let path = request.url!.path
        var statusCode = 200
        var body: [String: Any]
        if path.hasSuffix("/email/request") {
            requestCount += 1
            requestedEmail = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String])?["email"] ?? requestedEmail
            body = ["data": ["requestId": "email-request-\(requestCount)", "expiresIn": 600]]
        } else if path.hasSuffix("/email/verify") {
            switch outcome {
            case .timeout: throw URLError(.timedOut)
            case .invalidCode:
                statusCode = 422
                body = ["error": ["code": "invalid_otp", "message": "invalid"]]
            case .success:
                email = requestedEmail
                if path.contains("/auth/") {
                    body = ["data": ["token": "email-session-token", "tokenType": "Bearer", "user": user]]
                } else {
                    body = ["data": ["user": user]]
                }
            }
        } else if path == "/v1/me" {
            body = ["data": ["user": user]]
        } else if path == "/v1/home" {
            body = ["data": ["answers": []]]
        } else {
            body = ["data": [:]]
        }
        return (try JSONSerialization.data(withJSONObject: body), HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!)
    }

    private var user: [String: Any] {
        var result: [String: Any] = ["id": profileID, "displayName": "家族", "hasEmail": email != nil]
        if let email { result["email"] = email }
        return result
    }
}
