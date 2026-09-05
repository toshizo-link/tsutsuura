import Foundation
import XCTest
@testable import tsutsuura

final class ProductionConfigurationTests: XCTestCase {
    func testBundledAPIAndUniversalLinkHostUseToshizo() throws {
        let configuration = try APIConfiguration.fromInfoDictionary()
        XCTAssertEqual(configuration.baseURL, APIConfiguration.productionBaseURL)
        XCTAssertEqual(configuration.baseURL.absoluteString, "https://toshizo.link/tsutsuura-api/api")
        XCTAssertEqual(configuration.baseURL.host, PairingLinkParser.productionHost)
        let token = String(repeating: "a", count: 48)
        let invitation = configuration.baseURL.appendingPathComponent("invite").appendingPathComponent(token)
        XCTAssertEqual(PairingLinkParser.token(from: invitation), token)
    }

    func testPendingVerificationStorageIsIsolatedAcrossServerRoots() throws {
        let newConfiguration = try APIConfiguration(baseURL: APIConfiguration.productionBaseURL)
        let oldConfiguration = try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://kttprojects.conohawing.com/tsutsuura-api/api")))
        XCTAssertNotEqual(newConfiguration.verificationStorageSuiteName, oldConfiguration.verificationStorageSuiteName)
        XCTAssertNotEqual(newConfiguration.verificationStorageSuiteName, Bundle.main.bundleIdentifier)
        let suffix = ".tests.\(UUID().uuidString)"
        let oldSuite = oldConfiguration.verificationStorageSuiteName + suffix
        let newSuite = newConfiguration.verificationStorageSuiteName + suffix
        let oldDefaults = try XCTUnwrap(UserDefaults(suiteName: oldSuite))
        let newDefaults = try XCTUnwrap(UserDefaults(suiteName: newSuite))
        defer {
            oldDefaults.removePersistentDomain(forName: oldSuite)
            newDefaults.removePersistentDomain(forName: newSuite)
        }
        let key = "jp.tsutsuura.pending-email-login-verification.v1"
        oldDefaults.set(Data("old-server-challenge".utf8), forKey: key)
        XCTAssertNil(newDefaults.data(forKey: key))
    }

    @MainActor
    func testOldServerBearerReturnsToSetupWhenNewServerRejectsIt() async throws {
        let tokenStore = InMemoryTokenStore(token: "old-server-bearer")
        let transport = MigrationUnauthorizedTransport()
        let api = DefaultAppAPI(
            configuration: try APIConfiguration(baseURL: APIConfiguration.productionBaseURL),
            transport: transport,
            tokenStore: tokenStore,
            retryPolicy: .disabled,
            mutationProtectionKey: Data(repeating: 1, count: 32)
        )
        let store = AppStore(api: api, haptics: NoopHaptics())
        await store.restoreSession()
        XCTAssertEqual(store.session, .signedOut)
        XCTAssertEqual(store.path, [.onboarding])
        XCTAssertNil(store.home.feed)
        let remainingToken = await tokenStore.readToken()
        XCTAssertNil(remainingToken)
        let recordedRequest = await transport.request
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.url?.host, "toshizo.link")
        XCTAssertEqual(request.url?.path, "/tsutsuura-api/api/v1/me")
    }
}

private actor MigrationUnauthorizedTransport: HTTPTransport {
    private(set) var request: URLRequest?

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        return (
            Data(#"{"error":{"code":"unauthorized","message":"Invalid session."}}"#.utf8),
            HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        )
    }
}
