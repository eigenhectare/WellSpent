import XCTest

@MainActor
final class WatchRestartRecoveryUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testCommittedWatchCommandSurvivesProcessTerminationBeforeTransport() {
        verifyRecovery(from: "committed", attempts: 0)
    }

    func testWatchOutboxSurvivesTerminationAfterDeliveryAttemptWithoutAcknowledgement() {
        verifyRecovery(from: "delivery", attempts: 1)
    }

    private func verifyRecovery(from phase: String, attempts: Int) {
        let id = UUID().uuidString
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["-ui-test-restart-id", id, "-ui-test-restart-phase", phase]
        app.launch()
        let report = "runs=1 segments=1 outbox=1 sequence=2 revision=1 attempts=\(attempts)"
        XCTAssertTrue(app.staticTexts["fault.report"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["fault.report"].label, report)
        let original = app.staticTexts["fault.identity"].value as? String
        XCTAssertNotNil(original)
        XCTAssertNotEqual(original, "missing")
        for _ in 0..<2 {
            app.terminate()
            XCTAssertEqual(app.state, .notRunning)
            app.launchArguments = ["-ui-test-restart-id", id, "-ui-test-restart-phase", "recover"]
            app.launch()
            XCTAssertTrue(app.staticTexts["fault.report"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["fault.phase"].label, "recover")
            XCTAssertEqual(app.staticTexts["fault.report"].label, report)
            XCTAssertEqual(app.staticTexts["fault.identity"].value as? String, original)
        }
    }
}
