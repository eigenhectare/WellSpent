import XCTest

@MainActor
final class WatchWidgetUITests: XCTestCase {
    func testIdleWidgetOpensProjectsAndActiveNamesRespectPrivacy() {
        let privateApp = launch(fixture: "populated", family: "rectangular")
        XCTAssertTrue(named("Start timer", in: privateApp).waitForExistence(timeout: 10))
        XCTAssertFalse(privateApp.debugDescription.contains("Client Launch"))
        capture(privateApp, name: "idle-project-picker")
        privateApp.terminate()
        let optedIn = launch(fixture: "active", family: "rectangular", extra: ["-ui-test-widget-names"])
        XCTAssertTrue(named("Client Launch", in: optedIn).waitForExistence(timeout: 10))
        capture(optedIn, name: "active-opt-in")
        optedIn.terminate()
        let redacted = launch(
            fixture: "active", family: "rectangular",
            extra: [
                "-ui-test-widget-names", "-ui-test-privacy-redacted",
            ])
        XCTAssertTrue(named("Billable time", in: redacted).waitForExistence(timeout: 10))
        XCTAssertFalse(redacted.debugDescription.contains("Client Launch"))
        capture(redacted, name: "active-redacted")
    }

    func testActivePausedAndBlockedWidgetRendering() {
        for (fixture, expected) in [
            ("active-pending", "Tracking time"), ("paused", "Paused"), ("conflict", "Review on iPhone"),
        ] {
            let app = launch(fixture: fixture, family: "rectangular")
            let alternatives = expected == "Tracking time" ? ["Tracking time", "Running"] : [expected]
            XCTAssertTrue(
                app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", alternatives))
                    .firstMatch.waitForExistence(timeout: 10))
            XCTAssertFalse(app.debugDescription.contains("Client Launch"))
            capture(app, name: fixture)
            app.terminate()
        }
    }

    func testAllAccessoryFamiliesRenderWithoutProjectNames() {
        for fixture in ["populated", "active", "paused"] {
            for family in ["circular", "corner", "inline", "rectangular"] {
                let app = launch(fixture: fixture, family: family)
                XCTAssertTrue(app.descendants(matching: .any)["watch.widget-preview"].waitForExistence(timeout: 10))
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

    private func launch(fixture: String, family: String?, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-watch-fixture", fixture] + extra
        if let family { app.launchArguments += ["-ui-test-widget-family", family] }
        app.launch()
        return app
    }

    private func named(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "WAT-18-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
