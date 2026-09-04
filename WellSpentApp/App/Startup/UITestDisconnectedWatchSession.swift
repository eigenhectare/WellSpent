#if DEBUG
    import Foundation
    import WatchConnectivity

    /// UI and model fixtures must never publish their catalog to a paired device.
    @MainActor
    final class UITestDisconnectedWatchSession: IPhoneWatchConnectivitySession {
        var activationState: WCSessionActivationState = .notActivated
        let isPaired = false
        let isWatchAppInstalled = false
        let isReachable = false
        var outstandingUserInfoPackets: [[String: Any]] = []

        func configure(delegate: any WCSessionDelegate) {}
        func activate() { activationState = .activated }
        func sendMessage(_ message: [String: Any], errorHandler: (@Sendable (any Error) -> Void)?) {}
        func queueUserInfo(_ userInfo: [String: Any]) { outstandingUserInfoPackets.append(userInfo) }
        func publishApplicationContext(_ applicationContext: [String: Any]) throws {}
    }
#endif
