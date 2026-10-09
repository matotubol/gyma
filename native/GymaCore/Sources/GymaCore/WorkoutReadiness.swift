import Foundation

public enum Soreness: String, Codable, CaseIterable, Sendable, Identifiable {
    case none, mild, moderate, high
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
    public static var allNone: [Muscle: Soreness] {
        Dictionary(uniqueKeysWithValues: Muscle.allCases.map { ($0, .none) })
    }
}

/// A fresh pre-start check, distinct from the earlier planning conversation.
public struct WorkoutReadiness: Codable, Sendable, Equatable {
    public var energy: Energy
    public var soreness: [Muscle: Soreness]
    public var recordedAt: Date
    public init(energy: Energy, soreness: [Muscle: Soreness] = Soreness.allNone, recordedAt: Date = Date()) {
        self.energy = energy; self.soreness = soreness; self.recordedAt = recordedAt
    }
    public func soreness(for muscle: Muscle) -> Soreness { soreness[muscle] ?? .none }
    public func validate() throws {
        guard Set(soreness.keys) == Set(Muscle.allCases),
              (-2_208_988_800.0...4_102_444_800.0).contains(recordedAt.timeIntervalSince1970) else {
            throw GymaError.invalid("Check your energy and soreness for every muscle before starting.")
        }
    }

    private enum CodingKeys: String, CodingKey { case energy, soreness, recordedAt }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        energy = try values.decode(Energy.self, forKey: .energy)
        recordedAt = try values.decode(Date.self, forKey: .recordedAt)
        let decoded = try values.decode([String: Soreness].self, forKey: .soreness)
        var entries: [Muscle: Soreness] = [:]
        for (key, value) in decoded {
            guard let muscle = Muscle(rawValue: key) else { throw GymaError.invalid("Unknown muscle in readiness check.") }
            entries[muscle] = value
        }
        soreness = entries
        try validate()
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(energy, forKey: .energy)
        try values.encode(recordedAt, forKey: .recordedAt)
        // String keys let sortedKeys produce stable command bytes across process restarts.
        try values.encode(Dictionary(uniqueKeysWithValues: soreness.map { ($0.key.rawValue, $0.value) }), forKey: .soreness)
    }
}
