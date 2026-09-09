import XCTest

/// Explicitly opted-in UI smoke test for an already provisioned disposable QA
/// account. Normal test runs skip it; no credentials or demo launch flags are used.
final class ControlledLiveAccountUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testControlledFixtureMarkAndPreferencesPersistOnLiveBackend() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["TSUTSUURA_RUN_CONTROLLED_LIVE_QA"] == "1")
        let suffix = try XCTUnwrap(environment["TSUTSUURA_LIVE_QA_SUFFIX"])
        XCTAssertNotNil(suffix.range(of: "^[a-f0-9]{8}$", options: .regularExpression))
        let expectedName = "Simulator QA あなた \(suffix)"
        let expectedFamily = "Simulator QA \(suffix)"
        let app = XCUIApplication()
        app.launch()
        openSettings(in: app)
        assertFixture(in: app, name: expectedName, family: expectedFamily)
        capture(app, named: "live-qa-verified-fixture")

        openMark(in: app)
        let initial = app.buttons["personal-mark-initial"]
        reveal(initial, in: app)
        initial.tap()
        let canvas = app.descendants(matching: .any)
            .matching(identifier: "personal-mark-canvas").firstMatch
        reveal(canvas, in: app)
        XCTAssertEqual(paintedCells(in: canvas), 0)
        let initialY = canvas.frame.minY
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 2.5 / 16, dy: 3.5 / 16))
            .press(
                forDuration: 0.05,
                thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 13.5 / 16, dy: 11.5 / 16)),
                withVelocity: .slow,
                thenHoldForDuration: 0.15
            )
        let savedCount = paintedCells(in: canvas)
        XCTAssertGreaterThanOrEqual(savedCount, 12, "A continuous stroke must reach its final cells.")
        XCTAssertEqual(canvas.frame.minY, initialY, accuracy: 2)
        capture(app, named: "live-qa-continuous-drawing")
        app.buttons["personal-mark-save"].tap()
        XCTAssertTrue(app.buttons["personal-mark-button"].waitForExistence(timeout: 20), "The live backend must accept the mark save.")
        assertFixture(in: app, name: expectedName, family: expectedFamily)
        openMark(in: app)
        XCTAssertEqual(paintedCells(in: canvas), savedCount)
        reveal(canvas, in: app)
        capture(app, named: "live-qa-reopened-saved-mark")

        app.terminate()
        app.launch()
        openSettings(in: app)
        assertFixture(in: app, name: expectedName, family: expectedFamily)
        openMark(in: app)
        XCTAssertEqual(paintedCells(in: canvas), savedCount, "The live mark must survive terminating and relaunching the app.")
        reveal(canvas, in: app)
        capture(app, named: "live-qa-mark-after-relaunch")
        goBack(in: app)
        assertFixture(in: app, name: expectedName, family: expectedFamily)

        // Preserve every preference and do not request notification permission.
        let notices = app.buttons["notification-settings-button"]
        reveal(notices, in: app)
        notices.tap()
        let daily = app.switches["notification-daily-toggle"]
        let family = app.switches["notification-family-toggle"]
        XCTAssertTrue(daily.waitForExistence(timeout: 10))
        let originalDaily = daily.value as? String
        let originalFamily = family.value as? String
        let save = app.buttons["notification-save-button"]
        reveal(save, in: app)
        capture(app, named: "live-qa-unchanged-notification-preferences")
        save.tap()
        XCTAssertTrue(notices.waitForExistence(timeout: 20), "The live backend must accept an unchanged preference save.")
        assertFixture(in: app, name: expectedName, family: expectedFamily)
        reveal(notices, in: app)
        notices.tap()
        XCTAssertTrue(daily.waitForExistence(timeout: 10))
        XCTAssertEqual(daily.value as? String, originalDaily)
        XCTAssertEqual(family.value as? String, originalFamily)
        capture(app, named: "live-qa-reloaded-notification-preferences")
        goBack(in: app)
    }

    @MainActor
    private func openSettings(in app: XCUIApplication) {
        let profile = app.buttons["home-tab-profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 20), "An existing authenticated QA session is required; this test does not sign in.")
        profile.tap()
        let settings = app.buttons["設定"]
        let foundSettings = settings.waitForExistence(timeout: 10)
        if !foundSettings {
            capture(app, named: "live-qa-home-navigation-failure")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "live-qa-home-navigation-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(foundSettings)
        settings.tap()
        XCTAssertTrue(app.textFields["settings-name-input"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func assertFixture(in app: XCUIApplication, name: String, family: String) {
        let field = app.textFields["settings-name-input"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertEqual(field.value as? String, name, "Refusing to mutate any account other than the explicitly selected disposable QA fixture.")
        let familyLabel = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", family + " · ")).firstMatch
        XCTAssertTrue(familyLabel.exists, "The exact controlled QA family must also match before proceeding.")
    }

    @MainActor
    private func openMark(in app: XCUIApplication) {
        let edit = app.buttons["personal-mark-button"]
        reveal(edit, in: app)
        edit.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "personal-mark-canvas").firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor
    private func paintedCells(in canvas: XCUIElement) -> Int {
        guard let value = canvas.value as? String,
              let count = Int(value.prefix(while: { $0.isNumber })) else {
            XCTFail("The canvas must report its painted-cell count.")
            return -1
        }
        return count
    }

    @MainActor
    private func goBack(in app: XCUIApplication) {
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: 4, dy: app.frame.height * 0.5))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: app.frame.width * 0.8, dy: app.frame.height * 0.5)))
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.exists)
        for _ in 0..<12 {
            let save = app.buttons["personal-mark-save"]
            let bottom = save.exists ? save.frame.minY - 12 : app.frame.maxY - 36
            let top = app.frame.minY + 100
            let frame = element.frame
            if element.isHittable, frame.minY >= top, frame.maxY <= bottom { return }
            let shift = frame.minY < top
                ? min(250, top - frame.minY + 16)
                : -min(250, frame.maxY - bottom + 16)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let x = app.frame.width * 0.98
            let y = app.frame.height * 0.5
            origin.withOffset(CGVector(dx: x, dy: y))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: x, dy: y + shift)), withVelocity: .slow, thenHoldForDuration: 0.25)
        }
        capture(app, named: "live-qa-element-reveal-failure")
        XCTFail("Could not reveal \(element.identifier): \(element.frame)")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
