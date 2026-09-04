import Darwin
import Foundation
import SwiftData
import WellSpentWatchContracts
import XCTest

@testable import WellSpentWatchStore

/// Accelerated, isolated storage workloads. These are not physical battery,
/// WidgetKit scheduling, network, or backup/restore measurements.
@MainActor
final class WatchResourceTests: XCTestCase {
    private let originID = UUID(uuidString: "10000000-0000-0000-0000-000000000025")!
    private let projectID = UUID(uuidString: "20000000-0000-0000-0000-000000000025")!
    private let snapshotID = UUID(uuidString: "50000000-0000-0000-0000-000000000025")!
    private let startAt = Date(timeIntervalSince1970: 1_800_000_000)

    func testOfflineCapacityRejectsWithoutEvictionAndSurvivesReopen() throws {
        let fixture = try ResourceStoreFixture()
        defer { fixture.remove() }
        var samples: [ResourceSample] = []
        defer { attach(samples) }
        var pending: [WatchOutboxItem] = []
        var expectedState: WatchStoreState?

        try autoreleasepool {
            let (store, container) = try open(fixture)
            try installSetup(on: store)
            samples.append(try sample("baseline", fixture, store, container))
            try enqueueSessions(on: store, count: WatchStoreLimits.maximumOutboxEntries / 4)
            pending = try store.pendingOutbox()
            expectedState = try store.state()
            XCTAssertEqual(pending.count, WatchStoreLimits.maximumOutboxEntries)
            XCTAssertEqual(pending.map(\.originSequence), Array(1...UInt64(pending.count)))
            let envelopes = try pending.map { try ContractWireCodec.decodeMutation($0.envelopeData) }
            XCTAssertNil(envelopes.first?.predecessorMutationID)
            for index in 1..<envelopes.count {
                XCTAssertEqual(envelopes[index].predecessorMutationID, envelopes[index - 1].mutationID)
            }

            XCTAssertThrowsError(try enqueueSessions(on: store, count: 1, offset: 32)) { error in
                XCTAssertEqual(error as? WatchStoreError, .localCapacityExceeded)
            }
            XCTAssertEqual(try store.pendingOutbox(), pending)
            XCTAssertEqual(try store.state(), expectedState)
            samples.append(try sample("offline-capacity-rejected-without-eviction", fixture, store, container))
        }

        try autoreleasepool {
            let (store, container) = try open(fixture)
            XCTAssertEqual(try store.pendingOutbox(), pending)
            XCTAssertEqual(try store.state(), expectedState)
            samples.append(try sample("capacity-reopened", fixture, store, container))
        }
    }

    func testRepeatedOfflineReconnectCyclesTrimAcknowledgementsAndMeasureStorage() throws {
        let fixture = try ResourceStoreFixture()
        defer { fixture.remove() }
        var samples: [ResourceSample] = []
        defer { attach(samples) }
        var allAcknowledgementIDs: [UUID] = []
        var expectedSequence: UInt64 = 1

        // 96 sessions in quarter-hour slots and 384 durable mutations.
        // Each offline batch and acknowledgement phase uses a recreated container.
        for cycle in 0..<12 {
            var pending: [WatchOutboxItem] = []
            var expectedProjection: WatchCachedProjection?
            try autoreleasepool {
                let (store, container) = try open(fixture)
                if cycle == 0 {
                    try installSetup(on: store)
                    samples.append(try sample("baseline", fixture, store, container))
                }
                XCTAssertEqual(try store.state().pendingMutationCount, 0)
                XCTAssertEqual(try store.state().nextOriginSequence, expectedSequence)
                try enqueueSessions(on: store, count: 8, offset: cycle * 8)
                pending = try store.pendingOutbox()
                expectedProjection = try store.state().projection
                XCTAssertEqual(pending.count, 32)
                XCTAssertEqual(pending.map(\.originSequence), Array(expectedSequence..<(expectedSequence + 32)))
                expectedSequence += 32
                samples.append(try sample("cycle-\(cycle + 1)-offline", fixture, store, container))
            }

            try autoreleasepool {
                let (store, container) = try open(fixture)
                XCTAssertEqual(try store.pendingOutbox(), pending)
                XCTAssertEqual(try store.state().projection, expectedProjection)
                let first = try XCTUnwrap(pending.first)
                for attempt in 1...3 {
                    try store.recordDeliveryAttempt(
                        mutationID: first.mutationID,
                        attemptedAt: startAt.addingTimeInterval(Double(attempt)), nextRetryAt: nil)
                }
                XCTAssertEqual(try store.pendingOutbox().first?.attemptCount, 3)
                XCTAssertEqual(try store.pendingOutbox().first?.envelopeData, first.envelopeData)

                for item in pending {
                    let acknowledgement = acknowledgement(for: item)
                    try store.receiveAcknowledgement(acknowledgement)
                    try store.receiveAcknowledgement(acknowledgement)
                    allAcknowledgementIDs.append(acknowledgement.acknowledgementID)
                }
                XCTAssertTrue(try store.pendingOutbox().isEmpty)
                XCTAssertEqual(try store.state().projection, expectedProjection)
                XCTAssertEqual(try store.state().nextOriginSequence, expectedSequence)
                let context = ModelContext(container)
                let retained = try context.fetch(FetchDescriptor<WatchAcknowledgementRecord>())
                XCTAssertEqual(
                    Set(retained.map(\.acknowledgementID)),
                    Set(allAcknowledgementIDs.suffix(WatchStoreLimits.maximumAcknowledgements)))
                XCTAssertEqual(try store.state().quarantinedMutationCount, 0)
                samples.append(try sample("cycle-\(cycle + 1)-acknowledged", fixture, store, container))
            }
        }

        try autoreleasepool {
            let (store, container) = try open(fixture)
            XCTAssertEqual(try store.state().originDeviceID, originID)
            XCTAssertEqual(try store.state().nextOriginSequence, 385)
            XCTAssertEqual(try store.state().pendingMutationCount, 0)
            XCTAssertEqual(try store.state().pendingSnapshotReceiptCount, 0)
            let retained = try ModelContext(container).fetch(FetchDescriptor<WatchAcknowledgementRecord>())
            XCTAssertEqual(retained.count, WatchStoreLimits.maximumAcknowledgements)
            XCTAssertEqual(
                Set(retained.map(\.acknowledgementID)),
                Set(allAcknowledgementIDs.suffix(WatchStoreLimits.maximumAcknowledgements)))
            samples.append(try sample("final-reopened", fixture, store, container))
        }
    }

    func testQuarantineRemainsByteExactWhenAcknowledgementHistoryIsTrimmed() throws {
        let fixture = try ResourceStoreFixture()
        defer { fixture.remove() }
        var samples: [ResourceSample] = []
        defer { attach(samples) }
        var quarantinedBytes: [UUID: Data] = [:]
        var quarantinedAcknowledgements: [UUID: Data] = [:]

        try autoreleasepool {
            let (store, container) = try open(fixture)
            try installSetup(on: store)
            samples.append(try sample("baseline", fixture, store, container))
            try enqueueSessions(on: store, count: WatchStoreLimits.maximumOutboxEntries / 4)
            let pending = try store.pendingOutbox()
            for item in pending.prefix(WatchStoreLimits.maximumQuarantineEntries) {
                let conflict = acknowledgement(for: item, outcome: .conflict)
                try store.receiveAcknowledgement(conflict)
                quarantinedBytes[item.mutationID] = item.envelopeData
                quarantinedAcknowledgements[item.mutationID] = try ContractWireCodec.encodeCanonical(conflict)
            }
            let next = pending[WatchStoreLimits.maximumQuarantineEntries]
            let beforeRejection = try store.pendingOutbox()
            XCTAssertThrowsError(try store.receiveAcknowledgement(acknowledgement(for: next, outcome: .conflict))) {
                error in
                XCTAssertEqual(error as? WatchStoreError, .localCapacityExceeded)
            }
            XCTAssertEqual(try store.pendingOutbox(), beforeRejection)
            XCTAssertEqual(try store.state().quarantinedMutationCount, WatchStoreLimits.maximumQuarantineEntries)
            samples.append(try sample("quarantine-capacity-preserves-pending", fixture, store, container))

            for item in beforeRejection { try store.receiveAcknowledgement(acknowledgement(for: item)) }
            // Late acknowledgements with no pending envelope are legal. They must
            // trim only acknowledgement history, never quarantined source bytes.
            for index in 0..<WatchStoreLimits.maximumAcknowledgements {
                try store.receiveAcknowledgement(
                    MutationAcknowledgement(
                        acknowledgementID: UUID(), mutationID: UUID(), originDeviceID: originID,
                        originSequence: UInt64(1_000 + index), outcome: .duplicate,
                        canonicalSnapshotID: snapshotID, canonicalGeneration: 10,
                        conflictID: nil, reasonCode: .duplicate,
                        acknowledgedAt: startAt.addingTimeInterval(Double(1_000 + index))))
            }
            XCTAssertTrue(try store.state().isBlocked)
            XCTAssertTrue(try store.pendingOutbox().isEmpty)
            samples.append(try sample("acknowledgements-trimmed-quarantine-retained", fixture, store, container))
        }

        try autoreleasepool {
            let (store, container) = try open(fixture)
            let context = ModelContext(container)
            let records = try context.fetch(FetchDescriptor<WatchQuarantineRecord>())
            XCTAssertEqual(records.count, WatchStoreLimits.maximumQuarantineEntries)
            for record in records {
                let mutationID = try XCTUnwrap(record.mutationID)
                XCTAssertEqual(record.envelopeData, quarantinedBytes[mutationID])
                XCTAssertEqual(record.acknowledgementData, quarantinedAcknowledgements[mutationID])
                let acknowledgement = try ContractWireCodec.decodeCanonical(
                    MutationAcknowledgement.self, from: XCTUnwrap(record.acknowledgementData))
                XCTAssertEqual(acknowledgement.mutationID, mutationID)
                XCTAssertEqual(acknowledgement.outcome, .conflict)
            }
            XCTAssertTrue(try store.state().isBlocked)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<WatchAcknowledgementRecord>()), 256)
            samples.append(try sample("quarantine-reopened-byte-exact", fixture, store, container))
        }
    }

    func testMultiHourElapsedProjectionDoesNotEnqueueWrites() throws {
        let fixture = try ResourceStoreFixture()
        defer { fixture.remove() }
        var samples: [ResourceSample] = []
        defer { attach(samples) }
        let (store, container) = try open(fixture)
        try installSetup(on: store)
        _ = try store.performLocalCommand(
            .start(
                StartTimerAction(runID: UUID(), segmentID: UUID(), projectID: projectID, durationGoalSeconds: 3_600)),
            capturedAt: startAt, timeZoneID: "UTC")
        let initialState = try store.state()
        let pending = try store.pendingOutbox()
        let initialFiles = try fixture.fileContents()
        var saveAttempts = 0
        store.setBeforeSaveForTesting { saveAttempts += 1 }
        samples.append(try sample("running-before-48-hour-projection", fixture, store, container))

        for minute in stride(from: 0, through: 48 * 60, by: 5) {
            let widget = try WatchWidgetSnapshotReader(container: container).read()
            XCTAssertEqual(widget.elapsed(at: startAt.addingTimeInterval(Double(minute * 60))), Double(minute * 60))
            XCTAssertEqual(try store.state(), initialState)
        }

        XCTAssertEqual(saveAttempts, 0)
        XCTAssertEqual(try store.pendingOutbox(), pending)
        XCTAssertEqual(try fixture.fileContents(), initialFiles)
        samples.append(try sample("running-after-48-hour-projection", fixture, store, container))
    }

    private func open(_ fixture: ResourceStoreFixture) throws -> (WellSpentWatchStore, ModelContainer) {
        let container = try WatchStorePersistence.makePersistentContainer(storeURL: fixture.storeURL)
        return (
            try WellSpentWatchStore(container: container, storeURL: fixture.storeURL, originDeviceID: originID),
            container
        )
    }

    private func installSetup(on store: WellSpentWatchStore) throws {
        let snapshot = TimerSnapshotEnvelope(
            capabilities: ContractCapability.allCases,
            ledgerHead: TimerLedgerHead(
                snapshotID: snapshotID, canonicalGeneration: 10, activeRunID: nil,
                activeRunRevision: nil, headMutationID: nil),
            projects: [
                ProjectSnapshot(
                    id: projectID, workspaceID: nil, name: "Resource Fixture", colorToken: nil, symbolName: nil)
            ],
            tags: [], tombstones: [], activeRun: nil, activeRunSegments: [],
            recentlyEndedRun: nil, recentlyEndedRunSegments: [],
            totals: TimerTotalsSnapshot(
                todaySeconds: 0, weekSeconds: 0, calculatedAt: startAt, calendarTimeZoneID: "UTC"),
            conflict: nil, recentAcknowledgements: [], receiptWatermarks: [],
            updateGuidance: MinimumAppVersionGuidance(
                minimumPhoneBuild: nil, minimumWatchBuild: nil, updateRequired: false))
        _ = try store.installSnapshotData(
            ContractWireCodec.encodeSnapshot(snapshot), contradictsPendingMutations: false)
        for receipt in try store.pendingSnapshotReceipts() {
            try store.compactSnapshotReceipt(receiptID: receipt.receiptID)
        }
    }

    private func enqueueSessions(on store: WellSpentWatchStore, count: Int, offset: Int = 0) throws {
        for index in 0..<count {
            let runID = UUID()
            let firstSegmentID = UUID()
            let resumedSegmentID = UUID()
            let actions: [TimerMutationAction] = [
                .start(
                    StartTimerAction(
                        runID: runID, segmentID: firstSegmentID, projectID: projectID, durationGoalSeconds: nil)),
                .pause(PauseTimerAction(runID: runID, openSegmentID: firstSegmentID)),
                .resume(ResumeTimerAction(runID: runID, newSegmentID: resumedSegmentID)),
                .end(EndTimerAction(runID: runID, openSegmentID: resumedSegmentID)),
            ]
            for (actionIndex, action) in actions.enumerated() {
                _ = try store.performLocalCommand(
                    action, capturedAt: startAt.addingTimeInterval(Double((offset + index) * 900 + actionIndex * 60)),
                    timeZoneID: "UTC")
            }
            let state = try store.state()
            XCTAssertEqual(state.projection.recentlyEndedRun?.id, runID)
            let elapsed = state.projection.recentlyEndedRunSegments.reduce(0.0) { total, segment in
                total + (segment.endedAt?.timeIntervalSince(segment.startedAt) ?? 0)
            }
            XCTAssertEqual(elapsed, 120)
        }
    }

    private func acknowledgement(for item: WatchOutboxItem, outcome: MutationOutcome = .applied)
        -> MutationAcknowledgement
    {
        MutationAcknowledgement(
            acknowledgementID: UUID(), mutationID: item.mutationID, originDeviceID: originID,
            originSequence: item.originSequence, outcome: outcome,
            canonicalSnapshotID: snapshotID, canonicalGeneration: 10,
            conflictID: outcome == .conflict ? UUID() : nil,
            reasonCode: outcome == .conflict ? .staleCausalBase : .applied,
            acknowledgedAt: startAt.addingTimeInterval(Double(item.originSequence)))
    }

    private func sample(
        _ phase: String, _ fixture: ResourceStoreFixture, _ store: WellSpentWatchStore, _ container: ModelContainer
    ) throws -> ResourceSample {
        let state = try store.state()
        let context = ModelContext(container)
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw CocoaError(.fileReadUnknown) }
        return ResourceSample(
            phase: phase, systemUptimeSeconds: ProcessInfo.processInfo.systemUptime,
            processCPUSeconds: Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000,
            voluntaryContextSwitches: Int64(usage.ru_nvcsw), involuntaryContextSwitches: Int64(usage.ru_nivcsw),
            pendingCount: state.pendingMutationCount, quarantineCount: state.quarantinedMutationCount,
            acknowledgementCount: try context.fetchCount(FetchDescriptor<WatchAcknowledgementRecord>()),
            receiptCount: state.pendingSnapshotReceiptCount,
            outboxPayloadBytes: try store.pendingOutbox().reduce(0) { $0 + $1.envelopeData.count },
            files: try fixture.files())
    }

    private func attach(_ samples: [ResourceSample]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(samples) else { return XCTFail("Unable to encode resource evidence") }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "watch-resource-profile"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private struct ResourceSample: Encodable {
    let phase: String
    let systemUptimeSeconds: Double
    let processCPUSeconds: Double
    let voluntaryContextSwitches: Int64
    let involuntaryContextSwitches: Int64
    let pendingCount: Int
    let quarantineCount: Int
    let acknowledgementCount: Int
    let receiptCount: Int
    let outboxPayloadBytes: Int
    let files: [ResourceFileSample]
}

private struct ResourceFileSample: Encodable {
    let name: String
    let logicalBytes: Int
    let allocatedBytes: Int?
}

private struct ResourceStoreFixture {
    let directoryURL: URL
    var storeURL: URL { directoryURL.appendingPathComponent("WellSpentWatch.store") }

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "WellSpentWatchResourceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: false)
    }

    func files() throws -> [ResourceFileSample] {
        try fileURLs().map { url in
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
            return ResourceFileSample(
                name: relativeName(url), logicalBytes: try XCTUnwrap(values.fileSize),
                allocatedBytes: values.totalFileAllocatedSize)
        }
    }

    func fileContents() throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: fileURLs().map { (relativeName($0), try Data(contentsOf: $0)) })
    }

    private func fileURLs() throws -> [URL] {
        var enumerationError: Error?
        guard
            let enumerator = FileManager.default.enumerator(
                at: directoryURL, includingPropertiesForKeys: [.isRegularFileKey],
                errorHandler: { _, error in
                    enumerationError = error
                    return false
                })
        else { throw CocoaError(.fileReadUnknown) }
        var files: [URL] = []
        for case let url as URL in enumerator {
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true { files.append(url) }
        }
        if let enumerationError { throw enumerationError }
        return files.sorted { relativeName($0) < relativeName($1) }
    }

    private func relativeName(_ url: URL) -> String { String(url.path.dropFirst(directoryURL.path.count + 1)) }

    func remove() { try? FileManager.default.removeItem(at: directoryURL) }
}
