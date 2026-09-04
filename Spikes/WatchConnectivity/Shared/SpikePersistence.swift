import Foundation

struct SpikeStateStore {
    enum StoreError: Error {
        case applicationSupportUnavailable
    }

    let stateURL: URL

    init(stateURL: URL? = nil) throws {
        if let stateURL {
            self.stateURL = stateURL
            return
        }
        guard let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw StoreError.applicationSupportUnavailable
        }
        self.stateURL = root
            .appendingPathComponent("WellSpentConnectivitySpike", isDirectory: true)
            .appendingPathComponent("state.json")
    }

    func load() throws -> SpikePersistentState? {
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return nil
        }
        return try SpikeCodec.decode(
            SpikePersistentState.self,
            from: Data(contentsOf: stateURL)
        )
    }

    func save(_ state: SpikePersistentState) throws {
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try SpikeCodec.encode(state).write(to: stateURL, options: [.atomic])
    }

    func evidenceURL(for state: SpikePersistentState) throws -> URL {
        let url = stateURL.deletingLastPathComponent()
            .appendingPathComponent("evidence.json")
        try SpikeCodec.encode(state.events).write(to: url, options: [.atomic])
        return url
    }
}
