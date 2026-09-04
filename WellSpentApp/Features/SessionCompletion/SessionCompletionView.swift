import SwiftUI

struct SessionCompletionView: View {
    @ObservedObject var model: WellSpentAppModel
    let route: CompletionRoute

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var selectedTagIDs = Set<UUID>()
    @State private var didLoadNote = false

    var body: some View {
        NavigationStack {
            Group {
                if let completed = completedPresentation {
                    Form {
                        if route.kind == .switched {
                            Section {
                                Label(
                                    "The previous session is saved. Your new timer is already running.",
                                    systemImage: "checkmark.circle.fill"
                                )
                                .foregroundStyle(.green)
                                .accessibilityIdentifier("switch-kept-running")
                            }
                        }

                        Section("Saved session") {
                            if let run = model.run(id: route.sessionID), model.isWatchOrigin(run) {
                                Label("Started on Apple Watch", systemImage: "applewatch")
                                Text(model.watchSyncStatusText).font(.footnote)
                            }
                            LabeledContent("Project", value: completed.projectName)
                            LabeledContent("Start") {
                                Text(completed.startAt, format: .dateTime.month().day().hour().minute().second())
                            }
                            LabeledContent("End") {
                                Text(completed.endAt, format: .dateTime.month().day().hour().minute().second())
                            }
                            LabeledContent(
                                "Exact duration",
                                value: DurationPresentation.exact(completed.countedDuration)
                            )
                            .accessibilityIdentifier("completed-session-duration")
                            if let pausedDuration = completed.pausedDuration {
                                LabeledContent(
                                    "Paused time",
                                    value: DurationPresentation.exact(pausedDuration)
                                )
                                LabeledContent(
                                    "Counted segments",
                                    value: String(completed.segmentCount ?? 0)
                                )
                            }
                        }

                        Section("Tags") {
                            SessionTagPicker(
                                tags: model.selectableSessionTags(sessionID: route.sessionID),
                                selectedTagIDs: $selectedTagIDs
                            )
                            Text("Choose any tags that describe this session. Manage choices in Settings.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("completion-tags")

                        Section("Optional note") {
                            TextEditor(text: $note)
                                .frame(minHeight: 140)
                                .accessibilityLabel("Session note")
                                .accessibilityIdentifier("completion-note")
                            Text("The time is already saved. Skipping or closing this screen will not remove it.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onAppear {
                        guard !didLoadNote else { return }
                        note = completed.note ?? ""
                        selectedTagIDs = Set(completed.tags.map(\.tagID))
                        didLoadNote = true
                    }
                } else {
                    ContentUnavailableView(
                        "Session Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("This completed session could not be found.")
                    )
                }
            }
            .navigationTitle(route.kind == .switched ? "Previous" : "Complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                        .accessibilityIdentifier("skip-completion-note")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Details") {
                        if model.saveSessionDetails(
                            sessionID: route.sessionID,
                            note: note,
                            tagIDs: selectedTagIDs
                        ) {
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier("save-completion-note")
                    .disabled(model.timerCommandsBlocked)
                }
            }
        }
        .interactiveDismissDisabled(false)
        .accessibilityIdentifier("session-completion-screen")
    }

    private var completedPresentation: CompletedTimerPresentation? {
        if let run = model.run(id: route.sessionID),
            run.state == .ended,
            let endAt = run.endAt,
            let project = model.project(id: run.projectID)
        {
            return CompletedTimerPresentation(
                projectName: project.displayName,
                startAt: run.startAt,
                endAt: endAt,
                countedDuration: run.countedDuration(at: endAt),
                pausedDuration: run.pausedDuration(at: endAt),
                segmentCount: run.segments.count,
                note: run.note,
                tags: run.tags
            )
        }
        guard let session = model.session(id: route.sessionID),
            let endAt = session.endAt,
            let project = model.project(id: session.projectID)
        else { return nil }
        return CompletedTimerPresentation(
            projectName: project.displayName,
            startAt: session.startAt,
            endAt: endAt,
            countedDuration: endAt.timeIntervalSince(session.startAt),
            pausedDuration: nil,
            segmentCount: nil,
            note: session.note,
            tags: session.tags
        )
    }
}

private struct CompletedTimerPresentation {
    let projectName: String
    let startAt: Date
    let endAt: Date
    let countedDuration: TimeInterval
    let pausedDuration: TimeInterval?
    let segmentCount: Int?
    let note: String?
    let tags: [SessionTagAssignmentSnapshot]
}
