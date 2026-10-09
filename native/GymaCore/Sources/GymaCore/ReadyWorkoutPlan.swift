import Foundation

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
    /// Project only the saved session's identity. Targets and readiness are prepared at the start action.
    func readyProgramPlan(now: Date = Date(), calendar: Calendar = .current) -> ReadyWorkoutPlan? {
        guard activeWorkout == nil, coachConversation?.plan == nil || coachConversation?.startedWorkoutID != nil,
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
