import Foundation

extension GymaState {
    public var activeWorkout: Workout? { workouts.first { $0.isActive } }

    public mutating func startWorkout(_ workout: Workout) throws {
        guard activeWorkout == nil else { throw GymaError.invalid("Finish or resume your current workout first.") }
        if trainingCalendar != nil { try validateCalendarWorkoutStart(now: workout.start) }
        try workout.validate()
        guard workout.isActive, !workouts.contains(where: { $0.id == workout.id }), !deletedWorkouts.contains(where: { $0.id == workout.id }),
              workout.exercises.allSatisfy({ $0.sets.isEmpty }),
              workout.exercises.allSatisfy({ $0.skippedSetCount == 0 && $0.skippedRemainingAt == nil }),
              workout.exercises.allSatisfy({ $0.snapshotWorkingSetCount == nil }), workout.restHistory?.isEmpty ?? true,
              Set(workout.exercises.map(\.exerciseID)).count == workout.exercises.count else { throw GymaError.invalid("A new workout needs unique exercises and no completed sets.") }
        for entry in workout.exercises where !catalog.contains(where: { $0.id == entry.exerciseID }) { throw GymaError.invalid("Unknown exercise in workout.") }
        workouts.insert(workout, at: 0); restTimer = nil; revision += 1
    }

    public mutating func addExercise(_ exerciseID: String, to workoutID: String) throws {
        let index = try activeIndex(workoutID)
        guard catalog.contains(where: { $0.id == exerciseID }), !workouts[index].exercises.contains(where: { $0.exerciseID == exerciseID }) else { throw GymaError.invalid("Exercise is unknown or already in this workout.") }
        workouts[index].exercises.append(.init(exerciseID: exerciseID)); revision += 1
    }
    public mutating func addSet(_ set: WorkSet, exerciseID: String, workoutID: String, now: Date = Date()) throws {
        try set.validate()
        guard set.kg <= 1000, set.reps <= 10000 else { throw GymaError.invalid("Set exceeds supported logging limits.") }
        let wi = try activeIndex(workoutID)
        let ei = try exerciseIndex(exerciseID, in: wi)
        try validateEventDate(now, workoutIndex: wi)
        guard !workouts[wi].exercises.flatMap(\.sets).contains(where: { $0.id == set.id }) else { throw GymaError.invalid("This set was already logged.") }
        try completeRest(at: now)
        workouts[wi].exercises[ei].sets.append(set)
        let entry = workouts[wi].exercises[ei]
        if canRest(workout: workouts[wi], entry: entry) {
            let seconds = entry.target?.restSeconds ?? 120
            restTimer = RestTimer(workoutID: workoutID, exerciseID: exerciseID, startedAt: now, endsAt: now.addingTimeInterval(Double(seconds)), sourceSetID: set.id, plannedSeconds: seconds)
        }
        revision += 1
    }
    public mutating func removeSet(_ setID: String, exerciseID: String, workoutID: String) throws {
        let wi = try activeIndex(workoutID); let ei = try exerciseIndex(exerciseID, in: wi)
        guard let si = workouts[wi].exercises[ei].sets.firstIndex(where: { $0.id == setID }) else { throw GymaError.stale("That set is no longer in this workout.") }
        workouts[wi].exercises[ei].sets.remove(at: si)
        workouts[wi].restHistory?.removeAll { $0.sourceSetID == setID }
        if restTimer?.exerciseID == exerciseID { restTimer = nil }
        revision += 1
    }
    public mutating func removeExercise(_ exerciseID: String, workoutID: String) throws {
        let wi = try activeIndex(workoutID); let ei = try exerciseIndex(exerciseID, in: wi)
        workouts[wi].exercises.remove(at: ei)
        if workouts[wi].selectedExerciseID == exerciseID { workouts[wi].selectedExerciseID = nil }
        workouts[wi].restHistory?.removeAll { $0.exerciseID == exerciseID }
        if restTimer?.exerciseID == exerciseID { restTimer = nil }
        revision += 1
    }
    public mutating func updateTarget(_ target: ExerciseTarget?, exerciseID: String, workoutID: String) throws {
        try target?.validate()
        let wi = try activeIndex(workoutID); let ei = try exerciseIndex(exerciseID, in: wi)
        workouts[wi].exercises[ei].target = target
        workouts[wi].exercises[ei].skippedRemainingAt = nil
        if restTimer?.exerciseID == exerciseID, target == nil || !canRest(workout: workouts[wi], entry: workouts[wi].exercises[ei]) { restTimer = nil }
        revision += 1
    }
    /// Changes only today's next exercise; earlier unfinished exercises remain available.
    public mutating func selectExercise(_ exerciseID: String, workoutID: String, now: Date = Date()) throws {
        let wi = try activeIndex(workoutID); let ei = try exerciseIndex(exerciseID, in: wi)
        try validateEventDate(now, workoutIndex: wi)
        guard !workouts[wi].exercises[ei].isTargetResolved else {
            throw GymaError.stale("That exercise has no remaining sets. Choose another exercise.")
        }
        try completeRest(at: now)
        workouts[wi].selectedExerciseID = exerciseID
        revision += 1
    }
    public mutating func skipSet(exerciseID: String, workoutID: String, now: Date = Date()) throws {
        let wi = try activeIndex(workoutID); let ei = try exerciseIndex(exerciseID, in: wi)
        try validateEventDate(now, workoutIndex: wi)
        guard !workouts[wi].exercises[ei].isTargetResolved, workouts[wi].exercises[ei].remainingSetCount > 0 else {
            throw GymaError.stale("That exercise has no remaining planned sets to skip.")
        }
        try completeRest(at: now)
        if workouts[wi].exercises[ei].skippedSets == nil { workouts[wi].exercises[ei].skippedSets = [] }
        workouts[wi].exercises[ei].skippedSets?.append(.init(skippedAt: now))
        revision += 1
    }
    public mutating func skipExercise(exerciseID: String, workoutID: String, now: Date = Date()) throws {
        let wi = try activeIndex(workoutID); let ei = try exerciseIndex(exerciseID, in: wi)
        try validateEventDate(now, workoutIndex: wi)
        let entry = workouts[wi].exercises[ei]
        guard !entry.isTargetResolved else { throw GymaError.stale("That exercise has no remaining sets to skip.") }
        try completeRest(at: now)
        if entry.remainingSetCount > 0 {
            if workouts[wi].exercises[ei].skippedSets == nil { workouts[wi].exercises[ei].skippedSets = [] }
            workouts[wi].exercises[ei].skippedSets?.append(contentsOf: (0..<entry.remainingSetCount).map { _ in SkippedSet(skippedAt: now) })
        }
        workouts[wi].exercises[ei].skippedRemainingAt = now
        revision += 1
    }
    public mutating func updateCheckIn(_ checkIn: SessionCheckIn, workoutID: String) throws {
        try checkIn.validate()
        guard let wi = workouts.firstIndex(where: { $0.id == workoutID }) else { throw GymaError.stale("Workout no longer exists.") }
        workouts[wi].checkIn = checkIn; workouts[wi].shift = checkIn.shift; workouts[wi].energy = workouts[wi].readiness?.energy ?? checkIn.energy
        if workouts[wi].acceptedPlanID == nil, !checkIn.painNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, restTimer?.workoutID == workoutID { restTimer = nil }
        revision += 1
    }
    public mutating func finishWorkout(_ workoutID: String, at now: Date = Date()) throws {
        let wi = try activeIndex(workoutID)
        try validateEventDate(now, workoutIndex: wi)
        guard workouts[wi].restHistory?.allSatisfy({ $0.endedAt <= now }) ?? true else { throw GymaError.invalid("Workout cannot finish before a recorded rest ended.") }
        try completeRest(at: now)
        workouts[wi].end = now; restTimer = nil
        let review = WorkoutReview.make(workout: workouts[wi], history: workouts, program: trainingProgram, catalog: catalog, now: now, priorPrograms: programHistory ?? [])
        if workoutReviews == nil { workoutReviews = [] }
        workoutReviews?.removeAll { $0.workoutID == workoutID }
        workoutReviews?.append(review)
        revision += 1
    }
    public mutating func deleteWorkout(_ workoutID: String) throws {
        guard let wi = workouts.firstIndex(where: { $0.id == workoutID }) else { throw GymaError.stale("Workout no longer exists.") }
        deletedWorkouts.insert(workouts.remove(at: wi), at: 0)
        if restTimer?.workoutID == workoutID { restTimer = nil }; revision += 1
    }
    public mutating func restoreWorkout(_ workoutID: String) throws {
        guard let wi = deletedWorkouts.firstIndex(where: { $0.id == workoutID }) else { throw GymaError.stale("Deleted workout no longer exists.") }
        guard !deletedWorkouts[wi].isActive || activeWorkout == nil else { throw GymaError.invalid("Finish your active workout before restoring this one.") }
        workouts.append(deletedWorkouts.remove(at: wi)); workouts.sort { $0.start > $1.start }; revision += 1
    }
    public mutating func setRestEnabled(_ enabled: Bool) { restEnabled = enabled; if !enabled { restTimer = nil }; revision += 1 }
    public mutating func extendRest(timerID: String, seconds: Int = 30, now: Date = Date()) throws {
        guard var timer = restTimer, timer.id == timerID else { throw GymaError.stale("That rest timer has been replaced or stopped.") }
        guard (1...600).contains(seconds) else { throw GymaError.invalid("Rest extension must be between 1 and 600 seconds.") }
        let deadline = max(timer.endsAt, now).addingTimeInterval(Double(seconds))
        guard deadline.timeIntervalSince(timer.startedAt) <= 86400 else { throw GymaError.invalid("Rest timer exceeds 24 hours.") }
        timer.endsAt = deadline; restTimer = timer; revision += 1
    }
    public mutating func skipRest(timerID: String, now: Date = Date()) throws {
        guard restTimer?.id == timerID else { throw GymaError.stale("That rest timer has been replaced or stopped.") }
        try completeRest(at: now); revision += 1
    }
    private func validateEventDate(_ date: Date, workoutIndex: Int) throws {
        guard (-2_208_988_800.0...4_102_444_800.0).contains(date.timeIntervalSince1970), date >= workouts[workoutIndex].start,
              workouts[workoutIndex].exercises.allSatisfy({ exercise in
                  (exercise.skippedRemainingAt.map({ $0 <= date }) ?? true) &&
                  (exercise.skippedSets?.allSatisfy({ $0.skippedAt <= date }) ?? true)
              }),
              workouts[workoutIndex].restHistory?.allSatisfy({ $0.endedAt <= date }) ?? true else {
            throw GymaError.invalid("Workout events must occur after the session started.")
        }
    }
    private mutating func completeRest(at now: Date) throws {
        guard let timer = restTimer else { return }
        let wi = try activeIndex(timer.workoutID)
        try validateEventDate(now, workoutIndex: wi)
        guard now >= timer.startedAt else { throw GymaError.invalid("Rest cannot end before it started.") }
        let plannedSeconds = timer.plannedSeconds.map(Double.init) ?? timer.endsAt.timeIntervalSince(timer.startedAt)
        guard plannedSeconds.isFinite, (0...86400).contains(plannedSeconds) else { throw GymaError.invalid("Invalid rest timer duration.") }
        let rest = CompletedRest(id: timer.id, exerciseID: timer.exerciseID, sourceSetID: timer.sourceSetID,
                                 plannedSeconds: Int(plannedSeconds), startedAt: timer.startedAt, endedAt: now)
        try rest.validate()
        if workouts[wi].restHistory == nil { workouts[wi].restHistory = [] }
        if workouts[wi].restHistory?.contains(where: { $0.id == rest.id }) != true { workouts[wi].restHistory?.append(rest) }
        restTimer = nil
    }
    private func activeIndex(_ id: String) throws -> Int {
        guard let index = workouts.firstIndex(where: { $0.id == id && $0.isActive }) else { throw GymaError.stale("This workout is no longer active. Refresh from iPhone.") }
        return index
    }
    private func exerciseIndex(_ id: String, in workoutIndex: Int) throws -> Int {
        guard let index = workouts[workoutIndex].exercises.firstIndex(where: { $0.exerciseID == id }) else { throw GymaError.stale("This exercise is no longer in the workout.") }
        return index
    }
    internal func canRest(workout: Workout, entry: WorkoutExercise) -> Bool {
        restEnabled && workout.isActive && entry.sets.last?.isWarmup == false &&
        (workout.acceptedPlanID != nil || (workout.checkIn?.painNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)) &&
        !entry.isTargetResolved
    }
}
