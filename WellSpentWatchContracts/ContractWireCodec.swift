import Foundation

public enum ContractWireCodec {
    public static func encodeMutation(_ mutation: TimerMutationEnvelope) throws -> Data {
        guard mutation.hasValidDigest() else {
            throw ContractWireError.digestMismatch
        }
        let data = try encodeCanonical(mutation)
        guard data.count <= WellSpentWatchContract.maximumMutationBytes else {
            throw ContractWireError.payloadTooLarge
        }
        return data
    }

    public static func decodeMutation(_ data: Data) throws -> TimerMutationEnvelope {
        guard data.count <= WellSpentWatchContract.maximumMutationBytes else {
            throw ContractWireError.payloadTooLarge
        }

        let header: MutationVersionHeader = try decodeCanonical(data)
        guard
            WellSpentWatchContract.supportedVersions.supports(
                protocolVersion: ContractVersion(
                    major: header.protocolMajor,
                    minor: header.protocolMinor
                ),
                schemaVersion: header.schemaVersion
            )
        else {
            throw ContractWireError.unsupportedProtocol
        }
        let mutation: TimerMutationEnvelope = try decodeCanonical(data)
        guard mutation.originSequence > 0, !mutation.capturedTimeZoneID.isEmpty else {
            throw ContractWireError.invalidEnvelope
        }
        guard (mutation.observedRunID == nil) == (mutation.observedRunRevision == nil) else {
            throw ContractWireError.invalidEnvelope
        }
        guard mutation.hasValidDigest() else {
            throw ContractWireError.digestMismatch
        }
        return mutation
    }

    /// Reads only the stable outer identity. This deliberately does not reject
    /// an unsupported protocol/action so the phone can durably retain and
    /// acknowledge otherwise identifiable input without decoding its payload.
    public static func decodeMutationHeader(_ data: Data) throws -> MutationTransportHeader {
        guard data.count <= WellSpentWatchContract.maximumMutationBytes else {
            throw ContractWireError.payloadTooLarge
        }
        return try decodeCanonical(MutationTransportHeader.self, from: data)
    }

    public static func encodeSnapshot(_ snapshot: TimerSnapshotEnvelope) throws -> Data {
        guard
            WellSpentWatchContract.supportedVersions.supports(
                protocolVersion: snapshot.protocolVersion,
                schemaVersion: snapshot.schemaVersion
            )
        else {
            throw ContractWireError.unsupportedProtocol
        }
        let data = try encodeCanonical(snapshot)
        guard data.count <= WellSpentWatchContract.maximumSnapshotBytes else {
            throw ContractWireError.payloadTooLarge
        }
        return data
    }

    public static func decodeSnapshot(_ data: Data) throws -> TimerSnapshotEnvelope {
        guard data.count <= WellSpentWatchContract.maximumSnapshotBytes else {
            throw ContractWireError.payloadTooLarge
        }

        let snapshot: TimerSnapshotEnvelope = try decodeCanonical(data)
        guard
            WellSpentWatchContract.supportedVersions.supports(
                protocolVersion: snapshot.protocolVersion,
                schemaVersion: snapshot.schemaVersion
            )
        else {
            throw ContractWireError.unsupportedProtocol
        }
        return snapshot
    }

    public static func encodeCanonical<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(value)
        } catch let error as ContractWireError {
            throw error
        } catch {
            throw ContractWireError.invalidEnvelope
        }
    }

    public static func decodeCanonical<Value: Decodable>(
        _ type: Value.Type = Value.self,
        from data: Data
    ) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        do {
            return try decoder.decode(type, from: data)
        } catch let error as ContractWireError {
            throw error
        } catch {
            throw ContractWireError.malformedPayload
        }
    }

    private static func decodeCanonical<Value: Decodable>(_ data: Data) throws -> Value {
        try decodeCanonical(Value.self, from: data)
    }
}

private struct MutationVersionHeader: Decodable {
    let protocolMajor: UInt16
    let protocolMinor: UInt16
    let schemaVersion: UInt16
}
