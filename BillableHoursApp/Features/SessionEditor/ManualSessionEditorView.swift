import SwiftUI

struct ManualSessionEditorView: View {
    @ObservedObject var model: BillableHoursAppModel
    let sessionID: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var projectID: UUID?
    @State private var startAt: Date
    @State private var endAt: Date
    @State private var note: String
    @State private var selectedTagIDs: Set<UUID>
    @State private var validationMessage: String?
    @State private var pendingOverlapSave = false

    init(model: BillableHoursAppModel, sessionID: UUID?) {
        self.model = model
        self.sessionID = sessionID
        let existing = sessionID.flatMap { model.session(id: $0) }
        let initialEnd = existing?.endAt ?? Date.now
        _projectID = State(
            initialValue: existing?.projectID
                ?? model.activeProjects.first?.id
                ?? model.projects.first?.id
        )
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if existing == nil, arguments.contains("UITEST_PREFILL_INVALID_SESSION") {
                _startAt = State(initialValue: initialEnd)
                _endAt = State(initialValue: initialEnd.addingTimeInterval(-3_600))
            } else if existing == nil, arguments.contains("UITEST_PREFILL_OVERLAP") {
                let interval = BillableHoursUITestBootstrap.overlapFixtureIntervals(
                    referenceDate: initialEnd
                ).manual
                _startAt = State(initialValue: interval.start)
                _endAt = State(initialValue: interval.end)
            } else {
                _startAt = State(
                    initialValue: existing?.startAt ?? initialEnd.addingTimeInterval(-3_600)
                )
                _endAt = State(initialValue: initialEnd)
            }
        #else
            _startAt = State(initialValue: existing?.startAt ?? initialEnd.addingTimeInterval(-3_600))
            _endAt = State(initialValue: initialEnd)
        #endif
        _note = State(initialValue: existing?.note ?? "")
        _selectedTagIDs = State(initialValue: Set(existing?.tags.map(\.tagID) ?? []))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    Menu {
                        ForEach(model.projects) { project in
                            Button(projectDisplayName(project)) {
                                projectID = project.id
                            }
                        }
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            Text(selectedProjectDisplayName)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Project")
                    .accessibilityValue(selectedProjectDisplayName)
                    .accessibilityIdentifier("session-project-picker")
                    .tint(.primary)
                }

                Section("Exact times") {
                    DatePicker("Start", selection: $startAt)
                        .accessibilityIdentifier("session-start")
                    DatePicker("End", selection: $endAt)
                        .accessibilityIdentifier("session-end")
                    if endAt > startAt {
                        LabeledContent(
                            "Duration",
                            value: DurationPresentation.exact(endAt.timeIntervalSince(startAt))
                        )
                    }
                }

                Section("Optional note") {
                    TextEditor(text: $note)
                        .frame(minHeight: 120)
                        .accessibilityIdentifier("session-note")
                }

                Section("Tags") {
                    SessionTagPicker(
                        tags: model.selectableSessionTags(sessionID: sessionID),
                        selectedTagIDs: $selectedTagIDs
                    )
                }
                .accessibilityIdentifier("session-tags")

                if let validationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("session-validation-error")
                    }
                }

                Section {
                    Text(
                        "Overlaps are allowed. If one is found, both sessions will remain and both count fully in reports."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(sessionID == nil ? "Add Session" : "Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("cancel-session-editor")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: validateAndSave)
                        .disabled(projectID == nil)
                        .accessibilityIdentifier("save-session")
                }
            }
            .alert("Overlap Detected", isPresented: $pendingOverlapSave) {
                Button("Save Anyway", action: commit)
                    .accessibilityIdentifier("save-overlapping-session")
                Button("Review", role: .cancel) {}
            } message: {
                Text(
                    "This session overlaps another record. Both will be visibly marked and fully included in report totals."
                )
            }
        }
        .accessibilityIdentifier("manual-session-editor")
    }

    private func validateAndSave() {
        validationMessage = nil
        guard let projectID else { return }
        do {
            let warnings = try model.overlapWarnings(
                projectID: projectID,
                startAt: startAt,
                endAt: endAt,
                excludingSessionID: sessionID
            )
            if warnings.isEmpty {
                commit()
            } else {
                pendingOverlapSave = true
            }
        } catch SessionCommandError.endMustFollowStart {
            validationMessage = "End time must be later than start time."
        } catch SessionCommandError.startIsInFuture {
            validationMessage = "Start time cannot be in the future."
        } catch SessionCommandError.endIsInFuture {
            validationMessage = "End time cannot be in the future."
        } catch {
            validationMessage = "Check the project and timestamps, then try again."
        }
    }

    private func commit() {
        guard let projectID else { return }
        let didSave: Bool
        if let sessionID {
            didSave = model.editCompletedSession(
                sessionID: sessionID,
                projectID: projectID,
                startAt: startAt,
                endAt: endAt,
                note: note,
                tagIDs: selectedTagIDs
            )
        } else {
            didSave = model.createManualSession(
                projectID: projectID,
                startAt: startAt,
                endAt: endAt,
                note: note,
                tagIDs: selectedTagIDs
            )
        }
        if didSave { dismiss() }
    }

    private var selectedProjectDisplayName: String {
        guard let projectID,
            let project = model.project(id: projectID)
        else {
            return "Choose a project"
        }
        return projectDisplayName(project)
    }

    private func projectDisplayName(_ project: ProjectSnapshot) -> String {
        project.status == .archived
            ? "\(project.displayName) — Archived"
            : project.displayName
    }
}

struct ActiveSessionEditorView: View {
    @ObservedObject var model: BillableHoursAppModel
    let sessionID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var startAt: Date
    @State private var note: String

    init(model: BillableHoursAppModel, sessionID: UUID) {
        self.model = model
        self.sessionID = sessionID
        let session = model.session(id: sessionID)
        _startAt = State(initialValue: session?.startAt ?? .now)
        _note = State(initialValue: session?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Active session") {
                    DatePicker("Start", selection: $startAt, in: ...Date.now)
                    TextEditor(text: $note)
                        .frame(minHeight: 120)
                }
                Section {
                    Text("An active session has no end time. Stop it from Track when work is complete.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Active Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if model.editActiveSession(sessionID: sessionID, startAt: startAt, note: note) {
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}
