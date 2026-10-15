import Foundation

extension GymaState {
    public mutating func saveCoachConversation(_ conversation: CoachConversation) throws {
        var next = conversation
        // Program acceptance belongs to the explicit accept operation, not a saved draft.
        if next.acceptedProgramID != coachConversation?.acceptedProgramID ||
            next.messages != coachConversation?.messages || next.proposedProgram != nil {
            next.acceptedProgramID = nil
        }
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
        guard let conversation = coachConversation, conversation.startedWorkoutID == nil,
              let plan = conversation.plan, plan.id == planID, let acceptedAt = plan.acceptedAt else {
            throw GymaError.invalid("Review and accept the coach plan before starting a workout.")
        }
        try conversation.validate(catalog: catalog)
        let calendar = planningCalendar(fallback: calendar)
        try validateCalendarWorkoutStart(now: now, calendar: calendar)
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
}
