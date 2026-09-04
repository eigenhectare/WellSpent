import Foundation
import Testing
import WellSpentWatchContracts
import WellSpentWatchStore

@testable import WellSpentWatch

@MainActor
struct WatchTimerStartBoundaryTests {
    private let projectID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    private let runID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    private let segmentID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
    private let mutationID = UUID(uuidString: "50000000-0000-0000-0000-000000000001")!
    private let originID = UUID(uuidString: "60000000-0000-0000-0000-000000000001")!
    private let startedAt = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func startCapturesOneImmediateBoundaryAndPersistsExactGoal() throws {
        let store = try configuredStore()
        var identities = [runID, segmentID].makeIterator()
        let boundary = WatchTimerStartBoundary(
            now: { startedAt },
            timeZoneID: { "America/New_York" },
            makeUUID: { identities.next()! }
        )

        let commit = try boundary.start(
            WatchStartRequest(project: project, durationGoalSeconds: 1_800)
        ) { action, capturedAt, timeZoneID in
            try store.performLocalCommand(
                action,
                capturedAt: capturedAt,
                timeZoneID: timeZoneID
            )
        }

        #expect(commit.mutation.mutationID == mutationID)
        #expect(commit.mutation.capturedAt == startedAt)
        #expect(commit.mutation.capturedTimeZoneID == "America/New_York")
        #expect(commit.projection.activeRun?.id == runID)
        #expect(commit.projection.activeRun?.durationGoalSeconds == 1_800)
        #expect(commit.projection.activeRun?.startedAt == startedAt)
        #expect(commit.projection.activeRunSegments.first?.id == segmentID)
        #expect(commit.projection.activeRunSegments.first?.startedAt == startedAt)
        #expect(try store.state().pendingMutationCount == 1)
    }

    @Test
    func rapidRepeatedStartCannotCreateASecondRunOrOutboxEntry() throws {
        let store = try configuredStore()
        var identities = [runID, segmentID, UUID(), UUID()].makeIterator()
        let boundary = WatchTimerStartBoundary(
            now: { startedAt },
            timeZoneID: { "UTC" },
            makeUUID: { identities.next()! }
        )
        let persist: WatchTimerStartBoundary.Persist = { action, capturedAt, timeZoneID in
            try store.performLocalCommand(
                action,
                capturedAt: capturedAt,
                timeZoneID: timeZoneID
            )
        }

        _ = try boundary.start(WatchStartRequest(project: project, durationGoalSeconds: nil), persist: persist)
        #expect(throws: WatchStoreError.commandInvalid) {
            try boundary.start(
                WatchStartRequest(project: project, durationGoalSeconds: nil),
                persist: persist
            )
        }

        let state = try store.state()
        #expect(state.projection.activeRun?.id == runID)
        #expect(state.projection.activeRunSegments.count == 1)
        #expect(state.pendingMutationCount == 1)
    }

    @Test
    func persistenceFailureDoesNotReportACommit() {
        struct InjectedFailure: Error {}
        var persistWasCalled = false
        let boundary = WatchTimerStartBoundary(
            now: { startedAt },
            timeZoneID: { "UTC" },
            makeUUID: UUID.init
        )

        #expect(throws: InjectedFailure.self) {
            try boundary.start(
                WatchStartRequest(project: project, durationGoalSeconds: nil)
            ) { _, _, _ in
                persistWasCalled = true
                throw InjectedFailure()
            }
        }
        #expect(persistWasCalled)
    }

    private var project: ProjectSnapshot {
        ProjectSnapshot(
            id: projectID,
            workspaceID: nil,
            name: "Client Launch",
            colorToken: "purple",
            symbolName: "🚀"
        )
    }

    private func configuredStore() throws -> WellSpentWatchStore {
        let store = try WellSpentWatchStore.makeEphemeral(
            originDeviceID: originID,
            uuidFactory: {
                // The first local command receives this deterministic mutation identity.
                mutationID
            },
            now: { startedAt }
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
            projects: [project],
            tags: [],
            tombstones: [],
            activeRun: nil,
            activeRunSegments: [],
            recentlyEndedRun: nil,
            recentlyEndedRunSegments: [],
            totals: TimerTotalsSnapshot(
                todaySeconds: 0,
                weekSeconds: 0,
                calculatedAt: startedAt,
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
}
