import XCTest

final class PersonalMarkDrawingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testContinuousDrawingSeparateStrokesErasingAndUndo() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["TSUTSUURA_DEMO_MODE"] = "authenticated"
        app.launch()

        let profile = app.buttons["home-tab-profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        profile.tap()
        let settings = app.buttons["設定"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let editMark = app.buttons["personal-mark-button"]
        XCTAssertTrue(editMark.waitForExistence(timeout: 5))
        reveal(editMark, in: app)
        editMark.tap()

        let canvas = app.descendants(matching: .any)
            .matching(identifier: "personal-mark-canvas").firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let clear = app.buttons["personal-mark-clear"]
        reveal(clear, in: app)
        clear.tap()
        reveal(canvas, in: app)
        XCTAssertEqual(paintedCells(in: canvas), 0)

        let firstStart = CGVector(dx: 2.5 / 16, dy: 2.5 / 16)
        let firstEnd = CGVector(dx: 13.5 / 16, dy: 7.5 / 16)
        let secondStart = CGVector(dx: 13.5 / 16, dy: 12.5 / 16)
        let secondEnd = CGVector(dx: 2.5 / 16, dy: 12.5 / 16)
        let originalFrame = canvas.frame
        stroke(on: canvas, from: firstStart, to: firstEnd)
        let firstStrokeCount = paintedCells(in: canvas)
        XCTAssertGreaterThanOrEqual(firstStrokeCount, 10, "A drag must paint a line, not just its initial touch.")
        XCTAssertEqual(canvas.frame.minY, originalFrame.minY, accuracy: 2, "Drawing must not scroll the page.")

        stroke(on: canvas, from: secondStart, to: secondEnd)
        let bothStrokeCount = paintedCells(in: canvas)
        XCTAssertEqual(bothStrokeCount, firstStrokeCount + 12, "The second stroke must paint all 12 cells without connecting to the previous stroke.")
        XCTAssertEqual(canvas.frame.minY, originalFrame.minY, accuracy: 2)

        let undo = app.buttons["personal-mark-undo"]
        reveal(undo, in: app)
        undo.tap()
        XCTAssertEqual(paintedCells(in: canvas), firstStrokeCount, "Undo must remove only the last stroke.")

        reveal(canvas, in: app)
        stroke(on: canvas, from: secondStart, to: secondEnd)
        XCTAssertEqual(paintedCells(in: canvas), bothStrokeCount)
        let erase = app.buttons["personal-mark-erase"]
        reveal(erase, in: app)
        erase.tap()
        reveal(canvas, in: app)
        stroke(on: canvas, from: secondStart, to: secondEnd)
        XCTAssertEqual(paintedCells(in: canvas), firstStrokeCount, "Erasing must follow the entire drag too.")

        reveal(undo, in: app)
        undo.tap()
        XCTAssertEqual(paintedCells(in: canvas), bothStrokeCount, "An erased stroke must be restorable with one undo.")
        undo.tap()
        XCTAssertEqual(paintedCells(in: canvas), firstStrokeCount)
        undo.tap()
        XCTAssertEqual(paintedCells(in: canvas), 0)
        XCTAssertFalse(app.buttons["personal-mark-save"].isEnabled)
        undo.tap()
        XCTAssertGreaterThan(paintedCells(in: canvas), 0, "Undoing the initial clear restores the previously saved mark.")
        XCTAssertFalse(undo.isEnabled)

        // Margin gestures still scroll the page, and the separate left edge
        // remains available for returning to settings after drawing.
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: 4, dy: app.frame.height * 0.55))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(
                CGVector(dx: app.frame.width * 0.8, dy: app.frame.height * 0.55)
            ))
        XCTAssertTrue(editMark.waitForExistence(timeout: 5))
    }

    @MainActor
    private func paintedCells(in canvas: XCUIElement) -> Int {
        guard let value = canvas.value as? String,
              let count = Int(value.prefix(while: { $0.isNumber })) else {
            XCTFail("The canvas should describe the number of painted cells for accessibility.")
            return -1
        }
        return count
    }

    @MainActor
    private func stroke(on canvas: XCUIElement, from start: CGVector, to end: CGVector) {
        canvas.coordinate(withNormalizedOffset: start)
            .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: end))
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            let save = app.buttons["personal-mark-save"]
            let bottom = save.exists ? save.frame.minY - 12 : app.frame.maxY - 24
            let top = app.frame.minY + 90
            if element.isHittable, element.frame.minY >= top, element.frame.maxY <= bottom { return }
            let shift = element.frame.minY < top
                ? min(220, top - element.frame.minY + 16)
                : -min(220, element.frame.maxY - bottom + 16)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = CGPoint(x: app.frame.width * 0.98, y: app.frame.height * 0.5)
            origin.withOffset(CGVector(dx: start.x, dy: start.y))
                .press(
                    forDuration: 0.05,
                    thenDragTo: origin.withOffset(CGVector(dx: start.x, dy: start.y + shift)),
                    withVelocity: .slow,
                    thenHoldForDuration: 0.25
                )
        }
        let saveFrame = app.buttons["personal-mark-save"].frame
        XCTFail("Could not reveal \(element.identifier) using the scrollable margin. Element: \(element.frame); app: \(app.frame); save: \(saveFrame).")
    }
}
