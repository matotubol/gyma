import Foundation

public struct GymaState: Codable, Sendable, Equatable {
    public var schemaVersion = 1
    public var storeID = UUID().uuidString
    public var revision = 0
    public var workouts: [Workout] = []
    public var deletedWorkouts: [Workout] = []
    public var customExercises: [ExerciseDefinition] = []
    public var restEnabled = true
    public var restTimer: RestTimer?
    public var commandReceipts: [String: CommandAcknowledgement] = [:]
    public var commandPayloads: [String: Data] = [:]

    public init() {}
    public var activeWorkout: Workout? { workouts.first { $0.isActive } }
    public var catalog: [ExerciseDefinition] { ExerciseCatalog.builtIn + customExercises }
    public func exercise(_ id: String) -> ExerciseDefinition {
        catalog.first { $0.id == id } ?? .init(id: id, name: "Unknown exercise", muscle: .core, iconKey: "bolt")
    }
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
            guard !exercise.id.isEmpty, exercise.id.count <= 200, !exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  exercise.name.count <= 200, exercise.iconKey.count <= 100,
                  exerciseIDs.insert(exercise.id).inserted else { throw GymaError.invalid("Invalid custom exercise identity or name.") }
        }
        guard (workouts + deletedWorkouts).allSatisfy({ workout in
            workout.exercises.allSatisfy { exerciseIDs.contains($0.exerciseID) }
        }) else { throw GymaError.invalid("A workout refers to an exercise missing from the catalog.") }
        if let timer = restTimer {
            let supportedDates = -2_208_988_800.0...4_102_444_800.0
            guard restEnabled, !timer.id.isEmpty, timer.id.count <= 200,
                  supportedDates.contains(timer.startedAt.timeIntervalSince1970), supportedDates.contains(timer.endsAt.timeIntervalSince1970), timer.endsAt >= timer.startedAt,
                  timer.endsAt.timeIntervalSince(timer.startedAt) <= 86400,
                  let workout = activeWorkout, workout.id == timer.workoutID,
                  let exercise = workout.exercises.first(where: { $0.exerciseID == timer.exerciseID }),
                  exercise.sets.last?.id == timer.sourceSetID,
                  exercise.sets.last?.isWarmup == false, canRest(workout: workout, entry: exercise) else { throw GymaError.invalid("Rest timer no longer matches the active workout.") }
        }
    }
    public mutating func startWorkout(_ workout: Workout) throws {
        guard activeWorkout == nil else { throw GymaError.invalid("Finish or resume your current workout first.") }
        try workout.validate()
        guard workout.isActive, !workouts.contains(where: { $0.id == workout.id }), !deletedWorkouts.contains(where: { $0.id == workout.id }),
              workout.exercises.allSatisfy({ $0.sets.isEmpty }),
              Set(workout.exercises.map(\.exerciseID)).count == workout.exercises.count else { throw GymaError.invalid("A new workout needs unique exercises and no completed sets.") }
        for entry in workout.exercises where !catalog.contains(where: { $0.id == entry.exerciseID }) { throw GymaError.invalid("Unknown exercise in workout.") }
        workouts.insert(workout, at: 0); restTimer = nil; revision += 1
    }
    public mutating func addCustomExercise(_ exercise: ExerciseDefinition) throws {
        guard !catalog.contains(where: { $0.id == exercise.id }), !exercise.id.isEmpty, exercise.id.count <= 200,
              !exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, exercise.name.count <= 200,
              exercise.iconKey.count <= 100 else { throw GymaError.invalid("Custom exercise must have a unique identity and a name of at most 200 characters.") }
        var item = exercise; item.custom = true; customExercises.append(item); revision += 1
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
        guard !workouts[wi].exercises.flatMap(\.sets).contains(where: { $0.id == set.id }) else { throw GymaError.invalid("This set was already logged.") }
        workouts[wi].exercises[ei].sets.append(set)
        restTimer = nil
        let entry = workouts[wi].exercises[ei]
        if canRest(workout: workouts[wi], entry: entry) {
            let seconds = entry.target?.restSeconds ?? 120
            restTimer = RestTimer(workoutID: workoutID, exerciseID: exerciseID, startedAt: now, endsAt: now.addingTimeInterval(Double(seconds)), sourceSetID: set.id)
        }
        revision += 1
    }
    public mutating func removeSet(_ setID: String, exerciseID: String, workoutID: String) throws {
        let wi = try activeIndex(workoutID); let ei = try exerciseIndex(exerciseID, in: wi)
        guard let si = workouts[wi].exercises[ei].sets.firstIndex(where: { $0.id == setID }) else { throw GymaError.stale("That set is no longer in this workout.") }
        workouts[wi].exercises[ei].sets.remove(at: si)
        if restTimer?.exerciseID == exerciseID { restTimer = nil }
        revision += 1
    }
    public mutating func removeExercise(_ exerciseID: String, workoutID: String) throws {
        let wi = try activeIndex(workoutID); let ei = try exerciseIndex(exerciseID, in: wi)
        workouts[wi].exercises.remove(at: ei)
        if restTimer?.exerciseID == exerciseID { restTimer = nil }
        revision += 1
    }
    public mutating func updateTarget(_ target: ExerciseTarget?, exerciseID: String, workoutID: String) throws {
        try target?.validate()
        let wi = try activeIndex(workoutID); let ei = try exerciseIndex(exerciseID, in: wi)
        workouts[wi].exercises[ei].target = target
        if restTimer?.exerciseID == exerciseID, target == nil || !canRest(workout: workouts[wi], entry: workouts[wi].exercises[ei]) { restTimer = nil }
        revision += 1
    }
    public mutating func updateCheckIn(_ checkIn: SessionCheckIn, workoutID: String) throws {
        try checkIn.validate()
        guard let wi = workouts.firstIndex(where: { $0.id == workoutID }) else { throw GymaError.stale("Workout no longer exists.") }
        workouts[wi].checkIn = checkIn; workouts[wi].shift = checkIn.shift; workouts[wi].energy = checkIn.energy
        if !checkIn.painNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, restTimer?.workoutID == workoutID { restTimer = nil }
        revision += 1
    }
    public mutating func finishWorkout(_ workoutID: String, at now: Date = Date()) throws {
        let wi = try activeIndex(workoutID)
        guard now >= workouts[wi].start else { throw GymaError.invalid("Workout cannot finish before it started.") }
        workouts[wi].end = now; restTimer = nil; revision += 1
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
    public mutating func skipRest(timerID: String) throws {
        guard restTimer?.id == timerID else { throw GymaError.stale("That rest timer has been replaced or stopped.") }
        restTimer = nil; revision += 1
    }
    private func activeIndex(_ id: String) throws -> Int {
        guard let index = workouts.firstIndex(where: { $0.id == id && $0.isActive }) else { throw GymaError.stale("This workout is no longer active. Refresh from iPhone.") }
        return index
    }
    private func exerciseIndex(_ id: String, in workoutIndex: Int) throws -> Int {
        guard let index = workouts[workoutIndex].exercises.firstIndex(where: { $0.exerciseID == id }) else { throw GymaError.stale("This exercise is no longer in the workout.") }
        return index
    }
    private func canRest(workout: Workout, entry: WorkoutExercise) -> Bool {
        restEnabled && workout.isActive && entry.sets.last?.isWarmup == false &&
        (workout.checkIn?.painNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) &&
        (entry.target.map { entry.sets.filter { $0.isWarmup == false }.count < $0.sets } ?? true)
    }
}
