import Foundation
import SwiftData
import WellSpentWatchContracts

#if DEBUG
    @MainActor
    enum WatchCompanionUITestFixture {
        static let runID = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!
        static let originID = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!

        static func seed(context: ModelContext, arguments: [String], now: Date) throws {
            guard arguments.contains(where: { $0.hasPrefix("UITEST_SEED_WATCH_") }) else { return }
            let repository = SwiftDataTimerRunRepository(context: context)
            let commands = TimerRunCommandService(repository: repository, dependencies: .live)
            let store = PhoneWatchSyncStore(
                context: context, timerRepository: repository, timerCommands: commands, dependencies: .live)
            let base = try store.makeSnapshot().ledgerHead
            if arguments.contains("UITEST_SEED_WATCH_CONFLICT") {
                _ = try commands.start(
                    projectID: WellSpentUITestBootstrap.projectOneID, capturedAt: now.addingTimeInterval(-900))
            }
            let segmentID = UUID()
            let start = try TimerMutationEnvelope(
                mutationID: UUID(), originDeviceID: originID, originSequence: 1,
                capturedAt: now.addingTimeInterval(-720), capturedTimeZoneID: "UTC",
                baseSnapshotID: base.snapshotID, baseCanonicalGeneration: base.canonicalGeneration,
                predecessorMutationID: nil, observedRunID: nil, observedRunRevision: nil,
                action: .start(
                    StartTimerAction(
                        runID: runID, segmentID: segmentID,
                        projectID: WellSpentUITestBootstrap.projectTwoID, durationGoalSeconds: nil))
            )
            _ = try store.receiveMutationData(ContractWireCodec.encodeMutation(start))
            guard !arguments.contains("UITEST_SEED_WATCH_CONFLICT") else { return }
            let snapshot = try store.makeSnapshot()
            let pause = try TimerMutationEnvelope(
                mutationID: UUID(), originDeviceID: originID, originSequence: 2,
                capturedAt: now.addingTimeInterval(-120), capturedTimeZoneID: "UTC",
                baseSnapshotID: snapshot.ledgerHead.snapshotID,
                baseCanonicalGeneration: snapshot.ledgerHead.canonicalGeneration,
                predecessorMutationID: nil, observedRunID: runID, observedRunRevision: 1,
                action: .pause(PauseTimerAction(runID: runID, openSegmentID: segmentID))
            )
            _ = try store.receiveMutationData(ContractWireCodec.encodeMutation(pause))
            if arguments.contains("UITEST_SEED_WATCH_ENDED") {
                _ = try commands.resume(runID: runID, capturedAt: now.addingTimeInterval(-60))
                _ = try commands.end(runID: runID, capturedAt: now.addingTimeInterval(-1))
                _ = try commands.annotate(runID: runID, note: "Watch work", tagIDs: [])
            }
            _ = try store.makeSnapshot()
        }
    }
#endif
