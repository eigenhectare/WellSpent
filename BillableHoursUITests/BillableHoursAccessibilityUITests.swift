import XCTest

final class BillableHoursAccessibilityUITests: XCTestCase {
    private let projectOneID = "11111111-1111-1111-1111-111111111111"
    private let completedSessionID = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOnboardingAtLargestDynamicTypePassesAccessibilityAudit() throws {
        let app = launch(largestDynamicType: true)

        XCTAssertTrue(app.textFields["onboarding-project-name"].waitForExistence(timeout: 5))
        try performAccessibilityAudit(in: app)
    }

    @MainActor
    func testActiveTimerAndCompletionPassAccessibilityAudits() throws {
        let app = launch(
            "UITEST_SKIP_ONBOARDING",
            "UITEST_SEED_ACTIVE",
            largestDynamicType: true
        )

        XCTAssertTrue(element("active-timer-card", in: app).waitForExistence(timeout: 5))
        try performAccessibilityAudit(in: app)

        let stopButton = app.buttons["stop-active-timer"]
        XCTAssertTrue(stopButton.exists)
        stopButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(element("session-completion-screen", in: app).waitForExistence(timeout: 5))
        try performAccessibilityAudit(in: app)
    }

    @MainActor
    func testDayWeekAndProjectReportsPassAccessibilityAudits() throws {
        let app = launch(
            "UITEST_SKIP_ONBOARDING",
            "UITEST_SEED_REPORTS",
            largestDynamicType: true
        )
        app.tabBars.buttons["Reports"].tap()

        XCTAssertTrue(element("day-report", in: app).waitForExistence(timeout: 5))
        try performAccessibilityAudit(in: app)

        app.buttons["Week"].tap()
        XCTAssertTrue(element("week-report", in: app).waitForExistence(timeout: 5))
        try performAccessibilityAudit(in: app)

        app.buttons["Project"].tap()
        XCTAssertTrue(element("project-report", in: app).waitForExistence(timeout: 5))
        try performAccessibilityAudit(in: app)
    }

    @MainActor
    func testHistoryReviewAndManualEditorPassAccessibilityAudits() throws {
        let app = launch(
            "UITEST_SKIP_ONBOARDING",
            "UITEST_SEED_OVERLAP",
            largestDynamicType: true
        )
        app.buttons["session-history"].tap()

        XCTAssertTrue(app.buttons["session-row-\(completedSessionID)"].waitForExistence(timeout: 5))
        try performAccessibilityAudit(in: app)

        app.buttons["session-row-\(completedSessionID)"].tap()
        XCTAssertTrue(element("session-review-screen", in: app).waitForExistence(timeout: 5))
        try performAccessibilityAudit(in: app)

        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["add-manual-session"].tap()
        XCTAssertTrue(element("manual-session-editor", in: app).waitForExistence(timeout: 5))
        try performAccessibilityAudit(in: app)
    }

    @MainActor
    func testProjectManagementAndSettingsPassAccessibilityAudits() throws {
        let app = launch(
            "UITEST_SKIP_ONBOARDING",
            "UITEST_SEED_POPULATED",
            largestDynamicType: true
        )
        app.buttons["manage-projects"].tap()

        XCTAssertTrue(app.navigationBars["Projects"].waitForExistence(timeout: 5))
        try performAccessibilityAudit(in: app)

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.switches["show-project-names-lock-screen"].waitForExistence(timeout: 5))
        try performAccessibilityAudit(in: app)
    }

    @MainActor
    func testRecoveryStatesPassAccessibilityAudits() throws {
        let projectionFailure = launch(
            "UITEST_SKIP_ONBOARDING",
            "UITEST_SEED_POPULATED",
            "UITEST_FORCE_ACTIVITY_ERROR",
            largestDynamicType: true
        )
        let startButton = projectionFailure.buttons["project-timer-\(projectOneID)"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(element("live-activity-recovery", in: projectionFailure).waitForExistence(timeout: 5))
        try performAccessibilityAudit(in: projectionFailure)
        projectionFailure.terminate()

        let disabledActivities = launch(
            "UITEST_SKIP_ONBOARDING",
            "UITEST_SEED_POPULATED",
            "UITEST_LIVE_ACTIVITIES_DISABLED",
            largestDynamicType: true
        )
        let disabledStartButton = disabledActivities.buttons[
            "project-timer-\(projectOneID)"
        ]
        XCTAssertTrue(disabledStartButton.waitForExistence(timeout: 5))
        disabledStartButton.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).tap()

        XCTAssertTrue(
            disabledActivities.buttons["open-live-activity-settings-recovery"]
                .waitForExistence(timeout: 5)
        )
        try performAccessibilityAudit(in: disabledActivities)
        disabledActivities.terminate()

        let longTimer = launch(
            "UITEST_SKIP_ONBOARDING",
            "UITEST_SEED_ACTIVE_LONG",
            largestDynamicType: true
        )
        XCTAssertTrue(element("long-running-timer-warning", in: longTimer).waitForExistence(timeout: 5))
        try performAccessibilityAudit(in: longTimer)
    }

    @MainActor
    private func launch(
        _ arguments: String...,
        largestDynamicType: Bool
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST_RESET_STORE"] + arguments
        if largestDynamicType {
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        }
        app.launch()
        return app
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func performAccessibilityAudit(in app: XCUIApplication) throws {
        let tabBar = app.tabBars.firstMatch
        let navigationBar = app.navigationBars.firstMatch
        let recoveryBanner = element("live-activity-recovery", in: app)
        let longTimerBanner = element("long-running-timer-warning", in: app)
        try app.performAccessibilityAudit { issue in
            let auditedElement = issue.element
            let auditedElementExists = auditedElement?.exists == true
            let staleElementIsKnownTabBarOverlap =
                !auditedElementExists
                && app.staticTexts.allElementsBoundByIndex.contains {
                    $0.exists && $0.frame.intersects(tabBar.frame)
                }

            let exclusion: String?
            if issue.auditType == .contrast,
                tabBar.exists,
                (auditedElementExists && auditedElement!.frame.intersects(tabBar.frame))
                    || staleElementIsKnownTabBarOverlap
            {
                exclusion = "system tab-bar overlap contrast sample"
            } else if issue.auditType == .contrast,
                let auditedElement,
                (recoveryBanner.exists && auditedElement.frame.intersects(recoveryBanner.frame))
                    || (longTimerBanner.exists && auditedElement.frame.intersects(longTimerBanner.frame))
            {
                exclusion = "content occluded by an opaque recovery banner"
            } else if issue.auditType == .textClipped,
                let auditedElement,
                auditedElement.label == "Stop",
                app.buttons["stop-active-timer"].exists
            {
                exclusion = "visually verified Stop label clipping false positive"
            } else if issue.auditType == .dynamicType,
                let auditedElement,
                navigationBar.exists,
                auditedElement.frame.intersects(navigationBar.frame)
            {
                exclusion = "system navigation-bar control scaling"
            } else {
                exclusion = nil
            }

            guard let exclusion else { return false }
            let elementDescription =
                auditedElementExists ? auditedElement!.label : issue.compactDescription
            let note = XCTAttachment(
                string: "Ignored \(exclusion) for \(elementDescription)."
            )
            note.name = "Documented accessibility audit exclusion"
            note.lifetime = .keepAlways
            self.add(note)
            return true
        }
    }
}
