import Foundation
import XCTest

final class SpikeProtocolTests: XCTestCase {
    func testEnvelopeDigestIsStableAndRoundTrips() throws {
        let payload = makeStartPayload(sequence: 7)
        let first = try SpikeMutationEnvelope(payload: payload)
        let second = try SpikeMutationEnvelope(payload: payload)

        XCTAssertEqual(first.payloadDigest, second.payloadDigest)
        XCTAssertTrue(first.hasValidDigest)

        let decoded = try SpikeCodec.decode(
            SpikeMutationEnvelope.self,
            from: SpikeCodec.encode(first)
        )
        XCTAssertEqual(decoded, first)
        XCTAssertTrue(decoded.hasValidDigest)
    }

    func testPersistentStateRoundTripsWithoutDroppingOutbox() throws {
        let fixtureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WCSpikeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }
        let store = try SpikeStateStore(
            stateURL: fixtureDirectory.appendingPathComponent("state.json")
        )
        var state = SpikePersistentState.empty(
            originDeviceID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        _ = try SpikeWatchReducer.makeNextMutation(
            state: &state,
            now: Date(timeIntervalSince1970: 1_800_000_010),
            timeZoneID: "UTC",
            makeUUID: deterministicUUIDProvider()
        )

        try store.save(state)
        let reopened = try XCTUnwrap(store.load())

        XCTAssertEqual(reopened, state)
        XCTAssertEqual(reopened.outbox.count, 1)
        XCTAssertEqual(reopened.localRunState, .running)
    }

    func testPhonePersistsThenAppliesMutationIdempotently() throws {
        var watch = SpikePersistentState.empty(
            originDeviceID: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let envelope = try SpikeWatchReducer.makeNextMutation(
            state: &watch,
            now: Date(timeIntervalSince1970: 1_800_000_010),
            timeZoneID: "UTC",
            makeUUID: deterministicUUIDProvider()
        )
        var phone = SpikePersistentState.empty(
            originDeviceID: UUID(uuidString: "30000000-0000-4000-8000-000000000001")!,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertNil(
            SpikePhoneReducer.receive(
                envelope: envelope,
                transport: .userInfo,
                state: &phone,
                now: Date(timeIntervalSince1970: 1_800_000_020)
            )
        )
        XCTAssertEqual(phone.inbox.first?.status, .received)
        XCTAssertEqual(phone.canonicalSnapshot.canonicalGeneration, 0)

        let acknowledgement = try XCTUnwrap(
            SpikePhoneReducer.processReceived(
                mutationID: envelope.payload.mutationID,
                state: &phone,
                now: Date(timeIntervalSince1970: 1_800_000_021),
                makeUUID: deterministicUUIDProvider()
            )
        )
        XCTAssertEqual(acknowledgement.outcome, .applied)
        XCTAssertEqual(phone.canonicalSnapshot.canonicalGeneration, 1)

        let duplicateAcknowledgement = SpikePhoneReducer.receive(
            envelope: envelope,
            transport: .message,
            state: &phone,
            now: Date(timeIntervalSince1970: 1_800_000_030)
        )
        XCTAssertEqual(duplicateAcknowledgement, acknowledgement)
        XCTAssertEqual(phone.canonicalSnapshot.canonicalGeneration, 1)
        XCTAssertEqual(phone.inbox.count, 1)
    }

    func testOutOfOrderSuccessorWaitsForPersistedPredecessor() throws {
        var watch = SpikePersistentState.empty(
            originDeviceID: UUID(uuidString: "40000000-0000-4000-8000-000000000001")!,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let provider = deterministicUUIDProvider()
        let start = try SpikeWatchReducer.makeNextMutation(
            state: &watch,
            now: Date(timeIntervalSince1970: 1_800_000_010),
            timeZoneID: "UTC",
            makeUUID: provider
        )
        let pause = try SpikeWatchReducer.makeNextMutation(
            state: &watch,
            now: Date(timeIntervalSince1970: 1_800_000_020),
            timeZoneID: "UTC",
            makeUUID: provider
        )
        var phone = SpikePersistentState.empty(
            originDeviceID: UUID(uuidString: "50000000-0000-4000-8000-000000000001")!,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        _ = SpikePhoneReducer.receive(
            envelope: pause,
            transport: .message,
            state: &phone,
            now: Date(timeIntervalSince1970: 1_800_000_030)
        )
        XCTAssertNil(
            SpikePhoneReducer.processReceived(
                mutationID: pause.payload.mutationID,
                state: &phone,
                now: Date(timeIntervalSince1970: 1_800_000_031),
                makeUUID: provider
            )
        )
        XCTAssertEqual(phone.inbox.first?.status, .received)

        _ = SpikePhoneReducer.receive(
            envelope: start,
            transport: .userInfo,
            state: &phone,
            now: Date(timeIntervalSince1970: 1_800_000_040)
        )
        let startAck = SpikePhoneReducer.processReceived(
            mutationID: start.payload.mutationID,
            state: &phone,
            now: Date(timeIntervalSince1970: 1_800_000_041),
            makeUUID: provider
        )
        let pauseAck = SpikePhoneReducer.processReceived(
            mutationID: pause.payload.mutationID,
            state: &phone,
            now: Date(timeIntervalSince1970: 1_800_000_042),
            makeUUID: provider
        )

        XCTAssertEqual(startAck?.outcome, .applied)
        XCTAssertEqual(pauseAck?.outcome, .applied)
        XCTAssertEqual(phone.canonicalSnapshot.canonicalGeneration, 2)
        XCTAssertEqual(phone.localRunState, .paused)
    }

    func testSnapshotNeverCompactsUnacknowledgedMutation() throws {
        var watch = SpikePersistentState.empty(now: Date(timeIntervalSince1970: 1_800_000_000))
        _ = try SpikeWatchReducer.makeNextMutation(
            state: &watch,
            now: Date(timeIntervalSince1970: 1_800_000_010),
            timeZoneID: "UTC",
            makeUUID: deterministicUUIDProvider()
        )
        let snapshot = SpikeSnapshot(
            protocolMajor: 1,
            protocolMinor: 0,
            schemaVersion: 1,
            snapshotID: UUID(),
            canonicalGeneration: 1,
            activeRunID: nil,
            activeRunRevision: nil,
            activeRunState: nil,
            openSegmentID: nil,
            headMutationID: nil,
            pendingConflictID: nil,
            producedAt: Date(timeIntervalSince1970: 1_800_000_020)
        )

        XCTAssertTrue(SpikeWatchReducer.install(snapshot: snapshot, state: &watch))
        XCTAssertEqual(watch.outbox.count, 1)
        XCTAssertEqual(watch.localRunState, .running)
    }

    private func makeStartPayload(sequence: UInt64) -> SpikeMutationPayload {
        SpikeMutationPayload(
            mutationID: UUID(uuidString: "60000000-0000-4000-8000-000000000001")!,
            originDeviceID: UUID(uuidString: "60000000-0000-4000-8000-000000000002")!,
            originSequence: sequence,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
            capturedTimeZoneID: "America/New_York",
            baseSnapshotID: nil,
            baseCanonicalGeneration: 0,
            predecessorMutationID: nil,
            observedRunID: nil,
            observedRunRevision: nil,
            action: SpikeAction(
                kind: .start,
                runID: UUID(uuidString: "60000000-0000-4000-8000-000000000003")!,
                segmentID: UUID(uuidString: "60000000-0000-4000-8000-000000000004")!,
                projectID: UUID(uuidString: "60000000-0000-4000-8000-000000000005")!
            )
        )
    }

    private func deterministicUUIDProvider() -> () -> UUID {
        var sequence: UInt64 = 1
        return {
            defer { sequence += 1 }
            let suffix = String(format: "%012llx", sequence)
            return UUID(uuidString: "70000000-0000-4000-8000-\(suffix)")!
        }
    }
}
