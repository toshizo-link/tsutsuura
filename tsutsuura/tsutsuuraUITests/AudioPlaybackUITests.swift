import XCTest

final class AudioPlaybackUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testPublishedVoicePlaybackPauseAndResumeControls() {
        let app = launchDemo(arguments: ["-tsutsuura-demo-audio-playback"])
        let audio = app.buttons["answer-audio-demo-playback-audio"]
        reveal(audio, in: app)
        audio.tap()
        waitForValue("再生中", on: audio)
        XCTAssertFalse(app.staticTexts["answer-audio-error-demo-playback-audio"].exists)
        capture(app, named: "voice-answer-playing")
        audio.tap()
        waitForValue("停止中", on: audio)
        audio.tap()
        waitForValue("再生中", on: audio)
        app.buttons["home-tab-profile"].tap()
        XCTAssertTrue(app.buttons["設定"].waitForExistence(timeout: 4))
    }

    @MainActor
    func testRecordedDraftCanBePreviewedPausedAndRemoved() {
        let app = launchDemo(arguments: ["-tsutsuura-demo-voice-success"])
        app.buttons["回答する"].tap()
        let voice = app.buttons["声で回答"]
        reveal(voice, in: app)
        voice.tap()
        // The control exists during the countdown; wait for the completed
        // capture and enabled action before transferring its actual AAC bytes.
        XCTAssertTrue(app.staticTexts["今日は家族と散歩をしました"].waitForExistence(timeout: 8))
        let useRecording = app.buttons["voice-use-answer-button"]
        XCTAssertTrue(useRecording.waitForExistence(timeout: 3))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: useRecording)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 4), .completed)
        reveal(useRecording, in: app)
        useRecording.tap()
        let preview = app.buttons["draft-audio-preview-button"]
        reveal(preview, in: app)
        preview.tap()
        waitForValue("再生中", on: preview)
        preview.tap()
        waitForValue("停止中", on: preview)
        XCTAssertFalse(app.staticTexts["draft-audio-error"].exists)
        capture(app, named: "voice-draft-listen-before-sending")
        app.buttons["draft-audio-remove-button"].tap()
        XCTAssertTrue(preview.waitForNonExistence(timeout: 3))
    }

    @MainActor
    private func launchDemo(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["TSUTSUURA_DEMO_MODE"] = "authenticated"
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.buttons["home-tab-family"].waitForExistence(timeout: 6))
        return app
    }

    @MainActor
    private func waitForValue(_ value: String, on element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        for _ in 0..<18 {
            let familyTab = app.buttons["home-tab-family"]
            let answer = app.buttons["回答する"]
            let top = familyTab.exists && answer.exists ? answer.frame.maxY + 20 : app.frame.minY + 20
            let bottom = familyTab.exists ? familyTab.frame.minY - 12 : app.frame.maxY - 24
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
        XCTFail("Audio control must be reachable", file: file, line: line)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
