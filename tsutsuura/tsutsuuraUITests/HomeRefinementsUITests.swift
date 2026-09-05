import XCTest
import UIKit

final class HomeRefinementsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWaitingBannerDismissalSurvivesNavigationAndRelaunchButNotRelease() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["TSUTSUURA_DEMO_MODE"] = "authenticated"
        app.launchEnvironment["TSUTSUURA_DEMO_WAITING_QUESTION_ID"] = UUID().uuidString
        app.launchArguments = ["-tsutsuura-demo-waiting-question"]
        app.launch()

        let dismiss = app.buttons["dismiss-upcoming-question"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(dismiss.frame.width, 44)
        XCTAssertGreaterThanOrEqual(dismiss.frame.height, 44)
        dismiss.tap()
        XCTAssertTrue(dismiss.waitForNonExistence(timeout: 3))

        let family = app.buttons["home-tab-family"]
        let profile = app.buttons["home-tab-profile"]
        XCTAssertLessThanOrEqual(family.frame.height, 60, "Home tabs should leave more space for answers.")
        XCTAssertGreaterThanOrEqual(family.frame.height, 44, "Compact tabs still need a comfortable tap target.")
        XCTAssertEqual(family.value as? String, "選択中")
        profile.tap()
        XCTAssertEqual(profile.value as? String, "選択中")
        app.buttons["設定"].tap()
        XCTAssertTrue(app.buttons["戻る"].waitForExistence(timeout: 5))
        app.buttons["戻る"].tap()
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        XCTAssertFalse(dismiss.exists)

        app.terminate()
        app.launch()
        XCTAssertTrue(family.waitForExistence(timeout: 5))
        XCTAssertFalse(dismiss.exists, "Quiet refreshes and later visits must respect dismissal.")

        // A deliberate pull beyond the top restores the banner on either tab.
        // A small incidental tug must leave it dismissed.
        let familyTimeline = app.scrollViews["home-family-timeline"]
        let smallPull = familyTimeline.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.2))
        smallPull.press(forDuration: 0.05, thenDragTo: smallPull.withOffset(CGVector(dx: 0, dy: 35)))
        XCTAssertFalse(dismiss.exists)
        pullDownToRevealBanner(in: familyTimeline)
        XCTAssertTrue(dismiss.waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements["home-banner-pull-cue"].exists)
        dismiss.tap()
        XCTAssertTrue(dismiss.waitForNonExistence(timeout: 3))

        profile.tap()
        let profileTimeline = app.scrollViews["home-profile-timeline"]
        pullDownToRevealBanner(in: profileTimeline)
        XCTAssertTrue(dismiss.waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements["home-banner-pull-cue"].exists)

        // Explicitly restored visibility survives another visit too.
        app.terminate()
        app.launch()
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))

        // The same question becoming available must restore the answer action.
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["回答する"].waitForExistence(timeout: 5))
        XCTAssertFalse(dismiss.exists)
    }

    @MainActor
    func testOnlyAnUpwardSwipeBeginningInTheUpcomingBannerDismissesIt() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["TSUTSUURA_DEMO_MODE"] = "authenticated"
        app.launchEnvironment["TSUTSUURA_DEMO_WAITING_QUESTION_ID"] = UUID().uuidString
        app.launchArguments = ["-tsutsuura-demo-waiting-question"]
        app.launch()

        let banner = app.descendants(matching: .any)
            .matching(identifier: "home-question-banner").firstMatch
        let dismiss = app.buttons["dismiss-upcoming-question"]
        let timeline = app.scrollViews["home-family-timeline"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertTrue(dismiss.isHittable)

        // Even a scroll that ends inside the banner belongs to the timeline
        // when the finger began there.
        let progress = app.buttons["family-progress-details-button"]
        let originalProgressY = progress.frame.minY
        timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.75))
            .press(
                forDuration: 0.05,
                thenDragTo: banner.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.6)),
                withVelocity: .slow,
                thenHoldForDuration: 0.25
            )
        XCTAssertTrue(dismiss.exists, "Scrolling answers must not close the banner.")
        XCTAssertLessThan(progress.frame.minY, originalProgressY - 20, "The timeline must still scroll normally.")

        let shortUp = banner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        shortUp.press(forDuration: 0.05, thenDragTo: shortUp.withOffset(CGVector(dx: 0, dy: -24)))
        XCTAssertTrue(dismiss.exists, "A short movement must not dismiss the banner.")

        let downward = banner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        downward.press(forDuration: 0.05, thenDragTo: downward.withOffset(CGVector(dx: 0, dy: 64)))
        XCTAssertTrue(dismiss.exists, "A downward drag must not dismiss the banner.")

        let sideways = banner.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7))
        sideways.press(forDuration: 0.05, thenDragTo: sideways.withOffset(CGVector(dx: 110, dy: -55)))
        XCTAssertTrue(dismiss.exists, "A mostly horizontal drag must not dismiss the banner.")

        swipeUpInsideBanner(banner)
        XCTAssertTrue(dismiss.waitForNonExistence(timeout: 3))
        XCTAssertFalse(banner.exists)
        capture(app, named: "upcoming-banner-dismissed-by-upward-swipe")

        // Relaunch resets the timeline's scroll position while preserving the
        // explicit dismissal, ready to check the existing pull-to-reveal path.
        app.terminate()
        app.launch()
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        XCTAssertFalse(dismiss.exists)
        pullDownToRevealBanner(in: timeline)
        XCTAssertTrue(dismiss.waitForExistence(timeout: 3))
        capture(app, named: "swipe-dismissed-banner-restored-by-pull")
        dismiss.tap()
        XCTAssertTrue(dismiss.waitForNonExistence(timeout: 3), "The close button must remain usable after a swipe and restoration.")

        // Once published, the question and answer action cannot be dismissed.
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["回答する"].waitForExistence(timeout: 5))
        // Resolve this container in the new process. Reusing the pre-relaunch
        // firstMatch can return the terminated process's empty AX snapshot.
        let publishedBanner = app.descendants(matching: .any)
            .matching(identifier: "home-question-banner").firstMatch
        XCTAssertTrue(publishedBanner.waitForExistence(timeout: 5))
        swipeUpInsideBanner(publishedBanner)
        capture(app, named: "published-banner-after-upward-swipe")
        XCTAssertFalse(app.textViews["answer-input"].exists, "Swiping the banner must not activate the answer button.")
        XCTAssertTrue(publishedBanner.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["回答する"].isHittable)
        XCTAssertFalse(dismiss.exists)
        app.buttons["回答する"].tap()
        XCTAssertTrue(app.textViews["answer-input"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func swipeUpInsideBanner(_ banner: XCUIElement) {
        let start = banner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        start.press(
            forDuration: 0.05,
            thenDragTo: start.withOffset(CGVector(dx: 12, dy: -80)),
            withVelocity: .slow,
            thenHoldForDuration: 0.25
        )
    }

    @MainActor
    private func capture(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func pullDownToRevealBanner(in timeline: XCUIElement) {
        let start = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.25))
        let end = timeline.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.85))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1)
    }

    @MainActor
    func testCompactTabsAndWaitingBannerAtLargestTextSize() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["TSUTSUURA_DEMO_MODE"] = "authenticated"
        app.launchEnvironment["TSUTSUURA_DEMO_WAITING_QUESTION_ID"] = UUID().uuidString
        app.launchArguments = [
            "-tsutsuura-demo-waiting-question",
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        app.launch()
        let dismiss = app.buttons["dismiss-upcoming-question"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        XCTAssertTrue(dismiss.isHittable)
        for identifier in ["home-tab-family", "home-tab-profile"] {
            let tab = app.buttons[identifier]
            XCTAssertTrue(tab.isHittable)
            XCTAssertGreaterThanOrEqual(tab.frame.height, 44)
            XCTAssertTrue(app.frame.contains(tab.frame))
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "compact-home-large-text"
        attachment.lifetime = .keepAlways
        add(attachment)
        dismiss.tap()
        XCTAssertTrue(dismiss.waitForNonExistence(timeout: 3))
        app.buttons["home-tab-profile"].tap()
        XCTAssertTrue(app.buttons["設定"].waitForExistence(timeout: 5))
    }
}
