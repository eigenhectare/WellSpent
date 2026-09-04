import SwiftUI

struct TimerRunReviewView: View {
    @ObservedObject var model: WellSpentAppModel
    let runID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var showsDetailsEditor = false
    @State private var showsDeleteConfirmation = false

    var body: some View {
        Group {
            if let run = model.run(id: runID),
                let project = model.project(id: run.projectID)
            {
                List {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Section("Timer run") {
                            LabeledContent("Project", value: project.displayName)
                            LabeledContent("State", value: stateLabel(run.state))
                            if model.isWatchOrigin(run) {
                                LabeledContent("Origin", value: "Apple Watch")
                                Text(model.watchSyncStatusText).font(.footnote)
                            }
                            LabeledContent("Started") {
                                Text(
                                    run.startAt,
                                    format: .dateTime.year().month().day().hour().minute().second()
                                )
                            }
                            if let endAt = run.endAt {
                                LabeledContent("Ended") {
                                    Text(
                                        endAt,
                                        format: .dateTime.year().month().day().hour().minute().second()
                                    )
                                }
                            }
                            LabeledContent(
                                "Counted time",
                                value: DurationPresentation.exact(
                                    run.countedDuration(at: context.date)
                                )
                            )
                            LabeledContent(
                                "Paused time",
                                value: DurationPresentation.exact(
                                    run.pausedDuration(at: context.date)
                                )
                            )
                            if let goal = run.durationGoalSeconds {
                                LabeledContent(
                                    "Goal",
                                    value: DurationPresentation.exact(goal)
                                )
                            }
                        }
                    }

                    Section("Counted segments") {
                        ForEach(Array(run.segments.enumerated()), id: \.element.id) { index, segment in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Segment \(index + 1)")
                                    .font(.headline)
                                Text(
                                    segment.startAt,
                                    format: .dateTime.month().day().hour().minute().second()
                                )
                                .foregroundStyle(.secondary)
                                if let endAt = segment.endAt {
                                    Text(DurationPresentation.exact(endAt.timeIntervalSince(segment.startAt)))
                                        .monospacedDigit()
                                } else {
                                    Text("Currently counting")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .accessibilityIdentifier("timer-run-segment-\(segment.id.uuidString)")
                        }
                    }

                    if let note = run.note, !note.isEmpty {
                        Section("Note") { Text(note) }
                    }

                    if !run.tags.isEmpty {
                        Section("Tags") {
                            Text(run.tags.map(\.name).joined(separator: ", "))
                                .accessibilityIdentifier("session-tag-summary")
                        }
                    }

                    if run.segments.contains(where: {
                        model.overlappingSessionIDs.contains($0.id)
                    }) {
                        Section {
                            Label(
                                "A counted segment overlaps another record. Both records count fully in report totals.",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .accessibilityIdentifier("session-overlap-explanation")
                        }
                    }

                    Section("Audit") {
                        LabeledContent("Run ID", value: run.id.uuidString)
                            .textSelection(.enabled)
                        LabeledContent("Revision", value: String(run.revision))
                        LabeledContent("Created") {
                            Text(
                                run.createdAt,
                                format: .dateTime.year().month().day().hour().minute().second()
                            )
                        }
                        LabeledContent("Updated") {
                            Text(
                                run.updatedAt,
                                format: .dateTime.year().month().day().hour().minute().second()
                            )
                        }
                    }

                    if run.state == .ended {
                        Section {
                            Button("Delete Timer Run", role: .destructive) {
                                showsDeleteConfirmation = true
                            }
                            .disabled(model.timerCommandsBlocked)
                            .accessibilityIdentifier("delete-session")
                        }
                    }
                }
                .toolbar {
                    if run.state == .ended {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Edit Details") { showsDetailsEditor = true }
                                .disabled(model.timerCommandsBlocked)
                                .accessibilityIdentifier("edit-session")
                        }
                    }
                }
                .sheet(isPresented: $showsDetailsEditor) {
                    SessionCompletionView(
                        model: model,
                        route: CompletionRoute(sessionID: run.id, kind: .deepLink)
                    )
                }
                .alert("Delete this timer run?", isPresented: $showsDeleteConfirmation) {
                    Button("Delete Timer Run", role: .destructive) {
                        if model.deleteSession(id: run.id) { dismiss() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(
                        "This removes every counted segment in the run from reports. This action cannot be undone."
                    )
                }
            } else {
                ContentUnavailableView(
                    "Timer Run No Longer Available",
                    systemImage: "trash",
                    description: Text("It may have been deleted while this view was open.")
                )
            }
        }
        .navigationTitle("Timer Details")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("session-review-screen")
    }

    private func stateLabel(_ state: TimerRunState) -> String {
        switch state {
        case .running: "Running"
        case .paused: "Paused"
        case .ended: "Ended"
        }
    }
}
