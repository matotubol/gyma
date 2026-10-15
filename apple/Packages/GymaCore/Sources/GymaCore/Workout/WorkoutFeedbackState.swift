import Foundation

public extension GymaState {
    mutating func saveWorkoutFeedback(_ feedback: WorkoutFeedback) throws {
        try feedback.validate()
        guard workouts.contains(where: { $0.id == feedback.workoutID && !$0.isActive }) else {
            throw GymaError.stale("Feedback belongs to a completed workout.")
        }
        if workoutFeedback == nil { workoutFeedback = [] }
        workoutFeedback?.removeAll { $0.workoutID == feedback.workoutID }
        workoutFeedback?.append(feedback)
        coachConversation?.plan?.acceptedAt = nil
        coachConversation?.proposedProgram = nil
        revision += 1
    }
}
