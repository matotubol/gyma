import Foundation

public struct CoachMessage: Codable, Sendable, Identifiable, Equatable {
    public enum Role: String, Codable, Sendable { case user, assistant }
    public var id: String
    public var role: Role
    public var content: String
    public init(id: String = UUID().uuidString, role: Role, content: String) {
        self.id = id; self.role = role; self.content = content
    }
}

/// A proposed session stays separate from workout history until explicitly accepted and started.
public struct WorkoutPlan: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var title: String
    public var exercises: [WorkoutExercise]
    public var checkIn: SessionCheckIn
    public var createdAt: Date
    public var acceptedAt: Date?
    public var scheduledFor: Date?
    public var programID: String?
    public var programSessionID: String?
    public var programRevision: Int?
    public var scheduledDate: Date { scheduledFor ?? createdAt }
    public init(id: String = UUID().uuidString, title: String, exercises: [WorkoutExercise], checkIn: SessionCheckIn, createdAt: Date = Date(), acceptedAt: Date? = nil, scheduledFor: Date? = nil) {
        self.id = id; self.title = title; self.exercises = exercises; self.checkIn = checkIn; self.createdAt = createdAt; self.acceptedAt = acceptedAt; self.scheduledFor = scheduledFor
    }
    public func isScheduledForToday(at now: Date = Date(), calendar: Calendar = .current) -> Bool {
        calendar.isDate(scheduledDate, inSameDayAs: now)
    }
    public func validate(catalog: [ExerciseDefinition]) throws {
        let supportedDates = -2_208_988_800.0...4_102_444_800.0
        guard !id.isEmpty, id.count <= 200, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 200,
              supportedDates.contains(createdAt.timeIntervalSince1970),
              supportedDates.contains(scheduledDate.timeIntervalSince1970),
              acceptedAt.map({ supportedDates.contains($0.timeIntervalSince1970) && $0 >= createdAt }) ?? true,
              (1...12).contains(exercises.count), Set(exercises.map(\.exerciseID)).count == exercises.count else {
            throw GymaError.invalid("A workout plan needs a title and 1–12 unique exercises.")
        }
        try checkIn.validate()
        let hasProgram = programID != nil
        guard (programSessionID != nil) == hasProgram, (programRevision != nil) == hasProgram,
              programID.map({ !$0.isEmpty && $0.count <= 200 }) ?? true,
              programSessionID.map({ !$0.isEmpty && $0.count <= 200 }) ?? true,
              programRevision.map({ (1...1_000_000).contains($0) }) ?? true else {
            throw GymaError.invalid("Invalid program link in workout plan.")
        }
        let catalogIDs = Set(catalog.map(\.id))
        for exercise in exercises {
            guard catalogIDs.contains(exercise.exerciseID), exercise.sets.isEmpty, exercise.snapshotWorkingSetCount == nil, let target = exercise.target else {
                throw GymaError.invalid("Every planned exercise needs a known exercise and a target, with no completed sets.")
            }
            try target.validate()
        }
    }
}

public enum CoachConversationPurpose: String, Codable, Sendable {
    case program, workout
}

public struct CoachConversation: Codable, Sendable, Equatable {
    /// Nil preserves the workout-planning behavior of saved conversations from older app versions.
    public var purpose: CoachConversationPurpose?
    /// Retained for backup compatibility; never reported as readiness in a program conversation.
    public var checkIn: SessionCheckIn
    public var messages: [CoachMessage]
    public var plan: WorkoutPlan?
    public var startedWorkoutID: String?
    public var proposedProgram: TrainingProgram?
    public var proposedExercises: [CoachExerciseProposal]?
    public var acceptedProgramID: String?
    public var isProgramPlanning: Bool { purpose == .program }
    public init(checkIn: SessionCheckIn, messages: [CoachMessage] = [], plan: WorkoutPlan? = nil) {
        self.checkIn = checkIn; self.messages = messages; self.plan = plan
    }
    public static func programPlanning(profile: AthleteProfile? = nil, existingProgram: TrainingProgram? = nil) -> CoachConversation {
        // This compatibility placeholder is neither user-reported nor used to prepare a workout.
        var conversation = CoachConversation(checkIn: .init(shift: .off, energy: .medium,
                                                            timeMinutes: min(180, max(10, profile?.usualSessionMinutes ?? 45))))
        conversation.purpose = .program
        let request = existingProgram == nil ? "Create a recurring training program" : "Review and revise my recurring training program"
        conversation.messages = [.init(role: .user, content: "\(request) for my eight-week calendar using my saved profile, schedule, preferences and training history. Keep the sessions repeatable and explain progression. Ask about missing long-term information if needed. I will check in about daily readiness when I start a workout; do not plan a workout for today.")]
        return conversation
    }
    public func validate(catalog: [ExerciseDefinition]) throws {
        try checkIn.validate()
        guard !isProgramPlanning || (plan == nil && startedWorkoutID == nil) else {
            throw GymaError.invalid("Program planning cannot prepare or start today's workout. Check in when you are ready to train.")
        }
        guard acceptedProgramID.map({ isProgramPlanning && !$0.isEmpty && $0.count <= 200 && proposedProgram == nil && (proposedExercises ?? []).isEmpty }) ?? true else {
            throw GymaError.invalid("Invalid program-planning acceptance.")
        }
        try proposedProgram?.validate(catalog: catalog)
        try CoachExerciseProposal.validate(proposedExercises ?? [], catalog: catalog)
        guard (proposedExercises ?? []).isEmpty || (plan == nil && proposedProgram == nil && startedWorkoutID == nil) else {
            throw GymaError.invalid("Save proposed exercises to your library before reviewing a program or workout that uses them.")
        }
        guard proposedProgram == nil || (plan == nil && startedWorkoutID == nil) else {
            throw GymaError.invalid("Review a program proposal before preparing its session.")
        }
        guard startedWorkoutID.map({ !$0.isEmpty && $0.count <= 200 && plan == nil }) ?? true else {
            throw GymaError.invalid("Start a new check-in before planning your next workout.")
        }
        guard messages.count <= 200, Set(messages.map(\.id)).count == messages.count,
              messages.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 200 && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.content.count <= 16_000 }),
              messages.reduce(0, { $0 + $1.content.utf8.count }) <= 512_000 else {
            throw GymaError.invalid("The coach conversation is invalid or too long. Start a new conversation.")
        }
        if let plan {
            try plan.validate(catalog: catalog)
            guard plan.checkIn == checkIn else { throw GymaError.invalid("The workout plan must match the current check-in.") }
        }
    }
}
