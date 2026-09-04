import SwiftUI
import WellSpentWatchContracts

struct WatchStartedTimerView: View {
    let run: TimerRunSnapshot
    let segments: [TimerSegmentSnapshot]
    let project: ProjectSnapshot?
    let projects: [ProjectSnapshot]
    let recentProjectIDs: [UUID]
    let totals: TimerTotalsSnapshot?
    let pendingSync: Bool
    let isReachable: Bool
    let forcePrivacyRedaction: Bool
    let initialPage: Int
    let startsOnControlSurface: Bool
    let controlOperation: WatchTimerControlOperation?
    let onPauseOrResume: () -> Void
    let onEnd: () -> Void
    let onSwitch: (ProjectSnapshot) -> Void
    let onSetGoal: (Int?) -> Void

    @EnvironmentObject private var goalAlerts: WatchGoalAlertCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @WatchPrivacyRedaction private var privacyRedaction
    @WatchAccessibilitySettings private var accessibilitySettings
    @State private var selectedPage = 0
    @State private var selectedSurface = 1
    @State private var showsEndConfirmation = false
    @State private var presentedSheet: WatchTimerSheet?
    @State private var endConfirmationSeconds: TimeInterval = 0

    private var redactsProjectIdentity: Bool {
        privacyRedaction || forcePrivacyRedaction
    }

    var body: some View {
        TimelineView(
            .periodic(
                from: .now,
                by: isLuminanceReduced ? 60 : 1
            )
        ) { timeline in
            let metrics = WatchTimerMetrics.calculate(
                run: run,
                segments: segments,
                at: timeline.date
            )
            let goalProgress = WatchGoalProgress(
                runID: run.id, goalSeconds: run.durationGoalSeconds,
                reached: metrics.goal?.isReached == true,
                visible: scenePhase == .active && !redactsProjectIdentity
                    && selectedSurface == 1 && selectedPage == 0
                    && presentedSheet == nil && !showsEndConfirmation)
            TabView(selection: $selectedSurface) {
                WatchTimerControlsView(
                    runState: run.state,
                    operation: controlOperation,
                    onEnd: {
                        endConfirmationSeconds = metrics.billableSeconds
                        showsEndConfirmation = true
                    },
                    onPauseOrResume: onPauseOrResume,
                    onNew: { presentedSheet = .switchProject }
                )
                .tag(0)

                metricPages(metrics: metrics, presentationDate: timeline.date)
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: goalProgress, initial: true) { _, progress in goalAlerts.observe(progress) }
        }
        .background(Color.black)
        .watchPrivacyFixtureToggle()
        .transaction { transaction in
            if accessibilitySettings.reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .onAppear {
            selectedPage = initialPage
            selectedSurface = startsOnControlSurface ? 0 : 1
        }
        .onDisappear { goalAlerts.leaveForeground() }
        .onChange(of: run.id) { _, _ in presentedSheet = nil }
        .alert("End this run?", isPresented: $showsEndConfirmation) {
            Button("End Run", role: .destructive, action: onEnd)
                .accessibilityIdentifier("watch.controls.end.confirm")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("watch.controls.end.cancel")
        } message: {
            Text(
                "End with \(WatchDurationText.spoken(endConfirmationSeconds)) of billable time?"
            )
        }
        .sheet(item: $presentedSheet) { sheet in
            Group {
                switch sheet {
                case .goal:
                    WatchGoalSetupView(
                        project: project, currentGoalSeconds: run.durationGoalSeconds, isEditing: true
                    ) { seconds in
                        presentedSheet = nil
                        onSetGoal(seconds)
                    }
                case .switchProject:
                    WatchSwitchProjectView(
                        projects: projects,
                        recentProjectIDs: recentProjectIDs,
                        currentProject: project,
                        isBusy: controlOperation != nil,
                        onSelect: { destination in
                            presentedSheet = nil
                            onSwitch(destination)
                        }
                    )
                }
            }
            .watchAccessibilityPreviewEnvironment()
        }
    }

    private func metricPages(
        metrics: WatchTimerMetrics,
        presentationDate: Date
    ) -> some View {
        TabView(selection: $selectedPage) {
            WatchElapsedMetricPage(
                run: run,
                metrics: metrics,
                project: project,
                pendingSync: pendingSync,
                isReachable: isReachable,
                redactsProjectIdentity: redactsProjectIdentity,
                onConfigureGoal: { presentedSheet = .goal }
            )
            .tag(0)

            WatchRunMetricPage(
                run: run,
                metrics: metrics,
                redactsProjectIdentity: redactsProjectIdentity
            )
            .tag(1)

            WatchTotalsMetricPage(
                totals: totals,
                presentationDate: presentationDate,
                isReachable: isReachable
            )
            .tag(2)
        }
        .tabViewStyle(.verticalPage(transitionStyle: accessibilitySettings.reduceMotion ? .identity : .automatic))
        .accessibilityHint(
            "Swipe vertically or turn the Digital Crown to change metric pages. Swipe right for controls."
        )
    }
}

private enum WatchTimerSheet: String, Identifiable {
    case goal
    case switchProject
    var id: String { rawValue }
}

private struct WatchElapsedMetricPage: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let run: TimerRunSnapshot
    let metrics: WatchTimerMetrics
    let project: ProjectSnapshot?
    let pendingSync: Bool
    let isReachable: Bool
    let redactsProjectIdentity: Bool
    let onConfigureGoal: () -> Void

    private var accent: Color {
        redactsProjectIdentity ? .gray : Color.watchTimerProjectToken(project?.colorToken)
    }

    private var projectName: String {
        WatchProjectIdentity.displayName(
            project?.name,
            redacted: redactsProjectIdentity
        )
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            content(compact: false)
            content(compact: true)
            ScrollView { content(compact: false) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watch.timer.running")
    }

    private func content(compact: Bool) -> some View {
        VStack(spacing: compact ? 2 : 4) {
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(statusTitle)
                    .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(statusColor)
                    .accessibilityIdentifier("watch.metrics.elapsed")
                    .accessibilitySortPriority(5)
                Spacer(minLength: 4)
                ViewThatFits(in: .horizontal) {
                    syncStatus.fixedSize(horizontal: true, vertical: false)
                    syncStatus.labelStyle(.iconOnly)
                }
            }

            Text(WatchDurationText.digital(metrics.billableSeconds))
                .font(.system(size: compact ? 26 : 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.58)
                .lineLimit(1)
                .foregroundStyle(.primary)
                .accessibilityLabel(
                    "Billable elapsed, \(WatchDurationText.spoken(metrics.billableSeconds))"
                )
                .accessibilityIdentifier("watch.metrics.billable")
                .accessibilitySortPriority(3)

            Text(projectName)
                .font(.system(compact ? .subheadline : .headline, design: .rounded, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : (compact ? 1 : 2))
                .foregroundStyle(redactsProjectIdentity ? .secondary : .primary)
                .accessibilityLabel("Project, \(projectName)")
                .accessibilityIdentifier("watch.metrics.project")
                .accessibilitySortPriority(4)

            Button(action: onConfigureGoal) {
                goalView.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens time goal and optional alert settings.")
            .accessibilityIdentifier(metrics.goal == nil ? "watch.metrics.no-goal" : "watch.metrics.goal")

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 10)
        .padding(.vertical, compact ? 2 : 4)
    }

    @ViewBuilder
    private var syncStatus: some View {
        if pendingSync {
            Label(
                isReachable ? String(localized: "Pending") : String(localized: "Saved offline"),
                systemImage: isReachable ? "arrow.up.arrow.down" : "wifi.slash"
            )
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isReachable ? .orange : .yellow)
            .accessibilityLabel(
                isReachable
                    ? String(localized: "Timer saved locally and pending sync")
                    : String(localized: "Offline. Timer saved locally and will sync later")
            )
            .accessibilityIdentifier("watch.timer.pending-sync")
            .accessibilitySortPriority(1)
        } else if !isReachable {
            Label("Offline", systemImage: "wifi.slash")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.yellow)
                .accessibilityLabel("Offline. Showing the timer saved on this Watch")
                .accessibilityIdentifier("watch.timer.offline")
                .accessibilitySortPriority(1)
        }
    }

    @ViewBuilder
    private var goalView: some View {
        if let goal = metrics.goal {
            VStack(spacing: 4) {
                ProgressView(value: goal.progress)
                    .tint(goal.isReached ? .green : accent)
                    .accessibilityHidden(true)
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text(goalTitle(goal)).fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 4)
                        goalPercent(goal)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goalTitle(goal))
                            .fixedSize(horizontal: false, vertical: true)
                        goalPercent(goal)
                    }
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(goal.isReached ? .green : .secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(goalAccessibilityLabel(goal))
            .accessibilityIdentifier("watch.metrics.goal")
            .accessibilitySortPriority(2)
        } else {
            Text("No time goal")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("watch.metrics.no-goal")
                .accessibilitySortPriority(2)
        }
    }

    private var statusTitle: String {
        switch run.state {
        case .running: String(localized: "Running")
        case .paused: String(localized: "Paused")
        case .ended: String(localized: "Ended")
        }
    }

    private func goalPercent(_ goal: WatchTimerMetrics.Goal) -> some View {
        let wholePercent = (metrics.billableSeconds / goal.targetSeconds * 100).rounded(.down)
        return Text((wholePercent / 100).formatted(.percent.precision(.fractionLength(0))))
            .monospacedDigit()
    }

    private var statusColor: Color {
        switch run.state {
        case .running: .green
        case .paused: .orange
        case .ended: .secondary
        }
    }

    private func goalTitle(_ goal: WatchTimerMetrics.Goal) -> String {
        if goal.overtimeSeconds >= 1 {
            return String(localized: "\(WatchDurationText.digital(goal.overtimeSeconds)) over")
        }
        if goal.isReached { return String(localized: "Goal reached") }
        return String(localized: "\(WatchDurationText.digital(goal.remainingSeconds)) left")
    }

    private func goalAccessibilityLabel(_ goal: WatchTimerMetrics.Goal) -> String {
        if goal.overtimeSeconds >= 1 {
            return String(localized: "Goal exceeded by \(WatchDurationText.spoken(goal.overtimeSeconds))")
        }
        if goal.isReached { return String(localized: "Time goal reached") }
        return String(localized: "Time goal, \(WatchDurationText.spoken(goal.remainingSeconds)) remaining")
    }
}

private struct WatchRunMetricPage: View {
    let run: TimerRunSnapshot
    let metrics: WatchTimerMetrics
    let redactsProjectIdentity: Bool

    var body: some View {
        ViewThatFits(in: .vertical) {
            content(spacing: 8, rowPadding: 7)
            content(spacing: 0, rowPadding: 0)
            ScrollView { content(spacing: 8, rowPadding: 7) }
        }
    }

    private func content(spacing: CGFloat, rowPadding: CGFloat) -> some View {
        VStack(spacing: spacing) {
            metricHeader("Run", symbol: "timer", compact: rowPadding == 0)
            WatchMetricRow(
                title: "Billable",
                value: WatchDurationText.digital(metrics.billableSeconds),
                accessibilityValue: WatchDurationText.spoken(metrics.billableSeconds),
                identifier: "watch.metrics.run.billable",
                verticalPadding: rowPadding
            )
            WatchMetricRow(
                title: "Paused",
                value: WatchDurationText.digital(metrics.pausedSeconds),
                accessibilityValue: WatchDurationText.spoken(metrics.pausedSeconds),
                identifier: "watch.metrics.run.paused",
                verticalPadding: rowPadding
            )
            WatchMetricRow(
                title: "Started",
                value: run.startedAt.formatted(date: .omitted, time: .shortened),
                accessibilityValue: run.startedAt.formatted(date: .omitted, time: .complete),
                identifier: "watch.metrics.run.started",
                verticalPadding: rowPadding
            )
            WatchMetricRow(
                title: "Segments",
                value: "\(metrics.segmentCount)",
                accessibilityValue: "\(metrics.segmentCount)",
                identifier: "watch.metrics.run.segments",
                verticalPadding: rowPadding
            )
        }
        .padding(.horizontal, 9)
        .padding(.vertical, rowPadding == 0 ? 0 : 7)
    }

    private func metricHeader(_ title: LocalizedStringKey, symbol: String, compact: Bool) -> some View {
        HStack {
            Label(title, systemImage: symbol)
                .font(compact ? .system(size: 12, weight: .semibold) : .headline)
                .accessibilityIdentifier("watch.metrics.run")
            Spacer()
            if redactsProjectIdentity {
                Image(systemName: "eye.slash.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Project identity hidden")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WatchMetricRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: LocalizedStringResource
    let value: String
    let accessibilityValue: String
    let identifier: String
    let verticalPadding: CGFloat

    var body: some View {
        rowLayout {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text(value)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 44 : 28, alignment: .leading)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(String(localized: title)), \(accessibilityValue)")
        .accessibilityIdentifier(identifier)
    }

    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
    }
}

private struct WatchTotalsMetricPage: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let totals: TimerTotalsSnapshot?
    let presentationDate: Date
    let isReachable: Bool

    var body: some View {
        ViewThatFits(in: .vertical) {
            content(spacing: 9, verticalPadding: 8)
            content(spacing: 5, verticalPadding: 5)
            ScrollView { content(spacing: 9, verticalPadding: 8) }
        }
    }

    private func content(spacing: CGFloat, verticalPadding: CGFloat) -> some View {
        VStack(spacing: spacing) {
            HStack {
                Label("Totals", systemImage: "chart.bar.fill")
                    .font(.headline)
                    .accessibilityLabel(totalsHeaderAccessibilityLabel)
                    .accessibilityIdentifier("watch.metrics.totals")
                Spacer()
            }

            if let totals {
                totalsLayout {
                    totalCard(
                        title: "Today",
                        seconds: totals.todaySeconds,
                        identifier: "watch.metrics.totals.today",
                        verticalPadding: verticalPadding
                    )
                    totalCard(
                        title: "This Week",
                        seconds: totals.weekSeconds,
                        identifier: "watch.metrics.totals.week",
                        verticalPadding: verticalPadding
                    )
                }
                freshnessLabel(totals)
            } else {
                ContentUnavailableView(
                    String(localized: "Totals unavailable"),
                    systemImage: "iphone.and.arrow.forward",
                    description: Text("Open WellSpent on iPhone to refresh.")
                )
                .accessibilityIdentifier("watch.metrics.totals.unavailable")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
    }

    private var totalsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
    }

    private func totalCard(
        title: LocalizedStringResource,
        seconds: Int,
        identifier: String,
        verticalPadding: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(WatchDurationText.digital(TimeInterval(seconds)))
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, verticalPadding)
        .background(Color.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(String(localized: title)), \(WatchDurationText.spoken(TimeInterval(seconds)))")
        .accessibilityIdentifier(identifier)
    }

    private var totalsHeaderAccessibilityLabel: String {
        guard let totals else { return String(localized: "Totals unavailable") }
        return
            switch WatchTotalsFreshness.classify(
                totals,
                at: presentationDate,
                isReachable: isReachable
            )
        {
        case .current: String(localized: "Totals, cached from iPhone and updated recently")
        case .offline: String(localized: "Totals, offline cached values")
        case .stale: String(localized: "Totals, stale cached values")
        }
    }

    @ViewBuilder
    private func freshnessLabel(_ totals: TimerTotalsSnapshot) -> some View {
        let freshness = WatchTotalsFreshness.classify(
            totals,
            at: presentationDate,
            isReachable: isReachable
        )
        switch freshness {
        case .current:
            Label("From iPhone", systemImage: "iphone")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Cached totals from iPhone, updated recently")
                .accessibilityIdentifier("watch.metrics.totals.current")
        case .offline:
            Label {
                Text("Offline · \(totals.calculatedAt, style: .relative)")
            } icon: {
                Image(systemName: "wifi.slash")
            }
            .foregroundStyle(.yellow)
            .accessibilityLabel(
                "Offline. Cached totals updated \(totals.calculatedAt.formatted(date: .abbreviated, time: .shortened))"
            )
            .accessibilityIdentifier("watch.metrics.totals.offline")
        case .stale:
            Label {
                Text("Cached · \(totals.calculatedAt, style: .relative)")
            } icon: {
                Image(systemName: "clock.badge.exclamationmark")
            }
            .foregroundStyle(.orange)
            .accessibilityLabel(
                "Stale cached totals updated \(totals.calculatedAt.formatted(date: .abbreviated, time: .shortened))"
            )
            .accessibilityIdentifier("watch.metrics.totals.stale")
        }
    }
}

extension Color {
    fileprivate static func watchTimerProjectToken(_ token: String?) -> Color {
        switch token?.lowercased() {
        case "cyan", "teal": .cyan
        case "green": .green
        case "orange": .orange
        case "pink": .pink
        case "purple", "indigo": .purple
        case "red": .red
        case "yellow": .yellow
        default: .blue
        }
    }
}
