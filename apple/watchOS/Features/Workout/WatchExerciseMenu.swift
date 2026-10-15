import GymaCore
import SwiftUI

@MainActor
struct WatchExerciseMenu: View {
    let workout: Workout
    let draft: WatchSetDraft?
    let pendingCommand: WatchCommand?
    let restTimer: RestTimer?
    let showsRest: Bool
    let hasHiddenExercises: Bool
    let canCancelSet: Bool
    let canFinishWorkout: Bool
    let exerciseName: (String) -> String
    let canChooseExercise: (WorkoutExercise) -> Bool
    let selectExercise: (WorkoutExercise) -> Void
    let resumeSet: () -> Void
    let cancelSet: () -> Void
    let finishWorkout: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let pending = pendingCommand {
                    Label(pending.action.watchDescription, systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption).foregroundStyle(.mint)
                } else if let draft, draft.phase == .performing || draft.phase == .review {
                    Text("Resume or cancel your unsaved set before choosing another exercise.")
                        .font(.caption2).foregroundStyle(.secondary)
                    Button(draft.phase == .review ? "Review current set" : "Resume current set") {
                        resumeSet()
                    }
                    .buttonStyle(WatchPrimaryButtonStyle())
                    Button("Cancel set", role: .destructive) { cancelSet() }
                        .font(.caption).disabled(!canCancelSet)
                } else if workout.nextExercise != nil {
                    Text("Choose any exercise; return to the others later.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("All planned sets are done or skipped.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let timer = restTimer, timer.workoutID == workout.id, showsRest {
                    Button { resumeSet() } label: {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let remaining = timer.remaining(at: context.date)
                            Label(remaining > 0 ? "Rest \(WatchRestPresentation.duration(ceil(remaining)))" : "Rest complete",
                                  systemImage: "timer")
                                .font(.caption).foregroundStyle(.mint)
                        }
                    }
                    .buttonStyle(.plain)
                    Text("Choosing another exercise ends this rest.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(workout.exercises) { exercise in
                    Button { selectExercise(exercise) } label: {
                        HStack(spacing: 7) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(exerciseName(exercise.exerciseID)).font(.headline)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(exerciseProgress(exercise)).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: exercise.isTargetResolved ?
                                  (exercise.skippedSetCount > 0 || exercise.skippedRemainingAt != nil ? "minus.circle" : "checkmark.circle.fill") : "chevron.right")
                                .foregroundStyle(exercise.isTargetResolved ? Color.secondary : Color.mint)
                        }
                        .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canChooseExercise(exercise))
                    .accessibilityHint(exercise.isTargetResolved ? "No planned sets remaining" : "Choose this exercise")
                }
                if hasHiddenExercises {
                    Text("More exercises are available on iPhone.")
                        .font(.caption2).foregroundStyle(.orange)
                }
                Button(workout.nextExercise == nil && !hasHiddenExercises ? "Finish workout" : "Finish workout early") {
                    finishWorkout()
                }
                .font(.caption).frame(maxWidth: .infinity).disabled(!canFinishWorkout)
            }
            .padding(.vertical, 3)
        }
    }

    private func exerciseProgress(_ exercise: WorkoutExercise) -> String {
        let completed = exercise.target.map { "\(exercise.workingSetCount)/\($0.sets) done" }
            ?? "\(exercise.workingSetCount) sets done"
        if exercise.skippedSetCount > 0 { return completed + " · \(exercise.skippedSetCount) skipped" }
        return completed + (exercise.skippedRemainingAt != nil ? " · stopped" : "")
    }
}
