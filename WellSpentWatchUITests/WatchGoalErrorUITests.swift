import XCTest

/// Exercises production error presentation using disconnected, in-memory
/// fixtures. These cases never ask the system for notification permission.
@MainActor
final class WatchGoalErrorUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSettingsFailureAtOrdinaryText() throws { try settingsFailure(largest: false) }
    func testSettingsFailureAtLargestText() throws { try settingsFailure(largest: true) }
    func testPermissionFailureRetryAtOrdinaryText() throws { try permissionFailure(largest: false) }
    func testPermissionFailureRetryAtLargestText() throws { try permissionFailure(largest: true) }
    func testSchedulingFailureRetryAtOrdinaryText() throws { try schedulingFailure(largest: false) }
    func testSchedulingFailureRetryAtLargestText() throws { try schedulingFailure(largest: true) }
    func testGoalSaveFailurePreservesGoalAtOrdinaryText() throws { try goalSaveFailure(largest: false) }
    func testGoalSaveFailurePreservesGoalAtLargestText() throws { try goalSaveFailure(largest: true) }

    private func settingsFailure(largest: Bool) throws {
        let app = launch("populated", flag: "-ui-test-alerts-settings-failure", largest: largest)
        openSetup(app, active: false)
        try checkStatus("Couldn’t save alert settings", in: app, name: "settings-failure")
        let toggle = app.switches["watch.goal.alerts-toggle"]
        tap(toggle, in: app, upwards: false)
        XCTAssertEqual(toggle.value as? String, "0", "An unsaved opt-in must not appear enabled.")
        try checkStatus("Time tracking still works", in: app, name: "settings-unsaved")
        try startGoal(app)
    }

    private func permissionFailure(largest: Bool) throws {
        let app = launch("populated", flag: "-ui-test-alerts-permission-failure-once", largest: largest)
        openSetup(app, active: false)
        let toggle = app.switches["watch.goal.alerts-toggle"]
        tap(toggle, in: app)
        try checkStatus("Couldn’t request permission", in: app, name: "permission-failure")
        tap(toggle, in: app, upwards: false)
        XCTAssertEqual(toggle.value as? String, "0")
        tap(toggle, in: app)
        try checkStatus("Alerts follow counted time", in: app, name: "permission-recovered")
        XCTAssertFalse(app.descendants(matching: .any)["watch.timer.running"].exists)
        try startGoal(app)
    }

    private func schedulingFailure(largest: Bool) throws {
        let app = launch("active", flag: "-ui-test-alerts-scheduling-failure-once", largest: largest)
        openSetup(app, active: true)
        tap(app.switches["watch.goal.alerts-toggle"], in: app)
        try checkStatus("Couldn’t schedule this alert", in: app, name: "scheduling-failure")
        let retry = app.buttons["watch.goal.alerts-retry"]
        reveal(retry, in: app)
        assertPrimaryTarget(retry)
        capture(app, "scheduling-retry")
        try audit(app)
        tap(retry, in: app)
        try checkStatus("Alerts follow counted time", in: app, name: "scheduling-recovered", upwards: false)
        XCTAssertFalse(retry.exists)
        dismissSetup(app)
        XCTAssertTrue(app.descendants(matching: .any)["watch.timer.running"].waitForExistence(timeout: 5))
        try assertSavedGoal(30, in: app)
    }

    private func goalSaveFailure(largest: Bool) throws {
        let app = launch("active", flag: "-ui-test-goal-save-failure-once", largest: largest)
        openSetup(app, active: true)
        tap(app.buttons["watch.goal.15"], in: app)
        let title = app.staticTexts["Couldn’t save time goal"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        // The native alert exposes its prose both as a table child and under
        // the alert heading on some display classes.
        let message = app.staticTexts.matching(
            identifier: "The timer and its previous goal are unchanged. Open Time Goal to try again."
        ).firstMatch
        reveal(message, in: app)
        capture(app, "goal-save-failure-message")
        try audit(app)
        // watchOS reports the OK glyph as a 22-point-wide Button inside its
        // full-size, tappable table row. Exercise and measure that native row.
        let okay = app.tables.cells.containing(.button, identifier: "OK").firstMatch
        reveal(okay, in: app)
        assertPrimaryTarget(okay)
        capture(app, "goal-save-failure-dismiss")
        try audit(app)
        tap(okay, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["watch.timer.running"].waitForExistence(timeout: 5))
        try assertSavedGoal(30, in: app)
        openSetup(app, active: true)
        tap(app.buttons["watch.goal.15"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["watch.timer.running"].waitForExistence(timeout: 5))
        XCTAssertFalse(title.exists)
        try assertSavedGoal(15, in: app)
    }

    private func assertSavedGoal(_ minutes: Int, in app: XCUIApplication) throws {
        openSetup(app, active: true)
        tap(app.buttons["watch.goal.custom"], in: app)
        let picker = app.descendants(matching: .any)["watch.goal.custom-picker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, String(minutes))
        capture(app, "saved-goal-\(minutes)")
        try audit(app)
        dismissSetup(app)
    }

    private func dismissSetup(_ app: XCUIApplication) {
        // An active timer's sheet supplies watchOS's native Close control;
        // picker-presented goal setup supplies the app's Cancel control.
        let candidates = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "Close"]))
        guard let close = candidates.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
            capture(app, "missing-dismiss-control")
            XCTFail("Goal setup has no hittable Cancel or native Close control.")
            return
        }
        // Unlike content rows, the navigation control belongs in the top
        // chrome; do not apply the scrolling content's top inset to it.
        XCTAssertGreaterThanOrEqual(close.frame.width, 28)
        XCTAssertGreaterThanOrEqual(close.frame.height, 28)
        close.tap()
    }

    private func startGoal(_ app: XCUIApplication) throws {
        tap(app.buttons["watch.goal.15"], in: app, upwards: false)
        XCTAssertTrue(app.descendants(matching: .any)["watch.timer.running"].waitForExistence(timeout: 5))
        capture(app, "immediate-start-after-alert-error")
        try audit(app)
    }

    private func launch(_ fixture: String, flag: String, largest: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-watch-fixture", fixture, flag]
        if largest { app.launchArguments.append("-ui-test-largest-text") }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        return app
    }

    private func openSetup(_ app: XCUIApplication, active: Bool) {
        let button =
            active
            ? app.buttons["watch.metrics.goal"]
            : app.buttons["watch.project.options.20000000-0000-0000-0000-000000000001"]
        tap(button, in: app)
        XCTAssertTrue(app.buttons["watch.goal.open"].waitForExistence(timeout: 5))
    }

    private func checkStatus(
        _ text: String, in app: XCUIApplication, name: String, upwards: Bool = true
    ) throws {
        let status = app.staticTexts["watch.goal.alerts-status"]
        reveal(status, in: app, upwards: upwards)
        let matches = NSPredicate(format: "label CONTAINS %@", text)
        let outcome = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: matches, object: status)], timeout: 5)
        if outcome != .completed { capture(app, "unexpected-\(name)") }
        XCTAssertEqual(outcome, .completed, "Actual explanation: \(status.label)")
        if status.frame.height > WatchUITestScrolling.viewport(app).height - 24 {
            XCTAssertTrue(WatchUITestScrolling.revealTextEdge(status, in: app, ending: false))
            capture(app, "\(name)-beginning")
            try audit(app)
            XCTAssertTrue(WatchUITestScrolling.revealTextEdge(status, in: app, ending: true))
            capture(app, "\(name)-ending")
            try audit(app)
        }
        capture(app, name)
        try audit(app)
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool = true) {
        reveal(element, in: app, upwards: upwards)
        if element.elementType == .switch {
            // Let native automation use the switch's activation point rather
            // than the center of the combined label-and-switch rectangle.
            element.tap()
            return
        }
        let visible = element.frame.intersection(WatchUITestScrolling.viewport(app))
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: visible.midX, dy: visible.midY)).tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool = true) {
        if WatchUITestScrolling.reveal(element, in: app, upwards: upwards) { return }
        capture(app, "unreachable-element")
        XCTFail("Unreachable element: \(element.debugDescription)")
    }

    private func assertPrimaryTarget(_ element: XCUIElement) {
        XCTAssertGreaterThanOrEqual(element.frame.width, 44)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44)
    }

    private func audit(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit { issue in
            let detail = XCTAttachment(string: "\(issue.detailedDescription)\n\(issue.element?.debugDescription ?? "")")
            detail.name = "WAT-23-goal-error-audit"
            detail.lifetime = .keepAlways
            self.add(detail)
            return WatchAccessibilityUITests.isNativePagingIndicator(
                hitRegion: issue.auditType == .hitRegion, description: issue.detailedDescription,
                elementType: issue.element?.elementType, value: issue.element?.value as? String,
                frame: issue.element?.frame)
        }
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        for attachment in [XCTAttachment(screenshot: app.screenshot()), XCTAttachment(string: app.debugDescription)] {
            attachment.name = "WAT-23-goal-error-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
