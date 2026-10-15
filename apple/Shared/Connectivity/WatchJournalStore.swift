import Foundation

/// Owns journal file I/O. The session validates snapshots and publishes only after saving.
struct WatchJournalStore {
    let url: URL
    private static let maximumBytes = 256 * 1024

    func load() throws -> WatchJournal {
        guard FileManager.default.fileExists(atPath: url.path) else { return WatchJournal() }
        let data = try Data(contentsOf: url)
        guard data.count <= Self.maximumBytes else { throw ConnectivityError.invalidJournal }
        return try JSONDecoder().decode(WatchJournal.self, from: data)
    }

    func save(_ journal: WatchJournal) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(journal)
        guard data.count <= Self.maximumBytes else { throw ConnectivityError.payloadTooLarge }
        try data.write(to: url, options: .atomic)
    }
}
