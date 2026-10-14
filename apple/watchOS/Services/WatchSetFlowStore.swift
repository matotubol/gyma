import Combine
import Foundation
import GymaCore

@MainActor
final class WatchSetFlowStore: ObservableObject {
    @Published private(set) var flow = WatchSetFlow()
    @Published private(set) var storageError: String?
    private let url: URL
    private var unreadable = false

    init() {
        url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GymaConnectivity", isDirectory: true)
            .appendingPathComponent("watch-set-flow.json")
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                guard data.count < 64 * 1024 else { throw GymaError.invalid("Saved Watch set is too large.") }
                flow = try JSONDecoder().decode(WatchSetFlow.self, from: data)
                try flow.validate()
            }
        } catch {
            unreadable = true
            storageError = "Your saved set could not be read. Reopen Gyma to retry; the draft is preserved."
        }
    }

    @discardableResult
    func update<T>(_ operation: (inout WatchSetFlow) throws -> T) throws -> T {
        guard !unreadable else { throw GymaError.invalid(storageError ?? "Watch storage is unavailable.") }
        var next = flow
        let result = try operation(&next)
        try next.validate()
        guard next != flow else { return result }
        do {
            let data = try JSONEncoder().encode(next)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            flow = next; storageError = nil
            return result
        } catch {
            storageError = "Your set could not be saved on this Watch. Free some storage and reopen Gyma."
            throw error
        }
    }
}
