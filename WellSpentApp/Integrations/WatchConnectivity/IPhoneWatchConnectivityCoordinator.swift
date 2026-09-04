import Combine
import Foundation
@preconcurrency import WatchConnectivity
import WellSpentWatchContracts

enum IPhoneWatchConnectivityState: Equatable {
    case activating
    case available(reachable: Bool)
    case unavailable
}

@MainActor
protocol IPhoneWatchConnectivitySession: AnyObject {
    var activationState: WCSessionActivationState { get }
    var isPaired: Bool { get }
    var isWatchAppInstalled: Bool { get }
    var isReachable: Bool { get }
    var outstandingUserInfoPackets: [[String: Any]] { get }

    func configure(delegate: any WCSessionDelegate)
    func activate()
    func sendMessage(
        _ message: [String: Any],
        errorHandler: (@Sendable (any Error) -> Void)?
    )
    func queueUserInfo(_ userInfo: [String: Any])
    func publishApplicationContext(_ applicationContext: [String: Any]) throws
}

extension WCSession: IPhoneWatchConnectivitySession {
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

    func publishApplicationContext(_ applicationContext: [String: Any]) throws {
        try updateApplicationContext(applicationContext)
    }
}

@MainActor
final class IPhoneWatchConnectivityCoordinator: NSObject, ObservableObject {
    @Published private(set) var state: IPhoneWatchConnectivityState = .activating
    @Published private(set) var pendingAcknowledgementCount = 0
    @Published private(set) var lastDiagnosticCode: String?

    var onCanonicalMutationApplied: (() -> Void)?
    var onStatusChanged: (() -> Void)?

    private let syncStore: PhoneWatchSyncStore
    private let session: any IPhoneWatchConnectivitySession
    private let now: () -> Date

    init(
        syncStore: PhoneWatchSyncStore,
        session: any IPhoneWatchConnectivitySession = WCSession.default,
        now: @escaping () -> Date = Date.init
    ) {
        self.syncStore = syncStore
        self.session = session
        self.now = now
        super.init()
    }

    func activate() {
        session.configure(delegate: self)
        session.activate()
        refreshState()
    }

    func publishLatestSnapshot() {
        defer { onStatusChanged?() }
        guard session.activationState == .activated,
            session.isPaired,
            session.isWatchAppInstalled
        else {
            refreshState()
            return
        }
        do {
            let snapshot = try syncStore.makeSnapshot()
            let data = try ContractWireCodec.encodeSnapshot(snapshot)
            try session.publishApplicationContext(
                WatchConnectivityWire.packet(
                    kind: .snapshot,
                    payload: data,
                    identifier: snapshot.ledgerHead.snapshotID
                )
            )
            lastDiagnosticCode = nil
        } catch {
            lastDiagnosticCode = "snapshot_publish_failed"
        }
    }

    func retryPendingTransfers() {
        defer { onStatusChanged?() }
        do {
            let result = try syncStore.processReceivedInbox()
            if !result.acknowledgements.isEmpty {
                onCanonicalMutationApplied?()
            }
            dispatchPendingAcknowledgements(forceDurable: true)
            publishLatestSnapshot()
        } catch {
            lastDiagnosticCode = "inbox_resume_failed"
        }
    }

    #if DEBUG
        func receiveForTesting(kind: WatchConnectivityPayloadKind, data: Data) {
            receive(kind: kind, data: data)
        }
    #endif

    private func receive(kind: WatchConnectivityPayloadKind, data: Data) {
        do {
            switch kind {
            case .mutation:
                let result = try syncStore.receiveMutationData(data, receivedAt: now())
                if !result.acknowledgements.isEmpty {
                    onCanonicalMutationApplied?()
                }
                dispatchPendingAcknowledgements(forceDurable: false)
                publishLatestSnapshot()
            case .snapshotReceipt:
                try syncStore.receiveSnapshotReceiptData(data)
                updatePendingCount()
            case .acknowledgement, .snapshot:
                lastDiagnosticCode = "unexpected_payload"
            }
        } catch {
            lastDiagnosticCode = "payload_receive_failed"
        }
        onStatusChanged?()
    }

    private func dispatchPendingAcknowledgements(forceDurable: Bool) {
        guard session.activationState == .activated else {
            updatePendingCount()
            return
        }
        do {
            let pending = try syncStore.pendingAcknowledgements()
            let outstandingIDs = Set(
                session.outstandingUserInfoPackets.compactMap {
                    WatchConnectivityWire.decode($0)?.identifier
                }
            )
            for item in pending {
                let packet = WatchConnectivityWire.packet(
                    kind: .acknowledgement,
                    payload: item.data,
                    identifier: item.acknowledgementID
                )
                if session.isReachable {
                    session.sendMessage(packet) { _ in }
                }
                if forceDurable || !outstandingIDs.contains(item.acknowledgementID) {
                    session.queueUserInfo(packet)
                    try syncStore.recordAcknowledgementAttempt(id: item.acknowledgementID, at: now())
                }
            }
            pendingAcknowledgementCount = pending.count
            lastDiagnosticCode = nil
        } catch {
            lastDiagnosticCode = "ack_dispatch_failed"
            updatePendingCount()
        }
    }

    private func updatePendingCount() {
        pendingAcknowledgementCount = (try? syncStore.pendingAcknowledgements().count) ?? 0
    }

    private func refreshState() {
        defer { onStatusChanged?() }
        guard session.activationState == .activated,
            session.isPaired,
            session.isWatchAppInstalled
        else {
            state = session.activationState == .notActivated ? .activating : .unavailable
            return
        }
        state = .available(reachable: session.isReachable)
    }
}

extension IPhoneWatchConnectivityCoordinator: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.refreshState()
            if error != nil {
                self.lastDiagnosticCode = "session_activation_failed"
                return
            }
            self.retryPendingTransfers()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.refreshState()
            if session.isReachable {
                self?.dispatchPendingAcknowledgements(forceDurable: false)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let packet = WatchConnectivityWire.decode(message) else { return }
        Task { @MainActor [weak self] in
            self?.receive(kind: packet.kind, data: packet.payload)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let packet = WatchConnectivityWire.decode(userInfo) else { return }
        Task { @MainActor [weak self] in
            self?.receive(kind: packet.kind, data: packet.payload)
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.refreshState()
            self?.retryPendingTransfers()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.refreshState() }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.refreshState()
            self.session.activate()
        }
    }
}
