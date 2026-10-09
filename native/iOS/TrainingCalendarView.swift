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
                    Label("Your eight weeks", systemImage: "calendar")
                        .font(.headline).foregroundStyle(GymaStyle.accent)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption)
                }
                if let plan = model.state.trainingCalendar {
                    summary(plan, now: now)
                } else {
                    Text("Plan training around your shifts").font(.title3.bold())
                    Text("Five sessions per 10-day cycle. Set up your dates and see all eight weeks ahead.")
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
                Text(today < plan.startDate ? "First seven days · Open all eight weeks" : "Next seven days · Open all eight weeks")
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
    @State private var selectedDay: CalendarDaySelection?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(at: context.date)
        }
        .sheet(isPresented: $setupPresented) { TrainingCalendarSetupView(existing: model.state.trainingCalendar) }
        .sheet(item: $selectedDay) { selection in
            NavigationStack { TrainingCalendarDayView(dayOffset: selection.id) }
        }
    }

    private func content(at now: Date) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let plan = model.state.trainingCalendar {
                    calendarContent(plan, now: now)
                } else {
                    setupIntroduction
                }
            }.padding(20)
        }
        .background(GymaStyle.background)
        .navigationTitle("Training calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let plan = model.state.trainingCalendar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Today") {
                        if let offset = plan.dayOffset(for: now) { selectedDay = .init(id: offset) }
                    }.disabled(plan.dayOffset(for: now) == nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit", systemImage: "slider.horizontal.3") { setupPresented = true }
                        .disabled(model.storageBlocked || model.state.activeWorkout != nil)
                }
            }
        }
    }

    private var setupIntroduction: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("A plan that fits your shifts", systemImage: "calendar.badge.clock")
                .font(.title2.bold()).foregroundStyle(GymaStyle.accent)
            Text("See 56 days of training and recovery, with five sessions in each 10-day shift cycle.")
            Text("Your default is after morning shift 2, before night shift 1, and days off 2, 3 and 4. Your first morning shift is 17 October 2026.")
                .foregroundStyle(.secondary)
            Button("Set up eight weeks", systemImage: "plus") { setupPresented = true }
                .buttonStyle(.borderedProminent).disabled(model.storageBlocked || model.state.activeWorkout != nil)
            NavigationLink("View your recurring program") { TrainingProgramView() }
        }.padding(20).background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 22))
    }

    private func calendarContent(_ plan: TrainingCalendarPlan, now: Date) -> some View {
        let entries = plan.entries(program: model.state.trainingProgram, history: model.state.workouts, now: now)
        let months = calendarMonths(plan)
        let sessions = model.state.trainingProgram?.sessions ?? []
        let sessionNumbers = Dictionary(sessions.enumerated().map { ($0.element.id, $0.offset + 1) }, uniquingKeysWith: { first, _ in first })
        return VStack(alignment: .leading, spacing: 22) {
            blockSummary(plan, entries: entries)
            CalendarLegend()
            if !sessions.isEmpty { CalendarSessionKey(sessions: sessions) }
            ForEach(months, id: \.self) { month in
                CalendarMonthGrid(plan: plan, month: month, entries: entries, sessionNumbers: sessionNumbers, now: now) { day in
                    selectedDay = .init(id: day.id)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Review on \(calendarDate(plan.reviewDate, plan: plan, template: "d MMMM yyyy"))")
                    .font(.headline)
                Text("Review your progress, recovery and exercise comfort after eight weeks. Keep exercises that are working; your program does not automatically change.")
                    .font(.subheadline).foregroundStyle(.secondary)
                NavigationLink("Review your program") { TrainingProgramView() }
                    .font(.subheadline.bold())
            }.padding(18).background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private func blockSummary(_ plan: TrainingCalendarPlan, entries: [TrainingCalendarDay]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(calendarRange(plan)).font(.title2.bold())
            Text("56 days · \(entries.filter(\.isTraining).count) planned sessions")
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

private struct CalendarDaySelection: Identifiable { let id: Int }

private struct CalendarSessionKey: View {
    let sessions: [ProgramSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Session key").font(.subheadline.bold())
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
            Text("M = morning · A = afternoon · N = night · O = off")
        }.font(.caption).foregroundStyle(.secondary)
    }
}

private struct CalendarMonthGrid: View {
    let plan: TrainingCalendarPlan
    let month: Date
    let entries: [TrainingCalendarDay]
    let sessionNumbers: [String: Int]
    let now: Date
    let onSelect: (TrainingCalendarDay) -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var monthEntries: [TrainingCalendarDay] {
        entries.filter { plan.calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
    }
    private var paddingDays: Int {
        guard let first = monthEntries.first else { return 0 }
        return (plan.calendar.component(.weekday, from: first.date) + 5) % 7
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(calendarDate(month, plan: plan, template: "MMMM yyyy")).font(.title3.bold())
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<7, id: \.self) { index in
                    Text(weekdayLabel(index)).font(.caption.weight(.medium))
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
                ForEach(0..<paddingDays, id: \.self) { _ in Color.clear.frame(height: 64) }
                ForEach(monthEntries) { day in
                    CalendarDayCell(day: day, plan: plan, sessionNumber: day.session.flatMap { sessionNumbers[$0.id] }, now: now) { onSelect(day) }
                }
            }
        }.padding(14).background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private func weekdayLabel(_ index: Int) -> String {
        let symbols = plan.calendar.veryShortStandaloneWeekdaySymbols
        return symbols[(index + 1) % 7]
    }
}

private struct CalendarDayCell: View {
    let day: TrainingCalendarDay
    let plan: TrainingCalendarPlan
    let sessionNumber: Int?
    let now: Date
    let action: () -> Void
    private var isToday: Bool { plan.calendar.isDate(day.date, inSameDayAs: now) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(calendarDate(day.date, plan: plan, template: "d")).font(.subheadline.bold())
                Text(calendarShiftCode(day.shift)).font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 2) {
                    Image(systemName: calendarDaySymbol(day))
                    if let sessionNumber { Text("\(sessionNumber)").fontWeight(.semibold) }
                }.font(.caption2)
                    .foregroundStyle(day.isTraining || !day.workouts.isEmpty ? GymaStyle.accent : Color.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(day.isTraining ? GymaStyle.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(isToday ? GymaStyle.accent : Color.clear, lineWidth: 2) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(calendarDayAccessibility(day, plan: plan, now: now))
        .accessibilityHint("Show session details and calendar options")
    }
}

private struct TrainingCalendarDayView: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    let dayOffset: Int
    @State private var movePresented = false
    @State private var startingProgram = false
    @State private var activePresented = false
    @State private var activeWorkoutID: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            List {
                if let plan = model.state.trainingCalendar,
                   let day = plan.entries(program: model.state.trainingProgram, history: model.state.workouts, now: context.date).first(where: { $0.id == dayOffset }) {
                    dayContent(day, plan: plan, now: context.date)
                } else {
                    Text("This day is no longer in your calendar.").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Your day")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(isPresented: $movePresented) { TrainingCalendarMoveView(sourceOffset: dayOffset) }
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
            if let session = day.session { sessionPreview(session) }
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
        if plan.calendar.isDate(day.date, inSameDayAs: now), day.workouts.isEmpty {
            Section {
                if model.state.trainingProgram != nil {
                    Button("Start next workout", systemImage: "play.fill") { startingProgram = true }
                        .disabled(model.storageBlocked || model.state.activeWorkout != nil)
                } else {
                    NavigationLink("Plan your program with coach") { TrainingProgramView() }
                }
            } footer: {
                Text("Program planning uses your goals and schedule. Today's sleep, energy and soreness are collected only when starting a workout.")
            }
        }
        Section {
            if calendarCanEdit(day, plan: plan, state: model.state, now: now) {
                Button(day.isTraining ? "Make this a recovery day" : "Plan training on this day", systemImage: day.isTraining ? "moon.zzz" : "dumbbell") {
                    model.update { try $0.setCalendarTrainingDay(on: day.date, isTraining: !day.isTraining, now: Date()) }
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
            Text("These are your saved program's base targets. Loads, repetitions and readiness are reviewed when you prepare the session.")
        }
    }
}

private struct TrainingCalendarMoveView: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    let sourceOffset: Int

    var body: some View {
        NavigationStack {
            List {
                if let plan = model.state.trainingCalendar, let source = plan.date(at: sourceOffset) {
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
                            if model.update({ try $0.moveCalendarTrainingDay(from: source, to: day.date, now: Date()) }) { dismiss() }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(calendarDate(day.date, plan: plan, template: "EEEE d MMMM"))
                                Text(calendarCycleLabel(day.cycleDay)).font(.caption).foregroundStyle(.secondary)
                            }
                        }.disabled(model.storageBlocked)
                    }
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
    @State private var error: String?
    private let timeZone: TimeZone

    init(existing: TrainingCalendarPlan?) {
        self.existing = existing
        let zone = existing.flatMap { TimeZone(identifier: $0.timeZoneIdentifier) } ?? TimeZone(identifier: "Europe/Amsterdam") ?? .current
        timeZone = zone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17)) ?? Date()
        _startDate = State(initialValue: existing?.startDate ?? max(anchor, calendar.startOfDay(for: Date())))
        _cycleAnchorDate = State(initialValue: existing?.cycleAnchorDate ?? anchor)
        _trainingDays = State(initialValue: Set(existing?.trainingCycleDays ?? [2, 5, 8, 9, 10]))
        _prefersUpperLower = State(initialValue: existing?.prefersUpperLower ?? true)
    }

    private var preview: TrainingCalendarPlan {
        var plan = TrainingCalendarPlan(startDate: startDate, cycleAnchorDate: cycleAnchorDate, trainingCycleDays: trainingDays.sorted(), timeZone: timeZone, prefersUpperLower: prefersUpperLower)
        if let existing, plan.startDate == existing.startDate {
            plan.dayOverrides = existing.dayOverrides
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
                } header: { Text("Your dates") } footer: {
                    Text("The first morning shift anchors the repeating 10-day cycle. Dates stay in \(timeZone.identifier).")
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
                } header: { Text("Training days · \(trainingDays.count) of 5 selected") } footer: {
                    Text("Choose exactly five days per cycle. Individual dates can be moved or changed to recovery after saving. Saved program sessions continue across cycles.")
                }
                Section {
                    Toggle("Prefer alternating upper/lower", isOn: $prefersUpperLower)
                } footer: {
                    Text("Your coach uses this preference when discussing your program. Saving this calendar keeps your current exercises and session order.")
                }
                if existing != nil {
                    Section {
                        Text("Individual date changes are kept when the block start stays the same. A new start date replaces the calendar schedule. Recorded workouts are kept. Past dates and dates with recorded training cannot be changed.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Button(existing == nil ? "Create calendar" : "Save calendar") { save() }
                        .disabled(trainingDays.count != 5 || model.storageBlocked || model.state.activeWorkout != nil)
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
        let plan = preview
        if model.update({ try $0.saveTrainingCalendar(plan, now: Date()) }) { dismiss() }
        else { error = model.errorMessage }
    }
}

private func calendarCanEdit(_ day: TrainingCalendarDay, plan: TrainingCalendarPlan, state: GymaState, now: Date = Date()) -> Bool {
    day.date >= plan.calendar.startOfDay(for: now) && day.workouts.isEmpty && state.activeWorkout == nil
}

private func calendarDate(_ date: Date, plan: TrainingCalendarPlan, template: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = .autoupdatingCurrent
    formatter.calendar = plan.calendar
    formatter.timeZone = plan.calendar.timeZone
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter.string(from: date)
}

private func calendarRange(_ plan: TrainingCalendarPlan) -> String {
    "\(calendarDate(plan.startDate, plan: plan, template: "d MMM")) – \(calendarDate(plan.lastDate, plan: plan, template: "d MMM yyyy"))"
}

private func calendarMonths(_ plan: TrainingCalendarPlan) -> [Date] {
    var months: [Date] = []
    for date in plan.dates {
        guard let start = plan.calendar.dateInterval(of: .month, for: date)?.start else { continue }
        if months.last != start { months.append(start) }
    }
    return months
}

private func calendarShiftCode(_ shift: Shift) -> String {
    switch shift { case .morning: return "M"; case .afternoon: return "A"; case .night: return "N"; case .off: return "O" }
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

private func calendarDayAccessibility(_ day: TrainingCalendarDay, plan: TrainingCalendarPlan, now: Date) -> String {
    let date = calendarDate(day.date, plan: plan, template: "EEEE d MMMM yyyy")
    let training = day.isTraining ? day.session?.title ?? "Training" : "Recovery"
    let status = day.workouts.contains(where: { $0.isActive }) ? ", workout in progress" : (!day.workouts.isEmpty ? ", completed workout" : "")
    let today = plan.calendar.isDate(day.date, inSameDayAs: now) ? "Today, " : ""
    return "\(today)\(date), \(calendarCycleLabel(day.cycleDay)), \(training)\(status)"
}

private func calendarTargetDescription(_ target: ExerciseTarget) -> String {
    let load = target.loadKg.map { "\($0.gymaNumber) kg" } ?? "Load to review"
    let effort = target.targetEffort.map { " · \($0.label)" } ?? ""
    return "\(target.sets) × \(target.repsMin)–\(target.repsMax) · \(load) · \(target.restSeconds)s rest\(effort)"
}
