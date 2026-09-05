import XCTest

/// Captures the real UI with fictional local content for the Japanese store page.
final class AppStoreScreenshotUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureJapaneseStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["TSUTSUURA_DEMO_MODE"] = "authenticated"
        app.launch()
        XCTAssertTrue(app.buttons["home-tab-family"].waitForExistence(timeout: 10))
        capture(app, named: "store-01-family")

        app.buttons["回答する"].tap()
        XCTAssertTrue(app.textViews["answer-input"].waitForExistence(timeout: 5))
        capture(app, named: "store-02-answer")

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["home-tab-profile"].waitForExistence(timeout: 5))
        app.buttons["home-tab-profile"].tap()
        XCTAssertTrue(app.buttons["設定"].waitForExistence(timeout: 5))
        capture(app, named: "store-03-history")
        app.buttons["設定"].tap()
        let mark = app.buttons["personal-mark-button"]
        XCTAssertTrue(mark.waitForExistence(timeout: 5))
        XCTAssertTrue(mark.isHittable)
        mark.tap()
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(identifier: "personal-mark-canvas").firstMatch.waitForExistence(timeout: 5))
        capture(app, named: "store-04-personal-mark")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
