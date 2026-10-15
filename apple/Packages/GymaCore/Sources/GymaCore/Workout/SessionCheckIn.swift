import Foundation

public enum Energy: String, Codable, CaseIterable, Sendable, Identifiable {
    case great, good, medium, poor
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
}

public struct SessionCheckIn: Codable, Sendable, Equatable {
    public var shift: Shift
    public var energy: Energy
    public var timeMinutes: Int
    public var sleepHours: Double?
    public var notes: String
    public var recentTrainingNote: String
    public var painNote: String
    public var soreness: [Muscle: Soreness]?
    public init(shift: Shift, energy: Energy, timeMinutes: Int = 45, sleepHours: Double? = nil, notes: String = "", recentTrainingNote: String = "", painNote: String = "", soreness: [Muscle: Soreness]? = nil) {
        self.shift = shift; self.energy = energy; self.timeMinutes = timeMinutes; self.sleepHours = sleepHours; self.notes = notes; self.recentTrainingNote = recentTrainingNote; self.painNote = painNote; self.soreness = soreness
    }
    public func soreness(for muscle: Muscle) -> Soreness { soreness?[muscle] ?? .none }
    public var allSoreness: [Muscle: Soreness] { Dictionary(uniqueKeysWithValues: Muscle.allCases.map { ($0, soreness(for: $0)) }) }
    public func validate() throws {
        guard (10...180).contains(timeMinutes), sleepHours.map({ $0.isFinite && (0...24).contains($0) }) ?? true,
              [notes, recentTrainingNote, painNote].allSatisfy({ $0.count <= 2000 }) else {
            throw GymaError.invalid("Invalid session check-in.")
        }
    }
}
