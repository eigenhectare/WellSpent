import Foundation
import Testing
import WellSpentWatchContracts

@testable import WellSpentWatch
@testable import WellSpentWatchStore

@MainActor
struct WatchTimerControlBoundaryTests {
    private let originID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let projectAID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    private let projectBID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    private let runID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    private let segmentID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
    private let mutationID = UUID(uuidString: "50000000-0000-0000-0000-000000000001")!
    private let newRunID = UUID(uuidString: "60000000-0000-0000-0000-000000000001")!
    private let newSegmentID = UUID(uuidString: "70000000-0000-0000-0000-000000000001")!
    private let startedAt = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func pauseCapturesOneBoundaryAndARepeatedPauseCannotAppendMutation() throws {
        let store = try configuredStore(state: .running)
        let source = try #require(store.state().projection.activeRun)
        let segments = storeStateSegments(store)
        let boundaryAt = startedAt.addingTimeInterval(60)
        let boundary = WatchTimerControlBoundary(
            now: { boundaryAt },
            timeZoneID: { "America/New_York" }
        )

        let commit = try boundary.pause(
            run: source,
            segments: segments,
            persist: persist(to: store)
        )

        #expect(commit.mutation.capturedAt == boundaryAt)
        #expect(commit.mutation.capturedTimeZoneID == "America/New_York")
        #expect(commit.mutation.action == .pause(PauseTimerAction(runID: runID, openSegmentID: segmentID)))
        #expect(commit.projection.activeRun?.state == .paused)
        #expect(commit.projection.activeRunSegments.first?.endedAt == boundaryAt)

        #expect(throws: WatchStoreError.commandInvalid) {
            try boundary.pause(run: source, segments: segments, persist: persist(to: store))
        }
        #expect(try store.state().pendingMutationCount == 1)
        #expect(try store.state().projection.activeRunSegments.count == 1)
    }

    @Test
    func resumeOpensExactlyOneNewSegmentWithoutCountingPausedGap() throws {
        let store = try configuredStore(state: .paused)
        let source = try #require(store.state().projection.activeRun)
        let segments = storeStateSegments(store)
        let boundaryAt = startedAt.addingTimeInterval(120)
        let boundary = WatchTimerControlBoundary(
            now: { boundaryAt },
            timeZoneID: { "UTC" },
            makeUUID: { newSegmentID }
        )

        let commit = try boundary.resume(
            run: source,
            segments: segments,
            persist: persist(to: store)
        )

        #expect(commit.mutation.capturedAt == boundaryAt)
        #expect(commit.mutation.action == .resume(ResumeTimerAction(runID: runID, newSegmentID: newSegmentID)))
        #expect(commit.projection.activeRun?.state == .running)
        #expect(commit.projection.activeRunSegments.count == 2)
        #expect(commit.projection.activeRunSegments.last?.startedAt == boundaryAt)
        #expect(commit.projection.activeRunSegments.last?.endedAt == nil)
    }

    @Test
    func endClosesRunningSegmentButDoesNotChangePausedSegmentBoundary() throws {
        let runningStore = try configuredStore(state: .running)
        let running = try #require(runningStore.state().projection.activeRun)
        let runningEnd = startedAt.addingTimeInterval(90)
        let runningBoundary = WatchTimerControlBoundary(
            now: { runningEnd },
            timeZoneID: { "UTC" }
        )

        let runningCommit = try runningBoundary.end(
            run: running,
            segments: storeStateSegments(runningStore),
            persist: persist(to: runningStore)
        )
        #expect(runningCommit.projection.activeRun == nil)
        #expect(runningCommit.projection.recentlyEndedRun?.endedAt == runningEnd)
        #expect(runningCommit.projection.recentlyEndedRunSegments.first?.endedAt == runningEnd)

        let pausedStore = try configuredStore(state: .paused)
        let paused = try #require(pausedStore.state().projection.activeRun)
        let originalSegmentEnd = try #require(
            pausedStore.state().projection.activeRunSegments.first?.endedAt
        )
        let pausedEnd = startedAt.addingTimeInterval(150)
        let pausedBoundary = WatchTimerControlBoundary(
            now: { pausedEnd },
            timeZoneID: { "UTC" }
        )

        let pausedCommit = try pausedBoundary.end(
            run: paused,
            segments: storeStateSegments(pausedStore),
            persist: persist(to: pausedStore)
        )
        #expect(pausedCommit.projection.recentlyEndedRun?.endedAt == pausedEnd)
        #expect(pausedCommit.projection.recentlyEndedRunSegments.first?.endedAt == originalSegmentEnd)
    }

    @Test
    func switchEndsAndStartsAtOneExactBoundary() throws {
        let store = try configuredStore(state: .running)
        let source = try #require(store.state().projection.activeRun)
        var identities = [newRunID, newSegmentID].makeIterator()
        let boundaryAt = startedAt.addingTimeInterval(75)
        let boundary = WatchTimerControlBoundary(
            now: { boundaryAt },
            timeZoneID: { "America/Los_Angeles" },
            makeUUID: { identities.next()! }
        )

        let commit = try boundary.switchRun(
            run: source,
            segments: storeStateSegments(store),
            request: WatchStartRequest(project: projectB, durationGoalSeconds: 1_800),
            persist: persist(to: store)
        )

        #expect(commit.mutation.capturedAt == boundaryAt)
        #expect(commit.projection.recentlyEndedRun?.id == runID)
        #expect(commit.projection.recentlyEndedRun?.endedAt == boundaryAt)
        #expect(commit.projection.recentlyEndedRunSegments.last?.endedAt == boundaryAt)
        #expect(commit.projection.activeRun?.id == newRunID)
        #expect(commit.projection.activeRun?.projectID == projectBID)
        #expect(commit.projection.activeRun?.startedAt == boundaryAt)
        #expect(commit.projection.activeRun?.durationGoalSeconds == 1_800)
        #expect(
            commit.projection.activeRunSegments == [
                TimerSegmentSnapshot(
                    id: newSegmentID,
                    runID: newRunID,
                    workspaceID: nil,
                    projectID: projectBID,
                    startedAt: boundaryAt,
                    endedAt: nil,
                    startTimeZoneID: "America/Los_Angeles",
                    endTimeZoneID: nil,
                    revision: 1
                )
            ])
    }

    @Test
    func failedSwitchRollsBackOldRunSegmentAndOutboxTogether() throws {
        struct InjectedFailure: Error {}
        let store = try configuredStore(state: .running)
        let before = try store.state()
        store.setBeforeSaveForTesting { throw InjectedFailure() }
        var identities = [newRunID, newSegmentID].makeIterator()
        let boundary = WatchTimerControlBoundary(
            now: { startedAt.addingTimeInterval(75) },
            timeZoneID: { "UTC" },
            makeUUID: { identities.next()! }
        )

        #expect(throws: WatchStoreError.saveFailed) {
            try boundary.switchRun(
                run: #require(before.projection.activeRun),
                segments: before.projection.activeRunSegments,
                request: WatchStartRequest(project: projectB, durationGoalSeconds: nil),
                persist: persist(to: store)
            )
        }

        store.setBeforeSaveForTesting {}
        let after = try store.state()
        #expect(after.projection == before.projection)
        #expect(after.pendingMutationCount == 0)
        #expect(after.nextOriginSequence == before.nextOriginSequence)
    }

    @Test
    func failedPauseResumeAndEndRollBackThenRetryExactlyOnce() throws {
        struct InjectedFailure: Error {}
        let cases: [(WatchTimerControlOperation, TimerRunState)] = [
            (.pause, .running), (.resume, .paused), (.end, .running), (.end, .paused),
        ]
        for (operation, initialState) in cases {
            let store = try configuredStore(state: initialState)
            let before = try store.state()
            let beforeOutbox = try store.pendingOutbox()
            let run = try #require(before.projection.activeRun)
            let boundaryAt = startedAt.addingTimeInterval(120)
            let boundary = WatchTimerControlBoundary(
                now: { boundaryAt }, timeZoneID: { "UTC" }, makeUUID: { newSegmentID }
            )
            let attempt: () throws -> WatchCommandCommit = {
                switch operation {
                case .pause:
                    try boundary.pause(
                        run: run, segments: before.projection.activeRunSegments, persist: persist(to: store))
                case .resume:
                    try boundary.resume(
                        run: run, segments: before.projection.activeRunSegments, persist: persist(to: store))
                case .end:
                    try boundary.end(
                        run: run, segments: before.projection.activeRunSegments, persist: persist(to: store))
                case .switchRun:
                    throw WatchTimerControlBoundaryError.invalidSwitchDestination
                }
            }
            store.setBeforeSaveForTesting { throw InjectedFailure() }
            #expect(throws: WatchStoreError.saveFailed) { try attempt() }
            #expect(try store.state() == before)
            #expect(try store.pendingOutbox() == beforeOutbox)

            store.setBeforeSaveForTesting {}
            let commit = try attempt()
            let after = try store.state()
            #expect(commit.mutation.capturedAt == boundaryAt)
            #expect(after.pendingMutationCount == before.pendingMutationCount + 1)
            #expect(after.nextOriginSequence == before.nextOriginSequence + 1)
            switch operation {
            case .pause:
                #expect(after.projection.activeRun?.state == .paused)
                #expect(after.projection.activeRunSegments.count == 1)
                #expect(after.projection.activeRunSegments[0].endedAt == boundaryAt)
            case .resume:
                #expect(after.projection.activeRun?.state == .running)
                #expect(after.projection.activeRunSegments.count == 2)
                #expect(after.projection.activeRunSegments[0] == before.projection.activeRunSegments[0])
                #expect(after.projection.activeRunSegments[1].startedAt == boundaryAt)
            case .end:
                #expect(after.projection.activeRun == nil)
                #expect(after.projection.recentlyEndedRun?.endedAt == boundaryAt)
                #expect(after.projection.recentlyEndedRunSegments.count == 1)
                #expect(
                    after.projection.recentlyEndedRunSegments[0].endedAt
                        == (initialState == .paused ? before.projection.activeRunSegments[0].endedAt : boundaryAt))
            case .switchRun: break
            }
        }
    }

    @Test
    func invalidSameProjectSwitchNeverCallsPersistence() throws {
        let store = try configuredStore(state: .running)
        let source = try #require(store.state().projection.activeRun)
        var didPersist = false
        let boundary = WatchTimerControlBoundary()

        #expect(throws: WatchTimerControlBoundaryError.invalidSwitchDestination) {
            try boundary.switchRun(
                run: source,
                segments: storeStateSegments(store),
                request: WatchStartRequest(project: projectA, durationGoalSeconds: nil)
            ) { _, _, _ in
                didPersist = true
                throw WatchTimerControlBoundaryError.invalidRunState
            }
        }
        #expect(!didPersist)
    }

    private var projectA: ProjectSnapshot {
        ProjectSnapshot(
            id: projectAID,
            workspaceID: nil,
            name: "Client Launch",
            colorToken: "purple",
            symbolName: "🚀"
        )
    }

    private var projectB: ProjectSnapshot {
        ProjectSnapshot(
            id: projectBID,
            workspaceID: nil,
            name: "Admin & Operations",
            colorToken: "blue",
            symbolName: "gearshape.fill"
        )
    }

    private func configuredStore(state: TimerRunState) throws -> WellSpentWatchStore {
        let store = try WellSpentWatchStore.makeEphemeral(
            originDeviceID: originID,
            uuidFactory: { mutationID },
            now: { startedAt }
        )
        let segmentEnd = state == .paused ? startedAt.addingTimeInterval(45) : nil
        let run = TimerRunSnapshot(
            id: runID,
            workspaceID: nil,
            projectID: projectAID,
            state: state,
            startedAt: startedAt,
            endedAt: nil,
            startTimeZoneID: "UTC",
            endTimeZoneID: nil,
            durationGoalSeconds: nil,
            normalizedNote: nil,
            tagIDs: [],
            originDeviceID: originID,
            revision: 1,
            lastAppliedMutationID: nil,
            createdAt: startedAt,
            updatedAt: segmentEnd ?? startedAt,
            updatedTimeZoneID: "UTC"
        )
        let segment = TimerSegmentSnapshot(
            id: segmentID,
            runID: runID,
            workspaceID: nil,
            projectID: projectAID,
            startedAt: startedAt,
            endedAt: segmentEnd,
            startTimeZoneID: "UTC",
            endTimeZoneID: segmentEnd == nil ? nil : "UTC",
            revision: segmentEnd == nil ? 1 : 2
        )
        let snapshot = TimerSnapshotEnvelope(
            capabilities: ContractCapability.allCases,
            ledgerHead: TimerLedgerHead(
                snapshotID: UUID(uuidString: "80000000-0000-0000-0000-000000000001")!,
                canonicalGeneration: 1,
                activeRunID: runID,
                activeRunRevision: 1,
                headMutationID: nil
            ),
            projects: [projectA, projectB],
            tags: [],
            tombstones: [],
            activeRun: run,
            activeRunSegments: [segment],
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

    private func persist(to store: WellSpentWatchStore) -> WatchTimerControlBoundary.Persist {
        { action, capturedAt, timeZoneID in
            try store.performLocalCommand(
                action,
                capturedAt: capturedAt,
                timeZoneID: timeZoneID
            )
        }
    }

    private func storeStateSegments(_ store: WellSpentWatchStore) -> [TimerSegmentSnapshot] {
        (try? store.state().projection.activeRunSegments) ?? []
    }
}
