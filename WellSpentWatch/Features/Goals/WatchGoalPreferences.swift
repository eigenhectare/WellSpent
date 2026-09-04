import Foundation

struct WatchGoalPreferences: Codable, Equatable {
    var alertsEnabled = false
    var recentGoalSeconds: [Int] = []
    var acknowledgedGoal: String?
    var storeOriginID: UUID?

    mutating func recordGoal(_ seconds: Int?) {
        guard let seconds, seconds >= 300, seconds <= 28_800, seconds % 300 == 0 else { return }
        recentGoalSeconds = Array(([seconds] + recentGoalSeconds.filter { $0 != seconds }).prefix(3))
    }

    mutating func sanitize() {
        var seen = Set<Int>()
        recentGoalSeconds = Array(
            recentGoalSeconds.filter {
                $0 >= 300 && $0 <= 28_800 && $0 % 300 == 0 && seen.insert($0).inserted
            }.prefix(3))
        if let acknowledgedGoal, acknowledgedGoal.count > 64 { self.acknowledgedGoal = nil }
    }
}

@MainActor
protocol WatchGoalPreferenceStore {
    func load() throws -> WatchGoalPreferences
    func save(_ preferences: WatchGoalPreferences) throws
}

/// Watch-local preferences contain no project names, notes, or tags. Keep the
/// bounded file protected and out of backups, just like the timer cache.
@MainActor
final class WatchGoalFilePreferences: WatchGoalPreferenceStore {
    private let url: URL

    init(url: URL? = nil) throws {
        self.url =
            try url
            ?? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: false
            )
            .appendingPathComponent("WatchGoalAlerts", isDirectory: true)
            .appendingPathComponent("preferences.json")
    }

    func load() throws -> WatchGoalPreferences {
        guard FileManager.default.fileExists(atPath: url.path) else { return WatchGoalPreferences() }
        let data = try Data(contentsOf: url)
        guard data.count <= 16_384 else { throw CocoaError(.fileReadCorruptFile) }
        var preferences = try JSONDecoder().decode(WatchGoalPreferences.self, from: data)
        preferences.sanitize()
        return preferences
    }

    func save(_ preferences: WatchGoalPreferences) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try protect(directory)
        try JSONEncoder().encode(preferences).write(
            to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try protect(url)
    }

    private func protect(_ url: URL) throws {
        var protectedURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedURL.setResourceValues(values)
        #if !targetEnvironment(simulator)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path)
        #endif
    }
}

#if DEBUG
    @MainActor
    final class WatchGoalMemoryPreferences: WatchGoalPreferenceStore {
        var value = WatchGoalPreferences()
        func load() -> WatchGoalPreferences { value }
        func save(_ preferences: WatchGoalPreferences) { value = preferences }
    }
#endif

@MainActor
final class WatchGoalUnavailablePreferences: WatchGoalPreferenceStore {
    func load() throws -> WatchGoalPreferences { throw CocoaError(.fileReadNoPermission) }
    func save(_ preferences: WatchGoalPreferences) throws { throw CocoaError(.fileWriteNoPermission) }
}
