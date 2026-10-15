import GymaCore
import SwiftUI

@MainActor
struct WatchSetScreen: View {
    let draft: WatchSetDraft
    let exercise: WorkoutExercise?
    let exerciseName: String
    let compact: Bool
    let availableHeight: CGFloat
    let isEnabled: Bool
    @Binding var actualReps: Int
    @Binding var actualKg: Double
    let chooseSetType: () -> Void
    let editValue: (WatchValueField) -> Void
    let startSet: () -> Void
    let finishSet: () -> Void
    let confirmReps: () -> Void
    let confirmWeight: (Double) -> Void
    let confirmEffort: (SetEffort?) -> Void

    @ViewBuilder
    var body: some View {
        let setTitle = draft.isWarmupSet ? "WARM-UP" :
            (exercise?.target.map { "SET \((exercise?.resolvedSetCount ?? draft.workingSetCount) + 1) OF \($0.sets)" } ?? "SET \(draft.workingSetCount + 1)")
        if draft.phase == .prepared {
            Button(action: chooseSetType) {
                HStack(spacing: 4) {
                    WatchWorkoutEyebrow(setTitle)
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.mint)
                }
            }
            .buttonStyle(.plain).disabled(!isEnabled)
            .accessibilityLabel(draft.isWarmupSet ? "Warm-up, change set type" : "Working set, change set type")
        } else if draft.phase != .review || draft.currentReviewStep == .weight { WatchWorkoutEyebrow(setTitle) }
        Text(exerciseName)
            .font(.system(size: draft.phase == .review ? 16 : (compact ? 19 : 22), weight: .bold, design: .rounded))
            .lineLimit(draft.phase == .review || compact ? 1 : 2).minimumScaleFactor(0.8)
            .multilineTextAlignment(.center)
        if (draft.phase == .prepared || draft.phase == .performing), !draft.isWarmupSet,
           let effort = exercise?.target?.targetEffort {
            Text("Aim: \(effort.label)").font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        switch draft.phase {
        case .prepared:
            preparationValues(draft)
            WatchWorkoutButton("Start Set", symbol: "play.fill", action: startSet)
                .disabled(!isEnabled)
        case .performing:
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(draft.kg.formatted()).font(.system(size: compact ? 29 : 35, weight: .bold, design: .rounded))
                Text("kg").foregroundStyle(.secondary)
                Text("× \(draft.expectedReps)").font(.title2.bold()).foregroundStyle(.mint)
            }
            WatchWorkoutButton("Finish Set", symbol: "checkmark", action: finishSet)
                .disabled(!isEnabled)
        case .review:
            if draft.currentReviewStep == .reps {
                WatchRepsControl(title: "REPS · \(setTitle)",
                                 height: max(50, min(72, availableHeight - 86)), reps: $actualReps)
                    .disabled(!isEnabled)
                WatchWorkoutButton("Confirm Reps", symbol: "arrow.right", action: confirmReps)
                    .disabled(!isEnabled)
            } else if draft.currentReviewStep == .weight {
                WatchWeightReview(height: max(44, min(94, availableHeight - 108)), kg: $actualKg,
                                  isEnabled: isEnabled, confirm: confirmWeight)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(SetEffort.allCases) { effort in
                            effortButton(effort.label, effort: effort)
                        }
                        effortButton("Not sure", effort: nil)
                    }
                }
                .frame(maxHeight: max(100, availableHeight - 30))
            }
        case .submitting:
            Text("\(draft.actualKg.formatted()) kg × \(draft.actualReps)")
                .font(.title2.bold()).foregroundStyle(.mint)
            ProgressView("Saving set…").font(.caption)
        }
    }

    private func preparationValues(_ draft: WatchSetDraft) -> some View {
        HStack(spacing: 8) {
            valueButton(draft.kg.formatted(), unit: "KG", field: .preparedKg)
            valueButton("\(draft.expectedReps)", unit: "REPS", field: .expectedReps)
        }
        .disabled(!isEnabled)
    }

    private func valueButton(_ value: String, unit: String, field: WatchValueField) -> some View {
        Button { editValue(field) } label: {
            VStack(spacing: 2) {
                Text(value).font(.system(size: 27, weight: .bold, design: .rounded)).minimumScaleFactor(0.6)
                HStack(spacing: 3) {
                    Text(unit).font(.system(size: 10, weight: .semibold))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
                }
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 5)
            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain).accessibilityLabel("Change \(unit): \(value)")
    }

    private func effortButton(_ title: String, effort: SetEffort?) -> some View {
        Button { confirmEffort(effort) } label: {
            Text(title).font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).disabled(!isEnabled)
        .accessibilityHint("Save this working set")
    }
}
