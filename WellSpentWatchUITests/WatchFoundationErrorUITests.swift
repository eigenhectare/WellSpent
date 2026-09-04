import XCTest

@MainActor
final class WatchFoundationErrorUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testStoreUnavailableAtOrdinaryText() throws { try unavailable(largest: false, expanded: false) }
    func testStoreUnavailableAtLargestText() throws { try unavailable(largest: true, expanded: false) }
    func testStoreUnavailableAtLargestExpandedText() throws { try unavailable(largest: true, expanded: true) }

    private func unavailable(largest: Bool, expanded: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-watch-fixture", "store-unavailable"]
        if largest { app.launchArguments.append("-ui-test-largest-text") }
        if expanded { app.launchArguments += ["-NSDoubleLocalizedStrings", "YES"] }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["watch.foundation.screen"].waitForExistence(timeout: 5))
        capture(app, "initial")
        try app.performAccessibilityAudit()
        for phrase in ["Open WellSpent on your iPhone, then try again.", "Local cache unavailable"] {
            let text = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", phrase)).firstMatch
            XCTAssertTrue(WatchUITestScrolling.reveal(text, in: app))
            if expanded { XCTAssertEqual(text.label.components(separatedBy: phrase).count - 1, 2) }
            XCTAssertTrue(WatchUITestScrolling.revealTextEdge(text, in: app, ending: false))
            capture(app, "\(phrase)-beginning")
            try app.performAccessibilityAudit()
            XCTAssertTrue(WatchUITestScrolling.revealTextEdge(text, in: app, ending: true))
            capture(app, "\(phrase)-ending")
            try app.performAccessibilityAudit()
        }
        XCTAssertFalse(app.descendants(matching: .any)["watch.timer.running"].exists)
        XCTAssertFalse(app.buttons["watch.controls.end"].exists)
        XCTAssertFalse(app.buttons["watch.project.open.20000000-0000-0000-0000-000000000001"].exists)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        for attachment in [XCTAttachment(screenshot: app.screenshot()), XCTAttachment(string: app.debugDescription)] {
            attachment.name = "WAT-23-foundation-error-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
