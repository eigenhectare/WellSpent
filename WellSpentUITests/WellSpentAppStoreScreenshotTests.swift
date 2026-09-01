import XCTest

final class WellSpentAppStoreScreenshotTests: XCTestCase {
    private let completedSessionID = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCapture01ProjectTimers() {
        let app = launch("UITEST_SEED_APP_STORE")
        XCTAssertTrue(app.staticTexts["💼 Client Strategy"].waitForExistence(timeout: 5))
        capture("01-project-timers", in: app)
    }

    @MainActor
    func testCapture02ActiveTimer() {
        let app = launch("UITEST_SEED_APP_STORE_ACTIVE")
        XCTAssertTrue(element("active-timer-card", in: app).waitForExistence(timeout: 5))
        app.swipeDown()
        capture("02-active-timer", in: app)
    }

    @MainActor
    func testCapture03CompletionDetails() {
        let app = launch("UITEST_SEED_APP_STORE")
        let url = URL(string: "wellspent://completion/\(completedSessionID)")!
        app.open(url)
        XCTAssertTrue(element("session-completion-screen", in: app).waitForExistence(timeout: 5))
        capture("03-completion-details", in: app)
    }

    @MainActor
    func testCapture04DayReport() {
        let app = launch("UITEST_SEED_APP_STORE")
        app.tabBars.buttons["Reports"].tap()
        XCTAssertTrue(element("day-report", in: app).waitForExistence(timeout: 5))
        capture("04-day-report", in: app)
    }

    @MainActor
    func testCapture05ExactDrillDown() {
        let app = launch("UITEST_SEED_APP_STORE")
        app.tabBars.buttons["Reports"].tap()
        let total = app.buttons["day-report-total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        total.tap()
        XCTAssertTrue(element("report-drill-down", in: app).waitForExistence(timeout: 5))
        capture("05-exact-drill-down", in: app)
    }

    @MainActor
    func testCapture06PrivacyAndSupport() {
        let app = launch("UITEST_SEED_APP_STORE")
        app.tabBars.buttons["Settings"].tap()
        let privacyLink = element("privacy-policy-link", in: app)
        for _ in 0..<6 where !privacyLink.exists {
            app.swipeUp()
        }
        XCTAssertTrue(privacyLink.waitForExistence(timeout: 5))
        app.swipeUp()
        capture("06-privacy-and-support", in: app)
    }

    @MainActor
    private func launch(_ seed: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "UITEST_RESET_STORE",
            "UITEST_SKIP_ONBOARDING",
            seed,
            "-AppleLanguages",
            "(en)",
            "-AppleLocale",
            "en_US",
        ]
        app.launch()
        return app
    }

    @MainActor
    private func capture(_ name: String, in app: XCUIApplication) {
        XCTAssertEqual(app.state, .runningForeground)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
