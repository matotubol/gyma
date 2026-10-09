import SwiftUI
import Charts
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
                    Section("Check-in") {
                        LabeledContent("Shift", value: workout.shift.label)
                        LabeledContent("Energy", value: workout.energy.label)
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
                            }
                            if exercise.sets.isEmpty { Text("No sets logged").foregroundStyle(.secondary) }
                            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                                HStack {
                                    Text("\(index + 1)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 25)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("\(set.kg.gymaNumber) kg × \(set.reps) reps").fontWeight(.medium)
                                        if let effort = set.effort { Text(effort.label).font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    if set.isWarmup == true { Text("Warm-up").font(.caption).foregroundStyle(.secondary) }
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

struct ProgressViewScreen: View {
    @EnvironmentObject private var model: GymaAppModel

    private var recent: [Workout] {
        let from = Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        return model.completedWorkouts.filter { $0.start >= from }
    }

    private var trainedExercises: [ExerciseDefinition] {
        let ids = Set(model.completedWorkouts.flatMap { $0.exercises.filter { !$0.sets.isEmpty }.map(\.exerciseID) })
        return model.state.catalog.filter { ids.contains($0.id) }.sorted { $0.name < $1.name }
    }

    private var volumeDays: [VolumeDay] {
        let grouped = Dictionary(grouping: recent) { Calendar.current.startOfDay(for: $0.start) }
        return grouped.map { VolumeDay(day: $0.key, volume: $0.value.reduce(0) { $0 + $1.liftedVolume }) }.sorted { $0.day < $1.day }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeading(title: "The work adds up", subtitle: "Your last 30 days of completed sessions.")
                HStack(spacing: 12) {
                    StatTile(value: "\(recent.count)", label: "workouts", symbol: "figure.strengthtraining.traditional")
                    StatTile(value: "\(recent.reduce(0) { $0 + $1.loggedSets })", label: "sets logged", symbol: "checkmark.circle")
                }
                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Volume over time").font(.headline)
                        Text("\(recent.reduce(0) { $0 + $1.liftedVolume }.gymaNumber) kg lifted").font(.title2.bold())
                        Chart(volumeDays) { day in
                            BarMark(x: .value("Day", day.day, unit: .day), y: .value("Volume (kg)", day.volume))
                                .foregroundStyle(GymaStyle.accent.gradient).cornerRadius(4)
                        }
                        .frame(height: 180)
                        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                        .accessibilityLabel("Daily training volume in kilograms")
                        Text("Volume is load × reps, including warm-up sets.").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(20).background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 22))
                }
                SectionHeading(title: "By exercise", subtitle: "Watch the lifts you come back to.")
                if trainedExercises.isEmpty {
                    EmptyState(title: "Give it a session", message: "Finish a workout to start seeing your progress here.", symbol: "chart.xyaxis.line")
                } else {
                    VStack(spacing: 0) {
                        ForEach(trainedExercises) { exercise in
                            NavigationLink { ExerciseProgressView(exercise: exercise) } label: {
                                HStack {
                                    Circle().fill(exercise.muscle.tint).frame(width: 9, height: 9)
                                    Text(exercise.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }.padding(18)
                            }
                            if exercise.id != trainedExercises.last?.id { Divider().padding(.leading, 35) }
                        }
                    }
                    .background(GymaStyle.card, in: RoundedRectangle(cornerRadius: 22))
                }
            }.padding(20)
        }
        .background(GymaStyle.background)
        .navigationTitle("Progress")
    }
}

private struct VolumeDay: Identifiable {
    let day: Date
    let volume: Double
    var id: Date { day }
}

private struct ExerciseProgressView: View {
    @EnvironmentObject private var model: GymaAppModel
    let exercise: ExerciseDefinition

    private var sessions: [ExerciseSession] {
        model.completedWorkouts.compactMap { workout in
            guard let entry = workout.exercises.first(where: { $0.exerciseID == exercise.id }) else { return nil }
            let sets = entry.sets.filter { $0.isWarmup != true }
            guard !sets.isEmpty else { return nil }
            return ExerciseSession(workout: workout, sets: sets)
        }.sorted { $0.workout.start < $1.workout.start }
    }

    var body: some View {
        List {
            if sessions.isEmpty {
                EmptyState(title: "No working sets yet", message: "Log a working set in a completed workout to see this lift’s progress.", symbol: "dumbbell")
            } else {
                Section {
                    HStack(spacing: 12) {
                        StatTile(value: (sessions.flatMap(\.sets).map(\.kg).max() ?? 0).gymaNumber, label: "best load · kg")
                        StatTile(value: (sessions.map(\.estimate).max() ?? 0).gymaNumber, label: "estimated 1RM · kg")
                    }.listRowInsets(EdgeInsets())
                    Chart(sessions) { session in
                        LineMark(x: .value("Workout", session.workout.start), y: .value("Estimated 1RM", session.estimate))
                            .foregroundStyle(GymaStyle.accent)
                        PointMark(x: .value("Workout", session.workout.start), y: .value("Estimated 1RM", session.estimate))
                            .foregroundStyle(GymaStyle.accent)
                    }.frame(height: 190).padding(.vertical, 10)
                    Text("Epley estimate: load × (1 + reps ÷ 30). Warm-ups are excluded. This is a trend, not a tested maximum.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Sessions") {
                    ForEach(sessions.reversed()) { session in
                        NavigationLink { WorkoutDetailView(workoutID: session.workout.id) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(session.workout.start, format: .dateTime.day().month(.wide).year()).font(.headline)
                                Text(session.sets.map { "\($0.kg.gymaNumber) × \($0.reps)" }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(exercise.name).navigationBarTitleDisplayMode(.inline)
    }
}

private struct ExerciseSession: Identifiable {
    let workout: Workout
    let sets: [WorkSet]
    var id: String { workout.id }
    var estimate: Double { sets.map { $0.reps <= 1 ? $0.kg : $0.kg * (1 + Double($0.reps) / 30) }.max() ?? 0 }
}
