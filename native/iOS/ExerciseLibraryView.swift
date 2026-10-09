import SwiftUI
import GymaCore

struct ExerciseLibraryView: View {
    @EnvironmentObject private var model: GymaAppModel
    @State private var search = ""
    @State private var createPresented = false

    private var exercises: [ExerciseDefinition] {
        model.state.catalog.filter { exercise in
            search.isEmpty || exercise.name.localizedCaseInsensitiveContains(search) ||
            exercise.muscle.label.localizedCaseInsensitiveContains(search) ||
            (exercise.trainingMetadata?.equipment?.label.localizedCaseInsensitiveContains(search) ?? false)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            Section {
                Button("Create custom exercise", systemImage: "plus.circle") { createPresented = true }
                    .disabled(model.storageBlocked)
            } footer: {
                Text("Add the cable, Smith or machine variants you actually use. Your coach can plan with these exercises on its next request.")
            }
            if !exercises.filter(\.custom).isEmpty {
                Section("Your exercises") {
                    ForEach(exercises.filter(\.custom)) { exercise in row(exercise) }
                }
            }
            Section("Built-in exercises") {
                ForEach(exercises.filter { !$0.custom }) { exercise in row(exercise) }
            }
            if exercises.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .navigationTitle("Exercise library")
        .searchable(text: $search, prompt: "Name, muscle or equipment")
        .sheet(isPresented: $createPresented) { LibraryExerciseEditor() }
    }

    private func row(_ exercise: ExerciseDefinition) -> some View {
        NavigationLink {
            ExerciseLibraryDetailView(exerciseID: exercise.id)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                Text([exercise.muscle.label, exercise.trainingMetadata?.equipment?.label].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ExerciseLibraryDetailView: View {
    @EnvironmentObject private var model: GymaAppModel
    let exerciseID: String
    @State private var editPresented = false
    private var exercise: ExerciseDefinition { model.state.exercise(exerciseID) }

    var body: some View {
        Form {
            Section {
                LabeledContent("Type", value: exercise.custom ? "Custom exercise" : "Built-in exercise")
                LabeledContent("Soreness region", value: exercise.muscle.label)
                if let metadata = exercise.trainingMetadata {
                    LabeledContent("Equipment", value: metadata.equipment?.label ?? "Not specified")
                    LabeledContent("Logged load", value: metadata.loadConvention.label)
                    LabeledContent("Direct muscles", value: metadata.primaryMuscles.map(\.label).joined(separator: ", "))
                    LabeledContent("Secondary muscles", value: metadata.secondaryMuscles.isEmpty ? "None specified" : metadata.secondaryMuscles.map(\.label).joined(separator: ", "))
                    LabeledContent("Measurement", value: metadata.measurement == .seconds ? "Seconds" : "Repetitions")
                } else {
                    Text("Detailed muscle and equipment information is not set. Muscle totals will show this as an information gap.")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Muscle involvement is an estimate used for training summaries. Secondary involvement is kept separate from direct working sets.")
            }
            if exercise.custom {
                Section {
                    Button("Edit exercise", systemImage: "pencil") { editPresented = true }
                        .disabled(model.storageBlocked)
                } footer: {
                    Text("Changes apply to this exercise throughout your history. Create a separate exercise when the machine, setup or movement is different.")
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editPresented) { LibraryExerciseEditor(existing: exercise) }
    }
}

private struct LibraryExerciseEditor: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    var existing: ExerciseDefinition? = nil
    @State private var name = ""
    @State private var region: Muscle = .chest
    @State private var includeMetadata = true
    @State private var equipment: AthleteEquipment?
    @State private var loadConvention: ExerciseLoadConvention = .unknown
    @State private var primary: [TrainingMuscle] = []
    @State private var secondary: [TrainingMuscle] = []
    @State private var loaded = false
    @State private var error: String?

    private var hasHistory: Bool {
        guard let existing else { return false }
        return (model.state.workouts + model.state.deletedWorkouts).contains { workout in
            workout.exercises.contains { $0.exerciseID == existing.id }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Exercise name", text: $name)
                    Picker("Soreness region", selection: $region) {
                        ForEach(Muscle.allCases) { Text($0.label).tag($0) }
                    }
                } footer: {
                    Text("Use a specific name, such as Smith incline press or cable row — narrow grip. Separate variants keep load comparisons meaningful.")
                }
                Section {
                    Toggle("Add muscle and equipment details", isOn: $includeMetadata)
                        .disabled(hasHistory && existing?.trainingMetadata != nil)
                    if includeMetadata {
                        Picker("Equipment", selection: $equipment) {
                            Text("Not specified").tag(Optional<AthleteEquipment>.none)
                            ForEach(AthleteEquipment.allCases) { Text($0.label).tag(Optional($0)) }
                        }
                        .disabled(hasHistory)
                        Picker("Logged load", selection: $loadConvention) {
                            ForEach(ExerciseLoadConvention.allCases) { Text($0.label).tag($0) }
                        }
                        .disabled(hasHistory)
                    }
                } footer: {
                    if hasHistory {
                        Text("This exercise is in your history. Equipment and load meaning are fixed to keep comparisons valid. Create a new variant for another machine or load convention. Name and muscle corrections apply throughout history.")
                    } else {
                        Text("Leave details off if you are unsure. Choose how you will record kilograms and use that convention consistently. Unknown muscle involvement is shown as a data gap rather than guessed.")
                    }
                }
                if includeMetadata {
                    Section {
                        ForEach(TrainingMuscle.allCases) { muscle in
                            Toggle(muscle.label, isOn: muscleBinding(muscle, direct: true))
                        }
                    } header: { Text("Direct muscles") } footer: {
                        Text("Choose at least one main target of the exercise.")
                    }
                    Section {
                        ForEach(TrainingMuscle.allCases.filter { !primary.contains($0) }) { muscle in
                            Toggle(muscle.label, isOn: muscleBinding(muscle, direct: false))
                        }
                    } header: { Text("Secondary muscles") } footer: {
                        Text("Optional assisting muscles. These are reported separately and do not add fractional sets to direct volume.")
                    }
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
                }
            }
            .navigationTitle(existing == nil ? "New exercise" : "Edit exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(model.storageBlocked || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                guard !loaded else { return }
                if let existing {
                    name = existing.name
                    region = existing.muscle
                    includeMetadata = existing.trainingMetadata != nil
                    equipment = existing.trainingMetadata?.equipment
                    loadConvention = existing.trainingMetadata?.loadConvention ?? .unknown
                    primary = existing.trainingMetadata?.primaryMuscles ?? []
                    secondary = existing.trainingMetadata?.secondaryMuscles ?? []
                }
                loaded = true
            }
        }
    }

    private func muscleBinding(_ muscle: TrainingMuscle, direct: Bool) -> Binding<Bool> {
        Binding(get: { (direct ? primary : secondary).contains(muscle) }, set: { selected in
            if direct {
                primary.removeAll { $0 == muscle }
                if selected { primary.append(muscle); secondary.removeAll { $0 == muscle } }
            } else {
                secondary.removeAll { $0 == muscle }
                if selected { secondary.append(muscle) }
            }
        })
    }

    private func save() {
        do {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= 200 else { throw GymaError.invalid("Use an exercise name of at most 200 characters.") }
            guard !model.state.catalog.contains(where: { $0.id != existing?.id && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(trimmed) == .orderedSame }) else {
                throw GymaError.invalid("That exercise name is already in your library. Use its existing entry or name the specific variant.")
            }
            let metadata: ExerciseMetadata? = includeMetadata ? .init(primaryMuscles: primary, secondaryMuscles: secondary, equipment: equipment,
                measurement: existing?.trainingMetadata?.measurement ?? .repetitions, loadConvention: loadConvention) : nil
            try metadata?.validate()
            let exercise = ExerciseDefinition(id: existing?.id ?? "custom_\(UUID().uuidString)", name: trimmed, muscle: region,
                                              iconKey: existing?.iconKey ?? "barbell", custom: true, metadata: metadata)
            if model.update({ state in
                if let existing {
                    guard let index = state.customExercises.firstIndex(where: { $0.id == existing.id }), state.customExercises[index] == existing else {
                        throw GymaError.stale("This exercise changed. Close the editor and open it again.")
                    }
                    let used = (state.workouts + state.deletedWorkouts).contains { $0.exercises.contains { $0.exerciseID == existing.id } }
                    if used {
                        let previous = existing.trainingMetadata
                        guard metadata?.equipment == previous?.equipment,
                              (metadata?.loadConvention ?? .unknown) == (previous?.loadConvention ?? .unknown),
                              (metadata?.measurement ?? .repetitions) == (previous?.measurement ?? .repetitions) else {
                            throw GymaError.invalid("Create a new exercise variant to change equipment or load meaning once it is in your history.")
                        }
                    }
                    state.customExercises[index] = exercise
                    state.revision += 1
                } else {
                    try state.addCustomExercise(exercise)
                }
                state.coachConversation?.plan?.acceptedAt = nil
                state.coachConversation?.proposedProgram = nil
            }) {
                model.notice = "Exercise saved to your library."
                dismiss()
            } else { error = model.errorMessage }
        } catch { self.error = error.localizedDescription }
    }
}
