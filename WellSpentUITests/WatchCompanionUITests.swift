import XCTest

final class WatchCompanionUITests: XCTestCase {
    private let runID = "88888888-8888-4888-8888-888888888888"
    private let firstProject = "11111111-1111-1111-1111-111111111111"

    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testPausedWatchRunResumesAndSwitchesOnPhone() {
        let app = launch("UITEST_SEED_WATCH_PAUSED")
        XCTAssertTrue(app.buttons["resume-active-timer"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["timer-watch-origin"].exists || app.otherElements["timer-watch-origin"].exists)
        app.buttons["resume-active-timer"].tap()
        XCTAssertTrue(app.buttons["pause-active-timer"].waitForExistence(timeout: 5))
        app.buttons["pause-active-timer"].tap()
        app.buttons["project-timer-\(firstProject)"].tap()
        XCTAssertTrue(app.otherElements["session-completion-screen"].waitForExistence(timeout: 5))
        app.buttons["skip-completion-note"].tap()
        XCTAssertTrue(app.buttons["stop-active-timer"].label.contains("Client Redesign"))
    }

    @MainActor
    func testPausedWatchRunEndsWithoutCountingPausedTime() {
        let app = launch("UITEST_SEED_WATCH_PAUSED")
        XCTAssertTrue(app.buttons["stop-active-timer"].waitForExistence(timeout: 8))
        app.buttons["stop-active-timer"].tap()
        XCTAssertTrue(app.otherElements["session-completion-screen"].waitForExistence(timeout: 5))
        let duration = app.staticTexts["completed-session-duration"]
        XCTAssertTrue(duration.waitForExistence(timeout: 5))
        XCTAssertTrue(duration.label.contains("0:10:00"), duration.debugDescription)
        app.buttons["skip-completion-note"].tap()
        XCTAssertFalse(app.buttons["resume-active-timer"].exists)
    }

    @MainActor
    func testWatchHistoryGroupsSegmentsAndKeepsDetailsAvailable() {
        let app = launch("UITEST_SEED_WATCH_ENDED")
        app.buttons["session-history"].tap()
        let row = app.buttons["session-row-\(runID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        XCTAssertTrue(row.label.contains("2 counted segments"))
        row.tap()
        XCTAssertTrue(app.staticTexts["Counted segments"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Segment 1"].exists)
        XCTAssertTrue(app.staticTexts["Segment 2"].exists)
    }

    @MainActor
    func testConflictKeepPhoneAndRelaunchPreservesResolution() {
        let app = launch("UITEST_SEED_WATCH_CONFLICT")
        confirm("keepPhone", in: app)
        XCTAssertTrue(app.buttons["stop-active-timer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["stop-active-timer"].label.contains("Client Redesign"))
        app.terminate()
        app.launchArguments = ["UITEST_SKIP_ONBOARDING"]
        app.launch()
        XCTAssertTrue(app.buttons["stop-active-timer"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["review-watch-conflict"].exists)
    }

    @MainActor
    func testConflictUseWatchShowsChosenProject() {
        let app = launch("UITEST_SEED_WATCH_CONFLICT")
        confirm("useWatch", in: app)
        XCTAssertTrue(app.buttons["stop-active-timer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["stop-active-timer"].label.contains("Advisory"))
    }

    @MainActor
    func testConflictKeepBothExplainsOverlapAndPreservesTwoRuns() {
        let app = launch("UITEST_SEED_WATCH_CONFLICT")
        confirm("keepBoth", in: app)
        XCTAssertTrue(app.buttons["stop-active-timer"].waitForExistence(timeout: 5))
        app.buttons["session-history"].tap()
        XCTAssertTrue(app.staticTexts["Session History"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'session-row-'")).count, 2)
    }

    @MainActor
    func testFailedConflictSaveStaysInConfirmationWithoutLosingVersions() {
        let app = launch("UITEST_SEED_WATCH_CONFLICT", "UITEST_FORCE_COMMAND_ERROR")
        confirm("keepPhone", in: app)
        XCTAssertTrue(app.staticTexts["conflict-save-error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["confirm-conflict-resolution"].isEnabled)
        app.buttons["Cancel"].tap()
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["review-watch-conflict"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["project-timer-\(firstProject)"].isEnabled)
    }

    @MainActor
    func testConflictReviewAtLargestTextAndCancelKeepsVersions() {
        let app = launch(
            "UITEST_SEED_WATCH_CONFLICT", "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL")
        let review = app.buttons["review-watch-conflict"]
        scroll(to: review, in: app)
        review.tap()
        let option = app.buttons["conflict-choice-keepBoth"]
        scroll(to: option, in: app)
        option.tap()
        XCTAssertTrue(app.staticTexts["conflict-result-explanation"].waitForExistence(timeout: 5))
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Conflict confirmation — largest text"
        capture.lifetime = .keepAlways
        add(capture)
        app.buttons["Cancel"].tap()
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["review-watch-conflict"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func confirm(_ choice: String, in app: XCUIApplication) {
        let review = app.buttons["review-watch-conflict"]
        XCTAssertTrue(review.waitForExistence(timeout: 8))
        review.tap()
        let option = app.buttons["conflict-choice-\(choice)"]
        scroll(to: option, in: app)
        option.tap()
        XCTAssertTrue(app.staticTexts["conflict-result-explanation"].waitForExistence(timeout: 5))
        if choice == "keepBoth" {
            XCTAssertTrue(app.staticTexts["conflict-result-explanation"].label.contains("overlapping time"))
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "Keep both confirmation"
            capture.lifetime = .keepAlways
            add(capture)
        }
        let save = app.buttons["confirm-conflict-resolution"]
        scroll(to: save, in: app)
        save.tap()
    }

    @MainActor
    private func scroll(to element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_RESET_STORE", "UITEST_SKIP_ONBOARDING"] + arguments
        // An earlier app-hosted unit suite may have left a launch without these
        // fixture arguments running. Always start a fresh fixture process.
        app.terminate()
        app.launch()
        return app
    }
}
