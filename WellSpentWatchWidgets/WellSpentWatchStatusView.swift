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
    let entry: WellSpentWatchStatusEntry
    var familyOverride: WidgetFamily? = nil

    private var family: WidgetFamily { familyOverride ?? widgetFamily }
    private var isRunning: Bool { entry.state?.timerState == .running }

    var body: some View {
        Group {
            if isRunning {
                runningContent
            } else {
                WellSpentHourglassComplicationMark()
                    .frame(width: markSize, height: markSize)
                    .scaleEffect(0.8)
            }
        }
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

    @ViewBuilder
    private var runningContent: some View {
        if family == .accessoryInline {
            HStack(spacing: 4) {
                WellSpentHourglassComplicationMark()
                    .frame(width: 12, height: 12)
                elapsedText
            }
            .font(.caption2.weight(.semibold))
        } else {
            GeometryReader { geometry in
                let iconSize = runningMarkSize(in: geometry.size)
                let midpoint = geometry.size.height / 2
                ZStack {
                    WellSpentHourglassComplicationMark()
                        .frame(width: iconSize, height: iconSize)
                        .position(
                            x: geometry.size.width / 2,
                            y: midpoint - iconSize / 2
                        )

                    elapsedText
                        .font(
                            .system(
                                size: runningTimerFontSize(for: geometry.size.height),
                                weight: .semibold,
                                design: .rounded
                            )
                        )
                        .monospacedDigit()
                        .frame(width: max(1, geometry.size.width - 4), alignment: .center)
                        .multilineTextAlignment(.center)
                        .position(
                            x: geometry.size.width / 2,
                            y: midpoint + geometry.size.height / 4
                        )
                }
            }
        }
    }

    @ViewBuilder
    private var elapsedText: some View {
        if let state = entry.state, let timerStart = state.elapsedTimerStart {
            if state.elapsed(at: entry.date) < 3_600 {
                Text(
                    timerInterval: timerStart...Date.distantFuture,
                    countsDown: false,
                    showsHours: false
                )
            } else {
                Text(verbatim: Self.hoursAndMinutes(state.elapsed(at: entry.date)))
            }
        } else {
            Text(verbatim: "0:00")
        }
    }

    private func runningMarkSize(in size: CGSize) -> CGFloat {
        let maximum: CGFloat
        switch family {
        case .accessoryCorner: maximum = 20
        case .accessoryCircular: maximum = 24
        case .accessoryRectangular: maximum = 28
        default: maximum = 24
        }
        return min(maximum, size.width * 0.36, size.height * 0.36)
    }

    private func runningTimerFontSize(for height: CGFloat) -> CGFloat {
        min(14, max(10, height * 0.2))
    }

    private static func hoursAndMinutes(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int(interval.rounded(.down)) / 60)
        return String(format: "%d:%02d", totalMinutes / 60, totalMinutes % 60)
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
    var body: some View {
        WellSpentHourglassSilhouette()
            .fill(.primary)
            .widgetAccentable()
            .aspectRatio(1, contentMode: .fit)
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

private func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
    CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
}
