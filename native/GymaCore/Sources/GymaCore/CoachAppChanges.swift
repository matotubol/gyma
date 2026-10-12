import Foundation

/// Typed operations proposed by the coach. The app previews and commits the entire batch atomically.
public struct CoachAppChange: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case replaceProgram, deleteProgram, configureCalendar, setTrainingDay, moveTrainingDay
        case setActivity, completeActivity, upsertExercise, deleteExercise, updateProfile, clearProfile
        case renameWorkout, deleteWorkout, restoreWorkout, correctSet, removeSet
        case setWorkoutTarget, addWorkoutExercise, removeWorkoutExercise, setRestEnabled
    }
    public var kind: Kind
    public var program: TrainingProgram?
    public var programID: String?
    public var calendar: TrainingCalendarPlan?
    public var date: Date?
    public var destinationDate: Date?
    public var enabled: Bool?
    public var activityKind: CalendarActivityKind?
    public var durationMinutes: Int?
    public var exercise: ExerciseDefinition?
    public var exerciseID: String?
    public var profile: AthleteProfile?
    public var workoutID: String?
    public var name: String?
    public var set: WorkSet?
    public var setID: String?
    public var target: ExerciseTarget?

    public init(kind: Kind, program: TrainingProgram? = nil, programID: String? = nil,
                calendar: TrainingCalendarPlan? = nil, date: Date? = nil, destinationDate: Date? = nil,
                enabled: Bool? = nil, activityKind: CalendarActivityKind? = nil, durationMinutes: Int? = nil,
                exercise: ExerciseDefinition? = nil, exerciseID: String? = nil, profile: AthleteProfile? = nil,
                workoutID: String? = nil, name: String? = nil, set: WorkSet? = nil,
                setID: String? = nil, target: ExerciseTarget? = nil) {
        self.kind = kind; self.program = program; self.programID = programID; self.calendar = calendar
        self.date = date; self.destinationDate = destinationDate; self.enabled = enabled
        self.activityKind = activityKind; self.durationMinutes = durationMinutes
        self.exercise = exercise; self.exerciseID = exerciseID; self.profile = profile
        self.workoutID = workoutID; self.name = name; self.set = set; self.setID = setID; self.target = target
    }

    /// Reject unused payloads so the review cannot describe only part of a requested operation.
    fileprivate func validatePayload() throws {
        let present: Set<String> = Set([
            program == nil ? nil : "program", programID == nil ? nil : "programID",
            calendar == nil ? nil : "calendar", date == nil ? nil : "date",
            destinationDate == nil ? nil : "destinationDate", enabled == nil ? nil : "enabled",
            activityKind == nil ? nil : "activityKind", durationMinutes == nil ? nil : "durationMinutes",
            exercise == nil ? nil : "exercise", exerciseID == nil ? nil : "exerciseID",
            profile == nil ? nil : "profile", workoutID == nil ? nil : "workoutID",
            name == nil ? nil : "name", set == nil ? nil : "set", setID == nil ? nil : "setID",
            target == nil ? nil : "target"
        ].compactMap { $0 })
        let required: Set<String>
        var optional: Set<String> = []
        switch kind {
        case .replaceProgram: required = ["program"]
        case .deleteProgram: required = ["programID"]
        case .configureCalendar: required = ["calendar"]
        case .setTrainingDay: required = ["date", "enabled"]
        case .moveTrainingDay: required = ["date", "destinationDate"]
        case .setActivity: required = ["date", "activityKind", "enabled"]; optional = ["durationMinutes"]
        case .completeActivity: required = ["date", "activityKind", "enabled"]
        case .upsertExercise: required = ["exercise"]
        case .deleteExercise: required = ["exerciseID"]
        case .updateProfile: required = ["profile"]
        case .clearProfile: required = []
        case .renameWorkout: required = ["workoutID", "name"]
        case .deleteWorkout, .restoreWorkout: required = ["workoutID"]
        case .correctSet: required = ["workoutID", "exerciseID", "setID", "set"]
        case .removeSet: required = ["workoutID", "exerciseID", "setID"]
        case .setWorkoutTarget: required = ["workoutID", "exerciseID"]; optional = ["target"]
        case .addWorkoutExercise: required = ["workoutID", "exerciseID"]; optional = ["target"]
        case .removeWorkoutExercise: required = ["workoutID", "exerciseID"]
        case .setRestEnabled: required = ["enabled"]
        }
        guard required.isSubset(of: present), present.isSubset(of: required.union(optional)) else {
            throw GymaError.invalid("The \(kind.rawValue) change has missing or unrelated fields.")
        }
        for value in [programID, exerciseID, workoutID, setID].compactMap({ $0 }) {
            guard !value.isEmpty, value.count <= 200 else { throw GymaError.invalid("An app change has an invalid identity.") }
        }
        for value in [date, destinationDate].compactMap({ $0 }) {
            guard (-2_208_988_800.0...4_102_444_800.0).contains(value.timeIntervalSince1970) else {
                throw GymaError.invalid("An app change has an invalid date.")
            }
        }
    }
}

public struct CoachAppChangeProposal: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var baseStoreID: String
    public var baseRevision: Int
    public var changes: [CoachAppChange]
    /// Created from actual operations and state, never from the model's explanatory text.
    public var summaries: [String]

    public init(id: String = UUID().uuidString, baseStoreID: String, baseRevision: Int,
                changes: [CoachAppChange], summaries: [String] = []) {
        self.id = id; self.baseStoreID = baseStoreID; self.baseRevision = baseRevision
        self.changes = changes; self.summaries = summaries
    }

    public init(changes: [CoachAppChange], state: GymaState, now: Date = Date()) throws {
        self.init(baseStoreID: state.storeID, baseRevision: state.revision, changes: changes)
        summaries = try state.previewCoachAppChanges(self, now: now).summaries
    }

    public func apply(to state: inout GymaState, now: Date = Date()) throws {
        try state.applyCoachAppChanges(self, now: now)
    }

    private enum CodingKeys: String, CodingKey { case id, baseStoreID, baseRevision, changes, summaries }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        baseStoreID = try values.decode(String.self, forKey: .baseStoreID)
        baseRevision = try values.decode(Int.self, forKey: .baseRevision)
        changes = try values.decode([CoachAppChange].self, forKey: .changes)
        summaries = try values.decodeIfPresent([String].self, forKey: .summaries) ?? []
    }
}

public struct CoachAppChangePreview: Sendable, Equatable {
    public var state: GymaState
    public var summaries: [String]
}

public extension GymaState {
    func previewCoachAppChanges(_ proposal: CoachAppChangeProposal, now: Date = Date()) throws -> CoachAppChangePreview {
        guard proposal.baseStoreID == storeID, proposal.baseRevision == revision else {
            throw GymaError.stale("Your app data changed after this proposal. Ask the coach to review the latest data before applying it.")
        }
        guard !proposal.id.isEmpty, proposal.id.count <= 200, (1...30).contains(proposal.changes.count),
              revision < 1_000_000_000,
              (-2_208_988_800.0...4_102_444_800.0).contains(now.timeIntervalSince1970) else {
            throw GymaError.invalid("A coach proposal needs 1–30 valid changes.")
        }
        var candidate = self
        var summaries: [String] = []
        for change in proposal.changes {
            try change.validatePayload()
            summaries.append(try candidate.performCoachAppChange(change, now: now))
        }
        // Training changes invalidate earlier drafts; presentation and timer preferences do not.
        if proposal.changes.contains(where: { $0.kind != .renameWorkout && $0.kind != .setRestEnabled }) {
            candidate.coachConversation?.plan = nil
            candidate.coachConversation?.proposedProgram = nil
            candidate.coachConversation?.proposedExercises = nil
            candidate.coachConversation?.acceptedProgramID = nil
        }
        for index in candidate.workouts.indices { candidate.workouts[index].coachConversation?.proposal = nil }
        candidate.revision = revision + 1
        if proposal.changes.contains(where: { $0.kind == .replaceProgram }), let program = candidate.trainingProgram {
            for session in program.sessions {
                try CoachingConstraints.validate(exercises: session.exercises, profile: candidate.athleteProfile, catalog: candidate.catalog)
            }
            try candidate.validateAvailableIncrements(program)
        }
        try candidate.validate()
        return CoachAppChangePreview(state: candidate, summaries: summaries)
    }

    mutating func applyCoachAppChanges(_ proposal: CoachAppChangeProposal, now: Date = Date()) throws {
        self = try previewCoachAppChanges(proposal, now: now).state
    }
}

private extension GymaState {
    mutating func performCoachAppChange(_ change: CoachAppChange, now: Date) throws -> String {
        switch change.kind {
        case .replaceProgram:
            var program = change.program!
            let previous = trainingProgram
            let versions = (programHistory ?? []) + (previous.map { [$0] } ?? [])
            let sameIdentity = versions.filter { $0.id == program.id }
            program.revision = (sameIdentity.map(\.revision).max() ?? 0) + 1
            program.createdAt = sameIdentity.map(\.createdAt).min() ?? now
            program.updatedAt = now
            try program.validate(catalog: catalog)
            try archiveCoachProgram(previous)
            trainingProgram = program
            let sessions = program.sessions.map { session in
                "\(session.title): " + session.exercises.map {
                    "\(exercise($0.exerciseID).name) — \(coachTargetDescription($0.target))"
                }.joined(separator: "; ")
            }.joined(separator: "\n")
            let removed = previous?.sessions.filter { old in !program.sessions.contains(where: { $0.id == old.id }) }.map(\.title) ?? []
            let removal = removed.isEmpty ? "" : "\nRemoved sessions: \(removed.joined(separator: ", "))."
            let increments = program.progressionRule.exerciseIncrements.keys.sorted().map {
                "\(exercise($0).name): \(program.progressionRule.exerciseIncrements[$0]!) kg"
            }.joined(separator: ", ")
            return "Save program ‘\(program.title)’ (revision \(program.revision)). Goal: \(program.goal).\n\(sessions)\(removal)\nProgression: \(program.progressionRule.loadIncrementKg) kg after \(program.progressionRule.successfulExposuresRequired) successful exposures. \(increments)\n\(program.rationale)"
        case .deleteProgram:
            guard let program = trainingProgram, program.id == change.programID else {
                throw GymaError.stale("That saved program is no longer current.")
            }
            try archiveCoachProgram(program)
            trainingProgram = nil
            return "Remove current program ‘\(program.title)’. Its saved version and completed workouts remain in history."
        case .configureCalendar:
            let plan = change.calendar!
            if let previous = trainingCalendar, plan.startDate < previous.reviewDate {
                let preserved = try previous.reconfigured(startDate: plan.startDate, cycleAnchorDate: plan.cycleAnchorDate,
                                                          trainingCycleDays: plan.trainingCycleDays, prefersUpperLower: plan.prefersUpperLower)
                guard preserved.timeZoneIdentifier == plan.timeZoneIdentifier,
                      preserved.dayOverrides == plan.dayOverrides, preserved.activities == plan.activities else {
                    throw GymaError.invalid("Calendar setup must preserve saved individual dates and activities. Use training-day and activity changes to edit those entries explicitly.")
                }
            }
            try saveTrainingCalendar(plan, now: now)
            let overrides = plan.dayOverrides.map {
                "\(coachDate(plan.date(at: $0.dayOffset)!, calendar: plan.calendar)): \($0.isTraining ? "training" : "rest")"
            }.joined(separator: "; ")
            let activities = plan.activities.map {
                "\(coachDate(plan.date(at: $0.dayOffset)!, calendar: plan.calendar)): \($0.kind.title), \($0.durationMinutes) min\($0.isCompleted ? ", completed" : "")"
            }.joined(separator: "; ")
            return "Set eight-week calendar from \(coachDate(plan.startDate, calendar: plan.calendar)); cycle day 1 on \(coachDate(plan.cycleAnchorDate, calendar: plan.calendar)); train on cycle days \(plan.trainingCycleDays.map(String.init).joined(separator: ", ")). Time zone: \(plan.timeZoneIdentifier). Prefer upper/lower: \(plan.prefersUpperLower ? "yes" : "no").\nIndividual dates: \(overrides.isEmpty ? "none" : overrides).\nOptional activities: \(activities.isEmpty ? "none" : activities)."
        case .setTrainingDay:
            try setCalendarTrainingDay(on: change.date!, isTraining: change.enabled!, now: now)
            return "Set \(coachDate(change.date!)) to \(change.enabled! ? "a training day" : "a rest day")."
        case .moveTrainingDay:
            try moveCalendarTrainingDay(from: change.date!, to: change.destinationDate!, now: now)
            return "Move training from \(coachDate(change.date!)) to \(coachDate(change.destinationDate!))."
        case .setActivity:
            try setCalendarActivity(on: change.date!, kind: change.activityKind!, isPlanned: change.enabled!, durationMinutes: change.durationMinutes, now: now)
            let duration = trainingCalendar?.activities(on: change.date!).first(where: { $0.kind == change.activityKind })?.durationMinutes
            return "\(change.enabled! ? "Plan" : "Remove") \(change.activityKind!.title) on \(coachDate(change.date!))\(change.enabled! ? " for \(duration ?? change.activityKind!.defaultDurationMinutes) minutes" : "")."
        case .completeActivity:
            try setCalendarActivityCompleted(on: change.date!, kind: change.activityKind!, isCompleted: change.enabled!, now: now)
            return "Mark \(change.activityKind!.title) on \(coachDate(change.date!)) \(change.enabled! ? "completed" : "not completed")."
        case .upsertExercise:
            var item = change.exercise!
            item.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !catalog.contains(where: { $0.id != item.id && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(item.name) == .orderedSame }) else {
                throw GymaError.invalid("That exercise name is already in your library. Use its existing identity or name a distinct variant.")
            }
            let old = catalog.first { $0.id == item.id }
            if let old, (workouts + deletedWorkouts).contains(where: { workout in
                workout.exercises.contains { $0.exerciseID == item.id && !$0.sets.isEmpty }
            }) {
                let before = old.trainingMetadata, after = item.trainingMetadata
                guard before?.equipment == after?.equipment, before?.loadConvention == after?.loadConvention,
                      before?.measurement == after?.measurement else {
                    throw GymaError.invalid("Create a new exercise variant when changing equipment, load convention or measurement for an exercise with recorded sets. Renaming its existing identity is supported.")
                }
            }
            if ExerciseCatalog.builtIn.contains(where: { $0.id == item.id }) {
                item.custom = false
                if exerciseOverrides == nil { exerciseOverrides = [] }
                exerciseOverrides?.removeAll { $0.id == item.id }
                exerciseOverrides?.append(item)
            } else {
                item.custom = true
                customExercises.removeAll { $0.id == item.id }
                customExercises.append(item)
            }
            hiddenExerciseIDs?.removeAll { $0 == item.id }
            if var reviews = workoutReviews {
                for ri in reviews.indices {
                    for ei in reviews[ri].exercises.indices where reviews[ri].exercises[ei].exerciseID == item.id {
                        reviews[ri].exercises[ei].exerciseName = item.name
                    }
                }
                workoutReviews = reviews
            }
            let metadata = item.trainingMetadata
            return "\(old.map { "Update ‘\($0.name)’ to" } ?? "Add exercise") ‘\(item.name)’ (\(item.muscle.label)). Direct muscles: \(metadata?.primaryMuscles.map(\.label).joined(separator: ", ") ?? "unspecified"); secondary: \(metadata?.secondaryMuscles.map(\.label).joined(separator: ", ") ?? "unspecified"); equipment: \(metadata?.equipment?.label ?? "unspecified"); load: \(metadata?.loadConvention.label ?? "unspecified"); measurement: \(metadata?.measurement.rawValue ?? "unspecified")."
        case .deleteExercise:
            guard let item = catalog.first(where: { $0.id == change.exerciseID }) else { throw GymaError.stale("That exercise is no longer available.") }
            if hiddenExerciseIDs == nil { hiddenExerciseIDs = [] }
            if hiddenExerciseIDs?.contains(item.id) != true { hiddenExerciseIDs?.append(item.id) }
            return "Remove ‘\(item.name)’ from the exercise library. Existing workouts and saved program references keep the exercise."
        case .updateProfile:
            let profile = change.profile!
            let summary = coachProfileSummary(profile)
            try saveAthleteProfile(profile, now: now)
            return summary
        case .clearProfile:
            clearAthleteProfile()
            return "Clear the saved athlete profile, including its bodyweight measurements, preferences and limitations."
        case .renameWorkout:
            let index = try coachWorkoutIndex(change.workoutID!)
            let name = change.name!.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 200 else { throw GymaError.invalid("A workout name needs 1–200 characters.") }
            let old = coachWorkoutDescription(workouts[index])
            workouts[index].planTitle = name
            return "Rename \(old) to ‘\(name)’."
        case .deleteWorkout:
            let workout = workouts[try coachWorkoutIndex(change.workoutID!)]
            try deleteWorkout(workout.id)
            return "Move \(coachWorkoutDescription(workout)) to Recently deleted, including its \(workout.totalSets) logged sets."
        case .restoreWorkout:
            guard let workout = deletedWorkouts.first(where: { $0.id == change.workoutID }) else { throw GymaError.stale("That deleted workout is unavailable.") }
            try restoreWorkout(workout.id)
            return "Restore \(coachWorkoutDescription(workout)) with its \(workout.totalSets) logged sets."
        case .correctSet, .removeSet, .setWorkoutTarget, .addWorkoutExercise, .removeWorkoutExercise:
            return try performCoachWorkoutEdit(change, now: now)
        case .setRestEnabled:
            setRestEnabled(change.enabled!)
            return "Turn automatic rest timers \(change.enabled! ? "on" : "off")."
        }
    }

    mutating func archiveCoachProgram(_ program: TrainingProgram?) throws {
        guard let program else { return }
        var history = programHistory ?? []
        if history.contains(where: { $0.id == program.id && $0.revision == program.revision }) { return }
        guard history.count < 100 else { throw GymaError.invalid("Program history is full. Export a backup before saving another version.") }
        history.append(program)
        programHistory = history
    }

    func coachWorkoutIndex(_ id: String) throws -> Int {
        guard let index = workouts.firstIndex(where: { $0.id == id }) else { throw GymaError.stale("That workout is unavailable. Restore it first if it was deleted.") }
        return index
    }

    mutating func performCoachWorkoutEdit(_ change: CoachAppChange, now: Date) throws -> String {
        let wi = try coachWorkoutIndex(change.workoutID!)
        let exerciseID = change.exerciseID!
        guard catalog.contains(where: { $0.id == exerciseID }) else { throw GymaError.invalid("That exercise is not in the catalog.") }
        let context = "\(exercise(exerciseID).name) in \(coachWorkoutDescription(workouts[wi]))"
        let summary: String
        if change.kind == .addWorkoutExercise {
            guard !workouts[wi].exercises.contains(where: { $0.exerciseID == exerciseID }) else { throw GymaError.invalid("That workout already contains this exercise.") }
            try change.target?.validate()
            workouts[wi].exercises.append(.init(exerciseID: exerciseID, target: change.target))
            summary = "Add \(context): \(coachTargetDescription(change.target))."
        } else {
            guard let ei = workouts[wi].exercises.firstIndex(where: { $0.exerciseID == exerciseID }) else { throw GymaError.stale("That exercise is no longer in this workout.") }
            switch change.kind {
            case .correctSet, .removeSet:
                guard let si = workouts[wi].exercises[ei].sets.firstIndex(where: { $0.id == change.setID }) else { throw GymaError.stale("That set is no longer in this workout.") }
                let old = workouts[wi].exercises[ei].sets[si]
                if change.kind == .correctSet {
                    let replacement = change.set!
                    guard replacement.id == old.id else { throw GymaError.invalid("A set correction must keep the original set identity.") }
                    try replacement.validate()
                    workouts[wi].exercises[ei].sets[si] = replacement
                    if replacement.isWarmup != false { workouts[wi].restHistory?.removeAll { $0.sourceSetID == old.id } }
                    summary = "Correct set \(si + 1) of \(context): \(coachSetDescription(old)) → \(coachSetDescription(replacement))."
                } else {
                    workouts[wi].exercises[ei].sets.remove(at: si)
                    workouts[wi].restHistory?.removeAll { $0.sourceSetID == old.id }
                    summary = "Remove set \(si + 1) of \(context): \(coachSetDescription(old))."
                }
                if restTimer?.workoutID == change.workoutID, restTimer?.exerciseID == exerciseID { restTimer = nil }
            case .setWorkoutTarget:
                try change.target?.validate()
                let old = workouts[wi].exercises[ei].target
                workouts[wi].exercises[ei].target = change.target
                if restTimer?.workoutID == change.workoutID, restTimer?.exerciseID == exerciseID { restTimer = nil }
                summary = "Change target for \(context): \(coachTargetDescription(old)) → \(coachTargetDescription(change.target))."
            case .removeWorkoutExercise:
                let count = workouts[wi].exercises[ei].sets.count
                workouts[wi].exercises.remove(at: ei)
                workouts[wi].restHistory?.removeAll { $0.exerciseID == exerciseID }
                if restTimer?.workoutID == change.workoutID, restTimer?.exerciseID == exerciseID { restTimer = nil }
                summary = "Remove \(context), including \(count) logged sets and its rest records."
            default: throw GymaError.invalid("Unsupported workout edit.")
            }
        }
        if !workouts[wi].isActive {
            let workout = workouts[wi]
            let review = WorkoutReview.make(workout: workout, history: workouts, program: trainingProgram,
                                            catalog: catalog, now: now, priorPrograms: programHistory ?? [])
            if workoutReviews == nil { workoutReviews = [] }
            workoutReviews?.removeAll { $0.workoutID == workout.id }
            workoutReviews?.append(review)
        }
        return summary
    }

    func coachDate(_ date: Date, calendar: Calendar? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = (calendar ?? trainingCalendar?.calendar)?.timeZone ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func coachWorkoutDescription(_ workout: Workout) -> String {
        "‘\(workout.planTitle ?? "Workout")’ on \(coachDate(workout.start))\(workout.isActive ? " (active)" : "")"
    }

    func coachTargetDescription(_ target: ExerciseTarget?) -> String {
        guard let target else { return "no target" }
        return "\(target.sets) × \(target.repsMin)–\(target.repsMax) reps, \(target.loadKg.map { "\($0) kg" } ?? "load not set"), \(target.restSeconds)s rest, effort \(target.targetEffort?.label ?? "not set")"
    }

    func coachSetDescription(_ set: WorkSet) -> String {
        "\(set.kg) kg × \(set.reps) reps, \(set.isWarmup.map { $0 ? "warm-up" : "working set" } ?? "unclassified"), effort \(set.effort?.label ?? "not set")"
    }

    func coachProfileSummary(_ profile: AthleteProfile) -> String {
        let previous = athleteProfile
        var details = ["Save athlete profile: \(profile.primaryGoal.label); secondary goals: \(profile.secondaryGoals.map(\.label).joined(separator: ", ")); \(profile.experience.label).",
                       "Height: \(profile.heightCM.map { "\($0) cm" } ?? "not set"); \(profile.daysPerWeek) days/week; \(profile.usualSessionMinutes) min/session.",
                       "Equipment: \(profile.equipment.map(\.label).joined(separator: ", ")). Increments: \(profile.loadIncrements.map { "\($0.equipment.label) \($0.incrementKg) kg" }.joined(separator: ", ")).",
                       "Preferred exercises: \(profile.preferredExercises.joined(separator: ", ")). Avoided: \(profile.avoidedExercises.joined(separator: ", ")).",
                       "Goal notes: \(profile.goalNotes)\nSchedule: \(profile.scheduleNotes)\nEquipment notes: \(profile.equipmentNotes)\nLimitations: \(profile.ongoingLimitations)"]
        let changed = profile.bodyweightHistory.filter { item in previous?.bodyweightHistory.contains(item) != true }
        let removed = (previous?.bodyweightHistory ?? []).filter { old in !profile.bodyweightHistory.contains(where: { $0.id == old.id }) }
        details.append("Bodyweight: \(profile.bodyweightHistory.count) saved measurements. \(removed.count) removed.")
        details += changed.map { "Bodyweight on \(coachDate($0.recordedAt)): \($0.kg) kg." }
        return details.joined(separator: "\n")
    }
}
