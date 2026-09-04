import XCTest

/// Disconnected fixtures inject two pre-commit failures: first cancel, then
/// explicitly retry. Successful retries use the real timer/store boundary.
/// The boundary unit suite separately verifies actual save-failure rollback.
@MainActor
final class WatchControlErrorUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPauseFailureCancelAndRetryAtOrdinaryText() throws { try failure(.pause, largest: false) }
    func testPauseFailureCancelAndRetryAtLargestText() throws { try failure(.pause, largest: true) }
    func testResumeFailureCancelAndRetryAtOrdinaryText() throws { try failure(.resume, largest: false) }
    func testResumeFailureCancelAndRetryAtLargestText() throws { try failure(.resume, largest: true) }
    func testSwitchFailureCancelAndRetryAtOrdinaryText() throws { try failure(.switchRun, largest: false) }
    func testSwitchFailureCancelAndRetryAtLargestText() throws { try failure(.switchRun, largest: true) }
    func testEndFailureCancelAndRetryAtOrdinaryText() throws { try failure(.end, largest: false) }
    func testEndFailureCancelAndRetryAtLargestText() throws { try failure(.end, largest: true) }

    private enum Operation: String {
        case pause, resume, end
        case switchRun = "switch"

        var failureTitle: String { "Couldn’t \(rawValue)" }
        var failureMessage: String {
            self == .switchRun
                ? "The original run is unchanged. Try again or keep the current timer."
                : "The run is unchanged. Try again when you’re ready."
        }
    }

    private func failure(_ operation: Operation, largest: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-test-watch-fixture", operation == .resume ? "paused" : "active",
            "-ui-test-control-surface", "-ui-test-control-failure", operation.rawValue,
            "-ui-test-control-failure-count", "2",
        ]
        if largest { app.launchArguments.append("-ui-test-largest-text") }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        try invoke(operation, in: app)
        try inspectFailure(operation, in: app)
        let cancel = nativeRow("Cancel", in: app)
        tap(cancel, in: app)
        XCTAssertFalse(app.staticTexts[operation.failureTitle].exists)
        XCTAssertFalse(app.descendants(matching: .any)["watch.controls.busy"].exists)
        let originalAction = operation == .resume ? "resume" : "pause"
        XCTAssertTrue(app.buttons["watch.controls.\(originalAction)"].waitForExistence(timeout: 5))
        let status = app.staticTexts["watch.controls.status"]
        reveal(status, in: app)
        XCTAssertEqual(status.label, operation == .resume ? "Run paused" : "Run active")
        capture(app, "\(operation.rawValue)-cancelled")
        try audit(app)
        assertProject("Client Launch", in: app)
        app.swipeRight()

        try invoke(operation, in: app)
        XCTAssertTrue(app.staticTexts[operation.failureTitle].waitForExistence(timeout: 5))
        let retry = nativeRow("Try Again", in: app)
        reveal(retry, in: app)
        assertPrimaryTarget(retry)
        capture(app, "\(operation.rawValue)-retry")
        try audit(app, nativeDialogTitle: operation.failureTitle)
        tap(retry, in: app)
        XCTAssertFalse(app.staticTexts[operation.failureTitle].exists)
        switch operation {
        case .end:
            XCTAssertTrue(app.descendants(matching: .any)["watch.end-summary.saved"].waitForExistence(timeout: 5))
            let sync = app.descendants(matching: .any)["watch.end-summary.sync"]
            reveal(sync, in: app)
            XCTAssertEqual(sync.label, "Run saved locally and pending sync")
            XCTAssertFalse(app.descendants(matching: .any)["watch.timer.running"].exists)
        case .pause, .resume, .switchRun:
            let nextAction = operation == .pause ? "resume" : "pause"
            XCTAssertTrue(app.buttons["watch.controls.\(nextAction)"].waitForExistence(timeout: 5))
            assertProject(operation == .switchRun ? "Admin & Operations" : "Client Launch", in: app)
        }
        capture(app, "\(operation.rawValue)-recovered")
        try audit(app)
    }

    private func invoke(_ operation: Operation, in app: XCUIApplication) throws {
        switch operation {
        case .pause, .resume:
            tap(app.buttons["watch.controls.\(operation.rawValue)"], in: app)
        case .switchRun:
            tap(app.buttons["watch.controls.new"], in: app)
            let destination = app.buttons["watch.switch.project.20000000-0000-0000-0000-000000000002"]
            reveal(destination, in: app)
            assertPrimaryTarget(destination)
            capture(app, "switch-destination")
            try audit(app)
            tap(destination, in: app)
        case .end:
            tap(app.buttons["watch.controls.end"], in: app)
            let confirm = nativeRow("End Run", in: app)
            reveal(confirm, in: app)
            capture(app, "end-confirmation")
            try audit(app, nativeDialogTitle: "End this run?")
            tap(confirm, in: app)
        }
    }

    private func inspectFailure(_ operation: Operation, in app: XCUIApplication) throws {
        let title = app.staticTexts[operation.failureTitle]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        capture(app, "\(operation.rawValue)-error-title")
        try audit(app, nativeDialogTitle: operation.failureTitle)
        let message = app.staticTexts.matching(identifier: operation.failureMessage).firstMatch
        reveal(message, in: app)
        XCTAssertTrue(WatchUITestScrolling.revealTextEdge(message, in: app, ending: false))
        capture(app, "\(operation.rawValue)-error-message-beginning")
        try audit(app, nativeDialogTitle: operation.failureTitle)
        XCTAssertTrue(WatchUITestScrolling.revealTextEdge(message, in: app, ending: true))
        capture(app, "\(operation.rawValue)-error-message-ending")
        try audit(app, nativeDialogTitle: operation.failureTitle)
        for action in ["Try Again", "Cancel"] {
            let row = nativeRow(action, in: app)
            reveal(row, in: app)
            assertPrimaryTarget(row)
            capture(app, "\(operation.rawValue)-error-\(action)")
            try audit(app, nativeDialogTitle: operation.failureTitle)
        }
    }

    private func assertProject(_ name: String, in app: XCUIApplication) {
        app.swipeLeft()
        let project = app.descendants(matching: .any)["watch.metrics.project"]
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        reveal(project, in: app)
        XCTAssertEqual(project.label, "Project, \(name)")
        XCTAssertFalse(app.descendants(matching: .any)["watch.end-summary.saved"].exists)
    }

    private func nativeRow(_ title: String, in app: XCUIApplication) -> XCUIElement {
        // The text glyph can be narrower than 44 points. Its containing native
        // table row is the actual tappable alert action; measure that surface.
        let row = app.tables.cells.containing(.button, identifier: title).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        return row
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        reveal(element, in: app)
        assertPrimaryTarget(element)
        let visible = element.frame.intersection(WatchUITestScrolling.viewport(app))
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: visible.midX, dy: visible.midY)).tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        if WatchUITestScrolling.reveal(element, in: app) { return }
        capture(app, "unreachable-element")
        XCTFail("Unreachable element: \(element.debugDescription)")
    }

    private func assertPrimaryTarget(_ element: XCUIElement) {
        XCTAssertGreaterThanOrEqual(element.frame.width, 44)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44)
    }

    private func audit(_ app: XCUIApplication, nativeDialogTitle: String? = nil) throws {
        try app.performAccessibilityAudit { issue in
            let detail = XCTAttachment(string: "\(issue.detailedDescription)\n\(issue.element?.debugDescription ?? "")")
            detail.name = "WAT-23-control-error-audit"
            detail.lifetime = .keepAlways
            self.add(detail)
            let paging = WatchAccessibilityUITests.isNativePagingIndicator(
                hitRegion: issue.auditType == .hitRegion, description: issue.detailedDescription,
                elementType: issue.element?.elementType, value: issue.element?.value as? String,
                frame: issue.element?.frame)
            let nativeDialog =
                nativeDialogTitle != nil && app.tables.firstMatch.exists
                && app.buttons["Cancel"].exists
                && app.buttons[nativeDialogTitle == "End this run?" ? "End Run" : "Try Again"].exists
            return paging
                || Self.isNativeControlHeading(
                    nativeDialog: nativeDialog, expectedTitle: nativeDialogTitle,
                    hitRegion: issue.auditType == .hitRegion, description: issue.detailedDescription,
                    elementType: issue.element?.elementType, label: issue.element?.label, frame: issue.element?.frame)
        }
    }

    func testNativeControlHeadingExceptionDoesNotHideActionsOrUnrelatedText() {
        let description = "The size of this UIAccessibilityElementMockView is too small for user to interact."
        let frame = CGRect(x: 16, y: 40, width: 130, height: 19.5)
        for title in ["End this run?", "Couldn’t end", "Couldn’t pause", "Couldn’t resume", "Couldn’t switch"] {
            XCTAssertTrue(
                Self.isNativeControlHeading(
                    nativeDialog: true, expectedTitle: title, hitRegion: true, description: description,
                    elementType: .staticText, label: title, frame: frame))
            for (native, hitRegion, type, label, candidateFrame) in [
                (false, true, XCUIElement.ElementType.staticText, title, frame),
                (true, false, .staticText, title, frame),
                (true, true, .button, title, frame),
                (true, true, .staticText, "Try Again", frame),
                (true, true, .staticText, "Cancel", frame),
                (true, true, .staticText, "End Run", frame),
                (true, true, .staticText, "Unrelated text", frame),
                (true, true, .staticText, title, CGRect(x: 0, y: 0, width: 130, height: 19.5)),
                (true, true, .staticText, title, CGRect(x: 16, y: 40, width: 130, height: 44)),
            ] {
                XCTAssertFalse(
                    Self.isNativeControlHeading(
                        nativeDialog: native, expectedTitle: title, hitRegion: hitRegion, description: description,
                        elementType: type, label: label, frame: candidateFrame))
            }
        }
        for title in [nil, "Unrelated text", "Try Again"] as [String?] {
            XCTAssertFalse(
                Self.isNativeControlHeading(
                    nativeDialog: true, expectedTitle: title, hitRegion: true, description: description,
                    elementType: .staticText, label: title, frame: frame))
        }
        XCTAssertFalse(
            Self.isNativeControlHeading(
                nativeDialog: true, expectedTitle: "Couldn’t pause", hitRegion: true,
                description: "A different problem",
                elementType: .staticText, label: "Couldn’t pause", frame: frame))
    }

    private static func isNativeControlHeading(
        nativeDialog: Bool, expectedTitle: String?, hitRegion: Bool, description: String,
        elementType: XCUIElement.ElementType?, label: String?, frame: CGRect?
    ) -> Bool {
        nativeDialog && hitRegion && elementType == .staticText && label == expectedTitle
            && ["End this run?", "Couldn’t end", "Couldn’t pause", "Couldn’t resume", "Couldn’t switch"].contains(
                expectedTitle ?? "")
            && description == "The size of this UIAccessibilityElementMockView is too small for user to interact."
            && frame == CGRect(x: 16, y: 40, width: 130, height: 19.5)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        for attachment in [XCTAttachment(screenshot: app.screenshot()), XCTAttachment(string: app.debugDescription)] {
            attachment.name = "WAT-23-control-error-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
