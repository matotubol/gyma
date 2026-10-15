import Foundation

public struct CompanionSnapshot: Codable, Sendable, Equatable {
    public var storeID: String
    public var revision: Int
    public var generatedAt: Date
    public var activeWorkout: Workout?
    public var readyPlan: ReadyWorkoutPlan?
    public var catalog: [ExerciseDefinition]
    public var restTimer: RestTimer?
    public var isTruncated: Bool
    /// Distinguishes a bounded set window from omitted exercises when deciding whether the session is complete.
    public var totalExerciseCount: Int?
    public init(state: GymaState, now: Date = Date(), calendar: Calendar = .current) {
        let calendar = state.planningCalendar(fallback: calendar)
        storeID = state.storeID; revision = state.revision; generatedAt = now; restTimer = state.restTimer; isTruncated = false
        totalExerciseCount = state.activeWorkout?.exercises.count
        if state.activeWorkout == nil, state.coachConversation?.startedWorkoutID == nil,
           let plan = state.coachConversation?.plan, plan.acceptedAt != nil,
           state.canStartAcceptedPlan(plan, now: now, calendar: calendar) { readyPlan = ReadyWorkoutPlan(plan: plan, calendar: calendar) }
        if readyPlan == nil { readyPlan = state.readyProgramPlan(now: now, calendar: calendar) }
        var workout = state.activeWorkout
        if var current = workout {
            // Sync only the active session and a bounded recent set window. Phone keeps full history.
            isTruncated = current.exercises.count > 12 || current.exercises.contains { $0.sets.count > 20 }
            var visibleExercises = Array(current.exercises.prefix(12))
            if let selected = current.nextExercise, !visibleExercises.contains(where: { $0.exerciseID == selected.exerciseID }) {
                visibleExercises[visibleExercises.count - 1] = selected
            }
            current.exercises = visibleExercises.map { item in
                var item = item; item.snapshotWorkingSetCount = item.workingSetCount; item.sets = Array(item.sets.suffix(20))
                if var target = item.target { target.reason = String(target.reason.prefix(200)); item.target = target }
                return item
            }
            if !current.exercises.contains(where: { $0.exerciseID == current.selectedExerciseID }) { current.selectedExerciseID = nil }
            current.planTitle = current.planTitle.map { String($0.prefix(160)) }
            // Notes and other sensitive history are not needed for watch controls.
            current.checkIn = nil; current.coachConversation = nil
            if let rest = current.restHistory?.last,
               current.exercises.contains(where: { $0.exerciseID == rest.exerciseID && $0.sets.contains(where: { $0.id == rest.sourceSetID }) }) {
                current.restHistory = [rest]
            } else { current.restHistory = nil }
            workout = current
        }
        activeWorkout = workout
        catalog = (workout?.exercises ?? []).map { entry in
            var definition = state.exercise(entry.exerciseID); definition.name = String(definition.name.prefix(200)); return definition
        }
        // Character limits alone do not bound UTF-8 size. Leave headroom below WCSession's message limit.
        let encoder = JSONEncoder()
        while (try? encoder.encode(self).count).map({ $0 > 48 * 1024 }) ?? true {
            if readyPlan != nil { readyPlan = nil; isTruncated = true; continue }
            guard var current = activeWorkout, !current.exercises.isEmpty else { break }
            isTruncated = true
            if let index = current.exercises.indices.max(by: { current.exercises[$0].sets.count < current.exercises[$1].sets.count }), !current.exercises[index].sets.isEmpty {
                current.exercises[index].sets.removeFirst()
            } else {
                current.exercises.removeLast(); catalog.removeLast()
                if !current.exercises.contains(where: { $0.exerciseID == current.selectedExerciseID }) { current.selectedExerciseID = nil }
            }
            if let rest = current.restHistory?.last,
               !current.exercises.contains(where: { $0.exerciseID == rest.exerciseID && $0.sets.contains(where: { $0.id == rest.sourceSetID }) }) { current.restHistory = nil }
            activeWorkout = current
        }
    }
}
