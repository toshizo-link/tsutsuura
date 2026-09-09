import XCTest
import UIKit

final class tsutsuuraUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFamilyWelcomeOffersOrganizerAndDeviceSetupChoices() throws {
        let app = launchSignedOutDemo()
        let createFamilyButton = app.buttons["create-family-button"]
        let setUpDeviceButton = app.buttons["setup-this-iphone-button"]

        XCTAssertTrue(createFamilyButton.waitForExistence(timeout: 3))
        XCTAssertTrue(setUpDeviceButton.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["家族と、毎日ひとこと"].exists)
        XCTAssertTrue(createFamilyButton.label.contains("家族をつくる"))
        XCTAssertTrue(setUpDeviceButton.label.contains("家族の番号を入力"))
        XCTAssertTrue(app.buttons["returning-user-login-button"].exists)
        attachScreenshot(of: app, named: "welcome-default")
        for button in [createFamilyButton, setUpDeviceButton] {
            XCTAssertTrue(scrollFullyIntoView(button, in: app))
            assertFullyVisible(button, in: app)
        }
    }

    @MainActor
    func testReturningUserCanReachEmailLoginAndReturn() throws {
        let app = launchSignedOutDemo()
        let returningUserButton = app.buttons["returning-user-login-button"]
        XCTAssertTrue(returningUserButton.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToHittable(returningUserButton, in: app))
        returningUserButton.tap()

        XCTAssertTrue(
            app.textFields["email-address-input"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.buttons["email-login-submit"].exists)
        XCTAssertTrue(app.staticTexts["メールでログイン"].exists)
        let backButton = app.buttons["lifecycle-back-button"]
        XCTAssertTrue(backButton.exists)
        backButton.tap()

        XCTAssertTrue(app.buttons["create-family-button"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSignedOutAccountRecoveryIsReachableAndCanReturn() throws {
        let app = launchSignedOutDemo()
        let recoveryButton = app.buttons["account-recovery-button"]
        XCTAssertTrue(recoveryButton.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToHittable(recoveryButton, in: app))
        recoveryButton.tap()

        let codeField = app.textFields["recovery-code-input"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["recover-account-submit-button"].exists)
        XCTAssertFalse(app.buttons["recover-account-submit-button"].isEnabled)
        XCTAssertTrue(
            app.staticTexts["復旧コードは一回だけ使えます。復旧すると、紛失した端末を含む以前のログインはすべて無効になります。"]
                .exists
        )

        app.buttons["lifecycle-back-button"].tap()
        XCTAssertTrue(
            app.buttons["account-recovery-button"]
                .waitForExistence(timeout: 3)
        )
    }

    @MainActor
    func testWelcomeActionsRemainReachableAtAccessibilityTextSize() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["TSUTSUURA_DEMO_MODE"] = "signedOut"
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        app.launch()
        XCTAssertTrue(app.buttons["create-family-button"].waitForExistence(timeout: 3))
        attachScreenshot(of: app, named: "welcome-accessibility-xxxl")

        for identifier in [
            "create-family-button",
            "setup-this-iphone-button",
            "returning-user-login-button",
            "account-recovery-button",
        ] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 3))
            XCTAssertTrue(scrollFullyIntoView(button, in: app, maximumSwipes: 10))
            assertFullyVisible(button, in: app)
        }
    }

    @MainActor
    func testPairingEntryBackReturnsToWelcome() throws {
        let app = launchSignedOutDemo()
        let setupButton = app.buttons["setup-this-iphone-button"]
        XCTAssertTrue(setupButton.waitForExistence(timeout: 3))
        setupButton.tap()

        let codeField = app.textFields["pairing-code-input"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 3))
        let backButton = app.buttons["pairing-entry-back-button"]
        XCTAssertTrue(backButton.exists)
        XCTAssertTrue(backButton.isEnabled)
        XCTAssertTrue(backButton.isHittable)
        backButton.tap()

        XCTAssertTrue(
            app.buttons["setup-this-iphone-button"]
                .waitForExistence(timeout: 3)
        )
    }

    @MainActor
    func testInvalidPairingGuidancePreservesRecipientContext() throws {
        let app = launchSignedOutDemo()
        app.buttons["setup-this-iphone-button"].tap()

        let codeField = app.textFields["pairing-code-input"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 3))
        codeField.tap()
        codeField.typeText("999999")
        let dismissKeyboard = app.buttons["dismiss-pairing-keyboard"]
        XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 3))
        dismissKeyboard.tap()

        let activate = app.buttons["pairing-activate-button"]
        XCTAssertTrue(activate.isEnabled)
        activate.tap()

        let error = app.buttons["error-toast-dismiss-button"]
        XCTAssertTrue(error.waitForExistence(timeout: 3))
        XCTAssertEqual(
            error.label,
            "エラー。この招待は利用できません。ご家族に新しい設定番号を送ってもらってください。閉じる"
        )
        XCTAssertEqual(codeField.value as? String, "999999")
        error.tap()
        XCTAssertTrue(error.waitForNonExistence(timeout: 3))
        XCTAssertTrue(codeField.exists)
    }

    @MainActor
    func testPairingEntryAndShareRemainReachableAtAccessibilityTextSize() throws {
        let app = launchSignedOutDemo(
            additionalArguments: [
                "-UIPreferredContentSizeCategoryName",
                UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
            ]
        )

        let setupButton = app.buttons["setup-this-iphone-button"]
        XCTAssertTrue(setupButton.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToHittable(setupButton, in: app, maximumSwipes: 10))
        setupButton.tap()

        let codeField = app.textFields["pairing-code-input"]
        let entryBack = app.buttons["pairing-entry-back-button"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToHittable(codeField, in: app, maximumSwipes: 10))
        XCTAssertTrue(entryBack.exists)
        XCTAssertTrue(entryBack.isHittable)
        entryBack.tap()

        completeYoungerFamilySetup(in: app)
        for identifier in [
            "pairing-share-button",
            "pairing-copy-link-button",
            "pairing-copy-code-button",
            "pairing-share-finished-button",
        ] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 3))
            XCTAssertTrue(scrollToHittable(button, in: app, maximumSwipes: 12))
            XCTAssertTrue(button.isEnabled)
        }
        let code = app.descendants(matching: .any)["pairing-share-code"]
        XCTAssertTrue(code.exists)
        XCTAssertTrue(scrollToHittable(code, in: app, maximumSwipes: 12))
    }

    @MainActor
    func testExpiredPairingReissueRemainsReachableAtAccessibilityTextSize() throws {
        let app = launchSignedOutDemo(
            additionalArguments: [
                "-tsutsuura-demo-expired-pairing",
                "-UIPreferredContentSizeCategoryName",
                UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
            ]
        )
        completeYoungerFamilySetup(in: app)

        let reissue = app.buttons["pairing-reissue-expired-button"]
        XCTAssertTrue(reissue.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToHittable(reissue, in: app, maximumSwipes: 12))
        XCTAssertTrue(reissue.isEnabled)
    }

    @MainActor
    func testOrganizerSetupKeyboardKeepsLayoutAndSuggestsFamilyName() throws {
        let app = launchSignedOutDemo()
        let createFamilyButton = app.buttons["create-family-button"]
        XCTAssertTrue(createFamilyButton.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToHittable(createFamilyButton, in: app))
        createFamilyButton.tap()

        let organizerField = app.textFields["organizer-name-input"]
        let familyField = app.textFields["family-name-input"]
        XCTAssertTrue(organizerField.waitForExistence(timeout: 3))
        XCTAssertTrue(familyField.exists)

        organizerField.tap()
        organizerField.typeText("yuta")

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(
            organizerField.frame.width,
            app.frame.width * 0.60
        )
        XCTAssertGreaterThan(familyField.frame.width, app.frame.width * 0.60)
        XCTAssertLessThan(
            organizerField.frame.maxY,
            keyboard.frame.minY - 8
        )

        let suggestedName = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "value == %@",
                "yutaの家族"
            ),
            object: familyField
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [suggestedName], timeout: 3),
            .completed
        )

        familyField.tap()
        XCTAssertLessThan(familyField.frame.maxY, keyboard.frame.minY - 8)

        let dismissKeyboard = app.buttons["dismiss-organizer-keyboard"]
        XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 3))
        dismissKeyboard.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["organizer-continue-button"].exists)
    }

    @MainActor
    func testOrganizerNameLimitIsVisibleAndEnforced() throws {
        let app = launchSignedOutDemo()
        app.buttons["create-family-button"].tap()

        let organizerField = app.textFields["organizer-name-input"]
        XCTAssertTrue(organizerField.waitForExistence(timeout: 3))
        organizerField.tap()
        organizerField.typeText(String(repeating: "a", count: 81))

        let clampedValue = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "value == %@",
                String(repeating: "a", count: 80)
            ),
            object: organizerField
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [clampedValue], timeout: 3),
            .completed
        )
        let counter = app.descendants(matching: .any)[
            "organizer-name-input-character-count"
        ]
        XCTAssertTrue(counter.waitForExistence(timeout: 3))
        XCTAssertEqual(counter.label, "80文字、上限80文字")
    }

    @MainActor
    func testYoungerFamilyMemberCreatesAndSharesManagedMemberSetup() throws {
        let app = launchSignedOutDemo()

        completeYoungerFamilySetup(in: app)

        let pairingCode = app.descendants(matching: .any)[
            "pairing-share-code"
        ]
        XCTAssertTrue(pairingCode.waitForExistence(timeout: 3))
        XCTAssertEqual(
            pairingCode.label,
            "設定番号、0、0、0、0、0、1"
        )
        let shareButton = app.buttons["pairing-share-button"]
        XCTAssertTrue(shareButton.exists)
        XCTAssertEqual(
            shareButton.label,
            "おばあちゃんへ設定リンクを送る"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["おばあちゃんさん"].exists
        )
        XCTAssertTrue(app.buttons["pairing-share-finished-button"].exists)
    }

    @MainActor
    func testPairingInviteOffersCopyFeedbackAndLiveExpiration() throws {
        let app = launchSignedOutDemo()
        completeYoungerFamilySetup(in: app)

        let expiration = app.staticTexts["pairing-expiration-status"]
        XCTAssertTrue(expiration.waitForExistence(timeout: 3))
        let initialExpiration = expiration.label
        XCTAssertTrue(initialExpiration.contains("あと"))
        XCTAssertTrue(initialExpiration.contains("まで"))

        let linkCopyButton = app.buttons["pairing-copy-link-button"]
        XCTAssertTrue(scrollToHittable(linkCopyButton, in: app))
        linkCopyButton.tap()
        let copyFeedback = app.staticTexts["pairing-copy-feedback"]
        XCTAssertTrue(copyFeedback.waitForExistence(timeout: 3))
        XCTAssertEqual(copyFeedback.label, "リンクをコピーしました")

        let codeCopyButton = app.buttons["pairing-copy-code-button"]
        XCTAssertTrue(codeCopyButton.isHittable)
        codeCopyButton.tap()
        XCTAssertEqual(copyFeedback.label, "6桁の番号をコピーしました")

        let countdownChanged = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label != %@", initialExpiration),
            object: expiration
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [countdownChanged], timeout: 3),
            .completed
        )
        XCTAssertTrue(app.buttons["pairing-share-button"].isEnabled)
    }

    @MainActor
    func testElderPairingCodeCompletesDeviceSetup() throws {
        let app = launchSignedOutDemo()
        completeYoungerFamilySetup(in: app)

        let finishedSharing = app.buttons["pairing-share-finished-button"]
        XCTAssertTrue(scrollToHittable(finishedSharing, in: app))
        finishedSharing.tap()

        let finishedFamilySetup = app.buttons["family-setup-finished-button"]
        XCTAssertTrue(finishedFamilySetup.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToHittable(finishedFamilySetup, in: app))
        finishedFamilySetup.tap()
        finishEssentials(in: app)

        let profileButton = app.buttons["home-tab-profile"]
        XCTAssertTrue(profileButton.waitForExistence(timeout: 5))
        profileButton.tap()

        let settingsButton = app.buttons["設定"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        settingsButton.tap()

        let familySettingsButton = app.buttons["family-settings-button"]
        XCTAssertTrue(familySettingsButton.waitForExistence(timeout: 3))

        openOtherSettings(in: app)
        let signOutButton = app.buttons["settings-sign-out-button"]
        XCTAssertTrue(scrollToHittable(signOutButton, in: app))
        signOutButton.tap()
        let confirmSignOut = app.sheets.buttons["ログアウト"]
        XCTAssertTrue(confirmSignOut.waitForExistence(timeout: 3))
        confirmSignOut.tap()

        let setUpDeviceButton = app.buttons["setup-this-iphone-button"]
        XCTAssertTrue(setUpDeviceButton.waitForExistence(timeout: 3))
        setUpDeviceButton.tap()

        let codeField = app.textFields["pairing-code-input"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 3))
        codeField.tap()
        codeField.typeText("000001")

        let dismissKeyboard = app.buttons["dismiss-pairing-keyboard"]
        XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 3))
        dismissKeyboard.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))

        let checkPairingButton = app.buttons["pairing-activate-button"]
        XCTAssertTrue(checkPairingButton.isHittable)
        checkPairingButton.tap()

        let confirmButton = app.buttons["pairing-confirm-button"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["この内容で合っていますか？"].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(
                    NSPredicate(
                        format: "label CONTAINS %@",
                        "yutaの家族"
                    )
                )
                .firstMatch
                .exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(
                    NSPredicate(format: "label CONTAINS %@", "おばあちゃん")
                )
                .firstMatch
                .exists
        )
        let confirmationBackButton = app.buttons[
            "pairing-confirmation-back-button"
        ]
        XCTAssertTrue(confirmationBackButton.waitForExistence(timeout: 3))
        XCTAssertTrue(confirmationBackButton.isEnabled)
        XCTAssertTrue(confirmationBackButton.isHittable)
        confirmationBackButton.tap()
        XCTAssertTrue(codeField.waitForExistence(timeout: 3))

        // Returning to entry restores focus on the compact layout. Dismiss
        // that keyboard before exercising the same six-digit code again so
        // the first tap is delivered to the action rather than to focus
        // teardown during the navigation animation.
        if app.keyboards.firstMatch.exists,
           dismissKeyboard.waitForExistence(timeout: 2) {
            dismissKeyboard.tap()
            XCTAssertTrue(
                app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
            )
        }
        let checkPairingReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "enabled == true AND hittable == true"
            ),
            object: checkPairingButton
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [checkPairingReady], timeout: 3),
            .completed
        )
        checkPairingButton.tap()
        if !confirmButton.waitForExistence(timeout: 5),
           checkPairingButton.isEnabled,
           checkPairingButton.isHittable {
            checkPairingButton.tap()
        }
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 3))
        confirmButton.tap()
        completeRequiredPersonalMark(in: app)

        let readyTitle = app.staticTexts["pairing-ready-title"]
        XCTAssertTrue(readyTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(readyTitle.label, "準備できました")
        XCTAssertTrue(app.staticTexts["「おばあちゃん」が使うiPhoneです"].exists)
        XCTAssertFalse(
            app.descendants(matching: .any)["おばあちゃんさん"].exists
        )

        let startButton = app.buttons["pairing-start-button"]
        XCTAssertTrue(startButton.exists)
        startButton.tap()
        finishEssentials(in: app)

        XCTAssertTrue(app.buttons["home-tab-family"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home-tab-profile"].exists)
        XCTAssertTrue(app.buttons["回答する"].exists)
    }

    @MainActor
    func testAuthenticatedDemoOpensQuestionScreen() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["TSUTSUURA_DEMO_MODE"] = "authenticated"
        app.launch()

        let questionButton = app.buttons["回答する"]
        XCTAssertTrue(questionButton.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["home-tab-family"].exists)
        XCTAssertTrue(app.buttons["home-tab-profile"].exists)
        assertFullyVisible(questionButton, in: app)
        assertFullyVisible(app.buttons["home-tab-family"], in: app)
        assertFullyVisible(app.buttons["home-tab-profile"], in: app)
        attachScreenshot(of: app, named: "home-default")
        questionButton.tap()

        XCTAssertTrue(
            app.staticTexts["今日、家族に伝えたい小さな出来事は？"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.textViews["answer-input"].exists)
        let voiceButton = app.buttons["声で回答"]
        XCTAssertTrue(voiceButton.exists)
        attachScreenshot(of: app, named: "question-default")
        XCTAssertTrue(scrollFullyIntoView(voiceButton, in: app))
        assertFullyVisible(voiceButton, in: app)
    }

    @MainActor
    func testFamilyProgressAnnouncesEveryMemberByNameAndState() throws {
        let app = launchAuthenticatedDemo()
        let battery = app.descendants(matching: .any)["family-answer-battery"]
        XCTAssertTrue(battery.waitForExistence(timeout: 5))
        XCTAssertEqual(battery.value as? String, "2人中0人が回答済み")
        let currentMember = app.descendants(matching: .any)["つつうら：未回答"]
        let familyMember = app.descendants(matching: .any)["あおい：未回答"]
        XCTAssertFalse(currentMember.exists)
        attachScreenshot(of: app, named: "family-battery-empty")
        showFamilyProgressDetails(in: app)
        XCTAssertTrue(currentMember.waitForExistence(timeout: 5))
        XCTAssertTrue(familyMember.exists)
        XCTAssertFalse(app.staticTexts["Close"].exists)
        XCTAssertFalse(app.staticTexts["checkmark.circle.fill"].exists)
        attachScreenshot(of: app, named: "family-battery-members")
        let details = app.buttons["family-progress-details-button"]
        XCTAssertTrue(scrollAboveBottomNavigation(details, in: app))
        details.tap()
        XCTAssertTrue(currentMember.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func testFamilyBatteryShowsFullCharge() throws {
        let app = launchAuthenticatedDemo(
            additionalArguments: ["-tsutsuura-demo-battery-complete"]
        )
        let battery = app.descendants(matching: .any)["family-answer-battery"]
        XCTAssertTrue(battery.waitForExistence(timeout: 5))
        XCTAssertEqual(battery.value as? String, "2人中2人が回答済み")
        attachScreenshot(of: app, named: "family-battery-complete")
        showFamilyProgressDetails(in: app)
        for name in ["つつうら", "あおい"] {
            XCTAssertTrue(app.descendants(matching: .any)["\(name)：回答済み"].exists)
        }
    }

    @MainActor
    func testSocialActionsAreAvailableBeforeTodaysAnswer() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["TSUTSUURA_DEMO_MODE"] = "authenticated"
        app.launch()

        XCTAssertTrue(app.buttons["回答する"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["コメント"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["いいね"].firstMatch.exists)
    }

    @MainActor
    func testPhotoGalleryPagesThroughEveryIndexedImage() throws {
        let app = launchAuthenticatedDemo(
            additionalArguments: ["-tsutsuura-demo-gallery"]
        )
        let gallery = app.descendants(matching: .any)["answer-photo-gallery"]
        XCTAssertTrue(gallery.waitForExistence(timeout: 5))
        XCTAssertTrue(
            scrollAboveBottomNavigation(gallery, in: app, maximumSwipes: 10)
        )

        let firstPhoto = app.descendants(matching: .any)["answer-photo-1-of-3"]
        XCTAssertTrue(firstPhoto.waitForExistence(timeout: 3))
        XCTAssertTrue(firstPhoto.isHittable)
        let pageIndicator = app.staticTexts["answer-photo-page-indicator"]
        XCTAssertTrue(pageIndicator.waitForExistence(timeout: 3))
        XCTAssertEqual(pageIndicator.label, "写真1／3")

        firstPhoto.swipeLeft()
        XCTAssertTrue(
            waitUntilLabelEquals("写真2／3", for: pageIndicator, timeout: 3)
        )

        let secondPhoto = app.descendants(matching: .any)["answer-photo-2-of-3"]
        XCTAssertTrue(secondPhoto.waitForExistence(timeout: 3))
        XCTAssertTrue(waitUntilHittable(secondPhoto, timeout: 3))
        secondPhoto.swipeLeft()
        XCTAssertTrue(
            waitUntilLabelEquals("写真3／3", for: pageIndicator, timeout: 3)
        )

        let thirdPhoto = app.descendants(matching: .any)["answer-photo-3-of-3"]
        XCTAssertTrue(thirdPhoto.waitForExistence(timeout: 3))
        XCTAssertTrue(waitUntilHittable(thirdPhoto, timeout: 3))
    }

    @MainActor
    func testSelectedPhotoRemovalControlsAnnounceIndexAndTotal() throws {
        let app = launchAuthenticatedDemo(
            additionalArguments: ["-tsutsuura-demo-draft-photos"]
        )
        let questionButton = app.buttons["回答する"]
        XCTAssertTrue(questionButton.waitForExistence(timeout: 5))
        questionButton.tap()

        let firstRemove = app.buttons["写真1／2を削除"]
        let secondRemove = app.buttons["写真2／2を削除"]
        XCTAssertTrue(firstRemove.waitForExistence(timeout: 5))
        XCTAssertTrue(secondRemove.exists)
        XCTAssertTrue(scrollToHittable(firstRemove, in: app))

        firstRemove.tap()

        XCTAssertTrue(
            app.buttons["写真1／1を削除"].waitForExistence(timeout: 3)
        )
        XCTAssertFalse(app.buttons["写真2／2を削除"].exists)
    }

    @MainActor
    func testHomeTabSelectionTransfers() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["TSUTSUURA_DEMO_MODE"] = "authenticated"
        app.launch()

        let familyButton = app.buttons["home-tab-family"]
        let profileButton = app.buttons["home-tab-profile"]
        XCTAssertTrue(familyButton.waitForExistence(timeout: 3))
        XCTAssertTrue(profileButton.exists)
        XCTAssertEqual(familyButton.value as? String, "選択中")

        profileButton.tap()

        XCTAssertEqual(profileButton.value as? String, "選択中")
        XCTAssertNotEqual(familyButton.value as? String, "選択中")
        XCTAssertTrue(app.buttons["設定"].waitForExistence(timeout: 3))
        assertFullyVisible(familyButton, in: app)
        assertFullyVisible(profileButton, in: app)
        attachScreenshot(of: app, named: "profile-default")
    }

    @MainActor
    func testAuthenticatedDemoSubmitsAnswer() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["TSUTSUURA_DEMO_MODE"] = "authenticated"
        app.launch()

        let questionButton = app.buttons["回答する"]
        XCTAssertTrue(questionButton.waitForExistence(timeout: 3))
        questionButton.tap()

        let questionScreenMarker = app.buttons["声で回答"]
        if !questionScreenMarker.waitForExistence(timeout: 3) {
            XCTAssertTrue(questionButton.isHittable)
            questionButton.tap()
            XCTAssertTrue(questionScreenMarker.waitForExistence(timeout: 3))
        }

        let answerInput = app.textViews["answer-input"].firstMatch
        XCTAssertTrue(answerInput.waitForExistence(timeout: 3))
        answerInput.tap()
        answerInput.typeText("Family demo answer")

        let dismissKeyboard = app.buttons["dismiss-answer-keyboard"]
        XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 3))
        dismissKeyboard.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        app.buttons["submit-answer-button"].tap()
        confirmAnswerSubmission(in: app)

        XCTAssertTrue(
            app.staticTexts["Family demo answer"]
                .waitForExistence(timeout: 5)
        )
        let battery = app.descendants(matching: .any)["family-answer-battery"]
        XCTAssertEqual(battery.value as? String, "2人中1人が回答済み")
        // The success overlay can briefly cover an already-updated home view.
        // Capture only after its real controls can receive touches again.
        XCTAssertTrue(waitUntilHittable(
            app.buttons["family-progress-details-button"], timeout: 5
        ))
        showFamilyProgressDetails(in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["つつうら：回答済み"]
                .waitForExistence(timeout: 5),
            "Submitting today's answer should announce the current member as answered"
        )
        attachScreenshot(of: app, named: "family-battery-half")
    }

    @MainActor
    func testAnswerKeyboardKeepsFullWidthEditor() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["TSUTSUURA_DEMO_MODE"] = "authenticated"
        app.launch()

        let questionButton = app.buttons["回答する"]
        XCTAssertTrue(questionButton.waitForExistence(timeout: 3))
        questionButton.tap()

        let answerInput = app.textViews["answer-input"].firstMatch
        if !answerInput.waitForExistence(timeout: 5) {
            XCTAssertTrue(questionButton.isHittable)
            questionButton.tap()
            XCTAssertTrue(answerInput.waitForExistence(timeout: 3))
        }
        let unfocusedWidth = answerInput.frame.width
        answerInput.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
        answerInput.typeText("Keyboard layout answer")

        XCTAssertGreaterThanOrEqual(
            answerInput.frame.width,
            unfocusedWidth * 0.95
        )
        XCTAssertLessThan(
            answerInput.frame.maxY,
            keyboard.frame.minY - 8
        )
        XCTAssertTrue(
            app.buttons["submit-answer-from-keyboard"].isHittable
        )
    }

    @MainActor
    func testCommentKeyboardComposerPostsComment() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["TSUTSUURA_DEMO_MODE"] = "authenticated"
        app.launch()

        let questionButton = app.buttons["回答する"]
        XCTAssertTrue(questionButton.waitForExistence(timeout: 3))
        questionButton.tap()

        let answerInput = app.textViews["answer-input"].firstMatch
        XCTAssertTrue(answerInput.waitForExistence(timeout: 3))
        answerInput.tap()
        answerInput.typeText("Comment flow answer")
        let keyboardSubmit = app.buttons["submit-answer-from-keyboard"]
        XCTAssertTrue(keyboardSubmit.waitForExistence(timeout: 3))
        keyboardSubmit.tap()
        confirmAnswerSubmission(in: app)
        XCTAssertTrue(answerInput.waitForNonExistence(timeout: 5))

        let commentButton = app.buttons["コメント"].firstMatch
        XCTAssertTrue(commentButton.waitForExistence(timeout: 8))
        XCTAssertTrue(
            scrollAboveBottomNavigation(commentButton, in: app),
            "Comment action should be fully visible above the bottom navigation"
        )
        let commentButtonReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: commentButton
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [commentButtonReady], timeout: 3),
            .completed
        )
        commentButton.tap()

        let commentsTitle = app.staticTexts["comments-screen-title"]
        let commentInput = app.textFields["comment-input"]
        XCTAssertTrue(commentsTitle.waitForExistence(timeout: 3))
        XCTAssertTrue(commentInput.waitForExistence(timeout: 3))
        XCTAssertTrue(commentsTitle.isHittable)
        let unfocusedWidth = commentInput.frame.width
        commentInput.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))
        commentInput.typeText("Keyboard comment")
        XCTAssertFalse(app.descendants(matching: .any)["comment-character-count"].exists)

        XCTAssertGreaterThanOrEqual(
            commentInput.frame.width,
            unfocusedWidth * 0.95
        )
        XCTAssertLessThan(
            commentInput.frame.maxY,
            keyboard.frame.minY - 8
        )
        XCTAssertTrue(app.buttons["comment-send-button"].isHittable)

        app.buttons["comment-send-button"].tap()

        let postedComment = app.staticTexts["Keyboard comment"]
        XCTAssertTrue(postedComment.waitForExistence(timeout: 3))
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 3))
        let commentAboveComposer = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                postedComment.exists
                    && postedComment.isHittable
                    && postedComment.frame.maxY
                        < commentInput.frame.minY - 8
            },
            object: postedComment
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [commentAboveComposer], timeout: 3),
            .completed
        )
        XCTAssertLessThan(
            postedComment.frame.maxY,
            commentInput.frame.minY - 8
        )
    }

    @MainActor
    func testSettingsKeyboardKeepsFullWidthForm() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["TSUTSUURA_DEMO_MODE"] = "authenticated"
        app.launch()

        let profileButton = app.buttons["home-tab-profile"]
        XCTAssertTrue(profileButton.waitForExistence(timeout: 3))
        profileButton.tap()

        let settingsButton = app.buttons["設定"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        settingsButton.tap()

        let nameField = app.textFields["settings-name-input"]
        let saveButton = app.buttons["settings-save-button"]
        let familySettingsButton = app.buttons["family-settings-button"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        XCTAssertTrue(saveButton.exists)
        XCTAssertTrue(familySettingsButton.exists)
        let unfocusedWidth = nameField.frame.width
        nameField.tap()

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))

        XCTAssertGreaterThanOrEqual(
            nameField.frame.width,
            unfocusedWidth * 0.95
        )
        XCTAssertLessThan(nameField.frame.maxY, keyboard.frame.minY - 8)
        XCTAssertTrue(saveButton.isHittable)
    }

    @MainActor
    func testSettingsShowsSaveAndRefreshCompletionFeedback() throws {
        let app = launchAuthenticatedDemo()
        openSettings(in: app)

        let nameField = app.textFields["settings-name-input"]
        let saveButton = app.buttons["settings-save-button"]
        XCTAssertFalse(saveButton.isEnabled)
        nameField.tap()
        nameField.typeText("QA")
        XCTAssertTrue(waitUntilEnabled(saveButton, timeout: 3))
        app.buttons["dismiss-settings-keyboard"].tap()
        XCTAssertTrue(scrollToHittable(saveButton, in: app))
        saveButton.tap()
        XCTAssertTrue(
            app.staticTexts["settings-save-feedback"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertEqual(
            app.staticTexts["settings-save-feedback"].label,
            "保存しました"
        )
        XCTAssertFalse(saveButton.isEnabled)

        openOtherSettings(in: app)
        let refreshButton = app.buttons["settings-refresh-button"]
        XCTAssertTrue(scrollToHittable(refreshButton, in: app, maximumSwipes: 10))
        refreshButton.tap()
        let refreshFeedback = app.staticTexts["settings-refresh-feedback"]
        XCTAssertTrue(refreshFeedback.waitForExistence(timeout: 5))
        XCTAssertTrue(refreshFeedback.label.hasPrefix("更新しました · "))
    }

    @MainActor
    func testSettingsReachNotificationsAccountRecoveryAndHelp() throws {
        let app = launchAuthenticatedDemo()
        openSettings(in: app)
        attachScreenshot(of: app, named: "settings-simplified")

        let notificationButton = app.buttons["notification-settings-button"]
        XCTAssertTrue(notificationButton.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToHittable(notificationButton, in: app))
        notificationButton.tap()

        XCTAssertTrue(app.staticTexts["iPhoneのお知らせ"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.switches["notification-family-toggle"].exists)
        XCTAssertTrue(app.switches["notification-daily-toggle"].exists)
        attachScreenshot(of: app, named: "notifications-simplified")
        XCTAssertFalse(app.switches["コメントが届いたとき"].exists)
        let noticeDetails = app.buttons["notification-details"]
        XCTAssertTrue(scrollToHittable(noticeDetails, in: app))
        noticeDetails.tap()
        XCTAssertTrue(app.switches["コメントが届いたとき"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.switches["いいねが届いたとき"].exists)
        app.buttons["lifecycle-back-button"].tap()

        let accountButton = app.buttons["account-privacy-button"]
        XCTAssertTrue(accountButton.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToHittable(accountButton, in: app))
        accountButton.tap()

        XCTAssertTrue(app.staticTexts["機種変更・データ"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["delete-account-button"].exists)
        let recoveryNavigation = app.buttons["recovery-code-navigation-button"]
        XCTAssertTrue(recoveryNavigation.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToHittable(recoveryNavigation, in: app))
        recoveryNavigation.tap()

        let createRecoveryCode = app.buttons["create-recovery-code-button"]
        XCTAssertTrue(createRecoveryCode.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToHittable(createRecoveryCode, in: app))
        createRecoveryCode.tap()
        let copyRecoveryCode = app.buttons["copy-recovery-code-button"]
        XCTAssertTrue(copyRecoveryCode.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToHittable(copyRecoveryCode, in: app))
        copyRecoveryCode.tap()
        XCTAssertTrue(app.staticTexts["復旧コードをコピーしました"].exists)

        app.buttons["lifecycle-back-button"].tap()
        XCTAssertTrue(app.staticTexts["機種変更・データ"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["delete-account-button"].exists)
        app.buttons["lifecycle-back-button"].tap()

        let helpButton = app.buttons["help-button"]
        XCTAssertTrue(helpButton.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToHittable(helpButton, in: app))
        helpButton.tap()

        XCTAssertTrue(app.staticTexts["使い方"].waitForExistence(timeout: 3))
        let replayButton = app.buttons["replay-essentials-button"]
        XCTAssertTrue(replayButton.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToHittable(replayButton, in: app, maximumSwipes: 10))
        replayButton.tap()
        XCTAssertTrue(app.staticTexts["一日ひとつ、家族に近況を"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["次へ"].exists)
    }

    @MainActor
    func testHistorySearchAndPaginationTerminalState() throws {
        let app = launchAuthenticatedDemo()
        openProfile(in: app)

        let searchField = app.textFields["history-search-field"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["忙しい朝に、そっとお茶を入れてくれたこと。"]
                .waitForExistence(timeout: 3)
        )

        let endLabel = app.staticTexts["history-end-label"]
        let loadMoreButton = app.buttons["history-load-more-button"]
        XCTAssertTrue(
            endLabel.waitForExistence(timeout: 3)
                || loadMoreButton.waitForExistence(timeout: 1),
            "History must expose either the next-page action or an explicit end state."
        )
        if loadMoreButton.exists {
            XCTAssertTrue(scrollToHittable(loadMoreButton, in: app))
            loadMoreButton.tap()
            XCTAssertTrue(
                endLabel.waitForExistence(timeout: 5)
                    || loadMoreButton.waitForExistence(timeout: 1)
            )
        }

        XCTAssertTrue(
            scrollAboveBottomNavigation(searchField, in: app),
            "History search should be fully visible above the bottom navigation"
        )
        guard focusTextField(searchField, in: app) else {
            return XCTFail("History search field did not accept keyboard focus")
        }
        searchField.typeText("no-matching-answer")
        searchField.typeText("\n")
        XCTAssertTrue(
            app.staticTexts["条件に合う回答がありません"]
                .waitForExistence(timeout: 5)
        )
        let clearSearch = app.buttons["history-clear-search"]
        XCTAssertTrue(scrollAboveBottomNavigation(clearSearch, in: app))
        clearSearch.tap()
        XCTAssertTrue(app.staticTexts["忙しい朝に、そっとお茶を入れてくれたこと。"].waitForExistence(timeout: 5))
        XCTAssertEqual(searchField.value as? String, "質問や回答を検索")
        XCTAssertFalse(clearSearch.exists)
    }

    @MainActor
    func testReturningToProfileAfterSearchDoesNotReopenKeyboard() throws {
        let app = launchAuthenticatedDemo()
        openProfile(in: app)
        let search = app.textFields["history-search-field"]
        XCTAssertTrue(focusTextField(search, in: app))
        search.typeText("no-matching-answer")
        XCTAssertTrue(app.keyboards.firstMatch.exists)

        app.buttons["home-tab-family"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        app.buttons["home-tab-profile"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        XCTAssertEqual(search.value as? String, "no-matching-answer")
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 1),
                       "Returning to history must not focus its search field automatically")
        XCTAssertTrue(app.staticTexts["条件に合う回答がありません"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testHomeTabsReplaceComplexFiltersAndShowSelection() throws {
        let app = launchAuthenticatedDemo()
        openProfile(in: app)
        XCTAssertFalse(buttonContainingLabel("絞り込み", in: app).exists)
        let profileTab = app.buttons["home-tab-profile"]
        let familyTab = app.buttons["home-tab-family"]
        XCTAssertEqual(profileTab.value as? String, "選択中")
        XCTAssertTrue(profileTab.isSelected)
        XCTAssertFalse(familyTab.isSelected)

        familyTab.tap()
        XCTAssertTrue(app.staticTexts["夕飯のときに昔の写真を見つけて、みんなで笑ったこと。"].waitForExistence(timeout: 5))
        XCTAssertEqual(familyTab.value as? String, "選択中")
        XCTAssertTrue(familyTab.isSelected)
        XCTAssertFalse(profileTab.isSelected)
        XCTAssertFalse(app.textFields["history-search-field"].exists)
    }

    @MainActor
    func testPublishedAnswersHaveNoEditOrDeleteActions() throws {
        let app = launchAuthenticatedDemo()
        openProfile(in: app)
        XCTAssertTrue(app.staticTexts["忙しい朝に、そっとお茶を入れてくれたこと。"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["edit-answer-demo-answer-history"].exists)
        XCTAssertFalse(buttonContainingLabel("この回答を編集", in: app).exists)
        XCTAssertFalse(app.buttons["回答を削除"].exists)
        let comments = app.buttons["answer-comments-demo-answer-history"]
        XCTAssertTrue(scrollAboveBottomNavigation(comments, in: app))
        comments.tap()
        XCTAssertTrue(app.staticTexts["comments-screen-title"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testEdgeSwipeReturnsFromSettings() throws {
        let app = launchAuthenticatedDemo()
        openSettings(in: app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.55))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.55)))
        XCTAssertTrue(app.textFields["history-search-field"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["settings-name-input"].exists)
        XCTAssertEqual(app.buttons["home-tab-profile"].value as? String, "選択中")
    }

    @MainActor
    func testDiagonalBackSwipeLocksVerticalScrollAndCancellationRestoresScrolling() throws {
        let app = launchAuthenticatedDemo()
        openSettings(in: app)
        let name = app.textFields["settings-name-input"]
        let originalY = name.frame.minY
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 4, dy: app.frame.height * 0.6))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 54, dy: app.frame.height * 0.6 - 140)))
        XCTAssertTrue(name.exists, "A short horizontal movement cancels back navigation.")
        XCTAssertEqual(name.frame.minY, originalY, accuracy: 2, "Vertical motion in an edge swipe must not scroll content.")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.75))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.4)))
        XCTAssertLessThan(name.frame.minY, originalY - 10, "Normal vertical scrolling must work after a canceled back swipe.")
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 4, dy: app.frame.height * 0.45))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: 145, dy: app.frame.height * 0.45 + 210)))
        XCTAssertTrue(app.textFields["history-search-field"].waitForExistence(timeout: 5), "Back responds to horizontal travel even with larger vertical movement.")
    }

    @MainActor
    func testEmailEnrollmentThenReturningLogin() throws {
        let app = launchAuthenticatedDemo()
        openSettings(in: app)
        let account = app.buttons["account-privacy-button"]
        XCTAssertTrue(scrollToHittable(account, in: app))
        account.tap()
        let enroll = app.buttons["email-enrollment-navigation-button"]
        XCTAssertTrue(enroll.waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["phone-enrollment-submit"].exists)
        XCTAssertTrue(scrollToHittable(enroll, in: app))
        enroll.tap()
        let email = app.textFields["email-address-input"]
        XCTAssertTrue(email.waitForExistence(timeout: 4))
        let currentEmail = email.value as? String ?? ""
        // Enrollment now shows the saved address. Place the caret at its end
        // before replacing it, rather than inserting into the existing value.
        email.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        if currentEmail.contains("@") {
            email.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentEmail.count))
        }
        email.typeText("family@example.com")
        XCTAssertEqual(email.value as? String, "family@example.com")
        let send = app.buttons["email-enrollment-submit"]
        XCTAssertTrue(scrollToHittable(send, in: app))
        XCTAssertTrue(send.isEnabled)
        send.tap()
        let code = app.textFields["email-verification-code-input"]
        XCTAssertTrue(code.waitForExistence(timeout: 4))
        code.tap()
        code.typeText("123456")
        app.buttons["dismiss-code-keyboard"].tap()
        app.buttons["verify-email-code-button"].tap()
        XCTAssertTrue(app.staticTexts["機種変更・データ"].waitForExistence(timeout: 5))
        attachScreenshot(of: app, named: "verified-email-account")
        app.buttons["lifecycle-back-button"].tap()
        openOtherSettings(in: app)
        let signOut = app.buttons["settings-sign-out-button"]
        XCTAssertTrue(scrollToHittable(signOut, in: app))
        signOut.tap()
        let confirm = app.sheets.buttons["ログアウト"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        let returning = app.buttons["returning-user-login-button"]
        XCTAssertTrue(returning.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollToHittable(returning, in: app))
        returning.tap()
        XCTAssertTrue(email.waitForExistence(timeout: 4))
        email.tap()
        email.typeText("family@example.com")
        let login = app.buttons["email-login-submit"]
        XCTAssertTrue(scrollToHittable(login, in: app))
        login.tap()
        XCTAssertTrue(code.waitForExistence(timeout: 4))
        code.tap()
        code.typeText("123456")
        app.buttons["dismiss-code-keyboard"].tap()
        app.buttons["verify-email-code-button"].tap()
        XCTAssertTrue(app.buttons["home-tab-family"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPullingHomeKeepsQuestionBannerFixedWithoutErrorOrSpinner() throws {
        let app = launchAuthenticatedDemo()
        let answer = app.buttons["回答する"]
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        let originalFrame = answer.frame
        let startY = min(app.frame.height * 0.65, originalFrame.maxY + 150)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: app.frame.midX, dy: startY))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: app.frame.midX, dy: min(startY + 190, app.frame.height - 170))))
        XCTAssertEqual(answer.frame.minY, originalFrame.minY, accuracy: 1)
        XCTAssertEqual(answer.frame.height, originalFrame.height, accuracy: 1)
        XCTAssertFalse(app.staticTexts["cancelled"].exists)
        XCTAssertEqual(app.activityIndicators.count, 0)
        XCTAssertFalse(app.buttons["home-refresh-button"].exists)
        XCTAssertFalse(app.staticTexts["最新の回答を確認"].exists)
        XCTAssertTrue(answer.isHittable)
        XCTAssertEqual(app.activityIndicators.count, 0)
        attachScreenshot(of: app, named: "home-fixed-banner-after-pull")
    }

    @MainActor
    func testMissingPersonalMarkMustBeDrawnBeforeHomeAndCannotBeSkipped() throws {
        let app = launchAuthenticatedDemo(additionalArguments: ["-tsutsuura-demo-missing-mark"])
        let required = app.staticTexts["personal-mark-required-title"]
        XCTAssertTrue(required.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["home-tab-family"].exists)
        XCTAssertFalse(app.buttons["lifecycle-back-button"].exists)
        XCTAssertFalse(app.buttons["personal-mark-heart"].exists)
        XCTAssertFalse(app.buttons["personal-mark-initial"].exists)
        XCTAssertFalse(app.buttons["personal-mark-save"].isEnabled)
        swipeGuideBack(in: app)
        XCTAssertTrue(required.exists, "Back gestures cannot bypass the required mark.")
        XCTAssertFalse(app.buttons["home-tab-family"].exists)
        completeRequiredPersonalMark(in: app)
        XCTAssertTrue(app.buttons["home-tab-family"].waitForExistence(timeout: 5))
        openSettings(in: app)
        let edit = app.buttons["personal-mark-button"]
        XCTAssertTrue(scrollToHittable(edit, in: app))
        edit.tap()
        XCTAssertTrue(app.buttons["lifecycle-back-button"].waitForExistence(timeout: 5))
        XCTAssertFalse(required.exists, "An existing saved mark can be edited without repeating setup.")
        XCTAssertEqual(app.staticTexts["personal-mark-current-kind"].label, "かいたしるしを使います")
    }

    @MainActor
    func testPersonalMarkSupportsDrawingUndoAndSavedChoice() throws {
        let app = launchAuthenticatedDemo()
        openSettings(in: app)
        let openMark = app.buttons["personal-mark-button"]
        XCTAssertTrue(scrollToHittable(openMark, in: app))
        openMark.tap()

        let kind = app.staticTexts["personal-mark-current-kind"]
        XCTAssertTrue(kind.waitForExistence(timeout: 5))
        XCTAssertEqual(app.sheets.count, 0, "Icon creation uses a navigation page.")
        XCTAssertTrue(app.buttons["lifecycle-back-button"].exists)
        let clear = app.buttons["personal-mark-clear"]
        scrollAlongDrawingMargin(to: clear, in: app)
        clear.tap()
        XCTAssertEqual(kind.label, "指でしるしをかいてください")
        XCTAssertFalse(app.buttons["personal-mark-save"].isEnabled)
        let canvas = app.descendants(matching: .any).matching(identifier: "personal-mark-canvas").firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 3))
        scrollAlongDrawingMargin(to: canvas, in: app)
        drawPersonalMark(on: canvas)
        XCTAssertEqual(kind.label, "かいたしるしを使います")

        let undo = app.buttons["personal-mark-undo"]
        scrollAlongDrawingMargin(to: undo, in: app)
        XCTAssertTrue(undo.isEnabled)
        undo.tap()
        XCTAssertEqual(kind.label, "指でしるしをかいてください")
        XCTAssertFalse(app.buttons["personal-mark-save"].isEnabled)
        scrollAlongDrawingMargin(to: canvas, in: app)
        drawPersonalMark(on: canvas)
        app.buttons["personal-mark-save"].tap()
        XCTAssertTrue(openMark.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollToHittable(openMark, in: app))
        openMark.tap()
        XCTAssertTrue(kind.waitForExistence(timeout: 5))
        XCTAssertEqual(kind.label, "かいたしるしを使います", "The saved mark must load when the editor opens again.")
        attachScreenshot(of: app, named: "personal-mark-saved")

        scrollAlongDrawingMargin(to: clear, in: app)
        clear.tap()
        XCTAssertFalse(app.buttons["personal-mark-save"].isEnabled, "An existing mark cannot be replaced with an empty canvas.")
        app.buttons["lifecycle-back-button"].tap()
        XCTAssertTrue(openMark.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollToHittable(openMark, in: app))
        openMark.tap()
        XCTAssertTrue(kind.waitForExistence(timeout: 5))
        XCTAssertEqual(kind.label, "かいたしるしを使います", "Cancelling an empty edit preserves the saved drawing.")
    }

    @MainActor
    func testFirstSetupCanPersonalizeAndReturnToLastGuideStep() throws {
        let app = launchSignedOutDemo()
        let createFamily = app.buttons["create-family-button"]
        XCTAssertTrue(scrollToHittable(createFamily, in: app))
        createFamily.tap()
        let name = app.textFields["organizer-name-input"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(focusTextField(name, in: app))
        name.typeText("まさこ")
        app.buttons["dismiss-organizer-keyboard"].tap()
        let continueSetup = app.buttons["organizer-continue-button"]
        XCTAssertTrue(scrollToHittable(continueSetup, in: app))
        continueSetup.tap()
        completeRequiredPersonalMark(in: app)
        let finishSetup = app.buttons["family-setup-finished-button"]
        XCTAssertTrue(finishSetup.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollToHittable(finishSetup, in: app))
        finishSetup.tap()

        let title = app.staticTexts["essentials-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "一日ひとつ、家族に近況を")
        let next = app.buttons["essentials-next-button"]
        next.tap()
        XCTAssertTrue(waitUntilLabelEquals("ひとことから、答えてみる", for: title, timeout: 3))
        swipeGuideBack(in: app)
        XCTAssertTrue(waitUntilLabelEquals("一日ひとつ、家族に近況を", for: title, timeout: 3))
        XCTAssertFalse(app.buttons["home-tab-family"].exists, "An onboarding back gesture must remain in the guide until its first step.")
        for _ in 0..<3 { next.tap() }
        XCTAssertTrue(waitUntilLabelEquals("準備ができました", for: title, timeout: 3))
        let personalize = app.buttons["essentials-personalize-button"]
        XCTAssertTrue(scrollToHittable(personalize, in: app))
        personalize.tap()
        XCTAssertTrue(app.buttons["personal-mark-save"].waitForExistence(timeout: 5))
        app.buttons["lifecycle-back-button"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "準備ができました", "Returning from editing a saved mark must preserve guide progress.")
        attachScreenshot(of: app, named: "first-setup-ready-to-start")
        next.tap()
        XCTAssertTrue(app.buttons["home-tab-family"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testEssentialsReplayExplainsImmutableAnswersAndCanGoBack() throws {
        let app = launchAuthenticatedDemo()
        openSettings(in: app)
        let help = app.buttons["help-button"]
        XCTAssertTrue(scrollToHittable(help, in: app))
        help.tap()
        app.buttons["replay-essentials-button"].tap()
        let title = app.staticTexts["essentials-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "一日ひとつ、家族に近況を")
        let next = app.buttons["essentials-next-button"]
        next.tap()
        XCTAssertTrue(waitUntilLabelEquals("ひとことから、答えてみる", for: title, timeout: 3))
        XCTAssertTrue(app.staticTexts["送る前に確認しましょう。送った回答は編集・削除できません。"].exists)
        app.buttons["essentials-previous-button"].tap()
        XCTAssertTrue(waitUntilLabelEquals("一日ひとつ、家族に近況を", for: title, timeout: 3))
        for _ in 0..<3 { next.tap() }
        XCTAssertTrue(waitUntilLabelEquals("準備ができました", for: title, timeout: 3))
        XCTAssertTrue(app.staticTexts["名前の横のしるしは、あなたがかいた絵です。「設定」から、いつでもかき直せます。"].exists)
        attachScreenshot(of: app, named: "essentials-last-step")
        next.tap()
        XCTAssertTrue(app.buttons["replay-essentials-button"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFinalOnboardingOffersNotificationsAndCanStartWithoutPermission() throws {
        let app = launchNotificationGuide(response: "authorized")
        let optIn = app.buttons["essentials-notification-opt-in"]
        XCTAssertTrue(scrollToHittable(optIn, in: app))
        XCTAssertTrue(optIn.isEnabled)
        XCTAssertFalse(app.staticTexts["essentials-notification-authorized"].exists,
                       "Simply opening the guide must not request notification permission.")
        attachScreenshot(of: app, named: "onboarding-notification-choice")
        let finish = app.buttons["essentials-next-button"]
        XCTAssertTrue(finish.isHittable, "Finishing must remain available without opting in.")
        finish.tap()
        XCTAssertTrue(app.buttons["replay-essentials-button"].waitForExistence(timeout: 5))
        app.buttons["replay-essentials-button"].tap()
        advanceToFinalGuidePage(in: app)
        XCTAssertTrue(scrollToHittable(optIn, in: app), "Skipping must not record an authorization choice.")
        optIn.tap()
        let allowed = app.descendants(matching: .any).matching(identifier: "essentials-notification-authorized").firstMatch
        XCTAssertTrue(allowed.waitForExistence(timeout: 5))
        XCTAssertFalse(optIn.exists, "A granted permission must not prompt again.")
        finish.tap()
        XCTAssertTrue(app.buttons["replay-essentials-button"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDecliningNotificationPermissionKeepsOnboardingUsable() throws {
        let app = launchNotificationGuide(response: "denied")
        let optIn = app.buttons["essentials-notification-opt-in"]
        XCTAssertTrue(scrollToHittable(optIn, in: app))
        optIn.tap()
        let settings = app.buttons["essentials-notification-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        XCTAssertFalse(optIn.exists, "A denied permission must not immediately prompt again.")
        let finish = app.buttons["essentials-next-button"]
        XCTAssertTrue(finish.isHittable)
        finish.tap()
        XCTAssertTrue(app.buttons["replay-essentials-button"].waitForExistence(timeout: 5))
        app.buttons["replay-essentials-button"].tap()
        advanceToFinalGuidePage(in: app)
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        XCTAssertFalse(optIn.exists)
    }

    @MainActor
    private func launchNotificationGuide(response: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["TSUTSUURA_DEMO_MODE"] = "authenticated"
        app.launchEnvironment["TSUTSUURA_TEST_PUSH_AUTHORIZATION"] = "notDetermined"
        app.launchEnvironment["TSUTSUURA_TEST_PUSH_RESPONSE"] = response
        app.launch()
        openSettings(in: app)
        let help = app.buttons["help-button"]
        XCTAssertTrue(scrollToHittable(help, in: app))
        help.tap()
        app.buttons["replay-essentials-button"].tap()
        advanceToFinalGuidePage(in: app)
        return app
    }

    @MainActor
    private func advanceToFinalGuidePage(in app: XCUIApplication) {
        let title = app.staticTexts["essentials-title"]
        let titles = ["一日ひとつ、家族に近況を", "ひとことから、答えてみる", "「家族」と「あなた」を選ぶ", "準備ができました"]
        for index in 0..<3 {
            XCTAssertTrue(waitUntilLabelEquals(titles[index], for: title, timeout: 5))
            let next = app.buttons["essentials-next-button"]
            XCTAssertTrue(waitUntilHittable(next, timeout: 3))
            next.tap()
            if !waitUntilLabelEquals(titles[index + 1], for: title, timeout: 3),
               title.label == titles[index], next.isHittable { next.tap() }
        }
        XCTAssertTrue(waitUntilLabelEquals(titles[3], for: title, timeout: 5))
    }

    @MainActor
    func testGuideReplayEdgeBackMovesToPreviousStepBeforeClosing() throws {
        let app = launchAuthenticatedDemo()
        openSettings(in: app)
        let help = app.buttons["help-button"]
        XCTAssertTrue(scrollToHittable(help, in: app))
        help.tap()
        app.buttons["replay-essentials-button"].tap()
        let title = app.staticTexts["essentials-title"]
        XCTAssertTrue(waitUntilLabelEquals("一日ひとつ、家族に近況を", for: title, timeout: 3))
        let next = app.buttons["essentials-next-button"]
        next.tap()
        XCTAssertTrue(waitUntilLabelEquals("ひとことから、答えてみる", for: title, timeout: 3))
        swipeGuideBack(in: app)
        XCTAssertTrue(waitUntilLabelEquals("一日ひとつ、家族に近況を", for: title, timeout: 3))
        XCTAssertFalse(app.buttons["replay-essentials-button"].exists, "Step2 edge-back must not dismiss the guide.")
        next.tap()
        next.tap()
        XCTAssertTrue(waitUntilLabelEquals("「家族」と「あなた」を選ぶ", for: title, timeout: 3))
        app.buttons["essentials-previous-button"].tap()
        XCTAssertTrue(waitUntilLabelEquals("ひとことから、答えてみる", for: title, timeout: 3))
        swipeGuideBack(in: app)
        XCTAssertTrue(waitUntilLabelEquals("一日ひとつ、家族に近況を", for: title, timeout: 3))
        swipeGuideBack(in: app)
        XCTAssertTrue(app.buttons["replay-essentials-button"].waitForExistence(timeout: 3))
    }

    @MainActor
    private func swipeGuideBack(in app: XCUIApplication) {
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: 4, dy: app.frame.height * 0.55))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(
                CGVector(dx: app.frame.width * 0.8, dy: app.frame.height * 0.55)
            ))
    }

    @MainActor
    func testCommentsHideEditAndDeleteWhileReplyAndReportRemainReachable() throws {
        let app = launchAuthenticatedDemo()
        let commentsButton = app.buttons["answer-comments-demo-answer-family"]
        XCTAssertTrue(commentsButton.waitForExistence(timeout: 5))
        func revealCommentsButton() -> Bool {
            for _ in 0..<12 {
                let answerButton = app.buttons["回答する"]
                let top = answerButton.exists ? answerButton.frame.maxY + 24 : app.frame.minY + 80
                let bottom = min(app.buttons["home-tab-family"].frame.minY, app.buttons["home-tab-profile"].frame.minY) - 12
                let frame = commentsButton.frame
                if frame.minY >= top, frame.maxY <= bottom, commentsButton.isHittable { return true }
                // The fixed question banner obscures content above the
                // timeline. Reverse when a gesture moves the target under it.
                let shift = frame.minY < top
                    ? min(140, top - frame.minY + 12)
                    : -min(140, max(24, frame.maxY - bottom + 12))
                let origin = app.coordinate(withNormalizedOffset: .zero)
                let start = CGVector(dx: app.frame.width * 0.95, dy: (top + bottom) / 2)
                origin.withOffset(start).press(
                    forDuration: 0.05,
                    thenDragTo: origin.withOffset(CGVector(dx: start.dx, dy: start.dy + shift)),
                    withVelocity: .slow,
                    thenHoldForDuration: 0.25
                )
            }
            return false
        }
        XCTAssertTrue(revealCommentsButton())
        commentsButton.tap()

        let commentsTitle = app.staticTexts["comments-screen-title"]
        if !commentsTitle.waitForExistence(timeout: 3),
           commentsButton.exists {
            XCTAssertTrue(revealCommentsButton())
            commentsButton.tap()
        }
        XCTAssertTrue(commentsTitle.waitForExistence(timeout: 3))

        // Wait for an existing comment by the current user before checking
        // that ownership no longer exposes editing or deletion controls.
        XCTAssertTrue(app.staticTexts["その写真、今度わたしにも見せて！"].waitForExistence(timeout: 5))
        let editButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "edit-comment-"))
        let deleteButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "delete-comment-"))
        XCTAssertFalse(editButtons.firstMatch.exists)
        XCTAssertFalse(deleteButtons.firstMatch.exists)

        app.swipeUp()
        let reportButton = app.buttons["報告"].firstMatch
        let replyButton = app.buttons["返信"].firstMatch
        XCTAssertTrue(reportButton.waitForExistence(timeout: 3))
        XCTAssertTrue(replyButton.waitForExistence(timeout: 3))
        let composerInput = app.textFields["comment-input"]
        XCTAssertTrue(composerInput.exists)
        XCTAssertTrue(
            scroll(
                reportButton,
                above: composerInput,
                in: app
            ),
            "Comment actions should be fully visible above the composer"
        )
        XCTAssertLessThan(reportButton.frame.maxY, composerInput.frame.minY)
        XCTAssertLessThan(replyButton.frame.maxY, composerInput.frame.minY)
        reportButton.tap()
        let reportAlert = app.alerts.firstMatch
        XCTAssertTrue(reportAlert.waitForExistence(timeout: 3))
        let confirmReport = reportAlert.buttons["不適切な内容として報告"]
        XCTAssertTrue(confirmReport.waitForExistence(timeout: 3))
        confirmReport.tap()

        XCTAssertTrue(scrollToHittable(replyButton, in: app))
        replyButton.tap()

        let input = app.textFields["comment-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.typeText("Reply UI comment")
        app.buttons["comment-send-button"].tap()
        XCTAssertTrue(app.staticTexts["Reply UI comment"].waitForExistence(timeout: 5))
        let renderedReplyMarker = app.staticTexts
            .matching(NSPredicate(format: "label == %@", "返信"))
            .firstMatch
        XCTAssertTrue(renderedReplyMarker.exists)
        XCTAssertFalse(editButtons.firstMatch.exists, "A newly posted reply must not expose an edit action either.")
        XCTAssertFalse(deleteButtons.firstMatch.exists, "A newly posted reply must not expose a delete action either.")
    }

    @MainActor
    func testDeterministicVoiceSuccessReturnsTranscriptAndRecording() throws {
        let app = launchAuthenticatedDemo(
            additionalArguments: ["-tsutsuura-demo-voice-success"]
        )
        openQuestion(in: app)
        app.buttons["声で回答"].tap()

        let transcript = app.staticTexts["今日は家族と散歩をしました"]
        XCTAssertTrue(transcript.waitForExistence(timeout: 7))
        let useAnswerButton = app.buttons["voice-use-answer-button"]
        XCTAssertTrue(useAnswerButton.waitForExistence(timeout: 3))
        XCTAssertTrue(waitUntilEnabled(useAnswerButton, timeout: 3))
        useAnswerButton.tap()

        let answerInput = app.textViews["answer-input"].firstMatch
        XCTAssertTrue(answerInput.waitForExistence(timeout: 3))
        XCTAssertTrue(
            (answerInput.value as? String)?
                .contains("今日は家族と散歩をしました") == true
        )
        XCTAssertTrue(app.buttons["submit-answer-button"].isEnabled)
    }

    @MainActor
    func testAuthenticatedCoreActionsAtLargestAccessibilityTextSize() throws {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["TSUTSUURA_DEMO_MODE"] = "authenticated"
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        app.launch()

        let familyTab = app.buttons["home-tab-family"]
        let profileTab = app.buttons["home-tab-profile"]
        XCTAssertTrue(familyTab.waitForExistence(timeout: 5))
        XCTAssertTrue(profileTab.exists)
        XCTAssertGreaterThan(
            familyTab.frame.height,
            90,
            "Largest accessibility text must visibly expand the navigation controls."
        )
        assertFullyVisible(familyTab, in: app)
        assertFullyVisible(profileTab, in: app)
        attachScreenshot(of: app, named: "home-accessibility-xxxl")

        showFamilyProgressDetails(in: app)
        let currentMember = app.descendants(matching: .any)["つつうら：未回答"]
        XCTAssertTrue(currentMember.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollAboveBottomNavigation(currentMember, in: app, maximumSwipes: 10))
        attachScreenshot(of: app, named: "family-battery-accessibility-xxxl")
        let progressDetails = app.buttons["family-progress-details-button"]
        XCTAssertTrue(scrollAboveBottomNavigation(progressDetails, in: app, maximumSwipes: 10))
        progressDetails.tap()

        let answerQuestion = app.buttons["回答する"]
        XCTAssertTrue(answerQuestion.waitForExistence(timeout: 3))
        XCTAssertTrue(
            scrollAboveBottomNavigation(
                answerQuestion,
                in: app,
                maximumSwipes: 10
            )
        )
        assertFullyVisible(answerQuestion, in: app)
        answerQuestion.tap()
        XCTAssertTrue(app.buttons["声で回答"].waitForExistence(timeout: 3))
        let questionBack = app.buttons["戻る"].firstMatch
        assertFullyVisible(questionBack, in: app)
        attachScreenshot(of: app, named: "question-accessibility-xxxl")
        let voiceButton = app.buttons["声で回答"]
        XCTAssertTrue(scrollFullyIntoView(voiceButton, in: app, maximumSwipes: 10))
        assertFullyVisible(voiceButton, in: app)
        XCTAssertTrue(scrollFullyIntoView(questionBack, in: app, maximumSwipes: 10))
        questionBack.tap()

        let likeButton = app.buttons["いいね"].firstMatch
        XCTAssertTrue(likeButton.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollAboveBottomNavigation(likeButton, in: app, maximumSwipes: 10))
        assertFullyVisible(likeButton, in: app)
        let familyComments = app.buttons["answer-comments-demo-answer-family"]
        XCTAssertTrue(familyComments.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollAboveBottomNavigation(familyComments, in: app))
        assertFullyVisible(familyComments, in: app)
        attachScreenshot(of: app, named: "answer-actions-accessibility-xxxl")
        familyComments.tap()
        XCTAssertTrue(app.staticTexts["comments-screen-title"].waitForExistence(timeout: 3))
        let commentsBack = app.buttons["戻る"].firstMatch
        XCTAssertTrue(commentsBack.isHittable)
        commentsBack.tap()

        XCTAssertTrue(profileTab.waitForExistence(timeout: 3))
        profileTab.tap()
        let settingsButton = app.buttons["設定"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        // Screen bounds include the persistent tabs. Reveal the settings
        // control above them before tapping, including at accessibility sizes.
        XCTAssertTrue(scrollAboveBottomNavigation(settingsButton, in: app))
        assertFullyVisible(settingsButton, in: app)
        attachScreenshot(of: app, named: "profile-accessibility-xxxl")
        settingsButton.tap()

        let nameField = app.textFields["settings-name-input"]
        let saveButton = app.buttons["settings-save-button"]
        let settingsBack = app.buttons["戻る"].firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertTrue(saveButton.exists)
        XCTAssertTrue(settingsBack.exists)
        XCTAssertTrue(settingsBack.isHittable)

        guard focusTextField(nameField, in: app) else {
            return XCTFail("Settings name field did not accept keyboard focus")
        }
        nameField.typeText("A")
        let dismissKeyboard = app.buttons["dismiss-settings-keyboard"]
        XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 3))
        dismissKeyboard.tap()
        XCTAssertTrue(scrollToHittable(saveButton, in: app, maximumSwipes: 10))
        XCTAssertTrue(saveButton.isEnabled)

        let familySettings = app.buttons["family-settings-button"]
        XCTAssertTrue(familySettings.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToHittable(familySettings, in: app, maximumSwipes: 10))
    }

    @MainActor
    func testDecorativeSymbolsDoNotExposeRawAccessibilityNames() throws {
        let app = launchAuthenticatedDemo()
        XCTAssertTrue(app.buttons["回答する"].waitForExistence(timeout: 5))
        showFamilyProgressDetails(in: app)

        for rawName in [
            "Mark Read",
            "Close",
            "hand.thumbsup.fill",
            "person.3.fill",
            "text.book.closed.fill",
        ] {
            XCTAssertFalse(
                app.descendants(matching: .any)[rawName].exists,
                "Decorative symbol leaked into accessibility as \(rawName)"
            )
        }

        XCTAssertTrue(
            app.descendants(matching: .any)["つつうら：未回答"].exists
        )
    }

    @MainActor
    func testDeterministicVoiceDenialOffersRecoveryAndTextFallback() throws {
        let app = launchAuthenticatedDemo(
            additionalArguments: ["-tsutsuura-demo-voice-denied"]
        )
        openQuestion(in: app)
        app.buttons["声で回答"].tap()

        XCTAssertTrue(
            app.staticTexts["音声認識が許可されていません。設定で音声認識を許可してください。"]
                .waitForExistence(timeout: 7)
        )
        XCTAssertTrue(app.buttons["open-voice-permission-settings"].exists)
        let textFallback = app.buttons["use-text-answer-instead"]
        XCTAssertTrue(textFallback.exists)
        XCTAssertTrue(scrollToHittable(textFallback, in: app))
        textFallback.tap()

        XCTAssertTrue(app.textViews["answer-input"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["open-voice-permission-settings"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchEnvironment["UI_TESTING"] = "1"
            app.launchEnvironment["TSUTSUURA_DEMO_MODE"] = "signedOut"
            app.launch()
        }
    }

    /// The drawing surface deliberately owns finger drags. Scroll using its outside margin.
    @MainActor
    private func scrollAlongDrawingMargin(to element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            let bottom = app.buttons["personal-mark-save"].frame.minY - 12
            let top = app.frame.minY + 90
            if element.isHittable && element.frame.maxY <= bottom && element.frame.minY >= top { return }
            let shift = element.frame.minY < top
                ? min(220, top - element.frame.minY + 16)
                : -min(220, element.frame.maxY - bottom + 16)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = CGPoint(x: app.frame.width * 0.98, y: app.frame.height * 0.5)
            origin.withOffset(CGVector(dx: start.x, dy: start.y))
                .press(forDuration: 0.05,
                       thenDragTo: origin.withOffset(CGVector(dx: start.x, dy: start.y + shift)),
                       withVelocity: .slow, thenHoldForDuration: 0.25)
        }
        XCTFail("Could not reveal \(element.identifier) in drawing page: \(element.frame)")
    }

    @MainActor
    private func drawPersonalMark(on canvas: XCUIElement) {
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25))
            .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.65)))
    }

    @MainActor
    private func completeRequiredPersonalMark(in app: XCUIApplication) {
        let required = app.staticTexts["personal-mark-required-title"]
        XCTAssertTrue(required.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["home-tab-family"].exists)
        let save = app.buttons["personal-mark-save"]
        XCTAssertFalse(save.isEnabled)
        let canvas = app.descendants(matching: .any).matching(identifier: "personal-mark-canvas").firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        scrollAlongDrawingMargin(to: canvas, in: app)
        drawPersonalMark(on: canvas)
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(required.waitForNonExistence(timeout: 5))
    }

    @MainActor
    private func finishEssentials(in app: XCUIApplication) {
        if app.staticTexts["personal-mark-required-title"].exists {
            completeRequiredPersonalMark(in: app)
        }
        let title = app.staticTexts["essentials-title"]
        let next = app.buttons["essentials-next-button"]
        let titles = ["一日ひとつ、家族に近況を", "ひとことから、答えてみる", "「家族」と「あなた」を選ぶ", "準備ができました"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        for index in 0..<3 {
            XCTAssertTrue(waitUntilLabelEquals(titles[index], for: title, timeout: 3))
            XCTAssertTrue(waitUntilHittable(next, timeout: 3))
            next.tap()
            // A route-entry animation can expose an accessible control before
            // its hit target settles. Never advance based on a blind tap count.
            if !waitUntilLabelEquals(titles[index + 1], for: title, timeout: 3),
               title.label == titles[index], next.isHittable {
                next.tap()
            }
            XCTAssertTrue(waitUntilLabelEquals(titles[index + 1], for: title, timeout: 3))
        }
        XCTAssertTrue(next.label.contains("つつうらをはじめる"))
        next.tap()
        XCTAssertTrue(app.buttons["home-tab-family"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func openOtherSettings(in app: XCUIApplication) {
        let otherActions = app.buttons["ほかの操作"]
        XCTAssertTrue(scrollToHittable(otherActions, in: app, maximumSwipes: 10))
        otherActions.tap()
    }

    @MainActor
    private func confirmAnswerSubmission(in app: XCUIApplication) {
        let confirm = app.alerts.buttons["家族に送る"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "送った後は変更・削除できません。")).firstMatch.exists)
        confirm.tap()
    }

    @MainActor
    private func launchSignedOutDemo(
        additionalArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["TSUTSUURA_DEMO_MODE"] = "signedOut"
        app.launchArguments += ["-essentials-v2-demo-user", "NO", "-essentials-v2-demo-managed-member-1", "NO"]
        app.launchArguments += additionalArguments
        app.launch()
        return app
    }

    @MainActor
    private func launchAuthenticatedDemo(
        additionalArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["TSUTSUURA_DEMO_MODE"] = "authenticated"
        app.launchArguments += additionalArguments
        app.launch()
        return app
    }

    @MainActor
    private func openProfile(in app: XCUIApplication) {
        let profileButton = app.buttons["home-tab-profile"]
        XCTAssertTrue(profileButton.waitForExistence(timeout: 5))
        profileButton.tap()
        let historySearch = app.textFields["history-search-field"]
        if !historySearch.waitForExistence(timeout: 5),
           profileButton.isHittable {
            profileButton.tap()
        }
        XCTAssertTrue(historySearch.waitForExistence(timeout: 5))
    }

    @MainActor
    private func showFamilyProgressDetails(in app: XCUIApplication) {
        let details = app.buttons["family-progress-details-button"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollAboveBottomNavigation(details, in: app, maximumSwipes: 10))
        details.tap()
    }

    @MainActor
    private func openSettings(in app: XCUIApplication) {
        openProfile(in: app)
        let settingsButton = app.buttons["設定"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToHittable(settingsButton, in: app))
        settingsButton.tap()
        XCTAssertTrue(
            app.textFields["settings-name-input"]
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    private func openQuestion(in app: XCUIApplication) {
        let questionButton = app.buttons["回答する"]
        XCTAssertTrue(questionButton.waitForExistence(timeout: 5))
        questionButton.tap()
        let voiceButton = app.buttons["声で回答"]
        if !voiceButton.waitForExistence(timeout: 4) {
            XCTAssertTrue(questionButton.isHittable)
            questionButton.tap()
            XCTAssertTrue(voiceButton.waitForExistence(timeout: 4))
        }
    }

    @MainActor
    private func buttonContainingLabel(
        _ label: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", label)
        ).firstMatch
    }

    @MainActor
    private func waitUntilEnabled(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitUntilHittable(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitUntilLabelEquals(
        _ label: String,
        for element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func completeYoungerFamilySetup(in app: XCUIApplication) {
        let createFamilyButton = app.buttons["create-family-button"]
        XCTAssertTrue(createFamilyButton.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToHittable(createFamilyButton, in: app))
        createFamilyButton.tap()

        let organizerField = app.textFields["organizer-name-input"]
        if !organizerField.waitForExistence(timeout: 3) {
            createFamilyButton.tap()
        }
        XCTAssertTrue(organizerField.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToHittable(organizerField, in: app, maximumSwipes: 10))
        guard focusTextField(organizerField, in: app) else {
            return XCTFail("Organizer name field did not accept keyboard focus")
        }
        organizerField.typeText("yuta")

        let dismissOrganizerKeyboard = app.buttons[
            "dismiss-organizer-keyboard"
        ]
        XCTAssertTrue(dismissOrganizerKeyboard.waitForExistence(timeout: 3))
        dismissOrganizerKeyboard.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))

        let continueButton = app.buttons["organizer-continue-button"]
        XCTAssertTrue(continueButton.exists)
        XCTAssertTrue(scrollToHittable(continueButton, in: app))
        continueButton.tap()
        completeRequiredPersonalMark(in: app)

        let addMemberButton = app.buttons["add-managed-member-button"]
        XCTAssertTrue(addMemberButton.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollToHittable(addMemberButton, in: app))
        addMemberButton.tap()

        let memberNameField = app.textFields["managed-member-name-input"]
        XCTAssertTrue(memberNameField.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToHittable(memberNameField, in: app))
        guard focusTextField(memberNameField, in: app) else {
            return XCTFail("Managed-member name field did not accept keyboard focus")
        }
        memberNameField.typeText("おばあちゃん")

        let dismissMemberKeyboard = app.buttons[
            "dismiss-managed-member-keyboard"
        ]
        XCTAssertTrue(dismissMemberKeyboard.waitForExistence(timeout: 3))
        dismissMemberKeyboard.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))

        let createPairingButton = app.buttons["create-pairing-button"]
        XCTAssertTrue(createPairingButton.exists)
        XCTAssertTrue(scrollToHittable(createPairingButton, in: app))
        createPairingButton.tap()

        let pairingCode = app.descendants(matching: .any)[
            "pairing-share-code"
        ]
        XCTAssertTrue(pairingCode.waitForExistence(timeout: 5))
    }

    @MainActor
    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func assertFullyVisible(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.isHittable, file: file, line: line)
        XCTAssertFalse(element.frame.isEmpty, file: file, line: line)
        XCTAssertTrue(
            app.frame.insetBy(dx: -1, dy: -1).contains(element.frame),
            "\(element.label) is clipped: \(element.frame) exceeds \(app.frame)",
            file: file,
            line: line
        )
    }

    @MainActor
    private func scrollFullyIntoView(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maximumSwipes: Int = 6
    ) -> Bool {
        guard scrollToHittable(element, in: app, maximumSwipes: maximumSwipes) else {
            return false
        }
        for _ in 0..<maximumSwipes {
            let bounds = app.frame
            let frame = element.frame
            if bounds.insetBy(dx: -1, dy: -1).contains(frame) {
                return element.isHittable
            }
            // Hittability permits partly clipped controls. Reveal their full
            // height with a short drag; horizontal overflow is a layout failure.
            guard frame.minX >= bounds.minX - 1,
                  frame.maxX <= bounds.maxX + 1 else { return false }
            let direction: CGFloat = frame.minY < bounds.minY ? 1 : -1
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(
                    forDuration: 0.05,
                    thenDragTo: app.coordinate(
                        withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5 + direction * 0.15)
                    )
                )
        }
        return element.isHittable
            && app.frame.insetBy(dx: -1, dy: -1).contains(element.frame)
    }

    @MainActor
    private func scrollToHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maximumSwipes: Int = 6
    ) -> Bool {
        guard !element.isHittable else { return true }

        for _ in 0..<maximumSwipes {
            // Some screens open near their bottom (for example, Comments),
            // so the requested element can be above rather than below the
            // viewport. Choose the direction from its current frame instead
            // of blindly moving farther away from it.
            if element.frame.maxY <= app.frame.minY + 8 {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
            if element.isHittable {
                return true
            }
        }
        return element.isHittable
    }

    @MainActor
    private func focusTextField(
        _ field: XCUIElement,
        in app: XCUIApplication
    ) -> Bool {
        for attempt in 0..<3 {
            guard field.waitForExistence(timeout: 1) else { return false }
            if attempt == 0 {
                field.tap()
            } else {
                field.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
                ).tap()
            }
            if app.keyboards.firstMatch.waitForExistence(timeout: 1.5) {
                return true
            }
        }
        return false
    }

    @MainActor
    private func scrollAboveBottomNavigation(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maximumSwipes: Int = 6
    ) -> Bool {
        // Wrapped tab labels can make one control taller than the other.
        // Use the highest visible edge so scrolling starts above both tabs.
        let bottomNavigation = [app.buttons["home-tab-family"], app.buttons["home-tab-profile"]]
            .filter { $0.exists && $0.frame.intersects(app.frame) }
            .min { $0.frame.minY < $1.frame.minY }
        guard let bottomNavigation else {
            return scrollToHittable(
                element,
                in: app,
                maximumSwipes: maximumSwipes
            )
        }
        return scroll(
            element,
            above: bottomNavigation,
            in: app,
            maximumSwipes: maximumSwipes
        )
    }

    @MainActor
    private func scroll(
        _ element: XCUIElement,
        above obstruction: XCUIElement,
        in app: XCUIApplication,
        maximumSwipes: Int = 6
    ) -> Bool {
        guard scrollToHittable(
            element,
            in: app,
            maximumSwipes: maximumSwipes
        ) else {
            return false
        }

        guard obstruction.exists else { return element.isHittable }

        for _ in 0..<maximumSwipes {
            if element.frame.maxY <= obstruction.frame.minY - 8 {
                return element.isHittable
            }

            // A full swipe can carry a just-revealed action off the top of a
            // compact screen. Move the scroll view only far enough to clear
            // the persistent navigation. Derive the start point from the
            // navigation frame so the gesture never begins on that control.
            let startY = max(
                0.35,
                min(
                    0.75,
                    (obstruction.frame.minY - 24) / app.frame.height
                )
            )
            let dragStart = app.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: startY)
            )
            let dragEnd = app.coordinate(
                withNormalizedOffset: CGVector(
                    dx: 0.5,
                    dy: max(0.2, startY - 0.16)
                )
            )
            dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
        }

        return element.isHittable
            && element.frame.maxY <= obstruction.frame.minY - 8
    }

}
