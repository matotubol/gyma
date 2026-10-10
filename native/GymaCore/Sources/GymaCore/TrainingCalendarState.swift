import Foundation

public extension GymaState {
    /// The calendar schedules opportunities to train. Only completed workouts advance the program.
    mutating func saveTrainingCalendar(_ plan: TrainingCalendarPlan, now: Date = Date()) throws {
        try plan.validate()
        try validateCalendarEditDate(now)
        guard trainingCalendar != plan else { return }
        let today = plan.calendar.startOfDay(for: now)
        let startsLaterBlock = trainingCalendar.map { plan.startDate >= $0.reviewDate } ?? false
        if plan.startDate < today {
            guard let previous = trainingCalendar,
                  previous.startDate == plan.startDate,
                  previous.timeZoneIdentifier == plan.timeZoneIdentifier,
                  plan.dates.filter({ $0 < today }).allSatisfy({ date in
                      previous.cycleDay(on: date) == plan.cycleDay(on: date) &&
                      previous.isTrainingDay(on: date) == plan.isTrainingDay(on: date) &&
                      previous.activities(on: date) == plan.activities(on: date)
                  }) else {
                throw GymaError.invalid("Earlier calendar days cannot be changed. Start a new block today or later, or move individual upcoming sessions.")
            }
        }
        // Reconfiguring an existing block must not rewrite a recorded day's calendar status.
        if let previous = trainingCalendar, !startsLaterBlock {
            if previous.activities.contains(where: \.isCompleted) {
                guard previous.startDate == plan.startDate, previous.timeZoneIdentifier == plan.timeZoneIdentifier else {
                    throw GymaError.invalid("The block start and time zone cannot change after an optional activity is completed.")
                }
            }
            for activity in previous.activities where activity.isCompleted {
                guard let date = previous.date(at: activity.dayOffset),
                      plan.activities(on: date).contains(activity),
                      previous.cycleDay(on: date) == plan.cycleDay(on: date) else {
                    throw GymaError.invalid("Completed optional activities cannot be changed in calendar setup.")
                }
            }
            for workout in workouts where plan.dayOffset(for: workout.start) != nil && previous.dayOffset(for: workout.start) != nil {
                guard previous.cycleDay(on: workout.start) == plan.cycleDay(on: workout.start),
                      previous.isTrainingDay(on: workout.start) == plan.isTrainingDay(on: workout.start) else {
                    throw GymaError.invalid("A day with a recorded workout cannot be rescheduled.")
                }
            }
        }
        for activity in plan.activities {
            guard let date = plan.date(at: activity.dayOffset) else { continue }
            if activity.isCompleted {
                guard trainingCalendar?.activities(on: date).contains(activity) == true else {
                    throw GymaError.invalid("Mark an optional activity done on its day instead of completing it in calendar setup.")
                }
            }
        }
        try validateUpcomingCalendarAbs(plan, now: now)
        if startsLaterBlock, let previous = trainingCalendar {
            var history = trainingCalendarHistory ?? []
            guard history.count < 100 else {
                throw GymaError.invalid("Calendar history is full. Export a backup before starting another block.")
            }
            history.append(previous)
            trainingCalendarHistory = history
        }
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
        try validateUpcomingCalendarAbs(plan, now: now)
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
        try validateUpcomingCalendarAbs(plan, now: now)
        trainingCalendar = plan
        invalidateCalendarDrafts()
        revision += 1
    }

    /// Optional activities are independent of recorded strength workouts on the same date.
    mutating func setCalendarActivity(on date: Date, kind: CalendarActivityKind, isPlanned: Bool,
                                      durationMinutes: Int? = nil, now: Date = Date()) throws {
        guard var plan = trainingCalendar else { throw GymaError.invalid("Set up your training calendar first.") }
        try validateCalendarEditDate(now)
        try validateCalendarEditDate(date)
        try plan.setActivity(on: date, kind: kind, isPlanned: isPlanned, durationMinutes: durationMinutes, now: now)
        guard plan != trainingCalendar else { return }
        if isPlanned, kind == .abs { try validateCalendarAbsRecovery(plan, on: date, now: now) }
        trainingCalendar = plan
        invalidateCalendarDrafts()
        revision += 1
    }

    mutating func setCalendarActivityCompleted(on date: Date, kind: CalendarActivityKind, isCompleted: Bool,
                                               now: Date = Date()) throws {
        guard var plan = trainingCalendar else { throw GymaError.invalid("Set up your training calendar first.") }
        try validateCalendarEditDate(now)
        try validateCalendarEditDate(date)
        try plan.setActivityCompleted(on: date, kind: kind, isCompleted: isCompleted, now: now)
        guard plan != trainingCalendar else { return }
        if isCompleted, kind == .abs { try validateCalendarAbsRecovery(plan, on: date, now: now) }
        trainingCalendar = plan
        invalidateCalendarDrafts()
        revision += 1
    }

    private func validateUpcomingCalendarAbs(_ plan: TrainingCalendarPlan, now: Date) throws {
        let today = plan.calendar.startOfDay(for: now)
        for activity in plan.activities where activity.kind == .abs && !activity.isCompleted {
            guard let date = plan.date(at: activity.dayOffset), date >= today else { continue }
            try validateCalendarAbsRecovery(plan, on: date, now: now)
        }
        // Rescheduling tomorrow's strength session must also respect abs already done today.
        // Recheck projected work only, so edits cannot rewrite or reject older actual history.
        let yesterday = plan.calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let recentPlans = [plan] + (trainingCalendar.map { [$0] } ?? []) + (trainingCalendarHistory ?? [])
        for source in recentPlans {
            for activity in source.activities where activity.kind == .abs && activity.isCompleted {
                guard let date = source.date(at: activity.dayOffset), date >= yesterday, date <= today else { continue }
                try validateCalendarAbsRecovery(plan, on: date, now: now, includeRecorded: false)
            }
        }
    }

    private func validateCalendarAbsRecovery(_ plan: TrainingCalendarPlan, on date: Date, now: Date, includeRecorded: Bool = true) throws {
        let day = plan.calendar.startOfDay(for: date)
        func isNeighbor(_ other: Date) -> Bool {
            let distance = plan.calendar.dateComponents([.day], from: day, to: plan.calendar.startOfDay(for: other)).day
            return distance == -1 || distance == 1
        }
        func trainsAbs(_ exerciseID: String) -> Bool {
            catalog.first(where: { $0.id == exerciseID })?.trainingMetadata?.primaryMuscles.contains(.abdominals) == true
        }
        let recordedAbs = includeRecorded && workouts.contains { workout in
            workout.start <= now && isNeighbor(workout.start) && workout.exercises.contains { exercise in
                trainsAbs(exercise.exerciseID) && exercise.sets.contains { $0.isWarmup != true }
            }
        }
        let previousCalendars = (trainingCalendar.map { [$0] } ?? []) + (trainingCalendarHistory ?? [])
        let completedAbs = includeRecorded && previousCalendars.contains { previous in
            previous.activities.contains { activity in
                guard activity.kind == .abs, activity.isCompleted,
                      let completedDate = previous.date(at: activity.dayOffset), completedDate <= now else { return false }
                return isNeighbor(completedDate)
            }
        }
        let projectedAbs = plan.entries(program: trainingProgram, history: workouts, now: now).contains { entry in
            isNeighbor(entry.date) && entry.session?.exercises.contains(where: { trainsAbs($0.exerciseID) }) == true
        }
        guard !recordedAbs, !completedAbs, !projectedAbs else {
            throw GymaError.invalid("Leave a day between direct ab sessions. A neighboring activity or strength workout already includes abs; choose walking or gentle stretching instead.")
        }
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
