import Foundation
import Testing
import WellSpentWatchContracts

@testable import WellSpentWatch
@testable import WellSpentWatchStore

@MainActor
struct WatchTimerAnnotationBoundaryTests {
    private let originID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let projectID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    private let runID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    private let segmentID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
    private let mutationID = UUID(uuidString: "50000000-0000-0000-0000-000000000001")!
    private let activeTagID = UUID(uuidString: "60000000-0000-0000-0000-000000000001")!
    private let secondTagID = UUID(uuidString: "60000000-0000-0000-0000-000000000002")!
    private let historicalTagID = UUID(uuidString: "60000000-0000-0000-0000-000000000003")!
    private let startedAt = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func saveNormalizesNoteSortsTagsAndCapturesOneBoundary() throws {
        let store = try configuredStore()
        let state = try store.state()
        let savedAt = startedAt.addingTimeInterval(240)
        let boundary = WatchTimerAnnotationBoundary(
            now: { savedAt },
            timeZoneID: { "America/New_York" }
        )

        let commit = try boundary.save(
            run: #require(state.projection.recentlyEndedRun),
            draft: WatchTimerAnnotationDraft(
                note: "  Prepared court filing  \n",
                tagIDs: [secondTagID, activeTagID]
            ),
            availableTags: state.projection.tags,
            persist: persist(to: store)
        )

        #expect(commit.mutation.capturedAt == savedAt)
        #expect(commit.mutation.capturedTimeZoneID == "America/New_York")
        #expect(
            commit.mutation.action
                == .annotate(
                    AnnotateTimerAction(
                        runID: runID,
                        normalizedNote: "Prepared court filing",
                        tagIDs: [activeTagID, secondTagID]
                    )
                )
        )
        #expect(commit.projection.recentlyEndedRun?.state == .ended)
        #expect(commit.projection.recentlyEndedRun?.endedAt == startedAt.addingTimeInterval(180))
        #expect(commit.projection.recentlyEndedRun?.normalizedNote == "Prepared court filing")
        #expect(commit.projection.recentlyEndedRun?.tagIDs == [activeTagID, secondTagID])
        #expect(commit.projection.recentlyEndedRunSegments == state.projection.recentlyEndedRunSegments)
        #expect(try store.state().pendingMutationCount == 1)
    }

    @Test
    func whitespaceOnlyNoteClearsTheSavedNote() throws {
        let store = try configuredStore(note: "Existing note")
        let state = try store.state()
        let commit = try WatchTimerAnnotationBoundary().save(
            run: #require(state.projection.recentlyEndedRun),
            draft: WatchTimerAnnotationDraft(note: " \n ", tagIDs: []),
            availableTags: state.projection.tags,
            persist: persist(to: store)
        )

        #expect(commit.projection.recentlyEndedRun?.normalizedNote == nil)
        #expect(commit.projection.recentlyEndedRun?.state == .ended)
    }

    @Test
    func noteOnlyEditPreservesAnAssignedHistoricalTag() throws {
        let store = try configuredStore(tagIDs: [historicalTagID])
        let state = try store.state()
        let commit = try WatchTimerAnnotationBoundary().save(
            run: #require(state.projection.recentlyEndedRun),
            draft: WatchTimerAnnotationDraft(
                note: "Follow-up",
                tagIDs: [historicalTagID]
            ),
            availableTags: state.projection.tags,
            persist: persist(to: store)
        )

        #expect(commit.projection.recentlyEndedRun?.tagIDs == [historicalTagID])
        #expect(commit.projection.recentlyEndedRun?.normalizedNote == "Follow-up")
    }

    @Test
    func invalidStateUnknownTagOversizedAndUnchangedDraftsNeverPersist() throws {
        let store = try configuredStore()
        let ended = try #require(store.state().projection.recentlyEndedRun)
        var calls = 0
        let persist: WatchTimerAnnotationBoundary.Persist = { _, _, _ in
            calls += 1
            throw WatchStoreError.saveFailed
        }
        let boundary = WatchTimerAnnotationBoundary()
        let running = rebuild(ended, state: .running, endedAt: nil)

        #expect(throws: WatchTimerAnnotationBoundaryError.invalidRunState) {
            try boundary.save(
                run: running,
                draft: WatchTimerAnnotationDraft(note: "Note", tagIDs: []),
                availableTags: [],
                persist: persist
            )
        }
        #expect(throws: WatchTimerAnnotationBoundaryError.invalidTagSelection) {
            try boundary.save(
                run: ended,
                draft: WatchTimerAnnotationDraft(note: "Note", tagIDs: [UUID()]),
                availableTags: [],
                persist: persist
            )
        }
        #expect(throws: WatchTimerAnnotationBoundaryError.noteTooLong) {
            try boundary.save(
                run: ended,
                draft: WatchTimerAnnotationDraft(
                    note: String(repeating: "x", count: 1_001),
                    tagIDs: []
                ),
                availableTags: [],
                persist: persist
            )
        }
        #expect(throws: WatchTimerAnnotationBoundaryError.unchanged) {
            try boundary.save(
                run: ended,
                draft: WatchTimerAnnotationDraft(note: "", tagIDs: []),
                availableTags: [],
                persist: persist
            )
        }
        #expect(calls == 0)
    }

    @Test
    func saveFailureRollsBackAnnotationAndOutboxTogether() throws {
        struct InjectedFailure: Error {}
        let store = try configuredStore()
        let before = try store.state()
        store.setBeforeSaveForTesting { throw InjectedFailure() }

        #expect(throws: WatchStoreError.saveFailed) {
            try WatchTimerAnnotationBoundary().save(
                run: #require(before.projection.recentlyEndedRun),
                draft: WatchTimerAnnotationDraft(note: "Unsaved", tagIDs: [activeTagID]),
                availableTags: before.projection.tags,
                persist: persist(to: store)
            )
        }

        store.setBeforeSaveForTesting {}
        let after = try store.state()
        #expect(after.projection == before.projection)
        #expect(after.pendingMutationCount == 0)
        #expect(after.nextOriginSequence == before.nextOriginSequence)
    }

    private func configuredStore(
        note: String? = nil,
        tagIDs: [UUID] = []
    ) throws -> WellSpentWatchStore {
        let store = try WellSpentWatchStore.makeEphemeral(
            originDeviceID: originID,
            uuidFactory: { mutationID },
            now: { startedAt }
        )
        let endedAt = startedAt.addingTimeInterval(180)
        let run = TimerRunSnapshot(
            id: runID,
            workspaceID: nil,
            projectID: projectID,
            state: .ended,
            startedAt: startedAt,
            endedAt: endedAt,
            startTimeZoneID: "UTC",
            endTimeZoneID: "UTC",
            durationGoalSeconds: 120,
            normalizedNote: note,
            tagIDs: tagIDs,
            originDeviceID: originID,
            revision: 2,
            lastAppliedMutationID: nil,
            createdAt: startedAt,
            updatedAt: endedAt,
            updatedTimeZoneID: "UTC"
        )
        let segment = TimerSegmentSnapshot(
            id: segmentID,
            runID: runID,
            workspaceID: nil,
            projectID: projectID,
            startedAt: startedAt,
            endedAt: endedAt,
            startTimeZoneID: "UTC",
            endTimeZoneID: "UTC",
            revision: 2
        )
        let snapshot = TimerSnapshotEnvelope(
            capabilities: ContractCapability.allCases,
            ledgerHead: TimerLedgerHead(
                snapshotID: UUID(uuidString: "70000000-0000-0000-0000-000000000001")!,
                canonicalGeneration: 1,
                activeRunID: nil,
                activeRunRevision: nil,
                headMutationID: nil
            ),
            projects: [
                ProjectSnapshot(
                    id: projectID,
                    workspaceID: nil,
                    name: "Client",
                    colorToken: "blue",
                    symbolName: "briefcase.fill"
                )
            ],
            tags: [
                TagSnapshot(id: activeTagID, workspaceID: nil, name: "Billable"),
                TagSnapshot(id: secondTagID, workspaceID: nil, name: "Deep focus"),
            ],
            tombstones: [],
            activeRun: nil,
            activeRunSegments: [],
            recentlyEndedRun: run,
            recentlyEndedRunSegments: [segment],
            totals: TimerTotalsSnapshot(
                todaySeconds: 180,
                weekSeconds: 180,
                calculatedAt: endedAt,
                calendarTimeZoneID: "UTC"
            ),
            conflict: nil,
            recentAcknowledgements: [],
            receiptWatermarks: [],
            updateGuidance: MinimumAppVersionGuidance(
                minimumPhoneBuild: nil,
                minimumWatchBuild: nil,
                updateRequired: false
            )
        )
        _ = try store.installSnapshotData(
            ContractWireCodec.encodeSnapshot(snapshot),
            contradictsPendingMutations: false
        )
        if let receiptID = try store.pendingSnapshotReceipts().first?.receiptID {
            try store.compactSnapshotReceipt(receiptID: receiptID)
        }
        return store
    }

    private func persist(to store: WellSpentWatchStore) -> WatchTimerAnnotationBoundary.Persist {
        { action, capturedAt, timeZoneID in
            try store.performLocalCommand(
                action,
                capturedAt: capturedAt,
                timeZoneID: timeZoneID
            )
        }
    }

    private func rebuild(
        _ run: TimerRunSnapshot,
        state: TimerRunState,
        endedAt: Date?
    ) -> TimerRunSnapshot {
        TimerRunSnapshot(
            id: run.id,
            workspaceID: run.workspaceID,
            projectID: run.projectID,
            state: state,
            startedAt: run.startedAt,
            endedAt: endedAt,
            startTimeZoneID: run.startTimeZoneID,
            endTimeZoneID: endedAt == nil ? nil : run.endTimeZoneID,
            durationGoalSeconds: run.durationGoalSeconds,
            normalizedNote: run.normalizedNote,
            tagIDs: run.tagIDs,
            originDeviceID: run.originDeviceID,
            revision: run.revision,
            lastAppliedMutationID: run.lastAppliedMutationID,
            createdAt: run.createdAt,
            updatedAt: run.updatedAt,
            updatedTimeZoneID: run.updatedTimeZoneID
        )
    }
}
