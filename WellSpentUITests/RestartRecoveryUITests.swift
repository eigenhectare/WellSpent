import XCTest

@MainActor
final class RestartRecoveryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testReceiptSurvivesProcessTerminationAndAppliesExactlyOnce() {
        verifyRecovery(from: "receipt", expectedBefore: "runs=0 segments=0 inbox=1 ack=0 status=received revision=0")
    }

    func testCommittedMutationSurvivesTerminationBeforeAcknowledgementDelivery() {
        verifyRecovery(from: "committed", expectedBefore: "runs=1 segments=1 inbox=1 ack=1 status=terminal revision=1")
    }

    private func verifyRecovery(from phase: String, expectedBefore: String) {
        let id = UUID().uuidString
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["-ui-test-restart-id", id, "-ui-test-restart-phase", phase]
        app.launch()
        waitForInitialCheckpoint(in: app)
        XCTAssertEqual(app.staticTexts["fault.report"].label, expectedBefore)
        let original = app.staticTexts["fault.identity"].value as? String
        let originalAck = app.staticTexts["fault.ack"].value as? String
        XCTAssertNotNil(original)
        XCTAssertNotEqual(original, "missing")
        app.terminate()
        XCTAssertEqual(app.state, .notRunning)
        app.launchArguments = ["-ui-test-restart-id", id, "-ui-test-restart-phase", "recover"]
        app.launch()
        assertRecovered(app, original: original)
        let recoveredAck = app.staticTexts["fault.ack"].value as? String
        XCTAssertNotNil(recoveredAck)
        XCTAssertNotEqual(recoveredAck, "none")
        if phase == "committed" { XCTAssertEqual(recoveredAck, originalAck) }
        app.terminate()
        XCTAssertEqual(app.state, .notRunning)
        app.launch()
        assertRecovered(app, original: original)
        XCTAssertEqual(app.staticTexts["fault.ack"].value as? String, recoveredAck)
    }

    private func assertRecovered(_ app: XCUIApplication, original: String?) {
        XCTAssertTrue(app.staticTexts["fault.report"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["fault.phase"].label, "recover")
        XCTAssertEqual(
            app.staticTexts["fault.report"].label,
            "runs=1 segments=1 inbox=1 ack=1 status=terminal revision=1")
        XCTAssertEqual(app.staticTexts["fault.identity"].value as? String, original)
    }

    /// A newly constructed `XCUIApplication` can report PID 0 even while an
    /// app left by an earlier test session is still running. In that state,
    /// `terminate()` is a no-op and `launch()` only activates the stale process,
    /// dropping this test's launch arguments. Retry only after positively
    /// identifying the ordinary app surface; an absent or slow checkpoint is
    /// otherwise a real failure and must not be converted into a new seed.
    private func waitForInitialCheckpoint(in app: XCUIApplication) {
        let report = app.staticTexts["fault.report"]
        if !report.waitForExistence(timeout: 10), ordinaryAppIsForeground(in: app) {
            app.terminate()
            XCTAssertEqual(app.state, .notRunning)
            app.launch()
        }
        XCTAssertTrue(report.waitForExistence(timeout: 10))
    }

    private func ordinaryAppIsForeground(in app: XCUIApplication) -> Bool {
        app.navigationBars["Track"].exists
            || app.otherElements["onboarding-screen"].exists
            || app.otherElements["active-timer-card"].exists
    }
}
