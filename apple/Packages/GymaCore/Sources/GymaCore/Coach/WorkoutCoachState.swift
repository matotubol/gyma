import Foundation

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
            if change.effectiveAction == .updateTarget {
                try CoachingConstraints.validate(exercises: [.init(exerciseID: change.replacementExerciseID ?? change.exerciseID, target: change.target)], profile: athleteProfile, catalog: catalog)
            }
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
        if change.effectiveAction == .updateTarget {
            try CoachingConstraints.validate(exercises: [.init(exerciseID: change.replacementExerciseID ?? change.exerciseID, target: change.target)], profile: athleteProfile, catalog: catalog)
        }
        guard let exerciseIndex = workouts[index].exercises.firstIndex(where: { $0.exerciseID == change.exerciseID }) else {
            throw GymaError.stale("This exercise is no longer in the workout.")
        }
        var next = self
        switch change.effectiveAction {
        case .updateTarget:
            if let replacement = change.replacementExerciseID {
                try next.replaceExercise(change.exerciseID, with: replacement, workoutID: workoutID, target: change.target)
            } else {
                // A target adjustment does not shorten a rest already in progress.
                next.workouts[index].exercises[exerciseIndex].target = change.target
                next.revision += 1
            }
        case .selectExercise:
            try next.selectExercise(change.exerciseID, workoutID: workoutID)
        case .skipSet:
            try next.skipSet(exerciseID: change.exerciseID, workoutID: workoutID)
        case .skipExercise:
            try next.skipExercise(exerciseID: change.exerciseID, workoutID: workoutID)
        }
        next.workouts[index].coachConversation?.proposal = nil
        self = next
    }

    mutating func dismissWorkoutCoachChange(workoutID: String) throws {
        guard let index = workouts.firstIndex(where: { $0.id == workoutID && $0.isActive }) else {
            throw GymaError.stale("This workout has ended.")
        }
        workouts[index].coachConversation?.proposal = nil
    }
}
