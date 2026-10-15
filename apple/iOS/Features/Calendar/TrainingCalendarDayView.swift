import Foundation
import SwiftUI
import GymaCore

struct CalendarDaySelection: Identifiable {
    let date: Date
    let blockStartDate: Date
    let timeZoneIdentifier: String
    var id: Date { date }

    func matches(_ plan: TrainingCalendarPlan) -> Bool {
        plan.startDate == blockStartDate && plan.timeZoneIdentifier == timeZoneIdentifier && plan.dayOffset(for: date) != nil
    }
}

struct TrainingCalendarDayView: View {
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
                            Text("\(workout.totalSets) sets · \(workout.volume.gymaNumber) kg · \(workout.minutes()) min")
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

private func calendarTargetDescription(_ target: ExerciseTarget) -> String {
    let load = target.loadKg.map { "\($0.gymaNumber) kg" } ?? "Load to review"
    let effort = target.targetEffort.map { " · \($0.label)" } ?? ""
    return "\(target.sets) × \(target.repsMin)–\(target.repsMax) · \(load) · \(target.restSeconds)s rest\(effort)"
}
