import Foundation
import SwiftUI
import GymaCore

struct CalendarActivityIndicators: View {
    let activities: [CalendarActivity]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(activities) { activity in
                Image(systemName: calendarActivitySymbol(activity.kind))
                    .foregroundStyle(activity.isCompleted ? GymaStyle.accent : Color.secondary)
            }
        }
        .font(.system(size: 10)).frame(height: 12)
        .accessibilityHidden(true)
    }
}

func calendarCanEdit(_ day: TrainingCalendarDay, plan: TrainingCalendarPlan, state: GymaState, now: Date = Date()) -> Bool {
    day.date >= plan.calendar.startOfDay(for: now) && day.workouts.isEmpty && state.activeWorkout == nil
}

func calendarDate(_ date: Date, plan: TrainingCalendarPlan, template: String) -> String {
    calendarDate(date, calendar: plan.calendar, template: template)
}

func calendarDate(_ date: Date, calendar: Calendar, template: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter.string(from: date)
}

func calendarRange(_ plan: TrainingCalendarPlan) -> String {
    "\(calendarDate(plan.startDate, plan: plan, template: "d MMM")) – \(calendarDate(plan.lastDate, plan: plan, template: "d MMM yyyy"))"
}

func calendarCycleLabel(_ day: Int) -> String {
    switch day {
    case 1...2: return "Morning shift \(day)"
    case 3...4: return "Afternoon shift \(day - 2)"
    case 5...6: return "Night shift \(day - 4)"
    default: return "Day off \(day - 6)"
    }
}

func calendarTrainingTiming(_ day: Int) -> String {
    switch day {
    case 1...2: return "After your morning shift"
    case 3...4: return "Plan around your afternoon shift"
    case 5...6: return "Before your night shift, after adequate sleep"
    case 7: return "First day off after nights · Prioritize sleep and recovery"
    default: return "Train on your day off"
    }
}

func calendarActivitySymbol(_ kind: CalendarActivityKind) -> String {
    switch kind {
    case .inclineWalking: return "figure.walk"
    case .stretching: return "figure.flexibility"
    case .abs: return "figure.core.training"
    }
}
