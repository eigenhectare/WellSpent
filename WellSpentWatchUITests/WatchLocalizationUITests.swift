import XCTest

@MainActor
final class WatchLocalizationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testExpandedEnglishUsesTheRealLocalizationBoundary() {
        let app = launch("populated")
        let projects = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Projects")).firstMatch
        XCTAssertTrue(projects.waitForExistence(timeout: 5))
        capture(app, "expanded-picker")
        // Do not accept a launch flag as proof. Foundation must actually
        // expand a catalog string on the running Watch before testing layout.
        XCTAssertEqual(projects.label.components(separatedBy: "Projects").count - 1, 2)
        let start = app.buttons["watch.project.open.20000000-0000-0000-0000-000000000001"]
        reveal(start, in: app)
        start.tap()
        let status = app.staticTexts["watch.metrics.elapsed"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        capture(app, "expanded-started")
        XCTAssertEqual(status.label.components(separatedBy: "Running").count - 1, 2)
    }

    func testExpandedPrimaryStatesAtOrdinaryAndLargestText() throws {
        for largest in [false, true] {
            for fixture in ["populated", "active", "paused", "ended", "offline", "pending", "conflict", "unsupported"] {
                let app = launch(fixture, extra: largest ? ["-ui-test-largest-text"] : [])
                capture(app, "expanded-\(fixture)-\(largest ? "largest" : "ordinary")")
                try audit(app)
                app.terminate()
            }
        }
    }

    func testExpandedGoalSetupAtLargestTextStartsImmediately() throws {
        let app = launch("populated", extra: ["-ui-test-largest-text"])
        tap(app.buttons["watch.project.options.20000000-0000-0000-0000-000000000001"], in: app)
        capture(app, "expanded-goal-options-largest")
        try audit(app)
        tap(app.buttons["watch.goal.custom"], in: app)
        capture(app, "expanded-custom-goal-top-largest")
        let confirm = app.buttons["watch.goal.custom-confirm"]
        reveal(confirm, in: app)
        capture(app, "expanded-custom-goal-confirm-largest")
        try audit(app)
        tap(confirm, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["watch.timer.running"].waitForExistence(timeout: 5))
    }

    func testExpandedControlsAndSwitchAtLargestText() throws {
        let app = launch("active", extra: ["-ui-test-largest-text", "-ui-test-control-surface"])
        capture(app, "expanded-controls-largest")
        try audit(app)
        tap(app.buttons["watch.controls.pause"], in: app)
        tap(app.buttons["watch.controls.resume"], in: app)
        tap(app.buttons["watch.controls.new"], in: app)
        capture(app, "expanded-switch-top-largest")
        let destination = app.buttons["watch.switch.project.20000000-0000-0000-0000-000000000002"]
        reveal(destination, in: app)
        capture(app, "expanded-switch-destination-largest")
        try audit(app)
        tap(destination, in: app)
        app.swipeLeft()
        let project = app.descendants(matching: .any)["watch.metrics.project"]
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        XCTAssertTrue(project.label.contains("Admin & Operations"))
    }

    func testCustomGoalWheelSelectionIsReachableAndPersistedWithExpandedText() throws {
        for largest in [false, true] {
            let app = launch("populated", extra: largest ? ["-ui-test-largest-text"] : [])
            tap(app.buttons["watch.project.options.20000000-0000-0000-0000-000000000001"], in: app)
            tap(app.buttons["watch.goal.custom"], in: app)
            let picker = app.descendants(matching: .any)["watch.goal.custom-picker"].firstMatch
            let confirm = app.buttons["watch.goal.custom-confirm"]
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            XCTAssertTrue(picker.isHittable)
            XCTAssertGreaterThanOrEqual(picker.frame.height, 60)
            XCTAssertLessThanOrEqual(picker.frame.maxY, confirm.frame.minY)
            let original = picker.value as? String
            picker.swipeUp(velocity: .slow)
            let selected = try XCTUnwrap(Int(picker.value as? String ?? ""))
            XCTAssertNotEqual(String(selected), original)
            XCTAssertTrue((5...480).contains(selected) && selected % 5 == 0)
            capture(app, "expanded-custom-wheel-selected-\(largest ? "largest" : "ordinary")")
            try audit(app)
            tap(confirm, in: app)
            let goal = app.buttons["watch.metrics.goal"]
            XCTAssertTrue(goal.waitForExistence(timeout: 5))
            tap(goal, in: app)
            tap(app.buttons["watch.goal.custom"], in: app)
            XCTAssertEqual(picker.value as? String, String(selected))
            capture(app, "expanded-custom-wheel-restored-\(largest ? "largest" : "ordinary")")
            app.terminate()
        }
    }

    func testExpandedNoteTagsAndSaveFailureAtLargestText() throws {
        let app = launch("ended-long-content", extra: ["-ui-test-largest-text", "-ui-test-summary-failure"])
        tap(app.buttons["watch.end-summary.note"], in: app)
        let field = app.textFields["watch.end-summary.note-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue((field.value as? String)?.hasPrefix("Reviewed research findings") == true)
        capture(app, "expanded-note-top-largest")
        try audit(app)
        tap(app.buttons["watch.end-summary.note-use"], in: app)
        tap(app.buttons["watch.end-summary.tags"], in: app)
        capture(app, "expanded-tags-largest")
        try audit(app)
        tap(app.buttons["watch.end-summary.tag.90000000-0000-0000-0000-000000000002"], in: app)
        tap(app.buttons["watch.end-summary.tags-use"], in: app)
        tap(app.buttons["watch.end-summary.save"], in: app)
        let discard = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Discard Edit")).firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        capture(app, "expanded-save-failure-largest")
        try audit(app)
        tap(discard, in: app)
        XCTAssertFalse(app.buttons["watch.end-summary.save"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["watch.timer.running"].exists)
    }

    private func audit(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit { issue in
            let attachment = XCTAttachment(
                string:
                    "\(issue.detailedDescription)\nRaw value: \(String(describing: issue.element?.value))\n\(issue.element?.debugDescription ?? "No element")"
            )
            attachment.name = "WAT-23-expanded-audit"
            attachment.lifetime = .keepAlways
            self.add(attachment)
            return WatchAccessibilityUITests.isNativePagingIndicator(
                hitRegion: issue.auditType == .hitRegion, description: issue.detailedDescription,
                elementType: issue.element?.elementType, value: issue.element?.value as? String,
                frame: issue.element?.frame, expandedEnglish: true)
        }
    }

    private func launch(_ fixture: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            [
                "-ui-test-watch-fixture", fixture, "-NSDoubleLocalizedStrings", "YES",
                "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            ] + extra
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<18 {
            if isReachable(element, in: app) {
                return
            }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)),
                withVelocity: XCUIGestureVelocity(rawValue: 80), thenHoldForDuration: 0.3)
        }
        capture(app, "unreachable-expanded-element")
        XCTAssertTrue(isReachable(element, in: app))
    }

    private func isReachable(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let viewport = app.frame.insetBy(dx: 0, dy: 8)
        if viewport.contains(element.frame) { return true }
        // A wrapping project/note card can exceed the whole small display.
        // Its visible action area must still offer a full 44-point target.
        let visible = viewport.intersection(element.frame)
        return element.frame.height > viewport.height && visible.height >= 44 && visible.width >= 44
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        reveal(element, in: app)
        let visible = app.frame.insetBy(dx: 0, dy: 8).intersection(element.frame)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: visible.midX, dy: visible.midY)).tap()
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        for attachment in [XCTAttachment(screenshot: app.screenshot()), XCTAttachment(string: app.debugDescription)] {
            attachment.name = "WAT-23-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
