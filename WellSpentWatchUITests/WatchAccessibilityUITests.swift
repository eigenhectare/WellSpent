import XCTest

@MainActor
final class WatchAccessibilityUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPickerAtLargestText() throws { try audit("populated") }
    func testLongProjectNamesAtLargestText() throws { try audit("long-names") }
    func testActiveMetricsAtLargestText() throws { try audit("active") }
    func testPausedMetricsAtLargestText() throws { try audit("paused") }
    func testControlsAtLargestText() throws { try audit("active", extra: ["-ui-test-control-surface"]) }
    func testSummaryAtLargestText() throws { try audit("ended") }
    func testOfflinePickerAtLargestText() throws { try audit("offline") }
    func testPendingPickerAtLargestText() throws { try audit("pending") }
    func testConflictAtLargestText() throws { try audit("conflict") }
    func testUpgradeAtLargestText() throws { try audit("unsupported") }
    func testSetupAtLargestText() throws { try audit("setup") }
    func testEmptyProjectsAtLargestText() throws { try audit("empty") }

    func testPrimaryAndErrorStatesAtStandardText() throws {
        for fixture in [
            "populated", "long-names", "active", "paused", "ended", "offline", "pending", "conflict",
            "unsupported", "setup", "empty",
        ] {
            let app = launch(fixture, largestText: false)
            try audit(app)
            capture(app, "\(fixture)-standard")
        }
    }

    func testGoalAndSyncMetricStatesAtLargestText() throws {
        for fixture in ["active-no-goal", "goal-reached", "overtime", "active-offline", "active-pending"] {
            try audit(fixture)
        }
    }

    func testRunDetailsRemainReachableAtLargestText() throws {
        let app = launch("active", extra: ["-ui-test-metric-page", "1"])
        let segments = app.descendants(matching: .any)["watch.metrics.run.segments"]
        reveal(segments, in: app)
        try audit(app)
        capture(app, "run-details-bottom-largest")
    }

    func testTotalsFreshnessRemainsReachableAtLargestText() throws {
        let app = launch("stale-totals", extra: ["-ui-test-metric-page", "2"])
        let freshness = app.descendants(matching: .any)["watch.metrics.totals.stale"]
        reveal(freshness, in: app)
        try audit(app)
        capture(app, "totals-freshness-largest")
    }

    func testCustomGoalRemainsReachableAtLargestText() throws {
        let app = launch("populated")
        let options = app.buttons["watch.project.options.20000000-0000-0000-0000-000000000001"]
        reveal(options, in: app)
        options.tap()
        XCTAssertTrue(app.buttons["watch.goal.open"].waitForExistence(timeout: 5))
        try audit(app)
        capture(app, "goal-options-largest")
        let custom = app.buttons["watch.goal.custom"]
        reveal(custom, in: app)
        custom.tap()
        let confirm = app.buttons["watch.goal.custom-confirm"]
        reveal(confirm, in: app)
        assertPrimaryTarget(confirm)
        try audit(app)
        capture(app, "custom-goal-largest")
        confirm.tap()
        XCTAssertTrue(app.descendants(matching: .any)["watch.timer.running"].waitForExistence(timeout: 5))
    }

    func testGoalSettingsRemainReachableAtLargestText() {
        let app = launch("active")
        let goal = app.buttons["watch.metrics.goal"]
        reveal(goal, in: app)
        assertPrimaryTarget(goal)
        goal.tap()
        XCTAssertTrue(app.buttons["watch.goal.open"].waitForExistence(timeout: 5))
    }

    func testTimerControlsRemainOperableAtLargestText() {
        let app = launch("active", extra: ["-ui-test-control-surface"])
        let pause = app.buttons["watch.controls.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        assertPrimaryTarget(pause)
        pause.tap()
        let resume = app.buttons["watch.controls.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        assertPrimaryTarget(resume)
        resume.tap()
        let end = app.buttons["watch.controls.end"]
        assertPrimaryTarget(end)
        let new = app.buttons["watch.controls.new"]
        assertPrimaryTarget(new)
        reveal(app.staticTexts["watch.controls.status"], in: app)
        capture(app, "controls-status-largest")
        app.swipeDown()
        reveal(end, in: app)
        end.tap()
        // watchOS exposes SwiftUI alert buttons by their system label, not the
        // identifier attached to the source Button.
        let confirm = app.buttons["End Run"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.descendants(matching: .any)["watch.end-summary.saved"].waitForExistence(timeout: 5))
    }

    func testSummaryDoneRemainsReachableAtLargestText() {
        let app = launch("ended-long-content")
        let done = app.buttons["watch.end-summary.done"]
        reveal(done, in: app)
        assertPrimaryTarget(done)
        done.tap()
        XCTAssertTrue(app.staticTexts["Projects"].waitForExistence(timeout: 5))
    }

    private func launch(_ fixture: String, extra: [String] = [], largestText: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["-ui-test-watch-fixture", fixture] + extra
        if largestText { app.launchArguments.append("-ui-test-largest-text") }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        return app
    }

    private func audit(_ fixture: String, extra: [String] = []) throws {
        let app = launch(fixture, extra: extra)
        capture(app, "\(fixture)-largest\(extra.isEmpty ? "" : "-controls")")
        try audit(app)
    }

    private func audit(_ app: XCUIApplication, nativeStartAlert: Bool = false) throws {
        // Preserve every report. Only exact, documented native ornaments are
        // handled; this never suppresses app-owned targets or alert actions.
        try app.performAccessibilityAudit { issue in
            let detail = XCTAttachment(
                string:
                    "\(issue.compactDescription)\n\(issue.detailedDescription)\n\(issue.element?.debugDescription ?? "No element")"
            )
            detail.name = "WAT-23-audit-element"
            detail.lifetime = .keepAlways
            self.add(detail)
            let paging = Self.isNativePagingIndicator(
                hitRegion: issue.auditType == .hitRegion, description: issue.detailedDescription,
                elementType: issue.element?.elementType, value: issue.element?.value as? String,
                frame: issue.element?.frame)
            return paging
                || Self.isNativeStartAlertHeading(
                    nativeDialog: nativeStartAlert && app.tables.firstMatch.exists
                        && app.buttons["Try Again"].exists && app.buttons["Cancel"].exists,
                    hitRegion: issue.auditType == .hitRegion, description: issue.detailedDescription,
                    elementType: issue.element?.elementType, label: issue.element?.label, frame: issue.element?.frame)
        }
    }

    private func capture(_ app: XCUIApplication, _ label: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "WAT-23-\(label)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testImmediateStartWithCombinedAccessibilityAdaptations() throws {
        let app = launch("populated", extra: combinedSettings)
        let start = app.buttons["watch.project.open.20000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        reveal(start, in: app)
        assertPrimaryTarget(start)
        try audit(app)
        capture(app, "picker-combined-settings")
        start.tap()
        XCTAssertTrue(app.descendants(matching: .any)["watch.timer.running"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["watch.metrics.elapsed"].label, "Running")
        try audit(app)
        capture(app, "started-combined-settings")
    }

    func testSwitchRemainsOperableWithCombinedAccessibilityAdaptations() throws {
        let app = launch("active", extra: combinedSettings + ["-ui-test-control-surface"])
        let new = app.buttons["watch.controls.new"]
        reveal(new, in: app)
        assertPrimaryTarget(new)
        new.tap()
        let destination = app.buttons["watch.switch.project.20000000-0000-0000-0000-000000000002"]
        reveal(destination, in: app)
        assertPrimaryTarget(destination)
        try audit(app)
        capture(app, "switch-combined-settings")
        destination.tap()
        app.swipeLeft()
        let identity = app.descendants(matching: .any)["watch.metrics.project"]
        XCTAssertTrue(identity.waitForExistence(timeout: 5))
        XCTAssertEqual(identity.label, "Project, Admin & Operations")
    }

    func testStartFailureIsReadableAndRecoverableWithCombinedAccessibilityAdaptations() throws {
        let app = launch("populated", extra: combinedSettings + ["-ui-test-start-failure"])
        app.buttons["watch.project.open.20000000-0000-0000-0000-000000000001"].tap()
        let retry = app.buttons["Try Again"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        reveal(retry, in: app)
        // The native alert's element frame is its text, not an app-owned
        // button target. Let the platform audit inspect its actual hit region.
        XCTAssertTrue(retry.isHittable)
        try audit(app, nativeStartAlert: true)
        capture(app, "start-failure-combined-settings")
        let cancel = app.buttons["Cancel"]
        reveal(cancel, in: app)
        cancel.tap()
        XCTAssertTrue(app.staticTexts["Projects"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["watch.timer.running"].exists)
    }

    private var combinedSettings: [String] {
        ["-ui-test-bold-text", "-ui-test-increased-contrast", "-ui-test-reduced-motion", "-ui-test-without-color"]
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<18 {
            if element.exists && element.isHittable && app.frame.insetBy(dx: 0, dy: 8).contains(element.frame) {
                return
            }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
            let finish = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            start.press(
                forDuration: 0.05, thenDragTo: finish,
                withVelocity: XCUIGestureVelocity(rawValue: 80), thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(element.exists && element.isHittable)
        XCTAssertTrue(app.frame.insetBy(dx: 0, dy: 8).contains(element.frame))
    }

    private func assertPrimaryTarget(_ element: XCUIElement) {
        XCTAssertTrue(element.isHittable)
        XCTAssertGreaterThanOrEqual(element.frame.width, 44)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44)
    }

    func testNativePagingExceptionDoesNotHideAppControlFailures() {
        let description = "The size of this PUICMaterialPageIndicatorView is too small for user to interact."
        let frame = CGRect(x: 154, y: 33.5, width: 6, height: 32)
        XCTAssertTrue(
            Self.isNativePagingIndicator(
                hitRegion: true, description: description,
                elementType: .other, value: "page 1 of 3", frame: frame))
        for height in [46.0, 48.0] {
            XCTAssertTrue(
                Self.isNativePagingIndicator(
                    hitRegion: true, description: description,
                    elementType: .other, value: "page 3 of 3", frame: CGRect(x: 200, y: 45, width: 6, height: height)))
        }
        XCTAssertFalse(
            Self.isNativePagingIndicator(
                hitRegion: false, description: description,
                elementType: .other, value: "page 1 of 3", frame: frame))
        XCTAssertFalse(
            Self.isNativePagingIndicator(
                hitRegion: true, description: description,
                elementType: .button, value: "page 1 of 3", frame: frame))
        XCTAssertFalse(
            Self.isNativePagingIndicator(
                hitRegion: true, description: "SwiftUI.AccessibilityNode",
                elementType: .other, value: "page 1 of 3", frame: frame))
        XCTAssertFalse(
            Self.isNativePagingIndicator(
                hitRegion: true, description: description,
                elementType: .other, value: "Time Goal", frame: frame))
        XCTAssertFalse(
            Self.isNativePagingIndicator(
                hitRegion: true, description: description,
                elementType: .other, value: "page 1 of 3", frame: CGRect(x: 0, y: 0, width: 20, height: 20)))
    }

    static func isNativePagingIndicator(
        hitRegion: Bool, description: String, elementType: XCUIElement.ElementType?, value: String?, frame: CGRect?,
        expandedEnglish: Bool = false
    ) -> Bool {
        let normalValues = ["page 1 of 3", "page 2 of 3", "page 3 of 3"]
        // NSDoubleLocalizedStrings also expands system resources. The raw
        // native value was captured in WAT23-Small-Expanded2; its placeholder
        // fragment belongs to watchOS, not an app-owned accessibility element.
        let expandedValues = normalValues.map { "page @ of @ \($0)" }
        guard hitRegion, elementType == .other,
            description == "The size of this PUICMaterialPageIndicatorView is too small for user to interact.",
            (normalValues + (expandedEnglish ? expandedValues : [])).contains(value ?? ""), let frame
        else { return false }
        return frame.width == 6 && [32.0, 46.0, 48.0].contains(frame.height)
    }

    func testExpandedNativePagingExceptionRequiresItsExplicitContext() {
        let description = "The size of this PUICMaterialPageIndicatorView is too small for user to interact."
        let frame = CGRect(x: 154, y: 33.5, width: 6, height: 32)
        for value in ["page @ of @ page 1 of 3", "page @ of @ page 2 of 3", "page @ of @ page 3 of 3"] {
            XCTAssertTrue(
                Self.isNativePagingIndicator(
                    hitRegion: true, description: description, elementType: .other, value: value, frame: frame,
                    expandedEnglish: true))
            XCTAssertFalse(
                Self.isNativePagingIndicator(
                    hitRegion: true, description: description, elementType: .other, value: value, frame: frame))
            XCTAssertFalse(
                Self.isNativePagingIndicator(
                    hitRegion: true, description: description, elementType: .button, value: value, frame: frame,
                    expandedEnglish: true))
        }
        XCTAssertFalse(
            Self.isNativePagingIndicator(
                hitRegion: false, description: description, elementType: .other,
                value: "page @ of @ page 1 of 3", frame: frame, expandedEnglish: true))
    }

    func testNativeAlertHeadingExceptionDoesNotHideButtonsOrUnrelatedText() {
        let description = "The size of this UIAccessibilityElementMockView is too small for user to interact."
        let frame = CGRect(x: 16, y: 40, width: 130, height: 19.5)
        XCTAssertTrue(
            Self.isNativeStartAlertHeading(
                nativeDialog: true, hitRegion: true, description: description,
                elementType: .staticText, label: "Couldn’t start", frame: frame))
        for (native, hitRegion, type, label, candidateFrame) in [
            (false, true, XCUIElement.ElementType.staticText, "Couldn’t start", frame),
            (true, false, .staticText, "Couldn’t start", frame),
            (true, true, .button, "Couldn’t start", frame),
            (true, true, .staticText, "Try Again", frame),
            (true, true, .staticText, "Couldn’t start", CGRect(x: 0, y: 0, width: 130, height: 19.5)),
        ] {
            XCTAssertFalse(
                Self.isNativeStartAlertHeading(
                    nativeDialog: native, hitRegion: hitRegion, description: description,
                    elementType: type, label: label, frame: candidateFrame))
        }
    }

    private static func isNativeStartAlertHeading(
        nativeDialog: Bool, hitRegion: Bool, description: String,
        elementType: XCUIElement.ElementType?, label: String?, frame: CGRect?
    ) -> Bool {
        nativeDialog && hitRegion && elementType == .staticText && label == "Couldn’t start"
            && description == "The size of this UIAccessibilityElementMockView is too small for user to interact."
            && frame == CGRect(x: 16, y: 40, width: 130, height: 19.5)
    }
}
