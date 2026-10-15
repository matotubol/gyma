import SwiftUI
import GymaCore

struct ActiveWorkoutView: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    let workoutID: String
    @State private var pickerPresented = false
    @State private var finishPresented = false
    @State private var coachPresented = false
    @State private var replacement: WorkoutExercise?

    var body: some View {
        Group {
            if let workout = model.workout(workoutID), workout.end == nil {
                List {
                    Section {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            HStack(spacing: 20) {
                                summary("\(workout.minutes(at: context.date))", "minutes")
                                summary("\(workout.totalSets)", "sets")
                                summary(workout.volume.gymaNumber, "kg lifted")
                            }
                            .padding(.vertical, 8)
                        }
                        HStack {
                            Label(workout.energy.label, systemImage: workout.energy.symbol)
                            Spacer()
                            Text(workout.shift.label)
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Section {
                        Button { coachPresented = true } label: {
                            Label("Ask coach", systemImage: "bubble.left.and.bubble.right.fill").font(.headline)
                        }
                    } footer: { Text("Swap exercises, change targets or skip planned work for today. Your recurring program stays unchanged.") }
                    if let timer = model.state.restTimer, timer.workoutID == workoutID {
                        Section { RestTimerCard(timer: timer).listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
                    }
                    if let readiness = workout.readiness {
                        Section {
                            DisclosureGroup("Before this workout") { WorkoutReadinessSummary(readiness: readiness) }
                        }
                    }
                    Section {
                        if workout.exercises.isEmpty {
                            EmptyState(title: "Choose your first exercise", message: "Build this session as you go. Every set is saved on your iPhone and shared with your Watch.", symbol: "dumbbell")
                        }
                        ForEach(workout.exercises) { exercise in
                            NavigationLink {
                                ExerciseLogView(workoutID: workoutID, exerciseID: exercise.exerciseID)
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack {
                                        Text(model.name(for: exercise.exerciseID)).font(.headline)
                                        Spacer()
                                        Text("\(exercise.sets.count)").font(.headline.monospacedDigit()).foregroundStyle(GymaStyle.accent)
                                    }
                                    if workout.nextExercise?.exerciseID == exercise.exerciseID {
                                        Label("Up next", systemImage: "play.fill").font(.caption).foregroundStyle(GymaStyle.accent)
                                    }
                                    if exercise.skippedSetCount > 0 {
                                        Text("\(exercise.skippedSetCount) planned sets skipped").font(.caption).foregroundStyle(.secondary)
                                    } else if exercise.skippedRemainingAt != nil {
                                        Text("Stopped for today").font(.caption).foregroundStyle(.secondary)
                                    }
                                    if let target = exercise.target {
                                        Text("Target: \(target.sets) × \(target.repsMin)–\(target.repsMax) reps\(target.loadKg.map { " · \($0.gymaNumber) kg" } ?? "")")
                                            .font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        Text(exercise.sets.isEmpty ? "Ready for your first set" : setSummary(exercise.sets))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 7)
                            }
                            .contextMenu {
                                if !exercise.isTargetResolved {
                                    Button("Do this exercise next", systemImage: "play.fill") {
                                        model.update { try $0.selectExercise(exercise.exerciseID, workoutID: workoutID) }
                                    }
                                    Button("Replace for today", systemImage: "arrow.triangle.2.circlepath") { replacement = exercise }
                                }
                            }
                        }
                        .onMove { offsets, destination in
                            var ids = workout.exercises.map(\.exerciseID)
                            ids.move(fromOffsets: offsets, toOffset: destination)
                            model.update { try $0.reorderExercises(ids, workoutID: workoutID) }
                        }
                        Button { pickerPresented = true } label: {
                            Label("Add exercise", systemImage: "plus.circle.fill").font(.headline).padding(.vertical, 7)
                        }
                    } header: { Text("Exercises") } footer: {
                        Text("Open any exercise to train it, replace it or skip a set. Tap Edit to reorder today's exercises.")
                    }
                    Section {
                        Button { finishPresented = true } label: {
                            Label("Finish workout", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity).font(.headline)
                        }
                        .buttonStyle(.borderedProminent).padding(.vertical, 4)
                    }
                }
                .navigationTitle(workout.title)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
            } else {
                ContentUnavailableView("Session complete", systemImage: "checkmark.circle", description: Text("Your workout is saved in History."))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $pickerPresented) { ExercisePickerView(workoutID: workoutID) }
        .sheet(item: $replacement) { ExercisePickerView(workoutID: workoutID, replacingExerciseID: $0.exerciseID) }
        .sheet(isPresented: $coachPresented) {
            NavigationStack {
                WorkoutCoachView(workoutID: workoutID)
            }
        }
        .confirmationDialog("Finish this workout?", isPresented: $finishPresented, titleVisibility: .visible) {
            Button("Finish and save") {
                model.update { try $0.finishWorkout(workoutID) }
            }
        } message: { Text("Your logged sets will be kept in History and the rest timer will stop.") }
        .onChange(of: model.workout(workoutID)?.end) { _, end in if end != nil { dismiss() } }
    }

    private func summary(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setSummary(_ sets: [WorkSet]) -> String {
        sets.suffix(3).map { "\($0.kg.gymaNumber) kg × \($0.reps)" }.joined(separator: " · ")
    }
}
