import SwiftUI
import WellSpentWatchContracts

struct WatchConflictReviewView: View {
    @ObservedObject var model: WellSpentAppModel
    let conflictID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var selectedBranchID: UUID?
    @State private var watchEndAt = Date.now
    @State private var confirmation: PhoneConflictResolutionPlan?
    @State private var errorMessage: String?

    private var conflict: PhoneTimerConflict? {
        model.pendingWatchConflicts.first { $0.snapshot.conflictID == conflictID }
    }

    var body: some View {
        NavigationStack {
            List {
                if let conflict {
                    Section {
                        Label("Both versions are preserved", systemImage: "lock.shield")
                            .font(.headline)
                        Text(
                            "Changes arrived from different saved versions. Timer controls are unavailable until you choose a result. Saved running timers continue to count. Device origin does not decide which time is correct."
                        )
                        Text(
                            "Only the saved iPhone version currently counts in reports. Nothing is changed until you confirm."
                        )
                        .foregroundStyle(.secondary)
                    }
                    Section("Saved on iPhone") {
                        ForEach(model.runs.filter { conflict.snapshot.involvedRunIDs.contains($0.id) }) { run in
                            NavigationLink {
                                TimerRunReviewView(model: model, runID: run.id)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(model.project(id: run.projectID)?.displayName ?? "Unavailable project")
                                    Text(
                                        "\(run.state.rawValue.capitalized) · \(DurationPresentation.exact(run.countedDuration(at: watchEndAt)))"
                                    )
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    let branches = PhoneConflictResolutionPlan.latestBranches(conflict)
                    Section("Watch versions") {
                        ForEach(branches, id: \.mutation.mutationID) { branch in
                            if let projection = branch.projection {
                                Button {
                                    selectedBranchID = branch.mutation.mutationID
                                } label: {
                                    Label(
                                        branches.count == 1
                                            ? "Watch version" : "Watch version \(branch.mutation.originSequence)",
                                        systemImage: selectedBranchID == branch.mutation.mutationID
                                            ? "checkmark.circle.fill" : "circle"
                                    )
                                }
                                .accessibilityIdentifier("select-watch-conflict-branch")
                                ForEach(
                                    [projection.recentlyEndedRun, projection.activeRun].compactMap { $0 }
                                        .filter { conflict.snapshot.involvedRunIDs.contains($0.id) }, id: \.id
                                ) { run in
                                    ConflictRunDetails(
                                        run: run,
                                        segments: (projection.recentlyEndedRunSegments + projection.activeRunSegments)
                                            .filter { $0.runID == run.id },
                                        model: model, referenceDate: watchEndAt
                                    )
                                }
                            } else {
                                Text(
                                    "A Watch change is preserved in the audit but cannot be safely reconstructed. It cannot replace saved runs automatically."
                                )
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section {
                        DatePicker("End unfinished Watch runs at", selection: $watchEndAt, in: ...Date.now)
                        Text(
                            "Used only for Keep both. Paused gaps stay excluded. Review exact seconds on the confirmation screen."
                        )
                        .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Choose a result") {
                        ForEach(PhoneConflictChoice.allCases) { choice in
                            Button(choice.title) { prepare(choice, conflict: conflict) }
                                .disabled(
                                    model.isPerformingTimerCommand || (choice != .keepPhone && selectedBranchID == nil)
                                )
                                .accessibilityIdentifier("conflict-choice-\(choice.rawValue)")
                        }
                    }
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                } else {
                    ContentUnavailableView(
                        "Review complete", systemImage: "checkmark.circle",
                        description: Text("No pending conflict remains for this review."))
                }
            }
            .navigationTitle("Review Timer Versions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear {
                if let conflict {
                    selectedBranchID =
                        PhoneConflictResolutionPlan.latestBranches(conflict)
                        .first(where: { $0.projection != nil })?.mutation.mutationID
                }
            }
            .sheet(item: $confirmation) { plan in
                ConflictConfirmationView(model: model, plan: plan) { dismiss() }
            }
        }
        .accessibilityIdentifier("watch-conflict-review")
    }

    private func prepare(_ choice: PhoneConflictChoice, conflict: PhoneTimerConflict) {
        do {
            confirmation = try PhoneConflictResolutionPlan.make(
                conflict: conflict, runs: model.runs, choice: choice,
                branchID: selectedBranchID, at: .now, watchEndAt: watchEndAt,
                timeZoneID: TimeZone.current.identifier
            )
            errorMessage = nil
        } catch {
            errorMessage =
                "That result has invalid or overlapping boundaries within a run. Review the Watch end time or keep the saved iPhone version. Nothing was changed."
        }
    }
}

private struct ConflictConfirmationView: View {
    @ObservedObject var model: WellSpentAppModel
    let plan: PhoneConflictResolutionPlan
    let completed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Result") {
                    Text(plan.choice.title).font(.headline)
                    Text(plan.explanation).accessibilityIdentifier("conflict-result-explanation")
                    Text(
                        plan.payload.chosenActiveRunID == nil
                            ? "No timer will remain active." : "Exactly one timer will remain running or paused.")
                }
                Section("Retained iPhone runs") {
                    ForEach(model.runs.filter { plan.payload.retainedRunIDs.contains($0.id) }) { run in
                        Text(
                            "\(model.project(id: run.projectID)?.displayName ?? "Project") · \(run.state.rawValue.capitalized) · \(DurationPresentation.exact(run.countedDuration(at: plan.capturedAt)))"
                        )
                    }
                }
                ForEach(plan.payload.replacementRuns, id: \.id) { run in
                    Section("Saved Watch result") {
                        ConflictRunDetails(
                            run: run, segments: plan.payload.replacementSegments.filter { $0.runID == run.id },
                            model: model, referenceDate: plan.capturedAt)
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).accessibilityIdentifier("conflict-save-error") }
                }
                Section {
                    Button(model.isPerformingTimerCommand ? "Saving…" : "Confirm Resolution") {
                        Task {
                            errorMessage = await model.resolveWatchConflict(plan)
                            if errorMessage == nil {
                                dismiss()
                                completed()
                            }
                        }
                    }
                    .disabled(model.isPerformingTimerCommand)
                    .accessibilityIdentifier("confirm-conflict-resolution")
                }
            }
            .navigationTitle("Confirm Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(model.isPerformingTimerCommand)
                }
            }
        }
        .interactiveDismissDisabled(model.isPerformingTimerCommand)
    }
}

private struct ConflictRunDetails: View {
    let run: WellSpentWatchContracts.TimerRunSnapshot
    let segments: [TimerSegmentSnapshot]
    let model: WellSpentAppModel
    let referenceDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.project(id: run.projectID)?.displayName ?? "Unavailable project").font(.headline)
            Text(run.state.rawValue.capitalized)
            Text(
                "Counted: \(DurationPresentation.exact(segments.reduce(0) { $0 + ($1.endedAt ?? referenceDate).timeIntervalSince($1.startedAt) }))"
            )
            LabeledContent("Started") {
                Text(run.startedAt, format: .dateTime.year().month().day().hour().minute().second())
            }
            if let end = run.endedAt {
                LabeledContent("Ended") { Text(end, format: .dateTime.year().month().day().hour().minute().second()) }
            }
            if let note = run.normalizedNote { Text(note) }
            if !run.tagIDs.isEmpty {
                Text(
                    run.tagIDs.map { id in model.sessionTags.first { $0.id == id }?.name ?? "Archived tag" }.joined(
                        separator: ", "))
            }
            DisclosureGroup("\(segments.count) exact counted segments") {
                ForEach(segments, id: \.id) { segment in
                    VStack(alignment: .leading) {
                        Text(segment.startedAt, format: .dateTime.year().month().day().hour().minute().second())
                        if let end = segment.endedAt {
                            Text(end, format: .dateTime.year().month().day().hour().minute().second())
                        } else {
                            Text("Still counting")
                        }
                    }
                }
            }
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }
}
