import SwiftUI
import GymaCore

struct LogSetView: View {
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
    @State private var skipPresented = false

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
                        guard model.state.restTimer == nil else {
                            error = "Tap Start next set on the rest timer before logging your completed set."
                            return
                        }
                        guard let load = Double(kg.replacingOccurrences(of: ",", with: ".")), load.isFinite, (0...1000).contains(load),
                              let count = Int(reps), (1...1000).contains(count) else { error = AppError.invalidSet.localizedDescription; return }
                        let set = WorkSet(id: setID, kg: load, reps: count, effort: effort, isWarmup: warmup)
                        if model.update({ try $0.addSet(set, exerciseID: exerciseID, workoutID: workoutID) }) { saved = true; dismiss() }
                        else { error = model.errorMessage }
                    } label: { Label("Save set", systemImage: "checkmark").font(.headline).frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).disabled(saved).padding(.vertical, 5)
                }
                if let exercise = model.workout(workoutID)?.exercises.first(where: { $0.exerciseID == exerciseID }),
                   exercise.target != nil, !exercise.isTargetResolved {
                    Section {
                        Button("Cancel this planned set", systemImage: "forward.end") { skipPresented = true }
                    } footer: { Text("Use this if you stopped or did not perform the set. No reps or volume will be recorded.") }
                }
            }
            .navigationTitle("Log set").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .confirmationDialog("Cancel this planned set?", isPresented: $skipPresented, titleVisibility: .visible) {
                Button("Skip set") {
                    if model.update({ try $0.skipSet(exerciseID: exerciseID, workoutID: workoutID) }) { dismiss() }
                    else { error = model.errorMessage }
                }
            } message: { Text("Your entered weight and reps will not be saved. Completed sets stay in the workout.") }
        }
    }
}
