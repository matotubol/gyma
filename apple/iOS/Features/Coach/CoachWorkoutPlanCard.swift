import SwiftUI
import GymaCore

struct CoachWorkoutPlanCard: View {
    @EnvironmentObject private var model: GymaAppModel
    let plan: WorkoutPlan
    var onAccepted: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Label(plan.acceptedAt == nil ? "WORKOUT DRAFT" : "ACCEPTED WORKOUT", systemImage: plan.acceptedAt == nil ? "list.clipboard" : "checkmark.seal")
                    .font(.caption.weight(.bold)).foregroundStyle(GymaStyle.accent)
                Text(plan.title).font(.title2.bold())
                Text("\(plan.exercises.count) exercises · \(plan.exercises.reduce(0) { $0 + ($1.target?.sets ?? 0) }) sets")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(Array(plan.exercises.enumerated()), id: \.element.id) { index, exercise in
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    Text("\(index + 1). \(model.name(for: exercise.exerciseID))").font(.headline)
                    if let target = exercise.target {
                        Text("\(target.sets) sets × \(repDescription(target)) reps")
                            .font(.subheadline.weight(.medium))
                        HStack(alignment: .top) {
                            Label(target.loadKg.map { "\($0.gymaNumber) kg" } ?? "Choose a comfortable load", systemImage: "dumbbell")
                            Spacer(minLength: 8)
                            Label("\(target.restSeconds)s rest", systemImage: "timer")
                        }
                        .font(.subheadline).foregroundStyle(.secondary)
                        if !target.reason.isEmpty {
                            Text(target.reason).font(.caption).foregroundStyle(.secondary)
                        }
                        if let effort = target.targetEffort {
                            Text("Effort target: \(effort.label)").font(.caption).foregroundStyle(GymaStyle.accent)
                        }
                    }
                }
            }
            Divider()
            Text("Your Watch will guide the accepted sets, reps and rest times. You can adjust the reps and kilograms you actually complete.")
                .font(.caption).foregroundStyle(.secondary)
            Button {
                if model.acceptCoachPlan(plan.id) { onAccepted() }
            } label: {
                Label("Accept workout plan", systemImage: "checkmark")
                    .font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).disabled(!model.canAcceptCoachPlan)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private func repDescription(_ target: ExerciseTarget) -> String {
        target.repsMin == target.repsMax ? "\(target.repsMin)" : "\(target.repsMin)–\(target.repsMax)"
    }
}
