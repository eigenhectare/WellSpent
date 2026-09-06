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
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.redactionReasons) private var redactionReasons
    let entry: WellSpentWatchStatusEntry
    var familyOverride: WidgetFamily? = nil

    private var family: WidgetFamily { familyOverride ?? widgetFamily }

    private var redacted: Bool { isLuminanceReduced || !redactionReasons.isEmpty }
    private var state: WatchWidgetState? { entry.state }
    private var isActive: Bool { state?.runID != nil }

    private var accent: Color {
        renderingMode == .fullColor
            ? Color(red: 1, green: 0.76, blue: 0.42) : .primary
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circular
            case .accessoryCorner:
                Image(systemName: statusSymbol)
                    .font(.title2)
                    .foregroundStyle(accent)
                    .widgetAccentable()
                    .widgetLabel {
                        if isActive { elapsed } else { Text(statusLabel) }
                    }
                    .accessibilityLabel(statusLabel)
            case .accessoryInline:
                HStack(spacing: 3) {
                    Image(systemName: statusSymbol)
                    if isActive { elapsed } else { Text(statusLabel) }
                    if state?.pendingSync == true { Image(systemName: "arrow.triangle.2.circlepath") }
                }
            default:
                rectangular
            }
        }
        // Identity has already been replaced above when the incoming privacy
        // environment is active. Keep that sanitized content visible instead
        // of letting SwiftUI redact the entire generic status/link label too.
        .unredacted()
        .widgetURL((state?.route ?? .projects).url)
        .accessibilityHint(
            isActive
                ? String(localized: "Opens the current timer.")
                : String(localized: "Choose a project in the app to start a timer.")
        )
    }

    private var circular: some View {
        VStack(spacing: 1) {
            Image(systemName: statusSymbol)
                .font(.caption2)
                .foregroundStyle(accent)
                .widgetAccentable()
                .accessibilityHidden(true)
            if isActive {
                elapsed.font(.system(.caption, design: .rounded, weight: .semibold))
                Text(state?.timerState == .paused ? String(localized: "PAUSED") : String(localized: "TIME"))
                    .font(.system(size: 11, weight: .semibold))
            } else {
                Text(state?.timerState == .ready ? String(localized: "Projects") : shortStatus)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var rectangular: some View {
        ViewThatFits {
            detailedRectangular
            compactRectangular
        }
    }

    private var detailedRectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: statusSymbol).foregroundStyle(accent)
                    .widgetAccentable().accessibilityHidden(true)
                Text(state?.timerState == .ready ? String(localized: "WellSpent") : statusLabel).fixedSize()
                Spacer(minLength: 0)
                if state?.pendingSync == true {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .accessibilityLabel("Pending sync")
                }
            }
            .font(.caption2.weight(.semibold))
            if isActive {
                elapsed.font(.system(.title2, design: .rounded, weight: .semibold))
                HStack(spacing: 4) {
                    Text(
                        redacted
                            ? String(localized: "Billable time")
                            : (state?.projectName ?? String(localized: "Billable time"))
                    )
                    .privacySensitive(state?.projectName != nil)
                    .fixedSize()
                    Spacer(minLength: 0)
                    if let goal = state?.durationGoalSeconds, let state {
                        Text(goalLabel(seconds: goal, state: state)).fixedSize()
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else if state?.timerState == .ready {
                Text("Start timer")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .fixedSize()
                Label("Choose a project", systemImage: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            } else {
                Text(detailLabel).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Accessory views cannot scroll. Prefer full copy when it fits, then keep
    /// the essential state/time or the single project-picker destination.
    /// A tap is navigation only, including when the visible snapshot is stale.
    @ViewBuilder
    private var compactRectangular: some View {
        if isActive {
            VStack(alignment: .leading, spacing: 3) {
                Text(state?.timerState == .paused ? String(localized: "Paused") : String(localized: "Running"))
                    .font(.caption2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    elapsed.font(.system(.title2, design: .rounded, weight: .semibold))
                    if state?.pendingSync == true {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2).accessibilityLabel("Pending sync")
                    }
                }
            }
        } else if state?.timerState == .ready {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "play.fill")
                    .foregroundStyle(accent)
                    .widgetAccentable()
                    .accessibilityHidden(true)
                Text("Start timer")
                    .font(.caption2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint("Choose a project in the app to start a timer.")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: statusSymbol).font(.title3).foregroundStyle(accent)
                    .widgetAccentable().accessibilityHidden(true)
                Text(shortStatus).font(.caption2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(statusLabel)
            .accessibilityValue(detailLabel)
        }
    }

    private func goalLabel(seconds: Int, state: WatchWidgetState) -> String {
        state.elapsed(at: entry.date) >= Double(seconds)
            ? String(localized: "Goal met") : String(localized: "\(seconds / 60)m goal")
    }

    @ViewBuilder
    private var elapsed: some View {
        if let start = state?.elapsedTimerStart {
            Text(timerInterval: start...Date.distantFuture, countsDown: false)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        } else {
            Text(Self.duration(state?.elapsed(at: entry.date) ?? 0))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }

    private var statusLabel: String {
        switch state?.timerState {
        case .blocked: String(localized: "Review on iPhone")
        case .paused: String(localized: "Paused")
        case .ready: String(localized: "Start timer")
        case .running: String(localized: "Tracking time")
        case .setupRequired: String(localized: "Set up on iPhone")
        case .updateRequired: String(localized: "Update WellSpent")
        case .none: String(localized: "WellSpent")
        }
    }

    private var shortStatus: String {
        switch state?.timerState {
        case .blocked: String(localized: "Review")
        case .updateRequired: String(localized: "Update")
        case .setupRequired: String(localized: "Set up")
        default: String(localized: "Open")
        }
    }

    private var detailLabel: String {
        switch state?.timerState {
        case .blocked: String(localized: "Your time is preserved.")
        case .updateRequired: String(localized: "Open the app to continue.")
        case .setupRequired: String(localized: "Create your first project.")
        default: String(localized: "Track billable time from your wrist.")
        }
    }

    private var statusSymbol: String {
        switch state?.timerState {
        case .blocked: "exclamationmark.bubble.fill"
        case .paused: "pause.fill"
        case .running: "stopwatch.fill"
        case .updateRequired: "arrow.down.app"
        case .ready: "play.fill"
        case .setupRequired, .none: "stopwatch"
        }
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded(.down)))
        if value >= 3_600 {
            return String(format: "%d:%02d:%02d", value / 3_600, value / 60 % 60, value % 60)
        }
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
