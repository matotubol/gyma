import SwiftUI
import GymaCore

struct ActiveWorkoutView: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    let workoutID: String
    @State private var pickerPresented = false
    @State private var finishPresented = false

    var body: some View {
        Group {
            if let workout = model.workout(workoutID), workout.end == nil {
                List {
                    Section {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            HStack(spacing: 20) {
                                summary("\(workout.minutes(at: context.date))", "minutes")
                                summary("\(workout.loggedSets)", "sets")
                                summary(workout.liftedVolume.gymaNumber, "kg lifted")
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
                    if let timer = model.state.restTimer, timer.workoutID == workoutID {
                        Section { RestTimerCard(timer: timer).listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
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
                        }
                        Button { pickerPresented = true } label: {
                            Label("Add exercise", systemImage: "plus.circle.fill").font(.headline).padding(.vertical, 7)
                        }
                    } header: { Text("Exercises") }
                    Section {
                        Button { finishPresented = true } label: {
                            Label("Finish workout", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity).font(.headline)
                        }
                        .buttonStyle(.borderedProminent).padding(.vertical, 4)
                    }
                }
                .navigationTitle(workout.title)
            } else {
                ContentUnavailableView("Session complete", systemImage: "checkmark.circle", description: Text("Your workout is saved in History."))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $pickerPresented) { ExercisePickerView(workoutID: workoutID) }
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

struct RestTimerCard: View {
    @EnvironmentObject private var model: GymaAppModel
    let timer: RestTimer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = max(0, Int(ceil(timer.remaining(at: context.date))))
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(seconds > 0 ? "Take a breath" : "Ready when you are", systemImage: "timer")
                            .font(.headline)
                        Text(model.name(for: timer.exerciseID)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(seconds / 60):\(String(format: "%02d", seconds % 60))")
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit()
                        .contentTransition(.numericText())
                        .accessibilityLabel("\(seconds) seconds remaining")
                }
                HStack {
                    Button { model.update { try $0.extendRest(timerID: timer.id) } } label: {
                        Label("30 seconds", systemImage: "plus")
                    }.buttonStyle(.bordered)
                    Spacer()
                    Button(seconds > 0 ? "Skip rest" : "Dismiss") { model.update { try $0.skipRest(timerID: timer.id) } }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(18)
            .background(GymaStyle.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
        }
    }
}

struct ExercisePickerView: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    let workoutID: String
    @State private var search = ""
    @State private var muscle: Muscle?
    @State private var customPresented = false
    @State private var error: String?

    private var available: [ExerciseDefinition] {
        let existing = Set(model.workout(workoutID)?.exercises.map(\.exerciseID) ?? [])
        return model.state.catalog.filter {
            !existing.contains($0.id) && (muscle == nil || $0.muscle == muscle) &&
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Muscle group", selection: $muscle) {
                        Text("All muscles").tag(Muscle?.none)
                        ForEach(Muscle.allCases) { Text($0.label).tag(Optional($0)) }
                    }
                }
                Section {
                    ForEach(available) { exercise in
                        Button {
                            if model.update({ try $0.addExercise(exercise.id, to: workoutID) }) { dismiss() }
                            else { error = model.errorMessage }
                        } label: {
                            HStack(spacing: 13) {
                                Image(systemName: "dumbbell.fill").foregroundStyle(exercise.muscle.tint)
                                    .frame(width: 42, height: 42)
                                    .background(exercise.muscle.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(exercise.name).foregroundStyle(.primary)
                                    Text(exercise.muscle.label).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle").foregroundStyle(GymaStyle.accent)
                            }.padding(.vertical, 3)
                        }
                    }
                    if available.isEmpty { Text("No more matching exercises.").foregroundStyle(.secondary) }
                }
                Section { Button("Create custom exercise", systemImage: "plus") { customPresented = true } }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .searchable(text: $search, prompt: "Find an exercise")
            .navigationTitle("Add exercise").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $customPresented) { CustomExerciseView(workoutID: workoutID) { dismiss() } }
        }
    }
}

private struct CustomExerciseView: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    let workoutID: String
    var onAdded: () -> Void
    @State private var name = ""
    @State private var muscle: Muscle = .chest
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Exercise name", text: $name)
                    Picker("Muscle", selection: $muscle) { ForEach(Muscle.allCases) { Text($0.label).tag($0) } }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Custom exercise").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty, trimmed.count <= 100 else { error = AppError.invalidCustomName.localizedDescription; return }
                        let exercise = ExerciseDefinition(id: "custom_\(UUID().uuidString)", name: trimmed, muscle: muscle, custom: true)
                        if model.update({
                            try $0.addCustomExercise(exercise)
                            try $0.addExercise(exercise.id, to: workoutID)
                        }) { dismiss(); onAdded() }
                        else { error = model.errorMessage }
                    }.bold()
                }
            }
        }
    }
}

struct ExerciseLogView: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    let workoutID: String
    let exerciseID: String
    @State private var logPresented = false
    @State private var targetPresented = false
    @State private var removePresented = false

    private var exercise: WorkoutExercise? { model.workout(workoutID)?.exercises.first { $0.exerciseID == exerciseID } }

    var body: some View {
        List {
            if let exercise {
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
                    Button("Remove exercise", systemImage: "trash", role: .destructive) { removePresented = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $logPresented) { LogSetView(workoutID: workoutID, exerciseID: exerciseID, exercise: exercise) }
        .sheet(isPresented: $targetPresented) { TargetEditorView(workoutID: workoutID, exerciseID: exerciseID, target: exercise?.target) }
        .confirmationDialog("Remove this exercise and its sets?", isPresented: $removePresented, titleVisibility: .visible) {
            Button("Remove exercise", role: .destructive) {
                if model.update({ try $0.removeExercise(exerciseID, workoutID: workoutID) }) { dismiss() }
            }
        }
        .onChange(of: model.workout(workoutID)?.end) { _, end in if end != nil { dismiss() } }
    }
}

private struct LogSetView: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    let workoutID: String
    let exerciseID: String
    @State private var kg: String
    @State private var reps: String
    @State private var warmup = false
    @State private var effort: SetEffort?
    @State private var error: String?
    @State private var saved = false
    @State private var setID = UUID().uuidString

    init(workoutID: String, exerciseID: String, exercise: WorkoutExercise?) {
        self.workoutID = workoutID
        self.exerciseID = exerciseID
        let previous = exercise?.sets.last { $0.isWarmup == false }
        _kg = State(initialValue: (exercise?.target?.loadKg ?? previous?.kg).map { String($0) } ?? "")
        _reps = State(initialValue: String(exercise?.target?.repsMin ?? previous?.reps ?? 8))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(model.name(for: exerciseID)) {
                    HStack { Text("Load"); Spacer(); TextField("0", text: $kg).keyboardType(.decimalPad).multilineTextAlignment(.trailing); Text("kg").foregroundStyle(.secondary) }
                    HStack { Text("Repetitions"); Spacer(); TextField("8", text: $reps).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                    Toggle("Warm-up set", isOn: $warmup)
                }
                Section("How did it feel?") {
                    Picker("Effort", selection: $effort) {
                        Text("Not recorded").tag(SetEffort?.none)
                        ForEach(SetEffort.allCases) { Text($0.label).tag(Optional($0)) }
                    }.pickerStyle(.inline).labelsHidden()
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    Button {
                        guard !saved else { return }
                        guard let load = Double(kg.replacingOccurrences(of: ",", with: ".")), load.isFinite, (0...1000).contains(load),
                              let count = Int(reps), (1...1000).contains(count) else { error = AppError.invalidSet.localizedDescription; return }
                        let set = WorkSet(id: setID, kg: load, reps: count, effort: effort, isWarmup: warmup)
                        if model.update({ try $0.addSet(set, exerciseID: exerciseID, workoutID: workoutID) }) { saved = true; dismiss() }
                        else { error = model.errorMessage }
                    } label: { Label("Save set", systemImage: "checkmark").font(.headline).frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).disabled(saved).padding(.vertical, 5)
                }
            }
            .navigationTitle("Log set").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct TargetEditorView: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    let workoutID: String
    let exerciseID: String
    @State private var sets: Int
    @State private var repsMin: Int
    @State private var repsMax: Int
    @State private var rest: Int
    @State private var load: String
    @State private var error: String?

    init(workoutID: String, exerciseID: String, target: ExerciseTarget?) {
        self.workoutID = workoutID
        self.exerciseID = exerciseID
        _sets = State(initialValue: target?.sets ?? 3)
        _repsMin = State(initialValue: target?.repsMin ?? 8)
        _repsMax = State(initialValue: target?.repsMax ?? 12)
        _rest = State(initialValue: target?.restSeconds ?? 90)
        _load = State(initialValue: target?.loadKg.map { String($0) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan your working sets") {
                    Stepper("\(sets) sets", value: $sets, in: 1...10)
                    Stepper("Minimum reps: \(repsMin)", value: $repsMin, in: 1...50)
                    Stepper("Maximum reps: \(repsMax)", value: $repsMax, in: 1...50)
                    TextField("Target load in kg (optional)", text: $load).keyboardType(.decimalPad)
                    Stepper("Rest: \(rest) seconds", value: $rest, in: 15...600, step: 15)
                }
                Section { Button("Remove target", role: .destructive) { save(nil) } }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Exercise target").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = load.trimmingCharacters(in: .whitespaces)
                        let number = Double(trimmed.replacingOccurrences(of: ",", with: "."))
                        guard repsMax >= repsMin, trimmed.isEmpty || (number != nil && number!.isFinite && (0...1000).contains(number!)) else {
                            error = AppError.invalidTarget.localizedDescription; return
                        }
                        save(ExerciseTarget(sets: sets, repsMin: repsMin, repsMax: repsMax, loadKg: number, restSeconds: rest))
                    }.bold()
                }
            }
        }
    }

    private func save(_ target: ExerciseTarget?) {
        if model.update({ try $0.updateTarget(target, exerciseID: exerciseID, workoutID: workoutID) }) { dismiss() }
        else { error = model.errorMessage }
    }
}
