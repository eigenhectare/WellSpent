import SwiftUI
import WellSpentWatchStore
import WidgetKit

struct WellSpentWatchStatusEntry: TimelineEntry {
    let date: Date
    let state: WatchWidgetState?

    var relevance: TimelineEntryRelevance? {
        let score: Float = state?.runID != nil ? 90 : (state?.timerState == .blocked ? 70 : 10)
        return TimelineEntryRelevance(score: score, duration: 30 * 60)
    }
}

struct WellSpentWatchStatusView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    let entry: WellSpentWatchStatusEntry
    var familyOverride: WidgetFamily? = nil

    private var family: WidgetFamily { familyOverride ?? widgetFamily }
    private var isRunning: Bool { entry.state?.timerState == .running }

    var body: some View {
        WellSpentHourglassComplicationMark(
            isRunning: isRunning,
            animatesTrace: !isLuminanceReduced
        )
        .frame(width: markSize, height: markSize)
        .scaleEffect(0.8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .unredacted()
        .widgetURL((entry.state?.route ?? .projects).url)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("WellSpent")
        .accessibilityValue(isRunning ? "Timer running" : "No timer running")
        .accessibilityHint(
            entry.state?.runID != nil
                ? String(localized: "Opens the current timer.")
                : String(localized: "Opens WellSpent to choose a project.")
        )
        .accessibilityIdentifier("watch.complication.hourglass")
    }

    private var markSize: CGFloat {
        switch family {
        case .accessoryInline: 18
        case .accessoryCorner: 38
        case .accessoryCircular: 44
        case .accessoryRectangular: 52
        default: 44
        }
    }
}

/// A one-color vector interpretation of the iPhone app icon. WidgetKit assigns
/// the accent group's actual color so the mark follows the selected Watch face.
private struct WellSpentHourglassComplicationMark: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let isRunning: Bool
    let animatesTrace: Bool

    var body: some View {
        GeometryReader { geometry in
            let dimension = min(geometry.size.width, geometry.size.height)
            ZStack {
                WellSpentHourglassSilhouette()
                    .fill(.primary)
                    .widgetAccentable()

                if isRunning {
                    runningTrace(dimension: dimension)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func runningTrace(dimension: CGFloat) -> some View {
        if animatesTrace {
            PhaseAnimator([false, true]) { completedLap in
                trace(dimension: dimension, start: completedLap ? 0.5 : 0)
            } animation: { completedLap in
                completedLap ? .linear(duration: 2) : nil
            }
        } else {
            trace(dimension: dimension, start: 0.5)
        }
    }

    private func trace(dimension: CGFloat, start: CGFloat) -> some View {
        WellSpentHourglassTrace()
            .trim(from: start, to: start + 0.475)
            .stroke(
                traceColor,
                style: StrokeStyle(
                    lineWidth: max(1.5, dimension * 0.065),
                    lineCap: .round,
                    lineJoin: .round
                )
            )
    }

    private var traceColor: Color {
        renderingMode == .fullColor ? .black.opacity(0.72) : .primary
    }
}

/// The filled shape preserves the app icon's broad rounded caps, concave sides,
/// narrow waist, and balanced upper/lower silhouette without its multicolor fill.
private struct WellSpentHourglassSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: point(0.22, 0.08, in: rect))
        path.addCurve(
            to: point(0.15, 0.22, in: rect),
            control1: point(0.14, 0.08, in: rect),
            control2: point(0.12, 0.15, in: rect)
        )
        path.addCurve(
            to: point(0.47, 0.49, in: rect),
            control1: point(0.24, 0.36, in: rect),
            control2: point(0.36, 0.44, in: rect)
        )
        path.addCurve(
            to: point(0.47, 0.55, in: rect),
            control1: point(0.50, 0.51, in: rect),
            control2: point(0.50, 0.53, in: rect)
        )
        path.addCurve(
            to: point(0.15, 0.88, in: rect),
            control1: point(0.36, 0.64, in: rect),
            control2: point(0.24, 0.75, in: rect)
        )
        path.addCurve(
            to: point(0.22, 0.96, in: rect),
            control1: point(0.12, 0.93, in: rect),
            control2: point(0.15, 0.96, in: rect)
        )
        path.addLine(to: point(0.78, 0.96, in: rect))
        path.addCurve(
            to: point(0.85, 0.88, in: rect),
            control1: point(0.85, 0.96, in: rect),
            control2: point(0.88, 0.93, in: rect)
        )
        path.addCurve(
            to: point(0.53, 0.55, in: rect),
            control1: point(0.76, 0.75, in: rect),
            control2: point(0.64, 0.64, in: rect)
        )
        path.addCurve(
            to: point(0.53, 0.49, in: rect),
            control1: point(0.50, 0.53, in: rect),
            control2: point(0.50, 0.51, in: rect)
        )
        path.addCurve(
            to: point(0.85, 0.22, in: rect),
            control1: point(0.64, 0.44, in: rect),
            control2: point(0.76, 0.36, in: rect)
        )
        path.addCurve(
            to: point(0.78, 0.08, in: rect),
            control1: point(0.88, 0.15, in: rect),
            control2: point(0.86, 0.08, in: rect)
        )
        path.closeSubpath()
        return path
    }
}

/// The trace walks clockwise around one half, crosses the waist, continues
/// around the opposite half, crosses again, and returns to its starting point.
/// It contains two identical laps so a 95%-of-one-lap trim window can cross the
/// seam continuously. PhaseAnimator starts when the running view appears and
/// moves the gap a full lap in 2 seconds; the equivalent end frames reset cleanly.
private struct WellSpentHourglassTrace: Shape {
    func path(in rect: CGRect) -> Path {
        let lap = lap(in: rect)
        var doubledPath = Path()
        doubledPath.addPath(lap)
        doubledPath.addPath(lap)
        return doubledPath
    }

    private func lap(in rect: CGRect) -> Path {
        var lap = Path()
        lap.move(to: point(0.50, 0.08, in: rect))
        lap.addLine(to: point(0.78, 0.08, in: rect))
        lap.addCurve(
            to: point(0.85, 0.22, in: rect),
            control1: point(0.86, 0.08, in: rect),
            control2: point(0.88, 0.15, in: rect)
        )
        lap.addCurve(
            to: point(0.53, 0.50, in: rect),
            control1: point(0.76, 0.36, in: rect),
            control2: point(0.64, 0.44, in: rect)
        )
        lap.addLine(to: point(0.47, 0.54, in: rect))
        lap.addCurve(
            to: point(0.15, 0.88, in: rect),
            control1: point(0.36, 0.64, in: rect),
            control2: point(0.24, 0.75, in: rect)
        )
        lap.addCurve(
            to: point(0.22, 0.96, in: rect),
            control1: point(0.12, 0.93, in: rect),
            control2: point(0.15, 0.96, in: rect)
        )
        lap.addLine(to: point(0.78, 0.96, in: rect))
        lap.addCurve(
            to: point(0.85, 0.88, in: rect),
            control1: point(0.85, 0.96, in: rect),
            control2: point(0.88, 0.93, in: rect)
        )
        lap.addCurve(
            to: point(0.53, 0.54, in: rect),
            control1: point(0.76, 0.75, in: rect),
            control2: point(0.64, 0.64, in: rect)
        )
        lap.addLine(to: point(0.47, 0.50, in: rect))
        lap.addCurve(
            to: point(0.15, 0.22, in: rect),
            control1: point(0.36, 0.44, in: rect),
            control2: point(0.24, 0.36, in: rect)
        )
        lap.addCurve(
            to: point(0.22, 0.08, in: rect),
            control1: point(0.12, 0.15, in: rect),
            control2: point(0.14, 0.08, in: rect)
        )
        lap.closeSubpath()
        return lap
    }
}

private func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
    CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
}
