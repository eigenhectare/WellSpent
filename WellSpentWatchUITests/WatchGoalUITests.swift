import XCTest

@MainActor
final class WatchGoalUITests: XCTestCase {
    private let projectID = "20000000-0000-0000-0000-000000000001"

    func testAlertsDefaultOffAndDenialStillAllowsImmediateGoalStart() {
        let app = launch(extra: ["-ui-test-alerts-denied"])
        openSetup(app)
        let toggle = app.switches["watch.goal.alerts-toggle"]
        reveal(toggle, app: app)
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap()
        let status = app.staticTexts["watch.goal.alerts-status"]
        reveal(status, app: app)
        XCTAssertTrue(status.label.contains("Time goals still work"))
        capture(app, name: "permission-denied")
        let goal = app.buttons["watch.goal.15"]
        reveal(goal, app: app, upwards: false)
        goal.tap()
        XCTAssertTrue(app.descendants(matching: .any)["watch.timer.running"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["watch.metrics.goal"].exists)
    }

    func testCustomGoalCanBeEditedRemovedAndReusedFromRecents() {
        let app = launch()
        openSetup(app)
        let custom = app.buttons["watch.goal.custom"]
        reveal(custom, app: app)
        custom.tap()
        let use = app.buttons["watch.goal.custom-confirm"]
        XCTAssertTrue(use.waitForExistence(timeout: 5))
        capture(app, name: "custom-goal")
        use.tap()
        let edit = app.buttons["watch.metrics.goal"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let recent = app.buttons["watch.goal.45"]
        reveal(recent, app: app)
        XCTAssertTrue(recent.exists)
        recent.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let remove = app.buttons["watch.goal.open"]
        reveal(remove, app: app, upwards: false)
        remove.tap()
        XCTAssertTrue(app.buttons["watch.metrics.no-goal"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["watch.metrics.no-goal"].label, "No time goal")
        app.buttons["watch.metrics.no-goal"].tap()
        let preset = app.buttons["watch.goal.30"]
        reveal(preset, app: app)
        preset.tap()
        XCTAssertTrue(app.descendants(matching: .any)["watch.metrics.goal"].waitForExistence(timeout: 5))
        capture(app, name: "goal-edited")
    }

    func testOptionalAlertEnableAndDisableNeverStartsATimer() {
        let app = launch()
        openSetup(app)
        let toggle = app.switches["watch.goal.alerts-toggle"]
        reveal(toggle, app: app)
        toggle.tap()
        let status = app.staticTexts["watch.goal.alerts-status"]
        reveal(status, app: app)
        XCTAssertTrue(status.label.contains("counted time"))
        capture(app, name: "alerts-enabled")
        reveal(toggle, app: app, upwards: false)
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertFalse(app.descendants(matching: .any)["watch.timer.running"].exists)
    }

    private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-watch-fixture", "populated"] + extra
        app.launch()
        return app
    }

    private func openSetup(_ app: XCUIApplication) {
        let options = app.buttons["watch.project.options.\(projectID)"]
        XCTAssertTrue(options.waitForExistence(timeout: 10))
        options.tap()
        XCTAssertTrue(app.buttons["watch.goal.open"].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication, upwards: Bool = true) {
        XCTAssertTrue(WatchUITestScrolling.reveal(element, in: app, upwards: upwards))
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "WAT-20-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
