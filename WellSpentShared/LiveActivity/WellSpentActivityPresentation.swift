import SwiftUI
import WidgetKit

/// Shared real presentation views, also hosted by the simulator visual tests.
public struct WellSpentActivityPresentation: View {
    public enum Family: String, CaseIterable {
        case lockScreen, expanded, compact, minimal, watchMirror
    }

    private let runID: UUID
    private let startedAt: Date
    private let state: WellSpentActivityAttributes.ContentState
    private let family: Family
    private let isStale: Bool
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.redactionReasons) private var redactionReasons

    public init(
        runID: UUID, startedAt: Date, state: WellSpentActivityAttributes.ContentState,
        family: Family, isStale: Bool = false
    ) {
        self.runID = runID
        self.startedAt = startedAt
        self.state = state
        self.family = family
        self.isStale = isStale
    }

    public var body: some View {
        Group {
            switch family {
            case .watchMirror: watchMirror
            case .compact: compact
            case .minimal: statusIcon
            case .lockScreen, .expanded: full
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var label: String {
        dimmed || redactionReasons.contains(.privacy) ? "WellSpent timer" : state.displayLabel
    }

    private var canStop: Bool { state.canStop && !isStale }
    private var status: String { isStale ? "Open app to refresh" : state.statusText }
    private var symbol: String {
        if state.requiresReview == true || isStale { return "exclamationmark.circle" }
        switch state.phase {
        case .running: return "stopwatch.fill"
        case .paused: return "pause.circle.fill"
        case .stopped: return "checkmark.circle.fill"
        }
    }

    private var statusIcon: some View {
        Image(systemName: symbol)
            .foregroundStyle(state.requiresReview == true || isStale ? Color.orange : Color.accentColor)
            .accessibilityLabel(status)
    }

    private var compact: some View {
        HStack(spacing: 4) {
            statusIcon
            if state.requiresReview != true && !isStale {
                elapsed.font(.caption2.monospacedDigit())
            }
        }
    }

    private var full: some View {
        HStack(spacing: 12) {
            statusIcon.font(.title2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.headline)
                    .lineLimit(2)
                    .privacySensitive(state.showsProjectName)
                elapsed.font(family == .expanded ? .title : .title2)
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let sync = state.syncStatusText, state.requiresReview != true {
                    Text(sync).font(.caption2).foregroundStyle(.secondary)
                }
                if state.phase == .stopped {
                    Text("Tap to add notes").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if canStop {
                Button(intent: StopWellSpentTimerIntent(activityID: runID, revision: state.revision)) {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .accessibilityLabel("Stop WellSpent timer")
                .accessibilityHint("Opens WellSpent to save the stop for this run")
            }
        }
        .padding(family == .expanded ? 12 : 16)
    }

    private var watchMirror: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(watchMirrorTint.opacity(0.18))
                    WellSpentLiveActivityHourglass()
                        .fill(watchMirrorTint)
                        .frame(width: 18, height: 18)
                }
                .frame(width: 34, height: 34)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(status)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    elapsed
                        .font(.headline.weight(.bold))
                }
                .layoutPriority(1)

                Spacer(minLength: 0)

                if canStop {
                    Link(destination: WellSpentDeepLink.watchStopURL(for: runID, revision: state.revision)) {
                        ZStack {
                            Circle()
                                .fill(.red)
                            Image(systemName: "stop.fill")
                                .font(.body.weight(.bold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(state.stopAccessibilityLabel)
                    .accessibilityHint("Opens WellSpent on Apple Watch and saves the stop for this run")
                }
            }

            Text(label)
                .font(.caption)
                .lineLimit(1)
                .privacySensitive(state.showsProjectName)

            if let syncStatus = state.syncStatusText {
                Label(syncStatus, systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
    }

    private var watchMirrorTint: Color {
        if state.requiresReview == true { return .orange }
        switch state.phase {
        case .running: return .accentColor
        case .paused: return .yellow
        case .stopped: return .green
        }
    }

    @ViewBuilder
    private var elapsed: some View {
        if let anchor = state.timerAnchor(legacyStartedAt: startedAt), !isStale {
            Text(timerInterval: anchor...Date.distantFuture, countsDown: false)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityLabel("Elapsed time")
        } else if isStale {
            Text("—").accessibilityLabel("Open the app for current elapsed time")
        } else {
            Text(
                Duration.seconds(state.elapsed(at: startedAt, legacyStartedAt: startedAt)),
                format: .time(pattern: .hourMinuteSecond)
            )
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityLabel(state.phase == .stopped ? "Final elapsed time" : "Counted time")
        }
    }
}

private struct WellSpentLiveActivityHourglass: Shape {
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

    private func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
    }
}
