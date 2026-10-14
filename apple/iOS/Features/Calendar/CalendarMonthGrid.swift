import Foundation
import SwiftUI
import GymaCore

struct CalendarMonthGrid: View {
    let month: TrainingCalendarMonth
    let selectedDate: Date
    let compact: Bool
    let onSelect: (TrainingCalendarMonthDay) -> Void
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 44), spacing: compact ? 0 : 2), count: 7)
    }

    private var paddingDays: Int {
        (month.calendar.component(.weekday, from: month.monthStart) - month.calendar.firstWeekday + 7) % 7
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(0..<7, id: \.self) { index in
                    Text(weekdayLabel(index)).font(.caption.weight(.medium))
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
                ForEach(0..<paddingDays, id: \.self) { _ in Color.clear.frame(height: 64).accessibilityHidden(true) }
                ForEach(month.days) { day in
                    CalendarDayCell(day: day, calendar: month.calendar,
                                    isSelected: month.calendar.isDate(day.date, inSameDayAs: selectedDate)) {
                        onSelect(day)
                    }
                }
            }
        }.padding(compact ? 0 : 8).background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private func weekdayLabel(_ index: Int) -> String {
        let symbols = month.calendar.veryShortStandaloneWeekdaySymbols
        return symbols[(index + month.calendar.firstWeekday - 1) % 7]
    }
}

private struct CalendarDayCell: View {
    let day: TrainingCalendarMonthDay
    let calendar: Calendar
    let isSelected: Bool
    let action: () -> Void

    private var symbol: String? {
        if day.workouts.contains(where: { $0.isActive }) { return "record.circle" }
        if !day.workouts.isEmpty { return "checkmark.circle.fill" }
        guard let scheduledDay = day.scheduledDay else { return nil }
        return scheduledDay.isTraining ? "dumbbell.fill" : "minus"
    }

    private var hasTraining: Bool { day.scheduledDay?.isTraining == true || !day.workouts.isEmpty }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(calendarDate(day.date, calendar: calendar, template: "d"))
                    .font(.subheadline.bold())
                    .foregroundStyle(day.isToday ? Color.white : Color.primary)
                    .frame(width: 28, height: 28)
                    .background(day.isToday ? GymaStyle.accent : Color.clear, in: Circle())
                Group {
                    if let symbol { Image(systemName: symbol) }
                    else { Color.clear }
                }
                .font(.caption2).frame(height: 12)
                .foregroundStyle(hasTraining ? GymaStyle.accent : Color.secondary)
                CalendarActivityIndicators(activities: day.activities)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(hasTraining ? GymaStyle.accent.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(isSelected ? GymaStyle.accent : Color.clear, lineWidth: 2) }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityHint("Show this day's plan, activities and recorded training below the calendar")
    }

    private var accessibilityLabel: String {
        var descriptions = [calendarDate(day.date, calendar: calendar, template: "EEEE d MMMM yyyy")]
        if day.isToday { descriptions.insert("Today", at: 0) }
        if let scheduledDay = day.scheduledDay {
            descriptions.append(scheduledDay.isTraining ? "Strength training planned" : "Recovery day")
            descriptions.append(calendarCycleLabel(scheduledDay.cycleDay))
            if !day.isCurrentPlan { descriptions.append("Previous calendar block") }
        } else {
            descriptions.append("Outside a saved calendar block")
        }
        if day.workouts.contains(where: { $0.isActive }) { descriptions.append("Workout in progress") }
        let completedCount = day.workouts.filter { !$0.isActive }.count
        if completedCount > 0 { descriptions.append("\(completedCount) recorded workout\(completedCount == 1 ? "" : "s")") }
        descriptions += day.activities.map { "\($0.kind.title), \($0.durationMinutes) minutes, \($0.isCompleted ? "completed" : "planned")" }
        return descriptions.joined(separator: ", ")
    }
}
