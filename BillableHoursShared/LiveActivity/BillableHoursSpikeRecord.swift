import Foundation

/// A deliberately small FND-02 persistence model. FND-03 will replace this
/// spike store with the production local persistence design.
public struct BillableHoursSpikeRecord: Codable, Equatable, Sendable {
    public let activityID: UUID
    public let startedAt: Date
    public var endedAt: Date?

    public init(activityID: UUID, startedAt: Date, endedAt: Date? = nil) {
        self.activityID = activityID
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

public enum BillableHoursSpikeStorageError: LocalizedError, Equatable {
    case suiteUnavailable(String)
    case recordNotFound(UUID)
    case persistenceFailed

    public var errorDescription: String? {
        switch self {
        case .suiteUnavailable(let suiteName):
            "The shared defaults suite \(suiteName) is unavailable."
        case .recordNotFound(let activityID):
            "No spike record exists for \(activityID.uuidString)."
        case .persistenceFailed:
            "The exact stop time could not be flushed to shared storage."
        }
    }
}

public enum BillableHoursSpikeStorage {
    public static let appGroupIdentifier = "group.com.drewreilly.billablehours"

    private static let keyPrefix = "fnd02.live-activity."
    private static let activeActivityKey = keyPrefix + "active-id"
    private static let pendingCompletionKey = keyPrefix + "pending-completion-id"

    @discardableResult
    public static func begin(
        activityID: UUID,
        at startedAt: Date,
        suiteName: String = appGroupIdentifier
    ) throws -> BillableHoursSpikeRecord {
        let record = BillableHoursSpikeRecord(activityID: activityID, startedAt: startedAt)
        let defaults = try defaults(for: suiteName)
        try save(record, to: defaults)
        defaults.set(activityID.uuidString, forKey: activeActivityKey)
        try flush(defaults)
        return record
    }

    /// Persists before returning so callers can end the ActivityKit activity
    /// only after the source of truth contains the exact captured timestamp.
    @discardableResult
    public static func stop(
        activityID: UUID,
        at endedAt: Date,
        suiteName: String = appGroupIdentifier
    ) throws -> BillableHoursSpikeRecord {
        let defaults = try defaults(for: suiteName)
        guard var stoppedRecord = try record(activityID: activityID, defaults: defaults) else {
            throw BillableHoursSpikeStorageError.recordNotFound(activityID)
        }

        if stoppedRecord.endedAt == nil {
            stoppedRecord.endedAt = endedAt
            try save(stoppedRecord, to: defaults)
        }

        defaults.set(activityID.uuidString, forKey: pendingCompletionKey)
        try flush(defaults)

        guard let persisted = try record(activityID: activityID, defaults: defaults),
            persisted.endedAt == stoppedRecord.endedAt
        else {
            throw BillableHoursSpikeStorageError.persistenceFailed
        }
        return persisted
    }

    public static func record(
        activityID: UUID,
        suiteName: String = appGroupIdentifier
    ) throws -> BillableHoursSpikeRecord? {
        try record(activityID: activityID, defaults: defaults(for: suiteName))
    }

    public static func activeRecord(
        suiteName: String = appGroupIdentifier
    ) throws -> BillableHoursSpikeRecord? {
        let defaults = try defaults(for: suiteName)
        guard let rawID = defaults.string(forKey: activeActivityKey),
            let activityID = UUID(uuidString: rawID)
        else {
            return nil
        }
        return try record(activityID: activityID, defaults: defaults)
    }

    public static func consumePendingCompletionID(
        suiteName: String = appGroupIdentifier
    ) throws -> UUID? {
        let defaults = try defaults(for: suiteName)
        guard let rawID = defaults.string(forKey: pendingCompletionKey),
            let activityID = UUID(uuidString: rawID)
        else {
            return nil
        }
        defaults.removeObject(forKey: pendingCompletionKey)
        try flush(defaults)
        return activityID
    }

    public static func clearSpikeData(
        suiteName: String = appGroupIdentifier
    ) throws {
        let defaults = try defaults(for: suiteName)
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }
        try flush(defaults)
    }

    private static func record(
        activityID: UUID,
        defaults: UserDefaults
    ) throws -> BillableHoursSpikeRecord? {
        guard let data = defaults.data(forKey: recordKey(for: activityID)) else {
            return nil
        }
        return try JSONDecoder().decode(BillableHoursSpikeRecord.self, from: data)
    }

    private static func save(_ record: BillableHoursSpikeRecord, to defaults: UserDefaults) throws {
        let data = try JSONEncoder().encode(record)
        defaults.set(data, forKey: recordKey(for: record.activityID))
    }

    private static func defaults(for suiteName: String) throws -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw BillableHoursSpikeStorageError.suiteUnavailable(suiteName)
        }
        return defaults
    }

    private static func flush(_ defaults: UserDefaults) throws {
        guard defaults.synchronize() else {
            throw BillableHoursSpikeStorageError.persistenceFailed
        }
    }

    private static func recordKey(for activityID: UUID) -> String {
        keyPrefix + "record." + activityID.uuidString
    }
}

public enum BillableHoursDeepLink {
    public static let scheme = "billablehours"

    public static var trackerURL: URL {
        URL(string: "\(scheme)://track")!
    }

    public static func completionURL(for activityID: UUID) -> URL {
        URL(string: "\(scheme)://completion/\(activityID.uuidString)")!
    }

    public static func isTrackerURL(_ url: URL) -> Bool {
        url.scheme == scheme && url.host == "track" && (url.path.isEmpty || url.path == "/")
    }

    public static func completionActivityID(from url: URL) -> UUID? {
        guard url.scheme == scheme, url.host == "completion" else {
            return nil
        }
        return url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:))
    }
}
