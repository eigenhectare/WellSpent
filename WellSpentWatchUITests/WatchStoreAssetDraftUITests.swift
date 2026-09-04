import XCTest

/// Review-only screenshots from isolated DEBUG fixtures. Never present these
/// as signed release-candidate captures or as actual Watch Connectivity proof.
@MainActor
final class WatchStoreAssetDraftUITests: XCTestCase {
    func testCaptureFiveDraftStoreScreens() {
        let app = XCUIApplication()
        launch(app, fixture: "populated")
        let options = app.buttons["watch.project.options.20000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(options.waitForExistence(timeout: 10))
        capture(app, name: "01-projects")

        options.tap()
        XCTAssertTrue(app.buttons["watch.goal.open"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["watch.timer.running"].exists)
        capture(app, name: "02-goal-setup")

        launch(app, fixture: "active")
        XCTAssertTrue(app.descendants(matching: .any)["watch.timer.running"].waitForExistence(timeout: 10))
        capture(app, name: "03-active-metrics")
        app.swipeRight()
        XCTAssertTrue(app.buttons["watch.controls.pause"].waitForExistence(timeout: 5))
        capture(app, name: "04-controls")

        launch(app, fixture: "ended")
        XCTAssertTrue(app.descendants(matching: .any)["watch.end-summary.billable"].waitForExistence(timeout: 10))
        capture(app, name: "05-summary")
        app.terminate()
    }

    private func launch(_ app: XCUIApplication, fixture: String) {
        app.terminate()
        app.launchArguments = ["-ui-test-watch-fixture", fixture]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "DRAFT-WAT27-\(name)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "DRAFT-WAT27-\(name)-accessibility"
        tree.lifetime = .keepAlways
        add(tree)
    }
}
