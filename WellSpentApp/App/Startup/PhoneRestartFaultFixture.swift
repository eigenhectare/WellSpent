#if DEBUG
    import SwiftData
    import SwiftUI
    import WellSpentWatchContracts

    /// Disk-backed checkpoint harness. XCTest kills the process only after the
    /// real store reaches a named boundary, then reopens the same private file.
    @MainActor
    final class PhoneRestartFaultFixture {
        let container: ModelContainer
        let report: String
        let fingerprint: String
        let acknowledgement: String
        let phase: String

        private enum Checkpoint: Error { case receiptSaved }
        nonisolated private static let now = Date(timeIntervalSince1970: 1_800_000_000)
        private static let runID = UUID(uuidString: "31000000-0000-4000-8000-000000000001")!
        private static let segmentID = UUID(uuidString: "41000000-0000-4000-8000-000000000001")!
        private static let projectID = UUID(uuidString: "21000000-0000-4000-8000-000000000001")!
        private static let originID = UUID(uuidString: "11000000-0000-4000-8000-000000000001")!
        private static let mutationID = UUID(uuidString: "51000000-0000-4000-8000-000000000001")!

        static func requested() throws -> PhoneRestartFaultFixture? {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "-ui-test-restart-id") else { return nil }
            guard arguments.indices.contains(index + 3),
                let id = UUID(uuidString: arguments[index + 1]),
                arguments[index + 2] == "-ui-test-restart-phase",
                ["receipt", "committed", "recover"].contains(arguments[index + 3])
            else { throw CocoaError(.fileReadCorruptFile) }
            return try PhoneRestartFaultFixture(id: id, phase: arguments[index + 3])
        }

        private init(id: UUID, phase: String) throws {
            self.phase = phase
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            .appendingPathComponent("WAT22_FAULT_FIXTURE", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
            let url = directory.appendingPathComponent("phone.store")
            // Recovery must not silently create a new store; seeding may never
            // overwrite an existing store. Each XCTest supplies a fresh UUID.
            guard FileManager.default.fileExists(atPath: url.path) == (phase == "recover") else {
                throw CocoaError(.fileReadCorruptFile)
            }
            container = try WellSpentPersistence.makePersistentContainer(storeURL: url)
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let repository = SwiftDataTimerRunRepository(context: context)
            let dependencies = WellSpentDependencies(
                nowProvider: NowProvider { Self.now }, localeProvider: LocaleProvider { Locale(identifier: "en_US") },
                timeZoneProvider: TimeZoneProvider { TimeZone(secondsFromGMT: 0)! },
                calendarProvider: CalendarProvider { Calendar(identifier: .gregorian) }, uuidProvider: .live)
            let commands = TimerRunCommandService(repository: repository, dependencies: dependencies)
            let store = PhoneWatchSyncStore(
                context: context, timerRepository: repository, timerCommands: commands, dependencies: dependencies,
                showsSystemProjectNames: { false })

            if phase == "recover" {
                let inbox = try context.fetch(FetchDescriptor<PhoneMutationInboxRecord>())
                guard inbox.count == 1, let original = inbox.first else { throw CocoaError(.fileReadCorruptFile) }
                let originalData = original.envelopeData
                let coordinator = IPhoneWatchConnectivityCoordinator(
                    syncStore: store, session: UITestDisconnectedWatchSession(), now: { Self.now })
                coordinator.activate()
                coordinator.retryPendingTransfers()
                guard coordinator.lastDiagnosticCode == nil else { throw CocoaError(.fileReadCorruptFile) }
                // Simulate the original mutation arriving again after a lost
                // acknowledgement. It must retain the exact terminal receipt.
                _ = try store.receiveMutationData(originalData)
            } else {
                context.insert(ProjectRecord(id: Self.projectID, name: "WAT22_FAULT_FIXTURE"))
                try context.save()
                let head = try store.makeSnapshot().ledgerHead
                let mutation = try TimerMutationEnvelope(
                    mutationID: Self.mutationID, originDeviceID: Self.originID, originSequence: 1,
                    capturedAt: Self.now, capturedTimeZoneID: "UTC", baseSnapshotID: head.snapshotID,
                    baseCanonicalGeneration: head.canonicalGeneration, predecessorMutationID: nil,
                    observedRunID: nil, observedRunRevision: nil,
                    action: .start(
                        StartTimerAction(
                            runID: Self.runID, segmentID: Self.segmentID, projectID: Self.projectID,
                            durationGoalSeconds: nil)))
                if phase == "receipt" {
                    store.setAfterInboxReceiptSavedForTesting { throw Checkpoint.receiptSaved }
                }
                do {
                    _ = try store.receiveMutationData(ContractWireCodec.encodeMutation(mutation))
                } catch Checkpoint.receiptSaved {
                    // No canonical application or acknowledgement dispatch has
                    // occurred. Keep the process alive for XCTest to terminate.
                }
            }
            let runs = try repository.fetchRuns()
            let segments = try repository.fetchSessions()
            let inbox = try context.fetch(FetchDescriptor<PhoneMutationInboxRecord>())
            let pending = try store.pendingAcknowledgements()
            let first = inbox.first
            report =
                "runs=\(runs.count) segments=\(segments.count) inbox=\(inbox.count) ack=\(pending.count) "
                + "status=\(first?.statusRawValue ?? "missing") revision=\(runs.first?.revision ?? 0)"
            fingerprint = first.map { "\($0.mutationID.uuidString)/\($0.payloadDigestHex)" } ?? "missing"
            acknowledgement = pending.first.map { $0.data.base64EncodedString() } ?? "none"
        }
    }

    struct PhoneRestartFaultFixtureView: View {
        let fixture: PhoneRestartFaultFixture
        var body: some View {
            VStack(spacing: 16) {
                Text(fixture.phase).accessibilityIdentifier("fault.phase")
                Text(fixture.report).accessibilityIdentifier("fault.report")
                Text("Journal identity").accessibilityIdentifier("fault.identity")
                    .accessibilityValue(fixture.fingerprint)
                Text("Acknowledgement bytes").accessibilityIdentifier("fault.ack")
                    .accessibilityValue(fixture.acknowledgement)
            }
            .padding()
        }
    }
#endif
