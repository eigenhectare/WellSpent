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
                if let session = model.session(id: route.sessionID),
                    let endAt = session.endAt,
                    let project = model.project(id: session.projectID)
                {
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
                            LabeledContent("Project", value: project.displayName)
                            LabeledContent("Start") {
                                Text(session.startAt, format: .dateTime.month().day().hour().minute().second())
                            }
                            LabeledContent("End") {
                                Text(endAt, format: .dateTime.month().day().hour().minute().second())
                            }
                            LabeledContent(
                                "Exact duration",
                                value: DurationPresentation.exact(endAt.timeIntervalSince(session.startAt))
                            )
                            .accessibilityIdentifier("completed-session-duration")
                        }

                        Section("Tags") {
                            SessionTagPicker(
                                tags: model.selectableSessionTags(sessionID: session.id),
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
                        note = session.note ?? ""
                        selectedTagIDs = Set(session.tags.map(\.tagID))
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
                }
            }
        }
        .interactiveDismissDisabled(false)
        .accessibilityIdentifier("session-completion-screen")
    }
}
