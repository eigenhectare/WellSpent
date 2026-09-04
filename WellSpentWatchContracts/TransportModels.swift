import Foundation

public enum WatchConnectivityPayloadKind: String, Codable, Equatable, Sendable {
    case acknowledgement
    case mutation
    case snapshot
    case snapshotReceipt = "snapshot_receipt"
}

/// The property-list-safe wrapper used by every production WCSession path.
/// The optional opaque identifier lets senders suppress an already-queued
/// durable transfer without decoding or logging its content.
public enum WatchConnectivityWire {
    public static let kindKey = "wellspent.kind"
    public static let payloadKey = "wellspent.payload"
    public static let identifierKey = "wellspent.identifier"

    public static func packet(
        kind: WatchConnectivityPayloadKind,
        payload: Data,
        identifier: UUID? = nil
    ) -> [String: Any] {
        var packet: [String: Any] = [
            kindKey: kind.rawValue,
            payloadKey: payload,
        ]
        if let identifier {
            packet[identifierKey] = identifier.uuidString
        }
        return packet
    }

    public static func decode(
        _ packet: [String: Any]
    ) -> (kind: WatchConnectivityPayloadKind, payload: Data, identifier: UUID?)? {
        guard let rawKind = packet[kindKey] as? String,
            let kind = WatchConnectivityPayloadKind(rawValue: rawKind),
            let payload = packet[payloadKey] as? Data
        else { return nil }
        let identifier = (packet[identifierKey] as? String).flatMap(UUID.init(uuidString:))
        return (kind, payload, identifier)
    }
}

public struct MutationTransportHeader: Codable, Equatable, Sendable {
    public let protocolMajor: UInt16
    public let protocolMinor: UInt16
    public let schemaVersion: UInt16
    public let mutationID: UUID
    public let originDeviceID: UUID
    public let originSequence: UInt64
    public let payloadDigest: SHA256Digest
}
