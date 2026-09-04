import XCTest

@MainActor
final class WellSpentWatchUITests: XCTestCase {
    private let projectAID = "20000000-0000-0000-0000-000000000001"

    func testPopulatedPickerImmediatelyStartsOpenTimer() {
        let app = launch(fixture: "populated")

        XCTAssertTrue(app.staticTexts["Projects"].waitForExistence(timeout: 10))
        app.buttons["watch.project.open.\(projectAID)"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["watch.timer.running"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertEqual(
            app.descendants(matching: .any)["watch.metrics.project"].label,
            "Project, Client Launch"
        )
        XCTAssertEqual(app.buttons["watch.metrics.no-goal"].label, "No time goal")
        XCTAssertTrue(app.descendants(matching: .any)["watch.timer.pending-sync"].exists)
    }

    func testPresetGoalImmediatelyStartsTimer() {
        let app = launch(fixture: "populated")

        XCTAssertTrue(
            app.buttons["watch.project.options.\(projectAID)"].waitForExistence(timeout: 10)
        )
        app.buttons["watch.project.options.\(projectAID)"].tap()
        XCTAssertTrue(app.buttons["watch.goal.30"].waitForExistence(timeout: 5))
        app.buttons["watch.goal.30"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["watch.timer.running"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.descendants(matching: .any)["watch.metrics.goal"].exists)
    }

    func testSetupAndEmptyCatalogHaveDifferentRecoveryCopy() {
        var app = launch(fixture: "setup")
        XCTAssertTrue(
            app.descendants(matching: .any)["watch.state.finish-setup"]
                .waitForExistence(timeout: 10)
        )
        app.terminate()

        app = launch(fixture: "empty")
        XCTAssertTrue(
            app.descendants(matching: .any)["watch.state.no-projects"]
                .waitForExistence(timeout: 10)
        )
    }

    func testArchivedProjectIsRemovedFromPicker() {
        let app = launch(fixture: "archived")

        XCTAssertTrue(app.staticTexts["Projects"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Archived Client"].exists)
        XCTAssertTrue(app.staticTexts["Client Launch"].exists)
    }

    func testCachedProjectRemainsSelectableOfflineAndWhilePending() {
        var app = launch(fixture: "offline")
        XCTAssertTrue(
            app.descendants(matching: .any)["watch.sync-badge.offline"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.buttons["watch.project.open.\(projectAID)"].isEnabled)
        app.buttons["watch.project.open.\(projectAID)"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["watch.timer.pending-sync"]
                .waitForExistence(timeout: 5)
        )
        app.terminate()

        app = launch(fixture: "pending")
        XCTAssertTrue(
            app.descendants(matching: .any)["watch.sync-badge.pending"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.buttons["watch.project.open.\(projectAID)"].isEnabled)
    }

    func testPersistedActiveRunReconstructsWithoutAnIntermediateScreen() {
        let app = launch(fixture: "active")

        XCTAssertTrue(
            app.descendants(matching: .any)["watch.timer.running"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertEqual(
            app.descendants(matching: .any)["watch.metrics.project"].label,
            "Project, Client Launch"
        )
        XCTAssertTrue(app.descendants(matching: .any)["watch.metrics.goal"].exists)
    }

    func testCrownMetricPagesExposeElapsedRunAndPhoneAuthoredTotals() {
        let app = launch(fixture: "active")

        let elapsedPage = app.descendants(matching: .any)["watch.metrics.elapsed"]
        XCTAssertTrue(elapsedPage.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["watch.metrics.billable"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["watch.metrics.goal"].exists)

        app.swipeUp()
        let runPage = app.descendants(matching: .any)["watch.metrics.run"]
        XCTAssertTrue(runPage.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["watch.metrics.run.paused"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["watch.metrics.run.segments"].exists)

        app.swipeUp()
        XCTAssertTrue(
            app.descendants(matching: .any)["watch.metrics.totals"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.descendants(matching: .any)["watch.metrics.totals.today"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["watch.metrics.totals.week"].exists)
    }

    func testHorizontalSwipeRevealsWorkoutStyleControlSurface() {
        let app = launch(fixture: "active")

        XCTAssertTrue(
            app.descendants(matching: .any)["watch.metrics.elapsed"]
                .waitForExistence(timeout: 10)
        )
        app.swipeRight()

        XCTAssertTrue(
            app.descendants(matching: .any)["watch.controls.screen"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["watch.controls.end"].isEnabled)
        XCTAssertTrue(app.buttons["watch.controls.pause"].isEnabled)
        XCTAssertTrue(app.buttons["watch.controls.new"].isEnabled)
    }

    func testPauseAndResumeExposeBusyStateAndPersistVisibleState() {
        let app = launch(
            fixture: "active",
            controlSurface: true,
            controlDelay: true
        )

        let pause = app.buttons["watch.controls.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        pause.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["watch.controls.busy"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertFalse(app.buttons["watch.controls.new"].isEnabled)

        let resume = app.buttons["watch.controls.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        XCTAssertTrue(resume.isEnabled)
        resume.tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        XCTAssertTrue(pause.isEnabled)
    }

    func testEndRequiresConfirmationThenRoutesToPersistedSummary() {
        let app = launch(fixture: "active", controlSurface: true)

        let end = app.buttons["watch.controls.end"]
        XCTAssertTrue(end.waitForExistence(timeout: 10))
        end.tap()
        XCTAssertTrue(app.buttons["End Run"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'billable time'"))
                .firstMatch.exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(end.waitForExistence(timeout: 5))

        end.tap()
        app.buttons["End Run"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["watch.end-summary.screen"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.descendants(matching: .any)["watch.end-summary.billable"].exists)
        XCTAssertEqual(
            app.descendants(matching: .any)["watch.end-summary.sync"].label,
            "Run saved locally and pending sync"
        )
        app.buttons["watch.end-summary.done"].tap()
        XCTAssertTrue(app.staticTexts["Projects"].waitForExistence(timeout: 5))
    }

    func testNewSwitchesProjectsAndFailureKeepsOriginalRun() {
        var app = launch(fixture: "active", controlSurface: true)
        XCTAssertTrue(app.buttons["watch.controls.new"].waitForExistence(timeout: 10))
        app.buttons["watch.controls.new"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["watch.switch.screen"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Client Launch"].exists)
        app.buttons["watch.switch.project.20000000-0000-0000-0000-000000000002"].tap()
        app.swipeLeft()
        let switchedProject = app.descendants(matching: .any)["watch.metrics.project"]
        XCTAssertTrue(switchedProject.waitForExistence(timeout: 5))
        XCTAssertEqual(switchedProject.label, "Project, Admin & Operations")
        app.terminate()

        app = launch(
            fixture: "active",
            controlSurface: true,
            controlFailure: "switch"
        )
        XCTAssertTrue(app.buttons["watch.controls.new"].waitForExistence(timeout: 10))
        app.buttons["watch.controls.new"].tap()
        app.buttons["watch.switch.project.20000000-0000-0000-0000-000000000002"].tap()
        XCTAssertTrue(app.staticTexts["Couldn’t switch"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        app.swipeLeft()
        let originalProject = app.descendants(matching: .any)["watch.metrics.project"]
        XCTAssertTrue(originalProject.waitForExistence(timeout: 5))
        XCTAssertEqual(originalProject.label, "Project, Client Launch")
    }

    func testSwitchPickerHandlesOfflineSingleProjectAndArchivedDestination() {
        var app = launch(fixture: "active-offline", controlSurface: true)
        XCTAssertTrue(app.buttons["watch.controls.new"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["watch.controls.pause"].isEnabled)
        app.terminate()

        app = launch(fixture: "active-single-project", controlSurface: true)
        XCTAssertTrue(app.buttons["watch.controls.new"].waitForExistence(timeout: 10))
        app.buttons["watch.controls.new"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["watch.switch.empty"]
                .waitForExistence(timeout: 5)
        )
        app.buttons["watch.switch.cancel"].firstMatch.tap()
        app.terminate()

        app = launch(fixture: "active-archived-target", controlSurface: true)
        XCTAssertTrue(app.buttons["watch.controls.new"].waitForExistence(timeout: 10))
        app.buttons["watch.controls.new"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["watch.switch.screen"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.staticTexts["Archived Client"].exists)
    }

    func testEndedSummaryShowsExactOrderedBillingDetailsBeforeOptionalEdits() {
        let app = launch(fixture: "ended")

        XCTAssertTrue(
            app.descendants(matching: .any)["watch.end-summary.screen"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertEqual(
            app.descendants(matching: .any)["watch.end-summary.billable"].label,
            "Billable duration, 12 minutes"
        )
        XCTAssertEqual(
            app.descendants(matching: .any)["watch.end-summary.paused"].label,
            "Paused, 2 minutes"
        )
        XCTAssertTrue(app.descendants(matching: .any)["watch.end-summary.started"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["watch.end-summary.ended"].exists)
        XCTAssertEqual(
            app.descendants(matching: .any)["watch.end-summary.goal"].label,
            "Goal, Goal reached, 2 minutes over"
        )
        XCTAssertEqual(
            app.descendants(matching: .any)["watch.end-summary.segments"].label,
            "Segments, 2 segments"
        )
        XCTAssertEqual(
            app.descendants(matching: .any)["watch.end-summary.sync"].label,
            "Run synced"
        )
    }

    func testSystemNoteEntryCancelAndDoneLeaveEndedRunSafe() {
        let app = launch(fixture: "ended")
        let note = app.buttons["watch.end-summary.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        note.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["watch.end-summary.note-editor"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.textFields["watch.end-summary.note-field"].exists)
        app.buttons["watch.end-summary.note-cancel"].firstMatch.tap()

        let done = app.buttons["watch.end-summary.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(app.staticTexts["Projects"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["watch.timer.running"].exists)
    }

    func testOfflineTagAnnotationPersistsBeforeSuccessAndShowsPendingState() {
        let app = launch(
            fixture: "ended-offline",
            summaryDelay: true
        )
        let tags = app.buttons["watch.end-summary.tags"]
        XCTAssertTrue(tags.waitForExistence(timeout: 10))
        tags.tap()
        let billableTag =
            app.buttons["watch.end-summary.tag.90000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(billableTag.waitForExistence(timeout: 5))
        billableTag.tap()
        app.buttons["watch.end-summary.tags-use"].tap()

        let save = app.buttons["watch.end-summary.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["watch.end-summary.saving"]
                .waitForExistence(timeout: 2)
        )
        let done = app.buttons["watch.end-summary.done"]
        XCTAssertFalse(done.isEnabled)
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: done
        )
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        XCTAssertEqual(
            app.descendants(matching: .any)["watch.end-summary.sync"].label,
            "Offline. Run saved locally and will sync later"
        )
        XCTAssertEqual(
            app.buttons["watch.end-summary.tags"].label,
            "Tags, Billable"
        )
    }

    func testAnnotationFailureCanDiscardEditWithoutChangingEndedRun() {
        let app = launch(fixture: "ended", summaryFailure: true)
        XCTAssertTrue(app.buttons["watch.end-summary.tags"].waitForExistence(timeout: 10))
        app.buttons["watch.end-summary.tags"].tap()
        app.buttons["watch.end-summary.tag.90000000-0000-0000-0000-000000000002"].tap()
        app.buttons["watch.end-summary.tags-use"].tap()
        app.buttons["watch.end-summary.save"].tap()

        XCTAssertTrue(app.staticTexts["Couldn’t save changes"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["Your run is still saved. The note and tags were not changed."].exists
        )
        app.buttons["Discard Edit"].tap()
        XCTAssertTrue(app.buttons["watch.end-summary.done"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["watch.end-summary.save"].exists)
        XCTAssertEqual(app.buttons["watch.end-summary.tags"].label, "Tags, None")
    }

    func testDoneRequiresConfirmationForAnUnsavedAnnotationDraft() {
        let app = launch(fixture: "ended")
        XCTAssertTrue(app.buttons["watch.end-summary.tags"].waitForExistence(timeout: 10))
        app.buttons["watch.end-summary.tags"].tap()
        app.buttons["watch.end-summary.tag.90000000-0000-0000-0000-000000000001"].tap()
        app.buttons["watch.end-summary.tags-use"].tap()

        let done = app.buttons["watch.end-summary.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(app.staticTexts["Unsaved changes"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["watch.timer.running"].exists)
    }

    func testHistoricalTagLongContentAndSummaryRelaunchRemainUnderstandable() {
        var app = launch(fixture: "ended-historical-tag")
        let tags = app.buttons["watch.end-summary.tags"]
        XCTAssertTrue(tags.waitForExistence(timeout: 10))
        XCTAssertEqual(tags.label, "Tags, Archived tag")
        tags.tap()
        XCTAssertTrue(app.staticTexts["No longer active"].waitForExistence(timeout: 5))
        app.buttons["watch.end-summary.tags-cancel"].firstMatch.tap()
        app.terminate()

        app = launch(fixture: "ended-long-content", largestText: true)
        XCTAssertTrue(
            app.descendants(matching: .any)["watch.end-summary.screen"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.buttons["watch.end-summary.note"].exists)
        XCTAssertTrue(app.buttons["watch.end-summary.tags"].exists)
        app.terminate()

        app = launch(fixture: "ended")
        XCTAssertTrue(
            app.descendants(matching: .any)["watch.end-summary.screen"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertFalse(app.descendants(matching: .any)["watch.timer.running"].exists)
    }

    func testPausedBillablePresentationDoesNotAdvance() {
        let app = launch(fixture: "paused")
        let billable = app.descendants(matching: .any)["watch.metrics.billable"]
        XCTAssertTrue(billable.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Paused"].exists)
        let initialValue = billable.label

        let wait = expectation(description: "Observe paused presentation")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { wait.fulfill() }
        waitForExpectations(timeout: 3)

        XCTAssertEqual(billable.label, initialValue)
    }

    func testGoalNoGoalReachedAndOvertimeStates() {
        var app = launch(fixture: "active-no-goal")
        XCTAssertTrue(app.buttons["watch.metrics.no-goal"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["watch.metrics.no-goal"].label, "No time goal")
        app.terminate()

        app = launch(fixture: "goal-reached")
        let reachedGoal = app.descendants(matching: .any)["watch.metrics.goal"]
        XCTAssertTrue(reachedGoal.waitForExistence(timeout: 10))
        XCTAssertEqual(reachedGoal.label, "Time goal reached")
        app.terminate()

        app = launch(fixture: "overtime")
        let overtimeGoal = app.descendants(matching: .any)["watch.metrics.goal"]
        XCTAssertTrue(overtimeGoal.waitForExistence(timeout: 10))
        XCTAssertTrue(overtimeGoal.label.hasPrefix("Goal exceeded by"))
    }

    func testOfflinePendingAndStaleTotalsAreExplicit() {
        var app = launch(fixture: "active-pending")
        XCTAssertTrue(
            app.descendants(matching: .any)["watch.timer.pending-sync"]
                .waitForExistence(timeout: 10)
        )
        app.terminate()

        app = launch(fixture: "active-offline")
        XCTAssertTrue(
            app.descendants(matching: .any)["watch.timer.offline"]
                .waitForExistence(timeout: 10)
        )
        app.terminate()

        app = launch(fixture: "active-offline", metricPage: 2)
        let offlineTotals = app.staticTexts["watch.metrics.totals"]
        XCTAssertTrue(offlineTotals.waitForExistence(timeout: 10))
        XCTAssertTrue(offlineTotals.label.contains("offline cached"))
        app.terminate()

        app = launch(fixture: "stale-totals", metricPage: 2)
        XCTAssertTrue(
            app.descendants(matching: .any)["watch.metrics.totals.stale"]
                .waitForExistence(timeout: 10)
        )
    }

    func testPrivacyRedactionAndLargeDurationRemainLegible() {
        var app = launch(fixture: "active", privacyRedacted: true)
        let privateProject = app.descendants(matching: .any)["watch.metrics.project"]
        XCTAssertTrue(privateProject.waitForExistence(timeout: 10))
        XCTAssertEqual(privateProject.label, "Project, Billable timer")
        XCTAssertFalse(privateProject.label.contains("Client Launch"))
        app.terminate()

        app = launch(fixture: "large-duration")
        let billable = app.descendants(matching: .any)["watch.metrics.billable"]
        XCTAssertTrue(billable.waitForExistence(timeout: 10))
        XCTAssertTrue(billable.label.contains("100 hours"))
    }

    func testStartFailureKeepsPickerRecoverable() {
        let app = launch(fixture: "populated", startFailure: true)

        XCTAssertTrue(app.staticTexts["Projects"].waitForExistence(timeout: 10))
        app.buttons["watch.project.open.\(projectAID)"].tap()
        XCTAssertTrue(app.staticTexts["Couldn’t start"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Projects"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["watch.timer.running"].exists)
    }

    func testConflictAndUpgradeAreBlockingStates() {
        var app = launch(fixture: "conflict")
        XCTAssertTrue(
            app.descendants(matching: .any)["watch.state.review-required"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertFalse(app.staticTexts["Projects"].exists)
        app.terminate()

        app = launch(fixture: "unsupported")
        XCTAssertTrue(
            app.descendants(matching: .any)["watch.state.update-required"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertFalse(app.staticTexts["Projects"].exists)
    }

    func testLongDuplicateNamesAndMissingEmojiRender() {
        let app = launch(fixture: "long-names", largestText: true)

        XCTAssertTrue(
            app.descendants(matching: .any)["watch.project-picker.screen"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(
            app.buttons["watch.project.open.20000000-0000-0000-0000-000000000003"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.buttons["watch.project.options.20000000-0000-0000-0000-000000000003"]
                .isEnabled
        )
    }

    private func launch(
        fixture: String,
        largestText: Bool = false,
        startFailure: Bool = false,
        privacyRedacted: Bool = false,
        metricPage: Int? = nil,
        controlSurface: Bool = false,
        controlDelay: Bool = false,
        controlFailure: String? = nil,
        summaryDelay: Bool = false,
        summaryFailure: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-watch-fixture", fixture]
        if largestText { app.launchArguments.append("-ui-test-largest-text") }
        if startFailure { app.launchArguments.append("-ui-test-start-failure") }
        if privacyRedacted { app.launchArguments.append("-ui-test-privacy-redacted") }
        if controlSurface { app.launchArguments.append("-ui-test-control-surface") }
        if controlDelay { app.launchArguments.append("-ui-test-control-delay") }
        if summaryDelay { app.launchArguments.append("-ui-test-summary-delay") }
        if summaryFailure { app.launchArguments.append("-ui-test-summary-failure") }
        if let controlFailure {
            app.launchArguments.append(contentsOf: ["-ui-test-control-failure", controlFailure])
        }
        if let metricPage {
            app.launchArguments.append(contentsOf: ["-ui-test-metric-page", "\(metricPage)"])
        }
        app.launch()
        return app
    }
}
