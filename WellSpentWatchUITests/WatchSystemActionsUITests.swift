import XCTest

@MainActor
final class WatchSystemActionsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testCompleteGuideAtOrdinaryText() throws { try completeGuide(largest: false, expanded: false) }
    func testCompleteGuideAtLargestText() throws { try completeGuide(largest: true, expanded: false) }
    func testCompleteGuideAtLargestExpandedText() throws { try completeGuide(largest: true, expanded: true) }

    func testSetupGuideIsReachableAndDoesNotStartATimer() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-watch-fixture", "populated"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        let help = app.buttons["watch.system-actions.help"]
        // Native List rows are lazy: absence before scrolling is not absence
        // from the picker. Reveal the actual row before asserting/tapping it.
        XCTAssertTrue(WatchUITestScrolling.reveal(help, in: app))
        help.tap()
        XCTAssertTrue(app.staticTexts["watch.system-actions.title"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "WAT-19-system-action-guide"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Close"].firstMatch.tap()
        XCTAssertFalse(app.descendants(matching: .any)["watch.timer.running"].exists)
    }

    private func completeGuide(largest: Bool, expanded: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-watch-fixture", "populated"]
        if largest { app.launchArguments.append("-ui-test-largest-text") }
        if expanded { app.launchArguments += ["-NSDoubleLocalizedStrings", "YES"] }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        let help = app.buttons["watch.system-actions.help"]
        XCTAssertTrue(WatchUITestScrolling.reveal(help, in: app))
        XCTAssertGreaterThanOrEqual(help.frame.width, 44)
        XCTAssertGreaterThanOrEqual(help.frame.height, 44)
        help.tap()
        let title = app.staticTexts["watch.system-actions.title"]
        XCTAssertTrue(WatchUITestScrolling.reveal(title, in: app))
        capture(app, "title")
        try app.performAccessibilityAudit()
        let paragraphs = [
            "Add WellSpent Timer from the system Control Center gallery. Choose a favorite project in its configuration, or use your most recent project.",
            "The control starts a project, pauses a running timer, or resumes a paused timer. It opens WellSpent to save the change, including when your iPhone is offline.",
            "Try “Pause my timer in WellSpent” or “Resume my timer in WellSpent.” Start, Switch Project, and End are also available in Shortcuts.",
            "System project choices follow the project-name privacy setting on iPhone. Siri availability and permission are managed in system settings; the app works without Siri.",
            "On supported Apple Watch Ultra models, assign the WellSpent control using the system Action button settings. WellSpent does not take over the button or use workout shortcuts.",
        ]
        for (index, paragraph) in paragraphs.enumerated() {
            let text = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", paragraph)).firstMatch
            XCTAssertTrue(WatchUITestScrolling.reveal(text, in: app), "Paragraph \(index + 1) is unreachable.")
            if expanded {
                XCTAssertGreaterThan(text.label.count, paragraph.count, "The app's actual localized text must expand.")
            }
            XCTAssertTrue(WatchUITestScrolling.revealTextEdge(text, in: app, ending: false))
            capture(app, "paragraph-\(index + 1)-beginning")
            try app.performAccessibilityAudit()
            XCTAssertTrue(WatchUITestScrolling.revealTextEdge(text, in: app, ending: true))
            capture(app, "paragraph-\(index + 1)-ending")
            try app.performAccessibilityAudit()
        }
        let done = app.buttons["watch.system-actions.done"]
        XCTAssertTrue(WatchUITestScrolling.reveal(done, in: app))
        XCTAssertGreaterThanOrEqual(done.frame.width, 44)
        XCTAssertGreaterThanOrEqual(done.frame.height, 44)
        capture(app, "done")
        try app.performAccessibilityAudit()
        done.tap()
        XCTAssertTrue(WatchUITestScrolling.reveal(help, in: app))
        XCTAssertFalse(app.descendants(matching: .any)["watch.timer.running"].exists)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        for attachment in [XCTAttachment(screenshot: app.screenshot()), XCTAttachment(string: app.debugDescription)] {
            attachment.name = "WAT-23-system-help-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
