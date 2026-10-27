import SwiftUI
import GymaCore

/// Add an exercise to a started workout, or edit one's library reference and targets.
struct WorkoutExerciseEditor: View {
    let date: String
    let initial: SessionExercise?
    let minimumSets: Int
    /// Completed sets that would move with a changed exercise.
    let recordedSets: Int
    /// Saves targets with the client entry ID and whether recorded sets may be reassigned. Returns an error message.
    let onSave: (ExerciseTargets, String, Bool) async -> String?
    let onRemove: (() async -> String?)?

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: LibraryExercise?
    @State private var sets = "3"
    @State private var reps = "10"
    @State private var kg = "0"
    @State private var autoKg = false
    @State private var entryId = newEntityID()
    @State private var picking = false
    @State private var saving = false
    @State private var error: String?
    @State private var confirmReassign = false
    @State private var confirmRemove = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let error { ErrorBanner(message: error) }
                    Button { picking = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chosen?.name ?? "Choose exercise").font(.subheadline.weight(.semibold))
                                    .foregroundStyle(chosen == nil ? Theme.muted : Theme.ink)
                                if let chosen { Text(chosen.detail).font(.caption).foregroundStyle(Theme.muted) }
                            }
                            Spacer()
                            Image(systemName: "chevron.down").font(.caption).foregroundStyle(Theme.muted)
                        }
                        .inputField()
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 10) {
                        NumberStepper(label: "Target sets", value: $sets, step: 1, range: Double(minimumSets)...100)
                        NumberStepper(label: "Target reps", value: $reps, step: 1, range: 1...1000)
                    }
                    NumberStepper(label: "Target kg", value: $kg, step: chosen.map { kgStep($0.equipment) } ?? 2.5, decimal: true)

                    if let chosen {
                        KgSuggestView(exercise: chosen, before: date, reps: reps, kg: kg, autoFill: autoKg) { kg = $0 }
                            .id(chosen.id)
                    }

                    Button(action: save) {
                        Text(saving ? "Saving…" : initial == nil ? "Add exercise to workout" : "Save exercise changes")
                    }
                    .buttonStyle(.primary)
                    .disabled(chosen == nil || saving)

                    if onRemove != nil {
                        Button("Remove exercise", role: .destructive) { confirmRemove = true }
                            .font(.subheadline)
                            .foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity)
                            .disabled(saving)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle(initial == nil ? "Add to this workout" : "Edit workout exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
            }
            .keyboardDoneButton()
            .sheet(isPresented: $picking) {
                ExercisePickerSheet { exercise in
                    chosen = exercise
                    autoKg = (parseNumber(kg) ?? 0) == 0
                }
                .environmentObject(model)
            }
            .confirmationDialog("Changing this exercise will also reassign its \(recordedSets) recorded \(recordedSets == 1 ? "set" : "sets") to the new exercise.",
                                isPresented: $confirmReassign, titleVisibility: .visible) {
                Button("Save correction") { submit(reassign: true) }
            }
            .confirmationDialog(removeTitle, isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove exercise", role: .destructive) { remove() }
            }
        }
        .interactiveDismissDisabled(saving)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let initial {
                chosen = initial.library
                sets = String(initial.plannedSets); reps = String(initial.plannedReps); kg = formatKg(initial.plannedKg)
            }
        }
    }

    private var removeTitle: String {
        "Remove \(initial?.name ?? "this exercise")\(recordedSets > 0 ? " and its \(recordedSets) recorded \(recordedSets == 1 ? "set" : "sets")" : "") from this workout?"
    }

    private func save() {
        guard let chosen else { return }
        if let initial, initial.exerciseId != chosen.id, recordedSets > 0 { confirmReassign = true; return }
        submit(reassign: false)
    }

    private func submit(reassign: Bool) {
        guard let chosen else { return }
        guard let setCount = parseCount(sets, in: minimumSets...100), let repCount = parseCount(reps, in: 1...1000),
              let load = parseNumber(kg), (0...10000).contains(load) else {
            error = "Use \(minimumSets)–100 sets, 1–1000 reps and 0–10000 kg."
            return
        }
        saving = true; error = nil
        Task {
            error = await onSave(ExerciseTargets(exerciseId: chosen.id, plannedSets: setCount, plannedReps: repCount, plannedKg: load), entryId, reassign)
            saving = false
            if error == nil { dismiss() }
        }
    }

    private func remove() {
        guard let onRemove else { return }
        saving = true; error = nil
        Task {
            error = await onRemove()
            saving = false
            if error == nil { dismiss() }
        }
    }
}

/// Log a set performed without the timer, or correct / remove a recorded set.
struct WorkoutSetEditor: View {
    let initial: PerformedSet?
    let exercise: SessionExercise
    /// Saves kg, reps and the set ID. Returns an error message.
    let onSave: (Double, Int, String) async -> String?
    let onRemove: (() async -> String?)?

    @Environment(\.dismiss) private var dismiss
    @State private var kg = ""
    @State private var reps = ""
    @State private var setId = newEntityID()
    @State private var saving = false
    @State private var error: String?
    @State private var confirmRemove = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(exercise.name).font(.headline)
                    if initial == nil {
                        Text("Enter a set you already performed. No timer needed.").font(.caption).foregroundStyle(Theme.muted)
                    }
                    if let error { ErrorBanner(message: error) }
                    HStack(spacing: 10) {
                        NumberStepper(label: "kg", value: $kg, step: kgStep(exercise.equipment), decimal: true, large: true)
                        NumberStepper(label: "reps", value: $reps, step: 1, range: 0...1000, large: true)
                    }
                    Button(action: save) {
                        Text(saving ? "Saving…" : initial == nil ? "Save completed set" : "Save set changes")
                    }
                    .buttonStyle(.primary)
                    .disabled(saving)
                    if onRemove != nil {
                        Button("Remove set", role: .destructive) { confirmRemove = true }
                            .font(.subheadline)
                            .foregroundStyle(Theme.danger)
                            .frame(maxWidth: .infinity)
                            .disabled(saving)
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle(initial.map { "Edit set \($0.setNumber)" } ?? "Log a completed set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
            }
            .keyboardDoneButton()
            .confirmationDialog("Remove this recorded set from the workout and its totals?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove set", role: .destructive) { remove() }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(saving)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            kg = formatKg(initial?.actualKg ?? exercise.plannedKg)
            reps = String(initial?.actualReps ?? exercise.plannedReps)
            if let initial { setId = initial.id }
        }
    }

    private func save() {
        guard let load = parseNumber(kg), (0...10000).contains(load), let count = parseCount(reps, in: 0...1000) else {
            error = "Enter kg between 0 and 10000 and whole reps between 0 and 1000."
            return
        }
        saving = true; error = nil
        Task {
            error = await onSave(load, count, setId)
            saving = false
            if error == nil { dismiss() }
        }
    }

    private func remove() {
        guard let onRemove else { return }
        saving = true; error = nil
        Task {
            error = await onRemove()
            saving = false
            if error == nil { dismiss() }
        }
    }
}
