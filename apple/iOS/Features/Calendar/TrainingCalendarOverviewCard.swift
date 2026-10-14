import Foundation
import SwiftUI
import GymaCore

struct TrainingCalendarOverviewCard: View {
    @EnvironmentObject private var model: GymaAppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            card(at: context.date)
        }
    }

    private func card(at now: Date) -> some View {
        NavigationLink { TrainingCalendarView() } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Your calendar", systemImage: "calendar")
                        .font(.headline).foregroundStyle(GymaStyle.accent)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption)
                }
                if let plan = model.state.trainingCalendar {
                    summary(plan, now: now)
                } else {
                    Text("Plan training around your shifts").font(.title3.bold())
                    Text("Choose your training days in each 10-day cycle and see all eight weeks ahead.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Set up calendar").font(.subheadline.bold()).foregroundStyle(GymaStyle.accent)
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 22))
        }.buttonStyle(.plain)
    }

    private func summary(_ plan: TrainingCalendarPlan, now: Date) -> some View {
        let entries = plan.entries(program: model.state.trainingProgram, history: model.state.workouts, now: now)
        let today = plan.calendar.startOfDay(for: now)
        let upcoming = entries.first { $0.date >= today && $0.isTraining && $0.workouts.isEmpty }
        let preview = Array(entries.filter { $0.date >= today }.prefix(7))
        return VStack(alignment: .leading, spacing: 12) {
            Text(calendarRange(plan)).font(.subheadline.weight(.medium))
            if let upcoming {
                Text("Next: \(upcoming.session?.title ?? "Training") · \(calendarDate(upcoming.date, plan: plan, template: "EEE d MMM"))")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text(today > plan.lastDate ? "Block complete · Review your program" : "No upcoming training days in this block")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if !preview.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    ForEach(preview) { day in CalendarPreviewDay(day: day, plan: plan, now: now) }
                }
                Text(today < plan.startDate ? "First seven planned days · Open calendar" : "Next seven days · Open calendar")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct CalendarPreviewDay: View {
    let day: TrainingCalendarDay
    let plan: TrainingCalendarPlan
    let now: Date

    var body: some View {
        VStack(spacing: 6) {
            Text(calendarDate(day.date, plan: plan, template: "EEEEE")).font(.caption)
            Text(calendarDate(day.date, plan: plan, template: "d")).font(.subheadline.bold())
            Image(systemName: calendarDaySymbol(day)).font(.caption)
                .foregroundStyle(day.isTraining ? GymaStyle.accent : Color.secondary)
            CalendarActivityIndicators(activities: day.activities)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(day.isTraining ? GymaStyle.accent.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(calendarDayAccessibility(day, plan: plan, now: now))
    }
}

private func calendarDaySymbol(_ day: TrainingCalendarDay) -> String {
    if day.workouts.contains(where: { $0.isActive }) { return "record.circle" }
    if !day.workouts.isEmpty { return "checkmark.circle.fill" }
    return day.isTraining ? "dumbbell.fill" : "minus"
}

private func calendarDayAccessibility(_ day: TrainingCalendarDay, plan: TrainingCalendarPlan, now: Date) -> String {
    let date = calendarDate(day.date, plan: plan, template: "EEEE d MMMM yyyy")
    let training = day.isTraining ? day.session?.title ?? "Training" : "Recovery"
    let status = day.workouts.contains(where: { $0.isActive }) ? ", workout in progress" : (!day.workouts.isEmpty ? ", completed workout" : "")
    let today = plan.calendar.isDate(day.date, inSameDayAs: now) ? "Today, " : ""
    let activities = day.activities.map { "\($0.kind.title), \($0.durationMinutes) minutes, \($0.isCompleted ? "completed" : "planned")" }.joined(separator: "; ")
    let optionalActivities = activities.isEmpty ? "" : ", optional activities: \(activities)"
    return "\(today)\(date), \(calendarCycleLabel(day.cycleDay)), \(training)\(status)\(optionalActivities)"
}
