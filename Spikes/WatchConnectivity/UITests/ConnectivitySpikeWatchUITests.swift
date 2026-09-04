import XCTest

final class ConnectivitySpikeWatchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testProbeLaunchesWithSessionPreflight() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["WC Probe"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.descendants(matching: .any)["session-status"].exists
        )
    }

    func testPhysicalP1StartPauseResumeEnd() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("WatchConnectivity transport requires paired physical devices")
        #else
        let app = XCUIApplication()
        app.launch()

        let session = app.descendants(matching: .any)
            .matching(identifier: "session-status")
            .firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 10))
        XCTAssertTrue(
            waitUntil(timeout: 90) {
                (session.value as? String)?.contains("Activated, Reachable") == true
            },
            "The Watch and phone probes did not become foreground reachable"
        )

        let reset = app.buttons.matching(identifier: "reset-watch-probe-button").firstMatch
        XCTAssertTrue(reset.waitForExistence(timeout: 10))
        tapWhenHittable(reset, in: app)

        let primary = app.buttons.matching(identifier: "watch-primary-action").firstMatch
        XCTAssertTrue(primary.waitForExistence(timeout: 10))
        waitForLabel("Queue Start", element: primary)
        waitForValue("0", elementID: "watch-outbox-count", in: app)
        waitForValue("0", elementID: "watch-ack-count", in: app)

        tapWhenHittable(primary, in: app)
        waitForLabel("Queue Pause", element: primary)
        tapWhenHittable(primary, in: app)
        waitForLabel("Queue Resume", element: primary)
        tapWhenHittable(primary, in: app)
        waitForLabel("Queue Pause", element: primary)

        let end = app.buttons.matching(identifier: "watch-end-action").firstMatch
        XCTAssertTrue(end.waitForExistence(timeout: 10))
        tapWhenHittable(end, in: app)
        waitForLabel("Queue Start", element: primary)

        waitForValue("0", elementID: "watch-outbox-count", in: app, timeout: 120)
        waitForValue("4", elementID: "watch-ack-count", in: app, timeout: 120)
        XCTAssertFalse(
            app.descendants(matching: .any)
                .matching(identifier: "watch-last-error")
                .firstMatch.exists
        )
        #endif
    }

    private func waitForLabel(
        _ expected: String,
        element: XCUIElement,
        timeout: TimeInterval = 30
    ) {
        XCTAssertTrue(
            waitUntil(timeout: timeout) { element.label == expected },
            "Expected label \(expected); got \(element.label)"
        )
    }

    private func waitForValue(
        _ expected: String,
        elementID: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 30
    ) {
        let element = app.descendants(matching: .any)
            .matching(identifier: elementID)
            .firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Missing \(elementID)")
        XCTAssertTrue(
            waitUntil(timeout: timeout) { element.value as? String == expected },
            "Expected \(elementID) to become \(expected); got \(String(describing: element.value))"
        )
    }

    private func tapWhenHittable(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "Element was not hittable: \(element)")
        element.tap()
    }

    private func waitUntil(
        timeout: TimeInterval,
        pollInterval: TimeInterval = 0.25,
        condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        }
        return condition()
    }
}
