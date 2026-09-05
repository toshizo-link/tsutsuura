import XCTest

final class AnswerPhotoFullscreenUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTappedPhotoOpensFullscreenAndPagesWithinItsAnswer() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["TSUTSUURA_DEMO_MODE"] = "authenticated"
        app.launchArguments.append("-tsutsuura-demo-gallery")
        app.launch()

        let inlineGallery = app.descendants(matching: .any)
            .matching(identifier: "answer-photo-gallery").firstMatch
        XCTAssertTrue(inlineGallery.waitForExistence(timeout: 10))
        revealGallery(inlineGallery, in: app)
        let inlineCounter = app.staticTexts["answer-photo-page-indicator"]
        let close = app.buttons["answer-fullscreen-photo-close"]
        let firstThumbnail = photo(1, fullScreen: false, in: app)
        assertThumbnailBounds(firstThumbnail, within: inlineGallery)
        firstThumbnail.swipeLeft()
        waitForPhoto(2, counter: inlineCounter)
        XCTAssertFalse(close.exists, "Swiping the inline gallery must not open full screen.")

        photo(2, fullScreen: false, in: app).tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let counter = app.staticTexts["answer-fullscreen-photo-page-indicator"]
        waitForPhoto(2, counter: counter)
        XCTAssertTrue(photo(2, fullScreen: true, in: app).isHittable)
        capture(app, named: "fullscreen-photo-starts-at-tapped-second-landscape-image")

        photo(2, fullScreen: true, in: app).swipeLeft()
        waitForPhoto(3, counter: counter)
        capture(app, named: "fullscreen-third-square-image")
        photo(3, fullScreen: true, in: app).swipeRight()
        waitForPhoto(2, counter: counter)
        photo(2, fullScreen: true, in: app).swipeRight()
        waitForPhoto(1, counter: counter)
        capture(app, named: "fullscreen-first-portrait-image")
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        waitForPhoto(1, counter: inlineCounter)

        // A second presentation gets a fresh selection and can close normally.
        photo(1, fullScreen: false, in: app).tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        waitForPhoto(1, counter: counter)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        XCTAssertTrue(inlineGallery.isHittable)
    }

    @MainActor
    func testDownwardSwipeDismissesButShortUpwardAndHorizontalDragsDoNot() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["TSUTSUURA_DEMO_MODE"] = "authenticated"
        app.launchArguments.append("-tsutsuura-demo-gallery")
        app.launch()

        let inlineGallery = app.descendants(matching: .any)
            .matching(identifier: "answer-photo-gallery").firstMatch
        XCTAssertTrue(inlineGallery.waitForExistence(timeout: 10))
        revealGallery(inlineGallery, in: app)
        let firstThumbnail = photo(1, fullScreen: false, in: app)
        assertThumbnailBounds(firstThumbnail, within: inlineGallery)
        firstThumbnail.tap()

        let close = app.buttons["answer-fullscreen-photo-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let counter = app.staticTexts["answer-fullscreen-photo-page-indicator"]
        waitForPhoto(1, counter: counter)
        let fullScreenGallery = app.descendants(matching: .any)
            .matching(identifier: "answer-fullscreen-photo-gallery").firstMatch
        let restingTop = fullScreenGallery.frame.minY

        verticalDrag(in: fullScreenGallery, app: app, distance: 42)
        XCTAssertTrue(close.exists, "A short downward drag must spring back instead of closing.")
        waitForRestingPosition(photo(1, fullScreen: true, in: app), top: restingTop)
        waitForPhoto(1, counter: counter)

        verticalDrag(in: fullScreenGallery, app: app, distance: -150)
        XCTAssertTrue(close.exists, "An upward swipe must not dismiss the photo.")
        waitForRestingPosition(photo(1, fullScreen: true, in: app), top: restingTop)
        waitForPhoto(1, counter: counter)

        photo(1, fullScreen: true, in: app).swipeLeft()
        waitForPhoto(2, counter: counter)
        XCTAssertTrue(close.exists, "Horizontal paging must remain available after cancelled drags.")
        capture(app, named: "fullscreen-photo-after-cancelled-vertical-drags-and-horizontal-page")

        // Start in the black letterbox above this landscape photo. The
        // entire full-screen surface must support the dismissal gesture.
        verticalDrag(in: fullScreenGallery, app: app, distance: 190, fromTopLetterbox: true)
        XCTAssertTrue(close.waitForNonExistence(timeout: 5), "A deliberate downward swipe must dismiss full screen.")
        waitForPhoto(2, counter: app.staticTexts["answer-photo-page-indicator"])
        XCTAssertTrue(inlineGallery.isHittable)

        // Dismissal must not leave stale gesture state in a new presentation.
        photo(2, fullScreen: false, in: app).tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        waitForPhoto(2, counter: counter)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func assertThumbnailBounds(_ thumbnail: XCUIElement, within gallery: XCUIElement) {
        XCTAssertTrue(thumbnail.isHittable)
        XCTAssertTrue(
            gallery.frame.insetBy(dx: -2, dy: -2).contains(thumbnail.frame),
            "A cropped photo must expose only its visible touch/accessibility bounds. Photo: \(thumbnail.frame); gallery: \(gallery.frame)."
        )
    }

    @MainActor
    private func verticalDrag(
        in gallery: XCUIElement,
        app: XCUIApplication,
        distance: CGFloat,
        fromTopLetterbox: Bool = false
    ) {
        let frame = gallery.frame
        let startY = fromTopLetterbox ? frame.minY + 32
            : (distance < 0 ? frame.midY + 30 : frame.minY + frame.height * 0.28)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: frame.midX, dy: startY))
            .press(
                forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: frame.midX, dy: startY + distance)),
                withVelocity: .slow,
                thenHoldForDuration: 0.15
            )
    }

    @MainActor
    private func waitForRestingPosition(_ gallery: XCUIElement, top: CGFloat) {
        let returned = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                gallery.exists && abs(gallery.frame.minY - top) < 2
            },
            object: gallery
        )
        XCTAssertEqual(XCTWaiter.wait(for: [returned], timeout: 3), .completed)
    }

    @MainActor
    private func photo(_ index: Int, fullScreen: Bool, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "answer-\(fullScreen ? "fullscreen-" : "")photo-\(index)-of-3").firstMatch
    }

    @MainActor
    private func waitForPhoto(_ index: Int, counter: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND label == %@", "写真\(index)／3"),
            object: counter
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    @MainActor
    private func capture(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func revealGallery(_ gallery: XCUIElement, in app: XCUIApplication) {
        let bottomTab = app.buttons["home-tab-family"]
        for _ in 0..<12 {
            if gallery.isHittable,
               gallery.frame.minY >= app.frame.minY + 100,
               gallery.frame.maxY < bottomTab.frame.minY - 8 { return }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let x = app.frame.width * 0.95
            origin.withOffset(CGVector(dx: x, dy: app.frame.height * 0.68))
                .press(
                    forDuration: 0.05,
                    thenDragTo: origin.withOffset(CGVector(dx: x, dy: app.frame.height * 0.43)),
                    withVelocity: .slow,
                    thenHoldForDuration: 0.25
                )
        }
        XCTFail("The answer's inline gallery must be visible before testing its photos.")
    }
}
