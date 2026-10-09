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
    public var coachConversation: CoachConversation?
    public var athleteProfile: AthleteProfile?
    public var trainingProgram: TrainingProgram?
    public var programHistory: [TrainingProgram]?
    public var workoutReviews: [WorkoutReview]?
    public var workoutFeedback: [WorkoutFeedback]?
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
            try exercise.metadata?.validate()
            guard !exercise.id.isEmpty, exercise.id.count <= 200, !exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  exercise.name.count <= 200, exercise.iconKey.count <= 100,
                  exerciseIDs.insert(exercise.id).inserted else { throw GymaError.invalid("Invalid custom exercise identity or name.") }
        }
        guard (workouts + deletedWorkouts).allSatisfy({ workout in
            workout.exercises.allSatisfy { exerciseIDs.contains($0.exerciseID) && $0.snapshotWorkingSetCount == nil }
        }) else { throw GymaError.invalid("A workout refers to an exercise missing from the catalog.") }
        try coachConversation?.validate(catalog: catalog)
        try athleteProfile?.validate()
        try trainingProgram?.validate(catalog: catalog)
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
    public mutating func saveCoachConversation(_ conversation: CoachConversation) throws {
        var next = conversation
        if var plan = next.plan {
            var previous = coachConversation?.plan
            let acceptedAt = previous?.acceptedAt
            previous?.acceptedAt = nil
            let requestedAcceptance = plan.acceptedAt
            plan.acceptedAt = nil
            // Only the explicit accept operation can establish acceptance. Editing invalidates it.
            if plan == previous, requestedAcceptance == acceptedAt { plan.acceptedAt = acceptedAt }
            next.plan = plan
        }
        try next.validate(catalog: catalog)
        coachConversation = next; revision += 1
    }
    public mutating func acceptCoachPlan(planID: String, now: Date = Date()) throws {
        guard var conversation = coachConversation, var plan = conversation.plan, plan.id == planID else {
            throw GymaError.stale("That coach plan has changed. Review the current proposal first.")
        }
        try validateProgramLink(plan, now: now)
        try validatePlanningContext(plan)
        try CoachingConstraints.validate(exercises: plan.exercises, profile: athleteProfile, catalog: catalog)
        plan.acceptedAt = now; conversation.plan = plan
        try conversation.validate(catalog: catalog)
        coachConversation = conversation; revision += 1
    }
    @discardableResult
    public mutating func startAcceptedPlan(planID: String, readiness: WorkoutReadiness? = nil, now: Date = Date(), calendar: Calendar = .current) throws -> String {
        guard let conversation = coachConversation, let plan = conversation.plan, plan.id == planID, let acceptedAt = plan.acceptedAt else {
            throw GymaError.invalid("Review and accept the coach plan before starting a workout.")
        }
        try conversation.validate(catalog: catalog)
        guard plan.isScheduledForToday(at: now, calendar: calendar) else { throw GymaError.stale("This accepted plan is not scheduled for today. Update the plan on iPhone first.") }
        if let readiness {
            try readiness.validate()
            guard abs(now.timeIntervalSince(readiness.recordedAt)) <= 300 else { throw GymaError.stale("Your readiness check expired. Check your energy and soreness again before starting.") }
        }
        try validateProgramLink(plan, now: now)
        try validatePlanningContext(plan)
        try CoachingConstraints.validate(exercises: plan.exercises, profile: athleteProfile, catalog: catalog)
        var workout = Workout(start: now, shift: plan.checkIn.shift, energy: readiness?.energy ?? plan.checkIn.energy, checkIn: plan.checkIn, readiness: readiness,
                              coachConversation: WorkoutCoachConversation(messages: conversation.messages),
                              planTitle: plan.title, acceptedPlanID: plan.id, planAcceptedAt: acceptedAt, exercises: plan.exercises)
        workout.programID = plan.programID
        workout.programSessionID = plan.programSessionID
        workout.programRevision = plan.programRevision
        try startWorkout(workout)
        coachConversation?.plan = nil
        coachConversation?.startedWorkoutID = workout.id
        return workout.id
    }
    public mutating func startWorkout(_ workout: Workout) throws {
        guard activeWorkout == nil else { throw GymaError.invalid("Finish or resume your current workout first.") }
        try workout.validate()
        guard workout.isActive, !workouts.contains(where: { $0.id == workout.id }), !deletedWorkouts.contains(where: { $0.id == workout.id }),
              workout.exercises.allSatisfy({ $0.sets.isEmpty }),
              workout.exercises.allSatisfy({ $0.snapshotWorkingSetCount == nil }), workout.restHistory?.isEmpty ?? true,
              Set(workout.exercises.map(\.exerciseID)).count == workout.exercises.count else { throw GymaError.invalid("A new workout needs unique exercises and no completed sets.") }
        for entry in workout.exercises where !catalog.contains(where: { $0.id == entry.exerciseID }) { throw GymaError.invalid("Unknown exercise in workout.") }
        workouts.insert(workout, at: 0); restTimer = nil; revision += 1
    }
    public mutating func addCustomExercise(_ exercise: ExerciseDefinition) throws {
        try exercise.metadata?.validate()
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
        workouts[wi].restHistory?.removeAll { $0.exerciseID == exerciseID }
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
    private func canRest(workout: Workout, entry: WorkoutExercise) -> Bool {
        restEnabled && workout.isActive && entry.sets.last?.isWarmup == false &&
        (workout.acceptedPlanID != nil || (workout.checkIn?.painNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)) &&
        (entry.target.map { entry.workingSetCount < $0.sets } ?? true)
    }
}
