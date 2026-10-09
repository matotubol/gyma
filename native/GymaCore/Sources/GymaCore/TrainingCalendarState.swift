import Foundation

public extension GymaState {
    /// The calendar schedules opportunities to train. Only completed workouts advance the program.
    mutating func saveTrainingCalendar(_ plan: TrainingCalendarPlan, now: Date = Date()) throws {
        try plan.validate()
        try validateCalendarEditDate(now)
        let today = plan.calendar.startOfDay(for: now)
        if plan.startDate < today {
            guard let previous = trainingCalendar,
                  previous.startDate == plan.startDate,
                  previous.timeZoneIdentifier == plan.timeZoneIdentifier,
                  plan.dates.filter({ $0 < today }).allSatisfy({ date in
                      previous.cycleDay(on: date) == plan.cycleDay(on: date) &&
                      previous.isTrainingDay(on: date) == plan.isTrainingDay(on: date)
                  }) else {
                throw GymaError.invalid("Earlier calendar days cannot be changed. Start a new block today or later, or move individual upcoming sessions.")
            }
        }
        // Reconfiguring an existing block must not rewrite a recorded day's calendar status.
        if let previous = trainingCalendar {
            for workout in workouts where plan.dayOffset(for: workout.start) != nil && previous.dayOffset(for: workout.start) != nil {
                guard previous.cycleDay(on: workout.start) == plan.cycleDay(on: workout.start),
                      previous.isTrainingDay(on: workout.start) == plan.isTrainingDay(on: workout.start) else {
                    throw GymaError.invalid("A day with a recorded workout cannot be rescheduled.")
                }
            }
        }
        guard trainingCalendar != plan else { return }
        trainingCalendar = plan
        invalidateCalendarDrafts()
        revision += 1
    }

    mutating func setCalendarTrainingDay(on date: Date, isTraining: Bool, now: Date = Date()) throws {
        guard var plan = trainingCalendar else { throw GymaError.invalid("Set up your training calendar first.") }
        try validateCalendarEditDate(now)
        try validateCalendarEditDate(date)
        try requireUnrecordedCalendarDay(date, plan: plan)
        try plan.setTrainingDay(on: date, isTraining: isTraining, now: now)
        guard plan != trainingCalendar else { return }
        trainingCalendar = plan
        invalidateCalendarDrafts()
        revision += 1
    }

    mutating func moveCalendarTrainingDay(from source: Date, to destination: Date, now: Date = Date()) throws {
        guard var plan = trainingCalendar else { throw GymaError.invalid("Set up your training calendar first.") }
        try validateCalendarEditDate(now)
        try validateCalendarEditDate(source)
        try validateCalendarEditDate(destination)
        try requireUnrecordedCalendarDay(source, plan: plan)
        try requireUnrecordedCalendarDay(destination, plan: plan)
        try plan.moveTrainingDay(from: source, to: destination, now: now)
        trainingCalendar = plan
        invalidateCalendarDrafts()
        revision += 1
    }

    private func validateCalendarEditDate(_ date: Date) throws {
        guard (-2_208_988_800.0...4_102_444_800.0).contains(date.timeIntervalSince1970) else {
            throw GymaError.invalid("The calendar edit date is invalid.")
        }
    }

    private func requireUnrecordedCalendarDay(_ date: Date, plan: TrainingCalendarPlan) throws {
        guard !workouts.contains(where: { plan.calendar.isDate($0.start, inSameDayAs: date) }) else {
            throw GymaError.invalid("A day with an active or recorded workout cannot be rescheduled.")
        }
    }

    private mutating func invalidateCalendarDrafts() {
        // Keep the discussion, but require a fresh check-in after changing its scheduling context.
        // Incrementing state.revision also rejects any in-flight reply based on the old calendar.
        coachConversation?.plan = nil
        coachConversation?.proposedProgram = nil
    }
}
