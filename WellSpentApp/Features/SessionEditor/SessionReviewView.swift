import SwiftUI

struct SessionReviewView: View {
    @ObservedObject var model: WellSpentAppModel
    let sessionID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var showsEditor = false
    @State private var showsDeleteConfirmation = false

    var body: some View {
        Group {
            if let session = model.session(id: sessionID),
                let project = model.project(id: session.projectID)
            {
                List {
                    Section("Session") {
                        LabeledContent("Project", value: project.displayName)
                        LabeledContent("Source", value: session.source == .timer ? "Timer" : "Manual")
                        LabeledContent("Start") {
                            Text(session.startAt, format: .dateTime.year().month().day().hour().minute().second())
                        }
                        if let endAt = session.endAt {
                            LabeledContent("End") {
                                Text(endAt, format: .dateTime.year().month().day().hour().minute().second())
                            }
                            LabeledContent(
                                "Exact duration",
                                value: DurationPresentation.exact(endAt.timeIntervalSince(session.startAt))
                            )
                        } else {
                            LabeledContent("State", value: "Active")
                        }
                    }

                    if let note = session.note, !note.isEmpty {
                        Section("Note") { Text(note) }
                    }

                    if !session.tags.isEmpty {
                        Section("Tags") {
                            Text(session.tags.map(\.name).joined(separator: ", "))
                                .accessibilityIdentifier("session-tag-summary")
                        }
                    }

                    if model.overlappingSessionIDs.contains(session.id) {
                        Section {
                            Label(
                                "This session overlaps another record. Both records count fully in report totals.",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(.primary)
                            .accessibilityIdentifier("session-overlap-explanation")
                        }
                    }

                    Section("Audit") {
                        LabeledContent("Created") {
                            Text(session.createdAt, format: .dateTime.year().month().day().hour().minute().second())
                        }
                        LabeledContent("Updated") {
                            Text(session.updatedAt, format: .dateTime.year().month().day().hour().minute().second())
                        }
                    }

                    if session.endAt != nil {
                        Section {
                            Button("Delete Session", role: .destructive) {
                                showsDeleteConfirmation = true
                            }
                            .accessibilityIdentifier("delete-session")
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit") { showsEditor = true }
                            .accessibilityIdentifier("edit-session")
                    }
                }
                .sheet(isPresented: $showsEditor) {
                    if session.endAt == nil {
                        ActiveSessionEditorView(model: model, sessionID: session.id)
                    } else {
                        ManualSessionEditorView(model: model, sessionID: session.id)
                    }
                }
                .alert(
                    "Delete this session?",
                    isPresented: $showsDeleteConfirmation,
                ) {
                    Button("Delete Session", role: .destructive) {
                        if model.deleteSession(id: session.id) { dismiss() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This removes its full contribution from reports. This action cannot be undone.")
                }
            } else {
                ContentUnavailableView(
                    "Session No Longer Available",
                    systemImage: "trash",
                    description: Text("It may have been deleted while this view was open.")
                )
            }
        }
        .navigationTitle("Session Details")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("session-review-screen")
    }
}
