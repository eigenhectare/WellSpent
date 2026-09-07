import XCTest

@MainActor
final class WatchWidgetUITests: XCTestCase {
    func testIdleUsesCenteredHourglassAndRunningShowsElapsedTime() {
        var app = launch(fixture: "populated", family: "rectangular")
        var mark = app.descendants(matching: .any)["watch.widget-preview"]
        XCTAssertTrue(mark.waitForExistence(timeout: 10))
        XCTAssertEqual(mark.label, "WellSpent")
        XCTAssertEqual(mark.value as? String, "No timer running")
        XCTAssertFalse(app.debugDescription.contains("Start timer"))
        XCTAssertFalse(app.debugDescription.contains("Client Launch"))
        capture(app, name: "idle-hourglass")
        app.terminate()

        app = launch(fixture: "active", family: "rectangular")
        mark = app.descendants(matching: .any)["watch.widget-preview"]
        XCTAssertTrue(mark.waitForExistence(timeout: 10))
        XCTAssertEqual(mark.value as? String, "Timer running")
        XCTAssertFalse(app.debugDescription.contains("Tracking time"))
        XCTAssertFalse(app.debugDescription.contains("Client Launch"))
        capture(app, name: "running-hourglass-with-elapsed-time")
    }

    func testOnlyRunningStateShowsElapsedTime() {
        for (fixture, expectedValue) in [
            ("active-pending", "Timer running"),
            ("paused", "No timer running"),
            ("conflict", "No timer running"),
        ] {
            let app = launch(fixture: fixture, family: "rectangular")
            let mark = app.descendants(matching: .any)["watch.widget-preview"]
            XCTAssertTrue(mark.waitForExistence(timeout: 10))
            XCTAssertEqual(mark.value as? String, expectedValue)
            XCTAssertFalse(app.debugDescription.contains("Client Launch"))
            capture(app, name: fixture)
            app.terminate()
        }
    }

    func testRunningTimerAtOneHourOrMoreUsesHourMinuteDisplay() {
        let app = launch(fixture: "large-duration", family: "rectangular")
        let mark = app.descendants(matching: .any)["watch.widget-preview"]
        XCTAssertTrue(mark.waitForExistence(timeout: 10))
        XCTAssertEqual(mark.value as? String, "Timer running")
        capture(app, name: "running-hour-minute-display")
    }

    func testRectangularRunningWidgetStopEndsCurrentTimer() {
        let app = launch(fixture: "active", family: "rectangular")
        let stop = app.buttons["watch.widget.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        stop.tap()
        let mark = app.descendants(matching: .any)["watch.widget-preview"]
        XCTAssertTrue(mark.waitForExistence(timeout: 5))
        XCTAssertEqual(mark.value as? String, "No timer running")
        XCTAssertFalse(stop.exists)
        capture(app, name: "native-widget-stop-ended")
    }

    func testAllAccessoryFamiliesRenderWithoutProjectNames() {
        for fixture in ["populated", "active", "paused"] {
            for family in ["circular", "corner", "inline", "rectangular"] {
                let app = launch(fixture: fixture, family: family)
                XCTAssertTrue(
                    app.descendants(matching: .any)["watch.widget-preview"]
                        .waitForExistence(timeout: 10)
                )
                XCTAssertFalse(app.staticTexts["Client Launch"].exists)
                capture(app, name: "\(fixture)-family-\(family)")
                app.terminate()
            }
        }
    }

    func testIdleComplicationOpensPickerBeforeProjectTapStartsTimer() {
        let app = launch(
            fixture: "populated", family: nil,
            extra: ["-ui-test-widget-url", "wellspent-watch://projects"])
        let project = app.buttons["watch.project.open.20000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["watch.goal.open"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["watch.timer.running"].exists)
        project.tap()
        XCTAssertTrue(app.descendants(matching: .any)["watch.timer.running"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["watch.metrics.project"].label, "Project, Client Launch")
        XCTAssertTrue(app.buttons["watch.metrics.no-goal"].exists)
        capture(app, name: "idle-tap-started-selected-project")
    }

    func testPausedComplicationReopensPausedTimerWithoutResuming() {
        let app = launch(
            fixture: "paused", family: nil,
            extra: ["-ui-test-widget-url", "wellspent-watch://projects"])
        XCTAssertTrue(app.staticTexts["watch.metrics.elapsed"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["watch.metrics.elapsed"].label, "Paused")
        XCTAssertFalse(app.buttons["watch.project.open.20000000-0000-0000-0000-000000000001"].exists)
        XCTAssertFalse(app.buttons["watch.goal.open"].exists)
        app.swipeRight()
        XCTAssertTrue(app.buttons["watch.controls.resume"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["watch.controls.pause"].exists)
        capture(app, name: "paused-tap-awaits-resume")
    }

    func testProjectLinkOpensSetupWithoutStartingAndStaleLinkKeepsCurrentRun() {
        let url = "wellspent-watch://project/20000000-0000-0000-0000-000000000001"
        let app = launch(fixture: "populated", family: nil, extra: ["-ui-test-widget-url", url])
        XCTAssertTrue(app.buttons["watch.goal.open"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["watch.timer.running"].exists)
        app.terminate()
        let active = launch(
            fixture: "active", family: nil,
            extra: [
                "-ui-test-widget-url", "wellspent-watch://run/30000000-0000-0000-0000-000000000099",
            ])
        XCTAssertTrue(active.descendants(matching: .any)["watch.timer.running"].waitForExistence(timeout: 10))
        XCTAssertFalse(active.buttons["watch.goal.open"].exists)
    }

    func testMirroredLiveActivityStopLinkEndsTheExactActiveRun() {
        let url =
            "wellspent-watch://live-activity/stop/30000000-0000-0000-0000-000000000001?revision=1"
        let app = launch(fixture: "active", family: nil, extra: ["-ui-test-widget-url", url])

        XCTAssertTrue(
            app.descendants(matching: .any)["watch.end-summary.screen"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertFalse(app.descendants(matching: .any)["watch.timer.running"].exists)
    }

    func testWarmComplicationReturnsToElapsedAndKeepsPausedTime() {
        let app = launch(fixture: "paused", family: nil, extra: ["-ui-test-widget-reentry"])
        let elapsed = app.staticTexts["watch.metrics.elapsed"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 10))
        let billable = app.staticTexts["watch.metrics.billable"].label
        app.swipeRight()
        XCTAssertTrue(app.buttons["watch.controls.resume"].waitForExistence(timeout: 5))
        app.buttons["watch.widget.reentry"].tap()
        XCTAssertTrue(elapsed.waitForExistence(timeout: 5))
        XCTAssertTrue(elapsed.isHittable)
        XCTAssertEqual(elapsed.label, "Paused")
        XCTAssertEqual(app.staticTexts["watch.metrics.billable"].label, billable)

        let runPage = app.descendants(matching: .any)["watch.metrics.run"]
        XCTAssertTrue(swipeUp(app, until: runPage))
        app.buttons["watch.widget.reentry"].tap()
        XCTAssertTrue(elapsed.waitForExistence(timeout: 5))
        XCTAssertTrue(elapsed.isHittable)
        XCTAssertFalse(app.buttons["watch.goal.open"].exists)
        XCTAssertEqual(elapsed.label, "Paused")
        XCTAssertEqual(app.staticTexts["watch.metrics.billable"].label, billable)
        capture(app, name: "warm-paused-complication")
    }

    private func launch(fixture: String, family: String?, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-watch-fixture", fixture] + extra
        if let family { app.launchArguments += ["-ui-test-widget-family", family] }
        app.launch()
        return app
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "WAT-18-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func swipeUp(_ app: XCUIApplication, until element: XCUIElement) -> Bool {
        if element.exists { return true }
        for _ in 0..<3 {
            app.swipeUp()
            if element.waitForExistence(timeout: 2) { return true }
        }
        return false
    }
}
