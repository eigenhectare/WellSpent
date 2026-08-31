import Foundation

/// A content-free, durable command handoff between the Live Activity intent
/// process and the app's authoritative SwiftData command layer.
public struct BillableHoursStopRequest: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let endedAt: Date
    public let endTimeZoneID: String

    public init(sessionID: UUID, endedAt: Date, endTimeZoneID: String) {
        self.sessionID = sessionID
        self.endedAt = endedAt
        self.endTimeZoneID = endTimeZoneID
    }
}

public enum BillableHoursStopHandoffError: LocalizedError, Equatable {
    case suiteUnavailable
    case persistenceFailed

    public var errorDescription: String? {
        switch self {
        case .suiteUnavailable:
            "The shared timer handoff is unavailable."
        case .persistenceFailed:
            "The stop request could not be saved."
        }
    }
}

public enum BillableHoursStopHandoff {
    public static let appGroupIdentifier = "group.com.drewreilly.billablehours"

    private static let requestFilePrefix = "request."
    private static let lock = NSLock()

    /// Persists the first captured stop for a session. Duplicate intent
    /// invocations keep the original timestamp, matching the idempotent timer
    /// command in the app.
    @discardableResult
    public static func persist(
        sessionID: UUID,
        endedAt: Date,
        endTimeZoneID: String,
        suiteName: String = appGroupIdentifier
    ) throws -> BillableHoursStopRequest {
        try withLock {
            let directoryURL = try storageDirectory(for: suiteName)
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            let fileURL = requestFileURL(for: sessionID, in: directoryURL)
            if let existing = try request(at: fileURL) {
                return existing
            }

            let persistedRequest = BillableHoursStopRequest(
                sessionID: sessionID,
                endedAt: endedAt,
                endTimeZoneID: endTimeZoneID
            )
            try JSONEncoder().encode(persistedRequest).write(to: fileURL, options: .atomic)
            return persistedRequest
        }
    }

    public static func pendingRequests(
        suiteName: String = appGroupIdentifier
    ) throws -> [BillableHoursStopRequest] {
        try withLock {
            let directoryURL = try storageDirectory(for: suiteName)
            guard FileManager.default.fileExists(atPath: directoryURL.path) else {
                return []
            }
            return try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
            )
            .filter { $0.lastPathComponent.hasPrefix(requestFilePrefix) }
            .compactMap { try request(at: $0) }
            .sorted {
                if $0.endedAt != $1.endedAt { return $0.endedAt < $1.endedAt }
                return $0.sessionID.uuidString < $1.sessionID.uuidString
            }
        }
    }

    /// Removes a handoff only after the app has durably applied it to the
    /// authoritative session store.
    public static func acknowledge(
        sessionID: UUID,
        suiteName: String = appGroupIdentifier
    ) throws {
        try withLock {
            let directoryURL = try storageDirectory(for: suiteName)
            let fileURL = requestFileURL(for: sessionID, in: directoryURL)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    public static func clear(
        suiteName: String = appGroupIdentifier
    ) throws {
        try withLock {
            let directoryURL = try storageDirectory(for: suiteName)
            guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }
            for fileURL in try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
            ) where fileURL.lastPathComponent.hasPrefix(requestFilePrefix) {
                try FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    private static func request(at fileURL: URL) throws -> BillableHoursStopRequest? {
        do {
            return try JSONDecoder().decode(
                BillableHoursStopRequest.self,
                from: Data(contentsOf: fileURL)
            )
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // Another process may acknowledge a request after directory listing.
            return nil
        }
    }

    private static func storageDirectory(for suiteName: String) throws -> URL {
        if suiteName == appGroupIdentifier {
            guard
                let containerURL = FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: suiteName
                )
            else {
                throw BillableHoursStopHandoffError.suiteUnavailable
            }
            return
                containerURL
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent("BillableHours", isDirectory: true)
                .appendingPathComponent("StopHandoff", isDirectory: true)
        }

        let encodedSuiteName = Data(suiteName.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("BillableHoursStopHandoffTests", isDirectory: true)
            .appendingPathComponent(encodedSuiteName, isDirectory: true)
    }

    private static func withLock<Result>(
        _ operation: () throws -> Result
    ) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }

    private static func requestFileURL(for sessionID: UUID, in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent(
            requestFilePrefix + sessionID.uuidString + ".json",
            isDirectory: false
        )
    }
}
