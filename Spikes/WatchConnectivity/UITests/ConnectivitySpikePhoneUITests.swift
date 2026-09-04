import XCTest

final class ConnectivitySpikePhoneUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testProbeLaunchesWithInstallationPreflight() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["WC Probe"].waitForExistence(timeout: 10))
        XCTAssertTrue(
            app.descendants(matching: .any)["paired-watch-status"].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["watch-install-status"].exists
        )
    }

    func testPhysicalCompanionRoundTrip() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("WatchConnectivity transport requires paired physical devices")
        #else
        let app = XCUIApplication()
        app.launch()

        waitForValue("Activated", elementID: "phone-session-status", in: app)
        waitForValue("Yes", elementID: "paired-watch-status", in: app)
        waitForValue("Installed", elementID: "watch-install-status", in: app)
        waitForValue("Yes", elementID: "phone-reachability-status", in: app)

        let advance = app.buttons["advance-snapshot-button"]
        XCTAssertTrue(advance.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 20) { advance.isEnabled })
        let receiptCount = app.descendants(matching: .any)[
            "phone-snapshot-receipt-count"
        ]
        XCTAssertTrue(receiptCount.waitForExistence(timeout: 10))
        let receiptsBeforePublish = Int(receiptCount.value as? String ?? "") ?? 0
        advance.tap()

        XCTAssertTrue(
            waitUntil(timeout: 45) {
                let current = Int(receiptCount.value as? String ?? "") ?? 0
                return current > receiptsBeforePublish
            },
            "The Watch did not install the snapshot and return its durable receipt"
        )
        XCTAssertFalse(app.staticTexts["snapshot_publish_failed_7006"].exists)
        #endif
    }

    func testPhysicalP1Receiver() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("WatchConnectivity transport requires paired physical devices")
        #else
        let app = XCUIApplication()
        app.launchEnvironment["WC_PROBE_RESET_ON_LAUNCH"] = "1"
        app.launch()

        waitForValue("Activated", elementID: "phone-session-status", in: app)
        waitForValue("Yes", elementID: "paired-watch-status", in: app)
        waitForValue("Installed", elementID: "watch-install-status", in: app)
        waitForValue("Yes", elementID: "phone-reachability-status", in: app, timeout: 90)

        waitForInteger(4, elementID: "phone-inbox-count", in: app, timeout: 120)
        waitForInteger(
            4,
            elementID: "phone-terminal-receipt-count",
            in: app,
            timeout: 120
        )
        waitForInteger(4, elementID: "phone-generation", in: app, timeout: 120)
        waitForAtLeastInteger(
            4,
            elementID: "phone-duplicate-delivery-count",
            in: app,
            timeout: 120
        )
        waitForValue("No", elementID: "phone-mutation-blocked", in: app)
        #endif
    }

    private func waitForValue(
        _ value: String,
        elementID: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 30
    ) {
        let element = app.descendants(matching: .any)[elementID]
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Missing \(elementID)")
        XCTAssertTrue(
            waitUntil(timeout: timeout) { element.value as? String == value },
            "Expected \(elementID) to become \(value); got \(String(describing: element.value))"
        )
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

    private func waitForInteger(
        _ expected: Int,
        elementID: String,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) {
        waitForAtLeastInteger(expected, elementID: elementID, in: app, timeout: timeout)
        let element = app.descendants(matching: .any)[elementID]
        XCTAssertEqual(
            Int(element.value as? String ?? ""),
            expected,
            "Expected exactly \(expected) for \(elementID)"
        )
    }

    private func waitForAtLeastInteger(
        _ expected: Int,
        elementID: String,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) {
        let element = app.descendants(matching: .any)[elementID]
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Missing \(elementID)")
        XCTAssertTrue(
            waitUntil(timeout: timeout) {
                (Int(element.value as? String ?? "") ?? -1) >= expected
            },
            "Expected \(elementID) to reach \(expected); got \(String(describing: element.value))"
        )
    }
}
