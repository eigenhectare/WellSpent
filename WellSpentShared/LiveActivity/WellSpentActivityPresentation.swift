import SwiftUI
import WidgetKit

/// Shared real presentation views, also hosted by the simulator visual tests.
/// The small mirrored card deliberately identifies the iPhone copy: a native
/// Watch command can be newer while the companion is unreachable.
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
        VStack(alignment: .leading, spacing: 4) {
            Label("iPhone copy", systemImage: "iphone")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(state.requiresReview == true ? "Review on iPhone" : status)
                .font(.headline)
            Text(label)
                .font(.caption)
                .lineLimit(1)
                .privacySensitive(state.showsProjectName)
            Text(state.requiresReview == true ? "Both versions are preserved" : "Open Watch app for current timer")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
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
