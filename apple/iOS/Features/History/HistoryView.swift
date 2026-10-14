import SwiftUI
import GymaCore

struct HistoryView: View {
    @EnvironmentObject private var model: GymaAppModel
    @State private var search = ""

    private var workouts: [Workout] {
        model.sortedWorkouts.filter { workout in
            search.isEmpty || workout.title.localizedCaseInsensitiveContains(search) ||
            workout.exercises.contains { model.name(for: $0.exerciseID).localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        List {
            if search.isEmpty {
                Section {
                    Text("Your completed workouts stay here across calendar blocks. Open a session to review its sets, weights and coach discussion.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    NavigationLink {
                        ProgressViewScreen()
                    } label: {
                        Label("Compare exercise progress", systemImage: "chart.xyaxis.line")
                    }
                }
            }
            if workouts.isEmpty {
                EmptyState(title: search.isEmpty ? "Your story starts here" : "No matching workouts",
                           message: search.isEmpty ? "Completed sessions and your current workout will appear here." : "Try an exercise or workout name.", symbol: "clock.arrow.circlepath")
                    .listRowBackground(Color.clear)
            }
            ForEach(workouts) { workout in
                NavigationLink {
                    if workout.end == nil { ActiveWorkoutView(workoutID: workout.id) }
                    else { WorkoutDetailView(workoutID: workout.id) }
                } label: { WorkoutSummaryRow(workout: workout) }
            }
        }
        .searchable(text: $search, prompt: "Workout or exercise")
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { DeletedWorkoutsView() } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Deleted workouts")
            }
        }
    }
}

struct WorkoutDetailView: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    let workoutID: String
    @State private var deletePresented = false

    var body: some View {
        Group {
            if let workout = model.workout(workoutID) {
                List {
                    Section {
                        Text(workout.start, format: .dateTime.weekday(.wide).day().month(.wide).year()).font(.headline)
                        HStack(spacing: 12) {
                            StatTile(value: "\(workout.loggedSets)", label: "sets")
                            StatTile(value: workout.liftedVolume.gymaNumber, label: "kg lifted")
                            StatTile(value: "\(workout.minutes())", label: "minutes")
                        }.listRowInsets(EdgeInsets())
                    }
                    if !workout.isActive { WorkoutReviewSummarySection(workout: workout) }
                    Section("Before workout") {
                        if let readiness = workout.readiness { WorkoutReadinessSummary(readiness: readiness) }
                        else { Text("Pre-workout soreness was not recorded for this session.").foregroundStyle(.secondary) }
                    }
                    if workout.coachConversation?.messages.isEmpty == false {
                        Section {
                            NavigationLink("Workout coach conversation") { WorkoutCoachView(workoutID: workoutID) }
                        }
                    }
                    Section("Planning check-in") {
                        LabeledContent("Shift", value: workout.checkIn?.shift.label ?? workout.shift.label)
                        LabeledContent("Energy", value: workout.checkIn?.energy.label ?? workout.energy.label)
                        if let checkIn = workout.checkIn {
                            LabeledContent("Time available", value: "\(checkIn.timeMinutes) min")
                            if let hours = checkIn.sleepHours { LabeledContent("Sleep", value: "\(hours.gymaNumber) hours") }
                            if !checkIn.notes.isEmpty { Text(checkIn.notes) }
                            if !checkIn.recentTrainingNote.isEmpty { LabeledContent("Recent training", value: checkIn.recentTrainingNote) }
                            if !checkIn.painNote.isEmpty { LabeledContent("Pain / limitations", value: checkIn.painNote) }
                        }
                    }
                    ForEach(workout.exercises) { exercise in
                        Section(model.name(for: exercise.exerciseID)) {
                            if let target = exercise.target {
                                Text("Planned: \(target.sets) × \(target.repsMin)–\(target.repsMax) reps · \(target.restSeconds)s rest")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let effort = target.targetEffort {
                                    Text("Effort target: \(effort.label)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if exercise.sets.isEmpty { Text("No sets logged").foregroundStyle(.secondary) }
                            if exercise.skippedSetCount > 0 {
                                Label("\(exercise.skippedSetCount) planned sets skipped · no reps or volume", systemImage: "forward.end")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else if exercise.skippedRemainingAt != nil {
                                Text("Stopped for this session").font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                                HStack {
                                    Text("\(index + 1)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 25)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(set.kg.gymaNumber) kg × \(set.reps) reps").fontWeight(.medium)
                                        if let effort = set.effort { Text(effort.label).font(.caption).foregroundStyle(.secondary) }
                                        else if set.isWarmup == false { Text("Effort not recorded").font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    if set.isWarmup == true { Text("Warm-up").font(.caption).foregroundStyle(.secondary) }
                                    else if set.isWarmup == nil { Text("Unclassified").font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                            ForEach((workout.restHistory ?? []).filter { $0.exerciseID == exercise.exerciseID }) { rest in
                                LabeledContent("Rest after set \((exercise.sets.firstIndex { $0.id == rest.sourceSetID } ?? 0) + 1)",
                                               value: "\(Int(rest.elapsedSeconds))s / \(rest.plannedSeconds)s planned")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section {
                        Button("Delete workout", systemImage: "trash", role: .destructive) { deletePresented = true }
                    } footer: { Text("Deleted workouts can be restored from History.") }
                }
                .navigationTitle(workout.title)
            } else {
                ContentUnavailableView("Workout unavailable", systemImage: "tray", description: Text("It may have been deleted or replaced by a backup."))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this workout?", isPresented: $deletePresented, titleVisibility: .visible) {
            Button("Move to deleted workouts", role: .destructive) {
                if model.update({ try $0.deleteWorkout(workoutID) }) { dismiss() }
            }
        } message: { Text("You can restore it later.") }
    }
}

private struct DeletedWorkoutsView: View {
    @EnvironmentObject private var model: GymaAppModel

    var body: some View {
        List {
            if model.state.deletedWorkouts.isEmpty {
                EmptyState(title: "Nothing deleted", message: "Workouts you delete will stay here until you restore them.", symbol: "trash")
                    .listRowBackground(Color.clear)
            }
            ForEach(model.state.deletedWorkouts.sorted { $0.start > $1.start }) { workout in
                VStack(alignment: .leading, spacing: 8) {
                    WorkoutSummaryRow(workout: workout)
                    Button("Restore workout", systemImage: "arrow.uturn.backward") { model.update { try $0.restoreWorkout(workout.id) } }
                        .buttonStyle(.bordered)
                }.padding(.vertical, 5)
            }
        }
        .navigationTitle("Deleted workouts").navigationBarTitleDisplayMode(.inline)
    }
}
