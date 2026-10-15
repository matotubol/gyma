import Foundation

extension GymaState {
    public func validate() throws {
        // Keep wire revisions representable on watchOS arm64_32 as well as iPhone.
        guard schemaVersion == 1, !storeID.isEmpty, storeID.count <= 200, (0...1_000_000_000).contains(revision), workouts.filter(\.isActive).count <= 1 else { throw GymaError.invalid("Invalid state version or multiple active workouts.") }
        guard commandReceipts.count <= 50_000, Set(commandReceipts.keys) == Set(commandPayloads.keys),
              commandReceipts.allSatisfy({ key, receipt in
                  key == receipt.commandID && !key.isEmpty && key.count <= 200 &&
                  receipt.revision >= 0 && receipt.revision <= revision && receipt.status != .duplicate
              }), commandPayloads.values.allSatisfy({ $0.count <= 16_384 }) else { throw GymaError.invalid("Invalid command receipt ledger.") }
        var ids = Set<String>()
        for workout in workouts + deletedWorkouts {
            guard ids.insert(workout.id).inserted else { throw GymaError.invalid("Duplicate workout identity.") }
            try workout.validate()
        }
        var exerciseIDs = Set(ExerciseCatalog.builtIn.map(\.id))
        for exercise in customExercises {
            try exercise.metadata?.validate()
            guard !exercise.id.isEmpty, exercise.id.count <= 200, !exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  exercise.name.count <= 200, exercise.iconKey.count <= 100,
                  exerciseIDs.insert(exercise.id).inserted else { throw GymaError.invalid("Invalid custom exercise identity or name.") }
        }
        let builtInIDs = Set(ExerciseCatalog.builtIn.map(\.id))
        var overrideIDs = Set<String>()
        for exercise in exerciseOverrides ?? [] {
            try exercise.metadata?.validate()
            guard builtInIDs.contains(exercise.id), overrideIDs.insert(exercise.id).inserted,
                  !exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  exercise.name.count <= 200, exercise.iconKey.count <= 100 else {
                throw GymaError.invalid("Invalid built-in exercise override.")
            }
        }
        let hidden = hiddenExerciseIDs ?? []
        guard Set(hidden).count == hidden.count, Set(hidden).isSubset(of: exerciseIDs) else {
            throw GymaError.invalid("Invalid removed exercise identities.")
        }
        guard (workouts + deletedWorkouts).allSatisfy({ workout in
            workout.exercises.allSatisfy { exerciseIDs.contains($0.exerciseID) && $0.snapshotWorkingSetCount == nil }
        }) else { throw GymaError.invalid("A workout refers to an exercise missing from the catalog.") }
        try coachConversation?.validate(catalog: catalog)
        try athleteProfile?.validate()
        try trainingProgram?.validate(catalog: catalog)
        try trainingCalendar?.validate()
        try trainingCalendar?.validateWorkoutOverrides(catalog: catalog)
        guard (trainingCalendarHistory?.count ?? 0) <= 100 else {
            throw GymaError.invalid("Calendar history can contain at most 100 saved blocks.")
        }
        for plan in trainingCalendarHistory ?? [] {
            try plan.validate()
            try plan.validateWorkoutOverrides(catalog: catalog)
        }
        for program in programHistory ?? [] { try program.validate(catalog: catalog) }
        guard (programHistory?.count ?? 0) <= 100,
              Set((workoutReviews ?? []).map(\.workoutID)).count == (workoutReviews?.count ?? 0) else {
            throw GymaError.invalid("Invalid coaching history.")
        }
        for review in workoutReviews ?? [] {
            try review.validate()
            guard (workouts + deletedWorkouts).contains(where: { $0.id == review.workoutID && !$0.isActive }) else {
                throw GymaError.invalid("A workout review must belong to completed training.")
            }
        }
        guard Set((workoutFeedback ?? []).map(\.workoutID)).count == (workoutFeedback?.count ?? 0) else {
            throw GymaError.invalid("Duplicate workout feedback.")
        }
        for feedback in workoutFeedback ?? [] {
            try feedback.validate()
            guard (workouts + deletedWorkouts).contains(where: { $0.id == feedback.workoutID && !$0.isActive }) else {
                throw GymaError.invalid("Feedback must belong to a completed workout.")
            }
        }
        if let timer = restTimer {
            let supportedDates = -2_208_988_800.0...4_102_444_800.0
            guard restEnabled, !timer.id.isEmpty, timer.id.count <= 200,
                  supportedDates.contains(timer.startedAt.timeIntervalSince1970), supportedDates.contains(timer.endsAt.timeIntervalSince1970), timer.endsAt >= timer.startedAt,
                  timer.endsAt.timeIntervalSince(timer.startedAt) <= 86400,
                  timer.plannedSeconds.map({ (15...600).contains($0) }) ?? true,
                  let workout = activeWorkout, workout.id == timer.workoutID,
                  timer.startedAt >= workout.start,
                  let exercise = workout.exercises.first(where: { $0.exerciseID == timer.exerciseID }),
                  exercise.sets.last?.id == timer.sourceSetID,
                  exercise.sets.last?.isWarmup == false, canRest(workout: workout, entry: exercise) else { throw GymaError.invalid("Rest timer no longer matches the active workout.") }
        }
    }
}
