import Foundation

/// One civil date in the month browser, including dates outside any saved training block.
/// Recorded workouts belong to the display calendar's start date, independent of a schedule.
public struct TrainingCalendarMonthDay: Sendable, Equatable, Identifiable {
    public var id: Date { date }
    public let date: Date
    public let plan: TrainingCalendarPlan?
    /// Keeps the source plan's original date and day offset for current-block editing.
    public let scheduledDay: TrainingCalendarDay?
    public let isCurrentPlan: Bool
    public let workouts: [Workout]
    public let isToday: Bool
    public var activities: [CalendarActivity] { scheduledDay?.activities ?? [] }
}

/// A read-only month view over the current block, saved blocks, and all retained workouts.
/// Changing the visible month neither creates a schedule nor changes the program rotation.
public struct TrainingCalendarMonth: Sendable, Equatable {
    public let calendar: Calendar
    public let monthStart: Date
    public let days: [TrainingCalendarMonthDay]

    public func month(byAdding offset: Int) -> Date? {
        calendar.date(byAdding: .month, value: offset, to: monthStart)
    }

    public static func make(state: GymaState, containing monthDate: Date, now: Date = Date(),
                            calendar fallback: Calendar = .current) -> Self {
        let calendar = state.planningCalendar(fallback: fallback)
        guard let interval = calendar.dateInterval(of: .month, for: monthDate),
              let dayRange = calendar.range(of: .day, in: .month, for: interval.start) else {
            return Self(calendar: calendar, monthStart: monthDate, days: [])
        }
        let monthStart = interval.start
        let dates = dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - dayRange.lowerBound, to: monthStart)
        }
        let visibleDates = Set(dates)
        var recorded: [Date: [Workout]] = [:]
        for workout in state.workouts where workout.start <= now {
            let date = calendar.startOfDay(for: workout.start)
            if visibleDates.contains(date) { recorded[date, default: []].append(workout) }
        }

        var scheduled: [Date: (plan: TrainingCalendarPlan, day: TrainingCalendarDay, isCurrent: Bool)] = [:]
        // Archives are oldest first; the most recently saved block wins if imported blocks overlap.
        // The current block always takes precedence, without ever duplicating actual workouts.
        let sources = (state.trainingCalendarHistory ?? []).map { (plan: $0, isCurrent: false) }
            + (state.trainingCalendar.map { [(plan: $0, isCurrent: true)] } ?? [])
        for source in sources {
            let entries = source.plan.entries(program: source.isCurrent ? state.trainingProgram : nil,
                                              history: state.workouts, now: now)
            for entry in entries {
                // A saved October 13 stays October 13 when an older block used another time zone.
                // Converting its midnight instant directly could move it to the preceding date.
                let components = source.plan.calendar.dateComponents([.era, .year, .month, .day], from: entry.date)
                guard let date = calendar.date(from: components), visibleDates.contains(date) else { continue }
                scheduled[date] = (source.plan, entry, source.isCurrent)
            }
        }

        let today = calendar.startOfDay(for: now)
        let days = dates.map { date in
            let actual = (recorded[date] ?? []).sorted {
                $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start
            }
            let source = scheduled[date]
            var scheduledDay = source?.day
            // Keep the row and its optional schedule consistent even across archived time zones.
            scheduledDay?.workouts = actual
            return TrainingCalendarMonthDay(date: date, plan: source?.plan, scheduledDay: scheduledDay,
                                            isCurrentPlan: source?.isCurrent ?? false,
                                            workouts: actual, isToday: date == today)
        }
        return Self(calendar: calendar, monthStart: monthStart, days: days)
    }
}
