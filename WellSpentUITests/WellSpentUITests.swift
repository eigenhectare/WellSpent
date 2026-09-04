import XCTest

final class WellSpentUITests: XCTestCase {
    private let projectOneID = "11111111-1111-1111-1111-111111111111"
    private let projectTwoID = "22222222-2222-2222-2222-222222222222"
    private let archivedProjectID = "33333333-3333-3333-3333-333333333333"
    private let completedSessionID = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    private let meetingTagID = "10000000-0000-4000-8000-000000000001"
    private let collaborationTagID = "10000000-0000-4000-8000-000000000003"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFreshOnboardingExplainsModelAndCanDismissToEmptyState() {
        let app = launch()

        XCTAssertTrue(app.otherElements["onboarding-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Time survives interruptions"].exists)
        XCTAssertTrue(app.staticTexts["Private on the Lock Screen"].exists)
        app.buttons["dismiss-onboarding"].tap()

        XCTAssertTrue(app.staticTexts["No Projects Yet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["create-first-project"].exists)
    }

    @MainActor
    func testOnboardingCreatesFirstProjectAtLargestAccessibilitySize() {
        let app = launch(
            additionalArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        )

        let name = app.textFields["onboarding-project-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("First Client")
        name.typeText("\n")
        app.buttons["onboarding-create-project"].tap()

        XCTAssertTrue(app.staticTexts["First Client"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTrackStartsOneTimerAndArchivedProjectsStayHidden() {
        let app = launch(
            "UITEST_SKIP_ONBOARDING",
            "UITEST_SEED_ARCHIVED",
            additionalArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        )

        XCTAssertTrue(app.staticTexts["Client Redesign"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Legacy Account"].exists)
        app.buttons["project-timer-\(projectOneID)"].tap()

        XCTAssertTrue(element("active-timer-card", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("active-elapsed-time", in: app).exists)
        XCTAssertTrue(app.buttons["stop-active-timer"].label.contains("Stop Client Redesign timer"))
    }

    @MainActor
    func testPauseAndResumeKeepOneTimerRunVisible() {
        let app = launch("UITEST_SKIP_ONBOARDING", "UITEST_SEED_ACTIVE")
        let pause = app.buttons["pause-active-timer"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))

        pause.tap()

        let resume = app.buttons["resume-active-timer"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Paused"].firstMatch.exists)
        XCTAssertTrue(element("active-timer-card", in: app).exists)

        resume.tap()

        XCTAssertTrue(app.buttons["pause-active-timer"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("active-timer-card", in: app).exists)
    }

    @MainActor
    func testStartFailureNeverShowsFalseActiveState() {
        let app = launch(
            "UITEST_SKIP_ONBOARDING",
            "UITEST_SEED_POPULATED",
            "UITEST_FORCE_COMMAND_ERROR"
        )

        app.buttons["project-timer-\(projectOneID)"].tap()

        XCTAssertTrue(
            app.staticTexts["The change could not be saved. Your existing data was not changed."]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(element("active-timer-card", in: app).exists)
    }

    @MainActor
    func testSwitchStartsNewTimerBeforePreviousNoteSheet() {
        let app = launch("UITEST_SKIP_ONBOARDING", "UITEST_SEED_ACTIVE")

        app.buttons["project-timer-\(projectTwoID)"].tap()

        XCTAssertTrue(app.otherElements["session-completion-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["switch-kept-running"].exists)
        app.buttons["skip-completion-note"].tap()
        XCTAssertTrue(app.staticTexts["Advisory"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("active-timer-card", in: app).exists)
    }

    @MainActor
    func testSwitchNoteSaveDoesNotStopNewTimer() {
        let app = launch("UITEST_SKIP_ONBOARDING", "UITEST_SEED_ACTIVE")
        app.buttons["project-timer-\(projectTwoID)"].tap()
        XCTAssertTrue(app.otherElements["session-completion-screen"].waitForExistence(timeout: 5))

        let note = app.textViews["completion-note"]
        for _ in 0..<6 where !note.isHittable { app.swipeUp() }
        XCTAssertTrue(note.isHittable)
        note.tap()
        note.typeText("Previous-session handoff")
        app.buttons["save-completion-note"].tap()

        XCTAssertTrue(element("active-timer-card", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["stop-active-timer"].label.contains("Stop Advisory timer"))
    }

    @MainActor
    func testSwitchFailureKeepsExistingTimerActive() {
        let app = launch(
            "UITEST_SKIP_ONBOARDING",
            "UITEST_SEED_ACTIVE",
            "UITEST_FORCE_COMMAND_ERROR"
        )
        app.buttons["project-timer-\(projectTwoID)"].tap()

        XCTAssertTrue(
            app.staticTexts["The change could not be saved. Your existing data was not changed."]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["stop-active-timer"].label.contains("Stop Client Redesign timer"))
        XCTAssertFalse(app.otherElements["session-completion-screen"].exists)
    }

    @MainActor
    func testActiveTimerSurvivesBackgroundAndStopPersistsBeforeCompletion() {
        let app = launch("UITEST_SKIP_ONBOARDING", "UITEST_SEED_ACTIVE")
        XCTAssertTrue(element("active-timer-card", in: app).waitForExistence(timeout: 5))

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(element("active-timer-card", in: app).waitForExistence(timeout: 5))
        app.buttons["stop-active-timer"].tap()

        XCTAssertTrue(app.otherElements["session-completion-screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["completed-session-duration"].exists)
        app.terminate()

        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["UITEST_SKIP_ONBOARDING"]
        relaunched.launch()
        XCTAssertFalse(element("active-timer-card", in: relaunched).exists)
        relaunched.buttons["session-history"].tap()
        XCTAssertTrue(relaunched.staticTexts["Client Redesign"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCompletionDeepLinkLoadsSavedSessionAndLongNoteCanBeSaved() {
        let app = launch("UITEST_SKIP_ONBOARDING", "UITEST_SEED_COMPLETION")
        let url = URL(string: "wellspent://completion/\(completedSessionID)")!
        app.open(url)

        XCTAssertTrue(app.otherElements["session-completion-screen"].waitForExistence(timeout: 5))
        let note = app.textViews["completion-note"]
        note.tap()
        note.typeText(String(repeating: "Detailed client work. ", count: 20))
        app.buttons["save-completion-note"].tap()
        XCTAssertFalse(app.otherElements["session-completion-screen"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testProjectManagementBlocksActiveArchiveAndRestoresArchivedProject() {
        let activeApp = launch("UITEST_SKIP_ONBOARDING", "UITEST_SEED_ACTIVE")
        activeApp.buttons["manage-projects"].tap()
        XCTAssertTrue(activeApp.navigationBars["Projects"].waitForExistence(timeout: 5))
        activeApp.buttons["manage-project-\(projectOneID)"].tap()
        activeApp.buttons["Archive"].tap()
        activeApp.buttons["Archive"].tap()
        XCTAssertTrue(
            activeApp.staticTexts[
                "Stop or switch this active timer before archiving its project."
            ].waitForExistence(timeout: 5)
        )

        activeApp.terminate()
        let archivedApp = launch("UITEST_SKIP_ONBOARDING", "UITEST_SEED_ARCHIVED")
        archivedApp.buttons["manage-projects"].tap()
        XCTAssertTrue(archivedApp.staticTexts["Legacy Account"].waitForExistence(timeout: 5))
        archivedApp.buttons["restore-project-\(archivedProjectID)"].tap()
        XCTAssertTrue(archivedApp.staticTexts["Legacy Account"].exists)
    }

    @MainActor
    func testDuplicateProjectWarningIsNonblocking() {
        let app = launch("UITEST_SKIP_ONBOARDING", "UITEST_SEED_POPULATED")
        app.buttons["manage-projects"].tap()
        app.buttons["new-project"].tap()
        let field = app.textFields["project-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Client Redesign")
        app.buttons["save-project"].tap()

        XCTAssertTrue(
            app.staticTexts["Another project has this exact name. Both projects were kept."]
                .waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testProjectRenamePreservesHistoricalSessionVisibility() {
        let app = launch("UITEST_SKIP_ONBOARDING", "UITEST_SEED_REPORTS")
        app.buttons["manage-projects"].tap()
        app.buttons["manage-project-\(projectOneID)"].tap()
        app.buttons["Edit"].tap()
        let field = app.textFields["project-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(" Updated")
        app.buttons["save-project"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["session-history"].tap()

        XCTAssertTrue(app.staticTexts["Client Redesign Updated"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["session-row-\(completedSessionID)"].exists)
    }

    @MainActor
    func testProjectCanBeCreatedWithAnEmojiIdentity() {
        let app = launch("UITEST_SKIP_ONBOARDING", "UITEST_SEED_POPULATED")
        app.buttons["manage-projects"].tap()
        app.buttons["new-project"].tap()

        let name = app.textFields["project-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Research")

        let emoji = app.textFields["project-emoji"]
        emoji.tap()
        emoji.typeText("🧭")
        app.buttons["save-project"].tap()

        XCTAssertTrue(app.staticTexts["🧭 Research"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCompletionSupportsMultipleTagsAndReviewShowsThem() {
        let app = launch("UITEST_SKIP_ONBOARDING", "UITEST_SEED_COMPLETION")
        let url = URL(string: "wellspent://completion/\(completedSessionID)")!
        app.open(url)

        XCTAssertTrue(app.otherElements["session-completion-screen"].waitForExistence(timeout: 5))
        app.buttons["session-tag-\(meetingTagID)"].tap()
        app.buttons["session-tag-\(collaborationTagID)"].tap()
        app.buttons["save-completion-note"].tap()

        app.buttons["session-history"].tap()
        app.buttons["session-row-\(completedSessionID)"].tap()
        let summary = element("session-tag-summary", in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "meeting, collaboration")
    }

    @MainActor
    func testSettingsCanAddAndRemoveTagChoices() {
        let app = launch("UITEST_SKIP_ONBOARDING")
        app.tabBars.buttons["Settings"].tap()

        let newTag = app.textFields["new-session-tag"]
        for _ in 0..<5 {
            if newTag.exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(newTag.waitForExistence(timeout: 5))
        newTag.tap()
        newTag.typeText("research")
        app.buttons["add-session-tag"].tap()
        XCTAssertTrue(app.staticTexts["research"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Track"].tap()
        app.tabBars.buttons["Settings"].tap()

        let removeMeeting = app.buttons["remove-session-tag-\(meetingTagID)"]
        for _ in 0..<5 {
            if removeMeeting.exists { break }
            app.swipeDown()
        }
        XCTAssertTrue(removeMeeting.exists)
        removeMeeting.tap()
        app.buttons["Remove Tag"].tap()
        XCTAssertTrue(removeMeeting.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testDeleteAllLocalDataRequiresConfirmationAndReturnsToFirstLaunch() {
        let app = launch("UITEST_SKIP_ONBOARDING", "UITEST_SEED_REPORTS")
        app.tabBars.buttons["Settings"].tap()

        let eraseButton = app.buttons["delete-all-local-data"]
        for _ in 0..<6 {
            if eraseButton.exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(eraseButton.waitForExistence(timeout: 5))
        eraseButton.tap()
        let confirmationButton = app.buttons["Delete All Data"]
        XCTAssertTrue(confirmationButton.waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["onboarding-screen"].exists)
        confirmationButton.tap()
        XCTAssertTrue(confirmationButton.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["onboarding-screen"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.otherElements["onboarding-screen"].waitForExistence(timeout: 5))
        app.buttons["dismiss-onboarding"].tap()
        XCTAssertTrue(app.staticTexts["No Projects Yet"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSuccessfulArchiveRemovesProjectFromTrackButKeepsItManageable() {
        let app = launch("UITEST_SKIP_ONBOARDING", "UITEST_SEED_POPULATED")
        app.buttons["manage-projects"].tap()
        app.buttons["manage-project-\(projectTwoID)"].tap()
        app.buttons["Archive"].tap()
        app.buttons["Archive"].tap()
        XCTAssertTrue(app.buttons["restore-project-\(projectTwoID)"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        XCTAssertFalse(app.staticTexts["Advisory"].exists)
    }

    @MainActor
    func testManualEditorShowsValidationAndCancelDoesNotCreateSession() {
        let app = launch(
            "UITEST_SKIP_ONBOARDING",
            "UITEST_SEED_POPULATED",
            "UITEST_PREFILL_INVALID_SESSION"
        )
        app.buttons["session-history"].tap()
        app.buttons["add-manual-session"].tap()
        XCTAssertTrue(app.otherElements["manual-session-editor"].waitForExistence(timeout: 5))
        app.buttons["save-session"].tap()
        XCTAssertTrue(app.staticTexts["session-validation-error"].waitForExistence(timeout: 5))
        app.buttons["cancel-session-editor"].tap()
        XCTAssertTrue(app.staticTexts["No Sessions"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testOverlapWarningAllowsSaveAndHistoryShowsMarker() {
        let app = launch(
            "UITEST_SKIP_ONBOARDING",
            "UITEST_SEED_OVERLAP",
            "UITEST_PREFILL_OVERLAP"
        )
        app.buttons["session-history"].tap()
        XCTAssertTrue(app.staticTexts["overlap-marker"].waitForExistence(timeout: 5))
        app.buttons["add-manual-session"].tap()
        app.buttons["save-session"].tap()
        XCTAssertTrue(app.alerts["Overlap Detected"].waitForExistence(timeout: 5))
        app.buttons["save-overlapping-session"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["overlap-marker"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDeleteRequiresConfirmationAndCancelPreservesSession() {
        let app = launch("UITEST_SKIP_ONBOARDING", "UITEST_SEED_OVERLAP")
        app.buttons["session-history"].tap()
        app.buttons["session-row-\(completedSessionID)"].tap()
        app.buttons["delete-session"].tap()
        XCTAssertTrue(app.alerts["Delete this session?"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(element("session-review-screen", in: app).exists)
    }

    @MainActor
    func testManualEditorCanSelectArchivedProjectForHistoricalWork() {
        let app = launch("UITEST_SKIP_ONBOARDING", "UITEST_SEED_REPORTS")
        app.buttons["session-history"].tap()
        app.buttons["add-manual-session"].tap()
        let projectMenu = app.buttons["Client Redesign"]
        XCTAssertTrue(projectMenu.waitForExistence(timeout: 5))
        projectMenu.tap()

        XCTAssertTrue(app.buttons["Legacy Account — Archived"].waitForExistence(timeout: 5))
        app.buttons["Legacy Account — Archived"].tap()
        app.buttons["cancel-session-editor"].tap()
    }

    @MainActor
    func testPrivacySettingDefaultsOffAndPersistsExplicitOptIn() {
        let app = launch("UITEST_SKIP_ONBOARDING")
        app.tabBars.buttons["Settings"].tap()
        let toggle = app.switches["show-project-names-lock-screen"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertTrue(element("lock-screen-private-preview", in: app).exists)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let enabled = NSPredicate(format: "value == '1'")
        expectation(for: enabled, evaluatedWith: toggle)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(element("lock-screen-specific-preview", in: app).waitForExistence(timeout: 5))
        app.terminate()

        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["UITEST_SKIP_ONBOARDING"]
        relaunched.launch()
        relaunched.tabBars.buttons["Settings"].tap()
        XCTAssertEqual(
            relaunched.switches["show-project-names-lock-screen"].value as? String,
            "1"
        )
    }

    @MainActor
    func testSettingsShowsPrivacySupportAndOwnershipInformation() {
        let app = launch("UITEST_SKIP_ONBOARDING")
        app.tabBars.buttons["Settings"].tap()

        let privacyPolicy = scrollToElement("privacy-policy-link", in: app)
        XCTAssertTrue(privacyPolicy.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollToElement("support-link", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(
            scrollToElement("source-code-link", in: app).waitForExistence(timeout: 5)
        )
        XCTAssertEqual(
            scrollToElement("app-version", in: app).label,
            "Version, 0.1.0 (2)"
        )
        XCTAssertEqual(
            scrollToElement("app-copyright", in: app).label,
            "Copyright, © 2026 WellSpent contributors"
        )
        XCTAssertTrue(
            scrollToElement("source-license", in: app).waitForExistence(timeout: 5)
        )
    }

    @MainActor
    func testDayWeekAndProjectAggregatesOpenExactSourceSegments() {
        let app = launch("UITEST_SKIP_ONBOARDING", "UITEST_SEED_REPORTS")
        app.tabBars.buttons["Reports"].tap()

        XCTAssertTrue(app.buttons["day-report-total"].waitForExistence(timeout: 5))
        app.buttons["day-report-total"].tap()
        XCTAssertTrue(element("report-drill-down", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["report-source-session-\(completedSessionID)"].exists)
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons["Week"].tap()
        XCTAssertTrue(app.buttons["week-report-total"].waitForExistence(timeout: 5))
        app.buttons["week-report-total"].tap()
        XCTAssertTrue(element("report-drill-down", in: app).waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons["Project"].tap()
        XCTAssertTrue(app.buttons["project-report-total"].waitForExistence(timeout: 5))
        app.buttons["project-report-total"].tap()
        XCTAssertTrue(element("report-drill-down", in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testReportDeletionRemovesSourceAndRecalculatesOpenDrillDown() {
        let app = launch("UITEST_SKIP_ONBOARDING", "UITEST_SEED_REPORTS")
        app.tabBars.buttons["Reports"].tap()
        app.buttons["day-report-total"].tap()
        let source = app.buttons["report-source-session-\(completedSessionID)"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap()
        app.buttons["delete-session"].tap()
        app.alerts["Delete this session?"].buttons["Delete Session"].tap()

        XCTAssertTrue(element("report-drill-down", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(source.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testDayReportCoversEmptyAndOverlapStates() {
        let emptyApp = launch("UITEST_SKIP_ONBOARDING", "UITEST_SEED_POPULATED")
        emptyApp.tabBars.buttons["Reports"].tap()
        XCTAssertTrue(emptyApp.staticTexts["No billable time on this day"].waitForExistence(timeout: 5))
        emptyApp.terminate()

        let overlapApp = launch("UITEST_SKIP_ONBOARDING", "UITEST_SEED_OVERLAP")
        overlapApp.tabBars.buttons["Reports"].tap()
        XCTAssertTrue(overlapApp.staticTexts["overlap-marker"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            overlapApp.staticTexts[
                "Overlapping records are both fully included, so a day total may exceed 24 hours."
            ].exists
        )
    }

    @MainActor
    func testLiveActivityFailureKeepsTimerTruthfulAndOffersRetry() {
        let app = launch(
            "UITEST_SKIP_ONBOARDING",
            "UITEST_SEED_POPULATED",
            "UITEST_FORCE_ACTIVITY_ERROR"
        )

        app.buttons["project-timer-\(projectOneID)"].tap()

        XCTAssertTrue(element("active-timer-card", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("live-activity-recovery", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["retry-live-activity"].exists)
        XCTAssertTrue(
            app.staticTexts[
                "Your timer is saved, but the Lock Screen activity is out of date. Retry from the app."
            ].exists
        )
    }

    @MainActor
    func testLongRunningTimerExplainsSourceTruthAndOffersRecreation() {
        let app = launch("UITEST_SKIP_ONBOARDING", "UITEST_SEED_ACTIVE_LONG")

        XCTAssertTrue(element("active-timer-card", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(
            element("long-running-timer-warning", in: app).waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["recreate-live-activity"].exists)
    }

    @MainActor
    func testMalformedTimerStateDirectsUserToSessionHistoryWithoutMutation() {
        let app = launch("UITEST_SKIP_ONBOARDING", "UITEST_SEED_MALFORMED_ACTIVE")

        XCTAssertTrue(
            element("timer-reconciliation-review", in: app).waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Advisory"].exists)
        XCTAssertTrue(app.buttons["session-history"].exists)
    }

    @MainActor
    func testDisabledLiveActivitiesExposeAnActionableSettingsState() {
        let app = launch(
            "UITEST_SKIP_ONBOARDING",
            "UITEST_SEED_POPULATED",
            "UITEST_LIVE_ACTIVITIES_DISABLED"
        )

        app.buttons["project-timer-\(projectOneID)"].tap()

        XCTAssertTrue(element("active-timer-card", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("live-activity-recovery", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["open-live-activity-settings-recovery"].exists)
        XCTAssertFalse(app.buttons["retry-live-activity"].exists)
        XCTAssertTrue(
            app.staticTexts[
                "Your timer is saved, but Live Activities are disabled. Enable them in Settings or continue in the app."
            ].exists
        )

        app.tabBars.buttons["Settings"].tap()

        XCTAssertTrue(
            element("live-activity-availability", in: app).waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["open-live-activity-settings"].exists)
    }

    @MainActor
    private func launch(
        _ arguments: String...,
        additionalArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_RESET_STORE"] + arguments + additionalArguments
        app.launch()
        return app
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func scrollToElement(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let target = element(identifier, in: app)
        for _ in 0..<8 where !target.exists {
            app.swipeUp()
        }
        return target
    }
}
