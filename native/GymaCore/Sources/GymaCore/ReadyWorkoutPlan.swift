import Foundation

/// The saved calendar decides whether a new strength workout may start today.
/// An in-progress workout remains resumable even after its scheduled day ends.
public enum DailyTrainingStatus: Sendable, Equatable {
    case noCalendar
    case beforeStart(Date)
    case trainingDay
    case recoveryDay
    case completedToday
    case blockComplete
    case activeWorkout
    case unavailable

    public var allowsWorkoutStart: Bool {
        switch self {
        case .noCalendar, .trainingDay: return true
        default: return false
        }
    }

    public var startUnavailableReason: String? {
        switch self {
        case .noCalendar, .trainingDay: return nil
        case .beforeStart: return "Your training block has not started yet. Review the first training date in Calendar."
        case .recoveryDay: return "Today is a recovery day. Your next strength session unlocks on a scheduled training day."
        case .completedToday: return "Today's strength workout is already recorded. Review it in History; the next session unlocks on a scheduled training day."
        case .blockComplete: return "Your eight-week block is complete. Review your progress and save the next calendar block before starting."
        case .activeWorkout: return "Resume or finish your current workout first."
        case .unavailable: return "Your training day could not be checked. Review the saved calendar before starting."
        }
    }
}

/// The Watch receives only the information needed to review readiness and start
/// an accepted plan or the next saved program session; private notes remain on iPhone.
public struct ReadyWorkoutPlan: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var scheduledFor: Date
    public var availableFrom: Date
    public var expiresAt: Date
    public var energy: Energy
    public var soreness: [Muscle: Soreness]
    public var exerciseCount: Int
    /// Present only when readiness will prepare a new session from an accepted program.
    public var programID: String?
    public var programSessionID: String?
    public var programRevision: Int?

    public init(plan: WorkoutPlan, calendar: Calendar = .current) {
        id = plan.id; title = String(plan.title.prefix(160)); scheduledFor = plan.scheduledDate
        availableFrom = calendar.startOfDay(for: scheduledFor)
        expiresAt = calendar.date(byAdding: .day, value: 1, to: availableFrom) ?? availableFrom.addingTimeInterval(86400)
        energy = plan.checkIn.energy; soreness = plan.checkIn.allSoreness; exerciseCount = plan.exercises.count
    }
    public init(program: TrainingProgram, session: ProgramSession, stateRevision: Int, now: Date = Date(), calendar: Calendar = .current) {
        availableFrom = calendar.startOfDay(for: now)
        scheduledFor = availableFrom
        expiresAt = calendar.date(byAdding: .day, value: 1, to: availableFrom) ?? availableFrom.addingTimeInterval(86400)
        let sessionIndex = program.sessions.firstIndex(where: { $0.id == session.id }) ?? 0
        id = "program-\(stateRevision)-\(program.revision)-\(sessionIndex)-\(availableFrom.timeIntervalSince1970)"
        title = String(session.title.prefix(160)); exerciseCount = session.exercises.count
        // Form defaults only: these are not a reported check-in or workout readiness record.
        energy = .good; soreness = Soreness.allNone
        programID = program.id; programSessionID = session.id; programRevision = program.revision
    }
    public func isAvailable(at now: Date = Date()) -> Bool { now >= availableFrom && now < expiresAt }
    public func validate() throws {
        let supportedDates = -2_208_988_800.0...4_102_444_800.0
        guard !id.isEmpty, id.count <= 200, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 160,
              [scheduledFor, availableFrom, expiresAt].allSatisfy({ supportedDates.contains($0.timeIntervalSince1970) }),
              availableFrom <= scheduledFor, scheduledFor < expiresAt, expiresAt.timeIntervalSince(availableFrom) <= 172800,
              Set(soreness.keys) == Set(Muscle.allCases), (1...12).contains(exerciseCount),
              (programID != nil) == (programSessionID != nil), (programID != nil) == (programRevision != nil),
              programID.map({ !$0.isEmpty && $0.count <= 200 }) ?? true,
              programSessionID.map({ !$0.isEmpty && $0.count <= 200 }) ?? true,
              programRevision.map({ (1...1_000_000).contains($0) }) ?? true else {
            throw GymaError.invalid("The ready workout plan is invalid. Refresh from iPhone.")
        }
    }
}

public extension GymaState {
    /// Calendar plans retain their original civil dates while the device travels.
    func planningCalendar(fallback: Calendar = .current) -> Calendar {
        trainingCalendar?.calendar ?? fallback
    }

    func dailyTrainingStatus(now: Date = Date(), calendar: Calendar = .current) -> DailyTrainingStatus {
        if activeWorkout != nil { return .activeWorkout }
        guard (-2_208_988_800.0...4_102_444_800.0).contains(now.timeIntervalSince1970) else { return .unavailable }
        // Existing standalone use remains available until a calendar is explicitly saved.
        guard let schedule = trainingCalendar else { return .noCalendar }
        guard (try? schedule.validate()) != nil else { return .unavailable }
        let calendar = planningCalendar(fallback: calendar)
        let today = calendar.startOfDay(for: now)
        if today < calendar.startOfDay(for: schedule.startDate) { return .beforeStart(schedule.startDate) }
        if today >= schedule.reviewDate { return .blockComplete }
        if workouts.contains(where: { $0.start <= now && calendar.isDate($0.start, inSameDayAs: now) }) {
            return .completedToday
        }
        return schedule.isTrainingDay(on: now) ? .trainingDay : .recoveryDay
    }

    /// Use the same eligibility for iPhone and Watch; a draft dated today cannot override a rest day.
    func canStartAcceptedPlan(_ plan: WorkoutPlan, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard activeWorkout == nil, let conversation = coachConversation, conversation.startedWorkoutID == nil,
              conversation.plan == plan, plan.acceptedAt != nil,
              dailyTrainingStatus(now: now, calendar: calendar).allowsWorkoutStart,
              plan.isScheduledForToday(at: now, calendar: planningCalendar(fallback: calendar)) else { return false }
        do {
            try conversation.validate(catalog: catalog)
            try validateProgramLink(plan, now: now)
            try validatePlanningContext(plan)
            try CoachingConstraints.validate(exercises: plan.exercises, profile: athleteProfile, catalog: catalog)
            return true
        } catch { return false }
    }

    /// Project only the saved session's identity. Targets and readiness are prepared at the start action.
    func readyProgramPlan(now: Date = Date(), calendar: Calendar = .current) -> ReadyWorkoutPlan? {
        let calendar = planningCalendar(fallback: calendar)
        guard activeWorkout == nil, dailyTrainingStatus(now: now, calendar: calendar).allowsWorkoutStart,
              coachConversation?.plan?.isScheduledForToday(at: now, calendar: calendar) != true || coachConversation?.startedWorkoutID != nil,
              (-2_208_988_800.0...4_102_444_800.0).contains(now.timeIntervalSince1970),
              let program = trainingProgram, (try? program.validate(catalog: catalog)) != nil,
              let session = program.nextSession(history: workouts, now: now) else { return nil }
        if let trainingCalendar {
            guard let entry = trainingCalendar.entries(program: program, history: workouts, now: now)
                .first(where: { trainingCalendar.calendar.isDate($0.date, inSameDayAs: now) }),
                  entry.session?.id == session.id else { return nil }
        } else if workouts.contains(where: { $0.start <= now && calendar.isDate($0.start, inSameDayAs: now) }) {
            return nil
        }
        let ready = ReadyWorkoutPlan(program: program, session: session, stateRevision: revision, now: now, calendar: calendar)
        return (try? ready.validate()) != nil ? ready : nil
    }
}

extension GymaState {
    func validateCalendarWorkoutStart(now: Date, calendar: Calendar = .current) throws {
        let status = dailyTrainingStatus(now: now, calendar: calendar)
        guard status.allowsWorkoutStart else {
            throw GymaError.stale(status.startUnavailableReason ?? "Today has no available strength session.")
        }
    }
}
