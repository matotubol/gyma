import Foundation

/// Call from one serialized owner (the iPhone MainActor store). Atomic saves include mutations and command receipts.
public struct JSONFileStore: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> GymaState {
        guard FileManager.default.fileExists(atPath: url.path) else { return GymaState() }
        let data = try Data(contentsOf: url)
        let state = try JSONDecoder().decode(GymaState.self, from: data)
        try state.validate(); return state
    }
    public func save(_ state: GymaState) throws {
        try state.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Foundation writes a sibling temporary file and atomically replaces the destination.
        // Load failures are propagated and the original file is never silently replaced.
        try data.write(to: url, options: [.atomic])
    }
}
