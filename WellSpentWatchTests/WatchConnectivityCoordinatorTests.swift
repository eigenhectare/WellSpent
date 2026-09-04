import Foundation
import WatchConnectivity
import WellSpentWatchContracts
import XCTest

@testable import WellSpentWatch
@testable import WellSpentWatchStore

@MainActor
final class WatchConnectivityCoordinatorTests: XCTestCase {
    private let originID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    private let projectID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
    private let runID = UUID(uuidString: "30000000-0000-4000-8000-000000000001")!
    private let segmentID = UUID(uuidString: "40000000-0000-4000-8000-000000000001")!
    private let snapshotID = UUID(uuidString: "50000000-0000-4000-8000-000000000001")!
    private let now = Date(timeIntervalSince1970: 2_000_000)

    func testOfflineMutationStaysPendingWhileDurableTransferIsQueued() throws {
        let store = try configuredStore()
        let commit = try store.performLocalCommand(
            .start(
                StartTimerAction(
                    runID: runID,
                    segmentID: segmentID,
                    projectID: projectID,
                    durationGoalSeconds: nil
                )
            ),
            capturedAt: now,
            timeZoneID: "UTC"
        )
        let session = FakeWatchSession()
        session.reachable = false
        let coordinator = WatchConnectivityCoordinator(
            store: store,
            session: session,
            now: { self.now }
        )
        coordinator.activate()
        coordinator.retryPendingTransfers()

        XCTAssertTrue(session.messages.isEmpty)
        XCTAssertEqual(packetKinds(in: session.userInfoPackets), [.mutation])
        XCTAssertEqual(try store.pendingOutbox().first?.mutationID, commit.mutation.mutationID)
        XCTAssertEqual(try store.pendingOutbox().first?.attemptCount, 1)
        XCTAssertEqual(coordinator.state, .available(reachable: false, pendingCount: 1))

        session.reachable = true
        coordinator.retryPendingTransfers()
        XCTAssertEqual(packetKinds(in: session.messages), [.mutation])
        XCTAssertEqual(try store.pendingOutbox().count, 1)
    }

    func testAcknowledgementCompactsOnlyMatchingMutation() throws {
        let store = try configuredStore()
        let commit = try store.performLocalCommand(
            .start(
                StartTimerAction(
                    runID: runID,
                    segmentID: segmentID,
                    projectID: projectID,
                    durationGoalSeconds: nil
                )
            ),
            capturedAt: now,
            timeZoneID: "UTC"
        )
        let session = FakeWatchSession()
        let coordinator = WatchConnectivityCoordinator(store: store, session: session)
        coordinator.activate()
        let acknowledgement = MutationAcknowledgement(
            acknowledgementID: UUID(),
            mutationID: commit.mutation.mutationID,
            originDeviceID: originID,
            originSequence: 1,
            outcome: .applied,
            canonicalSnapshotID: UUID(),
            canonicalGeneration: 2,
            conflictID: nil,
            reasonCode: .applied,
            acknowledgedAt: now
        )

        coordinator.receiveForTesting(
            kind: .acknowledgement,
            data: try ContractWireCodec.encodeCanonical(acknowledgement)
        )

        XCTAssertEqual(try store.pendingOutbox().count, 0)
        XCTAssertEqual(coordinator.state, .available(reachable: false, pendingCount: 0))
    }

    func testSnapshotQueuesReceiptAndPreservesNewerPendingProjection() throws {
        let store = try configuredStore()
        _ = try store.performLocalCommand(
            .start(
                StartTimerAction(
                    runID: runID,
                    segmentID: segmentID,
                    projectID: projectID,
                    durationGoalSeconds: nil
                )
            ),
            capturedAt: now,
            timeZoneID: "UTC"
        )
        let session = FakeWatchSession()
        let coordinator = WatchConnectivityCoordinator(store: store, session: session)
        coordinator.activate()
        let next = snapshot(
            id: UUID(uuidString: "50000000-0000-4000-8000-000000000002")!,
            generation: 2
        )

        coordinator.receiveForTesting(
            kind: .snapshot,
            data: try ContractWireCodec.encodeSnapshot(next)
        )

        let state = try store.state()
        XCTAssertEqual(state.projection.ledgerHead, next.ledgerHead)
        XCTAssertEqual(state.projection.activeRun?.id, runID)
        XCTAssertEqual(state.pendingMutationCount, 1)
        XCTAssertEqual(state.pendingSnapshotReceiptCount, 0)
        XCTAssertTrue(packetKinds(in: session.userInfoPackets).contains(.snapshotReceipt))
    }

    func testDuplicateSnapshotDoesNotCreateAnotherReceipt() throws {
        let store = try configuredStore()
        let session = FakeWatchSession()
        let coordinator = WatchConnectivityCoordinator(store: store, session: session)
        coordinator.activate()
        let original = snapshot(id: snapshotID, generation: 1)

        coordinator.receiveForTesting(
            kind: .snapshot,
            data: try ContractWireCodec.encodeSnapshot(original)
        )

        XCTAssertTrue(session.userInfoPackets.isEmpty)
        XCTAssertEqual(try store.state().pendingSnapshotReceiptCount, 0)
    }

    private func configuredStore() throws -> WellSpentWatchStore {
        let store = try WellSpentWatchStore.makeInMemory(
            originDeviceID: originID,
            now: { self.now }
        )
        _ = try store.installSnapshotData(
            ContractWireCodec.encodeSnapshot(snapshot(id: snapshotID, generation: 1)),
            contradictsPendingMutations: false
        )
        for receipt in try store.pendingSnapshotReceipts() {
            try store.compactSnapshotReceipt(receiptID: receipt.receiptID)
        }
        return store
    }

    private func snapshot(id: UUID, generation: UInt64) -> TimerSnapshotEnvelope {
        TimerSnapshotEnvelope(
            capabilities: ContractCapability.allCases,
            ledgerHead: TimerLedgerHead(
                snapshotID: id,
                canonicalGeneration: generation,
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
                    symbolName: nil
                )
            ],
            tags: [],
            tombstones: [],
            activeRun: nil,
            activeRunSegments: [],
            recentlyEndedRun: nil,
            recentlyEndedRunSegments: [],
            totals: TimerTotalsSnapshot(
                todaySeconds: 0,
                weekSeconds: 0,
                calculatedAt: now,
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
    }

    private func packetKinds(in packets: [[String: Any]]) -> [WatchConnectivityPayloadKind] {
        packets.compactMap { WatchConnectivityWire.decode($0)?.kind }
    }
}

@MainActor
private final class FakeWatchSession: WatchConnectivitySession {
    var activationState: WCSessionActivationState = .notActivated
    var reachable = false
    var isReachable: Bool { reachable }
    var hasContentPending: Bool { !outstandingUserInfoPackets.isEmpty }
    var outstandingUserInfoPackets: [[String: Any]] = []
    var messages: [[String: Any]] = []
    var userInfoPackets: [[String: Any]] = []

    func configure(delegate: any WCSessionDelegate) {}

    func activate() {
        activationState = .activated
    }

    func sendMessage(
        _ message: [String: Any],
        errorHandler: (@Sendable (any Error) -> Void)?
    ) {
        messages.append(message)
    }

    func queueUserInfo(_ userInfo: [String: Any]) {
        userInfoPackets.append(userInfo)
        outstandingUserInfoPackets.append(userInfo)
    }
}
