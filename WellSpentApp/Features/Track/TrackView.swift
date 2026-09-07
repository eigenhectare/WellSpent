import SwiftUI

struct TrackView: View {
    @ObservedObject var model: WellSpentAppModel
    @Environment(\.colorScheme) private var colorScheme

    private var palette: WellSpentPalette { WellSpentPalette(colorScheme: colorScheme) }

    @State private var showsCreateProject = false
    @State private var showsManualSession = false

    var body: some View {
        NavigationStack {
            List {
                if let conflict = model.pendingWatchConflicts.first {
                    Section {
                        Label("Timer versions need review", systemImage: "exclamationmark.bubble.fill")
                            .font(.headline)
                        Text("Both versions are preserved. Choose which time should count before continuing.")
                        Button("Review Preserved Time") {
                            model.openConflictReview(id: conflict.snapshot.conflictID)
                        }
                        .accessibilityIdentifier("review-watch-conflict")
                    }
                    .listRowBackground(palette.surface)
                }
                if let activeRun = model.activeRun,
                    let project = model.project(id: activeRun.projectID)
                {
                    Section {
                        ActiveTimerCard(
                            project: project,
                            run: activeRun,
                            isBusy: model.isPerformingTimerCommand || model.timerCommandsBlocked,
                            isWatchOrigin: model.isWatchOrigin(activeRun),
                            pauseOrResume: {
                                Task {
                                    if activeRun.state == .paused {
                                        await model.resumeActiveTimer()
                                    } else {
                                        await model.pauseActiveTimer()
                                    }
                                }
                            },
                            stop: {
                                Task { await model.stopActiveTimer() }
                            }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }

                Section {
                    if model.activeProjects.isEmpty {
                        ContentUnavailableView {
                            Label("No Projects Yet", systemImage: "folder.badge.plus")
                        } description: {
                            Text("Create a project, then tap it whenever billable work begins.")
                        } actions: {
                            Button("Create First Project") {
                                showsCreateProject = true
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("create-first-project")
                        }
                    } else {
                        ForEach(model.activeProjects) { project in
                            ProjectTimerRow(
                                project: project,
                                activeRun: model.activeRun,
                                isBusy: model.isPerformingTimerCommand || model.timerCommandsBlocked
                            ) {
                                Task { await model.startOrSwitch(to: project.id) }
                            }
                        }
                    }
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Projects")
                            .font(.headline)
                            .foregroundStyle(palette.ink)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        if !model.activeProjects.isEmpty {
                            Text(model.activeProjects.count, format: .number)
                                .font(.subheadline)
                                .foregroundStyle(palette.secondary)
                                .accessibilityLabel("\(model.activeProjects.count) projects")
                        }
                    }
                    .textCase(nil)
                } footer: {
                    if !model.activeProjects.isEmpty {
                        Text(projectInstruction)
                            .font(.footnote)
                            .foregroundStyle(palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                            .accessibilityIdentifier("project-timer-instruction")
                    }
                }
                .listRowBackground(palette.surface)
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(24)
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .foregroundStyle(palette.ink)
            .navigationTitle("Track")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    NavigationLink {
                        SessionHistoryView(model: model)
                    } label: {
                        Label("Session History", systemImage: "clock.arrow.circlepath")
                    }
                    .accessibilityIdentifier("session-history")

                    NavigationLink {
                        ProjectManagementView(model: model)
                    } label: {
                        Label("Manage Projects", systemImage: "folder")
                    }
                    .accessibilityIdentifier("manage-projects")

                    Menu {
                        Button("Add Session", systemImage: "calendar.badge.plus") {
                            showsManualSession = true
                        }
                        Button("New Project", systemImage: "folder.badge.plus") {
                            showsCreateProject = true
                        }
                    } label: {
                        Label("Track Actions", systemImage: "plus")
                    }
                    .accessibilityIdentifier("track-actions")
                }
            }
            .sheet(isPresented: $showsCreateProject) {
                ProjectEditorView(model: model, mode: .create)
            }
            .sheet(isPresented: $showsManualSession) {
                ManualSessionEditorView(model: model, sessionID: nil)
            }
        }
    }

    private var projectInstruction: String {
        if model.activeRun != nil, model.activeProjects.count > 1 {
            "Tap another project to switch at one exact timestamp."
        } else {
            "Tap once to start. Only one timer runs at a time."
        }
    }
}

private struct ProjectTimerRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let project: ProjectSnapshot
    let activeRun: TimerRunSnapshot?
    let isBusy: Bool
    let action: () -> Void

    private var isActive: Bool { activeRun?.projectID == project.id }
    private var palette: WellSpentPalette { WellSpentPalette(colorScheme: colorScheme) }

    var body: some View {
        Button(action: action) {
            let rowLayout =
                dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(spacing: 12))
            rowLayout {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Circle()
                        .fill(ProjectPalette.color(for: project.colorToken))
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(project.displayName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if isActive {
                            Label(
                                activeRun?.state == .paused ? "Paused" : "Active",
                                systemImage: activeRun?.state == .paused
                                    ? "pause.circle.fill" : "checkmark.circle.fill"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.accent)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(actionTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isActive && activeRun?.state != .paused ? palette.secondary : palette.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 14)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .listRowSeparatorTint(palette.separator)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier("project-timer-\(project.id.uuidString)")
    }

    private var actionTitle: String {
        if isActive { return activeRun?.state == .paused ? "Resume" : "Running" }
        return activeRun == nil ? "Start" : "Switch"
    }

    private var accessibilityLabel: String {
        if isActive {
            return activeRun?.state == .paused
                ? "Resume \(project.displayName) timer"
                : "\(project.displayName), active timer"
        }
        return activeRun == nil
            ? "Start \(project.displayName) timer"
            : "Switch timer to \(project.displayName)"
    }

    private var accessibilityHint: String {
        if isActive {
            return activeRun?.state == .paused
                ? "Continues the same timer with a new counted segment."
                : "Currently running."
        }
        if activeRun == nil { return "Only one timer runs at a time." }
        return "Ends the current session and starts this project at the same timestamp."
    }
}

private struct ActiveTimerCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .largeTitle) private var elapsedFontSize: CGFloat = 56
    let project: ProjectSnapshot
    let run: TimerRunSnapshot
    let isBusy: Bool
    let isWatchOrigin: Bool
    let pauseOrResume: () -> Void
    let stop: () -> Void

    private var palette: WellSpentPalette { WellSpentPalette(colorScheme: colorScheme) }
    private var contentAlignment: HorizontalAlignment { colorScheme == .dark ? .center : .leading }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = run.countedDuration(at: context.date)
            VStack(alignment: contentAlignment, spacing: 20) {
                let headingLayout =
                    dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: contentAlignment, spacing: 10))
                    : AnyLayout(HStackLayout(spacing: 10))
                headingLayout {
                    HStack(spacing: 8) {
                        Image(systemName: run.state == .paused ? "pause.circle.fill" : "timer")
                            .accessibilityHidden(true)
                        Text(run.state == .paused ? "Paused" : "Running")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(palette.soft, in: Capsule())
                    .fixedSize(horizontal: false, vertical: true)

                    if !dynamicTypeSize.isAccessibilitySize {
                        Spacer(minLength: 0)
                    }
                    Text("Current session")
                        .font(.footnote)
                        .foregroundStyle(palette.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: contentAlignment, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle()
                            .fill(ProjectPalette.color(for: project.colorToken))
                            .frame(width: 12, height: 12)
                            .accessibilityHidden(true)
                        Text(project.displayName)
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .multilineTextAlignment(colorScheme == .dark ? .center : .leading)

                    if isWatchOrigin {
                        Label("Started on Apple Watch", systemImage: "applewatch")
                            .font(.caption)
                            .foregroundStyle(palette.secondary)
                            .accessibilityIdentifier("timer-watch-origin")
                    }

                    VStack(alignment: contentAlignment, spacing: 6) {
                        Text(DurationPresentation.exact(elapsed))
                            .font(.system(size: elapsedFontSize, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.35)
                            .accessibilityLabel("Elapsed \(DurationPresentation.accessibility(elapsed))")
                            .accessibilityIdentifier("active-elapsed-time")

                        Text("Time tracked")
                            .font(.footnote)
                            .foregroundStyle(palette.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: colorScheme == .dark ? .center : .leading)
                }

                let controlsLayout =
                    dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 12))
                    : AnyLayout(HStackLayout(spacing: 12))
                controlsLayout {
                    Button(action: pauseOrResume) {
                        HStack(spacing: 8) {
                            Image(systemName: run.state == .paused ? "play.fill" : "pause.fill")
                            Text(run.state == .paused ? "Resume" : "Pause")
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .accessibilityHidden(true)
                    }
                    .buttonStyle(TrackTimerButtonStyle(foreground: palette.ink, background: palette.soft))
                    .disabled(isBusy)
                    .accessibilityLabel(run.state == .paused ? "Resume timer" : "Pause timer")
                    .accessibilityHint(
                        run.state == .paused ? "Begins a new counted segment." : "Stops counting until you resume."
                    )
                    .accessibilityIdentifier(
                        run.state == .paused ? "resume-active-timer" : "pause-active-timer"
                    )

                    Button(role: .destructive, action: stop) {
                        HStack(spacing: 8) {
                            Image(systemName: "stop.fill")
                            Text(isBusy ? "Saving…" : "Stop")
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .accessibilityHidden(true)
                    }
                    .buttonStyle(TrackTimerButtonStyle(foreground: .white, background: palette.destructive))
                    .disabled(isBusy)
                    .accessibilityLabel(
                        "Stop \(project.displayName) timer, \(DurationPresentation.accessibility(elapsed)) elapsed"
                    )
                    .accessibilityIdentifier("stop-active-timer")
                }
            }
            .padding(colorScheme == .dark ? 20 : 0)
            .padding(.vertical, colorScheme == .dark ? 0 : 8)
            .background(
                colorScheme == .dark ? palette.surface : Color.clear,
                in: RoundedRectangle(cornerRadius: 22)
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("active-timer-card")
        }
    }
}

private struct TrackTimerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let foreground: Color
    let background: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .background(background, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}
