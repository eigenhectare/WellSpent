import XCTest

@MainActor
final class WatchWidgetUITests: XCTestCase {
    func testRecentWidgetNamesArePrivateAndOptInIsRedacted() {
        let privateApp = launch(fixture: "populated", family: "rectangular")
        XCTAssertTrue(named("Recent project 1", in: privateApp).waitForExistence(timeout: 10))
        XCTAssertFalse(privateApp.debugDescription.contains("Client Launch"))
        capture(privateApp, name: "recent-private")
        privateApp.terminate()
        let optedIn = launch(fixture: "populated", family: "rectangular", extra: ["-ui-test-widget-names"])
        XCTAssertTrue(named("Client Launch", in: optedIn).waitForExistence(timeout: 10))
        capture(optedIn, name: "recent-opt-in")
        optedIn.terminate()
        let redacted = launch(
            fixture: "populated", family: "rectangular",
            extra: [
                "-ui-test-widget-names", "-ui-test-privacy-redacted",
            ])
        XCTAssertTrue(named("Recent project 1", in: redacted).waitForExistence(timeout: 10))
        XCTAssertFalse(redacted.debugDescription.contains("Client Launch"))
        capture(redacted, name: "recent-redacted")
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
        for family in ["circular", "corner", "inline", "rectangular"] {
            let app = launch(fixture: "active", family: family)
            XCTAssertTrue(app.descendants(matching: .any)["watch.widget-preview"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Client Launch"].exists)
            capture(app, name: "family-\(family)")
            app.terminate()
        }
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
