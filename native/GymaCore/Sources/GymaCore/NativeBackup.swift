import Foundation

/// A full-fidelity native archive. Companion snapshots deliberately use a separate, bounded format.
public enum NativeBackup {
    public static func decode(_ data: Data) throws -> GymaState {
        guard data.count <= 100 * 1024 * 1024 else { throw GymaError.invalid("Backup exceeds 100 MB.") }
        let state = try JSONDecoder().decode(GymaState.self, from: data)
        try state.validate()
        return state
    }
    public static func encode(_ state: GymaState) throws -> Data {
        try state.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(state)
    }
}
