import Combine
import Foundation
import SwiftUI
@preconcurrency import WatchConnectivity

#if os(watchOS)
@preconcurrency import WatchKit
#endif

@MainActor
final class SpikeConnectivityController: NSObject, ObservableObject {
    static let shared = SpikeConnectivityController()

    @Published private(set) var state: SpikePersistentState
    @Published private(set) var isReachable = false
    @Published private(set) var isPaired = false
    @Published private(set) var isCounterpartAppInstalled = false
    @Published private(set) var activationLabel = "Not activated"
    @Published private(set) var lastErrorCode: String?
    @Published private(set) var evidenceURL: URL?
    @Published var holdInboxBeforeApply = false
    @Published var holdAcknowledgements = false

    private let store: SpikeStateStore
    private let session = WCSession.default

    #if DEBUG && os(watchOS)
    private let shouldQueueStartOnActivation =
        ProcessInfo.processInfo.environment[
            "WC_PROBE_AUTOMATION_QUEUE_START_ON_ACTIVATION"
        ] == "1"
    private var didQueueAutomatedStart = false
    #endif

    private var isMessageFastPathEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment[
            "WC_PROBE_AUTOMATION_DISABLE_FAST_PATH"
        ] != "1"
        #else
        true
        #endif
    }

    #if os(watchOS)
    private var connectivityTasks: [WKWatchConnectivityRefreshBackgroundTask] = []
    private var contentPendingObservation: NSKeyValueObservation?
    #endif

    private override init() {
        do {
            let store = try SpikeStateStore()
            self.store = store
            if ProcessInfo.processInfo.environment["WC_PROBE_RESET_ON_LAUNCH"] == "1" {
                let reset = SpikePersistentState.empty()
                try store.save(reset)
                state = reset
            } else {
                state = try store.load() ?? .empty()
            }
        } catch {
            fatalError("Spike state initialization failed: \(error)")
        }
        super.init()
        #if DEBUG && os(iOS)
        holdInboxBeforeApply = ProcessInfo.processInfo.environment[
            "WC_PROBE_AUTOMATION_HOLD_INBOX_BEFORE_APPLY"
        ] == "1"
        holdAcknowledgements = ProcessInfo.processInfo.environment[
            "WC_PROBE_AUTOMATION_HOLD_ACKNOWLEDGEMENTS"
        ] == "1"
        #endif
        configureSession()
    }

    var primaryActionLabel: String {
        switch state.localRunState {
        case nil:
            "Queue Start"
        case .running:
            "Queue Pause"
        case .paused:
            "Queue Resume"
        }
    }

    var canEnd: Bool {
        state.localRunID != nil && !state.mutationBlocked
    }

    var canPublishSnapshot: Bool {
        #if os(iOS)
        session.activationState == .activated && isPaired && isCounterpartAppInstalled
        #else
        false
        #endif
    }

    func queueNextMutation() {
        do {
            var candidate = state
            let envelope = try SpikeWatchReducer.makeNextMutation(
                state: &candidate,
                now: Date(),
                timeZoneID: TimeZone.current.identifier,
                makeUUID: UUID.init
            )
            candidate.appendEvent(
                evidenceEvent(
                    code: "watch_local_commit_\(envelope.payload.action.kind.rawValue)",
                    mutation: envelope,
                    transport: .local,
                    generation: candidate.installedSnapshot?.canonicalGeneration
                )
            )
            try commit(candidate)
            #if DEBUG && os(watchOS)
            print(
                "[WCProbe] watch_local_commit"
                    + " action=\(envelope.payload.action.kind.rawValue)"
                    + " mutation=\(envelope.payload.mutationID.uuidString)"
                    + " outbox=\(candidate.outbox.count)"
            )
            #endif
            dispatchMutation(envelope, forceDurableRetry: false)
        } catch {
            recordError("queue_command_failed")
        }
    }

    func queueEndMutation() {
        do {
            var candidate = state
            let envelope = try SpikeWatchReducer.makeEndMutation(
                state: &candidate,
                now: Date(),
                timeZoneID: TimeZone.current.identifier,
                makeUUID: UUID.init
            )
            candidate.appendEvent(
                evidenceEvent(
                    code: "watch_local_commit_end",
                    mutation: envelope,
                    transport: .local,
                    generation: candidate.installedSnapshot?.canonicalGeneration
                )
            )
            try commit(candidate)
            dispatchMutation(envelope, forceDurableRetry: false)
        } catch {
            recordError("queue_end_failed")
        }
    }

    func retryPendingTransfers() {
        #if os(watchOS)
        for envelope in state.outbox {
            dispatchMutation(envelope, forceDurableRetry: true)
        }
        #else
        for receipt in state.inbox {
            if let acknowledgement = receipt.acknowledgement {
                dispatchAcknowledgement(acknowledgement)
            }
        }
        publishCanonicalSnapshot()
        #endif
    }

    func publishCanonicalSnapshot() {
        #if os(iOS)
        guard session.activationState == .activated else {
            recordError("snapshot_session_inactive")
            return
        }
        guard isPaired else {
            recordError("snapshot_watch_not_paired")
            return
        }
        guard isCounterpartAppInstalled else {
            recordError("snapshot_watch_app_not_installed")
            return
        }
        do {
            let data = try SpikeCodec.encode(state.canonicalSnapshot)
            try session.updateApplicationContext([
                SpikeWireKey.kind: SpikeWireKind.snapshot.rawValue,
                SpikeWireKey.payload: data,
            ])
            appendAndPersistEvent(
                evidenceEvent(
                    code: "phone_snapshot_published",
                    transport: .applicationContext,
                    generation: state.canonicalSnapshot.canonicalGeneration
                )
            )
        } catch {
            recordError("snapshot_publish_failed", error: error)
        }
        #endif
    }

    func advanceSyntheticSnapshot() {
        #if os(iOS)
        do {
            var candidate = state
            let current = candidate.canonicalSnapshot
            candidate.canonicalSnapshot = SpikeSnapshot(
                protocolMajor: current.protocolMajor,
                protocolMinor: current.protocolMinor,
                schemaVersion: current.schemaVersion,
                snapshotID: UUID(),
                canonicalGeneration: current.canonicalGeneration + 1,
                activeRunID: current.activeRunID,
                activeRunRevision: current.activeRunRevision,
                activeRunState: current.activeRunState,
                openSegmentID: current.openSegmentID,
                headMutationID: current.headMutationID,
                pendingConflictID: current.pendingConflictID,
                producedAt: Date()
            )
            candidate.appendEvent(
                evidenceEvent(
                    code: "phone_synthetic_catalog_revision",
                    transport: .local,
                    generation: candidate.canonicalSnapshot.canonicalGeneration
                )
            )
            try commit(candidate)
            publishCanonicalSnapshot()
        } catch {
            recordError("synthetic_snapshot_failed")
        }
        #endif
    }

    func exportEvidence() {
        do {
            evidenceURL = try store.evidenceURL(for: state)
        } catch {
            recordError("evidence_export_failed")
        }
    }

    func resetProbeState() {
        do {
            let reset = SpikePersistentState.empty()
            try commit(reset)
            evidenceURL = nil
        } catch {
            recordError("probe_reset_failed")
        }
    }

    #if os(watchOS)
    func handleBackgroundTasks(_ tasks: Set<WKRefreshBackgroundTask>) {
        for task in tasks {
            if let connectivityTask = task as? WKWatchConnectivityRefreshBackgroundTask {
                connectivityTasks.append(connectivityTask)
            } else {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
        appendAndPersistEvent(
            evidenceEvent(
                code: "watch_background_wake",
                transport: .local,
                generation: state.installedSnapshot?.canonicalGeneration
            )
        )
        completeConnectivityTasksIfPossible()
    }
    #endif

    private func configureSession() {
        guard WCSession.isSupported() else {
            activationLabel = "Unsupported"
            return
        }
        session.delegate = self
        session.activate()

        #if os(watchOS)
        contentPendingObservation = session.observe(\.hasContentPending) { [weak self] session, _ in
            let hasContentPending = session.hasContentPending
            Task { @MainActor in
                if !hasContentPending {
                    self?.completeConnectivityTasksIfPossible()
                }
            }
        }
        #endif
    }

    private func refreshSessionState() {
        isReachable = session.isReachable
        guard session.activationState == .activated else {
            isPaired = false
            isCounterpartAppInstalled = false
            return
        }
        #if os(iOS)
        isPaired = session.isPaired
        isCounterpartAppInstalled = session.isWatchAppInstalled
        #else
        isPaired = false
        isCounterpartAppInstalled = false
        #endif
    }

    private func dispatchMutation(
        _ envelope: SpikeMutationEnvelope,
        forceDurableRetry: Bool
    ) {
        guard session.activationState == .activated else {
            return
        }
        guard let data = try? SpikeCodec.encode(envelope) else {
            recordError("mutation_encode_failed")
            return
        }
        let message: [String: Any] = [
            SpikeWireKey.kind: SpikeWireKind.mutation.rawValue,
            SpikeWireKey.payload: data,
        ]

        if session.isReachable && isMessageFastPathEnabled {
            session.sendMessage(message, replyHandler: nil) { [weak self] error in
                let code = (error as NSError).code
                Task { @MainActor in self?.recordError("message_error_\(code)") }
            }
            appendAndPersistEvent(
                evidenceEvent(
                    code: "watch_message_sent",
                    mutation: envelope,
                    transport: .message,
                    generation: state.installedSnapshot?.canonicalGeneration
                )
            )
        }

        let mutationID = envelope.payload.mutationID
        guard forceDurableRetry || !state.queuedMutationIDs.contains(mutationID) else {
            return
        }
        _ = session.transferUserInfo(message)
        var candidate = state
        candidate.queuedMutationIDs.insert(mutationID)
        candidate.appendEvent(
            evidenceEvent(
                code: forceDurableRetry ? "watch_user_info_retried" : "watch_user_info_queued",
                mutation: envelope,
                transport: .userInfo,
                generation: candidate.installedSnapshot?.canonicalGeneration
            )
        )
        do {
            try commit(candidate)
        } catch {
            recordError("queue_marker_save_failed")
        }
    }

    private func receive(
        kind: SpikeWireKind,
        data: Data,
        transport: SpikeTransportKind
    ) {
        switch kind {
        case .mutation:
            #if os(iOS)
            receiveMutation(data: data, transport: transport)
            #endif
        case .acknowledgement:
            #if os(watchOS)
            receiveAcknowledgement(data: data, transport: transport)
            #endif
        case .snapshot:
            #if os(watchOS)
            receiveSnapshot(data: data, transport: transport)
            #endif
        case .snapshotReceipt:
            #if os(iOS)
            receiveSnapshotReceipt(data: data, transport: transport)
            #endif
        }
        #if os(watchOS)
        completeConnectivityTasksIfPossible()
        #endif
    }

    #if os(iOS)
    private func receiveMutation(data: Data, transport: SpikeTransportKind) {
        do {
            let envelope = try SpikeCodec.decode(SpikeMutationEnvelope.self, from: data)

            if let storedAcknowledgement = state.inbox.first(where: {
                $0.id == envelope.payload.mutationID
            })?.acknowledgement {
                appendAndPersistEvent(
                    evidenceEvent(
                        code: "phone_duplicate_received",
                        mutation: envelope,
                        transport: transport,
                        generation: state.canonicalSnapshot.canonicalGeneration
                    )
                )
                dispatchAcknowledgement(storedAcknowledgement)
                return
            }

            if !state.inbox.contains(where: { $0.id == envelope.payload.mutationID }) {
                var receivedState = state
                _ = SpikePhoneReducer.receive(
                    envelope: envelope,
                    transport: transport,
                    state: &receivedState,
                    now: Date()
                )
                receivedState.appendEvent(
                    evidenceEvent(
                        code: "phone_inbox_persisted",
                        mutation: envelope,
                        transport: transport,
                        generation: receivedState.canonicalSnapshot.canonicalGeneration
                    )
                )
                try commit(receivedState)
            }

            if holdInboxBeforeApply {
                appendAndPersistEvent(
                    evidenceEvent(
                        code: "phone_inbox_apply_held",
                        mutation: envelope,
                        transport: .local,
                        generation: state.canonicalSnapshot.canonicalGeneration
                    )
                )
                return
            }

            processReceivedInbox()
        } catch {
            recordError("mutation_receive_failed")
        }
    }

    private func processReceivedInbox() {
        do {
            var candidate = state
            var acknowledgements: [SpikeMutationAcknowledgement] = []
            var madeProgress = true

            while madeProgress {
                madeProgress = false
                let receivedIDs = candidate.inbox.filter {
                    $0.status == .received
                }.map(\.id)
                for mutationID in receivedIDs {
                    if let acknowledgement = SpikePhoneReducer.processReceived(
                        mutationID: mutationID,
                        state: &candidate,
                        now: Date(),
                        makeUUID: UUID.init
                    ) {
                        acknowledgements.append(acknowledgement)
                        candidate.appendEvent(
                            evidenceEvent(
                                code: "phone_mutation_\(acknowledgement.outcome.rawValue)",
                                mutationID: acknowledgement.mutationID,
                                originSequence: acknowledgement.originSequence,
                                transport: .local,
                                generation: acknowledgement.canonicalGeneration
                            )
                        )
                        madeProgress = true
                    }
                }
            }

            guard !acknowledgements.isEmpty else { return }
            try commit(candidate)
            for acknowledgement in acknowledgements {
                dispatchAcknowledgement(acknowledgement)
            }
            publishCanonicalSnapshot()
        } catch {
            recordError("inbox_apply_failed")
        }
    }

    private func dispatchAcknowledgement(
        _ acknowledgement: SpikeMutationAcknowledgement
    ) {
        if holdAcknowledgements {
            appendAndPersistEvent(
                evidenceEvent(
                    code: "phone_ack_held",
                    mutationID: acknowledgement.mutationID,
                    originSequence: acknowledgement.originSequence,
                    transport: .local,
                    generation: acknowledgement.canonicalGeneration
                )
            )
            return
        }
        guard session.activationState == .activated,
            let data = try? SpikeCodec.encode(acknowledgement)
        else { return }
        let message: [String: Any] = [
            SpikeWireKey.kind: SpikeWireKind.acknowledgement.rawValue,
            SpikeWireKey.payload: data,
        ]
        if session.isReachable && isMessageFastPathEnabled {
            session.sendMessage(message, replyHandler: nil) { [weak self] error in
                let code = (error as NSError).code
                Task { @MainActor in self?.recordError("ack_message_error_\(code)") }
            }
        }
        _ = session.transferUserInfo(message)
        appendAndPersistEvent(
            evidenceEvent(
                code: "phone_ack_queued",
                mutationID: acknowledgement.mutationID,
                originSequence: acknowledgement.originSequence,
                transport: .userInfo,
                generation: acknowledgement.canonicalGeneration
            )
        )
    }

    private func receiveSnapshotReceipt(data: Data, transport: SpikeTransportKind) {
        do {
            let receipt = try SpikeCodec.decode(SpikeSnapshotReceipt.self, from: data)
            guard !state.receivedSnapshotReceipts.contains(where: {
                $0.receiptID == receipt.receiptID
            }) else { return }
            var candidate = state
            candidate.receivedSnapshotReceipts.append(receipt)
            candidate.appendEvent(
                evidenceEvent(
                    code: "phone_snapshot_receipt",
                    transport: transport,
                    generation: receipt.canonicalGeneration
                )
            )
            try commit(candidate)
        } catch {
            recordError("snapshot_receipt_failed")
        }
    }
    #endif

    #if os(watchOS)
    private func receiveAcknowledgement(data: Data, transport: SpikeTransportKind) {
        do {
            let acknowledgement = try SpikeCodec.decode(
                SpikeMutationAcknowledgement.self,
                from: data
            )
            var candidate = state
            SpikeWatchReducer.install(acknowledgement: acknowledgement, state: &candidate)
            candidate.appendEvent(
                evidenceEvent(
                    code: "watch_ack_\(acknowledgement.outcome.rawValue)",
                    mutationID: acknowledgement.mutationID,
                    originSequence: acknowledgement.originSequence,
                    transport: transport,
                    generation: acknowledgement.canonicalGeneration
                )
            )
            try commit(candidate)
            #if DEBUG
            print(
                "[WCProbe] watch_ack_saved"
                    + " mutation=\(acknowledgement.mutationID.uuidString)"
                    + " outbox=\(candidate.outbox.count)"
                    + " acks=\(candidate.acknowledgements.count)"
            )
            #endif
        } catch {
            recordError("ack_receive_failed")
        }
    }

    private func receiveSnapshot(data: Data, transport: SpikeTransportKind) {
        do {
            let snapshot = try SpikeCodec.decode(SpikeSnapshot.self, from: data)
            var candidate = state
            let installed = SpikeWatchReducer.install(snapshot: snapshot, state: &candidate)
            candidate.appendEvent(
                evidenceEvent(
                    code: installed ? "watch_snapshot_installed" : "watch_snapshot_stale",
                    transport: transport,
                    generation: snapshot.canonicalGeneration
                )
            )
            try commit(candidate)
            guard installed else { return }

            let receipt = SpikeSnapshotReceipt(
                receiptID: UUID(),
                originDeviceID: candidate.originDeviceID,
                snapshotID: snapshot.snapshotID,
                canonicalGeneration: snapshot.canonicalGeneration,
                installedAt: Date()
            )
            dispatchSnapshotReceipt(receipt)
        } catch {
            recordError("snapshot_receive_failed")
        }
    }

    private func dispatchSnapshotReceipt(_ receipt: SpikeSnapshotReceipt) {
        guard session.activationState == .activated,
            let data = try? SpikeCodec.encode(receipt)
        else { return }
        _ = session.transferUserInfo([
            SpikeWireKey.kind: SpikeWireKind.snapshotReceipt.rawValue,
            SpikeWireKey.payload: data,
        ])
        appendAndPersistEvent(
            evidenceEvent(
                code: "watch_snapshot_receipt_queued",
                transport: .userInfo,
                generation: receipt.canonicalGeneration
            )
        )
    }

    private func completeConnectivityTasksIfPossible() {
        guard session.activationState != .activated || !session.hasContentPending else {
            return
        }
        let tasks = connectivityTasks
        connectivityTasks.removeAll()
        for task in tasks {
            task.setTaskCompletedWithSnapshot(false)
        }
    }
    #endif

    private func commit(_ candidate: SpikePersistentState) throws {
        try store.save(candidate)
        state = candidate
        lastErrorCode = nil
    }

    private func appendAndPersistEvent(_ event: SpikeEvidenceEvent) {
        do {
            var candidate = state
            candidate.appendEvent(event)
            try commit(candidate)
        } catch {
            lastErrorCode = "event_save_failed"
        }
    }

    private func recordError(_ code: String, error: (any Error)? = nil) {
        let nsError = error as NSError?
        let evidenceCode = nsError.map { "\(code)_\($0.code)" } ?? code
        lastErrorCode = evidenceCode
        var candidate = state
        candidate.appendEvent(
            evidenceEvent(
                code: evidenceCode,
                transport: .local,
                generation: state.installedSnapshot?.canonicalGeneration
                    ?? state.canonicalSnapshot.canonicalGeneration
            )
        )
        if (try? store.save(candidate)) != nil {
            state = candidate
        }
        #if DEBUG
        if let nsError {
            print(
                "[WCProbe] \(evidenceCode) domain=\(nsError.domain) "
                    + "description=\(nsError.localizedDescription)"
            )
        }
        #endif
    }

    private func evidenceEvent(
        code: String,
        mutation: SpikeMutationEnvelope? = nil,
        mutationID: UUID? = nil,
        originSequence: UInt64? = nil,
        transport: SpikeTransportKind,
        generation: UInt64?
    ) -> SpikeEvidenceEvent {
        SpikeEvidenceEvent(
            id: UUID(),
            code: code,
            at: Date(),
            mutationID: mutation?.payload.mutationID ?? mutationID,
            originSequence: mutation?.payload.originSequence ?? originSequence,
            transport: transport,
            canonicalGeneration: generation,
            reachable: session.isReachable
        )
    }

    private func decodeWire(_ dictionary: [String: Any]) -> (SpikeWireKind, Data)? {
        guard let rawKind = dictionary[SpikeWireKey.kind] as? String,
            let kind = SpikeWireKind(rawValue: rawKind),
            let data = dictionary[SpikeWireKey.payload] as? Data
        else { return nil }
        return (kind, data)
    }
}

extension SpikeConnectivityController: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        let activationRawValue = activationState.rawValue
        let errorCode = (error as NSError?)?.code
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.activationLabel = switch activationRawValue {
            case WCSessionActivationState.activated.rawValue: "Activated"
            case WCSessionActivationState.inactive.rawValue: "Inactive"
            default: "Not activated"
            }
            self.isReachable = reachable
            self.refreshSessionState()
            if let errorCode {
                self.recordError("activation_error_\(errorCode)")
            } else {
                #if DEBUG
                if ProcessInfo.processInfo.environment[
                    "WC_PROBE_AUTOMATION_CANCEL_PENDING_TRANSFERS"
                ] == "1" {
                    for transfer in session.outstandingUserInfoTransfers {
                        transfer.cancel()
                    }
                }
                #endif
                self.appendAndPersistEvent(
                    self.evidenceEvent(
                        code: "session_activation_\(activationRawValue)",
                        transport: .local,
                        generation: self.state.installedSnapshot?.canonicalGeneration
                            ?? self.state.canonicalSnapshot.canonicalGeneration
                    )
                )
                #if os(watchOS)
                for envelope in self.state.outbox {
                    self.dispatchMutation(envelope, forceDurableRetry: false)
                }
                #if DEBUG
                if self.shouldQueueStartOnActivation && !self.didQueueAutomatedStart {
                    self.didQueueAutomatedStart = true
                    let delaySeconds = Double(
                        ProcessInfo.processInfo.environment[
                            "WC_PROBE_AUTOMATION_QUEUE_START_DELAY_SECONDS"
                        ] ?? "0"
                    ) ?? 0
                    if delaySeconds > 0 {
                        Task { @MainActor [weak self] in
                            try? await Task.sleep(
                                nanoseconds: UInt64(delaySeconds * 1_000_000_000)
                            )
                            self?.queueNextMutation()
                        }
                    } else {
                        self.queueNextMutation()
                    }
                }
                #endif
                self.completeConnectivityTasksIfPossible()
                #else
                self.processReceivedInbox()
                #endif
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isReachable = reachable
            self.refreshSessionState()
            self.appendAndPersistEvent(
                self.evidenceEvent(
                    code: reachable ? "reachability_on" : "reachability_off",
                    transport: .local,
                    generation: self.state.installedSnapshot?.canonicalGeneration
                        ?? self.state.canonicalSnapshot.canonicalGeneration
                )
            )
            #if os(watchOS)
            if reachable {
                for envelope in self.state.outbox {
                    self.dispatchMutation(envelope, forceDurableRetry: false)
                }
            }
            #endif
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let rawKind = message[SpikeWireKey.kind] as? String,
            let kind = SpikeWireKind(rawValue: rawKind),
            let data = message[SpikeWireKey.payload] as? Data
        else { return }
        Task { @MainActor [weak self] in
            self?.receive(kind: kind, data: data, transport: .message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let rawKind = userInfo[SpikeWireKey.kind] as? String,
            let kind = SpikeWireKind(rawValue: rawKind),
            let data = userInfo[SpikeWireKey.payload] as? Data
        else { return }
        Task { @MainActor [weak self] in
            self?.receive(kind: kind, data: data, transport: .userInfo)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let rawKind = applicationContext[SpikeWireKey.kind] as? String,
            let kind = SpikeWireKind(rawValue: rawKind),
            let data = applicationContext[SpikeWireKey.payload] as? Data
        else { return }
        Task { @MainActor [weak self] in
            self?.receive(kind: kind, data: data, transport: .applicationContext)
        }
    }

    #if os(iOS)
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.refreshSessionState()
            self.appendAndPersistEvent(
                self.evidenceEvent(
                    code: "watch_install_state_changed",
                    transport: .local,
                    generation: self.state.canonicalSnapshot.canonicalGeneration
                )
            )
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.activationLabel = "Inactive" }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.activationLabel = "Deactivated"
            self.session.activate()
        }
    }
    #endif
}
