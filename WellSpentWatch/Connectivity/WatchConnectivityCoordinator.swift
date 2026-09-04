import Combine
import Foundation
@preconcurrency import WatchConnectivity
import WatchKit
import WellSpentWatchContracts
import WellSpentWatchStore

enum WatchConnectivityState: Equatable {
    case activating
    case available(reachable: Bool, pendingCount: Int)
    case blocked
    case unavailable
}

@MainActor
protocol WatchConnectivitySession: AnyObject {
    var activationState: WCSessionActivationState { get }
    var isReachable: Bool { get }
    var hasContentPending: Bool { get }
    var outstandingUserInfoPackets: [[String: Any]] { get }

    func configure(delegate: any WCSessionDelegate)
    func activate()
    func sendMessage(
        _ message: [String: Any],
        errorHandler: (@Sendable (any Error) -> Void)?
    )
    func queueUserInfo(_ userInfo: [String: Any])
}

extension WCSession: WatchConnectivitySession {
    var outstandingUserInfoPackets: [[String: Any]] {
        outstandingUserInfoTransfers.map(\.userInfo)
    }

    func configure(delegate: any WCSessionDelegate) {
        self.delegate = delegate
    }

    func sendMessage(
        _ message: [String: Any],
        errorHandler: (@Sendable (any Error) -> Void)?
    ) {
        sendMessage(message, replyHandler: nil, errorHandler: errorHandler)
    }

    func queueUserInfo(_ userInfo: [String: Any]) {
        transferUserInfo(userInfo)
    }
}

@MainActor
final class WatchConnectivityCoordinator: NSObject, ObservableObject {
    @Published private(set) var state: WatchConnectivityState = .activating
    @Published private(set) var lastDiagnosticCode: String?

    var onStoreChanged: (() -> Void)?
    var beforeBackgroundTaskCompletion: (() async -> Void)?

    private let store: WellSpentWatchStore
    private let session: any WatchConnectivitySession
    private let now: () -> Date
    private var backgroundTasks: [WKWatchConnectivityRefreshBackgroundTask] = []
    private var isCompletingBackgroundTasks = false

    init(
        store: WellSpentWatchStore,
        session: any WatchConnectivitySession = WCSession.default,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.session = session
        self.now = now
        super.init()
    }

    func activate() {
        session.configure(delegate: self)
        session.activate()
        refreshState()
    }

    func retryPendingTransfers(forceDurable: Bool = false) {
        guard session.activationState == .activated else {
            refreshState()
            completeBackgroundTasksIfPossible()
            return
        }
        do {
            try dispatchMutations(forceDurable: forceDurable)
            try dispatchSnapshotReceipts()
            lastDiagnosticCode = nil
        } catch {
            lastDiagnosticCode = "pending_dispatch_failed"
        }
        refreshState()
        completeBackgroundTasksIfPossible()
    }

    func receiveForTesting(kind: WatchConnectivityPayloadKind, data: Data) {
        receive(kind: kind, data: data)
    }

    func handleBackgroundTasks(_ tasks: Set<WKRefreshBackgroundTask>) {
        for task in tasks {
            if let connectivityTask = task as? WKWatchConnectivityRefreshBackgroundTask {
                backgroundTasks.append(connectivityTask)
            } else {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
        retryPendingTransfers(forceDurable: true)
    }

    private func dispatchMutations(forceDurable: Bool) throws {
        let outstandingIDs = Set(
            session.outstandingUserInfoPackets.compactMap {
                WatchConnectivityWire.decode($0)?.identifier
            }
        )
        for item in try store.pendingOutbox() {
            let packet = WatchConnectivityWire.packet(
                kind: .mutation,
                payload: item.envelopeData,
                identifier: item.mutationID
            )
            if session.isReachable {
                session.sendMessage(packet) { _ in }
            }
            if forceDurable || !outstandingIDs.contains(item.mutationID) {
                session.queueUserInfo(packet)
                try store.recordDeliveryAttempt(
                    mutationID: item.mutationID,
                    attemptedAt: now(),
                    nextRetryAt: nil
                )
            }
        }
    }

    private func dispatchSnapshotReceipts() throws {
        let outstandingIDs = Set(
            session.outstandingUserInfoPackets.compactMap {
                WatchConnectivityWire.decode($0)?.identifier
            }
        )
        for receipt in try store.pendingSnapshotReceipts() {
            if outstandingIDs.contains(receipt.receiptID) { continue }
            session.queueUserInfo(
                WatchConnectivityWire.packet(
                    kind: .snapshotReceipt,
                    payload: receipt.receiptData,
                    identifier: receipt.receiptID
                )
            )
            try store.recordSnapshotReceiptAttempt(
                receiptID: receipt.receiptID,
                attemptedAt: now()
            )
            // WCSession now owns a durable copy. A future snapshot will create a
            // new receipt if this transfer can never be delivered.
            try store.compactSnapshotReceipt(receiptID: receipt.receiptID)
        }
    }

    private func receive(kind: WatchConnectivityPayloadKind, data: Data) {
        do {
            switch kind {
            case .acknowledgement:
                let acknowledgement = try ContractWireCodec.decodeCanonical(
                    MutationAcknowledgement.self,
                    from: data
                )
                try store.receiveAcknowledgement(acknowledgement)
                onStoreChanged?()
                retryPendingTransfers()
            case .snapshot:
                let snapshot = try ContractWireCodec.decodeSnapshot(data)
                let result = try store.installSnapshotData(
                    data,
                    contradictsPendingMutations: try contradictsPendingMutations(snapshot)
                )
                if case .reviewRequired = result {
                    lastDiagnosticCode = "snapshot_review_required"
                } else {
                    lastDiagnosticCode = nil
                }
                onStoreChanged?()
                retryPendingTransfers()
            case .mutation, .snapshotReceipt:
                lastDiagnosticCode = "unexpected_payload"
            }
        } catch {
            lastDiagnosticCode = "payload_receive_failed"
            refreshState()
        }
    }

    private func contradictsPendingMutations(_ snapshot: TimerSnapshotEnvelope) throws -> Bool {
        let pending = try store.pendingOutbox()
        guard !pending.isEmpty else { return false }

        let acknowledged = Set(
            snapshot.recentAcknowledgements
                .filter { $0.outcome == .applied || $0.outcome == .duplicate }
                .map(\.mutationID)
        )
        if pending.allSatisfy({ acknowledged.contains($0.mutationID) }) {
            return false
        }

        let installed = try store.state().projection.ledgerHead
        return installed?.activeRunID != snapshot.ledgerHead.activeRunID
            || installed?.activeRunRevision != snapshot.ledgerHead.activeRunRevision
    }

    private func refreshState() {
        guard session.activationState == .activated else {
            state = session.activationState == .notActivated ? .activating : .unavailable
            return
        }
        guard let storeState = try? store.state() else {
            state = .unavailable
            return
        }
        if storeState.isBlocked {
            state = .blocked
        } else {
            state = .available(
                reachable: session.isReachable,
                pendingCount: storeState.pendingMutationCount
            )
        }
    }

    private func completeBackgroundTasksIfPossible() {
        guard !backgroundTasks.isEmpty, !isCompletingBackgroundTasks else { return }
        guard session.activationState != .activated || !session.hasContentPending else { return }
        isCompletingBackgroundTasks = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Finish finite notification projection work before handing the WC
            // runtime back to the OS. This does not request background runtime.
            await beforeBackgroundTaskCompletion?()
            isCompletingBackgroundTasks = false
            guard session.activationState != .activated || !session.hasContentPending else { return }
            let completed = backgroundTasks
            backgroundTasks.removeAll()
            for task in completed {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}

extension WatchConnectivityCoordinator: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if error != nil {
                self.lastDiagnosticCode = "session_activation_failed"
            }
            self.refreshState()
            self.retryPendingTransfers(forceDurable: true)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.refreshState()
            if reachable { self?.retryPendingTransfers() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let packet = WatchConnectivityWire.decode(message) else { return }
        let kind = packet.kind
        let payload = packet.payload
        Task { @MainActor [weak self] in
            self?.receive(kind: kind, data: payload)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let packet = WatchConnectivityWire.decode(userInfo) else { return }
        let kind = packet.kind
        let payload = packet.payload
        Task { @MainActor [weak self] in
            self?.receive(kind: kind, data: payload)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let packet = WatchConnectivityWire.decode(applicationContext) else { return }
        let kind = packet.kind
        let payload = packet.payload
        Task { @MainActor [weak self] in
            self?.receive(kind: kind, data: payload)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didFinish userInfoTransfer: WCSessionUserInfoTransfer,
        error: (any Error)?
    ) {
        Task { @MainActor [weak self] in
            if error != nil {
                self?.lastDiagnosticCode = "durable_transfer_failed"
            }
            self?.completeBackgroundTasksIfPossible()
        }
    }
}
