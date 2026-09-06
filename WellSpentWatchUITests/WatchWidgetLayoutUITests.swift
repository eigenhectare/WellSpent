import XCTest

/// Tests the production widget view under constrained proposed sizes. This
/// app-hosted harness is not the WidgetKit compositor or a curved-label preview.
@MainActor
final class WatchWidgetLayoutUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testRectangularAtOrdinaryText() throws { try rectangular(largest: false, expanded: false) }
    func testRectangularAtLargestText() throws { try rectangular(largest: true, expanded: false) }
    func testRectangularAtLargestExpandedText() throws { try rectangular(largest: true, expanded: true) }

    func testRectangularOptInAndPrivacyAtLargestExpandedText() throws {
        for fixture in ["populated", "long-names", "active"] {
            for privacy in ["visible", "redacted", "luminance"] {
                var extra = ["-ui-test-widget-names", "-ui-test-largest-text", "-NSDoubleLocalizedStrings", "YES"]
                if privacy == "redacted" { extra.append("-ui-test-privacy-redacted") }
                if privacy == "luminance" { extra.append("-ui-test-reduced-luminance") }
                let app = launch(fixture, extra: extra)
                try verify(app, name: "\(fixture)-\(privacy)", expanded: true, recent: fixture != "active")
                let tree = app.debugDescription
                let name = fixture == "long-names" ? "Quarterly launch planning and customer research" : "Client Launch"
                if privacy != "visible" {
                    XCTAssertFalse(tree.contains(name))

                }
                if fixture != "active" {
                    verifyProjectPickerLabel(app)
                    XCTAssertFalse(tree.contains(name))
                }
                app.terminate()
            }
        }
    }

    private func rectangular(largest: Bool, expanded: Bool) throws {
        for fixture in [
            "populated", "active", "paused", "active-pending", "conflict", "unsupported", "setup", "store-unavailable",
            "large-duration", "goal-reached", "overtime",
        ] {
            var extra: [String] = []
            if largest { extra.append("-ui-test-largest-text") }
            if expanded { extra += ["-NSDoubleLocalizedStrings", "YES"] }
            let app = launch(fixture, extra: extra)
            try verify(app, name: fixture, expanded: expanded, recent: fixture == "populated")
            XCTAssertFalse(app.debugDescription.contains("Client Launch"))
            if fixture == "populated" { verifyProjectPickerLabel(app) }
            app.terminate()
        }
    }

    private func launch(_ fixture: String, extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-watch-fixture", fixture, "-ui-test-widget-family", "rectangular"] + extra
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        return app
    }

    private func verify(_ app: XCUIApplication, name: String, expanded: Bool, recent: Bool) throws {
        let bounds = app.staticTexts["watch.widget-preview.bounds"]
        XCTAssertTrue(bounds.waitForExistence(timeout: 5))
        let values = try XCTUnwrap(bounds.value as? String).split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(values.count, 4)
        let region = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        XCTAssertGreaterThan(region.width, 0)
        XCTAssertEqual(region.height, 88)
        XCTAssertTrue(app.frame.contains(region))
        capture(app, name)
        let measured = XCTAttachment(string: "proposal=\(region)\narguments=\(app.launchArguments)")
        measured.name = "WAT-23-widget-proposal-\(name)"
        measured.lifetime = .keepAlways
        add(measured)
        let texts = app.staticTexts.allElementsBoundByIndex.filter { $0.identifier != "watch.widget-preview.bounds" }
        // A Link with an explicit accessible name can be a single Button node;
        // its text children correctly disappear from the accessibility tree.
        XCTAssertFalse((texts + app.buttons.allElementsBoundByIndex).isEmpty)
        for text in texts { assertInside(text, region: region) }
        if recent {
            // The whole accessory is a single widgetURL destination. There
            // must be no nested project shortcut that bypasses the picker.
            XCTAssertTrue(app.buttons.allElementsBoundByIndex.isEmpty)
            verifyProjectPickerLabel(app)
        }
        if expanded && !name.contains("visible") {
            let labels = (texts + app.buttons.allElementsBoundByIndex).map(\.label)
            XCTAssertTrue(
                labels.contains { label in
                    ["Start timer", "Running", "Paused", "Review", "Update", "Set up", "Open"].contains { word in
                        label.components(separatedBy: word).count >= 3
                    }
                }, "The real localization boundary must expand; a launch flag alone is not evidence.")
        }
        try app.performAccessibilityAudit { issue in
            let detail = XCTAttachment(string: "\(issue.detailedDescription)\n\(issue.element?.debugDescription ?? "")")
            detail.name = "WAT-23-widget-layout-audit"
            detail.lifetime = .keepAlways
            self.add(detail)
            return false
        }
        // Preserve both app-scoped and composited-screen evidence. A populated
        // accessibility tree alone cannot prove that safe content was drawn.
        let rendered = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        rendered.name = "WAT-23-widget-rendered-\(name)"
        rendered.lifetime = .keepAlways
        add(rendered)
    }

    private func verifyProjectPickerLabel(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts.allElementsBoundByIndex.contains { $0.label.contains("Start timer") })
    }

    private func assertInside(_ element: XCUIElement, region: CGRect) {
        XCTAssertGreaterThan(element.frame.width, 0, element.label)
        XCTAssertGreaterThan(element.frame.height, 0, element.label)
        XCTAssertGreaterThanOrEqual(element.frame.minX + 0.5, region.minX, element.label)
        XCTAssertLessThanOrEqual(element.frame.maxX, region.maxX + 0.5, element.label)
        XCTAssertGreaterThanOrEqual(element.frame.minY + 0.5, region.minY, element.label)
        XCTAssertLessThanOrEqual(element.frame.maxY, region.maxY + 0.5, element.label)
    }

    private func capture(_ app: XCUIApplication, _ fixture: String) {
        for attachment in [XCTAttachment(screenshot: app.screenshot()), XCTAttachment(string: app.debugDescription)] {
            attachment.name = "WAT-23-widget-layout-\(fixture)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
