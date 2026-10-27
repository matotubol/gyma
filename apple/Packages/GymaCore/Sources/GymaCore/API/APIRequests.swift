import Foundation

// Request bodies. The API's schemas are strict: nullable keys must be sent as null, unknown keys are rejected.

public struct PlannedExerciseInput: Encodable, Sendable, Equatable {
    public var exerciseId: String
    public var sets: Int
    public var reps: Int
    public var plannedKg: Double

    public init(exerciseId: String, sets: Int, reps: Int, plannedKg: Double) {
        self.exerciseId = exerciseId; self.sets = sets; self.reps = reps; self.plannedKg = roundKg(plannedKg)
    }
}

public struct SaveWorkoutPlan: Encodable, Sendable {
    public var kind: DayKind?
    public var expectedVersion: Int
    public var exercises: [PlannedExerciseInput]

    public init(kind: DayKind?, expectedVersion: Int, exercises: [PlannedExerciseInput]) {
        self.kind = kind; self.expectedVersion = expectedVersion; self.exercises = exercises
    }

    enum CodingKeys: String, CodingKey { case kind, expectedVersion, exercises }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(expectedVersion, forKey: .expectedVersion)
        try container.encode(exercises, forKey: .exercises)
    }
}

public struct CreateExercise: Encodable, Sendable {
    public var name: String
    public var equipment: Equipment
    public var brand: Brand?

    public init(name: String, equipment: Equipment, brand: Brand?) {
        self.name = name; self.equipment = equipment; self.brand = equipment.hasBrand ? brand : nil
    }

    enum CodingKeys: String, CodingKey { case name, equipment, brand }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(equipment, forKey: .equipment)
        try container.encode(brand, forKey: .brand)
    }
}

/// Planned targets for adding or editing an exercise inside a started workout.
public struct ExerciseTargets: Sendable, Equatable {
    public var exerciseId: String
    public var plannedSets: Int
    public var plannedReps: Int
    public var plannedKg: Double

    public init(exerciseId: String, plannedSets: Int, plannedReps: Int, plannedKg: Double) {
        self.exerciseId = exerciseId; self.plannedSets = plannedSets; self.plannedReps = plannedReps; self.plannedKg = roundKg(plannedKg)
    }
}

struct StartSessionBody: Encodable { let expectedPlanVersion: Int }
struct VersionBody: Encodable { let expectedVersion: Int }
struct StartSetBody: Encodable { let setId: String; let exercisePosition: Int; let expectedVersion: Int }
struct ConfirmSetBody: Encodable { let actualKg: Double; let actualReps: Int; let expectedVersion: Int }
struct LogSetBody: Encodable { let actualKg: Double; let actualReps: Int; let expectedVersion: Int; let setId: String; let exercisePosition: Int }
struct EditExerciseBody: Encodable {
    let exerciseId: String; let plannedSets: Int; let plannedReps: Int; let plannedKg: Double
    let expectedVersion: Int; let allowReassign: Bool
}
struct AddExerciseBody: Encodable {
    let exerciseId: String; let plannedSets: Int; let plannedReps: Int; let plannedKg: Double
    let expectedVersion: Int; let entryId: String
}

/// The API accepts kilograms with at most two decimals.
public func roundKg(_ kg: Double) -> Double { (kg * 100).rounded() / 100 }
