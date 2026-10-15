import SwiftUI
import GymaCore

struct ExercisePickerView: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    let workoutID: String
    var replacingExerciseID: String? = nil
    @State private var search = ""
    @State private var muscle: Muscle?
    @State private var customPresented = false
    @State private var error: String?

    private var available: [ExerciseDefinition] {
        let existing = Set(model.workout(workoutID)?.exercises.map(\.exerciseID) ?? [])
        return model.state.availableExercises.filter {
            !existing.contains($0.id) && (muscle == nil || $0.muscle == muscle) &&
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let replacingExerciseID {
                    Section {
                        Text("Replace \(model.name(for: replacingExerciseID)) for this workout. Logged sets stay saved under the original exercise. The replacement starts without a suggested load.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Picker("Muscle group", selection: $muscle) {
                        Text("All muscles").tag(Muscle?.none)
                        ForEach(Muscle.allCases) { Text($0.label).tag(Optional($0)) }
                    }
                }
                Section {
                    ForEach(available) { exercise in
                        Button {
                            if model.addWorkoutExercise(exercise.id, workoutID: workoutID, replacingExerciseID: replacingExerciseID) {
                                dismiss()
                            }
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
                                Image(systemName: replacingExerciseID == nil ? "plus.circle" : "arrow.triangle.2.circlepath").foregroundStyle(GymaStyle.accent)
                            }.padding(.vertical, 3)
                        }
                    }
                    if available.isEmpty { Text("No more matching exercises.").foregroundStyle(.secondary) }
                }
                Section { Button("Create custom exercise", systemImage: "plus") { customPresented = true } }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .searchable(text: $search, prompt: "Find an exercise")
            .navigationTitle(replacingExerciseID == nil ? "Add exercise" : "Replace for today").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $customPresented) { CustomExerciseView(workoutID: workoutID, replacingExerciseID: replacingExerciseID) { dismiss() } }
        }
    }
}
