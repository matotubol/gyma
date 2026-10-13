import SwiftUI
import GymaCore

/// Edits an unstarted prescription; the caller commits it to a date or a reviewed daily draft.
struct PlannedWorkoutEditor: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    let title: String
    let onSave: ([WorkoutExercise]) throws -> Void
    @State private var exercises: [WorkoutExercise]
    @State private var selection: ExerciseSelection?
    @State private var targetEntry: WorkoutExercise?
    @State private var error: String?

    private struct ExerciseSelection: Identifiable {
        let id = UUID()
        let replacingID: String?
    }

    init(title: String, exercises: [WorkoutExercise], onSave: @escaping ([WorkoutExercise]) throws -> Void) {
        self.title = title; self.onSave = onSave
        _exercises = State(initialValue: exercises)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Changes apply to this workout only. Your recurring program stays the same.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Drag the handles to reorder. Tap an exercise to edit its targets, or use Replace to choose another movement.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Exercises") {
                    ForEach(exercises) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            Button { targetEntry = entry } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(model.name(for: entry.exerciseID)).font(.headline)
                                    if let target = entry.target {
                                        Text("\(target.sets) × \(target.repsMin)–\(target.repsMax) · \(target.loadKg.map { "\($0.gymaNumber) kg" } ?? "Choose load") · \(target.restSeconds)s rest")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                            Button("Replace exercise", systemImage: "arrow.triangle.2.circlepath") {
                                selection = .init(replacingID: entry.exerciseID)
                            }.font(.caption).buttonStyle(.borderless)
                        }.padding(.vertical, 4)
                    }
                    .onMove { exercises.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { exercises.remove(atOffsets: $0) }
                }
                Section {
                    Button("Add exercise", systemImage: "plus") { selection = .init(replacingID: nil) }
                        .disabled(exercises.count >= 12)
                }
                if let error { Section { Text(error).foregroundStyle(.orange) } }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.bold().disabled(exercises.isEmpty || model.storageBlocked)
                }
            }
            .sheet(item: $selection) { selected in
                PlannedExercisePicker(excluded: Set(exercises.map(\.exerciseID))) { definition in
                    if let oldID = selected.replacingID, let index = exercises.firstIndex(where: { $0.exerciseID == oldID }) {
                        var target = exercises[index].target ?? .init(sets: 3, repsMin: 8, repsMax: 12)
                        // Loads are not interchangeable between machines or exercise variants.
                        target.loadKg = nil; target.reason = "Choose a comfortable load for this replacement."
                        exercises[index] = .init(exerciseID: definition.id, target: target)
                    } else {
                        exercises.append(.init(exerciseID: definition.id, target: .init(sets: 3, repsMin: 8, repsMax: 12)))
                    }
                    selection = nil
                }
            }
            .sheet(item: $targetEntry) { entry in
                PlannedTargetEditor(name: model.name(for: entry.exerciseID), target: entry.target ?? .init(sets: 3, repsMin: 8, repsMax: 12)) { target in
                    if let index = exercises.firstIndex(where: { $0.exerciseID == entry.exerciseID }) {
                        exercises[index].target = target
                    }
                    targetEntry = nil
                }
            }
        }
    }

    private func save() {
        do {
            let plan = WorkoutPlan(title: title, exercises: exercises, checkIn: .init(shift: .off, energy: .good))
            try plan.validate(catalog: model.state.catalog)
            try onSave(exercises)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct PlannedExercisePicker: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    let excluded: Set<String>
    let onChoose: (ExerciseDefinition) -> Void
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.state.availableExercises.filter {
                    !excluded.contains($0.id) && $0.trainingMetadata?.measurement != .seconds &&
                        (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
                }) { exercise in
                    Button { onChoose(exercise) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name).foregroundStyle(.primary)
                            Text(exercise.muscle.label).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Find an exercise")
            .navigationTitle("Choose exercise").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct PlannedTargetEditor: View {
    @Environment(\.dismiss) private var dismiss
    let name: String
    let onSave: (ExerciseTarget) -> Void
    @State private var target: ExerciseTarget
    @State private var load: String
    @State private var error: String?

    init(name: String, target: ExerciseTarget, onSave: @escaping (ExerciseTarget) -> Void) {
        self.name = name; self.onSave = onSave
        _target = State(initialValue: target)
        _load = State(initialValue: target.loadKg.map { String($0) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(name) {
                    Stepper("Sets: \(target.sets)", value: $target.sets, in: 1...10)
                    Stepper("Minimum reps: \(target.repsMin)", value: $target.repsMin, in: 1...50)
                    Stepper("Maximum reps: \(target.repsMax)", value: $target.repsMax, in: 1...50)
                    TextField("Load in kg (optional)", text: $load).keyboardType(.decimalPad)
                    Stepper("Rest: \(target.restSeconds)s", value: $target.restSeconds, in: 15...600, step: 15)
                    Picker("Effort", selection: $target.targetEffort) {
                        Text("Not set").tag(SetEffort?.none)
                        ForEach(SetEffort.allCases) { Text($0.label).tag(Optional($0)) }
                    }
                }
                if let error { Text(error).foregroundStyle(.orange) }
            }
            .navigationTitle("Today's target").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            let value = load.trimmingCharacters(in: .whitespacesAndNewlines)
                            let kg = Double(value.replacingOccurrences(of: ",", with: "."))
                            guard value.isEmpty || kg != nil else { throw AppError.invalidTarget }
                            var edited = target; edited.loadKg = kg; edited.reason = "Adjusted for this workout."
                            try edited.validate()
                            onSave(edited)
                        } catch { self.error = error.localizedDescription }
                    }.bold()
                }
            }
        }
    }
}
