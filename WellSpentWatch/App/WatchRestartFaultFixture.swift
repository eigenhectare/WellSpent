#if DEBUG
    import SwiftUI
    import WellSpentWatchContracts
    import WellSpentWatchStore

    @MainActor
    final class WatchRestartFaultFixture {
        let report: String
        let fingerprint: String
        let phase: String
        private let store: WellSpentWatchStore
        private static let now = Date(timeIntervalSince1970: 1_800_000_000)
        private static let originID = UUID(uuidString: "12000000-0000-4000-8000-000000000001")!
        private static let projectID = UUID(uuidString: "22000000-0000-4000-8000-000000000001")!
        private static let runID = UUID(uuidString: "32000000-0000-4000-8000-000000000001")!
        private static let segmentID = UUID(uuidString: "42000000-0000-4000-8000-000000000001")!

        static func requested() throws -> WatchRestartFaultFixture? {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "-ui-test-restart-id") else { return nil }
            guard arguments.indices.contains(index + 3), let id = UUID(uuidString: arguments[index + 1]),
                arguments[index + 2] == "-ui-test-restart-phase",
                ["committed", "delivery", "recover"].contains(arguments[index + 3])
            else { throw CocoaError(.fileReadCorruptFile) }
            return try WatchRestartFaultFixture(id: id, phase: arguments[index + 3])
        }

        private init(id: UUID, phase: String) throws {
            self.phase = phase
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            .appendingPathComponent("WAT22_FAULT_FIXTURE", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
            let url = directory.appendingPathComponent("watch.store")
            guard FileManager.default.fileExists(atPath: url.path) == (phase == "recover") else {
                throw CocoaError(.fileReadCorruptFile)
            }
            store = try WellSpentWatchStore.openRestartFixture(at: url, originDeviceID: Self.originID)
            if phase != "recover" {
                _ = try store.installSnapshotData(
                    ContractWireCodec.encodeSnapshot(Self.snapshot), contradictsPendingMutations: false)
                for receipt in try store.pendingSnapshotReceipts() {
                    try store.compactSnapshotReceipt(receiptID: receipt.receiptID)
                }
                let commit = try store.performLocalCommand(
                    .start(
                        StartTimerAction(
                            runID: Self.runID, segmentID: Self.segmentID,
                            projectID: Self.projectID, durationGoalSeconds: nil)),
                    capturedAt: Self.now, timeZoneID: "UTC")
                if phase == "delivery" {
                    // Same durable boundary used after dispatching a transfer;
                    // transport cannot acknowledge it in this isolated harness.
                    try store.recordDeliveryAttempt(
                        mutationID: commit.mutation.mutationID,
                        attemptedAt: Self.now, nextRetryAt: Self.now.addingTimeInterval(30))
                }
            }
            // Opening the persistent store executes its real journal recovery.
            // Recovery never seeds a catalog, recreates a command, or starts WC.
            let state = try store.state()
            let outbox = try store.pendingOutbox()
            let run = state.projection.activeRun
            report =
                "runs=\(run == nil ? 0 : 1) segments=\(state.projection.activeRunSegments.count) "
                + "outbox=\(outbox.count) sequence=\(state.nextOriginSequence) "
                + "revision=\(run?.revision ?? 0) attempts=\(outbox.first?.attemptCount ?? 0)"
            fingerprint =
                outbox.first.map {
                    "\(run?.id.uuidString ?? "missing")/\($0.mutationID.uuidString)/\($0.payloadDigest.hex)/"
                        + $0.envelopeData.base64EncodedString()
                } ?? "missing"
        }

        private static var snapshot: TimerSnapshotEnvelope {
            TimerSnapshotEnvelope(
                capabilities: ContractCapability.allCases,
                ledgerHead: TimerLedgerHead(
                    snapshotID: UUID(uuidString: "52000000-0000-4000-8000-000000000001")!,
                    canonicalGeneration: 1, activeRunID: nil, activeRunRevision: nil, headMutationID: nil),
                projects: [
                    ProjectSnapshot(
                        id: projectID, workspaceID: nil, name: "WAT22_FAULT_FIXTURE",
                        colorToken: nil, symbolName: nil)
                ],
                tags: [], tombstones: [], activeRun: nil, activeRunSegments: [], recentlyEndedRun: nil,
                recentlyEndedRunSegments: [],
                totals: TimerTotalsSnapshot(
                    todaySeconds: 0, weekSeconds: 0, calculatedAt: now, calendarTimeZoneID: "UTC"),
                conflict: nil, recentAcknowledgements: [], receiptWatermarks: [],
                updateGuidance: MinimumAppVersionGuidance(
                    minimumPhoneBuild: nil, minimumWatchBuild: nil,
                    updateRequired: false))
        }
    }

    struct WatchRestartFaultFixtureView: View {
        let fixture: WatchRestartFaultFixture
        var body: some View {
            VStack {
                Text(fixture.phase).accessibilityIdentifier("fault.phase")
                Text(fixture.report).font(.caption2).accessibilityIdentifier("fault.report")
                Text("Journal identity").font(.caption2).accessibilityIdentifier("fault.identity")
                    .accessibilityValue(fixture.fingerprint)
            }
        }
    }
#endif
