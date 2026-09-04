import Foundation
import WellSpentWatchContracts
import WellSpentWatchStore

enum WatchTimerAnnotationBoundaryError: Error, Equatable {
    case invalidRunState
    case invalidTagSelection
    case noteTooLong
    case unchanged
}

struct WatchTimerAnnotationDraft: Equatable, Sendable {
    static let maximumNoteLength = 1_000

    let note: String
    let tagIDs: Set<UUID>

    var normalizedNote: String? {
        let normalized = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    var sortedTagIDs: [UUID] {
        tagIDs.sorted { $0.uuidString < $1.uuidString }
    }

    func differs(from run: TimerRunSnapshot) -> Bool {
        normalizedNote != run.normalizedNote
            || sortedTagIDs
                != run.tagIDs.sorted {
                    $0.uuidString < $1.uuidString
                }
    }
}

struct WatchTimerAnnotationFailure: Equatable, Identifiable {
    let runID: UUID
    let draft: WatchTimerAnnotationDraft

    var id: UUID { runID }
    let title = String(localized: "Couldn’t save changes")
    let message = String(localized: "Your run is still saved. The note and tags were not changed.")
}

/// Constructs one complete annotation mutation after the run is durably ended.
/// It has no SwiftUI, WatchKit, or transport dependency, so every Watch entry
/// point can share the same validation and local-first persistence boundary.
struct WatchTimerAnnotationBoundary {
    typealias Persist = (TimerMutationAction, Date, String) throws -> WatchCommandCommit

    private let now: () -> Date
    private let timeZoneID: () -> String

    init(
        now: @escaping () -> Date = Date.init,
        timeZoneID: @escaping () -> String = { TimeZone.autoupdatingCurrent.identifier }
    ) {
        self.now = now
        self.timeZoneID = timeZoneID
    }

    func save(
        run: TimerRunSnapshot,
        draft: WatchTimerAnnotationDraft,
        availableTags: [TagSnapshot],
        persist: Persist
    ) throws -> WatchCommandCommit {
        guard run.state == .ended, run.endedAt != nil else {
            throw WatchTimerAnnotationBoundaryError.invalidRunState
        }
        guard draft.normalizedNote?.count ?? 0 <= WatchTimerAnnotationDraft.maximumNoteLength else {
            throw WatchTimerAnnotationBoundaryError.noteTooLong
        }

        // Active catalog tags may be newly selected. IDs already assigned to
        // this run remain valid even after the iPhone archives the tag, which
        // keeps a note-only edit from silently erasing historical metadata.
        let allowedTagIDs = Set(availableTags.map(\.id)).union(run.tagIDs)
        guard draft.tagIDs.isSubset(of: allowedTagIDs) else {
            throw WatchTimerAnnotationBoundaryError.invalidTagSelection
        }
        guard draft.differs(from: run) else {
            throw WatchTimerAnnotationBoundaryError.unchanged
        }

        return try persist(
            .annotate(
                AnnotateTimerAction(
                    runID: run.id,
                    normalizedNote: draft.normalizedNote,
                    tagIDs: draft.sortedTagIDs
                )
            ),
            now(),
            timeZoneID()
        )
    }
}
