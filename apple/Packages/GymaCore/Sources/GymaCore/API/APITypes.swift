import Foundation

// Mirrors gym-web's /api/v1 contract (web/src/types.ts and the Zod schemas).

public enum DayKind: String, Codable, Sendable, CaseIterable {
    case training, rest
}

public enum Equipment: String, Codable, Sendable, CaseIterable {
    case machine, cable, dumbbell, barbell, bodyweight, other

    public var label: String { self == .other ? "Other equipment" : rawValue.capitalized }
    public var hasBrand: Bool { self == .machine || self == .cable }
}

public enum Brand: String, Codable, Sendable, CaseIterable {
    case matrix = "Matrix"
    case panatta = "Panatta"
}

public struct CalendarDay: Codable, Sendable, Equatable {
    public let date: String
    public let kind: DayKind?
    public let version: Int
    public let updatedAt: String
    public let exerciseCount: Int
}

public struct LibraryExercise: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let equipment: Equipment
    public let brand: Brand?

    public init(id: String, name: String, equipment: Equipment, brand: Brand?) {
        self.id = id; self.name = name; self.equipment = equipment; self.brand = brand
    }
}

public struct PlannedExercise: Codable, Sendable, Equatable {
    public let exerciseId: String
    public let name: String
    public let equipment: Equipment
    public let brand: Brand?
    public let sets: Int
    public let reps: Int
    public let plannedKg: Double

    public var library: LibraryExercise { LibraryExercise(id: exerciseId, name: name, equipment: equipment, brand: brand) }
}

public struct WorkoutPlan: Codable, Sendable, Equatable {
    public let date: String
    public let kind: DayKind?
    public let version: Int
    public let updatedAt: String?
    public let exercises: [PlannedExercise]
}

public struct SessionExercise: Codable, Sendable, Equatable, Identifiable {
    public let entryId: String
    public let position: Int
    public let exerciseId: String
    public let name: String
    public let equipment: Equipment
    public let brand: Brand?
    public let plannedSets: Int
    public let plannedReps: Int
    public let plannedKg: Double

    public var id: String { entryId }
    public var library: LibraryExercise { LibraryExercise(id: exerciseId, name: name, equipment: equipment, brand: brand) }
}

public enum SetStatus: String, Codable, Sendable {
    case active, completed, cancelled
}

public struct PerformedSet: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let exercisePosition: Int
    public let setNumber: Int
    public let status: SetStatus
    public let startedAt: String
    public let completedAt: String?
    public let actualKg: Double?
    public let actualReps: Int?
    public let recordedManually: Bool
}

public struct LiftedSet: Codable, Sendable, Hashable {
    public var kg: Double
    public var reps: Int

    public init(kg: Double, reps: Int) { self.kg = kg; self.reps = reps }
}

public struct ExerciseHistory: Codable, Sendable, Equatable {
    public let exerciseId: String
    public let lastDate: String
    public let lastSets: [LiftedSet]
    public let bestRepsByKg: [LiftedSet]
    public let bestVolume: Double

    public init(exerciseId: String, lastDate: String, lastSets: [LiftedSet], bestRepsByKg: [LiftedSet], bestVolume: Double) {
        self.exerciseId = exerciseId; self.lastDate = lastDate; self.lastSets = lastSets
        self.bestRepsByKg = bestRepsByKg; self.bestVolume = bestVolume
    }
}

public enum SessionStatus: String, Codable, Sendable {
    case active, completed
}

public struct WorkoutSession: Codable, Sendable, Equatable {
    public let id: String
    public let date: String
    public let planVersion: Int
    public let version: Int
    public let status: SessionStatus
    public let startedAt: String
    public let completedAt: String?
    public let exercises: [SessionExercise]
    public let sets: [PerformedSet]
    public let history: [ExerciseHistory]
}

public struct ExerciseProgressPoint: Codable, Sendable, Equatable, Identifiable {
    public let date: String
    public let sets: Int
    public let bestKg: Double
    public let bestReps: Int
    public let maxReps: Int
    public let volume: Double

    public var id: String { date }
}

public struct ExerciseProgress: Codable, Sendable, Equatable {
    public let exercise: LibraryExercise
    public let sessions: [ExerciseProgressPoint]
}

/// Opaque 32-character lowercase hex ID, as the API requires for client-chosen set and entry IDs.
public func newEntityID() -> String {
    UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
}
