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

struct TrainingCalendarView: View {
    @EnvironmentObject private var model: GymaAppModel
    @State private var setupPresented = false
    @State private var visibleMonth: Date?
    @State private var selectedDate: Date?
    @State private var dayDetails: CalendarDaySelection?
    @State private var blockDetailsExpanded = false
    @State private var keyExpanded = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(at: context.date)
        }
        .sheet(isPresented: $setupPresented) { TrainingCalendarSetupView(existing: model.state.trainingCalendar) }
        .sheet(item: $dayDetails) { selection in
            NavigationStack { TrainingCalendarDayView(selection: selection) }
        }
    }

    private func content(at now: Date) -> some View {
        let month = TrainingCalendarMonth.make(state: model.state, containing: visibleMonth ?? now, now: now)
        return GeometryReader { geometry in
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        monthContent(month, now: now, compact: geometry.size.width < 368).id("calendarMonth")
                        if let plan = model.state.trainingCalendar {
                            calendarDetails(plan, now: now)
                        } else {
                            setupIntroduction
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, geometry.size.width < 368 ? 6 : 16)
                }
                .background(GymaStyle.background)
                .navigationTitle("Training calendar")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Today") {
                            visibleMonth = month.calendar.dateInterval(of: .month, for: now)?.start
                            selectedDate = month.calendar.startOfDay(for: now)
                            withAnimation { scroll.scrollTo("calendarMonth", anchor: .top) }
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityHint("Show this month and select today")
                    }
                    if model.state.trainingCalendar != nil {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Edit", systemImage: "slider.horizontal.3") { setupPresented = true }
                                .disabled(model.storageBlocked || model.state.activeWorkout != nil)
                        }
                    }
                }
            }
        }
    }

    private func monthContent(_ month: TrainingCalendarMonth, now: Date, compact: Bool) -> some View {
        let selection = month.calendar.startOfDay(for: selectedDate ?? now)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                monthButton("Previous month", symbol: "chevron.left", offset: -1, month: month, now: now)
                Spacer(minLength: 0)
                Text(calendarDate(month.monthStart, calendar: month.calendar, template: "MMMM yyyy"))
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                monthButton("Next month", symbol: "chevron.right", offset: 1, month: month, now: now)
            }
            CalendarMonthGrid(month: month, selectedDate: selection, compact: compact) { day in
                visibleMonth = month.monthStart
                selectedDate = day.date
            }
            if let day = month.days.first(where: { month.calendar.isDate($0.date, inSameDayAs: selection) }) {
                selectedDaySummary(day, calendar: month.calendar, now: now)
            } else {
                Text("Select a day to see its plan and recorded training.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func monthButton(_ title: String, symbol: String, offset: Int, month: TrainingCalendarMonth, now: Date) -> some View {
        Button {
            guard let destination = month.month(byAdding: offset) else { return }
            visibleMonth = destination
            selectedDate = month.calendar.isDate(destination, equalTo: now, toGranularity: .month)
                ? month.calendar.startOfDay(for: now) : destination
        } label: {
            Image(systemName: symbol).font(.headline)
                .frame(width: 44, height: 44)
                .background(GymaStyle.card, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(month.month(byAdding: offset) == nil)
        .accessibilityLabel(title)
    }

    private func selectedDaySummary(_ day: TrainingCalendarMonthDay, calendar: Calendar, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(calendarDate(day.date, calendar: calendar, template: "EEEE d MMMM"))
                    .font(.headline)
                Spacer(minLength: 8)
                if day.isToday {
                    Text("Today").font(.caption.bold()).foregroundStyle(GymaStyle.accent)
                }
            }
            if let scheduledDay = day.scheduledDay {
                Label(scheduledDay.isTraining ? "Strength training" : "Recovery day",
                      systemImage: scheduledDay.isTraining ? "dumbbell.fill" : "moon.zzz")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(scheduledDay.isTraining ? GymaStyle.accent : Color.secondary)
                Text("\(calendarCycleLabel(scheduledDay.cycleDay)) · Cycle day \(scheduledDay.cycleDay)")
                    .font(.caption).foregroundStyle(.secondary)
                if !day.isCurrentPlan {
                    Text("Previous calendar block").font(.caption).foregroundStyle(.secondary)
                }
                if day.workouts.isEmpty {
                    if day.date < calendar.startOfDay(for: now) {
                        Text(scheduledDay.isTraining ? "No workout recorded for this day." : "No strength workout recorded.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else if let session = scheduledDay.session {
                        Text("\(day.isToday ? "Today's session" : "Session preview"): \(session.title)")
                            .font(.subheadline)
                    } else if scheduledDay.isTraining {
                        Text("A strength session is planned for this date.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(unscheduledDayTitle(day, calendar: calendar))
                    .font(.subheadline.weight(.medium))
                if let plan = model.state.trainingCalendar,
                   day.date < calendar.startOfDay(for: plan.startDate) {
                    Text("Your current block starts \(calendarDate(plan.startDate, calendar: calendar, template: "d MMMM yyyy")).")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if day.workouts.isEmpty {
                    Text(day.date < calendar.startOfDay(for: now) ? "No workout recorded for this day." : "No strength workout is scheduled for this date.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            ForEach(day.workouts) { workout in
                NavigationLink {
                    if workout.isActive { ActiveWorkoutView(workoutID: workout.id) }
                    else { WorkoutDetailView(workoutID: workout.id) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: workout.isActive ? "record.circle" : "checkmark.circle.fill")
                            .foregroundStyle(GymaStyle.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workout.title).font(.subheadline.bold())
                            Text("\(workout.loggedSets) sets · \(workout.liftedVolume.gymaNumber) kg · \(workout.minutes()) min")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(workout.isActive ? "Resume workout" : "View recorded weights and reps")
                                .font(.caption).foregroundStyle(GymaStyle.accent)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }.frame(minHeight: 44)
                }.buttonStyle(.plain)
            }
            ForEach(day.activities) { activity in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: calendarActivitySymbol(activity.kind))
                        .foregroundStyle(activity.isCompleted ? GymaStyle.accent : Color.secondary)
                    Text("\(activity.kind.title) · \(activity.durationMinutes) min")
                    Spacer(minLength: 4)
                    Text(activity.isCompleted ? "Done" : "Planned").foregroundStyle(.secondary)
                }.font(.caption)
            }
            if day.isCurrentPlan, let scheduledDay = day.scheduledDay, let plan = day.plan {
                Button {
                    dayDetails = .init(date: scheduledDay.date, blockStartDate: plan.startDate, timeZoneIdentifier: plan.timeZoneIdentifier)
                } label: {
                    Label("Day details and options", systemImage: "arrow.up.right.square")
                        .frame(minHeight: 44)
                }.font(.subheadline.bold())
                if day.isToday, day.workouts.isEmpty {
                    Text(model.state.dailyTrainingStatus(now: now).allowsWorkoutStart
                         ? "Open day details to check in and start today's workout."
                         : "No new strength workout can start today.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private func unscheduledDayTitle(_ day: TrainingCalendarMonthDay, calendar: Calendar) -> String {
        guard let plan = model.state.trainingCalendar else { return "No calendar plan for this day" }
        return day.date < calendar.startOfDay(for: plan.startDate) ? "Before your current block" : "Outside your current block"
    }

    private var setupIntroduction: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("A plan that fits your shifts", systemImage: "calendar.badge.clock")
                .font(.title2.bold()).foregroundStyle(GymaStyle.accent)
            Text("See 56 days of training and recovery, with the training days you choose in each 10-day shift cycle.")
            Text("Start training on 13 October 2026, after sleep following your night shifts. Your first morning shift stays on 17 October. The opening strength dates are 13, 14 and 16 October.")
                .foregroundStyle(.secondary)
            Text("Add optional incline walking, stretching or abs to individual days. These activities keep your strength program in its usual order.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("Set up eight weeks", systemImage: "plus") { setupPresented = true }
                .buttonStyle(.borderedProminent).disabled(model.storageBlocked || model.state.activeWorkout != nil)
            NavigationLink("View your recurring program") { TrainingProgramView() }
        }.padding(20).background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 22))
    }

    private func calendarDetails(_ plan: TrainingCalendarPlan, now: Date) -> some View {
        let entries = plan.entries(program: model.state.trainingProgram, history: model.state.workouts, now: now)
        let sessions = model.state.trainingProgram?.sessions ?? []
        return VStack(alignment: .leading, spacing: 18) {
            DisclosureGroup("Calendar key", isExpanded: $keyExpanded) {
                CalendarLegend().padding(.top, 12)
            }.font(.subheadline.bold())
            DisclosureGroup("Current block · \(calendarRange(plan))", isExpanded: $blockDetailsExpanded) {
                VStack(alignment: .leading, spacing: 18) {
                    blockSummary(plan, entries: entries)
                    if !sessions.isEmpty { CalendarSessionKey(sessions: sessions) }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Review on \(calendarDate(plan.reviewDate, plan: plan, template: "d MMMM yyyy"))")
                            .font(.headline)
                        Text("Review your progress, recovery and exercise comfort after eight weeks. Your recorded workouts remain available in every month.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        NavigationLink("Review your program") { TrainingProgramView() }
                            .font(.subheadline.bold())
                    }
                    if model.state.trainingCalendarHistory?.isEmpty == false {
                        NavigationLink {
                            TrainingCalendarHistoryView()
                        } label: {
                            Label("Previous calendar blocks", systemImage: "clock.arrow.circlepath")
                                .font(.subheadline.bold())
                        }
                    }
                }
                .padding(.top, 12)
            }
        }
    }

    private func blockSummary(_ plan: TrainingCalendarPlan, entries: [TrainingCalendarDay]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(calendarRange(plan)).font(.title2.bold())
            Text("56 days · \(entries.filter(\.isTraining).count) planned strength sessions")
                .font(.subheadline).foregroundStyle(GymaStyle.accent)
            Text("2 mornings · 2 afternoons · 2 nights · 4 days off")
                .font(.subheadline).foregroundStyle(.secondary)
            if model.state.trainingProgram == nil {
                Text("Training dates are ready. Save a recurring program to see its sessions and exercises here.")
                    .font(.subheadline)
                NavigationLink("Set up your program") { TrainingProgramView() }
                    .font(.subheadline.bold())
            } else {
                Text("Sessions continue in your saved program's order across shift cycles. Future sessions are a preview; completed training determines what comes next.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if plan.prefersUpperLower {
                Text("Preference: alternating upper/lower. Your saved program supplies the sessions; discuss any split changes with your coach.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Calendar time zone: \(plan.timeZoneIdentifier)")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct CalendarDaySelection: Identifiable {
    let date: Date
    let blockStartDate: Date
    let timeZoneIdentifier: String
    var id: Date { date }

    func matches(_ plan: TrainingCalendarPlan) -> Bool {
        plan.startDate == blockStartDate && plan.timeZoneIdentifier == timeZoneIdentifier && plan.dayOffset(for: date) != nil
    }
}

private struct TrainingCalendarHistoryView: View {
    @EnvironmentObject private var model: GymaAppModel
    private var plans: [TrainingCalendarPlan] { model.state.trainingCalendarHistory ?? [] }

    var body: some View {
        List {
            ForEach(Array(plans.enumerated().reversed()), id: \.offset) { _, plan in
                NavigationLink {
                    ArchivedCalendarPlanView(plan: plan)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(calendarRange(plan)).font(.headline)
                        Text("\(plan.activities.filter(\.isCompleted).count) optional activities completed")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Calendar history")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ArchivedCalendarPlanView: View {
    @EnvironmentObject private var model: GymaAppModel
    let plan: TrainingCalendarPlan

    var body: some View {
        List {
            Section {
                Text(calendarRange(plan)).font(.headline)
                Text("Your saved schedule and optional activity records for this block.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(plan.entries(program: nil, history: model.state.workouts)) { day in
                Section(calendarDate(day.date, plan: plan, template: "EEEE d MMMM")) {
                    LabeledContent(calendarCycleLabel(day.cycleDay), value: day.isTraining ? "Strength" : "Recovery")
                    ForEach(day.workouts) { workout in
                        NavigationLink {
                            if workout.isActive { ActiveWorkoutView(workoutID: workout.id) }
                            else { WorkoutDetailView(workoutID: workout.id) }
                        } label: {
                            Label(workout.title, systemImage: workout.isActive ? "record.circle" : "checkmark.circle.fill")
                        }
                    }
                    ForEach(day.activities) { activity in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(activity.kind.title, systemImage: calendarActivitySymbol(activity.kind))
                            Text("\(activity.durationMinutes) min · \(activity.isCompleted ? "Completed" : "Planned")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Previous block")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CalendarSessionKey: View {
    let sessions: [ProgramSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Program sessions").font(.subheadline.bold())
            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                HStack(spacing: 8) {
                    Text("\(index + 1)").font(.caption.bold()).foregroundStyle(GymaStyle.accent)
                        .frame(width: 22, height: 22)
                        .background(GymaStyle.accent.opacity(0.12), in: Circle())
                    Text(session.title).font(.subheadline)
                }
            }
        }
    }
}

private struct CalendarLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Label("Training", systemImage: "dumbbell.fill").foregroundStyle(GymaStyle.accent)
                Label("Recovery", systemImage: "minus")
            }
            HStack(spacing: 16) {
                Label("Completed", systemImage: "checkmark.circle.fill")
                Label("Active", systemImage: "record.circle")
            }
            HStack(spacing: 12) {
                Label("Walk", systemImage: "figure.walk")
                Label("Stretch", systemImage: "figure.flexibility")
                Label("Abs", systemImage: "figure.core.training")
            }
            Text("Filled date = today · Outlined day = selected")
            Text("Dates outside a saved block show recorded training when available. Select a date for shift details and optional activities.")
        }.font(.caption).foregroundStyle(.secondary)
    }
}

private struct CalendarMonthGrid: View {
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

private struct CalendarActivityIndicators: View {
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

private struct TrainingCalendarDayView: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    let selection: CalendarDaySelection
    @State private var movePresented = false
    @State private var startingProgram = false
    @State private var activePresented = false
    @State private var activeWorkoutID: String?
    @State private var workoutEditor: CalendarWorkoutDraft?

    private struct CalendarWorkoutDraft: Identifiable {
        let id = UUID()
        let date: Date
        let exercises: [WorkoutExercise]
        let storeID: String
        let revision: Int
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            List {
                if let plan = model.state.trainingCalendar,
                   selection.matches(plan),
                   let day = plan.entries(program: model.state.trainingProgram, history: model.state.workouts, now: context.date)
                    .first(where: { plan.calendar.isDate($0.date, inSameDayAs: selection.date) }) {
                    dayContent(day, plan: plan, now: context.date)
                } else {
                    Text("This day is no longer in your calendar.").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Your day")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(isPresented: $movePresented) { TrainingCalendarMoveView(selection: selection) }
        .sheet(item: $workoutEditor) { draft in
            PlannedWorkoutEditor(title: "Edit this day's workout", exercises: draft.exercises) { exercises in
                guard model.state.storeID == draft.storeID, model.state.revision == draft.revision else {
                    throw GymaError.stale("Your training data changed. Reopen this day's workout before saving.")
                }
                guard model.update({ try $0.setCalendarWorkout(on: draft.date, exercises: exercises) }) else {
                    throw GymaError.invalid(model.errorMessage ?? "The workout could not be saved.")
                }
            }
        }
        .sheet(isPresented: $startingProgram) {
            ProgramWorkoutStartView { workoutID in
                startingProgram = false
                activeWorkoutID = workoutID
                activePresented = true
            }
        }
        .navigationDestination(isPresented: $activePresented) {
            if let activeWorkoutID { ActiveWorkoutView(workoutID: activeWorkoutID) }
        }
    }

    @ViewBuilder
    private func dayContent(_ day: TrainingCalendarDay, plan: TrainingCalendarPlan, now: Date) -> some View {
        Section {
            Text(calendarDate(day.date, plan: plan, template: "EEEE d MMMM yyyy")).font(.title3.bold())
            LabeledContent("Shift", value: calendarCycleLabel(day.cycleDay))
            LabeledContent("10-day cycle", value: "Day \(day.cycleDay)")
            Label(day.isTraining ? "Training day" : "Recovery day", systemImage: day.isTraining ? "dumbbell.fill" : "moon.zzz")
                .foregroundStyle(day.isTraining ? GymaStyle.accent : Color.secondary)
            if day.isTraining { Text(calendarTrainingTiming(day.cycleDay)).font(.subheadline).foregroundStyle(.secondary) }
        }
        if !day.workouts.isEmpty {
            Section("Recorded training") {
                ForEach(day.workouts) { workout in
                    NavigationLink {
                        if workout.isActive { ActiveWorkoutView(workoutID: workout.id) }
                        else { WorkoutDetailView(workoutID: workout.id) }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Label(workout.title, systemImage: workout.isActive ? "record.circle" : "checkmark.circle.fill")
                                .font(.headline)
                            Text("\(workout.loggedSets) sets · \(workout.liftedVolume.gymaNumber) kg · \(workout.minutes()) min")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(workout.isActive ? "In progress" : "Completed").font(.caption).foregroundStyle(GymaStyle.accent)
                        }
                    }
                }
            }
        }
        if day.isTraining && day.workouts.isEmpty {
            if let session = day.session {
                sessionPreview(session)
                if calendarCanEdit(day, plan: plan, state: model.state, now: now) {
                    Section {
                        Button("Edit this day's workout", systemImage: "square.and.pencil") {
                            workoutEditor = .init(date: day.date, exercises: session.exercises,
                                                  storeID: model.state.storeID, revision: model.state.revision)
                        }.disabled(model.storageBlocked || model.coachRequestInFlight)
                        if plan.workoutOverride(on: day.date) != nil {
                            Label("Custom exercises for this date", systemImage: "calendar.badge.checkmark")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Reset to program exercises") {
                                model.update { try $0.setCalendarWorkout(on: day.date, exercises: nil) }
                            }.disabled(model.storageBlocked || model.coachRequestInFlight)
                        }
                    } footer: {
                        Text("Replace exercises, edit targets or change their order for this date only. You can also ask Coach to edit this date. Your recurring program stays unchanged.")
                    }
                }
            }
            else if day.date < plan.calendar.startOfDay(for: now) {
                Section("Training") {
                    Text("No workout recorded. This date does not add catch-up training.")
                        .foregroundStyle(.secondary)
                }
            }
            else {
                Section("Training") {
                    Text("Save a recurring program to fill in this session's exercises and targets.")
                    NavigationLink("Your program") { TrainingProgramView() }
                }
            }
        }
        if plan.calendar.isDate(day.date, inSameDayAs: now), day.isTraining, day.workouts.isEmpty,
           model.state.dailyTrainingStatus(now: now).allowsWorkoutStart {
            Section {
                if model.state.trainingProgram != nil {
                    Button("Start today's workout", systemImage: "play.fill") {
                        guard let currentPlan = model.state.trainingCalendar, selection.matches(currentPlan),
                              currentPlan.calendar.isDate(day.date, inSameDayAs: Date()),
                              model.state.dailyTrainingStatus().allowsWorkoutStart else { return }
                        startingProgram = true
                    }
                    .disabled(model.storageBlocked || model.coachRequestInFlight)
                } else {
                    NavigationLink("Plan your program with coach") { TrainingProgramView() }
                }
            } footer: {
                Text("Program planning uses your goals and schedule. Today's sleep, energy and soreness are collected only when starting a workout.")
            }
        }
        CalendarDayActivities(day: day, plan: plan, now: now)
        Section {
            if calendarCanEdit(day, plan: plan, state: model.state, now: now) {
                Button(day.isTraining ? "Make this a recovery day" : "Plan training on this day", systemImage: day.isTraining ? "moon.zzz" : "dumbbell") {
                    model.update {
                        guard let currentPlan = $0.trainingCalendar, selection.matches(currentPlan) else {
                            throw GymaError.invalid("This day is no longer in your current calendar.")
                        }
                        try $0.setCalendarTrainingDay(on: day.date, isTraining: !day.isTraining, now: Date())
                    }
                }.disabled(model.storageBlocked)
                if day.isTraining {
                    Button("Move training to another day", systemImage: "arrow.right") { movePresented = true }
                        .disabled(model.storageBlocked)
                }
            } else {
                Text("Past dates and days with recorded training cannot be changed. Finish any active workout before editing the calendar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: { Text("Calendar options") } footer: {
            Text("Moving or skipping a date adjusts the preview. Your session order advances when training is completed; missed dates never create catch-up workouts. Changing the calendar clears an unstarted draft. Check in again before training.")
        }
    }

    private func sessionPreview(_ session: ProgramSession) -> some View {
        Section {
            ForEach(session.exercises) { exercise in
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.name(for: exercise.exerciseID)).font(.headline)
                    if let target = exercise.target {
                        Text(calendarTargetDescription(target)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 3)
            }
        } header: { Text("Preview · \(session.title)") } footer: {
            Text("These are the targets planned for this date. Loads, repetitions and readiness are reviewed when you prepare the session.")
        }
    }
}

private struct CalendarDayActivities: View {
    @EnvironmentObject private var model: GymaAppModel
    @State private var error: String?
    let day: TrainingCalendarDay
    let plan: TrainingCalendarPlan
    let now: Date

    private var canEdit: Bool {
        day.date >= plan.calendar.startOfDay(for: now)
    }

    private var isToday: Bool { plan.calendar.isDate(day.date, inSameDayAs: now) }

    private var availableKinds: [CalendarActivityKind] {
        CalendarActivityKind.allCases.filter { kind in !day.activities.contains(where: { $0.kind == kind }) }
    }

    var body: some View {
        Section {
            if day.activities.isEmpty {
                Text("No optional activities planned.").foregroundStyle(.secondary)
            }
            ForEach(day.activities) { activity in activityRow(activity) }
            if canEdit && !availableKinds.isEmpty {
                Menu {
                    ForEach(availableKinds) { kind in
                        Button(kind.title, systemImage: calendarActivitySymbol(kind)) {
                            updateActivity { try $0.setCalendarActivity(on: day.date, kind: kind, isPlanned: true, now: Date()) }
                        }
                    }
                } label: {
                    Label("Add an optional activity", systemImage: "plus.circle")
                }.disabled(model.storageBlocked)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        } header: { Text("Optional activities") } footer: {
            Text("Add these on strength or recovery days when you feel recovered. Walking and stretching can stay easy; hard abs sessions need recovery too. Activities do not advance your strength program. Mark them done on the day; past dates stay unchanged.")
        }
    }

    private func activityRow(_ activity: CalendarActivity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(activity.kind.title, systemImage: calendarActivitySymbol(activity.kind)).font(.headline)
                Spacer()
                if activity.isCompleted {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(GymaStyle.accent)
                        .accessibilityLabel("Completed")
                }
            }
            if canEdit && !activity.isCompleted {
                Stepper(value: Binding(get: { activity.durationMinutes }, set: { minutes in
                    updateActivity {
                        try $0.setCalendarActivity(on: day.date, kind: activity.kind, isPlanned: true, durationMinutes: minutes, now: Date())
                    }
                }), in: activity.kind.durationRange, step: 5) {
                    Text("\(activity.durationMinutes) min").font(.subheadline)
                }
                .accessibilityLabel("\(activity.kind.title) duration")
                .disabled(model.storageBlocked)
            } else {
                Text("\(activity.durationMinutes) min · \(activity.isCompleted ? "Completed" : "Planned")")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Text(activity.kind.guidance).font(.caption).foregroundStyle(.secondary)
            if canEdit {
                HStack {
                    if isToday {
                        Button(activity.isCompleted ? "Undo completion" : "Mark done", systemImage: activity.isCompleted ? "arrow.uturn.backward" : "checkmark") {
                            updateActivity {
                                try $0.setCalendarActivityCompleted(on: day.date, kind: activity.kind, isCompleted: !activity.isCompleted, now: Date())
                            }
                        }
                        .disabled(model.storageBlocked)
                    }
                    Spacer()
                    if !activity.isCompleted {
                        Button("Remove", role: .destructive) {
                            updateActivity {
                                try $0.setCalendarActivity(on: day.date, kind: activity.kind, isPlanned: false, now: Date())
                            }
                        }
                        .disabled(model.storageBlocked)
                    }
                }.font(.subheadline).buttonStyle(.borderless)
            }
        }.padding(.vertical, 5)
    }

    private func updateActivity(_ mutation: (inout GymaState) throws -> Void) {
        error = model.update(mutation) ? nil : model.errorMessage
    }
}

private struct TrainingCalendarMoveView: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    let selection: CalendarDaySelection

    var body: some View {
        NavigationStack {
            List {
                if let plan = model.state.trainingCalendar, selection.matches(plan) {
                    let source = selection.date
                    let entries = plan.entries(program: model.state.trainingProgram, history: model.state.workouts)
                    let destinations = entries.filter { !$0.isTraining && calendarCanEdit($0, plan: plan, state: model.state) }
                    Section {
                        Text("Move training from \(calendarDate(source, plan: plan, template: "EEE d MMM")) to a recovery day in this block.")
                            .foregroundStyle(.secondary)
                    } footer: {
                        Text("Changing the calendar clears an unstarted draft. Check in again before training.")
                    }
                    if destinations.isEmpty {
                        Text("There are no editable recovery days in this block.").foregroundStyle(.secondary)
                    }
                    ForEach(destinations) { day in
                        Button {
                            if model.update({
                                guard let currentPlan = $0.trainingCalendar, selection.matches(currentPlan) else {
                                    throw GymaError.invalid("This day is no longer in your current calendar.")
                                }
                                try $0.moveCalendarTrainingDay(from: source, to: day.date, now: Date())
                            }) { dismiss() }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(calendarDate(day.date, plan: plan, template: "EEEE d MMMM"))
                                Text(calendarCycleLabel(day.cycleDay)).font(.caption).foregroundStyle(.secondary)
                            }
                        }.disabled(model.storageBlocked)
                    }
                } else {
                    Text("This day is no longer in your current calendar.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Move training")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct TrainingCalendarSetupView: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    let existing: TrainingCalendarPlan?
    @State private var startDate: Date
    @State private var cycleAnchorDate: Date
    @State private var trainingDays: Set<Int>
    @State private var prefersUpperLower: Bool
    @State private var openingScheduleRequested = false
    @State private var error: String?
    private let timeZone: TimeZone
    private let basePlan: TrainingCalendarPlan

    init(existing: TrainingCalendarPlan?) {
        self.existing = existing
        let zone = existing.flatMap { TimeZone(identifier: $0.timeZoneIdentifier) } ?? TimeZone(identifier: "Europe/Amsterdam") ?? .current
        timeZone = zone
        let plan = existing ?? TrainingCalendarPlan.defaultPlan(now: Date(), timeZone: zone)
        basePlan = plan
        _startDate = State(initialValue: plan.startDate)
        _cycleAnchorDate = State(initialValue: plan.cycleAnchorDate)
        _trainingDays = State(initialValue: Set(plan.trainingCycleDays))
        _prefersUpperLower = State(initialValue: plan.prefersUpperLower)
    }

    private var preview: TrainingCalendarPlan {
        (try? configuredPlan()) ?? TrainingCalendarPlan(startDate: startDate, cycleAnchorDate: cycleAnchorDate, trainingCycleDays: trainingDays.sorted(), timeZone: timeZone, prefersUpperLower: prefersUpperLower)
    }

    private var openingStartDate: Date {
        basePlan.calendar.date(from: DateComponents(year: 2026, month: 10, day: 13)) ?? basePlan.startDate
    }

    private var firstMorningDate: Date {
        basePlan.calendar.date(from: DateComponents(year: 2026, month: 10, day: 17)) ?? basePlan.cycleAnchorDate
    }

    private var configurationError: String? {
        do { _ = try configuredPlan(); return nil }
        catch { return error.localizedDescription }
    }

    private func configuredPlan() throws -> TrainingCalendarPlan {
        var plan: TrainingCalendarPlan
        if existing != nil {
            plan = try basePlan.reconfigured(startDate: startDate, cycleAnchorDate: cycleAnchorDate, trainingCycleDays: trainingDays.sorted(), prefersUpperLower: prefersUpperLower)
        } else {
            plan = TrainingCalendarPlan(startDate: startDate, cycleAnchorDate: cycleAnchorDate, trainingCycleDays: trainingDays.sorted(), timeZone: timeZone, prefersUpperLower: prefersUpperLower)
            if plan.cycleAnchorDate == firstMorningDate {
                for override in basePlan.dayOverrides {
                    if let date = basePlan.date(at: override.dayOffset), let offset = plan.dayOffset(for: date) {
                        plan.dayOverrides.append(.init(dayOffset: offset, isTraining: override.isTraining))
                    }
                }
            }
            try plan.validate()
        }
        if openingScheduleRequested, plan.startDate == openingStartDate, plan.cycleAnchorDate == firstMorningDate {
            try plan.setTrainingDay(on: openingStartDate, isTraining: true, now: Date())
            if let recoveryDate = plan.calendar.date(byAdding: .day, value: 2, to: openingStartDate) {
                try plan.setTrainingDay(on: recoveryDate, isTraining: false, now: Date())
            }
        }
        return plan
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Block starts", selection: $startDate, displayedComponents: .date)
                    DatePicker("First morning shift", selection: $cycleAnchorDate, displayedComponents: .date)
                    Text("Eight weeks: \(calendarRange(preview))\nReview: \(calendarDate(preview.reviewDate, plan: preview, template: "d MMMM yyyy"))")
                        .font(.caption).foregroundStyle(.secondary)
                    if existing != nil, basePlan.calendar.startOfDay(for: Date()) <= openingStartDate {
                        Button("Start on 13 October") {
                            startDate = openingStartDate
                            cycleAnchorDate = firstMorningDate
                            openingScheduleRequested = true
                            error = nil
                        }.disabled(model.storageBlocked || model.state.activeWorkout != nil)
                    }
                } header: { Text("Your dates") } footer: {
                    Text("The block can start before your first morning shift. That shift anchors the repeating 10-day cycle. Dates stay in \(timeZone.identifier).")
                }
                if preview.startDate == openingStartDate, preview.cycleAnchorDate == firstMorningDate {
                    Section("Your first days off") {
                        ForEach(Array(preview.entries(program: nil, history: []).prefix(4))) { day in
                            LabeledContent(calendarDate(day.date, plan: preview, template: "EEE d MMM"), value: day.isTraining ? "Strength" : "Recovery")
                        }
                        Text("On 13 October, sleep after your final night shift before training. Check your energy and soreness; move the session if you need more recovery.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    ForEach(1...10, id: \.self) { day in
                        Toggle(isOn: Binding(get: { trainingDays.contains(day) }, set: { enabled in
                            if enabled { trainingDays.insert(day) } else { trainingDays.remove(day) }
                        })) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Day \(day) · \(calendarCycleLabel(day))")
                                if [2, 5, 8, 9, 10].contains(day) {
                                    Text(calendarTrainingTiming(day)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.tint(GymaStyle.accent)
                    }
                } header: { Text("Training days · \(trainingDays.count) of 10 selected") } footer: {
                    Text("Choose 1–10 training days per cycle to fit your schedule. Individual dates can be moved or changed to recovery after saving. Saved program sessions continue across cycles.")
                }
                Section {
                    Toggle("Prefer alternating upper/lower", isOn: $prefersUpperLower)
                } footer: {
                    Text("Your coach uses this preference when discussing your program. Saving this calendar keeps your current exercises and session order.")
                }
                if existing != nil {
                    Section {
                        Text(startDate > basePlan.lastDate
                             ? "This starts a new eight-week block. Your previous calendar and optional activity records will stay in calendar history."
                             : "Individual date changes and optional activities keep their calendar dates when the block start changes. A change that would leave any of them outside the block must be resolved first. Recorded training and completed activities are kept.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let configurationError { Section { Text(configurationError).foregroundStyle(.red) } }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Button(existing == nil ? "Create calendar" : "Save calendar") { save() }
                        .disabled(configurationError != nil || model.storageBlocked || model.state.activeWorkout != nil)
                } footer: {
                    Text("The calendar reserves training dates. It does not start workouts or replace your program at the end of eight weeks. Changing the calendar clears an unstarted draft. Check in again before training.")
                }
            }
            .environment(\.timeZone, timeZone)
            .environment(\.calendar, preview.calendar)
            .navigationTitle(existing == nil ? "Plan eight weeks" : "Calendar settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func save() {
        do {
            let plan = try configuredPlan()
            if model.update({ try $0.saveTrainingCalendar(plan, now: Date()) }) { dismiss() }
            else { error = model.errorMessage }
        } catch { self.error = error.localizedDescription }
    }
}

private func calendarCanEdit(_ day: TrainingCalendarDay, plan: TrainingCalendarPlan, state: GymaState, now: Date = Date()) -> Bool {
    day.date >= plan.calendar.startOfDay(for: now) && day.workouts.isEmpty && state.activeWorkout == nil
}

private func calendarDate(_ date: Date, plan: TrainingCalendarPlan, template: String) -> String {
    calendarDate(date, calendar: plan.calendar, template: template)
}

private func calendarDate(_ date: Date, calendar: Calendar, template: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter.string(from: date)
}

private func calendarRange(_ plan: TrainingCalendarPlan) -> String {
    "\(calendarDate(plan.startDate, plan: plan, template: "d MMM")) – \(calendarDate(plan.lastDate, plan: plan, template: "d MMM yyyy"))"
}

private func calendarCycleLabel(_ day: Int) -> String {
    switch day {
    case 1...2: return "Morning shift \(day)"
    case 3...4: return "Afternoon shift \(day - 2)"
    case 5...6: return "Night shift \(day - 4)"
    default: return "Day off \(day - 6)"
    }
}

private func calendarTrainingTiming(_ day: Int) -> String {
    switch day {
    case 1...2: return "After your morning shift"
    case 3...4: return "Plan around your afternoon shift"
    case 5...6: return "Before your night shift, after adequate sleep"
    case 7: return "First day off after nights · Prioritize sleep and recovery"
    default: return "Train on your day off"
    }
}

private func calendarDaySymbol(_ day: TrainingCalendarDay) -> String {
    if day.workouts.contains(where: { $0.isActive }) { return "record.circle" }
    if !day.workouts.isEmpty { return "checkmark.circle.fill" }
    return day.isTraining ? "dumbbell.fill" : "minus"
}

private func calendarActivitySymbol(_ kind: CalendarActivityKind) -> String {
    switch kind {
    case .inclineWalking: return "figure.walk"
    case .stretching: return "figure.flexibility"
    case .abs: return "figure.core.training"
    }
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

private func calendarTargetDescription(_ target: ExerciseTarget) -> String {
    let load = target.loadKg.map { "\($0.gymaNumber) kg" } ?? "Load to review"
    let effort = target.targetEffort.map { " · \($0.label)" } ?? ""
    return "\(target.sets) × \(target.repsMin)–\(target.repsMax) · \(load) · \(target.restSeconds)s rest\(effort)"
}
