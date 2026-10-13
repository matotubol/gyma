import Foundation

public extension GymaState {
    /// Changes only this session's order; recurring program sessions stay unchanged.
    mutating func reorderExercises(_ exerciseIDs: [String], workoutID: String) throws {
        guard let wi = workouts.firstIndex(where: { $0.id == workoutID && $0.isActive }) else {
            throw GymaError.stale("This workout is no longer active.")
        }
        let entries = workouts[wi].exercises
        guard exerciseIDs.count == entries.count, Set(exerciseIDs).count == entries.count,
              Set(exerciseIDs) == Set(entries.map(\.exerciseID)) else {
            throw GymaError.stale("The exercise list changed. Open it again before reordering.")
        }
        workouts[wi].exercises = exerciseIDs.compactMap { id in entries.first { $0.exerciseID == id } }
        revision += 1
    }

    /// Retains any logged work under its original exercise and substitutes only the remaining work.
    mutating func replaceExercise(_ exerciseID: String, with replacementExerciseID: String,
                                  workoutID: String, target: ExerciseTarget? = nil, now: Date = Date()) throws {
        guard let wi = workouts.firstIndex(where: { $0.id == workoutID && $0.isActive }),
              let ei = workouts[wi].exercises.firstIndex(where: { $0.exerciseID == exerciseID }) else {
            throw GymaError.stale("This exercise is no longer in an active workout.")
        }
        guard catalog.contains(where: { $0.id == replacementExerciseID }),
              !workouts[wi].exercises.contains(where: { $0.exerciseID == replacementExerciseID }) else {
            throw GymaError.invalid("Choose an exercise from your library that is not already in this workout.")
        }
        let original = workouts[wi].exercises[ei]
        guard !original.isTargetResolved else { throw GymaError.stale("This exercise has no remaining planned sets to replace.") }
        var replacementTarget = target ?? original.target
        if target == nil, original.target != nil {
            replacementTarget?.sets = original.remainingSetCount
            // Loads do not transfer reliably between different movements or machines.
            replacementTarget?.loadKg = nil
        }
        try replacementTarget?.validate()
        let wasCurrent = workouts[wi].nextExercise?.exerciseID == exerciseID
        // Apply as one transaction so a rejected event date cannot partially replace an exercise.
        var next = self
        if original.sets.isEmpty && original.skippedSetCount == 0 {
            next.workouts[wi].exercises[ei] = .init(exerciseID: replacementExerciseID, target: replacementTarget)
            if next.workouts[wi].selectedExerciseID == exerciseID { next.workouts[wi].selectedExerciseID = replacementExerciseID }
        } else {
            try next.skipExercise(exerciseID: exerciseID, workoutID: workoutID, now: now)
            next.workouts[wi].exercises.insert(.init(exerciseID: replacementExerciseID, target: replacementTarget), at: ei + 1)
        }
        if wasCurrent { next.workouts[wi].selectedExerciseID = replacementExerciseID }
        next.revision = revision + 1
        self = next
    }
}
