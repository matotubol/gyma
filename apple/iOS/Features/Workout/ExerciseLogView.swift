import SwiftUI
import GymaCore

struct ExerciseLogView: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    let workoutID: String
    let exerciseID: String
    @State private var logPresented = false
    @State private var targetPresented = false
    @State private var removePresented = false
    @State private var replacementPresented = false
    @State private var skipPresented = false
    @State private var stopPresented = false

    private var exercise: WorkoutExercise? { model.workout(workoutID)?.exercises.first { $0.exerciseID == exerciseID } }

    var body: some View {
        List {
            if let exercise {
                Section {
                    if !exercise.isTargetResolved {
                        Button("Do this exercise next", systemImage: "play.fill") {
                            model.update { try $0.selectExercise(exerciseID, workoutID: workoutID) }
                        }
                        Button("Replace for today", systemImage: "arrow.triangle.2.circlepath") { replacementPresented = true }
                        if exercise.target != nil {
                            Button("Skip a planned set", systemImage: "forward.end") { skipPresented = true }
                        }
                        Button("Stop this exercise", systemImage: "stop.circle") { stopPresented = true }
                    }
                    if exercise.skippedSetCount > 0 {
                        Label("\(exercise.skippedSetCount) planned sets skipped", systemImage: "forward.end")
                            .foregroundStyle(.secondary)
                    }
                    if exercise.skippedRemainingAt != nil {
                        Text("Stopped for today. Your completed sets stay saved.").foregroundStyle(.secondary)
                    }
                } header: { Text("Change today") } footer: {
                    Text("These changes apply only to this workout. Skipped sets add no reps or lifted volume.")
                }
                Section("Your target") {
                    if let target = exercise.target {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(target.sets) sets × \(target.repsMin)–\(target.repsMax) reps").font(.title3.bold())
                                Text("\(target.loadKg.map { "\($0.gymaNumber) kg · " } ?? "")\(target.restSeconds)s rest").foregroundStyle(.secondary)
                                if !target.reason.isEmpty { Text(target.reason).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Button("Edit") { targetPresented = true }
                        }
                    } else {
                        Button("Set a target", systemImage: "scope") { targetPresented = true }
                        Text("A target is a plan. Only logged sets count toward your workout.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let timer = model.state.restTimer, timer.exerciseID == exerciseID, timer.workoutID == workoutID {
                    Section { RestTimerCard(timer: timer).listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
                }
                Section {
                    if exercise.sets.isEmpty { Text("No sets yet. Start with a load that feels right today.").foregroundStyle(.secondary).padding(.vertical, 8) }
                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                        HStack(spacing: 14) {
                            Text("\(index + 1)").font(.headline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 25)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(set.kg.gymaNumber) kg × \(set.reps)").font(.headline)
                                Text([set.isWarmup == true ? "Warm-up" : (set.isWarmup == false ? "Working set" : "Unclassified"), set.effort?.label].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(GymaStyle.accent)
                        }
                        .padding(.vertical, 5)
                        .swipeActions {
                            Button("Delete", role: .destructive) { model.update { try $0.removeSet(set.id, exerciseID: exerciseID, workoutID: workoutID) } }
                        }
                    }
                    Button { logPresented = true } label: {
                        Label("Log set", systemImage: "plus.circle.fill").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 5)
                    }.buttonStyle(.borderedProminent)
                        .disabled(model.state.restTimer != nil || exercise.skippedRemainingAt != nil)
                } header: { Text("Logged sets · \(exercise.sets.count)") }
                Section {
                    Toggle("Automatic rest timer", isOn: Binding(get: { model.state.restEnabled }, set: { value in model.update { $0.setRestEnabled(value) } }))
                } footer: {
                    Text("Rest starts after a working set. Warm-ups and the final target set do not start a timer. A pain note also pauses automatic rest guidance.")
                }
            }
        }
        .navigationTitle(model.name(for: exerciseID)).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if exercise?.sets.isEmpty == true && exercise?.skippedSetCount == 0 {
                        Button("Remove exercise", systemImage: "trash", role: .destructive) { removePresented = true }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $logPresented) { LogSetView(workoutID: workoutID, exerciseID: exerciseID, exercise: exercise) }
        .sheet(isPresented: $targetPresented) { TargetEditorView(workoutID: workoutID, exerciseID: exerciseID, target: exercise?.target) }
        .sheet(isPresented: $replacementPresented) { ExercisePickerView(workoutID: workoutID, replacingExerciseID: exerciseID) }
        .confirmationDialog("Skip one planned set?", isPresented: $skipPresented, titleVisibility: .visible) {
            Button("Skip set") { model.update { try $0.skipSet(exerciseID: exerciseID, workoutID: workoutID) } }
        } message: { Text("This set will be marked skipped, without adding reps or volume. Your completed sets stay saved.") }
        .confirmationDialog("Stop this exercise for today?", isPresented: $stopPresented, titleVisibility: .visible) {
            Button("Skip remaining sets") { model.update { try $0.skipExercise(exerciseID: exerciseID, workoutID: workoutID) } }
        } message: { Text("All remaining planned sets will be marked skipped. Your completed sets stay saved, and you can choose another exercise.") }
        .confirmationDialog("Remove this exercise and its sets?", isPresented: $removePresented, titleVisibility: .visible) {
            Button("Remove exercise", role: .destructive) {
                if model.update({ try $0.removeExercise(exerciseID, workoutID: workoutID) }) { dismiss() }
            }
        }
        .onChange(of: model.workout(workoutID)?.end) { _, end in if end != nil { dismiss() } }
        .onChange(of: exercise == nil) { _, missing in if missing { dismiss() } }
    }
}
