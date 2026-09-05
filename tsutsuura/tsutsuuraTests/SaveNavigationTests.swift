import Foundation
import XCTest
@testable import tsutsuura

@MainActor
final class SaveNavigationTests: XCTestCase {
    func testNotificationSaveFinishesWithoutDismissingPageOpenedAfterBack() async throws {
        let entered = expectation(description: "notification save reached server")
        let transport = DeferredPageSaveTransport { entered.fulfill() }
        let store = try makeStore(transport: transport)
        store.path = [.home, .settings, .notificationSettings]
        let visit = store.navigationVisit()
        let preferences = NotificationPreferences(dailyReminderEnabled: false)
        let saving = Task {
            await store.finishSave(from: visit) {
                await store.updateNotificationPreferences(preferences)
            }
        }
        await fulfillment(of: [entered], timeout: 2)
        XCTAssertTrue(store.notificationPreferences.isSaving)
        store.path.removeLast()
        store.path.append(.help)
        await transport.finish()

        let mayDismiss = await saving.value
        XCTAssertFalse(mayDismiss)
        XCTAssertEqual(store.path, [.home, .settings, .help])
        XCTAssertEqual(store.notificationPreferences.preferences, preferences,
                       "Leaving the page must not discard the requested save")
        XCTAssertFalse(store.notificationPreferences.isSaving)
    }

    func testOldCommentSaveCannotDismissAReopenedVisitToTheSameEditor() async throws {
        let entered = expectation(description: "comment save reached server")
        let transport = DeferredPageSaveTransport { entered.fulfill() }
        let store = try makeStore(transport: transport)
        let comment = Comment(id: "comment", answerID: "answer",
                              author: AnswerAuthor(id: "user", displayName: "家族"),
                              body: "前のコメント", createdAt: Date(timeIntervalSince1970: 0))
        store.commentThreads["answer"] = CommentThreadState(comments: [comment])
        let editor = AppRoute.commentEditor(commentID: "comment", answerID: "answer")
        store.path = [.home, .comments(answerID: "answer"), editor]
        let visit = store.navigationVisit()
        let saving = Task {
            await store.finishSave(from: visit) {
                await store.updateComment(commentID: "comment", answerID: "answer", body: "ありがとう")
            }
        }
        await fulfillment(of: [entered], timeout: 2)
        store.path.removeLast()
        store.path.append(editor)
        await transport.finish()

        let mayDismiss = await saving.value
        XCTAssertFalse(mayDismiss, "Equal route arrays can represent separate visits")
        XCTAssertEqual(store.path.last, editor)
        XCTAssertEqual(store.commentThreads["answer"]?.comments.first?.body, "ありがとう")
        XCTAssertEqual(store.commentThreads["answer"]?.isMutating, false)
    }

    func testSaveOnTheOriginalVisitCanStillDismissAfterSuccess() async throws {
        let entered = expectation(description: "save reached server")
        let transport = DeferredPageSaveTransport { entered.fulfill() }
        let store = try makeStore(transport: transport)
        store.path = [.home, .settings, .notificationSettings]
        let visit = store.navigationVisit()
        let saving = Task {
            await store.finishSave(from: visit) {
                await store.updateNotificationPreferences(NotificationPreferences())
            }
        }
        await fulfillment(of: [entered], timeout: 2)
        await transport.finish()
        let mayDismiss = await saving.value
        XCTAssertTrue(mayDismiss)
        XCTAssertNil(store.notificationPreferences.errorMessage)
    }

    private func makeStore(transport: DeferredPageSaveTransport) throws -> AppStore {
        AppStore(api: DefaultAppAPI(
            configuration: try APIConfiguration(baseURL: APIConfiguration.productionBaseURL),
            transport: transport,
            tokenStore: InMemoryTokenStore(token: "fixture-bearer"),
            retryPolicy: .disabled,
            mutationProtectionKey: Data(repeating: 1, count: 32)
        ), haptics: NoopHaptics())
    }
}

private actor DeferredPageSaveTransport: HTTPTransport {
    private let onStart: @Sendable () -> Void
    private var continuation: CheckedContinuation<Void, Never>?

    init(onStart: @escaping @Sendable () -> Void) { self.onStart = onStart }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            onStart()
        }
        let data: Data
        if request.url?.lastPathComponent == "notification-preferences" {
            let preferences = try JSONSerialization.jsonObject(with: request.httpBody!)
            data = try JSONSerialization.data(withJSONObject: ["data": ["preferences": preferences]])
        } else {
            data = Data(#"{"data":{"comment":{"id":"comment","answerId":"answer","author":{"id":"user","displayName":"家族"},"body":"ありがとう","createdAt":"2026-09-05T12:00:00Z"}}}"#.utf8)
        }
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }

    func finish() { continuation?.resume(); continuation = nil }
}
