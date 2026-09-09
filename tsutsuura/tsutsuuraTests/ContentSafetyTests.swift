import Foundation
import XCTest
@testable import tsutsuura

@MainActor
final class ContentSafetyTests: XCTestCase {
    func testBlockSnapshotThenUnblockRestoresUnreportedContentAndPreservesFamily() async throws {
        let (store, transport) = try await fixture()
        let answer = try XCTUnwrap(store.home.feed?.answers.first)
        let family = store.home.feed?.family
        let result1 = await store.blockUser(answer.author)
        XCTAssertTrue(result1)
        XCTAssertTrue(store.home.feed?.answers.isEmpty == true)
        XCTAssertEqual(store.home.feed?.family, family)
        XCTAssertTrue(store.contentSafety.hiddenAnswerIDs.contains("answer"))
        let result2 = await store.unblockUser(userID: "other")
        XCTAssertTrue(result2)
        XCTAssertEqual(store.home.feed?.answers.map(\.id), ["answer"])
        XCTAssertTrue(store.contentSafety.hiddenAnswerIDs.isEmpty)
        let methods = await transport.mutationMethods
        XCTAssertEqual(methods, ["PUT", "DELETE"])
    }

    func testUnblockKeepsOppositeDirectionBlockHidden() async throws {
        let (store, transport) = try await fixture()
        let author = try XCTUnwrap(store.home.feed?.answers.first?.author)
        _ = await store.blockUser(author)
        await transport.setOppositeBlock(true)
        _ = await store.unblockUser(userID: author.id)
        XCTAssertTrue(store.contentSafety.blockedUsers.isEmpty)
        XCTAssertTrue(store.contentSafety.hiddenUserIDs.contains(author.id))
        XCTAssertTrue(store.home.feed?.answers.isEmpty == true)
    }

    func testReportedAnswerAndMediaStayHiddenAcrossUnblockAndNewSession() async throws {
        let (store, transport) = try await fixture()
        let answer = try XCTUnwrap(store.home.feed?.answers.first)
        let result3 = await store.reportAnswer(answerID: answer.id, reason: .privacy)
        XCTAssertTrue(result3)
        XCTAssertFalse(store.contentSafety.allowsMedia(id: "photo"))
        XCTAssertTrue(store.home.feed?.answers.isEmpty == true)
        _ = await store.blockUser(answer.author)
        _ = await store.unblockUser(userID: answer.author.id)
        XCTAssertTrue(store.home.feed?.answers.isEmpty == true)
        XCTAssertFalse(store.contentSafety.allowsMedia(id: "photo"))
        let secondStore = try makeStore(transport)
        await secondStore.restoreSession()
        XCTAssertTrue(secondStore.home.feed?.answers.isEmpty == true)
        XCTAssertTrue(secondStore.contentSafety.hiddenAnswerIDs.contains(answer.id))
    }

    func testReportedCommentDisappearsAndCannotReturnAfterRefresh() async throws {
        let (store, _) = try await fixture()
        _ = await store.loadComments(answerID: "answer")
        XCTAssertEqual(store.commentThreads["answer"]?.comments.count, 1)
        let result4 = await store.reportComment(commentID: "comment", answerID: "answer", reason: .harassment)
        XCTAssertTrue(result4)
        _ = await store.loadComments(answerID: "answer")
        XCTAssertTrue(store.commentThreads["answer"]?.comments.isEmpty == true)
        XCTAssertNotNil(store.contentSafety.feedback)
    }

    func testInFlightFeedCannotRestoreBlockedAnswer() async throws {
        let (store, transport) = try await fixture()
        let author = try XCTUnwrap(store.home.feed?.answers.first?.author)
        let started = expectation(description: "old feed started")
        await transport.pauseNext("home", onStart: { started.fulfill() })
        let oldFeed = Task { await store.refreshHome() }
        await fulfillment(of: [started], timeout: 2)
        _ = await store.blockUser(author)
        await transport.resume()
        await oldFeed.value
        XCTAssertTrue(store.home.feed?.answers.isEmpty == true)
    }

    func testInFlightCommentsCannotRestoreReportedComment() async throws {
        let (store, transport) = try await fixture()
        _ = await store.loadComments(answerID: "answer")
        let started = expectation(description: "old thread started")
        await transport.pauseNext("comments", onStart: { started.fulfill() })
        let oldThread = Task { await store.loadComments(answerID: "answer") }
        await fulfillment(of: [started], timeout: 2)
        _ = await store.reportComment(commentID: "comment", answerID: "answer", reason: .inappropriate)
        await transport.resume()
        _ = await oldThread.value
        XCTAssertTrue(store.commentThreads["answer"]?.comments.isEmpty == true)
        XCTAssertFalse(store.commentThreads["answer"]?.isLoading == true)
    }

    func testReportSharesWorkingGuardAndLateSuccessCannotMutateSignedOutSession() async throws {
        let (store, transport) = try await fixture()
        _ = await store.loadComments(answerID: "answer")
        let author = try XCTUnwrap(store.home.feed?.answers.first?.author)
        let started = expectation(description: "report started")
        await transport.pauseNext("reports", onStart: { started.fulfill() })
        let report = Task { await store.reportComment(commentID: "comment", answerID: "answer", reason: .spam) }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(store.contentSafety.isWorking)
        let result5 = await store.blockUser(author)
        XCTAssertFalse(result5)
        let result6 = await store.reportComment(commentID: "comment", answerID: "answer", reason: .spam)
        XCTAssertFalse(result6)
        await store.signOut()
        await transport.resume()
        let result7 = await report.value
        XCTAssertFalse(result7)
        XCTAssertEqual(store.session, .signedOut)
        XCTAssertTrue(store.commentThreads.isEmpty)
        XCTAssertNil(store.contentSafety.feedback)
    }

    func testUnavailableSafetyEndpointNeverClaimsBlockSuccess() async throws {
        let (store, transport) = try await fixture()
        let author = try XCTUnwrap(store.home.feed?.answers.first?.author)
        await transport.setFailsMutations(true)
        let result8 = await store.blockUser(author)
        XCTAssertFalse(result8)
        XCTAssertEqual(store.home.feed?.answers.count, 1)
        XCTAssertFalse(store.contentSafety.hiddenUserIDs.contains(author.id))
        XCTAssertNil(store.contentSafety.feedback)
        XCTAssertNotNil(store.contentSafety.errorMessage)
    }

    func testPendingSubmissionCannotRestoreModeratorHiddenAnswerOrMedia() async throws {
        let (store, transport) = try await fixture()
        let today = Question(id: "today", prompt: "今日の質問", publishedOn: "2026-09-07", answer: nil)
        store.question.question = today
        store.home.feed?.todayQuestion = today
        store.home.feed?.todayAnsweredUserIDs = []
        store.question.draft = "今日の回答"
        let started = expectation(description: "answer submission started")
        await transport.pauseNext("answer", onStart: { started.fulfill() })
        let submission = Task { await store.submitAnswer() }
        await fulfillment(of: [started], timeout: 2)
        await transport.setHiddenSubmission(true)
        _ = await store.loadContentSafety()
        await transport.resume()
        await submission.value
        XCTAssertNil(store.question.question?.answer)
        XCTAssertNil(store.home.feed?.myAnswer)
        XCTAssertFalse(store.home.feed?.answers.contains { $0.id == "submitted" } == true)
        XCTAssertFalse(store.history.answers.contains { $0.id == "submitted" })
        XCTAssertEqual(store.question.question?.hasAnswered, true)
        XCTAssertEqual(store.question.question?.answerHidden, true)
        XCTAssertEqual(store.question.question?.canAnswer, false)
        XCTAssertEqual(store.home.feed?.todayAnsweredUserIDs, ["user"])
        XCTAssertFalse(store.contentSafety.allowsMedia(id: "submitted-photo"))
        XCTAssertTrue(store.question.answerDraft.isEmpty)
    }

    func testPendingSubmissionCannotRestoreSignedOutSession() async throws {
        let (store, transport) = try await fixture()
        store.question.question = Question(id: "today", prompt: "今日の質問", publishedOn: "2026-09-07", answer: nil)
        store.question.draft = "今日の回答"
        let started = expectation(description: "answer submission started")
        await transport.pauseNext("answer", onStart: { started.fulfill() })
        let submission = Task { await store.submitAnswer() }
        await fulfillment(of: [started], timeout: 2)
        await store.signOut()
        await transport.resume()
        await submission.value
        XCTAssertEqual(store.session, .signedOut)
        XCTAssertNil(store.question.question)
        XCTAssertNil(store.home.feed)
        XCTAssertTrue(store.history.answers.isEmpty)
        XCTAssertTrue(store.contentSafety.mediaOwners.isEmpty)
        XCTAssertNil(store.question.errorMessage)
    }

    func testPendingCommentCannotRecreateBlockedThread() async throws {
        let (store, transport) = try await fixture()
        let answer = try XCTUnwrap(store.home.feed?.answers.first)
        _ = await store.loadComments(answerID: answer.id)
        store.setCommentDraft("新しいコメント", answerID: answer.id)
        let started = expectation(description: "comment send started")
        await transport.pauseNext("comments", onStart: { started.fulfill() })
        let post = Task { await store.postComment(answerID: answer.id) }
        await fulfillment(of: [started], timeout: 2)
        _ = await store.blockUser(answer.author)
        await transport.resume()
        await post.value
        XCTAssertNil(store.commentThreads[answer.id])
    }

    func testPendingReplyCannotRecreateSignedOutSession() async throws {
        let (store, transport) = try await fixture()
        _ = await store.loadComments(answerID: "answer")
        let started = expectation(description: "reply send started")
        await transport.pauseNext("comments", onStart: { started.fulfill() })
        let reply = Task { await store.replyToComment(answerID: "answer", parentCommentID: "comment", body: "返信") }
        await fulfillment(of: [started], timeout: 2)
        await store.signOut()
        await transport.resume()
        let succeeded = await reply.value
        XCTAssertFalse(succeeded)
        XCTAssertTrue(store.commentThreads.isEmpty)
        XCTAssertNil(store.contentSafety.feedback)
    }

    func testInFlightMediaCannotReopenAfterReport() async throws {
        let (store, transport) = try await fixture()
        let answer = try XCTUnwrap(store.home.feed?.answers.first)
        let photo = try XCTUnwrap(answer.media.first)
        let started = expectation(description: "photo request started")
        await transport.pauseNext("photo", onStart: { started.fulfill() })
        let photoTask = Task { try await store.fetchAnswerMedia(photo) }
        await fulfillment(of: [started], timeout: 2)
        _ = await store.reportAnswer(answerID: answer.id, reason: .privacy)
        await transport.resume()
        do {
            _ = try await photoTask.value
            XCTFail("A hidden photo must not return to its former viewer")
        } catch is CancellationError { }
        catch { XCTFail("Expected safety cancellation, received \(error)") }
    }

    func testModeratorHiddenOwnAnswerClosesComposerAndPurgesEveryCachedCopy() async throws {
        let (store, transport) = try await fixture()
        var answer = try XCTUnwrap(store.home.feed?.answers.first)
        answer.author = AnswerAuthor(id: "user", displayName: "あなた")
        store.home.feed?.answers = [answer]
        let today = Question(id: "today", prompt: "今日の質問", publishedOn: "2026-09-07", answer: answer)
        store.home.feed?.myAnswer = answer
        store.home.feed?.todayQuestion = today
        store.question.question = today
        await transport.setReportedAnswer(true)
        _ = await store.loadContentSafety()
        XCTAssertNil(store.home.feed?.myAnswer)
        XCTAssertNil(store.home.feed?.todayQuestion?.answer)
        XCTAssertNil(store.question.question?.answer)
        XCTAssertEqual(store.question.question?.hasAnswered, true)
        XCTAssertEqual(store.question.question?.answerHidden, true)
        XCTAssertEqual(store.question.question?.canAnswer, false)
        XCTAssertFalse(store.contentSafety.allowsMedia(id: "photo"))
        let json = Data(#"{"id":"today","prompt":"今日の質問","date":"2026-09-07","answer":null,"hasAnswered":true,"answerHidden":true}"#.utf8)
        let decoded = try JSONDecoder().decode(Question.self, from: json)
        XCTAssertFalse(decoded.canAnswer)
    }

    func testBundledLicensesContainFullRequiredNotices() {
        let sections = InformationDocument.licenses.sections
        XCTAssertEqual(sections.count, 3)
        XCTAssertTrue(sections[2].1.contains("TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION"))
        XCTAssertTrue(sections[2].1.contains("END OF TERMS AND CONDITIONS"))
        XCTAssertTrue(sections[1].1.contains("廻想体"))
    }

    private func fixture() async throws -> (AppStore, SafetyFixtureTransport) {
        let transport = SafetyFixtureTransport()
        let store = try makeStore(transport)
        await store.restoreSession()
        _ = try XCTUnwrap(store.home.feed?.answers.first, "Fixture must decode a real home feed: \(store.home.errorMessage ?? "no reported error")")
        let loaded = await store.loadComments(answerID: "answer")
        XCTAssertTrue(loaded, "Fixture comment page must decode successfully")
        _ = try XCTUnwrap(store.commentThreads["answer"]?.comments.first, "Fixture must begin with a visible comment")
        return (store, transport)
    }
    private func makeStore(_ transport: SafetyFixtureTransport) throws -> AppStore {
        AppStore(api: DefaultAppAPI(configuration: try APIConfiguration(baseURL: APIConfiguration.productionBaseURL), transport: transport,
            tokenStore: InMemoryTokenStore(token: "safety-fixture-token"), retryPolicy: .disabled,
            mutationProtectionKey: Data(repeating: 7, count: 32)), haptics: NoopHaptics())
    }
}

private actor SafetyFixtureTransport: HTTPTransport {
    private var blocked = false
    private var oppositeBlock = false
    private var reportedAnswer = false
    private var reportedComment = false
    private var hiddenSubmission = false
    private var failsMutations = false
    private var pauseSuffix: String?
    private var onStart: (@Sendable () -> Void)?
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var mutationMethods: [String] = []
    func pauseNext(_ suffix: String, onStart: @escaping @Sendable () -> Void) { pauseSuffix = suffix; self.onStart = onStart }
    func resume() { continuation?.resume(); continuation = nil }
    func setHiddenSubmission(_ value: Bool) { hiddenSubmission = value }
    func setReportedAnswer(_ value: Bool) { reportedAnswer = value }
    func setOppositeBlock(_ value: Bool) { oppositeBlock = value }
    func setFailsMutations(_ value: Bool) { failsMutations = value }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let method = request.value(forHTTPHeaderField: "X-HTTP-Method-Override") ?? request.httpMethod ?? "GET"
        let path = url.path
        let other: [String: Any] = ["id": "other", "displayName": "あおい"]
        let own: [String: Any] = ["id": "user", "displayName": "あなた", "avatarMark": "1" + String(repeating: "0", count: 255)]
        let family: [String: Any] = ["id": "family", "name": "家族", "memberCount": 2, "members": [own, other]]
        let answer: [String: Any] = ["id": "answer", "question": ["id": "question", "prompt": "最近うれしかったことは？"], "author": other, "body": "ありがとう", "createdAt": "2026-09-07T09:00:00Z", "media": [["id": "photo", "kind": "photo", "url": "https://toshizo.link/tsutsuura-api/api/v1/answers/answer/media/photo", "mimeType": "image/png", "byteCount": 10]]]
        let comment: [String: Any] = ["id": "comment", "answerId": "answer", "author": other, "body": "こんにちは", "createdAt": "2026-09-07T09:00:00Z"]
        var data: [String: Any] = [:]
        var status = 200
        if path.hasSuffix("/me") { data = ["user": own.merging(["family": family]) { _, new in new }] }
        else if path.hasSuffix("/blocks/other") {
            mutationMethods.append(method)
            if failsMutations { status = 404 } else { blocked = method == "PUT" }
        } else if path.hasSuffix("/blocks") {
            let invisible = blocked || oppositeBlock
            data = ["users": blocked ? [other] : [], "hiddenUserIds": invisible ? ["other"] : [], "hiddenAnswerIds": (invisible || reportedAnswer ? ["answer"] : []) + (hiddenSubmission ? ["submitted"] : []), "hiddenCommentIds": invisible || reportedComment ? ["comment"] : []]
        } else if path.hasSuffix("/reports") {
            if path.contains("/comments/") { reportedComment = true } else { reportedAnswer = true }
            data = ["report": ["id": "report", "status": "pending"]]
        } else if path.hasSuffix("/comments") {
            data = method == "POST" ? ["comment": comment.merging(["id": "new-comment", "author": own]) { _, value in value }]
                : ["items": reportedComment || blocked || oppositeBlock ? [] : [comment]]
        } else if path.hasSuffix("/today/answer") {
            let photo: [String: Any] = ["id": "submitted-photo", "kind": "photo", "url": "https://toshizo.link/tsutsuura-api/api/v1/answers/submitted/media/submitted-photo", "mimeType": "image/png"]
            data = ["answer": answer.merging(["id": "submitted", "author": own,
                "question": ["id": "today", "prompt": "今日の質問"], "answerDate": "2026-09-07", "media": [photo]]) { _, value in value }]
        } else if path.hasSuffix("/home") {
            data = ["family": family, "feed": blocked || oppositeBlock || reportedAnswer ? [] : [answer]]
        } else if path.hasSuffix("/answers") { data = ["items": []] }
        let body = try JSONSerialization.data(withJSONObject: status == 200 ? ["data": data] : ["error": ["code": "not_found", "message": "現在この操作は利用できません。"]])
        if let suffix = pauseSuffix, path.hasSuffix(suffix) {
            pauseSuffix = nil
            await withCheckedContinuation { continuation in self.continuation = continuation; onStart?() }
        }
        return (body, HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!)
    }
}
