import SwiftUI

struct TrackView: View {
    @ObservedObject var model: BillableHoursAppModel

    @State private var showsCreateProject = false
    @State private var showsManualSession = false

    var body: some View {
        NavigationStack {
            List {
                if let activeSession = model.activeSession,
                    let project = model.project(id: activeSession.projectID)
                {
                    Section("Active timer") {
                        ActiveTimerCard(
                            project: project,
                            session: activeSession,
                            isStopping: model.isPerformingTimerCommand,
                            stop: {
                                Task { await model.stopActiveTimer() }
                            }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }

                Section {
                    Text("Projects")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)
                        .listRowBackground(Color.clear)

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
                                activeSession: model.activeSession,
                                isBusy: model.isPerformingTimerCommand
                            ) {
                                Task { await model.startOrSwitch(to: project.id) }
                            }
                        }

                        Text(projectInstruction)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("project-timer-instruction")
                            .listRowBackground(Color.clear)
                    }
                }
            }
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
        if model.activeSession != nil, model.activeProjects.count > 1 {
            "Tap another project to switch at one exact timestamp."
        } else {
            "Tap once to start. Only one timer runs at a time."
        }
    }
}

private struct ProjectTimerRow: View {
    let project: ProjectSnapshot
    let activeSession: TimeSessionSnapshot?
    let isBusy: Bool
    let action: () -> Void

    private var isActive: Bool { activeSession?.projectID == project.id }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(ProjectPalette.color(for: project.colorToken))
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.displayName)
                        .font(isActive ? .headline : .body)
                        .foregroundStyle(.primary)
                    if isActive {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                }
                Spacer()
                Text(actionTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isActive ? Color.secondary : Color.blue)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .listRowBackground(isActive ? Color.blue.opacity(0.12) : Color.clear)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier("project-timer-\(project.id.uuidString)")
    }

    private var actionTitle: String {
        if isActive { return "Running" }
        return activeSession == nil ? "Start" : "Switch"
    }

    private var accessibilityLabel: String {
        if isActive { return "\(project.displayName), active timer" }
        return activeSession == nil
            ? "Start \(project.displayName) timer"
            : "Switch timer to \(project.displayName)"
    }

    private var accessibilityHint: String {
        if isActive { return "Currently running." }
        if activeSession == nil { return "Only one timer runs at a time." }
        return "Ends the current session and starts this project at the same timestamp."
    }
}

private struct ActiveTimerCard: View {
    let project: ProjectSnapshot
    let session: TimeSessionSnapshot
    let isStopping: Bool
    let stop: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(session.startAt))
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "timer")
                                .foregroundStyle(.blue)
                                .accessibilityHidden(true)
                            Text("Active")
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.caption.weight(.semibold))
                        Text(project.displayName)
                            .font(.title2.bold())
                    }
                    Spacer()
                    Circle()
                        .fill(ProjectPalette.color(for: project.colorToken))
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                }

                Text(DurationPresentation.exact(elapsed))
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel("Elapsed \(DurationPresentation.accessibility(elapsed))")
                    .accessibilityIdentifier("active-elapsed-time")

                Button(role: .destructive, action: stop) {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.fill")
                        Text(isStopping ? "Stopping…" : "Stop")
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityHidden(true)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.62, green: 0.02, blue: 0.06))
                .disabled(isStopping)
                .accessibilityLabel(
                    "Stop \(project.displayName) timer, \(DurationPresentation.accessibility(elapsed)) elapsed"
                )
                .accessibilityIdentifier("stop-active-timer")
            }
            .padding()
            .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.blue, lineWidth: 2)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("active-timer-card")
        }
    }
}
