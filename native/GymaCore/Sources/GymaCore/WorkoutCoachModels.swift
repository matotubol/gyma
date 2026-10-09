import Foundation

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

    public init(id: String = UUID().uuidString, storeID: String, workoutID: String, basedOnRevision: Int,
                exerciseID: String, replacementExerciseID: String? = nil, target: ExerciseTarget, reason: String) {
        self.id = id; self.storeID = storeID; self.workoutID = workoutID; self.basedOnRevision = basedOnRevision
        self.exerciseID = exerciseID; self.replacementExerciseID = replacementExerciseID
        self.target = target; self.reason = reason
    }

    public func validate() throws {
        guard [id, storeID, workoutID, exerciseID].allSatisfy({ !$0.isEmpty && $0.count <= 200 }),
              replacementExerciseID.map({ !$0.isEmpty && $0.count <= 200 && $0 != exerciseID }) ?? true,
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
              !exercise.isTargetComplete, target.sets > exercise.workingSetCount else {
            throw GymaError.stale("That exercise has changed or is complete. Ask the coach to review the current workout.")
        }
        guard catalog.contains(where: { $0.id == exerciseID }) else { throw GymaError.invalid("This exercise is no longer in your library.") }
        if let replacementExerciseID {
            guard exercise.sets.isEmpty, catalog.contains(where: { $0.id == replacementExerciseID }),
                  !workout.exercises.contains(where: { $0.exerciseID == replacementExerciseID }) else {
                throw GymaError.invalid("Only an exercise with no logged sets can be replaced with an unused exercise from your library.")
            }
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

public extension GymaState {
    mutating func appendWorkoutCoachMessage(_ text: String, workoutID: String) throws {
        guard let index = workouts.firstIndex(where: { $0.id == workoutID }) else {
            throw GymaError.stale("This workout is no longer available.")
        }
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var conversation = workouts[index].coachConversation ?? WorkoutCoachConversation()
        // Retrying the last unanswered message never duplicates it.
        if conversation.messages.last?.role != .user || conversation.messages.last?.content != content {
            conversation.messages.append(CoachMessage(role: .user, content: content))
        }
        conversation.proposal = nil
        try conversation.validate()
        workouts[index].coachConversation = conversation
        // Chat alone does not change the training revision or invalidate Watch commands.
    }

    mutating func saveWorkoutCoachReply(_ reply: WorkoutCoachReply, workoutID: String,
                                       expectedStoreID: String, expectedRevision: Int,
                                       expectedConversation: WorkoutCoachConversation) throws {
        guard storeID == expectedStoreID, revision == expectedRevision,
              let index = workouts.firstIndex(where: { $0.id == workoutID }),
              workouts[index].coachConversation == expectedConversation else {
            throw GymaError.stale("Your workout changed while the coach was replying. Send again for advice based on your latest sets.")
        }
        let message = reply.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, message.count <= 8000 else { throw GymaError.invalid("The coach returned an invalid message.") }
        if let change = reply.change {
            guard change.storeID == storeID, change.basedOnRevision == revision else {
                throw GymaError.stale("The proposed change is based on an earlier workout. Ask again with your latest sets.")
            }
            try change.validate(for: workouts[index], catalog: catalog)
            try CoachingConstraints.validate(exercises: [.init(exerciseID: change.replacementExerciseID ?? change.exerciseID, target: change.target)], profile: athleteProfile, catalog: catalog)
        }
        var conversation = expectedConversation
        conversation.messages.append(CoachMessage(role: .assistant, content: message))
        conversation.proposal = reply.change
        try conversation.validate()
        workouts[index].coachConversation = conversation
    }

    mutating func applyWorkoutCoachChange(_ changeID: String, workoutID: String) throws {
        guard let index = workouts.firstIndex(where: { $0.id == workoutID && $0.isActive }),
              let change = workouts[index].coachConversation?.proposal, change.id == changeID,
              change.storeID == storeID, change.basedOnRevision == revision else {
            throw GymaError.stale("Your workout changed after this suggestion. Ask the coach to update it before applying.")
        }
        try change.validate(for: workouts[index], catalog: catalog)
        try CoachingConstraints.validate(exercises: [.init(exerciseID: change.replacementExerciseID ?? change.exerciseID, target: change.target)], profile: athleteProfile, catalog: catalog)
        guard let exerciseIndex = workouts[index].exercises.firstIndex(where: { $0.exerciseID == change.exerciseID }) else {
            throw GymaError.stale("This exercise is no longer in the workout.")
        }
        // Completed sets, completed rests and the currently running rest stay intact.
        if let replacement = change.replacementExerciseID { workouts[index].exercises[exerciseIndex].exerciseID = replacement }
        workouts[index].exercises[exerciseIndex].target = change.target
        workouts[index].coachConversation?.proposal = nil
        revision += 1
    }

    mutating func dismissWorkoutCoachChange(workoutID: String) throws {
        guard let index = workouts.firstIndex(where: { $0.id == workoutID && $0.isActive }) else {
            throw GymaError.stale("This workout has ended.")
        }
        workouts[index].coachConversation?.proposal = nil
    }
}
