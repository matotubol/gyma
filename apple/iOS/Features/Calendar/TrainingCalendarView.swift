import Foundation
import SwiftUI
import GymaCore

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
                            Text("\(workout.totalSets) sets · \(workout.volume.gymaNumber) kg · \(workout.minutes()) min")
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
