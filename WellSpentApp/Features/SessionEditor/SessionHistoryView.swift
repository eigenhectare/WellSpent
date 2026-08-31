import SwiftUI

struct SessionHistoryView: View {
    @ObservedObject var model: WellSpentAppModel
    @State private var showsNewSession = false

    var body: some View {
        List {
            if model.sessions.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "clock",
                    description: Text("Stopped timers and manual sessions appear here.")
                )
            } else {
                ForEach(model.sessions.sorted { $0.startAt > $1.startAt }) { session in
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
