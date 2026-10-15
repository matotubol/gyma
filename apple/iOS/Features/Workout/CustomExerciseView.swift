import SwiftUI
import GymaCore

struct CustomExerciseView: View {
    @EnvironmentObject private var model: GymaAppModel
    @Environment(\.dismiss) private var dismiss
    let workoutID: String
    var replacingExerciseID: String? = nil
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
                        if model.addCustomWorkoutExercise(exercise, workoutID: workoutID, replacingExerciseID: replacingExerciseID) {
                            dismiss(); onAdded()
                        }
                        else { error = model.errorMessage }
                    }.bold()
                }
            }
        }
    }
}
