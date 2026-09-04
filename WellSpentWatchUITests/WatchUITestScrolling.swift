import XCTest

/// Scrolls visible content separately from native navigation chrome and follows
/// current element positions when conditional rows appear or disappear.
@MainActor
enum WatchUITestScrolling {
    static func viewport(_ app: XCUIApplication) -> CGRect {
        // Large-text navigation chrome can be taller than the status bar.
        // Keep content taps below its real bounds, but allow native alert
        // actions in the bottom region. Close uses its own chrome hit target.
        let screen = app.frame
        let navigationBottom =
            app.navigationBars.allElementsBoundByIndex
            .map(\.frame)
            .filter { $0.minY <= screen.minY + 1 && $0.width >= screen.width / 2 }
            .map(\.maxY).max() ?? screen.minY + 25
        let top = max(screen.minY + 25, navigationBottom)
        return CGRect(x: screen.minX + 1, y: top, width: screen.width - 2, height: screen.maxY - top)
    }

    static func reveal(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool = true) -> Bool {
        for _ in 0..<18 {
            let content = viewport(app)
            var scrollDown = upwards
            var dragDistance = app.frame.height * 0.35
            if element.exists, element.frame.height > 0, element.frame.width > 0 {
                // A retry can remove a row and change the scroll position.
                // Follow current geometry rather than the caller's old hint.
                let offset = element.frame.midY - content.midY
                scrollDown = offset > 0
                // Short drags below the pan threshold do not scroll watchOS.
                dragDistance = min(dragDistance, max(24, abs(offset)))
            }
            // Native watchOS alert prose can be visible without being a hit
            // target. Require hit testing for controls, not read-only text.
            if element.exists && (element.elementType == .staticText || element.isHittable) {
                let visible = element.frame.intersection(content)
                let requiredHeight: CGFloat
                switch element.elementType {
                case .staticText: requiredHeight = min(element.frame.height, content.height - 24)
                case .switch: requiredHeight = min(element.frame.height, content.height - 8)
                default: requiredHeight = min(element.frame.height, 44)
                }
                if visible.height + 0.5 >= requiredHeight, visible.width >= 28 { return true }
            }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: scrollDown ? 0.8 : 0.45))
            let end = start.withOffset(CGVector(dx: 0, dy: scrollDown ? -dragDistance : dragDistance))
            start.press(
                forDuration: 0.05, thenDragTo: end,
                withVelocity: XCUIGestureVelocity(rawValue: 80), thenHoldForDuration: 0.3)
        }
        return false
    }

    /// Long paragraphs are read across scroll positions. Verify both edges,
    /// with separate screenshots, instead of demanding subpoint alignment of
    /// a paragraph whose height almost exactly matches the usable viewport.
    static func revealTextEdge(_ element: XCUIElement, in app: XCUIApplication, ending: Bool) -> Bool {
        for _ in 0..<18 {
            guard element.exists else { return false }
            let content = viewport(app)
            let edge = ending ? element.frame.maxY : element.frame.minY
            if ending {
                if edge <= content.maxY - 4 && edge >= content.minY + 20 { return true }
            } else if edge >= content.minY + 4 && edge <= content.maxY - 20 {
                return true
            }
            let desired = ending ? content.maxY - 8 : content.minY + 8
            let offset = edge - desired
            let distance = min(app.frame.height * 0.35, max(24, abs(offset)))
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: offset > 0 ? 0.8 : 0.45))
            let finish = start.withOffset(CGVector(dx: 0, dy: offset > 0 ? -distance : distance))
            start.press(
                forDuration: 0.05, thenDragTo: finish,
                withVelocity: XCUIGestureVelocity(rawValue: 80), thenHoldForDuration: 0.3)
        }
        return false
    }
}
