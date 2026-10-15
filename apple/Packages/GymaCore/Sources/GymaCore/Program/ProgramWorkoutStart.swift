import Foundation

extension GymaState {
    /// Starts a reviewed session prepared from a fresh check-in without replacing the saved program conversation.
    @discardableResult
    public mutating func startPreparedProgramPlan(_ plan: WorkoutPlan, readiness: WorkoutReadiness, now: Date = Date(), calendar: Calendar = .current) throws -> String {
        guard activeWorkout == nil else { throw GymaError.invalid("Finish or resume your current workout first.") }
        let calendar = planningCalendar(fallback: calendar)
        try validateCalendarWorkoutStart(now: now, calendar: calendar)
        try plan.validate(catalog: catalog)
        try readiness.validate()
        guard plan.programID != nil, plan.isScheduledForToday(at: now, calendar: calendar),
              plan.createdAt <= now, now.timeIntervalSince(plan.createdAt) <= 300,
              abs(now.timeIntervalSince(readiness.recordedAt)) <= 300,
              plan.checkIn.energy == readiness.energy, plan.checkIn.allSoreness == readiness.soreness else {
            throw GymaError.stale("Today's session or check-in changed. Review your current readiness and prepare the session again.")
        }
        try validateProgramLink(plan, now: now)
        try validatePlanningContext(plan)
        try CoachingConstraints.validate(exercises: plan.exercises, profile: athleteProfile, catalog: catalog)
        var workout = Workout(start: now, shift: plan.checkIn.shift, energy: readiness.energy, checkIn: plan.checkIn, readiness: readiness,
                              planTitle: plan.title, acceptedPlanID: plan.id, planAcceptedAt: now, exercises: plan.exercises)
        workout.programID = plan.programID
        workout.programSessionID = plan.programSessionID
        workout.programRevision = plan.programRevision
        var next = self
        try next.startWorkout(workout)
        if next.coachConversation?.isProgramPlanning != true, next.coachConversation?.startedWorkoutID == nil {
            // Any unstarted daily draft is superseded by the session the user just reviewed.
            next.coachConversation = nil
        }
        try next.validate()
        self = next
        return workout.id
    }

    /// A Watch start collects readiness now; no earlier planning check-in is reused.
    @discardableResult
    public mutating func startReadyProgramPlan(planID: String, readiness: WorkoutReadiness, now: Date = Date(), calendar: Calendar = .current) throws -> String {
        guard let ready = readyProgramPlan(now: now, calendar: calendar), ready.id == planID else {
            throw GymaError.stale("Your program or training day changed. Refresh today's workout before starting.")
        }
        try readiness.validate()
        let checkIn = SessionCheckIn(shift: trainingCalendar?.shift(on: now) ?? .off, energy: readiness.energy,
                                     timeMinutes: min(180, max(10, athleteProfile?.usualSessionMinutes ?? 45)),
                                     soreness: readiness.soreness)
        let plan = try nextProgramPlan(checkIn: checkIn, now: now)
        return try startPreparedProgramPlan(plan, readiness: readiness, now: now, calendar: calendar)
    }
}
