import XCTest

@MainActor
final class WatchPrivacyUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPickerAndSummaryHidePrivateContentInReducedLuminance() {
        for fixture in ["populated", "ended-long-content"] {
            let app = launch(fixture, extra: ["-ui-test-reduced-luminance"])
            assertPrivate(app)
            capture(app, fixture)
        }
    }

    func testActiveAndPausedKeepTimeButHideNamesInReducedLuminance() {
        for fixture in ["active", "paused"] {
            let app = launch(fixture, extra: ["-ui-test-reduced-luminance"])
            let identity = app.descendants(matching: .any)["watch.metrics.project"]
            XCTAssertTrue(identity.waitForExistence(timeout: 5))
            XCTAssertEqual(identity.label, "Project, Billable timer")
            XCTAssertTrue(app.descendants(matching: .any)["watch.metrics.billable"].exists)
            assertNoPrivateStrings(app)
            capture(app, fixture)
        }
    }

    func testGoalSheetRedactsAndRestoresWithoutStartingTimer() {
        let app = launch("populated", extra: ["-ui-test-privacy-toggle"])
        app.buttons["watch.project.options.20000000-0000-0000-0000-000000000001"].tap()
        XCTAssertTrue(app.buttons["watch.goal.open"].waitForExistence(timeout: 5))
        togglePrivacy(app)
        assertPrivate(app)
        capture(app, "goal-sheet")
        togglePrivacy(app)
        XCTAssertTrue(app.buttons["watch.goal.open"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["watch.timer.running"].exists)
        app.buttons["watch.goal.open"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["watch.timer.running"].waitForExistence(timeout: 5))
    }

    func testSwitchSheetRedactsAndRestoresWithoutChangingCurrentRun() {
        let app = launch("active", extra: ["-ui-test-privacy-toggle", "-ui-test-control-surface"])
        app.buttons["watch.controls.new"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["watch.switch.screen"].waitForExistence(timeout: 5))
        togglePrivacy(app)
        assertPrivate(app)
        capture(app, "switch-sheet")
        togglePrivacy(app)
        XCTAssertTrue(app.staticTexts["Client Launch"].waitForExistence(timeout: 5))
        app.buttons["watch.switch.project.20000000-0000-0000-0000-000000000002"].tap()
        app.swipeLeft()
        let identity = app.descendants(matching: .any)["watch.metrics.project"]
        XCTAssertTrue(identity.waitForExistence(timeout: 5))
        XCTAssertEqual(identity.label, "Project, Admin & Operations")
    }

    func testNoteEditorHidesItsValueAndPreservesTheDraftAcrossRedaction() {
        let app = launch("ended-long-content", extra: ["-ui-test-privacy-toggle"])
        let note = app.buttons["watch.end-summary.note"]
        reveal(note, app: app)
        note.tap()
        let field = app.textFields["watch.end-summary.note-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let original = field.value as? String
        XCTAssertTrue(original?.contains("Reviewed research findings") == true)
        togglePrivacy(app)
        assertPrivate(app)
        XCTAssertFalse(field.exists)
        capture(app, "note-sheet")
        togglePrivacy(app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, original)
        app.buttons["watch.end-summary.note-cancel"].firstMatch.tap()
    }

    func testTagEditorPreservesUnsavedSelectionAcrossRedaction() {
        let app = launch("ended", extra: ["-ui-test-privacy-toggle"])
        let tags = app.buttons["watch.end-summary.tags"]
        reveal(tags, app: app)
        tags.tap()
        let tag = app.buttons["watch.end-summary.tag.90000000-0000-0000-0000-000000000002"]
        XCTAssertTrue(tag.waitForExistence(timeout: 5))
        tag.tap()
        XCTAssertEqual(tag.label, "Deep focus, selected")
        togglePrivacy(app)
        assertPrivate(app)
        capture(app, "tag-sheet")
        togglePrivacy(app)
        XCTAssertTrue(tag.waitForExistence(timeout: 5))
        XCTAssertEqual(tag.label, "Deep focus, selected")
        let useTags = app.buttons["watch.end-summary.tags-use"]
        reveal(useTags, app: app)
        useTags.tap()
        XCTAssertTrue(app.buttons["watch.end-summary.save"].waitForExistence(timeout: 5))
    }

    private func launch(_ fixture: String, extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = ["-ui-test-watch-fixture", fixture] + extra
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        return app
    }

    private func togglePrivacy(_ app: XCUIApplication) {
        let toggles = app.buttons.matching(identifier: "watch.test.privacy-toggle")
        guard let visible = toggles.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
            XCTFail("No foreground privacy fixture toggle")
            return
        }
        visible.tap()
    }

    private func assertPrivate(_ app: XCUIApplication) {
        XCTAssertEqual(app.state, .runningForeground, "The privacy transition must not crash or dismiss the app.")
        XCTAssertTrue(app.descendants(matching: .any)["watch.privacy.screen"].firstMatch.waitForExistence(timeout: 5))
        assertNoPrivateStrings(app)
    }

    private func assertNoPrivateStrings(_ app: XCUIApplication) {
        let tree = app.debugDescription
        let attachment = XCTAttachment(string: tree)
        attachment.name = "WAT-23-redacted-accessibility-tree"
        attachment.lifetime = .keepAlways
        add(attachment)
        for value in [
            "Client Launch", "Admin & Operations", "Quarterly launch planning", "Reviewed research", "Deep focus",
        ] {
            XCTAssertFalse(tree.contains(value), "Private value remains exposed to accessibility: \(value)")
        }
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<18 {
            if element.exists && element.isHittable { return }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.8)).press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.45)),
                withVelocity: XCUIGestureVelocity(rawValue: 80), thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func capture(_ app: XCUIApplication, _ label: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "WAT-23-private-\(label)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
