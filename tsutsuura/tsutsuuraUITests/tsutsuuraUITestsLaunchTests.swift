import XCTest

final class tsutsuuraUITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["TSUTSUURA_DEMO_MODE"] = "signedOut"
        app.launch()

        XCTAssertTrue(app.buttons["create-family-button"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["setup-this-iphone-button"].exists)
        XCTAssertTrue(app.buttons["returning-user-login-button"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Family Welcome"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
