import Foundation
import SwiftUI
import GymaCore

struct TrainingCalendarHistoryView: View {
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
