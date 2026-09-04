import SwiftUI

struct SessionHistoryView: View {
    @ObservedObject var model: WellSpentAppModel
    @State private var showsNewSession = false

    var body: some View {
        List {
            if historyItems.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "clock",
                    description: Text("Stopped timers and manual sessions appear here.")
                )
            } else {
                ForEach(historyItems) { item in
                    switch item {
                    case .run(let run):
                        NavigationLink {
                            TimerRunReviewView(model: model, runID: run.id)
                        } label: {
                            TimerRunHistoryRow(
                                run: run,
                                project: model.project(id: run.projectID),
                                isWatchOrigin: model.isWatchOrigin(run),
                                overlaps: run.segments.contains {
                                    model.overlappingSessionIDs.contains($0.id)
                                }
                            )
                        }
                        .accessibilityIdentifier("session-row-\(run.id.uuidString)")
                    case .manual(let session):
                        NavigationLink {
                            SessionReviewView(model: model, sessionID: session.id)
                        } label: {
                            SessionHistoryRow(
                                session: session,
                                project: model.project(id: session.projectID),
                                overlaps: model.overlappingSessionIDs.contains(session.id)
                            )
                        }
                        .accessibilityIdentifier("session-row-\(session.id.uuidString)")
                    }
                }
            }
        }
        .navigationTitle("Session History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsNewSession = true
                } label: {
                    Label("Add Session", systemImage: "plus")
                }
                .disabled(model.projects.isEmpty)
                .accessibilityIdentifier("add-manual-session")
            }
        }
        .sheet(isPresented: $showsNewSession) {
            ManualSessionEditorView(model: model, sessionID: nil)
        }
    }

    private var historyItems: [SessionHistoryItem] {
        let runs = model.runs.map(SessionHistoryItem.run)
        let manual = model.sessions.filter { $0.source == .manual }.map(SessionHistoryItem.manual)
        return (runs + manual).sorted { $0.startAt > $1.startAt }
    }
}

private enum SessionHistoryItem: Identifiable {
    case run(TimerRunSnapshot)
    case manual(TimeSessionSnapshot)

    var id: UUID {
        switch self {
        case .run(let run): run.id
        case .manual(let session): session.id
        }
    }

    var startAt: Date {
        switch self {
        case .run(let run): run.startAt
        case .manual(let session): session.startAt
        }
    }
}

private struct TimerRunHistoryRow: View {
    let run: TimerRunSnapshot
    let project: ProjectSnapshot?
    let isWatchOrigin: Bool
    let overlaps: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 5) {
                Text(project?.displayName ?? "Unknown Project")
                    .font(.headline)
                Text(run.startAt, format: .dateTime.month().day().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(DurationPresentation.exact(run.countedDuration(at: context.date)))
                    .monospacedDigit()
                if isWatchOrigin {
                    Label("Apple Watch · \(run.segments.count) counted segments", systemImage: "applewatch")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !run.tags.isEmpty {
                    Text(run.tags.map(\.name).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                SessionFlagsView(
                    stateLabel: run.state == .running
                        ? "Running" : (run.state == .paused ? "Paused" : nil),
                    overlaps: overlaps
                )
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }
}

struct SessionHistoryRow: View {
    let session: TimeSessionSnapshot
    let project: ProjectSnapshot?
    let overlaps: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(project?.displayName ?? "Unknown Project")
                .font(.headline)
            Text(session.startAt, format: .dateTime.month().day().hour().minute())
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let endAt = session.endAt {
                Text(DurationPresentation.exact(endAt.timeIntervalSince(session.startAt)))
                    .monospacedDigit()
            } else {
                Text("Running from stored start time")
            }
            if !session.tags.isEmpty {
                Text(session.tags.map(\.name).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SessionFlagsView(isActive: session.endAt == nil, overlaps: overlaps)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
