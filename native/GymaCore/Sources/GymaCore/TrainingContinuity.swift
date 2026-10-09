import Foundation

/// Feedback explains deviations without changing the recorded training or the athlete profile.
public struct WorkoutFeedback: Codable, Sendable, Equatable, Identifiable {
    public var workoutID: String
    public var recordedAt: Date
    public var note: String
    public var painNote: String
    public var id: String { workoutID }
    public init(workoutID: String, recordedAt: Date = Date(), note: String = "", painNote: String = "") {
        self.workoutID = workoutID; self.recordedAt = recordedAt; self.note = note; self.painNote = painNote
    }
    public func validate() throws {
        guard !workoutID.isEmpty, workoutID.count <= 200, note.count <= 2000, painNote.count <= 2000,
              (-2_208_988_800.0...4_102_444_800.0).contains(recordedAt.timeIntervalSince1970) else {
            throw GymaError.invalid("Keep workout feedback under 2,000 characters per field.")
        }
    }
}

public extension GymaState {
    func validatePlanningContext(_ plan: WorkoutPlan) throws {
        let knownWorkoutIDs = Set(workouts.map(\.id))
        let newerFeedback = (workoutFeedback ?? []).contains { knownWorkoutIDs.contains($0.workoutID) && $0.recordedAt > plan.createdAt }
        guard !(athleteProfile.map { $0.updatedAt > plan.createdAt } ?? false), !newerFeedback else {
            throw GymaError.stale("Your profile or workout feedback changed after this draft. Prepare the next session again or ask the coach to update it.")
        }
    }

    func validateProgramLink(_ plan: WorkoutPlan, now: Date = Date()) throws {
        guard let id = plan.programID else { return }
        guard let program = trainingProgram, program.id == id, program.revision == plan.programRevision,
              program.nextSession(history: workouts, now: now)?.id == plan.programSessionID else {
            throw GymaError.stale("Your program or next session changed. Prepare a fresh session from your program.")
        }
        try CoachingConstraints.validate(exercises: plan.exercises, profile: athleteProfile, catalog: catalog)
        try validateAvailableIncrements(program)
    }

    mutating func acceptProgramProposal(programID: String, now: Date = Date()) throws {
        guard activeWorkout == nil, var conversation = coachConversation,
              var program = conversation.proposedProgram, program.id == programID else {
            throw GymaError.stale("That program proposal has changed. Review the current proposal.")
        }
        try program.validate(catalog: catalog)
        for session in program.sessions { try CoachingConstraints.validate(exercises: session.exercises, profile: athleteProfile, catalog: catalog) }
        var next = self
        if let previous = trainingProgram {
            next.programHistory = Array(((programHistory ?? []) + [previous]).suffix(100))
        }
        program.updatedAt = now
        try program.validate(catalog: catalog)
        next.trainingProgram = program
        conversation.proposedProgram = nil
        conversation.messages.append(.init(role: .assistant, content: "Program saved. Its sessions repeat in order; missed days do not add extra work. Review today's session below."))
        conversation.plan = try next.nextProgramPlan(checkIn: conversation.checkIn, now: now)
        try conversation.validate(catalog: catalog)
        next.coachConversation = conversation
        next.revision += 1
        self = next
    }

    func nextProgramPlan(checkIn: SessionCheckIn, now: Date = Date()) throws -> WorkoutPlan {
        guard let program = trainingProgram, let session = program.nextSession(history: workouts, now: now) else {
            throw GymaError.invalid("Save a program before preparing its next session.")
        }
        try program.validate(catalog: catalog)
        try checkIn.validate()
        try validateAvailableIncrements(program)
        var exercises = program.nextExercises(history: workouts, now: now, catalog: catalog, priorPrograms: programHistory ?? [])
        // A local rule cannot assess a new pain report. Preserve the plan for discussion, with no increase.
        let latestSession = workouts.filter { $0.programID == program.id && $0.programSessionID == session.id && !$0.isActive }
            .sorted { ($0.end ?? $0.start) > ($1.end ?? $1.start) }.first
        let recentPainFeedback = (workoutFeedback ?? []).contains { feedback in
            feedback.workoutID == latestSession?.id && now.timeIntervalSince(feedback.recordedAt) >= 0 &&
            now.timeIntervalSince(feedback.recordedAt) < 14 * 86400 && !feedback.painNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let painNeedsReview = recentPainFeedback || !checkIn.painNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let difficultDay = checkIn.energy == .poor || checkIn.allSoreness.values.contains(.high) || painNeedsReview
        if difficultDay {
            for index in exercises.indices {
                if var target = exercises[index].target {
                    if painNeedsReview { target.loadKg = nil }
                    else if let previousLoad = latestSession?.exercises.first(where: { $0.exerciseID == exercises[index].exerciseID })?.target?.loadKg {
                        target.loadKg = target.loadKg.map { min($0, previousLoad) }
                    } else { target.loadKg = nil }
                    exercises[index].target = target
                    exercises[index].target?.reason = "Readiness needs review today. Discuss a comfortable adjustment with the coach before accepting."
                }
            }
        }
        // Preserve the program's priority order and shorten today's draft, never the saved template.
        let secondsAvailable = checkIn.timeMinutes * 60
        func estimatedSeconds(_ entries: [WorkoutExercise]) -> Int {
            entries.reduce(0) { seconds, entry in
                guard let target = entry.target else { return seconds }
                return seconds + 90 + target.sets * max(20, target.repsMax * 3) + max(0, target.sets - 1) * target.restSeconds
            }
        }
        var shortened = false
        while exercises.count > 1 && estimatedSeconds(exercises) > secondsAvailable {
            exercises.removeLast(); shortened = true
        }
        while estimatedSeconds(exercises) > secondsAvailable,
              let index = exercises.lastIndex(where: { ($0.target?.sets ?? 0) > 1 }) {
            exercises[index].target?.sets -= 1; shortened = true
        }
        if shortened {
            let previousReason = exercises[0].target?.reason ?? ""
            exercises[0].target?.reason = "Shortened today's draft to fit about \(checkIn.timeMinutes) minutes while keeping the program's first-priority work. Duration is an estimate. The saved program is unchanged. " + previousReason
        }
        var plan = WorkoutPlan(title: session.title, exercises: exercises, checkIn: checkIn, createdAt: now, scheduledFor: now)
        plan.programID = program.id; plan.programSessionID = session.id; plan.programRevision = program.revision
        try plan.validate(catalog: catalog)
        try CoachingConstraints.validate(exercises: exercises, profile: athleteProfile, catalog: catalog)
        return plan
    }

    mutating func updateProgressionRule(_ rule: ProgressionRule, now: Date = Date()) throws {
        guard activeWorkout == nil, var program = trainingProgram else { throw GymaError.invalid("Finish your workout before editing the saved program.") }
        program.progressionRule = rule; program.revision += 1; program.updatedAt = now
        try program.validate(catalog: catalog)
        if let previous = trainingProgram { programHistory = Array(((programHistory ?? []) + [previous]).suffix(100)) }
        trainingProgram = program
        coachConversation = nil
        revision += 1
    }

    mutating func restoreProgramVersion(id: String, version: Int, now: Date = Date()) throws {
        guard activeWorkout == nil, var restored = programHistory?.last(where: { $0.id == id && $0.revision == version }) else {
            throw GymaError.stale("This program version is unavailable or a workout is still active.")
        }
        let allVersions = (programHistory ?? []) + (trainingProgram.map { [$0] } ?? [])
        restored.revision = (allVersions.filter { $0.id == id }.map(\.revision).max() ?? version) + 1
        restored.updatedAt = now
        try restored.validate(catalog: catalog)
        for session in restored.sessions { try CoachingConstraints.validate(exercises: session.exercises, profile: athleteProfile, catalog: catalog) }
        if let previous = trainingProgram { programHistory = Array(((programHistory ?? []) + [previous]).suffix(100)) }
        trainingProgram = restored; coachConversation = nil; revision += 1
    }

    mutating func archiveTrainingProgram() throws {
        guard activeWorkout == nil else { throw GymaError.invalid("Finish your current workout before changing programs.") }
        if let current = trainingProgram { programHistory = Array(((programHistory ?? []) + [current]).suffix(100)) }
        trainingProgram = nil
        coachConversation = nil
        revision += 1
    }

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

    private func validateAvailableIncrements(_ program: TrainingProgram) throws {
        for id in Set(program.sessions.flatMap { $0.exercises.map(\.exerciseID) }) {
            guard let equipment = catalog.first(where: { $0.id == id })?.trainingMetadata?.equipment,
                  let available = athleteProfile?.loadIncrements.first(where: { $0.equipment == equipment })?.incrementKg else { continue }
            let configured = program.progressionRule.exerciseIncrements[id] ?? program.progressionRule.loadIncrementKg
            let multiple = configured / available
            guard multiple >= 1 - 0.000001, abs(multiple - multiple.rounded()) < 0.000001 else {
                throw GymaError.invalid("The saved increase for \(exercise(id).name) no longer matches your available equipment increment. Update the program's progression rules or discuss a revision with the coach.")
            }
        }
    }
}
