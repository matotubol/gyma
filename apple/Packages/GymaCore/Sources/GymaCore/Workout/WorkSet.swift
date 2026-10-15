import Foundation

public enum SetEffort: String, Codable, CaseIterable, Sendable, Identifiable {
    case easy, challenging, limit
    public var id: String { rawValue }
    public var label: String {
        switch self { case .easy: return "Several more reps"; case .challenging: return "1–2 more reps"; case .limit: return "At my limit" }
    }
}

public struct WorkSet: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var kg: Double
    public var reps: Int
    public var effort: SetEffort?
    /// Nil means the user has not classified the set.
    public var isWarmup: Bool?
    public init(id: String = UUID().uuidString, kg: Double, reps: Int, effort: SetEffort? = nil, isWarmup: Bool? = nil) {
        self.id = id; self.kg = kg; self.reps = reps; self.effort = effort; self.isWarmup = isWarmup
    }
    public var volume: Double { kg * Double(reps) }
    public var oneRepMax: Double { reps <= 1 ? kg : kg * (1 + Double(reps) / 30) }
    public func validate() throws {
        guard !id.isEmpty, id.count <= 200, kg.isFinite, (0...1000).contains(kg), (1...10000).contains(reps) else { throw GymaError.invalid("Invalid completed set.") }
    }
}

/// A decision not to perform a planned set. Never counted as completed training.
public struct SkippedSet: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var skippedAt: Date
    public init(id: String = UUID().uuidString, skippedAt: Date = Date()) {
        self.id = id; self.skippedAt = skippedAt
    }
}
