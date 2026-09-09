import XCTest

final class ContentSafetyUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testReportAnswerIncludesMediaAndHidesItFromFamilyTimeline() {
        let app = launchDemo(gallery: true)
        let safety = app.buttons["answer-safety-demo-answer-family"]
        reveal(safety, in: app)
        safety.tap()
        XCTAssertTrue(app.staticTexts["この回答を報告する"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "添付された写真・音声")).firstMatch.exists)
        let reason = app.buttons["safety-reason-privacy"]
        reveal(reason, in: app)
        reason.tap()
        let submit = app.buttons["safety-report-submit"]
        reveal(submit, in: app)
        submit.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "safety-feedback").firstMatch.waitForExistence(timeout: 5))
        capture(app, named: "answer-and-media-reported")
        backFromSafety(app)
        XCTAssertTrue(app.buttons["home-tab-family"].waitForExistence(timeout: 4))
        XCTAssertFalse(safety.exists)
        XCTAssertFalse(app.buttons["answer-photo-1-of-3"].exists)
    }

    @MainActor
    func testBlockAndUnblockFromSettingsRestoresFamilyAnswer() {
        let app = launchDemo()
        let safety = app.buttons["answer-safety-demo-answer-family"]
        reveal(safety, in: app)
        safety.tap()
        let block = app.buttons["safety-block-button"]
        reveal(block, in: app)
        block.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
        app.alerts.buttons["ブロックする"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "safety-feedback").firstMatch.waitForExistence(timeout: 5))
        capture(app, named: "family-user-blocked")
        backFromSafety(app)
        XCTAssertFalse(safety.exists)
        app.buttons["home-tab-profile"].tap()
        app.buttons["設定"].tap()
        let blockedUsers = app.buttons["blocked-users-button"]
        reveal(blockedUsers, in: app)
        blockedUsers.tap()
        let unblock = app.buttons["unblock-user-demo-family-1"]
        reveal(unblock, in: app)
        capture(app, named: "blocked-user-settings")
        unblock.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
        app.alerts.buttons["解除する"].tap()
        XCTAssertTrue(unblock.waitForNonExistence(timeout: 5))
        app.buttons["lifecycle-back-button"].tap()
        let back = app.buttons["戻る"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 4))
        reveal(back, in: app)
        back.tap()
        app.buttons["home-tab-family"].tap()
        reveal(safety, in: app)
        XCTAssertTrue(safety.exists)
        capture(app, named: "unblocked-answer-restored")
    }

    @MainActor
    func testReportCommentHidesItAndKeepsOtherComments() {
        let app = launchDemo()
        let comments = app.buttons["answer-comments-demo-answer-family"]
        reveal(comments, in: app)
        comments.tap()
        let report = app.buttons["comment-safety-demo-comment-2"]
        reveal(report, in: app)
        report.tap()
        XCTAssertTrue(app.staticTexts["このコメントを報告する"].waitForExistence(timeout: 4))
        let submit = app.buttons["safety-report-submit"]
        reveal(submit, in: app)
        submit.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "safety-feedback").firstMatch.waitForExistence(timeout: 5))
        backFromSafety(app)
        XCTAssertFalse(report.exists)
        XCTAssertFalse(app.staticTexts["もちろん。アルバムにしておくね。"].exists)
        XCTAssertTrue(app.staticTexts["その写真、今度わたしにも見せて！"].exists)
        capture(app, named: "reported-comment-removed")
    }

    @MainActor
    private func launchDemo(gallery: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["TSUTSUURA_DEMO_MODE"] = "authenticated"
        if gallery { app.launchArguments = ["-tsutsuura-demo-gallery"] }
        app.launch()
        XCTAssertTrue(app.buttons["home-tab-family"].waitForExistence(timeout: 6))
        return app
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 4), file: file, line: line)
        for _ in 0..<18 {
            let answerButton = app.buttons["回答する"]
            let familyTab = app.buttons["home-tab-family"]
            let composer = app.textFields["comment-input"]
            let top = familyTab.exists && answerButton.exists ? answerButton.frame.maxY + 20 : app.frame.minY + 20
            let bottom = familyTab.exists ? familyTab.frame.minY - 12
                : composer.exists ? composer.frame.minY - 16 : app.frame.maxY - 16
            let frame = element.frame
            if frame.minY >= top && frame.maxY <= bottom && element.isHittable { return }
            let shift = frame.minY < top ? min(140, top - frame.minY + 12)
                : -min(140, max(24, frame.maxY - bottom + 12))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = CGVector(dx: app.frame.width * (familyTab.exists ? 0.95 : 0.70), dy: (top + bottom) / 2)
            origin.withOffset(start).press(forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: start.dx, dy: start.dy + shift)),
                withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTFail("Control must be reachable by scrolling", file: file, line: line)
    }

    @MainActor
    private func backFromSafety(_ app: XCUIApplication) {
        let back = app.buttons["lifecycle-back-button"]
        reveal(back, in: app)
        back.tap()
    }

    @MainActor
    private func capture(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
