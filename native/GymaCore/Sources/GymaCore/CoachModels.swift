import Foundation

public struct CoachMessage: Codable, Sendable, Identifiable, Equatable {
    public enum Role: String, Codable, Sendable { case user, assistant }
    public var id: String
    public var role: Role
    public var content: String
    public init(id: String = UUID().uuidString, role: Role, content: String) {
        self.id = id; self.role = role; self.content = content
    }
}

/// A proposed session stays separate from workout history until explicitly accepted and started.
public struct WorkoutPlan: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var exercises: [WorkoutExercise]
    public var checkIn: SessionCheckIn
    public var createdAt: Date
    public var acceptedAt: Date?
    public init(id: String = UUID().uuidString, title: String, exercises: [WorkoutExercise], checkIn: SessionCheckIn, createdAt: Date = Date(), acceptedAt: Date? = nil) {
        self.id = id; self.title = title; self.exercises = exercises; self.checkIn = checkIn; self.createdAt = createdAt; self.acceptedAt = acceptedAt
    }
    public func validate(catalog: [ExerciseDefinition]) throws {
        let supportedDates = -2_208_988_800.0...4_102_444_800.0
        guard !id.isEmpty, id.count <= 200, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 200,
              supportedDates.contains(createdAt.timeIntervalSince1970),
              acceptedAt.map({ supportedDates.contains($0.timeIntervalSince1970) && $0 >= createdAt }) ?? true,
              (1...12).contains(exercises.count), Set(exercises.map(\.exerciseID)).count == exercises.count else {
            throw GymaError.invalid("A workout plan needs a title and 1–12 unique exercises.")
        }
        try checkIn.validate()
        let catalogIDs = Set(catalog.map(\.id))
        for exercise in exercises {
            guard catalogIDs.contains(exercise.exerciseID), exercise.sets.isEmpty, exercise.snapshotWorkingSetCount == nil, let target = exercise.target else {
                throw GymaError.invalid("Every planned exercise needs a known exercise and a target, with no completed sets.")
            }
            try target.validate()
        }
    }
}

public struct CoachConversation: Codable, Sendable, Equatable {
    public var checkIn: SessionCheckIn
    public var messages: [CoachMessage]
    public var plan: WorkoutPlan?
    public var startedWorkoutID: String?
    public init(checkIn: SessionCheckIn, messages: [CoachMessage] = [], plan: WorkoutPlan? = nil) {
        self.checkIn = checkIn; self.messages = messages; self.plan = plan
    }
    public func validate(catalog: [ExerciseDefinition]) throws {
        try checkIn.validate()
        guard startedWorkoutID.map({ !$0.isEmpty && $0.count <= 200 && plan == nil }) ?? true else {
            throw GymaError.invalid("Start a new check-in before planning your next workout.")
        }
        guard messages.count <= 200, Set(messages.map(\.id)).count == messages.count,
              messages.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 200 && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.content.count <= 16_000 }),
              messages.reduce(0, { $0 + $1.content.utf8.count }) <= 512_000 else {
            throw GymaError.invalid("The coach conversation is invalid or too long. Start a new conversation.")
        }
        if let plan {
            try plan.validate(catalog: catalog)
            guard plan.checkIn == checkIn else { throw GymaError.invalid("The workout plan must match the current check-in.") }
        }
    }
}
