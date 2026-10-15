import Foundation

public enum WorkoutCoachAction: String, Codable, Sendable {
    case updateTarget, selectExercise, skipSet, skipExercise
}

/// A proposed edit is bound to the training state that the coach actually saw.
public struct WorkoutCoachChange: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var storeID: String
    public var workoutID: String
    public var basedOnRevision: Int
    public var exerciseID: String
    public var replacementExerciseID: String?
    public var target: ExerciseTarget
    public var reason: String
    /// Missing on older saved proposals, which only adjusted targets or substituted exercises.
    public var action: WorkoutCoachAction?
    public var effectiveAction: WorkoutCoachAction { action ?? .updateTarget }

    public init(id: String = UUID().uuidString, storeID: String, workoutID: String, basedOnRevision: Int,
                exerciseID: String, replacementExerciseID: String? = nil, target: ExerciseTarget, reason: String,
                action: WorkoutCoachAction? = nil) {
        self.id = id; self.storeID = storeID; self.workoutID = workoutID; self.basedOnRevision = basedOnRevision
        self.exerciseID = exerciseID; self.replacementExerciseID = replacementExerciseID
        self.target = target; self.reason = reason; self.action = action
    }

    public func validate() throws {
        guard [id, storeID, workoutID, exerciseID].allSatisfy({ !$0.isEmpty && $0.count <= 200 }),
              replacementExerciseID.map({ !$0.isEmpty && $0.count <= 200 && $0 != exerciseID }) ?? true,
              effectiveAction == .updateTarget || replacementExerciseID == nil,
              (0...1_000_000_000).contains(basedOnRevision),
              !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reason.count <= 2000 else {
            throw GymaError.invalid("The coach suggested an invalid workout change.")
        }
        try target.validate()
    }

    public func validate(for workout: Workout, catalog: [ExerciseDefinition]) throws {
        try validate()
        guard workout.isActive, workout.id == workoutID,
              let exercise = workout.exercises.first(where: { $0.exerciseID == exerciseID }),
              !exercise.isTargetResolved else {
            throw GymaError.stale("That exercise has changed or is complete. Ask the coach to review the current workout.")
        }
        guard catalog.contains(where: { $0.id == exerciseID }) else { throw GymaError.invalid("This exercise is no longer in your library.") }
        if let replacementExerciseID {
            guard catalog.contains(where: { $0.id == replacementExerciseID }),
                  !workout.exercises.contains(where: { $0.exerciseID == replacementExerciseID }) else {
                throw GymaError.invalid("Choose an unused exercise from your library. Logged sets stay with the original exercise.")
            }
        } else if effectiveAction == .updateTarget, target.sets <= exercise.resolvedSetCount {
            throw GymaError.invalid("The new target must leave room for upcoming sets. Use Skip set or Stop exercise to cancel planned work.")
        }
        if effectiveAction == .skipSet, exercise.target == nil {
            throw GymaError.invalid("This exercise has no planned set to skip. Stop the exercise instead.")
        }
    }
}

public struct WorkoutCoachConversation: Codable, Sendable, Equatable {
    public var messages: [CoachMessage]
    public var proposal: WorkoutCoachChange?
    public init(messages: [CoachMessage] = [], proposal: WorkoutCoachChange? = nil) {
        self.messages = messages; self.proposal = proposal
    }
    public func validate() throws {
        guard messages.count <= 200, Set(messages.map(\.id)).count == messages.count,
              messages.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 200 && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.content.count <= 16_000 }),
              messages.reduce(0, { $0 + $1.content.utf8.count }) <= 512_000 else {
            throw GymaError.invalid("This workout's coach conversation is too long. Keep your next question shorter.")
        }
        try proposal?.validate()
    }
}

public struct WorkoutCoachReply: Sendable, Equatable {
    public var message: String
    public var change: WorkoutCoachChange?
    public init(message: String, change: WorkoutCoachChange? = nil) { self.message = message; self.change = change }
}
