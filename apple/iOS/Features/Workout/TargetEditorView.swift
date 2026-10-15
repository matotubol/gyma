import SwiftUI
import GymaCore

struct TargetEditorView: View {
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
                Section {
                    Stepper("\(sets) sets", value: $sets, in: 1...10)
                    Stepper("Minimum reps: \(repsMin)", value: $repsMin, in: 1...50)
                    Stepper("Maximum reps: \(repsMax)", value: $repsMax, in: 1...50)
                    TextField("Target load in kg (optional)", text: $load).keyboardType(.decimalPad)
                    Stepper("Rest: \(rest) seconds", value: $rest, in: 15...600, step: 15)
                } header: { Text("Plan your working sets") } footer: {
                    Text("For this workout only. The set target includes working sets already logged and planned sets skipped. Increase it to add more work after stopping.")
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
