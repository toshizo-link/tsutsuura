import Foundation
import XCTest
@testable import tsutsuura

final class HTTPMethodOverrideTests: XCTestCase {
    private let user = Data(#"{"data":{"id":"user","displayName":"まさこ"}}"#.utf8)
    private let empty = Data(#"{"data":{}}"#.utf8)

    func testPatchPutDeleteUsePostWithOriginalMethodHeaderAndAuthorization() async throws {
        let transport = OverrideRecordingTransport(responses: [(200, user), (200, empty), (200, empty)])
        let api = try makeAPI(transport)
        _ = try await api.updateProfile(displayName: "まさこ")
        try await api.registerPushToken(String(repeating: "a", count: 64), environment: .production)
        try await api.unregisterPushToken(tokenHash: "token-hash")

        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests.map(\.httpMethod), ["POST", "POST", "POST"])
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "X-HTTP-Method-Override") }, ["PATCH", "PUT", "DELETE"])
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "Authorization") }, Array(repeating: "Bearer fixture-bearer", count: 3))
        XCTAssertEqual(requests.compactMap { $0.url?.path }, [
            "/tsutsuura-api/api/v1/me", "/tsutsuura-api/api/v1/push-tokens", "/tsutsuura-api/api/v1/push-tokens/token-hash"
        ])
        let nameBody = try JSONSerialization.jsonObject(with: XCTUnwrap(requests[0].httpBody)) as? [String: String]
        XCTAssertEqual(nameBody, ["displayName": "まさこ"])
        let tokenBody = try JSONSerialization.jsonObject(with: XCTUnwrap(requests[1].httpBody)) as? [String: String]
        XCTAssertEqual(tokenBody, ["token": String(repeating: "a", count: 64), "platform": "ios", "environment": "production"])
        XCTAssertNil(requests[2].httpBody)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")
    }

    func testGetAndOrdinaryPostRemainUnchanged() async throws {
        let challenge = Data(#"{"data":{"requestId":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","expiresIn":600}}"#.utf8)
        let transport = OverrideRecordingTransport(responses: [(200, user), (202, challenge)])
        let api = try makeAPI(transport)
        _ = try await api.fetchMe()
        _ = try await api.requestEmailOTP(email: "family@example.com")
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.httpMethod), ["GET", "POST"])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "X-HTTP-Method-Override") == nil })
        XCTAssertNil(requests[0].httpBody)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer fixture-bearer")
        XCTAssertNil(requests[1].value(forHTTPHeaderField: "Authorization"))
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(requests[1].httpBody)) as? [String: String]
        XCTAssertEqual(body, ["email": "family@example.com"])
    }

    func testPutAndDeleteRetriesKeepOverrideBodyAuthorizationAndIdempotencyKey() async throws {
        let transport = OverrideRecordingTransport(responses: [
            (503, empty), (200, empty), // PUT registration remains retryable.
            (200, user), // Existing account-deletion preflight remains GET.
            (503, empty), (200, empty) // DELETE retains its durable receipt key.
        ])
        let api = try makeAPI(transport, retryPolicy: APIRequestRetryPolicy(maximumAttempts: 2, initialDelay: 0, maximumDelay: 0))
        try await api.registerPushToken(String(repeating: "b", count: 64), environment: .production)
        try await api.deleteAccount()
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.httpMethod), ["POST", "POST", "GET", "POST", "POST"])
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "X-HTTP-Method-Override") }, ["PUT", "PUT", nil, "DELETE", "DELETE"])
        XCTAssertEqual(requests[0].httpBody, requests[1].httpBody)
        XCTAssertEqual(requests[3].httpBody, requests[4].httpBody)
        let deletionKey = try XCTUnwrap(requests[3].value(forHTTPHeaderField: "Idempotency-Key"))
        XCTAssertFalse(deletionKey.isEmpty)
        XCTAssertEqual(deletionKey, requests[4].value(forHTTPHeaderField: "Idempotency-Key"))
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-bearer" })
    }

    func testPatchKeepsItsExistingNoAutomaticRetryPolicy() async throws {
        let transport = OverrideRecordingTransport(responses: [(503, empty), (200, user)])
        let api = try makeAPI(transport, retryPolicy: APIRequestRetryPolicy(maximumAttempts: 2, initialDelay: 0, maximumDelay: 0))
        do {
            _ = try await api.updateProfile(displayName: "まさこ")
            XCTFail("A PATCH save must not gain automatic retries when sent over POST")
        } catch APIClientError.server(let status, _) {
            XCTAssertEqual(status, 503)
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "X-HTTP-Method-Override"), "PATCH")
    }

    private func makeAPI(_ transport: OverrideRecordingTransport, retryPolicy: APIRequestRetryPolicy = .disabled) throws -> DefaultAppAPI {
        DefaultAppAPI(configuration: try APIConfiguration(baseURL: APIConfiguration.productionBaseURL),
                      transport: transport, tokenStore: InMemoryTokenStore(token: "fixture-bearer"),
                      retryPolicy: retryPolicy, mutationProtectionKey: Data(repeating: 1, count: 32))
    }
}

private actor OverrideRecordingTransport: HTTPTransport {
    private var responses: [(Int, Data)]
    private(set) var requests: [URLRequest] = []
    init(responses: [(Int, Data)]) { self.responses = responses }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        let response = responses.removeFirst()
        return (response.1, HTTPURLResponse(url: request.url!, statusCode: response.0, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!)
    }
}
