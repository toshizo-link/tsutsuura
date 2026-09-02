import XCTest

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
        XCTAssertTrue(app.staticTexts["どちらから始めますか？"].exists)
        XCTAssertTrue(createFamilyButton.label.contains("家族をつくる"))
        XCTAssertTrue(setUpDeviceButton.label.contains("このiPhoneを設定"))
        XCTAssertTrue(app.buttons["returning-user-login-button"].exists)
    }

    @MainActor
    func testReturningUserCanReachPhoneLoginAndReturn() throws {
        let app = launchSignedOutDemo()
        let returningUserButton = app.buttons["returning-user-login-button"]
        XCTAssertTrue(returningUserButton.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToHittable(returningUserButton, in: app))
        returningUserButton.tap()

        XCTAssertTrue(
            app.textFields["returning-phone-input"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.buttons["returning-phone-submit"].exists)
        XCTAssertTrue(app.staticTexts["以前のアカウントに戻る"].exists)
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
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()

        for identifier in [
            "create-family-button",
            "setup-this-iphone-button",
            "returning-user-login-button",
            "account-recovery-button",
        ] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 3))
            XCTAssertTrue(scrollToHittable(button, in: app, maximumSwipes: 10))
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
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
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
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
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

        let profileButton = app.buttons["あなた"]
        XCTAssertTrue(profileButton.waitForExistence(timeout: 5))
        profileButton.tap()

        let settingsButton = app.buttons["設定"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        settingsButton.tap()

        let familySettingsButton = app.buttons["family-settings-button"]
        XCTAssertTrue(familySettingsButton.waitForExistence(timeout: 3))

        let signOutButton = app.buttons["settings-sign-out-button"]
        XCTAssertTrue(signOutButton.exists)
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

        XCTAssertTrue(app.buttons["家族"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["あなた"].exists)
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
        XCTAssertTrue(app.buttons["家族"].exists)
        XCTAssertTrue(app.buttons["あなた"].exists)
        questionButton.tap()

        XCTAssertTrue(
            app.staticTexts["今日、家族に伝えたい小さな出来事は？"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.textViews["answer-input"].exists)
        let voiceButton = app.buttons["声で回答"]
        XCTAssertTrue(voiceButton.exists)
        XCTAssertTrue(scrollToHittable(voiceButton, in: app))
    }

    @MainActor
    func testFamilyProgressAnnouncesEveryMemberByNameAndState() throws {
        let app = launchAuthenticatedDemo()

        let currentMember = app.descendants(matching: .any)["つつうら：未回答"]
        let familyMember = app.descendants(matching: .any)["あおい：未回答"]
        XCTAssertTrue(currentMember.waitForExistence(timeout: 5))
        XCTAssertTrue(familyMember.exists)
        XCTAssertFalse(app.staticTexts["Close"].exists)
        XCTAssertFalse(app.staticTexts["checkmark.circle.fill"].exists)
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

        let familyButton = app.buttons["家族"]
        let profileButton = app.buttons["あなた"]
        XCTAssertTrue(familyButton.waitForExistence(timeout: 3))
        XCTAssertTrue(profileButton.exists)
        XCTAssertEqual(familyButton.value as? String, "選択中")

        profileButton.tap()

        XCTAssertEqual(profileButton.value as? String, "選択中")
        XCTAssertNotEqual(familyButton.value as? String, "選択中")
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

        XCTAssertTrue(
            app.staticTexts["Family demo answer"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["つつうら：回答済み"]
                .waitForExistence(timeout: 5),
            "Submitting today's answer should announce the current member as answered"
        )
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
        XCTAssertEqual(
            app.descendants(matching: .any)["comment-character-count"].label,
            "コメントは16文字、最大1,000文字"
        )

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

        let profileButton = app.buttons["あなた"]
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

        let refreshButton = buttonContainingLabel("データを更新", in: app)
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

        let notificationButton = app.buttons["notification-settings-button"]
        XCTAssertTrue(notificationButton.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToHittable(notificationButton, in: app))
        notificationButton.tap()

        XCTAssertTrue(app.staticTexts["端末の通知"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.switches["家族の活動"].exists)
        XCTAssertTrue(app.switches["毎日の質問リマインダー"].exists)
        XCTAssertTrue(app.switches["コメント"].exists)
        XCTAssertTrue(app.switches["いいね"].exists)
        app.buttons["lifecycle-back-button"].tap()

        let accountButton = app.buttons["account-privacy-button"]
        XCTAssertTrue(accountButton.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToHittable(accountButton, in: app))
        accountButton.tap()

        XCTAssertTrue(app.buttons["delete-account-button"].waitForExistence(timeout: 3))
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
        XCTAssertTrue(app.buttons["delete-account-button"].waitForExistence(timeout: 3))
        app.buttons["lifecycle-back-button"].tap()

        let helpButton = app.buttons["help-button"]
        XCTAssertTrue(helpButton.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToHittable(helpButton, in: app))
        helpButton.tap()

        XCTAssertTrue(app.staticTexts["使い方・ヘルプ"].waitForExistence(timeout: 3))
        let replayButton = buttonContainingLabel("最初の案内をもう一度見る", in: app)
        XCTAssertTrue(replayButton.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollToHittable(replayButton, in: app, maximumSwipes: 10))
        replayButton.tap()
        XCTAssertTrue(app.staticTexts["家族で一日ひとつ"].waitForExistence(timeout: 3))
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
            app.staticTexts["過去の回答はまだありません"]
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testHistoryFiltersCanExpandFromMineToWholeFamily() throws {
        let app = launchAuthenticatedDemo()
        openProfile(in: app)

        let filterButton = buttonContainingLabel("絞り込み", in: app)
        XCTAssertTrue(filterButton.waitForExistence(timeout: 5))
        XCTAssertTrue(
            scrollAboveBottomNavigation(filterButton, in: app),
            "History filters should be fully visible above the bottom navigation"
        )
        filterButton.tap()

        XCTAssertTrue(app.staticTexts["履歴を絞り込む"].waitForExistence(timeout: 3))
        let familyScope = app.buttons["家族全員"]
        XCTAssertTrue(familyScope.waitForExistence(timeout: 3))
        familyScope.tap()

        let applyButton = buttonContainingLabel("この条件で表示", in: app)
        XCTAssertTrue(scrollToHittable(applyButton, in: app))
        applyButton.tap()

        XCTAssertTrue(
            app.staticTexts["夕飯のときに昔の写真を見つけて、みんなで笑ったこと。"]
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testOwnerCanReachAnswerEditAndDeleteControls() throws {
        let app = launchAuthenticatedDemo()
        openProfile(in: app)

        let editButton = app.buttons["edit-answer-demo-answer-history"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollAboveBottomNavigation(editButton, in: app))
        editButton.tap()

        XCTAssertTrue(app.staticTexts["回答を編集"].waitForExistence(timeout: 3))
        XCTAssertTrue(buttonContainingLabel("変更を保存", in: app).exists)
        let deleteButton = app.buttons["回答を削除"]
        XCTAssertTrue(deleteButton.exists)
        XCTAssertTrue(scrollAboveBottomNavigation(deleteButton, in: app))
        deleteButton.tap()

        XCTAssertTrue(app.staticTexts["この回答を削除しますか？"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testCommentOwnershipReplyAndReportActionsAreReachable() throws {
        let app = launchAuthenticatedDemo()
        let commentsButton = app.buttons["answer-comments-demo-answer-family"]
        XCTAssertTrue(commentsButton.waitForExistence(timeout: 5))
        // Keep the action comfortably above the persistent bottom navigation.
        // XCTest can report a partly covered control as hittable, so exercise
        // the same short scroll a user would use to reveal the card actions.
        XCTAssertTrue(scrollAboveBottomNavigation(commentsButton, in: app))
        commentsButton.tap()

        let commentsTitle = app.staticTexts["comments-screen-title"]
        if !commentsTitle.waitForExistence(timeout: 3),
           commentsButton.exists {
            XCTAssertTrue(scrollAboveBottomNavigation(commentsButton, in: app))
            commentsButton.tap()
        }
        XCTAssertTrue(commentsTitle.waitForExistence(timeout: 3))

        let editOwnComment = app.buttons["edit-comment-demo-comment-1"]
        let deleteOwnComment = app.buttons["delete-comment-demo-comment-1"]
        XCTAssertTrue(editOwnComment.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollToHittable(editOwnComment, in: app))
        XCTAssertTrue(editOwnComment.isHittable)
        XCTAssertTrue(deleteOwnComment.isHittable)

        deleteOwnComment.tap()
        let deleteAlert = app.alerts.firstMatch
        XCTAssertTrue(deleteAlert.waitForExistence(timeout: 3))
        XCTAssertTrue(deleteAlert.buttons["削除"].exists)
        let cancelDeletion = deleteAlert.buttons["キャンセル"]
        XCTAssertTrue(cancelDeletion.exists)
        cancelDeletion.tap()

        editOwnComment.tap()
        XCTAssertTrue(app.staticTexts["コメントを編集"].waitForExistence(timeout: 3))
        XCTAssertTrue(buttonContainingLabel("変更を保存", in: app).exists)
        app.buttons["lifecycle-back-button"].tap()
        XCTAssertTrue(commentsTitle.waitForExistence(timeout: 3))

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
        let useAnswerButton = app.buttons["この回答"]
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
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()

        let familyTab = app.buttons["家族"]
        let profileTab = app.buttons["あなた"]
        XCTAssertTrue(familyTab.waitForExistence(timeout: 5))
        XCTAssertTrue(profileTab.exists)
        XCTAssertTrue(familyTab.isHittable)
        XCTAssertTrue(profileTab.isHittable)

        let answerQuestion = app.buttons["回答する"]
        XCTAssertTrue(answerQuestion.waitForExistence(timeout: 3))
        XCTAssertTrue(
            scrollAboveBottomNavigation(
                answerQuestion,
                in: app,
                maximumSwipes: 10
            )
        )
        answerQuestion.tap()
        XCTAssertTrue(app.buttons["声で回答"].waitForExistence(timeout: 3))
        let questionBack = app.buttons["戻る"].firstMatch
        XCTAssertTrue(questionBack.isHittable)
        questionBack.tap()

        let familyComments = app.buttons["answer-comments-demo-answer-family"]
        XCTAssertTrue(familyComments.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollAboveBottomNavigation(familyComments, in: app))
        familyComments.tap()
        XCTAssertTrue(app.staticTexts["comments-screen-title"].waitForExistence(timeout: 3))
        let commentsBack = app.buttons["戻る"].firstMatch
        XCTAssertTrue(commentsBack.isHittable)
        commentsBack.tap()

        XCTAssertTrue(profileTab.waitForExistence(timeout: 3))
        profileTab.tap()
        let settingsButton = app.buttons["設定"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollToHittable(settingsButton, in: app))
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

    @MainActor
    private func launchSignedOutDemo(
        additionalArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchEnvironment["TSUTSUURA_DEMO_MODE"] = "signedOut"
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
        let profileButton = app.buttons["あなた"]
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
        let bottomNavigation = app.buttons["家族"]
        guard bottomNavigation.exists else {
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
